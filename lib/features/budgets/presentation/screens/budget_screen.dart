import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:go_router/go_router.dart';

import '../../../../app/routes.dart';
import '../../../../core/utils/currency_utils.dart';
import '../../../../shared/widgets/error_display.dart';
import '../../../../shared/widgets/loading_indicator.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../groups/presentation/providers/group_provider.dart';
import '../providers/budget_composition_provider.dart';
import '../providers/budget_repository_provider.dart';
import '../providers/budget_reservation_provider.dart';
import '../providers/income_sources_provider.dart';
import '../widgets/budget_overview_card.dart';
import '../widgets/category_budget_tile.dart';
import '../widgets/editable_section.dart';
import '../widgets/validation_alert_banner.dart';
import 'group_budget_detail_screen.dart';
import 'personal_budget_detail_screen.dart';
import '../../../../app/app_theme.dart';
import '../../../expenses/presentation/providers/recurring_expense_provider.dart';
import '../../../expenses/presentation/widgets/budget_reservation_display.dart';
/// Unified budget management screen
///
/// Replaces the previous 3 separate screens:
/// - budget_settings_screen.dart
/// - budget_dashboard_screen.dart
/// - budget_management_screen.dart
///
/// Features:
/// - Group budget editing
/// - Category budgets with member contributions
/// - Drill-down expandable categories
/// - Validation alerts
/// - Real-time sync
class BudgetScreen extends ConsumerStatefulWidget {
  const BudgetScreen({super.key});

  @override
  ConsumerState<BudgetScreen> createState() => _BudgetScreenState();
}

class _BudgetScreenState extends ConsumerState<BudgetScreen> {
  int _selectedMonth = DateTime.now().month;
  int _selectedYear = DateTime.now().year;
  bool _categoriesExpanded = false;

  @override
  void initState() {
    super.initState();
    // Force sync income sources on screen load
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final userId = ref.read(currentUserIdProvider);
      if (userId.isNotEmpty) {
        print('🔄 [BudgetScreen] Forcing income sync for userId: $userId');
        ref.read(budgetRepositoryProvider).getIncomeSources(userId).then((result) {
          result.fold(
            (failure) => print('❌ [BudgetScreen] Income sync failed: $failure'),
            (sources) {
              print('✅ [BudgetScreen] Synced ${sources.length} income sources');
              // Refresh the budget composition after sync
              final params = BudgetCompositionParams(
                groupId: ref.read(currentGroupIdProvider),
                year: _selectedYear,
                month: _selectedMonth,
              );
              ref.read(budgetCompositionProvider(params).notifier).refresh();
            },
          );
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final groupId = ref.watch(currentGroupIdProvider);
    final userId = ref.watch(currentUserIdProvider);

    final params = BudgetCompositionParams(
      groupId: groupId,
      year: _selectedYear,
      month: _selectedMonth,
    );

    final compositionAsync = ref.watch(budgetCompositionProvider(params));
    final incomeSourcesAsync = ref.watch(incomeSourcesProvider);

    // Calculate total income
    final totalIncome = incomeSourcesAsync.when(
      data: (sources) => sources.fold<int>(0, (sum, source) => sum + source.amount),
      loading: () => 0,
      error: (_, __) => 0,
    );

    // Feature 013 T038: Get reserved budget for recurring expenses
    final reservedBudget = ref.watch(currentMonthReservedBudgetProvider);

    // Get recurring expenses for budget reservation display
    final recurringExpensesState = ref.watch(recurringExpenseListProvider);
    final recurringExpenses = recurringExpensesState.templates;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _getMonthYearTitle(),
          style: GoogleFonts.playfairDisplay(
            fontWeight: FontWeight.w700,
          ),
        ),
        backgroundColor: AppColors.terracotta,
        foregroundColor: AppColors.cream,
        actions: [
          // Month selector
          IconButton(
            icon: const Icon(Icons.calendar_month),
            onPressed: () => _showMonthPicker(context),
            tooltip: 'Seleziona mese',
          ),
          // Refresh
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              ref.read(budgetCompositionProvider(params).notifier).refresh();
            },
            tooltip: 'Aggiorna',
          ),
          // Income Management
          IconButton(
            icon: const Icon(Icons.account_balance_wallet),
            onPressed: () {
              context.push(AppRoutes.incomeManagement);
            },
            tooltip: 'Gestisci Entrate',
          ),
        ],
      ),
      backgroundColor: AppColors.parchment,
      body: compositionAsync.when(
        loading: () => const LoadingIndicator(message: 'Caricamento budget...'),
        error: (error, stack) {
          debugPrint('Budget composition error: $error');
          debugPrint('Stack trace: $stack');
          return ErrorDisplay(
            icon: Icons.error_outline,
            title: 'Errore caricamento budget',
            message: error.toString(),
            onRetry: () {
              ref.read(budgetCompositionProvider(params).notifier).refresh();
            },
          );
        },
        data: (composition) => RefreshIndicator(
          onRefresh: () async {
            await ref.read(budgetCompositionProvider(params).notifier).refresh();
          },
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // Validation alerts
              if (composition.hasIssues)
                ValidationAlertBanner(issues: composition.issues),

              // Overview card
              BudgetOverviewCard(
                composition: composition,
                currentUserId: userId,
                totalIncome: totalIncome,
                reservedBudget: reservedBudget, // Feature 013 T038
                onPersonalTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => PersonalBudgetDetailScreen(
                        composition: composition,
                        currentUserId: userId,
                      ),
                    ),
                  );
                },
                onGroupTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => GroupBudgetDetailScreen(
                        composition: composition,
                        currentUserId: userId,
                      ),
                    ),
                  );
                },
              ),

              const SizedBox(height: 16),

              // Feature 013 T038: Budget reservation breakdown
              if (reservedBudget > 0)
                BudgetReservationDisplay(
                  recurringExpenses: recurringExpenses,
                  month: _selectedMonth,
                  year: _selectedYear,
                ),

              if (reservedBudget > 0) const SizedBox(height: 16),

              // Expandable categories section
              Card(
                color: AppColors.cream,
                child: Column(
                  children: [
                    InkWell(
                      onTap: () {
                        setState(() {
                          _categoriesExpanded = !_categoriesExpanded;
                        });
                      },
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                'Categorie',
                                style: GoogleFonts.playfairDisplay(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.ink,
                                ),
                              ),
                            ),
                            Icon(
                              _categoriesExpanded
                                ? Icons.expand_less
                                : Icons.expand_more,
                              color: AppColors.ink,
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (_categoriesExpanded)
                      ...composition.categoryBudgets.map((category) {
                        return CategoryBudgetTile(
                          key: ValueKey(category.categoryId),
                          categoryBudget: category,
                          params: params,
                          initiallyExpanded: false,
                        );
                      }).toList(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          context.push(AppRoutes.incomeManagement);
        },
        icon: const Icon(Icons.account_balance_wallet),
        label: const Text('Gestisci Entrate'),
        backgroundColor: AppColors.terracotta,
        foregroundColor: AppColors.cream,
      ),
    );
  }

  String _getMonthYearTitle() {
    const monthNames = [
      'Gennaio',
      'Febbraio',
      'Marzo',
      'Aprile',
      'Maggio',
      'Giugno',
      'Luglio',
      'Agosto',
      'Settembre',
      'Ottobre',
      'Novembre',
      'Dicembre',
    ];
    return 'Budget ${monthNames[_selectedMonth - 1]} $_selectedYear';
  }

  Future<void> _showMonthPicker(BuildContext context) async {
    final now = DateTime.now();
    final result = await showDialog<Map<String, int>>(
      context: context,
      builder: (context) => _MonthPickerDialog(
        initialMonth: _selectedMonth,
        initialYear: _selectedYear,
        currentMonth: now.month,
        currentYear: now.year,
      ),
    );

    if (result != null && mounted) {
      setState(() {
        _selectedMonth = result['month']!;
        _selectedYear = result['year']!;
      });
    }
  }
}

