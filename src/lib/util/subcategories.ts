/**
 * Sub-categories — a PURE DERIVATION over the existing `categories.json`.
 *
 * RECON VERDICT (see Feature #6 spec): there is NO nested / hierarchical
 * sub-category data and NO sub-category field anywhere. `categories.json` is
 * strictly flat. The ONE genuine, already-in-data second-level signal is
 * MULTI-LABEL MEMBERSHIP: ~3463 of 15974 tokens carry more than one category.
 * So within a selected category X, members are sub-grouped by their OTHER
 * co-assigned category slugs — a 100%-data-derived drill-down, no commands,
 * no subprocess, no catalog refetch.
 *
 * HONEST WEAKNESS (surfaced in the UI, never hidden): co-occurrence does not
 * cleanly partition the big categories — developer-tools is ~65% solo,
 * graphics ~89% solo. Every category therefore needs a "General <Label>"
 * bucket (= members carrying ONLY the selected slug), which is frequently the
 * LARGEST sub-group. The UI labels sub-groups as "<Selected> + <Other>" (and
 * "General <Selected>" for the solo bucket) so we never imply a true taxonomy
 * tree the data doesn't have.
 *
 * PARITY: the native (Swift) build implements the IDENTICAL derivation over
 * its own in-memory `categories.json` (Categories.swift `subgroups(in:)`).
 * Both shells MUST agree on:
 *   1. the sub-group KEY for every member (a co-occurring slug, or the
 *      {@link GENERAL_KEY} sentinel for solo members),
 *   2. the LABEL form ("<Selected Label> + <Other Label>", and
 *      "General <Selected Label>" for the sentinel),
 *   3. membership — a member with N other categories appears under each of
 *      those N sub-groups; deduped WITHIN a sub-group, NOT across; solo
 *      members go only to the general bucket,
 *   4. ordering — descending item count, tie-break by key slug ascending,
 *      with the general bucket PINNED LAST,
 *   5. the Linux cask exclusion (Tauri/Linux only; native is macOS-only).
 *
 * Sub-grouping is only defined for a SINGLE selected category. Multi-chip and
 * search-filtered views stay flat (the caller suppresses sub-grouping there).
 */

import type { CategoriesData, PackageKind } from "$lib/types";

/** Sentinel key for the "solo" bucket — members carrying ONLY the selected
 *  category slug. Chosen to never collide with a real category slug (no
 *  category in `categories.json` is named "__general__"). */
export const GENERAL_KEY = "__general__";

/** The catch-all slug. It is NEVER a co-occurring sub-group bucket — exactly as
 *  `categories.tiles`/`allCategories` sink it. A member tagged `[X, uncategorized]`
 *  is therefore treated as solo-in-X (→ general), matching native
 *  `CategoryCatalog.subgroups(in:)` (`Categories.swift`). Real data has such
 *  tokens (e.g. `translate-shell` = `[terminal, uncategorized]`), so without
 *  this the two shells would disagree on a live bucket. */
const UNCATEGORIZED_SLUG = "uncategorized";

/** One member token within a sub-group. */
export interface SubgroupMember {
  name: string;
  kind: PackageKind;
}

/**
 * One sub-group within a selected category. `key` is the co-occurring
 * category slug, or {@link GENERAL_KEY} for the solo bucket. `label` is the
 * display string ("<Selected> + <Other>" or "General <Selected>"). `items`
 * are the member tokens, deduped within this sub-group, alphabetically
 * sorted for stable scan order.
 */
export interface Subgroup {
  key: string;
  label: string;
  items: SubgroupMember[];
}

/**
 * Group the members of `selectedSlug` by their OTHER co-assigned category
 * slugs.
 *
 * Algorithm (must match native exactly):
 *   - Walk casks then formulae (casks skipped when `excludeCasks`).
 *   - A member belongs iff `selectedSlug` is in its category array.
 *   - Its OTHER slugs (every distinct slug except `selectedSlug` and the
 *     `uncategorized` catch-all) each get the member added to that slug's
 *     bucket.
 *   - A member with NO other slugs (solo) goes to the {@link GENERAL_KEY}
 *     bucket.
 *   - Within a bucket a token appears at most once (dedup by name+kind);
 *     across buckets a cross-tagged token intentionally repeats.
 *   - Each bucket's items are sorted by name (localeCompare).
 *   - Buckets are ordered by descending item count, tie-break by key slug
 *     ascending; the general bucket is PINNED LAST regardless of size.
 *
 * Labels resolve the pretty category names from `data.categories`; a missing
 * slug falls back to the raw slug (matches the store's `labelOf`).
 *
 * @param data the in-memory categories payload (null → empty result)
 * @param selectedSlug the single selected category slug
 * @param excludeCasks when true (Linux), cask members are omitted from every
 *        bucket and from the counts — matching the cask-free browse list
 */
export function subgroupsFor(
  data: CategoriesData | null,
  selectedSlug: string,
  excludeCasks: boolean,
): Subgroup[] {
  if (!data) return [];

  const selectedLabel = data.categories[selectedSlug]?.label ?? selectedSlug;
  // key → { items, seen } where `seen` dedups within the bucket.
  const buckets = new Map<string, { items: SubgroupMember[]; seen: Set<string> }>();

  const add = (key: string, member: SubgroupMember) => {
    let b = buckets.get(key);
    if (!b) {
      b = { items: [], seen: new Set() };
      buckets.set(key, b);
    }
    const dedupKey = `${member.kind}:${member.name}`;
    if (b.seen.has(dedupKey)) return;
    b.seen.add(dedupKey);
    b.items.push(member);
  };

  const consume = (map: Record<string, string[]>, kind: PackageKind) => {
    if (kind === "cask" && excludeCasks) return;
    for (const [name, cats] of Object.entries(map)) {
      if (!cats.includes(selectedSlug)) continue;
      // Distinct OTHER slugs (dedup the member's own array first so a token
      // double-listing a co-category doesn't double-add within the bucket).
      // `uncategorized` is never a co-occurring bucket (parity with native) —
      // a member whose only other slug is `uncategorized` is treated as solo.
      const others = new Set<string>();
      for (const c of cats) {
        if (c !== selectedSlug && c !== UNCATEGORIZED_SLUG) others.add(c);
      }
      if (others.size === 0) {
        add(GENERAL_KEY, { name, kind });
      } else {
        for (const other of others) add(other, { name, kind });
      }
    }
  };

  consume(data.casks, "cask");
  consume(data.formulae, "formula");

  const labelFor = (key: string): string => {
    if (key === GENERAL_KEY) return `General ${selectedLabel}`;
    const otherLabel = data.categories[key]?.label ?? key;
    return `${selectedLabel} + ${otherLabel}`;
  };

  const out: Subgroup[] = [];
  for (const [key, b] of buckets) {
    b.items.sort((a, z) => a.name.localeCompare(z.name));
    out.push({ key, label: labelFor(key), items: b.items });
  }

  out.sort((a, z) => {
    // General bucket pinned last regardless of size.
    if (a.key === GENERAL_KEY) return 1;
    if (z.key === GENERAL_KEY) return -1;
    // Descending item count, tie-break by key slug ascending.
    if (z.items.length !== a.items.length) return z.items.length - a.items.length;
    return a.key.localeCompare(z.key);
  });

  return out;
}
