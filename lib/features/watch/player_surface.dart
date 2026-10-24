import 'package:flutter/material.dart';

import '../../core/video/hls_video.dart';

/// 영상 영역. 서버가 `hls_url` 을 주면(모드 A) [HlsVideoView] 로 재생하고,
/// URL 이 없으면 배경만 그린다. 바깥(자막·상태·컨트롤)은 상위 화면 담당.
///
/// - **`playing` 이 된 뒤에만 HLS 를 연다** (API 계약 S-21 ②·④): 서버는 `playing` 을 HLS
///   플레이리스트가 생긴 뒤에 보내므로, 그 전에 매니페스트를 요청하면 404 가 치명 오류로 보인다.
///   한 번 열리면 `playing` 이 false 로 바뀌어도(종료) 닫지 않는다 — URL 이 바뀔 때만 다시 연다.
/// - 서버 HLS 는 영상이 없어도(소리만 모드) 원음 + 덕킹 TTS 를 믹스한 오디오를 담으므로
///   [expectVideo] 가 false 여도 플레이어는 띄우고, 화면에는 배경을 덮는다.
///
/// [hlsUrl] 은 **절대 URL** 이어야 한다 (서버는 `/hls/<id>/master.m3u8` 처럼 상대 경로를 주므로
/// 상위에서 `ServerConfig.resolve` 로 바꿔 넘긴다).
class PlayerSurface extends StatefulWidget {
  const PlayerSurface({
    super.key,
    required this.hlsUrl,
    required this.expectVideo,
    required this.playing,
    required this.muted,
    required this.volume,
    this.onEnded,
  });

  final String? hlsUrl;

  /// 플레이어가 플레이리스트 끝(ENDLIST)까지 다 틀었을 때. 모드 A "방송 끝 → 남은 지연분 재생" 종료 신호 (S-31).
  final VoidCallback? onEnded;

  /// 소스에 영상이 있다고 기대하는가 (`obs_stream`). false 면 오디오 전용 HLS 로 보고 배경을 덮는다.
  final bool expectVideo;
  final bool playing;
  final bool muted;
  final double volume;

  @override
  State<PlayerSurface> createState() => _PlayerSurfaceState();
}

class _PlayerSurfaceState extends State<PlayerSurface> {
  HlsVideoState? _video;

  /// `playing` 을 한 번이라도 받은 URL. 이 값과 [PlayerSurface.hlsUrl] 이 같을 때만 플레이어를 띄운다.
  String? _armedUrl;

  /// 재시도 횟수. 바뀌면 [HlsVideoView] 를 새로 만들어 처음부터 다시 연다.
  int _attempt = 0;

  @override
  void initState() {
    super.initState();
    _arm();
  }

  @override
  void didUpdateWidget(PlayerSurface old) {
    super.didUpdateWidget(old);
    if (old.hlsUrl != widget.hlsUrl) {
      _armedUrl = null;
      _video = null;
      _attempt = 0;
    }
    _arm();
  }

  void _arm() {
    if (widget.playing && widget.hlsUrl != null && _armedUrl != widget.hlsUrl) {
      _armedUrl = widget.hlsUrl;
      _video = null;
    }
  }

  bool get _streamOpen => widget.hlsUrl != null && _armedUrl == widget.hlsUrl;

  void _retry() => setState(() {
        _attempt++;
        _video = null;
      });

