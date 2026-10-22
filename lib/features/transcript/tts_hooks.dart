import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/tts/tts_player.dart';
import 'transcript_entry.dart';

/// 화면별 TTS 연결 도우미: 항목 키 생성, 재생/준비 중인 seg_id 계산, 오류 스낵바.
class TranscriptTts {
  TranscriptTts(this.ref, this.scope);

  final WidgetRef ref;

  /// 화면 식별자 (`mic`, `broadcast`). 두 화면의 seg_id 가 겹쳐도 구분된다.
  final String scope;

  String keyOf(TranscriptEntry e) => '$scope:${e.segId}';

  int? _segIdOf(String? key) {
    if (key == null || !key.startsWith('$scope:')) return null;
    return int.tryParse(key.substring(scope.length + 1));
  }

  /// 이 화면에서 지금 재생 중인 항목의 seg_id.
  int? speakingSegId(TtsState s) => _segIdOf(s.speakingKey);

  /// 이 화면에서 서버 합성을 기다리는 항목의 seg_id.
  int? loadingSegId(TtsState s) => _segIdOf(s.loadingKey);

  void toggle(TranscriptEntry e) {
    ref.read(ttsControllerProvider.notifier).toggle(
          key: keyOf(e),
          text: e.text,
          lang: e.lang,
        );
  }

  /// build() 안에서 호출: TTS 오류를 스낵바로 띄운다.
  void listenErrors(BuildContext context) {
    ref.listen<TtsState>(ttsControllerProvider, (prev, next) {
      if (next.error != null && next.errorSeq != (prev?.errorSeq ?? 0)) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(next.error!)));
      }
    });
  }
}
