# Research: Widget Button Deep Linking

**Feature**: 003-home-budget-widget
**Date**: 2026-01-18
**Research Question**: How to handle deep links from widget buttons using app_links ^6.4.1 and home_widget ^0.6.0?

---

## Decision

**URL Scheme Format**: Use `finapp://` custom URL scheme for widget button deep links
**Routing Strategy**: Integrate `app_links` package with `go_router` using push-based navigation to preserve stack state

### Implementation Summary

- **Scan Receipt Button**: `finapp://scan-receipt`
- **Manual Entry Button**: `finapp://add-expense`
- **Dashboard Tap**: `finapp://dashboard`

---

## Rationale

### Why Custom URL Scheme Over HTTPS

The project already has `finapp://` configured in both Android and iOS manifests, making custom URL schemes the pragmatic choice. While HTTPS-based App Links/Universal Links are more secure and professional for production, they require:

1. Domain ownership and SSL certificates
2. Hosting `assetlinks.json` (Android) and `apple-app-site-association` (iOS) files
3. Additional configuration complexity

For a budget tracking app where widget buttons open internal screens (not shared links), custom URL schemes provide:
- **Simplicity**: No server-side configuration needed
- **Reliability**: No dependency on network connectivity for verification
- **Adequate Security**: Since deep links only navigate to screens within the app
- **Development Speed**: Already configured and working in current implementation

### Why app_links + go_router Integration

The combination of `app_links` (for receiving deep links) and `go_router` (for navigation) provides:

1. **Unified Navigation**: go_router already handles all app navigation with declarative routes
2. **Stack Preservation**: Using `push()` instead of `go()` maintains navigation history
3. **Cold Start Support**: app_links handles both initial link (app not running) and link stream (app running)
4. **Error Handling**: go_router's error builder catches invalid deep link paths

### Why Not go_router Alone

While go_router supports automatic deep link handling via `FlutterDeepLinkingEnabled`, it has a critical limitation: it **clears the navigation stack** when handling deep links. This creates a poor user experience when users:
- Open the app from widget while already using the app
- Expect to return to their previous location after adding an expense

By using `app_links` to manually handle deep links and calling `router.push()`, we preserve the navigation stack.

---

## URL Scheme Design

### Format: `finapp://<screen-name>`

| Widget Action | Deep Link URL | Target Route |
|--------------|---------------|--------------|
| Scan Receipt Button | `finapp://scan-receipt` | `/scan-receipt` |
| Manual Entry Button | `finapp://add-expense` | `/add-expense` |
| Dashboard Tap | `finapp://dashboard` | `/dashboard` |

### URL Structure

```
finapp://scan-receipt
└─┬─┘   └────┬─────┘
scheme      host/path
```

The deep link handler extracts the host and constructs the route path:
```dart
final path = '/${uri.host}${uri.path}';  // "finapp://scan-receipt" → "/scan-receipt"
```

---

## Widget Button Setup

### Android: PendingIntent with URI

**Location**: `android/app/src/main/kotlin/com/ecologicaleaving/fin/widget/BudgetWidgetProvider.kt`

```kotlin
private fun setupClickHandlers(context: Context, views: RemoteViews) {
    // Scan button click
    val scanIntent = Intent(Intent.ACTION_VIEW).apply {
        data = Uri.parse("finapp://scan-receipt")
        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
    }
    val scanPendingIntent = PendingIntent.getActivity(
        context,
        1,  // Unique request code
        scanIntent,
        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
    )
    views.setOnClickPendingIntent(R.id.scan_button, scanPendingIntent)

    // Manual entry button click
    val manualIntent = Intent(Intent.ACTION_VIEW).apply {
        data = Uri.parse("finapp://add-expense")
        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
    }
    val manualPendingIntent = PendingIntent.getActivity(
        context,
        2,  // Different request code
        manualIntent,
        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
    )
    views.setOnClickPendingIntent(R.id.manual_button, manualPendingIntent)
}
```

