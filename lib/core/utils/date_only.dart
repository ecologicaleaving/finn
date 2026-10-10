/// Helpers per inviare al server una data "solo giorno" (yyyy-MM-dd)
/// senza spostamenti di fuso (issue #66).

String _pad(int v, int width) => v.toString().padLeft(width, '0');

/// Converte [d] in yyyy-MM-dd.
///
/// - DateTime locale: usa i componenti locali.
/// - UTC a mezzanotte esatta: marcatore di sola data, usa i suoi componenti.
/// - UTC con altro orario: è un istante, si converte in locale.
String toServerDate(DateTime d) {
  var x = d;
  if (d.isUtc) {
    final isMidnight = d.hour == 0 &&
        d.minute == 0 &&
        d.second == 0 &&
        d.millisecond == 0 &&
        d.microsecond == 0;
    if (!isMidnight) x = d.toLocal();
  }
  return '${_pad(x.year, 4)}-${_pad(x.month, 2)}-${_pad(x.day, 2)}';
}

/// Normalizza una stringa data di un payload (con o senza orario/offset).
String serverDateFromPayload(String raw) => toServerDate(DateTime.parse(raw));
