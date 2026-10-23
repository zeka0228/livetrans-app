import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 서버 주소 설정. Android 에뮬레이터에서는 호스트 PC가 10.0.2.2, 웹·데스크톱은 127.0.0.1.
class ServerConfig {
  const ServerConfig({required this.baseUrl});

  final String baseUrl;

  /// 빌드 시 `--dart-define=LIVETRANS_SERVER=http://127.0.0.1:8766` 으로 기본 서버를 바꿀 수 있다 (가짜 서버 검증용).
  static const _override = String.fromEnvironment('LIVETRANS_SERVER');

  static String defaultBaseUrl() {
    if (_override.isNotEmpty) return _override;
    return !kIsWeb && defaultTargetPlatform == TargetPlatform.android
        ? 'http://10.0.2.2:8765'
        : 'http://127.0.0.1:8765';
  }

  Uri rest(String path) => Uri.parse(join(baseUrl, path));

  /// 서버가 준 경로(`/hls/<id>/master.m3u8`)를 절대 http URL 로. 이미 절대 URL 이면 그대로.
  String resolve(String pathOrUrl) =>
      pathOrUrl.startsWith('http://') || pathOrUrl.startsWith('https://')
          ? pathOrUrl
          : join(baseUrl, pathOrUrl);

  /// 서버가 `/ws/sessions/<id>` 같은 경로를 주면 base 주소에 붙여 ws:// 로 바꾼다.
  Uri ws(String pathOrUrl) {
    final raw = pathOrUrl.startsWith('ws')
        ? pathOrUrl
        : join(baseUrl, pathOrUrl).replaceFirst(RegExp('^http'), 'ws');
    return Uri.parse(raw);
  }

  static String join(String base, String path) {
    final b = base.endsWith('/') ? base.substring(0, base.length - 1) : base;
    final p = path.startsWith('/') ? path : '/$path';
    return '$b$p';
  }

  ServerConfig copyWith({String? baseUrl}) =>
      ServerConfig(baseUrl: baseUrl ?? this.baseUrl);
}

class ServerConfigNotifier extends Notifier<ServerConfig> {
  @override
  ServerConfig build() => ServerConfig(baseUrl: ServerConfig.defaultBaseUrl());

  void setBaseUrl(String url) {
    final trimmed = url.trim();
    if (trimmed.isEmpty) return;
    state = state.copyWith(baseUrl: trimmed);
  }
}

final serverConfigProvider =
    NotifierProvider<ServerConfigNotifier, ServerConfig>(
  ServerConfigNotifier.new,
);
