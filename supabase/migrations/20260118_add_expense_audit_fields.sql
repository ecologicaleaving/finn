-- Migration: Add audit trail to expenses
-- Feature: 001-admin-expenses-cash-fix
-- Date: 2026-01-18
-- Purpose: Track who last modified each expense for admin accountability

-- Add last_modified_by column
ALTER TABLE public.expenses
ADD COLUMN last_modified_by UUID REFERENCES public.profiles(id);

-- Backfill existing rows (set to creator)
UPDATE public.expenses
SET last_modified_by = created_by
WHERE last_modified_by IS NULL;

-- Add comment for documentation
COMMENT ON COLUMN public.expenses.last_modified_by IS
'UUID of user who last modified this expense (tracks audit trail for admin edits)';

-- Create index for query performance
CREATE INDEX idx_expenses_last_modified_by
ON public.expenses(last_modified_by);

-- Verify migration
DO $$
BEGIN
  ASSERT (SELECT COUNT(*) FROM public.expenses WHERE last_modified_by IS NOT NULL) =
         (SELECT COUNT(*) FROM public.expenses),
  'Migration failed: Not all expenses have last_modified_by set';
END $$;
