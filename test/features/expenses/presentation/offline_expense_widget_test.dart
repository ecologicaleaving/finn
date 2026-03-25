import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:finn/features/offline/presentation/widgets/sync_status_banner.dart';
import 'package:finn/features/offline/presentation/providers/offline_providers.dart';
import 'package:finn/shared/services/connectivity_service.dart';

void main() {
  group('SyncStatusBanner widget', () {
    testWidgets('shows nothing when all synced (idle state)', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            syncStatusProvider.overrideWith((_) => const AsyncData(
              SyncStatusState.allSynced(),
            )),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: SyncStatusBanner(),
            ),
          ),
        ),
      );
      await tester.pump();

      // Should show nothing (SizedBox.shrink)
      expect(find.byType(MaterialBanner), findsNothing);
    });

    testWidgets('shows offline banner when offline with pending items', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            syncStatusProvider.overrideWith((_) => AsyncData(
              SyncStatusState.offlineWithPending(3),
            )),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: SyncStatusBanner(),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(MaterialBanner), findsOneWidget);
      expect(find.byIcon(Icons.cloud_off), findsOneWidget);
      expect(find.text('Offline - 3 expenses pending sync'), findsOneWidget);
    });

    testWidgets('shows syncing banner when online with pending items', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            syncStatusProvider.overrideWith((_) => AsyncData(
              SyncStatusState.syncing(2),
            )),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: SyncStatusBanner(),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(MaterialBanner), findsOneWidget);
      expect(find.text('Syncing 2 expenses...'), findsOneWidget);
    });
  });

  group('ExpenseSyncStatusIcon widget', () {
    testWidgets('shows pending icon for pending status', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ExpenseSyncStatusIcon(syncStatus: 'pending'),
          ),
        ),
      );
      expect(find.byIcon(Icons.cloud_upload_outlined), findsOneWidget);
    });

    testWidgets('shows error icon for failed status', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ExpenseSyncStatusIcon(syncStatus: 'failed'),
          ),
        ),
      );
      expect(find.byIcon(Icons.error_outline), findsOneWidget);
    });

    testWidgets('shows done icon for completed status', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ExpenseSyncStatusIcon(syncStatus: 'completed'),
          ),
        ),
      );
      expect(find.byIcon(Icons.cloud_done), findsOneWidget);
    });
  });
}
