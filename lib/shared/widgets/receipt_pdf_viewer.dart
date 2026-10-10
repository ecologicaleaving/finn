import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:pdfx/pdfx.dart';

/// Full-screen viewer for a PDF receipt already available as bytes.
class ReceiptPdfViewer extends StatefulWidget {
  const ReceiptPdfViewer({super.key, required this.bytes});

  final Uint8List bytes;

  /// Opens the viewer as a full-screen route.
  static Future<void> show(BuildContext context, Uint8List bytes) {
    return Navigator.of(context).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => ReceiptPdfViewer(bytes: bytes),
      ),
    );
  }

  @override
  State<ReceiptPdfViewer> createState() => _ReceiptPdfViewerState();
}

class _ReceiptPdfViewerState extends State<ReceiptPdfViewer> {
  late PdfControllerPinch _controller;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _controller = _createController();
  }

  PdfControllerPinch _createController() => PdfControllerPinch(
        document: PdfDocument.openData(widget.bytes),
      );

  void _retry() {
    final old = _controller;
    setState(() {
      _error = null;
      _controller = _createController();
    });
    old.dispose();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Scontrino PDF')),
      body: _error != null
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.picture_as_pdf, size: 48),
                  const SizedBox(height: 8),
                  const Text('Impossibile aprire il PDF'),
                  const SizedBox(height: 8),
                  TextButton.icon(
                    onPressed: _retry,
                    icon: const Icon(Icons.refresh, size: 16),
                    label: const Text('Riprova'),
                  ),
                ],
              ),
            )
          : PdfViewPinch(
              controller: _controller,
              onDocumentError: (error) {
                if (mounted) setState(() => _error = error);
              },
              builders: PdfViewPinchBuilders<DefaultBuilderOptions>(
                options: const DefaultBuilderOptions(),
                documentLoaderBuilder: (_) =>
                    const Center(child: CircularProgressIndicator()),
                pageLoaderBuilder: (_) =>
                    const Center(child: CircularProgressIndicator()),
              ),
            ),
    );
  }
}
