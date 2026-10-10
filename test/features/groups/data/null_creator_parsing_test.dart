// Regola di Davide (issue #46): le spese restano nel gruppo anche quando
// l'autore elimina l'account. In quel caso expenses.created_by / paid_by
// diventano NULL (FK ON DELETE SET NULL) e family_groups.created_by puo'
// essere NULL per un gruppo rimasto senza membri: il parsing non deve fallire.
import 'package:family_expense_tracker/features/budgets/data/models/group_budget_model.dart';
import 'package:family_expense_tracker/features/expenses/data/models/expense_model.dart';
import 'package:family_expense_tracker/features/groups/data/models/family_group_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('ExpenseModel.fromJson tolerates created_by and paid_by null', () {
    final model = ExpenseModel.fromJson({
      'id': 'e1',
      'group_id': 'g1',
      'created_by': null,
      'paid_by': null,
      'amount': 12.5,
      'date': '2026-10-01T00:00:00.000Z',
      'payment_method_id': 'pm1',
    });

    expect(model.createdBy, '');
    expect(model.paidBy, isNull);
    expect(model.id, 'e1');
  });

  test('FamilyGroupModel.fromJson tolerates created_by null', () {
    final model = FamilyGroupModel.fromJson({
      'id': 'g1',
      'name': 'Famiglia',
      'created_by': null,
    });

    expect(model.createdBy, '');
    expect(model.isAdmin('any-user'), isFalse);
  });

  test('GroupBudgetModel.fromJson tolerates created_by null', () {
    final model = GroupBudgetModel.fromJson({
      'id': 'b1',
      'group_id': 'g1',
      'amount': 1000,
      'month': 10,
      'year': 2026,
      'created_by': null,
      'created_at': '2026-10-01T00:00:00.000Z',
      'updated_at': '2026-10-01T00:00:00.000Z',
    });

    expect(model.createdBy, '');
  });
}
