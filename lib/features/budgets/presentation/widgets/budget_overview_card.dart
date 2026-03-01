import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/utils/currency_utils.dart';
import '../../domain/entities/budget_composition_entity.dart';

import '../../../../app/app_theme.dart';
/// Overview card showing budget totals and progress
///
/// Displays:
/// - Total budgeted vs total spent
/// - Overall progress bar
/// - Quick stats (categories, alerts)
/// - Personal vs Group budget breakdown
/// - Budget reservation for recurring expenses (Feature 013 T035-T036)
/// - Available budget after reservations
///
/// Example:
/// ```dart
/// BudgetOverviewCard(
///   composition: budgetComposition,
///   currentUserId: userId,
///   reservedBudget: 50000, // Optional: cents reserved for recurring expenses
/// )
/// ```
class BudgetOverviewCard extends StatelessWidget {
  const BudgetOverviewCard({
    super.key,
    required this.composition,
    required this.currentUserId,
    required this.totalIncome,
    this.reservedBudget = 0, // Feature 013 T035: Reserved budget in cents
    this.onTap,
    this.onPersonalTap,
    this.onGroupTap,
  });

  final BudgetComposition composition;
  final String currentUserId;
  final int totalIncome;
  final int reservedBudget; // Feature 013 T035
  final VoidCallback? onTap;
  final VoidCallback? onPersonalTap;
  final VoidCallback? onGroupTap;

  /// Calculate personal budget for current user
  /// Returns total income (user's available money)
  int _calculatePersonalBudget() {
    return totalIncome;
  }

