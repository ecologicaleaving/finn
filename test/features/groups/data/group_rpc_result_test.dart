import 'package:family_expense_tracker/core/errors/exceptions.dart';
import 'package:family_expense_tracker/features/groups/data/datasources/group_rpc_result.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

PostgrestException _pg(String message, [String? code = 'P0001']) =>
    PostgrestException(message: message, code: code);

void main() {
  group('mapGroupRpcError', () {
    test('invite codes map to InviteException', () {
      for (final code in ['invalid_code', 'already_used', 'expired']) {
        final e = mapGroupRpcError(_pg(code));
        expect(e, isA<InviteException>(), reason: code);
        expect(e.code, code);
        expect(e.message, inviteRpcErrorMessages[code]);
      }
    });

    test('group codes map to GroupException with Italian messages', () {
      for (final code in groupRpcErrorMessages.keys) {
        final e = mapGroupRpcError(_pg(code));
        expect(e, isA<GroupException>(), reason: code);
        expect(e.code, code);
        expect(e.message, groupRpcErrorMessages[code]);
        expect(e.message, isNot(contains('_')), reason: code);
      }
    });

    test('member_not_found is an error, not a success', () {
      final e = mapGroupRpcError(_pg('member_not_found'));
      expect(e, isA<GroupException>());
      expect(e.message, 'Membro non trovato in questo gruppo');
    });

    test('not_authenticated maps to AppAuthException', () {
      final e = mapGroupRpcError(_pg('not_authenticated', '28000'));
      expect(e, isA<AppAuthException>());
    });

    test('code embedded in a longer message is recognised', () {
      final e = mapGroupRpcError(_pg('ERROR: admin_cannot_leave'));
      expect(e, isA<GroupException>());
      expect(e.code, 'admin_cannot_leave');
    });

    test('unknown errors fall back to ServerException', () {
      final e = mapGroupRpcError(_pg('permission denied for table x', '42501'));
      expect(e, isA<ServerException>());
      expect(e.code, '42501');
    });

    test('does not confuse codes that are substrings of words', () {
      final e = mapGroupRpcError(_pg('token_expired_really'));
      expect(e, isA<ServerException>());
    });
  });

  group('ensureAffected', () {
    test('returns the row count when > 0', () {
      expect(ensureAffected(1, 'member_not_found'), 1);
      expect(ensureAffected(2.0, 'member_not_found'), 2);
      expect(ensureAffected('3', 'member_not_found'), 3);
    });

    test('throws GroupException when 0 rows were affected', () {
      expect(
        () => ensureAffected(0, 'member_not_found'),
        throwsA(isA<GroupException>()
            .having((e) => e.code, 'code', 'member_not_found')),
      );
    });

    test('throws GroupException when the result is null', () {
      expect(
        () => ensureAffected(null, 'group_not_deleted'),
        throwsA(isA<GroupException>()
            .having((e) => e.code, 'code', 'group_not_deleted')
            .having((e) => e.message, 'message',
                'Il gruppo non è stato eliminato')),
      );
    });

    test('throws GroupException for non-numeric results', () {
      expect(
        () => ensureAffected({'ok': true}, 'group_not_deleted'),
        throwsA(isA<GroupException>()),
      );
      expect(
        () => ensureAffected(-1, 'group_not_deleted'),
        throwsA(isA<GroupException>()),
      );
    });
  });
}
