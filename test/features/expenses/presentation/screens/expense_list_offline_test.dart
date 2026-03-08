import 'package:family_expense_tracker/core/enums/reimbursement_status.dart';
import 'package:family_expense_tracker/core/errors/failures.dart';
import 'package:family_expense_tracker/features/auth/domain/entities/user_entity.dart';
import 'package:family_expense_tracker/features/auth/presentation/providers/auth_provider.dart';
import 'package:family_expense_tracker/features/expenses/domain/repositories/expense_repository.dart';
import 'package:family_expense_tracker/features/expenses/domain/entities/expense_entity.dart';
import 'package:family_expense_tracker/features/expenses/presentation/providers/expense_provider.dart';
import 'package:family_expense_tracker/features/expenses/presentation/screens/expense_list_screen.dart';
import 'package:family_expense_tracker/features/groups/presentation/providers/group_provider.dart';
import 'package:dartz/dartz.dart';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

class _FakeExpenseRepository implements ExpenseRepository {
  @override
  Future<Either<Failure, ExpenseEntity>> createExpense({
    required double amount,
    required DateTime date,
    required String categoryId,
    String? paymentMethodId,
    String? merchant,
    String? notes,
    Uint8List? receiptImage,
    bool isGroupExpense = true,
    ReimbursementStatus reimbursementStatus = ReimbursementStatus.none,
    String? createdBy,
    String? paidBy,
    String? lastModifiedBy,
  }) async {
    throw UnimplementedError();
  }

  @override
  Future<Either<Failure, Unit>> deleteExpense({required String expenseId}) async {
    throw UnimplementedError();
  }

  @override
  Future<Either<Failure, ExpenseEntity>> getExpense({required String expenseId}) async {
    throw UnimplementedError();
  }

  @override
  Future<Either<Failure, List<ExpenseEntity>>> getExpenses({
    DateTime? startDate,
    DateTime? endDate,
    String? categoryId,
    String? createdBy,
    String? paidBy,
    bool? isGroupExpense,
    ReimbursementStatus? reimbursementStatus,
    int? limit,
    int? offset,
  }) async {
    return const Right([]);
  }

  @override
  Future<Either<Failure, ExpensesSummary>> getExpensesSummary({
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    throw UnimplementedError();
  }

  @override
  Future<Either<Failure, String>> getReceiptUrl({required String receiptPath}) async {
    throw UnimplementedError();
  }

  @override
  Future<Either<Failure, ExpenseEntity>> updateExpense({
    required String expenseId,
    double? amount,
    DateTime? date,
    String? categoryId,
    String? paymentMethodId,
    String? merchant,
    String? notes,
    ReimbursementStatus? reimbursementStatus,
  }) async {
    throw UnimplementedError();
  }

  @override
  Future<Either<Failure, ExpenseEntity>> updateExpenseClassification({
    required String expenseId,
    required bool isGroupExpense,
  }) async {
    throw UnimplementedError();
  }

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
  }) async {
    throw UnimplementedError();
  }

  @override
  Future<Either<Failure, String>> uploadReceiptImage({
    required String expenseId,
    required Uint8List imageData,
  }) async {
    throw UnimplementedError();
  }
}

class _FakeExpenseListNotifier extends ExpenseListNotifier {
  _FakeExpenseListNotifier(ExpenseListState state)
      : super(_FakeExpenseRepository()) {
    this.state = state;
  }
}

void main() {
  testWidgets('mostra spese dalla cache con indicatore pending sync', (tester) async {
    await initializeDateFormatting('it_IT');

    final expense = ExpenseEntity(
      id: 'offline-1',
      groupId: 'group-1',
      createdBy: 'user-1',
      amount: 12.5,
      date: DateTime(2026, 3, 8),
      categoryId: 'cat-1',
      categoryName: 'Alimentari',
      paymentMethodId: 'cash',
      paymentMethodName: 'Contanti',
      isGroupExpense: true,
      merchant: 'Spesa offline',
      notes: 'Cache locale',
      reimbursementStatus: ReimbursementStatus.none,
      syncStatus: 'pending',
    );

    final notifier = _FakeExpenseListNotifier(
      ExpenseListState(
        status: ExpenseListStatus.loaded,
        expenses: [expense],
        hasMore: false,
      ),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          expenseListProvider.overrideWith((ref) => notifier),
          currentUserProvider.overrideWithValue(
            const UserEntity(
              id: 'user-1',
              email: 'offline@example.com',
              displayName: 'Offline User',
              groupId: 'group-1',
            ),
          ),
          isGroupAdminProvider.overrideWithValue(false),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: ExpenseListScreen(),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Spesa offline'), findsOneWidget);
    expect(find.byIcon(Icons.cloud_upload_outlined), findsOneWidget);
  });
}
