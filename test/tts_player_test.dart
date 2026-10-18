import 'package:flutter_test/flutter_test.dart';
import 'package:livetrans_app/core/api/rest_client.dart';
import 'package:livetrans_app/core/config/server_config.dart';
import 'package:livetrans_app/core/tts/tts_player.dart';

void main() {
  test('TTS 요청 URL 은 text·lang 을 쿼리로 인코딩한다 (S-13 ②)', () {
    final client = RestClient(const ServerConfig(baseUrl: 'http://10.0.2.2:8765'));
    final uri = client.ttsUri(text: '안녕하세요, 테스트 & 검증', lang: 'ko');
    expect(uri.scheme, 'http');
    expect(uri.path, '/api/tts');
    expect(uri.queryParameters['text'], '안녕하세요, 테스트 & 검증');
    expect(uri.queryParameters['lang'], 'ko');
    expect(uri.toString(), contains('text=%EC%95%88'));
  });

  test('캐시 파일 이름은 같은 문장·언어에 같고 언어가 다르면 다르다', () {
    expect(ttsCacheName('hello', 'en'), ttsCacheName('hello', 'en'));
    expect(ttsCacheName('hello', 'en'), isNot(ttsCacheName('hello', 'ko')));
    expect(ttsCacheName('a b/c?', 'ja'), matches(RegExp(r'^tts_ja_[0-9a-f]+\.wav$')));
  });

  test('TtsState 키 판정', () {
    const s = TtsState(speakingKey: 'mic:3');
    expect(s.isSpeaking('mic:3'), isTrue);
    expect(s.isSpeaking('broadcast:3'), isFalse);
    expect(s.activeKey, 'mic:3');
    expect(const TtsState(loadingKey: 'mic:4').activeKey, 'mic:4');
    expect(const TtsState().activeKey, isNull);
  });
}
