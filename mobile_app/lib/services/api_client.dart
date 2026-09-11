import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/app_config.dart';
import '../models/transaction.dart';

class ApiException implements Exception {
  final String message;
  ApiException(this.message);
  @override
  String toString() => message;
}

class SyncResult {
  final bool success;
  final List<String> processed;
  final List<Map<String, dynamic>> failed;
  final int serverVersion;

  SyncResult({
    required this.success,
    required this.processed,
    required this.failed,
    required this.serverVersion,
  });

  factory SyncResult.fromJson(Map<String, dynamic> json) => SyncResult(
        success: json['success'] as bool,
        processed: (json['processed'] as List).cast<String>(),
        failed: (json['failed'] as List).cast<Map<String, dynamic>>(),
        serverVersion: json['server_version'] as int,
      );
}

class ApiClient {
  final AppConfig config;
  ApiClient(this.config);

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        'X-API-Key': config.apiKey,
      };

  Uri _uri(String path) => Uri.parse('${config.baseUrl}$path');

  Future<Map<String, dynamic>> getSetup(int year) async {
    final resp = await http.get(_uri('/api/v1/setup/$year'), headers: _headers);
    _checkOk(resp);
    return jsonDecode(resp.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> getSummary(int year, int month) async {
    final resp = await http.get(_uri('/api/v1/summary/$year/$month'), headers: _headers);
    _checkOk(resp);
    return jsonDecode(resp.body) as Map<String, dynamic>;
  }

  Future<List<dynamic>> getTransactions(int year, int month) async {
    final resp =
        await http.get(_uri('/api/v1/months/$year/$month/transactions'), headers: _headers);
    _checkOk(resp);
    return jsonDecode(resp.body) as List<dynamic>;
  }

  Future<SyncResult> sync(List<LocalTransaction> pending, {String clientId = 'flutter-app'}) async {
    final body = jsonEncode({
      'client_id': clientId,
      'operations': pending.map((t) => t.toSyncOperation()).toList(),
    });
    final resp = await http.post(_uri('/api/v1/sync'), headers: _headers, body: body);
    _checkOk(resp);
    return SyncResult.fromJson(jsonDecode(resp.body) as Map<String, dynamic>);
  }

  void _checkOk(http.Response resp) {
    if (resp.statusCode == 401) {
      throw ApiException('Invalid API key. Check Settings.');
    }
    if (resp.statusCode >= 400) {
      throw ApiException('API error ${resp.statusCode}: ${resp.body}');
    }
  }
}
