/// 명세 v0.5 §4.9·§6.1 — 모드 A 원본 소리 격리 점검.
///
/// 서버 규격이 아직 API 계약에 없어 명세의 `RouteStatus` 를 그대로 옮겼다.
/// 서버 세션이 확정 규격을 올리면 (API 계약 Q-API-11) 필드명을 맞춘다.
class AudioDevice {
  const AudioDevice({
    required this.id,
    required this.name,
    this.isDefault = false,
    this.active = true,
  });

  /// `device:{0.0.0.00000000}.{…}` 형태. 세션 요청의 `route.isolation_device` 와 loopback 대상에 그대로 쓴다.
  final String id;
  final String name;

  /// 사용자의 기본 출력 장치(우리 앱 플레이어가 쓰는 장치)면 true → 격리 장치로 고를 수 없다.
  final bool isDefault;

  /// 연결 끊긴 HDMI 장치 등은 false.
  final bool active;

  factory AudioDevice.fromJson(Map<String, dynamic> j) => AudioDevice(
        id: j['id']?.toString() ?? '',
        name: j['name']?.toString() ?? '',
        isDefault: j['is_default'] == true || j['default'] == true,
        active: j['active'] != false,
      );
}

class AudioDevices {
  const AudioDevices({required this.devices, this.router});

  final List<AudioDevice> devices;

  /// 서버가 쓰는 격리 방식 (`spare_device` | `virtual_cable` | `none`). 없으면 null.
  final String? router;

  AudioDevice? get defaultDevice {
    for (final d in devices) {
      if (d.isDefault) return d;
    }
    return null;
  }

  /// 격리 장치 후보: 기본 장치가 아니고 활성인 것.
  List<AudioDevice> get candidates =>
      devices.where((d) => !d.isDefault && d.active).toList();

  factory AudioDevices.fromJson(Map<String, dynamic> j) => AudioDevices(
        devices: (j['devices'] as List?)
                ?.map((e) => AudioDevice.fromJson((e as Map).cast()))
                .toList() ??
            const [],
        router: j['router']?.toString(),
      );
}

/// `POST /api/audio/route/check` 응답 (명세 §4.9 `RouteStatus`).
class RouteStatus {
  const RouteStatus({
    required this.isolated,
    this.captureTarget,
    this.userOutputDevice,
    this.problems = const [],
    this.setupGuide,
    this.restoreGuide,
  });

  final bool isolated;
  final String? captureTarget;
  final String? userOutputDevice;

  /// 사용자에게 보여줄 문제 목록 (한국어).
  final List<String> problems;
  final String? setupGuide;
  final String? restoreGuide;

  factory RouteStatus.fromJson(Map<String, dynamic> j) => RouteStatus(
        isolated: j['isolated'] == true,
        captureTarget: j['capture_target'] as String?,
        userOutputDevice: j['user_output_device'] as String?,
        problems:
            (j['problems'] as List?)?.map((e) => e.toString()).toList() ?? const [],
        setupGuide: j['setup_guide'] as String?,
        restoreGuide: j['restore_guide'] as String?,
      );
}

/// `POST /api/calibrate` 응답 (명세 §3.4). 아직 서버에 없다 — 404 면 앱은 수동 D 만 쓴다.
class CalibrateResult {
  const CalibrateResult({
    required this.recommendedDelayS,
    this.p99EndToEndMs,
    this.gpuUtil,
  });

  final int recommendedDelayS;
  final int? p99EndToEndMs;

  /// 평균 GPU 점유율 ρ. 0.7 넘으면 경고, 1 이상이면 서버가 시작을 거부한다.
  final double? gpuUtil;

  factory CalibrateResult.fromJson(Map<String, dynamic> j) => CalibrateResult(
        recommendedDelayS: (j['recommended_delay_s'] as num?)?.toInt() ?? 0,
        p99EndToEndMs: (j['p99_end_to_end_ms'] as num?)?.toInt(),
        gpuUtil: (j['gpu_util'] as num?)?.toDouble(),
      );
}
