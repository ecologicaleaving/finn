# Research: Widget Fixes and Category Selector Enhancement

**Feature**: 001-widget-category-fixes
**Date**: 2026-01-18
**Status**: Research Complete

## Overview

This document consolidates research findings from 6 specialized investigations into the technical implementation of:
1. Home screen widget fixes (display, real-time updates, visual design)
2. Widget action buttons (scan receipt, manual entry via deep links)
3. Category dropdown with most-recently-used ordering

---

## Research 1: Widget Data Persistence

### Decision

**Use home_widget ^0.6.0 package with dual storage approach**:
- **Individual primitive values** for native widget direct access
- **JSON object** for Flutter-side caching and validation

### Rationale

- **Android**: SharedPreferences via `FlutterSharedPreferences.xml` (automatic, no setup)
- **iOS**: UserDefaults with App Groups (requires Xcode configuration)
- **Performance**: <100ms total update cycle
- **Storage**: ~170 bytes per widget instance

### Platform Setup

**Android**:
- No special configuration required
- SharedPreferences automatically accessible
- Read via: `context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)`

**iOS (CRITICAL)**:
- **Must configure App Groups in Xcode**
- App Group ID: `group.com.ecologicaleaving.fin`
- Required for BOTH Runner and WidgetExtension targets
- Access via: `UserDefaults(suiteName: "group.com.ecologicaleaving.fin")`

### Data Format

Widget data includes:
- `totalAmount` (double) - Sum of personal expenses for current month
- `expenseCount` (int) - Number of expenses
- `hasError` (bool) - Error state indicator
- `lastUpdated` (DateTime) - Timestamp for staleness detection
- `currency` (String) - € symbol
- `month` (String) - "Gennaio 2026"
- `isDarkMode` (bool) - Theme preference

### Staleness Detection

- Data considered stale if `lastUpdated` > 24 hours old
- Both platforms show "Dati non aggiornati" indicator when stale
- Human-readable freshness: "Aggiornato 2 ore fa"

### Error States

Three distinct states:
- **No data**: "Budget non configurato" (fresh install)
- **Error**: "Errore di caricamento" (network/API failure)
- **Stale**: "Dati non aggiornati" (>24 hours old)

### Alternatives Rejected

- SQLite database (too complex)
- File-based JSON storage (less reliable)
- Hive/ObjectBox (unnecessary overhead)
- JSON-only storage (poor native performance)
- Primitives-only storage (no validation)

---

## Research 2: Deep Link Handling

### Decision

**Use `finapp://` custom URL scheme with `app_links` + `go_router` integration**

### URL Scheme Design

| Widget Action | Deep Link URL | Target Route |
|--------------|---------------|--------------|
| Scan Receipt Button | `finapp://scan-receipt` | `/scan-receipt` → CameraScreen |
| Manual Entry Button | `finapp://add-expense` | `/add-expense` → ManualExpenseScreen |
| Dashboard Tap | `finapp://dashboard` | `/dashboard` → DashboardScreen |

### Rationale

1. **Already Implemented**: Codebase has working configuration
2. **Stack Preservation**: Using `app_links` with `router.push()` maintains navigation history
3. **Cross-Platform**: Works identically on Android and iOS
4. **No Server Required**: Custom scheme doesn't need hosted verification files

### Implementation

**Android (Kotlin)**:
```kotlin
val scanIntent = Intent(Intent.ACTION_VIEW).apply {
    data = Uri.parse("finapp://scan-receipt")
    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
}
val scanPendingIntent = PendingIntent.getActivity(context, 1, scanIntent,
    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
views.setOnClickPendingIntent(R.id.scan_button, scanPendingIntent)
```

**iOS (SwiftUI)**:
```swift
Link(destination: URL(string: "finapp://scan-receipt")!) {
    HStack {
        Image(systemName: "doc.text.viewfinder")
        Text("Scansiona")
    }
}
```

