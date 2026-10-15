"""Deciders: everything that produces routing signals for one request.

A decider never raises. It returns
  {"decider": {"id", "version"}, "signals": [...], "latency_ms", "cost_usd",
   "error"?: str, "input"?: "excerpt"|"full"}
and an empty signal list means "undecidable": the policy then uses the
caller's declared default and says so."""

import functools
import hashlib
import json
import os
import re
import time
import urllib.error
import urllib.request

from delegation_config import ROOT, SERVICE_DECIDERS, kit_version
from delegation_router import (
    DECISION_TOKENS,
    TAG_THRESHOLD,
    count,
    credential_for,
    credential_required,
    endpoint_for,
    estimate_cost,
    excerpt,
)

PROMPT_FILE = ROOT / "config/router-prompt.v1.md"
MAX_DECISION_OUTPUT_TOKENS = 60
LLM_CONFIDENCE = 0.8
JSON_OBJECT = re.compile(r"\{.*\}", re.S)


@functools.lru_cache(maxsize=1)
def prompt():
    """The decider prompt, read once per process; its hash is part of the
    decider version."""
    text = PROMPT_FILE.read_text()
    return text, hashlib.sha256(text.encode()).hexdigest()[:8]


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
        self.prompt, digest = prompt()
        self.version = profile["model"] + "+" + digest

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
            usage = data.get("usage") if isinstance(data.get("usage"), dict) else {}
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
        in_tokens = count(usage.get("prompt_tokens")) or DECISION_TOKENS
        out_tokens = count(usage.get("completion_tokens")) or MAX_DECISION_OUTPUT_TOKENS
        cost = estimate_cost(self.meta, in_tokens, out_tokens)
        if cost is not None:
            result["cost_usd"] = round(cost, 8)
        result["usage"] = {"input": in_tokens, "output": out_tokens}
        result["latency_ms"] = int((time.monotonic() - started) * 1000)
        return result


# ---- service deciders ---------------------------------------------------------
#
# Each one asks its service the router's question in that service's own
# vocabulary and reports back the same signals the policy reads. The service
# is called with the decider's own credential, never a profile's; the request
# carries the excerpt and nothing else.

SCALE_LEVELS = [
    (0, "Trivial: any competent small model answers this correctly"),
    (1, "Easy: routine task, standard knowledge, short reasoning"),
    (2, "Moderate: multi-step reasoning or specialised knowledge"),
    (3, "Hard: long reasoning chains, subtle traps, or expert-level knowledge"),
    (4, "Frontier: research-grade; most current language models fail this"),
]
SCALE_QUESTION = (
    "How much language-model reasoning capability is intrinsically required to "
    "answer this request correctly? Judge capability, not length."
)
STRONG_QUESTION = (
    "Does answering this request correctly require a frontier-class language "
    "model rather than a small or mid-size one?"
)
TAG_DESCRIPTIONS = {
    "code": "answering requires writing or repairing executable code",
    "math": "answering requires non-trivial calculation",
    "rare": "answering requires obscure or specialised knowledge",
}
SERVICE_DEFAULTS = {
    "sage": {
        "url": "https://sage.levanto.ai",
        "path": "/decide/batch",
        "credential_env": "SAGE_API_KEY",
        "price": {"in": 0.05, "out": 10.0},  # Levanto Developer list, 2026-10
        "timeout": 3,
    },
    "jev": {
        "url": "https://api.typesafe.ai/v1/systemone",
        "path": "",
        "credential_env": "TYPESAFE_API_KEY",
        "model": "jev-latest",
        "price": {"in": 0.042, "out": 0.0},  # TypeSafe list, 2026-10
        "timeout": 3,
    },
    "dipylon": {"path": "/decide", "credential_env": None, "price": None, "timeout": 2},
    "classifier": {"path": "", "credential_env": None, "price": None, "timeout": 2},
}


