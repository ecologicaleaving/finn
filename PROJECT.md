# PROJECT.md - Single Source of Truth

## Project Info
- **Name**: Finn
- **Version**: v1.1.1
- **Status**: production
- **Platforms**: apk, ios, web
- **Description**: App gestione finanze familiari con tracking spese AI-powered

## Database
- **Provider**: supabase-cloud
- **Environment**: production
- **Database ID**: ofsnyaplaowbduujuucb
- **Schema**: sql-migrations
- **Migration Status**: current
- **Connection**: 
  - DEV: supabase local (localhost:54321)
  - PROD: flutter environment injection
- **Backup**: auto (supabase managed)
- **Seed Data**: default categories + demo transactions
- **Admin URL**: https://supabase.com/dashboard/project/ofsnyaplaowbduujuucb

## Deployment
- **Live URL**: N/A (mobile/desktop app)
- **Deploy Method**: flutter-build
- **Deploy Host**: github-releases
- **CI Status**: passing (unit tests green)
- **Last Deploy**: 2026-02-14T20:47:00Z
- **Environment Variables**: 
  - `SUPABASE_URL`: Flutter configuration
  - `SUPABASE_ANON_KEY`: Secure storage
  - `AI_SERVICE_KEY`: Receipt scanning API

## Repository
- **Main Branch**: main
- **Development Branch**: feature/issue-11
- **GitHub**: https://github.com/ecologicaleaving/finn

## Tech Stack
- **Frontend**: Flutter 3.0+ + Dart 3.0+
- **Backend**: Supabase Edge Functions + PostgreSQL
- **Database**: PostgreSQL (via Supabase Cloud)
- **Auth**: Supabase Auth + multi-user family support
- **AI Integration**: Receipt scanning + expense categorization
- **Charts**: FL Chart for expense analytics

## Services
- **Mobile App**: Flutter multi-platform (Android, iOS)
- **Desktop App**: Flutter desktop (Windows, macOS, Linux)
- **Web App**: Flutter web compilation
- **Backend API**: Supabase Edge Functions
- **Database**: Supabase PostgreSQL Cloud
- **AI Service**: Receipt OCR + expense categorization

## Monitoring
- **Health Check**: App startup + database connectivity
- **Database Health**: Supabase dashboard monitoring
- **AI Service**: Receipt processing success rate
- **Alerts**: enabled (budget violations, failed syncs)
- **Auto Deploy**: manual (flutter build + testing)


## Build Flavors

| Flavor | App Name | App ID | Uso |
|--------|----------|--------|-----|
| prod | **Fin** | com.ecologicaleaving.fin | Master / produzione |
| dev | **Fin Dev** | com.ecologicaleaving.fin.dev | Branch / test |

**Comandi build:**
- Test (branch PR): lutter build apk --debug --flavor dev --target-platform android-arm64
- Produzione (master): lutter build apk --release --flavor prod --target-platform android-arm64

**Regola CI:**
- Branch -> debug + flavor dev -> APK nella cartella /test/
- Master -> release + flavor prod -> symlink finn-latest.apk
## Development
- **Local Setup**: 
  1. `flutter pub get` (dependencies)
  2. Copy `.env.example` to `.env.dev` with credentials
  3. `supabase start` (local development database)
  4. `flutter run` (development mode)
- **Build Process**: 
  1. `flutter build apk --release` (Android)
  2. `flutter build ios --release` (iOS)
  3. `flutter build web --release` (Web PWA)
  4. `flutter build windows/macos/linux` (Desktop)

## Troubleshooting
- **Database Issues**: Check Supabase connection + migration status
- **Build Failures**: `flutter clean` + dependency resolution
- **AI Service**: Verify API keys + service endpoint status
- **Sync Problems**: Check user authentication + network connectivity

## Backlog
- **TODO**: Machine learning categorization automatica spese ricorrenti
- **TODO**: Dashboard web per amministrazione family accounts
- **TODO**: Integrazione bancaria automatica via Open Banking
- **TODO**: Report fiscali automatici e export contabilità
- **TODO**: Notifiche smart per budget overrun e saving opportunities
- **DONE**: Core expense tracking + multi-user family support
- **DONE**: Receipt scanning AI integration
- **DONE**: Bug #6 — Default category not saved on add expense (moved auto-selection from CategorySelector.build() side-effect to ManualExpenseScreen ref.listen + initState)
- **DONE**: Bug #7 — Dashboard totale gruppo non si aggiornava dopo aggiunta spesa (groupMembersExpensesProvider/groupExpensesByCategoryProvider ora invalidati correttamente)
- **DONE**: Bug #11 � Dashboard visualizzazione per mese mostrava tutti zero (fix calcolo date range mensile in expensesByPeriodProvider: uso DateTime overflow handling al posto di formula manuale, e uso startDate.year/month nel loop di building dei risultati)
- **DONE**: UX — Rimosso campo "Negozio" da schermata aggiunta/modifica spesa
- **DONE**: Bug #11 � Dashboard visualizzazione per mese mostrava tutti zero (fix calcolo date range mensile in expensesByPeriodProvider: uso DateTime overflow handling al posto di formula manuale, e uso startDate.year/month nel loop di building dei risultati)
- **DONE**: UX — Fix navigazione: dopo eliminazione spesa si torna all'elenco corretto con bottom menu (context.push + context.pop invece di context.go)
- **IN PROGRESS**: Advanced analytics e spending insights
- **TODO**: Subscription management e recurring expense alerts
- **TODO**: Investment tracking integration per portfolio overview

---
*Last Updated: 2026-02-28T10:00:00Z*
*Auto-generated from: https://app.8020solutions.org/status.html*