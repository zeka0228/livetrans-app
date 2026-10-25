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
  external void startLoad();
  external void recoverMediaError();
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

  /// 치명적 네트워크 오류(매니페스트 404 등) 자동 재시도 횟수. 서버는 `playing` 을 플레이리스트
  /// 생성 뒤에 보내지만(S-21 ②) 프록시·타이밍 차이로 첫 요청이 실패할 수 있어 몇 번은 조용히 다시 연다.
  int _networkRetries = 0;
  static const _maxNetworkRetries = 3;
  static const _networkRetryDelay = Duration(seconds: 2);
  Timer? _retryTimer;

  @override
  void initState() {
    super.initState();
    _viewType = 'livetrans-hls-${_nextViewId++}';
    // autoplay 는 끈다 — 재생 시점은 [widget.playing] 이 정한다 (모드 A 는 buffering 동안 멈춰 있어야 함).
    _video = web.document.createElement('video') as web.HTMLVideoElement
      ..autoplay = false
      ..playsInline = true
      ..controls = false
      ..muted = widget.muted
      ..volume = widget.volume;
    _video.style
      ..width = '100%'
      ..height = '100%'
      ..objectFit = 'contain'
      ..backgroundColor = '#000'
      // 플랫폼 뷰(DOM)가 클릭을 삼키면 그 위의 Flutter 탭(컨트롤 다시 보이기)·키보드 포커스가 끊긴다.
      // 자체 컨트롤을 안 쓰므로 포인터는 전부 Flutter 로 넘긴다.
      ..pointerEvents = 'none';
    ui_web.platformViewRegistry.registerViewFactory(
      _viewType,
      (int viewId) => _video,
    );
    _video.addEventListener('playing', _onPlaying.toJS);
    _video.addEventListener('waiting', _onWaiting.toJS);
    _video.addEventListener('pause', _onPause.toJS);
    _video.addEventListener('ended', _onEnded.toJS);
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

  void _onEnded(web.Event _) => _emit(HlsVideoStatus.ended);

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
    _networkRetries = 0;
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
    final hls = _hls;
    if (hls != null && type == 'networkError' && _networkRetries < _maxNetworkRetries) {
      _networkRetries++;
      _emit(
        HlsVideoStatus.loading,
        detail: '다시 연결 중 ($_networkRetries/$_maxNetworkRetries) · $details',
      );
      _retryTimer?.cancel();
      _retryTimer = Timer(_networkRetryDelay, () {
        if (mounted && _hls == hls) hls.startLoad();
      });
      return;
    }
    if (hls != null && type == 'mediaError' && _networkRetries < _maxNetworkRetries) {
      // 디코더 오류는 hls.js 가 권하는 recoverMediaError 로 한 번 더.
      _networkRetries++;
      _emit(HlsVideoStatus.buffering, detail: '디코더 복구 중 · $details');
      hls.recoverMediaError();
      return;
    }
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
      _retryTimer?.cancel();
      _hls?.destroy();
      _hls = null;
      _networkRetries = 0;
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
    _retryTimer?.cancel();
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