def band_mass(expectation, probabilities):
    """How much of a 0–4 distribution sits in the tier band the expectation
    lands in: ≥3 frontier, ≤1 small, 2 mid. The policy's confidence is the
    chance the band is right, not the chance of one exact level."""
    if not probabilities:
        return 0.5
    levels = list(enumerate(probabilities))
    if expectation >= 3:
        return sum(p for level, p in levels if level >= 3)
    if expectation < 1.5:
        return sum(p for level, p in levels if level <= 1)
    return sum(p for level, p in levels if level == 2)


def walk(value):
    """Every dict inside a JSON value, outermost first."""
    if isinstance(value, dict):
        yield value
        for v in value.values():
            yield from walk(v)
    elif isinstance(value, list):
        for v in value:
            yield from walk(v)


class ServiceDecider:
    """One JSON POST to a decision service. Subclasses give the payload and
    read the answer; everything else — credential, transport, the no-raise
    contract — is here."""

    id = "service"

    def __init__(self, cfg, timeout=None, opener=None, env=None):
        defaults = SERVICE_DEFAULTS[self.id]
        url = cfg.get("url", defaults.get("url"))
        if not url:
            # Reached through a `--decider` override: the configuration's own
            # decider is validated, an override of another kind is not.
            raise ValueError("router.decider.url is required for " + self.id)
        self.url = url.rstrip("/") + defaults["path"]
        self.credential_env = cfg.get("credential_env", defaults.get("credential_env"))
        self.model = cfg.get("model", defaults.get("model"))
        self.price = cfg["price"] if "price" in cfg else defaults.get("price")
        self.timeout = timeout or cfg.get("timeout", defaults.get("timeout", 3))
        self.opener = opener or urllib.request.urlopen
        self.env = os.environ if env is None else env
        self.version = self.id

    def credential(self):
        return self.env.get(self.credential_env) if self.credential_env else None

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

        if self.credential_env and not self.credential():
            return fail("missing credentials for decider: set " + self.credential_env)
        text = excerpt(body, input_mode)
        headers = {
            "Content-Type": "application/json",
            "Accept": "application/json",
            "User-Agent": "delegation-kit/" + kit_version(),
        }
        if self.credential():
            headers["Authorization"] = "Bearer " + self.credential()
        request = urllib.request.Request(
            self.url,
            data=json.dumps(self.payload(text, feats)).encode(),
            headers=headers,
            method="POST",
        )
        try:
            with self.opener(request, timeout=self.timeout) as response:
                data = json.loads(response.read(1_000_000))
        except urllib.error.HTTPError as error:
            return fail("decider http %d" % error.code)
        except (urllib.error.URLError, TimeoutError, OSError, ValueError):
            return fail("decider unreachable or timed out")
        try:
            signals, version, usage = self.parse(data, feats)
        except (KeyError, IndexError, TypeError, ValueError, AttributeError):
            return fail("decider returned malformed output")
        if version:
            result["decider"]["version"] = str(version)
        if not signals:
            return fail("decider gave no usable answer")
        result["signals"] = signals
        in_tokens, out_tokens = usage
        if in_tokens is not None:
            result["usage"] = {"input": in_tokens, "output": out_tokens or 0}
            cost = estimate_cost({"price": self.price}, in_tokens, out_tokens or 0)
            if cost is not None:
                result["cost_usd"] = round(cost, 8)
        result["latency_ms"] = int((time.monotonic() - started) * 1000)
        return result


