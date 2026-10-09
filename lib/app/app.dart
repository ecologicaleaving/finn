import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme/app_theme.dart';
import '../features/auth/presentation/providers/auth_provider.dart';
import '../features/expenses/presentation/providers/recurring_generation_provider.dart';
import 'routes.dart';
import '../features/offline/presentation/providers/offline_providers.dart';
import '../features/scanner/presentation/providers/scanner_provider.dart';
import '../features/widget/presentation/services/deep_link_handler.dart';
import '../shared/services/share_intent_service.dart';

/// Main application widget.
class FamilyExpenseTrackerApp extends ConsumerStatefulWidget {
  const FamilyExpenseTrackerApp({super.key});

  @override
  ConsumerState<FamilyExpenseTrackerApp> createState() =>
      _FamilyExpenseTrackerAppState();
}

class _FamilyExpenseTrackerAppState
    extends ConsumerState<FamilyExpenseTrackerApp>
    with WidgetsBindingObserver {
  DeepLinkHandler? _deepLinkHandler;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _setupShareIntentListener();
    _setupDeepLinkHandler();
    // Recurring expenses (issue #69): run once at startup if the session is
    // already restored (the auth listener in build() covers the later login).
    WidgetsBinding.instance.addPostFrameCallback((_) => _runRecurring());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _runRecurring();
    }
  }

  void _runRecurring() {
    if (!mounted) return;
    try {
      ref.read(recurringGenerationTriggerProvider).run();
    } catch (_) {
      // e.g. demo mode without Supabase: nothing to generate
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    ShareIntentService.setCallback(null);
    _deepLinkHandler?.dispose();
    super.dispose();
  }

  /// Set up deep link handler for widget and other deep links.
  void _setupDeepLinkHandler() {
    final router = ref.read(routerProvider);
    _deepLinkHandler = DeepLinkHandler(router);
    _deepLinkHandler!.initialize();
  }

  /// Set up listener for incoming shared images from other apps.
  void _setupShareIntentListener() {
    ShareIntentService.setCallback(_handleSharedImage);
  }

  /// Handle an image shared from another app.
  void _handleSharedImage(Uint8List imageData) {
    // Set the captured image in scanner provider
    ref.read(scannerProvider.notifier).setCapturedImage(imageData);

    // Navigate to review scan screen
    final router = ref.read(routerProvider);
    router.go('/review-scan');
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(routerProvider);

    // Keep the sync trigger (and the connectivity monitor it listens to)
    // alive for the whole app lifetime: expenses saved offline are uploaded
    // automatically when the connection comes back.
    ref.listen(syncTriggerProvider, (_, __) {});

    // Generate recurring instances after authentication (issue #69).
    ref.listen(
      authProvider.select(authenticatedUserId),
      (previous, next) {
        if (next != null && next != previous) _runRecurring();
      },
    );

    return MaterialApp.router(
      title: 'Spese Famiglia',
      debugShowCheckedModeBanner: false,

      // Localization
      locale: const Locale('it', 'IT'),
      supportedLocales: const [
        Locale('it', 'IT'),
      ],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],

      // Theme - Flourishing Finances
      theme: AppTheme.lightTheme,
      themeMode: ThemeMode.light, // Only light theme for now

      // Routing
      routerConfig: router,
    );
  }
}
