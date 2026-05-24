#!/usr/bin/env python3
"""
brew-browser — catalog enrichment via Anthropic Haiku 4.5.

Reads the bundled Homebrew catalog (Phase 12a output at
`src-tauri/data/catalog/{formula,cask}.json.gz`), diffs against prior
enrichment state, batches new/changed tokens through Claude Haiku 4.5,
and writes `src-tauri/data/enrichment.json.gz`.

Two prompt tiers:
  - Tier A — friendly_name + summary (~$3-5 against Haiku for the
    ~5000 tokens with thin or missing desc).
  - Tier B — use_cases + similar + tags (~$10-15 against Haiku for
    all 16000 tokens).

Designed to run offline (manually or by cron). NEVER invoked from
inside the brew-browser app — all rendering is from the bundled
enrichment.json.gz that the build step bakes into the binary.

Cost guard: passing no flag prints help and exits — you must
opt in with `--tier-a`, `--tier-b`, or `--all`. This is intentional;
running both tiers costs ~$20 against the user's Anthropic API.

Usage:
    python enrich.py                  # print help + exit (no API call)
    python enrich.py --help           # explicit help (no API call)
    python enrich.py --tier-a         # Tier A only (~$3-5)
    python enrich.py --tier-b         # Tier B only (~$10-15)
    python enrich.py --all            # both tiers (~$13-20)
    python enrich.py --tier-a --dry-run   # diff only, no LLM calls

Environment (loaded from `tools/enrich/.env`):
    ANTHROPIC_API_KEY=sk-ant-...      # REQUIRED for non-dry-run
    ENRICH_MODEL=claude-haiku-4-5-20251001
    ENRICH_BATCH_SIZE=50
    ENRICH_LIMIT=0
    ENRICH_DRY_RUN=0
"""
from __future__ import annotations

import argparse
import gzip
import hashlib
import json
import os
import sys
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable

from dotenv import load_dotenv

# ─────────────────────────────────────────────────────────────────────────────
# Paths
# ─────────────────────────────────────────────────────────────────────────────
SCRIPT_DIR = Path(__file__).resolve().parent
REPO_ROOT = SCRIPT_DIR.parent.parent
CATALOG_DIR = REPO_ROOT / "src-tauri" / "data" / "catalog"
FORMULA_GZ = CATALOG_DIR / "formula.json.gz"
CASK_GZ = CATALOG_DIR / "cask.json.gz"
OUTPUT_PATH = REPO_ROOT / "src-tauri" / "data" / "enrichment.json.gz"
STATE_PATH = SCRIPT_DIR / "state" / "last-snapshot.json"
LOG_PATH = SCRIPT_DIR / "state" / "cron.log"
PROMPT_TIER_A = (SCRIPT_DIR / "prompts" / "tier-a-friendly.txt").read_text()
PROMPT_TIER_B = (SCRIPT_DIR / "prompts" / "tier-b-features.txt").read_text()

# ─────────────────────────────────────────────────────────────────────────────
# Defaults & caps (mirror the Rust side's field-length caps)
# ─────────────────────────────────────────────────────────────────────────────
DEFAULT_BATCH_SIZE = 50
DEFAULT_MODEL = "claude-haiku-4-5-20251001"

FRIENDLY_NAME_MAX = 100  # Rust cap is 100; prompt asks for 50
SUMMARY_MAX = 1024  # Rust cap is 1024; prompt asks for 250
USE_CASE_MAX = 200
USE_CASES_MAX_COUNT = 5
SIMILAR_MAX_COUNT = 50  # Rust cap; prompt asks for 3-5
TAG_MAX = 30
TAGS_MAX_COUNT = 12

# Per-batch cost guesstimates (rough — token-count varies).
# Tier A: ~200 in + ~80 out tokens/item × 50/batch = ~14k tokens/batch.
# Tier B: ~600 in (includes VALID_TOKENS slice) + ~200 out tokens/item.
COST_PER_1M_INPUT_HAIKU = 0.80  # $/1M input tokens (Haiku 4.5)
COST_PER_1M_OUTPUT_HAIKU = 4.00  # $/1M output tokens

