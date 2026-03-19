import 'dart:convert';

import 'package:hive_flutter/hive_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/errors/exceptions.dart';
import '../models/user_model.dart';

/// Remote data source for authentication operations using Supabase Auth.
abstract class AuthRemoteDataSource {
  /// Get the currently authenticated user's profile.
  Future<UserModel> getCurrentUser();

  /// Sign in with email and password.
  Future<UserModel> signInWithEmail({
    required String email,
    required String password,
  });

  /// Register a new user with email and password.
  Future<UserModel> signUpWithEmail({
    required String email,
    required String password,
    required String displayName,
  });

  /// Sign out the current user.
  Future<void> signOut();

  /// Request a password reset email.
  Future<void> resetPassword({required String email});

  /// Update the current user's display name.
  Future<UserModel> updateDisplayName({required String displayName});

  /// Delete the current user's account.
  Future<void> deleteAccount({required bool anonymizeExpenses});

  /// Stream of authentication state changes.
  Stream<UserModel?> get authStateChanges;

  /// Check if a user is currently authenticated.
  bool get isAuthenticated;
}

/// Implementation of [AuthRemoteDataSource] using Supabase.
class AuthRemoteDataSourceImpl implements AuthRemoteDataSource {
  AuthRemoteDataSourceImpl({required this.supabaseClient});

  final SupabaseClient supabaseClient;

  static const _cachedProfileKey = 'cached_user_profile';

  /// Cache the user profile JSON in Hive for offline access
  Future<void> _cacheUserProfile(Map<String, dynamic> profileJson) async {
    try {
      final box = Hive.box<String>('expense_cache');
      await box.put(_cachedProfileKey, jsonEncode(profileJson));
    } catch (e) {
      print('[AUTH] Failed to cache user profile: $e');
    }
  }

  /// Load cached user profile from Hive
  UserModel? _loadCachedUserProfile() {
    try {
      final box = Hive.box<String>('expense_cache');
      final cached = box.get(_cachedProfileKey);
      if (cached != null) {
        final json = jsonDecode(cached) as Map<String, dynamic>;
        return UserModel.fromJson(json);
      }
    } catch (e) {
      print('[AUTH] Failed to load cached user profile: $e');
    }
    return null;
  }

  @override
  Future<UserModel> getCurrentUser() async {
    final user = supabaseClient.auth.currentUser;
    if (user == null) {
      throw const AppAuthException('Nessun utente autenticato', 'not_authenticated');
    }

    // Try to fetch profile from Supabase
    try {
      final response = await supabaseClient
          .from('profiles')
          .select()
          .eq('id', user.id)
          .single();

      // Cache profile for offline use
      await _cacheUserProfile(response);

      return UserModel.fromJson(response);
    } catch (profileError) {
      // Profile fetch failed (likely offline) — try cached profile
      print('[AUTH] Profile fetch failed, trying cache: $profileError');

      final cachedProfile = _loadCachedUserProfile();
      if (cachedProfile != null && cachedProfile.id == user.id) {
        print('[AUTH] Using cached profile for user ${user.id}');
        return cachedProfile;
      }

      // No cached profile available — rethrow as appropriate error
      if (profileError is PostgrestException) {
        throw ServerException(profileError.message, profileError.code);
      }
      if (profileError is AppAuthException) {
        rethrow;
      }
      throw ServerException(profileError.toString());
    }
  }

  @override
  Future<UserModel> signInWithEmail({
    required String email,
    required String password,
  }) async {
    print('[DATASOURCE] signInWithEmail starting...');
    try {
      print('[DATASOURCE] Calling supabase auth.signInWithPassword...');
      final response = await supabaseClient.auth.signInWithPassword(
        email: email,
        password: password,
      );
      print('[DATASOURCE] Auth response received, user: ${response.user?.id}');

      if (response.user == null) {
        print('[DATASOURCE] User is null!');
        throw const AppAuthException('Credenziali non valide', 'invalid_credentials');
      }

      // Fetch profile data
      try {
        print('[DATASOURCE] Fetching profile for user: ${response.user!.id}');
        final profileResponse = await supabaseClient
            .from('profiles')
            .select()
            .eq('id', response.user!.id)
            .single();
        print('[DATASOURCE] Profile fetched successfully');

        return UserModel.fromJson(profileResponse);
      } on PostgrestException catch (e) {
        // Profile fetch failed - maybe profile doesn't exist
        print('[DATASOURCE] Profile fetch failed: ${e.message}');
        throw AppAuthException('Errore profilo: ${e.message}', e.code);
      }
    } on AuthException catch (e) {
      print('[DATASOURCE] AuthException: ${e.message}');
      throw AppAuthException(_mapAuthErrorMessage(e.message), e.statusCode);
    } on PostgrestException catch (e) {
      print('[DATASOURCE] PostgrestException: ${e.message}');
      throw ServerException('Errore DB: ${e.message}', e.code);
    } catch (e) {
      print('[DATASOURCE] Unknown error: ${e.runtimeType}: $e');
      if (e is AppAuthException) rethrow;
      throw ServerException('Errore: ${e.runtimeType}: $e');
    }
  }

