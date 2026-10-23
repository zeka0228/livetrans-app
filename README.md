# livetrans-app

실시간 방송 번역기의 Flutter 앱입니다. 외국어 방송을 지연(D초) 재생하며 자막·번역·번역 음성을 원래 타이밍에 맞춰 보여 주는 개인 시청 도구의 클라이언트로, 백엔드 서버는 [livetrans-server](https://github.com/zeka0228/livetrans-server) 저장소입니다.

- 스택: Flutter 3.41 · Dart 3.11 · flutter_riverpod · web_socket_channel · record · audioplayers · hls.js(웹)
- 화면: **연결**(서버 health) · **마이크**(모드 C, 앱 마이크 → 서버 STT) · **방송 자막**(모드 B, PC 창 소리를 서버가 캡처 → 화자 레인별 자막·번역, 자막 탭 → 서버 TTS) · **동기 시청**(모드 A, 지연 재생 + 영상(HLS) + 자막 오버레이 — 서버 모드 A 구현 뒤 실서버 연결)
- 실행 플랫폼: 현재 **웹(Chrome)** 이 기본입니다. Windows 데스크톱은 Visual Studio C++ 워크로드가, Android 는 에뮬레이터가 준비되면 같은 코드로 빌드됩니다 (영상 재생은 웹에서만 지원, 그 외 플랫폼은 `media_kit` 예정).

## 설계 문서

설계·API 계약·결정·이력 문서는 저장소가 아니라 메인테이너의 Obsidian 볼트(`실시간 방송 번역기/`)에서 관리합니다. 앱↔서버 통신 규격은 그 안의 `API 계약 (앱↔서버)` 문서가 기준입니다. 이 README는 실행 방법만 다룹니다.

## 실행 (웹, 권장)

```bat
toolun_web.bat                              REM 서버 http://127.0.0.1:8765, 앱 http://127.0.0.1:8780
toolun_web.bat http://127.0.0.1:8766 8782   REM 다른 서버 주소·포트
```

릴리스 빌드(`flutter build web`) → `tool\serve_web.py` 로 정적 서빙 → Chrome 을 별도 프로필 + `--disable-web-security` 로 엽니다 (서버에 CORS 가 아직 없어서). 서버 주소는 `--dart-define=LIVETRANS_SERVER=…` 로 빌드에 박히며 연결 화면에서도 바꿀 수 있습니다. 디버그 `flutter run -d web-server` 는 브라우저를 다시 열면 빈 화면이 나는 경우가 있어 권장하지 않습니다.

다른 플랫폼:

```bat
flutter pub get
flutter run -d <device>
```

- Android 에뮬레이터에서 PC 서버 주소는 `http://10.0.2.2:8765`, Windows·웹에서는 `http://127.0.0.1:8765` 입니다.

### 서버 없이 확인하기 (가짜 서버)

```bat
REM 서버 저장소의 venv python 으로 (fastapi·uvicorn 필요)
set FAKE_HLS_DIR=<ffmpeg 로 만든 HLS 폴더>   REM 모드 A 영상까지 보려면 (만드는 법은 toolake_server.py 주석)
python toolake_server.py 8766
toolun_web.bat http://127.0.0.1:8766 8782
```

HLS 플레이어만 점검하려면 `flutter build web --release -o build\web_hls --dart-define=LIVETRANS_DEMO=hls --dart-define=HLS_URL=<m3u8 주소>` 뒤 같은 방식으로 서빙합니다.

테스트·정적 분석:

```bat
flutter test
flutter analyze
```

## Rights & Responsible Use

- 개인 시청 보조 도구입니다. 번역 결과물을 업로드·재배포하는 기능은 제공하지 않습니다.
- 타인의 목소리를 복제하는 기능이나 모델을 포함하지 않습니다. 음성 모델을 연결할 때는 본인이 사용 권리를 가진 것만 사용해야 합니다.

## 라이선스

Apache License 2.0
