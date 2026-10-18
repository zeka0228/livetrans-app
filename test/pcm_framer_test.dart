import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:livetrans_app/features/mic/pcm_framer.dart';

void main() {
  group('PcmFramer', () {
    test('임의 길이 청크를 640바이트 프레임으로 재분할한다', () {
      final framer = PcmFramer();
      final first = framer.push(Uint8List(1000));
      expect(first.length, 1);
      expect(first.single.length, 640);
      expect(framer.pendingBytes, 360);

      final second = framer.push(Uint8List(300));
      expect(second.length, 1);
      expect(framer.pendingBytes, 20);

      final third = framer.push(Uint8List(100));
      expect(third, isEmpty);
      expect(framer.pendingBytes, 120);

      expect(framer.flush()!.length, 120);
      expect(framer.pendingBytes, 0);
      expect(framer.flush(), isNull);
    });

    test('바이트 순서를 보존한다', () {
      final framer = PcmFramer(frameBytes: 4);
      final frames = framer.push(Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8, 9]));
      expect(frames.map((f) => f.toList()), [
        [1, 2, 3, 4],
        [5, 6, 7, 8],
      ]);
      expect(framer.flush()!.toList(), [9]);
    });
  });

  group('pcm16Rms', () {
    test('무음은 0', () {
      expect(pcm16Rms(Uint8List(640)), 0);
    });

    test('최대 진폭 구형파는 약 1', () {
      final data = ByteData(640);
      for (var i = 0; i < 320; i++) {
        data.setInt16(i * 2, i.isEven ? 32767 : -32768, Endian.little);
      }
      expect(pcm16Rms(data.buffer.asUint8List()), closeTo(1.0, 0.001));
    });
  });
}