  @override
  Widget build(BuildContext context) {
    final stats = composition.stats;
    final hasGroupBudget = composition.hasGroupBudget;

    // Calculate personal and group budgets
    final personalBudget = _calculatePersonalBudget();
    final groupBudget = stats.totalCategoryBudgets - personalBudget;

    // Calculate progress
    final progressPercentage = stats.overallPercentageUsed.clamp(0.0, 100.0);
    final isOverBudget = stats.isOverBudget;
    final isNearLimit = stats.isNearLimit && !isOverBudget;

    // Determine colors based on status
    Color progressColor;
    if (isOverBudget) {
      progressColor = AppColors.error;
    } else if (isNearLimit) {
      progressColor = AppColors.warning;
    } else {
      progressColor = AppColors.success;
    }

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppColors.cream,
          borderRadius: BorderRadius.circular(4),
          border: Border(
            left: BorderSide(
              color: AppColors.terracotta,
              width: 4,
            ),
          ),
          boxShadow: [
            BoxShadow(
              color: AppColors.ink.withValues(alpha: 0.05),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Icon(
                  Icons.account_balance_wallet,
                  color: AppColors.terracotta,
                  size: 28,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Budget Totale',
                        style: GoogleFonts.dmSans(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 1.0,
                          color: AppColors.inkLight,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${composition.month}/${composition.year}',
                        style: GoogleFonts.dmSans(
                          fontSize: 12,
                          color: AppColors.inkFaded,
                        ),
                      ),
                    ],
                  ),
                ),
                if (onTap != null)
                  Icon(
                    Icons.arrow_forward_ios,
                    size: 16,
                    color: AppColors.inkLight,
                  ),
              ],
            ),

            const SizedBox(height: 20),

            // Personal and Group Budget breakdown
            if (stats.hasBudgets) ...[
              // Group Budget Box
              InkWell(
                onTap: onGroupTap,
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.green.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.green.withOpacity(0.3)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.group, color: Colors.green, size: 20),
                      const SizedBox(width: 12),
                      Text(
                        'GRUPPO',
                        style: GoogleFonts.dmSans(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: Colors.green,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        CurrencyUtils.formatCentsCompact(groupBudget),
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: Colors.green,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Icon(Icons.arrow_forward_ios, size: 14, color: Colors.green),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 8),

              // Personal Budget Box
              InkWell(
                onTap: onPersonalTap,
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.blue.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.blue.withOpacity(0.3)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.person, color: Colors.blue, size: 20),
                      const SizedBox(width: 12),
                      Text(
                        'PERSONALE',
                        style: GoogleFonts.dmSans(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: Colors.blue,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        CurrencyUtils.formatCentsCompact(personalBudget),
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: Colors.blue,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Icon(Icons.arrow_forward_ios, size: 14, color: Colors.blue),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 16),
              const Divider(height: 1, color: AppColors.parchmentDark),
              const SizedBox(height: 16),
            ],

            // Amounts
            if (hasGroupBudget) ...[
              // Group budget amount
              Row(
                children: [
                  Text(
                    'Budget Gruppo:',
                    style: GoogleFonts.dmSans(
                      fontSize: 12,
                      color: AppColors.inkLight,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    CurrencyUtils.formatCentsCompact(composition.groupBudgetAmount),
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.ink,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
            ],

            // Total budgeted (sum of category budgets)
            Row(
              children: [
                Text(
                  'Budget Categorie:',
                  style: GoogleFonts.dmSans(
                    fontSize: 12,
                    color: AppColors.inkLight,
                  ),
                ),
                const Spacer(),
                Text(
                  CurrencyUtils.formatCentsCompact(stats.totalCategoryBudgets),
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AppColors.terracotta,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 8),

            // Total spent
            Row(
              children: [
                Text(
                  'Speso:',
                  style: GoogleFonts.dmSans(
                    fontSize: 12,
                    color: AppColors.inkLight,
                  ),
                ),
                const Spacer(),
                Text(
                  CurrencyUtils.formatCentsCompact(stats.totalSpent),
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: progressColor,
                  ),
                ),
              ],
            ),

            // Feature 013 T035: Reserved budget for recurring expenses
            if (reservedBudget > 0) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(
                    Icons.loop,
                    size: 14,
                    color: AppColors.inkLight,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'Riservato (ricorrenti):',
                    style: GoogleFonts.dmSans(
                      fontSize: 12,
                      color: AppColors.inkLight,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    CurrencyUtils.formatCentsCompact(reservedBudget),
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.warning,
                    ),
                  ),
                ],
              ),
            ],

            const SizedBox(height: 8),

            // Feature 013 T036: Available budget (total - spent - reserved)
            if (stats.hasBudgets) ...[
              Container(
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                decoration: BoxDecoration(
                  color: AppColors.parchment,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Row(
                  children: [
                    Text(
                      'Disponibile:',
                      style: GoogleFonts.dmSans(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: AppColors.ink,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      CurrencyUtils.formatCentsCompact(
                        stats.totalRemaining - reservedBudget,
                      ),
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: (stats.totalRemaining - reservedBudget) >= 0
                            ? AppColors.success
                            : AppColors.error,
                      ),
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 16),

            // Progress bar
            if (stats.hasBudgets) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: Stack(
                  children: [
                    // Background
                    Container(
                      height: 12,
                      decoration: BoxDecoration(
                        color: AppColors.parchment,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    // Progress
                    FractionallySizedBox(
                      widthFactor: (progressPercentage / 100).clamp(0.0, 1.0),
                      child: Container(
                        height: 12,
                        decoration: BoxDecoration(
                          color: progressColor,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),

              // Percentage text
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '${stats.overallPercentageUsed.toStringAsFixed(1)}% utilizzato',
                    style: GoogleFonts.dmSans(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: progressColor,
                    ),
                  ),
                  Text(
                    CurrencyUtils.formatCentsCompact(stats.totalRemaining),
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: AppColors.inkLight,
                    ),
                  ),
                ],
              ),
            ],

            // Quick stats
            if (stats.hasBudgets) ...[
              const SizedBox(height: 16),
              const Divider(height: 1, color: AppColors.parchmentDark),
              const SizedBox(height: 12),

              Row(
                children: [
                  _QuickStat(
                    label: 'Categorie',
                    value: '${stats.categoriesWithBudgets}',
                    icon: Icons.category,
                  ),
                  const SizedBox(width: 24),
                  if (stats.hasAlerts)
                    _QuickStat(
                      label: 'Allerte',
                      value: '${stats.alertCategoriesCount}',
                      icon: Icons.warning_amber,
                      color: AppColors.warning,
                    ),
                ],
              ),
            ],

            // Empty state
            if (!stats.hasBudgets)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  'Nessun budget impostato',
                  style: GoogleFonts.dmSans(
                    fontSize: 13,
                    color: AppColors.inkFaded,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Quick stat display (icon + label + value)
class _QuickStat extends StatelessWidget {
  const _QuickStat({
    required this.label,
    required this.value,
    required this.icon,
    this.color,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final statColor = color ?? AppColors.copper;

    return Row(
      children: [
        Icon(
          icon,
          size: 16,
          color: statColor,
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: GoogleFonts.dmSans(
            fontSize: 11,
            color: AppColors.inkLight,
          ),
        ),
        const SizedBox(width: 4),
        Text(
          value,
          style: GoogleFonts.jetBrainsMono(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: statColor,
          ),
        ),
      ],
    );
  }
}
