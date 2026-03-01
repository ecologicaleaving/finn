import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../app/routes.dart';
import '../../../../core/enums/reimbursement_status.dart';
import '../../../../core/utils/currency_utils.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../budgets/domain/entities/income_source_entity.dart';
import '../../../budgets/presentation/providers/income_sources_provider.dart';
import '../../../expenses/domain/entities/expense_entity.dart';
import '../../../expenses/presentation/providers/expense_provider.dart';
import '../../../groups/presentation/providers/group_provider.dart';
import '../../domain/entities/dashboard_stats_entity.dart';
import '../providers/dashboard_provider.dart';
import 'expenses_chart_widget.dart';

import '../../../../app/app_theme.dart';
/// Parameters for personal expenses provider
class PersonalExpensesParams {
  final String userId;
  final DashboardPeriod period;
  final int offset;

  const PersonalExpensesParams({
    required this.userId,
    required this.period,
    required this.offset,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PersonalExpensesParams &&
          runtimeType == other.runtimeType &&
          userId == other.userId &&
          period == other.period &&
          offset == other.offset;

  @override
  int get hashCode => userId.hashCode ^ period.hashCode ^ offset.hashCode;
}

/// Calculate date range based on period and offset
(DateTime start, DateTime end) _calculateDateRange(
  DashboardPeriod period,
  int offset,
) {
  final now = DateTime.now();

  switch (period) {
    case DashboardPeriod.week:
      final weekDay = now.weekday;
      final currentWeekStart = now.subtract(Duration(days: weekDay - 1));
      final targetWeekStart = currentWeekStart.add(Duration(days: offset * 7));
      final targetWeekEnd = targetWeekStart.add(const Duration(days: 6));
      return (
        DateTime(targetWeekStart.year, targetWeekStart.month, targetWeekStart.day),
        DateTime(targetWeekEnd.year, targetWeekEnd.month, targetWeekEnd.day, 23, 59, 59),
      );

    case DashboardPeriod.month:
      final targetDate = DateTime(now.year, now.month + offset, 1);
      final startDate = DateTime(targetDate.year, targetDate.month, 1);
      final endDate = DateTime(targetDate.year, targetDate.month + 1, 0, 23, 59, 59);
      return (startDate, endDate);

    case DashboardPeriod.year:
      final targetYear = now.year + offset;
      return (
        DateTime(targetYear, 1, 1),
        DateTime(targetYear, 12, 31, 23, 59, 59),
      );
  }
}

/// Parameters for group members expenses provider
class GroupMembersExpensesParams {
  final String groupId;
  final DashboardPeriod period;
  final int offset;

  const GroupMembersExpensesParams({
    required this.groupId,
    required this.period,
    required this.offset,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GroupMembersExpensesParams &&
          runtimeType == other.runtimeType &&
          groupId == other.groupId &&
          period == other.period &&
          offset == other.offset;

  @override
  int get hashCode => groupId.hashCode ^ period.hashCode ^ offset.hashCode;
}

/// Provider per le spese di gruppo di tutti i membri
final groupMembersExpensesProvider = FutureProvider.autoDispose
    .family<List<Map<String, dynamic>>, GroupMembersExpensesParams>((ref, params) async {
  final supabase = Supabase.instance.client;
  final (startDate, endDate) = _calculateDateRange(params.period, params.offset);

  // Query spese di gruppo raggruppate per paid_by
  final expenses = await supabase
      .from('expenses')
      .select('paid_by, paid_by_name, amount')
      .eq('group_id', params.groupId)
      .eq('is_group_expense', true)
      .gte('date', startDate.toIso8601String().split('T')[0])
      .lte('date', endDate.toIso8601String().split('T')[0]) as List;

  // Raggruppa per membro
  final Map<String, Map<String, dynamic>> memberTotals = {};

  for (final expense in expenses) {
    final paidBy = expense['paid_by'] as String?;
    final paidByName = expense['paid_by_name'] as String?;

    if (paidBy == null) continue;

    final amount = (expense['amount'] as num).toDouble();
    final amountCents = (amount * 100).round();

    if (!memberTotals.containsKey(paidBy)) {
      memberTotals[paidBy] = {
        'userId': paidBy,
        'name': paidByName ?? 'Sconosciuto',
        'total': 0,
      };
    }

    memberTotals[paidBy]!['total'] += amountCents;
  }

  // Converti in lista e ordina per totale decrescente
  final result = memberTotals.values.toList();
  result.sort((a, b) => (b['total'] as int).compareTo(a['total'] as int));

  return result;
});

/// Parameters for member-specific group expenses
class MemberGroupExpensesParams {
  final String groupId;
  final String memberId;
  final DashboardPeriod period;
  final int offset;

  const MemberGroupExpensesParams({
    required this.groupId,
    required this.memberId,
    required this.period,
    required this.offset,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MemberGroupExpensesParams &&
          runtimeType == other.runtimeType &&
          groupId == other.groupId &&
          memberId == other.memberId &&
          period == other.period &&
          offset == other.offset;

  @override
  int get hashCode =>
      groupId.hashCode ^ memberId.hashCode ^ period.hashCode ^ offset.hashCode;
}

/// Provider per le categorie delle spese di gruppo di un membro specifico
final memberGroupExpensesByCategoryProvider = FutureProvider.autoDispose
    .family<List<Map<String, dynamic>>, MemberGroupExpensesParams>((ref, params) async {
  final supabase = Supabase.instance.client;
  final (startDate, endDate) = _calculateDateRange(params.period, params.offset);

  // Query spese di gruppo di uno specifico membro
  final expenses = await supabase
      .from('expenses')
      .select('category_id, amount, expense_categories(name)')
      .eq('group_id', params.groupId)
      .eq('is_group_expense', true)
      .eq('paid_by', params.memberId)
      .gte('date', startDate.toIso8601String().split('T')[0])
      .lte('date', endDate.toIso8601String().split('T')[0]) as List;

  // Raggruppa per categoria
  final Map<String, Map<String, dynamic>> categoryTotals = {};

  for (final expense in expenses) {
    final categoryId = expense['category_id'] as String?;
    if (categoryId == null) continue;

    final categoryData = expense['expense_categories'];
    final categoryName = categoryData is Map<String, dynamic>
        ? (categoryData['name'] as String? ?? 'Sconosciuta')
        : 'Sconosciuta';

    final amount = (expense['amount'] as num).toDouble();
    final amountCents = (amount * 100).round();

    if (!categoryTotals.containsKey(categoryId)) {
      categoryTotals[categoryId] = {
        'categoryId': categoryId,
        'name': categoryName,
        'total': 0,
      };
    }

    categoryTotals[categoryId]!['total'] += amountCents;
  }

  // Converti in lista e ordina per totale decrescente
  final result = categoryTotals.values.toList();
  result.sort((a, b) => (b['total'] as int).compareTo(a['total'] as int));

  return result;
});

/// Provider per le categorie delle spese di gruppo (tutte)
final groupExpensesByCategoryProvider = FutureProvider.autoDispose
    .family<List<Map<String, dynamic>>, GroupMembersExpensesParams>((ref, params) async {
  final supabase = Supabase.instance.client;
  final (startDate, endDate) = _calculateDateRange(params.period, params.offset);

  // Query spese di gruppo raggruppate per categoria
  final expenses = await supabase
      .from('expenses')
      .select('category_id, amount, expense_categories(name)')
      .eq('group_id', params.groupId)
      .eq('is_group_expense', true)
      .gte('date', startDate.toIso8601String().split('T')[0])
      .lte('date', endDate.toIso8601String().split('T')[0]) as List;

  // Raggruppa per categoria
  final Map<String, Map<String, dynamic>> categoryTotals = {};

  for (final expense in expenses) {
    final categoryId = expense['category_id'] as String?;
    if (categoryId == null) continue;

    final categoryData = expense['expense_categories'];
    final categoryName = categoryData is Map<String, dynamic>
        ? (categoryData['name'] as String? ?? 'Sconosciuta')
        : 'Sconosciuta';

    final amount = (expense['amount'] as num).toDouble();
    final amountCents = (amount * 100).round();

    if (!categoryTotals.containsKey(categoryId)) {
      categoryTotals[categoryId] = {
        'categoryId': categoryId,
        'name': categoryName,
        'total': 0,
      };
    }

    categoryTotals[categoryId]!['total'] += amountCents;
  }

  // Converti in lista e ordina per totale decrescente
  final result = categoryTotals.values.toList();
  result.sort((a, b) => (b['total'] as int).compareTo(a['total'] as int));

  return result;
});

/// Provider per le categorie delle spese personali (solo dell'utente)
final personalOnlyExpensesByCategoryProvider = FutureProvider.autoDispose
    .family<List<Map<String, dynamic>>, PersonalExpensesParams>((ref, params) async {
  final supabase = Supabase.instance.client;
  final (startDate, endDate) = _calculateDateRange(params.period, params.offset);

  // Query spese personali (non di gruppo) dell'utente
  final expenses = await supabase
      .from('expenses')
      .select('category_id, amount, expense_categories(name)')
      .eq('paid_by', params.userId)
      .eq('is_group_expense', false)
      .gte('date', startDate.toIso8601String().split('T')[0])
      .lte('date', endDate.toIso8601String().split('T')[0]) as List;

  // Raggruppa per categoria
  final Map<String, Map<String, dynamic>> categoryTotals = {};

  for (final expense in expenses) {
    final categoryId = expense['category_id'] as String?;
    if (categoryId == null) continue;

    final categoryData = expense['expense_categories'];
    final categoryName = categoryData is Map<String, dynamic>
        ? (categoryData['name'] as String? ?? 'Sconosciuta')
        : 'Sconosciuta';

    final amount = (expense['amount'] as num).toDouble();
    final amountCents = (amount * 100).round();

    if (!categoryTotals.containsKey(categoryId)) {
      categoryTotals[categoryId] = {
        'categoryId': categoryId,
        'name': categoryName,
        'total': 0,
      };
    }

    categoryTotals[categoryId]!['total'] += amountCents;
  }

  // Converti in lista e ordina per totale decrescente
  final result = categoryTotals.values.toList();
  result.sort((a, b) => (b['total'] as int).compareTo(a['total'] as int));

  return result;
});

/// Parameters for group category expenses provider
class GroupCategoryExpensesParams {
  final String groupId;
  final String categoryId;
  final DashboardPeriod period;
  final int offset;
  final String? memberId; // Opzionale: se specificato, filtra per membro

  const GroupCategoryExpensesParams({
    required this.groupId,
    required this.categoryId,
    required this.period,
    required this.offset,
    this.memberId,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GroupCategoryExpensesParams &&
          runtimeType == other.runtimeType &&
          groupId == other.groupId &&
          categoryId == other.categoryId &&
          period == other.period &&
          offset == other.offset &&
          memberId == other.memberId;

  @override
  int get hashCode =>
      groupId.hashCode ^ categoryId.hashCode ^ period.hashCode ^ offset.hashCode ^ memberId.hashCode;
}

/// Provider per le spese di gruppo filtrate per categoria (e opzionalmente per membro)
final groupCategoryExpensesProvider = FutureProvider.autoDispose
    .family<List<ExpenseEntity>, GroupCategoryExpensesParams>((ref, params) async {
  final supabase = Supabase.instance.client;
  final (startDate, endDate) = _calculateDateRange(params.period, params.offset);

  // Query spese di gruppo per categoria specifica
  var query = supabase
      .from('expenses')
      .select('*, category_name:expense_categories(name)')
      .eq('group_id', params.groupId)
      .eq('is_group_expense', true)
      .eq('category_id', params.categoryId)
      .gte('date', startDate.toIso8601String().split('T')[0])
      .lte('date', endDate.toIso8601String().split('T')[0]);

  // Se specificato, filtra per membro
  if (params.memberId != null) {
    query = query.eq('paid_by', params.memberId!);
  }

  final response = await query.order('date', ascending: false) as List;

  return response.map<ExpenseEntity>((json) {
    final categoryData = json['category_name'];
    final categoryName = categoryData is Map<String, dynamic>
        ? (categoryData['name'] as String?)
        : null;

    // Parse reimbursement status
    final statusStr = json['reimbursement_status'] as String?;
    ReimbursementStatus status = ReimbursementStatus.none;
    if (statusStr != null) {
      try {
        status = ReimbursementStatus.values.firstWhere(
          (e) => e.toString().split('.').last == statusStr,
          orElse: () => ReimbursementStatus.none,
        );
      } catch (_) {
        status = ReimbursementStatus.none;
      }
    }

    return ExpenseEntity(
      id: json['id'] as String,
      amount: (json['amount'] as num).toDouble(),
      date: DateTime.parse(json['date'] as String),
      categoryId: json['category_id'] as String?,
      categoryName: categoryName,
      merchant: json['merchant'] as String?,
      notes: json['notes'] as String?,
      receiptUrl: json['receipt_url'] as String?,
      createdBy: json['created_by'] as String,
      createdByName: json['created_by_name'] as String?,
      paidBy: json['paid_by'] as String?,
      paidByName: json['paid_by_name'] as String?,
      groupId: json['group_id'] as String,
      isGroupExpense: json['is_group_expense'] as bool? ?? false,
      paymentMethodId: json['payment_method_id'] as String,
      paymentMethodName: json['payment_method_name'] as String?,
      reimbursementStatus: status,
      recurringExpenseId: json['recurring_expense_id'] as String?,
      isRecurringInstance: json['is_recurring_instance'] as bool? ?? false,
      createdAt: json['created_at'] != null ? DateTime.parse(json['created_at'] as String) : null,
      updatedAt: json['updated_at'] != null ? DateTime.parse(json['updated_at'] as String) : null,
      lastModifiedBy: json['last_modified_by'] as String?,
    );
  }).toList();
});

/// Parameters for personal category expenses provider
class PersonalCategoryExpensesParams {
  final String userId;
  final String categoryId;
  final DashboardPeriod period;
  final int offset;

  const PersonalCategoryExpensesParams({
    required this.userId,
    required this.categoryId,
    required this.period,
    required this.offset,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PersonalCategoryExpensesParams &&
          runtimeType == other.runtimeType &&
          userId == other.userId &&
          categoryId == other.categoryId &&
          period == other.period &&
          offset == other.offset;

  @override
  int get hashCode =>
      userId.hashCode ^ categoryId.hashCode ^ period.hashCode ^ offset.hashCode;
}

/// Provider per le spese personali filtrate per categoria
final personalCategoryExpensesProvider = FutureProvider.autoDispose
    .family<List<ExpenseEntity>, PersonalCategoryExpensesParams>((ref, params) async {
  final supabase = Supabase.instance.client;
  final (startDate, endDate) = _calculateDateRange(params.period, params.offset);

  // Query spese personali per categoria specifica
  final response = await supabase
      .from('expenses')
      .select('*, category_name:expense_categories(name)')
      .eq('paid_by', params.userId)
      .eq('is_group_expense', false)
      .eq('category_id', params.categoryId)
      .gte('date', startDate.toIso8601String().split('T')[0])
      .lte('date', endDate.toIso8601String().split('T')[0])
      .order('date', ascending: false) as List;

  return response.map<ExpenseEntity>((json) {
    final categoryData = json['category_name'];
    final categoryName = categoryData is Map<String, dynamic>
        ? (categoryData['name'] as String?)
        : null;

    // Parse reimbursement status
    final statusStr = json['reimbursement_status'] as String?;
    ReimbursementStatus status = ReimbursementStatus.none;
    if (statusStr != null) {
      try {
        status = ReimbursementStatus.values.firstWhere(
          (e) => e.toString().split('.').last == statusStr,
          orElse: () => ReimbursementStatus.none,
        );
      } catch (_) {
        status = ReimbursementStatus.none;
      }
    }

    return ExpenseEntity(
      id: json['id'] as String,
      amount: (json['amount'] as num).toDouble(),
      date: DateTime.parse(json['date'] as String),
      categoryId: json['category_id'] as String?,
      categoryName: categoryName,
      merchant: json['merchant'] as String?,
      notes: json['notes'] as String?,
      receiptUrl: json['receipt_url'] as String?,
      createdBy: json['created_by'] as String,
      createdByName: json['created_by_name'] as String?,
      paidBy: json['paid_by'] as String?,
      paidByName: json['paid_by_name'] as String?,
      groupId: json['group_id'] as String,
      isGroupExpense: json['is_group_expense'] as bool? ?? false,
      paymentMethodId: json['payment_method_id'] as String,
      paymentMethodName: json['payment_method_name'] as String?,
      reimbursementStatus: status,
      recurringExpenseId: json['recurring_expense_id'] as String?,
      isRecurringInstance: json['is_recurring_instance'] as bool? ?? false,
      createdAt: json['created_at'] != null ? DateTime.parse(json['created_at'] as String) : null,
      updatedAt: json['updated_at'] != null ? DateTime.parse(json['updated_at'] as String) : null,
      lastModifiedBy: json['last_modified_by'] as String?,
    );
  }).toList();
});

/// Provider per le spese personali e di gruppo raggruppate per categoria
final personalExpensesByCategoryProvider = FutureProvider.autoDispose
    .family<Map<String, dynamic>, PersonalExpensesParams>((ref, params) async {
  final supabase = Supabase.instance.client;
  final (startDate, endDate) = _calculateDateRange(params.period, params.offset);

  // Query spese personali (pagate dall'utente)
  // Use paid_by to include expenses created by admin on behalf of user
  final personalExpenses = await supabase
      .from('expenses')
      .select('amount, category_id, expense_categories(name)')
      .eq('paid_by', params.userId)
      .eq('is_group_expense', false)
      .gte('date', startDate.toIso8601String().split('T')[0])
      .lte('date', endDate.toIso8601String().split('T')[0]) as List;

  // Query spese di gruppo (pagate dall'utente)
  // Use paid_by to include expenses created by admin on behalf of user
  final groupExpenses = await supabase
      .from('expenses')
      .select('amount, category_id, expense_categories(name)')
      .eq('paid_by', params.userId)
      .eq('is_group_expense', true)
      .gte('date', startDate.toIso8601String().split('T')[0])
      .lte('date', endDate.toIso8601String().split('T')[0]) as List;

  // Raggruppa per categoria
  final Map<String, dynamic> categoryTotals = {};

  // Processa spese personali
  for (final expense in personalExpenses) {
    final categoryId = expense['category_id'] as String?;
    if (categoryId == null) continue;

    final categoryData = expense['expense_categories'];
    final categoryName = categoryData is Map<String, dynamic>
        ? (categoryData['name'] as String? ?? 'Sconosciuta')
        : 'Sconosciuta';

    final amount = (expense['amount'] as num).toDouble();
    final amountCents = (amount * 100).round();

    if (!categoryTotals.containsKey(categoryId)) {
      categoryTotals[categoryId] = {
        'name': categoryName,
        'personal': 0,
        'group': 0,
      };
    }

    categoryTotals[categoryId]['personal'] += amountCents;
  }

  // Processa spese di gruppo
  for (final expense in groupExpenses) {
    final categoryId = expense['category_id'] as String?;
    if (categoryId == null) continue;

    final categoryData = expense['expense_categories'];
    final categoryName = categoryData is Map<String, dynamic>
        ? (categoryData['name'] as String? ?? 'Sconosciuta')
        : 'Sconosciuta';

    final amount = (expense['amount'] as num).toDouble();
    final amountCents = (amount * 100).round();

    if (!categoryTotals.containsKey(categoryId)) {
      categoryTotals[categoryId] = {
        'name': categoryName,
        'personal': 0,
        'group': 0,
      };
    }

    categoryTotals[categoryId]['group'] += amountCents;
  }

  return categoryTotals;
});

/// Widget che mostra la vista personale completa della dashboard in una singola card
class PersonalDashboardView extends ConsumerStatefulWidget {
  const PersonalDashboardView({super.key});

  @override
  ConsumerState<PersonalDashboardView> createState() => _PersonalDashboardViewState();
}

class _PersonalDashboardViewState extends ConsumerState<PersonalDashboardView> {
  @override
  Widget build(BuildContext context) {
    final group = ref.watch(currentGroupProvider);
    final userId = ref.watch(currentUserIdProvider);
    final dashboardState = ref.watch(dashboardProvider);

    if (group == null) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Icon(Icons.group_off, size: 48, color: Colors.grey),
              const SizedBox(height: 8),
              Text(
                'Nessun gruppo disponibile',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 4),
              Text(
                'Crea o unisciti a un gruppo per iniziare',
                style: Theme.of(context).textTheme.bodySmall,
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Riepilogo header
            Row(
              children: [
                Icon(Icons.account_balance_wallet, color: AppColors.terracotta),
                const SizedBox(width: 8),
                Text(
                  'Riepilogo Mensile',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Totale Gruppo espandibile con categorie
            _GroupTotalCard(
              groupId: group.id,
              period: dashboardState.period,
              offset: dashboardState.offset,
            ),
            const SizedBox(height: 16),

            // Card utenti espandibili (me per primo, poi altri)
            _MembersCards(
              userId: userId,
              groupId: group.id,
              period: dashboardState.period,
              offset: dashboardState.offset,
            ),
            const SizedBox(height: 24),

            // Grafico a barre
            _PersonalBarChart(
              groupId: group.id,
              userId: userId,
              period: dashboardState.period,
              offset: dashboardState.offset,
            ),
            const SizedBox(height: 24),

            // Grafico a torta
            _PersonalPieChart(
              userId: userId,
              period: dashboardState.period,
              offset: dashboardState.offset,
            ),
          ],
        ),
      ),
    );
  }
}

/// Card Totale Gruppo espandibile con categorie dentro
class _GroupTotalCard extends ConsumerStatefulWidget {
  const _GroupTotalCard({
    required this.groupId,
    required this.period,
    required this.offset,
  });

  final String groupId;
  final DashboardPeriod period;
  final int offset;

  @override
  ConsumerState<_GroupTotalCard> createState() => _GroupTotalCardState();
}

class _GroupTotalCardState extends ConsumerState<_GroupTotalCard> {
  bool _isExpanded = false;

  void _showGroupCategoryExpensesBottomSheet(
    BuildContext context,
    WidgetRef ref,
    String categoryId,
    String categoryName,
  ) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollController) {
          return _GroupCategoryExpensesSheet(
            categoryId: categoryId,
            categoryName: categoryName,
            groupId: widget.groupId,
            memberId: null, // Nessun filtro per membro - mostra tutte le spese gruppo
            period: widget.period,
            offset: widget.offset,
            scrollController: scrollController,
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final membersParams = GroupMembersExpensesParams(
      groupId: widget.groupId,
      period: widget.period,
      offset: widget.offset,
    );
    final membersExpensesAsync = ref.watch(groupMembersExpensesProvider(membersParams));
    final categoriesAsync = ref.watch(groupExpensesByCategoryProvider(membersParams));

    return InkWell(
      onTap: () {
        setState(() {
          _isExpanded = !_isExpanded;
        });
      },
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.blue.shade50,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.blue.shade200),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header con totale
            Row(
              children: [
                Icon(Icons.group, color: Colors.blue.shade700, size: 28),
                const SizedBox(width: 12),
                Expanded(
                  child: membersExpensesAsync.when(
                    data: (members) {
                      final totalGroup = members.fold<int>(
                        0,
                        (sum, member) => sum + (member['total'] as int),
                      );

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Totale Gruppo',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: Colors.blue.shade700,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            CurrencyUtils.formatCents(totalGroup),
                            style: theme.textTheme.headlineMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: Colors.blue.shade700,
                            ),
                          ),
                        ],
                      );
                    },
                    loading: () => const CircularProgressIndicator(strokeWidth: 2),
                    error: (_, __) => const Text('--'),
                  ),
                ),
                Icon(
                  _isExpanded ? Icons.expand_less : Icons.expand_more,
                  color: Colors.blue.shade700,
                ),
              ],
            ),

            // Categorie espanse
            if (_isExpanded) ...[
              const SizedBox(height: 16),
              const Divider(height: 1),
              const SizedBox(height: 12),
              Text(
                'Categorie',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: Colors.blue.shade700,
                ),
              ),
              const SizedBox(height: 8),
              categoriesAsync.when(
                data: (categories) {
                  if (categories.isEmpty) {
                    return Text(
                      'Nessuna spesa di gruppo',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: Colors.grey,
                      ),
                    );
                  }

                  return Column(
                    children: categories.map((category) {
                      final name = category['name'] as String;
                      final categoryId = category['categoryId'] as String;
                      final total = category['total'] as int;

                      return InkWell(
                        onTap: () {
                          _showGroupCategoryExpensesBottomSheet(
                            context,
                            ref,
                            categoryId,
                            name,
                          );
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Text(
                                  name,
                                  style: theme.textTheme.bodySmall,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              Row(
                                children: [
                                  Text(
                                    CurrencyUtils.formatCentsCompact(total),
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  Icon(
                                    Icons.chevron_right,
                                    size: 16,
                                    color: Colors.blue.shade700,
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  );
                },
                loading: () => const Padding(
                  padding: EdgeInsets.all(8.0),
                  child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                ),
                error: (_, __) => Text(
                  'Errore caricamento categorie',
                  style: theme.textTheme.bodySmall?.copyWith(color: Colors.red),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Widget per le card dei membri
class _MembersCards extends ConsumerStatefulWidget {
  const _MembersCards({
    required this.userId,
    required this.groupId,
    required this.period,
    required this.offset,
  });

  final String userId;
  final String groupId;
  final DashboardPeriod period;
  final int offset;

  @override
  ConsumerState<_MembersCards> createState() => _MembersCardsState();
}

class _MembersCardsState extends ConsumerState<_MembersCards> {
  final Map<String, bool> _expandedMembers = {};

  @override
  Widget build(BuildContext context) {
    final membersParams = GroupMembersExpensesParams(
      groupId: widget.groupId,
      period: widget.period,
      offset: widget.offset,
    );
    final membersExpensesAsync = ref.watch(groupMembersExpensesProvider(membersParams));

    final personalParams = PersonalExpensesParams(
      userId: widget.userId,
      period: widget.period,
      offset: widget.offset,
    );
    final personalExpensesAsync = ref.watch(personalExpensesByCategoryProvider(personalParams));

    return membersExpensesAsync.when(
      data: (members) {
        // Ordina: utente corrente per primo, poi gli altri
        final sortedMembers = [...members];
        sortedMembers.sort((a, b) {
          final aIsCurrentUser = a['userId'] == widget.userId;
          final bIsCurrentUser = b['userId'] == widget.userId;

          if (aIsCurrentUser && !bIsCurrentUser) return -1;
          if (!aIsCurrentUser && bIsCurrentUser) return 1;
          return 0;
        });

        return Column(
          children: sortedMembers.map((member) {
            final memberUserId = member['userId'] as String;
            final name = member['name'] as String;
            final groupTotal = member['total'] as int;
            final isCurrentUser = memberUserId == widget.userId;
            final isExpanded = _expandedMembers[memberUserId] ?? false;

            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _MemberCard(
                memberUserId: memberUserId,
                name: name,
                groupTotal: groupTotal,
                isCurrentUser: isCurrentUser,
                isExpanded: isExpanded,
                groupId: widget.groupId,
                period: widget.period,
                offset: widget.offset,
                personalExpensesAsync: isCurrentUser ? personalExpensesAsync : null,
                onToggle: () {
                  setState(() {
                    _expandedMembers[memberUserId] = !isExpanded;
                  });
                },
              ),
            );
          }).toList(),
        );
      },
      loading: () => const Center(
        child: Padding(
          padding: EdgeInsets.all(20.0),
          child: CircularProgressIndicator(),
        ),
      ),
      error: (_, __) => const SizedBox(),
    );
  }
}

/// Card per singolo membro espandibile
class _MemberCard extends ConsumerWidget {
  const _MemberCard({
    required this.memberUserId,
    required this.name,
    required this.groupTotal,
    required this.isCurrentUser,
    required this.isExpanded,
    required this.groupId,
    required this.period,
    required this.offset,
    this.personalExpensesAsync,
    required this.onToggle,
  });

  final String memberUserId;
  final String name;
  final int groupTotal;
  final bool isCurrentUser;
  final bool isExpanded;
  final String groupId;
  final DashboardPeriod period;
  final int offset;
  final AsyncValue<Map<String, dynamic>>? personalExpensesAsync;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: InkWell(
        onTap: onToggle,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: isExpanded ? Colors.grey.shade100 : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.grey.shade300),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header row
              Row(
                children: [
                  Expanded(
                    child: Text(
                      isCurrentUser ? '$name (Tu)' : name,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: isCurrentUser ? Colors.blue.shade700 : Colors.grey.shade800,
                      ),
                    ),
                  ),
                  Icon(
                    isExpanded ? Icons.expand_less : Icons.expand_more,
                    size: 20,
                    color: Colors.grey.shade600,
                  ),
                ],
              ),
              const SizedBox(height: 8),

              // Totali quando chiuso
              if (!isExpanded) ...[
                // Spese gruppo
                Row(
                  children: [
                    Icon(Icons.group, size: 16, color: Colors.blue.shade700),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Gruppo:',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ),
                    Text(
                      CurrencyUtils.formatCentsCompact(groupTotal),
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: Colors.blue.shade700,
                      ),
                    ),
                  ],
                ),

                // Spese personali e totale (solo per utente corrente)
                if (isCurrentUser && personalExpensesAsync != null)
                  personalExpensesAsync!.when(
                    data: (categoryTotals) {
                      final totalPersonal = categoryTotals.values.fold<int>(
                        0,
                        (sum, category) => sum + (category['personal'] as int),
                      );
                      final totalCombined = groupTotal + totalPersonal;

                      return Column(
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Row(
                              children: [
                                Icon(Icons.person, size: 16, color: AppColors.terracotta),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    'Personali:',
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: Colors.grey.shade600,
                                    ),
                                  ),
                                ),
                                Text(
                                  CurrencyUtils.formatCentsCompact(totalPersonal),
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.terracotta,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 8),
                          const Divider(height: 1),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  'Totale:',
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    fontWeight: FontWeight.bold,
                                    color: Colors.grey.shade800,
                                  ),
                                ),
                              ),
                              Text(
                                CurrencyUtils.formatCents(totalCombined),
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.grey.shade800,
                                ),
                              ),
                            ],
                          ),
                        ],
                      );
                    },
                    loading: () => const SizedBox(height: 20),
                    error: (_, __) => const SizedBox(),
                  ),
              ],

              // Categorie espanse
              if (isExpanded) ...[
                const SizedBox(height: 12),
                const Divider(height: 1),
                const SizedBox(height: 12),
                _MemberCategories(
                  memberUserId: memberUserId,
                  groupId: groupId,
                  period: period,
                  offset: offset,
                  isCurrentUser: isCurrentUser,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Widget per mostrare le categorie di un membro
class _MemberCategories extends ConsumerWidget {
  const _MemberCategories({
    required this.memberUserId,
    required this.groupId,
    required this.period,
    required this.offset,
    required this.isCurrentUser,
  });

  final String memberUserId;
  final String groupId;
  final DashboardPeriod period;
  final int offset;
  final bool isCurrentUser;

  void _showCategoryExpenses(
    BuildContext context,
    WidgetRef ref,
    String categoryId,
    String categoryName,
    bool isGroupCategory,
  ) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollController) {
          if (isGroupCategory) {
            return _GroupCategoryExpensesSheet(
              categoryId: categoryId,
              categoryName: categoryName,
              groupId: groupId,
              memberId: memberUserId, // Filtra per questo membro
              period: period,
              offset: offset,
              scrollController: scrollController,
            );
          } else {
            return _PersonalCategoryExpensesSheet(
              categoryId: categoryId,
              categoryName: categoryName,
              userId: memberUserId,
              period: period,
              offset: offset,
              scrollController: scrollController,
            );
          }
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    // Get group categories for this specific member
    final memberGroupParams = MemberGroupExpensesParams(
      groupId: groupId,
      memberId: memberUserId,
      period: period,
      offset: offset,
    );
    final groupCategoriesAsync = ref.watch(memberGroupExpensesByCategoryProvider(memberGroupParams));

    // Get personal categories if current user
    final personalCategoriesParams = PersonalExpensesParams(
      userId: memberUserId,
      period: period,
      offset: offset,
    );
    final personalCategoriesAsync = isCurrentUser
        ? ref.watch(personalOnlyExpensesByCategoryProvider(personalCategoriesParams))
        : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Categorie',
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.bold,
            color: Colors.grey.shade800,
          ),
        ),
        const SizedBox(height: 8),

        // Categorie unificate (gruppo + personali per utente corrente)
        if (isCurrentUser && personalCategoriesAsync != null)
          // Utente corrente: mostra categorie unificate
          _buildUnifiedCategories(context, theme, ref, groupCategoriesAsync, personalCategoriesAsync)
        else
          // Altri utenti: solo categorie gruppo
          _buildGroupOnlyCategories(context, theme, ref, groupCategoriesAsync),
      ],
    );
  }

  Widget _buildGroupOnlyCategories(
    BuildContext context,
    ThemeData theme,
    WidgetRef ref,
    AsyncValue<List<Map<String, dynamic>>> groupCategoriesAsync,
  ) {
    return groupCategoriesAsync.when(
      data: (categories) {
        if (categories.isEmpty) {
          return Text(
            'Nessuna spesa',
            style: theme.textTheme.bodySmall?.copyWith(
              color: Colors.grey,
            ),
          );
        }

        return Column(
          children: categories.map((category) {
            final name = category['name'] as String;
            final categoryId = category['categoryId'] as String;
            final total = category['total'] as int;

            return InkWell(
              onTap: () {
                _showCategoryExpenses(context, ref, categoryId, name, true);
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        name,
                        style: theme.textTheme.bodySmall,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Row(
                      children: [
                        Text(
                          CurrencyUtils.formatCentsCompact(total),
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: Colors.blue.shade700,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Icon(
                          Icons.chevron_right,
                          size: 16,
                          color: Colors.grey.shade600,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        );
      },
      loading: () => const Padding(
        padding: EdgeInsets.all(8.0),
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      ),
      error: (_, __) => Text(
        'Errore caricamento categorie',
        style: theme.textTheme.bodySmall?.copyWith(color: Colors.red),
      ),
    );
  }

  Widget _buildUnifiedCategories(
    BuildContext context,
    ThemeData theme,
    WidgetRef ref,
    AsyncValue<List<Map<String, dynamic>>> groupCategoriesAsync,
    AsyncValue<List<Map<String, dynamic>>> personalCategoriesAsync,
  ) {
    return groupCategoriesAsync.when(
      data: (groupCategories) {
        return personalCategoriesAsync.when(
          data: (personalCategories) {
            // Unifica le categorie
            final Map<String, Map<String, dynamic>> unifiedCategories = {};

            // Aggiungi categorie gruppo
            for (final category in groupCategories) {
              final categoryId = category['categoryId'] as String;
              unifiedCategories[categoryId] = {
                'categoryId': categoryId,
                'name': category['name'] as String,
                'groupTotal': category['total'] as int,
                'personalTotal': 0,
              };
            }

            // Aggiungi/aggiorna categorie personali
            for (final category in personalCategories) {
              final categoryId = category['categoryId'] as String;
              if (unifiedCategories.containsKey(categoryId)) {
                unifiedCategories[categoryId]!['personalTotal'] = category['total'] as int;
              } else {
                unifiedCategories[categoryId] = {
                  'categoryId': categoryId,
                  'name': category['name'] as String,
                  'groupTotal': 0,
                  'personalTotal': category['total'] as int,
                };
              }
            }

            if (unifiedCategories.isEmpty) {
              return Text(
                'Nessuna spesa',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: Colors.grey,
                ),
              );
            }

            // Ordina per totale decrescente
            final sortedCategories = unifiedCategories.values.toList();
            sortedCategories.sort((a, b) {
              final totalA = (a['groupTotal'] as int) + (a['personalTotal'] as int);
              final totalB = (b['groupTotal'] as int) + (b['personalTotal'] as int);
              return totalB.compareTo(totalA);
            });

            return Column(
              children: sortedCategories.map((category) {
                final name = category['name'] as String;
                final categoryId = category['categoryId'] as String;
                final groupTotal = category['groupTotal'] as int;
                final personalTotal = category['personalTotal'] as int;

                return InkWell(
                  onTap: () {
                    // Mostra bottom sheet con entrambe le spese se presenti
                    _showCategoryExpenses(context, ref, categoryId, name, true);
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            name,
                            style: theme.textTheme.bodySmall,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Row(
                          children: [
                            // Totale gruppo
                            if (groupTotal > 0)
                              Row(
                                children: [
                                  Icon(Icons.group, size: 12, color: Colors.blue.shade700),
                                  const SizedBox(width: 2),
                                  Text(
                                    CurrencyUtils.formatCentsCompact(groupTotal),
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      fontWeight: FontWeight.w600,
                                      color: Colors.blue.shade700,
                                    ),
                                  ),
                                ],
                              ),

                            // Separatore
                            if (groupTotal > 0 && personalTotal > 0)
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 6),
                                child: Text(
                                  '+',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: Colors.grey.shade600,
                                  ),
                                ),
                              ),

                            // Totale personale
                            if (personalTotal > 0)
                              Row(
                                children: [
                                  Icon(Icons.person, size: 12, color: AppColors.terracotta),
                                  const SizedBox(width: 2),
                                  Text(
                                    CurrencyUtils.formatCentsCompact(personalTotal),
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      fontWeight: FontWeight.w600,
                                      color: AppColors.terracotta,
                                    ),
                                  ),
                                ],
                              ),

                            const SizedBox(width: 4),
                            Icon(
                              Icons.chevron_right,
                              size: 16,
                              color: Colors.grey.shade600,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            );
          },
          loading: () => const Padding(
            padding: EdgeInsets.all(8.0),
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          ),
          error: (_, __) => Text(
            'Errore caricamento categorie',
            style: theme.textTheme.bodySmall?.copyWith(color: Colors.red),
          ),
        );
      },
      loading: () => const Padding(
        padding: EdgeInsets.all(8.0),
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      ),
      error: (_, __) => Text(
        'Errore caricamento categorie',
        style: theme.textTheme.bodySmall?.copyWith(color: Colors.red),
      ),
    );
  }
}

/// Sezione Gruppo con totale e breakdown membri
class _GroupSection extends ConsumerStatefulWidget {
  const _GroupSection({
    required this.userId,
    required this.groupId,
    required this.period,
    required this.offset,
  });

  final String userId;
  final String groupId;
  final DashboardPeriod period;
  final int offset;

  @override
  ConsumerState<_GroupSection> createState() => _GroupSectionState();
}

class _GroupSectionState extends ConsumerState<_GroupSection> {
  bool _isExpanded = false;

  void _showGroupCategoryExpensesBottomSheet(
    BuildContext context,
    WidgetRef ref,
    String categoryId,
    String categoryName,
    String groupId,
  ) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollController) {
          return _GroupCategoryExpensesSheet(
            categoryId: categoryId,
            categoryName: categoryName,
            groupId: groupId,
            period: widget.period,
            offset: widget.offset,
            scrollController: scrollController,
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final membersParams = GroupMembersExpensesParams(
      groupId: widget.groupId,
      period: widget.period,
      offset: widget.offset,
    );
    final categoriesAsync = ref.watch(groupExpensesByCategoryProvider(membersParams));

    return InkWell(
      onTap: () {
        setState(() {
          _isExpanded = !_isExpanded;
        });
      },
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.blue.withOpacity(0.05),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.blue.withOpacity(0.2)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Icon(Icons.group, color: Colors.blue, size: 18),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Spese di Gruppo per Categoria',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: Colors.blue.shade700,
                    ),
                  ),
                ),
                Icon(
                  _isExpanded ? Icons.expand_less : Icons.expand_more,
                  color: Colors.blue.shade700,
                ),
              ],
            ),

            // Sezione espansa: categorie e grafico
            if (_isExpanded) ...[
              const SizedBox(height: 12),
              categoriesAsync.when(
                data: (categories) {
                  if (categories.isEmpty) {
                    return Text(
                      'Nessuna spesa di gruppo',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: Colors.grey,
                      ),
                    );
                  }

                  return Column(
                    children: [
                      // Lista categorie tappabili
                      ...categories.map((category) {
                        final name = category['name'] as String;
                        final categoryId = category['categoryId'] as String;
                        final total = category['total'] as int;

                        return InkWell(
                          onTap: () {
                            _showGroupCategoryExpensesBottomSheet(
                              context,
                              ref,
                              categoryId,
                              name,
                              widget.groupId,
                            );
                          },
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Text(
                                    name,
                                    style: theme.textTheme.bodySmall,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                Row(
                                  children: [
                                    Text(
                                      CurrencyUtils.formatCentsCompact(total),
                                      style: theme.textTheme.bodySmall?.copyWith(
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    Icon(
                                      Icons.chevron_right,
                                      size: 16,
                                      color: Colors.blue.shade700,
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        );
                      }).toList(),

                      // Grafico a torta
                      if (categories.length > 1) ...[
                        const SizedBox(height: 16),
                        SizedBox(
                          height: 200,
                          child: _CategoryPieChart(
                            categories: categories,
                            color: Colors.blue.shade700,
                          ),
                        ),
                      ],
                    ],
                  );
                },
                loading: () => const Padding(
                  padding: EdgeInsets.all(8.0),
                  child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                ),
                error: (_, __) => Text(
                  'Errore caricamento categorie',
                  style: theme.textTheme.bodySmall?.copyWith(color: Colors.red),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Sezione Personali
class _PersonalSection extends ConsumerStatefulWidget {
  const _PersonalSection({
    required this.userId,
    required this.period,
    required this.offset,
  });

  final String userId;
  final DashboardPeriod period;
  final int offset;

  @override
  ConsumerState<_PersonalSection> createState() => _PersonalSectionState();
}

class _PersonalSectionState extends ConsumerState<_PersonalSection> {
  bool _isExpanded = false;

  void _showPersonalCategoryExpensesBottomSheet(
    BuildContext context,
    WidgetRef ref,
    String categoryId,
    String categoryName,
    String userId,
  ) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollController) {
          return _PersonalCategoryExpensesSheet(
            categoryId: categoryId,
            categoryName: categoryName,
            userId: userId,
            period: widget.period,
            offset: widget.offset,
            scrollController: scrollController,
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final params = PersonalExpensesParams(
      userId: widget.userId,
      period: widget.period,
      offset: widget.offset,
    );
    final expensesAsync = ref.watch(personalExpensesByCategoryProvider(params));
    final categoriesAsync = ref.watch(personalOnlyExpensesByCategoryProvider(params));

    return InkWell(
      onTap: () {
        setState(() {
          _isExpanded = !_isExpanded;
        });
      },
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.terracotta.withOpacity(0.05),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.terracotta.withOpacity(0.2)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Icon(Icons.person, color: AppColors.terracotta, size: 18),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Personali',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: AppColors.terracotta,
                    ),
                  ),
                ),
                Icon(
                  _isExpanded ? Icons.expand_less : Icons.expand_more,
                  color: AppColors.terracotta,
                ),
              ],
            ),
            const SizedBox(height: 8),

            // Totale personali
            expensesAsync.when(
              data: (categoryTotals) {
                final totalPersonal = categoryTotals.values.fold<int>(
                  0,
                  (sum, category) => sum + (category['personal'] as int),
                );

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      CurrencyUtils.formatCentsCompact(totalPersonal),
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: AppColors.terracotta,
                      ),
                    ),

                    // Sezione espansa: categorie e grafico
                    if (_isExpanded) ...[
                      const SizedBox(height: 12),
                      const Divider(height: 1),
                      const SizedBox(height: 12),
                      Text(
                        'Categorie',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: AppColors.terracotta,
                        ),
                      ),
                      const SizedBox(height: 8),
                      categoriesAsync.when(
                        data: (categories) {
                          if (categories.isEmpty) {
                            return Text(
                              'Nessuna spesa personale',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: Colors.grey,
                              ),
                            );
                          }

                          return Column(
                            children: [
                              // Lista categorie tappabili
                              ...categories.map((category) {
                                final name = category['name'] as String;
                                final categoryId = category['categoryId'] as String;
                                final total = category['total'] as int;

                                return InkWell(
                                  onTap: () {
                                    _showPersonalCategoryExpensesBottomSheet(
                                      context,
                                      ref,
                                      categoryId,
                                      name,
                                      widget.userId,
                                    );
                                  },
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(vertical: 6),
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Expanded(
                                          child: Text(
                                            name,
                                            style: theme.textTheme.bodySmall,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        Row(
                                          children: [
                                            Text(
                                              CurrencyUtils.formatCentsCompact(total),
                                              style: theme.textTheme.bodySmall?.copyWith(
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                            const SizedBox(width: 4),
                                            Icon(
                                              Icons.chevron_right,
                                              size: 16,
                                              color: AppColors.terracotta,
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              }).toList(),

                              // Grafico a torta
                              if (categories.length > 1) ...[
                                const SizedBox(height: 16),
                                SizedBox(
                                  height: 200,
                                  child: _CategoryPieChart(
                                    categories: categories,
                                    color: AppColors.terracotta,
                                  ),
                                ),
                              ],
                            ],
                          );
                        },
                        loading: () => const Padding(
                          padding: EdgeInsets.all(8.0),
                          child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                        ),
                        error: (_, __) => Text(
                          'Errore caricamento categorie',
                          style: theme.textTheme.bodySmall?.copyWith(color: Colors.red),
                        ),
                      ),
                    ],
                  ],
                );
              },
              loading: () => const SizedBox(
                height: 20,
                width: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              error: (_, __) => Text('--', style: theme.textTheme.headlineSmall),
            ),
          ],
        ),
      ),
    );
  }
}

/// Sezione categorie
class _CategoriesSection extends ConsumerWidget {
  const _CategoriesSection({
    required this.userId,
    required this.period,
    required this.offset,
  });

  final String userId;
  final DashboardPeriod period;
  final int offset;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final params = PersonalExpensesParams(
      userId: userId,
      period: period,
      offset: offset,
    );
    final expensesAsync = ref.watch(personalExpensesByCategoryProvider(params));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        expensesAsync.when(
          data: (categoryTotals) {
            if (categoryTotals.isEmpty) {
              return Center(
                child: Text(
                  'Nessuna spesa personale questo mese',
                  style: theme.textTheme.bodySmall,
                ),
              );
            }

            final categories = categoryTotals.entries.toList()
              ..sort((a, b) {
                final totalA = (a.value['personal'] as int) + (a.value['group'] as int);
                final totalB = (b.value['personal'] as int) + (b.value['group'] as int);
                return totalB.compareTo(totalA);
              });

            return Column(
              children: categories.map((entry) {
                final categoryName = entry.value['name'] as String;
                final categoryId = entry.key;
                final personalSpent = entry.value['personal'] as int;
                final groupSpent = entry.value['group'] as int;
                final totalSpent = personalSpent + groupSpent;

                return InkWell(
                  onTap: () {
                    _showExpensesBottomSheet(context, ref, categoryId, categoryName, userId);
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            categoryName,
                            style: theme.textTheme.bodyMedium,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              CurrencyUtils.formatCentsCompact(totalSpent),
                              style: theme.textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            if (groupSpent > 0)
                              Text(
                                '(${CurrencyUtils.formatCentsCompact(groupSpent)} gruppo)',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: Colors.grey.shade600,
                                  fontSize: 11,
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            );
          },
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, __) => Text(
            'Errore caricamento categorie',
            style: theme.textTheme.bodySmall?.copyWith(color: Colors.red),
          ),
        ),
      ],
    );
  }

  void _showExpensesBottomSheet(
    BuildContext context,
    WidgetRef ref,
    String categoryId,
    String categoryName,
    String userId,
  ) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollController) {
          return _CategoryExpensesSheet(
            categoryId: categoryId,
            categoryName: categoryName,
            userId: userId,
            scrollController: scrollController,
          );
        },
      ),
    );
  }
}

/// Grafico a barre personalizzato per vista personale
class _PersonalBarChart extends ConsumerWidget {
  const _PersonalBarChart({
    required this.groupId,
    required this.userId,
    required this.period,
    required this.offset,
  });

  final String groupId;
  final String userId;
  final DashboardPeriod period;
  final int offset;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    // Convert DashboardPeriod to ChartPeriod
    final chartPeriod = period == DashboardPeriod.week
        ? ChartPeriod.week
        : period == DashboardPeriod.month
            ? ChartPeriod.month
            : ChartPeriod.year;

    final params = ExpenseChartParams(
      groupId: groupId,
      userId: userId,
      period: chartPeriod,
      isPersonalView: true,
      offset: offset,
    );
    final dataAsync = ref.watch(expensesByPeriodProvider(params));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.bar_chart, color: AppColors.terracotta),
            const SizedBox(width: 8),
            Text(
              'Andamento Spese',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),

        // Chart
        dataAsync.when(
          data: (data) => SizedBox(
            height: 200,
            child: data.isEmpty
                ? Center(
                    child: Text(
                      'Nessuna spesa nel periodo',
                      style: theme.textTheme.bodySmall,
                    ),
                  )
                : BarChart(
                    BarChartData(
                      alignment: BarChartAlignment.spaceAround,
                      maxY: _getMaxY(data),
                      barTouchData: BarTouchData(
                        enabled: true,
                        touchTooltipData: BarTouchTooltipData(
                          tooltipBgColor: Colors.black87,
                          getTooltipItem: (group, groupIndex, rod, rodIndex) {
                            final amount = rod.toY.round();
                            return BarTooltipItem(
                              CurrencyUtils.formatCents(amount),
                              const TextStyle(color: Colors.white),
                            );
                          },
                        ),
                      ),
                      titlesData: FlTitlesData(
                        show: true,
                        bottomTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            getTitlesWidget: (value, meta) {
                              final index = value.toInt();
                              if (index < 0 || index >= data.length) {
                                return const SizedBox.shrink();
                              }
                              return Padding(
                                padding: const EdgeInsets.only(top: 8),
                                child: Text(
                                  data[index]['label'],
                                  style: theme.textTheme.bodySmall,
                                ),
                              );
                            },
                          ),
                        ),
                        leftTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 50,
                            getTitlesWidget: (value, meta) {
                              if (value == 0) return const SizedBox.shrink();
                              return Text(
                                '€${(value / 100).toStringAsFixed(0)}',
                                style: theme.textTheme.bodySmall?.copyWith(fontSize: 10),
                              );
                            },
                          ),
                        ),
                        topTitles: const AxisTitles(
                          sideTitles: SideTitles(showTitles: false),
                        ),
                        rightTitles: const AxisTitles(
                          sideTitles: SideTitles(showTitles: false),
                        ),
                      ),
                      gridData: FlGridData(
                        show: true,
                        drawVerticalLine: false,
                        horizontalInterval: _getMaxY(data) / 5,
                      ),
                      borderData: FlBorderData(show: false),
                      barGroups: data
                          .asMap()
                          .entries
                          .map(
                            (entry) => BarChartGroupData(
                              x: entry.key,
                              barRods: [
                                BarChartRodData(
                                  toY: entry.value['value'].toDouble(),
                                  color: AppColors.terracotta,
                                  width: chartPeriod == ChartPeriod.month ? 6 : 16,
                                  borderRadius: const BorderRadius.only(
                                    topLeft: Radius.circular(4),
                                    topRight: Radius.circular(4),
                                  ),
                                ),
                              ],
                            ),
                          )
                          .toList(),
                    ),
                  ),
          ),
          loading: () => const SizedBox(
            height: 200,
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (error, _) => SizedBox(
            height: 200,
            child: Center(
              child: Text(
                'Errore caricamento dati',
                style: theme.textTheme.bodySmall?.copyWith(color: Colors.red),
              ),
            ),
          ),
        ),
      ],
    );
  }

  double _getMaxY(List<Map<String, dynamic>> data) {
    if (data.isEmpty) return 100;
    final maxValue = data.map((e) => e['value'] as int).reduce((a, b) => a > b ? a : b);
    if (maxValue == 0) return 100;
    return ((maxValue / 100).ceil() * 10).toDouble() * 10;
  }
}

/// Grafico a torta
class _PersonalPieChart extends ConsumerStatefulWidget {
  const _PersonalPieChart({
    required this.userId,
    required this.period,
    required this.offset,
  });

  final String userId;
  final DashboardPeriod period;
  final int offset;

  @override
  ConsumerState<_PersonalPieChart> createState() => _PersonalPieChartState();
}

class _PersonalPieChartState extends ConsumerState<_PersonalPieChart> {
  int _touchedIndex = -1;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final params = PersonalExpensesParams(
      userId: widget.userId,
      period: widget.period,
      offset: widget.offset,
    );
    final categoryExpensesAsync =
        ref.watch(personalExpensesByCategoryProvider(params));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.pie_chart, color: AppColors.terracotta),
            const SizedBox(width: 8),
            Text(
              'Spese per Categoria',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        categoryExpensesAsync.when(
          data: (categoryTotals) {
            if (categoryTotals.isEmpty) {
              return SizedBox(
                height: 200,
                child: Center(
                  child: Text(
                    'Nessuna spesa personale questo mese',
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              );
            }

            final categories = categoryTotals.entries.toList()
              ..sort((a, b) {
                final totalA = (a.value['personal'] as int) + (a.value['group'] as int);
                final totalB = (b.value['personal'] as int) + (b.value['group'] as int);
                return totalB.compareTo(totalA);
              });

            return Column(
              children: [
                // Pie chart at full width
                SizedBox(
                  height: 200,
                  child: PieChart(
                    PieChartData(
                      pieTouchData: PieTouchData(
                        touchCallback: (event, response) {
                          if (!event.isInterestedForInteractions ||
                              response == null ||
                              response.touchedSection == null) {
                            setState(() => _touchedIndex = -1);
                            return;
                          }

                          final index = response.touchedSection!.touchedSectionIndex;

                          if (event is FlTapUpEvent) {
                            final categoryEntry = categories[index];
                            final categoryId = categoryEntry.key;
                            final categoryName = categoryEntry.value['name'] as String;

                            _showExpensesBottomSheet(
                              context,
                              categoryId,
                              categoryName,
                            );
                          }

                          setState(() => _touchedIndex = index);
                        },
                      ),
                      borderData: FlBorderData(show: false),
                      sectionsSpace: 2,
                      centerSpaceRadius: 40,
                      sections: _buildSections(categories),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                // Horizontal scrollable legend
                _buildHorizontalLegend(categories, theme),
              ],
            );
          },
          loading: () => const SizedBox(
            height: 200,
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (error, _) => SizedBox(
            height: 200,
            child: Center(
              child: Text(
                'Errore caricamento dati',
                style: theme.textTheme.bodySmall?.copyWith(color: Colors.red),
              ),
            ),
          ),
        ),
      ],
    );
  }

  List<PieChartSectionData> _buildSections(
      List<MapEntry<String, dynamic>> categories) {
    final colors = [
      AppColors.terracotta,
      const Color(0xFF8B7355),
      const Color(0xFFD4A373),
      const Color(0xFFA0826D),
      const Color(0xFF6F4E37),
      const Color(0xFFB08968),
    ];

    return categories.asMap().entries.map((entry) {
      final index = entry.key;
      final categoryData = entry.value;
      final personal = categoryData.value['personal'] as int;
      final group = categoryData.value['group'] as int;
      final total = personal + group;
      final isTouched = index == _touchedIndex;

      return PieChartSectionData(
        color: colors[index % colors.length],
        value: total.toDouble(),
        title: '',
        radius: isTouched ? 65 : 55,
        titleStyle: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: Colors.white,
        ),
      );
    }).toList();
  }

  Widget _buildHorizontalLegend(
      List<MapEntry<String, dynamic>> categories, ThemeData theme) {
    final colors = [
      AppColors.terracotta,
      const Color(0xFF8B7355),
      const Color(0xFFD4A373),
      const Color(0xFFA0826D),
      const Color(0xFF6F4E37),
      const Color(0xFFB08968),
    ];

    return SizedBox(
      height: 85,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: categories.length,
        separatorBuilder: (context, index) => const SizedBox(width: 12),
        itemBuilder: (context, index) {
          final categoryData = categories[index];
          final categoryName = categoryData.value['name'] as String;
          final personal = categoryData.value['personal'] as int;
          final group = categoryData.value['group'] as int;
          final total = personal + group;
          final color = colors[index % colors.length];

          return Container(
            constraints: const BoxConstraints(
              minWidth: 100,
              maxWidth: 140,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              border: Border.all(
                color: color.withOpacity(0.3),
                width: 1.5,
              ),
              borderRadius: BorderRadius.circular(8),
              color: color.withOpacity(0.1),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        categoryName,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  CurrencyUtils.formatCents(total),
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (group > 0)
                  Text(
                    '(${CurrencyUtils.formatCents(group)} gruppo)',
                    style: TextStyle(
                      fontSize: 10,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildLegend(
      List<MapEntry<String, dynamic>> categories, ThemeData theme) {
    return ListView.builder(
      shrinkWrap: true,
      itemCount: categories.length,
      itemBuilder: (context, index) {
        final categoryData = categories[index];
        final categoryName = categoryData.value['name'] as String;
        final personal = categoryData.value['personal'] as int;
        final group = categoryData.value['group'] as int;
        final total = personal + group;

        final colors = [
          AppColors.terracotta,
          const Color(0xFF8B7355),
          const Color(0xFFD4A373),
          const Color(0xFFA0826D),
          const Color(0xFF6F4E37),
          const Color(0xFFB08968),
        ];

        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: [
              Container(
                width: 16,
                height: 16,
                decoration: BoxDecoration(
                  color: colors[index % colors.length],
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      categoryName,
                      style: theme.textTheme.bodySmall,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      CurrencyUtils.formatCents(total),
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showExpensesBottomSheet(
    BuildContext context,
    String categoryId,
    String categoryName,
  ) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollController) {
          return _CategoryExpensesSheet(
            categoryId: categoryId,
            categoryName: categoryName,
            userId: widget.userId,
            scrollController: scrollController,
          );
        },
      ),
    );
  }
}

/// Bottom sheet con elenco spese della categoria
class _CategoryExpensesSheet extends ConsumerWidget {
  const _CategoryExpensesSheet({
    required this.categoryId,
    required this.categoryName,
    required this.userId,
    required this.scrollController,
  });

  final String categoryId;
  final String categoryName;
  final String userId;
  final ScrollController scrollController;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final expensesAsync = ref.watch(expensesByCategoryProvider(
      (userId: userId, categoryId: categoryId),
    ));

    return Container(
      decoration: BoxDecoration(
        color: theme.scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Column(
        children: [
          // Handle
          Container(
            margin: const EdgeInsets.only(top: 8),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          // Header
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        categoryName,
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Spese del mese',
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          // Lista spese
          Expanded(
            child: expensesAsync.when(
              data: (expenses) {
                if (expenses.isEmpty) {
                  return Center(
                    child: Text(
                      'Nessuna spesa in questa categoria',
                      style: theme.textTheme.bodyMedium,
                    ),
                  );
                }

                return ListView.separated(
                  controller: scrollController,
                  padding: const EdgeInsets.all(16),
                  itemCount: expenses.length,
                  separatorBuilder: (context, index) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final expense = expenses[index];
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: CircleAvatar(
                        backgroundColor: AppColors.terracotta.withOpacity(0.1),
                        child: Icon(
                          expense.isGroupExpense ? Icons.group : Icons.person,
                          color: AppColors.terracotta,
                        ),
                      ),
                      title: Row(
                        children: [
                          Expanded(
                            child: Text(
                              expense.merchant ?? 'Spesa',
                              style: theme.textTheme.bodyLarge,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            DateFormat('d MMM yyyy', 'it').format(expense.date),
                            style: theme.textTheme.bodySmall,
                          ),
                          if (expense.categoryName != null)
                            Text(
                              expense.categoryName!,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: Colors.grey.shade600,
                                fontSize: 11,
                              ),
                            ),
                        ],
                      ),
                      trailing: Text(
                        expense.formattedAmount,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      onTap: () {
                        Navigator.pop(context);
                        context.push('/expense/${expense.id}');
                      },
                    );
                  },
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) => Center(
                child: Text(
                  'Errore caricamento spese',
                  style: theme.textTheme.bodyMedium?.copyWith(color: Colors.red),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Widget per grafico a torta delle categorie
class _CategoryPieChart extends StatelessWidget {
  const _CategoryPieChart({
    required this.categories,
    required this.color,
  });

  final List<Map<String, dynamic>> categories;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final totalAmount = categories.fold<int>(
      0,
      (sum, cat) => sum + (cat['total'] as int),
    );

    if (totalAmount == 0) {
      return const Center(
        child: Text('Nessun dato disponibile'),
      );
    }

    // Prendi solo le top 5 categorie
    final topCategories = categories.take(5).toList();

    return PieChart(
      PieChartData(
        sections: topCategories.asMap().entries.map((entry) {
          final index = entry.key;
          final category = entry.value;
          final categoryTotal = category['total'] as int;
          final percentage = (categoryTotal / totalAmount * 100);

          // Colori diversi per ogni categoria
          final colors = [
            color,
            color.withOpacity(0.8),
            color.withOpacity(0.6),
            color.withOpacity(0.4),
            color.withOpacity(0.3),
          ];

          return PieChartSectionData(
            color: colors[index % colors.length],
            value: categoryTotal.toDouble(),
            title: '${percentage.toStringAsFixed(1)}%',
            radius: 80,
            titleStyle: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          );
        }).toList(),
        sectionsSpace: 2,
        centerSpaceRadius: 0,
      ),
    );
  }
}

/// Bottom sheet con elenco spese di gruppo per categoria
class _GroupCategoryExpensesSheet extends ConsumerWidget {
  const _GroupCategoryExpensesSheet({
    required this.categoryId,
    required this.categoryName,
    required this.groupId,
    this.memberId,
    required this.period,
    required this.offset,
    required this.scrollController,
  });

  final String categoryId;
  final String categoryName;
  final String groupId;
  final String? memberId; // Opzionale: filtra per membro
  final DashboardPeriod period;
  final int offset;
  final ScrollController scrollController;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final params = GroupCategoryExpensesParams(
      groupId: groupId,
      categoryId: categoryId,
      period: period,
      offset: offset,
      memberId: memberId,
    );
    final expensesAsync = ref.watch(groupCategoryExpensesProvider(params));

    return Container(
      decoration: BoxDecoration(
        color: theme.scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Column(
        children: [
          // Handle
          Container(
            margin: const EdgeInsets.only(top: 8),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          // Header
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.group, color: Colors.blue, size: 20),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              categoryName,
                              style: theme.textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Spese di gruppo del mese',
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          // Lista spese
          Expanded(
            child: expensesAsync.when(
              data: (expenses) {
                if (expenses.isEmpty) {
                  return Center(
                    child: Text(
                      'Nessuna spesa di gruppo in questa categoria',
                      style: theme.textTheme.bodyMedium,
                    ),
                  );
                }

                return ListView.separated(
                  controller: scrollController,
                  padding: const EdgeInsets.all(16),
                  itemCount: expenses.length,
                  separatorBuilder: (context, index) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final expense = expenses[index];
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: CircleAvatar(
                        backgroundColor: Colors.blue.withOpacity(0.1),
                        child: Icon(
                          Icons.group,
                          color: Colors.blue,
                        ),
                      ),
                      title: Row(
                        children: [
                          Expanded(
                            child: Text(
                              expense.merchant ?? 'Spesa',
                              style: theme.textTheme.bodyLarge,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            DateFormat('d MMM yyyy', 'it').format(expense.date),
                            style: theme.textTheme.bodySmall,
                          ),
                          if (expense.paidByName != null)
                            Text(
                              'Pagato da: ${expense.paidByName}',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: Colors.grey.shade600,
                                fontSize: 11,
                              ),
                            ),
                        ],
                      ),
                      trailing: Text(
                        expense.formattedAmount,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      onTap: () {
                        Navigator.pop(context);
                        context.push('/expense/${expense.id}');
                      },
                    );
                  },
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) => Center(
                child: Text(
                  'Errore caricamento spese',
                  style: theme.textTheme.bodyMedium?.copyWith(color: Colors.red),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Bottom sheet con elenco spese personali per categoria
class _PersonalCategoryExpensesSheet extends ConsumerWidget {
  const _PersonalCategoryExpensesSheet({
    required this.categoryId,
    required this.categoryName,
    required this.userId,
    required this.period,
    required this.offset,
    required this.scrollController,
  });

  final String categoryId;
  final String categoryName;
  final String userId;
  final DashboardPeriod period;
  final int offset;
  final ScrollController scrollController;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final params = PersonalCategoryExpensesParams(
      userId: userId,
      categoryId: categoryId,
      period: period,
      offset: offset,
    );
    final expensesAsync = ref.watch(personalCategoryExpensesProvider(params));

    return Container(
      decoration: BoxDecoration(
        color: theme.scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Column(
        children: [
          // Handle
          Container(
            margin: const EdgeInsets.only(top: 8),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          // Header
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.person, color: AppColors.terracotta, size: 20),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              categoryName,
                              style: theme.textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Spese personali del mese',
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          // Lista spese
          Expanded(
            child: expensesAsync.when(
              data: (expenses) {
                if (expenses.isEmpty) {
                  return Center(
                    child: Text(
                      'Nessuna spesa personale in questa categoria',
                      style: theme.textTheme.bodyMedium,
                    ),
                  );
                }

                return ListView.separated(
                  controller: scrollController,
                  padding: const EdgeInsets.all(16),
                  itemCount: expenses.length,
                  separatorBuilder: (context, index) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final expense = expenses[index];
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: CircleAvatar(
                        backgroundColor: AppColors.terracotta.withOpacity(0.1),
                        child: Icon(
                          Icons.person,
                          color: AppColors.terracotta,
                        ),
                      ),
                      title: Row(
                        children: [
                          Expanded(
                            child: Text(
                              expense.merchant ?? 'Spesa',
                              style: theme.textTheme.bodyLarge,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            DateFormat('d MMM yyyy', 'it').format(expense.date),
                            style: theme.textTheme.bodySmall,
                          ),
                        ],
                      ),
                      trailing: Text(
                        expense.formattedAmount,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      onTap: () {
                        Navigator.pop(context);
                        context.push('/expense/${expense.id}');
                      },
                    );
                  },
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) => Center(
                child: Text(
                  'Errore caricamento spese',
                  style: theme.textTheme.bodyMedium?.copyWith(color: Colors.red),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
