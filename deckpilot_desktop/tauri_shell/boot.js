const STATUS_URL = "http://127.0.0.1:8080/api/health";
const APP_URL = "http://127.0.0.1:8080/";
const statusText = document.getElementById("status-text");
const hintText = document.getElementById("hint-text");
const statusDot = document.getElementById("status-dot");
const retryButton = document.getElementById("retry-button");
const openButton = document.getElementById("open-button");

let attempts = 0;
let redirected = false;

async function checkRuntime() {
  attempts += 1;
  statusText.textContent = "Checking local runtime...";
  hintText.textContent =
    "If startup takes too long, verify that `node` is installed and OBS is not already using the same port.";
  statusDot.classList.remove("ready", "error");

  try {
    const response = await fetch(STATUS_URL, { cache: "no-store" });
    if (!response.ok) {
      throw new Error(`Health returned ${response.status}`);
    }

    statusDot.classList.add("ready");
    statusText.textContent = "Runtime is ready. Opening DeckPilot Desktop...";
    hintText.textContent =
      "The native shell is handing control over to the local OBS desktop runtime.";
    openButton.disabled = false;

    if (!redirected) {
      redirected = true;
      window.location.replace(APP_URL);
    }
    return;
  } catch (error) {
    if (attempts >= 6) {
      statusDot.classList.add("error");
      statusText.textContent = "Local runtime is still offline.";
      hintText.textContent =
        "Retry startup. If it stays offline, check the Tauri terminal for Node startup errors.";
      openButton.disabled = false;
      return;
    }
  }

  window.setTimeout(checkRuntime, 700);
}

retryButton.addEventListener("click", () => {
  attempts = 0;
  redirected = false;
  openButton.disabled = true;
  checkRuntime();
});

openButton.addEventListener("click", () => {
  window.location.href = APP_URL;
});

checkRuntime();
