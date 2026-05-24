//! Trending tab commands: `trending_fetch` and `trending_clear_cache`.

use std::collections::HashSet;
use std::time::{Duration, Instant};

use tauri::State;

use crate::commands::settings::{Settings, SettingsLoadState};
use crate::error::BrewError;
use crate::state::AppState;
use crate::trending::cache::CachedTrending;
use crate::trending::client;
use crate::types::{TrendingReport, TrendingWindow};

/// Resolve the effective trending cache TTL from the persisted settings
/// (Phase 12d). The cache itself is TTL-agnostic — freshness is decided
/// here against the user's preference so a `settings_set` is honoured
/// on the very next `trending_fetch` without restarting the process.
///
/// **Fail-closed semantics:** when settings are `Corrupt`, the
/// `require_network` gate has already denied the call before we got
/// here, so this helper only ever runs on `Loaded` or `FirstLaunch`.
/// Both yield the default TTL when the setting is absent.
pub(crate) fn effective_trending_ttl(settings_state: &SettingsLoadState) -> Duration {
    let minutes = match settings_state {
        SettingsLoadState::Loaded(s) => s.trending_ttl_minutes,
        // FirstLaunch / Corrupt both fall through to the default. The
        // Corrupt branch is unreachable in practice (require_network has
        // already returned ParanoidModeBlocked) but we still hand back
        // the default rather than panic — defensive only.
        _ => Settings::default().trending_ttl_minutes,
    };
    Duration::from_secs(u64::from(minutes) * 60)
}

#[tauri::command]
pub async fn trending_fetch(
    window: TrendingWindow,
    state: State<'_, AppState>,
) -> Result<TrendingReport, BrewError> {
    // Paranoid-mode gate (Phase 12d). Even a stale cache hit is
    // disallowed in paranoid mode — the user's expectation is "no
    // outbound calls would happen here", and even though the cached
    // path doesn't hit the network, returning fresh-looking data
    // contradicts the toggle. The cost is zero (the gate is a single
    // RwLock read), the policy is unambiguous.
    state.require_network("trending_fetch").await?;

    // Resolve TTL from settings (Phase 13 — Finding 2 follow-up). The
    // hardcoded `TRENDING_TTL` constant in `trending::cache` is now the
    // *default* baseline only; the live decision uses the user's
    // configured `trending_ttl_minutes` (clamped 5..=1440).
    let ttl = {
        let guard = state.settings.read().await;
        effective_trending_ttl(&guard)
    };

    // 1. Short critical section: check cache freshness.
    {
        let cache = state.trending_cache.lock().await;
        if let Some(cached) = cache.get(window) {
            let age = cached.fetched_at.elapsed();
            if age < ttl {
                let mut report = cached.report.clone();
                report.cache_age_seconds = age.as_secs();
                return Ok(report);
            }
        }
    }

    // 2. Fetch.
    let installed_set = build_installed_set(&state).await;
    let fetched = client::fetch(window, &installed_set).await;

    match fetched {
        Ok(report) => {
            // 3. Insert into cache.
            let mut cache = state.trending_cache.lock().await;
            cache.put(
                window,
                CachedTrending {
                    fetched_at: Instant::now(),
                    report: report.clone(),
                },
            );
            Ok(report)
        }
        Err(e) => {
            // 4. Fall back to stale cache if available.
            let cache = state.trending_cache.lock().await;
            if let Some(cached) = cache.get(window) {
                let mut report = cached.report.clone();
                report.cache_age_seconds = cached.fetched_at.elapsed().as_secs();
                return Ok(report);
            }
            Err(e)
        }
    }
}

#[tauri::command]
pub async fn trending_clear_cache(state: State<'_, AppState>) -> Result<(), BrewError> {
    let mut cache = state.trending_cache.lock().await;
    cache.clear();
    Ok(())
}

