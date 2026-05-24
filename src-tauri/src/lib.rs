//! brew-browser — Tauri 2 backend entrypoint.
//!
//! Module layout per `memory-bank/backendApi.md` §9. This file is the
//! Tauri Builder + invoke_handler registration; every command lives
//! in `commands::*`.

mod brew;
mod catalog;
mod commands;
mod enrichment;
mod error;
mod github;
mod state;
mod trending;
mod types;
mod util;

use commands::*;

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    // Best-effort tracing setup — silent if RUST_LOG is unset.
    let _ = tracing_subscriber::fmt()
        .with_env_filter(
            tracing_subscriber::EnvFilter::try_from_default_env()
                .unwrap_or_else(|_| tracing_subscriber::EnvFilter::new("warn,brew_browser_lib=info")),
        )
        .try_init();

    tauri::Builder::default()
        .plugin(tauri_plugin_opener::init())
        .plugin(tauri_plugin_dialog::init())
        .menu(build_app_menu)
        .on_menu_event(handle_menu_event)
        .setup(|app| {
            state::initialize(app)?;
            #[cfg(target_os = "macos")]
            {
                // Apply NSVisualEffectView to the main window so it picks up the
                // native macOS "frosted glass" appearance. Material::HudWindow
                // gives a slightly heavier blur that looks good behind the
                // sidebar and main panes; the WebView background must be set
                // transparent in CSS (see app.css :root) for the blur to show.
                use tauri::Manager;
                use window_vibrancy::{apply_vibrancy, NSVisualEffectMaterial, NSVisualEffectState};
                if let Some(window) = app.get_webview_window("main") {
                    let _ = apply_vibrancy(
                        &window,
                        NSVisualEffectMaterial::HudWindow,
                        Some(NSVisualEffectState::Active),
                        None,
                    );
                }
            }
            Ok(())
        })
        .invoke_handler(tauri::generate_handler![
            app_version,
            brew_doctor,
            brew_get_analytics,
            brew_set_analytics,
            brew_list,
            brew_outdated,
            brew_info,
            brew_search,
            brew_search_desc,
            brew_install,
            brew_uninstall,
            brew_upgrade,
            brew_update,
            cancel_job,
            brewfile_dump,
            brewfile_install,
            brewfile_check,
            brewfile_list,
            brewfile_read,
            brewfile_delete,
            brewfile_export,
            brewfile_import,
            trending_fetch,
            trending_clear_cache,
            cask_icon,
            cask_icon_from_homepage,
            catalog_summary,
            catalog_refresh,
            catalog_lookup_formula,
            catalog_lookup_cask,
            catalog_formulae_summary,
            catalog_casks_summary,
            categories_data,
            enrichment_data,
            enrichment_lookup,
            disk_usage,
            disk_usage_clear_cache,
            open_in_finder,
            services_list,
            services_clear_cache,
            services_start,
            services_stop,
            services_restart,
            settings_get,
            settings_set,
            settings_reset,
            github_repo_stats,
            github_status,
            github_signin_start,
            github_signin_poll,
            github_signout,
            github_star,
            github_unstar,
            github_is_starred,
            github_watch,
            github_unwatch,
            github_create_issue,
        ])
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}

// =============================================================
// Native macOS menu (Phase 12+)
// =============================================================
//
// macOS apps have a system menu bar above the screen, not inside the window.
// The "App" menu is the first item (named after the app) and is where users
// expect to find "About <App>" and "Settings…". Per Tauri 2 conventions we
// build the menu in a closure passed to `.menu(...)` on the Builder, and
// dispatch click events from `.on_menu_event(...)`.
//
// The menu items emit Tauri events that the frontend listens for via
// `listen()` and turns into store-state updates (`ui.openAbout()` /
// `ui.openSettings()`). This keeps the menu definition Rust-side and the
// modal rendering entirely in Svelte.

const MENU_EVENT_ABOUT: &str = "brew-browser/menu/about";
const MENU_EVENT_SETTINGS: &str = "brew-browser/menu/settings";

fn build_app_menu<R: tauri::Runtime>(
    app: &tauri::AppHandle<R>,
) -> tauri::Result<tauri::menu::Menu<R>> {
    use tauri::menu::{MenuBuilder, MenuItemBuilder, PredefinedMenuItem, SubmenuBuilder};

    let pkg = app.package_info();

    // App menu: About (custom — opens our in-app modal), Settings…, ─, Hide
    // / Hide-Others / Show-All, ─, Quit. The native PredefinedMenuItem::about
    // would open the OS dialog; we route through our own modal instead via
    // a MenuItemBuilder + the menu event so the donate CTA + Anthropic
    // credits render in our UI.
    let about_item = MenuItemBuilder::new(format!("About {}", pkg.name))
        .id(MENU_EVENT_ABOUT)
        .build(app)?;
    let settings_item = MenuItemBuilder::new("Settings…")
        .id(MENU_EVENT_SETTINGS)
        .accelerator("CmdOrCtrl+,")
        .build(app)?;

    let app_submenu = SubmenuBuilder::new(app, pkg.name.clone())
        .item(&about_item)
        .separator()
        .item(&settings_item)
        .separator()
        .item(&PredefinedMenuItem::hide(app, None)?)
        .item(&PredefinedMenuItem::hide_others(app, None)?)
        .item(&PredefinedMenuItem::show_all(app, None)?)
        .separator()
        .item(&PredefinedMenuItem::quit(app, None)?)
        .build()?;

    // Standard ancillary menus — Edit (copy/paste/etc.) + Window. Pure
    // PredefinedMenuItems so we don't have to reinvent them.
    let edit_submenu = SubmenuBuilder::new(app, "Edit")
        .item(&PredefinedMenuItem::undo(app, None)?)
        .item(&PredefinedMenuItem::redo(app, None)?)
        .separator()
        .item(&PredefinedMenuItem::cut(app, None)?)
        .item(&PredefinedMenuItem::copy(app, None)?)
        .item(&PredefinedMenuItem::paste(app, None)?)
        .item(&PredefinedMenuItem::select_all(app, None)?)
        .build()?;

    let window_submenu = SubmenuBuilder::new(app, "Window")
        .item(&PredefinedMenuItem::minimize(app, None)?)
        .item(&PredefinedMenuItem::maximize(app, None)?)
        .separator()
        .item(&PredefinedMenuItem::close_window(app, None)?)
        .build()?;

    MenuBuilder::new(app)
        .item(&app_submenu)
        .item(&edit_submenu)
        .item(&window_submenu)
        .build()
}

fn handle_menu_event<R: tauri::Runtime>(
    app: &tauri::AppHandle<R>,
    event: tauri::menu::MenuEvent,
) {
    use tauri::Emitter;
    match event.id().as_ref() {
        MENU_EVENT_ABOUT => {
            let _ = app.emit("menu:about", ());
        }
        MENU_EVENT_SETTINGS => {
            let _ = app.emit("menu:settings", ());
        }
        _ => {}
    }
}
