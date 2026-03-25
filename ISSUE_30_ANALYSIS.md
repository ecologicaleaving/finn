# Issue #30 - Offline-First Analysis Report

## 🎯 Obiettivo Issue
Riscrivere il supporto offline con approccio **offline-first**: ogni schermata carica dalla cache locale in primo, poi aggiorna in background da Supabase. L'utente non deve mai vedere spinner infiniti o hang senza rete.

**Nota**: Sostituisce issue #28 (6 rework falliti). Contiene lezioni cruciali su cosa NON fare.

---

## 📊 Struttura Progetto

### Architettura Generale
```
lib/
├── main.dart                           # Entry point, init Hive/Supabase/timezone
├── app/
│   ├── app.dart                        # Widget principale FamilyExpenseTrackerApp
│   ├── routes.dart                     # Go Router configuration + redirect logic
├── features/
│   ├── auth/                           # Authentication
│   ├── expenses/                       # Spese (CORE)
│   ├── categories/                     # Categorie
│   ├── groups/                         # Famiglia/Gruppi
│   ├── offline/                        # 🔑 OFFLINE SUPPORT (Already exists!)
│   ├── dashboard/                      # Dashboard
│   ├── budgets/                        # Budget
│   ├── scanner/                        # Receipt OCR
│   └── [other features]
├── shared/
│   └── services/
│       └── connectivity_service.dart   # Network status monitoring
├── core/
│   ├── errors/
│   │   ├── exceptions.dart            # AppAuthException, ServerException, etc.
│   │   └── failures.dart              # Failure types for Either<> pattern
│   └── [config, enums, etc.]
```

### Pattern Architetturale
- **Clean Architecture**: Domain → Data → Presentation
- **State Management**: Riverpod (riverpod_annotation + code-gen)
- **Repository Pattern**: Repository interface + Impl con datasource remoto
- **Error Handling**: Either<Failure, T> (dartz)
- **UI Pattern**: ConsumerWidget/StateNotifier

---

## 🔧 Componenti Chiave - Lettura Approfondita

### 1️⃣ **Startup Flow (main.dart → routes.dart → home_screen.dart)**

#### main.dart - Inicializzazione (CRITICA)
```dart
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // 1. Load .env
  await dotenv.load(fileName: ".env");
  
  // 2. Init timezone (important for expense dates)
  tz.initializeTimeZones();
  final timezoneInfo = await FlutterTimezone.getLocalTimezone();
  tz.setLocalLocation(tz.getLocation(deviceTimezone));
  
  // 3. Init Hive for local caching
  await Hive.initFlutter();
  await Hive.openBox<String>('dashboard_cache');
  await Hive.openBox<String>('wizard_cache');
  
  // 4. Init SharedPreferences (for widget state)
  final sharedPreferences = await SharedPreferences.getInstance();
  
  // 5. Init ShareIntent (images from other apps)
  await ShareIntentService.initialize();
  
  // 6. Init Supabase (NETWORK CALL - can block if offline)
  if (!kDemoMode) {
    Env.validate();
    await Supabase.initialize(
      url: Env.supabaseUrl,
      anonKey: Env.supabaseAnonKey,
    );
    
    // 7. Widget system init
    // ... widget setup ...
  }
  
  // 8. Run app
  runApp(ProviderScope(
    overrides: [sharedPreferencesProvider.overrideWithValue(sharedPreferences)],
    child: const FamilyExpenseTrackerApp(),
  ));
}
```

**⚠️ PROBLEMA CRITICO**: 
- Line "await Supabase.initialize(...)" è bloccante
- Se rete è giù, tutto si blocca prima di `runApp()`
- In airplane mode: app non si apre

**Soluzione proposta**:
- Supabase init DEVE essere non-blocking or fail-safe
- Use `.timeout()` on Supabase.initialize or wrap in try-catch with fallback

---

#### routes.dart - Router Configuration
```dart
final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: kDemoMode ? '/main' : '/',
    
    redirect: (context, state) {
      if (kDemoMode) return null;
      
      final session = Supabase.instance.client.auth.currentSession;
      final isAuthenticated = session != null;
      
      // AUTH GATING:
      // Not authenticated + not on auth route → go to login
      // Authenticated + on auth route → go to home
      // Authenticated + no group → go to no-group
      // Authenticated + has group → go to main (dashboard)
      
      // PROBLEMA: Supone che auth state è sempre disponibile
      // In offline: currentSession POTREBBE essere null anche se cached
    };
  );
});
```

