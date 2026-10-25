/// 웹이 아닌 플랫폼: 메모리에만 둔다.
final Map<String, bool> _memory = {};

bool read(String key) => _memory[key] ?? false;

void write(String key, bool value) => _memory[key] = value;

void clear() => _memory.clear();
