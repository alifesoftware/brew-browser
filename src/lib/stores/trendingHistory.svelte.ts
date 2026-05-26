/**
 * trendingHistory.svelte.ts — v0.4.0
 *
 * Caches the opt-in trending-history endpoint payloads on the frontend.
 * Two slots:
 *
 *   1. `index` — the summary blob (top-N packages with velocity index
 *      + compact sparkline). Fetched once on Trending tab mount. Used
 *      by the trending list to render per-row inline sparklines from
 *      a single HTTP GET.
 *
 *   2. `seriesByKey` — per-package full series. Fetched on demand from
 *      PackageDetail. Keyed by `"{kind}:{name}"`.
 *
 * Every fetch path is gated by `enhancedTrendingEnabled` AND
 * `paranoidMode === false`. The store consults the settings store
 * before calling the IPC so the backend `FeatureDisabled`/`ParanoidModeBlocked`
 * errors are never the primary trigger — UI stays quiet when the user
 * hasn't opted in.
 *
 * Soft-fails: an IPC error sets `error` on the store but does NOT
 * throw to callers. Inline sparklines and detail charts simply don't
 * render — no toast, no drama. Failures are silent because the feature
 * is enrichment, not load-bearing.
 */

import { trendingHistoryFetch, trendingHistoryIndex } from "$lib/api";
import { settings } from "$lib/stores/settings.svelte";
import {
  isBrewError,
  type PackageKind,
  type TrendingHistoryIndex,
  type TrendingHistoryIndexEntry,
  type TrendingHistorySeries,
} from "$lib/types";

function keyOf(name: string, kind: PackageKind): string {
  return `${kind}:${name}`;
}

class TrendingHistoryStore {
  index: TrendingHistoryIndex | null = $state(null);
  /** Per-(kind,name) full series cache. Keys built via `keyOf`. */
  seriesByKey: Map<string, TrendingHistorySeries> = $state(new Map());

  loadingIndex: boolean = $state(false);
  /** Per-key in-flight markers — prevents redundant concurrent fetches
      when multiple components ask for the same package's series. */
  loadingSeriesKeys: Set<string> = $state(new Set());

  /** Last error from any fetch. UI generally ignores this (silent
      degrade) — exposed for diagnostics only. */
  error: string | null = $state(null);

  /** Index lookup table built lazily so repeated `entryFor` calls
      don't re-scan the array. Rebuilt whenever `index` changes. */
  #indexLookup: Map<string, TrendingHistoryIndexEntry> | null = null;

  /** Whether the toggle + paranoid combo allows fetching from the
      enhanced-trending endpoint. */
  get enabled(): boolean {
    return (
      settings.effective.enhancedTrendingEnabled === true &&
      settings.effective.paranoidMode === false
    );
  }

  /** Fetch the index blob if we haven't already (or if the existing
      copy is older than 6h — match the backend cache TTL).
      Idempotent and silent on failure. */
  async ensureIndexLoaded(): Promise<void> {
    if (!this.enabled) return;
    if (this.loadingIndex) return;
    // If we already have a fresh index, skip.
    if (this.index && this.index.cacheAgeSeconds < 6 * 60 * 60) return;

    this.loadingIndex = true;
    this.error = null;
    try {
      const fetched = await trendingHistoryIndex();
      this.index = fetched;
      this.#indexLookup = null; // bust the lookup cache
    } catch (e) {
      // Silent degrade — sparklines just don't show. Surface to
      // diagnostics only.
      this.error = isBrewError(e) ? e.code : String(e);
    } finally {
      this.loadingIndex = false;
    }
  }

  /** Sync lookup of an index entry by (name, kind). Returns `null` if
      the index isn't loaded yet or this package isn't in the top-N. */
  entryFor(name: string, kind: PackageKind): TrendingHistoryIndexEntry | null {
    if (!this.index) return null;
    if (!this.#indexLookup) {
      this.#indexLookup = new Map();
      for (const p of this.index.packages) {
        this.#indexLookup.set(keyOf(p.name, p.kind), p);
      }
    }
    return this.#indexLookup.get(keyOf(name, kind)) ?? null;
  }

  /** Sync sparkline lookup — short-circuit for inline list rendering. */
  sparklineFor(name: string, kind: PackageKind): number[] | null {
    return this.entryFor(name, kind)?.sparkline ?? null;
  }

  /** Sync velocity lookup. Prefers the server-precomputed value from
      the index blob (which the collector regenerated from the freshest
      data). Falls back to whatever the trending tab's TrendingEntry
      carries (computed by the backend from the rolling windows). */
  velocityFor(name: string, kind: PackageKind): number | null {
    return this.entryFor(name, kind)?.velocityIndex ?? null;
  }

  /** Fetch the full series for one package. Idempotent against the
      in-memory cache; the backend also caches 6h. */
  async ensureSeriesLoaded(name: string, kind: PackageKind): Promise<void> {
    if (!this.enabled) return;
    const key = keyOf(name, kind);
    if (this.loadingSeriesKeys.has(key)) return;
    if (this.seriesByKey.has(key)) return;

    this.loadingSeriesKeys.add(key);
    this.error = null;
    try {
      const fetched = await trendingHistoryFetch(name, kind);
      // Reassign the Map so $state picks up the change.
      this.seriesByKey = new Map(this.seriesByKey).set(key, fetched);
    } catch (e) {
      this.error = isBrewError(e) ? e.code : String(e);
    } finally {
      this.loadingSeriesKeys.delete(key);
    }
  }

  seriesFor(name: string, kind: PackageKind): TrendingHistorySeries | null {
    return this.seriesByKey.get(keyOf(name, kind)) ?? null;
  }
}

export const trendingHistory = new TrendingHistoryStore();
