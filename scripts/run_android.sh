#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SDK_ROOT="${ANDROID_SDK_ROOT:-${ANDROID_HOME:-$HOME/Library/Android/sdk}}"
ADB="$SDK_ROOT/platform-tools/adb"
EMULATOR_BIN="$SDK_ROOT/emulator/emulator"
AVD_NAME="${AVD_NAME:-Medium_Phone_API_35}"
EMULATOR_ID="${EMULATOR_ID:-emulator-5554}"
BOOT_TIMEOUT_SECS="${BOOT_TIMEOUT_SECS:-240}"
EMULATOR_HEADLESS="${EMULATOR_HEADLESS:-0}"

if [[ ! -x "$ADB" ]]; then
  echo "adb not found at: $ADB"
  exit 1
fi

if [[ ! -x "$EMULATOR_BIN" ]]; then
  echo "emulator binary not found at: $EMULATOR_BIN"
  exit 1
fi

if [[ ! -d "$SDK_ROOT/system-images/android-35/google_apis_playstore/arm64-v8a" ]]; then
  echo "Missing required system image directory:"
  echo "  $SDK_ROOT/system-images/android-35/google_apis_playstore/arm64-v8a"
  echo "Install with:"
  echo "  sdkmanager \"system-images;android-35;google_apis_playstore;arm64-v8a\""
  exit 1
fi

"$ADB" kill-server >/dev/null 2>&1 || true
"$ADB" start-server >/dev/null

if ! "$ADB" devices | grep -q "^$EMULATOR_ID\\s"; then
  echo "Launching AVD: $AVD_NAME"
  EMULATOR_ARGS=(
    -avd "$AVD_NAME"
    -no-boot-anim
  )

  if [[ "$EMULATOR_HEADLESS" == "1" ]]; then
    echo "Mode: headless (no emulator window)"
    EMULATOR_ARGS+=(
      -no-window
      -no-audio
      -gpu swiftshader_indirect
      -accel off
    )
  else
    echo "Mode: visible (emulator window should open)"
  fi

  nohup "$EMULATOR_BIN" "${EMULATOR_ARGS[@]}" > /tmp/obs_stream_deck_emulator.log 2>&1 &
fi

echo "Waiting for $EMULATOR_ID to boot..."
for ((i=1; i<=BOOT_TIMEOUT_SECS; i++)); do
  state="$($ADB -s "$EMULATOR_ID" get-state 2>/dev/null || true)"
  boot="$($ADB -s "$EMULATOR_ID" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r' || true)"

  if [[ "$state" == "device" && "$boot" == "1" ]]; then
    echo "Emulator is ready."
    break
  fi

  if (( i == BOOT_TIMEOUT_SECS )); then
    echo "Emulator did not become ready within ${BOOT_TIMEOUT_SECS}s."
    echo "Last lines from /tmp/obs_stream_deck_emulator.log:"
    tail -n 80 /tmp/obs_stream_deck_emulator.log || true
    exit 1
  fi

  sleep 1
done

echo
flutter devices

echo
cd "$PROJECT_DIR"
flutter run -d "$EMULATOR_ID"
