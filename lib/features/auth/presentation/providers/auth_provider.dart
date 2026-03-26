import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/datasources/auth_remote_datasource.dart';
import '../../data/models/user_model.dart';
import '../../data/repositories/auth_repository_impl.dart';
import '../../domain/entities/user_entity.dart';
import '../../domain/repositories/auth_repository.dart';

/// Provider for Supabase client
final supabaseClientProvider = Provider<SupabaseClient>((ref) {
  return Supabase.instance.client;
});

/// Provider for auth remote data source
final authRemoteDataSourceProvider = Provider<AuthRemoteDataSource>((ref) {
  return AuthRemoteDataSourceImpl(
    supabaseClient: ref.watch(supabaseClientProvider),
  );
});

/// Provider for auth repository
final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepositoryImpl(
    remoteDataSource: ref.watch(authRemoteDataSourceProvider),
  );
});

/// Auth state
enum AuthStatus {
  initial,
  loading,
  authenticated,
  unauthenticated,
  error,
}

/// Auth state class
class AuthState {
  const AuthState({
    this.status = AuthStatus.initial,
    this.user,
    this.errorMessage,
  });

  final AuthStatus status;
  final UserEntity? user;
  final String? errorMessage;

  AuthState copyWith({
    AuthStatus? status,
    UserEntity? user,
    String? errorMessage,
  }) {
    return AuthState(
      status: status ?? this.status,
      user: user ?? this.user,
      errorMessage: errorMessage,
    );
  }

  bool get isAuthenticated => status == AuthStatus.authenticated;
  bool get isLoading => status == AuthStatus.loading;
  bool get hasError => status == AuthStatus.error;
}

/// Auth notifier for managing authentication state
class AuthNotifier extends StateNotifier<AuthState> {
  AuthNotifier(this._authRepository) : super(const AuthState()) {
    _init();
  }

  final AuthRepository _authRepository;

  /// Try to load user from Hive cache directly (used as offline fallback)
  Future<UserEntity?> _loadCachedUser() async {
    try {
      final box = Hive.box<String>('user_profile_cache');
      final raw = box.get('cached_user_profile');
      if (raw != null) {
        final model = UserModel.fromJson(jsonDecode(raw) as Map<String, dynamic>);
        if (model.id.isNotEmpty) return model.toEntity();
      }
    } catch (_) {}
    return null;
  }

  /// Initialize auth state
  Future<void> _init() async {
    state = state.copyWith(status: AuthStatus.loading);

    final result = await _authRepository.getCurrentUser();
    await result.fold(
      (failure) async {
        // Fix #30: before giving up, try Hive cache (handles offline/session-null case)
        final cachedUser = await _loadCachedUser();
        if (cachedUser != null) {
          state = state.copyWith(
            status: AuthStatus.authenticated,
            user: cachedUser,
          );
        } else {
          state = state.copyWith(
            status: AuthStatus.unauthenticated,
            user: null,
          );
        }
      },
      (user) async {
        state = state.copyWith(
          status: AuthStatus.authenticated,
          user: user,
        );
      },
    );
  }

  /// Sign in with email and password
  Future<void> signInWithEmail({
    required String email,
    required String password,
  }) async {
    print('[AUTH] signInWithEmail called with email: $email');
    state = state.copyWith(status: AuthStatus.loading, errorMessage: null);

    final result = await _authRepository.signInWithEmail(
      email: email,
      password: password,
    );

    result.fold(
      (failure) {
        print('[AUTH] signInWithEmail FAILED: ${failure.message}');
        state = state.copyWith(
          status: AuthStatus.error,
          errorMessage: failure.message,
        );
      },
      (user) {
        print('[AUTH] signInWithEmail SUCCESS: ${user.email}');
        state = state.copyWith(
          status: AuthStatus.authenticated,
          user: user,
        );
      },
    );
  }

