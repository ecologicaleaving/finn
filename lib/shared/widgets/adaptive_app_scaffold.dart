import 'package:flutter/material.dart';

/// Keep the same destinations on phones and desktop, with room for the content.
class AdaptiveAppScaffold extends StatelessWidget {
  const AdaptiveAppScaffold({
    super.key,
    required this.body,
    required this.destinations,
    required this.selectedIndex,
    required this.onDestinationSelected,
    required this.onAdd,
  });

  final Widget body;
  final List<NavigationDestination> destinations;
  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 900;
          final extended = constraints.maxWidth >= 1200;
          return Scaffold(
            body: wide
                ? Row(
                    children: [
                      NavigationRail(
                        extended: extended,
                        selectedIndex: selectedIndex,
                        onDestinationSelected: onDestinationSelected,
                        labelType: extended
                            ? NavigationRailLabelType.none
                            : NavigationRailLabelType.all,
                        leading: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 24),
                          child: extended
                              ? Text('Finn',
                                  style: Theme.of(context)
                                      .textTheme
                                      .headlineMedium)
                              : const Icon(Icons.savings_outlined, size: 32),
                        ),
                        destinations: [
                          for (final destination in destinations)
                            NavigationRailDestination(
                              icon: destination.icon,
                              selectedIcon: destination.selectedIcon,
                              label: Text(destination.label),
                            ),
                        ],
                      ),
                      const VerticalDivider(width: 1),
                      Expanded(child: body),
                    ],
                  )
                : body,
            bottomNavigationBar: wide
                ? null
                : NavigationBar(
                    selectedIndex: selectedIndex,
                    onDestinationSelected: onDestinationSelected,
                    destinations: destinations,
                  ),
            floatingActionButton: FloatingActionButton(
              onPressed: onAdd,
              tooltip: 'Aggiungi spesa',
              shape: const CircleBorder(),
              child: const Icon(Icons.add),
            ),
          );
        },
      );
}