/// Month picker dialog
class _MonthPickerDialog extends StatefulWidget {
  const _MonthPickerDialog({
    required this.initialMonth,
    required this.initialYear,
    required this.currentMonth,
    required this.currentYear,
  });

  final int initialMonth;
  final int initialYear;
  final int currentMonth;
  final int currentYear;

  @override
  State<_MonthPickerDialog> createState() => _MonthPickerDialogState();
}

class _MonthPickerDialogState extends State<_MonthPickerDialog> {
  late int _selectedMonth;
  late int _selectedYear;

  @override
  void initState() {
    super.initState();
    _selectedMonth = widget.initialMonth;
    _selectedYear = widget.initialYear;
  }

  @override
  Widget build(BuildContext context) {
    const monthNames = [
      'Gen',
      'Feb',
      'Mar',
      'Apr',
      'Mag',
      'Giu',
      'Lug',
      'Ago',
      'Set',
      'Ott',
      'Nov',
      'Dic',
    ];

    return AlertDialog(
      title: Text(
        'Seleziona Mese',
        style: GoogleFonts.playfairDisplay(
          fontWeight: FontWeight.w700,
        ),
      ),
      content: SizedBox(
        width: 300,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Year selector
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  icon: const Icon(Icons.chevron_left),
                  onPressed: () {
                    setState(() => _selectedYear--);
                  },
                ),
                Text(
                  '$_selectedYear',
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.chevron_right),
                  onPressed: () {
                    setState(() => _selectedYear++);
                  },
                ),
              ],
            ),
            const SizedBox(height: 16),
            // Month grid
            GridView.builder(
              shrinkWrap: true,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 4,
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
                childAspectRatio: 1.5,
              ),
              itemCount: 12,
              itemBuilder: (context, index) {
                final month = index + 1;
                final isSelected =
                    month == _selectedMonth && _selectedYear == widget.initialYear;
                final isCurrent = month == widget.currentMonth &&
                    _selectedYear == widget.currentYear;

                return InkWell(
                  onTap: () {
                    setState(() => _selectedMonth = month);
                  },
                  child: Container(
                    decoration: BoxDecoration(
                      color: isSelected
                          ? AppColors.terracotta
                          : isCurrent
                              ? AppColors.terracotta.withValues(alpha: 0.2)
                              : AppColors.parchment,
                      borderRadius: BorderRadius.circular(4),
                      border: isCurrent && !isSelected
                          ? Border.all(color: AppColors.terracotta, width: 2)
                          : null,
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      monthNames[index],
                      style: GoogleFonts.dmSans(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: isSelected ? AppColors.cream : AppColors.ink,
                      ),
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(
            'Annulla',
            style: GoogleFonts.dmSans(),
          ),
        ),
        ElevatedButton(
          onPressed: () {
            Navigator.of(context).pop({
              'month': _selectedMonth,
              'year': _selectedYear,
            });
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.terracotta,
            foregroundColor: AppColors.cream,
          ),
          child: Text(
            'Conferma',
            style: GoogleFonts.dmSans(fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }
}
