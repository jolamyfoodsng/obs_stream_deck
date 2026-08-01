use std::{
  net::{IpAddr, Ipv4Addr, SocketAddr, TcpStream},
  path::{Path, PathBuf},
  process::{Child, Command, Stdio},
  sync::Mutex,
  time::Duration,
};

use tauri::{
  menu::{MenuBuilder, MenuItemBuilder},
  tray::{MouseButton, MouseButtonState, TrayIcon, TrayIconBuilder, TrayIconEvent},
  AppHandle, Manager, RunEvent, WindowEvent,
};
use tauri_plugin_updater::UpdaterExt;

#[derive(Default)]
struct BackendState {
  child: Mutex<Option<Child>>,
  tray: Mutex<Option<TrayIcon>>,
}

#[tauri::command]
async fn check_for_update(app: AppHandle) -> Result<Option<String>, String> {
  let updater = app
    .updater()
    .map_err(|e| format!("Updater not available: {e}"))?;
  let result = updater
    .check()
    .await
    .map_err(|e| format!("Update check failed: {e}"))?;
  Ok(result.map(|update| {
    format!(
      "Version {} is available (current: {})",
      update.version, update.current_version,
    )
  }))
}

#[tauri::command]
async fn install_update(app: AppHandle) -> Result<(), String> {
  let updater = app
    .updater()
    .map_err(|e| format!("Updater not available: {e}"))?;
  let update = updater
    .check()
    .await
    .map_err(|e| format!("Update check failed: {e}"))?
    .ok_or("No update available.".to_string())?;
  update
    .download_and_install(
      |downloaded, total| {
        log::info!("Downloading update: {downloaded}/{}", total.unwrap_or(0));
      },
      || {
        log::info!("Update download finished, installing...");
      },
    )
    .await
    .map_err(|e| format!("Update install failed: {e}"))
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
  let app = tauri::Builder::default()
    .plugin(tauri_plugin_updater::Builder::new().build())
    .setup(|app| {
      app.handle().plugin(
        tauri_plugin_log::Builder::default()
          .level(log::LevelFilter::Info)
          .build(),
      )?;
      app.manage(BackendState::default());
      configure_tray(app.handle())?;
      ensure_backend_started(app.handle())?;
      Ok(())
    })
    .on_window_event(|window, event| {
      if window.label() != "main" {
        return;
      }

      if let WindowEvent::CloseRequested { api, .. } = event {
        api.prevent_close();
        if let Err(error) = window.hide() {
          log::warn!("Failed to hide DeckPilot window: {error}");
        }
      }
    })
    .invoke_handler(tauri::generate_handler![check_for_update, install_update])
    .build(tauri::generate_context!())
    .expect("error while building DeckPilot Desktop");

  app.run(|app_handle, event| {
    if let RunEvent::Exit = event {
      stop_backend(app_handle);
    }
  });
}

fn configure_tray(app: &AppHandle) -> tauri::Result<()> {
  let show_item = MenuItemBuilder::with_id("show", "Show DeckPilot").build(app)?;
  let quit_item = MenuItemBuilder::with_id("quit", "Quit DeckPilot").build(app)?;
  let menu = MenuBuilder::new(app)
    .item(&show_item)
    .separator()
    .item(&quit_item)
    .build()?;

  let mut builder = TrayIconBuilder::with_id("main")
    .tooltip("DeckPilot Desktop")
    .menu(&menu)
    .show_menu_on_left_click(false)
    .on_menu_event(|app, event| match event.id().as_ref() {
      "show" => show_main_window(app),
      "quit" => app.exit(0),
      _ => {}
    })
    .on_tray_icon_event(|tray, event| {
      if let TrayIconEvent::Click {
        button: MouseButton::Left,
        button_state: MouseButtonState::Up,
        ..
      } = event
      {
        show_main_window(tray.app_handle());
      }
    });

  if let Some(icon) = app.default_window_icon() {
    builder = builder.icon(icon.clone()).icon_as_template(true);
  }

  let tray = builder.build(app)?;
  app
    .state::<BackendState>()
    .tray
    .lock()
    .expect("backend tray lock poisoned")
    .replace(tray);
  Ok(())
}

fn show_main_window(app: &AppHandle) {
  if let Some(window) = app.get_webview_window("main") {
    if let Err(error) = window.show() {
      log::warn!("Failed to show DeckPilot window: {error}");
    }
    if let Err(error) = window.unminimize() {
      log::warn!("Failed to unminimize DeckPilot window: {error}");
    }
    if let Err(error) = window.set_focus() {
      log::warn!("Failed to focus DeckPilot window: {error}");
    }
  }
}

fn ensure_backend_started(app: &AppHandle) -> Result<(), Box<dyn std::error::Error>> {
  if is_runtime_online() {
    log::info!("DeckPilot runtime already reachable on 127.0.0.1:8080.");
    return Ok(());
  }

  let runtime_dir = runtime_dir(app)?;
  let script_path = runtime_dir.join("server.js");
  if !script_path.exists() {
    return Err(format!(
      "DeckPilot runtime entrypoint was not found at {}.",
      script_path.display()
    )
    .into());
  }

  let child = Command::new("node")
    .arg(&script_path)
    .current_dir(&runtime_dir)
    .stdin(Stdio::null())
    .stdout(Stdio::inherit())
    .stderr(Stdio::inherit())
    .spawn()
    .map_err(|error| format!("Failed to launch DeckPilot runtime with node: {error}"))?;

  app.state::<BackendState>()
    .child
    .lock()
    .expect("backend state lock poisoned")
    .replace(child);

  log::info!(
    "DeckPilot runtime launched from {}.",
    runtime_dir.display()
  );
  Ok(())
}

fn stop_backend(app: &AppHandle) {
  let state = app.state::<BackendState>();
  let mut child_guard = state.child.lock().expect("backend state lock poisoned");
  if let Some(mut child) = child_guard.take() {
    if let Err(error) = child.kill() {
      log::warn!("Failed to stop DeckPilot runtime process: {error}");
    }
  }
}

fn runtime_dir(app: &AppHandle) -> Result<PathBuf, Box<dyn std::error::Error>> {
  if cfg!(debug_assertions) {
    return Ok(
      Path::new(env!("CARGO_MANIFEST_DIR"))
        .parent()
        .ok_or("Unable to resolve deckpilot_desktop directory.")?
        .to_path_buf(),
    );
  }

  Ok(app.path().resource_dir()?.to_path_buf())
}

fn is_runtime_online() -> bool {
  let address = SocketAddr::new(IpAddr::V4(Ipv4Addr::LOCALHOST), 8080);
  TcpStream::connect_timeout(&address, Duration::from_millis(250)).is_ok()
}
