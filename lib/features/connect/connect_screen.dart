import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/server_config.dart';
import '../../core/models/session.dart';
import 'connect_controller.dart';

class ConnectScreen extends ConsumerStatefulWidget {
  const ConnectScreen({super.key});

  @override
  ConsumerState<ConnectScreen> createState() => _ConnectScreenState();
}

class _ConnectScreenState extends ConsumerState<ConnectScreen> {
  late final TextEditingController _url;

  static const _presets = <String, String>{
    '에뮬레이터': 'http://10.0.2.2:8765',
    'Windows': 'http://127.0.0.1:8765',
  };

  @override
  void initState() {
    super.initState();
    _url = TextEditingController(text: ref.read(serverConfigProvider).baseUrl);
  }

  @override
  void dispose() {
    _url.dispose();
    super.dispose();
  }

  Future<void> _check() async {
    FocusScope.of(context).unfocus();
    ref.read(serverConfigProvider.notifier).setBaseUrl(_url.text);
    await ref.read(connectControllerProvider.notifier).check();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(connectControllerProvider);
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('서버 연결')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        children: [
          _HeroBanner(state: state),
          const SizedBox(height: 20),
          Text(
            '서버 주소',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _url,
            keyboardType: TextInputType.url,
            decoration: const InputDecoration(
              hintText: 'http://10.0.2.2:8765',
              prefixIcon: Icon(Icons.dns_outlined),
            ),
            onSubmitted: (_) => _check(),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            children: [
              for (final e in _presets.entries)
                ActionChip(
                  avatar: Icon(
                    e.key == 'Windows'
                        ? Icons.desktop_windows_outlined
                        : Icons.phone_android_outlined,
                    size: 16,
                  ),
                  label: Text(e.key),
                  onPressed: () => setState(() => _url.text = e.value),
                ),
            ],
          ),
          const SizedBox(height: 18),
          FilledButton.icon(
            onPressed: state.checking ? null : _check,
            icon: state.checking
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.network_check_rounded),
            label: Text(state.checking ? '확인 중…' : '연결 확인'),
          ),
          const SizedBox(height: 20),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 250),
            child: switch (state) {
              ConnectState(error: final err?) => _ErrorCard(
                  key: const ValueKey('error'),
                  message: err,
                ),
              ConnectState(health: final h?) => _HealthCard(
                  key: const ValueKey('health'),
                  health: h,
                  checkedAt: state.checkedAt,
                ),
              _ => const SizedBox.shrink(key: ValueKey('none')),
            },
          ),
        ],
      ),
    );
  }
}

class _HeroBanner extends StatelessWidget {
  const _HeroBanner({required this.state});

  final ConnectState state;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final ok = state.health?.status == 'ok';
    final (icon, title, subtitle) = switch (state) {
      ConnectState(checking: true) => (
          Icons.sync_rounded,
          '서버를 확인하는 중',
          '잠시만 기다려 주세요',
        ),
      ConnectState(error: _?) => (
          Icons.cloud_off_rounded,
          '서버에 닿지 못했어요',
          '주소와 서버 실행 여부를 확인하세요',
        ),
      ConnectState(health: _?) when ok => (
          Icons.cloud_done_rounded,
          '서버와 연결됐어요',
          '마이크 탭에서 녹음을 시작할 수 있어요',
        ),
      _ => (
          Icons.cloud_outlined,
          '서버에 연결해 주세요',
          'PC에서 서버를 실행한 뒤 확인하세요',
        ),
    };

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [scheme.primary, scheme.primary.withValues(alpha: 0.78)],
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: scheme.onPrimary.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(icon, color: scheme.onPrimary, size: 28),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: scheme.onPrimary,
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: scheme.onPrimary.withValues(alpha: 0.85),
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({super.key, required this.message});

  final String message;

  /// 연결 거부·시간 초과는 서버가 모델 로딩 중(포트 미개방)일 때의 전형적 증상 (API 계약 Q-API-8).
  static bool _looksLikeStarting(String m) {
    final lower = m.toLowerCase();
    return lower.contains('refused') ||
        lower.contains('시간 초과') ||
        lower.contains('timeout') ||
        lower.contains('socketexception');
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      color: scheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.error_outline_rounded, color: scheme.onErrorContainer),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '연결 실패',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: scheme.onErrorContainer,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    message,
                    style: TextStyle(
                      fontSize: 13,
                      color: scheme.onErrorContainer,
                    ),
                  ),
                  if (_looksLikeStarting(message)) ...[
                    const SizedBox(height: 8),
                    Text(
                      '서버를 방금 켰다면 모델을 로드하는 중일 수 있어요 (10~20초). 잠시 뒤 다시 확인하세요.',
                      style: TextStyle(
                        fontSize: 12,
                        color: scheme.onErrorContainer.withValues(alpha: 0.85),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HealthCard extends StatelessWidget {
  const _HealthCard({super.key, required this.health, this.checkedAt});

  final HealthInfo health;
  final DateTime? checkedAt;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final models = health.modelsLoaded;
    final total = health.memTotalMb;
    final used = health.memUsedMb;
    final ratio = (total != null && total > 0 && used != null)
        ? (used / total).clamp(0.0, 1.0)
        : null;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  '서버 상태',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: scheme.onSurface,
                  ),
                ),
                const Spacer(),
                _StatusPill(status: health.status),
              ],
            ),
            const SizedBox(height: 14),
            _InfoRow(
              icon: Icons.memory_rounded,
              label: 'GPU',
              value: health.gpuName ?? '정보 없음',
            ),
            if (ratio != null) ...[
              const SizedBox(height: 12),
              _InfoRow(
                icon: Icons.storage_rounded,
                label: 'VRAM',
                value: '$used / $total MB',
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(
                  value: ratio,
                  minHeight: 8,
                  backgroundColor: scheme.surfaceContainerHighest,
                ),
              ),
            ],
            const SizedBox(height: 12),
            _InfoRow(
              icon: Icons.model_training_rounded,
              label: '모델',
              value: models.isEmpty ? '로드된 모델 없음' : models.join(', '),
            ),
            if (checkedAt != null) ...[
              const SizedBox(height: 14),
              Text(
                '마지막 확인 ${_hhmmss(checkedAt!)}',
                style: TextStyle(fontSize: 11, color: scheme.outline),
              ),
            ],
          ],
        ),
      ),
    );
  }

  static String _two(int v) => v.toString().padLeft(2, '0');

  static String _hhmmss(DateTime t) =>
      '${_two(t.hour)}:${_two(t.minute)}:${_two(t.second)}';
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final ok = status == 'ok';
    final bg = ok ? scheme.primaryContainer : scheme.tertiaryContainer;
    final fg = ok ? scheme.onPrimaryContainer : scheme.onTertiaryContainer;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            ok ? Icons.check_circle_rounded : Icons.info_rounded,
            size: 14,
            color: fg,
          ),
          const SizedBox(width: 5),
          Text(
            ok ? '정상' : status,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: fg,
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: scheme.primary),
        const SizedBox(width: 10),
        SizedBox(
          width: 48,
          child: Text(
            label,
            style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }
}
