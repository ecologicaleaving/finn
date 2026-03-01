# Widget Data Persistence Research

**Feature**: 003-home-budget-widget
**Date**: 2026-01-18
**Research Question**: Best practices for persisting widget data (total amount + count + error state) that can be accessed by platform-native widgets
**Context**: Widget needs to cache expense data for display even when app is killed. Both Android and iOS native widgets need access.

---

## Decision

Use **home_widget package (^0.6.0)** with platform-native storage mechanisms:
- **Android**: SharedPreferences via `FlutterSharedPreferences.xml`
- **iOS**: UserDefaults with App Groups configuration

Store data in **two complementary formats**:
1. **Individual primitive values** (for direct native access via home_widget plugin)
2. **JSON object** (for Flutter-side caching and validation)

---

## Rationale

This dual-storage approach provides the best of both worlds:

1. **Native Performance**: Platform-native code can directly read primitive types (double, string, bool) without JSON parsing overhead
2. **Flutter Flexibility**: JSON format enables complex object serialization, validation, and easy debugging
3. **Proven Solution**: This exact pattern is already implemented and working in the existing codebase
4. **Cross-Platform Consistency**: home_widget package abstracts platform differences while maintaining native performance

The existing implementation in `WidgetLocalDataSourceImpl` demonstrates this pattern successfully handles widget updates across both platforms.

---

## Data Format

### Required Data Fields

| Field | Type | Description | Example | Validation |
|-------|------|-------------|---------|------------|
| `totalAmount` | `double` | Total expenses for period | `450.50` | >= 0 |
| `expenseCount` | `int` | Number of expenses | `23` | >= 0 |
| `hasError` | `bool` | Error state indicator | `false` | required |
| `lastUpdated` | `DateTime` | Last successful update timestamp | `2026-01-18T14:30:00.000Z` | required |
| `spent` | `double` | Current month spending | `450.50` | >= 0 |
| `limit` | `double` | Monthly budget limit | `800.00` | > 0 |
| `month` | `string` | Display month | `"Gennaio 2026"` | format: "MMMM yyyy" |
| `currency` | `string` | Currency symbol | `"€"` | <= 3 chars |
| `percentage` | `double` | Budget utilization | `56.31` | calculated |
| `isDarkMode` | `bool` | Theme preference | `false` | required |
| `groupId` | `string` | Family group ID | `"uuid"` | UUID format |
| `groupName` | `string` | Group display name | `"Famiglia"` | optional |

### JSON Schema

```json
{
  "totalAmount": 450.50,
  "expenseCount": 23,
  "hasError": false,
  "lastUpdated": "2026-01-18T14:30:00.000Z",
  "spent": 450.50,
  "limit": 800.00,
  "month": "Gennaio 2026",
  "currency": "€",
  "percentage": 56.31,
  "isDarkMode": false,
  "groupId": "123e4567-e89b-12d3-a456-426614174000",
  "groupName": "Famiglia Rossi"
}
```

### Dart Model Implementation

```dart
class WidgetDataModel extends WidgetDataEntity {
  const WidgetDataModel({
    required double spent,
    required double limit,
    required String month,
    String currency = '€',
    required bool isDarkMode,
    required DateTime lastUpdated,
    required String groupId,
    String? groupName,
    required int expenseCount,
    required bool hasError,
  }) : super(
    spent: spent,
    limit: limit,
    month: month,
    currency: currency,
    isDarkMode: isDarkMode,
    lastUpdated: lastUpdated,
    groupId: groupId,
    groupName: groupName,
    expenseCount: expenseCount,
    hasError: hasError,
  );

  /// Convert to JSON for Flutter-side caching
  Map<String, dynamic> toJson() {
    return {
      'totalAmount': spent,
      'expenseCount': expenseCount,
      'hasError': hasError,
      'spent': spent,
      'limit': limit,
      'month': month,
      'currency': currency,
      'percentage': percentage,
      'isDarkMode': isDarkMode,
      'lastUpdated': lastUpdated.toIso8601String(),
      'groupId': groupId,
      'groupName': groupName,
    };
  }

  /// Create from JSON
  factory WidgetDataModel.fromJson(Map<String, dynamic> json) {
    return WidgetDataModel(
      spent: (json['spent'] as num).toDouble(),
      limit: (json['limit'] as num).toDouble(),
      month: json['month'] as String,
      currency: (json['currency'] as String?) ?? '€',
      isDarkMode: json['isDarkMode'] as bool,
      lastUpdated: DateTime.parse(json['lastUpdated'] as String),
      groupId: json['groupId'] as String,
      groupName: json['groupName'] as String?,
      expenseCount: (json['expenseCount'] as int?) ?? 0,
      hasError: (json['hasError'] as bool?) ?? false,
    );
  }

  /// Serialize to JSON string
  String toJsonString() => jsonEncode(toJson());

  /// Deserialize from JSON string
  factory WidgetDataModel.fromJsonString(String jsonString) {
    return WidgetDataModel.fromJson(
      jsonDecode(jsonString) as Map<String, dynamic>,
    );
  }
}
```

