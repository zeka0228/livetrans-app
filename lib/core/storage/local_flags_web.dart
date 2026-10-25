import 'package:web/web.dart' as web;

const _prefix = 'livetrans.flag.';

bool read(String key) {
  try {
    return web.window.localStorage.getItem('$_prefix$key') == '1';
  } catch (_) {
    return false;
  }
}

void write(String key, bool value) {
  try {
    if (value) {
      web.window.localStorage.setItem('$_prefix$key', '1');
    } else {
      web.window.localStorage.removeItem('$_prefix$key');
    }
  } catch (_) {
    // 저장소를 못 쓰는 환경(시크릿 창 등)이면 그냥 넘어간다.
  }
}

void clear() {
  try {
    final keys = <String>[];
    for (var i = 0; i < web.window.localStorage.length; i++) {
      final k = web.window.localStorage.key(i);
      if (k != null && k.startsWith(_prefix)) keys.add(k);
    }
    for (final k in keys) {
      web.window.localStorage.removeItem(k);
    }
  } catch (_) {}
}
