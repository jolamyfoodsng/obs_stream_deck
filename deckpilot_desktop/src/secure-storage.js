import { execSync } from 'node:child_process';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';

const KEYCHAIN_SERVICE = 'DeckPilotDesktop';
const SECURE_FILE_PATH = path.join(
  os.homedir(),
  '.deckpilot',
  'secure-credentials.json',
);

async function _fileStore(key, value) {
  const dir = path.dirname(SECURE_FILE_PATH);
  await fs.mkdir(dir, { recursive: true });
  let data = {};
  try {
    const raw = await fs.readFile(SECURE_FILE_PATH, 'utf8');
    data = JSON.parse(raw);
  } catch (_) {}
  if (value === null) {
    delete data[key];
  } else {
    data[key] = value;
  }
  await fs.writeFile(SECURE_FILE_PATH, JSON.stringify(data), { mode: 0o600 });
}

async function _fileLoad(key) {
  try {
    const raw = await fs.readFile(SECURE_FILE_PATH, 'utf8');
    const data = JSON.parse(raw);
    return data[key] ?? null;
  } catch (_) {
    return null;
  }
}

async function _fileDelete(key) {
  await _fileStore(key, null);
}

const IS_MACOS = os.platform() === 'darwin';
const IS_WINDOWS = os.platform() === 'win32';

const DPAPI_FILE_PATH = path.join(
  os.homedir(),
  '.deckpilot',
  'dpapi-credentials.enc',
);

function _dpapiEncrypt(plaintext) {
  const encoded = Buffer.from(plaintext, 'utf8').toString('base64');
  const psScript = `
    Add-Type -AssemblyName System.Security
    $bytes = [Convert]::FromBase64String('${encoded}')
    $encrypted = [System.Security.Cryptography.ProtectedData]::Protect(
      $bytes, $null, [System.Security.Cryptography.DataProtectionScope]::CurrentUser
    )
    [Convert]::ToBase64String($encrypted)
  `;

  const result = execSync(
    `powershell -NoProfile -NonInteractive -Command "${psScript.replace(/"/g, '\\"')}"`,
    { stdio: ['ignore', 'pipe', 'ignore'], windowsHide: true },
  );
  return result.toString().trim();
}

function _dpapiDecrypt(encryptedBase64) {
  const psScript = `
    Add-Type -AssemblyName System.Security
    $bytes = [Convert]::FromBase64String('${encryptedBase64}')
    $decrypted = [System.Security.Cryptography.ProtectedData]::Unprotect(
      $bytes, $null, [System.Security.Cryptography.DataProtectionScope]::CurrentUser
    )
    [System.Text.Encoding]::UTF8.GetString($decrypted)
  `;

  const result = execSync(
    `powershell -NoProfile -NonInteractive -Command "${psScript.replace(/"/g, '\\"')}"`,
    { stdio: ['ignore', 'pipe', 'ignore'], windowsHide: true },
  );
  return result.toString().trim();
}

function _dpapiStore(key, value) {
  const dir = path.dirname(DPAPI_FILE_PATH);
  try { fs.mkdirSync(dir, { recursive: true }); } catch (_) {}
  let data = {};
  try { data = JSON.parse(fs.readFileSync(DPAPI_FILE_PATH, 'utf8')); } catch (_) {}

  const encrypted = _dpapiEncrypt(value);
  if (value === null) {
    delete data[key];
  } else {
    data[key] = encrypted;
  }

  fs.writeFileSync(DPAPI_FILE_PATH, JSON.stringify(data), { mode: 0o600 });
}

function _dpapiLoad(key) {
  try {
    const raw = fs.readFileSync(DPAPI_FILE_PATH, 'utf8');
    const data = JSON.parse(raw);
    const encrypted = data[key];
    if (!encrypted) return null;
    return _dpapiDecrypt(encrypted);
  } catch (_) {
    return null;
  }
}

function _dpapiDelete(key) {
  try {
    const raw = fs.readFileSync(DPAPI_FILE_PATH, 'utf8');
    const data = JSON.parse(raw);
    delete data[key];
    fs.writeFileSync(DPAPI_FILE_PATH, JSON.stringify(data), { mode: 0o600 });
  } catch (_) {}
}

function _keychainSet(account, password) {
  const service = KEYCHAIN_SERVICE;
  try {
    execSync(
      `security add-generic-password -a "${account}" -s "${service}" -w "${password}" -U`,
      { stdio: 'ignore' },
    );
  } catch (err) {
    const stderr = err.stderr?.toString() || '';
    if (stderr.includes('already exists') || stderr.includes('-25299')) {
      execSync(
        `security delete-generic-password -a "${account}" -s "${service}"`,
        { stdio: 'ignore' },
      );
      execSync(
        `security add-generic-password -a "${account}" -s "${service}" -w "${password}" -U`,
        { stdio: 'ignore' },
      );
    } else {
      throw err;
    }
  }
}

function _keychainGet(account) {
  try {
    const result = execSync(
      `security find-generic-password -a "${account}" -s "${KEYCHAIN_SERVICE}" -w`,
      { stdio: ['ignore', 'pipe', 'ignore'] },
    );
    return result.toString().trim();
  } catch (_) {
    return null;
  }
}

function _keychainDelete(account) {
  try {
    execSync(
      `security delete-generic-password -a "${account}" -s "${KEYCHAIN_SERVICE}"`,
      { stdio: 'ignore' },
    );
  } catch (_) {}
}

export async function secureStore(key, value) {
  if (typeof value !== 'string') {
    throw new TypeError('secureStore value must be a string');
  }
  if (IS_MACOS) {
    _keychainSet(key, value);
  } else if (IS_WINDOWS) {
    _dpapiStore(key, value);
  } else {
    await _fileStore(key, value);
  }
}

export async function secureLoad(key) {
  if (IS_MACOS) {
    return _keychainGet(key);
  }
  if (IS_WINDOWS) {
    return _dpapiLoad(key);
  }
  return _fileLoad(key);
}

export async function secureDelete(key) {
  if (IS_MACOS) {
    _keychainDelete(key);
  } else if (IS_WINDOWS) {
    _dpapiDelete(key);
  } else {
    await _fileDelete(key);
  }
}

export async function secureStoreAll(entries) {
  for (const [key, value] of Object.entries(entries)) {
    await secureStore(key, value);
  }
}

export async function secureLoadAll(keys) {
  const result = {};
  for (const key of keys) {
    result[key] = await secureLoad(key);
  }
  return result;
}

export async function secureDeleteAll(keys) {
  for (const key of keys) {
    await secureDelete(key);
  }
}
