import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

import 'app/app.dart';
import 'core/config/env.dart';
import 'core/services/monthly_budget_reset_service.dart';
import 'features/widget/presentation/providers/widget_provider.dart';
import 'features/widget/presentation/services/background_refresh_service.dart';
import 'features/widget/presentation/services/widget_update_service.dart';
import 'shared/services/share_intent_service.dart';

/// Demo mode flag - set via --dart-define=DEMO_MODE=true
const bool kDemoMode = bool.fromEnvironment('DEMO_MODE', defaultValue: false);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Load environment variables from .env file
  await dotenv.load(fileName: ".env");

  // Initialize timezone database
  tz.initializeTimeZones();

  // Get device timezone and set as local
  try {
    final timezoneInfo = await FlutterTimezone.getLocalTimezone();
    final String deviceTimezone = timezoneInfo.identifier;
    tz.setLocalLocation(tz.getLocation(deviceTimezone));
  } catch (e) {
    // Fallback to UTC if device timezone cannot be determined
    tz.setLocalLocation(tz.getLocation('UTC'));
  }

  // Initialize Hive for local caching
  await Hive.initFlutter();
  await Hive.openBox<String>('dashboard_cache');
  await Hive.openBox<String>('expense_cache');

  // Initialize wizard state cache box (Feature: 001-group-budget-wizard, Task: T004)
  // Used for temporary wizard draft storage with 24h expiry
  await Hive.openBox<String>('wizard_cache');

  // Initialize SharedPreferences for widget data persistence
  final sharedPreferences = await SharedPreferences.getInstance();

  // Initialize share intent service for receiving images from other apps
  await ShareIntentService.initialize();

  if (!kDemoMode) {
    // Validate environment in development
    if (!Env.isDevelopment) {
      Env.validate();
    }

    // Initialize Supabase
    await Supabase.initialize(
      url: Env.supabaseUrl,
      anonKey: Env.supabaseAnonKey,
    );

    // Monthly budget reset check (Feature: 001-group-budget-wizard, Task: T066)
    // Check if a new month has started and budget reset is needed
    // NOTE: This will be fully implemented when repositories are wired up
    // For now, service is initialized but not actively checking
    final monthlyResetService = MonthlyBudgetResetService();

    // TODO: Perform monthly reset check after user authentication
    // Example implementation:
    // final isResetNeeded = await monthlyResetService.isResetNeeded(
    //   userId: currentUserId,
    //   groupId: currentGroupId,
    // );
    // if (isResetNeeded) {
    //   await monthlyResetService.performReset(
    //     userId: currentUserId,
    //     groupId: currentGroupId,
    //   );
    // }

    // Widget initialization (only in non-demo mode)
    try {
      print('Main: Initializing widget functionality');

      // Setup widget lifecycle listener
      BackgroundRefreshService.setupWidgetListener(() {
        print('Main: Widget enabled callback triggered, updating widget');
        try {
          final container = ProviderContainer(
            overrides: [
              sharedPreferencesProvider.overrideWithValue(sharedPreferences),
            ],
          );
          container.read(widgetUpdateServiceProvider).triggerUpdate();
          container.dispose();
        } catch (e) {
          print('Main: Error updating widget after enable: $e');
        }
      });

      // Perform initial widget update (if widget already exists)
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(sharedPreferences),
        ],
      );
      await container.read(widgetUpdateServiceProvider).triggerUpdate();
      container.dispose();

      print('Main: Widget initialization completed');
    } catch (e) {
      print('Main: Error initializing widget: $e');
    }
  }

  runApp(
    ProviderScope(
      overrides: [
        // Override SharedPreferences provider with actual instance
        sharedPreferencesProvider.overrideWithValue(sharedPreferences),
      ],
      child: const FamilyExpenseTrackerApp(),
    ),
  );
}