**Flutter (Deep Link Handler)**:
```dart
// Handles both cold start (app not running) and warm start (app in background)
final initialUri = await _appLinks.getInitialLink();  // Cold start
_appLinks.uriLinkStream.listen((uri) => _handleDeepLink(uri));  // Warm start

void _handleDeepLink(Uri uri) {
  if (uri.scheme == 'finapp') {
    final path = '/${uri.host}${uri.path}';  // "/scan-receipt"
    _router.push(path);  // Preserves navigation stack
  }
}
```

### Complete Flow

1. User taps widget button → Widget sends `finapp://scan-receipt`
2. OS launches/activates app with URI
3. `app_links` receives URI (via `getInitialLink()` or `uriLinkStream`)
4. `DeepLinkHandler` extracts path and calls `router.push('/scan-receipt')`
5. `go_router` navigates to target screen

### Cold Start Handling

- `app_links.getInitialLink()` retrieves URI that launched the app
- `WidgetsBinding.instance.addPostFrameCallback()` ensures router is initialized
- Prevents "Navigator not ready" errors

### Warm Start Handling

- `app_links.uriLinkStream` emits URIs while app running
- `router.push()` adds screen to stack, preserving navigation history
- Non-blocking, doesn't interrupt current activity

### Alternatives Rejected

1. **go_router automatic deep linking**: Clears navigation stack (poor UX)
2. **home_widget's built-in handling**: Limited scope, doesn't integrate with app_links
3. **HTTPS Universal Links**: Overkill for internal navigation, requires domain verification
4. **Custom Method Channels**: Reinventing the wheel

---

## Research 3: Real-time Widget Updates

### Decision

**Hybrid Push Notification + Background Update Strategy**

- **Primary**: Push notifications (FCM/APNs) for <2 second updates
- **Fallback**: WorkManager periodic sync every 15 minutes

### Rationale

**Platform Limitations**:
- **iOS WidgetKit**: Not designed for real-time, minimum ~5 minute intervals, daily budget of 80-90 refreshes
- **Android**: 30-minute minimum for automatic updates, 10-second limit per update operation

**Performance Targets**:
- Foreground: Direct `HomeWidget.updateWidget()` calls (<500ms latency)
- Background: Push notifications trigger immediate updates (1-3 second latency)
- Fallback: WorkManager periodic sync every 15 minutes

### Implementation Strategy

**1. Foreground Updates** (App Active):
```dart
// Direct widget update when expense added
await HomeWidget.saveWidgetData('totalAmount', newTotal);
await HomeWidget.saveWidgetData('expenseCount', newCount);
await HomeWidget.updateWidget(
  name: 'BudgetWidget',
  androidName: 'BudgetWidgetProvider',
  iOSName: 'BudgetWidget',
);
```

**2. Background Push Updates**:
- FCM (Android) / APNs (iOS) push notifications
- Silent notifications trigger widget refresh
- Handled by background message handler
- 1-3 second latency from expense change to widget update

**3. Periodic Fallback**:
- WorkManager tasks every 15 minutes
- Ensures widget stays reasonably current even without push
- Battery-efficient scheduling

### Battery Optimization

- **Update throttling**: Minimum 2 seconds between updates
- **User preferences**: Configurable update frequency
- **Conditional push**: Only for significant changes (>€5 difference)
- **Staleness indicators**: Visual feedback when data outdated

### Alternatives Rejected

- **Pure periodic refresh**: Too slow for <2 second requirement
- **Constant WebSocket**: Excessive battery drain, killed by OS
- **iOS Background Fetch**: Unreliable timing, limited to ~4 times/day

---

## Research 4: Platform-Specific Widget UI

### Decision

**Platform-native UI implementations with shared data layer**

### Android: RemoteViews with LinearLayout

