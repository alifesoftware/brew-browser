# brew-browser — enrich tool

Build-time tooling. Generates `src-tauri/data/enrichment.json.gz` from
the bundled Homebrew catalog (Phase 12a output), using Anthropic Haiku
4.5 to attach friendly names, expanded summaries, use-case bullets,
similar-package recommendations, and tech-stack tags to each token.

**Not runtime: this never runs from inside the brew-browser app.**
It runs offline, the output is committed, and the app reads the bundled
`enrichment.json.gz` via `include_bytes!`. **Zero LLM calls happen on
the user's machine** — every Anthropic API request is paid for by the
maintainer (or a fork's maintainer) at build time.

## What it produces

`src-tauri/data/enrichment.json.gz` — a gzipped JSON shaped like:

```json
{
  "version": "2026-05-24T12:00:00Z",
  "generated_at": "2026-05-24T12:00:00Z",
  "model": "claude-haiku-4-5-20251001",
  "tiers": ["A", "B"],
  "entries": {
    "postgresql@14": {
      "friendly_name": "PostgreSQL 14",
      "summary": "Open-source object-relational database. Install when you need SQL with rich data types, ACID transactions, and extensibility for production workloads.",
      "use_cases": ["Run a local development database", "Host a self-hosted SaaS backend", "Power a JSONB-backed analytics warehouse"],
      "similar": ["mariadb", "mysql", "sqlite", "redis"],
      "tags": ["database", "sql", "server", "relational"]
    }
  }
}
```

The Rust backend `include_bytes!`s the gzip stream and parses it once
at startup (`src-tauri/src/enrichment/mod.rs`). There is no runtime
file dependency on this script after the build.

## When to run

After `tools/catalog/fetch.py` has refreshed the catalog (the catalog
is the source of truth for which tokens exist). Suggested cadence:

1. `python tools/catalog/fetch.py` — pulls fresh catalog, ~5 sec.
2. `python tools/enrich/enrich.py --tier-a` — only enriches the delta
   (~30-50 packages/week after the initial bulk run), ~$0.01-0.05.
3. Commit + push the new `catalog/*.json.gz` + `enrichment.json.gz`.

The script is diff-aware via `state/last-snapshot.json` — re-runs only
hit the LLM for tokens whose name or description changed since last
run, AND whose existing enrichment lacks the requested tier's fields.

## Setup

```sh
cd tools/enrich
python3 -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
cp .env.example .env
# edit .env, paste your ANTHROPIC_API_KEY
```

The `.env` file is `.gitignored` — secrets never commit.

## Cost guard (read this first)

**The script never makes API calls unless you explicitly opt in.** Run
with no flags or `--help` to see the available tiers without spending
any money:

```sh
python enrich.py            # prints help, exits — zero API calls
python enrich.py --help     # same
```

To actually run enrichment you must pass one of:

| Flag        | What it does                                              | Approx cost |
|-------------|-----------------------------------------------------------|-------------|
| `--tier-a`  | friendly_name + summary for tokens with thin/missing desc | $3-5        |
| `--tier-b`  | use_cases + similar + tags for all tokens                 | $10-15      |
| `--all`     | both tiers in one pass                                    | $13-20      |
| `--dry-run` | (combined with above) compute diff + estimate, no API     | $0          |
| `--limit N` | (combined with above) cap candidates to N for testing     | scales      |

Costs are estimates against Claude Haiku 4.5 (~$0.80 in / $4.00 out per
1M tokens as of 2026-05). The delta cost on weekly cron runs is ~$0.05.

## Operational examples

```sh
# Preview what Tier A would enrich on the current catalog (zero cost):
python enrich.py --tier-a --dry-run

# Bake friendly names + summaries (initial run, ~$3-5):
python enrich.py --tier-a

# Bake use cases + similar + tags (initial run, ~$10-15):
python enrich.py --tier-b

# Both tiers in one pass (~$13-20):
python enrich.py --all

# Test with a tiny subset against the live API (~$0.01):
python enrich.py --tier-a --limit 20
```

## Diff state

`state/last-snapshot.json` records `token -> hash(name + desc)` for
every token successfully written to `enrichment.json.gz`. A token is
re-enriched when ANY of these are true:

- The hash changed (upstream rewrote the description).
- The existing entry is missing the requested tier's fields.
- The token is brand new.

Delete `state/last-snapshot.json` to force a full re-enrichment on the
next run (useful when you've tuned the prompt and want to re-bake).

## Prompts

Live as plain text in `prompts/`:

- `prompts/tier-a-friendly.txt` — Tier A system message.
- `prompts/tier-b-features.txt` — Tier B system message.

Edit them in place; the script picks them up on the next invocation.
The Tier B system message gets a 500-token slice of valid token names
appended at runtime so the LLM's `similar` suggestions stay in-vocab;
the parser also drops anything not in the full token set as a final
sanity check.

## Output safety

- Field-length caps are enforced in the parser (`friendly_name ≤ 100`,
  `summary ≤ 1024`, `use_case ≤ 200`, `tag ≤ 30`, `≤ 50 similar`).
  The Rust loader re-applies the same caps as defense-in-depth.
- `similar` is filtered against the full valid-token set; LLM
  hallucinations get silently dropped.
- `tags` are normalised to `[a-z0-9-]` and lowercased.

## What it does NOT do

- Does NOT touch `categories.json` (that's `tools/categorize/`).
- Does NOT make API calls at runtime — the app never imports the
  `anthropic` SDK.
- Does NOT support non-Anthropic providers in v1 (Tier B's prompt is
  Anthropic-tuned). Future versions may support OpenAI if asked.

## Caveats

- LLM output is heuristic. Spot-check a few entries after the first
  Tier A or Tier B run; bad outputs get a "Wrong?" link in the UI so
  users can report them upstream.
- New popular packages may take 24h to appear (the cron runs daily).
- This tool requires network: it talks to `api.anthropic.com`. The
  app itself never does — the bundled enrichment is the canonical
  read-only artifact.
