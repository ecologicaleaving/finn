-- Migration: 20260926_46_account_deletion.sql
-- Issue: #46 - «Elimina account» elimina davvero l'utente (AC7)
--
-- DA APPLICARE A MANO su Supabase (SQL editor), DOPO
-- 20260926_46_secure_group_membership.sql.
-- Idempotente: solo CREATE OR REPLACE FUNCTION / REVOKE / GRANT.
--
-- delete_my_account(p_anonymize) elimina la riga auth.users del chiamante.
-- DELETE auth.users -> CASCADE su profiles (001). Da profiles/auth.users:
--   - CASCADE: income_sources, savings_goals, recurring_expenses,
--     group_expense_assignments, personal_budgets, category_budgets(user_id),
--     user_category_usage, budget_percentage_history, ...
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
--   - p_anonymize = true -> sulle spese rimaste nei gruppi il nome diventa
--     'Utente eliminato'; con false il nome resta (keep name)

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
