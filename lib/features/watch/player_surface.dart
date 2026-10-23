import 'package:flutter/material.dart';

import '../../core/video/hls_video.dart';

/// 영상 영역. 서버가 `hls_url` 을 주면(모드 A, `obs_stream` 소스) [HlsVideoView] 로 재생하고,
/// 소리만 모드이거나 아직 URL 이 없으면 배경만 그린다. 바깥(자막·상태·컨트롤)은 상위 화면 담당.
///
/// [hlsUrl] 은 **절대 URL** 이어야 한다 (서버는 `/hls/<id>/master.m3u8` 처럼 상대 경로를 주므로
/// 상위에서 `ServerConfig.resolve` 로 바꿔 넘긴다).
class PlayerSurface extends StatefulWidget {
  const PlayerSurface({
    super.key,
    required this.hlsUrl,
    required this.audioOnly,
    required this.playing,
    required this.muted,
    required this.volume,
  });

  final String? hlsUrl;
  final bool audioOnly;
  final bool playing;
  final bool muted;
  final double volume;

  @override
  State<PlayerSurface> createState() => _PlayerSurfaceState();
}

class _PlayerSurfaceState extends State<PlayerSurface> {
  HlsVideoState? _video;

  bool get _hasVideo => !widget.audioOnly && widget.hlsUrl != null;

  @override
  void didUpdateWidget(PlayerSurface old) {
    super.didUpdateWidget(old);
    if (old.hlsUrl != widget.hlsUrl || old.audioOnly != widget.audioOnly) _video = null;
  }

  @override
  Widget build(BuildContext context) {
    if (_hasVideo) {
      return Stack(
        fit: StackFit.expand,
        children: [
          HlsVideoView(
            url: widget.hlsUrl!,
            playing: widget.playing,
            muted: widget.muted,
            volume: widget.volume,
            onState: (s) => setState(() => _video = s),
          ),
          // 재생 중이 아닐 때(버퍼링·오류·미지원)만 작은 상태 칩. 재생 중엔 영상만.
          if (_video != null && _video!.status != HlsVideoStatus.playing)
            Positioned(
              left: 12,
              top: 12,
              child: _VideoStatusChip(state: _video!),
            ),
        ],
      );
    }
    return _AudioOnlyBackdrop(
      playing: widget.playing,
      muted: widget.muted,
      waitingForUrl: !widget.audioOnly && widget.hlsUrl == null,
    );
  }
}

class _VideoStatusChip extends StatelessWidget {
  const _VideoStatusChip({required this.state});

  final HlsVideoState state;

  @override
  Widget build(BuildContext context) {
    final (label, icon, color) = switch (state.status) {
      HlsVideoStatus.loading => ('영상 불러오는 중…', Icons.downloading_rounded, Colors.white70),
      HlsVideoStatus.ready => ('영상 준비됨', Icons.check_circle_outline_rounded, Colors.white70),
      HlsVideoStatus.buffering => ('영상 버퍼링…', Icons.hourglass_top_rounded, Colors.white70),
      HlsVideoStatus.paused => ('영상 일시정지', Icons.pause_circle_outline_rounded, Colors.white70),
      HlsVideoStatus.error => ('영상 오류', Icons.error_outline_rounded, Colors.redAccent),
      HlsVideoStatus.unsupported => ('이 플랫폼은 영상 미지원', Icons.videocam_off_outlined, Colors.orangeAccent),
      HlsVideoStatus.playing => ('재생 중', Icons.play_arrow_rounded, Colors.white70),
    };
    return Container(
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
          Text(
            state.detail == null ? label : '$label · ${state.detail}',
            style: TextStyle(color: color, fontSize: 11),
            overflow: TextOverflow.ellipsis,
          ),
        ],
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
