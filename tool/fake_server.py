"""앱 단독 검증용 가짜 서버.

기술 명세서 §6의 REST·WebSocket 형식만 흉내 낸다. STT는 하지 않고, 받은 PCM 바이트 수로
t_cap을 계산해 1초마다 segment.partial, 3초마다 segment.final을 보낸다.

실행:  python -I tool/fake_server.py   (fastapi, uvicorn 필요)
"""

import asyncio
import time
import uuid

from fastapi import FastAPI, WebSocket, WebSocketDisconnect
from starlette.websockets import WebSocketState

app = FastAPI()
SAMPLE_RATE = 16000
BYTES_PER_MS = SAMPLE_RATE * 2 / 1000


@app.get("/api/health")
async def health():
    return {
        "status": "ok",
        "gpu": {"name": "fake-gpu", "mem_total_mb": 16384, "mem_used_mb": 1024},
        "models_loaded": ["fake-stt"],
    }


@app.post("/api/sessions")
async def create_session(body: dict):
    sid = uuid.uuid4().hex[:8]
    return {
        "session_id": sid,
        "delay_s": body.get("delay_s") or 20,
        "hls_url": None,
        "ws_url": f"/ws/sessions/{sid}",
    }


@app.post("/api/sessions/{sid}/stop")
async def stop_session(sid: str):
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
    seq = 0
    received = 0
    seg_id = 0
    seg_start_ms = 0
    last_partial = time.monotonic()
    last_final = time.monotonic()

    async def send(type_: str, payload: dict):
        nonlocal seq
        seq += 1
        await ws.send_json(envelope(sid, seq, type_, payload))

    await send("session.state", {"state": "starting", "delay_s": 0})
    try:
        while True:
            msg = await ws.receive()
            if msg.get("type") == "websocket.disconnect":
                break
            if "bytes" in msg and msg["bytes"] is not None:
                received += len(msg["bytes"])
            elif "text" in msg and msg["text"]:
                text = msg["text"]
                if '"start"' in text:
                    await send("session.state", {"state": "playing", "delay_s": 0})
                elif '"stop"' in text:
                    await send("session.state", {"state": "stopped", "delay_s": 0})
            now = time.monotonic()
            t_cap = int(received / BYTES_PER_MS)
            if now - last_partial >= 1.0:
                last_partial = now
                await send(
                    "segment.partial",
                    {"seg_id": seg_id, "t_start_ms": seg_start_ms, "text": f"(가짜 중간) {t_cap} ms", "lang": "ko"},
                )
            if now - last_final >= 3.0:
                last_final = now
                await send(
                    "segment.final",
                    {
                        "seg_id": seg_id,
                        "t_start_ms": seg_start_ms,
                        "t_end_ms": t_cap,
                        "text": f"(가짜 확정) {received} bytes 수신",
                        "lang": "ko",
                        "lang_prob": 0.99,
                        "words": [],
                        "forced_cut": False,
                        "stt_ms": 12,
                    },
                )
                seg_id += 1
                seg_start_ms = t_cap
    except WebSocketDisconnect:
        pass
    finally:
        if ws.client_state == WebSocketState.CONNECTED:
            await ws.close()


if __name__ == "__main__":
    import uvicorn

    uvicorn.run(app, host="127.0.0.1", port=8765)
