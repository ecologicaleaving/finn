import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/errors/exceptions.dart';
import '../../../../core/utils/invite_code_generator.dart';
import '../models/family_group_model.dart';
import '../models/invite_model.dart';
import 'group_rpc_result.dart';

/// Remote data source for invite operations using Supabase.
abstract class InviteRemoteDataSource {
  /// Create a new invite code for the current user's group.
  Future<InviteModel> createInvite();

  /// Get the active invite for the current user's group.
  Future<InviteModel?> getActiveInvite();

  /// Validate an invite code.
  Future<InviteModel> validateInviteCode({required String code});

  /// Join a group using an invite code.
  Future<FamilyGroupModel> joinGroupWithCode({required String code});
}

/// Implementation of [InviteRemoteDataSource] using Supabase.
class InviteRemoteDataSourceImpl implements InviteRemoteDataSource {
  InviteRemoteDataSourceImpl({required this.supabaseClient});

  final SupabaseClient supabaseClient;

  String get _currentUserId {
    final userId = supabaseClient.auth.currentUser?.id;
    if (userId == null) {
      throw const AppAuthException('Nessun utente autenticato', 'not_authenticated');
    }
    return userId;
  }

  @override
  Future<InviteModel> createInvite() async {
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

      // Check for existing valid invite and invalidate it
      final existingInvites = await supabaseClient
          .from('invites')
          .select()
          .eq('group_id', groupId)
          .isFilter('used_by', null)
          .gt('expires_at', DateTime.now().toIso8601String());

      for (final invite in existingInvites) {
        await supabaseClient
            .from('invites')
            .delete()
            .eq('id', invite['id']);
      }

      // Create the invite (expires in 7 days).
      // Invite codes of other groups are no longer readable (RLS), so the
      // uniqueness is enforced by the UNIQUE constraint on invites.code:
      // on a collision (23505) a new code is generated and the insert retried.
      final expiresAt = DateTime.now().add(const Duration(days: 7));
      const maxAttempts = 10;
      Map<String, dynamic>? inviteResponse;

      for (var attempt = 0; attempt < maxAttempts && inviteResponse == null; attempt++) {
        final code = InviteCodeGenerator.generate();
        try {
          inviteResponse = await supabaseClient
              .from('invites')
              .insert({
                'group_id': groupId,
                'code': code,
                'created_by': userId,
                'expires_at': expiresAt.toIso8601String(),
              })
              .select()
              .single();
        } on PostgrestException catch (e) {
          if (e.code != '23505') rethrow;
        }
      }

      if (inviteResponse == null) {
        throw const ServerException('Impossibile generare un codice univoco', 'code_generation_failed');
      }

      return InviteModel.fromJson(inviteResponse);
    } on PostgrestException catch (e) {
      throw ServerException(e.message, e.code);
    } catch (e) {
      if (e is AppAuthException || e is GroupException || e is ServerException) {
        rethrow;
      }
      throw ServerException(e.toString());
    }
  }

  @override
  Future<InviteModel?> getActiveInvite() async {
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
        return null;
      }

      // Get active invite (not used, not expired)
      final inviteResponse = await supabaseClient
          .from('invites')
          .select()
          .eq('group_id', groupId)
          .isFilter('used_by', null)
          .gt('expires_at', DateTime.now().toIso8601String())
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();

      if (inviteResponse == null) {
        return null;
      }

      return InviteModel.fromJson(inviteResponse);
    } on PostgrestException catch (e) {
      throw ServerException(e.message, e.code);
    } catch (e) {
      if (e is AppAuthException) rethrow;
      throw ServerException(e.toString());
    }
  }

  @override
  Future<InviteModel> validateInviteCode({required String code}) async {
    try {
      // Normalize code to uppercase (the server normalizes too)
      final normalizedCode = code.toUpperCase().trim();

      // Invites are not readable by non-admins: validation happens in a
      // SECURITY DEFINER function that returns only what the join needs and
      // raises invalid_code / already_used / expired.
      final response = await supabaseClient.rpc(
        'validate_invite_code',
        params: {'p_code': normalizedCode},
      );

      final row = response is List
          ? (response.isNotEmpty ? response.first : null)
          : response;

      if (row is! Map) {
        throw const InviteException('Codice invito non valido', 'invalid_code');
      }

      return InviteModel(
        id: '',
        groupId: row['group_id'] as String,
        code: normalizedCode,
        createdBy: '',
        expiresAt: DateTime.parse(row['expires_at'] as String),
      );
    } on PostgrestException catch (e) {
      throw mapGroupRpcError(e);
    } catch (e) {
      if (e is AppException) rethrow;
      throw ServerException(e.toString());
    }
  }

  @override
  Future<FamilyGroupModel> joinGroupWithCode({required String code}) async {
    try {
      if (supabaseClient.auth.currentUser == null) {
        throw const AppAuthException('Nessun utente autenticato', 'not_authenticated');
      }

      // Server-side: checks the user is not in a group, locks and validates
      // the invite, marks it used and sets group_id / is_group_admin = false.
      final response = await supabaseClient.rpc(
        'join_group_with_code',
        params: {'p_code': code.toUpperCase().trim()},
      );

      if (response is! Map) {
        throw const ServerException('Errore durante l\'ingresso nel gruppo');
      }

      return FamilyGroupModel.fromJson(Map<String, dynamic>.from(response));
    } on PostgrestException catch (e) {
      throw mapGroupRpcError(e);
    } catch (e) {
      if (e is AppException) rethrow;
      throw ServerException(e.toString());
    }
  }
}
