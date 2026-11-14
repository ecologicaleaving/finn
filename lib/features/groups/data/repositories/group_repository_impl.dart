import 'package:dartz/dartz.dart';

import '../../../../core/errors/exceptions.dart';
import '../../../../core/errors/failures.dart';
import '../../domain/entities/family_group_entity.dart';
import '../../domain/entities/invite_entity.dart';
import '../../domain/entities/member_entity.dart';
import '../../domain/repositories/group_repository.dart';
import '../datasources/group_remote_datasource.dart';
import '../datasources/invite_remote_datasource.dart';

/// Implementation of [GroupRepository] using remote data sources.
class GroupRepositoryImpl implements GroupRepository {
  GroupRepositoryImpl({
    required this.groupRemoteDataSource,
    required this.inviteRemoteDataSource,
  });

  final GroupRemoteDataSource groupRemoteDataSource;
  final InviteRemoteDataSource inviteRemoteDataSource;

  @override
  Future<Either<Failure, FamilyGroupEntity>> createGroup({
    required String name,
  }) async {
    try {
      final group = await groupRemoteDataSource.createGroup(name: name);
      return Right(group.toEntity());
    } on AppAuthException catch (e) {
      return Left(AuthFailure(e.message));
    } on GroupException catch (e) {
      return Left(GroupFailure(e.message));
    } on ServerException catch (e) {
      return Left(ServerFailure(e.message));
    } catch (e) {
      return Left(ServerFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, FamilyGroupEntity>> getCurrentGroup() async {
    try {
      final group = await groupRemoteDataSource.getCurrentGroup();
      if (group == null) {
        return const Left(GroupFailure.noGroup);
      }
      return Right(group.toEntity());
    } on AppAuthException catch (e) {
      return Left(AuthFailure(e.message, e.code));
    } on ServerException catch (e) {
      return Left(ServerFailure(e.message, e.code));
    } catch (e) {
      return Left(ServerFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, FamilyGroupEntity>> getGroup({
    required String groupId,
  }) async {
    try {
      final group = await groupRemoteDataSource.getGroup(groupId: groupId);
      return Right(group.toEntity());
    } on ServerException catch (e) {
      return Left(ServerFailure(e.message));
    } catch (e) {
      return Left(ServerFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, List<MemberEntity>>> getGroupMembers({
    required String groupId,
  }) async {
    try {
      final members = await groupRemoteDataSource.getGroupMembers(groupId: groupId);
      return Right(members.map((m) => m.toEntity()).toList());
    } on ServerException catch (e) {
      return Left(ServerFailure(e.message));
    } catch (e) {
      return Left(ServerFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, Unit>> leaveGroup() async {
    try {
      await groupRemoteDataSource.leaveGroup();
      return const Right(unit);
    } on AppAuthException catch (e) {
      return Left(AuthFailure(e.message));
    } on GroupException catch (e) {
      return Left(GroupFailure(e.message));
    } on ServerException catch (e) {
      return Left(ServerFailure(e.message));
    } catch (e) {
      return Left(ServerFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, Unit>> removeMember({
    required String userId,
  }) async {
    try {
      await groupRemoteDataSource.removeMember(userId: userId);
      return const Right(unit);
    } on AppAuthException catch (e) {
      return Left(AuthFailure(e.message));
    } on GroupException catch (e) {
      return Left(GroupFailure(e.message));
    } on ServerException catch (e) {
      return Left(ServerFailure(e.message));
    } catch (e) {
      return Left(ServerFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, FamilyGroupEntity>> updateGroupName({
    required String name,
  }) async {
    try {
      final group = await groupRemoteDataSource.updateGroupName(name: name);
      return Right(group.toEntity());
    } on AppAuthException catch (e) {
      return Left(AuthFailure(e.message));
    } on GroupException catch (e) {
      return Left(GroupFailure(e.message));
    } on ServerException catch (e) {
      return Left(ServerFailure(e.message));
    } catch (e) {
      return Left(ServerFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, InviteEntity>> createInvite() async {
    try {
      final invite = await inviteRemoteDataSource.createInvite();
      return Right(invite.toEntity());
    } on AppAuthException catch (e) {
      return Left(AuthFailure(e.message));
    } on GroupException catch (e) {
      return Left(GroupFailure(e.message));
    } on ServerException catch (e) {
      return Left(ServerFailure(e.message));
    } catch (e) {
      return Left(ServerFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, InviteEntity>> getActiveInvite() async {
    try {
      final invite = await inviteRemoteDataSource.getActiveInvite();
      if (invite == null) {
        return Left(InviteFailure('Nessun codice invito attivo'));
      }
      return Right(invite.toEntity());
    } on AppAuthException catch (e) {
      return Left(AuthFailure(e.message));
    } on ServerException catch (e) {
      return Left(ServerFailure(e.message));
    } catch (e) {
      return Left(ServerFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, InviteEntity>> validateInviteCode({
    required String code,
  }) async {
    try {
      final invite = await inviteRemoteDataSource.validateInviteCode(code: code);
      return Right(invite.toEntity());
    } on AppAuthException catch (e) {
      return Left(AuthFailure(e.message));
    } on InviteException catch (e) {
      return Left(InviteFailure(e.message));
    } on ServerException catch (e) {
      return Left(ServerFailure(e.message));
    } catch (e) {
      return Left(ServerFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, FamilyGroupEntity>> joinGroupWithCode({
    required String code,
  }) async {
    try {
      final group = await inviteRemoteDataSource.joinGroupWithCode(code: code);
      return Right(group.toEntity());
    } on AppAuthException catch (e) {
      return Left(AuthFailure(e.message));
    } on GroupException catch (e) {
      return Left(GroupFailure(e.message));
    } on InviteException catch (e) {
      return Left(InviteFailure(e.message));
    } on ServerException catch (e) {
      return Left(ServerFailure(e.message));
    } catch (e) {
      return Left(ServerFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, Unit>> deleteGroup() async {
    try {
      await groupRemoteDataSource.deleteGroup();
      return const Right(unit);
    } on AppAuthException catch (e) {
      return Left(AuthFailure(e.message));
    } on GroupException catch (e) {
      return Left(GroupFailure(e.message));
    } on ServerException catch (e) {
      return Left(ServerFailure(e.message));
    } catch (e) {
      return Left(ServerFailure(e.toString()));
    }
  }
}
