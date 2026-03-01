-- Add RLS policy to allow admins to update group expenses
-- Migration: 20260124_add_admin_update_policy.sql
--
-- Purpose: Allow group admins to update any group expense in their group
-- This enables admins to edit expenses they created on behalf of other members

-- Add policy for admins to update group expenses
CREATE POLICY "Admins can update group expenses"
    ON public.expenses FOR UPDATE
    USING (
        is_group_expense = true AND
        group_id = public.get_my_group_id() AND
        EXISTS (
            SELECT 1 FROM public.profiles
            WHERE id = auth.uid()
            AND group_id = public.get_my_group_id()
            AND is_group_admin = true
        )
    )
    WITH CHECK (
        is_group_expense = true AND
        group_id = public.get_my_group_id() AND
        EXISTS (
            SELECT 1 FROM public.profiles
            WHERE id = auth.uid()
            AND group_id = public.get_my_group_id()
            AND is_group_admin = true
        )
    );
