import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../config/server_config.dart';
import '../models/capture_target.dart';
import '../models/session.dart';

/// REST 오류. 서버가 `{"detail": {"code", "message"}}` 형식으로 주면 [code]·[message]에 풀어 담는다 (API 계약 Q-API-7).
class ApiException implements Exception {
  ApiException(this.message, {this.statusCode, this.code});

  final String message;
  final int? statusCode;
  final String? code;

  factory ApiException.fromResponse(http.Response res) {
    String message = res.body;
    String? code;
    try {
      final decoded = jsonDecode(utf8.decode(res.bodyBytes));
      final detail = decoded is Map ? decoded['detail'] : null;
      if (detail is Map) {
        code = detail['code']?.toString();
        message = detail['message']?.toString() ?? message;
      } else if (detail != null) {
        message = detail.toString();
      }
    } catch (_) {}
    return ApiException(message, statusCode: res.statusCode, code: code);
  }

  @override
  String toString() {
    final prefix = code ?? (statusCode == null ? null : 'HTTP $statusCode');
    return prefix == null ? message : '$prefix: $message';
  }
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

  /// 캡처 가능한 창·프로세스 목록 (API 계약 S-9 ①).
  Future<CaptureTargets> captureTargets() async {
    final json = await _get('/api/capture/targets');
    return CaptureTargets.fromJson(json);
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
      throw ApiException.fromResponse(res);
    }
    if (res.bodyBytes.isEmpty) return const {};
    final decoded = jsonDecode(utf8.decode(res.bodyBytes));
    return decoded is Map<String, dynamic> ? decoded : const {};
  }
}

final restClientProvider = Provider<RestClient>((ref) {
  return RestClient(ref.watch(serverConfigProvider));
});
