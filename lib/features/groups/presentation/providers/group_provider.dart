import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../auth/presentation/providers/auth_provider.dart';
import '../../data/datasources/group_remote_datasource.dart';
import '../../data/datasources/invite_remote_datasource.dart';
import '../../data/repositories/group_repository_impl.dart';
import '../../domain/entities/family_group_entity.dart';
import '../../domain/entities/invite_entity.dart';
import '../../domain/entities/member_entity.dart';
import '../../domain/repositories/group_repository.dart';

/// Provider for group remote data source
final groupRemoteDataSourceProvider = Provider<GroupRemoteDataSource>((ref) {
  return GroupRemoteDataSourceImpl(
    supabaseClient: Supabase.instance.client,
  );
});

/// Provider for invite remote data source
final inviteRemoteDataSourceProvider = Provider<InviteRemoteDataSource>((ref) {
  return InviteRemoteDataSourceImpl(
    supabaseClient: Supabase.instance.client,
  );
});

/// Provider for group repository
final groupRepositoryProvider = Provider<GroupRepository>((ref) {
  return GroupRepositoryImpl(
    groupRemoteDataSource: ref.watch(groupRemoteDataSourceProvider),
    inviteRemoteDataSource: ref.watch(inviteRemoteDataSourceProvider),
  );
});

/// Group state status
enum GroupStatus {
  initial,
  loading,
  loaded,
  noGroup,
  error,
}

/// Group state class
class GroupState {
  const GroupState({
    this.status = GroupStatus.initial,
    this.group,
    this.members = const [],
    this.invite,
    this.errorMessage,
  });

  final GroupStatus status;
  final FamilyGroupEntity? group;
  final List<MemberEntity> members;
  final InviteEntity? invite;
  final String? errorMessage;

  GroupState copyWith({
    GroupStatus? status,
    FamilyGroupEntity? group,
    List<MemberEntity>? members,
    InviteEntity? invite,
    String? errorMessage,
  }) {
    return GroupState(
      status: status ?? this.status,
      group: group ?? this.group,
      members: members ?? this.members,
      invite: invite ?? this.invite,
      errorMessage: errorMessage,
    );
  }

  bool get hasGroup => group != null && group!.isNotEmpty;
  bool get isLoading => status == GroupStatus.loading;
  bool get hasError => status == GroupStatus.error;
}

/// Group notifier for managing group state
class GroupNotifier extends StateNotifier<GroupState> {
  GroupNotifier(this._groupRepository) : super(const GroupState());

  final GroupRepository _groupRepository;

  /// Load the current user's group
  Future<void> loadCurrentGroup() async {
    print('🔍 [GROUP] loadCurrentGroup called');
    state = state.copyWith(status: GroupStatus.loading, errorMessage: null);

    final result = await _groupRepository.getCurrentGroup();

    result.fold(
      (failure) {
        print('❌ [GROUP] Failed to load group: ${failure.message}');
        state = state.copyWith(
          status: GroupStatus.noGroup,
          group: null,
          members: [],
        );
      },
      (group) async {
        print('✅ [GROUP] Group loaded: ${group.name} (id: ${group.id})');
        state = state.copyWith(
          status: GroupStatus.loaded,
          group: group,
        );
        // Also load members
        await loadMembers();
        // And check for active invite
        await loadActiveInvite();
      },
    );
  }

  /// Load group members
  Future<void> loadMembers() async {
    if (state.group == null) return;

    print('🔍 [GROUP] Loading members for group ${state.group!.id}');
    final result = await _groupRepository.getGroupMembers(
      groupId: state.group!.id,
    );

    result.fold(
      (failure) {
        print('❌ [GROUP] Failed to load members: ${failure.message}');
        // Keep current state, just log the error
      },
      (members) {
        print('✅ [GROUP] Loaded ${members.length} members');
        state = state.copyWith(members: members);
      },
    );
  }

  /// Load active invite
  Future<void> loadActiveInvite() async {
    final result = await _groupRepository.getActiveInvite();

    result.fold(
      (failure) {
        state = state.copyWith(invite: null);
      },
      (invite) {
        state = state.copyWith(invite: invite);
      },
    );
  }

  /// Create a new group
  Future<bool> createGroup({required String name}) async {
    state = state.copyWith(status: GroupStatus.loading, errorMessage: null);

    final result = await _groupRepository.createGroup(name: name);

    return result.fold(
      (failure) {
        state = state.copyWith(
          status: GroupStatus.noGroup,
          errorMessage: failure.message,
        );
        return false;
      },
      (group) {
        state = state.copyWith(
          status: GroupStatus.loaded,
          group: group,
          members: [],
        );
        loadMembers();
        return true;
      },
    );
  }