class SageDecider(ServiceDecider):
    """Levanto Sage: one batch request with a 0–4 scale and a tags question
    (recipe "Model Router"). Answers are matched by shape, so either batch
    envelope the service has shipped is read."""

    id = "sage"

    def payload(self, text, feats):
        return {
            "reasoning": "off",
            "requests": [
                {
                    "content": text,
                    "questions": [
                        {
                            "id": "difficulty",
                            "kind": "scale",
                            "instructions": SCALE_QUESTION,
                            "levels": [
                                {"level": level, "description": description}
                                for level, description in SCALE_LEVELS
                            ],
                        },
                        {
                            "id": "tags",
                            "kind": "tags",
                            "instructions": "Which of these apply to answering the request correctly?",
                            "tags": [
                                {"id": tag, "name": description}
                                for tag, description in TAG_DESCRIPTIONS.items()
                            ],
                        },
                    ],
                }
            ],
        }

    def parse(self, data, feats):
        found = list(walk(data))
        signals = []
        scale = next(
            (
                d
                for d in found
                if "expectation" in d and isinstance(d.get("probabilities"), list)
            ),
            None,
        )
        if scale and scale["expectation"] is not None:
            probabilities = [float(p) for p in scale["probabilities"]]
            signals.append(
                {
                    "kind": "scale",
                    "key": "difficulty",
                    "expectation": float(scale["expectation"]),
                    "confidence": band_mass(float(scale["expectation"]), probabilities),
                    "range": [0, 4],
                    "distribution": [
                        {"level": level, "p": p}
                        for level, p in enumerate(probabilities)
                    ],
                }
            )
        tags = next(
            (
                d
                for d in found
                if isinstance(d.get("tags"), list)
                and d["tags"]
                and all(isinstance(t, dict) and "probability" in t for t in d["tags"])
            ),
            None,
        )
        if tags:
            signals.append(
                {
                    "kind": "tags",
                    "key": "tags",
                    "tags": {
                        str(t.get("id")): float(t["probability"])
                        for t in tags["tags"]
                        if t.get("probability") is not None
                    },
                }
            )
        meta = data.get("meta") if isinstance(data.get("meta"), dict) else {}
        usage = meta.get("usage") if isinstance(meta.get("usage"), dict) else {}
        return (
            signals,
            meta.get("model"),
            (count(usage.get("input_tokens")), count(usage.get("output_tokens"))),
        )


class JevDecider(ServiceDecider):
    """TypeSafe Jev (System One API): a 5-level score for difficulty, a noul
    for "needs a frontier model", nouls for code and rare. Jev is weak on
    numbers, so a request that carries any is never routed below mid."""

    id = "jev"

    def payload(self, text, feats):
        return {
            "state": text,
            "model": self.model,
            "questions": {
                "difficulty": {
                    "type": "score",
                    "instructions": SCALE_QUESTION,
                    "criteria": [description for _, description in SCALE_LEVELS],
                },
                "strong": {
                    "type": "noul",
                    "instructions": STRONG_QUESTION,
                    "criteria": {
                        "true": "Only a frontier-class model answers this correctly",
                        "false": "A small or mid-size model answers this correctly",
                    },
                },
                "code": {
                    "type": "noul",
                    "instructions": "Does answering this request require writing or repairing executable code?",
                },
                "rare": {
                    "type": "noul",
                    "instructions": "Does answering this request require obscure or specialised knowledge?",
                },
            },
        }

    def parse(self, data, feats):
        answers = data["answers"]
        signals = []
        score = answers.get("difficulty") or {}
        if score.get("score") is not None:
            probabilities = score.get("probabilities") or {}
            signals.append(
                {
                    "kind": "scale",
                    "key": "difficulty",
                    "expectation": float(score["score"]),
                    "confidence": float(score.get("confidence", 0.5)),
                    "range": [0, len(SCALE_LEVELS) - 1],
                    "distribution": [
                        {"level": int(level), "p": float(p)}
                        for level, p in probabilities.items()
                    ],
                }
            )
        strong = answers.get("strong") or {}
        if strong.get("noul") is not None:
            signals.append(
                {"kind": "yesno", "key": "strong", "p": float(strong["noul"])}
            )
        tags = {}
        for tag in ("code", "rare"):
            answer = answers.get(tag) or {}
            if answer.get("noul") is not None:
                tags[tag] = float(answer["noul"])
        if feats.get("has_numbers"):
            tags["math"] = TAG_THRESHOLD
        if tags:
            signals.append({"kind": "tags", "key": "tags", "tags": tags})
        usage = data.get("usage") if isinstance(data.get("usage"), dict) else {}
        return (
            signals,
            data.get("model"),
            (count(usage.get("input_tokens")), count(usage.get("output_tokens"))),
        )


