import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../domain/entities/expense_category_entity.dart';
import '../../domain/repositories/category_repository.dart';
import 'category_repository_provider.dart';
import '../../../../core/config/default_italian_categories.dart';
import '../../../offline/data/datasources/category_cache_provider.dart';
import '../../../offline/data/datasources/category_cache_datasource.dart';

/// State for category management
class CategoryState {
  const CategoryState({
    this.categories = const [],
    this.isLoading = false,
    this.errorMessage,
  });

  final List<ExpenseCategoryEntity> categories;
  final bool isLoading;
  final String? errorMessage;

  CategoryState copyWith({
    List<ExpenseCategoryEntity>? categories,
    bool? isLoading,
    String? errorMessage,
  }) {
    return CategoryState(
      categories: categories ?? this.categories,
      isLoading: isLoading ?? this.isLoading,
      errorMessage: errorMessage,
    );
  }

  factory CategoryState.initial() {
    return const CategoryState();
  }

  /// Get default categories
  List<ExpenseCategoryEntity> get defaultCategories =>
      categories.where((c) => c.isDefault).toList();

  /// Get custom categories
  List<ExpenseCategoryEntity> get customCategories =>
      categories.where((c) => !c.isDefault).toList();

  /// Find category by ID
  ExpenseCategoryEntity? findById(String categoryId) {
    try {
      return categories.firstWhere((c) => c.id == categoryId);
    } catch (_) {
      return null;
    }
  }
}

/// Category provider for managing category state
class CategoryNotifier extends StateNotifier<CategoryState> {
  CategoryNotifier(
    this._repository,
    this._supabaseClient,
    this._cacheDataSource,
    this._groupId,
  ) : super(CategoryState.initial()) {
    _init();
  }

  final CategoryRepository _repository;
  final SupabaseClient _supabaseClient;
  final CategoryCacheDataSource _cacheDataSource;
  final String _groupId;

  RealtimeChannel? _categoriesChannel;

  Future<void> _init() async {
    await loadCategories();
    _subscribeToRealtimeChanges();
  }

  /// Load categories for the group
  Future<void> loadCategories({bool includeExpenseCount = false}) async {
    state = state.copyWith(isLoading: true, errorMessage: null);

    try {
      final result = await _repository.getCategories(
        groupId: _groupId,
        includeExpenseCount: includeExpenseCount,
      );

      result.fold(
        (failure) async {
          // Check if this is a network error
          if (_isNetworkError(failure.message)) {
            // Try to load from cache first
            final cachedCategories = await _loadFromCache();

            if (cachedCategories.isNotEmpty) {
              // Use cached categories (includes custom categories!)
              state = state.copyWith(
                categories: cachedCategories,
                isLoading: false,
                errorMessage: null,
              );
            } else {
              // No cache, use default Italian categories as last resort
              state = state.copyWith(
                categories: _getOfflineFallbackCategories(),
                isLoading: false,
                errorMessage: null,
              );
            }
          } else {
            state = state.copyWith(
              isLoading: false,
              errorMessage: failure.message,
            );
          }
        },
        (categories) {
          // Successfully loaded from server - cache them for offline use
          _cacheDataSource.cacheCategories(_groupId, categories).catchError((e) {
            // Cache failed but still show categories
            print('Failed to cache categories: $e');
          });

          state = state.copyWith(
            categories: categories,
            isLoading: false,
          );
        },
      );
    } catch (e) {
      // Check if this is a network-related exception
      if (e is SocketException ||
          e.toString().contains('SocketException') ||
          e.toString().contains('Failed host lookup') ||
          e.toString().contains('ClientException')) {
        // Try to load from cache first
        final cachedCategories = await _loadFromCache();

        if (cachedCategories.isNotEmpty) {
          // Use cached categories (includes custom categories!)
          state = state.copyWith(
            categories: cachedCategories,
            isLoading: false,
            errorMessage: null,
          );
        } else {
          // No cache, use default Italian categories as last resort
          state = state.copyWith(
            categories: _getOfflineFallbackCategories(),
            isLoading: false,
            errorMessage: null,
          );
        }
      } else {
        state = state.copyWith(
          isLoading: false,
          errorMessage: 'Failed to load categories: $e',
        );
      }
    }
  }

  /// Load categories from local cache
  Future<List<ExpenseCategoryEntity>> _loadFromCache() async {
    try {
      return await _cacheDataSource.getCachedCategories(_groupId);
    } catch (e) {
      // If cache fails, return empty list
      return [];
    }
  }

