import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 서버 주소 설정. Android 에뮬레이터에서는 호스트 PC가 10.0.2.2, 웹·데스크톱은 127.0.0.1.
class ServerConfig {
  const ServerConfig({required this.baseUrl});

  final String baseUrl;

  static String defaultBaseUrl() =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android
          ? 'http://10.0.2.2:8765'
          : 'http://127.0.0.1:8765';

  Uri rest(String path) => Uri.parse(join(baseUrl, path));

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
