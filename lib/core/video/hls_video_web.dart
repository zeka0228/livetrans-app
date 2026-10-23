import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:ui_web' as ui_web;

import 'package:flutter/widgets.dart';
import 'package:web/web.dart' as web;

import 'hls_video.dart';

// ---- hls.js 바인딩 (web/index.html 이 전역 `Hls` 를 로드한다) ----

@JS('Hls')
extension type _Hls._(JSObject _) implements JSObject {
  external factory _Hls(JSObject config);
  external void loadSource(String url);
  external void attachMedia(web.HTMLVideoElement element);
  external void destroy();
  external void on(String event, JSFunction callback);
  external JSArray<JSObject> get subtitleTracks;
  external set subtitleTrack(int index);
  external set subtitleDisplay(bool value);
  external double get latency;
}

@JS('Hls.isSupported')
external bool _hlsIsSupported();

bool get _hlsLoaded => web.window.hasProperty('Hls'.toJS).toDart;

int _nextViewId = 0;

/// 웹 구현: `<video>` 한 개를 HtmlElementView 로 끼우고 hls.js 가 MSE 로 밀어 넣는다.
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
  late final String _viewType;
  late final web.HTMLVideoElement _video;
  _Hls? _hls;
  HlsVideoStatus _status = HlsVideoStatus.loading;
  int _subtitleTracks = 0;

  @override
  void initState() {
    super.initState();
    _viewType = 'livetrans-hls-${_nextViewId++}';
    _video = web.document.createElement('video') as web.HTMLVideoElement
      ..autoplay = true
      ..playsInline = true
      ..controls = false
      ..muted = widget.muted
      ..volume = widget.volume;
    _video.style
      ..width = '100%'
      ..height = '100%'
      ..objectFit = 'contain'
      ..backgroundColor = '#000';
    ui_web.platformViewRegistry.registerViewFactory(
      _viewType,
      (int viewId) => _video,
    );
    _video.addEventListener('playing', _onPlaying.toJS);
    _video.addEventListener('waiting', _onWaiting.toJS);
    _video.addEventListener('pause', _onPause.toJS);
    _load();
  }

  void _emit(HlsVideoStatus status, {String? detail}) {
    _status = status;
    final hls = _hls;
    double? latency;
    if (hls != null && status == HlsVideoStatus.playing) {
      final l = hls.latency;
      if (l.isFinite && l > 0) latency = l;
    }
    final state = HlsVideoState(
      status: status,
      detail: detail,
      latencyS: latency,
      subtitleTracks: _subtitleTracks,
    );
    // initState/didUpdateWidget 안에서도 불리므로(빌드 중) 부모의 setState 는 빌드가 끝난 뒤로 미룬다.
    scheduleMicrotask(() {
      if (mounted) widget.onState?.call(state);
    });
  }

  void _onPlaying(web.Event _) => _emit(HlsVideoStatus.playing);
  void _onWaiting(web.Event _) => _emit(HlsVideoStatus.buffering);
  void _onPause(web.Event _) {
    if (_status != HlsVideoStatus.error) _emit(HlsVideoStatus.paused);
  }

  void _load() {
    if (!_hlsLoaded) {
      _emit(
        HlsVideoStatus.unsupported,
        detail: 'hls.js 가 로드되지 않았습니다 (web/index.html 확인)',
      );
      return;
    }
    if (!_hlsIsSupported()) {
      _emit(
        HlsVideoStatus.unsupported,
        detail: '이 브라우저는 Media Source Extensions 를 지원하지 않습니다',
      );
      return;
    }
    _emit(HlsVideoStatus.loading);
    final hls = _Hls(
      {
        // 라이브 엣지에서 3 세그먼트(≈ 3 s) 뒤 = 명세 §3.3 플레이어 hold-back H.
        'liveSyncDurationCount': 3,
        'liveMaxLatencyDurationCount': 8,
        'enableWorker': true,
        'lowLatencyMode': false,
      }.jsify()! as JSObject,
    );
    _hls = hls;
    hls.on('hlsManifestParsed', _onManifestParsed.toJS);
    hls.on('hlsSubtitleTracksUpdated', _onSubtitleTracks.toJS);
    hls.on('hlsError', _onError.toJS);
    hls.subtitleDisplay = widget.nativeSubtitles;
    hls.loadSource(widget.url);
    hls.attachMedia(_video);
  }

  void _onManifestParsed(JSAny? event, JSAny? data) {
    _subtitleTracks = _hls?.subtitleTracks.length ?? 0;
    _emit(HlsVideoStatus.ready);
    if (widget.playing) _play();
  }

  void _onSubtitleTracks(JSAny? event, JSAny? data) {
    final hls = _hls;
    if (hls == null) return;
    _subtitleTracks = hls.subtitleTracks.length;
    if (widget.nativeSubtitles && _subtitleTracks > 0) hls.subtitleTrack = 0;
  }

  void _onError(JSAny? event, JSAny? data) {
    final d = data as JSObject?;
    if (d == null) return;
    final fatal = (d.getProperty<JSBoolean?>('fatal'.toJS))?.toDart ?? false;
    final type = d.getProperty<JSString?>('type'.toJS)?.toDart ?? '';
    final details = d.getProperty<JSString?>('details'.toJS)?.toDart ?? '';
    if (!fatal) return; // 비치명적(세그먼트 1개 실패 등)은 hls.js 가 스스로 복구한다.
    _emit(HlsVideoStatus.error, detail: '$type/$details');
  }

  void _play() {
    // play() 는 Promise 를 돌려주며 autoplay 정책에 막히면 reject 된다 → 소리 끔으로 재시도.
    _video.play().toDart.catchError((Object e) {
      if (!_video.muted) {
        _video.muted = true;
        return _video.play().toDart;
      }
      _emit(HlsVideoStatus.error, detail: '브라우저가 자동 재생을 막았습니다: $e');
      return null;
    });
  }

  @override
  void didUpdateWidget(HlsVideoImpl old) {
    super.didUpdateWidget(old);
    if (old.url != widget.url) {
      _hls?.destroy();
      _hls = null;
      _load();
      return;
    }
    if (old.muted != widget.muted) _video.muted = widget.muted;
    if (old.volume != widget.volume) _video.volume = widget.volume;
    if (old.nativeSubtitles != widget.nativeSubtitles) {
      _hls?.subtitleDisplay = widget.nativeSubtitles;
    }
    if (old.playing != widget.playing) {
      if (widget.playing) {
        _play();
      } else {
        _video.pause();
      }
    }
  }

  @override
  void dispose() {
    _hls?.destroy();
    _hls = null;
    _video
      ..pause()
      ..removeAttribute('src')
      ..remove();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => HtmlElementView(viewType: _viewType);
}
