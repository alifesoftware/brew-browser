<script lang="ts">
  import Boxes from "@lucide/svelte/icons/boxes";
  import Compass from "@lucide/svelte/icons/compass";
  import TrendingUp from "@lucide/svelte/icons/trending-up";
  import Archive from "@lucide/svelte/icons/archive";
  import Activity from "@lucide/svelte/icons/activity";
  import Server from "@lucide/svelte/icons/server";
  import Heart from "@lucide/svelte/icons/heart";

  import { ui } from "$lib/stores/ui.svelte";
  import { packages } from "$lib/stores/packages.svelte";
  import { activity } from "$lib/stores/activity.svelte";
  import { brewfiles } from "$lib/stores/brewfiles.svelte";
  import { services } from "$lib/stores/services.svelte";
  import { env } from "$lib/stores/env.svelte";
  import { normalizeServiceStatus } from "$lib/types";
  import { safeOpenUrl } from "$lib/util/url";
  import { SPONSOR_URL } from "$lib/util/donate";
  import type { SidebarSection } from "$lib/types";

  interface NavItem {
    id: SidebarSection;
    label: string;
    shortcut: string;
    icon: typeof Boxes;
  }

  const nav: NavItem[] = [
    { id: "library",   label: "Library",   shortcut: "⌘1", icon: Boxes },
    { id: "discover",  label: "Discover",  shortcut: "⌘2", icon: Compass },
    { id: "trending",  label: "Trending",  shortcut: "⌘3", icon: TrendingUp },
    { id: "snapshots", label: "Snapshots", shortcut: "⌘4", icon: Archive },
    { id: "services",  label: "Services",  shortcut: "⌘5", icon: Server },
    { id: "activity",  label: "Activity",  shortcut: "⌘6", icon: Activity },
  ];

  function badge(id: SidebarSection): string | null {
    if (id === "library") {
      const o = packages.outdated.length;
      return o > 0 ? String(o) : null;
    }
    if (id === "snapshots") {
      const n = brewfiles.list.length;
      return n > 0 ? String(n) : null;
    }
    if (id === "services") {
      const r = services.list.filter((s) => normalizeServiceStatus(s.status) === "started").length;
      return r > 0 ? String(r) : null;
    }
    if (id === "activity") {
      const r = activity.runningCount;
      return r > 0 ? String(r) : null;
    }
    return null;
  }

  function openSponsor() { void safeOpenUrl(SPONSOR_URL); }

  /**
   * Status dot color follows the spec in uxArchitecture.md §2:
   *   green  = ready (brew installed + idle)
   *   amber  = a write op is running
   *   red    = brew missing / unhealthy / probe failed
   *   muted  = first probe still in flight (no report yet)
   */
  const statusKind = $derived.by<"ready" | "running" | "missing" | "unknown">(() => {
    if (env.report === null) return "unknown";
    if (!env.installed) return "missing";
    if (activity.runningCount > 0) return "running";
    return "ready";
  });

  const statusTooltip = $derived.by(() => {
    const base = env.summary;
    if (activity.runningCount > 0) {
      const n = activity.runningCount;
      return `${base}\n${n} brew operation${n === 1 ? "" : "s"} running`;
    }
    return base;
  });

  function refreshEnv() {
    void env.refresh();
  }
</script>

