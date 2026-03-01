-- Migration: 065_enhance_user_category_usage_for_mru
-- Purpose: Add MRU (Most Recently Used) tracking to user_category_usage table
-- Feature: 001-widget-category-fixes (User Story 3)
-- Created: 2026-01-18

-- Add columns for MRU tracking
ALTER TABLE user_category_usage
ADD COLUMN IF NOT EXISTS last_used_at TIMESTAMPTZ,
ADD COLUMN IF NOT EXISTS use_count INTEGER DEFAULT 0;

-- Create composite index for efficient MRU queries
-- NULLS LAST ensures virgin categories (never used) appear at end
CREATE INDEX IF NOT EXISTS idx_user_category_usage_mru
ON user_category_usage (user_id, last_used_at DESC NULLS LAST);

-- Update existing records with baseline data
-- Set last_used_at to first_used_at for existing records, use_count to 1
UPDATE user_category_usage
SET
    last_used_at = first_used_at,
    use_count = 1
WHERE last_used_at IS NULL;

-- Create or replace upsert function for atomic usage tracking
-- This function is called whenever an expense is saved with a category
CREATE OR REPLACE FUNCTION upsert_category_usage(
  p_user_id UUID,
  p_category_id UUID,
  p_last_used_at TIMESTAMPTZ
) RETURNS VOID AS $$
BEGIN
  -- Insert new record or update existing one
  INSERT INTO user_category_usage (
    id,
    user_id,
    category_id,
    first_used_at,
    last_used_at,
    use_count
  )
  VALUES (
    gen_random_uuid(),
    p_user_id,
    p_category_id,
    p_last_used_at,
    p_last_used_at,
    1
  )
  ON CONFLICT (user_id, category_id)
  DO UPDATE SET
    last_used_at = p_last_used_at,
    use_count = user_category_usage.use_count + 1;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Grant execute permission to authenticated users
GRANT EXECUTE ON FUNCTION upsert_category_usage TO authenticated;

-- Add comment for documentation
COMMENT ON FUNCTION upsert_category_usage IS 'Atomically updates category usage tracking when an expense is saved. Increments use_count and updates last_used_at timestamp for MRU ordering.';
