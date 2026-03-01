import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../shared/widgets/error_display.dart';
import '../../../../shared/widgets/loading_indicator.dart';
import '../../../../shared/widgets/primary_button.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../expenses/domain/entities/expense_entity.dart';
import '../../../expenses/presentation/providers/expense_provider.dart';
import '../providers/group_provider.dart';
import '../widgets/invite_code_card.dart';
import '../widgets/member_list_item.dart';

/// Screen showing group details, members, and admin actions.
class GroupDetailsScreen extends ConsumerStatefulWidget {
  const GroupDetailsScreen({super.key});

  @override
  ConsumerState<GroupDetailsScreen> createState() => _GroupDetailsScreenState();
}

class _GroupDetailsScreenState extends ConsumerState<GroupDetailsScreen> {
  @override
  void initState() {
    super.initState();
    // Load group data when screen opens
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(groupProvider.notifier).loadCurrentGroup();
      // Filter expenses to show only group expenses
      ref.read(expenseListProvider.notifier).setFilterIsGroupExpense(true);
    });
  }

  @override
  void dispose() {
    // Clear group expense filter when leaving screen
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(expenseListProvider.notifier).setFilterIsGroupExpense(null);
    });
    super.dispose();
  }

  Future<void> _handleLeaveGroup() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Lascia il gruppo'),
        content: const Text(
          'Sei sicuro di voler lasciare il gruppo? Le tue spese rimarranno visibili agli altri membri.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Annulla'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Lascia'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final success = await ref.read(groupProvider.notifier).leaveGroup();
      if (mounted && success) {
        await ref.read(authProvider.notifier).refreshUser();
        if (mounted) {
          context.go('/no-group');
        }
      }
    }
  }

  Future<void> _handleDeleteGroup() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Elimina il gruppo'),
        content: const Text(
          'Sei sicuro di voler eliminare il gruppo? Questa azione non può essere annullata.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Annulla'),
          ),
          TextButton(
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Elimina'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final success = await ref.read(groupProvider.notifier).deleteGroup();
      if (mounted && success) {
        await ref.read(authProvider.notifier).refreshUser();
        if (mounted) {
          context.go('/no-group');
        }
      }
    }
  }

  Future<void> _handleRemoveMember(String userId, String displayName) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rimuovi membro'),
        content: Text(
          'Sei sicuro di voler rimuovere $displayName dal gruppo?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Annulla'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Rimuovi'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await ref.read(groupProvider.notifier).removeMember(userId: userId);
    }
  }

  Future<void> _handleGenerateInvite() async {
    await ref.read(groupProvider.notifier).createInvite();
  }

  @override
  Widget build(BuildContext context) {
    final groupState = ref.watch(groupProvider);
    final currentUser = ref.watch(currentUserProvider);
    final isAdmin = ref.watch(isGroupAdminProvider);
    final theme = Theme.of(context);

    if (groupState.isLoading && groupState.group == null) {
      return const Scaffold(
        body: LoadingIndicator(message: 'Caricamento gruppo...'),
      );
    }

    if (groupState.group == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Gruppo')),
        body: ErrorDisplay(
          message: 'Gruppo non trovato',
          onRetry: () => ref.read(groupProvider.notifier).loadCurrentGroup(),
        ),
      );
    }

    final group = groupState.group!;
    final members = groupState.members;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/'),
        ),
        title: Text(group.name),
        actions: [
          if (isAdmin)
            IconButton(
              icon: const Icon(Icons.edit),
              onPressed: () => _showEditNameDialog(context, group.name),
            ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          await ref.read(groupProvider.notifier).loadCurrentGroup();
        },
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Error message
            if (groupState.hasError && groupState.errorMessage != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: InlineError(message: groupState.errorMessage!),
              ),

            // Group spending summary
            _buildGroupSpendingSummary(ref, theme),
            const SizedBox(height: 24),

            // Invite code section (admin only)
            if (isAdmin) ...[
              Text(
                'Codice invito',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              if (groupState.invite != null)
                InviteCodeCard(
                  invite: groupState.invite!,
                  onRefresh: _handleGenerateInvite,
                )
              else
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        Text(
                          'Nessun codice invito attivo',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 12),
                        SecondaryButton(
                          onPressed: _handleGenerateInvite,
                          label: 'Genera codice',
                          icon: Icons.add,
                          isLoading: groupState.isLoading,
                        ),
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: 24),
            ],

            // Members section with spending
            _buildMembersSection(ref, members, currentUser, isAdmin, theme),
            const SizedBox(height: 24),

            // Group expenses section (Feature request: show all members' expenses)
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Spese del gruppo',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                TextButton.icon(
                  onPressed: () => context.go('/expenses?tab=1'),
                  icon: const Icon(Icons.arrow_forward, size: 18),
                  label: const Text('Vedi tutte'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            _buildGroupExpensesSection(ref, theme),
            const SizedBox(height: 32),

            // Actions section
            if (isAdmin && members.length == 1) ...[
              DangerButton(
                onPressed: _handleDeleteGroup,
                label: 'Elimina gruppo',
                icon: Icons.delete_forever,
                isLoading: groupState.isLoading,
              ),
            ] else ...[
              SecondaryButton(
                onPressed: _handleLeaveGroup,
                label: 'Lascia il gruppo',
                icon: Icons.exit_to_app,
                isLoading: groupState.isLoading,
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// Build group expenses section showing recent expenses from all members
  Widget _buildGroupExpensesSection(WidgetRef ref, ThemeData theme) {
    final expenseListState = ref.watch(expenseListProvider);
    final groupMembers = ref.watch(groupMembersProvider);

    // Create member name lookup map
    final memberNames = Map<String, String>.fromEntries(
      groupMembers.map((m) => MapEntry(m.userId, m.displayName)),
    );

    if (expenseListState.isLoading && expenseListState.expenses.isEmpty) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }

    if (expenseListState.hasError) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            'Errore nel caricamento delle spese: ${expenseListState.errorMessage}',
            style: TextStyle(color: theme.colorScheme.error),
          ),
        ),
      );
    }

    final expenses = expenseListState.expenses.take(5).toList();

    if (expenses.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            children: [
              Icon(
                Icons.receipt_long_outlined,
                size: 48,
                color: theme.colorScheme.onSurfaceVariant.withOpacity(0.5),
              ),
              const SizedBox(height: 12),
              Text(
                'Nessuna spesa ancora',
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Card(
      child: Column(
        children: [
          for (int i = 0; i < expenses.length; i++) ...[
            _buildExpenseItem(expenses[i], memberNames, theme),
            if (i < expenses.length - 1) const Divider(height: 1),
          ],
        ],
      ),
    );
  }

  /// Build individual expense list item
  Widget _buildExpenseItem(
    ExpenseEntity expense,
    Map<String, String> memberNames,
    ThemeData theme,
  ) {
    // Use paidBy to show who actually paid for the expense
    final paidByName = expense.paidByName ??
                       (expense.paidBy != null ? memberNames[expense.paidBy!] : null) ??
                       'Sconosciuto';

    return ListTile(
      leading: CircleAvatar(
        backgroundColor: theme.colorScheme.primaryContainer,
        child: Icon(
          Icons.receipt,
          color: theme.colorScheme.onPrimaryContainer,
          size: 20,
        ),
      ),
      title: Row(
        children: [
          Expanded(
            child: Text(
              expense.categoryName ?? 'Senza categoria',
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Text(
            '€${expense.amount.toStringAsFixed(2)}',
            style: theme.textTheme.bodyLarge?.copyWith(
              fontWeight: FontWeight.bold,
              color: theme.colorScheme.primary,
            ),
          ),
        ],
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 4),
          Row(
            children: [
              Icon(
                Icons.person,
                size: 14,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 4),
              Text(
                paidByName,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: 12),
              Icon(
                Icons.calendar_today,
                size: 14,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 4),
              Text(
                _formatDate(expense.date),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ],
      ),
      onTap: () => context.go('/expense/${expense.id}'),
    );
  }

  /// Format date for display
  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final expenseDate = DateTime(date.year, date.month, date.day);

    if (expenseDate == today) {
      return 'Oggi';
    } else if (expenseDate == yesterday) {
      return 'Ieri';
    } else {
      return '${date.day}/${date.month}/${date.year}';
    }
  }

  /// Build group spending summary card
  Widget _buildGroupSpendingSummary(WidgetRef ref, ThemeData theme) {
    final expenseListState = ref.watch(expenseListProvider);

    // Calculate total group spending
    final totalSpending = expenseListState.expenses
        .where((e) => e.isGroupExpense)
        .fold<double>(0, (sum, expense) => sum + expense.amount);

    return Card(
      color: theme.colorScheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.account_balance_wallet,
                  color: theme.colorScheme.onPrimaryContainer,
                  size: 24,
                ),
                const SizedBox(width: 12),
                Text(
                  'Spese totali del gruppo',
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: theme.colorScheme.onPrimaryContainer,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              '€${totalSpending.toStringAsFixed(2)}',
              style: theme.textTheme.displaySmall?.copyWith(
                color: theme.colorScheme.onPrimaryContainer,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '${expenseListState.expenses.where((e) => e.isGroupExpense).length} spese registrate',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onPrimaryContainer.withOpacity(0.8),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Build members section with individual spending
  Widget _buildMembersSection(
    WidgetRef ref,
    List<dynamic> members,
    dynamic currentUser,
    bool isAdmin,
    ThemeData theme,
  ) {
    final expenseListState = ref.watch(expenseListProvider);

    // Calculate spending per member using paidBy to attribute expenses correctly
    final spendingByMember = <String, double>{};
    for (final expense in expenseListState.expenses) {
      if (expense.isGroupExpense && expense.paidBy != null) {
        spendingByMember[expense.paidBy!] =
            (spendingByMember[expense.paidBy!] ?? 0) + expense.amount;
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Membri (${members.length})',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Card(
          child: Column(
            children: [
              for (int i = 0; i < members.length; i++) ...[
                _buildMemberItemWithSpending(
                  members[i],
                  members[i].userId == currentUser?.id,
                  isAdmin && members[i].userId != currentUser?.id,
                  spendingByMember[members[i].userId] ?? 0,
                  theme,
                ),
                if (i < members.length - 1) const Divider(height: 1),
              ],
            ],
          ),
        ),
      ],
    );
  }

  /// Build member list item with spending total
  Widget _buildMemberItemWithSpending(
    dynamic member,
    bool isCurrentUser,
    bool canRemove,
    double totalSpending,
    ThemeData theme,
  ) {
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: member.isAdmin
            ? theme.colorScheme.primaryContainer
            : theme.colorScheme.secondaryContainer,
        child: Icon(
          member.isAdmin ? Icons.admin_panel_settings : Icons.person,
          color: member.isAdmin
              ? theme.colorScheme.onPrimaryContainer
              : theme.colorScheme.onSecondaryContainer,
        ),
      ),
      title: Row(
        children: [
          Expanded(
            child: Text(
              member.displayName,
              style: theme.textTheme.bodyLarge?.copyWith(
                fontWeight: isCurrentUser ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ),
          // Show spending total
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '€${totalSpending.toStringAsFixed(2)}',
                style: theme.textTheme.bodyLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.primary,
                ),
              ),
              Text(
                'spese',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ],
      ),
      subtitle: Row(
        children: [
          if (member.isAdmin)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                'Admin',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          if (isCurrentUser) ...[
            if (member.isAdmin) const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: theme.colorScheme.secondary.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                'Tu',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.secondary,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ],
      ),
      trailing: canRemove
          ? IconButton(
              icon: const Icon(Icons.person_remove),
              onPressed: () => _handleRemoveMember(
                member.userId,
                member.displayName,
              ),
              tooltip: 'Rimuovi membro',
            )
          : null,
    );
  }

  Future<void> _showEditNameDialog(BuildContext context, String currentName) async {
    final controller = TextEditingController(text: currentName);

    final newName = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Modifica nome gruppo'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'Nome del gruppo',
          ),
          textCapitalization: TextCapitalization.words,
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Annulla'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            child: const Text('Salva'),
          ),
        ],
      ),
    );

    if (newName != null && newName.isNotEmpty && newName != currentName) {
      await ref.read(groupProvider.notifier).updateGroupName(name: newName);
    }

    controller.dispose();
  }
}
