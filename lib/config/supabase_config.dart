import 'package:supabase_flutter/supabase_flutter.dart';
import 'app_constants.dart';

class SupabaseConfig {
  static Future<void> initialize() async {
    await Supabase.initialize(
      url: AppConstants.supabaseUrl,
      anonKey: AppConstants.supabaseAnonKey,
      authOptions: const FlutterAuthClientOptions(
        authFlowType: AuthFlowType.pkce,
      ),
    );
  }

  static SupabaseClient get client => Supabase.instance.client;

  static dynamic get auth => Supabase.instance.client.auth;

  static dynamic get realtime => Supabase.instance.client.realtime;
}
