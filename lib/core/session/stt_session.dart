import 'dart:async';
import 'dart:typed_data';

import '../api/rest_client.dart';
import '../api/ws_client.dart';
import '../config/server_config.dart';
import '../models/events.dart';
import '../models/session.dart';

/// 세션 하나의 수명: REST 생성 → WS 연결 → `control start` → 이벤트 수신 → `control stop` →
/// `session.state=stopped` 까지 드레인 → close (API 계약 §1.2, S-1).
///
/// 마이크 모드와 방송 모드가 같이 쓴다. 오디오 전송은 선택(모드 B 는 보내지 않음).
class SttSessionClient {
  SttSessionClient({
    required this.rest,
    required this.config,
    this.stopTimeout = const Duration(seconds: 10),
  });

  final RestClient rest;
  final ServerConfig config;

  /// stop 후 `stopped` 를 기다리는 최대 시간. 지나면 그냥 닫는다 (S-1 권고 10 s).
  final Duration stopTimeout;

  WsClient? _ws;
  StreamSubscription<ServerEvent>? _sub;
  final StreamController<ServerEvent> _events =
      StreamController<ServerEvent>.broadcast();
  final Completer<void> _closed = Completer<void>();
  final Completer<void> _stopped = Completer<void>();
  SessionInfo? _info;
  bool _stopping = false;

  /// 서버 이벤트. WS 가 닫히면 스트림도 닫힌다.
  Stream<ServerEvent> get events => _events.stream;

  /// WS 가 어느 쪽에서든 닫히면 완료.
  Future<void> get closed => _closed.future;

  /// 앱이 stop 을 보낸 뒤라면 true — 이후의 서버 측 close 는 정상이다.
  bool get isStopping => _stopping;

  SessionInfo? get info => _info;

  Future<SessionInfo> open(SessionRequest request) async {
    final info = await rest.createSession(request);
    final ws = WsClient(config.ws(info.wsUrl));
    await ws.connect();
    _ws = ws;
    _info = info;
    _sub = ws.events.listen(
      _onEvent,
      onError: (Object e, StackTrace st) {
        if (!_events.isClosed) _events.addError(e, st);
      },
      onDone: () => unawaited(_finish()),
    );
    ws.sendText(ClientMessage.control('start'));
    return info;
  }

  void sendAudio(Uint8List bytes) => _ws?.sendBinary(bytes);

  /// `config.update` 같은 텍스트 메시지 (§6.2). 연결이 없으면 조용히 무시한다.
  void sendText(String text) => _ws?.sendText(text);

  /// `control stop` 을 보내고 서버가 남은 발화를 끝내 `stopped` 를 줄 때까지 기다린 뒤 닫는다.
  Future<void> stop() async {
    final ws = _ws;
    if (ws == null) return;
    _stopping = true;
    ws.sendText(ClientMessage.control('stop'));
    await Future.any([_stopped.future, _closed.future])
        .timeout(stopTimeout, onTimeout: () {});
    await _finish();
  }

  /// 기다리지 않고 바로 닫는다 (오류·치명적 error 이벤트).
  Future<void> abort() => _finish();

  void _onEvent(ServerEvent e) {
    if (e.payload case SessionStatePayload(state: 'stopped')) {
      if (!_stopped.isCompleted) _stopped.complete();
    }
    if (!_events.isClosed) _events.add(e);
  }

  Future<void> _finish() async {
    final ws = _ws;
    _ws = null;
    final sub = _sub;
    _sub = null;
    await sub?.cancel();
    await ws?.close();
    if (!_closed.isCompleted) _closed.complete();
    if (!_events.isClosed) await _events.close();
  }
}
