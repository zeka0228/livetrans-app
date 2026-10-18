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
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _url,
            keyboardType: TextInputType.url,
            decoration: const InputDecoration(
              labelText: '서버 주소',
              hintText: 'http://10.0.2.2:8765',
              border: OutlineInputBorder(),
              helperText: 'Android 에뮬레이터는 10.0.2.2, Windows는 127.0.0.1',
            ),
            onSubmitted: (_) => _check(),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: state.checking ? null : _check,
            icon: state.checking
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.network_check),
            label: const Text('연결 확인'),
          ),
          const SizedBox(height: 20),
          if (state.error != null)
            Card(
              color: scheme.errorContainer,
              child: ListTile(
                leading: Icon(Icons.error_outline, color: scheme.onErrorContainer),
                title: const Text('연결 실패'),
                subtitle: Text(state.error!),
              ),
            ),
          if (state.health != null) _HealthCard(health: state.health!),
        ],
      ),
    );
  }
}

class _HealthCard extends StatelessWidget {
  const _HealthCard({required this.health});

  final HealthInfo health;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final ok = health.status == 'ok';
    final models = health.modelsLoaded;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(ok ? Icons.check_circle : Icons.info_outline,
                    color: ok ? scheme.primary : scheme.tertiary),
                const SizedBox(width: 8),
                Text('상태: ${health.status}',
                    style: const TextStyle(fontWeight: FontWeight.w600)),
              ],
            ),
            const SizedBox(height: 8),
            Text('GPU: ${health.gpuName ?? '정보 없음'}'),
            if (health.memTotalMb != null)
              Text('VRAM: ${health.memUsedMb ?? '-'} / ${health.memTotalMb} MB'),
            Text('로드된 모델: ${models.isEmpty ? '없음' : models.join(', ')}'),
          ],
        ),
      ),
    );
  }
}
