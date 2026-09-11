import 'package:shared_preferences/shared_preferences.dart';

/// Base URL + API key are entered once in Settings and stored on-device
/// (SharedPreferences), never hardcoded in source - this repo is public.
class AppConfig {
  static const _baseUrlKey = 'base_url';
  static const _apiKeyKey = 'api_key';
  static const defaultBaseUrl = 'https://personal-finance-omega-fawn.vercel.app';

  final String baseUrl;
  final String apiKey;

  const AppConfig({required this.baseUrl, required this.apiKey});

  bool get isConfigured => apiKey.isNotEmpty;

  static Future<AppConfig> load() async {
    final prefs = await SharedPreferences.getInstance();
    return AppConfig(
      baseUrl: prefs.getString(_baseUrlKey) ?? defaultBaseUrl,
      apiKey: prefs.getString(_apiKeyKey) ?? '',
    );
  }

  static Future<void> save({required String baseUrl, required String apiKey}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_baseUrlKey, baseUrl);
    await prefs.setString(_apiKeyKey, apiKey);
  }
}
