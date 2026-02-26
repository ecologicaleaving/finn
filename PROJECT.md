# PROJECT.md - Single Source of Truth

## Project Info
- **Name**: Finn
- **Version**: v1.0.1
- **Status**: production
- **Platforms**: apk, ios, web
- **Description**: App gestione finanze familiari con tracking spese AI-powered

## Database
- **Provider**: supabase-cloud
- **Environment**: production
- **Database ID**: finn-family-expenses
- **Schema**: sql-migrations
- **Migration Status**: current
- **Connection**: 
  - DEV: supabase local (localhost:54321)
  - PROD: flutter environment injection
- **Backup**: auto (supabase managed)
- **Seed Data**: default categories + demo transactions
- **Admin URL**: https://supabase.com/dashboard

## Deployment
- **Live URL**: N/A (mobile/desktop app)
- **Deploy Method**: flutter-build
- **Deploy Host**: github-releases
- **CI Status**: passing
- **Last Deploy**: 2026-02-14T20:47:00Z
- **Environment Variables**: 
  - `SUPABASE_URL`: Flutter configuration
  - `SUPABASE_ANON_KEY`: Secure storage
  - `AI_SERVICE_KEY`: Receipt scanning API

## Repository
- **Main Branch**: main
- **Development Branch**: feature/ai-receipt-scanning
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
- **DONE**: Fix #6 - categoria default non salvata (CategorySelector race condition)
- **DONE**: Core expense tracking + multi-user family support
- **DONE**: Receipt scanning AI integration
- **IN PROGRESS**: Advanced analytics e spending insights
- **TODO**: Subscription management e recurring expense alerts
- **TODO**: Investment tracking integration per portfolio overview

---
*Last Updated: 2026-02-26T00:00:00Z*
*Auto-generated from: https://app.8020solutions.org/status.html*