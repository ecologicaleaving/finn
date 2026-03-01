import 'dart:io';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Script to apply the MRU category tracking migration (065)
/// Run with: dart run scripts/apply_migration_065.dart
Future<void> main() async {
  print('🚀 Applying MRU category tracking migration (065)...\n');

  // Read environment variables or use default for local dev
  final supabaseUrl = Platform.environment['SUPABASE_URL'] ??
      'https://bkcpjplhikgxuonwwgxm.supabase.co';
  final supabaseAnonKey = Platform.environment['SUPABASE_ANON_KEY'] ??
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImJrY3BqcGxoaWtneHVvbnd3Z3htIiwicm9sZSI6ImFub24iLCJpYXQiOjE3MzU1Njc1NTAsImV4cCI6MjA1MTE0MzU1MH0.K5C9BxT2qpP9mNvXqzz2xNf5hRQC4O_YnKqXqzJ5Zj4';

  try {
    // Initialize Supabase
    await Supabase.initialize(
      url: supabaseUrl,
      anonKey: supabaseAnonKey,
    );

    final supabase = Supabase.instance.client;
    print('✅ Connected to Supabase\n');

    // Read migration SQL
    final migrationSql = await File('supabase/migrations/065_enhance_user_category_usage_for_mru.sql').readAsString();

    print('📝 Executing migration SQL...\n');

    // Execute migration (requires exec_sql function or RPC)
    // Note: If exec_sql doesn't exist, this will fail - use manual Dashboard method instead
    await supabase.rpc('exec_sql', params: {'sql': migrationSql});

    print('✅ Migration applied successfully!\n');
    print('📊 Changes made:');
    print('   - Added last_used_at column (TIMESTAMPTZ)');
    print('   - Added use_count column (INTEGER)');
    print('   - Created composite index for MRU queries');
    print('   - Created upsert_category_usage() RPC function');
    print('   - Updated existing records with baseline data\n');

  } catch (e) {
    print('❌ Migration failed:');
    print('   Error: $e\n');
    print('💡 Apply migration manually via Supabase Dashboard:');
    print('   1. Go to https://supabase.com/dashboard');
    print('   2. Select your project');
    print('   3. Go to SQL Editor');
    print('   4. Copy SQL from: supabase/migrations/065_enhance_user_category_usage_for_mru.sql');
    print('   5. Paste and run in the SQL Editor\n');
    exit(1);
  }
}