  /// Join a group with invite code
  Future<bool> joinGroupWithCode({required String code}) async {
    state = state.copyWith(status: GroupStatus.loading, errorMessage: null);

    final result = await _groupRepository.joinGroupWithCode(code: code);

    return result.fold(
      (failure) {
        state = state.copyWith(
          status: GroupStatus.noGroup,
          errorMessage: failure.message,
        );
        return false;
      },
      (group) {
        state = state.copyWith(
          status: GroupStatus.loaded,
          group: group,
        );
        loadMembers();
        return true;
      },
    );
  }

  /// Validate an invite code
  Future<InviteEntity?> validateInviteCode({required String code}) async {
    final result = await _groupRepository.validateInviteCode(code: code);

    return result.fold(
      (failure) {
        state = state.copyWith(errorMessage: failure.message);
        return null;
      },
      (invite) => invite,
    );
  }

  /// Create an invite code
  Future<bool> createInvite() async {
    final result = await _groupRepository.createInvite();

    return result.fold(
      (failure) {
        state = state.copyWith(errorMessage: failure.message);
        return false;
      },
      (invite) {
        state = state.copyWith(invite: invite);
        return true;
      },
    );
  }

  /// Update group name
  Future<bool> updateGroupName({required String name}) async {
    final result = await _groupRepository.updateGroupName(name: name);

    return result.fold(
      (failure) {
        state = state.copyWith(errorMessage: failure.message);
        return false;
      },
      (group) {
        state = state.copyWith(group: group);
        return true;
      },
    );
  }

  /// Remove a member from the group
  Future<bool> removeMember({required String userId}) async {
    final result = await _groupRepository.removeMember(userId: userId);

    return result.fold(
      (failure) {
        state = state.copyWith(errorMessage: failure.message);
        return false;
      },
      (_) {
        // Reload members
        loadMembers();
        return true;
      },
    );
  }

  /// Leave the current group
  Future<bool> leaveGroup() async {
    state = state.copyWith(status: GroupStatus.loading, errorMessage: null);

    final result = await _groupRepository.leaveGroup();

    return result.fold(
      (failure) {
        state = state.copyWith(
          status: GroupStatus.loaded,
          errorMessage: failure.message,
        );
        return false;
      },
      (_) {
        state = state.copyWith(
          status: GroupStatus.noGroup,
          group: null,
          members: [],
          invite: null,
        );
        return true;
      },
    );
  }

  /// Delete the group
  Future<bool> deleteGroup() async {
    state = state.copyWith(status: GroupStatus.loading, errorMessage: null);

    final result = await _groupRepository.deleteGroup();

    return result.fold(
      (failure) {
        state = state.copyWith(
          status: GroupStatus.loaded,
          errorMessage: failure.message,
        );
        return false;
      },
      (_) {
        state = state.copyWith(
          status: GroupStatus.noGroup,
          group: null,
          members: [],
          invite: null,
        );
        return true;
      },
    );
  }

  /// Clear error message
  void clearError() {
    state = state.copyWith(errorMessage: null);
  }
}

/// Provider for group state
final groupProvider = StateNotifierProvider<GroupNotifier, GroupState>((ref) {
  // Watch auth state to reload group when user changes
  ref.watch(authProvider);
  return GroupNotifier(ref.watch(groupRepositoryProvider));
});

/// Convenience provider to check if user has a group
final userHasGroupProvider = Provider<bool>((ref) {
  return ref.watch(groupProvider).hasGroup;
});

/// Convenience provider to get current group
final currentGroupProvider = Provider<FamilyGroupEntity?>((ref) {
  return ref.watch(groupProvider).group;
});

/// Convenience provider to get current group ID
final currentGroupIdProvider = Provider<String>((ref) {
  final group = ref.watch(currentGroupProvider);
  if (group == null) {
    throw StateError('No group available');
  }
  return group.id;
});

/// Convenience provider to get group members
final groupMembersProvider = Provider<List<MemberEntity>>((ref) {
  return ref.watch(groupProvider).members;
});

/// Convenience provider to check if current user is group admin
final isGroupAdminProvider = Provider<bool>((ref) {
  final group = ref.watch(groupProvider).group;
  final currentUser = ref.watch(currentUserProvider);
  print('🔍 [isGroupAdminProvider] Checking admin status: group=${group?.name}, user=${currentUser?.id}');
  if (group == null || currentUser == null) {
    print('❌ [isGroupAdminProvider] No group or user, returning false');
    return false;
  }
  final isAdmin = group.isAdmin(currentUser.id);
  print('${isAdmin ? "✅" : "❌"} [isGroupAdminProvider] User is ${isAdmin ? "admin" : "not admin"}');
  return isAdmin;
});
