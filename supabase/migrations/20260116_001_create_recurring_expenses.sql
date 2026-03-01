-- Migration: Add Recurring Expenses Feature (Feature 013)
-- Created: 2026-01-16
-- Schema Version: From v3 to v4

-- =============================================================================
-- 1. CREATE TABLES
-- =============================================================================

-- Table: recurring_expenses
-- Stores recurring expense templates
CREATE TABLE IF NOT EXISTS recurring_expenses (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  group_id UUID REFERENCES family_groups(id) ON DELETE CASCADE,
  template_expense_id UUID REFERENCES expenses(id) ON DELETE SET NULL,

  -- Expense details
  amount DECIMAL(12, 2) NOT NULL CHECK (amount > 0),
  category_id UUID NOT NULL REFERENCES expense_categories(id) ON DELETE RESTRICT,
  category_name TEXT NOT NULL,
  merchant TEXT CHECK (char_length(merchant) <= 100),
  notes TEXT CHECK (char_length(notes) <= 500),
  is_group_expense BOOLEAN NOT NULL DEFAULT true,

  -- Recurrence configuration
  frequency TEXT NOT NULL CHECK (frequency IN ('daily', 'weekly', 'monthly', 'yearly')),
  anchor_date TIMESTAMP WITH TIME ZONE NOT NULL,
  is_paused BOOLEAN NOT NULL DEFAULT false,
  last_instance_created_at TIMESTAMP WITH TIME ZONE,
  next_due_date TIMESTAMP WITH TIME ZONE,

  -- Budget reservation
  budget_reservation_enabled BOOLEAN NOT NULL DEFAULT false,

  -- Default settings for generated instances
  default_reimbursement_status TEXT NOT NULL DEFAULT 'none' CHECK (default_reimbursement_status IN ('none', 'reimbursable', 'reimbursed')),
  payment_method_id UUID REFERENCES payment_methods(id) ON DELETE SET NULL,
  payment_method_name TEXT,

  -- Timestamps
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW()
);

-- Table: recurring_expense_instances
-- Audit trail mapping generated expenses to their templates
CREATE TABLE IF NOT EXISTS recurring_expense_instances (
  id SERIAL PRIMARY KEY,
  recurring_expense_id UUID NOT NULL REFERENCES recurring_expenses(id) ON DELETE CASCADE,
  expense_id UUID NOT NULL REFERENCES expenses(id) ON DELETE CASCADE,
  scheduled_date TIMESTAMP WITH TIME ZONE NOT NULL,
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),

  -- Ensure one expense can only be linked to one recurring template
  UNIQUE(expense_id)
);

-- =============================================================================
-- 2. CREATE INDEXES
-- =============================================================================

