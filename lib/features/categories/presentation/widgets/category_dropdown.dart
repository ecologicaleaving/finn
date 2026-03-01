// Widget: Category Dropdown with MRU Ordering
// Feature 001: Widget Category Fixes - Task T050-T051
// User Story 3: Enhanced Category Selector with MRU ordering

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../shared/widgets/custom_text_field.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../domain/entities/expense_category_entity.dart';
import '../providers/category_provider.dart';

/// Dropdown for selecting a category with MRU (Most Recently Used) ordering.
///
/// This widget displays categories ordered by user's most recent usage,
/// with virgin (never used) categories appearing last alphabetically.
///
/// Features:
/// - MRU ordering from database
/// - Visual distinction for default categories
/// - Optional virgin category indicator
/// - Consistent styling with app forms
/// - Integrates with Riverpod MRU provider
class CategoryDropdownMRU extends ConsumerWidget {
  const CategoryDropdownMRU({
    super.key,
    required this.value,
    required this.onChanged,
    this.label = 'Categoria',
    this.hint = 'Seleziona una categoria',
    this.validator,
    this.enabled = true,
    this.errorText,
    this.helperText,
    this.showVirginIndicator = false,
  });

  final String? value;
  final void Function(String?)? onChanged;
  final String label;
  final String hint;
  final String? Function(String?)? validator;
  final bool enabled;
  final String? errorText;
  final String? helperText;

  /// If true, shows a visual indicator for virgin (never used) categories.
  final bool showVirginIndicator;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authProvider);
    final groupId = authState.user?.groupId;
    final userId = authState.user?.id;

    if (groupId == null || userId == null) {
      return Text(
        'Errore: utente non autenticato',
        style: TextStyle(color: Theme.of(context).colorScheme.error),
      );
    }

    final mruState = ref.watch(categoryMRUProvider((groupId: groupId, userId: userId)));

    if (mruState.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (mruState.errorMessage != null) {
      return Text(
        mruState.errorMessage!,
        style: TextStyle(color: Theme.of(context).colorScheme.error),
      );
    }

    if (mruState.categories.isEmpty) {
      return const Text('Nessuna categoria disponibile');
    }

    return CategoryDropdownSimple(
      value: value,
      categories: mruState.categories,
      onChanged: onChanged,
      label: label,
      hint: hint,
      validator: validator,
      enabled: enabled,
      errorText: errorText,
      helperText: helperText,
      showVirginIndicator: showVirginIndicator,
    );
  }
}

/// Simple category dropdown without provider integration.
///
/// Use this when you already have the categories list,
/// or use CategoryDropdownMRU for automatic MRU ordering.
class CategoryDropdownSimple extends StatelessWidget {
  const CategoryDropdownSimple({
    super.key,
    required this.value,
    required this.categories,
    required this.onChanged,
    this.label = 'Categoria',
    this.hint = 'Seleziona una categoria',
    this.validator,
    this.enabled = true,
    this.errorText,
    this.helperText,
    this.showVirginIndicator = false,
  });

  final String? value;
  final List<ExpenseCategoryEntity> categories;
  final void Function(String?)? onChanged;
  final String label;
  final String hint;
  final String? Function(String?)? validator;
  final bool enabled;
  final String? errorText;
  final String? helperText;

  /// If true, shows a visual indicator for virgin (never used) categories.
  final bool showVirginIndicator;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return DropdownField<ExpenseCategoryEntity>(
      value: categories.where((c) => c.id == value).firstOrNull,
      items: categories,
      onChanged: (category) => onChanged?.call(category?.id),
      label: label,
      hint: hint,
      prefixIcon: Icons.category,
      validator: (category) => validator?.call(category?.id),
      enabled: enabled,
      errorText: errorText,
      helperText: helperText,
      displayStringForItem: (category) => category.name,
      itemBuilder: (category) {
        return Row(
          children: [
            // Category name
            Expanded(
              child: Text(
                category.name,
                style: theme.textTheme.bodyLarge,
              ),
            ),

            // Visual indicators
            if (category.isDefault)
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: Icon(
                  Icons.star,
                  size: 16,
                  color: theme.colorScheme.primary.withValues(alpha: 0.7),
                ),
              ),
          ],
        );
      },
    );
  }
}
