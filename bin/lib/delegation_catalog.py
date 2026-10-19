"""The model catalog: which rung each model sits on, and why.

The shipped `config/catalog.json` places every model it can from the
Artificial Analysis Intelligence Index (0–100, a composite of public
evaluations, with coding and math sub-indexes and list prices) through one
published rule, `index-bands-v1`: frontier within N points of the best model
of the day, mid within M, small below. Every row records its evidence; a
model the board does not list keeps a hand placement marked as such, and a
profile's own `tier` wins over everything.

Two ways to a current ladder, neither automatic: the shipped file, refreshed
before each release; or `delegation-router catalog refresh` with the user's
own key, which writes `catalog.local.json` beside the key files and takes
precedence while it is at least as recent."""

import datetime
import functools
import json
import re
import urllib.error
import urllib.request

from delegation_config import (
    EFFORT_ORDER,
    PROFILE_ROUTING_FIELDS,
    ROOT,
    _number,
    atomic,
    data_home,
    kit_version,
    read,
)
from delegation_credentials import key_from_file


AA_URL = "https://artificialanalysis.ai/api/v2/data/llms/models"


AA_ATTRIBUTION = "https://artificialanalysis.ai/"


AA_KEY_FILE = "artificial-analysis.env"


AA_KEY_VAR = "AA_API_KEY"


RULE = "index-bands-v1"


BANDS = {"frontier_within": 8, "mid_within": 20}


VARIANT = re.compile(r"^(?P<base>.*?)\s*\((?P<inside>[^()]*)\)\s*$")


VARIANT_WORDS = set(EFFORT_ORDER) | {"reasoning", "non-reasoning", "thinking"}


# ---- the catalog in effect ---------------------------------------------------


@functools.lru_cache(maxsize=1)
def catalog():
    """The model catalog: the shipped `config/catalog.json`, overlaid by the
    user's own `catalog.local.json` (written by `delegation-router catalog
    refresh`) whenever that one is at least as recent. Read once per process."""
    shipped = read(ROOT / "config/catalog.json")
    shipped["catalog_source"] = "shipped"
    shipped["catalog_file"] = str(ROOT / "config/catalog.json")
    local_file = data_home() / "config" / "catalog.local.json"
    try:
        local = read(local_file)
        if _catalog_shape_ok(local) and str(local.get("catalog_version", "")) >= str(
            shipped["catalog_version"]
        ):
            merged = dict(shipped)
            merged["models"] = {**shipped["models"], **local["models"]}
            merged["catalog_version"] = local["catalog_version"]
            if local.get("tiering"):
                merged["tiering"] = local["tiering"]
            merged["catalog_source"] = "local"
            merged["catalog_file"] = str(local_file)
            return merged
    except (OSError, ValueError):
        pass
    return shipped


def _catalog_shape_ok(local):
    """A local overlay is used only when every row is an object and its
    tiering, if any, carries the three numbers the band rule reads; anything
    else is ignored rather than crashing every command that reads the
    catalog."""
    if not isinstance(local, dict) or not isinstance(local.get("models"), dict):
        return False
    if not all(isinstance(row, dict) for row in local["models"].values()):
        return False
    tiering = local.get("tiering")
    return not tiering or (
        isinstance(tiering, dict)
        and all(
            _number(tiering.get(key))
            for key in ("top_index", "frontier_within", "mid_within")
        )
    )


def normalize_name(name):
    """Names compared with case, spaces, dots and dashes ignored."""
    return re.sub(r"[^a-z0-9]", "", str(name).lower())


def catalog_row(cat, model):
    """The catalog row for a profile's model id: exact, else the row whose
    evidence names the same model once case, dots and dashes are ignored."""
    if model in cat["models"]:
        return cat["models"][model]
    wanted = normalize_name(model)
    for row in cat["models"].values():
        evidence = row.get("evidence") or {}
        if evidence.get("name") and normalize_name(evidence["name"]) == wanted:
            return row
    return None


def place(index, tiering):
    """One rung for one index under the bands the catalog records
    (`index-bands-v1`): frontier within N points of the best model of the
    day, mid within M, small below."""
    if index is None:
        return None
    top = tiering["top_index"]
    if index >= top - tiering["frontier_within"]:
        return "frontier"
    if index >= top - tiering["mid_within"]:
        return "mid"
    return "small"


