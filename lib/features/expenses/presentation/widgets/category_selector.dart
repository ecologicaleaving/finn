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
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final authState = ref.watch(authProvider);
    final groupId = authState.user?.groupId;

    if (groupId == null) {
      return const Text('Nessun gruppo disponibile');
    }

    final categoryState = ref.watch(categoryProvider(groupId));

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
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                category.getIcon(),
                size: 18,
                color: isSelected
                    ? theme.colorScheme.onPrimaryContainer
                    : theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 6),
              Text(
                category.name,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: isSelected
                      ? theme.colorScheme.onPrimaryContainer
                      : theme.colorScheme.onSurfaceVariant,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
            ],
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

    final selectedCategory = categoryState.categories.firstWhere(
      (cat) => cat.id == selectedCategoryId,
      orElse: () => categoryState.categories.first,
    );

    return InkWell(
      onTap: enabled
          ? () => _showCategoryGridDialog(context, ref, categoryState.categories)
          : null,
      borderRadius: BorderRadius.circular(12),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: 'Categoria',
          prefixIcon: Icon(selectedCategory.getIcon()),
          suffixIcon: const Icon(Icons.arrow_drop_down),
          enabled: enabled,
        ),
        child: Text(selectedCategory.name),
      ),
    );
  }

  void _showCategoryGridDialog(
    BuildContext context,
    WidgetRef ref,
    List<ExpenseCategoryEntity> categories,
  ) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.5,
        maxChildSize: 0.9,
        expand: false,
        builder: (context, scrollController) => Container(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              // Handle bar
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Text(
                'Seleziona Categoria',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 16),
              Expanded(
                child: GridView.builder(
                  controller: scrollController,
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    childAspectRatio: 0.85,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                  ),
                  itemCount: categories.length,
                  itemBuilder: (context, index) {
                    final category = categories[index];
                    final isSelected = category.id == selectedCategoryId;

                    return _CategoryCard(
                      category: category,
                      isSelected: isSelected,
                      onTap: () {
                        onCategorySelected(category.id);
                        Navigator.pop(context);
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

}

class _CategoryCard extends StatelessWidget {
  const _CategoryCard({
    required this.category,
    required this.isSelected,
    required this.onTap,
  });

  final ExpenseCategoryEntity category;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      elevation: isSelected ? 4 : 1,
      color: isSelected
          ? theme.colorScheme.primaryContainer
          : theme.colorScheme.surface,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              category.getIcon(),
              size: 40,
              color: isSelected
                  ? theme.colorScheme.primary
                  : theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                category.name,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: isSelected
                      ? theme.colorScheme.onPrimaryContainer
                      : theme.colorScheme.onSurfaceVariant,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                ),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
