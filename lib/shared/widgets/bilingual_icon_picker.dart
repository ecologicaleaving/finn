// Bilingual Icon Picker Widget
// Feature: 014-category-icons
// Purpose: Material Icons picker with Italian/English search support

import 'package:flutter/material.dart';
import '../../core/services/icon_helper.dart';
import '../../core/services/icon_matching_service.dart';

/// Custom icon picker with bilingual (Italian/English) search support.
///
/// Wraps a custom picker dialog with Italian keyword translation for better UX.
class BilingualIconPicker {
  /// Show icon picker dialog with bilingual search.
  ///
  /// Returns the selected IconData or null if cancelled.
  static Future<IconData?> showIconPicker(
    BuildContext context, {
    IconData? selectedIcon,
    String? categoryName,
  }) async {
    return showDialog<IconData>(
      context: context,
      builder: (BuildContext context) {
        return _IconPickerDialog(
          selectedIcon: selectedIcon,
          categoryName: categoryName,
        );
      },
    );
  }

  /// Get icon name suggestion based on category name.
  ///
  /// Returns a suggested icon name for the given category name.
  static String getSuggestedIconName(String categoryName) {
    return IconMatchingService.getDefaultIconNameForCategory(categoryName);
  }

  /// Get IconData from icon name.
  static IconData? getIconFromName(String iconName) {
    return IconHelper.getIconFromName(iconName);
  }
}

class _IconPickerDialog extends StatefulWidget {
  const _IconPickerDialog({
    this.selectedIcon,
    this.categoryName,
  });

  final IconData? selectedIcon;
  final String? categoryName;

  @override
  State<_IconPickerDialog> createState() => _IconPickerDialogState();
}

class _IconPickerDialogState extends State<_IconPickerDialog> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  IconData? _selectedIcon;

  @override
  void initState() {
    super.initState();
    _selectedIcon = widget.selectedIcon;
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<MapEntry<String, IconData>> _getFilteredIcons() {
    final allIcons = IconHelper.getAllIcons().entries.toList();

    if (_searchQuery.isEmpty) {
      return allIcons;
    }

    final query = _searchQuery.toLowerCase();
    return allIcons.where((entry) {
      final iconName = entry.key.toLowerCase();

      // Check English match
      if (iconName.contains(query)) {
        return true;
      }

      // Check Italian keyword translation
      for (final translationEntry
          in IconMatchingService.italianToEnglishIconKeywords.entries) {
        if (translationEntry.key.contains(query)) {
          // Italian keyword matches - check if icon name matches translated value
          if (iconName.contains(translationEntry.value)) {
            return true;
          }
        }
      }

      return false;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final filteredIcons = _getFilteredIcons();

    return Dialog(
      child: Container(
        width: MediaQuery.of(context).size.width * 0.9,
        height: MediaQuery.of(context).size.height * 0.8,
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // Header
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Seleziona icona',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Search bar
            TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Cerca icone (italiano o inglese)',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                          setState(() {
                            _searchQuery = '';
                          });
                        },
                      )
                    : null,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onChanged: (value) {
                setState(() {
                  _searchQuery = value;
                });
              },
            ),
            const SizedBox(height: 16),

            // Icon grid
            Expanded(
              child: filteredIcons.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.search_off,
                            size: 64,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Nessuna icona trovata',
                            style: theme.textTheme.bodyLarge?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    )
                  : GridView.builder(
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 4,
                        crossAxisSpacing: 8,
                        mainAxisSpacing: 8,
                      ),
                      itemCount: filteredIcons.length,
                      itemBuilder: (context, index) {
                        final entry = filteredIcons[index];
                        final icon = entry.value;
                        final isSelected = _selectedIcon?.codePoint == icon.codePoint;

                        return InkWell(
                          onTap: () {
                            setState(() {
                              _selectedIcon = icon;
                            });
                          },
                          borderRadius: BorderRadius.circular(12),
                          child: Container(
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? theme.colorScheme.primaryContainer
                                  : theme.colorScheme.surface,
                              border: Border.all(
                                color: isSelected
                                    ? theme.colorScheme.primary
                                    : theme.colorScheme.outline.withOpacity(0.3),
                                width: isSelected ? 2 : 1,
                              ),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  icon,
                                  size: 32,
                                  color: isSelected
                                      ? theme.colorScheme.primary
                                      : theme.colorScheme.onSurface,
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  entry.key.replaceAll('_', ' '),
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: isSelected
                                        ? theme.colorScheme.onPrimaryContainer
                                        : theme.colorScheme.onSurfaceVariant,
                                  ),
                                  textAlign: TextAlign.center,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
            const SizedBox(height: 16),

            // Action buttons
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Annulla'),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _selectedIcon != null
                      ? () => Navigator.of(context).pop(_selectedIcon)
                      : null,
                  child: const Text('Seleziona'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
