-- Migration: 20260926_49_fix_category_expense_count_and_batch_reassign.sql
-- Issue #49: category deletion leaves orphaned expenses.
--
-- Root cause: get_category_expense_count (019) and batch_update_expense_category
-- (018) read/write the legacy text column `expenses.category`, while the app
-- only populates `expenses.category_id` (UUID FK, ON DELETE SET NULL, 013).
-- The count therefore always returned 0 and the batch reassignment updated
-- 0 rows, so a category with expenses could be deleted, nulling their FK.
--
-- This migration redefines both functions (same signatures, no overloads)
-- to operate on `category_id`, scoped to the caller's group because they are
-- SECURITY DEFINER. Migrations 018 and 019 are left untouched.
--
-- Legacy column `expenses.category` is intentionally NOT modified by the
-- batch reassignment: it is no longer written by the app and is kept only
-- for historical/compatibility reads.
--
-- Idempotent: CREATE OR REPLACE with identical signatures, repeatable GRANTs.

-- ---------------------------------------------------------------------------
-- get_category_expense_count(TEXT)
-- ---------------------------------------------------------------------------
-- In produzione esiste la versione (uuid) della 019: CREATE OR REPLACE con un tipo
-- diverso non la sostituirebbe ma creerebbe un secondo overload ambiguo, che
-- continuerebbe a contare sulla colonna legacy. Si rimuove solo quell'overload
-- (nessun dato toccato; nessuna dipendenza oltre a PostgREST).
DROP FUNCTION IF EXISTS public.get_category_expense_count(UUID);

CREATE OR REPLACE FUNCTION public.get_category_expense_count(
  p_category_id TEXT
)
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
DECLARE
  v_count INTEGER;
  v_category_uuid UUID;
BEGIN
  IF p_category_id IS NULL OR btrim(p_category_id) = '' THEN
    RETURN 0;
  END IF;

  BEGIN
    v_category_uuid := p_category_id::uuid;
  EXCEPTION WHEN invalid_text_representation THEN
    -- Legacy non-UUID identifier: fall back to the legacy text column
    SELECT COUNT(*)
      INTO v_count
      FROM public.expenses e
     WHERE e.category = p_category_id
       AND e.group_id IN (
         SELECT p.group_id FROM public.profiles p WHERE p.id = auth.uid()
       );
    RETURN COALESCE(v_count, 0);
  END;

  SELECT COUNT(*)
    INTO v_count
    FROM public.expenses e
   WHERE e.category_id = v_category_uuid
     AND e.group_id IN (
       SELECT p.group_id FROM public.profiles p WHERE p.id = auth.uid()
     );

  RETURN COALESCE(v_count, 0);
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_category_expense_count(TEXT) TO authenticated;

COMMENT ON FUNCTION public.get_category_expense_count(TEXT) IS
  'Issue #49: number of expenses (expenses.category_id) using a category, '
  'limited to the caller''s group. Falls back to the legacy text column for '
  'non-UUID ids. Returns 0 when unused.';

-- ---------------------------------------------------------------------------
-- batch_update_expense_category(UUID, TEXT, TEXT)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.batch_update_expense_category(
  p_group_id UUID,
  p_old_category_id TEXT,
  p_new_category_id TEXT
)
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_updated_count INTEGER;
  v_old_uuid UUID;
  v_new_uuid UUID;
BEGIN
  -- (a) Caller must belong to the group (function bypasses RLS)
  IF NOT EXISTS (
    SELECT 1
      FROM public.profiles p
     WHERE p.id = auth.uid()
       AND p.group_id = p_group_id
  ) THEN
    RAISE EXCEPTION 'Not a member of group %', p_group_id
      USING ERRCODE = '42501';
  END IF;

  -- Validate identifiers (avoid cryptic 22P02 errors)
  BEGIN
    v_old_uuid := p_old_category_id::uuid;
    v_new_uuid := p_new_category_id::uuid;
  EXCEPTION WHEN invalid_text_representation THEN
    RAISE EXCEPTION 'Invalid category id (expected UUID): old=%, new=%',
      p_old_category_id, p_new_category_id
      USING ERRCODE = '22023';
  END;

  IF v_old_uuid IS NULL OR v_new_uuid IS NULL THEN
    RAISE EXCEPTION 'Category ids must not be null'
      USING ERRCODE = '22023';
  END IF;

  -- Nothing to do when source and target are the same
  IF v_old_uuid = v_new_uuid THEN
    RETURN 0;
  END IF;

  -- (b) Target category must exist in the same group
  IF NOT EXISTS (
    SELECT 1
      FROM public.expense_categories c
     WHERE c.id = v_new_uuid
       AND c.group_id = p_group_id
  ) THEN
    RAISE EXCEPTION 'Target category % not found in group %',
      v_new_uuid, p_group_id
      USING ERRCODE = '23503';
  END IF;

  -- (c) Reassign expenses via the FK column actually used by the app
  UPDATE public.expenses
     SET category_id = v_new_uuid,
         updated_at = NOW()
   WHERE group_id = p_group_id
     AND category_id = v_old_uuid;

  -- (d) Return affected rows
  GET DIAGNOSTICS v_updated_count = ROW_COUNT;
  RETURN v_updated_count;
END;
$$;

GRANT EXECUTE ON FUNCTION public.batch_update_expense_category(UUID, TEXT, TEXT) TO authenticated;

COMMENT ON FUNCTION public.batch_update_expense_category(UUID, TEXT, TEXT) IS
  'Issue #49: reassign expenses.category_id from old to new category within a '
  'group the caller belongs to. Target category must belong to the same group. '
  'Returns count of updated expenses (0 when old = new).';
