/**
 * Categories store — lazy-loads the bundled `categories.json` via the
 * `categories_data` Tauri command and exposes derived helpers for tile
 * rendering, filtering, and per-package lookup.
 *
 * Singleton: import `categories` from this module everywhere; the store
 * fetches once per process and caches the result.
 */

import { categoriesData } from "$lib/api";
import { settings } from "$lib/stores/settings.svelte";
import type { CategoriesData, PackageKind } from "$lib/types";

interface CategoryTile {
  slug: string;
  label: string;
  icon: string;
  count: number;
}

class CategoriesStore {
  data: CategoriesData | null = $state(null);
  loading: boolean = $state(false);
  error: string | null = $state(null);

  private loadPromise: Promise<void> | null = null;

  /** Lazy-load on first access. Safe to call repeatedly — only fetches once. */
  async ensureLoaded(): Promise<void> {
    if (this.data || this.loadPromise) {
      return this.loadPromise ?? Promise.resolve();
    }
    this.loading = true;
    this.error = null;
    this.loadPromise = (async () => {
      try {
        this.data = await categoriesData();
      } catch (e) {
        this.error = `Failed to load categories: ${String(e)}`;
      } finally {
        this.loading = false;
        this.loadPromise = null;
      }
    })();
    return this.loadPromise;
  }

  /**
   * Categories of a given token, in declared order. Returns an empty array if
   * the token is uncategorized OR the data isn't loaded yet.
   */
  categoriesOf(name: string, kind: PackageKind): string[] {
    if (!this.data) return [];
    const map = kind === "cask" ? this.data.casks : this.data.formulae;
    return map[name] ?? [];
  }

  /**
   * Sorted tile list for the Discover grid. `developer-tools` first (largest),
   * `uncategorized` always last, the rest by descending count.
   */
  tiles = $derived.by<CategoryTile[]>(() => {
    if (!this.data) return [];
    const counts = new Map<string, number>();
    for (const cats of Object.values(this.data.casks)) {
      for (const c of cats) counts.set(c, (counts.get(c) ?? 0) + 1);
    }
    for (const cats of Object.values(this.data.formulae)) {
      for (const c of cats) counts.set(c, (counts.get(c) ?? 0) + 1);
    }
    const out: CategoryTile[] = [];
    for (const [slug, meta] of Object.entries(this.data.categories)) {
      out.push({ slug, label: meta.label, icon: meta.icon, count: counts.get(slug) ?? 0 });
    }
    out.sort((a, b) => {
      if (a.slug === "uncategorized") return 1;
      if (b.slug === "uncategorized") return -1;
      return b.count - a.count;
    });
    return out;
  });

  /**
   * All tokens that belong to a given category, with their kind. Used by the
   * filtered view after a tile click. Returns deterministic alphabetical order.
   */
  tokensInCategory(slug: string): Array<{ name: string; kind: PackageKind }> {
    if (!this.data) return [];
    const out: Array<{ name: string; kind: PackageKind }> = [];
    for (const [name, cats] of Object.entries(this.data.casks)) {
      if (cats.includes(slug)) out.push({ name, kind: "cask" });
    }
    for (const [name, cats] of Object.entries(this.data.formulae)) {
      if (cats.includes(slug)) out.push({ name, kind: "formula" });
    }
    out.sort((a, b) => a.name.localeCompare(b.name));
    return out;
  }

  /** Pretty label for a slug. Falls back to the slug if data isn't loaded. */
  labelOf(slug: string): string {
    return this.data?.categories[slug]?.label ?? slug;
  }

  /**
   * Phase 13 — central gate for all category-driven UI. When the master
   * AI Features toggle is OFF, every consumer should treat categories
   * as if they don't exist (donut chart hidden, chip filters hidden,
   * Discover tile grid hidden, PackageDetail Categories row hidden).
   *
   * Components read this as `categories.visible` and `{#if categories.visible}`
   * around any category-rendering branch.
   */
  get visible(): boolean {
    return settings.effective.aiFeaturesEnabled;
  }
}

export const categories = new CategoriesStore();
