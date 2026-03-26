import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/routes.dart';
import '../../../dashboard/presentation/screens/dashboard_screen.dart';
import '../../../expenses/presentation/screens/expense_tabs_screen.dart';
import '../../../groups/presentation/providers/group_provider.dart';
import '../../../offline/presentation/providers/offline_providers.dart';
import '../../../offline/presentation/widgets/sync_status_banner.dart';
import 'settings_screen.dart';

/// Main navigation screen with bottom navigation bar.
class MainNavigationScreen extends ConsumerStatefulWidget {
  const MainNavigationScreen({super.key});

  @override
  ConsumerState<MainNavigationScreen> createState() =>
      _MainNavigationScreenState();
}

class _MainNavigationScreenState extends ConsumerState<MainNavigationScreen> {
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    // Load group data when the screen is first shown
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(groupProvider.notifier).loadCurrentGroup();
      // T9: Initialize SyncTrigger to activate auto-sync on connectivity change.
      // The provider's build() method sets up a listener on connectivityServiceProvider
      // that triggers sync whenever network is restored.
      // Bug #2 fix: use ref.read to initialise; SyncTrigger is keepAlive so it
      // stays alive for the entire app lifetime without needing a watch here.
      ref.read(syncTriggerProvider.notifier);
    });
  }

  final List<Widget> _screens = const [
    DashboardScreen(),
    ExpenseTabsScreen(),
    SettingsScreen(),
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
      icon: Icon(Icons.settings_outlined),
      selectedIcon: Icon(Icons.settings),
      label: 'Impostazioni',
    ),
  ];

  void _onDestinationSelected(int index) {
    setState(() {
      _currentIndex = index;
    });
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
    return Scaffold(
      // T10: Sync status banner — shown above content when offline/pending
      // Bug #4 fix: wrap banner in SafeArea so it respects the status bar
      // height and is not clipped behind it.
      body: Column(
        children: [
          SafeArea(
            bottom: false,
            child: const SyncStatusBanner(),
          ),
          Expanded(
            child: IndexedStack(
              index: _currentIndex,
              children: _screens,
            ),
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: _onDestinationSelected,
        destinations: _destinations,
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddExpenseOptions,
        tooltip: 'Aggiungi spesa',
        shape: const CircleBorder(),
        child: const Icon(Icons.add),
      ),
    );
  }
}
