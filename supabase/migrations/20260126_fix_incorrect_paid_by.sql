-- Migration: Fix incorrect paid_by for expenses created by admin for other members
-- Date: 2026-01-26
-- Purpose: Update expenses that were created before the paid_by fix
--
-- This migration will help identify and fix expenses where:
-- - Amount is 600 (the test expenses)
-- - paid_by should be updated to the correct member ID

-- IMPORTANT: Before running this migration, you need to:
-- 1. Find Giovanna's user ID from the profiles table
-- 2. Update the WHERE clause to match the correct admin user ID
-- 3. Uncomment and run the UPDATE statement

-- Step 1: View expenses that need to be fixed (600 euro expenses)
-- Run this query first to see what needs to be fixed:
SELECT
    id,
    amount,
    created_by,
    paid_by,
    is_group_expense,
    created_by_name,
    paid_by_name,
    date
FROM public.expenses
WHERE amount = 600
ORDER BY created_at DESC;

-- Step 2: Get all user IDs and names from profiles to identify the correct member
SELECT
    id as user_id,
    display_name,
    email
FROM public.profiles
ORDER BY display_name;

-- Step 3: Once you have identified Giovanna's user ID, uncomment and run this:
-- (Replace 'giovanna-user-id-here' with the actual UUID)

/*
UPDATE public.expenses
SET
    paid_by = 'giovanna-user-id-here',
    paid_by_name = 'Giovanna'  -- Update with correct display name
WHERE
    amount = 600
    AND paid_by != 'giovanna-user-id-here'  -- Only update if not already correct
    AND created_at > '2026-01-26'  -- Only update recent test expenses
    AND is_group_expense = true;

-- Verify the update
SELECT
    id,
    amount,
    created_by,
    paid_by,
    created_by_name,
    paid_by_name,
    is_group_expense
FROM public.expenses
WHERE amount = 600
ORDER BY created_at DESC;
*/
