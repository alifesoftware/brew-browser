<script lang="ts">
  import SearchIcon from "@lucide/svelte/icons/search";
  import XIcon from "@lucide/svelte/icons/x";
  import Pill from "./Pill.svelte";
  import Input from "./Input.svelte";
  import LoadingState from "./LoadingState.svelte";
  import EmptyState from "./EmptyState.svelte";
  import { search } from "$lib/stores/search.svelte";
  import { ui } from "$lib/stores/ui.svelte";
  import { packages } from "$lib/stores/packages.svelte";
  import { categories } from "$lib/stores/categories.svelte";
  import { discover } from "$lib/stores/discover.svelte";
  import { resolveCategoryIcon } from "$lib/util/categoryIcon";
  import type { PackageKind, SearchHit } from "$lib/types";

  // Lazy-load categories on mount. The store guards against duplicate fetches.
  categories.ensureLoaded();

  function openHit(h: { name: string; kind: PackageKind }) {
    ui.selectPackage(h.name, h.kind);
  }

  function handleKey(e: KeyboardEvent) {
    if (e.key === "Enter") {
      search.run(search.query);
    }
  }

  function fmt(n: number): string {
    return n.toLocaleString();
  }

  /**
   * Search-results filtered by the currently-selected category chips. A package
   * matches if ANY of its categories are in the active selection (OR logic),
   * which matches user intent for "narrow down by domain".
   */
  function chipMatch(name: string, kind: PackageKind): boolean {
    if (!discover.hasFilter) return true;
    const cats = categories.categoriesOf(name, kind);
    for (const c of cats) {
      if (discover.selectedCategories.has(c)) return true;
    }
    return false;
  }

  let allHits = $derived<SearchHit[]>(
    [
      ...(search.results?.formulae ?? []),
      ...(search.results?.casks ?? []),
    ].filter((h) => chipMatch(h.name, h.kind)),
  );

  /**
   * Browse-mode list (no search query): union of all packages whose categories
   * intersect the selected chips. Sorted alphabetically for stable scan order.
   */
  let browseItems = $derived.by<Array<{ name: string; kind: PackageKind }>>(() => {
    if (!discover.hasFilter || !categories.data) return [];
    const set = new Set<string>();
    const out: Array<{ name: string; kind: PackageKind }> = [];
    for (const slug of discover.selectedCategories) {
      for (const pkg of categories.tokensInCategory(slug)) {
        const key = `${pkg.kind}:${pkg.name}`;
        if (!set.has(key)) {
          set.add(key);
          out.push(pkg);
        }
      }
    }
    out.sort((a, b) => a.name.localeCompare(b.name));
    return out;
  });

  /** Header label for the filtered browse view. */
  let browseTitle = $derived.by(() => {
    if (discover.selectedCategories.size === 1) {
      const [slug] = discover.selectedCategories;
      return categories.labelOf(slug);
    }
    return `${discover.selectedCategories.size} categories`;
  });
</script>

