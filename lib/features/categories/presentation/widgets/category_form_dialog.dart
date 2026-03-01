import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/services/icon_helper.dart';
import '../../../../shared/widgets/bilingual_icon_picker.dart';
import '../../domain/entities/expense_category_entity.dart';
import '../providers/category_actions_provider.dart';

/// Dialog for creating or editing a category
class CategoryFormDialog extends ConsumerStatefulWidget {
  const CategoryFormDialog({
    super.key,
    required this.groupId,
    this.categoryToEdit,
  });

  final String groupId;
  final ExpenseCategoryEntity? categoryToEdit;

  @override
  ConsumerState<CategoryFormDialog> createState() => _CategoryFormDialogState();
}

class _CategoryFormDialogState extends ConsumerState<CategoryFormDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  bool _isSubmitting = false;
  String? _errorMessage;
  IconData? _selectedIcon;

  bool get _isEditing => widget.categoryToEdit != null;
  bool get _isDefaultCategory => widget.categoryToEdit?.isDefault ?? false;

  @override
  void initState() {
    super.initState();
    if (_isEditing) {
      _nameController.text = widget.categoryToEdit!.name;
      _selectedIcon = widget.categoryToEdit!.getIcon();
    }
    // Listen to name changes for smart icon suggestions
    _nameController.addListener(_handleNameChange);
  }

  void _handleNameChange() {
    if (!_isEditing && _nameController.text.isNotEmpty) {
      // Only auto-suggest for new categories, not when editing
      final suggestedIconName = BilingualIconPicker.getSuggestedIconName(
        _nameController.text,
      );
      final suggestedIcon = BilingualIconPicker.getIconFromName(suggestedIconName);

      if (suggestedIcon != null && _selectedIcon == null) {
        setState(() {
          _selectedIcon = suggestedIcon;
        });
      }
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _handleSubmit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    try {
      final actions = ref.read(categoryActionsProvider);
      final name = _nameController.text.trim();

      // Check if name already exists (skip for default categories since we're only changing icon)
      if (!_isDefaultCategory) {
        final exists = await actions.categoryNameExists(
          groupId: widget.groupId,
          name: name,
          excludeCategoryId: _isEditing ? widget.categoryToEdit!.id : null,
        );

        if (exists) {
          setState(() {
            _errorMessage = 'A category with this name already exists';
            _isSubmitting = false;
          });
          return;
        }
      }

      final iconName = _selectedIcon != null
          ? IconHelper.getNameFromIcon(_selectedIcon!)
          : null;

      ExpenseCategoryEntity? result;

      if (_isEditing) {
        if (_isDefaultCategory) {
          // Default category: only update icon
          print('🔄 Updating default category icon: ${widget.categoryToEdit!.id}');
          print('   Name: ${widget.categoryToEdit!.name}');
          print('   Old icon: ${widget.categoryToEdit!.iconName}');
          print('   New icon: $iconName');

          if (iconName != null && widget.categoryToEdit!.iconName != iconName) {
            result = await actions.updateCategoryIcon(
              groupId: widget.groupId,
              categoryId: widget.categoryToEdit!.id,
              iconName: iconName,
            );
            print('   Icon update result: ${result != null ? "SUCCESS" : "FAILED"}');
          } else {
            // No icon change, return the existing category
            result = widget.categoryToEdit;
          }
        } else {
          // Custom category: update name and icon
          print('🔄 Updating category: ${widget.categoryToEdit!.id}');
          print('   Old name: ${widget.categoryToEdit!.name}');
          print('   New name: $name');
          print('   Old icon: ${widget.categoryToEdit!.iconName}');
          print('   New icon: $iconName');

          // Update category name first
          result = await actions.updateCategory(
            groupId: widget.groupId,
            categoryId: widget.categoryToEdit!.id,
            name: name,
          );

          print('   Name update result: ${result != null ? "SUCCESS" : "FAILED"}');

          // If icon changed, update it separately
          if (result != null && iconName != null) {
            final iconChanged = widget.categoryToEdit!.iconName != iconName;
            print('   Icon changed: $iconChanged');
            if (iconChanged) {
              result = await actions.updateCategoryIcon(
                groupId: widget.groupId,
                categoryId: widget.categoryToEdit!.id,
                iconName: iconName,
              );
              print('   Icon update result: ${result != null ? "SUCCESS" : "FAILED"}');
            }
          }
        }
      } else {
        print('✨ Creating new category: $name with icon: $iconName');
        // Create new category with icon
        result = await actions.createCategory(
          groupId: widget.groupId,
          name: name,
          iconName: iconName,
        );
        print('   Create result: ${result != null ? "SUCCESS" : "FAILED"}');
      }

      if (mounted) {
        if (result != null) {
          print('✅ Operation successful!');
          Navigator.of(context).pop();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                _isDefaultCategory
                    ? 'Category icon updated successfully'
                    : _isEditing
                        ? 'Category updated successfully'
                        : 'Category created successfully',
              ),
            ),
          );
        } else {
          print('❌ Operation failed - result is null');
          setState(() {
            _errorMessage = _isDefaultCategory
                ? 'Failed to update category icon'
                : _isEditing
                    ? 'Failed to update category'
                    : 'Failed to create category';
            _isSubmitting = false;
          });
        }
      }
    } catch (e, stackTrace) {
      print('💥 Exception caught: $e');
      print('Stack trace: $stackTrace');
      if (mounted) {
        setState(() {
          _errorMessage = 'An error occurred: $e';
          _isSubmitting = false;
        });
      }
    }
  }

  Future<void> _handleIconPicker() async {
    // Suggest icon based on current category name
    IconData? initialIcon = _selectedIcon;
    if (initialIcon == null && _nameController.text.isNotEmpty) {
      final suggestedIconName = BilingualIconPicker.getSuggestedIconName(
        _nameController.text,
      );
      initialIcon = BilingualIconPicker.getIconFromName(suggestedIconName);
    }

    final icon = await BilingualIconPicker.showIconPicker(
      context,
      selectedIcon: initialIcon,
      categoryName: _nameController.text,
    );

    if (icon != null) {
      setState(() {
        _selectedIcon = icon;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AlertDialog(
      title: Text(_isDefaultCategory
          ? 'Edit Category Icon'
          : _isEditing
              ? 'Edit Category'
              : 'New Category'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Icon picker button
            InkWell(
              onTap: _isSubmitting ? null : _handleIconPicker,
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  border: Border.all(
                    color: theme.colorScheme.outline.withValues(alpha: 0.5),
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        _selectedIcon ?? Icons.category,
                        size: 28,
                        color: theme.colorScheme.onPrimaryContainer,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Icona categoria',
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Tocca per cambiare',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      Icons.edit,
                      size: 20,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _nameController,
              decoration: InputDecoration(
                labelText: 'Nome categoria',
                hintText: 'es. Animali, Istruzione',
                prefixIcon: const Icon(Icons.label_outline),
                helperText: _isDefaultCategory
                    ? 'Il nome delle categorie default non può essere modificato'
                    : null,
              ),
              autofocus: !_isDefaultCategory,
              textCapitalization: TextCapitalization.words,
              enabled: !_isSubmitting && !_isDefaultCategory,
              validator: (value) {
                if (_isDefaultCategory) return null; // Skip validation for default categories
                if (value == null || value.trim().isEmpty) {
                  return 'Category name cannot be empty';
                }
                if (value.trim().length < 1) {
                  return 'Category name must be at least 1 character';
                }
                if (value.trim().length > 50) {
                  return 'Category name must be at most 50 characters';
                }
                return null;
              },
              onFieldSubmitted: (_) => _handleSubmit(),
            ),
            if (_errorMessage != null) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.errorContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.error_outline,
                      color: theme.colorScheme.onErrorContainer,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _errorMessage!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onErrorContainer,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSubmitting ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _isSubmitting ? null : _handleSubmit,
          child: _isSubmitting
              ? const SizedBox(
                  height: 16,
                  width: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(_isEditing ? 'Save' : 'Create'),
        ),
      ],
    );
  }
}
