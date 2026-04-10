import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/errors/exceptions.dart';
import '../models/family_group_model.dart';
import '../models/member_model.dart';

/// Remote data source for group operations using Supabase.
abstract class GroupRemoteDataSource {
  /// Create a new family group.
  Future<FamilyGroupModel> createGroup({required String name});

  /// Get the current user's group.
  Future<FamilyGroupModel?> getCurrentGroup();

  /// Get a group by ID.
  Future<FamilyGroupModel> getGroup({required String groupId});

  /// Get all members of a group.
  Future<List<MemberModel>> getGroupMembers({required String groupId});

  /// Leave the current group.
  Future<void> leaveGroup();

  /// Remove a member from the group.
  Future<void> removeMember({required String userId});

  /// Update the group name.
  Future<FamilyGroupModel> updateGroupName({required String name});

  /// Delete the group.
  Future<void> deleteGroup();
}

/// Implementation of [GroupRemoteDataSource] using Supabase.
class GroupRemoteDataSourceImpl implements GroupRemoteDataSource {
  GroupRemoteDataSourceImpl({
    required this.supabaseClient,
    FlutterSecureStorage? secureStorage,
  }) : _secureStorage = secureStorage ?? const FlutterSecureStorage();

  final SupabaseClient supabaseClient;
  final FlutterSecureStorage _secureStorage;

  static const String _groupIdKey = 'cached_group_id';
  static const String _groupDataKey = 'cached_group_data';

  String get _currentUserId {
    final userId = supabaseClient.auth.currentUser?.id;
    if (userId == null) {
      throw const AppAuthException('Nessun utente autenticato', 'not_authenticated');
    }
    return userId;
  }

  /// Cache group ID in secure storage
  Future<void> _cacheGroupId(String groupId) async {
    try {
      await _secureStorage.write(key: _groupIdKey, value: groupId);
    } catch (e) {
      // Ignore cache errors
      print('Failed to cache group ID: $e');
    }
  }

  /// Get cached group ID
  Future<String?> _getCachedGroupId() async {
    try {
      return await _secureStorage.read(key: _groupIdKey);
    } catch (e) {
      return null;
    }
  }

  /// Cache group data
  Future<void> _cacheGroupData(FamilyGroupModel group) async {
    try {
      await _secureStorage.write(key: _groupDataKey, value: group.toJsonString());
    } catch (e) {
      print('Failed to cache group data: $e');
    }
  }

  /// Get cached group data
  Future<FamilyGroupModel?> _getCachedGroupData() async {
    try {
      final data = await _secureStorage.read(key: _groupDataKey);
      if (data != null) {
        return FamilyGroupModel.fromJsonString(data);
      }
    } catch (e) {
      return null;
    }
    return null;
  }

  @override
  Future<FamilyGroupModel> createGroup({required String name}) async {
    try {
      // Use RPC function to bypass RLS issues
      final groupResponse = await supabaseClient
          .rpc('create_family_group', params: {'group_name': name});

      if (groupResponse == null) {
        throw const ServerException('Errore nella creazione del gruppo');
      }

      return FamilyGroupModel.fromJson(groupResponse as Map<String, dynamic>);
    } on PostgrestException catch (e) {
      throw ServerException(e.message, e.code);
    } catch (e) {
      if (e is AppAuthException) rethrow;
      throw ServerException(e.toString());
    }
  }

