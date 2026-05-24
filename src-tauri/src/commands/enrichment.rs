//! Enrichment commands (Phase 13).
//!
//! Surfaces the bundled `enrichment.json.gz` payload via two IPC
//! commands. Both delegate to the parser in
//! [`crate::enrichment::EnrichmentData`] — there is no runtime LLM
//! traffic; the bundle is the canonical artifact.
//!
//! See `commands::categories` for the parallel pattern used by the
//! Phase 9 categories payload — both modules memoise the parsed
//! payload on `AppState` so the parse happens once per process.

use std::sync::Arc;

use tauri::State;

use crate::commands::info::validate_package_name;
use crate::enrichment::{EnrichmentData, EnrichmentEntry};
use crate::error::BrewError;
use crate::state::AppState;

/// Return the full enrichment payload. Memoised on `AppState` so
/// subsequent calls are an Arc-clone, not a re-parse.
#[tauri::command]
pub async fn enrichment_data(
    state: State<'_, AppState>,
) -> Result<Arc<EnrichmentData>, BrewError> {
    {
        let cached = state.enrichment_cache.lock().await;
        if let Some(data) = cached.as_ref() {
            return Ok(Arc::clone(data));
        }
    }

    let arc = EnrichmentData::load()?;
    let mut cached = state.enrichment_cache.lock().await;
    *cached = Some(Arc::clone(&arc));
    Ok(arc)
}

/// Lookup a single token. Returns `None` when the token is missing
/// (placeholder bundle, unmapped package, etc.). Validates the input
/// name first so an IPC caller can't probe with shell metacharacters.
#[tauri::command]
pub async fn enrichment_lookup(
    name: String,
    state: State<'_, AppState>,
) -> Result<Option<EnrichmentEntry>, BrewError> {
    validate_package_name(&name)?;
    let data = enrichment_data(state).await?;
    Ok(data.entries.get(&name).cloned())
}
