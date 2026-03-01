import 'package:supabase_flutter/supabase_flutter.dart';

/// Script to fix paid_by field for expenses created by admin for other members
///
/// This script will:
/// 1. Show all 600 euro expenses
/// 2. Show all users in the group
/// 3. Allow you to update paid_by for specific expenses
///
/// Usage: dart run scripts/fix_paid_by_expenses.dart

Future<void> main() async {
  // Initialize Supabase
  await Supabase.initialize(
    url: 'YOUR_SUPABASE_URL', // Replace with your Supabase URL
    anonKey: 'YOUR_SUPABASE_ANON_KEY', // Replace with your Supabase anon key
  );

  final supabase = Supabase.instance.client;

  print('🔍 Fetching all 600 euro expenses...\n');

  // Get all 600 euro expenses
  final expenses = await supabase
      .from('expenses')
      .select('id, amount, created_by, paid_by, created_by_name, paid_by_name, is_group_expense, date')
      .eq('amount', 600)
      .order('created_at', ascending: false);

  if (expenses.isEmpty) {
    print('❌ No 600 euro expenses found.');
    return;
  }

  print('Found ${expenses.length} expense(s) with amount 600 euro:\n');
  for (var i = 0; i < expenses.length; i++) {
    final expense = expenses[i];
    print('[$i] Expense ID: ${expense['id']}');
    print('    Amount: ${expense['amount']} euro');
    print('    Created by: ${expense['created_by_name']} (${expense['created_by']})');
    print('    Paid by: ${expense['paid_by_name']} (${expense['paid_by']})');
    print('    Group expense: ${expense['is_group_expense']}');
    print('    Date: ${expense['date']}');
    print('');
  }

  print('\n🔍 Fetching all users in your group...\n');

  // Get current user's group
  final currentUser = supabase.auth.currentUser;
  if (currentUser == null) {
    print('❌ No user logged in. Please log in first.');
    return;
  }

  final profile = await supabase
      .from('profiles')
      .select('group_id')
      .eq('id', currentUser.id)
      .single();

  final groupId = profile['group_id'] as String?;
  if (groupId == null) {
    print('❌ You are not part of any group.');
    return;
  }

  // Get all users in the group
  final users = await supabase
      .from('profiles')
      .select('id, display_name, email')
      .eq('group_id', groupId)
      .order('display_name');

  print('Users in your group:\n');
  for (var i = 0; i < users.length; i++) {
    final user = users[i];
    print('[$i] ${user['display_name']} (${user['email']})');
    print('    User ID: ${user['id']}');
    print('');
  }

  print('\n📝 To fix an expense, update it manually in Supabase Dashboard or use the SQL migration.\n');
  print('Example SQL to update expense paid_by:');
  print('');
  print('UPDATE public.expenses');
  print('SET paid_by = \'GIOVANNA_USER_ID_HERE\',');
  print('    paid_by_name = \'Giovanna\'');
  print('WHERE id = \'EXPENSE_ID_HERE\';');
  print('');
  print('Replace GIOVANNA_USER_ID_HERE with the user ID from the list above.');
  print('Replace EXPENSE_ID_HERE with the expense ID from the list above.');
}