---

## Platform Setup

### Android Configuration

**File**: `android/app/src/main/kotlin/com/ecologicaleaving/fin/widget/BudgetWidgetProvider.kt`

**Storage Access**:
```kotlin
// SharedPreferences key
private const val SHARED_PREFS = "FlutterSharedPreferences"

// Read widget data
val prefs = context.getSharedPreferences(SHARED_PREFS, Context.MODE_PRIVATE)

// Option 1: Read JSON object (preferred for validation)
val widgetDataJson = prefs.getString("flutter.widget_data", null)
if (widgetDataJson != null) {
    val widgetData = JSONObject(widgetDataJson)
    val totalAmount = widgetData.optDouble("totalAmount", 0.0)
    val expenseCount = widgetData.optInt("expenseCount", 0)
    val hasError = widgetData.optBoolean("hasError", false)
    val lastUpdatedString = widgetData.optString("lastUpdated", "")
    // Parse ISO8601 timestamp...
}

// Option 2: Read individual values (direct access)
val spent = prefs.getFloat("flutter.spent", 0f).toDouble()
val limit = prefs.getFloat("flutter.limit", 0f).toDouble()
val month = prefs.getString("flutter.month", "") ?: ""
val lastUpdated = prefs.getLong("flutter.lastUpdated", 0L)
```

**Staleness Detection**:
```kotlin
// Check if data is stale (>24 hours old)
val lastUpdatedString = widgetData.optString("lastUpdated", "")
val lastUpdated = if (lastUpdatedString.isNotEmpty()) {
    try {
        SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSSSSS", Locale.US)
            .parse(lastUpdatedString)?.time ?: 0L
    } catch (e: Exception) {
        0L
    }
} else {
    0L
}

val now = System.currentTimeMillis()
val dataAge = now - lastUpdated
val isStale = dataAge > (24 * 60 * 60 * 1000) // 24 hours

if (isStale && lastUpdated > 0) {
    showErrorState(context, appWidgetManager, appWidgetId, "Dati non aggiornati")
    return
}
```

**No Additional Configuration Required**:
- SharedPreferences automatically created by Flutter
- No manifest changes needed
- Data accessible immediately after Flutter writes

---

### iOS Configuration

**File**: `ios/BudgetWidget/BudgetWidget.swift`

**App Groups Setup** (CRITICAL):

1. **Xcode Configuration**:
   - Open project in Xcode
   - Select Runner target → Signing & Capabilities
   - Click "+ Capability" → Add "App Groups"
   - Create App Group: `group.com.family.financetracker`
   - **Repeat for BudgetWidget extension target**
   - Both targets MUST use identical App Group ID

2. **Verify Configuration**:
   - Runner.entitlements should contain:
     ```xml
     <key>com.apple.security.application-groups</key>
     <array>
         <string>group.com.family.financetracker</string>
     </array>
     ```
   - BudgetWidget.entitlements should have same entry

**Storage Access**:
```swift
// Access shared UserDefaults
let sharedDefaults = UserDefaults(suiteName: "group.com.family.financetracker")

// Read individual values (preferred for iOS widgets)
let spent = sharedDefaults?.double(forKey: "flutter.spent") ?? 0.0
let limit = sharedDefaults?.double(forKey: "flutter.limit") ?? 0.0
let month = sharedDefaults?.string(forKey: "flutter.month") ?? ""
let currency = sharedDefaults?.string(forKey: "flutter.currency") ?? "€"
let isDarkMode = sharedDefaults?.bool(forKey: "flutter.isDarkMode") ?? false
let lastUpdatedTimestamp = sharedDefaults?.double(forKey: "flutter.lastUpdated") ?? 0
let groupName = sharedDefaults?.string(forKey: "flutter.groupName")

// Convert timestamp to Date
let lastUpdated = lastUpdatedTimestamp > 0
    ? Date(timeIntervalSince1970: lastUpdatedTimestamp / 1000.0)
    : Date()
```

