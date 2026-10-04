import 'package:dartz/dartz.dart';
import 'package:family_expense_tracker/core/errors/failures.dart';
import 'package:family_expense_tracker/features/auth/domain/entities/user_entity.dart';
import 'package:family_expense_tracker/features/auth/domain/repositories/auth_repository.dart';
import 'package:family_expense_tracker/features/auth/presentation/providers/auth_provider.dart';
import 'package:flutter_test/flutter_test.dart';

// Issue #64 AC1/AC2: logout triggers a best-effort cleanup with the id of the
// outgoing user and never blocks the logout.

const _userA = UserEntity(id: 'A', email: 'a@x.it');

class _FakeAuthRepository implements AuthRepository {
  bool signOutFails = false;
  bool deleteFails = false;

  @override
  Future<Either<Failure, UserEntity>> getCurrentUser() async =>
      const Right(_userA);

  @override
  Future<Either<Failure, Unit>> signOut() async => signOutFails
      ? const Left(ServerFailure('net'))
      : const Right(unit);

  @override
  Future<Either<Failure, Unit>> deleteAccount({
    required bool anonymizeExpenses,
  }) async =>
      deleteFails ? const Left(ServerFailure('net')) : const Right(unit);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<AuthNotifier> _ready(
  _FakeAuthRepository repo,
  Future<void> Function(String?) cb,
) async {
  final notifier = AuthNotifier(repo, onSessionEnded: cb);
  await Future<void>.delayed(Duration.zero);
  expect(notifier.state.user?.id, 'A');
  return notifier;
}

void main() {
  test('signOut calls the cleanup once with the outgoing user id', () async {
    final calls = <String?>[];
    final notifier =
        await _ready(_FakeAuthRepository(), (id) async => calls.add(id));
    await notifier.signOut();
    expect(calls, ['A']);
    expect(notifier.state.status, AuthStatus.unauthenticated);
  });

  test('a throwing cleanup does not prevent the logout', () async {
    final notifier = await _ready(
      _FakeAuthRepository(),
      (id) async => throw Exception('boom'),
    );
    await notifier.signOut();
    expect(notifier.state.status, AuthStatus.unauthenticated);
  });

  test('cleanup also runs when signOut fails (best effort)', () async {
    final calls = <String?>[];
    final repo = _FakeAuthRepository()..signOutFails = true;
    final notifier = await _ready(repo, (id) async => calls.add(id));
    await notifier.signOut();
    expect(calls, ['A']);
  });

  test('deleteAccount cleans up only on success', () async {
    final calls = <String?>[];
    final repo = _FakeAuthRepository()..deleteFails = true;
    final notifier = await _ready(repo, (id) async => calls.add(id));
    await notifier.deleteAccount(anonymizeExpenses: false);
    expect(calls, isEmpty);

    repo.deleteFails = false;
    await notifier.deleteAccount(anonymizeExpenses: false);
    expect(calls, ['A']);
  });
}
