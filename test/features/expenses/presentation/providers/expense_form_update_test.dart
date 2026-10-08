import 'package:dartz/dartz.dart';
import 'package:family_expense_tracker/core/enums/reimbursement_status.dart';
import 'package:family_expense_tracker/core/errors/failures.dart';
import 'package:family_expense_tracker/features/expenses/domain/entities/expense_entity.dart';
import 'package:family_expense_tracker/features/expenses/domain/repositories/expense_repository.dart';
import 'package:family_expense_tracker/features/expenses/presentation/providers/expense_provider.dart';
import 'package:family_expense_tracker/features/widget/presentation/services/widget_update_service.dart';
import 'package:flutter_test/flutter_test.dart';

class _RecordingExpenseRepository implements ExpenseRepository {
  Map<String, Object?>? lastUpdate;

  @override
  Future<Either<Failure, ExpenseEntity>> updateExpenseWithTimestamp({
    required String expenseId,
    required DateTime originalUpdatedAt,
    required String lastModifiedBy,
    double? amount,
    DateTime? date,
    String? categoryId,
    String? paymentMethodId,
    String? merchant,
    String? notes,
    ReimbursementStatus? reimbursementStatus,
    bool? isGroupExpense,
    String? paidBy,
  }) async {
    lastUpdate = {
      'expenseId': expenseId,
      'lastModifiedBy': lastModifiedBy,
      'amount': amount,
      'isGroupExpense': isGroupExpense,
      'paidBy': paidBy,
    };
    return Right(ExpenseEntity(
      id: expenseId,
      groupId: 'g1',
      createdBy: 'u1',
      amount: amount ?? 10,
      date: DateTime(2026, 9, 10),
      paymentMethodId: 'pm',
      isGroupExpense: isGroupExpense ?? true,
      paidBy: paidBy ?? 'u1',
    ));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeWidgetUpdateService implements WidgetUpdateService {
  @override
  Future<void> triggerUpdate() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test('updateExpenseWithLock forwards isGroupExpense and paidBy (AC3/AC4)',
      () async {
    final repository = _RecordingExpenseRepository();
    final notifier = ExpenseFormNotifier(repository, _FakeWidgetUpdateService());

    final result = await notifier.updateExpenseWithLock(
      expenseId: 'e1',
      originalUpdatedAt: DateTime(2026, 9, 10, 12),
      lastModifiedBy: 'u1',
      isGroupExpense: false,
      paidBy: 'u2',
    );

    expect(repository.lastUpdate!['expenseId'], 'e1');
    expect(repository.lastUpdate!['isGroupExpense'], false);
    expect(repository.lastUpdate!['paidBy'], 'u2');
    expect(repository.lastUpdate!['amount'], isNull);
    expect(result, isNotNull);
    expect(result!.isGroupExpense, false);
    expect(result.paidBy, 'u2');
    expect(notifier.state.isSuccess, isTrue);
    notifier.dispose();
  });

  test('updateExpenseWithLock leaves unchanged fields null', () async {
    final repository = _RecordingExpenseRepository();
    final notifier = ExpenseFormNotifier(repository, _FakeWidgetUpdateService());

    await notifier.updateExpenseWithLock(
      expenseId: 'e1',
      originalUpdatedAt: DateTime(2026, 9, 10, 12),
      lastModifiedBy: 'u1',
      amount: 12.5,
    );

    expect(repository.lastUpdate!['amount'], 12.5);
    expect(repository.lastUpdate!['isGroupExpense'], isNull);
    expect(repository.lastUpdate!['paidBy'], isNull);
    notifier.dispose();
  });
}