  @override
  Future<FamilyGroupModel?> getCurrentGroup() async {
    try {
      final userId = _currentUserId;

      // Get user's profile to find group_id (with timeout to avoid hang when offline)
      final profileResponse = await supabaseClient
          .from('profiles')
          .select('group_id')
          .eq('id', userId)
          .single()
          .timeout(const Duration(seconds: 5));

      final groupId = profileResponse['group_id'] as String?;
      if (groupId == null) {
        return null;
      }

      // Cache the group ID for offline use
      await _cacheGroupId(groupId);

      // Get the group
      final groupResponse = await supabaseClient
          .from('family_groups')
          .select()
          .eq('id', groupId)
          .single()
          .timeout(const Duration(seconds: 5));

      // Get member count
      final memberCount = await supabaseClient
          .from('profiles')
          .select()
          .eq('group_id', groupId)
          .count(CountOption.exact)
          .timeout(const Duration(seconds: 5));

      final group = FamilyGroupModel.fromJson(groupResponse);
      final groupWithCount = group.copyWith(memberCount: memberCount.count);

      // Cache the group data for offline use
      await _cacheGroupData(groupWithCount);

      return groupWithCount;
    } catch (e) {
      // ANY error (timeout, SocketException, network) → try cache
      final cachedGroup = await _getCachedGroupData();
      if (cachedGroup != null) {
        return cachedGroup;
      }

      // No cache — rethrow with proper type
      if (e is AppAuthException) rethrow;
      if (e is PostgrestException && e.code == 'PGRST116') return null;
      throw ServerException(e.toString());
    }
  }

  @override
  Future<FamilyGroupModel> getGroup({required String groupId}) async {
    try {
      final groupResponse = await supabaseClient
          .from('family_groups')
          .select()
          .eq('id', groupId)
          .single();

      // Get member count
      final memberCount = await supabaseClient
          .from('profiles')
          .select()
          .eq('group_id', groupId)
          .count(CountOption.exact);

      final group = FamilyGroupModel.fromJson(groupResponse);
      return group.copyWith(memberCount: memberCount.count);
    } on PostgrestException catch (e) {
      throw ServerException(e.message, e.code);
    } catch (e) {
      throw ServerException(e.toString());
    }
  }

  @override
  Future<List<MemberModel>> getGroupMembers({required String groupId}) async {
    try {
      // Get the group to know who the admin is
      final groupResponse = await supabaseClient
          .from('family_groups')
          .select('created_by')
          .eq('id', groupId)
          .single();

      final adminId = groupResponse['created_by'] as String;

      // Get all members (profiles with this group_id)
      final membersResponse = await supabaseClient
          .from('profiles')
          .select()
          .eq('group_id', groupId)
          .order('created_at');

      return (membersResponse as List)
          .map((json) => MemberModel.fromJson(json, adminId))
          .toList();
    } on PostgrestException catch (e) {
      throw ServerException(e.message, e.code);
    } catch (e) {
      throw ServerException(e.toString());
    }
  }

  @override
  Future<void> leaveGroup() async {
    try {
      final userId = _currentUserId;

      // Get user's current group
      final profileResponse = await supabaseClient
          .from('profiles')
          .select('group_id')
          .eq('id', userId)
          .single();

      final groupId = profileResponse['group_id'] as String?;
      if (groupId == null) {
        throw const GroupException('Non fai parte di nessun gruppo', 'not_in_group');
      }

      // Check if user is admin
      final groupResponse = await supabaseClient
          .from('family_groups')
          .select('created_by')
          .eq('id', groupId)
          .single();

      final adminId = groupResponse['created_by'] as String;
      if (adminId == userId) {
        // Check if there are other members
        final memberCount = await supabaseClient
            .from('profiles')
            .select()
            .eq('group_id', groupId)
            .count(CountOption.exact);

        if (memberCount.count > 1) {
          throw const GroupException(
            'L\'amministratore non può lasciare il gruppo se ci sono altri membri',
            'admin_cannot_leave',
          );
        }
      }

      // Leave the group
      await supabaseClient
          .from('profiles')
          .update({'group_id': null})
          .eq('id', userId);
    } on PostgrestException catch (e) {
      throw ServerException(e.message, e.code);
    } catch (e) {
      if (e is AppAuthException || e is GroupException) rethrow;
      throw ServerException(e.toString());
    }
  }

