import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/errors/failures.dart';
import '../../domain/entities/payment_method_entity.dart';
import '../../domain/repositories/payment_method_repository.dart';
import '../../data/datasources/payment_method_remote_datasource.dart';
import '../../data/repositories/payment_method_repository_impl.dart';

/// State class for payment method management.
class PaymentMethodState {
  const PaymentMethodState({
    this.paymentMethods = const [],
    this.isLoading = false,
    this.errorMessage,
  });

  final List<PaymentMethodEntity> paymentMethods;
  final bool isLoading;
  final String? errorMessage;

  /// Get default payment methods only.
  List<PaymentMethodEntity> get defaultMethods =>
      paymentMethods.where((m) => m.isDefault).toList();

  /// Get custom payment methods only.
  List<PaymentMethodEntity> get customMethods =>
      paymentMethods.where((m) => !m.isDefault).toList();

  /// Get payment method by ID.
  PaymentMethodEntity? getById(String id) =>
      paymentMethods.cast<PaymentMethodEntity?>().firstWhere(
            (m) => m?.id == id,
            orElse: () => null,
          );

  /// Get default "Contanti" method.
  PaymentMethodEntity? get defaultContanti => paymentMethods
      .cast<PaymentMethodEntity?>()
      .firstWhere(
        (m) => m?.name == 'Contanti' && m?.isDefault == true,
        orElse: () => null,
      );

  /// Check if list is empty.
  bool get isEmpty => paymentMethods.isEmpty;

  /// Check if has error.
  bool get hasError => errorMessage != null;

  /// Create a copy with updated fields.
  PaymentMethodState copyWith({
    List<PaymentMethodEntity>? paymentMethods,
    bool? isLoading,
    String? errorMessage,
  }) {
    return PaymentMethodState(
      paymentMethods: paymentMethods ?? this.paymentMethods,
      isLoading: isLoading ?? this.isLoading,
      errorMessage: errorMessage,
    );
  }
}

/// State notifier for payment method management.
class PaymentMethodNotifier extends StateNotifier<PaymentMethodState> {
  PaymentMethodNotifier({
    required PaymentMethodRepository repository,
    required this.userId,
  })  : _repository = repository,
        super(const PaymentMethodState()) {
    loadPaymentMethods();
  }

  final PaymentMethodRepository _repository;
  final String userId;

  static const String _cacheKey = 'cached_payment_methods';

  /// Load all payment methods for the current user.
  Future<void> loadPaymentMethods() async {
    state = state.copyWith(isLoading: true, errorMessage: null);

    final result = await _repository.getPaymentMethods(userId: userId);

    result.fold(
      (failure) async {
        // Try Hive cache first
        final cached = await _loadFromCache();
        if (cached.isNotEmpty) {
          state = state.copyWith(paymentMethods: cached, isLoading: false);
          return;
        }
        // Fallback: hardcoded default payment methods
        state = state.copyWith(
          paymentMethods: _getDefaultPaymentMethods(),
          isLoading: false,
          errorMessage: null,
        );
      },
      (paymentMethods) {
        _saveToCache(paymentMethods); // write-through cache
        state = state.copyWith(
          paymentMethods: paymentMethods,
          isLoading: false,
          errorMessage: null,
        );
      },
    );
  }

  /// Refresh payment methods (for manual refresh).
  Future<void> refresh() async {
    await loadPaymentMethods();
  }

  /// Save payment methods to Hive cache.
  Future<void> _saveToCache(List<PaymentMethodEntity> methods) async {
    try {
      final box = Hive.box<String>('dashboard_cache');
      final data = methods
          .map((m) => {
                'id': m.id,
                'name': m.name,
                'isDefault': m.isDefault,
                'userId': m.userId,
                'createdAt': m.createdAt.toIso8601String(),
                'updatedAt': m.updatedAt.toIso8601String(),
              })
          .toList();
      await box.put('${_cacheKey}_$userId', jsonEncode(data));
    } catch (_) {}
  }

  /// Load payment methods from Hive cache.
  Future<List<PaymentMethodEntity>> _loadFromCache() async {
    try {
      final box = Hive.box<String>('dashboard_cache');
      final raw = box.get('${_cacheKey}_$userId');
      if (raw != null) {
        final list = jsonDecode(raw) as List;
        return list
            .map((m) => PaymentMethodEntity(
                  id: m['id'] as String,
                  name: m['name'] as String,
                  isDefault: m['isDefault'] as bool,
                  userId: m['userId'] as String?,
                  createdAt: DateTime.parse(m['createdAt'] as String),
                  updatedAt: DateTime.parse(m['updatedAt'] as String),
                ))
            .toList();
      }
    } catch (_) {}
    return [];
  }

  /// Returns hardcoded default payment methods for offline fallback.
  List<PaymentMethodEntity> _getDefaultPaymentMethods() {
    final now = DateTime.now();
    return [
      PaymentMethodEntity(
        id: 'offline-contanti',
        name: 'Contanti',
        isDefault: true,
        userId: null,
        createdAt: now,
        updatedAt: now,
      ),
      PaymentMethodEntity(
        id: 'offline-carta',
        name: 'Carta di credito',
        isDefault: true,
        userId: null,
        createdAt: now,
        updatedAt: now,
      ),
      PaymentMethodEntity(
        id: 'offline-bancomat',
        name: 'Bancomat',
        isDefault: true,
        userId: null,
        createdAt: now,
        updatedAt: now,
      ),
      PaymentMethodEntity(
        id: 'offline-bonifico',
        name: 'Bonifico',
        isDefault: true,
        userId: null,
        createdAt: now,
        updatedAt: now,
      ),
    ];
  }
}

/// Provider for PaymentMethodRepository.
final paymentMethodRepositoryProvider = Provider<PaymentMethodRepository>((ref) {
  final supabaseClient = Supabase.instance.client;
  final remoteDataSource = PaymentMethodRemoteDataSourceImpl(
    supabaseClient: supabaseClient,
  );
  return PaymentMethodRepositoryImpl(
    remoteDataSource: remoteDataSource,
  );
});

/// Provider for PaymentMethodNotifier (family provider for user-scoped state).
final paymentMethodProvider = StateNotifierProvider.family<
    PaymentMethodNotifier,
    PaymentMethodState,
    String>((ref, userId) {
  final repository = ref.watch(paymentMethodRepositoryProvider);
  return PaymentMethodNotifier(
    repository: repository,
    userId: userId,
  );
});