-- User isolation (list user's recurring expenses)
CREATE INDEX IF NOT EXISTS recurring_expenses_user_idx ON recurring_expenses(user_id);

-- Find active templates due for creation
CREATE INDEX IF NOT EXISTS recurring_expenses_active_idx
  ON recurring_expenses(is_paused, next_due_date)
  WHERE is_paused = false;

-- Budget reservation calculations
CREATE INDEX IF NOT EXISTS recurring_expenses_reservation_idx
  ON recurring_expenses(budget_reservation_enabled, user_id)
  WHERE is_paused = false AND budget_reservation_enabled = true;

-- Group isolation
CREATE INDEX IF NOT EXISTS recurring_expenses_group_idx ON recurring_expenses(group_id);

-- Find all instances for a template
CREATE INDEX IF NOT EXISTS recurring_instances_template_idx
  ON recurring_expense_instances(recurring_expense_id);

-- Lookup which template generated an expense
CREATE INDEX IF NOT EXISTS recurring_instances_expense_idx
  ON recurring_expense_instances(expense_id);

-- Find instances by scheduled date
CREATE INDEX IF NOT EXISTS recurring_instances_date_idx
  ON recurring_expense_instances(scheduled_date);

-- =============================================================================
-- 3. ROW LEVEL SECURITY (RLS) POLICIES
-- =============================================================================

-- Enable RLS on recurring_expenses
ALTER TABLE recurring_expenses ENABLE ROW LEVEL SECURITY;

-- Policy: Users can view their own recurring expenses
CREATE POLICY recurring_expenses_select_policy ON recurring_expenses
  FOR SELECT
  USING (
    auth.uid() = user_id
    OR group_id IN (
      SELECT family_group_id FROM family_group_members WHERE user_id = auth.uid()
    )
  );

-- Policy: Users can insert their own recurring expenses
CREATE POLICY recurring_expenses_insert_policy ON recurring_expenses
  FOR INSERT
  WITH CHECK (auth.uid() = user_id);

-- Policy: Users can update their own recurring expenses or group expenses they belong to
CREATE POLICY recurring_expenses_update_policy ON recurring_expenses
  FOR UPDATE
  USING (
    auth.uid() = user_id
    OR (
      is_group_expense = true
      AND group_id IN (
        SELECT family_group_id FROM family_group_members WHERE user_id = auth.uid()
      )
    )
  );

-- Policy: Users can delete their own recurring expenses
CREATE POLICY recurring_expenses_delete_policy ON recurring_expenses
  FOR DELETE
  USING (auth.uid() = user_id);

-- Enable RLS on recurring_expense_instances
ALTER TABLE recurring_expense_instances ENABLE ROW LEVEL SECURITY;

-- Policy: Users can view instances linked to their recurring expenses
CREATE POLICY recurring_instances_select_policy ON recurring_expense_instances
  FOR SELECT
  USING (
    recurring_expense_id IN (
      SELECT id FROM recurring_expenses WHERE user_id = auth.uid()
    )
  );

-- Policy: System can insert instances (no direct user insertion)
CREATE POLICY recurring_instances_insert_policy ON recurring_expense_instances
  FOR INSERT
  WITH CHECK (
    recurring_expense_id IN (
      SELECT id FROM recurring_expenses WHERE user_id = auth.uid()
    )
  );

-- Policy: Users can delete instances for their recurring expenses
CREATE POLICY recurring_instances_delete_policy ON recurring_expense_instances
  FOR DELETE
  USING (
    recurring_expense_id IN (
      SELECT id FROM recurring_expenses WHERE user_id = auth.uid()
    )
  );

-- =============================================================================
-- 4. TRIGGERS
-- =============================================================================

-- Trigger function: Update updated_at timestamp
CREATE OR REPLACE FUNCTION update_recurring_expenses_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Trigger: Auto-update updated_at on recurring_expenses
CREATE TRIGGER recurring_expenses_updated_at_trigger
  BEFORE UPDATE ON recurring_expenses
  FOR EACH ROW
  EXECUTE FUNCTION update_recurring_expenses_updated_at();

-- =============================================================================
-- 5. ADD COLUMNS TO EXISTING TABLES
-- =============================================================================

-- Add recurring expense tracking to expenses table
ALTER TABLE expenses
  ADD COLUMN IF NOT EXISTS recurring_expense_id UUID REFERENCES recurring_expenses(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS is_recurring_instance BOOLEAN DEFAULT false;

-- Create index for recurring expense lookups
CREATE INDEX IF NOT EXISTS expenses_recurring_idx
  ON expenses(recurring_expense_id)
  WHERE recurring_expense_id IS NOT NULL;

-- =============================================================================
-- 6. REALTIME PUBLICATION
-- =============================================================================

-- Enable realtime for recurring_expenses table
ALTER PUBLICATION supabase_realtime ADD TABLE recurring_expenses;
ALTER PUBLICATION supabase_realtime ADD TABLE recurring_expense_instances;

-- =============================================================================
-- MIGRATION COMPLETE
-- =============================================================================
