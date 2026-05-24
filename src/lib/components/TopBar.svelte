<script lang="ts">
  import { onMount } from "svelte";
  import Sun from "@lucide/svelte/icons/sun";
  import Moon from "@lucide/svelte/icons/moon";
  import Monitor from "@lucide/svelte/icons/monitor";
  import SettingsIcon from "@lucide/svelte/icons/settings";
  import Check from "@lucide/svelte/icons/check";

  import { ui } from "$lib/stores/ui.svelte";
  import type { ThemePreference } from "$lib/types";

  /**
   * Compact top-right control cluster: a single theme button (current icon
   * reflects active theme; click opens a small popover with Light / Dark /
   * System) + a Settings gear, grouped as one rounded pill.
   *
   * Positioned absolutely in the top-right of the window above all content,
   * with right offset that clears the existing 32 px traffic-light-equivalent
   * area on the LEFT (the right side has no system chrome — full width).
   */

  let themeMenuOpen = $state(false);
  let buttonEl: HTMLButtonElement | undefined = $state();
  let menuEl: HTMLDivElement | undefined = $state();

  // Active-theme icon picker
  function activeIcon(theme: ThemePreference) {
    if (theme === "light") return Sun;
    if (theme === "dark") return Moon;
    return Monitor;
  }

  function activeLabel(theme: ThemePreference) {
    if (theme === "light") return "Light theme";
    if (theme === "dark") return "Dark theme";
    return "System theme";
  }

  function pickTheme(t: ThemePreference) {
    ui.setTheme(t);
    themeMenuOpen = false;
  }

  function toggleMenu() {
    themeMenuOpen = !themeMenuOpen;
  }

  // Close on outside click + Esc
  function onDocClick(e: MouseEvent) {
    if (!themeMenuOpen) return;
    const target = e.target as Node | null;
    if (
      target &&
      !buttonEl?.contains(target) &&
      !menuEl?.contains(target)
    ) {
      themeMenuOpen = false;
    }
  }

  function onKeydown(e: KeyboardEvent) {
    if (e.key === "Escape" && themeMenuOpen) {
      themeMenuOpen = false;
      buttonEl?.focus();
    }
  }

  onMount(() => {
    document.addEventListener("click", onDocClick);
    window.addEventListener("keydown", onKeydown);
    return () => {
      document.removeEventListener("click", onDocClick);
      window.removeEventListener("keydown", onKeydown);
    };
  });

  let ActiveIcon = $derived(activeIcon(ui.theme));
</script>

<div class="topbar" data-tauri-drag-region="false">
  <div class="group" role="group" aria-label="App controls">
    <!-- Theme dropdown trigger -->
    <button
      bind:this={buttonEl}
      type="button"
      class="ctrl"
      class:open={themeMenuOpen}
      onclick={toggleMenu}
      title={`Theme: ${activeLabel(ui.theme)}`}
      aria-label="Change theme"
      aria-haspopup="menu"
      aria-expanded={themeMenuOpen}
    >
      <ActiveIcon size={14} />
    </button>

    <!-- Settings gear -->
    <button
      type="button"
      class="ctrl"
      onclick={() => ui.openSettings()}
      title="Settings (⌘,)"
      aria-label="Open Settings"
    >
      <SettingsIcon size={14} />
    </button>
  </div>

  {#if themeMenuOpen}
    <div
      bind:this={menuEl}
      class="menu"
      role="menu"
      aria-label="Theme"
    >
      <button
        type="button"
        class="menu-item"
        class:active={ui.theme === "light"}
        role="menuitemradio"
        aria-checked={ui.theme === "light"}
        onclick={() => pickTheme("light")}
      >
        <Sun size={14} />
        <span>Light</span>
        {#if ui.theme === "light"}<Check size={12} class="check" />{/if}
      </button>
      <button
        type="button"
        class="menu-item"
        class:active={ui.theme === "dark"}
        role="menuitemradio"
        aria-checked={ui.theme === "dark"}
        onclick={() => pickTheme("dark")}
      >
        <Moon size={14} />
        <span>Dark</span>
        {#if ui.theme === "dark"}<Check size={12} class="check" />{/if}
      </button>
      <button
        type="button"
        class="menu-item"
        class:active={ui.theme === "system"}
        role="menuitemradio"
        aria-checked={ui.theme === "system"}
        onclick={() => pickTheme("system")}
      >
        <Monitor size={14} />
        <span>System</span>
        {#if ui.theme === "system"}<Check size={12} class="check" />{/if}
      </button>
    </div>
  {/if}
</div>

<style>
  /* Anchored to .content (the main panel area, not the window) via
     position: absolute. This keeps the theme + Settings group at the
     top-right of whichever panel is active without floating over the
     PackageDetail slide-over. .content has position: relative for this
     to anchor correctly. */
  .topbar {
    position: absolute;
    top: 14px;
    right: 16px;
    z-index: 5;
  }

  /* Theme + Settings form a logical pair — same "app preferences" family.
     Give them a subtle shared container (light sunken background, thin
     divider) so they read as one group, without the heavy bordered pill
     that was clashing with the rest of the panel-head buttons. */
  .group {
    display: inline-flex;
    align-items: center;
    background: var(--color-surface-sunken);
    border-radius: var(--radius-md);
    padding: 2px;
    gap: 0;
  }
  .ctrl {
    display: inline-flex;
    align-items: center;
    justify-content: center;
    width: 26px;
    height: 22px;
    background: transparent;
    border-radius: var(--radius-sm);
    color: var(--color-text-muted);
    cursor: pointer;
    transition: background-color 0.12s ease, color 0.12s ease;
  }
  .ctrl:hover {
    background: var(--color-surface-raised);
    color: var(--color-text-primary);
  }
  .ctrl.open {
    background: var(--color-surface-raised);
    color: var(--color-text-primary);
  }
  /* Hair-line divider between the two grouped controls. */
  .ctrl + .ctrl {
    position: relative;
  }
  .ctrl + .ctrl::before {
    content: "";
    position: absolute;
    left: -1px;
    top: 4px;
    bottom: 4px;
    width: 1px;
    background: var(--color-border);
    opacity: 0.6;
  }

  /* Dropdown popover */
  .menu {
    position: absolute;
    top: calc(100% + 4px);
    right: 0;
    min-width: 140px;
    padding: 4px;
    background: var(--color-surface-raised);
    border: 1px solid var(--color-border);
    border-radius: var(--radius-md);
    box-shadow: 0 8px 24px -4px color-mix(in oklch, black 30%, transparent);
    z-index: 51;
    display: flex;
    flex-direction: column;
    gap: 2px;
  }
  .menu-item {
    display: grid;
    grid-template-columns: 16px 1fr 14px;
    gap: var(--space-2);
    align-items: center;
    padding: 6px 8px;
    border-radius: var(--radius-sm);
    background: transparent;
    color: var(--color-text-primary);
    text-align: left;
    font-size: var(--text-body-sm);
    cursor: pointer;
  }
  .menu-item:hover { background: var(--color-surface-sunken); }
  .menu-item.active { color: var(--color-text-primary); }
  .menu-item :global(.check) { color: var(--color-accent); }
</style>
