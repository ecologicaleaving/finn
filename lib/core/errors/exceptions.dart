/// Custom exception classes for the application.
///
/// These exceptions are thrown by data sources and caught by repositories
/// to be converted into Failure objects.

/// Base class for all app exceptions
abstract class AppException implements Exception {
  const AppException(this.message, [this.code]);

  final String message;
  final String? code;

  @override
  String toString() => 'AppException: $message (code: $code)';
}

/// Exception thrown when a server/API request fails
class ServerException extends AppException {
  const ServerException(super.message, [super.code]);

  factory ServerException.fromStatusCode(int statusCode, [String? message]) {
    switch (statusCode) {
      case 400:
        return ServerException(message ?? 'Richiesta non valida', 'BAD_REQUEST');
      case 401:
        return const ServerException('Non autenticato', 'UNAUTHORIZED');
      case 403:
        return const ServerException('Accesso negato', 'FORBIDDEN');
      case 404:
        return ServerException(message ?? 'Risorsa non trovata', 'NOT_FOUND');
      case 409:
        return ServerException(message ?? 'Conflitto', 'CONFLICT');
      case 422:
        return ServerException(message ?? 'Dati non validi', 'UNPROCESSABLE');
      case 429:
        return const ServerException('Troppe richieste', 'RATE_LIMITED');
      case 500:
        return const ServerException('Errore del server', 'SERVER_ERROR');
      default:
        return ServerException(
          message ?? 'Errore sconosciuto ($statusCode)',
          'HTTP_$statusCode',
        );
    }
  }
}

/// Exception thrown when authentication fails
class AppAuthException extends AppException {
  const AppAuthException(super.message, [super.code]);

  static const invalidCredentials = AppAuthException(
    'Email o password non validi',
    'INVALID_CREDENTIALS',
  );

  static const emailAlreadyExists = AppAuthException(
    'Email già registrata',
    'EMAIL_EXISTS',
  );

  static const weakPassword = AppAuthException(
    'Password troppo debole',
    'WEAK_PASSWORD',
  );

  static const sessionExpired = AppAuthException(
    'Sessione scaduta',
    'SESSION_EXPIRED',
  );

  static const notAuthenticated = AppAuthException(
    'Utente non autenticato',
    'NOT_AUTHENTICATED',
  );
}

/// Exception thrown when local cache operations fail
class CacheException extends AppException {
  const CacheException(super.message, [super.code]);

  static const notFound = CacheException(
    'Dati non trovati nella cache',
    'CACHE_NOT_FOUND',
  );

  static const writeError = CacheException(
    'Errore di scrittura nella cache',
    'CACHE_WRITE_ERROR',
  );
}

/// Exception thrown when validation fails
class ValidationException extends AppException {
  const ValidationException(super.message, [super.code]);

  static const invalidEmail = ValidationException(
    'Formato email non valido',
    'INVALID_EMAIL',
  );

  static const invalidPassword = ValidationException(
    'La password deve avere almeno 8 caratteri',
    'INVALID_PASSWORD',
  );

  static const invalidAmount = ValidationException(
    'Importo non valido',
    'INVALID_AMOUNT',
  );

  static const invalidDate = ValidationException(
    'Data non valida',
    'INVALID_DATE',
  );

  static const futureDateNotAllowed = ValidationException(
    'La data non può essere nel futuro',
    'FUTURE_DATE',
  );
}

/// Exception thrown when concurrent edit conflicts occur (Feature 001-admin-expenses-cash-fix)
class ConflictException extends AppException {
  const ConflictException(super.message, [super.code]);

  static const expenseModified = ConflictException(
    'Questa spesa è stata modificata da un altro utente. Ricarica per vedere le ultime modifiche.',
    'EXPENSE_MODIFIED',
  );
}

/// Exception thrown when group operations fail
class GroupException extends AppException {
  const GroupException(super.message, [super.code]);

  static const notMember = GroupException(
    'Non sei membro di questo gruppo',
    'NOT_MEMBER',
  );

  static const notAdmin = GroupException(
    'Solo gli amministratori possono eseguire questa azione',
    'NOT_ADMIN',
  );

  static const groupFull = GroupException(
    'Il gruppo ha raggiunto il numero massimo di membri',
    'GROUP_FULL',
  );

  static const alreadyInGroup = GroupException(
    'Fai già parte di un gruppo',
    'ALREADY_IN_GROUP',
  );

  static const lastAdmin = GroupException(
    'Non puoi lasciare il gruppo essendo l\'unico amministratore',
    'LAST_ADMIN',
  );
}

/// Exception thrown when invite operations fail
class InviteException extends AppException {
  const InviteException(super.message, [super.code]);

  static const invalidCode = InviteException(
    'Codice invito non valido',
    'INVALID_CODE',
  );

  static const expired = InviteException(
    'Codice invito scaduto',
    'INVITE_EXPIRED',
  );

  static const alreadyUsed = InviteException(
    'Codice invito già utilizzato',
    'INVITE_USED',
  );
}

/// Exception thrown when OCR/scanning fails
class ScanException extends AppException {
  const ScanException(super.message, [super.code]);

  static const imageTooLarge = ScanException(
    'Immagine troppo grande (max 5MB)',
    'IMAGE_TOO_LARGE',
  );

  static const invalidFormat = ScanException(
    'Formato immagine non supportato',
    'INVALID_FORMAT',
  );

  static const ocrFailed = ScanException(
    'Impossibile leggere lo scontrino',
    'OCR_FAILED',
  );

  static const noTextFound = ScanException(
    'Nessun testo trovato nell\'immagine',
    'NO_TEXT_FOUND',
  );
}

/// Exception thrown when network is unavailable
class NetworkException extends AppException {
  const NetworkException([
    super.message = 'Connessione di rete non disponibile',
    super.code = 'NO_NETWORK',
  ]);
}

/// Exception thrown when permission is denied
class PermissionException extends AppException {
  const PermissionException(super.message, [super.code]);

  static const notAdmin = PermissionException(
    'Solo gli amministratori possono eseguire questa azione',
    'NOT_ADMIN',
  );

  static const accessDenied = PermissionException(
    'Accesso negato',
    'ACCESS_DENIED',
  );
}
