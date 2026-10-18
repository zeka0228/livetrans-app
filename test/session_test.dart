import 'package:flutter_test/flutter_test.dart';
import 'package:livetrans_app/core/config/server_config.dart';
import 'package:livetrans_app/core/models/session.dart';

void main() {
  test('마이크 세션 요청은 명세 §6.1 형태의 JSON을 만든다', () {
    final json = SessionRequest.mic(srcLang: 'ja').toJson();
    expect(json['mode'], 'C');
    expect(json['source'], {'type': 'mic_ws', 'params': {}});
    expect(json['src_lang'], 'ja');
    expect(json['tgt_lang'], 'ko');
    expect(json['delay_s'], isNull);
    expect(json['tts'], {'enabled': false, 'voice_ref': null, 'duck_db': -12});
    expect(json['display'], {'show_original': true});
  });

  test('SessionInfo는 ws_url이 없으면 경로를 만들어 낸다', () {
    final info = SessionInfo.fromJson({'session_id': 'abc', 'delay_s': 20});
    expect(info.wsUrl, '/ws/sessions/abc');
    expect(info.delayS, 20);
  });

  test('ServerConfig.ws는 http 주소를 ws로 바꾸고 경로를 붙인다', () {
    const cfg = ServerConfig(baseUrl: 'http://10.0.2.2:8765/');
    expect(cfg.ws('/ws/sessions/x').toString(), 'ws://10.0.2.2:8765/ws/sessions/x');
    expect(cfg.ws('ws://host:1/a').toString(), 'ws://host:1/a');
    expect(cfg.rest('api/health').toString(), 'http://10.0.2.2:8765/api/health');
  });
}