**Staleness Detection**:
```swift
private func isDataStale(_ lastUpdated: Date) -> Bool {
    let now = Date()
    let hoursSinceUpdate = now.timeIntervalSince(lastUpdated) / 3600
    return hoursSinceUpdate > 24 // 24 hours threshold
}

// Usage in widget
if isDataStale(entry.lastUpdated) {
    return Text("Dati non aggiornati")
        .font(.caption)
        .foregroundColor(.secondary)
}
```

**Flutter Bridge** (for App Group access):

```dart
// iOS requires writing to App Group UserDefaults via platform channel
static const platform = MethodChannel('widget_data');

Future<void> saveWidgetDataIOS(Map<String, dynamic> data) async {
  if (!Platform.isIOS) return;

  try {
    await platform.invokeMethod('saveWidgetData', {
      'data': jsonEncode(data),
    });
  } catch (e) {
    print('Failed to save to iOS App Group: $e');
  }
}
```

**Native iOS Method Handler** (AppDelegate.swift):
```swift
let sharedDefaults = UserDefaults(suiteName: "group.com.family.financetracker")

// Write data to shared container
if let args = call.arguments as? [String: Any],
   let jsonString = args["data"] as? String,
   let jsonData = jsonString.data(using: .utf8),
   let dataDict = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] {

    // Save each field individually
    sharedDefaults?.set(dataDict["spent"], forKey: "flutter.spent")
    sharedDefaults?.set(dataDict["limit"], forKey: "flutter.limit")
    sharedDefaults?.set(dataDict["month"], forKey: "flutter.month")
    // ... etc

    result(true)
}
```

---

## Staleness Detection Strategy

### Definition of "Stale Data"

Data is considered stale when:
- **Android**: `lastUpdated` > 24 hours old
- **iOS**: `lastUpdated` > 24 hours old
- **Both**: `lastUpdated` is missing or invalid (timestamp = 0)

### Implementation Pattern

**Flutter Side**:
```dart
class WidgetDataEntity {
  final DateTime lastUpdated;

  /// Check if data is stale (>24 hours old)
  bool get isStale {
    final now = DateTime.now();
    final age = now.difference(lastUpdated);
    return age.inHours > 24;
  }

  /// Check if data is fresh enough for display
  bool get isFresh => !isStale;

  /// Human-readable staleness indicator
  String get freshnessIndicator {
    final minutes = DateTime.now().difference(lastUpdated).inMinutes;
    final hours = minutes ~/ 60;

    if (minutes < 1) return "Aggiornato ora";
    if (minutes < 60) return "Aggiornato $minutes min fa";
    if (hours < 24) return "Aggiornato $hours ore fa";
    return "Dati non aggiornati";
  }
}
```

**Android Native**:
```kotlin
private fun formatLastUpdated(timestamp: Long): String {
    if (timestamp == 0L) return "Mai aggiornato"

    val now = System.currentTimeMillis()
    val diff = now - timestamp
    val minutes = diff / (1000 * 60)
    val hours = minutes / 60

    return when {
        minutes < 1 -> "Aggiornato ora"
        minutes < 60 -> "Aggiornato $minutes min fa"
        hours < 24 -> "Aggiornato $hours ore fa"
        else -> {
            val dateFormat = SimpleDateFormat("dd/MM HH:mm", Locale.ITALIAN)
            "Agg. ${dateFormat.format(Date(timestamp))}"
        }
    }
}
```

**iOS Native**:
```swift
private func formatLastUpdated(_ date: Date) -> String {
    let now = Date()
    let diff = now.timeIntervalSince(date)
    let minutes = Int(diff / 60)
    let hours = minutes / 60

    if minutes < 1 {
        return "Aggiornato ora"
    } else if minutes < 60 {
        return "Aggiornato \(minutes) min fa"
    } else if hours < 24 {
        return "Aggiornato \(hours) ore fa"
    } else {
        let formatter = DateFormatter()
        formatter.dateFormat = "dd/MM HH:mm"
        formatter.locale = Locale(identifier: "it_IT")
        return "Agg. \(formatter.string(from: date))"
    }
}
```

### UI Response to Stale Data

**Android Widget**:
```kotlin
if (isStale && lastUpdated > 0) {
    showErrorState(context, appWidgetManager, appWidgetId, "Dati non aggiornati")
    return
}

// Or show warning indicator instead of full error
views.setTextViewText(R.id.last_updated_text, formatLastUpdated(lastUpdated))
views.setViewVisibility(R.id.stale_indicator, if (isStale) View.VISIBLE else View.GONE)
```

