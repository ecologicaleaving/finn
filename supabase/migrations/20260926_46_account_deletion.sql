-- Migration: 20260926_46_account_deletion.sql
-- Issue: #46 - «Elimina account» elimina davvero l'utente (AC7)
--
-- DA APPLICARE A MANO su Supabase (SQL editor), DOPO
-- 20260926_46_secure_group_membership.sql.
-- Idempotente: solo CREATE OR REPLACE FUNCTION / REVOKE / GRANT.
--
-- delete_my_account(p_anonymize) elimina la riga auth.users del chiamante.
-- DELETE auth.users -> CASCADE su profiles (001). Da profiles/auth.users:
--   - CASCADE (dati PERSONALI dell'utente, corretto): income_sources,
--     savings_goals, recurring_expenses (solo se la tabella esiste: in
--     produzione NON esiste), group_expense_assignments, personal_budgets,
--     category_budgets(user_id), budget_percentage_history(user_id),
--     user_category_usage, ...
--   - CASCADE PERICOLOSI (dati di GRUPPO creati dall'utente), riassegnati dal
--     passo 2b PRIMA del DELETE: category_budgets.created_by,
--     group_budgets.created_by, budget_percentage_history.changed_by
--     (tutte NOT NULL, ON DELETE CASCADE)
--   - SET NULL: expenses.created_by, expenses.paid_by,
--     expense_categories.created_by, profiles.group_id
--   - NESSUNA AZIONE (bloccherebbero la DELETE, gestite qui prima):
--     family_groups.created_by, invites.created_by, invites.used_by,
--     expenses.last_modified_by
--
-- Regole:
--   - admin di un gruppo con altri membri -> errore 'admin_has_members'
--     (deve prima rimuovere i membri o eliminare il gruppo)
--   - admin/ultimo membro del proprio gruppo -> il gruppo viene eliminato
--   - gruppi "legacy" creati dall'utente ma di cui non fa piu' parte:
--     eliminati se vuoti, altrimenti created_by passa al membro piu' anziano
--     (che diventa admin)
--   - passo 2b: per i gruppi che CONTINUANO a esistere, created_by/changed_by
--     delle righe di gruppo create dall'utente passano a un altro membro:
--     admin attuale, poi membro piu' anziano, poi family_groups.created_by,
--     altrimenti errore 'group_data_owner_not_found' (rollback completo).
--     I budget personali di altri utenti creati dall'utente passano a
--     created_by = user_id. Se il gruppo viene eliminato le righe vanno via
--     col gruppo (corretto). NOTA: per budget_percentage_history l'attribuzione
--     dell'audit (changed_by) passa al nuovo owner, perche' la colonna e'
--     NOT NULL.
--   - p_anonymize = true -> sulle spese rimaste nei gruppi il nome diventa
--     'Utente eliminato'; con false il nome resta (keep name)
--
-- NOTA (comportamento invariato, da confermare): expenses.group_id ha
-- ON DELETE CASCADE, quindi l'eliminazione di un gruppo nei passi 1 e 2
-- cancella anche le spese ancora presenti in quel gruppo. Le spese non
-- vengono toccate da questa migration oltre a quanto sopra.

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
      DELETE FROM public.family_groups WHERE id = v_group_id;
    END IF;
  END IF;

  -- 2. Gruppi creati dall'utente di cui non fa piu' parte (dati legacy)
  FOR v_legacy IN
    SELECT fg.id FROM public.family_groups fg WHERE fg.created_by = v_uid
  LOOP
    SELECT p.id INTO v_new_owner
    FROM public.profiles p
    WHERE p.group_id = v_legacy.id AND p.id <> v_uid
    ORDER BY p.created_at NULLS LAST, p.id
    LIMIT 1;

    IF v_new_owner IS NULL THEN
      DELETE FROM public.family_groups WHERE id = v_legacy.id;
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
      RAISE EXCEPTION 'group_data_owner_not_found';
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