#### home_screen.dart - Prima Schermata
```dart
class HomeScreen extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authProvider);
    
    if (authState.status == AuthStatus.initial || 
        authState.status == AuthStatus.loading) {
      return LoadingIndicator(message: 'Caricamento...');
    }
    
    if (!authState.isAuthenticated) {
      context.go('/login');
      return LoadingIndicator();
    }
    
    if (!authState.user!.hasGroup) {
      context.go('/no-group');
      return LoadingIndicator();
    }
    
    context.go('/main');
    return LoadingIndicator();
  }
}
```

**Flusso startup**:
```
main() 
  → Hive init (local cache) ✓
  → Supabase init (NETWORK) ⚠️ BLOCCA SE OFFLINE
  → runApp()
    → FamilyExpenseTrackerApp
      → GoRouter redirect
        → Home screen (shows LoadingIndicator)
          → authProvider watch
            → authRepository.getCurrentUser()
              → Supabase query (NETWORK) ⚠️ BLOCCA
              → If fails → AuthStatus.loading forever
          → If not auth → Login
          → If auth + no group → No-group
          → If auth + group → Main (Dashboard)
```

---

### 2️⃣ **Auth & User Session (auth_remote_datasource.dart)**

#### authStateChanges Stream - ⚠️ CRITICO
```dart
@override
Stream<UserModel?> get authStateChanges {
  return supabaseClient.auth.onAuthStateChange.asyncMap((event) async {
    final user = event.session?.user;
    if (user == null) return null;

    try {
      // ⚠️ NO TIMEOUT - Can hang forever in offline mode!
      final response = await supabaseClient
          .from('profiles')
          .select()
          .eq('id', user.id)
          .single();

      return UserModel.fromJson(response);
    } catch (_) {
      return null;  // Falls back to null, but stream callback is slow
    }
  });
}
```

**Problema**: 
- Viene usato nel provider chain per monitorare auth state changes
- Se offline, query senza timeout blocca l'intero stream auth
- App non si riavvia bene

**Lezione da #28**: "authStateChanges è bloccante — la callback che fa query profiles senza timeout blocca l'intero stream auth"

**Soluzione**: 
- Add `.timeout(Duration(seconds: 5))` a profile query
- Cache profilo in Hive e usa come fallback

---

#### getCurrentUser()
```dart
Future<UserModel> getCurrentUser() async {
  final user = supabaseClient.auth.currentUser;
  if (user == null) {
    throw const AppAuthException('Nessun utente autenticato', 'not_authenticated');
  }

  // FETCH profilo - NO TIMEOUT!
  final response = await supabaseClient
      .from('profiles')
      .select()
      .eq('id', user.id)
      .single();

  return UserModel.fromJson(response);
}
```

**Problema**: Nessun timeout, catch solo PostgrestException

---

### 3️⃣ **Expense Repository & Loading (expense_repository_impl.dart)**

Doppio strato:
1. **ExpenseRepositoryImpl** - Domain layer (Either<Failure, T> pattern)
2. **ExpenseRemoteDataSourceImpl** - Supabase queries

#### getExpenses() Flow
```dart
// Repository
Future<Either<Failure, List<ExpenseEntity>>> getExpenses({...}) async {
  try {
    final expenses = await remoteDataSource.getExpenses(...);
    return Right(expenses.map((e) => e.toEntity()).toList());
  } on AppAuthException catch (e) {
    return Left(AuthFailure(e.message));
  } on ServerException catch (e) {
    return Left(ServerFailure(e.message));
  }
}

// Remote DataSource
Future<List<ExpenseModel>> getExpenses({...}) async {
  final groupId = await _currentUserGroupId;  // ⚠️ Query senza timeout
  
  final query = supabaseClient
      .from('expenses')
      .select(...)
      .eq('group_id', groupId);
  
  // Apply filters...
  
  final response = await query;  // ⚠️ NO TIMEOUT
  return (response as List).map((json) => ExpenseModel.fromJson(json)).toList();
}
```