# Friendly-name eligibility — packages with thin/missing desc benefit
# most from Tier A. Long, well-written brew descriptions can skip
# friendly_name and only get summary. We always enrich both for v1
# (simpler diff logic), but log how many were "thin".
THIN_DESC_LEN = 50


# ─────────────────────────────────────────────────────────────────────────────
# Data types
# ─────────────────────────────────────────────────────────────────────────────
@dataclass(frozen=True)
class Pkg:
    token: str
    kind: str  # "cask" | "formula"
    name: str  # display name (cask name[0] or formula name)
    desc: str

    def desc_hash(self) -> str:
        key = (self.name + "\x00" + self.desc).encode("utf-8")
        return hashlib.sha256(key).hexdigest()[:16]

    def display_for_prompt(self) -> str:
        d = (self.desc or "").strip().replace("\n", " ")[:200]
        return f"{self.token}: {d}"


# ─────────────────────────────────────────────────────────────────────────────
# Catalog loading
# ─────────────────────────────────────────────────────────────────────────────
def load_catalog() -> list[Pkg]:
    """Read the bundled formula + cask catalogs straight from .gz."""
    if not FORMULA_GZ.exists() or not CASK_GZ.exists():
        raise SystemExit(
            f"catalog missing: {FORMULA_GZ} / {CASK_GZ}\n"
            f"run `python tools/catalog/fetch.py` first to bake a fresh catalog."
        )

    log(f"  loading {FORMULA_GZ.relative_to(REPO_ROOT)}")
    with gzip.open(FORMULA_GZ, "rb") as f:
        formulae = json.loads(f.read())
    log(f"  loading {CASK_GZ.relative_to(REPO_ROOT)}")
    with gzip.open(CASK_GZ, "rb") as f:
        casks = json.loads(f.read())

    pkgs: list[Pkg] = []
    for f in formulae:
        token = f.get("name") or ""
        if not token:
            continue
        desc = (f.get("desc") or "").strip()
        pkgs.append(Pkg(token=token, kind="formula", name=token, desc=desc))
    for c in casks:
        token = c.get("token") or ""
        if not token:
            continue
        names = c.get("name") or []
        name = names[0] if isinstance(names, list) and names else token
        desc = (c.get("desc") or "").strip()
        pkgs.append(Pkg(token=token, kind="cask", name=name, desc=desc))

    log(f"  total: {len(pkgs)} packages ({sum(1 for p in pkgs if p.kind=='formula')} formulae + {sum(1 for p in pkgs if p.kind=='cask')} casks)")
    thin = sum(1 for p in pkgs if len(p.desc) < THIN_DESC_LEN)
    log(f"  thin-desc (< {THIN_DESC_LEN} chars): {thin}")
    return pkgs


# ─────────────────────────────────────────────────────────────────────────────
# Diff state
# ─────────────────────────────────────────────────────────────────────────────
def load_prior_state() -> dict[str, str]:
    """token → desc_hash (same hash format the script writes)."""
    if not STATE_PATH.exists():
        return {}
    try:
        return json.loads(STATE_PATH.read_text())
    except Exception:
        log(f"  warning: state file unparseable, treating as fresh run: {STATE_PATH}")
        return {}


def write_state(pkgs: list[Pkg]) -> None:
    STATE_PATH.parent.mkdir(parents=True, exist_ok=True)
    if STATE_PATH.exists():
        STATE_PATH.replace(STATE_PATH.with_suffix(".json.bak"))
    state = {p.token: p.desc_hash() for p in pkgs}
    tmp = STATE_PATH.with_suffix(".json.tmp")
    tmp.write_text(json.dumps(state, indent=0, sort_keys=True))
    tmp.replace(STATE_PATH)


