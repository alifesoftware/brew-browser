<script lang="ts">
  /**
   * SettingsSectionTrendingHistory.svelte — v0.4.0
   *
   * Sibling of SettingsSectionUpdates: mounted at the bottom of
   * SettingsSectionNetwork.svelte. The opt-in toggle for the trending-
   * history endpoint at `brew-browser.zerologic.com/trending-history/*`.
   *
   * Why a separate section? The endpoint is operated by the project,
   * not by upstream Homebrew — distinct trust boundary from the always-
   * on `formulae.brew.sh` paths. The disclosure copy makes that
   * explicit so users can decide knowingly.
   *
   * Two states:
   * - Offline Mode on → toggle disabled with "Disabled by Offline Mode"
   *   tooltip; hint copy points at the master switch above.
   * - Offline Mode off → toggle live; ON binds enhancedTrendingEnabled
   *   so the backend's `require_enhanced_trending` gate flips open.
   *
   * No "Test connection" button (D4 = passive); discovery happens in
   * Trending tab where the feature actually shows up.
   */

  import LineChart from "@lucide/svelte/icons/line-chart";

  import { settings } from "$lib/stores/settings.svelte";

  /** Offline Mode hard-locks this toggle regardless of its setting. */
  let offline = $derived(settings.effective.paranoidMode);
  /** Effective state used for the toggle visual + disclosure logic. */
  let on = $derived(settings.effective.enhancedTrendingEnabled);

  function onToggle(e: Event) {
    const v = (e.currentTarget as HTMLInputElement).checked;
    void settings.save({ enhancedTrendingEnabled: v });
  }
</script>

<div class="section">
  <h2>
    <LineChart size={18} aria-hidden="true" />
    Enhanced Trending History
  </h2>

  <div class="field">
    <label class="toggle" title={offline ? "Disabled by Offline Mode" : undefined}>
      <input
        type="checkbox"
        checked={on}
        onchange={onToggle}
        disabled={offline || settings.loading || settings.corruptOnDisk}
        aria-describedby="enhanced-trending-hint"
      />
      <span class="toggle-track" aria-hidden="true"></span>
      <span class="toggle-label">Fetch trending history</span>
    </label>

    <p class="hint" id="enhanced-trending-hint">
      When on, brew-browser fetches per-package historical install trends
      from <code>brew-browser.zerologic.com/trending-history/*</code> to
      power per-row sparklines on the Trending tab and a chart on each
      package's detail panel. Only the package name you're viewing is
      sent (one HTTP GET per package); no IP is logged at the server,
      no cookies, no fingerprinting. The endpoint is operated by the
      brew-browser project — a distinct trust boundary from the
      always-on Homebrew analytics paths above.
    </p>

    {#if offline}
      <p class="hint hint-warn">
        Offline Mode is on — this toggle is locked off. Turn Offline
        Mode off above to enable history fetching.
      </p>
    {/if}
  </div>
</div>

<style>
  /* Same nested-section pattern as SettingsSectionUpdates: a top
     divider, no second-tier H2 sized like the parent section's H1. */
  .section {
    display: flex;
    flex-direction: column;
    gap: var(--space-3);
    max-width: 580px;
    margin-top: var(--space-3);
    padding-top: var(--space-5);
    border-top: 1px solid var(--color-border);
  }
  h2 {
    display: inline-flex;
    align-items: center;
    gap: var(--space-2);
    font-size: var(--text-h2);
    font-weight: var(--fw-semibold);
    color: var(--color-text-primary);
    margin: 0 0 var(--space-2) 0;
  }
  .field {
    display: flex;
    flex-direction: column;
    gap: var(--space-2);
  }
  .hint {
    font-size: var(--text-body-sm);
    color: var(--color-text-muted);
    line-height: var(--lh-snug);
  }
  .hint code {
    font-family: var(--font-mono);
    font-size: var(--text-mono);
    padding: 1px 4px;
    background: var(--color-surface-sunken);
    border-radius: var(--radius-sm);
    color: var(--color-text-secondary);
    word-break: break-all;
  }
  .hint-warn {
    color: var(--color-warning-strong, #b45309);
  }

  /* ---------- Toggle (matches Network/Updates) ---------- */
  .toggle {
    display: inline-flex;
    align-items: center;
    gap: var(--space-2);
    cursor: pointer;
    user-select: none;
  }
  .toggle input { position: absolute; opacity: 0; pointer-events: none; }
  .toggle-track {
    width: 36px;
    height: 20px;
    background: var(--color-surface-sunken);
    border: 1px solid var(--color-border);
    border-radius: 999px;
    position: relative;
    transition: background-color var(--motion-duration-fast) var(--motion-ease-out);
  }
  .toggle-track::after {
    content: "";
    position: absolute;
    top: 1px;
    left: 1px;
    width: 16px;
    height: 16px;
    background: var(--color-surface-raised);
    border-radius: 50%;
    box-shadow: var(--shadow-xs);
    transition: transform var(--motion-duration-fast) var(--motion-ease-out);
  }
  .toggle input:checked + .toggle-track {
    background: var(--color-accent, #b8542a);
    border-color: var(--color-accent, #b8542a);
  }
  .toggle input:checked + .toggle-track::after {
    transform: translateX(16px);
    background: white;
  }
  .toggle input:disabled + .toggle-track {
    opacity: 0.6;
    cursor: not-allowed;
  }
  .toggle-label {
    font-size: var(--text-body);
    font-weight: var(--fw-medium);
    color: var(--color-text-primary);
  }
</style>
