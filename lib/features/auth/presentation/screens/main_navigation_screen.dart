import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/routes.dart';
import '../../../../shared/widgets/adaptive_app_scaffold.dart';
import '../../../../shared/widgets/loading_indicator.dart';
import '../../../../shared/widgets/error_display.dart';
import '../providers/auth_provider.dart';
import '../../../dashboard/presentation/screens/dashboard_screen.dart';
import '../../../expenses/presentation/screens/expense_tabs_screen.dart';
import '../../../reports/presentation/report_screen.dart';
import '../../../widget/presentation/services/widget_update_service.dart';
import 'settings_screen.dart';

/// Main navigation screen with bottom navigation bar.
class MainNavigationScreen extends ConsumerStatefulWidget {
  const MainNavigationScreen({super.key, this.initialIndex = 0});
  final int initialIndex;

  @override
  ConsumerState<MainNavigationScreen> createState() =>
      _MainNavigationScreenState();
}

class _MainNavigationScreenState extends ConsumerState<MainNavigationScreen> {
  int _currentIndex = 0;
  final Set<int> _visitedTabs = {};

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex.clamp(0, 3);
    _visitedTabs.add(_currentIndex);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Repopulate the widget for the current user (issue #64 AC4).
      // Fire and forget: offline it fails silently.
      ref.read(widgetUpdateServiceProvider).triggerUpdate().catchError((_) {});
    });
  }

  @override
  void didUpdateWidget(covariant MainNavigationScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    _currentIndex = widget.initialIndex.clamp(0, 3);
    _visitedTabs.add(_currentIndex);
  }

  List<Widget> get _screens => [
    _visitedTabs.contains(0) ? const DashboardScreen() : const SizedBox.shrink(),
    _visitedTabs.contains(1) ? const ExpenseTabsScreen() : const SizedBox.shrink(),
    _visitedTabs.contains(2) ? ReportScreen(active: _currentIndex == 2) : const SizedBox.shrink(),
    _visitedTabs.contains(3) ? const SettingsScreen() : const SizedBox.shrink(),
  ];

  final List<NavigationDestination> _destinations = const [
    NavigationDestination(
      icon: Icon(Icons.dashboard_outlined),
      selectedIcon: Icon(Icons.dashboard),
      label: 'Dashboard',
    ),
    NavigationDestination(
      icon: Icon(Icons.receipt_long_outlined),
      selectedIcon: Icon(Icons.receipt_long),
      label: 'Spese',
    ),
    NavigationDestination(
      icon: Icon(Icons.bar_chart_outlined),
      selectedIcon: Icon(Icons.bar_chart),
      label: 'Report',
    ),
    NavigationDestination(
      icon: Icon(Icons.settings_outlined),
      selectedIcon: Icon(Icons.settings),
      label: 'Impostazioni',
    ),
  ];

  void _onDestinationSelected(int index) {
    setState(() {
      _currentIndex = index;
      _visitedTabs.add(index);
    });
    context.go(index == 2 ? AppRoutes.report : '${AppRoutes.main}?tab=$index');
  }

  void _showAddExpenseOptions() {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('Inserimento manuale'),
              subtitle: const Text('Aggiungi una spesa manualmente'),
              onTap: () {
                Navigator.pop(context);
                context.push(AppRoutes.addExpense);
              },
            ),
            ListTile(
              leading: const Icon(Icons.arrow_upward, color: Color(0xFF2E7D32)),
              title: const Text('Aggiungi entrata'),
              subtitle: const Text('Registra un\'entrata una tantum'),
              onTap: () {
                Navigator.pop(context);
                context.push(AppRoutes.addIncome);
              },
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt_outlined),
              title: const Text('Scansiona scontrino'),
              subtitle: const Text('Usa la fotocamera per scansionare'),
              onTap: () {
                Navigator.pop(context);
                context.push(AppRoutes.scanReceipt);
              },
            ),
            ListTile(
              leading: const Icon(Icons.upload_file_outlined),
              title: const Text('Carica File'),
              subtitle: const Text('Carica ricevuta PDF o immagine'),
              onTap: () {
                Navigator.pop(context);
                context.push(AppRoutes.uploadFile);
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Browser routes can be restored before the profile request completes.
    final authState = ref.watch(authProvider);
    if (authState.user == null) {
      if (authState.status == AuthStatus.initial || authState.isLoading) {
        return const Scaffold(
          body: LoadingIndicator(message: 'Caricamento profilo...'),
        );
      }
      return Scaffold(
        body: ErrorDisplay(
          message: authState.errorMessage ??
              'Impossibile caricare il profilo. Riprova.',
          onRetry: () => ref.read(authProvider.notifier).retryCurrentUser(),
        ),
      );
    }
    return AdaptiveAppScaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: _screens,
      ),
      selectedIndex: _currentIndex,
      onDestinationSelected: _onDestinationSelected,
      destinations: _destinations,
      onAdd: _showAddExpenseOptions,
    );
  }
}