def bar(tiering):
    """The two scores the bands start at, from the catalog in effect: mid at
    the best of the day minus M, frontier at the best minus N."""
    if not tiering:
        return None
    top = tiering["top_index"]
    return {
        "mid": round(top - tiering["mid_within"], 1),
        "frontier": round(top - tiering["frontier_within"], 1),
    }


def tier_floor(tier, tiering):
    """The score a tier placed by hand stands for: the bottom of its band."""
    b = bar(tiering)
    if b is None or tier is None:
        return None
    return {"small": 0.0, "mid": b["mid"], "frontier": b["frontier"]}.get(tier)


def score_for_effort(row, effort):
    """The index measured at the reasoning setting the profile runs at, else
    the row's own index."""
    evidence = row.get("evidence") or {}
    variants = evidence.get("variants") or {}
    if effort and effort in variants:
        return variants[effort]
    return evidence.get("index")


def tier_for_effort(row, effort, tiering):
    """A rung for the reasoning setting the profile runs at, when the
    evidence measured that setting; else the row's rung."""
    evidence = row.get("evidence") or {}
    variants = evidence.get("variants") or {}
    if effort and effort in variants and tiering:
        return place(variants[effort], tiering)
    return row.get("tier")


def profile_meta(key, p, cat=None):
    """Routing metadata for one profile: the profile's own declarations win,
    the catalog fills the rest, unknown models stay without tier or price."""
    cat = cat if cat is not None else catalog()
    row = catalog_row(cat, p["model"])
    base = row or {}
    declared = PROFILE_ROUTING_FIELDS & set(p)
    effort = p.get("parameters", {}).get("effort")
    evidence = base.get("evidence")
    tiering = cat.get("tiering")
    if "tier" in p:
        tier, tier_source = p["tier"], "profile"
        score = tier_floor(tier, tiering)
    elif evidence:
        tier = tier_for_effort(base, effort, tiering)
        tier_source = "%s:%s" % (evidence["source"], evidence["date"])
        score = score_for_effort(base, effort)
    else:
        tier, tier_source = base.get("tier"), ("hand" if row else "unknown")
        score = tier_floor(tier, tiering)
    return {
        "profile": key,
        "model": p["model"],
        "adapter": p["adapter"],
        "family": p.get("family"),
        "tier": tier,
        "tier_source": tier_source,
        # The index the policy compares with the request's minimum: measured
        # where the board has the model, the bottom of its band otherwise.
        "score": score,
        "code": p["code"] if "code" in p else base.get("code", False),
        "price": p["price"] if "price" in p else base.get("price"),
        "context": p["context"] if "context" in p else base.get("context"),
        "json_mode": p["json_mode"] if "json_mode" in p else base.get("json_mode"),
        "effort": effort,
        "metadata_source": (
            "profile" if declared else ("catalog" if row else "unknown")
        ),
        "catalog_version": cat["catalog_version"],
    }


# ---- refreshing it from Artificial Analysis -----------------------------------


def parse_row(row):
    """One Artificial Analysis model row → family slug, reasoning variant,
    indexes and prices. The variant is read from the name's parenthetical
    ("Claude Opus 5.5 (Xhigh, Default Fallback)" → xhigh; "(0902)" → none)
    and the family is the slug without that variant's suffix
    (`claude-opus-5-5-xhigh` → `claude-opus-5-5`; `qwen3-8-max` stays, its
    "max" being part of the name). Anything missing is None."""
    name = row.get("name") or ""
    slug = row.get("slug") or ""
    base, variant = name, None
    m = VARIANT.match(name)
    if m:
        parts = [part.strip().lower() for part in m.group("inside").split(",")]
        found = [part for part in parts if part in VARIANT_WORDS]
        if found:
            base, variant = m.group("base").strip(), found[0]
    family = slug
    if variant and slug.endswith("-" + variant):
        family = slug[: -len(variant) - 1]
    ev = row.get("evaluations") if isinstance(row.get("evaluations"), dict) else {}
    pricing = row.get("pricing") if isinstance(row.get("pricing"), dict) else {}

    def number(value):
        return (
            float(value)
            if isinstance(value, (int, float)) and not isinstance(value, bool)
            else None
        )

    return {
        "id": row.get("id"),
        "slug": slug,
        "family": family,
        "name": name,
        "base": base,
        "variant": variant,
        "creator": (row.get("model_creator") or {}).get("name")
        if isinstance(row.get("model_creator"), dict)
        else None,
        "index": number(ev.get("artificial_analysis_intelligence_index")),
        "coding_index": number(ev.get("artificial_analysis_coding_index")),
        "math_index": number(ev.get("artificial_analysis_math_index")),
        "price_in": number(pricing.get("price_1m_input_tokens")),
        "price_out": number(pricing.get("price_1m_output_tokens")),
    }


