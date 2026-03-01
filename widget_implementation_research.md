# Home Screen Widget Implementation Research

## Research Question
Best practices for implementing Android RemoteViews widget and iOS WidgetKit widget with buttons and theme colors.

## Context
Need to render widget showing "€342,50 • 12 spese" with two buttons ("Scansiona scontrino", "Inserimento manuale") using specific theme colors: sageGreen (#7A9B76), deepForest (#3D5A3C), cream (#FFFBF5), warmSand (#F5EFE7).

---

## Decision

### Android (RemoteViews)
Use **LinearLayout** (vertical) containing:
- Header section with TextViews for amount and expense count
- Button container with two Buttons in horizontal LinearLayout
- Optional ImageView for error/warning indicator
- Apply custom colors via `setTextColor()` and `setInt()` methods
- Handle button clicks with PendingIntent using `setOnClickPendingIntent()`

### iOS (WidgetKit/SwiftUI)
Use **SwiftUI VStack** containing:
- Text views for amount and expense count (HStack)
- Link elements (not Button) for deep linking into app
- SF Symbol Image for error/warning indicator
- Apply custom colors via SwiftUI Color with hex values
- Adapt to light/dark mode using @Environment(\.colorScheme)

---

## Rationale

### Why These Layouts Meet Requirements

**Android RemoteViews Constraints:**
- RemoteViews has strict limitations on supported UI elements
- LinearLayout is explicitly supported (unlike ConstraintLayout or RecyclerView)
- TextView, Button, and ImageView are the only reliable widgets
- Custom colors must be applied programmatically, not via theme resources
- PendingIntent is the only mechanism for handling user interactions

**iOS WidgetKit Constraints:**
- WidgetKit widgets cannot use interactive SwiftUI Button elements
- Link elements provide deep linking capability for medium/large widgets
- SwiftUI provides excellent dark mode support out of the box
- SF Symbols integrate seamlessly for icons
- Timeline-based updates are system-controlled (can't force frequent updates)

**Design Considerations:**
- Both platforms require native code; Flutter cannot render the widget UI
- Data synchronization happens via SharedPreferences (Android) and App Groups (iOS)
- Error indicators should be subtle (small icon) to avoid cluttering the widget
- Buttons/Links should have sufficient tap target size (minimum 48dp/44pt)

---

## Android Layout

### XML Structure (widget_layout.xml)

```xml
<?xml version="1.0" encoding="utf-8"?>
<LinearLayout xmlns:android="http://schemas.android.com/apk/res/android"
    android:layout_width="match_parent"
    android:layout_height="wrap_content"
    android:orientation="vertical"
    android:padding="16dp"
    android:background="@drawable/widget_background">

    <!-- Header Section -->
    <LinearLayout
        android:layout_width="match_parent"
        android:layout_height="wrap_content"
        android:orientation="horizontal"
        android:gravity="center_vertical"
        android:layout_marginBottom="12dp">

        <!-- Error/Warning Icon (conditionally visible) -->
        <ImageView
            android:id="@+id/widget_error_icon"
            android:layout_width="16dp"
            android:layout_height="16dp"
            android:layout_marginEnd="8dp"
            android:src="@drawable/ic_warning"
            android:contentDescription="Warning"
            android:visibility="gone" />

        <!-- Amount Text -->
        <TextView
            android:id="@+id/widget_amount"
            android:layout_width="0dp"
            android:layout_height="wrap_content"
            android:layout_weight="1"
            android:text="€342,50"
            android:textSize="18sp"
            android:textStyle="bold"
            android:textColor="#3D5A3C" />

        <!-- Bullet Separator -->
        <TextView
            android:layout_width="wrap_content"
            android:layout_height="wrap_content"
            android:text=" • "
            android:textSize="18sp"
            android:textColor="#3D5A3C"
            android:layout_marginStart="4dp"
            android:layout_marginEnd="4dp" />

        <!-- Expense Count Text -->
        <TextView
            android:id="@+id/widget_expense_count"
            android:layout_width="wrap_content"
            android:layout_height="wrap_content"
            android:text="12 spese"
            android:textSize="18sp"
            android:textColor="#3D5A3C" />
    </LinearLayout>

    <!-- Button Container -->
    <LinearLayout
        android:layout_width="match_parent"
        android:layout_height="wrap_content"
        android:orientation="horizontal"
        android:gravity="center">

        <!-- Scan Receipt Button -->
        <Button
            android:id="@+id/widget_scan_button"
            android:layout_width="0dp"
            android:layout_height="48dp"
            android:layout_weight="1"
            android:text="Scansiona scontrino"
            android:textSize="14sp"
            android:textColor="#FFFBF5"
            android:background="@drawable/button_background_scan"
            android:layout_marginEnd="8dp" />

        <!-- Manual Entry Button -->
        <Button
            android:id="@+id/widget_manual_button"
            android:layout_width="0dp"
            android:layout_height="48dp"
            android:layout_weight="1"
            android:text="Inserimento manuale"
            android:textSize="14sp"
            android:textColor="#FFFBF5"
            android:background="@drawable/button_background_manual"
            android:layout_marginStart="8dp" />
    </LinearLayout>
</LinearLayout>
```

### Button Background Drawables

**button_background_scan.xml:**
```xml
<?xml version="1.0" encoding="utf-8"?>
<shape xmlns:android="http://schemas.android.com/apk/res/android"
    android:shape="rectangle">
    <solid android:color="#7A9B76" /> <!-- sageGreen -->
    <corners android:radius="8dp" />
</shape>
```

**button_background_manual.xml:**
```xml
<?xml version="1.0" encoding="utf-8"?>
<shape xmlns:android="http://schemas.android.com/apk/res/android"
    android:shape="rectangle">
    <solid android:color="#3D5A3C" /> <!-- deepForest -->
    <corners android:radius="8dp" />
</shape>
```

**widget_background.xml:**
```xml
<?xml version="1.0" encoding="utf-8"?>
<shape xmlns:android="http://schemas.android.com/apk/res/android"
    android:shape="rectangle">
    <solid android:color="#FFFBF5" /> <!-- cream -->
    <corners android:radius="16dp" />
</shape>
```

### Widget Provider Code (Kotlin)

```kotlin
class FinWidgetProvider : AppWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray
    ) {
        appWidgetIds.forEach { appWidgetId ->
            val views = RemoteViews(context.packageName, R.layout.widget_layout)

            // Get data from SharedPreferences
            val widgetData = HomeWidgetPlugin.getData(context)
            val amount = widgetData.getString("widget_amount", "€0,00")
            val count = widgetData.getString("widget_expense_count", "0 spese")
            val hasError = widgetData.getBoolean("widget_has_error", false)
            val isDarkMode = widgetData.getBoolean("widget_is_dark_mode", false)

            // Update text content
            views.setTextViewText(R.id.widget_amount, amount)
            views.setTextViewText(R.id.widget_expense_count, count)

            // Apply theme colors based on dark mode
            if (isDarkMode) {
                // Dark mode colors (adjust as needed)
                views.setTextColor(R.id.widget_amount, Color.parseColor("#F5EFE7")) // warmSand
                views.setTextColor(R.id.widget_expense_count, Color.parseColor("#F5EFE7"))
                views.setInt(R.id.widget_root, "setBackgroundColor", Color.parseColor("#3D5A3C")) // deepForest
            } else {
                // Light mode colors
                views.setTextColor(R.id.widget_amount, Color.parseColor("#3D5A3C")) // deepForest
                views.setTextColor(R.id.widget_expense_count, Color.parseColor("#3D5A3C"))
                views.setInt(R.id.widget_root, "setBackgroundColor", Color.parseColor("#FFFBF5")) // cream
            }

            // Show/hide error icon
            views.setViewVisibility(
                R.id.widget_error_icon,
                if (hasError) View.VISIBLE else View.GONE
            )

            // Set error icon tint (Android 12+)
            if (hasError && Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                views.setColorStateList(
                    R.id.widget_error_icon,
                    "setImageTintList",
                    ColorStateList.valueOf(Color.parseColor("#FF9800")) // warning orange
                )
            }

            // Setup button click handlers
            setupButtonClicks(context, views)

            // Update the widget
            appWidgetManager.updateAppWidget(appWidgetId, views)
        }
    }

    private fun setupButtonClicks(context: Context, views: RemoteViews) {
        // Scan Receipt Button
        val scanIntent = Intent(context, MainActivity::class.java).apply {
            action = "SCAN_RECEIPT"
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val scanPendingIntent = PendingIntent.getActivity(
            context,
            0,
            scanIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        views.setOnClickPendingIntent(R.id.widget_scan_button, scanPendingIntent)

        // Manual Entry Button
        val manualIntent = Intent(context, MainActivity::class.java).apply {
            action = "MANUAL_ENTRY"
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val manualPendingIntent = PendingIntent.getActivity(
            context,
            1,
            manualIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        views.setOnClickPendingIntent(R.id.widget_manual_button, manualPendingIntent)
    }
}
```

---

## iOS SwiftUI View

### Widget Entry and Timeline Provider

```swift
import WidgetKit
import SwiftUI

struct FinWidgetEntry: TimelineEntry {
    let date: Date
    let amount: String
    let expenseCount: String
    let hasError: Bool
    let isDarkMode: Bool
}

struct FinWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> FinWidgetEntry {
        FinWidgetEntry(
            date: Date(),
            amount: "€342,50",
            expenseCount: "12 spese",
            hasError: false,
            isDarkMode: false
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (FinWidgetEntry) -> ()) {
        let entry = placeholder(in: context)
        completion(entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<FinWidgetEntry>) -> ()) {
        // Read from App Group UserDefaults
        let sharedDefaults = UserDefaults(suiteName: "group.com.ecologicaleaving.fin")
        let amount = sharedDefaults?.string(forKey: "widget_amount") ?? "€0,00"
        let count = sharedDefaults?.string(forKey: "widget_expense_count") ?? "0 spese"
        let hasError = sharedDefaults?.bool(forKey: "widget_has_error") ?? false
        let isDarkMode = sharedDefaults?.bool(forKey: "widget_is_dark_mode") ?? false

        let entry = FinWidgetEntry(
            date: Date(),
            amount: amount,
            expenseCount: count,
            hasError: hasError,
            isDarkMode: isDarkMode
        )

        // Refresh timeline every 15 minutes
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 15, to: Date())!
        let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
        completion(timeline)
    }
}
```

### Widget View

```swift
struct FinWidgetView: View {
    var entry: FinWidgetEntry
    @Environment(\.colorScheme) var colorScheme

    // Theme colors
    private var sageGreen: Color { Color(hex: "7A9B76") }
    private var deepForest: Color { Color(hex: "3D5A3C") }
    private var cream: Color { Color(hex: "FFFBF5") }
    private var warmSand: Color { Color(hex: "F5EFE7") }

    // Computed colors based on mode
    private var backgroundColor: Color {
        entry.isDarkMode || colorScheme == .dark ? deepForest : cream
    }

    private var textColor: Color {
        entry.isDarkMode || colorScheme == .dark ? warmSand : deepForest
    }

    var body: some View {
        VStack(spacing: 12) {
            // Header Section
            HStack(spacing: 4) {
                if entry.hasError {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 14))
                        .foregroundColor(.orange)
                }

                Text(entry.amount)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(textColor)

                Text("•")
                    .font(.system(size: 18))
                    .foregroundColor(textColor)

                Text(entry.expenseCount)
                    .font(.system(size: 18))
                    .foregroundColor(textColor)

                Spacer()
            }

            // Button Container
            HStack(spacing: 16) {
                // Scan Receipt Link
                Link(destination: URL(string: "finapp://scan-receipt")!) {
                    Text("Scansiona scontrino")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(cream)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .background(sageGreen)
                        .cornerRadius(8)
                }

                // Manual Entry Link
                Link(destination: URL(string: "finapp://manual-entry")!) {
                    Text("Inserimento manuale")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(cream)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .background(deepForest)
                        .cornerRadius(8)
                }
            }
        }
        .padding(16)
        .background(backgroundColor)
        .cornerRadius(16)
    }
}

// Color extension for hex values
extension Color {
    init(hex: String) {
        let scanner = Scanner(string: hex)
        var rgbValue: UInt64 = 0
        scanner.scanHexInt64(&rgbValue)

        let r = Double((rgbValue & 0xFF0000) >> 16) / 255.0
        let g = Double((rgbValue & 0x00FF00) >> 8) / 255.0
        let b = Double(rgbValue & 0x0000FF) / 255.0

        self.init(red: r, green: g, blue: b)
    }
}
```

### Widget Configuration

```swift
@main
struct FinWidget: Widget {
    let kind: String = "FinWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: FinWidgetProvider()) { entry in
            FinWidgetView(entry: entry)
        }
        .configurationDisplayName("Fin Budget Widget")
        .description("Quick access to expense tracking")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}
```

---

## Button Implementation

### Android: PendingIntent Pattern

**Key Principles:**
1. Create an Intent with a custom action or target Activity
2. Wrap it in a PendingIntent (use FLAG_IMMUTABLE for security)
3. Attach to view using `setOnClickPendingIntent(viewId, pendingIntent)`
4. Handle the intent in your MainActivity or BroadcastReceiver

**Example for MainActivity handling:**
```kotlin
class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // Handle widget click
        when (intent.action) {
            "SCAN_RECEIPT" -> {
                // Navigate to scan screen
                MethodChannel(flutterEngine?.dartExecutor?.binaryMessenger, "widget_channel")
                    .invokeMethod("navigateToScan", null)
            }
            "MANUAL_ENTRY" -> {
                // Navigate to manual entry screen
                MethodChannel(flutterEngine?.dartExecutor?.binaryMessenger, "widget_channel")
                    .invokeMethod("navigateToManualEntry", null)
            }
        }
    }
}
```

### iOS: Deep Linking with URL Scheme

**Key Principles:**
1. Define custom URL scheme in Info.plist
2. Use SwiftUI Link with custom URL
3. Handle URL in SceneDelegate or AppDelegate
4. Bridge to Flutter via MethodChannel

**Info.plist configuration:**
```xml
<key>CFBundleURLTypes</key>
<array>
    <dict>
        <key>CFBundleURLSchemes</key>
        <array>
            <string>finapp</string>
        </array>
    </dict>
</array>
```

**AppDelegate handling:**
```swift
@UIApplicationMain
@objc class AppDelegate: FlutterAppDelegate {
    override func application(
        _ app: UIApplication,
        open url: URL,
        options: [UIApplication.OpenURLOptionsKey : Any] = [:]
    ) -> Bool {

        guard let flutterViewController = window?.rootViewController as? FlutterViewController else {
            return false
        }

        let channel = FlutterMethodChannel(
            name: "widget_channel",
            binaryMessenger: flutterViewController.binaryMessenger
        )

        // Parse URL and invoke Flutter method
        if url.scheme == "finapp" {
            switch url.host {
            case "scan-receipt":
                channel.invokeMethod("navigateToScan", arguments: nil)
            case "manual-entry":
                channel.invokeMethod("navigateToManualEntry", arguments: nil)
            default:
                break
            }
        }

        return true
    }
}
```

---

## Error Indicator

### Android: ImageView with Conditional Visibility

**Approach:**
- Add ImageView to layout with `android:visibility="gone"` by default
- Use `setViewVisibility()` to show/hide based on error state
- Apply color tint using `setColorStateList()` (Android 12+) or drawable tint

**XML:**
```xml
<ImageView
    android:id="@+id/widget_error_icon"
    android:layout_width="16dp"
    android:layout_height="16dp"
    android:src="@drawable/ic_warning"
    android:visibility="gone" />
```

**Code:**
```kotlin
views.setViewVisibility(
    R.id.widget_error_icon,
    if (hasError) View.VISIBLE else View.GONE
)

// Tint the icon (Android 12+)
if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
    views.setColorStateList(
        R.id.widget_error_icon,
        "setImageTintList",
        ColorStateList.valueOf(Color.parseColor("#FF9800"))
    )
}
```

### iOS: SF Symbol with Conditional Rendering

**Approach:**
- Use SF Symbol `exclamationmark.triangle.fill` for warning
- Conditionally render based on `entry.hasError`
- Apply orange foreground color for visibility

**SwiftUI:**
```swift
if entry.hasError {
    Image(systemName: "exclamationmark.triangle.fill")
        .font(.system(size: 14))
        .foregroundColor(.orange)
}
```

**Alternative SF Symbols:**
- `exclamationmark.circle.fill` - Circle with exclamation
- `xmark.circle.fill` - Error/close icon
- `info.circle.fill` - Information icon

---

## Theme Application

### Android: Programmatic Color Setting

**Challenge:** RemoteViews doesn't support theme attributes directly. All colors must be hardcoded or applied programmatically.

**Solutions:**

1. **setTextColor() for TextViews:**
```kotlin
views.setTextColor(R.id.widget_amount, Color.parseColor("#3D5A3C"))
```

2. **setInt() for background colors:**
```kotlin
views.setInt(R.id.widget_root, "setBackgroundColor", Color.parseColor("#FFFBF5"))
```

3. **Drawable resources for complex styling:**
```xml
<!-- Define in res/drawable/button_background_scan.xml -->
<shape android:shape="rectangle">
    <solid android:color="#7A9B76" />
    <corners android:radius="8dp" />
</shape>
```

4. **setColorStateList() for modern APIs (Android 12+):**
```kotlin
views.setColorStateList(
    R.id.widget_button,
    "setBackgroundTintList",
    ColorStateList.valueOf(Color.parseColor("#7A9B76"))
)
```

### iOS: SwiftUI Color Extension

**Approach:** Create Color extension for hex values, then use throughout widget.

**Implementation:**
```swift
extension Color {
    init(hex: String) {
        let scanner = Scanner(string: hex)
        var rgbValue: UInt64 = 0
        scanner.scanHexInt64(&rgbValue)

        let r = Double((rgbValue & 0xFF0000) >> 16) / 255.0
        let g = Double((rgbValue & 0x00FF00) >> 8) / 255.0
        let b = Double(rgbValue & 0x0000FF) / 255.0

        self.init(red: r, green: g, blue: b)
    }
}

// Usage
let sageGreen = Color(hex: "7A9B76")
let deepForest = Color(hex: "3D5A3C")
let cream = Color(hex: "FFFBF5")
let warmSand = Color(hex: "F5EFE7")
```

**Alternative: Asset Catalog Colors**

For better dark mode support, define colors in Assets.xcassets:
1. Create Color Set in Assets
2. Set "Appearances" to "Any, Dark"
3. Define light and dark variants
4. Use in code: `Color("SageGreen")`

---

## Dark Mode

### Android: Manual Dark Mode Handling

**Challenge:** RemoteViews doesn't automatically adapt to system theme. Must manually detect and apply colors.

**Approach:**

1. **Detect system dark mode in Flutter:**
```dart
bool isDarkMode = MediaQuery.of(context).platformBrightness == Brightness.dark;
await HomeWidget.saveWidgetData('widget_is_dark_mode', isDarkMode);
```

2. **Apply different colors in widget provider:**
```kotlin
val isDarkMode = widgetData.getBoolean("widget_is_dark_mode", false)

if (isDarkMode) {
    views.setTextColor(R.id.widget_amount, Color.parseColor("#F5EFE7")) // warmSand
    views.setInt(R.id.widget_root, "setBackgroundColor", Color.parseColor("#3D5A3C")) // deepForest
} else {
    views.setTextColor(R.id.widget_amount, Color.parseColor("#3D5A3C")) // deepForest
    views.setInt(R.id.widget_root, "setBackgroundColor", Color.parseColor("#FFFBF5")) // cream
}
```

3. **Update widget when theme changes:**
```dart
class MyApp extends StatefulWidget {
    @override
    _MyAppState createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
    @override
    void initState() {
        super.initState();
        WidgetsBinding.instance.addObserver(this);
    }

    @override
    void didChangePlatformBrightness() {
        super.didChangePlatformBrightness();
        _updateWidget();
    }

    void _updateWidget() async {
        bool isDarkMode = MediaQuery.of(context).platformBrightness == Brightness.dark;
        await HomeWidget.saveWidgetData('widget_is_dark_mode', isDarkMode);
        await HomeWidget.updateWidget(name: 'FinWidgetProvider');
    }
}
```

### iOS: Automatic Dark Mode Support

**Advantage:** WidgetKit automatically supports dark mode through SwiftUI's environment.

**Approach:**

1. **Use @Environment colorScheme:**
```swift
struct FinWidgetView: View {
    @Environment(\.colorScheme) var colorScheme

    private var textColor: Color {
        colorScheme == .dark ? warmSand : deepForest
    }
}
```

2. **Or read from widget data:**
```swift
private var backgroundColor: Color {
    entry.isDarkMode || colorScheme == .dark ? deepForest : cream
}
```

3. **Asset Catalog approach (recommended):**
```swift
// In Assets.xcassets, create color sets with light/dark variants
Color("WidgetBackground") // Automatically adapts
Color("WidgetText")
```

**Best Practice:** Combine both approaches - use Asset Catalog for primary colors, but also pass isDarkMode from Flutter for consistency with app state.

---

## Code Examples

### Complete Android Widget Setup

**1. Widget XML Layout (res/layout/widget_layout.xml):**
See "Android Layout" section above.

**2. Widget Provider (kotlin):**
See "Android Layout" section above.

**3. Widget Metadata (res/xml/widget_info.xml):**
```xml
<?xml version="1.0" encoding="utf-8"?>
<appwidget-provider xmlns:android="http://schemas.android.com/apk/res/android"
    android:minWidth="250dp"
    android:minHeight="110dp"
    android:updatePeriodMillis="900000"
    android:initialLayout="@layout/widget_layout"
    android:resizeMode="horizontal|vertical"
    android:widgetCategory="home_screen"
    android:description="@string/widget_description"
    android:previewImage="@drawable/widget_preview">
</appwidget-provider>
```

**4. AndroidManifest.xml registration:**
```xml
<receiver
    android:name=".FinWidgetProvider"
    android:exported="true">
    <intent-filter>
        <action android:name="android.appwidget.action.APPWIDGET_UPDATE" />
    </intent-filter>
    <meta-data
        android:name="android.appwidget.provider"
        android:resource="@xml/widget_info" />
</receiver>
```

**5. Flutter Integration:**
```dart
import 'package:home_widget/home_widget.dart';

Future<void> updateWidget({
  required String amount,
  required String expenseCount,
  required bool hasError,
}) async {
  await HomeWidget.saveWidgetData<String>('widget_amount', amount);
  await HomeWidget.saveWidgetData<String>('widget_expense_count', expenseCount);
  await HomeWidget.saveWidgetData<bool>('widget_has_error', hasError);

  // Detect dark mode
  bool isDarkMode = MediaQuery.of(context).platformBrightness == Brightness.dark;
  await HomeWidget.saveWidgetData<bool>('widget_is_dark_mode', isDarkMode);

  // Update widget
  await HomeWidget.updateWidget(
    name: 'FinWidgetProvider',
    androidName: 'FinWidgetProvider',
  );
}
```

### Complete iOS Widget Setup

**1. Widget Extension Target:**
Create new Widget Extension in Xcode: File → New → Target → Widget Extension

**2. Widget Code (FinWidget.swift):**
See "iOS SwiftUI View" section above.

**3. Info.plist URL Scheme:**
See "Button Implementation" section above.

**4. App Group Configuration:**
- Enable App Groups capability in both app and widget targets
- Use group ID: `group.com.ecologicaleaving.fin`

**5. Flutter Integration:**
```dart
import 'package:home_widget/home_widget.dart';

Future<void> updateWidget({
  required String amount,
  required String expenseCount,
  required bool hasError,
}) async {
  await HomeWidget.saveWidgetData<String>('widget_amount', amount);
  await HomeWidget.saveWidgetData<String>('widget_expense_count', expenseCount);
  await HomeWidget.saveWidgetData<bool>('widget_has_error', hasError);

  // Detect dark mode
  bool isDarkMode = MediaQuery.of(context).platformBrightness == Brightness.dark;
  await HomeWidget.saveWidgetData<bool>('widget_is_dark_mode', isDarkMode);

  // Update widget
  await HomeWidget.updateWidget(
    name: 'FinWidget',
    iOSName: 'FinWidget',
  );
}
```

**6. Handle Deep Links in AppDelegate:**
See "Button Implementation" section above.

---

## Alternatives Considered

### 1. Using ConstraintLayout on Android
**Rejected because:** RemoteViews doesn't support ConstraintLayout. LinearLayout and RelativeLayout are the only complex layouts available.

### 2. Using Flutter to Render Widget UI
**Rejected because:** Neither platform supports rendering widgets with Flutter code. Native code (Kotlin/Swift) is required.

### 3. Using SwiftUI Buttons in iOS Widget
**Rejected because:** WidgetKit doesn't support interactive Button elements. Only Link elements work for deep linking in medium/large widgets.

### 4. Using Theme Attributes for Android Colors
**Rejected because:** RemoteViews doesn't resolve theme attributes. All colors must be hardcoded or set programmatically.

### 5. Automatic Dark Mode Detection on Android
**Rejected because:** RemoteViews doesn't automatically adapt to system theme. Manual detection and color application required.

### 6. Frequent Widget Updates (every minute)
**Rejected because:**
- Android: System throttles widget updates; excessive updates drain battery
- iOS: Widgets have daily budget of 40-70 refreshes; system controls timing
- Best practice: Update only when data actually changes, minimum 15-minute intervals

### 7. Using RecyclerView/ListView for Button Layout
**Rejected because:** Overkill for 2 static buttons. LinearLayout is simpler and more efficient. RecyclerView requires RemoteViewsService and is meant for dynamic collections.

### 8. Using Glance Compose for Android Widgets
**Considered but not recommended:** Jetpack Glance allows writing widgets in Compose, but:
- Still experimental/alpha quality
- Adds dependency and complexity
- RemoteViews approach is more stable and widely documented
- May be considered for future refactoring

---

## Summary

### Android (RemoteViews)
- Use LinearLayout for structure
- Apply colors via setTextColor() and setInt()
- Handle clicks with PendingIntent
- Manually handle dark mode
- Show error icon with ImageView visibility

### iOS (WidgetKit)
- Use SwiftUI VStack/HStack
- Apply colors via Color(hex:) extension
- Handle clicks with Link deep links
- Automatic dark mode via @Environment
- Show error icon with SF Symbol conditionally

### Both Platforms
- Data synced from Flutter via home_widget plugin
- Update only when necessary (15+ minute intervals)
- Minimum 44dp/44pt tap targets for accessibility
- Error indicators should be subtle and non-intrusive
- Custom URL schemes for app navigation

---

## Sources

### Android RemoteViews & Widgets
- [Creating and Integrating Widgets on Android's Home Screen](https://firatgurgur.medium.com/creating-and-integrating-widgets-on-androids-home-screen-4d8403394cad)
- [RemoteViews.setOnClickPendingIntent Examples](https://www.tabnine.com/code/java/methods/android.widget.RemoteViews/setOnClickPendingIntent)
- [RemoteViews.SetOnClickPendingIntent Method (Microsoft Learn)](https://learn.microsoft.com/en-us/dotnet/api/android.widget.remoteviews.setonclickpendingintent?view=net-android-35.0)
- [Actions and App Widgets](https://commonsware.com/Jetpack/pages/chap-appwidget-006.html)
- [Android Widgets Tutorial](https://www.vogella.com/tutorials/AndroidWidgets/article.html)
- [How to create widgets in android](https://medium.com/@puruchauhan/android-widget-for-starters-5db14f23009b)
- [App widgets - Google Developer Training](https://google-developer-training.github.io/android-developer-advanced-course-concepts/unit-1-expand-the-user-experience/lesson-2-app-widgets/2-1-c-app-widgets/2-1-c-app-widgets.html)
- [Android - Widgets](https://www.tutorialspoint.com/android/android_widgets.htm)
- [Creating a home screen Widget for Android](https://en.proft.me/2017/05/9/creating-home-screen-widget-android/)
- [PendingIntents, Dalvik, and RemoteViews](https://medium.com/nothing-but-the-objectivetruth/pendingintents-dalvik-and-remoteviews-92700c9ddd20)

### Android RemoteViews Supported Elements
- [RemoteViews API Reference](https://developer.android.com/reference/android/widget/RemoteViews)
- [RemoteViews Class (Microsoft Learn)](https://learn.microsoft.com/en-us/dotnet/api/android.widget.remoteviews?view=net-android-35.0)
- [RemoteViewLayout Lint Rules](https://googlesamples.github.io/android-custom-lint-rules/checks/RemoteViewLayout.md.html)
- [RemoteViews.java Source Code](https://android.googlesource.com/platform/frameworks/base/+/master/core/java/android/widget/RemoteViews.java)
- [Implementing Android Widgets: A Practical Guide](https://medium.com/@serhii-tereshchenko/implementing-android-widgets-a-practical-guide-396b28325b9a)

### Android Colors & Theming
- [RemoteViews.SetTextColor Method](https://learn.microsoft.com/en-us/dotnet/api/android.widget.remoteviews.settextcolor?view=net-android-35.0)
- [Enhance your widget - Android Developers](https://developer.android.com/develop/ui/views/appwidgets/enhance)
- [RemoteViews.setTextColor Examples](https://www.tabnine.com/code/java/methods/android.widget.RemoteViews/setTextColor)
- [RemoteViews.setTextColor Java Examples](https://java.hotexamples.com/examples/android.widget/RemoteViews/setTextColor/java-remoteviews-settextcolor-method-examples.html)
- [Colors in an App Widget](https://commonsware.com/Jetpack/pages/chap-appwidget-005.html)

### Android Layouts
- [LinearLayout API Reference](https://developer.android.com/reference/android/widget/LinearLayout)
- [LinearLayout Class (Microsoft Learn)](https://learn.microsoft.com/en-us/dotnet/api/android.widget.linearlayout?view=net-android-35.0)
- [Layouts in views - Android Developers](https://developer.android.com/develop/ui/views/layout/declaring-layout)
- [Linear layout using the Layout Editor](https://umuzi-org.github.io/tech-department/projects/kotlin/project-1/liner-layout-using-the-layout-editor/)
- [Create a linear layout - Android Developers](https://developer.android.com/develop/ui/views/layout/linear)
- [LinearLayout and its Important Attributes with Examples](https://www.geeksforgeeks.org/android/linearlayout-and-its-important-attributes-with-examples-in-android/)

### iOS WidgetKit & SwiftUI
- [Building Widgets Using WidgetKit and SwiftUI](https://developer.apple.com/documentation/widgetkit/building_widgets_using_widgetkit_and_swiftui)
- [Customizing Button with ButtonStyle](https://www.hackingwithswift.com/quick-start/swiftui/customizing-button-with-buttonstyle)
- [Exploring WidgetKit: Creating Your First Control Widget in iOS 18](https://rudrank.com/exploring-widgetkit-first-control-widget-ios-18-swiftui)
- [SwiftUI features in WidgetKit](https://www.fivestars.blog/articles/swiftui-widgetkit/)
- [Implementing WidgetKit: Building Widgets for iOS Apps](https://www.momentslog.com/development/ios/implementing-widgetkit-building-widgets-for-ios-apps-with-swiftui-in-swift)
- [Adapting widgets for tint mode and dark mode in SwiftUI](https://www.createwithswift.com/adapting-widgets-for-tint-mode-and-dark-mode-in-swiftui/)
- [Creating Widgets in iOS with App Extensions](https://200oksolutions.com/blog/creating-ios-widgets-with-widgetkit-and-swiftui/)
- [Adding a Widget to a SwiftUI app](https://www.createwithswift.com/adding-a-widget-to-a-swiftui-app/)
- [SwiftUI - How to style buttons](https://dev.to/silviaespanagil/swiftui-tips-for-styling-buttons-1n4d)
- [WWDC 2025 - WidgetKit in iOS 26: A Complete Guide](https://dev.to/arshtechpro/wwdc-2025-widgetkit-in-ios-26-a-complete-guide-to-modern-widget-development-1cjp)

### WidgetKit Timeline & Updates
- [Keeping a widget up to date - Apple Developer](https://developer.apple.com/documentation/widgetkit/keeping-a-widget-up-to-date)
- [Understanding the Limitations of Widgets Runtime in iOS](https://medium.com/@telawittig/understanding-the-limitations-of-widgets-runtime-in-ios-app-development-and-strategies-for-managing-a3bb018b9f5a)
- [How to Update or Refresh a Widget? - Swift Senpai](https://swiftsenpai.com/development/refreshing-widget/)
- [WidgetKit refresh policy - Apple Developer Forums](https://developer.apple.com/forums/thread/657518)
- [TimelineProvider - Apple Developer](https://developer.apple.com/documentation/widgetkit/timelineprovider)
- [Building Widgets - Cornell App Dev](https://ios-course.cornellappdev.com/resources/archived-past-semesters/fa23/lectures/widgets/building-widgets)

### WidgetKit Dark Mode
- [Adapting widgets for tint mode and dark mode in SwiftUI](https://www.createwithswift.com/adapting-widgets-for-tint-mode-and-dark-mode-in-swiftui/)
- [WidgetKit & dark mode - Apple Developer Forums](https://developer.apple.com/forums/thread/656457)
- [How to detect dark mode - SwiftUI by Example](https://www.hackingwithswift.com/quick-start/swiftui/how-to-detect-dark-mode)
- [Dark Mode in SwiftUI - ZappyCode](https://zappycode.com/tutorials/dark-mode-in-swiftui)
- [Custom color scheme view modifier for SwiftUI](https://gist.github.com/ryanlintott/0bb21cd36a55f519bda5b441736edefe)
- [How to check dark mode with color scheme in SwiftUI](https://onmyway133.com/posts/how-to-check-dark-mode-with-color-scheme-in-swiftui/)
- [Implementing Dark Mode Accessibility in SwiftUI - Kodeco](https://www.kodeco.com/books/swiftui-cookbook/v1.0/chapters/6-implementing-dark-mode-accessibility-in-swiftui)
- [Handling Dark Mode Elegantly in SwiftUI](https://jacobzivandesign.com/technology/dark_mode_swift_ui/)
- [colorScheme - Apple Developer](https://developer.apple.com/documentation/swiftui/environmentvalues/colorscheme)

### iOS SF Symbols
- [SF Symbols - Apple Developer](https://developer.apple.com/sf-symbols/)
- [SF Symbols Human Interface Guidelines](https://developer.apple.com/design/human-interface-guidelines/sf-symbols)
- [The Complete Guide to SF Symbols - Hacking with Swift](https://www.hackingwithswift.com/articles/237/complete-guide-to-sf-symbols)
- [Using Custom Symbols in iOS 18's Control Center Widgets](https://crunchybagel.com/ios-18-control-center-widgets-image-symbols/)
- [SF Symbols - SwiftUI Handbook](https://designcode.io/swiftui-handbook-sf-symbols/)
- [SF Symbol: How to for Swift & SwiftUI](https://www.avanderlee.com/swift/sf-symbol-guide/)

### Flutter home_widget Plugin
- [Adding a Home Screen widget to your Flutter App - Google Codelabs](https://codelabs.developers.google.com/flutter-home-screen-widgets)
- [How to Create and Add Home Screen Widgets in Flutter](https://www.capitalnumbers.com/blog/home-screen-widgets-for-flutter-app/)
- [home_widget - Flutter Package](https://pub.dev/packages/home_widget)
- [Interactive HomeScreen Widgets with Flutter](https://medium.com/@ABausG/interactive-homescreen-widgets-with-flutter-using-home-widget-83cb0706a417)
- [How to Build Home Screen Widgets for iOS and Android with Flutter](https://www.walturn.com/insights/how-to-build-home-screen-widgets-for-ios-and-android-with-flutter)
- [flutter_home_widget_fork - GitHub](https://github.com/gskinnerTeam/flutter_home_widget_fork)
- [home_widget example](https://pub.dev/packages/home_widget/example)
- [Developing iOS & Android Home Screen Widgets in Flutter](https://ejolie.hashnode.dev/developing-ios-android-home-screen-widgets-in-flutter)
- [Build iOS Home Screen widgets with Flutter](https://medium.com/@tiaanvdr55/build-ios-home-screen-widgets-with-flutter-bebe71fa7ec9)
- [How to Create Home Screen Widgets with Flutter - Back4App](https://www.back4app.com/tutorials/how-to-create-home-screen-widgets-in-flutter-with-homewidget-and-back4app)
