import 'dart:typed_data';

/// Tipo di file di uno scontrino, riconosciuto dai magic bytes.
class ReceiptFileType {
  const ReceiptFileType(this.extension, this.contentType);

  final String extension;
  final String contentType;

  static const pdf = ReceiptFileType('pdf', 'application/pdf');
  static const png = ReceiptFileType('png', 'image/png');
  static const jpg = ReceiptFileType('jpg', 'image/jpeg');
  static const webp = ReceiptFileType('webp', 'image/webp');

  /// Riconosce il tipo dai primi byte. Input vuoto o sconosciuto: JPEG
  /// (comportamento storico), cosi' una spesa non viene mai bloccata.
  static ReceiptFileType detect(Uint8List bytes) {
    if (bytes.length >= 5 &&
        bytes[0] == 0x25 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x44 &&
        bytes[3] == 0x46 &&
        bytes[4] == 0x2D) {
      return pdf;
    }
    if (bytes.length >= 4 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4E &&
        bytes[3] == 0x47) {
      return png;
    }
    if (bytes.length >= 3 &&
        bytes[0] == 0xFF &&
        bytes[1] == 0xD8 &&
        bytes[2] == 0xFF) {
      return jpg;
    }
    if (bytes.length >= 12 &&
        bytes[0] == 0x52 && // R
        bytes[1] == 0x49 && // I
        bytes[2] == 0x46 && // F
        bytes[3] == 0x46 && // F
        bytes[8] == 0x57 && // W
        bytes[9] == 0x45 && // E
        bytes[10] == 0x42 && // B
        bytes[11] == 0x50) {
      // P
      return webp;
    }
    return jpg;
  }

  /// True se i byte sono un PDF.
  static bool isPdfBytes(Uint8List bytes) => detect(bytes) == pdf;

  /// Path nello storage: '<userId>/<expenseId>.<ext>'.
  static String storagePath(String userId, String expenseId, Uint8List bytes) =>
      '$userId/$expenseId.${detect(bytes).extension}';
}
