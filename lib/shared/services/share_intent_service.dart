import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:receive_sharing_intent/receive_sharing_intent.dart';
import 'package:flutter/foundation.dart';

/// Callback type for when shared image data is received.
typedef SharedImageCallback = void Function(Uint8List imageData);

/// Service for handling incoming share intents from other apps.
///
/// Allows users to share images directly from their device's gallery
/// or camera app to Fin for receipt processing.
class ShareIntentService {
  ShareIntentService._();

  static StreamSubscription<List<SharedMediaFile>>? _streamSubscription;
  static SharedImageCallback? _callback;
  static Uint8List? _pendingImageData;
  static bool _isInitialized = false;

  /// Initialize the share intent service.
  ///
  /// Sets up listeners for both:
  /// - Stream: Images shared when app is already running
  /// - Initial media: Images shared when app is launched via share
  static Future<void> initialize() async {
    if (kIsWeb || _isInitialized) return;

    try {
      // Handle media shared when app is already running
      _streamSubscription =
          ReceiveSharingIntent.instance.getMediaStream().listen(
        _handleSharedMedia,
        onError: (error) {
          // Silently handle stream errors
        },
      );

      // Handle media shared when app was launched via share intent
      final initialMedia =
          await ReceiveSharingIntent.instance.getInitialMedia();
      if (initialMedia.isNotEmpty) {
        await _handleSharedMedia(initialMedia);
      }

      _isInitialized = true;
    } catch (e) {
      // Service initialization failed, app can still function normally
    }
  }

  /// Set the callback to be invoked when shared image data is received.
  ///
  /// If there is pending image data from a cold start share,
  /// the callback will be invoked immediately with that data.
  static void setCallback(SharedImageCallback? callback) {
    _callback = callback;

    // If we have pending data from cold start, deliver it now
    if (_pendingImageData != null && _callback != null) {
      final data = _pendingImageData!;
      _pendingImageData = null;
      _callback!(data);
    }
  }

  /// Check if there is pending image data waiting to be processed.
  static bool get hasPendingImage => _pendingImageData != null;

  /// Get and clear the pending image data.
  ///
  /// Returns null if there is no pending data.
  static Uint8List? consumePendingImage() {
    final data = _pendingImageData;
    _pendingImageData = null;
    return data;
  }

  /// Process a list of shared media files.
  ///
  /// Only processes the first image file, as the app handles
  /// one receipt at a time.
  static Future<void> _handleSharedMedia(List<SharedMediaFile> files) async {
    if (files.isEmpty) return;

    // Filter for image files only and take the first one
    final imageFile = files.firstWhere(
      (file) => file.type == SharedMediaType.image,
      orElse: () => files.first,
    );

    // Only process if it's an image
    if (imageFile.type != SharedMediaType.image) {
      return;
    }

    final imageData = await _loadImageFromPath(imageFile.path);
    if (imageData == null) return;

    // Reset the intent to prevent duplicate processing
    reset();

    // Deliver to callback or store for later
    if (_callback != null) {
      _callback!(imageData);
    } else {
      // Store for when callback is set (cold start scenario)
      _pendingImageData = imageData;
    }
  }

  /// Load image data from a file path.
  ///
  /// Returns null if the file doesn't exist or can't be read.
  static Future<Uint8List?> _loadImageFromPath(String path) async {
    try {
      final file = File(path);
      if (!await file.exists()) {
        return null;
      }
      return await file.readAsBytes();
    } catch (e) {
      return null;
    }
  }

  /// Reset the share intent to prevent duplicate processing.
  ///
  /// Should be called after successfully processing a shared image.
  static void reset() {
    if (kIsWeb) return;
    try {
      ReceiveSharingIntent.instance.reset();
    } catch (e) {
      // Ignore reset errors
    }
  }

  /// Dispose the share intent service.
  ///
  /// Cancels the stream subscription and clears all state.
  static Future<void> dispose() async {
    await _streamSubscription?.cancel();
    _streamSubscription = null;
    _callback = null;
    _pendingImageData = null;
    _isInitialized = false;
  }
}
