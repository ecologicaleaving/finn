import 'package:http/http.dart' as http;

/// Public Auth settings are reachable before a user signs in. A user-profile
/// request cannot serve as a connectivity probe: it fails locally without a
/// session and would leave a first-time browser visitor permanently offline.
Future<bool> checkBackendReachability({
  required String supabaseUrl,
  required String anonKey,
  http.Client? client,
  Duration timeout = const Duration(seconds: 5),
}) async {
  final transport = client ?? http.Client();
  try {
    final base = supabaseUrl.replaceFirst(RegExp(r'/+$'), '');
    final response = await transport.get(
      Uri.parse('$base/auth/v1/settings'),
      headers: {'apikey': anonKey},
    ).timeout(timeout);
    return response.statusCode == 200;
  } catch (_) {
    return false;
  } finally {
    if (client == null) transport.close();
  }
}
