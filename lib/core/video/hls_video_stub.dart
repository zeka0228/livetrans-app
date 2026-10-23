import 'package:flutter/material.dart';

import 'hls_video.dart';

/// 웹이 아닌 플랫폼: 아직 플레이어가 없다 (명세 §8.3 `media_kit` 은 추후).
class HlsVideoImpl extends StatefulWidget {
  const HlsVideoImpl({
    super.key,
    required this.url,
    required this.playing,
    required this.muted,
    required this.volume,
    required this.nativeSubtitles,
    this.onState,
  });

  final String url;
  final bool playing;
  final bool muted;
  final double volume;
  final bool nativeSubtitles;
  final ValueChanged<HlsVideoState>? onState;

  @override
  State<HlsVideoImpl> createState() => _HlsVideoImplState();
}

class _HlsVideoImplState extends State<HlsVideoImpl> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.onState?.call(
        const HlsVideoState(
          status: HlsVideoStatus.unsupported,
          detail: '이 플랫폼에서는 아직 영상 재생을 지원하지 않습니다 (웹에서 실행하세요)',
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) => const ColoredBox(
        color: Color(0xFF000000),
        child: Center(
          child: Text(
            '영상 재생은 웹(Chrome)에서만 지원합니다',
            style: TextStyle(color: Color(0xB3FFFFFF), fontSize: 12),
          ),
        ),
      );
}
