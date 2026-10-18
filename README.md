# livetrans-app

실시간 방송 번역기의 Flutter 앱입니다. Windows 데스크톱이 본체(모드 A 동기 시청 플레이어, 모드 B 오버레이)이고, Android는 보조(모드 C 마이크, 수업 과제)입니다. 백엔드 서버는 [livetrans-server](https://github.com/zeka0228/livetrans-server) 저장소입니다.

- 스택: Flutter 3.41 · Dart 3.11 · flutter_riverpod · web_socket_channel · record
- 현재 범위: 서버 연결 화면 + 마이크 모드(STT) — 앱 마이크 PCM 스트림을 WebSocket으로 서버에 보내고 중간/확정 자막을 표시합니다.

## 설계 문서

설계·API 계약·결정·이력 문서는 저장소가 아니라 메인테이너의 Obsidian 볼트(`실시간 방송 번역기/`)에서 관리합니다. 앱↔서버 통신 규격은 그 안의 `API 계약 (앱↔서버)` 문서가 기준입니다. 이 README는 실행 방법만 다룹니다.

## 실행

```bat
flutter pub get
flutter run -d <device>
```

- Android 에뮬레이터에서 PC 서버 주소는 `http://10.0.2.2:8765`, Windows에서는 `http://127.0.0.1:8765` 입니다 (연결 화면에서 바꿀 수 있습니다).
- 서버 없이 앱만 확인하려면 가짜 서버를 띄웁니다 (fastapi·uvicorn 필요):

```bat
python tool\fake_server.py
```

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