<aside class="sidebar" aria-label="Primary navigation">
  <!--
    The brand wrapper is the sidebar's window-drag handle. Tauri's drag-region
    handler uses click-vs-drag detection, so the .brand button inside still
    fires its onclick (with an explicit opt-out for belt+suspenders).
  -->
  <header class="brand-wrap" data-tauri-drag-region>
    <button
      type="button"
      class="brand"
      class:active={ui.section === "dashboard"}
      aria-current={ui.section === "dashboard" ? "page" : undefined}
      onclick={() => ui.setSection("dashboard")}
      title="Dashboard (⌘0)"
      data-tauri-drag-region="false"
    >
      <span class="brand-mark" aria-hidden="true">🍺</span>
      <span class="brand-name">brew-browser</span>
    </button>
  </header>

  <nav>
    <ul>
      {#each nav as item (item.id)}
        {@const isActive = ui.section === item.id}
        {@const b = badge(item.id)}
        <li>
          <button
            class="nav-item"
            class:active={isActive}
            aria-current={isActive ? "page" : undefined}
            onclick={() => ui.setSection(item.id)}
            title={`${item.label} (${item.shortcut})`}
          >
            <span class="ico" aria-hidden="true"><item.icon size={16} /></span>
            <span class="label">{item.label}</span>
            {#if b}<span class="badge">{b}</span>{/if}
          </button>
        </li>
      {/each}
    </ul>
  </nav>

  <footer class="foot">
    <button
      type="button"
      class="status"
      class:status-ready={statusKind === "ready"}
      class:status-running={statusKind === "running"}
      class:status-missing={statusKind === "missing"}
      class:status-unknown={statusKind === "unknown"}
      title={statusTooltip}
      aria-label={statusTooltip}
      onclick={refreshEnv}
    >
      <span class="dot" aria-hidden="true"></span>
      <span class="status-label">{env.shortLabel}</span>
    </button>
    <button
      type="button"
      class="donate"
      title="Open GitHub Sponsors page in your browser"
      aria-label="Donate to brew-browser on GitHub Sponsors"
      onclick={openSponsor}
    >
      <Heart size={11} />
      <span>Donate</span>
    </button>
  </footer>
</aside>

<style>
  .sidebar {
    width: 200px;
    flex: none;
    background: var(--color-surface-raised);
    border-right: 1px solid var(--color-border);
    display: flex;
    flex-direction: column;
    min-height: 0;
  }
  .brand-wrap {
    border-bottom: 1px solid var(--color-border);
    /* Top padding clears the traffic-light cluster; the .brand button sits
       below the traffic lights at its natural sidebar width. Window dragging
       is handled by the separate .titlebar-drag-region overlay (+layout.svelte). */
    padding: 44px var(--space-2) var(--space-2) var(--space-2);
  }
  .brand {
    display: flex;
    align-items: center;
    gap: var(--space-2);
    width: 100%;
    padding: var(--space-2) var(--space-3);
    border-radius: var(--radius-md);
    font-weight: var(--fw-semibold);
    font-size: var(--text-body);
    color: var(--color-text-primary);
    text-align: left;
    cursor: pointer;
    transition: background-color var(--motion-duration-fast) var(--motion-ease-out);
  }
  .brand:hover { background: var(--color-surface-sunken); }
  .brand.active {
    background: var(--color-surface-sunken);
    color: var(--color-text-primary);
  }
  .brand-mark { font-size: 16px; }
  .brand-name { white-space: nowrap; }

  nav { flex: 1; padding: var(--space-2); overflow-y: auto; }
  ul { display: flex; flex-direction: column; gap: 1px; }

  .nav-item {
    display: flex;
    align-items: center;
    gap: var(--space-2);
    width: 100%;
    padding: var(--space-2) var(--space-3);
    border-radius: var(--radius-md);
    color: var(--color-text-secondary);
    font-size: var(--text-body);
    font-weight: var(--fw-medium);
    line-height: 1;
    text-align: left;
    transition: background-color var(--motion-duration-fast) var(--motion-ease-out);
  }
  .nav-item:hover { background: var(--color-surface-sunken); color: var(--color-text-primary); }
  .nav-item.active {
    background: var(--color-surface-sunken);
    color: var(--color-text-primary);
    font-weight: var(--fw-semibold);
  }
  .nav-item .label { flex: 1; }
  .ico { display: inline-flex; }
  .badge {
    display: inline-flex;
    align-items: center;
    justify-content: center;
    height: 16px;
    min-width: 16px;
    padding: 0 var(--space-1);
    border-radius: var(--radius-full);
    background: var(--color-brand);
    color: var(--color-text-inverse);
    font-size: var(--text-caption);
    font-weight: var(--fw-semibold);
  }

  .foot {
    border-top: 1px solid var(--color-border);
    padding: var(--space-3);
    display: flex;
    flex-direction: column;
    gap: var(--space-2);
  }
  .donate {
    display: inline-flex;
    align-items: center;
    gap: 6px;
    align-self: flex-start;
    padding: 2px var(--space-1);
    margin: -2px calc(-1 * var(--space-1));
    background: transparent;
    color: var(--color-text-muted);
    font-size: var(--text-caption);
    border-radius: var(--radius-sm);
    cursor: pointer;
    transition: background-color var(--motion-duration-fast) var(--motion-ease-out),
                color var(--motion-duration-fast) var(--motion-ease-out);
  }
  .donate:hover {
    background: var(--color-surface-sunken);
    color: var(--color-brand);
  }
  .status {
    display: inline-flex;
    align-items: center;
    gap: var(--space-2);
    font-size: var(--text-caption);
    color: var(--color-text-muted);
    padding: 2px var(--space-1);
    margin: -2px calc(-1 * var(--space-1));
    border-radius: var(--radius-sm);
    background: transparent;
    cursor: pointer;
    text-align: left;
    white-space: nowrap;
    transition: background-color var(--motion-duration-fast) var(--motion-ease-out);
  }
  .status:hover { background: var(--color-surface-sunken); }
  .dot {
    width: 8px; height: 8px; border-radius: var(--radius-full);
    background: var(--color-text-muted);
    transition: background-color var(--motion-duration-fast) var(--motion-ease-out);
  }
  .status-ready .dot   { background: var(--color-success); }
  .status-running .dot { background: var(--color-warning); }
  .status-missing .dot { background: var(--color-danger); }
  .status-unknown .dot { background: var(--color-text-muted); }
</style>
