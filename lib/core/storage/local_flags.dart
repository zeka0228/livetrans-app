import 'local_flags_stub.dart' if (dart.library.js_interop) 'local_flags_web.dart' as impl;

/// 기기에 남는 작은 불리언 플래그 ("안내를 이미 봤다" 같은 것).
///
/// - 웹: `localStorage` (앱 출처별로 따로, 같은 Chrome 프로필이면 다시 띄워도 유지).
/// - 그 외 플랫폼: 아직 저장소가 없어 **프로세스 메모리**에만 둔다 (앱을 다시 켜면 초기화).
///
/// 값이 없거나 저장소를 못 쓰면(시크릿 창 등) `false` 로 보고, 쓰기 실패는 조용히 무시한다.
abstract final class LocalFlags {
  static bool get(String key) => impl.read(key);

  static void set(String key, bool value) => impl.write(key, value);

  /// 테스트용: 전부 비운다.
  static void clear() => impl.clear();
}