  @override
  Future<void> removeMember({required String userId}) async {
    try {
      final currentUserId = _currentUserId;

      // Get current user's group
      final profileResponse = await supabaseClient
          .from('profiles')
          .select('group_id')
          .eq('id', currentUserId)
          .single();

      final groupId = profileResponse['group_id'] as String?;
      if (groupId == null) {
        throw const GroupException('Non fai parte di nessun gruppo', 'not_in_group');
      }

      // Check if current user is admin
      final groupResponse = await supabaseClient
          .from('family_groups')
          .select('created_by')
          .eq('id', groupId)
          .single();

      final adminId = groupResponse['created_by'] as String;
      if (adminId != currentUserId) {
        throw const GroupException(
          'Solo l\'amministratore può rimuovere membri',
          'not_admin',
        );
      }

      // Cannot remove yourself
      if (userId == currentUserId) {
        throw const GroupException('Non puoi rimuovere te stesso', 'cannot_remove_self');
      }

      // Remove the member
      await supabaseClient
          .from('profiles')
          .update({'group_id': null})
          .eq('id', userId)
          .eq('group_id', groupId);
    } on PostgrestException catch (e) {
      throw ServerException(e.message, e.code);
    } catch (e) {
      if (e is AppAuthException || e is GroupException) rethrow;
      throw ServerException(e.toString());
    }
  }

  @override
  Future<FamilyGroupModel> updateGroupName({required String name}) async {
    try {
      final userId = _currentUserId;

      // Get user's group
      final profileResponse = await supabaseClient
          .from('profiles')
          .select('group_id')
          .eq('id', userId)
          .single();

      final groupId = profileResponse['group_id'] as String?;
      if (groupId == null) {
        throw const GroupException('Non fai parte di nessun gruppo', 'not_in_group');
      }

      // Check if user is admin
      final groupResponse = await supabaseClient
          .from('family_groups')
          .select('created_by')
          .eq('id', groupId)
          .single();

      final adminId = groupResponse['created_by'] as String;
      if (adminId != userId) {
        throw const GroupException(
          'Solo l\'amministratore può modificare il nome del gruppo',
          'not_admin',
        );
      }

      // Update the group name
      final updatedGroup = await supabaseClient
          .from('family_groups')
          .update({'name': name})
          .eq('id', groupId)
          .select()
          .single();

      return FamilyGroupModel.fromJson(updatedGroup);
    } on PostgrestException catch (e) {
      throw ServerException(e.message, e.code);
    } catch (e) {
      if (e is AppAuthException || e is GroupException) rethrow;
      throw ServerException(e.toString());
    }
  }

  @override
  Future<void> deleteGroup() async {
    try {
      final userId = _currentUserId;

      // Get user's group
      final profileResponse = await supabaseClient
          .from('profiles')
          .select('group_id')
          .eq('id', userId)
          .single();

      final groupId = profileResponse['group_id'] as String?;
      if (groupId == null) {
        throw const GroupException('Non fai parte di nessun gruppo', 'not_in_group');
      }

      // Check if user is admin
      final groupResponse = await supabaseClient
          .from('family_groups')
          .select('created_by')
          .eq('id', groupId)
          .single();

      final adminId = groupResponse['created_by'] as String;
      if (adminId != userId) {
        throw const GroupException(
          'Solo l\'amministratore può eliminare il gruppo',
          'not_admin',
        );
      }

      // Check if there are other members
      final memberCount = await supabaseClient
          .from('profiles')
          .select()
          .eq('group_id', groupId)
          .count(CountOption.exact);

      if (memberCount.count > 1) {
        throw const GroupException(
          'Il gruppo non può essere eliminato se ci sono altri membri',
          'has_members',
        );
      }

      // Remove user from group
      await supabaseClient
          .from('profiles')
          .update({'group_id': null})
          .eq('id', userId);

      // Delete the group
      await supabaseClient
          .from('family_groups')
          .delete()
          .eq('id', groupId);
    } on PostgrestException catch (e) {
      throw ServerException(e.message, e.code);
    } catch (e) {
      if (e is AppAuthException || e is GroupException) rethrow;
      throw ServerException(e.toString());
    }
  }
}