  /// Check if error message indicates a network error
  bool _isNetworkError(String? message) {
    if (message == null) return false;
    return message.contains('SocketException') ||
        message.contains('Failed host lookup') ||
        message.contains('ClientException') ||
        message.contains('NetworkException');
  }

  /// Get offline fallback categories using Italian defaults
  List<ExpenseCategoryEntity> _getOfflineFallbackCategories() {
    const uuid = Uuid();
    final now = DateTime.now();

    return DefaultItalianCategories.categories.map((categoryName) {
      return ExpenseCategoryEntity(
        id: 'offline-${uuid.v4()}',
        name: categoryName,
        groupId: _groupId,
        isDefault: true,
        createdAt: now,
        updatedAt: now,
      );
    }).toList();
  }

  /// Subscribe to Supabase realtime for multi-device sync
  void _subscribeToRealtimeChanges() {
    _categoriesChannel = _supabaseClient
        .channel('expense-categories-changes-$_groupId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'expense_categories',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'group_id',
            value: _groupId,
          ),
          callback: _handleRealtimeChange,
        )
        .subscribe();
  }

  /// Handle incoming realtime events from other devices
  void _handleRealtimeChange(PostgresChangePayload payload) {
    switch (payload.eventType) {
      case PostgresChangeEvent.insert:
      case PostgresChangeEvent.update:
      case PostgresChangeEvent.delete:
      case PostgresChangeEvent.all:
        // Reload categories to get updated list
        loadCategories();
        break;
    }
  }

  @override
  void dispose() {
    _categoriesChannel?.unsubscribe();
    super.dispose();
  }
}

/// Provider for category state
final categoryProvider = StateNotifierProvider.family<CategoryNotifier, CategoryState, String>(
  (ref, groupId) {
    final supabaseClient = Supabase.instance.client;
    final repository = ref.watch(categoryRepositoryProvider);
    final cacheDataSource = ref.watch(categoryCacheDataSourceProvider);

    return CategoryNotifier(
      repository,
      supabaseClient,
      cacheDataSource,
      groupId,
    );
  },
);

// ========== MRU (Most Recently Used) Category Provider (Feature 001 T052) ==========

/// State for MRU-ordered categories
class MRUCategoryState {
  const MRUCategoryState({
    this.categories = const [],
    this.isLoading = false,
    this.errorMessage,
  });

  final List<ExpenseCategoryEntity> categories;
  final bool isLoading;
  final String? errorMessage;

  MRUCategoryState copyWith({
    List<ExpenseCategoryEntity>? categories,
    bool? isLoading,
    String? errorMessage,
  }) {
    return MRUCategoryState(
      categories: categories ?? this.categories,
      isLoading: isLoading ?? this.isLoading,
      errorMessage: errorMessage,
    );
  }

  factory MRUCategoryState.initial() {
    return const MRUCategoryState();
  }
}

/// Notifier for MRU-ordered categories
class MRUCategoryNotifier extends StateNotifier<MRUCategoryState> {
  MRUCategoryNotifier(
    this._repository,
    this._groupId,
    this._userId,
  ) : super(MRUCategoryState.initial()) {
    loadCategoriesByMRU();
  }

  final CategoryRepository _repository;
  final String _groupId;
  final String _userId;

  /// Load categories ordered by MRU (Most Recently Used)
  Future<void> loadCategoriesByMRU() async {
    state = state.copyWith(isLoading: true, errorMessage: null);

    final result = await _repository.getCategoriesByMRU(
      groupId: _groupId,
      userId: _userId,
    );

    result.fold(
      (failure) {
        state = state.copyWith(
          isLoading: false,
          errorMessage: failure.message,
        );
      },
      (categories) {
        state = state.copyWith(
          categories: categories,
          isLoading: false,
        );
      },
    );
  }

  /// Update category usage tracking after selecting a category
  Future<void> updateCategoryUsage(String categoryId) async {
    await _repository.updateCategoryUsage(
      userId: _userId,
      categoryId: categoryId,
    );

    // Reload categories to reflect new MRU order
    await loadCategoriesByMRU();
  }
}

/// Provider for MRU-ordered categories
///
/// Usage: categoryMRUProvider((groupId: 'xxx', userId: 'yyy'))
final categoryMRUProvider = StateNotifierProvider.family<
    MRUCategoryNotifier,
    MRUCategoryState,
    ({String groupId, String userId})>(
  (ref, params) {
    final repository = ref.watch(categoryRepositoryProvider);

    return MRUCategoryNotifier(
      repository,
      params.groupId,
      params.userId,
    );
  },
);
