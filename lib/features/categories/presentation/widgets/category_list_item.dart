import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/expense_category_entity.dart';
import '../providers/category_actions_provider.dart';
import 'category_form_dialog.dart';

/// List item widget for displaying a category with edit/delete actions
class CategoryListItem extends ConsumerWidget {
  const CategoryListItem({
    super.key,
    required this.category,
    required this.groupId,
  });

  final ExpenseCategoryEntity category;
  final String groupId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    return Card(
      margin: EdgeInsets.zero,
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: theme.colorScheme.primaryContainer,
          child: Icon(
            category.getIcon(),
            color: theme.colorScheme.onPrimaryContainer,
            size: 20,
          ),
        ),
        title: Text(
          category.name,
          style: theme.textTheme.bodyLarge?.copyWith(
            fontWeight: FontWeight.w500,
          ),
        ),
        subtitle: category.expenseCount != null
            ? Text(
                '${category.expenseCount} expense${category.expenseCount == 1 ? '' : 's'}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              )
            : null,
        trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (category.isDefault)
                    Chip(
                      label: const Text('Default'),
                      visualDensity: VisualDensity.compact,
                      side: BorderSide.none,
                      backgroundColor: theme.colorScheme.surfaceContainerHighest,
                    ),
                  Semantics(
                    button: true,
                    enabled: true,
                    label: 'Edit ${category.name} category icon',
                    child: IconButton(
                      icon: const Icon(Icons.edit_outlined),
                      onPressed: () => _showEditDialog(context, ref),
                      tooltip: category.isDefault ? 'Edit icon' : 'Edit category',
                    ),
                  ),
                  if (!category.isDefault)
                    Semantics(
                      button: true,
                      enabled: true,
                      label: 'Delete ${category.name} category',
                      child: IconButton(
                        icon: Icon(
                          Icons.delete_outline,
                          color: theme.colorScheme.error,
                        ),
                        onPressed: () => _handleDelete(context, ref),
                        tooltip: 'Delete category',
                      ),
                    ),
                ],
              ),
      ),
    );
  }

  void _showEditDialog(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (context) => CategoryFormDialog(
        groupId: groupId,
        categoryToEdit: category,
      ),
    );
  }

  Future<void> _handleDelete(BuildContext context, WidgetRef ref) async {
    // First, get the expense count
    final actions = ref.read(categoryActionsProvider);
    final expenseCount = await actions.getCategoryExpenseCount(
      categoryId: category.id,
    );

    if (!context.mounted) return;

    if (expenseCount != null && expenseCount > 0) {
      // Show error - cannot delete category with expenses
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Cannot Delete Category'),
          content: Text(
            'This category has $expenseCount expense${expenseCount == 1 ? '' : 's'}. '
            'Please reassign all expenses to another category before deleting.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      return;
    }

    // Show confirmation dialog
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Category'),
        content: Text(
          'Are you sure you want to delete "${category.name}"? This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true && context.mounted) {
      // Delete the category
      final success = await actions.deleteCategory(
        groupId: groupId,
        categoryId: category.id,
      );

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              success
                  ? 'Category deleted successfully'
                  : 'Failed to delete category',
            ),
          ),
        );
      }
    }
  }
}