**Problemi**:
1. NO timeout su nessuna query Supabase
2. `_currentUserGroupId` fa query senza timeout
3. Se offline: app sta in loading state indefinitamente

---

### 4️⃣ **Categories (category_remote_datasource.dart)**

Simile a expenses. Metodi chiave:
- `getCategories()` - NO TIMEOUT
- `getCategoriesByMRU()` - NO TIMEOUT
- `updateCategoryUsage()` - RPC function, NO TIMEOUT

**Pattern**:
```dart
Future<List<ExpenseCategoryModel>> getCategories({
  required String groupId,
  bool includeExpenseCount = false,
}) async {
  final query = supabaseClient
      .from('expense_categories')
      .select(...);
  
  // NO TIMEOUT!
  final response = await query;
  return (response as List).map(...).toList();
}
```

---

### 5️⃣ **Groups (group_remote_datasource.dart)**

#### getCurrentGroup()
```dart
Future<FamilyGroupModel?> getCurrentGroup() async {
  final userId = _currentUserId;
  
  // Query profiles → groups
  // NO TIMEOUT on either!
  final response = await supabaseClient
      .from('profiles')
      .select('group_id, group:group_id(...)')
      .eq('id', userId)
      .single();
  
  return FamilyGroupModel.fromJson(response['group']);
}
```

**Nota**: File ha secure storage per cache (good!), ma non è usato su startup.

---

### 6️⃣ **Expense Providers (expense_provider.dart)**

#### Provider Chain
```dart
final expenseRemoteDataSourceProvider = Provider<ExpenseRemoteDataSource>((ref) {
  return ExpenseRemoteDataSourceImpl(supabaseClient: Supabase.instance.client);
});

final expenseRepositoryProvider = Provider<ExpenseRepository>((ref) {
  return ExpenseRepositoryImpl(
    remoteDataSource: ref.watch(expenseRemoteDataSourceProvider),
  );
});

final expenseListProvider =
    StateNotifierProvider<ExpenseListNotifier, ExpenseListState>((ref) {
  ref.watch(authProvider);  // Refresh when auth changes
  return ExpenseListNotifier(ref.watch(expenseRepositoryProvider));
});
```

#### ExpenseListNotifier.loadExpenses()
```dart
Future<void> loadExpenses({bool refresh = false}) async {
  state = state.copyWith(status: ExpenseListStatus.loading);
  
  // Call repository
  final result = await _expenseRepository.getExpenses(
    startDate: state.filterStartDate,
    endDate: state.filterEndDate,
    categoryId: state.filterCategoryId,
    createdBy: state.filterCreatedBy,
    reimbursementStatus: state.filterReimbursementStatus,
    isGroupExpense: state.filterIsGroupExpense,
    limit: 20,
    offset: refresh ? 0 : state.expenses.length,
  );
  
  result.fold(
    (failure) {
      state = state.copyWith(status: ExpenseListStatus.error);
    },
    (expenses) {
      state = state.copyWith(
        status: ExpenseListStatus.loaded,
        expenses: refresh ? expenses : [...state.expenses, ...expenses],
      );
    },
  );
}
```

**Problema**: Se query fallisce (offline), mostra error state.
Vorrebbe: mostra cached data in offline mode.

---

### 7️⃣ **Auth Provider (auth_provider.dart)**

#### AuthNotifier._init()
```dart
Future<void> _init() async {
  state = state.copyWith(status: AuthStatus.loading);
  
  final result = await _authRepository.getCurrentUser();
  result.fold(
    (failure) {
      state = state.copyWith(
        status: AuthStatus.unauthenticated,
        user: null,
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
```

**Problema**: 
- Se offline e no cache → unauthenticated
- App rimanda a login anche se l'utente era autenticato prima
- Nessun fallback a cached user

---

### 8️⃣ **Offline Feature (lib/features/offline/)**

**BUONE NOTIZIE**: Feature offline esiste già! 

