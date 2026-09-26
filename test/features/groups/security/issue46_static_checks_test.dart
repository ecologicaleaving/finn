// Static checks for issue #46 (group membership security).
//
// The Supabase migrations cannot be executed in unit tests, so these tests
// check the source: the app must not write profiles.group_id /
// profiles.is_group_admin directly, and the new migrations must contain the
// SECURITY DEFINER functions and policies required by the acceptance
// criteria.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _membershipMigration =
    'supabase/migrations/20260926_46_secure_group_membership.sql';
const _accountMigration = 'supabase/migrations/20260926_46_account_deletion.sql';

String _read(String path) => File(path).readAsStringSync();

/// Returns the body of `CREATE OR REPLACE FUNCTION public.<name>(...)` up to
/// the closing `$$;`.
String _functionBody(String sql, String name) {
  final start = sql.indexOf(
    RegExp('CREATE OR REPLACE FUNCTION public\\.$name\\(', caseSensitive: false),
  );
  expect(start, isNot(-1), reason: 'function $name not found');
  final end = sql.indexOf('\$\$;', start);
  expect(end, isNot(-1), reason: 'end of function $name not found');
  return sql.substring(start, end);
}

void main() {
  group('AC3: no direct membership writes in lib/', () {
    test('no .from(\'profiles\') write contains group_id or is_group_admin', () {
      final offenders = <String>[];
      final files = Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart') && !f.path.endsWith('.g.dart'));

      final writePattern = RegExp(
        r"""from\(\s*['"]profiles['"]\s*\)\s*\.\s*(update|upsert|insert)\s*\(""",
      );

      for (final file in files) {
        final content = file.readAsStringSync();
        for (final match in writePattern.allMatches(content)) {
          // Inspect the payload: from the opening parenthesis to the end of
          // the statement.
          final statementEnd = content.indexOf(';', match.end);
          final payload = content.substring(
            match.end,
            statementEnd == -1 ? content.length : statementEnd,
          );
          if (payload.contains('group_id') ||
              payload.contains('is_group_admin') ||
              payload.contains('toJson')) {
            offenders.add('${file.path}: ${match.group(0)}');
          }
        }
      }

      expect(offenders, isEmpty,
          reason: 'Membership must change only through SECURITY DEFINER RPCs');
    });

    test('group/invite datasources use the RPC functions', () {
      final groupDs = _read(
          'lib/features/groups/data/datasources/group_remote_datasource.dart');
      final inviteDs = _read(
          'lib/features/groups/data/datasources/invite_remote_datasource.dart');
      final authDs =
          _read('lib/features/auth/data/datasources/auth_remote_datasource.dart');

      expect(groupDs, contains("rpc('leave_group'"));
      expect(groupDs, contains("'remove_group_member'"));
      expect(groupDs, contains("rpc('delete_family_group'"));
      expect(groupDs, contains("'create_family_group'"));
      expect(inviteDs, contains("'validate_invite_code'"));
      expect(inviteDs, contains("'join_group_with_code'"));
      expect(authDs, contains("'delete_my_account'"));
      expect(authDs, isNot(contains("from('profiles').delete()")));
    });
  });

  group('migrations', () {
    late String membership;
    late String account;

    setUpAll(() {
      membership = _read(_membershipMigration);
      account = _read(_accountMigration);
    });

    test('AC1: trigger blocks direct changes of group_id / is_group_admin', () {
      final body =
          _functionBody(membership, 'prevent_profile_membership_change');
      expect(body, contains('NEW.group_id IS DISTINCT FROM OLD.group_id'));
      expect(body,
          contains('NEW.is_group_admin IS DISTINCT FROM OLD.is_group_admin'));
      expect(body, contains("current_user NOT IN ('authenticated', 'anon')"));
      expect(membership,
          contains('DROP TRIGGER IF EXISTS trg_profiles_protect_membership'));
      expect(membership, contains('CREATE TRIGGER trg_profiles_protect_membership'));
    });

    test('AC2: invites SELECT restricted to group admins', () {
      expect(membership,
          contains('DROP POLICY IF EXISTS "Anyone can validate invite codes"'));
      expect(membership, contains('DROP POLICY IF EXISTS "Users can use invites"'));
      expect(membership, contains('"Admins can view group invites"'));
      final invitesSelectUsingTrue = RegExp(
        r'ON public\.invites FOR SELECT\s+USING\s*\(\s*true\s*\)',
        caseSensitive: false,
      );
      expect(invitesSelectUsingTrue.hasMatch(membership), isFalse);
      expect(invitesSelectUsingTrue.hasMatch(account), isFalse);
    });

    test('AC2/3/5/6/7: functions are SECURITY DEFINER with search_path', () {
      final functions = {
        'validate_invite_code': membership,
        'create_family_group': membership,
        'join_group_with_code': membership,
        'leave_group': membership,
        'remove_group_member': membership,
        'delete_family_group': membership,
        'delete_my_account': account,
      };
      functions.forEach((name, sql) {
        final body = _functionBody(sql, name);
        expect(body, contains('SECURITY DEFINER'), reason: name);
        expect(body, contains('SET search_path = public'), reason: name);
        expect(body, contains('auth.uid()'), reason: name);
        expect(sql, contains('GRANT EXECUTE ON FUNCTION public.$name('),
            reason: name);
      });
    });

    test('AC2: validate_invite_code rejects invalid, used and expired codes', () {
      final body = _functionBody(membership, 'validate_invite_code');
      expect(body, contains("RAISE EXCEPTION 'invalid_code'"));
      expect(body, contains("RAISE EXCEPTION 'already_used'"));
      expect(body, contains("RAISE EXCEPTION 'expired'"));
      expect(body, contains('upper(btrim('));
    });

    test('AC3: join locks the invite and resets is_group_admin', () {
      final body = _functionBody(membership, 'join_group_with_code');
      expect(body, contains('FOR UPDATE'));
      expect(body, contains("RAISE EXCEPTION 'already_in_group'"));
      expect(body, contains('is_group_admin = false'));
    });

    test('AC4: leave / remove / delete set is_group_admin = false', () {
      for (final name in [
        'leave_group',
        'remove_group_member',
        'delete_family_group',
      ]) {
        expect(_functionBody(membership, name),
            contains('is_group_admin = false'),
            reason: name);
      }
    });

    test('AC5/AC6: 0 affected rows raise an error', () {
      final remove = _functionBody(membership, 'remove_group_member');
      expect(remove, contains('GET DIAGNOSTICS'));
      expect(remove, contains("RAISE EXCEPTION 'member_not_found'"));
      expect(remove, contains("RAISE EXCEPTION 'not_admin'"));

      final delete = _functionBody(membership, 'delete_family_group');
      expect(delete, contains('DELETE FROM public.family_groups'));
      expect(delete, contains('GET DIAGNOSTICS'));
      expect(delete, contains("RAISE EXCEPTION 'group_not_deleted'"));
      expect(delete, contains("RAISE EXCEPTION 'not_admin'"));
    });

    test('AC7: delete_my_account deletes from auth.users', () {
      final body = _functionBody(account, 'delete_my_account');
      expect(body, contains('DELETE FROM auth.users WHERE id = v_uid'));
      expect(body, contains("RAISE EXCEPTION 'admin_has_members'"));
      expect(body, contains('used_by = NULL'));
      expect(body, contains('last_modified_by = NULL'));
    });

    test('AC8: migrations are idempotent', () {
      for (final sql in [membership, account]) {
        expect(
          RegExp(r'CREATE FUNCTION', caseSensitive: true).hasMatch(sql),
          isFalse,
          reason: 'use CREATE OR REPLACE FUNCTION',
        );
        // Every CREATE POLICY / CREATE TRIGGER is preceded by a DROP ... IF EXISTS
        for (final m in RegExp(r'CREATE POLICY "([^"]+)"').allMatches(sql)) {
          expect(sql, contains('DROP POLICY IF EXISTS "${m.group(1)}"'));
        }
        for (final m in RegExp(r'CREATE TRIGGER (\w+)').allMatches(sql)) {
          expect(sql, contains('DROP TRIGGER IF EXISTS ${m.group(1)}'));
        }
        expect(sql, isNot(contains('ALTER TABLE')));
      }
    });
  });
}
