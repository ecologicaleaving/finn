# PROJECT.md - Single Source of Truth

## Project Info
- **Name**: Finn
- **Version**: v1.6.1
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
- **URL Produzione**: https://finn.8020solutions.org — online dal 2026-11-09, HTTPS verificato tramite Cloudflare e direttamente sull'origine
- **Base web**: app non ancora pubblicata v1.6.1, `release/v1.6.1` (`586eace`), richiesta #81
- **Hosting**: Nginx su VPS `46.225.60.101`, release statiche in `/var/www/finn/releases/` e symlink `/var/www/finn/current`
- **DNS**: Cloudflare, record `A finn → 46.225.60.101`, proxy attivo, TTL automatico (creato dall'utente)
- **HTTPS origine**: Let's Encrypt emesso il 2026-11-09, scadenza 2027-02-07, in `/etc/letsencrypt/live/finn.8020solutions.org/`; ACME webroot `/var/www/letsencrypt`, timer Certbot attivo
- **Build Method**: `scripts/build-web.ps1` con Flutter 3.35.7 e configurazione client pubblica Supabase
- **Istruzioni**: [deploy e DNS](docs/CLOUDFLARE.md), [parità e verifica funzionale](docs/WEB_PARITY.md)

### 🗄️ Database
- **Provider**: supabase-cloud
- **Host**: ofsnyaplaowbduujuucb.supabase.co
- **Admin URL**: https://supabase.com/dashboard/project/ofsnyaplaowbduujuucb

### ⚙️ CI/CD
- **Pipeline**: github-actions (build APK, build web e test mirati)
- **Trigger**: APK su push/PR; web su PR e workflow_dispatch
- **CI Status**: web passing (run 42679724414); Flutter fissato a 3.35.7 in CI
- **Last Deploy**: mobile 2026-10-10 (v1.6.0); web 2026-11-10 (app v1.6.1, correzione titoli mensili #83)

### 🔑 Environment Variables (GitHub Secrets)

| Secret | Descrizione | Dove si trova |
|--------|-------------|---------------|
| `SUPABASE_URL` | URL progetto Supabase | Dashboard → Settings → API |
| `SUPABASE_ANON_KEY` | Chiave pubblica client | Dashboard → Settings → API |
| `AI_SERVICE_KEY` | API key scansione ricevute | Provider AI OCR |

**Secrets configurati**: sì
**Ultimo aggiornamento secrets**: 2026-02-14

## Repository
- **Main Branch**: master
- **Development Branch**: test
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
  3. `scripts/build-web.ps1` (Web PWA, configurazione client pubblica)
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
- **DONE**: #21 Feature — Entrate una tantum (income transactions)
- **DONE**: #26 Feature - Le mie spese divise per mese con navigazione e dettaglio per categoria
- **DONE**: #28 Feature - Supporto offline con cache locale e sync automatico
- **DONE**: v1.6.0 — fix del check generale (#45 offline, #46 sicurezza gruppi, #47 rimborsi, #48 lista/modifica spese, #49 categorie, #50 budget, #51 dashboard, #52 importi, #61 CI, #64 cambio account, #65 paginazione/cache, #66 data a mezzanotte, #67 scontrini, #68 riquadro GRUPPO) e #69 spese ricorrenti sul database
- **IN PROGRESS**: Advanced analytics e spending insights
- **TODO**: #11 Bug — Visualizzazione per mese nella dashboard mostra tutti zero
- **TODO**: Machine learning categorization automatica spese ricorrenti
- **TODO**: Dashboard web per amministrazione family accounts
- **IN PROGRESS**: #81 — app web v1.6.1 online via Nginx/Cloudflare; build e test browser passati, HTTPS verificato, prova autenticata e confronto CRUD con l'app da completare
- **DONE**: #83 — dettaglio spese mensili per categoria: titolo da note, negozio storico o categoria, con etichetta neutra quando non esiste testo; nessuna modifica ai dati
- **TODO**: Integrazione bancaria automatica via Open Banking
- **TODO**: Report fiscali automatici e export contabilità
- **TODO**: Subscription management e recurring expense alerts
- **TODO**: Investment tracking integration per portfolio overview

---
*Last Updated: 2026-11-10*
