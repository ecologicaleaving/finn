-- Migration: 20260926_46_secure_group_membership.sql
-- Issue: #46 - Nessuno puo' entrare nel gruppo di un'altra famiglia;
--              rimuovi membro / elimina gruppo funzionano davvero.
--
-- DA APPLICARE A MANO su Supabase (SQL editor) dopo aver confrontato le policy
-- attualmente in produzione su public.profiles e public.invites.
-- La migration e' idempotente: usa solo CREATE OR REPLACE FUNCTION,
-- DROP POLICY IF EXISTS / DROP TRIGGER IF EXISTS prima di ogni CREATE.
-- E' avvolta in BEGIN/COMMIT: un errore a meta' nell'SQL editor non lascia
-- lo stato parziale.
--
-- REGOLA DI DAVIDE (assoluta): le spese di un membro RESTANO nel gruppo quando
-- il membro viene rimosso, esce o elimina l'account. Le spese si cancellano
-- SOLO se eliminate una per una. Poiche' expenses.group_id e' ON DELETE
-- CASCADE, un gruppo che contiene spese NON viene mai eliminato:
--   - remove_group_member: le spese del membro rimosso restano nel gruppo
--     (non tocca expenses; quelle personali restano visibili al loro autore,
--     policy 'Creators can view personal expenses')
--   - leave_group: l'ultimo membro con spese lascia il gruppo SENZA membri e
--     SENZA essere eliminato; senza spese il gruppo si elimina (nessuna perdita)
--   - delete_family_group: ammessa solo se il gruppo non ha spese
--     ('group_has_expenses' altrimenti)
--   - la policy DELETE diretta su family_groups viene eliminata (vedi sotto):
--     l'unica via per eliminare un gruppo e' delete_family_group()
--
-- Contenuto:
--   AC1  trigger che impedisce a un utente autenticato di modificare
--        direttamente profiles.group_id / profiles.is_group_admin
--   AC2  SELECT su invites limitata agli admin del gruppo +
--        validate_invite_code() SECURITY DEFINER
--   AC3  create_family_group / join_group_with_code / leave_group
--        SECURITY DEFINER
--   AC4  leave / delete / remove impostano is_group_admin = false
--   AC5  remove_group_member() SECURITY DEFINER (errore se 0 righe)
--   AC6  delete_family_group() SECURITY DEFINER (errore se 0 righe)
--
-- Codici di errore (messaggio dell'eccezione, letti dall'app in
-- lib/features/groups/data/datasources/group_rpc_result.dart):
--   not_authenticated, invalid_code, already_used, expired, already_in_group,
--   not_in_group, not_admin, admin_cannot_leave, has_members, member_not_found,
--   cannot_remove_self, cannot_remove_admin, group_not_deleted, invalid_group_name,
--   membership_change_not_allowed, group_has_expenses

BEGIN;

-- ============================================================================
-- AC1: protezione di profiles.group_id / profiles.is_group_admin
-- ============================================================================
-- Si usa un trigger (e non i column privileges) per non toccare i GRANT sulle
-- altre colonne del profilo (display_name, timezone, budget_wizard_completed,
-- keep_name_on_delete, ...).
-- Il controllo e' su current_user: le chiamate dirette via PostgREST girano
-- come 'authenticated' / 'anon' e vengono rifiutate; le funzioni SECURITY
-- DEFINER (owner postgres) e le azioni FK ON DELETE SET NULL (eseguite come
-- owner della tabella) continuano a funzionare.

CREATE OR REPLACE FUNCTION public.prevent_profile_membership_change()
RETURNS trigger
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public
AS $$
BEGIN
  IF current_user NOT IN ('authenticated', 'anon') THEN
    RETURN NEW;
  END IF;

  IF TG_OP = 'INSERT' THEN
    IF NEW.group_id IS NOT NULL OR COALESCE(NEW.is_group_admin, false) THEN
      RAISE EXCEPTION 'membership_change_not_allowed'
        USING ERRCODE = '42501',
              HINT = 'group_id e is_group_admin si impostano solo tramite le funzioni RPC del gruppo';
    END IF;
    RETURN NEW;
  END IF;

  IF NEW.group_id IS DISTINCT FROM OLD.group_id
     OR NEW.is_group_admin IS DISTINCT FROM OLD.is_group_admin THEN
    RAISE EXCEPTION 'membership_change_not_allowed'
      USING ERRCODE = '42501',
            HINT = 'group_id e is_group_admin si impostano solo tramite le funzioni RPC del gruppo';
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_profiles_protect_membership ON public.profiles;
CREATE TRIGGER trg_profiles_protect_membership
  BEFORE INSERT OR UPDATE ON public.profiles
  FOR EACH ROW
  EXECUTE FUNCTION public.prevent_profile_membership_change();

