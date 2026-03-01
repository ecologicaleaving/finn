import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/services/icon_matching_service.dart';
import '../../../../core/utils/currency_utils.dart';
import '../../domain/entities/category_budget_with_members_entity.dart';
import '../providers/budget_composition_provider.dart';
import 'editable_section.dart';

import '../../../../app/app_theme.dart';
/// Expandable tile for a category budget
///
/// Header (collapsed):
/// - Category icon, name
/// - Budget: €X / €Y
/// - Mini progress bar
/// - Expand chevron
///
/// Expanded content:
/// - Group budget editing section
/// - Member contributions list
/// - Expenses preview
///
/// Example:
/// ```dart
/// CategoryBudgetTile(
///   categoryBudget: categoryBudget,
///   params: budgetParams,
/// )
/// ```
class CategoryBudgetTile extends ConsumerStatefulWidget {
  const CategoryBudgetTile({
    super.key,
    required this.categoryBudget,
    required this.params,
    this.initiallyExpanded = false,
  });

  final CategoryBudgetWithMembers categoryBudget;
  final BudgetCompositionParams params;
  final bool initiallyExpanded;

  @override
  ConsumerState<CategoryBudgetTile> createState() => _CategoryBudgetTileState();
}

class _CategoryBudgetTileState extends ConsumerState<CategoryBudgetTile> {
  late bool _isExpanded;

  @override
  void initState() {
    super.initState();
    _isExpanded = widget.initiallyExpanded;
  }

  Color get _categoryColor => Color(widget.categoryBudget.categoryColor);

  Color get _statusColor {
    if (widget.categoryBudget.stats.isOverBudget) {
      return AppColors.error;
    } else if (widget.categoryBudget.stats.isNearLimit) {
      return AppColors.warning;
    } else {
      return AppColors.success;
    }
  }