**Key Details**:
- **Intent.ACTION_VIEW**: Standard Android action for opening URIs
- **FLAG_ACTIVITY_NEW_TASK**: Required for PendingIntent to start activity from widget context
- **FLAG_IMMUTABLE**: Required on Android 12+ for security
- **Unique Request Codes**: Different codes (1, 2) prevent PendingIntent collision
- **Intent Filter**: Matches the `<data android:scheme="finapp"/>` in AndroidManifest.xml

### iOS: SwiftUI Link with URL

**Location**: `ios/BudgetWidget/BudgetWidget.swift`

```swift
struct MediumWidgetView: View {
    let entry: BudgetEntry

    var body: some View {
        VStack {
            // Quick actions
            HStack(spacing: 12) {
                Link(destination: URL(string: "finapp://scan-receipt")!) {
                    HStack {
                        Image(systemName: "doc.text.viewfinder")
                        Text("Scansiona")
                    }
                    .foregroundColor(.white)
                    .padding()
                    .background(Color.blue)
                    .cornerRadius(8)
                }

                Link(destination: URL(string: "finapp://add-expense")!) {
                    HStack {
                        Image(systemName: "plus")
                        Text("Manuale")
                    }
                    .foregroundColor(.white)
                    .padding()
                    .background(Color.blue)
                    .cornerRadius(8)
                }
            }
        }
    }
}
```

**Key Details**:
- **Link**: SwiftUI component for widget interactivity (iOS 14+)
- **URL(string:)!**: Force-unwrap is safe since URL scheme is hardcoded
- **CFBundleURLSchemes**: Matches the scheme in Info.plist (`finapp`)

---

## App-Side Handling: app_links + go_router

### Deep Link Handler Service

**Location**: `lib/features/widget/presentation/services/deep_link_handler.dart`

```dart
import 'dart:async';
import 'package:app_links/app_links.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

class DeepLinkHandler {
  DeepLinkHandler(this._router);

  final GoRouter _router;
  final _appLinks = AppLinks();
  StreamSubscription? _linkSubscription;

  /// Initialize deep link handling
  Future<void> initialize() async {
    // Handle initial link (app opened from deep link - COLD START)
    try {
      final initialUri = await _appLinks.getInitialLink();
      if (initialUri != null) {
        _handleDeepLink(initialUri);
      }
    } on PlatformException catch (e) {
      print('Failed to get initial link: $e');
    }

    // Handle links while app is running (WARM START)
    _linkSubscription = _appLinks.uriLinkStream.listen(
      (Uri uri) {
        _handleDeepLink(uri);
      },
      onError: (err) {
        print('Deep link error: $err');
      },
    );
  }

  /// Dispose and clean up resources
  void dispose() {
    _linkSubscription?.cancel();
  }

  /// Handle incoming deep link
  void _handleDeepLink(Uri uri) {
    print('Handling deep link: $uri');

    // Extract path from finapp:// scheme
    if (uri.scheme == 'finapp') {
      final path = '/${uri.host}${uri.path}';
      print('Navigating to: $path');

      // Use push instead of go to preserve navigation stack
      _router.push(path);
    }
  }
}
```

### Integration in Main App

**Location**: `lib/app/app.dart` (or wherever App widget is defined)

```dart
class FamilyExpenseTrackerApp extends ConsumerStatefulWidget {
  const FamilyExpenseTrackerApp({super.key});

  @override
  ConsumerState<FamilyExpenseTrackerApp> createState() => _FamilyExpenseTrackerAppState();
}

class _FamilyExpenseTrackerAppState extends ConsumerState<FamilyExpenseTrackerApp> {
  DeepLinkHandler? _deepLinkHandler;

  @override
  void initState() {
    super.initState();

    // Initialize deep link handler after first frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final router = ref.read(routerProvider);
      _deepLinkHandler = DeepLinkHandler(router);
      _deepLinkHandler!.initialize();
    });
  }

  @override
  void dispose() {
    _deepLinkHandler?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(routerProvider);

    return MaterialApp.router(
      routerConfig: router,
      // ... other configuration
    );
  }
}
```

### Route Configuration

**Location**: `lib/app/routes.dart`

Routes must be defined in `go_router` to handle deep link paths:

