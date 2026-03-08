# PROJECT.md - Single Source of Truth

## Project Info
- **Name**: Finn
- **Version**: v1.3.0
- **Status**: production
- **Platforms**: apk, ios, web
- **Description**: App gestione finanze familiari con tracking spese, supporto multi-utente familiare e scansione ricevute AI-powered.

## Database
- **Provider**: supabase-cloud
- **Environment**: production
- **Database ID**: ofsnyaplaowbduujuucb
- **Schema**: sql-migrations
- **Migration Status**: current
- **Connection**:
  - DEV: supabase local (localhost:54321) — `supabase start`
  - PROD: environment injection via `--dart-define`
- **Backup**: auto-managed (Supabase Cloud)
- **Seed Data**: default categories + demo transactions
- **Admin URL**: https://supabase.com/dashboard/project/ofsnyaplaowbduujuucb

## Deployment

### 📱 App Mobile
- **APK Produzione**: GitHub Releases
- **APK Test**: N/A — build locale o emulatore
- **Build Method**: manual (`flutter build apk --release`)
- **Distribuzione**: GitHub Releases (direct install)

### 🌐 Frontend Web
- **URL Produzione**: N/A (Flutter web — non ancora deployato)
- **Build Method**: `flutter build web --release`

### 🗄️ Database
- **Provider**: supabase-cloud
- **Host**: ofsnyaplaowbduujuucb.supabase.co
- **Admin URL**: https://supabase.com/dashboard/project/ofsnyaplaowbduujuucb

### ⚙️ CI/CD
- **Pipeline**: github-actions (unit tests)
- **Trigger**: push to main
- **CI Status**: failing (pre-existing repository issues outside issue #28 scope)
- **Last Deploy**: 2026-02-14T20:47:00Z

### 🔑 Environment Variables (GitHub Secrets)

| Secret | Descrizione | Dove si trova |
|--------|-------------|---------------|
| `SUPABASE_URL` | URL progetto Supabase | Dashboard → Settings → API |
| `SUPABASE_ANON_KEY` | Chiave pubblica client | Dashboard → Settings → API |
| `AI_SERVICE_KEY` | API key scansione ricevute | Provider AI OCR |

**Secrets configurati**: sì
**Ultimo aggiornamento secrets**: 2026-02-14

## Repository
- **Main Branch**: main
- **Development Branch**: feature/issue-7-bug-totale-dashboard-non-si-aggiorna-aut
- **GitHub**: https://github.com/ecologicaleaving/finn

## Tech Stack
- **Frontend/Mobile**: Flutter 3.0+ + Dart 3.0+
- **State Management**: Riverpod
- **Navigation**: go_router
- **Database**: Supabase Cloud PostgreSQL
- **Auth**: Supabase Auth (multi-user family support)
- **AI Integration**: Receipt OCR + expense categorization
- **Charts**: FL Chart
- **Deployment**: GitHub Releases (mobile) + manual (web)

## Services
- **App Mobile/Desktop**: Flutter multi-platform (Android, iOS, Windows, macOS, Linux)
- **Web App**: Flutter web (PWA)
- **Backend API**: Supabase Edge Functions
- **Database**: Supabase Cloud PostgreSQL
- **AI Service**: Receipt scanning + expense categorization

## Monitoring
- **Health Check**: App startup + database connectivity
- **Database Health**: https://supabase.com/dashboard/project/ofsnyaplaowbduujuucb
- **Alerts**: enabled (budget violations, failed syncs)
- **Auto Deploy**: false (build manuale)

## Development
- **Local Setup**:
  1. `flutter pub get`
  2. Copia `.env.example` in `.env.dev` con le credenziali
  3. `supabase start` (DB locale)
  4. `flutter run`
- **Build Process**:
  1. `flutter build apk --release` (Android)
  2. `flutter build ios --release` (iOS)
  3. `flutter build web --release` (Web PWA)
  4. `flutter build windows/macos/linux` (Desktop)

## Testing

### Strumenti
- **Framework Unit/Widget**: flutter_test
- **Framework E2E**: N/A
- **Run Unit Tests**: `flutter test`
- **Coverage**: optional

### Ambienti di test
- **Dispositivo/Emulatore**: emulatore Android / device fisico
- **Web**: `flutter run -d chrome`

### Flusso di test standard
1. Scrivi/aggiorna widget test per la feature
2. `flutter test` — tutti verdi prima di aprire PR
3. Verifica manuale su emulatore o device
4. Nessuna regressione su schermate esistenti

## Troubleshooting
- **Build fallita**: `flutter clean` + `flutter pub get`
- **DB non raggiungibile**: verifica credenziali Supabase + `supabase status` in locale
- **AI Service**: verifica `AI_SERVICE_KEY` + endpoint provider
- **Sync**: verifica autenticazione utente + connettività

## Backlog
- **DONE**: Core expense tracking + multi-user family support
- **DONE**: Receipt scanning AI integration
- **DONE**: Bug #6 — Default category not saved on add expense
- **DONE**: Bug #7 — Dashboard totale gruppo non si aggiornava dopo aggiunta spesa
- **DONE**: UX — Rimosso campo "Negozio" da schermata aggiunta/modifica spesa
- **DONE**: UX — Fix navigazione dopo eliminazione spesa
- **DONE**: #26 Feature - Le mie spese divise per mese con navigazione e dettaglio per categoria
- **DONE**: #28 Feature - Supporto offline con cache locale e sync automatico
- **IN PROGRESS**: Advanced analytics e spending insights
- **TODO**: #11 Bug — Visualizzazione per mese nella dashboard mostra tutti zero
- **TODO**: Machine learning categorization automatica spese ricorrenti
- **TODO**: Dashboard web per amministrazione family accounts
- **TODO**: Integrazione bancaria automatica via Open Banking
- **TODO**: Report fiscali automatici e export contabilità
- **TODO**: Subscription management e recurring expense alerts
- **TODO**: Investment tracking integration per portfolio overview

---
*Last Updated: 2026-03-08T21:48:06.8625855Z*

