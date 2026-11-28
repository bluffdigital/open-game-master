"""ASGI middleware for vLLM (--middleware ogm_think_budget.ThinkBudget).

Open Game Master asks for thinking on tool-deciding DM calls but sends no
thinking budget, and vLLM has no server-wide default for one. Qwen3.6 can
then think until max_tokens (16384), a ~2 minute turn that ends with no tool
call. This adds thinking_token_budget to chat-completion requests that turn
thinking on and do not set a budget themselves.

v2 (2026-11-26): also adds vLLM's repetition_detection to every chat request
that does not set one. On 2026-11-26 02:32 UTC a correction call in Zen's Solo
Test 2 hit the thinking budget mid-sentence, kept reasoning in the visible
reply and looped on "Then narrate." for 16k tokens (~2 min); OGM's own
stream-repetition guard only catches cycles of 160+ characters. A block of
OGM_REPEAT_MIN..OGM_REPEAT_MAX tokens repeated OGM_REPEAT_COUNT times in a row
now ends the reply. Anything it cannot parse is passed through untouched.
Set OGM_REPEAT_COUNT=0 to turn the guard off.
"""
import json
import os

BUDGET = int(os.environ.get("OGM_THINKING_TOKEN_BUDGET", "2048"))
REPEAT_MIN = int(os.environ.get("OGM_REPEAT_MIN", "3"))
REPEAT_MAX = int(os.environ.get("OGM_REPEAT_MAX", "64"))
REPEAT_COUNT = int(os.environ.get("OGM_REPEAT_COUNT", "6"))


def _patch(data):
    changed = False
    kwargs = data.get("chat_template_kwargs") or {}
    if BUDGET > 0 and kwargs.get("enable_thinking") is True and data.get("thinking_token_budget") is None:
        data["thinking_token_budget"] = BUDGET
        changed = True
    if REPEAT_COUNT >= 2 and data.get("repetition_detection") is None:
        data["repetition_detection"] = {
            "min_pattern_size": REPEAT_MIN,
            "max_pattern_size": REPEAT_MAX,
            "min_count": REPEAT_COUNT,
        }
        changed = True
    return changed


# --- v3 (2026-11-26): sampling log + file-based override, no restart needed to change ---
# Log: touch /workspace/vllm-plugins/ogm_sampling_log.on -> one JSON line per chat request
#      in /workspace/logs/ogm_sampling.log (sampling fields only, before -> after).
# Override: /workspace/vllm-plugins/ogm_sampling_override.json, e.g.
#   {"thinking": {"force": {"top_p": 0.95}, "if_missing": {"top_k": 20}},
#    "nothinking": {"if_missing": {...}}}
# Delete the file to turn the override off (re-read on every request by mtime).
import time as _time

_SAMPLING_KEYS = ("temperature", "top_p", "top_k", "min_p", "presence_penalty",
                  "frequency_penalty", "repetition_penalty", "repeat_penalty",
                  "max_tokens", "max_completion_tokens", "thinking_token_budget", "seed")
_PLUG_DIR = os.path.dirname(os.path.abspath(__file__))
_LOG_FLAG = os.path.join(_PLUG_DIR, "ogm_sampling_log.on")
_OVR_FILE = os.path.join(_PLUG_DIR, "ogm_sampling_override.json")
_LOG_FILE = "/workspace/logs/ogm_sampling.log"
_ovr_cache = {"mtime": None, "data": {}}


def _load_override():
    try:
        m = os.path.getmtime(_OVR_FILE)
    except OSError:
        _ovr_cache.update(mtime=None, data={})
        return {}
    if m != _ovr_cache["mtime"]:
        try:
            with open(_OVR_FILE) as f:
                d = json.load(f)
            _ovr_cache.update(mtime=m, data=d if isinstance(d, dict) else {})
        except Exception:
            _ovr_cache.update(mtime=m, data={})
    return _ovr_cache["data"]


def _snap(data):
    return {k: data[k] for k in _SAMPLING_KEYS if k in data}


_patch_v2 = _patch


def _patch(data):
    before = _snap(data)
    changed = _patch_v2(data)
    kw = data.get("chat_template_kwargs") or {}
    mode = "thinking" if kw.get("enable_thinking") is True else "nothinking"
    sec = _load_override().get(mode) or {}
    for k, v in (sec.get("if_missing") or {}).items():
        if data.get(k) is None:
            data[k] = v
            changed = True
    for k, v in (sec.get("force") or {}).items():
        if data.get(k) != v:
            data[k] = v
            changed = True
    if os.path.exists(_LOG_FLAG):
        try:
            rec = {"ts": _time.strftime("%Y-%m-%dT%H:%M:%SZ", _time.gmtime()), "mode": mode,
                   "tools": len(data.get("tools") or []), "tool_choice": data.get("tool_choice"),
                   "stream": bool(data.get("stream")), "before": before, "after": _snap(data)}
            with open(_LOG_FILE, "a") as f:
                f.write(json.dumps(rec) + "\n")
        except Exception:
            pass
    return changed


class ThinkBudget:
    def __init__(self, app):
        self.app = app

    async def __call__(self, scope, receive, send):
        if (
            scope.get("type") != "http"
            or scope.get("method") != "POST"
            or not scope.get("path", "").endswith("/chat/completions")
        ):
            return await self.app(scope, receive, send)

        chunks = []
        more = True
        while more:
            message = await receive()
            if message["type"] != "http.request":
                # Client went away before the body arrived; hand on as is.
                pending = [message]

                async def replay_disconnect():
                    return pending.pop(0) if pending else await receive()

                return await self.app(scope, replay_disconnect, send)
            chunks.append(message.get("body", b""))
            more = message.get("more_body", False)
        body = b"".join(chunks)

        try:
            data = json.loads(body)
            if isinstance(data, dict) and _patch(data):
                body = json.dumps(data).encode()
                headers = [
                    (k, v) for k, v in scope.get("headers", []) if k.lower() != b"content-length"
                ]
                headers.append((b"content-length", str(len(body)).encode()))
                scope = dict(scope, headers=headers)
        except Exception:
            pass

        sent = False

        async def replay():
            nonlocal sent
            if not sent:
                sent = True
                return {"type": "http.request", "body": body, "more_body": False}
            return await receive()

        return await self.app(scope, replay, send)