async fn build_installed_set(state: &AppState) -> HashSet<String> {
    let cache = state.installed_cache.read().await;
    let mut set = HashSet::new();
    if let Some(list) = cache.as_ref() {
        for p in list.formulae.iter().chain(list.casks.iter()) {
            set.insert(p.name.clone());
        }
    }
    set
}

// ---------- Tests ----------

#[cfg(test)]
mod tests {
    use super::*;
    use crate::commands::settings::Settings;
    use crate::trending::cache::TRENDING_TTL;

    #[test]
    fn effective_ttl_uses_loaded_setting() {
        // 5-minute setting → 300-second TTL.
        let s = Settings {
            trending_ttl_minutes: 5,
            ..Settings::default()
        };
        let ttl = effective_trending_ttl(&SettingsLoadState::Loaded(s));
        assert_eq!(ttl, Duration::from_secs(5 * 60));
    }

    #[test]
    fn effective_ttl_uses_default_on_first_launch() {
        // No settings file yet → fall back to the struct default
        // (60 minutes, matching the historical TRENDING_TTL constant).
        let ttl = effective_trending_ttl(&SettingsLoadState::FirstLaunch);
        assert_eq!(ttl, TRENDING_TTL);
        assert_eq!(ttl, Duration::from_secs(60 * 60));
    }

    #[test]
    fn effective_ttl_uses_default_on_corrupt() {
        // Corrupt is unreachable in practice (require_network denies
        // first), but the helper is defensive and falls back to the
        // default rather than panicking.
        let ttl = effective_trending_ttl(&SettingsLoadState::Corrupt {
            message: "boom".into(),
        });
        assert_eq!(ttl, TRENDING_TTL);
    }

    #[test]
    fn effective_ttl_max_setting() {
        let s = Settings {
            trending_ttl_minutes: 1440, // 24h, the clamp ceiling
            ..Settings::default()
        };
        let ttl = effective_trending_ttl(&SettingsLoadState::Loaded(s));
        assert_eq!(ttl, Duration::from_secs(24 * 60 * 60));
    }

    /// Core gate test: a cache entry inserted 10 minutes ago must be
    /// considered stale when the user's `trending_ttl_minutes` is 5.
    /// This is the explicit acceptance criterion from the spec — proves
    /// the setting actually affects the cache decision rather than the
    /// hardcoded 60-minute constant.
    #[test]
    fn ttl_setting_makes_old_cache_stale() {
        use crate::trending::cache::{CachedTrending, TrendingCache};
        use crate::types::{TrendingReport, TrendingWindow};

        let s = Settings {
            trending_ttl_minutes: 5, // 5 minute TTL
            ..Settings::default()
        };
        let ttl = effective_trending_ttl(&SettingsLoadState::Loaded(s));
        assert_eq!(ttl, Duration::from_secs(5 * 60));

        // Plant a cache entry that's 10 minutes old.
        let mut cache = TrendingCache::default();
        cache.put(
            TrendingWindow::D30,
            CachedTrending {
                fetched_at: Instant::now() - Duration::from_secs(10 * 60),
                report: TrendingReport {
                    window: TrendingWindow::D30,
                    fetched_at: "2026-05-24T00:00:00Z".into(),
                    cache_age_seconds: 0,
                    total_count: 0,
                    entries: Vec::new(),
                },
            },
        );

        // Mirror the freshness check from `trending_fetch`: with the
        // configured TTL of 5 min, the 10-min-old entry must be stale.
        let entry = cache.get(TrendingWindow::D30).expect("planted");
        let age = entry.fetched_at.elapsed();
        assert!(
            age >= ttl,
            "entry age {age:?} must be >= TTL {ttl:?} for the stale-check to fire"
        );

        // Sanity: under the historical 60-minute TTL, the same entry
        // would have been considered fresh — confirms the setting is
        // what's changing the decision.
        assert!(age < TRENDING_TTL, "10 min < 60 min default → would have been fresh");
    }
}