**iOS Widget**:
```swift
if isDataStale(entry.lastUpdated) {
    VStack {
        Text("⚠️ Dati non aggiornati")
            .font(.caption)
            .foregroundColor(.orange)
        Text(formatLastUpdated(entry.lastUpdated))
            .font(.caption2)
            .foregroundColor(.secondary)
    }
}
```

---

## Code Examples

### Save Operation (Flutter)

```dart
import 'package:home_widget/home_widget.dart';
import 'package:shared_preferences/shared_preferences.dart';

class WidgetLocalDataSourceImpl implements WidgetLocalDataSource {
  final SharedPreferences sharedPreferences;
  final MethodChannel? platformChannel;

  static const String _widgetDataKey = 'widget_data';
  static const String _appGroupSuiteName = 'group.com.family.financetracker';

  @override
  Future<void> saveWidgetData(WidgetDataModel data) async {
    final jsonString = data.toJsonString();

    // 1. Save JSON object to SharedPreferences (Flutter-side cache)
    await sharedPreferences.setString(_widgetDataKey, jsonString);

    // 2. Save individual fields for native widget access (via home_widget)
    await HomeWidget.saveWidgetData<double>('spent', data.spent);
    await HomeWidget.saveWidgetData<double>('limit', data.limit);
    await HomeWidget.saveWidgetData<String>('month', data.month);
    await HomeWidget.saveWidgetData<double>('percentage', data.percentage);
    await HomeWidget.saveWidgetData<String>('currency', data.currency);
    await HomeWidget.saveWidgetData<bool>('isDarkMode', data.isDarkMode);
    await HomeWidget.saveWidgetData<int>(
      'lastUpdated',
      data.lastUpdated.millisecondsSinceEpoch,
    );
    await HomeWidget.saveWidgetData<String>('groupName', data.groupName ?? '');
    await HomeWidget.saveWidgetData<int>('expenseCount', data.expenseCount);
    await HomeWidget.saveWidgetData<bool>('hasError', data.hasError);

    // 3. iOS: Also save to App Group UserDefaults via MethodChannel
    if (Platform.isIOS && platformChannel != null) {
      try {
        await platformChannel!.invokeMethod('saveWidgetData', {
          'data': jsonString,
        });
      } catch (e) {
        print('Failed to save to iOS App Group: $e');
      }
    }
  }

  @override
  Future<void> updateNativeWidget(WidgetDataModel data) async {
    // Trigger widget update on both platforms
    await HomeWidget.updateWidget(
      androidName: 'BudgetWidgetProvider',
      iOSName: 'BudgetWidget',
    );
  }
}
```

### Retrieve Operation (Flutter)

```dart
@override
Future<WidgetDataModel?> getCachedWidgetData() async {
  // Read JSON object from SharedPreferences
  final jsonString = sharedPreferences.getString(_widgetDataKey);
  if (jsonString == null) return null;

  try {
    return WidgetDataModel.fromJsonString(jsonString);
  } catch (e) {
    print('Failed to parse cached widget data: $e');
    return null;
  }
}
```

### Complete Update Flow

```dart
class WidgetUpdateService {
  final WidgetRepository _repository;

  Future<void> updateWidget() async {
    try {
      // 1. Fetch latest data from app
      final result = await _repository.getWidgetData();

      result.fold(
        (failure) => _handleError(failure),
        (data) async {
          // 2. Validate data freshness
          if (data.isStale) {
            print('Warning: Widget data is stale');
          }

          // 3. Save to local storage
          await _repository.saveWidgetData(data);

          // 4. Trigger native widget refresh
          await _repository.updateWidget();

          print('Widget updated successfully: ${data.expenseCount} expenses, ${data.spent}€');
        },
      );
    } catch (e) {
      print('Widget update failed: $e');
    }
  }

  void _handleError(Failure failure) {
    // Save error state to widget
    final errorData = WidgetDataModel(
      spent: 0,
      limit: 0,
      month: '',
      hasError: true,
      lastUpdated: DateTime.now(),
      expenseCount: 0,
      groupId: '',
      isDarkMode: false,
    );

    _repository.saveWidgetData(errorData);
  }
}
```

---

## Error State Storage

### Error Indicator Pattern

**Purpose**: Distinguish between "no data" vs "error loading data" vs "stale data"

