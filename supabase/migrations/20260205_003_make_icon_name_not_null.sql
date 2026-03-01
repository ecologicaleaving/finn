-- Migration: Make icon_name NOT NULL (OPTIONAL - deploy only after verification)
-- Feature: 014-category-icons
-- Date: 2026-02-05
-- Purpose: Enforce icon_name presence for all categories
-- WARNING: Only run this after verifying Phase 1 and Phase 2 migrations are successful

-- Set default value for future inserts
ALTER TABLE public.expense_categories
  ALTER COLUMN icon_name SET DEFAULT 'category';

-- Make column NOT NULL
ALTER TABLE public.expense_categories
  ALTER COLUMN icon_name SET NOT NULL;
