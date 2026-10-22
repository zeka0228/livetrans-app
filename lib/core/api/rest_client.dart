import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../config/server_config.dart';
import '../models/audio_route.dart';
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
    this.ttsTimeout = const Duration(seconds: 20),
  }) : _client = client ?? http.Client();

  final ServerConfig config;
  final http.Client _client;
  final Duration timeout;

  /// 음성 합성은 모델에 따라 몇 초 걸릴 수 있어 따로 둔다.
  final Duration ttsTimeout;

  Future<HealthInfo> health() async {
    final json = await _get('/api/health');
    return HealthInfo.fromJson(json);
  }

  /// 캡처 가능한 창·프로세스 목록 (API 계약 S-9 ①).
  Future<CaptureTargets> captureTargets() async {
    final json = await _get('/api/capture/targets');
    return CaptureTargets.fromJson(json);
  }

  /// 출력 장치 목록 — 모드 A 격리 장치 선택용 (명세 v0.5 §6.1). 서버 미구현이면 404.
  Future<AudioDevices> audioDevices() async {
    final json = await _get('/api/audio/devices');
    return AudioDevices.fromJson(json);
  }

  /// 소리 격리 점검 (명세 §4.9 `check()`). 통과해야 모드 A 를 시작할 수 있다.
  Future<RouteStatus> routeCheck({
    required String router,
    required String isolationDevice,
  }) async {
    final json = await _post('/api/audio/route/check', {
      'router': router,
      'isolation_device': isolationDevice,
    });
    return RouteStatus.fromJson(json);
  }

  /// 지연 보정 — 권장 D (명세 §3.4). 실시간 속도로 샘플을 돌리므로 오래 걸릴 수 있다.
  Future<CalibrateResult> calibrate({Duration timeout = const Duration(seconds: 90)}) async {
    final res = await _client
        .post(
          config.rest('/api/calibrate'),
          headers: const {'content-type': 'application/json'},
          body: jsonEncode(const {}),
        )
        .timeout(timeout);
    return CalibrateResult.fromJson(_decode(res));
  }

  Future<SessionInfo> createSession(SessionRequest request) async {
    final json = await _post('/api/sessions', request.toJson());
    return SessionInfo.fromJson(json);
  }

  Future<void> stopSession(String sessionId) async {
    await _post('/api/sessions/$sessionId/stop', const {});
  }

  /// `GET /api/tts?text=&lang=` → WAV 바이트 (API 계약 S-13).
  Future<Uint8List> ttsWav({required String text, required String lang}) async {
    final res = await _client.get(ttsUri(text: text, lang: lang)).timeout(ttsTimeout);
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw ApiException.fromResponse(res);
    }
    return res.bodyBytes;
  }

  Uri ttsUri({required String text, required String lang}) =>
      config.rest('/api/tts').replace(queryParameters: {'text': text, 'lang': lang});

  /// `GET /api/voices` → 서버가 합성할 수 있는 언어 목록. 형식이 확정되기 전이라 원본 JSON 을 그대로 준다.
  Future<Map<String, dynamic>> voices() => _get('/api/voices');

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
