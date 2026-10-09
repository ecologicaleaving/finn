-- Migration: 20260926_46_account_deletion.sql
-- Issue: #46 - «Elimina account» elimina davvero l'utente (AC7)
--
-- DA APPLICARE A MANO su Supabase (SQL editor), DOPO
-- 20260926_46_secure_group_membership.sql (che definisce
-- public._dispose_group_if_abandoned, usata qui).
-- Idempotente: blocco DO sullo schema (rieseguito non fa nulla) +
-- CREATE OR REPLACE FUNCTION / REVOKE / GRANT. Avvolta in BEGIN/COMMIT.
-- Il blocco DO prende un lock ACCESS EXCLUSIVE breve su tabelle piccole:
-- meglio applicarla con poco traffico.
--
-- REGOLA DI DAVIDE (assoluta): le spese di un membro RESTANO nel gruppo quando
-- il membro viene rimosso, esce o elimina l'account. Le spese si cancellano
-- SOLO se eliminate una per una. Questa migration non fa MAI una DELETE su
-- expenses e non elimina MAI un gruppo che contiene spese
-- (expenses.group_id e' ON DELETE CASCADE).
--
-- delete_my_account(p_anonymize) elimina la riga auth.users del chiamante.
-- DELETE auth.users -> CASCADE su profiles (001). Da profiles/auth.users:
--   - CASCADE (dati PERSONALI dell'utente, corretto): income_sources,
--     savings_goals, group_expense_assignments, personal_budgets,
--     category_budgets(user_id), budget_percentage_history(user_id),
--     user_category_usage, ...
--     recurring_expenses (#69, migration 20261009_69): user_id ON DELETE
--     CASCADE porta via i TEMPLATI di ricorrenza dell'utente (anche di
--     gruppo); le spese gia' generate restano (recurring_expense_id e' senza
--     FK). group_id e' SET NULL.
--   - SET NULL (questa migration, blocco DO): family_groups.created_by,
--     category_budgets.created_by, group_budgets.created_by,
--     budget_percentage_history.changed_by. Prima erano NOT NULL (le tre
--     ultime con CASCADE: avrebbero cancellato i dati di gruppo creati
--     dall'utente; family_groups.created_by senza ON DELETE: avrebbe
--     bloccato la cancellazione). Ora un gruppo senza membri puo' restare con
--     created_by NULL e le righe di gruppo non si perdono. Le funzioni che
--     decidono l'admin con fg.created_by gestiscono NULL (il confronto da'
--     NULL = false).
--   - SET NULL (gia' in produzione): expenses.created_by, expenses.paid_by,
--     expense_categories.created_by, profiles.group_id
--   - NESSUNA AZIONE (bloccherebbero la DELETE, gestite qui prima):
--     invites.created_by, invites.used_by, expenses.last_modified_by
--
-- Regole:
--   - admin di un gruppo con altri membri -> errore 'admin_has_members'
--     (deve prima rimuovere i membri; le loro spese restano nel gruppo)
--   - ultimo membro del proprio gruppo: se il gruppo ha spese il gruppo
--     RESTA (senza membri, created_by NULL); senza spese si elimina
--   - gruppi "legacy" creati dall'utente ma di cui non fa piu' parte: stessa
--     regola; con altri membri created_by passa al membro admin (altrimenti
--     al piu' anziano), senza membri il gruppo resta se ha spese
--   - passo 2b: per i gruppi che CONTINUANO a esistere, created_by/changed_by
--     delle righe di gruppo create dall'utente passano a un altro membro:
--     admin attuale, poi membro piu' anziano, poi family_groups.created_by.
--     Se nessuno e' disponibile (gruppo tenuto senza membri) le righe restano
--     e created_by/changed_by diventano NULL grazie al blocco DO; se il blocco
--     DO non e' stato applicato, 'group_data_owner_not_found' (rollback
--     completo) invece di perdere dati.
--     I budget personali di altri utenti creati dall'utente passano a
--     created_by = user_id.
--   - p_anonymize = true -> sulle spese rimaste nei gruppi il nome diventa
--     'Utente eliminato'; con false il nome resta (keep name)

BEGIN;

-- Schema: created_by / changed_by nullable con FK ON DELETE SET NULL verso
-- public.profiles. Il nome del vincolo si legge dal catalogo; se la FK punta a
-- una tabella diversa da public.profiles ci si ferma con un'eccezione.
DO $$
DECLARE
  v_pair text[];
  v_tbl text;
  v_col text;
  v_attnum smallint;
  v_con RECORD;
  v_has_set_null boolean;
BEGIN
  FOREACH v_pair SLICE 1 IN ARRAY ARRAY[
    ARRAY['family_groups', 'created_by'],
    ARRAY['category_budgets', 'created_by'],
    ARRAY['group_budgets', 'created_by'],
    ARRAY['budget_percentage_history', 'changed_by']
  ]
  LOOP
    v_tbl := v_pair[1];
    v_col := v_pair[2];

    CONTINUE WHEN to_regclass('public.' || v_tbl) IS NULL;

    EXECUTE format('ALTER TABLE public.%I ALTER COLUMN %I DROP NOT NULL', v_tbl, v_col);

    SELECT a.attnum INTO v_attnum
    FROM pg_attribute a
    WHERE a.attrelid = ('public.' || v_tbl)::regclass
      AND a.attname = v_col
      AND NOT a.attisdropped;

    v_has_set_null := false;

    FOR v_con IN
      SELECT c.conname, c.confrelid, c.confdeltype
      FROM pg_constraint c
      WHERE c.contype = 'f'
        AND c.conrelid = ('public.' || v_tbl)::regclass
        AND array_length(c.conkey, 1) = 1
        AND c.conkey[1] = v_attnum
    LOOP
      IF v_con.confrelid <> 'public.profiles'::regclass THEN
        RAISE EXCEPTION 'FK % su %.% punta a % (atteso public.profiles): mi fermo',
          v_con.conname, v_tbl, v_col, v_con.confrelid::regclass;
      END IF;

      IF v_con.confdeltype = 'n' THEN
        v_has_set_null := true;
      ELSE
        EXECUTE format('ALTER TABLE public.%I DROP CONSTRAINT %I', v_tbl, v_con.conname);
        RAISE NOTICE 'eliminata FK % su %.% (azione %)', v_con.conname, v_tbl, v_col, v_con.confdeltype;
      END IF;
    END LOOP;

    IF NOT v_has_set_null THEN
      EXECUTE format(
        'ALTER TABLE public.%I ADD CONSTRAINT %I FOREIGN KEY (%I) REFERENCES public.profiles(id) ON DELETE SET NULL',
        v_tbl, v_tbl || '_' || v_col || '_fkey', v_col);
      RAISE NOTICE 'creata FK %_%_fkey ON DELETE SET NULL', v_tbl, v_col;
    END IF;
  END LOOP;
END;
$$;

CREATE OR REPLACE FUNCTION public.delete_my_account(p_anonymize boolean DEFAULT false)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_uid UUID := auth.uid();
  v_group_id UUID;
  v_is_admin BOOLEAN;
  v_others INTEGER;
  v_rows INTEGER;
  v_legacy RECORD;
  v_new_owner UUID;
  v_g RECORD;
  v_owner UUID;
  v_creator UUID;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '28000';
  END IF;

  SELECT p.group_id, COALESCE(p.is_group_admin, false)
  INTO v_group_id, v_is_admin
  FROM public.profiles p
  WHERE p.id = v_uid
  FOR UPDATE;

  -- 1. Gruppo attuale
  IF v_group_id IS NOT NULL THEN
    -- Serializza con uscite/ingressi concorrenti nello stesso gruppo
    PERFORM 1 FROM public.family_groups WHERE id = v_group_id FOR UPDATE;

    -- created_by NULL (gruppo tenuto senza membri) -> confronto NULL = false
    v_is_admin := v_is_admin OR EXISTS (
      SELECT 1 FROM public.family_groups fg
      WHERE fg.id = v_group_id AND fg.created_by = v_uid
    );

    SELECT count(*) INTO v_others
    FROM public.profiles p
    WHERE p.group_id = v_group_id AND p.id <> v_uid;

    IF v_is_admin AND v_others > 0 THEN
      RAISE EXCEPTION 'admin_has_members';
    END IF;

    UPDATE public.profiles
    SET group_id = NULL, is_group_admin = false
    WHERE id = v_uid;

    IF v_others = 0 THEN
      -- Il gruppo si elimina solo se non ha spese; altrimenti resta
      -- (senza membri, created_by NULL dopo la cancellazione dell'utente).
      PERFORM public._dispose_group_if_abandoned(v_group_id);
    END IF;
  END IF;

  -- 2. Gruppi creati dall'utente di cui non fa piu' parte (dati legacy)
  -- Mai DELETE di un gruppo con spese: senza membri si usa l'helper, che
  -- elimina solo i gruppi vuoti di spese.
  FOR v_legacy IN
    SELECT fg.id FROM public.family_groups fg WHERE fg.created_by = v_uid
    FOR UPDATE
  LOOP
    -- Nuovo owner: prima un membro gia' admin (per non creare due admin),
    -- poi il piu' anziano.
    SELECT p.id INTO v_new_owner
    FROM public.profiles p
    WHERE p.group_id = v_legacy.id AND p.id <> v_uid
    ORDER BY COALESCE(p.is_group_admin, false) DESC, p.created_at NULLS LAST, p.id
    LIMIT 1;

    IF v_new_owner IS NULL THEN
      PERFORM public._dispose_group_if_abandoned(v_legacy.id);
    ELSE
      UPDATE public.family_groups SET created_by = v_new_owner WHERE id = v_legacy.id;
      UPDATE public.profiles SET is_group_admin = true WHERE id = v_new_owner;
    END IF;
  END LOOP;

  -- 2b. Riassegnazione dei dati di gruppo creati dall'utente (gruppi che
  -- sopravvivono): evita che il CASCADE su created_by/changed_by li cancelli.
  FOR v_g IN
    SELECT cb.group_id FROM public.category_budgets cb
    WHERE cb.created_by = v_uid AND cb.is_group_budget = true
      AND (cb.user_id IS NULL OR cb.user_id <> v_uid)
    UNION
    SELECT gb.group_id FROM public.group_budgets gb WHERE gb.created_by = v_uid
    UNION
    SELECT h.group_id FROM public.budget_percentage_history h
    WHERE h.changed_by = v_uid AND h.user_id <> v_uid
  LOOP
    CONTINUE WHEN v_g.group_id IS NULL;

    SELECT fg.created_by INTO v_creator
    FROM public.family_groups fg
    WHERE fg.id = v_g.group_id
    FOR UPDATE;

    IF NOT FOUND THEN
      CONTINUE;
    END IF;

    v_owner := NULL;

    -- (1) admin attuale (creatore del gruppo o is_group_admin)
    SELECT p.id INTO v_owner
    FROM public.profiles p
    WHERE p.group_id = v_g.group_id AND p.id <> v_uid
      AND (p.id = v_creator OR COALESCE(p.is_group_admin, false))
    ORDER BY (p.id = v_creator) DESC, p.created_at NULLS LAST, p.id
    LIMIT 1;

    -- (2) membro piu' anziano
    IF v_owner IS NULL THEN
      SELECT p.id INTO v_owner
      FROM public.profiles p
      WHERE p.group_id = v_g.group_id AND p.id <> v_uid
      ORDER BY p.created_at NULLS LAST, p.id
      LIMIT 1;
    END IF;

    -- (3) creatore del gruppo, anche se non e' piu' membro
    IF v_owner IS NULL AND v_creator IS NOT NULL AND v_creator <> v_uid THEN
      v_owner := v_creator;
    END IF;

    IF v_owner IS NULL THEN
      -- Gruppo tenuto senza membri: le righe di gruppo restano e
      -- created_by/changed_by diventano NULL alla DELETE dell'utente
      -- (FK SET NULL del blocco DO). Rete di sicurezza: se il blocco DO non
      -- e' stato applicato e una di queste colonne ha ancora un'azione
      -- diversa da SET NULL, ci si ferma invece di perdere dati.
      IF EXISTS (
        SELECT 1
        FROM pg_constraint c
        JOIN pg_attribute a ON a.attrelid = c.conrelid AND a.attnum = c.conkey[1]
        WHERE c.contype = 'f'
          AND array_length(c.conkey, 1) = 1
          AND c.confdeltype <> 'n'
          AND (
            (c.conrelid = 'public.category_budgets'::regclass AND a.attname = 'created_by')
            OR (to_regclass('public.group_budgets') IS NOT NULL
                AND c.conrelid = 'public.group_budgets'::regclass AND a.attname = 'created_by')
            OR (to_regclass('public.budget_percentage_history') IS NOT NULL
                AND c.conrelid = 'public.budget_percentage_history'::regclass AND a.attname = 'changed_by')
          )
      ) THEN
        RAISE EXCEPTION 'group_data_owner_not_found';
      END IF;
      CONTINUE;
    END IF;

    UPDATE public.category_budgets
    SET created_by = v_owner
    WHERE group_id = v_g.group_id AND created_by = v_uid
      AND is_group_budget = true;

    IF to_regclass('public.group_budgets') IS NOT NULL THEN
      UPDATE public.group_budgets
      SET created_by = v_owner
      WHERE group_id = v_g.group_id AND created_by = v_uid;
    END IF;

    IF to_regclass('public.budget_percentage_history') IS NOT NULL THEN
      UPDATE public.budget_percentage_history
      SET changed_by = v_owner
      WHERE group_id = v_g.group_id AND changed_by = v_uid
        AND user_id <> v_uid;
    END IF;
  END LOOP;

  -- Budget personali di altri utenti creati dall'utente: il proprietario
  -- naturale e' user_id.
  UPDATE public.category_budgets
  SET created_by = user_id
  WHERE created_by = v_uid AND is_group_budget = false
    AND user_id IS NOT NULL AND user_id <> v_uid;

  -- 3. Anonimizzazione delle spese rimaste (in altri gruppi)
  IF p_anonymize THEN
    IF EXISTS (
      SELECT 1 FROM information_schema.columns
      WHERE table_schema = 'public' AND table_name = 'expenses'
        AND column_name = 'created_by_name'
    ) THEN
      EXECUTE 'UPDATE public.expenses SET created_by_name = ''Utente eliminato'' WHERE created_by = $1'
        USING v_uid;
    END IF;

    IF EXISTS (
      SELECT 1 FROM information_schema.columns
      WHERE table_schema = 'public' AND table_name = 'expenses'
        AND column_name = 'paid_by_name'
    ) AND EXISTS (
      SELECT 1 FROM information_schema.columns
      WHERE table_schema = 'public' AND table_name = 'expenses'
        AND column_name = 'paid_by'
    ) THEN
      EXECUTE 'UPDATE public.expenses SET paid_by_name = ''Utente eliminato'' WHERE paid_by = $1'
        USING v_uid;
    END IF;
  END IF;

  -- 4. FK senza ON DELETE che bloccherebbero la cancellazione
  UPDATE public.invites SET used_by = NULL WHERE used_by = v_uid;
  DELETE FROM public.invites WHERE created_by = v_uid;

  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'expenses'
      AND column_name = 'last_modified_by'
  ) THEN
    EXECUTE 'UPDATE public.expenses SET last_modified_by = NULL WHERE last_modified_by = $1'
      USING v_uid;
  END IF;

  -- 5. Eliminazione dell'utente (CASCADE su profiles e tabelle collegate)
  DELETE FROM auth.users WHERE id = v_uid;
  GET DIAGNOSTICS v_rows = ROW_COUNT;

  IF v_rows = 0 THEN
    RAISE EXCEPTION 'account_not_deleted';
  END IF;
END;
$$;

REVOKE ALL ON FUNCTION public.delete_my_account(boolean) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.delete_my_account(boolean) FROM anon;
GRANT EXECUTE ON FUNCTION public.delete_my_account(boolean) TO authenticated;

COMMIT;
