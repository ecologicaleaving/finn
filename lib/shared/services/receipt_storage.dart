// Durable receipt storage, selected at compile time for each platform.
export 'receipt_storage_native.dart'
    if (dart.library.html) 'receipt_storage_web.dart';
