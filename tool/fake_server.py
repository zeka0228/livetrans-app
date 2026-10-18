"""앱 단독 검증용 가짜 서버.

API 계약 (앱↔서버) §1·§3 의 REST·WebSocket 동작을 흉내 낸다. STT 는 하지 않는다.
- 모드 C (mic_ws): 받은 PCM 바이트 수로 t_cap 을 계산해 1 s 마다 segment.partial, 3 s 마다 segment.final.
- 모드 B (loopback): 앱이 오디오를 보내지 않으므로 벽시계로 t_cap 을 계산해 같은 주기로 이벤트.
- stop 드레인 (S-1): control stop 을 받으면 0.5 s 뒤 마지막 segment.final → session.state=stopped → 서버가 close(1000).
- S-2: 다섯 번째 final 은 text="" 로 보내 앱이 빈 문장을 기록에 넣지 않는지 확인.
- GET /api/capture/targets (S-9 ①), E_CAPTURE_TARGET / E_SESSION_NOT_FOUND / E_NOT_IMPLEMENTED (Q-API-7).
- GET /api/tts?text&lang (S-13): ko/en/ja 는 0.8 s 짜리 삐 소리 WAV, 그 외 404 E_TTS_NO_VOICE, 빈/500자 초과 400 E_TTS_TEXT.

실행:  <서버 venv python> -I tool/fake_server.py [포트=8765]   (fastapi, uvicorn 필요)
"""

import asyncio
import io
import math
import struct
import time
import uuid
import wave

from fastapi import FastAPI, HTTPException, Response, WebSocket, WebSocketDisconnect
from starlette.websockets import WebSocketState

app = FastAPI()
SAMPLE_RATE = 16000
BYTES_PER_MS = SAMPLE_RATE * 2 / 1000

TARGETS = [
    {"id": "system", "kind": "system", "title": "PC 전체 소리 (기본 출력 장치)", "process": None, "pid": None, "windows": []},
    {
        "id": "pid:1234", "kind": "app", "title": "【LIVE】雑談配信 - YouTube - Chrome", "process": "chrome.exe", "pid": 1234,
        "windows": ["【LIVE】雑談配信 - YouTube - Chrome", "livetrans-server - Chrome"],
    },
    {"id": "pid:5678", "kind": "app", "title": "Twitch - Firefox", "process": "firefox.exe", "pid": 5678, "windows": ["Twitch - Firefox"]},
]

sessions: dict[str, dict] = {}


def error(status: int, code: str, message: str) -> HTTPException:
    return HTTPException(status_code=status, detail={"code": code, "message": message})


@app.get("/api/health")
async def health():
    return {
        "status": "ok",
        "gpu": {"name": "fake-gpu", "mem_total_mb": 16384, "mem_used_mb": 1024},
        "models_loaded": ["stt:fake:fake"],
    }


TTS_LANGS = {"ko": 440.0, "en": 523.3, "ja": 659.3}