#### File presenti:
```
lib/features/offline/
├── data/
│   ├── datasources/
│   │   ├── category_cache_datasource.dart
│   │   ├── offline_expense_local_datasource.dart
│   │   ├── offline_image_local_datasource.dart
│   ├── local/
│   │   └── offline_database.dart              # Drift database
│   ├── models/
│   │   ├── offline_expense_model.dart
│   │   ├── offline_expense_image_model.dart
│   │   ├── sync_conflict_model.dart
│   │   └── sync_queue_item_model.dart
├── domain/
│   ├── entities/
│   │   └── offline_expense_entity.dart        # OfflineExpenseEntity
│   ├── services/
│   │   ├── batch_sync_service.dart
│   │   └── sync_queue_processor.dart
├── infrastructure/
│   └── background_sync_service.dart
├── presentation/
│   ├── providers/
│   │   └── offline_providers.dart             # offlineDatabase, offlineExpenses, sync
│   ├── screens/
│   │   └── conflicts_screen.dart
│   └── widgets/
│       ├── sync_progress_indicator.dart
│       └── sync_status_banner.dart
```

#### OfflineDatabase (Drift)
Existe! Schema per:
- offline_expenses (id, user_id, amount, date, category_id, merchant, notes, etc.)
- offline_expense_images (id, expense_id, local_path, etc.)
- sync_queue_items (id, entity_id, operation, status, retry_count, etc.)

#### OfflineExpenseEntity
```dart
class OfflineExpenseEntity {
  final String id;
  final String userId;
  final double amount;
  final DateTime date;
  final String categoryId;
  final String? merchant;
  final String? notes;
  final bool isGroupExpense;
  final String localReceiptPath;
  final int? receiptImageSize;
  final String syncStatus;     // 'pending', 'syncing', 'completed', 'failed', 'conflict'
  final int retryCount;
  final DateTime lastSyncAttemptAt;
  final String syncErrorMessage;
  final bool hasConflict;
  final String serverVersionData;
  final DateTime localCreatedAt;
  final DateTime localUpdatedAt;
  
  // Methods
  bool get isPending => syncStatus == 'pending' || syncStatus == 'failed';
  bool get isSyncing => syncStatus == 'syncing';
  bool get isSynced => syncStatus == 'completed';
}
```

#### SyncQueueProcessor
```dart
class SyncQueueProcessor {
  // Retry delays: 30s, 2min, 5min
  static const List<int> _retryDelays = [30, 120, 300];
  static const int _batchSize = 10;
  
  Future<SyncQueueResult> processQueue() async {
    // Get pending items in batches
    // Group by operation (create, update, delete)
    // Call batch sync service
    // Update status based on results
  }
}
```

#### Offline Providers (offline_providers.dart)
```dart
@riverpod
OfflineDatabase offlineDatabase(OfflineDatabaseRef ref) { ... }

@riverpod
Stream<List<OfflineExpenseEntity>> offlineExpenses(OfflineExpensesRef ref) async* { ... }

@riverpod
Future<int> pendingSyncCount(PendingSyncCountRef ref) async { ... }

@riverpod
class SyncTrigger extends _$SyncTrigger {
  Future<void> sync() async {
    final processor = ref.read(syncQueueProcessorProvider);
    final result = await processor.processQueue();
  }
}
```

**Stato**: Feature offline è già implementata! 
Ma: **NON è integrata nel flusso principale**.

---

### 9️⃣ **Connectivity Service (shared/services/connectivity_service.dart)**

```dart
@riverpod
class ConnectivityService extends _$ConnectivityService {
  @override
  Stream<NetworkStatus> build() async* {
    // Initial check
    final initialResult = await _connectivity.checkConnectivity();
    yield await _mapResultsToStatus(initialResult);
    
    // Listen for changes with 2s debounce
    await for (final status in _subscription.stream) {
      yield status;
    }
  }
  
  Future<NetworkStatus> _mapResultsToStatus(
    List<ConnectivityResult> results,
  ) async {
    final hasNetworkInterface = results.any(
      (result) => result != ConnectivityResult.none,
    );
    
    if (!hasNetworkInterface) return NetworkStatus.offline;
    
    // Verify actual internet with Supabase ping
    return await _verifyInternetAccess() ? 
      NetworkStatus.online : NetworkStatus.offline;
  }
  
  Future<bool> _verifyInternetAccess() async {
    try {
      await Supabase.instance.client.auth.getUser().timeout(
        const Duration(seconds: 5),
      );
      return true;
    } catch (e) {
      return false;
    }
  }
}
```

