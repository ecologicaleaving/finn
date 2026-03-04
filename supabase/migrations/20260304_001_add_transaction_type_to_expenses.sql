-- Add transaction_type column to expenses table
-- Supports 'expense' (default) and 'income' types
ALTER TABLE expenses ADD COLUMN IF NOT EXISTS transaction_type VARCHAR(20) NOT NULL DEFAULT 'expense';

-- Add check constraint for valid values
ALTER TABLE expenses ADD CONSTRAINT chk_transaction_type
  CHECK (transaction_type IN ('expense', 'income'));

-- Index for filtering by transaction type
CREATE INDEX IF NOT EXISTS idx_expenses_transaction_type ON expenses(transaction_type);
