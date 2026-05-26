//! `reqwest`-based fetch + parse for Homebrew analytics endpoints.

use std::collections::HashSet;
use std::time::Duration;

use chrono::Utc;
use serde::Deserialize;

use crate::error::BrewError;
use crate::types::{PackageKind, TrendingEntry, TrendingReport, TrendingWindow};

const HOST: &str = "https://formulae.brew.sh/api/analytics/install";
const TIMEOUT: Duration = Duration::from_secs(10);
const MAX_ENTRIES: usize = 100;

/// JSON shape published at e.g. `/api/analytics/install/30d.json`.
///
/// The live endpoint returns a flat `items: [...]` array (see fixture
/// `tests/fixtures/trending_30d.json` for the canonical shape). Older
/// documentation referenced a `formulae: { name: [...] }` object-of-arrays
/// form; we keep deserialization support for that legacy shape as a
/// fallback so a future endpoint revert wouldn't silently break the tab.
#[derive(Debug, Deserialize)]
struct RawAnalytics {
    #[serde(default)]
    pub total_count: u64,
    #[serde(default)]
    pub items: Vec<RawAnalyticsItem>,
    #[serde(default)]
    pub formulae: std::collections::HashMap<String, Vec<RawAnalyticsItem>>,
}

#[derive(Debug, Deserialize)]
struct RawAnalyticsItem {
    #[serde(default)]
    pub number: u32,
    #[serde(default)]
    pub formula: String,
    #[serde(default)]
    pub count: String,
}

/// Fetch + parse a single window's analytics into a `TrendingReport`.
///
/// `installed` is the set of formula names the user has locally —
/// used to populate `installed_locally` on each entry.
pub async fn fetch(
    window: TrendingWindow,
    installed: &HashSet<String>,
) -> Result<TrendingReport, BrewError> {
    let url = format!("{}/{}.json", HOST, window.as_path_segment());
    let client = reqwest::Client::builder()
        .timeout(TIMEOUT)
        .user_agent(concat!(
            "brew-browser/",
            env!("CARGO_PKG_VERSION"),
            " (+https://github.com/msitarzewski/brew-browser)"
        ))
        .build()
        .map_err(|e| BrewError::Network {
            url: url.clone(),
            message: e.to_string(),
        })?;

    let resp = client.get(&url).send().await.map_err(|e| {
        if let Some(status) = e.status() {
            BrewError::HttpStatus {
                url: url.clone(),
                status: status.as_u16(),
            }
        } else {
            BrewError::Network {
                url: url.clone(),
                message: e.to_string(),
            }
        }
    })?;

    let status = resp.status();
    if !status.is_success() {
        return Err(BrewError::HttpStatus {
            url,
            status: status.as_u16(),
        });
    }

    let raw: RawAnalytics = resp.json().await.map_err(|e| BrewError::Network {
        url: url.clone(),
        message: format!("decoding json failed: {}", e),
    })?;

    // Prefer the flat `items` array (current live endpoint shape).
    // Fall back to flattening the legacy `formulae` object-of-arrays so a
    // future endpoint revert doesn't silently empty the Trending tab.
    let raw_items: Vec<RawAnalyticsItem> = if !raw.items.is_empty() {
        raw.items
    } else {
        raw.formulae
            .into_values()
            .filter_map(|items| items.into_iter().next())
            .collect()
    };

    let mut entries: Vec<TrendingEntry> = raw_items
        .into_iter()
        .filter(|item| !item.formula.is_empty())
        .map(|item| {
            let install_count = parse_count(&item.count);
            TrendingEntry {
                rank: item.number,
                name: item.formula.clone(),
                kind: PackageKind::Formula,
                install_count,
                install_count_formatted: item.count,
                installed_locally: installed.contains(&item.formula),
            }
        })
        .collect();

    // Sort by descending install_count and re-rank so a missing/zero
    // `number` field doesn't shuffle things.
    entries.sort_by_key(|e| std::cmp::Reverse(e.install_count));
    for (i, e) in entries.iter_mut().enumerate() {
        e.rank = (i as u32) + 1;
    }
    entries.truncate(MAX_ENTRIES);

    Ok(TrendingReport {
        window,
        fetched_at: Utc::now().to_rfc3339(),
        cache_age_seconds: 0,
        total_count: raw.total_count,
        entries,
    })
}

fn parse_count(s: &str) -> u64 {
    s.chars()
        .filter(|c| c.is_ascii_digit())
        .collect::<String>()
        .parse::<u64>()
        .unwrap_or(0)
}

// ---------- Tests ----------

#[cfg(test)]
mod tests {
    use super::*;

    fn load_fixture(name: &str) -> String {
        let path = std::path::Path::new(env!("CARGO_MANIFEST_DIR"))
            .join("tests")
            .join("fixtures")
            .join(name);
        std::fs::read_to_string(&path)
            .unwrap_or_else(|e| panic!("read fixture {}: {}", path.display(), e))
    }

