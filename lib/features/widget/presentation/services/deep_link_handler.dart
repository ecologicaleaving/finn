import 'dart:async';
import 'package:app_links/app_links.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

/// Service for handling deep links from widget and other sources
class DeepLinkHandler {
  DeepLinkHandler(this._router);

  final GoRouter _router;
  final _appLinks = AppLinks();
  StreamSubscription? _linkSubscription;

  /// Initialize deep link handling
  Future<void> initialize() async {
    // Handle initial link (app opened from deep link)
    try {
      final initialUri = await _appLinks.getInitialLink();
      if (initialUri != null) {
        _handleDeepLink(initialUri);
      }
    } on PlatformException catch (e) {
      print('Failed to get initial link: $e');
    }

    // Handle links while app is running
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
      // Map widget deep links to app routes
      String path;
      switch (uri.host) {
        case 'dashboard':
          path = '/main'; // Navigate to main screen with dashboard tab
          break;
        case 'scan-receipt':
          path = '/scan-receipt';
          break;
        case 'add-expense':
          path = '/add-expense';
          break;
        default:
          path = '/${uri.host}${uri.path}';
      }

      print('Navigating to: $path');

      // Delay navigation slightly to ensure app is fully initialized
      Future.delayed(const Duration(milliseconds: 100), () {
        try {
          // Use go for main navigation to reset stack
          if (path == '/main') {
            _router.go(path);
          } else {
            // Use push for other screens to allow back navigation
            _router.push(path);
          }
        } catch (e) {
          print('Navigation error: $e');
          // Fallback to main screen if navigation fails
          _router.go('/main');
        }
      });
    }
  }
}