# ─────────────────────────────────────────────────────────────────────────────
# Output assembly (round-trip the existing enrichment.json.gz)
# ─────────────────────────────────────────────────────────────────────────────
def load_existing_output() -> dict:
    """Read the prior enrichment.json.gz. Returns an empty skeleton if
    missing OR the placeholder ("0.0.0-placeholder")."""
    if not OUTPUT_PATH.exists():
        return _empty_payload()
    try:
        with gzip.open(OUTPUT_PATH, "rb") as f:
            data = json.loads(f.read())
        if not isinstance(data, dict) or "entries" not in data:
            return _empty_payload()
        # placeholder bundles have no entries — treat as fresh.
        return data
    except Exception as e:
        log(f"  warning: existing enrichment.json.gz unreadable ({e}); starting fresh")
        return _empty_payload()


def _empty_payload() -> dict:
    return {
        "version": "0.0.0-placeholder",
        "generated_at": "",
        "model": "",
        "tiers": [],
        "entries": {},
    }


def write_output_gz(payload: dict) -> int:
    """Atomic-write gzip-9'd JSON. Returns compressed byte count."""
    raw = json.dumps(payload, separators=(",", ":"), sort_keys=True).encode("utf-8")
    compressed = gzip.compress(raw, compresslevel=9)
    OUTPUT_PATH.parent.mkdir(parents=True, exist_ok=True)
    tmp = OUTPUT_PATH.with_suffix(".gz.tmp")
    tmp.write_bytes(compressed)
    tmp.replace(OUTPUT_PATH)
    return len(compressed)


# ─────────────────────────────────────────────────────────────────────────────
# Diff against existing enrichment
# ─────────────────────────────────────────────────────────────────────────────
def needs_tier_a(existing_entry: dict | None, prior_hash: str | None, current_hash: str) -> bool:
    """A token needs Tier A enrichment when EITHER the hash changed
    (desc rewrite) OR the existing entry is missing friendly_name/summary."""
    if existing_entry is None:
        return True
    if not existing_entry.get("friendly_name") or not existing_entry.get("summary"):
        return True
    if prior_hash is None or prior_hash != current_hash:
        return True
    return False


def needs_tier_b(existing_entry: dict | None, prior_hash: str | None, current_hash: str) -> bool:
    """A token needs Tier B when EITHER hash changed OR the entry lacks
    any Tier B field (use_cases, similar, tags). Empty lists mean "no Tier B
    enrichment run yet"."""
    if existing_entry is None:
        return True
    has_b = (
        bool(existing_entry.get("use_cases"))
        or bool(existing_entry.get("similar"))
        or bool(existing_entry.get("tags"))
    )
    if not has_b:
        return True
    if prior_hash is None or prior_hash != current_hash:
        return True
    return False


# ─────────────────────────────────────────────────────────────────────────────
# LLM calls
# ─────────────────────────────────────────────────────────────────────────────
def build_tier_a_user_prompt(batch: list[Pkg]) -> str:
    lines = ["Generate friendly_name + summary for each of these Homebrew packages:\n"]
    for i, p in enumerate(batch, 1):
        lines.append(f"{i}. [{p.kind}] {p.display_for_prompt()}")
    return "\n".join(lines)


def build_tier_b_system_prompt(valid_tokens: list[str]) -> str:
    """Tier B system message embeds the prompt + a compact VALID_TOKENS slice
    so the LLM's `similar` suggestions stay in-vocab."""
    # We can't pass all 16000 tokens — too large. Pass a stratified sample:
    # take the first ~500 most-relevant (alphabetical for determinism, but
    # in production we'd ideally pass per-category neighbours). For v1 we
    # send a hard 500-token slice with the note that the parser will drop
    # anything not in the actual full token set.
    sampled = sorted(valid_tokens)[:500]
    valid_block = ", ".join(sampled)
    return PROMPT_TIER_B + "\n\nVALID_TOKENS (partial sample of 500 — the parser drops anything not in the full set):\n" + valid_block


