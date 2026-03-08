# OBS Stream Deck (Flutter)

A Flutter Android-first Stream Deck style remote for OBS Studio.

## What is implemented

- Material 3 dark app shell with responsive layouts
- Clean architecture folder structure
- Riverpod state management
- go_router navigation
- Screens:
  - Connect to OBS
  - Main Controller (page swipe + indicators)
  - Button Editor
  - Page Manager
  - Macro Editor
  - Status Dashboard
  - Settings
- Reusable shared widgets (`DeckButton`, `DeckButtonGrid`, `StatusBadge`, etc.)
- Domain entities + repositories + use cases
- OBS service abstraction with:
  - `MockObsWebSocketService` (default for development)
  - `RealObsWebSocketService` (protocol integration boundary)
- Local persistence using `shared_preferences`
- Seed demo pages, buttons, sources, scenes, macros, and dashboard data

## OBS integration note

`RealObsWebSocketService` is wired for connection and request transport boundaries. Full OBS event/request protocol mapping can be expanded there without touching UI layers.

## Run locally

1. Install Flutter SDK (stable) and Android toolchain.
2. In project root, run:

```bash
flutter pub get
flutter run -d android
```

If emulator discovery is unstable on your machine, use the bundled runner:

```bash
./scripts/run_android.sh
```

It launches the AVD in visible mode by default, waits for full boot, and starts `flutter run` on `emulator-5554`.

To run without opening an emulator window (CI/headless):

```bash
EMULATOR_HEADLESS=1 ./scripts/run_android.sh
```

If you generated this folder from scratch and platform folders are missing, run:

```bash
flutter create --platforms=android .
```

Then re-apply dependencies if needed and run again.

## Switch mock vs real OBS service

Edit:

- `lib/core/constants/app_constants.dart`

Change:

- `AppConstants.useMockObsService`

`true` = mock service, `false` = real WebSocket transport.
