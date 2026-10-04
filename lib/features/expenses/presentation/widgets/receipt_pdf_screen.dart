import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../shared/widgets/receipt_pdf_viewer.dart';
import '../providers/receipt_image_provider.dart';

/// Downloads a PDF receipt from storage and shows it full screen.
class ReceiptPdfScreen extends ConsumerWidget {
  const ReceiptPdfScreen({super.key, required this.receiptPath});

  final String receiptPath;

  static Future<void> show(BuildContext context, String receiptPath) {
    return Navigator.of(context).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => ReceiptPdfScreen(receiptPath: receiptPath),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bytesAsync = ref.watch(receiptFileBytesProvider(receiptPath));

    return bytesAsync.when(
      data: (bytes) => ReceiptPdfViewer(bytes: bytes),
      loading: () => Scaffold(
        appBar: AppBar(title: const Text('Scontrino PDF')),
        body: const Center(child: CircularProgressIndicator()),
      ),
      error: (error, _) => Scaffold(
        appBar: AppBar(title: const Text('Scontrino PDF')),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.picture_as_pdf, size: 48),
              const SizedBox(height: 8),
              const Text('Impossibile scaricare il PDF'),
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: () =>
                    ref.invalidate(receiptFileBytesProvider(receiptPath)),
                icon: const Icon(Icons.refresh, size: 16),
                label: const Text('Riprova'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