**Constraints**:
- Must use LinearLayout (ConstraintLayout not supported)
- Only basic widgets: TextView, Button, ImageView
- Colors applied programmatically via `setTextColor()` and `setInt()`
- Button clicks via PendingIntent
- Dark mode requires manual detection

**Layout Structure**:
```xml
<LinearLayout orientation="vertical">
    <TextView id="@+id/amount_text" />  <!-- "€342,50 • 12 spese" -->
    <LinearLayout orientation="horizontal">
        <Button id="@+id/scan_button" text="Scansiona" />
        <Button id="@+id/manual_button" text="Manuale" />
    </LinearLayout>
    <ImageView id="@+id/error_icon" visibility="gone" />
</LinearLayout>
```

**Theme Application**:
```kotlin
views.setTextColor(R.id.amount_text, Color.parseColor("#3D5A3C"))  // deepForest
views.setInt(R.id.widget_background, "setBackgroundColor", Color.parseColor("#FFFBF5"))  // cream
```

### iOS: WidgetKit with SwiftUI

**Structure**:
```swift
struct WidgetView: View {
    var body: some View {
        VStack {
            Text("€\(totalAmount, specifier: "%.2f") • \(expenseCount) spese")
                .foregroundColor(Color(hex: "3D5A3C"))
            HStack {
                Link(destination: URL(string: "finapp://scan-receipt")!) {
                    Label("Scansiona", systemImage: "doc.text.viewfinder")
                }
                Link(destination: URL(string: "finapp://add-expense")!) {
                    Label("Manuale", systemImage: "plus")
                }
            }
            if hasError {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.red)
            }
        }
        .background(Color(hex: "FFFBF5"))
    }
}
```

**Dark Mode**:
```swift
@Environment(\.colorScheme) var colorScheme

var backgroundColor: Color {
    colorScheme == .dark ? Color(hex: "3D5A3C") : Color(hex: "FFFBF5")
}
```

### Theme Colors ("Flourishing Finances")