**Bene**: Ha timeout di 5s per la verifica.
**Problema**: Usato solo da Offline feature, non dal resto dell'app.

---

## 🚨 Problemi Identificati (Lezioni da #28)

### Critical Issues

| Problema | Localizzazione | Impatto | Soluzione Proposta |
|----------|---|---|---|
| **Supabase.initialize() bloccante** | main.dart | App non si apre in offline | Timeout o try-catch fallback |
| **authStateChanges senza timeout** | auth_remote_datasource.dart | Stream auth bloccato | Add .timeout(5s) + cache fallback |
| **getCurrentUser() senza timeout** | auth_remote_datasource.dart | Auth init blocking | Add .timeout(5s) + Hive cache |
| **getExpenses senza timeout** | expense_remote_datasource.dart | Expense list hang | Add .timeout(5s) per query |
| **getCategories senza timeout** | category_remote_datasource.dart | Categories loading hang | Add .timeout(5s) |
| **getCurrentGroup senza timeout** | group_remote_datasource.dart | Group loading hang | Add .timeout(5s) |
| **_currentUserGroupId query senza timeout** | expense_remote_datasource.dart | Ogni getExpenses call blocca | Add .timeout(5s) |
| **Provider chain dipende da rete** | expense_provider.dart | No cached data fallback | Use offline datasource in chain |
| **authProvider._init() no fallback cache** | auth_provider.dart | Offline → unauthenticated | Load from Hive if query fails |
| **Offline feature non integrata** | offline/ | Code presente ma non usato | Wire into main provider chain |

### Medium Issues

- Nessun caching di categorie in Hive
- Nessun caching di group data in Hive
- Nessun caching di user profile in Hive
- Nessun indicator visivo di stato offline
- Nessun sync auto-trigger al ripristino rete
- Expense expense_repository non sa come fallback a offline

### Vincoli Tecnici

**Lezione #28**: "Timeout sequenziali si sommano — 3 query con 5s timeout = 15s worst case. Usare Future.wait con timeout globale o parallelizzare."

- startup flow ha ~5 query (profile, group, categories, expenses)
- Con timeout individuale 5s = 25s worst case
- **Soluzione**: Parallelizzare queries in Future.wait con timeout globale 10s

---

## 📦 Dipendenze Già Presenti

```yaml
# State Management
flutter_riverpod: ^2.4.0
riverpod_annotation: ^2.3.0

# Database - Offline
drift: ^2.14.0          # ✓ Local DB per offline expenses
sqlite3_flutter_libs: ^0.5.0
hive_flutter: ^1.1.0    # ✓ Key-value cache
flutter_secure_storage: ^9.0.0  # ✓ Secure caching

# Network
connectivity_plus: ^6.1.0  # ✓ Network status
workmanager: ^0.9.0        # ✓ Background sync

# Backend
supabase_flutter: ^2.0.0

# Utils
uuid: ^4.0.0
equatable: ^2.0.5
dartz: ^0.10.1
```

**Tutte le dipendenze necessarie sono già presenti!**

---

## 🏗️ Flusso Startup Attuale vs. Proposto

### ATTUALE (Online-Only)
```
main() 
  → Hive init
  → Supabase init (NETWORK) ⚠️ BLOCCA
  → runApp()
    → authProvider._init()
      → getCurrentUser() (NETWORK) ⚠️ BLOCCA
    → if auth → loadExpenses() (NETWORK) ⚠️ BLOCCA
    → if auth → loadCategories() (NETWORK) ⚠️ BLOCCA
    → if auth → getCurrentGroup() (NETWORK) ⚠️ BLOCCA
    → Show data or error
```

**Risultato offline**: App in loading loop, nessun dato visibile.

