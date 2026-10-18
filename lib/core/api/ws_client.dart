import 'dart:async';
import 'dart:typed_data';

import 'package:web_socket_channel/web_socket_channel.dart';

import '../models/events.dart';

/// 세션 WebSocket. 텍스트 메시지는 [ServerEvent]로 파싱하고, 바이너리는 PCM 프레임 전송에 쓴다.
class WsClient {
  WsClient(this.uri);

  final Uri uri;
  WebSocketChannel? _channel;

  bool get isConnected => _channel != null;

  Future<void> connect() async {
    final channel = WebSocketChannel.connect(uri);
    await channel.ready;
    _channel = channel;
  }

  Stream<ServerEvent> get events {
    final channel = _channel;
    if (channel == null) {
      throw StateError('connect()를 먼저 호출해야 한다');
    }
    return channel.stream
        .where((m) => m is String)
        .map((m) => ServerEvent.parse(m as String));
  }

  void sendText(String text) => _channel?.sink.add(text);

  void sendBinary(Uint8List bytes) => _channel?.sink.add(bytes);

  Future<void> close() async {
    final channel = _channel;
    _channel = null;
    await channel?.sink.close();
  }
}