**Implementation**:
```dart
class WidgetDataModel {
  final bool hasError;
  final DateTime lastUpdated;

  /// Error states
  bool get hasNoData => spent == 0 && limit == 0 && month.isEmpty;
  bool get isStale => DateTime.now().difference(lastUpdated).inHours > 24;
  bool get isHealthy => !hasError && !hasNoData && !isStale;

  /// Error message for widget display
  String? get errorMessage {
    if (hasError) return "Errore di caricamento";
    if (hasNoData) return "Budget non configurato";
    if (isStale) return "Dati non aggiornati";
    return null;
  }
}
```

**Storage Pattern**:
```dart
// Save error state
await HomeWidget.saveWidgetData<bool>('hasError', true);
await HomeWidget.saveWidgetData<String>('errorMessage', 'Network timeout');

// Clear error state on success
await HomeWidget.saveWidgetData<bool>('hasError', false);
await HomeWidget.saveWidgetData<String>('errorMessage', '');
```

**Android Error Display**:
```kotlin
val hasError = prefs.getBoolean("flutter.hasError", false)
val errorMessage = prefs.getString("flutter.errorMessage", "Errore sconosciuto")

if (hasError) {
    showErrorState(context, appWidgetManager, appWidgetId, errorMessage)
    return
}
```

**iOS Error Display**:
```swift
let hasError = sharedDefaults?.bool(forKey: "flutter.hasError") ?? false
let errorMessage = sharedDefaults?.string(forKey: "flutter.errorMessage") ?? "Errore sconosciuto"

if hasError {
    return VStack {
        Image(systemName: "exclamationmark.triangle")
            .foregroundColor(.orange)
        Text(errorMessage)
            .font(.caption)
            .foregroundColor(.secondary)
    }
}
```

---

## Alternatives Considered

### 1. SQLite Database

**Pros**:
- Complex queries support
- Relational data storage
- Transaction support

**Cons**:
- Overkill for simple key-value storage
- Platform access complexity (need file sharing)
- Performance overhead for widgets
- Requires Drift/SQLite setup on native side

**Verdict**: Rejected - Too complex for widget data needs

---

### 2. File-Based JSON Storage

**Pros**:
- Human-readable format
- Easy debugging
- Version control friendly

**Cons**:
- File I/O slower than SharedPreferences/UserDefaults
- Manual file locking/concurrency handling
- Path management complexity across platforms
- Requires file provider setup on Android

**Verdict**: Rejected - Less reliable than native storage

---

### 3. Hive/ObjectBox

**Pros**:
- Fast NoSQL storage
- Flutter-native solutions
- Type-safe models

**Cons**:
- Requires native plugin integration for widget access
- Additional dependency overhead
- Limited native platform support
- More complex than needed for widget data

**Verdict**: Rejected - Unnecessary complexity

---

### 4. Only JSON String Storage

**Pros**:
- Single source of truth
- Simpler Flutter code
- Atomic updates

**Cons**:
- Native widgets must parse JSON (performance hit)
- Harder to read individual fields on native side
- More error-prone on platform side
- Requires JSON parsing libraries in Kotlin/Swift

**Verdict**: Rejected - Current dual approach is superior

---

### 5. Only Individual Primitive Values

**Pros**:
- Direct native access
- No JSON parsing overhead
- Platform-optimized

**Cons**:
- No atomic updates across all fields
- Hard to validate data consistency
- Difficult to version or migrate
- No Flutter-side object model benefits

**Verdict**: Rejected - Current dual approach is superior

---

## Performance Considerations

### Storage Size

| Data Type | Size | Count | Total |
|-----------|------|-------|-------|
| double | 8 bytes | 4 | 32 bytes |
| int | 4 bytes | 1 | 4 bytes |
| bool | 1 byte | 2 | 2 bytes |
| string (avg) | 20 bytes | 4 | 80 bytes |
| JSON overhead | - | - | ~50 bytes |
| **Total** | - | - | **~170 bytes** |

**Memory Impact**: Negligible (<1 KB per widget instance)

### Read Performance

| Operation | Android | iOS | Notes |
|-----------|---------|-----|-------|
| Read primitive | <1ms | <1ms | Direct key access |
| Read JSON | <5ms | <5ms | Includes parsing |
| Widget render | <100ms | <100ms | Total update time |

### Write Performance

| Operation | Time | Notes |
|-----------|------|-------|
| Save individual values | ~10ms | 10 keys × 1ms |
| Save JSON string | ~2ms | Single write |
| Trigger widget update | ~50ms | Platform broadcast |
| **Total update cycle** | **~60ms** | Well within budget |

### Update Frequency Impact