  /// Register with email and password
  Future<void> signUpWithEmail({
    required String email,
    required String password,
    required String displayName,
  }) async {
    state = state.copyWith(status: AuthStatus.loading, errorMessage: null);

    final result = await _authRepository.signUpWithEmail(
      email: email,
      password: password,
      displayName: displayName,
    );

    result.fold(
      (failure) {
        state = state.copyWith(
          status: AuthStatus.error,
          errorMessage: failure.message,
        );
      },
      (user) {
        state = state.copyWith(
          status: AuthStatus.authenticated,
          user: user,
        );
      },
    );
  }

  /// Sign out
  Future<void> signOut() async {
    state = state.copyWith(status: AuthStatus.loading, errorMessage: null);

    final result = await _authRepository.signOut();

    result.fold(
      (failure) {
        state = state.copyWith(
          status: AuthStatus.error,
          errorMessage: failure.message,
        );
      },
      (_) {
        state = state.copyWith(
          status: AuthStatus.unauthenticated,
          user: null,
        );
      },
    );
  }

  /// Request password reset
  Future<bool> resetPassword({required String email}) async {
    state = state.copyWith(status: AuthStatus.loading, errorMessage: null);

    final result = await _authRepository.resetPassword(email: email);

    return result.fold(
      (failure) {
        state = state.copyWith(
          status: AuthStatus.unauthenticated,
          errorMessage: failure.message,
        );
        return false;
      },
      (_) {
        state = state.copyWith(
          status: AuthStatus.unauthenticated,
        );
        return true;
      },
    );
  }

  /// Update display name
  Future<bool> updateDisplayName({required String displayName}) async {
    state = state.copyWith(status: AuthStatus.loading, errorMessage: null);

    final result = await _authRepository.updateDisplayName(
      displayName: displayName,
    );

    return result.fold(
      (failure) {
        state = state.copyWith(
          status: AuthStatus.authenticated,
          errorMessage: failure.message,
        );
        return false;
      },
      (user) {
        state = state.copyWith(
          status: AuthStatus.authenticated,
          user: user,
        );
        return true;
      },
    );
  }

  /// Delete account
  Future<bool> deleteAccount({required bool anonymizeExpenses}) async {
    state = state.copyWith(status: AuthStatus.loading, errorMessage: null);

    final result = await _authRepository.deleteAccount(
      anonymizeExpenses: anonymizeExpenses,
    );

    return result.fold(
      (failure) {
        state = state.copyWith(
          status: AuthStatus.authenticated,
          errorMessage: failure.message,
        );
        return false;
      },
      (_) {
        state = state.copyWith(
          status: AuthStatus.unauthenticated,
          user: null,
        );
        return true;
      },
    );
  }

  /// Clear error message
  void clearError() {
    state = state.copyWith(errorMessage: null);
  }

  /// Refresh current user
  Future<void> refreshUser() async {
    final result = await _authRepository.getCurrentUser();

    result.fold(
      (failure) {
        // Keep current state, just log the error
      },
      (user) {
        state = state.copyWith(user: user);
      },
    );
  }
}

/// Provider for auth state
final authProvider = StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  return AuthNotifier(ref.watch(authRepositoryProvider));
});

/// Convenience provider to check if user is authenticated
final isAuthenticatedProvider = Provider<bool>((ref) {
  return ref.watch(authProvider).isAuthenticated;
});

/// Convenience provider to get current user
final currentUserProvider = Provider<UserEntity?>((ref) {
  return ref.watch(authProvider).user;
});

/// Convenience provider to get current user ID
final currentUserIdProvider = Provider<String>((ref) {
  final user = ref.watch(currentUserProvider);
  if (user == null) {
    throw StateError('No authenticated user');
  }
  return user.id;
});

/// Convenience provider to check if user has a group
final hasGroupProvider = Provider<bool>((ref) {
  return ref.watch(authProvider).user?.hasGroup ?? false;
});
