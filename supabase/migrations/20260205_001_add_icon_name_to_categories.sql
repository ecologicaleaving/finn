-- Migration: Add icon_name column to expense_categories table
-- Feature: 014-category-icons
-- Date: 2026-02-05
-- Purpose: Add nullable icon_name column for custom category icons

-- Add icon_name column (nullable for safe migration)
ALTER TABLE public.expense_categories
  ADD COLUMN IF NOT EXISTS icon_name VARCHAR(100) NULL;

-- Add index for faster icon lookups
CREATE INDEX IF NOT EXISTS idx_expense_categories_icon_name
  ON public.expense_categories(icon_name)
  WHERE icon_name IS NOT NULL;

-- Add column comment
COMMENT ON COLUMN public.expense_categories.icon_name IS
  'Material Icons name for category display. Falls back to name-based matching if NULL.';
