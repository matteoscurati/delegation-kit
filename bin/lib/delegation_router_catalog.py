"""The model catalog and where its ladder comes from.

A third party places the models: Artificial Analysis publishes an
Intelligence Index (0–100, a composite of public evaluations) with coding
and math sub-indexes and list prices, for a few hundred models and their
reasoning settings. The kit turns that into the three rungs the policy uses
with one published rule — `index-bands-v1`: frontier within N points of the
best model of the day, mid within M, small below — and records the evidence
beside every row. The user's own declaration on a profile still wins.

Two ways to get a current ladder: the shipped `config/catalog.json`,
refreshed before each release; or `delegation-router catalog refresh` with
the user's own key, which writes `catalog.local.json` beside the key files
and takes precedence while it is newer. Neither happens on its own."""

import datetime
import json
import re
import urllib.error
import urllib.request

from delegation_config import ROOT, data_home, kit_version, read, atomic

AA_URL = "https://artificialanalysis.ai/api/v2/data/llms/models"
AA_ATTRIBUTION = "https://artificialanalysis.ai/"
AA_KEY_FILE = "artificial-analysis.env"
AA_KEY_VAR = "AA_API_KEY"
RULE = "index-bands-v1"
BANDS = {"frontier_within": 8, "mid_within": 20}
EFFORTS = ("none", "minimal", "low", "medium", "high", "xhigh", "max")
VARIANT = re.compile(r"^(?P<base>.*?)\s*\((?P<inside>[^()]*)\)\s*$")


def normalize(name):
    """Names compared with case, spaces, dots and dashes ignored."""
    return re.sub(r"[^a-z0-9]", "", str(name).lower())


def place(index, tiering):
    """One rung for one index under the bands the catalog records."""
    if index is None:
        return None
    top = tiering["top_index"]
    if index >= top - tiering["frontier_within"]:
        return "frontier"
    if index >= top - tiering["mid_within"]:
        return "mid"
    return "small"


VARIANT_WORDS = set(EFFORTS) | {"reasoning", "non-reasoning", "thinking"}


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
        key = normalize(parsed["family"] or parsed["base"])
        families.setdefault(key, {"by_name": normalize(parsed["base"]), "variants": {}})
        families[key]["variants"][parsed["variant"] or "default"] = parsed
    return families


def match(model_id, aa_name, families):
    """The family for a catalog model: its id against the family slugs, else
    the `aa_name` alias (or the id) against the measured base names. Exact
    only: a guess would place the wrong model."""
    wanted = normalize(model_id)
    if wanted in families:
        return wanted, "slug"
    wanted = normalize(aa_name or model_id)
    for key, family in families.items():
        if family["by_name"] == wanted:
            return key, "name"
    return None, None


def best_variant(variants):
    """The strongest reasoning setting a family was measured at."""
    order = {name: i for i, name in enumerate(EFFORTS)}
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
        new = {
            k: v
            for k, v in old.items()
            if k not in ("evidence", "price_source", "price_date")
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
    from delegation_router import _key_from_file

    value = env.get(key_var)
    if value:
        return value
    if key_var == AA_KEY_VAR:
        return _key_from_file(data_home() / "config" / AA_KEY_FILE, AA_KEY_VAR)
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
