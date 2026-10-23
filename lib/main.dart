import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'dev/hls_demo.dart';

/// 개발용 진입점 전환. `--dart-define=LIVETRANS_DEMO=hls` 면 HLS 플레이어 점검 화면만 띄운다.
const _demo = String.fromEnvironment('LIVETRANS_DEMO');
const _demoHlsUrl = String.fromEnvironment(
  'HLS_URL',
  defaultValue: 'http://127.0.0.1:8790/master.m3u8',
);

void main() {
  if (_demo == 'hls') {
    runApp(const HlsDemoApp(url: _demoHlsUrl));
    return;
  }
  runApp(const ProviderScope(child: LiveTransApp()));
}