### PROPOSTO (Offline-First)
```
main()
  → Hive init ✓
  → Offline DB init ✓
  → Supabase init (timeout 5s, fallback OK)
  → runApp()
    → authProvider._init()
      → Try: getCurrentUser() (timeout 5s)
      → Catch: Load from Hive cache ✓
      → Show cached auth
    → if auth → loadExpenses()
      → Try: remoteDataSource.getExpenses() (timeout 5s)
      → Catch: Load from offline DB ✓
      → Show cached expenses
    → if auth → loadCategories()
      → Try: remoteDataSource.getCategories() (timeout 5s)
      → Catch: Load from Hive or offline DB ✓
      → Show cached categories
    → if auth → getCurrentGroup()
      → Try: remoteDataSource.getCurrentGroup() (timeout 5s)
      → Catch: Load from secure storage cache ✓
      → Show cached group
    → Show data (cached or fresh)
    → Trigger background sync when online
```

**Risultato offline**: App aperta subito, dati cachati visibili, no spinner.

---

## 🎯 File Critici da Modificare

### 1. Startup (Priority 1)

- **main.dart** - Timeout Supabase.initialize, background init
- **auth_remote_datasource.dart** - Add .timeout() a tutti query
  - `getCurrentUser()` line ~50
  - `authStateChanges` getter line ~220
  - `signInWithEmail()` - query profile
- **auth_provider.dart** - Fallback to Hive cache on failure

### 2. Data Layer (Priority 1)

- **expense_remote_datasource.dart** - Add .timeout() to all queries
  - `getExpenses()` line ~100
  - `_currentUserGroupId` line ~180
  - `createExpense()`, `updateExpense()`, etc.
- **category_remote_datasource.dart** - Add .timeout() to all queries
  - `getCategories()` 
  - `getCategoriesByMRU()`
  - `updateCategoryUsage()`
- **group_remote_datasource.dart** - Add .timeout() to all queries
  - `getCurrentGroup()`
  - `getGroupMembers()`

### 3. Cache Integration (Priority 2)

- **expense_provider.dart** - Add offline datasource to provider chain
- **category_remote_datasource.dart** - Cache categories in Hive
- **group_remote_datasource.dart** - Use secure storage cache
- **Create**: expense_cache_datasource.dart (Hive)

### 4. Offline Feature Integration (Priority 2)

- **offline_providers.dart** - Wire into main app
  - Auto-sync trigger when online
  - Pending sync count display
- **sync_status_banner.dart** - Show in main navigation
- **Create**: offline_expense_datasource.dart (wrapper around offline DB)

### 5. UI Feedback (Priority 3)

- Add sync status banner
- Add offline indicator
- Add pending sync count
- Refresh button for manual sync

---

## 📋 File Legati alla Issue

### Diretti (Core offline-first logic)
1. `lib/features/auth/data/datasources/auth_remote_datasource.dart` - Auth queries
2. `lib/features/expenses/data/datasources/expense_remote_datasource.dart` - Expense queries
3. `lib/features/categories/data/datasources/category_remote_datasource.dart` - Category queries
4. `lib/features/groups/data/datasources/group_remote_datasource.dart` - Group queries
5. `lib/main.dart` - Startup flow
6. `lib/app/routes.dart` - Router logic
7. `lib/features/auth/presentation/providers/auth_provider.dart` - Auth state

### Offline Support (già esistenti, da integrare)
8. `lib/features/offline/` - Entire offline feature
9. `lib/shared/services/connectivity_service.dart` - Network monitoring
10. `lib/features/offline/presentation/providers/offline_providers.dart` - Offline state

### Dipendenti (UI layer)
11. `lib/features/expenses/presentation/providers/expense_provider.dart` - Expense list provider
12. `lib/features/categories/presentation/providers/category_repository_provider.dart` - Category provider
13. `lib/features/auth/presentation/screens/home_screen.dart` - Startup screen
14. `lib/features/auth/presentation/screens/main_navigation_screen.dart` - Main app shell

### Supporto (Non modificare, solo per reference)
15. `lib/features/offline/data/local/offline_database.dart` - Drift DB schema
16. `lib/features/offline/domain/services/sync_queue_processor.dart` - Sync logic

---

## 🔑 Lezioni Critiche da Issue #28

### ⛔ Cosa NON Fare

1. **MAI usare `ref.watch(networkStatus)` nei data provider chain**
   - Causa rebuild cascade a ogni cambio network
   - Provider data si perde e ricarica male
   - Soluzione: Use networkStatus solo per trigger sync, non per costruzione provider