-- Pulizia una tantum (idempotente) dei flag admin rimasti "appesi":
-- - utenti senza gruppo con is_group_admin = true (leave/delete vecchi)
-- - utenti admin di un gruppo che non hanno creato (entrati con un flag
--   rimasto dal gruppo precedente). Nessuna funzione dell'app assegna
--   is_group_admin a un non-creatore, quindi questi flag sono tutti stale.
UPDATE public.profiles
SET is_group_admin = false
WHERE is_group_admin = true
  AND group_id IS NULL;

UPDATE public.profiles p
SET is_group_admin = false
WHERE p.is_group_admin = true
  AND p.group_id IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM public.family_groups fg
    WHERE fg.id = p.group_id AND fg.created_by = p.id
  );

-- ============================================================================
-- AC2: inviti visibili solo agli admin del gruppo + validazione server-side
-- ============================================================================

DROP POLICY IF EXISTS "Anyone can validate invite codes" ON public.invites;
DROP POLICY IF EXISTS "Users can use invites" ON public.invites;

DROP POLICY IF EXISTS "Admins can view group invites" ON public.invites;
CREATE POLICY "Admins can view group invites"
    ON public.invites FOR SELECT
    USING (
        group_id = public.get_my_group_id()
        AND EXISTS (
            SELECT 1 FROM public.profiles p
            WHERE p.id = auth.uid()
              AND p.is_group_admin = true
              AND p.group_id = public.get_my_group_id()
        )
    );

-- Valida un codice invito esatto e restituisce solo i dati necessari al join.
-- Codice inesistente / gia' usato / scaduto -> eccezione.
CREATE OR REPLACE FUNCTION public.validate_invite_code(p_code text)
RETURNS TABLE (group_id uuid, group_name text, expires_at timestamptz)
LANGUAGE plpgsql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
DECLARE
  v_invite public.invites;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '28000';
  END IF;

  SELECT i.* INTO v_invite
  FROM public.invites i
  WHERE i.code = upper(btrim(COALESCE(p_code, '')));

  IF NOT FOUND THEN
    RAISE EXCEPTION 'invalid_code' USING HINT = 'Codice invito non valido';
  END IF;

  IF v_invite.used_at IS NOT NULL OR v_invite.used_by IS NOT NULL THEN
    RAISE EXCEPTION 'already_used' USING HINT = 'Codice invito gia'' utilizzato';
  END IF;

  IF v_invite.expires_at <= now() THEN
    RAISE EXCEPTION 'expired' USING HINT = 'Codice invito scaduto';
  END IF;

  -- Gruppo abbandonato (nessun membro, ma con spese conservate): l'invito non
  -- deve aprirlo a un estraneo.
  IF NOT EXISTS (SELECT 1 FROM public.profiles pr WHERE pr.group_id = v_invite.group_id) THEN
    RAISE EXCEPTION 'invalid_code' USING HINT = 'Codice invito non valido';
  END IF;

  RETURN QUERY
    SELECT v_invite.group_id, fg.name, v_invite.expires_at
    FROM public.family_groups fg
    WHERE fg.id = v_invite.group_id;
END;
$$;

