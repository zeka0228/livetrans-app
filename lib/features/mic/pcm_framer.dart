import 'dart:math' as math;
import 'dart:typed_data';

/// 녹음기가 주는 임의 길이 PCM16 청크를 고정 길이 프레임(기본 20 ms = 640 bytes)으로 재분할한다.
class PcmFramer {
  PcmFramer({this.frameBytes = 640});

  final int frameBytes;
  final BytesBuilder _pending = BytesBuilder(copy: false);

  int get pendingBytes => _pending.length;

  List<Uint8List> push(Uint8List chunk) {
    _pending.add(chunk);
    if (_pending.length < frameBytes) return const [];
    final all = _pending.takeBytes();
    final frames = <Uint8List>[];
    var offset = 0;
    while (all.length - offset >= frameBytes) {
      frames.add(Uint8List.sublistView(all, offset, offset + frameBytes));
      offset += frameBytes;
    }
    if (offset < all.length) {
      _pending.add(Uint8List.sublistView(all, offset));
    }
    return frames;
  }

  Uint8List? flush() {
    if (_pending.isEmpty) return null;
    return _pending.takeBytes();
  }
}

/// PCM16 little-endian 청크의 RMS를 0~1로 반환한다 (녹음 버튼 반응용).
double pcm16Rms(Uint8List bytes) {
  final sampleCount = bytes.lengthInBytes ~/ 2;
  if (sampleCount == 0) return 0;
  final data = ByteData.sublistView(bytes);
  var sum = 0.0;
  for (var i = 0; i < sampleCount; i++) {
    final s = data.getInt16(i * 2, Endian.little) / 32768.0;
    sum += s * s;
  }
  return math.sqrt(sum / sampleCount).clamp(0.0, 1.0);
}
