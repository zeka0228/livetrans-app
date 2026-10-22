import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../api/rest_client.dart';

/// `GET /api/tts` 요청 키. 같은 문장·언어는 같은 파일로 캐시된다.
String ttsCacheName(String text, String lang) =>
    'tts_${lang}_${text.hashCode.toUnsigned(32).toRadixString(16)}.wav';

class TtsState {
  const TtsState({
    this.speakingKey,
    this.loadingKey,
    this.error,
    this.errorSeq = 0,
  });

  /// 지금 재생 중인 항목의 키 (`<화면>:<seg_id>`).
  final String? speakingKey;

  /// 서버에 합성을 요청해 기다리는 중인 항목의 키.
  final String? loadingKey;
  final String? error;

  /// 같은 문구의 오류가 연달아 나도 스낵바가 다시 뜨도록 하는 카운터.
  final int errorSeq;

  bool isSpeaking(String key) => speakingKey == key;
  bool isLoading(String key) => loadingKey == key;

  /// 재생 중이거나 준비 중인 항목의 키.
  String? get activeKey => speakingKey ?? loadingKey;
}

/// 서버 TTS(`GET /api/tts?text&lang` → WAV)를 받아 재생한다 (API 계약 S-13, D-018).
/// - 탭 = 재생, 재생 중 같은 항목 탭 = 정지, 다른 항목 탭 = 이전 정지 후 새로 재생.
/// - WAV 는 임시 폴더에 캐시해 같은 문장은 다시 받지 않는다.
class TtsController extends Notifier<TtsState> {
  AudioPlayer? _player;
  StreamSubscription<void>? _completeSub;
  int _generation = 0;

  @override
  TtsState build() {
    ref.onDispose(() {
      unawaited(_completeSub?.cancel());
      unawaited(_player?.dispose());
    });
    return const TtsState();
  }

  AudioPlayer _engine() {
    final existing = _player;
    if (existing != null) return existing;
    final player = AudioPlayer(playerId: 'livetrans-tts');
    _completeSub = player.onPlayerComplete.listen((_) {
      if (state.speakingKey != null) {
        state = TtsState(errorSeq: state.errorSeq);
      }
    });
    _player = player;
    return player;
  }

  Future<void> toggle({
    required String key,
    required String text,
    required String lang,
  }) async {
    if (state.activeKey == key) {
      await stop();
      return;
    }
    final gen = ++_generation;
    final player = _engine();
    if (state.speakingKey != null) await player.stop();
    state = TtsState(loadingKey: key, errorSeq: state.errorSeq);

    try {
      final file = await _cachedWav(text, lang);
      if (gen != _generation) return;
      state = TtsState(speakingKey: key, errorSeq: state.errorSeq);
      await player.play(DeviceFileSource(file.path));
    } catch (e) {
      if (gen != _generation) return;
      state = TtsState(error: _describe(e), errorSeq: state.errorSeq + 1);
    }
  }

  Future<void> stop() async {
    _generation++;
    await _player?.stop();
    state = TtsState(errorSeq: state.errorSeq);
  }

  Future<File> _cachedWav(String text, String lang) async {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}${Platform.pathSeparator}${ttsCacheName(text, lang)}');
    if (await file.exists() && await file.length() > 44) return file;
    final bytes = await ref.read(restClientProvider).ttsWav(text: text, lang: lang);
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }

  static String _describe(Object e) {
    if (e is ApiException) {
      return switch (e.code) {
        'E_TTS_NO_VOICE' => '이 언어의 음성이 서버에 없습니다',
        'E_TTS_TEXT' => '읽을 수 없는 문장입니다 (비어 있거나 너무 김)',
        'E_TTS_FAILED' => '서버가 음성을 만들지 못했습니다',
        _ => e.statusCode == 404
            ? '서버가 아직 음성 합성을 지원하지 않습니다'
            : '음성 요청 실패: $e',
      };
    }
    if (e is TimeoutException) return '음성 합성 응답이 늦습니다 (시간 초과)';
    return '음성 재생 실패: $e';
  }
}

final ttsControllerProvider = NotifierProvider<TtsController, TtsState>(
  TtsController.new,
);
