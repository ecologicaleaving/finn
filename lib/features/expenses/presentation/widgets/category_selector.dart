import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../categories/domain/entities/expense_category_entity.dart';
import '../../../categories/presentation/providers/category_provider.dart';

/// Widget for selecting expense category from a grid of options loaded from database.
class CategorySelector extends ConsumerStatefulWidget {
  const CategorySelector({
    super.key,
    required this.selectedCategoryId,
    required this.onCategorySelected,
    this.enabled = true,
  });

  final String? selectedCategoryId;
  final ValueChanged<String> onCategorySelected;
  final bool enabled;

  @override
  ConsumerState<CategorySelector> createState() => _CategorySelectorState();
}

class _CategorySelectorState extends ConsumerState<CategorySelector> {
  bool _hasAutoSelected = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final authState = ref.watch(authProvider);
    final groupId = authState.user?.groupId;

    if (groupId == null) {
      return const Text('Nessun gruppo disponibile');
    }

    final categoryState = ref.watch(categoryProvider(groupId));

    // Auto-select first category if none is selected
    if (!_hasAutoSelected &&
        widget.selectedCategoryId == null &&
        categoryState.categories.isNotEmpty) {
      _hasAutoSelected = true;
      final categoryToSelect = categoryState.categories.first.id;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          widget.onCategorySelected(categoryToSelect);
        }
      });
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Label
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(
            'Categoria',
            style: theme.textTheme.titleSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),

        // Category grid
        if (categoryState.isLoading)
          const Center(child: CircularProgressIndicator())
        else if (categoryState.errorMessage != null)
          Text(
            categoryState.errorMessage!,
            style: TextStyle(color: theme.colorScheme.error),
          )
        else if (categoryState.categories.isEmpty)
          const Text('Nessuna categoria disponibile')
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: categoryState.categories.map((category) {
              final isSelected = category.id == widget.selectedCategoryId;

              return _CategoryChip(
                category: category,
                isSelected: isSelected,
                enabled: widget.enabled,
                onTap: () => widget.onCategorySelected(category.id),
              );
            }).toList(),
          ),
      ],
    );
  }
}

class _CategoryChip extends StatelessWidget {
  const _CategoryChip({
    required this.category,
    required this.isSelected,
    required this.enabled,
    required this.onTap,
  });

  final ExpenseCategoryEntity category;
  final bool isSelected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Material(
      color: isSelected
          ? theme.colorScheme.primaryContainer
          : theme.colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: isSelected
                ? Border.all(color: theme.colorScheme.primary, width: 2)
                : null,
          ),
          child: Text(
            category.name,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: isSelected
                  ? theme.colorScheme.onPrimaryContainer
                  : theme.colorScheme.onSurfaceVariant,
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
        ),
      ),
    );
  }
}

/// Compact category selector as a dropdown.
class CategoryDropdown extends ConsumerWidget {
  const CategoryDropdown({
    super.key,
    required this.selectedCategoryId,
    required this.onCategorySelected,
    this.enabled = true,
  });

  final String? selectedCategoryId;
  final ValueChanged<String> onCategorySelected;
  final bool enabled;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authProvider);
    final groupId = authState.user?.groupId;

    if (groupId == null) {
      return const Text('Nessun gruppo disponibile');
    }

    final categoryState = ref.watch(categoryProvider(groupId));

    if (categoryState.isLoading) {
      return const LinearProgressIndicator();
    }

    if (categoryState.errorMessage != null) {
      return Text(categoryState.errorMessage!);
    }

    return DropdownButtonFormField<String>(
      value: selectedCategoryId,
      decoration: const InputDecoration(
        labelText: 'Categoria',
        prefixIcon: Icon(Icons.category_outlined),
      ),
      items: categoryState.categories.map((category) {
        return DropdownMenuItem(
          value: category.id,
          child: Text(category.name),
        );
      }).toList(),
      onChanged: enabled
          ? (value) {
              if (value != null) {
                onCategorySelected(value);
              }
            }
          : null,
    );
  }
}
