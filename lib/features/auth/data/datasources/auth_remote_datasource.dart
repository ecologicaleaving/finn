import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:hive_flutter/hive_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/errors/exceptions.dart';
import '../models/user_model.dart';

// T2/T3: Hive box key for cached user profile
const _kUserProfileBox = 'user_profile_cache';
const _kUserProfileKey = 'cached_user_profile';

/// Remote data source for authentication operations using Supabase.
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

  // ──────────────────────────────────────────────────────────────────────
  // T2/T3: Hive-backed user profile cache helpers
  // ──────────────────────────────────────────────────────────────────────

  Future<void> _cacheUserProfile(UserModel user) async {
    try {
      final box = Hive.box<String>(_kUserProfileBox);
      await box.put(_kUserProfileKey, jsonEncode(user.toJson()));
    } catch (_) {
      // Ignore cache write errors
    }
  }

  Future<UserModel?> _getCachedUserProfile() async {
    try {
      final box = Hive.box<String>(_kUserProfileBox);
      final raw = box.get(_kUserProfileKey);
      if (raw != null) {
        return UserModel.fromJson(jsonDecode(raw) as Map<String, dynamic>);
      }
    } catch (_) {
      // Ignore cache read errors
    }
    return null;
  }

  Future<void> _clearCachedUserProfile() async {
    try {
      final box = Hive.box<String>(_kUserProfileBox);
      await box.delete(_kUserProfileKey);
    } catch (_) {}
  }

  // ──────────────────────────────────────────────────────────────────────
  // T2: getCurrentUser() — 5s timeout + Hive fallback
  // ──────────────────────────────────────────────────────────────────────

  bool _isNetworkError(Object e) {
    if (e is TimeoutException) return true;
    if (e is SocketException) return true;
    if (e is HttpException) return true;
    return false;
  }

  @override
  Future<UserModel> getCurrentUser() async {
    final user = supabaseClient.auth.currentUser;
    if (user == null) {
      throw const AppAuthException(
          'Nessun utente autenticato', 'not_authenticated');
    }

    try {
      final response = await supabaseClient
          .from('profiles')
          .select()
          .eq('id', user.id)
          .single()
          .timeout(const Duration(seconds: 10));

      final userModel = UserModel.fromJson(response);
      // ✅ WRITE-THROUGH CACHE: always save after successful fetch
      await _cacheUserProfile(userModel);
      return userModel;
    } catch (e) {
      // Only fall back to cache for network errors — app errors bubble up
      if (!_isNetworkError(e)) rethrow;

      final cached = await _getCachedUserProfile();
      if (cached != null) {
        return cached;
      }
      rethrow;
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
        throw const AppAuthException(
            'Credenziali non valide', 'invalid_credentials');
      }

      // Fetch profile data
      try {
        print('[DATASOURCE] Fetching profile for user: ${response.user!.id}');
        final profileResponse = await supabaseClient
            .from('profiles')
            .select()
            .eq('id', response.user!.id)
            .single()
            .timeout(const Duration(seconds: 5));
        print('[DATASOURCE] Profile fetched successfully');

        final userModel = UserModel.fromJson(profileResponse);
        await _cacheUserProfile(userModel);
        return userModel;
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
        throw const AppAuthException(
            'Registrazione fallita', 'signup_failed');
      }

      // The profile is created by a database trigger
      await Future.delayed(const Duration(milliseconds: 500));

      final profileResponse = await supabaseClient
          .from('profiles')
          .select()
          .eq('id', response.user!.id)
          .single()
          .timeout(const Duration(seconds: 5));

      final userModel = UserModel.fromJson(profileResponse);
      await _cacheUserProfile(userModel);
      return userModel;
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
      await _clearCachedUserProfile();
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
        throw const AppAuthException(
            'Nessun utente autenticato', 'not_authenticated');
      }

      final response = await supabaseClient
          .from('profiles')
          .update({'display_name': displayName})
          .eq('id', user.id)
          .select()
          .single()
          .timeout(const Duration(seconds: 5));

      final userModel = UserModel.fromJson(response);
      await _cacheUserProfile(userModel);
      return userModel;
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
        throw const AppAuthException(
            'Nessun utente autenticato', 'not_authenticated');
      }

      if (anonymizeExpenses) {
        await supabaseClient
            .from('expenses')
            .update({'created_by_name': 'Utente eliminato'})
            .eq('created_by', user.id);
      }

      await supabaseClient.from('profiles').delete().eq('id', user.id);
      await _clearCachedUserProfile();
      await supabaseClient.auth.signOut();
    } on PostgrestException catch (e) {
      throw ServerException(e.message, e.code);
    } catch (e) {
      if (e is AppAuthException) rethrow;
      throw ServerException(e.toString());
    }
  }

  // ──────────────────────────────────────────────────────────────────────
  // T3: authStateChanges — 5s timeout + Hive fallback
  // ──────────────────────────────────────────────────────────────────────

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
            .single()
            .timeout(const Duration(seconds: 10));

        final userModel = UserModel.fromJson(response);
        // ✅ WRITE-THROUGH CACHE: save profile on every successful auth event
        await _cacheUserProfile(userModel);
        return userModel;
      } catch (e) {
        // Only fall back to cache for network errors
        if (!_isNetworkError(e)) {
          // App-level error (RLS, schema) — still try cache to not break auth flow
          final cached = await _getCachedUserProfile();
          return cached;
        }
        // Network error — return cached profile
        final cached = await _getCachedUserProfile();
        return cached;
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