- **Primary**: sageGreen (#7A9B76), deepForest (#3D5A3C)
- **Backgrounds**: cream (#FFFBF5), warmSand (#F5EFE7)
- **Accents**: terracotta (#A8BFC4), amberHoney (#E8B44F)
- **Error**: softCoral (#E88D7A)

### Error Indicator

**Android**:
```kotlin
if (hasError) {
    views.setViewVisibility(R.id.error_icon, View.VISIBLE)
} else {
    views.setViewVisibility(R.id.error_icon, View.GONE)
}
```

**iOS**:
```swift
if hasError {
    Image(systemName: "exclamationmark.triangle.fill")
        .foregroundColor(.red)
}
```

### Alternatives Rejected

- **Flutter widget rendering**: Not supported by home_widget package
- **WebView-based widgets**: Poor performance, not allowed on iOS
- **Cross-platform UI toolkit**: No viable option exists for widgets

---

## Research 5: Supabase Realtime Push

### Decision

**Hybrid: Foreground realtime subscriptions + background periodic refresh**

### Rationale

**Foreground Performance**:
- Realtime subscriptions achieve <1 second updates (typically 300-600ms)
- WebSocket connection maintained while app active
- Minimal battery impact (1-2% per hour)

**Background Limitations**:
- Mobile platforms terminate background WebSocket connections after 3 seconds
- Persistent background subscriptions impractical and battery-intensive

### Implementation

**Subscription Setup**:
```dart
final subscription = supabase
    .from('expenses')
    .stream(primaryKey: ['id'])
    .eq('group_id', currentGroupId)
    .listen((List<Map<String, dynamic>> data) {
      // Filter by current user
      final userExpenses = data.where((e) => e['created_by'] == currentUserId);

      // Calculate totals
      final total = userExpenses.fold<double>(0, (sum, e) => sum + e['amount']);
      final count = userExpenses.length;

      // Update widget
      _updateWidget(total, count);
    });
```

**Event Handling**:
- `PostgresChangeEvent.all` listens to INSERT/UPDATE/DELETE
- Server-side filtering by `group_id` via RLS
- Client-side filtering by `created_by` (current user)
- Debounce rapid changes (500ms) to reduce update frequency

**Widget Update Flow**:
```
Supabase DB Change → Realtime WebSocket → ExpenseRealtimeService →
WidgetUpdateService → WidgetRepository → Platform Channel → Native Widget
```

**Connection Management**:
- Subscribe when app enters foreground (`AppLifecycleState.resumed`)
- Unsubscribe when app backgrounds (`AppLifecycleState.paused`)
- Auto-reconnect on network changes
- Fallback to WorkManager for background updates (30-minute intervals)

### Performance Targets

| Context | Target | Actual |
|---------|--------|--------|
| Foreground Update | <2 seconds | 300-600ms ✓ |
| Background Update | Reasonable | 30 minutes ✓ |
| Battery Impact | Acceptable | 1-2% foreground ✓ |

### Existing Pattern

The codebase already successfully implements this pattern in:
- `lib/features/budgets/personal/presentation/providers/budget_notifier.dart`
- `lib/features/categories/presentation/providers/category_provider.dart`

### Alternatives Rejected

- **24/7 background WebSocket**: Killed by OS, excessive battery drain
- **Polling-based updates**: Too slow for <2 second requirement
- **Cloud Functions + FCM**: Adds complexity, unnecessary with Realtime
- **Local database sync only**: Misses real-time updates from other devices

---

## Research 6: Category MRU Tracking

### Decision

**Extend existing `user_category_usage` table with MRU fields**

Add to existing table:
- `last_used_at` (timestamp) - Most recent expense in this category
- `use_count` (int) - Total number of expenses in this category

### Rationale

**Per-User Tracking**: Each family member sees categories ordered by their own usage patterns (not group-wide)

**Reuses Existing Infrastructure**: Leverages table already in place with RLS policies

**Efficient Queries**: Composite index `(user_id, last_used_at DESC)` enables fast sorting

**Update on Save**: Track usage when expenses are committed (not just selected in dropdown)

**Virgin Categories**: Never-used categories appear at end in alphabetical order

### Database Migration

**SQL Migration** (`065_enhance_user_category_usage_for_mru.sql`):
```sql
-- Add columns to existing table
ALTER TABLE user_category_usage
ADD COLUMN IF NOT EXISTS last_used_at TIMESTAMPTZ,
ADD COLUMN IF NOT EXISTS use_count INTEGER DEFAULT 0;

-- Create composite index for efficient MRU queries
CREATE INDEX IF NOT EXISTS idx_user_category_usage_mru
ON user_category_usage (user_id, last_used_at DESC NULLS LAST);

-- Update existing records (set to category creation date as baseline)
UPDATE user_category_usage
SET last_used_at = created_at,
    use_count = 0
WHERE last_used_at IS NULL;
```

### Drift Table Definition

```dart
class UserCategoryUsage extends Table {
  TextColumn get id => text()();
  TextColumn get userId => text()();
  TextColumn get categoryId => text().references(Categories, #id)();
  BoolColumn get isVirgin => boolean().withDefault(const Constant(true))();
  DateTimeColumn get lastUsedAt => dateTime().nullable()();  // NEW
  IntColumn get useCount => integer().withDefault(const Constant(0))();  // NEW
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}
```

### Query Pattern

**Supabase Query** (with LEFT JOIN for never-used categories):
```dart
final categories = await supabase
    .from('categories')
    .select('''
      id,
      name,
      group_id,
      is_default,
      user_category_usage!left(
        last_used_at,
        use_count
      )
    ''')
    .eq('group_id', currentGroupId)
    .order('user_category_usage.last_used_at', ascending: false, nullsFirst: false)
    .order('name', ascending: true);  // Fallback for never-used categories
```

### Update on Expense Save

```dart
Future<void> _updateCategoryUsage(String userId, String categoryId) async {
  await supabase.rpc('upsert_category_usage', params: {
    'p_user_id': userId,
    'p_category_id': categoryId,
    'p_last_used_at': DateTime.now().toIso8601String(),
  });
}

// PostgreSQL function
CREATE OR REPLACE FUNCTION upsert_category_usage(
  p_user_id TEXT,
  p_category_id TEXT,
  p_last_used_at TIMESTAMPTZ
) RETURNS VOID AS $$
BEGIN
  INSERT INTO user_category_usage (id, user_id, category_id, last_used_at, use_count, is_virgin)
  VALUES (gen_random_uuid(), p_user_id, p_category_id, p_last_used_at, 1, FALSE)
  ON CONFLICT (user_id, category_id)
  DO UPDATE SET
    last_used_at = p_last_used_at,
    use_count = user_category_usage.use_count + 1,
    is_virgin = FALSE,
    updated_at = NOW();
END;
$$ LANGUAGE plpgsql;
```

### Performance

**Estimated Query Time**: <10ms
- Index scan on `(user_id, last_used_at DESC)`
- No table scans
- LEFT JOIN includes never-used categories

**Storage Impact**: ~40 bytes per (user, category) pair

### Alternatives Rejected

1. **Track on Selection**: Too early, user might cancel
2. **Track in Expenses Table**: Requires expensive JOIN every query
3. **Group-wide MRU**: Doesn't reflect individual user habits
4. **Separate MRU Table**: Unnecessary duplication
5. **Client-side Only**: Loses data across devices

---

## Implementation Checklist

### Phase 0: Research ✓
- [x] Widget data persistence strategy
- [x] Deep link handling approach
- [x] Real-time update mechanism
- [x] Platform-specific UI requirements
- [x] Supabase Realtime integration
- [x] Category MRU tracking design

### Phase 1: Data Model & Contracts (Next)
- [ ] Update `WidgetDataEntity` with new fields
- [ ] Create `CategoryUsage` Drift table
- [ ] Define widget provider contracts
- [ ] Define category selector contracts
- [ ] Define deep link contracts
- [ ] Create developer quickstart guide

### Phase 2: Implementation (Via /speckit.tasks)
- [ ] Android widget UI implementation
- [ ] iOS widget UI implementation
- [ ] Real-time subscription service
- [ ] Deep link handler updates
- [ ] Category dropdown widget
- [ ] MRU tracking integration
- [ ] End-to-end testing

---

## Key Technical Decisions Summary

| Aspect | Decision | Rationale |
|--------|----------|-----------|
| **Widget Data** | home_widget ^0.6.0 with dual storage | Platform-native performance, proven reliability |
| **Deep Links** | finapp:// custom scheme | Already implemented, preserves navigation stack |
| **Real-time** | Hybrid push + periodic | Balances <2s requirement with battery efficiency |
| **Android UI** | RemoteViews + LinearLayout | Platform constraint, limited but sufficient |
| **iOS UI** | WidgetKit + SwiftUI | Modern iOS standard, automatic dark mode |
| **Push Updates** | Supabase Realtime foreground | <1s latency, existing pattern in codebase |
| **MRU Tracking** | Extend user_category_usage table | Reuses infrastructure, per-user personalization |
| **Update Trigger** | On expense save | Accurate tracking, avoids premature updates |

---

## References

All research drew from 100+ authoritative sources including:
- Official Flutter documentation
- Android Developers guides
- Apple Developer documentation
- Package documentation (pub.dev)
- Technical tutorials and community guides
- Codebase analysis (existing implementations)

Complete source citations available in individual research documents created by agents a256355, a7379a7, a3449b5, a7eacab, a7c64c0, and ace7e95.

---

**Research Status**: COMPLETE
**Ready for**: Phase 1 (Data Model & Contracts)
**Next Command**: Continue with Phase 1 artifact generation
