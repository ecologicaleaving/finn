-- Migration: Add reimbursement v2 fields to expenses table
-- Issue #19: Sistema rimborsi v2 — tracking per creditore, flusso confirm, integrazione budget
-- Date: 2026-03-10

-- Add new columns to expenses table
ALTER TABLE public.expenses
  ADD COLUMN IF NOT EXISTS reimbursable_to_label TEXT DEFAULT NULL,
  ADD COLUMN IF NOT EXISTS reimbursable_to_user_id UUID DEFAULT NULL REFERENCES auth.users(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS reimbursable_amount DECIMAL(10,2) DEFAULT NULL,
  ADD COLUMN IF NOT EXISTS reimbursement_confirmed_by UUID DEFAULT NULL REFERENCES auth.users(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS reimbursement_note TEXT DEFAULT NULL;

-- Index for fast lookup of expenses where current user is the debtor
CREATE INDEX IF NOT EXISTS idx_expenses_reimbursable_to_user_id
  ON public.expenses(reimbursable_to_user_id)
  WHERE reimbursable_to_user_id IS NOT NULL;

-- RLS Policy: allow reimbursable_to_user_id user to read and update reimbursement_status
-- (so Giovanna can see expenses she needs to reimburse and confirm them)
CREATE POLICY IF NOT EXISTS "Debtor can view expenses assigned to them"
  ON public.expenses
  FOR SELECT
  TO authenticated
  USING (
    reimbursable_to_user_id = auth.uid()
  );

CREATE POLICY IF NOT EXISTS "Debtor can confirm reimbursement"
  ON public.expenses
  FOR UPDATE
  TO authenticated
  USING (
    reimbursable_to_user_id = auth.uid()
    AND reimbursement_status = 'reimbursable'
  )
  WITH CHECK (
    reimbursable_to_user_id = auth.uid()
    AND reimbursement_status = 'reimbursed'
    AND reimbursement_confirmed_by = auth.uid()
  );
