import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/errors/exceptions.dart';

/// Helpers to interpret the results of the group/invite/account RPC functions
/// defined in `supabase/migrations/20260926_46_*.sql` (issue #46).
///
/// The SQL functions raise exceptions whose message is a short error code
/// (e.g. `invalid_code`, `not_admin`). These helpers map those codes to the
/// app exceptions with Italian messages.

/// Error codes raised by the invite-related functions.
const Map<String, String> inviteRpcErrorMessages = {
  'invalid_code': 'Codice invito non valido',
  'already_used': 'Questo codice invito è già stato utilizzato',
  'expired': 'Questo codice invito è scaduto',
};

/// Error codes raised by the group/account functions.
const Map<String, String> groupRpcErrorMessages = {
  'already_in_group':
      'Fai già parte di un gruppo. Devi prima uscire dal gruppo attuale.',
  'not_in_group': 'Non fai parte di nessun gruppo',
  'not_admin': 'Solo l\'amministratore può eseguire questa azione',
  'admin_cannot_leave':
      'L\'amministratore non può lasciare il gruppo se ci sono altri membri',
  'has_members': 'Il gruppo non può essere eliminato se ci sono altri membri',
  'member_not_found': 'Membro non trovato in questo gruppo',
  'cannot_remove_self': 'Non puoi rimuovere te stesso',
  'cannot_remove_admin': 'Non puoi rimuovere l\'amministratore del gruppo',
  'group_not_deleted': 'Il gruppo non è stato eliminato',
  'invalid_group_name': 'Il nome del gruppo deve avere tra 2 e 30 caratteri',
  'admin_has_members':
      'Sei amministratore di un gruppo con altri membri: rimuovi i membri o '
          'elimina il gruppo prima di eliminare l\'account',
  'account_not_deleted': 'L\'account non è stato eliminato',
  'membership_change_not_allowed': 'Operazione non consentita',
};

/// Extracts the error code raised by an RPC function from a
/// [PostgrestException] message, or `null` if it is not a known code.
String? rpcErrorCode(PostgrestException e) {
  final message = e.message.trim();
  if (inviteRpcErrorMessages.containsKey(message) ||
      groupRpcErrorMessages.containsKey(message) ||
      message == 'not_authenticated') {
    return message;
  }
  // Be tolerant with messages that carry a prefix (e.g. "ERROR: code").
  for (final code in [
    ...inviteRpcErrorMessages.keys,
    ...groupRpcErrorMessages.keys,
    'not_authenticated',
  ]) {
    if (RegExp('(^|[^a-z_])$code(\$|[^a-z_])').hasMatch(message)) {
      return code;
    }
  }
  return null;
}

/// Maps a [PostgrestException] raised by a group/invite/account RPC to the
/// matching app exception.
///
/// - invite codes -> [InviteException]
/// - group codes -> [GroupException]
/// - `not_authenticated` -> [AppAuthException]
/// - anything else -> [ServerException]
AppException mapGroupRpcError(PostgrestException e) {
  final code = rpcErrorCode(e);
  if (code == null) {
    return ServerException(e.message, e.code);
  }
  if (code == 'not_authenticated') {
    return const AppAuthException('Nessun utente autenticato', 'not_authenticated');
  }
  final inviteMessage = inviteRpcErrorMessages[code];
  if (inviteMessage != null) {
    return InviteException(inviteMessage, code);
  }
  return GroupException(groupRpcErrorMessages[code]!, code);
}

/// Ensures that an RPC that returns the number of affected rows actually
/// changed something. Throws a [GroupException] with [errorCode] otherwise.
///
/// Returns the number of affected rows.
int ensureAffected(dynamic rpcResult, String errorCode) {
  int? rows;
  if (rpcResult is int) {
    rows = rpcResult;
  } else if (rpcResult is num) {
    rows = rpcResult.toInt();
  } else if (rpcResult is String) {
    rows = int.tryParse(rpcResult);
  }

  if (rows == null || rows <= 0) {
    throw GroupException(
      groupRpcErrorMessages[errorCode] ?? 'Nessuna modifica effettuata',
      errorCode,
    );
  }
  return rows;
}
