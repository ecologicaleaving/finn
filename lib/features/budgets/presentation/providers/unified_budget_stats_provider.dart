// Riverpod Provider: Unified Budget Stats Provider
// Aggregates group, personal, and category budgets for unified dashboard view

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/utils/budget_calculator.dart';
import '../../../../core/utils/currency_utils.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../categories/presentation/providers/category_provider.dart';
import '../../../groups/presentation/providers/group_provider.dart';
import '../../domain/entities/unified_budget_stats_entity.dart';
import 'budget_provider.dart';
import 'category_budget_provider.dart';

/// Provider parameters for unified budget stats
class UnifiedBudgetStatsParams {
  final String groupId;
  final String userId;
  final int year;
  final int month;

  const UnifiedBudgetStatsParams({
    required this.groupId,
    required this.userId,
    required this.year,
    required this.month,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is UnifiedBudgetStatsParams &&
          runtimeType == other.runtimeType &&
          groupId == other.groupId &&
          userId == other.userId &&
          year == other.year &&
          month == other.month;

  @override
  int get hashCode => groupId.hashCode ^ userId.hashCode ^ year.hashCode ^ month.hashCode;
}

/// Provider for unified budget statistics
/// Aggregates group, personal, and category budgets into a single unified view
final unifiedBudgetStatsProvider = FutureProvider.family<
    UnifiedBudgetStatsEntity, UnifiedBudgetStatsParams>(
  (ref, params) async {
    try {
      // Read budget provider for group/personal totals
      final budgetState = ref.read(
        budgetProvider((groupId: params.groupId, userId: params.userId)),
      );

      // Read category budgets
      final categoryBudgetState = ref.read(
        categoryBudgetProvider((
          groupId: params.groupId,
          year: params.year,
          month: params.month,
        )),
      );

      // Read categories for names and colors
      final categoryState = ref.read(
        categoryProvider(params.groupId),
      );

      // Get Supabase client for expense queries
      final supabase = Supabase.instance.client;

      // Calculate aggregated stats
      int totalBudgeted = 0;
      int totalSpent = 0;
      final List<CategoryBudgetWithStats> allCategoriesWithStats = [];
      final List<CategoryBudgetWithStats> alertCategories = [];

      // Process category budgets
      for (final budgetData in categoryBudgetState.budgets) {
        final categoryId = budgetData['category_id'] as String;
        final isGroupBudget = budgetData['is_group_budget'] as bool? ?? true;
        final budgetAmount = budgetData['amount'] as int;
        final budgetType = budgetData['budget_type'] as String?;
        final percentageOfGroup = budgetData['percentage_of_group'] as num?;
        final budgetId = budgetData['id'] as String;

        // Find category info
        final category = categoryState.categories.firstWhere(
          (c) => c.id == categoryId,
          orElse: () => throw Exception('Category not found: $categoryId'),
        );

        // Query expenses for this category
        final startOfMonth = DateTime(params.year, params.month, 1);
        final endOfMonth = DateTime(params.year, params.month + 1, 0, 23, 59, 59);

        var query = supabase
            .from('expenses')
            .select()
            .eq('group_id', params.groupId)
            .eq('category_id', categoryId)
            .neq('transaction_type', 'income')
            .gte('date', startOfMonth.toIso8601String().split('T')[0])
            .lte('date', endOfMonth.toIso8601String().split('T')[0]);

        // Filter by budget type
        if (isGroupBudget) {
          query = query.eq('is_group_expense', true);
        } else {
          query = query.eq('is_group_expense', false).eq('created_by', params.userId);
        }

        final expenseData = await query as List<dynamic>;

        // Calculate spent amount in cents
        // Database stores amounts as DECIMAL in euros, but budgets are in cents
        // Convert euros to cents to match budget unit
        int spentAmountCents = 0;
        debugPrint('🔍 DEBUG Category ${category.name}: Found ${expenseData.length} expenses');
        for (final expense in expenseData) {
          final rawAmount = expense['amount'];
          debugPrint('🔍 DEBUG  - Expense raw amount: $rawAmount (type: ${rawAmount.runtimeType})');
          final amountEur = (expense['amount'] as num).toDouble();
          debugPrint('🔍 DEBUG  - Converted to euros: $amountEur');
          final amountCents = (amountEur * 100).round();
          debugPrint('🔍 DEBUG  - Converted to cents: $amountCents');
          spentAmountCents += amountCents;
        }

        int spentAmount = spentAmountCents;

        // DEBUG: Print values for debugging
        debugPrint('🔍 DEBUG Category ${category.name}: budgetAmount=$budgetAmount cents, spentAmount=$spentAmount cents (from ${expenseData.length} expenses)');

        // Calculate percentage (both amounts are in cents)
        final percentageUsed = budgetAmount > 0
            ? CurrencyUtils.calculatePercentageUsed(budgetAmount, spentAmount)
            : 0.0;

        final isOverBudget = BudgetCalculator.isOverBudget(budgetAmount, spentAmount);
        final isNearLimit = BudgetCalculator.isNearLimit(budgetAmount, spentAmount);

        // Generate a color for the category (categories don't have color field)
        // Use a hash of the category ID to generate a consistent color
        final colorHash = categoryId.hashCode;
        final categoryColor = 0xFF000000 + (colorHash.abs() % 0xFFFFFF);

        // Create category stat
        final categoryWithStats = CategoryBudgetWithStats(
          categoryId: categoryId,
          categoryName: category.name,
          categoryColor: categoryColor,
          isGroupBudget: isGroupBudget,
          budgetAmount: budgetAmount,
          spentAmount: spentAmount,
          percentageUsed: percentageUsed,
          isOverBudget: isOverBudget,
          isNearLimit: isNearLimit,
          percentageOfGroupBudget: percentageOfGroup?.toDouble(),
          budgetId: budgetId,
        );

        allCategoriesWithStats.add(categoryWithStats);

        // Add to alerts if near limit or over budget
        if (isNearLimit || isOverBudget) {
          alertCategories.add(categoryWithStats);
        }

        // Add to totals
        totalBudgeted += budgetAmount;
        totalSpent += spentAmount;
      }

      // Sort alerts by severity (over budget first, then by percentage)
      alertCategories.sort((a, b) {
        if (a.isOverBudget && !b.isOverBudget) return -1;
        if (!a.isOverBudget && b.isOverBudget) return 1;
        return b.percentageUsed.compareTo(a.percentageUsed);
      });

      // Get top spending categories (top 5 by spent amount)
      final topSpending = List<CategoryBudgetWithStats>.from(allCategoriesWithStats);
      topSpending.sort((a, b) => b.spentAmount.compareTo(a.spentAmount));
      final topSpendingCategories = topSpending.take(5).toList();

      // Sort all categories: alerts first, then by name
      allCategoriesWithStats.sort((a, b) {
        // Alerts first
        final aIsAlert = a.isNearLimit || a.isOverBudget;
        final bIsAlert = b.isNearLimit || b.isOverBudget;
        if (aIsAlert && !bIsAlert) return -1;
        if (!aIsAlert && bIsAlert) return 1;

        // Then by over budget
        if (a.isOverBudget && !b.isOverBudget) return -1;
        if (!a.isOverBudget && b.isOverBudget) return 1;

        // Then by percentage
        if (aIsAlert && bIsAlert) {
          return b.percentageUsed.compareTo(a.percentageUsed);
        }

        // Finally by name
        return a.categoryName.compareTo(b.categoryName);
      });

      // Calculate overall percentage (both amounts are in cents)
      final overallPercentageUsed = totalBudgeted > 0
          ? CurrencyUtils.calculatePercentageUsed(totalBudgeted, totalSpent)
          : 0.0;

      // Get group and personal budgets from computed totals
      final groupBudget = budgetState.computedTotals.totalGroupBudget;
      final personalBudget = budgetState.computedTotals.totalPersonalBudget;

      // Create unified entity
      return UnifiedBudgetStatsEntity(
        totalBudgeted: totalBudgeted,
        totalSpent: totalSpent,
        totalRemaining: totalBudgeted - totalSpent,
        overallPercentageUsed: overallPercentageUsed,
        groupBudget: groupBudget,
        groupSpent: budgetState.groupStats.spentAmount,
        personalBudget: personalBudget,
        personalSpent: budgetState.personalStats.spentAmount,
        alertCategoriesCount: alertCategories.length,
        alertCategories: alertCategories,
        topSpendingCategories: topSpendingCategories,
        allCategories: allCategoriesWithStats,
        activeCategoriesCount: allCategoriesWithStats.length,
        month: params.month,
        year: params.year,
      );
    } catch (e) {
      // Return empty stats on error
      return UnifiedBudgetStatsEntity.empty(
        month: params.month,
        year: params.year,
      );
    }
  },
);

/// Convenience provider for current month's unified stats
final currentMonthUnifiedStatsProvider = FutureProvider<UnifiedBudgetStatsEntity>(
  (ref) async {
    final groupId = ref.watch(currentGroupIdProvider);
    final userId = ref.watch(currentUserIdProvider);
    final now = DateTime.now();

    final params = UnifiedBudgetStatsParams(
      groupId: groupId,
      userId: userId,
      year: now.year,
      month: now.month,
    );

    return ref.watch(unifiedBudgetStatsProvider(params).future);
  },
);