REVOKE ALL ON FUNCTION public.validate_invite_code(text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.validate_invite_code(text) FROM anon;
GRANT EXECUTE ON FUNCTION public.validate_invite_code(text) TO authenticated;

-- ============================================================================
-- AC3: creazione gruppo (stessa firma e tipo di ritorno di 005)
-- ============================================================================

CREATE OR REPLACE FUNCTION public.create_family_group(group_name TEXT)
RETURNS public.family_groups
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  new_group public.family_groups;
  v_uid UUID := auth.uid();
  v_current_group UUID;
  v_name TEXT := btrim(COALESCE(group_name, ''));
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '28000';
  END IF;

  IF char_length(v_name) < 2 OR char_length(v_name) > 30 THEN
    RAISE EXCEPTION 'invalid_group_name'
      USING HINT = 'Il nome del gruppo deve avere tra 2 e 30 caratteri';
  END IF;

  SELECT p.group_id INTO v_current_group
  FROM public.profiles p
  WHERE p.id = v_uid
  FOR UPDATE;

  IF v_current_group IS NOT NULL THEN
    RAISE EXCEPTION 'already_in_group';
  END IF;

  INSERT INTO public.family_groups (name, created_by)
  VALUES (v_name, v_uid)
  RETURNING * INTO new_group;

  UPDATE public.profiles
  SET group_id = new_group.id, is_group_admin = true
  WHERE id = v_uid;

  RETURN new_group;
END;
$$;

REVOKE ALL ON FUNCTION public.create_family_group(TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.create_family_group(TEXT) FROM anon;
GRANT EXECUTE ON FUNCTION public.create_family_group(TEXT) TO authenticated;

-- ============================================================================
-- AC3: entrare in un gruppo con codice invito
-- ============================================================================

CREATE OR REPLACE FUNCTION public.join_group_with_code(p_code text)
RETURNS public.family_groups
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid UUID := auth.uid();
  v_current_group UUID;
  v_invite public.invites;
  v_group public.family_groups;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '28000';
  END IF;

  SELECT p.group_id INTO v_current_group
  FROM public.profiles p
  WHERE p.id = v_uid
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '28000';
  END IF;

  IF v_current_group IS NOT NULL THEN
    RAISE EXCEPTION 'already_in_group';
  END IF;

  -- FOR UPDATE: due utenti che usano lo stesso codice insieme vengono
  -- serializzati; il secondo vede used_at valorizzato.
  SELECT i.* INTO v_invite
  FROM public.invites i
  WHERE i.code = upper(btrim(COALESCE(p_code, '')))
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'invalid_code' USING HINT = 'Codice invito non valido';
  END IF;

  IF v_invite.used_at IS NOT NULL OR v_invite.used_by IS NOT NULL THEN
    RAISE EXCEPTION 'already_used' USING HINT = 'Codice invito gia'' utilizzato';
  END IF;

  IF v_invite.expires_at <= now() THEN
    RAISE EXCEPTION 'expired' USING HINT = 'Codice invito scaduto';
  END IF;

  -- Gruppo abbandonato (nessun membro, ma con spese conservate): un invito
  -- pendente di un ex membro non deve aprirlo a un estraneo.
  IF NOT EXISTS (SELECT 1 FROM public.profiles pr WHERE pr.group_id = v_invite.group_id) THEN
    RAISE EXCEPTION 'invalid_code' USING HINT = 'Codice invito non valido';
  END IF;

  UPDATE public.invites
  SET used_by = v_uid, used_at = now()
  WHERE id = v_invite.id;

  UPDATE public.profiles
  SET group_id = v_invite.group_id, is_group_admin = false
  WHERE id = v_uid;

  SELECT fg.* INTO v_group
  FROM public.family_groups fg
  WHERE fg.id = v_invite.group_id;

  RETURN v_group;
END;
$$;

REVOKE ALL ON FUNCTION public.join_group_with_code(text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.join_group_with_code(text) FROM anon;
GRANT EXECUTE ON FUNCTION public.join_group_with_code(text) TO authenticated;

-- ============================================================================
-- Helper interno: elimina un gruppo rimasto senza membri SOLO se non ha spese
-- ============================================================================
-- Ritorna: 'missing' | 'has_members' | 'kept' | 'deleted'.
-- - 'kept': il gruppo ha spese (anche personali): NON viene eliminato; gli
--   inviti pendenti scadono (nessuno deve poter entrare in un gruppo
--   abbandonato). Nulla viene cancellato.
-- - 'deleted': nessuna spesa -> nessuna perdita di dati, il gruppo si elimina.
-- Il lock FOR UPDATE sulla riga del gruppo serializza: un INSERT concorrente
-- in expenses (la sua FK prende FOR KEY SHARE) aspetta e poi fallisce per FK,
-- invece di sparire in silenzio col CASCADE.
-- Non e' esposta all'app: nessun GRANT, REVOKE esplicito anche da anon e
-- authenticated (i default privileges di Supabase li concedono).

CREATE OR REPLACE FUNCTION public._dispose_group_if_abandoned(p_group_id uuid)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  PERFORM 1 FROM public.family_groups WHERE id = p_group_id FOR UPDATE;
  IF NOT FOUND THEN
    RETURN 'missing';
  END IF;

  IF EXISTS (SELECT 1 FROM public.profiles WHERE group_id = p_group_id) THEN
    RETURN 'has_members';
  END IF;

  IF EXISTS (SELECT 1 FROM public.expenses WHERE group_id = p_group_id) THEN
    UPDATE public.invites
    SET expires_at = now()
    WHERE group_id = p_group_id
      AND used_at IS NULL
      AND used_by IS NULL
      AND expires_at > now();
    RETURN 'kept';
  END IF;

  DELETE FROM public.family_groups WHERE id = p_group_id;
  RETURN 'deleted';
END;
$$;

REVOKE ALL ON FUNCTION public._dispose_group_if_abandoned(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public._dispose_group_if_abandoned(uuid) FROM anon;
REVOKE ALL ON FUNCTION public._dispose_group_if_abandoned(uuid) FROM authenticated;

-- ============================================================================
-- AC3/AC4: lasciare il gruppo
-- ============================================================================
-- - admin con altri membri -> admin_cannot_leave
-- - ultimo membro: se il gruppo ha spese il gruppo NON viene eliminato (resta
--   senza membri, con tutte le spese; gli inviti pendenti scadono). Se non ha
--   spese si elimina (nessuna perdita).
-- - uscire non cancella mai spese.

CREATE OR REPLACE FUNCTION public.leave_group()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid UUID := auth.uid();
  v_group_id UUID;
  v_is_admin BOOLEAN;
  v_others INTEGER;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '28000';
  END IF;

  SELECT p.group_id, COALESCE(p.is_group_admin, false)
  INTO v_group_id, v_is_admin
  FROM public.profiles p
  WHERE p.id = v_uid
  FOR UPDATE;

  IF v_group_id IS NULL THEN
    RAISE EXCEPTION 'not_in_group';
  END IF;

  -- Serializza uscite concorrenti dallo stesso gruppo
  PERFORM 1 FROM public.family_groups WHERE id = v_group_id FOR UPDATE;

  -- created_by puo' essere NULL (gruppo tenuto senza membri): il confronto
  -- da' NULL, cioe' false.
  v_is_admin := v_is_admin OR EXISTS (
    SELECT 1 FROM public.family_groups fg
    WHERE fg.id = v_group_id AND fg.created_by = v_uid
  );

  SELECT count(*) INTO v_others
  FROM public.profiles p
  WHERE p.group_id = v_group_id AND p.id <> v_uid;

  IF v_is_admin AND v_others > 0 THEN
    RAISE EXCEPTION 'admin_cannot_leave';
  END IF;

  UPDATE public.profiles
  SET group_id = NULL, is_group_admin = false
  WHERE id = v_uid;

  IF v_others = 0 THEN
    -- Elimina il gruppo solo se non ha spese; altrimenti resta.
    PERFORM public._dispose_group_if_abandoned(v_group_id);
  END IF;
END;
$$;

REVOKE ALL ON FUNCTION public.leave_group() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.leave_group() FROM anon;
GRANT EXECUTE ON FUNCTION public.leave_group() TO authenticated;

-- ============================================================================
-- AC4/AC5: rimuovere un membro (solo admin dello stesso gruppo)
-- ============================================================================
-- Fa solo UPDATE su profiles: le spese del membro rimosso RESTANO nel gruppo
-- (nessun riferimento a expenses, nessuna DELETE). Le sue spese personali
-- restano visibili al loro autore (policy 'Creators can view personal
-- expenses'). Con family_groups.created_by NULL il controllo
-- cannot_remove_admin non scatta (NULL = uuid e' NULL): corretto.

CREATE OR REPLACE FUNCTION public.remove_group_member(p_user_id uuid)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid UUID := auth.uid();
  v_group_id UUID;
  v_is_admin BOOLEAN;
  v_rows INTEGER;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '28000';
  END IF;

  SELECT p.group_id, COALESCE(p.is_group_admin, false)
  INTO v_group_id, v_is_admin
  FROM public.profiles p
  WHERE p.id = v_uid;

  IF v_group_id IS NULL THEN
    RAISE EXCEPTION 'not_in_group';
  END IF;

  v_is_admin := v_is_admin OR EXISTS (
    SELECT 1 FROM public.family_groups fg
    WHERE fg.id = v_group_id AND fg.created_by = v_uid
  );

  IF NOT v_is_admin THEN
    RAISE EXCEPTION 'not_admin';
  END IF;

  IF p_user_id IS NULL THEN
    RAISE EXCEPTION 'member_not_found';
  END IF;

  IF p_user_id = v_uid THEN
    RAISE EXCEPTION 'cannot_remove_self';
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.family_groups fg
    WHERE fg.id = v_group_id AND fg.created_by = p_user_id
  ) THEN
    RAISE EXCEPTION 'cannot_remove_admin';
  END IF;

  UPDATE public.profiles
  SET group_id = NULL, is_group_admin = false
  WHERE id = p_user_id
    AND group_id = v_group_id;

  GET DIAGNOSTICS v_rows = ROW_COUNT;

  IF v_rows = 0 THEN
    RAISE EXCEPTION 'member_not_found';
  END IF;

  RETURN v_rows;
END;
$$;

REVOKE ALL ON FUNCTION public.remove_group_member(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.remove_group_member(uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.remove_group_member(uuid) TO authenticated;

-- ============================================================================
-- AC4/AC6: eliminare il gruppo (solo admin, nessun altro membro)
-- ============================================================================
-- Ammessa SOLO se il gruppo non contiene spese (nessuna riga in expenses con
-- quel group_id, anche personali): expenses.group_id e' ON DELETE CASCADE, quindi
-- eliminare un gruppo con spese le cancellerebbe tutte. In quel caso
-- eccezione 'group_has_expenses': le spese vanno eliminate una per una.
-- Senza spese, la DELETE porta via invites, budget, categorie, ... (CASCADE);
-- profiles.group_id e' ON DELETE SET NULL (ma lo azzeriamo esplicitamente
-- insieme a is_group_admin).

CREATE OR REPLACE FUNCTION public.delete_family_group()
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid UUID := auth.uid();
  v_group_id UUID;
  v_is_admin BOOLEAN;
  v_others INTEGER;
  v_rows INTEGER;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '28000';
  END IF;

  SELECT p.group_id, COALESCE(p.is_group_admin, false)
  INTO v_group_id, v_is_admin
  FROM public.profiles p
  WHERE p.id = v_uid
  FOR UPDATE;

  IF v_group_id IS NULL THEN
    RAISE EXCEPTION 'not_in_group';
  END IF;

  v_is_admin := v_is_admin OR EXISTS (
    SELECT 1 FROM public.family_groups fg
    WHERE fg.id = v_group_id AND fg.created_by = v_uid
  );

  IF NOT v_is_admin THEN
    RAISE EXCEPTION 'not_admin';
  END IF;

  SELECT count(*) INTO v_others
  FROM public.profiles p
  WHERE p.group_id = v_group_id AND p.id <> v_uid;

  IF v_others > 0 THEN
    RAISE EXCEPTION 'has_members';
  END IF;

  -- Lock sul gruppo: un INSERT concorrente di una spesa aspetta e poi fallisce.
  PERFORM 1 FROM public.family_groups WHERE id = v_group_id FOR UPDATE;

  -- Mai cancellare spese in blocco: il gruppo si elimina solo se e' vuoto.
  IF EXISTS (SELECT 1 FROM public.expenses WHERE group_id = v_group_id) THEN
    RAISE EXCEPTION 'group_has_expenses'
      USING HINT = 'Elimina prima le spese una per una';
  END IF;

  UPDATE public.profiles
  SET group_id = NULL, is_group_admin = false
  WHERE group_id = v_group_id;

  DELETE FROM public.family_groups WHERE id = v_group_id;
  GET DIAGNOSTICS v_rows = ROW_COUNT;

  IF v_rows = 0 THEN
    RAISE EXCEPTION 'group_not_deleted';
  END IF;

  RETURN v_rows;
END;
$$;

REVOKE ALL ON FUNCTION public.delete_family_group() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.delete_family_group() FROM anon;
GRANT EXECUTE ON FUNCTION public.delete_family_group() TO authenticated;

-- ============================================================================
-- Blindatura RLS: nessuna DELETE diretta di un gruppo via REST
-- ============================================================================
-- La policy "Admins can delete their group" (004_fix_rls_recursion.sql)
-- permetterebbe all'admin una DELETE diretta su family_groups che, col CASCADE
-- su expenses.group_id, cancellerebbe tutte le spese aggirando
-- delete_family_group(). Viene eliminata e NON ricreata. La policy DELETE su
-- expenses resta: e' la cancellazione singola, ammessa dalla regola.
DROP POLICY IF EXISTS "Admins can delete their group" ON public.family_groups;

COMMIT;