def build_tier_b_user_prompt(batch: list[Pkg]) -> str:
    lines = ["Generate use_cases + similar + tags for each of these Homebrew packages:\n"]
    for i, p in enumerate(batch, 1):
        lines.append(f"{i}. [{p.kind}] {p.display_for_prompt()}")
    return "\n".join(lines)


def call_anthropic(system: str, user: str, model: str) -> str:
    import anthropic
    client = anthropic.Anthropic()
    resp = client.messages.create(
        model=model,
        max_tokens=8192,
        system=system,
        messages=[{"role": "user", "content": user}],
    )
    return "".join(block.text for block in resp.content if hasattr(block, "text"))


# ─────────────────────────────────────────────────────────────────────────────
# Parsing / validation (mirrors Rust caps; defense in depth)
# ─────────────────────────────────────────────────────────────────────────────
def parse_tier_a_response(raw: str) -> dict[str, dict]:
    """Parse the LLM's JSON-line reply into {token: {friendly_name, summary}}.
    Drops malformed lines silently."""
    out: dict[str, dict] = {}
    for line in raw.splitlines():
        line = line.strip()
        if not line or not line.startswith("{"):
            continue
        try:
            obj = json.loads(line)
            tok = obj.get("token")
            fn = obj.get("friendly_name")
            sm = obj.get("summary")
            if not isinstance(tok, str) or (fn is None and sm is None):
                continue
            entry: dict = {}
            if isinstance(fn, str) and fn.strip():
                entry["friendly_name"] = fn.strip()[:FRIENDLY_NAME_MAX]
            if isinstance(sm, str) and sm.strip():
                entry["summary"] = sm.strip()[:SUMMARY_MAX]
            if entry:
                out[tok] = entry
        except json.JSONDecodeError:
            continue
    return out


def parse_tier_b_response(raw: str, valid_token_set: set[str]) -> dict[str, dict]:
    """Parse the LLM's JSON-line reply into {token: {use_cases, similar, tags}}.
    Filters `similar` against `valid_token_set` to drop hallucinations."""
    out: dict[str, dict] = {}
    for line in raw.splitlines():
        line = line.strip()
        if not line or not line.startswith("{"):
            continue
        try:
            obj = json.loads(line)
            tok = obj.get("token")
            ucs = obj.get("use_cases", [])
            sim = obj.get("similar", [])
            tags = obj.get("tags", [])
            if not isinstance(tok, str):
                continue
            entry: dict = {}
            if isinstance(ucs, list):
                clean_ucs = [
                    s.strip()[:USE_CASE_MAX]
                    for s in ucs
                    if isinstance(s, str) and s.strip()
                ][:USE_CASES_MAX_COUNT]
                if clean_ucs:
                    entry["use_cases"] = clean_ucs
            if isinstance(sim, list):
                # Filter to valid tokens only; drop self-refs and dupes.
                clean_sim: list[str] = []
                seen: set[str] = set()
                for s in sim:
                    if not isinstance(s, str):
                        continue
                    s = s.strip()
                    if not s or s == tok or s in seen:
                        continue
                    if s not in valid_token_set:
                        continue
                    seen.add(s)
                    clean_sim.append(s)
                    if len(clean_sim) >= SIMILAR_MAX_COUNT:
                        break
                if clean_sim:
                    entry["similar"] = clean_sim
            if isinstance(tags, list):
                clean_tags: list[str] = []
                seen_t: set[str] = set()
                for t in tags:
                    if not isinstance(t, str):
                        continue
                    # Normalize: lowercase, hyphen-only.
                    t = t.strip().lower().replace(" ", "-").replace("_", "-")
                    if not t or t in seen_t:
                        continue
                    if len(t) > TAG_MAX:
                        t = t[:TAG_MAX]
                    # Reject anything with non-allowed chars.
                    if not all(c.isalnum() or c == "-" for c in t):
                        continue
                    seen_t.add(t)
                    clean_tags.append(t)
                    if len(clean_tags) >= TAGS_MAX_COUNT:
                        break
                if clean_tags:
                    entry["tags"] = clean_tags
            if entry:
                out[tok] = entry
        except json.JSONDecodeError:
            continue
    return out