def group(rows):
    """Rows by family: keyed by normalized family slug (and, for rows without
    a slug, by normalized base name), each a dict variant → parsed row."""
    families = {}
    for row in rows:
        parsed = parse_row(row)
        if not parsed["name"] or parsed["index"] is None:
            continue
        key = normalize_name(parsed["family"] or parsed["base"])
        families.setdefault(
            key, {"by_name": normalize_name(parsed["base"]), "variants": {}}
        )
        families[key]["variants"][parsed["variant"] or "default"] = parsed
    return families


def match(model_id, aa_name, families):
    """The family for a catalog model: its id against the family slugs, else
    the `aa_name` alias (or the id) against the measured base names. Exact
    only: a guess would place the wrong model."""
    wanted = normalize_name(model_id)
    if wanted in families:
        return wanted, "slug"
    wanted = normalize_name(aa_name or model_id)
    for key, family in families.items():
        if family["by_name"] == wanted:
            return key, "name"
    return None, None


def best_variant(variants):
    """The strongest reasoning setting a family was measured at."""
    order = {name: i for i, name in enumerate(EFFORT_ORDER)}
    return max(variants.items(), key=lambda kv: (order.get(kv[0], -1), kv[1]["index"]))


def refresh(catalog, rows, today):
    """A new catalog from the shipped one and the Artificial Analysis rows:
    matched models get evidence, prices they lacked and a rung from the rule;
    unmatched models keep what they had and are listed."""
    families = group(rows)
    if not families:
        raise ValueError("no usable model rows in the Artificial Analysis response")
    top = max(
        parsed["index"]
        for family in families.values()
        for parsed in family["variants"].values()
    )
    tiering = {
        "rule": RULE,
        **BANDS,
        "top_index": top,
        "source": "artificialanalysis",
        "date": today,
        "attribution": AA_ATTRIBUTION,
    }
    models = {}
    unmatched = []
    for model_id, old in catalog["models"].items():
        # A price an earlier refresh took from the board is the board's to
        # update; a price written by hand is kept.
        from_board = str(old.get("price_source", "")).startswith("artificialanalysis")
        new = {
            k: v
            for k, v in old.items()
            if k not in ("evidence", "price_source", "price_date")
            and not (k == "price" and from_board)
        }
        key, how = match(model_id, old.get("aa_name"), families)
        if key is None:
            new["evidence"] = None
            unmatched.append(model_id)
            models[model_id] = new
            continue
        variant_name, best = best_variant(families[key]["variants"])
        new["evidence"] = {
            "source": "artificialanalysis",
            "name": best["base"],
            "aa_id": best["id"],
            "match": how,
            "index": best["index"],
            "variant": variant_name,
            "variants": {
                name: p["index"] for name, p in families[key]["variants"].items()
            },
            "coding_index": best["coding_index"],
            "math_index": best["math_index"],
            "date": today,
            "via": "api",
        }
        new["tier"] = place(best["index"], tiering)
        if (
            new.get("price") is None
            and best["price_in"] is not None
            and best["price_out"] is not None
        ):
            new["price"] = {"in": best["price_in"], "out": best["price_out"]}
            new["price_source"] = "artificialanalysis " + today
        models[model_id] = new
    return (
        {"catalog_version": today, "tiering": tiering, "models": models},
        unmatched,
    )


