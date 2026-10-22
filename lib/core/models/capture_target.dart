/// `GET /api/capture/targets` 응답 (API 계약 S-9 ①).
class CaptureTarget {
  const CaptureTarget({
    required this.id,
    required this.kind,
    required this.title,
    this.process,
    this.pid,
    this.windows = const [],
  });

  /// `"system"` 또는 `"pid:1234"`. 세션 생성 시 `source.params.target` 에 그대로 보낸다.
  final String id;

  /// `"system"` | `"app"`
  final String kind;
  final String title;
  final String? process;
  final int? pid;

  /// 그 프로세스의 창 제목 전체 (S-9 확정 규격 ②). 같은 Chrome 창 여러 개가 1항목으로 묶인다.
  final List<String> windows;

  bool get isSystem => kind == 'system';

  factory CaptureTarget.fromJson(Map<String, dynamic> j) => CaptureTarget(
        id: j['id']?.toString() ?? '',
        kind: j['kind']?.toString() ?? 'app',
        title: j['title']?.toString() ?? '',
        process: j['process'] as String?,
        pid: (j['pid'] as num?)?.toInt(),
        windows:
            (j['windows'] as List?)?.map((e) => e.toString()).toList() ?? const [],
      );
}

class CaptureTargets {
  const CaptureTargets({
    required this.targets,
    required this.appCaptureSupported,
    this.captureAvailable = true,
  });

  final List<CaptureTarget> targets;

  /// false 면 서버에 캡처 헬퍼(wincap)가 없어 `targets` 가 비어 있다 (S-9 확정 규격 ①).
  final bool captureAvailable;

  /// false 면 `system` 만 고를 수 있다.
  final bool appCaptureSupported;

  factory CaptureTargets.fromJson(Map<String, dynamic> j) => CaptureTargets(
        targets: (j['targets'] as List?)
                ?.map((e) => CaptureTarget.fromJson((e as Map).cast()))
                .toList() ??
            const [],
        appCaptureSupported: j['app_capture_supported'] != false,
        captureAvailable: j['capture_available'] != false,
      );
}
