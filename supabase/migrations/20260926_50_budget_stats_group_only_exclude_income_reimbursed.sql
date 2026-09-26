-- Migration: Budget stats consider only group budgets and real group spending (issue #50)
--
-- Problems fixed:
--   1. get_category_budget_stats read `amount` from every category_budgets row of
--      the category (group + personal), so the value picked was arbitrary.
--   2. get_overall_group_budget_stats summed every category_budgets row (group +
--      personal), inflating the total budget.
--   3. Neither function excluded income (transaction_type = 'income') or already
--      reimbursed expenses (reimbursement_status = 'reimbursed') from spending.
--   4. ensure_altro_category_budget checked for ANY budget row of the "Varie"
--      category, so a personal budget prevented the group row from being created.
--
-- Notes:
--   - Group budget rows have user_id NULL, so the UNIQUE constraint
--     (category_id, group_id, year, month, is_group_budget, user_id) does not
--     prevent duplicates: we keep only the most recent group row per category.
--   - Signatures and RETURNS TABLE are unchanged (CREATE OR REPLACE, no DROP),
--     so this migration is idempotent.
--   - The euro-to-cents conversion introduced in 051 (amount * 100) is kept.

-- ---------------------------------------------------------------------------
-- 1. get_category_budget_stats
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION get_category_budget_stats(
  p_group_id UUID,
  p_category_id UUID,
  p_year INTEGER,
  p_month INTEGER
)
RETURNS TABLE(
  category_id UUID,
  category_name TEXT,
  budget_amount INTEGER,
  spent_amount INTEGER,
  remaining_amount INTEGER,
  percentage_used NUMERIC,
  is_over_budget BOOLEAN,
  month INTEGER,
  year INTEGER
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_budget_amount INTEGER;
  v_spent_amount INTEGER;
  v_category_name TEXT;
  v_month_start DATE;
  v_month_end DATE;
BEGIN
  v_month_start := make_date(p_year, p_month, 1);

  IF p_month = 12 THEN
    v_month_end := make_date(p_year + 1, 1, 1) - INTERVAL '1 day';
  ELSE
    v_month_end := make_date(p_year, p_month + 1, 1) - INTERVAL '1 day';
  END IF;

  -- Group budget only (most recent row if duplicates exist)
  SELECT cb.amount
  INTO v_budget_amount
  FROM public.category_budgets cb
  WHERE cb.group_id = p_group_id
    AND cb.category_id = p_category_id
    AND cb.year = p_year
    AND cb.month = p_month
    AND COALESCE(cb.is_group_budget, true) = true
  ORDER BY cb.updated_at DESC NULLS LAST, cb.created_at DESC NULLS LAST
  LIMIT 1;

  v_budget_amount := COALESCE(v_budget_amount, 0);

  SELECT ec.name
  INTO v_category_name
  FROM public.expense_categories ec
  WHERE ec.id = p_category_id;

  -- Group spending only, excluding income and reimbursed expenses (euros -> cents)
  SELECT COALESCE(SUM(e.amount * 100), 0)::INTEGER
  INTO v_spent_amount
  FROM public.expenses e
  WHERE e.group_id = p_group_id
    AND e.category_id = p_category_id
    AND e.is_group_expense = true
    AND e.transaction_type <> 'income'
    AND e.reimbursement_status <> 'reimbursed'
    AND e.date >= v_month_start
    AND e.date <= v_month_end;

  RETURN QUERY
  SELECT
    p_category_id,
    v_category_name,
    v_budget_amount,
    v_spent_amount,
    v_budget_amount - v_spent_amount AS remaining_amount,
    CASE
      WHEN v_budget_amount > 0 THEN (v_spent_amount::NUMERIC / v_budget_amount::NUMERIC) * 100
      ELSE 0
    END AS percentage_used,
    v_spent_amount > v_budget_amount AS is_over_budget,
    p_month,
    p_year;
END;
$$;

COMMENT ON FUNCTION get_category_budget_stats(UUID, UUID, INTEGER, INTEGER) IS
'Calculates group budget statistics for a specific category and month (group budget row only; group expenses excluding income and reimbursed).';

-- ---------------------------------------------------------------------------
-- 2. get_overall_group_budget_stats
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION get_overall_group_budget_stats(
  p_group_id UUID,
  p_year INTEGER,
  p_month INTEGER
)
RETURNS TABLE(
  total_budgeted INTEGER,
  total_spent INTEGER,
  total_remaining INTEGER,
  percentage_used NUMERIC,
  categories_over_budget INTEGER,
  month INTEGER,
  year INTEGER
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_total_budgeted INTEGER;
  v_total_spent INTEGER;
  v_categories_over_budget INTEGER;
  v_month_start DATE;
  v_month_end DATE;
BEGIN
  v_month_start := make_date(p_year, p_month, 1);

  IF p_month = 12 THEN
    v_month_end := make_date(p_year + 1, 1, 1) - INTERVAL '1 day';
  ELSE
    v_month_end := make_date(p_year, p_month + 1, 1) - INTERVAL '1 day';
  END IF;

  -- Total budgeted: one group budget row per category
  SELECT COALESCE(SUM(gb.amount), 0)::INTEGER
  INTO v_total_budgeted
  FROM (
    SELECT DISTINCT ON (cb.category_id) cb.amount
    FROM public.category_budgets cb
    WHERE cb.group_id = p_group_id
      AND cb.year = p_year
      AND cb.month = p_month
      AND COALESCE(cb.is_group_budget, true) = true
    ORDER BY cb.category_id, cb.updated_at DESC NULLS LAST, cb.created_at DESC NULLS LAST
  ) gb;

  -- Total spent: group expenses with a category, excluding income and reimbursed
  SELECT COALESCE(SUM(e.amount * 100), 0)::INTEGER
  INTO v_total_spent
  FROM public.expenses e
  WHERE e.group_id = p_group_id
    AND e.category_id IS NOT NULL
    AND e.is_group_expense = true
    AND e.transaction_type <> 'income'
    AND e.reimbursement_status <> 'reimbursed'
    AND e.date >= v_month_start
    AND e.date <= v_month_end;

  -- Categories over budget (expense filters in the JOIN's ON clause so that
  -- categories without spending are not lost)
  WITH group_budgets AS (
    SELECT DISTINCT ON (cb.category_id)
      cb.category_id,
      cb.group_id,
      cb.amount
    FROM public.category_budgets cb
    WHERE cb.group_id = p_group_id
      AND cb.year = p_year
      AND cb.month = p_month
      AND COALESCE(cb.is_group_budget, true) = true
    ORDER BY cb.category_id, cb.updated_at DESC NULLS LAST, cb.created_at DESC NULLS LAST
  ),
  category_spending AS (
    SELECT
      gb.category_id,
      gb.amount AS budget,
      COALESCE(SUM(e.amount * 100), 0)::INTEGER AS spent
    FROM group_budgets gb
    LEFT JOIN public.expenses e
      ON e.category_id = gb.category_id
      AND e.group_id = gb.group_id
      AND e.is_group_expense = true
      AND e.transaction_type <> 'income'
      AND e.reimbursement_status <> 'reimbursed'
      AND e.date >= v_month_start
      AND e.date <= v_month_end
    GROUP BY gb.category_id, gb.amount
  )
  SELECT COUNT(*)::INTEGER
  INTO v_categories_over_budget
  FROM category_spending cs
  WHERE cs.spent > cs.budget;

  RETURN QUERY
  SELECT
    v_total_budgeted,
    v_total_spent,
    v_total_budgeted - v_total_spent AS total_remaining,
    CASE
      WHEN v_total_budgeted > 0 THEN (v_total_spent::NUMERIC / v_total_budgeted::NUMERIC) * 100
      ELSE 0
    END AS percentage_used,
    v_categories_over_budget,
    p_month,
    p_year;
END;
$$;

COMMENT ON FUNCTION get_overall_group_budget_stats(UUID, INTEGER, INTEGER) IS
'Calculates overall group budget statistics (group budget rows only, one per category; group expenses excluding income and reimbursed).';

-- ---------------------------------------------------------------------------
-- 3. ensure_altro_category_budget: existence check limited to the group row
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION ensure_altro_category_budget(
    p_group_id UUID,
    p_year INTEGER,
    p_month INTEGER
)
RETURNS TABLE (
    id UUID,
    category_id UUID,
    group_id UUID,
    amount INTEGER,
    month INTEGER,
    year INTEGER,
    created_by UUID,
    is_group_budget BOOLEAN,
    budget_type TEXT,
    percentage_of_group NUMERIC,
    created_at TIMESTAMPTZ,
    updated_at TIMESTAMPTZ
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_system_category_id UUID;
    v_current_user_id UUID;
    v_budget_id UUID;
BEGIN
    v_current_user_id := auth.uid();

    SELECT ec.id INTO v_system_category_id
    FROM expense_categories ec
    WHERE ec.group_id = p_group_id
    AND ec.is_system_category = true
    AND ec.is_default = true
    LIMIT 1;

    IF v_system_category_id IS NULL THEN
        INSERT INTO expense_categories (
            name,
            group_id,
            is_default,
            is_system_category,
            created_by
        ) VALUES (
            'Varie',
            p_group_id,
            true,
            true,
            v_current_user_id
        )
        RETURNING expense_categories.id INTO v_system_category_id;
    END IF;

    -- Only the GROUP budget row counts: a personal "Varie" budget must not
    -- prevent the group row from being created.
    SELECT cb.id INTO v_budget_id
    FROM category_budgets cb
    WHERE cb.category_id = v_system_category_id
    AND cb.group_id = p_group_id
    AND cb.year = p_year
    AND cb.month = p_month
    AND COALESCE(cb.is_group_budget, true) = true
    ORDER BY cb.updated_at DESC NULLS LAST
    LIMIT 1;

    IF v_budget_id IS NULL THEN
        INSERT INTO category_budgets (
            category_id,
            group_id,
            amount,
            month,
            year,
            created_by,
            is_group_budget,
            budget_type
        ) VALUES (
            v_system_category_id,
            p_group_id,
            0,
            p_month,
            p_year,
            v_current_user_id,
            true,
            'FIXED'
        )
        RETURNING category_budgets.id INTO v_budget_id;
    END IF;

    RETURN QUERY
    SELECT
        cb.id,
        cb.category_id,
        cb.group_id,
        cb.amount,
        cb.month,
        cb.year,
        cb.created_by,
        cb.is_group_budget,
        cb.budget_type,
        cb.percentage_of_group,
        cb.created_at,
        cb.updated_at
    FROM category_budgets cb
    WHERE cb.id = v_budget_id;
END;
$$;

COMMENT ON FUNCTION ensure_altro_category_budget(UUID, INTEGER, INTEGER) IS
'Ensures the "Altro" (Varie) system category has a GROUP budget entry for the specified group/month/year. Creates it with amount=0 if missing. Returns the budget record.';

GRANT EXECUTE ON FUNCTION ensure_altro_category_budget(UUID, INTEGER, INTEGER) TO authenticated;
