"""릴리스 웹 빌드(build/web)를 정적으로 서빙한다.  python tool/serve_web.py [폴더=build/web] [포트=8780]

- CORS `*`, 캐시 끔 (빌드를 다시 하면 새로고침만으로 반영).
- `flutter run -d web-server`(디버그) 는 브라우저를 다시 열면 빈 화면이 나는 경우가 있어 시연·검증은 이 방식으로 한다.
- 서버(livetrans-server)에 CORS 가 없으므로 Chrome 은 tool/run_web.bat 처럼 `--disable-web-security` + 별도 프로필로 연다.
"""
import sys
from functools import partial
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer

TYPES = {
    ".m3u8": "application/vnd.apple.mpegurl",
    ".m4s": "video/iso.segment",
    ".mp4": "video/mp4",
    ".vtt": "text/vtt",
    ".wasm": "application/wasm",
    ".js": "text/javascript",
    ".json": "application/json",
}


class Handler(SimpleHTTPRequestHandler):
    def end_headers(self):
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Cache-Control", "no-cache")
        super().end_headers()

    def guess_type(self, path):
        for ext, media in TYPES.items():
            if path.endswith(ext):
                return media
        return super().guess_type(path)

    def log_message(self, fmt, *args):
        sys.stdout.write("%s %s\n" % (self.address_string(), fmt % args))
        sys.stdout.flush()


def main() -> None:
    directory = sys.argv[1] if len(sys.argv) > 1 else "build/web"
    port = int(sys.argv[2]) if len(sys.argv) > 2 else 8780
    print(f"serving {directory} at http://127.0.0.1:{port}  (Ctrl+C 로 종료)")
    ThreadingHTTPServer(("127.0.0.1", port), partial(Handler, directory=directory)).serve_forever()


if __name__ == "__main__":
    main()
