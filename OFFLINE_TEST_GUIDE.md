# T15 — Test Offline su Device Reale (Airplane Mode)

## Prerequisiti
- Android device fisico (Android 8+) o iOS 13+
- Build debug: `flutter run`
- Account Finn già registrato

---

## Test 1: Avvio App in Airplane Mode

**Setup:**
1. Apri Impostazioni → abilita **Modalità Aereo**
2. Verifica che WiFi e dati mobili siano OFF
3. Forza chiusura dell'app se aperta

**Passi:**
1. Apri l'app Finn
2. Attendi max 3 secondi

**Expected:**
- ✅ App si apre (NON blocca su splash)
- ✅ Schermata principale visibile (non spinner infinito)
- ✅ Dati cachati mostrati (spese precedenti)
- ✅ Banner arancione "Offline - X expenses pending sync" visibile (se ci sono pending)

**Failure prima di questa issue (#30):**
- ❌ App bloccata su splash screen indefinitamente
- ❌ Nessun dato visibile

---

## Test 2: Aggiunta Spesa Offline

**Setup:** Airplane mode attiva

**Passi:**
1. Premi FAB (+) → "Inserimento manuale"
2. Inserisci: importo €25, categoria "Alimentari", data oggi
3. Premi "Salva"

**Expected:**
- ✅ Spesa salvata localmente (Drift DB)
- ✅ Toast/feedback di conferma
- ✅ Spesa appare nella lista con icona ☁️↑ (pending sync)
- ✅ Banner mostra "+1 expense pending sync"

---

## Test 3: Ripristino Connessione → Auto-Sync

**Setup:** Spesa offline aggiunta (Test 2 completato)

**Passi:**
1. Disabilita Airplane Mode
2. Attendi 3-5 secondi (auto-sync trigger)

**Expected:**
- ✅ Banner blu "Syncing 1 expense..." appare
- ✅ Dopo sync completata: banner sparisce
- ✅ Spesa visibile nella lista con stato synced
- ✅ Spesa visibile su altro device/web Supabase

---

## Test 4: Riavvio App con Dati Cachati

**Setup:** Connessione attiva, alcune spese già sincronizzate

**Passi:**
1. Abilita Airplane Mode
2. Forza chiusura app
3. Riapri app

**Expected:**
- ✅ App aperta in < 3 secondi
- ✅ Spese precedenti visibili (da cache Drift)
- ✅ Categorie visibili (da cache Drift)
- ✅ Info utente/gruppo visibili (da Hive/SecureStorage)

---

## Test 5: Timeout Supabase Init

**Setup:** Simula rete molto lenta (usa Android Dev Settings → "Simulate slow network")

**Passi:**
1. Imposta rete a 2G (emulato)
2. Forza chiusura app
3. Riapri app

**Expected:**
- ✅ App si apre entro 12 secondi (10s timeout Supabase init)
- ✅ Dati cachati mostrati in attesa del caricamento remoto
- ✅ Dopo timeout: banner "Offline" visibile se sync fallisce

---

## Checklist Criteri di Accettazione

| Test | Risultato | Note |
|------|-----------|------|
| T1: App apre in airplane mode | ⬜ | |
| T2: Spesa salvata offline | ⬜ | |
| T3: Auto-sync al ritorno online | ⬜ | |
| T4: Dati cachati dopo riavvio | ⬜ | |
| T5: Timeout 10s Supabase init | ⬜ | |

---

## Note Implementative

### Cosa è stato cambiato (Issue #30)
- `main.dart`: Supabase.initialize() con `.timeout(10s)` + try/catch
- `auth_remote_datasource.dart`: tutti i query Supabase con `.timeout(5s)` + Hive fallback
- `expense_remote_datasource.dart`: `.timeout(5s)` su query + fallback a Drift DB
- `category_remote_datasource.dart`: `.timeout(5s)` + fallback a CachedCategories (Drift)
- `group_remote_datasource.dart`: `.timeout(5s)` + parallelize + fallback SecureStorage
- `expense_provider.dart`: wired con `offlineExpenseLocalDataSource`
- `main_navigation_screen.dart`: `SyncStatusBanner` integrata

### Architettura Offline-First
```
App Start
├── Hive init (sync, local)
├── Supabase init (async, timeout 10s, fallback: OK)
└── runApp() → sempre subito

Auth Init
├── Try: profiles query (timeout 5s)
└── Catch: load from Hive 'dashboard_cache'['cached_user_profile']

Expense Load
├── Try: Supabase query (timeout 5s)
└── Catch: load from Drift offline_expenses

Category Load
├── Try: Supabase query (timeout 5s) + cache to Drift
└── Catch: load from Drift cached_categories

Group Load
├── Try: Supabase query (timeout 5s, parallel)
└── Catch: load from FlutterSecureStorage 'cached_group_data'

Write (CreateExpense)
├── Try: Supabase INSERT
└── Catch: save to Drift offline_expenses (syncStatus='pending')

Auto-Sync
└── SyncTrigger listens to ConnectivityService
    └── On NetworkStatus.online → processQueue()
```
