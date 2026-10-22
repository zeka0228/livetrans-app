"""앱 단독 검증용 가짜 서버.

API 계약 (앱↔서버) §1·§3 의 REST·WebSocket 동작을 흉내 낸다. STT 는 하지 않는다.
- 모드 C (mic_ws): 받은 PCM 바이트 수로 t_cap 을 계산해 1 s 마다 segment.partial, 3 s 마다 segment.final.
- 모드 B (loopback): 앱이 오디오를 보내지 않으므로 벽시계로 t_cap 을 계산해 같은 주기로 이벤트.
- stop 드레인 (S-1): control stop 을 받으면 0.5 s 뒤 마지막 segment.final → session.state=stopped → 서버가 close(1000).
- S-2: 다섯 번째 final 은 text="" 로 보내 앱이 빈 문장을 기록에 넣지 않는지 확인.
- GET /api/capture/targets (S-9 ①), E_CAPTURE_TARGET / E_SESSION_NOT_FOUND / E_NOT_IMPLEMENTED (Q-API-7).
- GET /api/tts?text&lang (S-13): ko/en/ja 는 0.8 s 짜리 삐 소리 WAV, 그 외 404 E_TTS_NO_VOICE, 빈/500자 초과 400 E_TTS_TEXT.
- **모드 A (동기 시청, 명세 §6 v0.5 — 앱이 기대하는 동작, API 계약 §1.6·Q-API-9~11)**:
  - GET /api/audio/devices, POST /api/audio/route/check, POST /api/calibrate (3 s 뒤 권장 12 s).
  - POST /api/sessions mode A: route.isolation_device 가 기본 장치거나 target=system 이면 400 E_ROUTE_NOT_ISOLATED.
    delay_s 가 null 이면 calibrating 단계(2 s)를 거쳐 12 s, 아니면 요청값.
  - WS: starting → (start) → calibrating → buffering{delay_s, play_start_wall_ms} → playing. t_cap 은 start 기준 벽시계.
    3 s 마다 segment.final(speaker S0/S1 번갈아) + 0.8 s 뒤 translation.final + tts.ready, 2 s 마다 metrics,
    5번째마다 deadline.event L1, 9번째마다 L3. 격리 장치가 `device:lost` 면 재생 15 s 뒤 E_ROUTE_LOST → stopped → close.

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

# 모드 A 격리 장치 후보 (명세 §4.9). 기본 장치는 격리 장치로 못 쓴다.
AUDIO_DEVICES = [
    {"id": "device:spk", "name": "스피커 (Realtek High Definition Audio)", "is_default": True, "active": True},
    {"id": "device:hdmi", "name": "LG ULTRAGEAR (NVIDIA High Definition Audio)", "is_default": False, "active": True},
    {"id": "device:cable", "name": "CABLE Input (VB-Audio Virtual Cable)", "is_default": False, "active": True},
    {"id": "device:dp", "name": "DELL U2723QE (연결 끊김)", "is_default": False, "active": False},
    {"id": "device:lost", "name": "테스트용 — 재생 15 s 뒤 끊기는 장치", "is_default": False, "active": True},
]
DEFAULT_DEVICE = "device:spk"
FAKE_RECOMMENDED_DELAY_S = 12

JA_LINES = [
    ("皆さんこんにちは、配信始めていきます。", "여러분 안녕하세요, 방송 시작하겠습니다."),
    ("今日はちょっと遅れてごめんなさい。", "오늘은 조금 늦어서 미안해요."),
    ("コメントありがとう、全部読んでるよ。", "댓글 고마워요, 전부 읽고 있어요."),
    ("えっと、次のゲーム何にしようかな。", "음, 다음 게임은 뭘로 할까."),
    ("このボス強すぎない？", "이 보스 너무 센 거 아냐?"),
    ("よし、もう一回いくぞ！", "좋아, 한 번 더 간다!"),
]

sessions: dict[str, dict] = {}


def error(status: int, code: str, message: str, **extra) -> HTTPException:
    return HTTPException(status_code=status, detail={"code": code, "message": message, **extra})


def now_ms() -> int:
    return int(time.time() * 1000)


@app.get("/api/health")
async def health():
    return {
        "status": "ok",
        "gpu": {"name": "fake-gpu", "mem_total_mb": 16384, "mem_used_mb": 1024},
        "models_loaded": ["stt:fake:fake", "tts:fake", "mt:fake"],
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


# ---- 모드 A: 소리 격리 점검·보정 (명세 §4.9·§3.4) -------------------------------------


@app.get("/api/audio/devices")
async def audio_devices():
    return {"devices": AUDIO_DEVICES, "router": "spare_device", "default_device": DEFAULT_DEVICE}


def route_status(isolation_device: str | None) -> dict:
    dev = next((d for d in AUDIO_DEVICES if d["id"] == isolation_device), None)
    problems = []
    if dev is None:
        problems.append(f"격리 장치를 찾을 수 없습니다: {isolation_device}")
    else:
        if dev["is_default"]:
            problems.append("격리 장치가 사용자 출력 장치(기본 장치)와 같습니다 — 되먹임이 생기고 원본이 들립니다")
        if not dev["active"]:
            problems.append("격리 장치가 연결 끊김 상태입니다 (모니터 전원·케이블 확인)")
    return {
        "isolated": not problems,
        "capture_target": isolation_device if not problems else None,
        "user_output_device": DEFAULT_DEVICE,
        "problems": problems,
        "setup_guide": "Windows 설정 → 시스템 → 소리 → 볼륨 믹서에서 브라우저(chrome.exe)의 출력 장치를 "
        f"'{dev['name'] if dev else '격리 장치'}' 로 바꾸세요. 우리 앱은 기본 스피커 그대로.",
        "restore_guide": "시청을 마치면 볼륨 믹서에서 브라우저 출력 장치를 '기본값'으로 되돌리세요.",
    }


@app.post("/api/audio/route/check")
async def audio_route_check(body: dict):
    await asyncio.sleep(0.8)
    return route_status(body.get("isolation_device"))


@app.post("/api/calibrate")
async def calibrate(body: dict | None = None):
    await asyncio.sleep(3.0)
    return {
        "recommended_delay_s": FAKE_RECOMMENDED_DELAY_S,
        "p99_end_to_end_ms": 7800,
        "gpu_util": 0.42,
        "p50_ms": {"sep": 400, "diar": 150, "stt": 350, "mt": 900, "tts": 120},
        "p99_ms": {"sep": 800, "diar": 300, "stt": 1200, "mt": 2500, "tts": 400},
    }


# ---- 세션 ---------------------------------------------------------------------------


@app.post("/api/sessions")
async def create_session(body: dict):
    mode = body.get("mode")
    source = body.get("source") or {}
    stype = source.get("type")
    params = source.get("params") or {}
    if mode == "C" and stype == "mic_ws":
        pass
    elif mode == "B" and stype == "loopback":
        target = params.get("target")
        if target not in {t["id"] for t in TARGETS}:
            raise error(400, "E_CAPTURE_TARGET", f"캡처 대상을 찾을 수 없습니다: {target}")
    elif mode == "A" and stype in {"loopback", "obs_stream"}:
        route = body.get("route") or {}
        iso = route.get("isolation_device")
        if stype == "loopback" and params.get("target") in (None, "system"):
            raise error(400, "E_ROUTE_NOT_ISOLATED", "모드 A 에서는 PC 전체 소리를 캡처할 수 없습니다 (되먹임)",
                        problems=["격리 장치를 고르고 점검을 통과하세요"])
        if iso is not None:
            status = route_status(iso)
            if not status["isolated"]:
                raise error(400, "E_ROUTE_NOT_ISOLATED", "원본 소리가 격리되지 않았습니다", problems=status["problems"])
    else:
        raise error(501, "E_NOT_IMPLEMENTED", f"mode={mode}, source={stype} 는 지원하지 않습니다")

    sid = uuid.uuid4().hex[:8]
    requested = body.get("delay_s")
    sess = {
        "mode": mode,
        "stopped": False,
        "delay_s": int(requested) if requested else None,
        "has_video": stype == "obs_stream",
        "isolation": ((body.get("route") or {}).get("isolation_device")) or params.get("target"),
        "tts": bool((body.get("tts") or {}).get("enabled")),
    }
    sessions[sid] = sess
    return {
        "session_id": sid,
        "delay_s": sess["delay_s"],
        "hls_url": f"/hls/{sid}/master.m3u8" if mode == "A" and sess["has_video"] else None,
        "ws_url": f"/ws/sessions/{sid}",
    }


@app.post("/api/sessions/{sid}/stop")
async def stop_session(sid: str):
    if sid not in sessions:
        raise error(404, "E_SESSION_NOT_FOUND", f"세션이 없습니다: {sid}")
    sessions.pop(sid, None)
    return {"session_id": sid, "stopped": True}


def envelope(sid: str, seq: int, type_: str, payload: dict) -> dict:
    return {"v": 1, "type": type_, "seq": seq, "session_id": sid, "ts_wall_ms": now_ms(), "payload": payload}


@app.websocket("/ws/sessions/{sid}")
async def session_ws(ws: WebSocket, sid: str):
    await ws.accept()
    sess = sessions.get(sid)
    if sess is None:
        await ws.close(code=4404, reason="unknown session")
        return
    try:
        if sess["mode"] == "A":
            await run_mode_a(ws, sid, sess)
        else:
            await run_mode_bc(ws, sid, sess)
    except WebSocketDisconnect:
        pass
    finally:
        sessions.pop(sid, None)
        if ws.client_state == WebSocketState.CONNECTED:
            await ws.close()


class Sender:
    def __init__(self, ws: WebSocket, sid: str):
        self.ws, self.sid, self.seq = ws, sid, 0

    async def __call__(self, type_: str, payload: dict):
        self.seq += 1
        await self.ws.send_json(envelope(self.sid, self.seq, type_, payload))


async def recv(ws: WebSocket, timeout: float):
    try:
        return await asyncio.wait_for(ws.receive(), timeout=timeout)
    except asyncio.TimeoutError:
        return None


async def run_mode_bc(ws: WebSocket, sid: str, sess: dict):
    mode = sess["mode"]
    send = Sender(ws, sid)
    received = 0
    seg_id = 0
    seg_start_ms = 0
    finals = 0
    started_at: float | None = None
    last_partial = time.monotonic()
    last_final = time.monotonic()
    lang = "ja" if mode == "B" else "ko"

    def t_cap() -> int:
        if mode == "C":
            return int(received / BYTES_PER_MS)
        return 0 if started_at is None else int((time.monotonic() - started_at) * 1000)

    async def emit_final(text: str):
        nonlocal seg_id, seg_start_ms, finals
        finals += 1
        await send("segment.final", {
            "seg_id": seg_id, "t_start_ms": seg_start_ms, "t_end_ms": t_cap(), "text": text, "lang": lang,
            "lang_prob": 0.99, "words": [], "forced_cut": False, "stt_ms": 12,
        })
        seg_id += 1
        seg_start_ms = t_cap()

    await send("session.state", {"state": "starting", "delay_s": None, "play_start_wall_ms": None})
    while True:
        msg = await recv(ws, 0.25)
        if msg is not None:
            if msg.get("type") == "websocket.disconnect":
                return
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
            await send("segment.partial", {"seg_id": seg_id, "t_start_ms": seg_start_ms, "text": f"(가짜 중간) {t_cap()} ms", "lang": lang})
        if now - last_final >= 3.0:
            last_final = now
            if finals == 4:
                await emit_final("")  # S-2: 빈 문장
            elif mode == "C":
                await emit_final(f"(가짜 확정) {received} bytes 수신")
            else:
                await emit_final(f"(가짜 확정) 창 소리 {t_cap() // 1000} s 째")


async def run_mode_a(ws: WebSocket, sid: str, sess: dict):
    """모드 A: 캡처 시작 시각을 t_cap=0 으로 두고 D초 뒤 재생. 이벤트는 캡처 시간축으로 보낸다."""
    send = Sender(ws, sid)
    state = {"state": "starting", "delay_s": sess["delay_s"], "play_start_wall_ms": None}
    await send("session.state", dict(state))

    # start 대기
    while True:
        msg = await recv(ws, 0.25)
        if msg is None:
            continue
        if msg.get("type") == "websocket.disconnect":
            return
        if msg.get("text") and '"start"' in msg["text"]:
            break
        if msg.get("text") and '"stop"' in msg["text"]:
            state["state"] = "stopped"
            await send("session.state", dict(state))
            await ws.close(code=1000)
            return

    if state["delay_s"] is None:
        state["state"] = "calibrating"
        await send("session.state", dict(state))
        await asyncio.sleep(2.0)
        state["delay_s"] = FAKE_RECOMMENDED_DELAY_S

    delay_ms = state["delay_s"] * 1000
    cap_start_wall = now_ms()
    state["play_start_wall_ms"] = cap_start_wall + delay_ms
    state["state"] = "buffering"
    await send("session.state", dict(state))

    def t_cap() -> int:
        return now_ms() - cap_start_wall

    seg_id = 0
    last_final_t = 0
    last_metrics = time.monotonic()
    pending_tr: list[tuple[int, int, str, str | None]] = []  # (due_t_cap, seg_id, text, speaker)
    playing = False
    lost_at = 15_000 if sess.get("isolation") == "device:lost" else None
    miss_rate = 0.0

    async def emit_final(end_ms: int, text: str, tr: str, speaker: str | None, late_level: str | None):
        nonlocal seg_id
        await send("segment.final", {
            "seg_id": seg_id, "t_start_ms": end_ms - 3000, "t_end_ms": end_ms - 300, "text": text, "lang": "ja",
            "lang_prob": 0.97, "words": [], "forced_cut": False, "stt_ms": 420, **({"speaker": speaker} if speaker else {}),
        })
        pending_tr.append((end_ms + 800, seg_id, tr, speaker))
        if late_level:
            await send("deadline.event", {"seg_id": seg_id, "kind": "tts" if late_level == "L1" else "subtitle",
                                          "level": late_level, "late_ms": 350 if late_level == "L1" else 2100})
        seg_id += 1

    while True:
        msg = await recv(ws, 0.2)
        if msg is not None:
            if msg.get("type") == "websocket.disconnect":
                return
            if msg.get("text") and '"stop"' in msg["text"]:
                await asyncio.sleep(0.6)
                t = t_cap()
                await emit_final(t, "(stop 뒤 마지막 문장) お疲れ様でした。", "(stop 뒤 마지막 문장) 수고하셨습니다.", "S0", None)
                state["state"] = "stopped"
                await send("session.state", dict(state))
                sessions.pop(sid, None)
                await ws.close(code=1000)
                return
            # config.update 등은 로그만
        t = t_cap()
        if not playing and t >= delay_ms:
            playing = True
            state["state"] = "playing"
            await send("session.state", dict(state))
        if t - last_final_t >= 3000:
            last_final_t = t
            n = seg_id
            ja, ko = JA_LINES[n % len(JA_LINES)]
            speaker = "S0" if n % 3 else "S1"
            level = "L3" if (n and n % 9 == 0) else ("L1" if (n and n % 5 == 0) else None)
            if level == "L3":
                miss_rate = min(0.05, miss_rate + 0.01)
            await emit_final(t, ja, ko, speaker, level)
        for item in list(pending_tr):
            if t >= item[0]:
                pending_tr.remove(item)
                await send("translation.final", {
                    "seg_id": item[1], "text": item[2], "src_lang": "ja", "tgt_lang": "ko", "engine": "fake",
                    "fallback": False, "mt_ms": 650, **({"speaker": item[3]} if item[3] else {}),
                })
                if sess.get("tts"):
                    await send("tts.ready", {"seg_id": item[1], "duration_ms": 1800, "rate": 1.0,
                                             "voice_ref": "system:auto", "tts_ms": 90})
        if time.monotonic() - last_metrics >= 2.0:
            last_metrics = time.monotonic()
            await send("metrics", {
                "p50_ms": {"sep": 400, "diar": 150, "stt": 350, "mt": 900, "tts": 120},
                "p99_ms": {"sep": 800, "diar": 300, "stt": 1200, "mt": 2500, "tts": 400},
                "gpu_util_stream": 0.35, "miss_rate": miss_rate, "queue_depth": 1, "gpu_mem_used_mb": 8600,
            })
        if lost_at is not None and playing and t >= delay_ms + lost_at:
            await send("error", {"code": "E_ROUTE_LOST", "message": "격리 장치가 분리되었습니다 (device:lost)", "recoverable": False})
            state["state"] = "stopped"
            await send("session.state", dict(state))
            sessions.pop(sid, None)
            await ws.close(code=1000)
            return


if __name__ == "__main__":
    import sys

    import uvicorn

    port = int(sys.argv[1]) if len(sys.argv) > 1 else 8765
    uvicorn.run(app, host="127.0.0.1", port=port)
