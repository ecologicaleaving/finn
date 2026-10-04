import 'package:dartz/dartz.dart';
import 'package:family_expense_tracker/core/errors/failures.dart';
import 'package:family_expense_tracker/features/auth/domain/entities/user_entity.dart';
import 'package:family_expense_tracker/features/auth/domain/repositories/auth_repository.dart';
import 'package:family_expense_tracker/features/auth/presentation/providers/auth_provider.dart';
import 'package:family_expense_tracker/features/groups/domain/entities/family_group_entity.dart';
import 'package:family_expense_tracker/features/groups/domain/entities/invite_entity.dart';
import 'package:family_expense_tracker/features/groups/domain/entities/member_entity.dart';
import 'package:family_expense_tracker/features/groups/domain/repositories/group_repository.dart';
import 'package:family_expense_tracker/features/groups/presentation/providers/group_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

// Issue #64 AC3/AC4: a display-name change must not wipe the group state,
// while a different user logging in must get a fresh group state.

const _userA = UserEntity(id: 'A', email: 'a@x.it', displayName: 'A');
const _userARenamed = UserEntity(id: 'A', email: 'a@x.it', displayName: 'A2');
const _userB = UserEntity(id: 'B', email: 'b@x.it', displayName: 'B');

class _FakeAuthRepository implements AuthRepository {
  @override
  Future<Either<Failure, UserEntity>> getCurrentUser() async =>
      const Right(_userA);

  @override
  Future<Either<Failure, UserEntity>> updateDisplayName({
    required String displayName,
  }) async =>
      const Right(_userARenamed);

  @override
  Future<Either<Failure, UserEntity>> signInWithEmail({
    required String email,
    required String password,
  }) async =>
      const Right(_userB);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeGroupRepository implements GroupRepository {
  @override
  Future<Either<Failure, FamilyGroupEntity>> getCurrentGroup() async =>
      const Right(
        FamilyGroupEntity(id: 'g1', name: 'Famiglia', createdBy: 'A'),
      );

  @override
  Future<Either<Failure, List<MemberEntity>>> getGroupMembers({
    required String groupId,
  }) async =>
      const Right([]);

  @override
  Future<Either<Failure, InviteEntity>> getActiveInvite() async =>
      const Left(ServerFailure('none'));

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late ProviderContainer container;

  setUp(() {
    container = ProviderContainer(overrides: [
      authRepositoryProvider.overrideWithValue(_FakeAuthRepository()),
      groupRepositoryProvider.overrideWithValue(_FakeGroupRepository()),
    ]);
    addTearDown(container.dispose);
  });

  test('updateDisplayName keeps the group; a new user gets a fresh state',
      () async {
    container.listen(groupProvider, (_, __) {});
    await Future<void>.delayed(Duration.zero); // auth init
    expect(container.read(currentUserProvider)?.id, 'A');

    final notifierA = container.read(groupProvider.notifier);
    await notifierA.loadCurrentGroup();
    expect(container.read(groupProvider).hasGroup, isTrue);

    // AC3: loading -> authenticated with a new name
    await container
        .read(authProvider.notifier)
        .updateDisplayName(displayName: 'A2');
    expect(identical(container.read(groupProvider.notifier), notifierA), isTrue);
    expect(container.read(groupProvider).hasGroup, isTrue);

    // AC4: B logs in -> notifier recreated, A's group is gone
    await container
        .read(authProvider.notifier)
        .signInWithEmail(email: 'b@x.it', password: 'pw');
    expect(container.read(currentUserProvider)?.id, 'B');
    expect(identical(container.read(groupProvider.notifier), notifierA), isFalse);
    expect(container.read(groupProvider).hasGroup, isFalse);
  });
}