def beep_wav(freq: float, seconds: float = 0.8, rate: int = 16000) -> bytes:
    n = int(rate * seconds)
    frames = b"".join(
        struct.pack("<h", int(12000 * math.sin(2 * math.pi * freq * i / rate) * min(1.0, (n - i) / (rate * 0.1))))
        for i in range(n)
    )
    buf = io.BytesIO()
    with wave.open(buf, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(rate)
        w.writeframes(frames)
    return buf.getvalue()


@app.get("/api/voices")
async def voices():
    return {"languages": sorted(TTS_LANGS), "voices": [{"voice_ref": "fake:beep", "languages": sorted(TTS_LANGS)}]}


@app.get("/api/tts")
async def tts(text: str = "", lang: str = "ko"):
    if not text.strip() or len(text) > 500:
        raise error(400, "E_TTS_TEXT", "텍스트가 비었거나 500자를 넘습니다")
    if lang not in TTS_LANGS:
        raise error(404, "E_TTS_NO_VOICE", f"{lang} 음성이 없습니다")
    return Response(content=beep_wav(TTS_LANGS[lang]), media_type="audio/wav")


@app.get("/api/capture/targets")
async def capture_targets():
    return {"targets": TARGETS, "capture_available": True, "app_capture_supported": True}


@app.post("/api/sessions")
async def create_session(body: dict):
    mode = body.get("mode")
    source = body.get("source") or {}
    stype = source.get("type")
    if mode == "C" and stype == "mic_ws":
        pass
    elif mode == "B" and stype == "loopback":
        target = (source.get("params") or {}).get("target")
        if target not in {t["id"] for t in TARGETS}:
            raise error(400, "E_CAPTURE_TARGET", f"캡처 대상을 찾을 수 없습니다: {target}")
    else:
        raise error(501, "E_NOT_IMPLEMENTED", f"mode={mode}, source={stype} 는 지원하지 않습니다")
    sid = uuid.uuid4().hex[:8]
    sessions[sid] = {"mode": mode, "stopped": False}
    return {"session_id": sid, "delay_s": None, "hls_url": None, "ws_url": f"/ws/sessions/{sid}"}


@app.post("/api/sessions/{sid}/stop")
async def stop_session(sid: str):
    if sid not in sessions:
        raise error(404, "E_SESSION_NOT_FOUND", f"세션이 없습니다: {sid}")
    sessions.pop(sid, None)
    return {"session_id": sid, "stopped": True}


def envelope(sid: str, seq: int, type_: str, payload: dict) -> dict:
    return {
        "v": 1,
        "type": type_,
        "seq": seq,
        "session_id": sid,
        "ts_wall_ms": int(time.time() * 1000),
        "payload": payload,
    }


@app.websocket("/ws/sessions/{sid}")
async def session_ws(ws: WebSocket, sid: str):
    await ws.accept()
    sess = sessions.get(sid)
    if sess is None:
        await ws.close(code=4404, reason="unknown session")
        return
    mode = sess["mode"]
    seq = 0
    received = 0
    seg_id = 0
    seg_start_ms = 0
    finals = 0
    started_at: float | None = None
    last_partial = time.monotonic()
    last_final = time.monotonic()
    lang = "ja" if mode == "B" else "ko"

    async def send(type_: str, payload: dict):
        nonlocal seq
        seq += 1
        await ws.send_json(envelope(sid, seq, type_, payload))

    def t_cap() -> int:
        if mode == "C":
            return int(received / BYTES_PER_MS)
        return 0 if started_at is None else int((time.monotonic() - started_at) * 1000)

    async def emit_final(text: str):
        nonlocal seg_id, seg_start_ms, finals
        finals += 1
        await send(
            "segment.final",
            {
                "seg_id": seg_id,
                "t_start_ms": seg_start_ms,
                "t_end_ms": t_cap(),
                "text": text,
                "lang": lang,
                "lang_prob": 0.99,
                "words": [],
                "forced_cut": False,
                "stt_ms": 12,
            },
        )
        seg_id += 1
        seg_start_ms = t_cap()

    await send("session.state", {"state": "starting", "delay_s": None, "play_start_wall_ms": None})
    try:
        while True:
            try:
                msg = await asyncio.wait_for(ws.receive(), timeout=0.25)
            except asyncio.TimeoutError:
                msg = None
            if msg is not None:
                if msg.get("type") == "websocket.disconnect":
                    break
                if msg.get("bytes") is not None:
                    received += len(msg["bytes"])
                    if started_at is None:
                        started_at = time.monotonic()
                        await send("session.state", {"state": "playing", "delay_s": None, "play_start_wall_ms": None})
                elif msg.get("text"):
                    text = msg["text"]
                    if '"start"' in text and started_at is None:
                        started_at = time.monotonic()
                        await send("session.state", {"state": "playing", "delay_s": None, "play_start_wall_ms": None})
                    elif '"stop"' in text:
                        # S-1: 드레인 — 마지막 발화를 끝내고 stopped 를 보낸 뒤 서버가 닫는다
                        await asyncio.sleep(0.5)
                        await emit_final("(가짜 마지막 문장) stop 뒤에 도착")
                        await send("session.state", {"state": "stopped", "delay_s": None, "play_start_wall_ms": None})
                        sessions.pop(sid, None)
                        await ws.close(code=1000)
                        return
            if started_at is None:
                continue
            now = time.monotonic()
            if now - last_partial >= 1.0:
                last_partial = now
                await send(
                    "segment.partial",
                    {"seg_id": seg_id, "t_start_ms": seg_start_ms, "text": f"(가짜 중간) {t_cap()} ms", "lang": lang},
                )
            if now - last_final >= 3.0:
                last_final = now
                if finals == 4:
                    await emit_final("")  # S-2: 빈 문장
                elif mode == "C":
                    await emit_final(f"(가짜 확정) {received} bytes 수신")
                else:
                    await emit_final(f"(가짜 확정) 창 소리 {t_cap() // 1000} s 째")
    except WebSocketDisconnect:
        pass
    finally:
        sessions.pop(sid, None)
        if ws.client_state == WebSocketState.CONNECTED:
            await ws.close()


if __name__ == "__main__":
    import sys

    import uvicorn

    port = int(sys.argv[1]) if len(sys.argv) > 1 else 8765
    uvicorn.run(app, host="127.0.0.1", port=port)