    // ---------- parse_count ----------

    #[test]
    fn parse_count_strips_commas_and_returns_number() {
        assert_eq!(parse_count("1,234,567"), 1_234_567);
        assert_eq!(parse_count("100"), 100);
        assert_eq!(parse_count("0"), 0);
    }

    #[test]
    fn parse_count_empty_or_garbage_returns_zero() {
        assert_eq!(parse_count(""), 0);
        assert_eq!(parse_count("---"), 0);
        // Non-digit and non-comma chars are stripped, leaving "" → 0.
        assert_eq!(parse_count("abc"), 0);
    }

    #[test]
    fn parse_count_handles_decimal_like_input_by_concatenation() {
        // "1.5" → "15" (we strip non-digits including the decimal point).
        // brew's count format is always thousands-comma-separated integers,
        // so this is expected behavior.
        assert_eq!(parse_count("1.5"), 15);
    }

    // ---------- RawAnalytics shape: real fixture ----------
    //
    // BUG (documented in apiTests.md): the published formulae.brew.sh
    // analytics payload uses `items: [...]` as the top-level array, not
    // the `formulae: { name: [...] }` object the current parser expects.
    // This test pins the expected wire shape against the real fixture so
    // when the parser is fixed in a future wave, the test confirms the
    // intended shape.

    #[test]
    fn real_trending_fixture_has_top_level_items_array_not_formulae_object() {
        let raw = load_fixture("trending_30d.json");
        let v: serde_json::Value = serde_json::from_str(&raw).expect("valid json");
        assert!(
            v.get("items").and_then(|x| x.as_array()).is_some(),
            "real trending payload must have top-level `items` array"
        );
        // The current parser's `formulae` field is NOT in the real payload.
        // If this assertion ever fails (i.e., `formulae` shows up), the
        // BUG documented in apiTests.md should be revisited.
        assert!(
            v.get("formulae").is_none(),
            "real trending payload should not have top-level `formulae` key (it has `items`)"
        );

        // total_count and category are present on the real payload.
        assert!(v.get("total_count").and_then(|x| x.as_u64()).is_some());
        assert!(v.get("category").and_then(|x| x.as_str()).is_some());
    }

    #[test]
    fn raw_analytics_items_round_trip_individual_item_struct() {
        // The per-item shape DOES match RawAnalyticsItem; only the
        // container shape is wrong. Confirm an individual item parses.
        let raw = load_fixture("trending_30d.json");
        let v: serde_json::Value = serde_json::from_str(&raw).unwrap();
        let first = &v["items"][0];
        let item: RawAnalyticsItem =
            serde_json::from_value(first.clone()).expect("item must parse");
        assert!(item.number >= 1);
        assert!(!item.formula.is_empty());
        assert!(!item.count.is_empty());
    }

    #[test]
    fn parser_consumes_items_array_from_real_payload() {
        // After FIX-B (PASS-2): the parser now reads the flat `items`
        // array. `formulae` remains absent on the real payload — that's
        // expected — and the legacy fallback path is exercised by
        // `raw_analytics_parses_documented_legacy_shape` below.
        let raw = load_fixture("trending_30d.json");
        let parsed: RawAnalytics = serde_json::from_str(&raw)
            .expect("RawAnalytics parses real payload");
        assert_eq!(parsed.total_count, 25_713_624);
        assert!(
            parsed.formulae.is_empty(),
            "real payload has no legacy `formulae` object — `items` is the source of truth"
        );
        assert!(
            !parsed.items.is_empty(),
            "real payload must populate `items` for the parser to yield entries"
        );
        // First item from the fixture.
        let first = &parsed.items[0];
        assert_eq!(first.number, 1);
        assert_eq!(first.formula, "ca-certificates");
        assert_eq!(first.count, "481,964");
    }

    // ---------- Compat: synthetic legacy payload still parses ----------
    //
    // If formulae.brew.sh ever publishes the documented (but unused)
    // `formulae: { name: [...] }` shape, the current parser handles it.
    // Locking the behavior here so a fix doesn't regress legacy support.

    #[test]
    fn raw_analytics_parses_documented_legacy_shape() {
        let synthetic = serde_json::json!({
            "total_count": 100u64,
            "formulae": {
                "wget": [
                    { "number": 1, "formula": "wget", "count": "42" }
                ],
                "git": [
                    { "number": 2, "formula": "git", "count": "10" }
                ]
            }
        });
        let raw = serde_json::to_string(&synthetic).unwrap();
        let parsed: RawAnalytics = serde_json::from_str(&raw).expect("legacy shape parses");
        assert_eq!(parsed.total_count, 100);
        assert_eq!(parsed.formulae.len(), 2);
        assert!(parsed.formulae.contains_key("wget"));
        assert!(parsed.formulae.contains_key("git"));
    }
}