# ─────────────────────────────────────────────────────────────────────────────
# Batching
# ─────────────────────────────────────────────────────────────────────────────
def chunked(seq: list[Pkg], n: int) -> Iterable[list[Pkg]]:
    for i in range(0, len(seq), n):
        yield seq[i : i + n]


# ─────────────────────────────────────────────────────────────────────────────
# Logging
# ─────────────────────────────────────────────────────────────────────────────
def log(msg: str) -> None:
    ts = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
    line = f"[{ts}] {msg}"
    print(line, flush=True)
    try:
        LOG_PATH.parent.mkdir(parents=True, exist_ok=True)
        with LOG_PATH.open("a") as f:
            f.write(line + "\n")
    except Exception:
        pass


# ─────────────────────────────────────────────────────────────────────────────
# Run a single tier
# ─────────────────────────────────────────────────────────────────────────────
def run_tier_a(
    candidates: list[Pkg],
    existing_entries: dict,
    batch_size: int,
    model: str,
    dry_run: bool,
) -> tuple[dict[str, dict], int]:
    """Returns (per-token updates, batches dispatched)."""
    log(f"Tier A — friendly_name + summary for {len(candidates)} tokens")
    if dry_run:
        log("  DRY RUN — skipping LLM calls")
        for p in candidates[:10]:
            log(f"    would enrich: [{p.kind}] {p.token}")
        if len(candidates) > 10:
            log(f"    … and {len(candidates) - 10} more")
        return ({}, 0)

    updates: dict[str, dict] = {}
    batches = list(chunked(candidates, batch_size))
    for i, batch in enumerate(batches, 1):
        log(f"  Tier A batch {i}/{len(batches)} ({len(batch)} items)")
        user = build_tier_a_user_prompt(batch)
        try:
            raw = call_anthropic(PROMPT_TIER_A, user, model)
        except Exception as e:
            log(f"    WARN: batch {i} failed: {type(e).__name__}: {e}")
            log(f"    skipping; rerun will retry")
            continue
        parsed = parse_tier_a_response(raw)
        log(f"    parsed {len(parsed)}/{len(batch)} items")
        for tok, fields in parsed.items():
            base = dict(existing_entries.get(tok, {}))
            base.update(fields)
            updates[tok] = base
    return (updates, len(batches))


def run_tier_b(
    candidates: list[Pkg],
    valid_token_set: set[str],
    existing_entries: dict,
    batch_size: int,
    model: str,
    dry_run: bool,
) -> tuple[dict[str, dict], int]:
    log(f"Tier B — use_cases + similar + tags for {len(candidates)} tokens")
    if dry_run:
        log("  DRY RUN — skipping LLM calls")
        for p in candidates[:10]:
            log(f"    would enrich: [{p.kind}] {p.token}")
        if len(candidates) > 10:
            log(f"    … and {len(candidates) - 10} more")
        return ({}, 0)

    system = build_tier_b_system_prompt(sorted(valid_token_set))
    updates: dict[str, dict] = {}
    batches = list(chunked(candidates, batch_size))
    for i, batch in enumerate(batches, 1):
        log(f"  Tier B batch {i}/{len(batches)} ({len(batch)} items)")
        user = build_tier_b_user_prompt(batch)
        try:
            raw = call_anthropic(system, user, model)
        except Exception as e:
            log(f"    WARN: batch {i} failed: {type(e).__name__}: {e}")
            log(f"    skipping; rerun will retry")
            continue
        parsed = parse_tier_b_response(raw, valid_token_set)
        log(f"    parsed {len(parsed)}/{len(batch)} items")
        for tok, fields in parsed.items():
            base = dict(existing_entries.get(tok, {}))
            base.update(fields)
            updates[tok] = base
    return (updates, len(batches))


