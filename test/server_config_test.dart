import 'package:flutter_test/flutter_test.dart';
import 'package:livetrans_app/core/config/server_config.dart';

void main() {
  const cfg = ServerConfig(baseUrl: 'http://127.0.0.1:8766');

  test('resolve 는 서버가 준 상대 경로를 base 에 붙인다', () {
    expect(cfg.resolve('/hls/abc/master.m3u8'), 'http://127.0.0.1:8766/hls/abc/master.m3u8');
    expect(cfg.resolve('hls/abc/master.m3u8'), 'http://127.0.0.1:8766/hls/abc/master.m3u8');
  });

  test('resolve 는 절대 URL 은 그대로 둔다', () {
    expect(cfg.resolve('https://cdn.example/x.m3u8'), 'https://cdn.example/x.m3u8');
  });

  test('ws 는 http base 를 ws 로 바꾼다', () {
    expect(cfg.ws('/ws/sessions/1').toString(), 'ws://127.0.0.1:8766/ws/sessions/1');
  });
}