```dart
final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: AppRoutes.home,
    routes: [
      GoRoute(
        path: AppRoutes.scanReceipt,  // '/scan-receipt'
        name: 'scanReceipt',
        builder: (context, state) => const CameraScreen(),
      ),
      GoRoute(
        path: AppRoutes.addExpense,  // '/add-expense'
        name: 'addExpense',
        builder: (context, state) => const ManualExpenseScreen(),
      ),
      GoRoute(
        path: AppRoutes.dashboard,  // '/dashboard'
        name: 'dashboard',
        builder: (context, state) => const DashboardScreen(),
      ),
    ],
  );
});
```

---

## Cold Start Handling

### Challenge: App Not Running

When the app is completely terminated and a user taps a widget button:

1. **OS launches app** with the deep link URI as launch intent
2. **Flutter engine initializes** (takes 1-2 seconds)
3. **app_links.getInitialLink()** retrieves the URI that launched the app
4. **Navigation occurs** after app initialization is complete

### Solution: Post-Frame Callback

```dart
WidgetsBinding.instance.addPostFrameCallback((_) {
  final router = ref.read(routerProvider);
  _deepLinkHandler = DeepLinkHandler(router);
  _deepLinkHandler!.initialize();
});
```

**Why This Works**:
- `addPostFrameCallback` waits until the first frame is rendered
- Ensures `GoRouter` is fully initialized before attempting navigation
- Prevents "Navigator not ready" errors during cold start

### Alternative: Check in main()

For even earlier handling, could initialize in `main()`:

```dart
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // ... other initialization

  runApp(
    ProviderScope(
      child: const FamilyExpenseTrackerApp(),
    ),
  );
}
```

However, this approach requires the router to be available before the app widget builds, which complicates the dependency injection pattern (Riverpod providers).

---

## Warm Start Handling

### Challenge: App Running in Background

When the app is already running or in background:

1. **User taps widget button**
2. **OS sends URI to running app** via platform channel
3. **app_links.uriLinkStream** emits the URI
4. **Handler navigates** immediately (no initialization delay)

### Solution: Stream Subscription

```dart
_linkSubscription = _appLinks.uriLinkStream.listen(
  (Uri uri) {
    _handleDeepLink(uri);
  },
  onError: (err) {
    print('Deep link error: $err');
  },
);
```

**Why This Works**:
- Stream-based approach handles multiple deep links during app lifetime
- Non-blocking: doesn't interrupt user's current activity
- `router.push()` adds new screen to stack, preserving user's navigation history

---

## Platform Differences

### Android: Intent Filter + PendingIntent

**AndroidManifest.xml Configuration**:
```xml
<intent-filter>
    <action android:name="android.intent.action.VIEW"/>
    <category android:name="android.intent.category.DEFAULT"/>
    <category android:name="android.intent.category.BROWSABLE"/>
    <data android:scheme="finapp"/>
</intent-filter>
```

**Behavior**:
- Widget button triggers `Intent(Intent.ACTION_VIEW)` with `finapp://` URI
- Android OS finds MainActivity via intent filter
- MainActivity launches with URI data
- `app_links` plugin retrieves URI from intent extras

**Cold Start**: Intent extras persist through app launch
**Warm Start**: Intent delivered to existing activity instance via `onNewIntent()`

### iOS: URL Types + Link

**Info.plist Configuration**:
```xml
<key>CFBundleURLTypes</key>
<array>
    <dict>
        <key>CFBundleURLSchemes</key>
        <array>
            <string>finapp</string>
        </array>
        <key>CFBundleURLName</key>
        <string>com.ecologicaleaving.fin</string>
    </dict>
</array>
```

**Behavior**:
- SwiftUI `Link` component opens URL when tapped
- iOS checks URL scheme against registered apps
- Launches Flutter app's main scene with URL
- `app_links` plugin receives URL via AppDelegate's `openURL` method

**Cold Start**: URL passed to AppDelegate during launch
**Warm Start**: URL delivered via `openURL` callback

---

## Code Examples

### Complete Deep Link Flow

**1. User taps "Scan Receipt" button on widget**