**Daily Widget Updates**:
- Background refresh: 48 updates/day (every 30 min)
- User-triggered: ~10 updates/day (expense adds)
- Total: ~60 updates/day
- Data written: ~10 KB/day
- Annual storage: ~3.5 MB/year

**Battery Impact**: Minimal (SharedPreferences/UserDefaults optimized by OS)

---

## Testing Recommendations

### Unit Tests

```dart
test('should save and retrieve widget data correctly', () async {
  final data = WidgetDataModel(
    spent: 450.50,
    limit: 800.00,
    month: 'Gennaio 2026',
    hasError: false,
    lastUpdated: DateTime.now(),
    expenseCount: 23,
    groupId: 'test-group',
    isDarkMode: false,
  );

  await dataSource.saveWidgetData(data);
  final retrieved = await dataSource.getCachedWidgetData();

  expect(retrieved, equals(data));
});

test('should detect stale data correctly', () {
  final staleData = WidgetDataModel(
    spent: 100,
    limit: 500,
    month: 'Gennaio 2026',
    hasError: false,
    lastUpdated: DateTime.now().subtract(Duration(hours: 25)),
    expenseCount: 5,
    groupId: 'test',
    isDarkMode: false,
  );

  expect(staleData.isStale, isTrue);
});
```

### Integration Tests

1. **Android**:
   - Install widget on home screen
   - Verify SharedPreferences data accessible
   - Add expense in app → verify widget updates
   - Simulate 25h delay → verify "Dati non aggiornati" shown

2. **iOS**:
   - Configure App Groups in Xcode
   - Verify UserDefaults data shared between app and widget
   - Add expense in app → verify widget timeline reloads
   - Test widget in all sizes (small, medium, large)

### Manual Test Cases

| Test Case | Steps | Expected Result |
|-----------|-------|-----------------|
| Fresh install | Install app, add widget | Shows "Budget non configurato" |
| First expense | Add expense manually | Widget shows correct amount |
| Stale data | Set device date +2 days | Shows "Dati non aggiornati" |
| Error state | Turn off network, force refresh | Shows error indicator |
| Theme change | Toggle dark mode | Widget adapts theme immediately |

---

## Migration Strategy

If existing widgets need data format changes:

1. **Version field in JSON**:
   ```json
   {
     "version": 2,
     "data": { ... }
   }
   ```

2. **Backward compatibility**:
   ```dart
   factory WidgetDataModel.fromJson(Map<String, dynamic> json) {
     final version = json['version'] as int? ?? 1;

     if (version == 1) {
       return _fromV1(json);
     } else {
       return _fromV2(json);
     }
   }
   ```

3. **Safe migration**:
   - New fields optional with defaults
   - Never remove old fields (mark deprecated)
   - Test on both platforms before release

---

## Sources

- [home_widget Flutter package](https://pub.dev/packages/home_widget)
- [shared_preferences Flutter package](https://pub.dev/packages/shared_preferences)
- [Adding a Home Screen widget to your Flutter App | Google Codelabs](https://codelabs.developers.google.com/flutter-home-screen-widgets)
- [Setting up your AppGroup to share data between App & Extensions in iOS](https://medium.com/@B4k3R/setting-up-your-appgroup-to-share-data-between-app-extensions-in-ios-43c7c642c4c7)
- [Adding iOS app extensions - Flutter Documentation](https://docs.flutter.dev/platform-integration/ios/app-extensions)
- [Sharing information between iOS app and an extension](https://rderik.com/blog/sharing-information-between-ios-app-and-an-extension/)

---

## Summary

**Chosen Solution**: home_widget package with dual storage (individual primitives + JSON object)

**Key Benefits**:
1. Native performance for widget rendering
2. Flutter flexibility for validation and debugging
3. Cross-platform consistency
4. Proven implementation in existing codebase
5. Minimal storage overhead (~170 bytes)
6. Fast read/write operations (<100ms total)

**Critical Requirements**:
- Android: No special setup (uses FlutterSharedPreferences automatically)
- iOS: Must configure App Groups in Xcode for both Runner and Widget Extension
- Both: Use `lastUpdated` timestamp for staleness detection (>24h = stale)
- Both: Store `hasError` boolean for error state indication

**Next Steps**:
1. Extend existing `WidgetDataModel` with `expenseCount`, `totalAmount`, `hasError` fields
2. Update native Android widget to read and display new fields
3. Update iOS widget to read and display new fields
4. Add staleness detection UI to both platforms
5. Test end-to-end flow with real expense data