# ─────────────────────────────────────────────────────────────────────────────
# Cost estimate
# ─────────────────────────────────────────────────────────────────────────────
def estimate_cost(tier_a_items: int, tier_b_items: int) -> str:
    # Rough averages: see comments above the constants.
    a_in = tier_a_items * 200
    a_out = tier_a_items * 80
    b_in = tier_b_items * 600
    b_out = tier_b_items * 200
    cost = (
        (a_in + b_in) / 1_000_000 * COST_PER_1M_INPUT_HAIKU
        + (a_out + b_out) / 1_000_000 * COST_PER_1M_OUTPUT_HAIKU
    )
    return f"${cost:.2f}"


# ─────────────────────────────────────────────────────────────────────────────
# CLI
# ─────────────────────────────────────────────────────────────────────────────
def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        prog="enrich.py",
        description=(
            "Generate LLM-enriched metadata for the bundled Homebrew catalog. "
            "ZERO RUNTIME LLM CALLS — output is baked into the app binary. "
            "Costs ~$3-20 against your Anthropic API key per FULL run; ~$0.05 per delta. "
            "DEFAULT (no flags) prints this help and exits — you must opt in with "
            "--tier-a, --tier-b, or --all."
        ),
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=(
            "Example workflows:\n"
            "  python enrich.py --tier-a --dry-run    # see what would be enriched (no cost)\n"
            "  python enrich.py --tier-a              # bake friendly names + summaries (~$3-5)\n"
            "  python enrich.py --tier-b              # bake use cases + similar + tags (~$10-15)\n"
            "  python enrich.py --all                 # both (~$13-20)\n"
        ),
    )
    p.add_argument(
        "--tier-a",
        action="store_true",
        help="Run Tier A (friendly_name + summary).",
    )
    p.add_argument(
        "--tier-b",
        action="store_true",
        help="Run Tier B (use_cases + similar + tags).",
    )
    p.add_argument(
        "--all",
        action="store_true",
        help="Run both tiers in one pass (~$13-20).",
    )
    p.add_argument(
        "--dry-run",
        action="store_true",
        help="Compute diff + cost estimate; do not call the LLM.",
    )
    p.add_argument(
        "--limit",
        type=int,
        default=0,
        help="Process at most N candidates per tier (testing).",
    )
    return p


