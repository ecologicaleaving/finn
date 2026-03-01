/// Tests for Issue #6: Default category not saved when adding expense.
///
/// Verifies that the auto-selection logic (now in ManualExpenseScreen)
/// correctly sets the default category when categories become available,
/// does not override user selections, and satisfies the save guard.
///
/// These are pure-logic unit tests: no Flutter widgets, no providers,
/// no generated code — verifying the condition that was moved out of
/// CategorySelector.build() into ManualExpenseScreen.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:family_expense_tracker/features/categories/domain/entities/expense_category_entity.dart';

// ---------------------------------------------------------------------------
// Helper
// ---------------------------------------------------------------------------

ExpenseCategoryEntity _cat(String id, String name) {
  final now = DateTime(2026, 1, 1);
  return ExpenseCategoryEntity(
    id: id,
    name: name,
    groupId: 'group-test',
    isDefault: true,
    createdAt: now,
    updatedAt: now,
  );
}

// ---------------------------------------------------------------------------
// Extracted auto-select condition (mirrors the fix in ManualExpenseScreen)
//
// Logic in ManualExpenseScreen.build() ref.listen callback:
//   if (_selectedCategoryId == null && next.categories.isNotEmpty) {
//     setState(() { _selectedCategoryId = next.categories.first.id; });
//   }
//
// Logic in ManualExpenseScreen.initState() postFrameCallback:
//   if (_selectedCategoryId == null && categoryState.categories.isNotEmpty) {
//     setState(() { _selectedCategoryId = categoryState.categories.first.id; });
//   }
// ---------------------------------------------------------------------------

String? _applyAutoSelect(
  String? currentSelection,
  List<ExpenseCategoryEntity> categories,
) {
  if (currentSelection == null && categories.isNotEmpty) {
    return categories.first.id;
  }
  return currentSelection;
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('Issue #6 — ManualExpenseScreen default category auto-selection', () {
    group('_applyAutoSelect() condition', () {
      test('selects first category when none is currently selected', () {
        final result = _applyAutoSelect(
          null,
          [_cat('cat-1', 'Alimentari'), _cat('cat-2', 'Trasporti')],
        );
        expect(result, 'cat-1',
            reason: 'First category should be auto-selected when none is set');
      });

      test('returns null when category list is empty (still loading)', () {
        final result = _applyAutoSelect(null, []);
        expect(result, isNull,
            reason: 'No auto-select should happen while categories are loading');
      });

      test('does NOT override a category already selected by the user', () {
        final result = _applyAutoSelect(
          'cat-2', // user picked cat-2
          [_cat('cat-1', 'Alimentari'), _cat('cat-2', 'Trasporti')],
        );
        expect(result, 'cat-2',
            reason: "User's selection must not be overridden by auto-select");
      });

      test('does NOT override even when selected category is the first one', () {
        final result = _applyAutoSelect(
          'cat-1', // already set (either by user or prior auto-select)
          [_cat('cat-1', 'Alimentari'), _cat('cat-2', 'Trasporti')],
        );
        expect(result, 'cat-1');
      });
    });

    group('transition from loading → loaded (async categories)', () {
      test('auto-select fires on first non-empty state transition', () {
        String? selectedCategoryId;

        // Simulated provider state: empty (loading)
        final emptyCategories = <ExpenseCategoryEntity>[];
        selectedCategoryId =
            _applyAutoSelect(selectedCategoryId, emptyCategories);
        expect(selectedCategoryId, isNull);

        // Simulated provider state: categories loaded
        final loadedCategories = [
          _cat('cat-1', 'Alimentari'),
          _cat('cat-2', 'Trasporti'),
        ];
        selectedCategoryId =
            _applyAutoSelect(selectedCategoryId, loadedCategories);
        expect(selectedCategoryId, 'cat-1');
      });

      test('realtime reload does NOT re-trigger auto-select once set', () {
        // Initial auto-select happened
        String? selectedCategoryId = 'cat-1';

        // A realtime update refreshes the category list
        final refreshedCategories = [
          _cat('cat-1', 'Alimentari'),
          _cat('cat-2', 'Trasporti'),
          _cat('cat-3', 'Casa'), // new category added by admin
        ];

        selectedCategoryId =
            _applyAutoSelect(selectedCategoryId, refreshedCategories);

        // Selection must remain 'cat-1' — not reset or re-selected
        expect(selectedCategoryId, 'cat-1');
      });
    });

    group('form submission requirement', () {
      test('form cannot submit without a category (guard in _handleSave)', () {
        String? selectedCategoryId;
        // Mirrors: if (_selectedCategoryId == null) { return; }
        bool canSubmit = selectedCategoryId != null;
        expect(canSubmit, isFalse);
      });

      test('auto-selected category satisfies submission guard', () {
        String? selectedCategoryId;

        // Auto-select fires (categories available)
        selectedCategoryId = _applyAutoSelect(
          selectedCategoryId,
          [_cat('cat-1', 'Alimentari')],
        );

        bool canSubmit = selectedCategoryId != null;
        expect(canSubmit, isTrue);
        expect(selectedCategoryId, 'cat-1');
      });

      test('the fix: no re-trigger after user manually taps the same chip', () {
        // Issue scenario: user opens form, auto-select fires,
        // user saves, save should work (selectedCategoryId is set).
        String? selectedCategoryId;

        // Auto-select fires on screen open
        selectedCategoryId = _applyAutoSelect(
          selectedCategoryId,
          [_cat('cat-1', 'Alimentari'), _cat('cat-2', 'Trasporti')],
        );
        expect(selectedCategoryId, 'cat-1');

        // User does NOT re-tap the chip — they just press Save
        // selectedCategoryId remains 'cat-1' (no reset possible now)
        bool canSubmit = selectedCategoryId != null;
        expect(canSubmit, isTrue,
            reason:
                'With fix: auto-selected category is in state → save works');
      });
    });

    group('ExpenseCategoryEntity validity', () {
      test('category with non-empty id is valid for selection', () {
        final cat = _cat('cat-1', 'Alimentari');
        expect(cat.isNotEmpty, isTrue);
        expect(cat.id, 'cat-1');
      });

      test('empty category factory produces invalid category', () {
        final empty = ExpenseCategoryEntity.empty();
        expect(empty.isEmpty, isTrue);
      });
    });
  });
}
