import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:path_provider/path_provider.dart';

import 'tts_store.dart';

class _FileTtsStore implements TtsStore {
  Future<File> _file(String name) async {
    final dir = await getTemporaryDirectory();
    return File('${dir.path}${Platform.pathSeparator}$name');
  }

  @override
  Future<Source?> cached(String name) async {
    final file = await _file(name);
    if (await file.exists() && await file.length() > 44) {
      return DeviceFileSource(file.path);
    }
    return null;
  }

  @override
  Future<Source> put(String name, List<int> bytes) async {
    final file = await _file(name);
    await file.writeAsBytes(bytes, flush: true);
    return DeviceFileSource(file.path);
  }
}

TtsStore createTtsStore() => _FileTtsStore();