class DipylonDecider(ServiceDecider):
    """Dipylon `/decide`: one yesno, "does this need a strong model?". A
    selective-use verdict other than `retain` halves the confidence; a 503
    (model loading) is undecidable like any other failure."""

    id = "dipylon"

    def payload(self, text, feats):
        return {
            "document": text,
            "prompt": {
                "type": "yesno",
                "key": "strong",
                "instructions": STRONG_QUESTION,
            },
        }

    def parse(self, data, feats):
        response = data["response"]
        p = float(response["probability"])
        # `probability` is read as P(yes) when the answer is yes; when the
        # answer is no it is whichever reading agrees with that answer.
        p_yes = p if response.get("answer") == "yes" else min(p, 1 - p)
        confidence = abs(p_yes - 0.5) * 2
        selective = (
            data.get("selective_use")
            if isinstance(data.get("selective_use"), dict)
            else {}
        )
        if selective.get("action") not in (None, "retain"):
            confidence *= 0.5
        meta = data.get("meta") if isinstance(data.get("meta"), dict) else {}
        binding = (
            selective.get("binding")
            if isinstance(selective.get("binding"), dict)
            else {}
        )
        version = str(meta.get("model") or "dipylon")
        if binding.get("artifact_id"):
            version += "+" + str(binding["artifact_id"])
        return (
            [{"kind": "yesno", "key": "strong", "p": p_yes, "confidence": confidence}],
            version,
            (None, None),
        )


class ClassifierDecider(ServiceDecider):
    """A local classifier behind `POST {text}`. Read: `difficulty` (0..1) or
    NVIDIA's `prompt_complexity_score`; `p_needs_strong`; `tags` as
    probabilities, or NVIDIA's `task_type_1` naming code; `confidence`."""

    id = "classifier"

    def payload(self, text, feats):
        return {"text": text}

    def parse(self, data, feats):
        signals = []
        confidence = float(data.get("confidence", 0.7))
        difficulty = data.get("difficulty", data.get("prompt_complexity_score"))
        if difficulty is not None:
            d = min(max(float(difficulty), 0.0), 1.0)
            signals.append(
                {
                    "kind": "scale",
                    "key": "difficulty",
                    "expectation": d * 4,
                    "confidence": confidence,
                    "range": [0, 4],
                }
            )
        if data.get("p_needs_strong") is not None:
            signals.append(
                {
                    "kind": "yesno",
                    "key": "strong",
                    "p": min(max(float(data["p_needs_strong"]), 0.0), 1.0),
                    "confidence": confidence,
                }
            )
        tags = {}
        if isinstance(data.get("tags"), dict):
            tags = {str(k): float(v) for k, v in data["tags"].items()}
        task = str(data.get("task_type_1", "")).lower()
        if "code" in task:
            tags["code"] = max(tags.get("code", 0.0), 1.0)
        if tags:
            signals.append({"kind": "tags", "key": "tags", "tags": tags})
        return signals, data.get("model") or "classifier", (None, None)


SERVICE_CLASSES = {
    "sage": SageDecider,
    "jev": JevDecider,
    "dipylon": DipylonDecider,
    "classifier": ClassifierDecider,
}


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
    if kind in SERVICE_DECIDERS:
        cfg = decider_cfg if decider_cfg.get("kind", "llm") == kind else {}
        return SERVICE_CLASSES[kind](cfg, timeout=timeout, opener=opener, env=env)
    raise ValueError("decider kind not available in this release: " + str(kind))
