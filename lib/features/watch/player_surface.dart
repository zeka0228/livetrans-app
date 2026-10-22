import 'package:flutter/material.dart';

/// 영상 영역. 지금은 **자리만** — 서버가 HLS(모드 A)를 주기 시작하면 이 위젯 안을
/// `media_kit` 플레이어로 바꾼다 (명세 §8.3). 바깥(자막·상태·컨트롤)은 그대로 둔다.
///
/// [audioOnly] 면 "소리만" 모드라 영상 없이 파형 느낌의 배경만 보여준다.
class PlayerSurface extends StatelessWidget {
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
                    audioOnly
                        ? Icons.graphic_eq_rounded
                        : Icons.ondemand_video_rounded,
                    size: 48,
                    color: Colors.white.withValues(alpha: playing ? 0.9 : 0.45),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    audioOnly
                        ? (playing
                              ? '소리만 모드 · 자막·번역 음성 재생 중'
                              : '소리만 모드 (영상 없음)')
                        : (hlsUrl == null ? '영상 스트림 대기 중' : '영상 플레이어 자리 (HLS)'),
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.75),
                      fontSize: 12,
                    ),
                  ),
                  if (!audioOnly && hlsUrl != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        hlsUrl!,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.4),
                          fontSize: 10,
                        ),
                        overflow: TextOverflow.ellipsis,
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
