# DeckPilot Test Guide

This project uses a layered Flutter test strategy:

- `test/unit/`
  - business logic
  - premium limits
  - OBS state mapping
  - macro sequencing
  - review/onboarding gating
- `test/widget/`
  - screen behavior
  - locked-feature UX
  - responsive layouts
  - settings/help flows
- `integration_test/`
  - full app journeys with fake OBS and fake billing

## Test doubles

Reusable fakes live under `test/test_helpers/fakes/`.

Main fakes:

- `FakeObsRepository`
- `FakeObsWebSocketService`
- `FakeBillingService`
- `FakeConnectionRepository`
- `FakeControllerRepository`
- `FakeMacroRepository`
- `FakeDashboardRepository`
- `FakeReviewPromptService`
- `FakeObsAutoDiscoveryService`
- `FakeSceneThumbnailService`
- `FakeStreamHealthMonitor`

Shared sample fixtures live in:

- `test/test_helpers/fixtures/sample_data.dart`

## Commands

Run analysis:

```bash
flutter analyze
```

Run unit and widget tests:

```bash
flutter test
```

Run a specific test file:

```bash
flutter test test/widget/controller_screen_test.dart
```

Run the integration suite on a connected emulator/device:

```bash
flutter test integration_test/app_flow_test.dart -d emulator-5554
```

Replace `emulator-5554` with any device from `flutter devices`.

## What is covered

The suite currently validates:

- connection screen flows
- no dummy scene fallback when disconnected
- OBS-backed scene/controller rendering
- quick-control state changes from live OBS state
- premium limits for pages, scenes, and macros
- premium modal timing for locked actions
- preview-first premium UX for macros/monitor/pages
- settings premium/review/help flows
- onboarding/review threshold logic
- responsive controller layouts for phone and tablet
- macro execution order and failure handling
- fake end-to-end app flows through `integration_test`

## Design note

Tests do not require:

- a real OBS server
- a real WebSocket connection
- real Google Play Billing

All of those are isolated behind injected fakes so the suite stays deterministic.