2. **SEMPRE .timeout(Duration(seconds: 5)) su query Supabase**
   - Offline = network hang infinito senza timeout
   - Fallback catch sia SocketException che TimeoutException che PostgrestException
   - Ogni datasource method DEVE avere timeout

3. **authStateChanges è bloccante**
   - La callback asyncMap che fa query senza timeout blocca tutto
   - Usare sempre fallback a profilo cachato in Hive
   - Separare auth stream (fast) da profile fetch (network)

4. **Startup app MAI blocking su rete**
   - `runApp()` DEVE partire subito
   - Sync è background/fire-and-forget
   - Use Future.wait o Future.delayed per async initialization

5. **FALLBACK catch TUTTI gli errori**
   - Non solo SocketException
   - Also TimeoutException, PostgrestException, generico Exception
   - Pattern: `try { remote + cache } catch (_) { cache only }`

6. **Timeout sequenziali si sommano**
   - 3 query × 5s timeout = 15s worst case
   - Usare Future.wait con timeout globale
   - Oppure parallelizzare queries

7. **TEST su device REALE in airplane mode**
   - Mock tests non catturano bug reali
   - Timeout behavior è diverso su device
   - Mandatory: Test on real device with airplane mode ON

---

## 📊 Stato Progetto

### Presente
- ✅ Offline database (Drift) - Exists
- ✅ Offline entity model - Exists
- ✅ Sync queue processor - Exists
- ✅ Batch sync service - Exists
- ✅ Connectivity monitoring - Exists
- ✅ Hive cache - Exists
- ✅ Secure storage - Exists

### Mancante/Da Integrare
- ❌ Timeout su query Supabase (auth, expense, category, group)
- ❌ Cache fallback in provider chain
- ❌ Auto-sync trigger on connectivity change
- ❌ Sync status UI (banner, indicator)
- ❌ Pending sync count display
- ❌ Category cache in Hive
- ❌ Group data cache

---

## 🧪 Testing Strategy

### Unit Tests Richiesti
1. auth_remote_datasource - timeout + fallback
2. expense_remote_datasource - timeout + fallback
3. category_remote_datasource - timeout + fallback
4. group_remote_datasource - timeout + fallback
5. auth_provider - offline auth state
6. expense_provider - offline expense list

### Widget Tests
1. Home screen in offline mode
2. Expense list with pending sync
3. Sync status banner

### E2E / Integration Tests
1. **Startup in airplane mode** (MANDATORY per AC)
2. Add expense offline → verify saved locally
3. Restore connection → verify sync
4. Reopen app offline → verify data
5. Multiple sync operations → verify no duplicates

### Device Testing (CRITICAL)
- **Real Android device** in airplane mode
- Verify: app opens, shows cached data, no spinner
- Add expense, restart app, verify persisted
- Turn off airplane mode, verify auto-sync

---

## 📝 Riepilogo Analisi

### Architettura Attuale
- Clean Architecture: Domain/Data/Presentation
- Riverpod per state management
- Repository pattern con Either<> error handling
- Offline feature esiste ma NON integrata

### Problemi Chiave
1. Nessun timeout su Supabase queries → hang offline
2. Nessun fallback a cache se rete fallisce
3. Offline feature non connessa al flusso principale
4. Startup bloccante su Supabase init

### Punti di Intervento
- auth_remote_datasource.dart (3 places)
- expense_remote_datasource.dart (5 places)
- category_remote_datasource.dart (4 places)
- group_remote_datasource.dart (2 places)
- auth_provider.dart (1 place)
- main.dart (1 place)
- expense_provider.dart (1 place)
- Aggiungere: offline_expense_datasource.dart (wrapper)
- Aggiungere: category_cache_service.dart (Hive cache)
- Aggiungere: sync_auto_trigger (connectivity listener)

### Dipendenze
- Tutte presenti (Drift, Hive, connectivity_plus, workmanager, uuid)
- No nuove dipendenze richieste

---

**Report generato**: 2026-03-25 10:02 GMT+1
**Status**: Pronto per implementazione offline-first
**Checkpoint 1 (Piano)**: Agente deve produrre piano dettagliato evitando i 7 problemi da #28