  @override
  Future<UserModel> signUpWithEmail({
    required String email,
    required String password,
    required String displayName,
  }) async {
    try {
      final response = await supabaseClient.auth.signUp(
        email: email,
        password: password,
        data: {'display_name': displayName},
      );

      if (response.user == null) {
        throw const AppAuthException('Registrazione fallita', 'signup_failed');
      }

      // The profile is created by a database trigger
      // Wait a moment for the trigger to complete
      await Future.delayed(const Duration(milliseconds: 500));

      // Fetch the created profile
      final profileResponse = await supabaseClient
          .from('profiles')
          .select()
          .eq('id', response.user!.id)
          .single();

      return UserModel.fromJson(profileResponse);
    } on AuthException catch (e) {
      throw AppAuthException(_mapAuthErrorMessage(e.message), e.statusCode);
    } on PostgrestException catch (e) {
      throw ServerException(e.message, e.code);
    } catch (e) {
      if (e is AppAuthException) rethrow;
      throw ServerException(e.toString());
    }
  }

  @override
  Future<void> signOut() async {
    try {
      await supabaseClient.auth.signOut();
    } on AuthException catch (e) {
      throw AppAuthException(_mapAuthErrorMessage(e.message), e.statusCode);
    } catch (e) {
      throw ServerException(e.toString());
    }
  }

  @override
  Future<void> resetPassword({required String email}) async {
    try {
      await supabaseClient.auth.resetPasswordForEmail(email);
    } on AuthException catch (e) {
      throw AppAuthException(_mapAuthErrorMessage(e.message), e.statusCode);
    } catch (e) {
      throw ServerException(e.toString());
    }
  }

  @override
  Future<UserModel> updateDisplayName({required String displayName}) async {
    try {
      final user = supabaseClient.auth.currentUser;
      if (user == null) {
        throw const AppAuthException('Nessun utente autenticato', 'not_authenticated');
      }

      final response = await supabaseClient
          .from('profiles')
          .update({'display_name': displayName})
          .eq('id', user.id)
          .select()
          .single();

      return UserModel.fromJson(response);
    } on PostgrestException catch (e) {
      throw ServerException(e.message, e.code);
    } catch (e) {
      if (e is AppAuthException) rethrow;
      throw ServerException(e.toString());
    }
  }

  @override
  Future<void> deleteAccount({required bool anonymizeExpenses}) async {
    try {
      final user = supabaseClient.auth.currentUser;
      if (user == null) {
        throw const AppAuthException('Nessun utente autenticato', 'not_authenticated');
      }

      // If anonymizing, update expenses with "Utente eliminato"
      if (anonymizeExpenses) {
        await supabaseClient
            .from('expenses')
            .update({'created_by_name': 'Utente eliminato'})
            .eq('created_by', user.id);
      }

      // Delete profile (will cascade or be handled by RLS)
      await supabaseClient.from('profiles').delete().eq('id', user.id);

      // Sign out
      await supabaseClient.auth.signOut();
    } on PostgrestException catch (e) {
      throw ServerException(e.message, e.code);
    } catch (e) {
      if (e is AppAuthException) rethrow;
      throw ServerException(e.toString());
    }
  }

  @override
  Stream<UserModel?> get authStateChanges {
    return supabaseClient.auth.onAuthStateChange.asyncMap((event) async {
      final user = event.session?.user;
      if (user == null) return null;

      try {
        final response = await supabaseClient
            .from('profiles')
            .select()
            .eq('id', user.id)
            .single();

        return UserModel.fromJson(response);
      } catch (_) {
        return null;
      }
    });
  }

  @override
  bool get isAuthenticated => supabaseClient.auth.currentUser != null;

  /// Map Supabase auth error messages to Italian
  String _mapAuthErrorMessage(String message) {
    final lowerMessage = message.toLowerCase();

    if (lowerMessage.contains('invalid login credentials') ||
        lowerMessage.contains('invalid_credentials')) {
      return 'Email o password non corretti';
    }
    if (lowerMessage.contains('email not confirmed')) {
      return 'Email non confermata. Controlla la tua casella di posta';
    }
    if (lowerMessage.contains('user already registered') ||
        lowerMessage.contains('already registered')) {
      return 'Questo indirizzo email è già registrato';
    }
    if (lowerMessage.contains('password') &&
        lowerMessage.contains('weak')) {
      return 'La password è troppo debole';
    }
    if (lowerMessage.contains('rate limit') ||
        lowerMessage.contains('too many requests')) {
      return 'Troppi tentativi. Riprova tra qualche minuto';
    }
    if (lowerMessage.contains('network') ||
        lowerMessage.contains('connection')) {
      return 'Errore di connessione. Controlla la tua rete';
    }

    return 'Si è verificato un errore. Riprova più tardi';
  }
}
