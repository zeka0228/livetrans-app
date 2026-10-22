import 'package:flutter_test/flutter_test.dart';
import 'package:livetrans_app/core/models/capture_target.dart';
import 'package:livetrans_app/core/models/session.dart';

void main() {
  test('capture targets 응답을 파싱한다 (S-9 ①)', () {
    final t = CaptureTargets.fromJson({
      'targets': [
        {'id': 'system', 'kind': 'system', 'title': 'PC 전체 소리', 'process': null, 'pid': null},
        {'id': 'pid:1234', 'kind': 'app', 'title': 'YouTube - Chrome', 'process': 'chrome.exe', 'pid': 1234},
      ],
      'app_capture_supported': false,
    });
    expect(t.appCaptureSupported, isFalse);
    expect(t.targets.first.isSystem, isTrue);
    expect(t.targets.last.pid, 1234);
    expect(t.targets.last.process, 'chrome.exe');
  });

  test('app_capture_supported 가 없으면 true 로 본다', () {
    expect(CaptureTargets.fromJson({'targets': []}).appCaptureSupported, isTrue);
  });

  test('방송 세션 요청은 mode B + loopback + target 을 보낸다 (S-9 ②)', () {
    final json = SessionRequest.broadcast(target: 'pid:1234', srcLang: 'ja').toJson();
    expect(json['mode'], 'B');
    expect(json['source'], {'type': 'loopback', 'params': {'target': 'pid:1234'}});
    expect(json['src_lang'], 'ja');
    expect(json['tgt_lang'], 'ko');
  });
}
