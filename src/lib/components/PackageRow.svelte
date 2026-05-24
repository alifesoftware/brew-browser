<script lang="ts">
  import ChevronRight from "@lucide/svelte/icons/chevron-right";
  import PackageIcon from "@lucide/svelte/icons/package";
  import Pill from "./Pill.svelte";
  import { iconCache } from "$lib/stores/iconCache.svelte";
  import { enrichment } from "$lib/stores/enrichment.svelte";
  import type { Package } from "$lib/types";

  interface Props {
    pkg: Package;
    selected?: boolean;
    onSelect?: (pkg: Package) => void;
  }

  let { pkg, selected = false, onSelect }: Props = $props();

  /** AI-enriched friendly name for this row's token, or null when the
   *  AI Features toggle is off / no enrichment entry. Called inline in
   *  markup — the underlying enrichment.friendlyName() is a sync Map.get(),
   *  no IPC, sub-microsecond, so we don't need a per-row $derived. */
  function friendlyOf(token: string): string | null {
    return enrichment.friendlyName(token);
  }

  // Per-row icon state. We keep this row-local rather than reading
  // iconCache.cache directly so the row can reflect "loading" before the
  // first resolve, and we don't recompute the Map lookup on every keystroke
  // in the Library filter.
  let iconDataUrl = $state<string | null>(null);
  let iconLoaded = $state(false);

  // Lazy-fetch on mount (and re-fetch if the row's pkg identity changes —
  // happens when the Library list re-keys on filter swap).
  //
  // Phase 8: gating now lives inside iconCache via pkg.iconSource — formulae
  // resolve to null immediately (iconSource.kind === "none") without an IPC
  // hop, so we can drive both kinds through the same path and let the store
  // route to cask_icon vs cask_icon_from_homepage. We still peek the cache
  // first to avoid a microtask on the hot path.
  $effect(() => {
    const token = pkg.name;
    // Synchronous peek first — avoids a microtask if cached.
    const cached = iconCache.peek(token);
    if (cached !== undefined) {
      iconDataUrl = cached;
      iconLoaded = true;
      return;
    }
    iconLoaded = false;
    iconDataUrl = null;
    let canceled = false;
    iconCache.getIcon(pkg).then((result) => {
      if (canceled) return;
      iconDataUrl = result;
      iconLoaded = true;
    });
    return () => { canceled = true; };
  });
</script>

<button
  class="row"
  class:selected
  aria-current={selected ? "true" : undefined}
  onclick={() => onSelect?.(pkg)}
>
  <span class="icon-slot" aria-hidden="true">
    {#if iconDataUrl}
      <img src={iconDataUrl} alt="" width="24" height="24" class="cask-icon" />
    {:else if pkg.iconSource.kind !== "none" && iconLoaded}
      <!-- tried, no icon — small neutral fallback so casks remain visually distinct from formulae -->
      <PackageIcon size={18} class="fallback-icon" />
    {/if}
    <!-- packages with iconSource.kind === "none" (formulae, casks with no app + no homepage)
         intentionally render an empty 24px slot so the name column stays aligned -->
  </span>
  <span class="name truncate" title={pkg.name}>
    <span class="name-text">{pkg.name}</span>
    {#if friendlyOf(pkg.name)}
      <span class="friendly-subtitle">{friendlyOf(pkg.name)}</span>
    {/if}
  </span>
  <span class="version truncate">{pkg.installedVersion ?? pkg.stableVersion ?? "—"}</span>
  <span class="kind"><Pill tone={pkg.kind === "formula" ? "formula" : "cask"}>{pkg.kind}</Pill></span>
  <span class="outdated">
    {#if pkg.outdated}
      <span class="upgrade" title="Upgrade available">
        <ChevronRight size={14} />
        {pkg.stableVersion ?? ""}
      </span>
    {/if}
  </span>
</button>

<style>
  .row {
    display: grid;
    /* minmax(0, 1fr) on the name column — without it, long names like
       "claude-code-templates" expand the 1fr beyond its share, pushing the
       version/type/outdated columns rightward inconsistently across rows. */
    grid-template-columns: 24px minmax(0, 1fr) 120px 80px 120px;
    align-items: center;
    width: 100%;
    min-height: 36px;
    padding: 0 var(--space-3);
    gap: var(--space-3);
    color: var(--color-text-primary);
    font-size: var(--text-body);
    border-bottom: 1px solid var(--color-border);
    text-align: left;
    transition: background-color var(--motion-duration-fast) var(--motion-ease-out);
  }
  .row > * { min-width: 0; overflow: hidden; }

  /* Narrow-window responsive (detail panel open + small window): drop the
     trailing "Outdated" column (5th). Library row layout has 5 cells:
     icon / name / version / type / outdated. */
  @media (max-width: 880px) {
    .row {
      grid-template-columns: 24px minmax(0, 1fr) 120px 80px;
    }
    .row > :nth-child(5) { display: none; }
  }
  /* Tightest: also drop Version (3rd col). Leave icon / NAME / TYPE. */
  @media (max-width: 720px) {
    .row {
      grid-template-columns: 24px minmax(0, 1fr) 80px;
    }
    .row > :nth-child(3),
    .row > :nth-child(5) { display: none; }
  }
  .row:hover { background: var(--color-surface-sunken); }
  .row.selected {
    background: var(--color-selection-strong);
    color: var(--color-text-inverse);
  }
  .row.selected .version,
  .row.selected .upgrade { color: inherit; }

  .icon-slot {
    width: 24px;
    height: 24px;
    display: inline-flex;
    align-items: center;
    justify-content: center;
    flex-shrink: 0;
    /* no transition / no fade-in — designSystem §6 says terminal-style instant for lists */
  }
  .cask-icon {
    width: 24px;
    height: 24px;
    border-radius: 4px; /* matches macOS app-icon rounding-feel without faking the squircle */
    object-fit: contain;
    display: block;
  }
  .row :global(.fallback-icon) {
    color: var(--color-text-muted);
    opacity: 0.6;
  }
  .row.selected :global(.fallback-icon) {
    color: var(--color-text-inverse);
    opacity: 0.7;
  }

  /* Vertical flex container so the optional AI-enriched friendly_name
     subtitle (Phase 13) stacks below the raw token. Children manage
     their own truncation; the parent's .truncate class is overridden
     to allow the column. */
  .name {
    font-weight: var(--fw-medium);
    display: flex;
    flex-direction: column;
    align-items: flex-start;
    min-width: 0;
    white-space: normal;
  }
  .name-text {
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
    max-width: 100%;
  }
  .friendly-subtitle {
    display: block;
    font-size: var(--text-caption);
    color: var(--color-text-muted);
    font-weight: var(--fw-regular, 400);
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
    max-width: 100%;
    line-height: 1.2;
    margin-top: 1px;
  }
  /* Selected-row variant: keep the subtitle legible against the strong
     selection background by tinting toward the inverse text color. */
  .row.selected .friendly-subtitle {
    color: var(--color-text-inverse);
    opacity: 0.75;
  }
  .version { font-size: var(--text-body-sm); color: var(--color-text-secondary); }
  .upgrade {
    display: inline-flex;
    align-items: center;
    gap: 2px;
    font-size: var(--text-caption);
    color: var(--color-warning-strong); /* darker amber for AA on light surface (was --color-warning at 2.9:1) */
  }
</style>
