import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../config/server_config.dart';
import '../models/session.dart';

class ApiException implements Exception {
  ApiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() =>
      statusCode == null ? message : 'HTTP $statusCode: $message';
}

class RestClient {
  RestClient(
    this.config, {
    http.Client? client,
    this.timeout = const Duration(seconds: 5),
  }) : _client = client ?? http.Client();

  final ServerConfig config;
  final http.Client _client;
  final Duration timeout;

  Future<HealthInfo> health() async {
    final json = await _get('/api/health');
    return HealthInfo.fromJson(json);
  }

  Future<SessionInfo> createSession(SessionRequest request) async {
    final json = await _post('/api/sessions', request.toJson());
    return SessionInfo.fromJson(json);
  }

  Future<void> stopSession(String sessionId) async {
    await _post('/api/sessions/$sessionId/stop', const {});
  }

  Future<Map<String, dynamic>> _get(String path) async {
    final res = await _client.get(config.rest(path)).timeout(timeout);
    return _decode(res);
  }

  Future<Map<String, dynamic>> _post(
    String path,
    Map<String, dynamic> body,
  ) async {
    final res = await _client
        .post(
          config.rest(path),
          headers: const {'content-type': 'application/json'},
          body: jsonEncode(body),
        )
        .timeout(timeout);
    return _decode(res);
  }

  Map<String, dynamic> _decode(http.Response res) {
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw ApiException(res.body, statusCode: res.statusCode);
    }
    if (res.bodyBytes.isEmpty) return const {};
    final decoded = jsonDecode(utf8.decode(res.bodyBytes));
    return decoded is Map<String, dynamic> ? decoded : const {};
  }
}

final restClientProvider = Provider<RestClient>((ref) {
  return RestClient(ref.watch(serverConfigProvider));
});