def main() -> int:
    load_dotenv(SCRIPT_DIR / ".env")
    parser = build_parser()
    args = parser.parse_args()

    # Cost guard: no tier flags ⇒ print help and exit. NEVER quietly proceed.
    if not (args.tier_a or args.tier_b or args.all):
        parser.print_help()
        print(
            "\n  No tier flag provided — exiting without API call.\n"
            "  Use --tier-a, --tier-b, or --all to run the enrichment.",
            file=sys.stderr,
        )
        return 0

    do_a = args.tier_a or args.all
    do_b = args.tier_b or args.all
    dry_run = args.dry_run or os.environ.get("ENRICH_DRY_RUN", "0") == "1"
    limit = args.limit or int(os.environ.get("ENRICH_LIMIT", "0"))
    batch_size = int(os.environ.get("ENRICH_BATCH_SIZE", DEFAULT_BATCH_SIZE))
    model = os.environ.get("ENRICH_MODEL", DEFAULT_MODEL)

    if not dry_run and not os.environ.get("ANTHROPIC_API_KEY"):
        raise SystemExit(
            "ANTHROPIC_API_KEY not set.\n"
            "Copy tools/enrich/.env.example to tools/enrich/.env and paste your key, "
            "or pass --dry-run to compute diff + cost without calling the API."
        )

    log("=== brew-browser enrich ===")
    log(f"output: {OUTPUT_PATH}")
    log(f"model: {model}  batch_size: {batch_size}  dry_run: {dry_run}")
    log(f"tiers: {'A' if do_a else ''}{'B' if do_b else ''}")

    pkgs = load_catalog()
    pkg_by_token = {p.token: p for p in pkgs}

    prior = load_prior_state()
    log(f"prior state: {len(prior)} tokens")

    existing = load_existing_output()
    existing_entries: dict = existing.get("entries", {})
    log(f"existing enrichment: {len(existing_entries)} entries (version {existing.get('version','')})")

    # Compute per-tier candidates.
    a_candidates: list[Pkg] = []
    b_candidates: list[Pkg] = []
    for p in pkgs:
        cur_hash = p.desc_hash()
        prior_hash = prior.get(p.token)
        existing_entry = existing_entries.get(p.token)
        if do_a and needs_tier_a(existing_entry, prior_hash, cur_hash):
            a_candidates.append(p)
        if do_b and needs_tier_b(existing_entry, prior_hash, cur_hash):
            b_candidates.append(p)

    if limit > 0:
        a_candidates = a_candidates[:limit]
        b_candidates = b_candidates[:limit]
        log(f"  (limited each tier to {limit} for this run)")

    log(f"Tier A candidates: {len(a_candidates)}")
    log(f"Tier B candidates: {len(b_candidates)}")
    log(f"  estimated cost (Haiku 4.5): {estimate_cost(len(a_candidates) if do_a else 0, len(b_candidates) if do_b else 0)}")

    if not a_candidates and not b_candidates:
        log("no work to do — exiting clean")
        return 0

    # Run tiers.
    valid_token_set = {p.token for p in pkgs}
    all_updates: dict[str, dict] = {}
    batches_run = 0

    if do_a:
        updates, n = run_tier_a(a_candidates, existing_entries, batch_size, model, dry_run)
        batches_run += n
        for tok, fields in updates.items():
            base = dict(all_updates.get(tok, existing_entries.get(tok, {})))
            base.update(fields)
            all_updates[tok] = base

    if do_b:
        updates, n = run_tier_b(b_candidates, valid_token_set, existing_entries, batch_size, model, dry_run)
        batches_run += n
        for tok, fields in updates.items():
            base = dict(all_updates.get(tok, existing_entries.get(tok, {})))
            base.update(fields)
            all_updates[tok] = base

    log(f"updates: {len(all_updates)} tokens across {batches_run} batches")

    if dry_run:
        log("DRY RUN — no output written")
        return 0

    if not all_updates:
        log("no successful enrichments this run — leaving output untouched so next run retries")
        return 1

    # Merge updates into existing payload. Carry-forward semantics: previous
    # entries stay unless the catalog dropped that token. Removed tokens are
    # pruned so the file doesn't accumulate dead weight.
    merged: dict[str, dict] = {}
    fresh_tokens = {p.token for p in pkgs}
    for tok, entry in existing_entries.items():
        if tok in fresh_tokens:
            merged[tok] = entry
    for tok, entry in all_updates.items():
        merged[tok] = entry

    # Determine the effective tiers covered.
    tiers: list[str] = list(existing.get("tiers", []))
    if do_a and "A" not in tiers:
        tiers.append("A")
    if do_b and "B" not in tiers:
        tiers.append("B")
    tiers.sort()

    payload = {
        "version": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "generated_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "model": model,
        "tiers": tiers,
        "entries": dict(sorted(merged.items())),
    }

    compressed = write_output_gz(payload)
    log(
        f"wrote {OUTPUT_PATH} — {len(payload['entries'])} entries, {compressed:,} bytes gzipped"
    )

    # Update state. Record hashes only for tokens that survived in the
    # output (so a failed batch can retry next run).
    out_tokens = set(payload["entries"].keys())
    successful_pkgs = [p for p in pkgs if p.token in out_tokens]
    write_state(successful_pkgs)
    log(f"state updated → {STATE_PATH}  ({len(successful_pkgs)} tokens recorded)")

    return 0


if __name__ == "__main__":
    sys.exit(main())
