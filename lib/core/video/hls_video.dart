import 'package:flutter/widgets.dart';

import 'hls_video_stub.dart' if (dart.library.js_interop) 'hls_video_web.dart'
    as impl;

/// 플레이어 상태 (API 계약 Q-API-14 — 웹은 hls.js, 그 외 플랫폼은 아직 미지원).
enum HlsVideoStatus {
  /// 매니페스트 받는 중.
  loading,

  /// 매니페스트 파싱 끝, 첫 프레임 대기.
  ready,
  playing,

  /// 데이터가 모자라 멈춤 (라이브 엣지 뒤처짐 등).
  buffering,
  paused,
  error,

  /// 이 플랫폼(또는 브라우저)에서 재생 불가.
  unsupported,
}

class HlsVideoState {
  const HlsVideoState({
    required this.status,
    this.detail,
    this.latencyS,
    this.subtitleTracks = 0,
  });

  final HlsVideoStatus status;

  /// 오류 코드·브라우저 메시지 등 사람이 읽을 보조 문구.
  final String? detail;

  /// hls.js 가 계산한 라이브 엣지 대비 지연(초). VOD 면 null.
  final double? latencyS;

  /// 매니페스트의 WebVTT 자막 트랙 수 (명세 §4.6 은 2개: 번역·원문).
  final int subtitleTracks;

  @override
  String toString() =>
      'HlsVideoState($status${detail == null ? '' : ', $detail'}'
      '${latencyS == null ? '' : ', latency ${latencyS!.toStringAsFixed(1)} s'}'
      ', subs $subtitleTracks)';
}

/// HLS(`master.m3u8`) 영상 뷰. 모드 A 서버 출력(명세 §4.6)을 재생한다.
///
/// - 웹: `<video>` + hls.js (`web/index.html` 에서 로드). Chrome 은 HLS 를 네이티브로 못 틀기 때문.
/// - 그 외 플랫폼: 자리 표시만 (추후 `media_kit`).
///
/// 자막은 기본적으로 **앱이 WebSocket 이벤트로 직접 그린다**. [nativeSubtitles] 를 켜면
/// 플레이어가 HLS 의 WebVTT 트랙을 자체 렌더링한다 (서버 자막 트랙 검증용).
class HlsVideoView extends StatelessWidget {
  const HlsVideoView({
    super.key,
    required this.url,
    this.playing = true,
    this.muted = false,
    this.volume = 1.0,
    this.nativeSubtitles = false,
    this.onState,
  });

  final String url;
  final bool playing;
  final bool muted;

  /// 0~1. 서버가 믹스한 출력 전체의 음량 (원음·TTS 개별 음량은 `config.update` 로 서버에).
  final double volume;
  final bool nativeSubtitles;
  final ValueChanged<HlsVideoState>? onState;

  @override
  Widget build(BuildContext context) => impl.HlsVideoImpl(
        url: url,
        playing: playing,
        muted: muted,
        volume: volume,
        nativeSubtitles: nativeSubtitles,
        onState: onState,
      );
}