  @override
  Widget build(BuildContext context) {
    final categoryBudget = widget.categoryBudget;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppColors.cream,
        borderRadius: BorderRadius.circular(4),
        border: Border(
          left: BorderSide(
            color: _categoryColor,
            width: 4,
          ),
        ),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(
          dividerColor: Colors.transparent,
          splashColor: Colors.transparent,
          highlightColor: Colors.transparent,
        ),
        child: ExpansionTile(
          initiallyExpanded: _isExpanded,
          onExpansionChanged: (expanded) {
            setState(() => _isExpanded = expanded);
          },
          tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          // Header
          title: _buildHeader(),
          subtitle: _buildSubtitle(),
          trailing: Icon(
            _isExpanded ? Icons.expand_less : Icons.expand_more,
            color: AppColors.inkLight,
          ),
          // Expanded content
          children: [
            const SizedBox(height: 8),
            _buildExpandedContent(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        // Category icon
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: _categoryColor.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Icon(
            IconMatchingService.getDefaultIconForCategory(
              widget.categoryBudget.categoryName,
            ),
            color: _categoryColor,
            size: 20,
          ),
        ),
        const SizedBox(width: 12),
        // Category name
        Expanded(
          child: Row(
            children: [
              Flexible(
                child: Text(
                  widget.categoryBudget.categoryName,
                  style: GoogleFonts.dmSans(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AppColors.ink,
                  ),
                ),
              ),
              // System category badge for "Varie"/"Altro"
              if (widget.categoryBudget.categoryName.toLowerCase() == 'varie' ||
                  widget.categoryBudget.categoryName.toLowerCase() == 'altro') ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.copper,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'SISTEMA',
                    style: GoogleFonts.dmSans(
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSubtitle() {
    final stats = widget.categoryBudget.stats;
    final budgetAmount = widget.categoryBudget.groupBudgetAmount;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        // Amounts
        Row(
          children: [
            Text(
              CurrencyUtils.formatCentsCompact(stats.spentAmount),
              style: GoogleFonts.jetBrainsMono(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: _statusColor,
              ),
            ),
            Text(
              ' / ',
              style: GoogleFonts.dmSans(
                fontSize: 12,
                color: AppColors.inkFaded,
              ),
            ),
            Text(
              CurrencyUtils.formatCentsCompact(budgetAmount),
              style: GoogleFonts.jetBrainsMono(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppColors.inkLight,
              ),
            ),
            const Spacer(),
            Text(
              '${stats.percentageUsed.toStringAsFixed(0)}%',
              style: GoogleFonts.jetBrainsMono(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: _statusColor,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        // Mini progress bar
        ClipRRect(
          borderRadius: BorderRadius.circular(2),
          child: Stack(
            children: [
              Container(
                height: 6,
                decoration: BoxDecoration(
                  color: AppColors.parchment,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              FractionallySizedBox(
                widthFactor: (stats.percentageUsed / 100).clamp(0.0, 1.0),
                child: Container(
                  height: 6,
                  decoration: BoxDecoration(
                    color: _statusColor,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildExpandedContent() {
    final categoryBudget = widget.categoryBudget;
    final notifier = ref.read(budgetCompositionProvider(widget.params).notifier);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Group budget section
        EditableSection(
          label: 'Budget Gruppo Categoria',
          value: categoryBudget.groupBudgetAmount,
          icon: Icons.account_balance_wallet,
          color: _categoryColor,
          onSave: (amount) async {
            await notifier.setCategoryBudget(
              categoryId: categoryBudget.categoryId,
              amount: amount,
            );
          },
          onDelete: categoryBudget.groupBudgetId != null
              ? () async {
                  await notifier.deleteCategoryBudget(categoryBudget.groupBudgetId!);
                }
              : null,
        ),

        const SizedBox(height: 16),

        // Member contributions section
        if (categoryBudget.memberContributions.isNotEmpty) ...[
          Text(
            'CONTRIBUTI MEMBRI',
            style: GoogleFonts.dmSans(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
              color: AppColors.inkLight,
            ),
          ),
          const SizedBox(height: 8),
          ...categoryBudget.memberContributions.map((contribution) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.parchment.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(
                    color: AppColors.parchmentDark,
                    width: 1,
                  ),
                ),
                child: Row(
                  children: [
                    // Avatar
                    CircleAvatar(
                      radius: 16,
                      backgroundColor: _categoryColor.withValues(alpha: 0.2),
                      child: Text(
                        contribution.userName[0].toUpperCase(),
                        style: GoogleFonts.dmSans(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: _categoryColor,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    // Name
                    Expanded(
                      child: Text(
                        contribution.userName,
                        style: GoogleFonts.dmSans(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppColors.ink,
                        ),
                      ),
                    ),
                    // Amount
                    Text(
                      contribution.displayValue,
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: AppColors.copper,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),
          const SizedBox(height: 8),
        ],

        // Allocation info
        if (categoryBudget.memberContributions.isNotEmpty) ...[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: categoryBudget.isOverAllocated
                  ? AppColors.warning.withValues(alpha: 0.1)
                  : AppColors.success.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(
                color: categoryBudget.isOverAllocated
                    ? AppColors.warning
                    : AppColors.success,
                width: 1,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  categoryBudget.isOverAllocated
                      ? Icons.warning_amber
                      : Icons.check_circle,
                  size: 16,
                  color: categoryBudget.isOverAllocated
                      ? AppColors.warning
                      : AppColors.success,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    categoryBudget.isOverAllocated
                        ? 'Over-allocated: ${CurrencyUtils.formatCentsCompact(categoryBudget.totalMemberContributions)} > ${CurrencyUtils.formatCentsCompact(categoryBudget.groupBudgetAmount)}'
                        : 'Allocato: ${categoryBudget.allocationPercentage.toStringAsFixed(1)}%',
                    style: GoogleFonts.dmSans(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: categoryBudget.isOverAllocated
                          ? AppColors.warning
                          : AppColors.success,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],

        // Spending stats
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.parchment.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _StatChip(
                label: 'Speso',
                value: CurrencyUtils.formatCentsCompact(categoryBudget.stats.spentAmount),
                color: _statusColor,
              ),
              _StatChip(
                label: 'Rimanente',
                value: CurrencyUtils.formatCentsCompact(categoryBudget.stats.remainingAmount),
                color: AppColors.inkLight,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Small stat chip for displaying key metrics
class _StatChip extends StatelessWidget {
  const _StatChip({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.dmSans(
            fontSize: 10,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.8,
            color: AppColors.inkLight,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: GoogleFonts.jetBrainsMono(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
      ],
    );
  }
}
