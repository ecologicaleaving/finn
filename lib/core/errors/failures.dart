import 'package:equatable/equatable.dart';

/// Base class for all failures in the application.
///
/// Failures are returned by repositories when an operation fails.
/// They are used for error handling at the presentation layer.
abstract class Failure extends Equatable {
  const Failure(this.message, [this.code]);

  final String message;
  final String? code;

  @override
  List<Object?> get props => [message, code];
}

/// Failure for server/API errors
class ServerFailure extends Failure {
  const ServerFailure(super.message, [super.code]);
}

/// Failure for authentication errors
class AuthFailure extends Failure {
  const AuthFailure(super.message, [super.code]);

  static const invalidCredentials = AuthFailure(
    'Email o password non validi',
    'INVALID_CREDENTIALS',
  );

  static const emailAlreadyExists = AuthFailure(
    'Email già registrata',
    'EMAIL_EXISTS',
  );

  static const sessionExpired = AuthFailure(
    'Sessione scaduta, effettua nuovamente l\'accesso',
    'SESSION_EXPIRED',
  );

  static const notAuthenticated = AuthFailure(
    'Utente non autenticato',
    'NOT_AUTHENTICATED',
  );
}

/// Failure for cache/local storage errors
class CacheFailure extends Failure {
  const CacheFailure(super.message, [super.code]);
}

/// Failure for validation errors
class ValidationFailure extends Failure {
  const ValidationFailure(super.message, [super.code]);
}

/// Failure for concurrent edit conflicts (Feature 001-admin-expenses-cash-fix)
class ConflictFailure extends Failure {
  const ConflictFailure(super.message, [super.code]);

  static const expenseModified = ConflictFailure(
    'Questa spesa è stata modificata da un altro utente. Ricarica per vedere le ultime modifiche.',
    'EXPENSE_MODIFIED',
  );
}

/// Failure for group operations
class GroupFailure extends Failure {
  const GroupFailure(super.message, [super.code]);

  static const notMember = GroupFailure(
    'Non sei membro di questo gruppo',
    'NOT_MEMBER',
  );

  static const notAdmin = GroupFailure(
    'Solo gli amministratori possono eseguire questa azione',
    'NOT_ADMIN',
  );

  static const groupFull = GroupFailure(
    'Il gruppo ha raggiunto il numero massimo di membri',
    'GROUP_FULL',
  );

  static const alreadyInGroup = GroupFailure(
    'Fai già parte di un gruppo. Lascia il gruppo attuale prima di unirti a un altro.',
    'ALREADY_IN_GROUP',
  );
}

/// Failure for invite operations
class InviteFailure extends Failure {
  const InviteFailure(super.message, [super.code]);

  static const invalidCode = InviteFailure(
    'Codice invito non valido',
    'INVALID_CODE',
  );

  static const expired = InviteFailure(
    'Codice invito scaduto. Chiedi un nuovo codice.',
    'INVITE_EXPIRED',
  );

  static const alreadyUsed = InviteFailure(
    'Codice invito già utilizzato',
    'INVITE_USED',
  );
}

/// Failure for receipt scanning/OCR
class ScanFailure extends Failure {
  const ScanFailure(super.message, [super.code]);

  static const imageTooLarge = ScanFailure(
    'Immagine troppo grande. Massimo 5MB.',
    'IMAGE_TOO_LARGE',
  );

  static const ocrFailed = ScanFailure(
    'Impossibile leggere lo scontrino. Riprova o inserisci i dati manualmente.',
    'OCR_FAILED',
  );
}

/// Failure for network errors
class NetworkFailure extends Failure {
  const NetworkFailure([
    super.message = 'Connessione di rete non disponibile. Controlla la connessione e riprova.',
    super.code = 'NO_NETWORK',
  ]);
}

/// Failure for unexpected errors
class UnexpectedFailure extends Failure {
  const UnexpectedFailure([
    super.message = 'Si è verificato un errore imprevisto. Riprova più tardi.',
    super.code = 'UNEXPECTED',
  ]);
}

/// Failure for permission errors
class PermissionFailure extends Failure {
  const PermissionFailure(super.message, [super.code]);

  static const notAdmin = PermissionFailure(
    'Solo gli amministratori possono eseguire questa azione',
    'NOT_ADMIN',
  );

  static const accessDenied = PermissionFailure(
    'Accesso negato',
    'ACCESS_DENIED',
  );
}