<section class="discover">
  <header class="panel-head" data-tauri-drag-region>
    <h1>Discover</h1>
  </header>

  <div class="search-bar">
    <Input
      bind:value={search.query}
      variant="search"
      placeholder="Search the Homebrew index…"
      ariaLabel="Search Homebrew"
      onInput={(v) => search.setQuery(v)}
      onKeydown={handleKey}
    />
    {#if search.recent.length > 0 && !search.results && !search.query && !discover.hasFilter}
      <div class="recent">
        <span class="uppercase-label">Recent</span>
        <ul>
          {#each search.recent as r (r)}
            <li><button onclick={() => search.run(r)}>{r}</button></li>
          {/each}
        </ul>
      </div>
    {/if}

    <!-- Phase 13: chip bar hidden when the AI Features toggle is off
         (categories are LLM-generated). Search results below still
         render normally because they don't depend on categories. -->
    {#if categories.visible && discover.hasFilter}
      <div class="chip-bar" aria-label="Active category filters">
        {#each [...discover.selectedCategories] as slug (slug)}
          {@const Icon = resolveCategoryIcon(
            categories.data?.categories[slug]?.icon ?? "HelpCircle",
          )}
          <button
            class="chip on"
            onclick={() => discover.toggle(slug)}
            aria-label={`Remove ${categories.labelOf(slug)} filter`}
          >
            <Icon size={12} />
            <span>{categories.labelOf(slug)}</span>
            <XIcon size={12} />
          </button>
        {/each}
        <button class="chip-clear" onclick={() => discover.clear()}>Clear</button>
      </div>
    {/if}
  </div>

  <div class="results">
    {#if search.loading}
      <LoadingState rows={6} label="Searching…" />
    {:else if search.error}
      <EmptyState title="Search failed" body={search.error}>
        {#snippet icon()}<SearchIcon size={48} />{/snippet}
      </EmptyState>
    {:else if search.results && allHits.length === 0}
      <EmptyState
        title={discover.hasFilter
          ? `No "${search.results.query}" results in the selected categories.`
          : `Nothing matches "${search.results.query}".`}
        body={discover.hasFilter
          ? "Try removing a chip or broadening the search term."
          : "Try a shorter or different term."}
      >
        {#snippet icon()}<SearchIcon size={48} />{/snippet}
      </EmptyState>
    {:else if search.results}
      <!-- Search-results mode wins over category browsing -->
      <ul class="list" aria-label="Search results">
        {#each allHits as h (h.name + h.kind)}
          {@const installed = h.installed || packages.isInstalled(h.name, h.kind)}
          <li>
            <button class="row row--with-desc" onclick={() => openHit(h)}>
              <span class="name truncate">{h.name}</span>
              <span class="kind"><Pill tone={h.kind === "formula" ? "formula" : "cask"}>{h.kind}</Pill></span>
              <span class="desc truncate text-muted">{h.description ?? ""}</span>
              <span class="installed">
                {#if installed}<Pill tone="success">installed</Pill>{/if}
              </span>
            </button>
          </li>
        {/each}
      </ul>
    {:else if categories.visible && discover.hasFilter}
      <!-- Chip-filtered browse mode. Phase 13: hidden when AI toggle off
           (no categories means no chip filter UI). -->
      <div class="cat-header">
        <h2>{browseTitle}</h2>
        <span class="text-muted">{fmt(browseItems.length)} packages</span>
      </div>
      {#if browseItems.length === 0}
        <EmptyState title="No packages match this filter." body="">
          {#snippet icon()}<SearchIcon size={48} />{/snippet}
        </EmptyState>
      {:else}
        <ul class="list" aria-label={`Packages in ${browseTitle}`}>
          {#each browseItems as h (h.name + h.kind)}
            {@const installed = packages.isInstalled(h.name, h.kind)}
            <li>
              <button class="row row--no-desc" onclick={() => openHit(h)}>
                <span class="name truncate">{h.name}</span>
                <span class="kind"><Pill tone={h.kind === "formula" ? "formula" : "cask"}>{h.kind}</Pill></span>
                <span class="installed">
                  {#if installed}<Pill tone="success">installed</Pill>{/if}
                </span>
              </button>
            </li>
          {/each}
        </ul>
      {/if}
    {:else if categories.visible && categories.loading && categories.tiles.length === 0}
      <LoadingState rows={4} label="Loading categories…" />
    {:else if categories.visible && categories.error}
      <EmptyState title="Categories unavailable" body={categories.error}>
        {#snippet icon()}<SearchIcon size={48} />{/snippet}
      </EmptyState>
    {:else if categories.visible}
      <!-- Default: category tile grid. Phase 13: hidden when AI toggle
           off. The empty state below covers the toggled-off case. -->
      <div class="cat-intro">
        <p class="text-muted">
          Browse {fmt(
            Object.keys(categories.data?.casks ?? {}).length +
              Object.keys(categories.data?.formulae ?? {}).length,
          )} packages by category, or type a query above to search.
        </p>
      </div>
      <div class="tile-grid" role="grid" aria-label="Categories">
        {#each categories.tiles as t (t.slug)}
          {@const Icon = resolveCategoryIcon(t.icon)}
          <button
            class="tile"
            role="gridcell"
            onclick={() => discover.selectOnly(t.slug)}
            aria-label={`${t.label} — ${fmt(t.count)} packages`}
          >
            <span class="tile-icon"><Icon size={24} /></span>
            <span class="tile-label">{t.label}</span>
            <span class="tile-count">{fmt(t.count)}</span>
          </button>
        {/each}
      </div>
    {:else}
      <!-- Phase 13: AI features off — invite the user to search since
           the category tile grid is hidden. -->
      <EmptyState
        title="Type a query to search the Homebrew index"
        body="Category browsing is hidden because AI features are turned off in Settings &rarr; Appearance."
      >
        {#snippet icon()}<SearchIcon size={48} />{/snippet}
      </EmptyState>
    {/if}
  </div>
</section>

<style>
  .discover { display: flex; flex-direction: column; min-height: 0; height: 100%; }
  .panel-head {
    display: flex; align-items: center; padding: var(--space-4);
    border-bottom: 1px solid var(--color-border);
  }
  .search-bar {
    padding: var(--space-4);
    border-bottom: 1px solid var(--color-border);
    display: flex;
    flex-direction: column;
    gap: var(--space-3);
  }
  .search-bar :global(.wrap) { width: 100%; max-width: 480px; }

  .recent { display: flex; gap: var(--space-3); align-items: center; }
  .recent ul { display: flex; gap: var(--space-2); flex-wrap: wrap; }
  .recent button {
    padding: var(--space-1) var(--space-2);
    background: var(--color-surface-sunken);
    border-radius: var(--radius-sm);
    font-size: var(--text-body-sm);
    color: var(--color-text-secondary);
  }
  .recent button:hover { color: var(--color-text-primary); }

  /* ── chip bar ─────────────────────────────────────────── */
  .chip-bar {
    display: flex;
    flex-wrap: wrap;
    gap: var(--space-2);
    align-items: center;
  }
  .chip {
    display: inline-flex;
    align-items: center;
    gap: 6px;
    padding: 2px var(--space-2);
    height: 22px;
    border-radius: var(--radius-full);
    border: 1px solid var(--color-border);
    background: var(--color-surface-sunken);
    color: var(--color-text-secondary);
    font-size: var(--text-body-sm);
    font-weight: var(--fw-medium);
    line-height: 1;
    cursor: pointer;
    transition: background 0.12s ease, border-color 0.12s ease, color 0.12s ease;
  }
  .chip:hover { color: var(--color-text-primary); }
  .chip.on {
    background: var(--color-brand-subtle);
    border-color: var(--color-brand);
    color: var(--color-text-primary);
  }
  .chip-clear {
    padding: 2px var(--space-2);
    height: 22px;
    border-radius: var(--radius-sm);
    color: var(--color-text-muted);
    font-size: var(--text-body-sm);
    background: transparent;
  }
  .chip-clear:hover { color: var(--color-text-primary); }

  /* ── results ─────────────────────────────────────────── */
  .results { flex: 1; overflow-y: auto; min-height: 0; }
  .list { display: flex; flex-direction: column; }

  .row {
    align-items: center;
    gap: var(--space-3);
    width: 100%;
    padding: var(--space-2) var(--space-3);
    min-height: 36px;
    text-align: left;
    color: var(--color-text-primary);
    font-size: var(--text-body);
    border-bottom: 1px solid var(--color-border);
    display: grid;
  }
  /* Two row layouts: with-description (search) and no-description (chip-filtered
     browse). Two important details:
       1. Flexible columns use minmax(0, Nfr), not bare Nfr, because each row is
          its own grid container and bare `1fr` = `minmax(auto, 1fr)` lets long
          names expand the name column past its share.
       2. The installed column is a FIXED 90px, not `auto`. With auto, the cell
          collapses when no pill is present, and the leftover space rebalances
          across the fr columns — which shifts the kind cell horizontally between
          installed-vs-not rows. Fixed width keeps every row's kind cell at the
          same x-position. */
  .row--with-desc { grid-template-columns: minmax(0, 1fr) 80px minmax(0, 2fr) 90px; }
  .row--no-desc   { grid-template-columns: minmax(0, 1fr) 80px 90px; }
  .row:hover { background: var(--color-surface-sunken); }
  .name { font-weight: var(--fw-medium); }
  .desc { font-size: var(--text-body-sm); }
  .installed { justify-self: end; min-width: 0; }

  /* ── Phase 9: category tile grid ─────────────────────────── */
  .cat-intro {
    padding: var(--space-4) var(--space-4) 0 var(--space-4);
    font-size: var(--text-body-sm);
  }
  .tile-grid {
    display: grid;
    grid-template-columns: repeat(auto-fill, minmax(180px, 1fr));
    gap: var(--space-3);
    padding: var(--space-4);
  }
  .tile {
    display: flex;
    flex-direction: column;
    align-items: flex-start;
    gap: var(--space-2);
    padding: var(--space-3);
    background: var(--color-surface-sunken);
    border: 1px solid var(--color-border);
    border-radius: var(--radius-md);
    text-align: left;
    color: var(--color-text-primary);
    transition: background 0.12s ease, border-color 0.12s ease, transform 0.12s ease;
    cursor: pointer;
  }
  .tile:hover {
    background: var(--color-surface);
    border-color: var(--color-accent);
    transform: translateY(-1px);
  }
  .tile:focus-visible {
    outline: 2px solid var(--color-accent);
    outline-offset: 2px;
  }
  .tile-icon { color: var(--color-accent); display: inline-flex; }
  .tile-label { font-weight: var(--fw-medium); font-size: var(--text-body); }
  .tile-count { font-size: var(--text-body-sm); color: var(--color-text-secondary); }

  .cat-header {
    display: flex;
    align-items: baseline;
    gap: var(--space-3);
    padding: var(--space-3) var(--space-4);
    border-bottom: 1px solid var(--color-border);
  }
  .cat-header h2 {
    font-size: var(--text-h3, 1.05rem);
    font-weight: var(--fw-medium);
    margin: 0;
  }
</style>
