-- Issue #69: spese ricorrenti sul database
--
-- Crea public.recurring_expenses (template delle ricorrenze) e collega le
-- istanze generate alle spese con expenses.recurring_expense_id.
--
-- Tutto idempotente: si puo rieseguire senza errori. Solo oggetti nuovi,
-- nessun DROP TABLE, nessun DELETE, nessun UPDATE su dati esistenti.
-- Sostituisce la vecchia 20260116_001_create_recurring_expenses.sql, mai
-- applicata e non funzionante (usa family_group_members, che non esiste).
--
-- Modello gruppi: profiles.group_id -> family_groups.id (get_my_group_id()).

BEGIN;

-- 1) Tabella template -------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.recurring_expenses (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  group_id uuid NULL REFERENCES public.family_groups(id) ON DELETE SET NULL,
  -- Senza FK: puo puntare a una spesa solo locale
  template_expense_id uuid NULL,
  amount numeric(12,2) NOT NULL CHECK (amount > 0),
  -- Senza FK: non deve bloccare ne modificare a cascata la cancellazione
  -- delle categorie (#49)
  category_id uuid NOT NULL,
  category_name text NOT NULL,
  merchant text CHECK (merchant IS NULL OR char_length(merchant) <= 100),
  notes text CHECK (notes IS NULL OR char_length(notes) <= 500),
  is_group_expense boolean NOT NULL DEFAULT true,
  frequency text NOT NULL CHECK (frequency IN ('daily','weekly','monthly','yearly')),
  anchor_date timestamptz NOT NULL,
  is_paused boolean NOT NULL DEFAULT false,
  last_instance_created_at timestamptz,
  next_due_date timestamptz,
  budget_reservation_enabled boolean NOT NULL DEFAULT false,
  default_reimbursement_status text NOT NULL DEFAULT 'none'
    CHECK (default_reimbursement_status IN ('none','reimbursable','reimbursed')),
  payment_method_id uuid NULL,
  payment_method_name text,
  deleted_at timestamptz NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

-- 2) Indici -------------------------------------------------------------------
CREATE INDEX IF NOT EXISTS recurring_expenses_user_idx
  ON public.recurring_expenses (user_id);
CREATE INDEX IF NOT EXISTS recurring_expenses_group_idx
  ON public.recurring_expenses (group_id);
CREATE INDEX IF NOT EXISTS recurring_expenses_active_idx
  ON public.recurring_expenses (user_id, next_due_date)
  WHERE is_paused = false AND deleted_at IS NULL;

-- 3) Trigger updated_at ---------------------------------------------------------
CREATE OR REPLACE FUNCTION public.set_recurring_expenses_updated_at()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS recurring_expenses_set_updated_at ON public.recurring_expenses;
CREATE TRIGGER recurring_expenses_set_updated_at
  BEFORE UPDATE ON public.recurring_expenses
  FOR EACH ROW EXECUTE FUNCTION public.set_recurring_expenses_updated_at();

-- 4) RLS --------------------------------------------------------------------------
-- Nessuna policy DELETE: l'eliminazione e un soft-delete (deleted_at).
ALTER TABLE public.recurring_expenses ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS recurring_expenses_select ON public.recurring_expenses;
CREATE POLICY recurring_expenses_select ON public.recurring_expenses
  FOR SELECT TO authenticated
  USING (
    user_id = auth.uid()
    OR (group_id IS NOT NULL AND group_id = public.get_my_group_id())
  );

DROP POLICY IF EXISTS recurring_expenses_insert ON public.recurring_expenses;
CREATE POLICY recurring_expenses_insert ON public.recurring_expenses
  FOR INSERT TO authenticated
  WITH CHECK (
    user_id = auth.uid()
    AND (group_id IS NULL OR group_id = public.get_my_group_id())
  );

DROP POLICY IF EXISTS recurring_expenses_update ON public.recurring_expenses;
CREATE POLICY recurring_expenses_update ON public.recurring_expenses
  FOR UPDATE TO authenticated
  USING (user_id = auth.uid())
  WITH CHECK (
    user_id = auth.uid()
    AND (group_id IS NULL OR group_id = public.get_my_group_id())
  );

GRANT SELECT, INSERT, UPDATE ON public.recurring_expenses TO authenticated;

-- 5) Colonne additive su expenses -----------------------------------------------
-- Senza FK: un'istanza non deve restare bloccata se il template non e ancora
-- arrivato sul server.
ALTER TABLE public.expenses
  ADD COLUMN IF NOT EXISTS recurring_expense_id uuid NULL;
ALTER TABLE public.expenses
  ADD COLUMN IF NOT EXISTS is_recurring_instance boolean NOT NULL DEFAULT false;

CREATE INDEX IF NOT EXISTS expenses_recurring_expense_idx
  ON public.expenses (recurring_expense_id)
  WHERE recurring_expense_id IS NOT NULL;

COMMIT;
