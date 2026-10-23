import 'package:audioplayers/audioplayers.dart';

import 'tts_store_io.dart' if (dart.library.js_interop) 'tts_store_web.dart' as impl;

/// 서버에서 받은 WAV 를 보관하고 `audioplayers` Source 로 돌려준다.
/// - 모바일·데스크톱: 임시 폴더 파일 (앱을 다시 켜도 캐시 유지)
/// - 웹: 메모리 (dart:io 없음)
abstract class TtsStore {
  Future<Source?> cached(String name);
  Future<Source> put(String name, List<int> bytes);
}

TtsStore createTtsStore() => impl.createTtsStore();
