import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';

import 'tts_store.dart';

class _MemoryTtsStore implements TtsStore {
  final _bytes = <String, Uint8List>{};

  @override
  Future<Source?> cached(String name) async {
    final b = _bytes[name];
    return b == null ? null : BytesSource(b, mimeType: 'audio/wav');
  }

  @override
  Future<Source> put(String name, List<int> bytes) async {
    final b = Uint8List.fromList(bytes);
    _bytes[name] = b;
    return BytesSource(b, mimeType: 'audio/wav');
  }
}

TtsStore createTtsStore() => _MemoryTtsStore();