  @override
  Widget build(BuildContext context) {
    if (!_streamOpen) {
      return _AudioOnlyBackdrop(
        playing: widget.playing,
        muted: widget.muted,
        waitingForUrl: widget.expectVideo && widget.hlsUrl == null,
      );
    }
    final video = _video;
    final showChip = video != null && video.status != HlsVideoStatus.playing;
    return Stack(
      fit: StackFit.expand,
      children: [
        HlsVideoView(
          key: ValueKey('${widget.hlsUrl}#$_attempt'),
          url: widget.hlsUrl!,
          // 한 번 열린 스트림은 멈추지 않는다: 입력이 끝나도(E_CAPTURE_LOST·stopped) HLS 에는 D 초만큼
          // 지연된 내용이 남아 있으므로 ENDLIST 까지 재생하게 둔다 (실서버 E2E 2026-10-24 에서 마지막 4 s 가 잘렸음).
          playing: true,
          muted: widget.muted,
          volume: widget.volume,
          onState: (s) {
            setState(() => _video = s);
            if (s.status == HlsVideoStatus.ended) widget.onEnded?.call();
          },
        ),
        // 소리만 모드: 오디오는 플레이어가 내고 화면은 배경으로 덮는다.
        if (!widget.expectVideo)
          _AudioOnlyBackdrop(
            playing: widget.playing,
            muted: widget.muted,
            waitingForUrl: false,
          ),
        // 재생 중이 아닐 때(버퍼링·오류·미지원)만 작은 상태 칩. 재생 중엔 영상만.
        if (showChip)
          Positioned(
            left: 12,
            top: 12,
            child: _VideoStatusChip(
              state: video,
              onRetry: video.status == HlsVideoStatus.error ? _retry : null,
            ),
          ),
      ],
    );
  }
}

class _VideoStatusChip extends StatelessWidget {
  const _VideoStatusChip({required this.state, this.onRetry});

  final HlsVideoState state;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final (label, icon, color) = switch (state.status) {
      HlsVideoStatus.loading => ('영상 불러오는 중…', Icons.downloading_rounded, Colors.white70),
      HlsVideoStatus.ready => ('영상 준비됨', Icons.check_circle_outline_rounded, Colors.white70),
      HlsVideoStatus.buffering => ('영상 버퍼링…', Icons.hourglass_top_rounded, Colors.white70),
      HlsVideoStatus.paused => ('영상 일시정지', Icons.pause_circle_outline_rounded, Colors.white70),
      HlsVideoStatus.ended => ('재생 끝', Icons.stop_circle_outlined, Colors.white70),
      HlsVideoStatus.error => ('영상 오류', Icons.error_outline_rounded, Colors.redAccent),
      HlsVideoStatus.unsupported => ('이 플랫폼은 영상 미지원', Icons.videocam_off_outlined, Colors.orangeAccent),
      HlsVideoStatus.playing => ('재생 중', Icons.play_arrow_rounded, Colors.white70),
    };
    final chip = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 260),
            child: Text(
              state.detail == null ? label : '$label · ${state.detail}',
              style: TextStyle(color: color, fontSize: 11),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (onRetry != null) ...[
            const SizedBox(width: 8),
            Icon(Icons.refresh_rounded, size: 14, color: color),
            const SizedBox(width: 2),
            Text('다시 시도', style: TextStyle(color: color, fontSize: 11)),
          ],
        ],
      ),
    );
    if (onRetry == null) return chip;
    return Semantics(
      button: true,
      label: '영상 다시 시도',
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onRetry,
        child: chip,
      ),
    );
  }
}

/// 소리만 모드(또는 URL 대기) 배경.
class _AudioOnlyBackdrop extends StatelessWidget {
  const _AudioOnlyBackdrop({
    required this.playing,
    required this.muted,
    required this.waitingForUrl,
  });

  final bool playing;
  final bool muted;
  final bool waitingForUrl;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xFF0B1526),
            scheme.primary.withValues(alpha: 0.35),
            const Color(0xFF05070C),
          ],
        ),
      ),
      // 재생 전에는 상태 오버레이가 설명하므로 배경만. 재생 중에는 자막(아래)과 겹치지 않게 위쪽에 둔다.
      child: !playing
          ? const SizedBox.expand()
          : Align(
              alignment: const Alignment(0, -0.45),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    waitingForUrl ? Icons.ondemand_video_rounded : Icons.graphic_eq_rounded,
                    size: 48,
                    color: Colors.white.withValues(alpha: 0.9),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    waitingForUrl ? '영상 스트림 대기 중' : '소리만 모드 · 자막·번역 음성 재생 중',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.75),
                      fontSize: 12,
                    ),
                  ),
                  if (muted)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.volume_off_rounded,
                            size: 14,
                            color: Colors.white.withValues(alpha: 0.6),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '음소거',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.6),
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
    );
  }
}