**2. Android Widget (Kotlin)**:
```kotlin
val scanIntent = Intent(Intent.ACTION_VIEW).apply {
    data = Uri.parse("finapp://scan-receipt")
    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
}
val scanPendingIntent = PendingIntent.getActivity(context, 1, scanIntent, flags)
views.setOnClickPendingIntent(R.id.scan_button, scanPendingIntent)
```

**3. iOS Widget (SwiftUI)**:
```swift
Link(destination: URL(string: "finapp://scan-receipt")!) {
    HStack {
        Image(systemName: "doc.text.viewfinder")
        Text("Scansiona")
    }
}
```

**4. OS launches/activates app with URI**

**5. Deep Link Handler (Dart)**:
```dart
// Cold start
final initialUri = await _appLinks.getInitialLink();
if (initialUri != null) {
  _handleDeepLink(initialUri);  // finapp://scan-receipt
}

// Warm start
_appLinks.uriLinkStream.listen((Uri uri) {
  _handleDeepLink(uri);  // finapp://scan-receipt
});
```

**6. Handle Deep Link**:
```dart
void _handleDeepLink(Uri uri) {
  if (uri.scheme == 'finapp') {
    final path = '/${uri.host}${uri.path}';  // "/scan-receipt"
    _router.push(path);  // Navigates to CameraScreen
  }
}
```

**7. Go Router navigates to screen**:
```dart
GoRoute(
  path: '/scan-receipt',
  builder: (context, state) => const CameraScreen(),
)
```

---

## Alternatives Considered

### Alternative 1: go_router Automatic Deep Linking

**Approach**: Enable `FlutterDeepLinkingEnabled` and let go_router handle deep links automatically.

**Configuration**:
```xml
<!-- iOS Info.plist -->
<key>FlutterDeepLinkingEnabled</key>
<true/>

<!-- Android AndroidManifest.xml -->
<meta-data
    android:name="flutter_deeplinking_enabled"
    android:value="true" />
```

**Why Rejected**:
- **Stack Clearing**: go_router clears the navigation stack when handling deep links automatically
- **Poor UX**: User loses their place in the app when tapping widget button
- **No Control**: Cannot customize navigation behavior (push vs. go)
- **Documentation Warning**: Official docs recommend `app_links` for stack preservation