def aa_key(env, key_var=AA_KEY_VAR):
    """The user's Artificial Analysis key: the variable, else the key file."""
    value = env.get(key_var)
    if value:
        return value
    if key_var == AA_KEY_VAR:
        return key_from_file(data_home() / "config" / AA_KEY_FILE, AA_KEY_VAR)
    return None


def fetch(key, opener=None, timeout=30, url=AA_URL):
    """One GET to the models endpoint with the user's key. Raises ValueError
    with a reason that carries no key."""
    opener = opener or urllib.request.urlopen
    request = urllib.request.Request(
        url,
        headers={
            "x-api-key": key,
            "Accept": "application/json",
            "User-Agent": "delegation-kit/" + kit_version(),
        },
    )
    try:
        with opener(request, timeout=timeout) as response:
            data = json.loads(response.read(50_000_000))
    except urllib.error.HTTPError as error:
        raise ValueError("Artificial Analysis answered HTTP %d" % error.code)
    except (urllib.error.URLError, TimeoutError, OSError) as error:
        raise ValueError("Artificial Analysis unreachable: " + type(error).__name__)
    rows = data.get("data") if isinstance(data, dict) else data
    if not isinstance(rows, list):
        raise ValueError("unexpected Artificial Analysis response shape")
    return rows


def local_path():
    return data_home() / "config" / "catalog.local.json"


def write(catalog, shipped=False):
    """The refreshed catalog goes beside the key files, or — from a checkout,
    before a release — into the shipped file."""
    path = ROOT / "config/catalog.json" if shipped else local_path()
    atomic(path, catalog)
    return path


def today():
    return datetime.date.today().isoformat()


def describe(cat):
    """What `catalog show` prints: the ladder's source and every row's rung
    with where it came from."""
    tiering = cat.get("tiering") or {}
    rows = []
    for model_id, row in sorted(cat["models"].items()):
        evidence = row.get("evidence")
        rows.append(
            {
                "model": model_id,
                "tier": row.get("tier"),
                "tier_source": (
                    "%s:%s" % (evidence["source"], evidence["date"])
                    if evidence
                    else "hand"
                ),
                "index": evidence.get("index") if evidence else None,
                "variant": evidence.get("variant") if evidence else None,
                "code": row.get("code"),
                "price": row.get("price"),
                "context": row.get("context"),
            }
        )
    return {
        "catalog_version": cat["catalog_version"],
        "catalog_source": cat.get("catalog_source", "shipped"),
        "catalog_file": cat.get("catalog_file"),
        "tiering": tiering,
        "models": rows,
        "with_evidence": sum(1 for r in rows if r["tier_source"] != "hand"),
        "hand_placed": sum(1 for r in rows if r["tier_source"] == "hand"),
    }


def shipped():
    return read(ROOT / "config/catalog.json")


# ---- what the commands print --------------------------------------------------


def render_show(report):
    lines = [
        "catalog %s (%s: %s)"
        % (report["catalog_version"], report["catalog_source"], report["catalog_file"])
    ]
    t = report["tiering"]
    if t:
        lines.append(
            "  ladder: %s — frontier within %s of the best (%s), mid within %s; %s, %s"
            % (
                t.get("rule"),
                t.get("frontier_within"),
                t.get("top_index"),
                t.get("mid_within"),
                t.get("source"),
                t.get("date"),
            )
        )
    lines.append(
        "  %d models with third-party evidence, %d placed by hand"
        % (report["with_evidence"], report["hand_placed"])
    )
    for m in report["models"]:
        lines.append(
            "    %-26s %-9s %s%s"
            % (
                m["model"],
                m["tier"],
                m["tier_source"],
                " index %s (%s)" % (m["index"], m["variant"])
                if m["index"] is not None
                else "",
            )
        )
    return lines


def render_refresh(summary):
    unmatched = summary["unmatched"]
    return [
        "catalog refreshed → %s (%s): %d models placed from Artificial Analysis (top index %s), %d unmatched%s"
        % (
            summary["written"],
            summary["catalog_version"],
            summary["matched"],
            summary["tiering"]["top_index"],
            len(unmatched),
            ": " + ", ".join(unmatched) if unmatched else "",
        ),
        "  data: Artificial Analysis, " + summary["attribution"],
    ]
