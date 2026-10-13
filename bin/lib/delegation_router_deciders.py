"""Deciders: everything that produces routing signals for one request.

A decider never raises. It returns
  {"decider": {"id", "version"}, "signals": [...], "latency_ms", "cost_usd",
   "error"?: str, "input"?: "excerpt"|"full"}
and an empty signal list means "undecidable": the policy then uses the
caller's declared default and says so."""

import hashlib
import json
import re
import time
import urllib.error
import urllib.request

from delegation_config import ROOT
from delegation_router import (
    DECISION_TOKENS,
    credential_for,
    credential_required,
    endpoint_for,
    excerpt,
)

PROMPT_FILE = ROOT / "config/router-prompt.v1.md"
MAX_DECISION_OUTPUT_TOKENS = 60
LLM_CONFIDENCE = 0.8
JSON_OBJECT = re.compile(r"\{.*\}", re.S)


class NoneDecider:
    """Rules only: no network, no judgement, always the caller's default."""

    id = "none"
    version = "rules-only"

    def decide(self, body, feats, input_mode="excerpt"):
        return {
            "decider": {"id": self.id, "version": self.version},
            "signals": [],
            "latency_ms": 0,
            "cost_usd": 0.0,
        }


class LlmDecider:
    """LLM-as-router: one cheap chat completion through one of the user's own
    HTTP profiles answers the difficulty/tags question from the prompt file."""

    id = "llm"

    def __init__(self, profile_key, profile, meta, timeout=3, opener=None, env=None):
        self.profile_key = profile_key
        self.profile = profile
        self.meta = meta
        self.timeout = timeout
        self.opener = opener or urllib.request.urlopen
        self.env = env
        self.prompt = PROMPT_FILE.read_text()
        self.version = (
            profile["model"]
            + "+"
            + hashlib.sha256(self.prompt.encode()).hexdigest()[:8]
        )

    def request_body(self, text):
        body = {
            "model": self.profile["model"],
            "messages": [
                {"role": "system", "content": self.prompt},
                {"role": "user", "content": "DATA\n" + text + "\nEND DATA"},
            ],
            "temperature": 0,
            "max_tokens": MAX_DECISION_OUTPUT_TOKENS,
            "stream": False,
        }
        if self.meta.get("json_mode"):
            body["response_format"] = {"type": "json_object"}
        adapter = self.profile["adapter"]
        if adapter == "deepseek-api":
            body["reasoning_effort"] = "low"
            body["thinking"] = {"type": "enabled"}
        elif adapter == "token-plan-openai":
            body["reasoning_effort"] = "low"
        return body

    def decide(self, body, feats, input_mode="excerpt"):
        started = time.monotonic()
        result = {
            "decider": {"id": self.id, "version": self.version},
            "signals": [],
            "latency_ms": 0,
            "cost_usd": 0.0,
            "input": input_mode,
        }

        def fail(reason):
            result["latency_ms"] = int((time.monotonic() - started) * 1000)
            result["error"] = reason
            return result

        token = credential_for(self.profile, self.env)
        if credential_required(self.profile) and not token:
            return fail("missing credentials for decider profile " + self.profile_key)
        text = excerpt(body, input_mode)
        payload = json.dumps(self.request_body(text)).encode()
        headers = {"Content-Type": "application/json", "Accept": "application/json"}
        if token:
            headers["Authorization"] = "Bearer " + token
        request = urllib.request.Request(
            endpoint_for(self.profile), data=payload, headers=headers, method="POST"
        )
        try:
            with self.opener(request, timeout=self.timeout) as response:
                raw = response.read(1_000_000)
        except urllib.error.HTTPError as error:
            return fail("decider http %d" % error.code)
        except (urllib.error.URLError, TimeoutError, OSError, ValueError):
            return fail("decider unreachable or timed out")
        try:
            data = json.loads(raw)
            content = data["choices"][0]["message"]["content"]
            if isinstance(content, list):
                content = "".join(
                    part.get("text", "") for part in content if isinstance(part, dict)
                )
            match = JSON_OBJECT.search(content)
            answer = json.loads(match.group(0)) if match else None
            usage = data.get("usage") or {}
        except (ValueError, KeyError, IndexError, TypeError, AttributeError):
            return fail("decider returned malformed output")
        if (
            not isinstance(answer, dict)
            or type(answer.get("difficulty")) is not int
            or not 0 <= answer["difficulty"] <= 4
            or not isinstance(answer.get("tags", []), list)
            or any(t not in {"code", "math", "rare"} for t in answer.get("tags", []))
        ):
            return fail("decider answer outside the schema")
        tags = {t: 0.0 for t in ("code", "math", "rare")}
        for t in answer.get("tags", []):
            tags[t] = 1.0
        level = answer["difficulty"]
        result["signals"] = [
            {
                "kind": "scale",
                "key": "difficulty",
                "expectation": level,
                "confidence": LLM_CONFIDENCE,
                "range": [0, 4],
                "distribution": [{"level": level, "p": 1.0}],
            },
            {"kind": "tags", "key": "tags", "tags": tags},
        ]
        result["reason"] = str(answer.get("reason", ""))[:200]
        in_tokens = usage.get("prompt_tokens") or DECISION_TOKENS
        out_tokens = usage.get("completion_tokens") or MAX_DECISION_OUTPUT_TOKENS
        price = self.meta.get("price")
        if price:
            result["cost_usd"] = round(
                in_tokens * price["in"] / 1e6 + out_tokens * price["out"] / 1e6, 8
            )
        result["usage"] = {"input": in_tokens, "output": out_tokens}
        result["latency_ms"] = int((time.monotonic() - started) * 1000)
        return result


def build(kind, c, decider_cfg, profile_meta_fn, timeout=None, opener=None, env=None):
    """Construct the decider named by the configuration (or an override)."""
    if kind == "none":
        return NoneDecider()
    if kind == "llm":
        key = decider_cfg.get("profile", c["router"]["default"])
        profile = c["profiles"][key]
        return LlmDecider(
            key,
            profile,
            profile_meta_fn(key, profile),
            timeout=timeout or decider_cfg.get("timeout", 3),
            opener=opener,
            env=env,
        )
    raise ValueError("decider kind not available in this release: " + str(kind))
