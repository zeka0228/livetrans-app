import 'package:flutter/material.dart';

import '../core/video/hls_video.dart';

/// 개발용 HLS 플레이어 점검 화면. 서버 모드 A 출력이나 ffmpeg 로 만든 테스트 스트림을 바로 틀어 본다.
///
/// 실행: `flutter run -d web-server --dart-define=LIVETRANS_DEMO=hls --dart-define=HLS_URL=http://127.0.0.1:8790/master.m3u8`
class HlsDemoApp extends StatefulWidget {
  const HlsDemoApp({super.key, required this.url});

  final String url;

  @override
  State<HlsDemoApp> createState() => _HlsDemoAppState();
}

class _HlsDemoAppState extends State<HlsDemoApp> {
  HlsVideoState? _state;
  bool _muted = false;
  bool _playing = true;
  bool _nativeSubs = true;
  double _volume = 1.0;
  final _log = <String>[];

  void _onState(HlsVideoState s) {
    setState(() {
      _state = s;
      _log.insert(0, '${DateTime.now().toIso8601String().substring(11, 19)} $s');
      if (_log.length > 30) _log.removeLast();
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = _state;
    return MaterialApp(
      title: 'HLS 데모',
      theme: ThemeData(colorSchemeSeed: Colors.blue, useMaterial3: true),
      home: Scaffold(
        appBar: AppBar(title: const Text('HLS 플레이어 점검 (개발용)')),
        body: Column(
          children: [
            AspectRatio(
              aspectRatio: 16 / 9,
              child: HlsVideoView(
                url: widget.url,
                playing: _playing,
                muted: _muted,
                volume: _volume,
                nativeSubtitles: _nativeSubs,
                onState: _onState,
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('URL: ${widget.url}', style: const TextStyle(fontSize: 12)),
                  const SizedBox(height: 4),
                  Text(
                    s == null ? '상태: (대기)' : '상태: ${s.status.name}'
                        '${s.detail == null ? '' : ' — ${s.detail}'}'
                        '${s.latencyS == null ? '' : ' · 지연 ${s.latencyS!.toStringAsFixed(1)} s'}'
                        ' · 자막 트랙 ${s.subtitleTracks}',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  Wrap(
                    spacing: 8,
                    children: [
                      FilledButton.tonal(
                        onPressed: () => setState(() => _playing = !_playing),
                        child: Text(_playing ? '일시정지' : '재생'),
                      ),
                      FilledButton.tonal(
                        onPressed: () => setState(() => _muted = !_muted),
                        child: Text(_muted ? '소리 켜기' : '소리 끄기'),
                      ),
                      FilledButton.tonal(
                        onPressed: () => setState(() => _nativeSubs = !_nativeSubs),
                        child: Text(_nativeSubs ? '플레이어 자막 끄기' : '플레이어 자막 켜기'),
                      ),
                    ],
                  ),
                  Slider(
                    value: _volume,
                    onChanged: (v) => setState(() => _volume = v),
                    label: '음량',
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                children: [
                  for (final line in _log)
                    Text(line, style: const TextStyle(fontSize: 11, fontFamily: 'monospace')),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