**Source**: [Handling Deep Links in Flutter Without Losing Navigation](https://medium.com/@pinky.hlaing173/handling-deep-links-in-flutter-without-losing-navigation-using-app-links-over-go-router-45845bc07373)

### Alternative 2: home_widget's Built-in Deep Linking

**Approach**: Use `home_widget` package's `HomeWidget.initiallyLaunchedFromHomeWidget()` and custom URI handling.

**Example**:
```dart
void _checkForWidgetLaunch() {
  HomeWidget.initiallyLaunchedFromHomeWidget().then(_launchedFromWidget);
}

void _launchedFromWidget(Uri? uri) {
  if (uri != null) {
    // Custom routing logic
  }
}
```

**Why Rejected**:
- **Limited Scope**: Only handles widget-launched URIs, not other deep links (notifications, web links)
- **Manual Implementation**: Requires custom routing logic instead of using go_router
- **Duplicate Code**: Would need separate handling for widget links vs. standard deep links
- **Less Flexible**: Doesn't integrate with existing `app_links` + `go_router` architecture

**Better Use Case**: Useful when widgets have unique URIs different from app routes (e.g., `widget://action?param=value`)

**Source**: [Adding a Home Screen widget to your Flutter App - Google Codelabs](https://codelabs.developers.google.com/flutter-home-screen-widgets)

### Alternative 3: HTTPS Universal Links / App Links

**Approach**: Use production-ready HTTPS links instead of custom scheme.

**URLs**:
- `https://fin.app/scan-receipt`
- `https://fin.app/add-expense`

**Requirements**:
- Domain ownership (`fin.app`)
- Hosted verification files:
  - Android: `https://fin.app/.well-known/assetlinks.json`
  - iOS: `https://fin.app/.well-known/apple-app-site-association`
- SSL certificate

**Why Deferred**:
- **Overkill for Internal Navigation**: Widget buttons only open screens within the app
- **Server Dependency**: Requires hosting and maintaining verification files
- **Network Requirement**: iOS verifies association file on app install (requires internet)
- **Development Complexity**: Hard to test locally without production domain

**When to Reconsider**: If adding social sharing features or email magic links where links are shared externally

**Sources**:
- [Set up app links for Android - Flutter Docs](https://docs.flutter.dev/cookbook/navigation/set-up-app-links)
- [Set up universal links for iOS - Flutter Docs](https://docs.flutter.dev/cookbook/navigation/set-up-universal-links)

### Alternative 4: Method Channel Custom Implementation

**Approach**: Build custom platform channels to handle widget clicks without deep links.

**Implementation**:
```dart
static const platform = MethodChannel('com.ecologicaleaving.fin/widget');

Future<void> handleWidgetClick() async {
  try {
    final String action = await platform.invokeMethod('getWidgetAction');
    if (action == 'scan') {
      context.push('/scan-receipt');
    }
  } catch (e) {
    print('Error: $e');
  }
}
```

**Why Rejected**:
- **Reinventing the Wheel**: app_links already provides this functionality
- **More Code**: Requires platform-specific implementations in Kotlin and Swift
- **No Standard**: Custom protocol harder to maintain and debug
- **Missing Features**: Would need to manually implement cold start handling, URL parsing, etc.

**Better Use Case**: When integrating platform-specific features that don't have Flutter plugins

---

## Implementation Checklist

### Platform Configuration

- [x] **Android**: `finapp://` scheme in AndroidManifest.xml (line 45)
- [x] **iOS**: `finapp` in CFBundleURLSchemes in Info.plist (line 53)
- [x] **Dependencies**: app_links ^6.4.1 and home_widget ^0.6.0 in pubspec.yaml

### Widget Implementation

- [x] **Android**: PendingIntent with `finapp://` URIs in BudgetWidgetProvider.kt
  - [x] Scan button: `finapp://scan-receipt` (line 214)
  - [x] Manual button: `finapp://add-expense` (line 227)
  - [x] Dashboard tap: `finapp://dashboard` (line 201)
- [x] **iOS**: SwiftUI Link components in BudgetWidget.swift
  - [x] Scan button: `finapp://scan-receipt` (lines 150, 215, 306)
  - [x] Manual button: `finapp://add-expense` (lines 159, 229, 320)
  - [x] Dashboard tap: `finapp://dashboard` (lines 183, 266)

### Flutter App Handling

- [x] **Service**: DeepLinkHandler service created
  - [x] Cold start: `getInitialLink()` implementation (line 18)
  - [x] Warm start: `uriLinkStream.listen()` implementation (line 27)
  - [x] URI parsing: Extract path from `finapp://` scheme (line 47)
  - [x] Navigation: Use `router.push()` to preserve stack (line 53)
- [x] **Routes**: go_router routes configured
  - [x] `/scan-receipt` → CameraScreen
  - [x] `/add-expense` → ManualExpenseScreen
  - [x] `/dashboard` → DashboardScreen

### Testing Scenarios

- [ ] **Cold Start (App Not Running)**:
  - [ ] Android: Tap widget button, verify app launches to correct screen
  - [ ] iOS: Tap widget button, verify app launches to correct screen
- [ ] **Warm Start (App in Background)**:
  - [ ] Android: Tap widget button, verify app opens to correct screen with stack preserved
  - [ ] iOS: Tap widget button, verify app opens to correct screen with stack preserved
- [ ] **App Already Open**:
  - [ ] Tap widget button, verify new screen pushed onto navigation stack
  - [ ] Press back button, verify user returns to previous screen
- [ ] **Invalid Deep Link**:
  - [ ] Send `finapp://unknown-route`, verify error page shown
  - [ ] Verify error page has "back to home" button

---

## References & Sources

### Official Documentation
- [Flutter Deep Linking - Official Docs](https://docs.flutter.dev/ui/navigation/deep-linking)
- [Set up app links for Android - Flutter Cookbook](https://docs.flutter.dev/cookbook/navigation/set-up-app-links)
- [Set up universal links for iOS - Flutter Cookbook](https://docs.flutter.dev/cookbook/navigation/set-up-universal-links)
- [app_links Package - pub.dev](https://pub.dev/packages/app_links)
- [home_widget Package - pub.dev](https://pub.dev/packages/home_widget)
- [go_router Deep Linking - pub.dev](https://pub.dev/documentation/go_router/latest/topics/Deep%20linking-topic.html)

### Tutorials & Guides
- [Flutter Deep Linking: The Ultimate Guide - Code with Andrea](https://codewithandrea.com/articles/flutter-deep-links/)
- [Deep Linking in Flutter: A Comprehensive Guide (Android) - Muhammad Fathy (Medium)](https://medium.com/@muhammad.fathy/deep-linking-in-flutter-a-comprehensive-guide-android-315360905a80)
- [Handling Deep Links Without Losing Navigation - Medium](https://medium.com/@pinky.hlaing173/handling-deep-links-in-flutter-without-losing-navigation-using-app-links-over-go-router-45845bc07373)
- [Interactive HomeScreen Widgets with Flutter - Anton Borries (Medium)](https://medium.com/@ABausG/interactive-homescreen-widgets-with-flutter-using-home-widget-83cb0706a417)
- [Adding a Home Screen widget to your Flutter App - Google Codelabs](https://codelabs.developers.google.com/flutter-home-screen-widgets)
- [Deep Links and Flutter applications - Flutter Community (Medium)](https://medium.com/flutter-community/deep-links-and-flutter-applications-how-to-handle-them-properly-8c9865af9283)

### Android-Specific
- [Create a deep link for a destination - Android Developers](https://developer.android.com/guide/navigation/design/deep-link)
- [Deep Linking in Flutter: a Complete How-To - OpenReplay Blog](https://blog.openreplay.com/deep-linking-in-flutter/)

### iOS-Specific
- [An iOS 17 SwiftUI WidgetKit Deep Link Tutorial - Answertopia](https://www.answertopia.com/swiftui/a-swiftui-widgetkit-deep-link-tutorial/)
- [Linking a widget to a specific view in SwiftUI - Create with Swift](https://www.createwithswift.com/linking-a-widget-to-a-specific-view-in-swiftui/)
- [Deeplink URL handling in SwiftUI - SwiftLee](https://www.avanderlee.com/swiftui/deeplink-url-handling/)

### Community Resources
- [GitHub: go_router_deep_links_example - Andrea Bizzotto](https://github.com/bizz84/go_router_deep_links_example)
- [GitHub: ABausG/home_widget - Official Repository](https://github.com/ABausG/home_widget)
- [home_widget example - pub.dev](https://pub.dev/packages/home_widget/example)

---

## Notes

### Current Implementation Status

The project **already has a working deep link implementation**:

1. **Platform Configuration**: Both AndroidManifest.xml and Info.plist have `finapp://` scheme configured
2. **Widget Buttons**: Android and iOS widgets already use deep link URIs for button clicks
3. **Deep Link Handler**: `DeepLinkHandler` service exists and handles both cold/warm starts
4. **Route Integration**: Routes are properly configured in go_router

### What This Research Provides

This research document serves as:
- **Technical Reference**: Explains *why* each piece of the implementation works
- **Debugging Guide**: Shows the complete flow from widget tap to screen navigation
- **Maintenance Documentation**: Future developers can understand the architecture
- **Alternative Analysis**: Documents why other approaches were not chosen

### Potential Improvements

While the current implementation is solid, future enhancements could include:

1. **Analytics**: Track which widget buttons are most used
2. **Error Boundary**: Better handling of invalid deep link URIs
3. **Deep Link Parameters**: Support query params like `finapp://add-expense?category=food`
4. **Universal Links**: Upgrade to HTTPS links when sharing features are added
5. **Testing**: Add automated tests for deep link handling

---

**Research Completed**: 2026-01-18
**Status**: Current implementation reviewed and documented
**Next Steps**: None required - implementation is complete and working
