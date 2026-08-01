#!/usr/bin/env node

import { createReadStream } from 'node:fs';
import fs from 'node:fs/promises';
import { execFile, spawn } from 'node:child_process';
import { createServer } from 'node:http';
import crypto from 'node:crypto';
import dgram from 'node:dgram';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { promisify } from 'node:util';

import { EventSubscription, OBSWebSocket } from 'obs-websocket-js';
import { WebSocketServer } from 'ws';
import {
  PROTOCOL_VERSION,
  MESSAGE_TYPE,
  COMMAND,
  COMMAND_TO_OBS_ACTION,
  ERROR_CODE,
  buildMessage,
  buildError,
  buildCommandResult,
  buildStateSnapshot,
  buildStatePatch,
  buildHelloAck,
} from './src/protocol.js';
import { MDNSAdvertiser } from './src/mdns-advertiser.js';
import { secureLoad, secureStore, secureDelete } from './src/secure-storage.js';
import { CloudRelayClient } from './src/cloud-relay.js';

const AGENT_VERSION = '1.0.0';
const AGENT_STARTED_AT = Date.now();

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const STATIC_ROOT = path.join(__dirname, 'src');
const STATE_FILE = process.env.DECKPILOT_STATE_PATH ||
    path.join(os.homedir(), '.deckpilot', 'desktop-agent-state.json');
const RELAY_BASE_URL =
    'https://deckpilot-relay.solitary-credit-34b2.workers.dev';
const MAX_LOGS = 500;
const STATS_POLL_MS = 1000;
const TOPOLOGY_POLL_MS = 5000;
const RELAY_POLL_MS = 3000;
const RELAY_REFRESH_MS = 4 * 60 * 1000;
const WORKSPACE_PULL_MS = 30 * 1000;
const AUDIO_METER_FLOOR_DB = -60;
const MICROPHONE_SILENCE_THRESHOLD_DB = -55;
const MICROPHONE_SILENCE_WINDOW_MS = 5000;
const NOTIFICATION_TEXT_LIMIT = 240;

const execFileAsync = promisify(execFile);

const DEFAULT_CONFIG = Object.freeze({
  obs_host: '127.0.0.1',
  obs_port: 4455,
  obs_password: '',
  auto_connect: true,
  sync_port: 8080,
  allow_discovery: false,
  automation_paused: false,
  desktop_notifications: false,
});

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function randomPin() {
  let value = '';
  for (let index = 0; index < 6; index += 1) {
    value += Math.floor(Math.random() * 10).toString();
  }
  return value;
}

function randomSecret() {
  return crypto.randomBytes(24).toString('base64url');
}

function isPlainObject(value) {
  return value !== null && typeof value === 'object' && !Array.isArray(value);
}

function cleanString(value, fallback = '') {
  if (typeof value !== 'string') {
    return fallback;
  }
  return value.trim();
}

function truncateText(value, limit = NOTIFICATION_TEXT_LIMIT) {
  const text = cleanString(value, '');
  if (text.length <= limit) {
    return text;
  }
  return `${text.slice(0, Math.max(0, limit - 3)).trimEnd()}...`;
}

function appleScriptString(value) {
  return `"${String(value).replace(/\\/g, '\\\\').replace(/"/g, '\\"')}"`;
}

function powerShellString(value) {
  return `'${String(value).replace(/'/g, "''")}'`;
}

function toInt(value, fallback) {
  if (typeof value === 'number' && Number.isFinite(value)) {
    return Math.trunc(value);
  }
  if (typeof value === 'string') {
    const parsed = Number.parseInt(value.trim(), 10);
    if (Number.isFinite(parsed)) {
      return parsed;
    }
  }
  return fallback;
}

function toFloat(value, fallback) {
  if (typeof value === 'number' && Number.isFinite(value)) {
    return value;
  }
  if (typeof value === 'string') {
    const parsed = Number.parseFloat(value.trim());
    if (Number.isFinite(parsed)) {
      return parsed;
    }
  }
  return fallback;
}

function normalizeName(value) {
  return cleanString(value).toLowerCase();
}

function createInitialObsState() {
  return {
    connection_status: 'disconnected',
    connected: false,
    stream_status: 'offline',
    recording_status: 'stopped',
    current_scene: null,
    preview_scene: null,
    scenes: [],
    audio_sources: [],
    sources: [],
    audio_meters_available: false,
    microphone_silent: false,
    silent_microphone_name: null,
    bitrate_kbps: 0,
    dropped_frames_percent: 0,
    cpu_usage_percent: 0,
    active_fps: 0,
    target_fps: null,
    output_width: null,
    output_height: null,
    average_frame_render_time_ms: 0,
    render_skipped_frames: 0,
    render_total_frames: 0,
    uptime_ms: 0,
    stream_timecode: null,
    stream_output_bytes: 0,
    studio_mode_enabled: false,
    virtual_camera_active: false,
    connection_latency_ms: null,
    output_reconnecting: false,
    output_congestion: 0,
    output_skipped_frames: 0,
    output_total_frames: 0,
    recording_duration_ms: 0,
    recording_timecode: null,
    last_error: null,
  };
}

function createDefaultState() {
  return {
    config: { ...DEFAULT_CONFIG },
    macros: [],
    automations: [],
    pages: [],
    pinnedIds: [],
    desktopId: crypto.randomUUID(),
    workspaceId: null,
    workspaceToken: null,
    workspaceRevision: 0,
    pairingPin: randomPin(),
    pairingSecret: randomSecret(),
    pairedDevice: null,
    roomCode: null,
    lastSyncAt: null,
    lastCloudSyncAt: null,
    accountEmail: null,
    accountLinked: false,
    accountLinkingRequestId: null,
    accountLinkingCode: null,
    accountLinkingExpiresAt: null,
    deviceToken: null,
    workspaceName: null,
    activityLog: [],
    accountLinkError: null,
    desktopName: os.hostname(),
    lastCloudSyncStatus: null,
    lastCloudSyncRevision: 0,
    firstRunConsentAccepted: false,
    notificationPermissionAsked: false,
  };
}

function normalizeConfig(rawConfig, currentConfig = DEFAULT_CONFIG) {
  const incoming = isPlainObject(rawConfig) ? rawConfig : {};
  return {
    obs_host: cleanString(incoming.obs_host, currentConfig.obs_host),
    obs_port: toInt(incoming.obs_port, currentConfig.obs_port),
    obs_password:
      typeof incoming.obs_password === 'string'
        ? incoming.obs_password
        : currentConfig.obs_password,
    auto_connect:
      typeof incoming.auto_connect === 'boolean'
        ? incoming.auto_connect
        : currentConfig.auto_connect,
    sync_port: toInt(incoming.sync_port, currentConfig.sync_port),
    allow_discovery:
      typeof incoming.allow_discovery === 'boolean'
        ? incoming.allow_discovery
        : currentConfig.allow_discovery,
    automation_paused:
      typeof incoming.automation_paused === 'boolean'
        ? incoming.automation_paused
        : currentConfig.automation_paused,
    desktop_notifications:
      typeof incoming.desktop_notifications === 'boolean'
        ? incoming.desktop_notifications
        : currentConfig.desktop_notifications,
  };
}

function normalizePersistedState(raw) {
  const fallback = createDefaultState();
  if (!isPlainObject(raw)) {
    return fallback;
  }

  return {
    config: normalizeConfig(raw.config, fallback.config),
    macros: Array.isArray(raw.macros) ? raw.macros : [],
    automations: Array.isArray(raw.automations) ? raw.automations : [],
    pages: Array.isArray(raw.pages) ? raw.pages : [],
    pinnedIds: Array.isArray(raw.pinnedIds)
      ? raw.pinnedIds.filter((entry) => typeof entry === 'string')
      : [],
    desktopId: cleanString(raw.desktopId, fallback.desktopId) || fallback.desktopId,
    workspaceId: cleanString(raw.workspaceId, '') || null,
    workspaceToken: cleanString(raw.workspaceToken, '') || null,
    workspaceRevision: toInt(raw.workspaceRevision, 0),
    pairingPin: cleanString(raw.pairingPin, fallback.pairingPin) || fallback.pairingPin,
    pairingSecret:
      cleanString(raw.pairingSecret, fallback.pairingSecret) || fallback.pairingSecret,
    pairedDevice: isPlainObject(raw.pairedDevice) ? raw.pairedDevice : null,
    roomCode: cleanString(raw.roomCode, '') || null,
    lastSyncAt:
      typeof raw.lastSyncAt === 'string' && raw.lastSyncAt.trim()
        ? raw.lastSyncAt
        : null,
    lastCloudSyncAt:
      typeof raw.lastCloudSyncAt === 'string' && raw.lastCloudSyncAt.trim()
        ? raw.lastCloudSyncAt
        : null,
    accountEmail: cleanString(raw.accountEmail, '') || null,
    accountLinked: typeof raw.accountLinked === 'boolean' ? raw.accountLinked : false,
    accountLinkingRequestId: cleanString(raw.accountLinkingRequestId, '') || null,
    accountLinkingCode: cleanString(raw.accountLinkingCode, '') || null,
    accountLinkingExpiresAt: cleanString(raw.accountLinkingExpiresAt, '') || null,
    deviceToken: cleanString(raw.deviceToken, '') || null,
    workspaceName: cleanString(raw.workspaceName, '') || null,
    activityLog: Array.isArray(raw.activityLog) ? raw.activityLog : [],
    accountLinkError: cleanString(raw.accountLinkError, '') || null,
    desktopName: cleanString(raw.desktopName, '') || fallback.desktopName,
    lastCloudSyncStatus: cleanString(raw.lastCloudSyncStatus, '') || null,
    lastCloudSyncRevision: toInt(raw.lastCloudSyncRevision, 0),
    firstRunConsentAccepted: typeof raw.firstRunConsentAccepted === 'boolean' ? raw.firstRunConsentAccepted : false,
    notificationPermissionAsked:
      typeof raw.notificationPermissionAsked === 'boolean'
        ? raw.notificationPermissionAsked
        : false,
  };
}

function mergeSettingsInput(currentConfig, rawInput, activePort) {
  const body = isPlainObject(rawInput) ? rawInput : {};
  return {
    ...currentConfig,
    obs_host: cleanString(body.obs_host, currentConfig.obs_host),
    obs_port: toInt(body.obs_port, currentConfig.obs_port),
    obs_password:
      typeof body.obs_password === 'string'
        ? body.obs_password
        : currentConfig.obs_password,
    auto_connect:
      typeof body.auto_connect === 'boolean'
        ? body.auto_connect
        : currentConfig.auto_connect,
    allow_discovery:
      typeof body.allow_discovery === 'boolean'
        ? body.allow_discovery
        : currentConfig.allow_discovery,
    desktop_notifications:
      typeof body.desktop_notifications === 'boolean'
        ? body.desktop_notifications
        : currentConfig.desktop_notifications,
    sync_port: activePort,
  };
}

function shallowCloneState(value) {
  return JSON.parse(JSON.stringify(value));
}

function flattenNumbers(value) {
  if (!Array.isArray(value)) {
    return [];
  }

  const output = [];
  for (const item of value) {
    if (Array.isArray(item)) {
      output.push(...flattenNumbers(item));
      continue;
    }
    if (typeof item === 'number' && Number.isFinite(item)) {
      output.push(item);
    }
  }
  return output;
}

function meterMulToDb(value) {
  if (!Number.isFinite(value) || value <= 0) {
    return AUDIO_METER_FLOOR_DB;
  }
  return Math.max(AUDIO_METER_FLOOR_DB, 20 * Math.log10(value));
}

function extractMeterLevelDb(meter) {
  if (!isPlainObject(meter)) {
    return null;
  }

  for (const key of ['inputLevelsDb', 'inputPeakDb', 'levelsDb']) {
    const values = flattenNumbers(meter[key]);
    if (values.length > 0) {
      return Math.max(...values);
    }
  }

  for (const key of ['inputLevelsMul', 'inputPeakMul', 'levelsMul']) {
    const values = flattenNumbers(meter[key]);
    if (values.length > 0) {
      return Math.max(...values.map(meterMulToDb));
    }
  }

  return null;
}

function isLoopbackAddress(address) {
  if (!address) {
    return false;
  }
  return (
    address === '127.0.0.1' ||
    address === '::1' ||
    address === '::ffff:127.0.0.1'
  );
}

function contentTypeFor(filePath) {
  const extension = path.extname(filePath).toLowerCase();
  switch (extension) {
    case '.html':
      return 'text/html; charset=utf-8';
    case '.css':
      return 'text/css; charset=utf-8';
    case '.js':
      return 'application/javascript; charset=utf-8';
    case '.json':
      return 'application/json; charset=utf-8';
    case '.svg':
      return 'image/svg+xml';
    case '.png':
      return 'image/png';
    case '.jpg':
    case '.jpeg':
      return 'image/jpeg';
    default:
      return 'application/octet-stream';
  }
}

function sortAutomations(rules) {
  if (!Array.isArray(rules)) return [];
  return rules.sort((a, b) => {
    const aIsStarter = a && a.isStarter === true ? 1 : 0;
    const bIsStarter = b && b.isStarter === true ? 1 : 0;
    return aIsStarter - bIsStarter;
  });
}

async function readJsonBody(request) {
  const chunks = [];
  for await (const chunk of request) {
    chunks.push(chunk);
  }

  const raw = Buffer.concat(chunks).toString('utf8').trim();
  if (!raw) {
    return {};
  }

  const parsed = JSON.parse(raw);
  return isPlainObject(parsed) ? parsed : {};
}

function sendJson(response, statusCode, body) {
  response.statusCode = statusCode;
  response.setHeader('Content-Type', 'application/json');
  response.setHeader('Access-Control-Allow-Origin', '*');
  response.setHeader('Access-Control-Allow-Methods', 'GET, POST, DELETE, OPTIONS');
  response.setHeader('Access-Control-Allow-Headers', 'Content-Type, Authorization');
  response.end(JSON.stringify(body));
}

function sendNotFound(response) {
  sendJson(response, 404, { error: 'Not found.' });
}

function sendUnauthorized(response) {
  sendJson(response, 401, { error: 'Unauthorized.' });
}

function pickSceneFlagged(scenes, currentProgram, currentPreview) {
  return scenes.map((scene) => ({
    ...scene,
    isProgram: normalizeName(scene.name) === normalizeName(currentProgram),
    isPreview: normalizeName(scene.name) === normalizeName(currentPreview),
  }));
}

function mapStreamStatus(active, outputState) {
  const normalized = cleanString(outputState).toUpperCase();
  if (normalized.includes('STARTING')) {
    return 'starting';
  }
  if (normalized.includes('STOPPING')) {
    return 'stopping';
  }
  if (normalized.includes('ERROR')) {
    return 'error';
  }
  return active ? 'live' : 'offline';
}

function mapRecordingStatus(active, outputState) {
  const normalized = cleanString(outputState).toUpperCase();
  if (normalized.includes('STARTING')) {
    return 'starting';
  }
  if (normalized.includes('STOPPING')) {
    return 'stopping';
  }
  if (normalized.includes('ERROR')) {
    return 'error';
  }
  if (normalized.includes('PAUSE')) {
    return 'paused';
  }
  return active ? 'recording' : 'stopped';
}

function defaultThreshold(trigger) {
  switch (trigger) {
    case 'droppedFramesHigh':
      return 5;
    case 'bitrateLowForDuration':
      return 3000;
    case 'cpuEncodingOverload':
      return 85;
    default:
      return null;
  }
}

function defaultDurationSeconds(trigger) {
  switch (trigger) {
    case 'obsConnectionLost':
      return 5;
    case 'streamEndedUnexpectedly':
      return 3;
    case 'cameraSourceLost':
      return 5;
    case 'droppedFramesHigh':
    case 'bitrateLowForDuration':
    case 'cpuEncodingOverload':
      return 10;
    case 'micSilentWhileLive':
      return 8;
    case 'streamLiveButRecordingOff':
      return 15;
    case 'brbSceneActiveTooLong':
      return 120;
    default:
      return 0;
  }
}

function defaultCooldownSeconds(trigger) {
  switch (trigger) {
    case 'obsConnectionLost':
    case 'streamEndedUnexpectedly':
    case 'cameraSourceLost':
    case 'micSilentWhileLive':
    case 'micMutedOnSpeakingScene':
      return 30;
    case 'droppedFramesHigh':
    case 'bitrateLowForDuration':
    case 'cpuEncodingOverload':
    case 'streamLiveButRecordingOff':
      return 45;
    case 'brbSceneActiveTooLong':
      return 120;
    default:
      return 24;
  }
}

function isLegacyTrigger(trigger) {
  return [
    'streamStarted',
    'streamStopped',
    'recordingStarted',
    'recordingStopped',
    'sceneChanged',
    'micMuted',
    'micUnmuted',
    'droppedFramesDetected',
    'bitrateLow',
    'obsDisconnected',
    'networkInstabilityDetected',
  ].includes(trigger);
}

function requiredMetadataInt(action, fallback) {
  if (!isPlainObject(action) || !isPlainObject(action.metadata)) {
    return fallback;
  }
  return toInt(action.metadata.value, fallback);
}

function requiredMetadataFloat(action, fallback) {
  if (!isPlainObject(action) || !isPlainObject(action.metadata)) {
    return fallback;
  }
  return toFloat(action.metadata.value, fallback);
}

class StateStore {
  constructor(filePath) {
    this.filePath = filePath;
  }

  async load() {
    try {
      const raw = await fs.readFile(this.filePath, 'utf8');
      return normalizePersistedState(JSON.parse(raw));
    } catch (_) {
      const initial = createDefaultState();
      await this.save(initial);
      return initial;
    }
  }

  async save(state) {
    await fs.mkdir(path.dirname(this.filePath), { recursive: true });
    await fs.writeFile(this.filePath, `${JSON.stringify(state, null, 2)}\n`, 'utf8');
  }
}

class ObsConnector {
  constructor({ log, onStateChange, onStatePatch }) {
    this.log = log;
    this.onStateChange = onStateChange;
    this.onStatePatch = onStatePatch;
    this.state = createInitialObsState();
    this.obs = null;
    this.connected = false;
    this.connecting = false;
    this.stopping = false;
    this.manualDisconnect = false;
    this.lastConfig = null;
    this.reconnectTimer = null;
    this.statsTimer = null;
    this.topologyTimer = null;
    this.unsupportedMuteInputs = new Set();
    this.lastAudibleAtByInput = new Map();
    this.recentBitrateSamples = [];
    this.lastOutputBytes = null;
    this.lastOutputBytesAt = null;
  }

  getState() {
    return shallowCloneState(this.state);
  }

  async startAutoConnect(config) {
    const host = cleanString(config?.host || config?.obs_host, '');
    if (!config || !host) {
      return;
    }
    await this.connect(config);
  }

  async connect(config) {
    const safeConfig = {
      host: cleanString(config.host || config.obs_host, '127.0.0.1'),
      port: toInt(config.port || config.obs_port, 4455),
      password:
        typeof config.password === 'string'
          ? config.password
          : typeof config.obs_password === 'string'
            ? config.obs_password
            : '',
    };

    this.lastConfig = safeConfig;
    this.manualDisconnect = false;
    this.stopping = false;
    this.clearReconnectTimer();

    if (this.connecting) {
      throw new Error('OBS connection is already in progress.');
    }

    await this.disposeClient({ preserveState: true });

    this.connecting = true;
    this.updateState({
      connection_status: 'connecting',
      connected: false,
      last_error: null,
    });

    const obs = new OBSWebSocket();
    this.attachClient(obs);
    this.obs = obs;

    const startedAt = Date.now();

    try {
      await obs.connect(
        `ws://${safeConfig.host}:${safeConfig.port}`,
        safeConfig.password || undefined,
        {
          rpcVersion: 1,
          eventSubscriptions:
            EventSubscription.All | EventSubscription.InputVolumeMeters,
        },
      );

      const latencyStart = Date.now();
      await obs.call('GetVersion');
      const connectionLatencyMs = Date.now() - latencyStart;

      this.connected = true;
      this.connecting = false;
      this.recentBitrateSamples = [];
      this.lastOutputBytes = null;
      this.lastOutputBytesAt = null;

      await this.refreshState();
      this.updateState({
        connection_status: 'connected',
        connected: true,
        connection_latency_ms: connectionLatencyMs,
        last_error: null,
      });
      this.startPolling();
      this.log(
        'obs',
        `Connected to OBS at ${safeConfig.host}:${safeConfig.port} in ${Date.now() - startedAt}ms.`,
      );
    } catch (error) {
      this.connecting = false;
      await this.disposeClient({ preserveState: true });
      const message = error instanceof Error ? error.message : String(error);
      this.updateDisconnectedState('error', message);
      this.log('error', `OBS connection failed: ${message}`);
      throw error;
    }
  }

  async disconnect({ manual = true } = {}) {
    this.manualDisconnect = manual;
    this.stopping = manual;
    this.clearReconnectTimer();
    await this.disposeClient({ preserveState: true });
    this.updateDisconnectedState('disconnected', null);
  }

  async stop() {
    this.manualDisconnect = true;
    this.stopping = true;
    this.clearReconnectTimer();
    await this.disposeClient({ preserveState: true });
  }

  async testConnection(config) {
    const obs = new OBSWebSocket();
    try {
      await obs.connect(
        `ws://${cleanString(config.host || config.obs_host, '127.0.0.1')}:${toInt(config.port || config.obs_port, 4455)}`,
        typeof config.password === 'string'
          ? config.password
          : config.obs_password || undefined,
        { rpcVersion: 1 },
      );
      await obs.disconnect();
    } finally {
      obs.removeAllListeners();
    }
  }

  attachClient(obs) {
    obs.on('ConnectionClosed', (error) => {
      this.connected = false;
      this.connecting = false;
      this.stopPolling();

      if (this.stopping || this.manualDisconnect) {
        return;
      }

      const message = error instanceof Error ? error.message : String(error);
      this.updateDisconnectedState('reconnecting', message || 'OBS disconnected.');
      this.log('error', `OBS disconnected: ${message || 'Connection closed.'}`);
      this.scheduleReconnect();
    });

    obs.on('CurrentProgramSceneChanged', (event) => {
      const currentScene = cleanString(event.sceneName, '') || null;
      const scenes = pickSceneFlagged(
        this.state.scenes,
        currentScene,
        this.state.preview_scene,
      );
      this.updateState({ current_scene: currentScene, scenes });
    });

    obs.on('CurrentPreviewSceneChanged', (event) => {
      const previewScene = cleanString(event.sceneName, '') || null;
      const scenes = pickSceneFlagged(
        this.state.scenes,
        this.state.current_scene,
        previewScene,
      );
      this.updateState({ preview_scene: previewScene, scenes });
    });

    obs.on('StudioModeStateChanged', (event) => {
      this.updateState({
        studio_mode_enabled: !!event.studioModeEnabled,
      });
    });

    obs.on('VirtualcamStateChanged', (event) => {
      this.updateState({
        virtual_camera_active: this.resolveVirtualCameraActive(event),
      });
    });

    obs.on('StreamStateChanged', (event) => {
      this.updateState({
        stream_status: mapStreamStatus(!!event.outputActive, event.outputState),
        output_reconnecting: !!event.outputReconnecting,
      });
    });

    obs.on('RecordStateChanged', (event) => {
      this.updateState({
        recording_status: mapRecordingStatus(!!event.outputActive, event.outputState),
      });
    });

    obs.on('InputMuteStateChanged', (event) => {
      const audioSources = this.state.audio_sources.map((source) => {
        if (source.id !== event.inputName && source.name !== event.inputName) {
          return source;
        }
        return {
          ...source,
          isMuted: !!event.inputMuted,
        };
      });
      this.updateAudioState(audioSources);
    });

    obs.on('SceneItemEnableStateChanged', (event) => {
      const key = `${event.sceneName}::${event.sceneItemId}`;
      const sources = this.state.sources.map((source) => {
        if (source.id !== key) {
          return source;
        }
        return {
          ...source,
          isVisible: !!event.sceneItemEnabled,
        };
      });
      this.updateState({ sources });
    });

    obs.on('SceneListChanged', () => {
      this.refreshTopology().catch(() => {});
    });

    obs.on('InputCreated', () => {
      this.refreshInputs().catch(() => {});
    });

    obs.on('InputRemoved', () => {
      this.refreshInputs().catch(() => {});
    });

    obs.on('InputVolumeMeters', (event) => {
      this.applyInputMeters(event.inputs);
    });
  }

  async disposeClient({ preserveState }) {
    this.stopPolling();
    if (!this.obs) {
      return;
    }

    const previous = this.obs;
    this.obs = null;
    previous.removeAllListeners();

    try {
      await previous.disconnect();
    } catch (_) {}

    this.connected = false;
    this.connecting = false;

    if (!preserveState) {
      this.updateDisconnectedState('disconnected', null);
    }
  }

  clearReconnectTimer() {
    if (this.reconnectTimer) {
      clearTimeout(this.reconnectTimer);
      this.reconnectTimer = null;
    }
  }

  scheduleReconnect() {
    if (this.reconnectTimer || !this.lastConfig || this.stopping) {
      return;
    }

    this.reconnectTimer = setTimeout(async () => {
      this.reconnectTimer = null;
      if (!this.lastConfig || this.stopping) {
        return;
      }
      try {
        await this.connect(this.lastConfig);
      } catch (_) {
        this.scheduleReconnect();
      }
    }, 5000);
  }

  stopPolling() {
    if (this.statsTimer) {
      clearInterval(this.statsTimer);
      this.statsTimer = null;
    }
    if (this.topologyTimer) {
      clearInterval(this.topologyTimer);
      this.topologyTimer = null;
    }
  }

  startPolling() {
    this.stopPolling();
    this.statsTimer = setInterval(() => {
      this.refreshStats().catch(() => {});
    }, STATS_POLL_MS);
    this.topologyTimer = setInterval(() => {
      this.refreshTopology().catch(() => {});
    }, TOPOLOGY_POLL_MS);
  }

  updateDisconnectedState(status, message) {
    this.recentBitrateSamples = [];
    this.lastOutputBytes = null;
    this.lastOutputBytesAt = null;
    this.updateState({
      connection_status: status,
      connected: false,
      stream_status: 'offline',
      recording_status: 'stopped',
      bitrate_kbps: 0,
      dropped_frames_percent: 0,
      output_reconnecting: false,
      connection_latency_ms: null,
      last_error: message || null,
    });
  }

  updateState(patch) {
    this.state = {
      ...this.state,
      ...patch,
    };

    if (Array.isArray(this.state.scenes)) {
      this.state.scenes = pickSceneFlagged(
        this.state.scenes,
        this.state.current_scene,
        this.state.preview_scene,
      );
    }

    if (typeof this.onStatePatch === 'function') {
      this.onStatePatch(patch);
    }

    if (typeof this.onStateChange === 'function') {
      this.onStateChange(this.getState());
    }
  }

  updateAudioState(audioSources) {
    const nextAudioSources = audioSources.map((source) => ({
      id: source.id,
      name: source.name,
      isMuted: !!source.isMuted,
      volume:
        typeof source.volume === 'number' && Number.isFinite(source.volume)
          ? source.volume
          : 0,
      levelDb:
        typeof source.levelDb === 'number' && Number.isFinite(source.levelDb)
          ? source.levelDb
          : AUDIO_METER_FLOOR_DB,
      hasLiveMeter: !!source.hasLiveMeter,
    }));

    let silentMicrophoneName = null;
    let microphoneSilent = false;

    if (this.state.audio_meters_available) {
      const microphone = this.selectPrimaryMicrophone(nextAudioSources);
      if (microphone) {
        const lastAudibleAt = this.lastAudibleAtByInput.get(microphone.id) || 0;
        const silentForMs = Date.now() - lastAudibleAt;
        if (!microphone.isMuted && silentForMs >= MICROPHONE_SILENCE_WINDOW_MS) {
          microphoneSilent = true;
          silentMicrophoneName = microphone.name;
        }
      }
    }

    this.updateState({
      audio_sources: nextAudioSources,
      microphone_silent: microphoneSilent,
      silent_microphone_name: silentMicrophoneName,
    });
  }

  async refreshState() {
    await this.refreshTopology();
    await this.refreshStudioMode();
    await this.refreshVirtualCameraStatus();
    await this.refreshVideoSettings();
    await this.refreshStats();
  }

  async refreshTopology() {
    if (!this.obs || !this.connected) {
      return;
    }

    const sceneList = await this.obs.call('GetSceneList');
    const currentProgram = cleanString(sceneList.currentProgramSceneName, '') || null;
    const currentPreview = cleanString(sceneList.currentPreviewSceneName, '') || null;
    const rawScenes = Array.isArray(sceneList.scenes) ? sceneList.scenes : [];
    const scenes = rawScenes
      .map((scene) => ({
        id: cleanString(scene.sceneName, ''),
        name: cleanString(scene.sceneName, ''),
      }))
      .filter((scene) => scene.name)
      .map((scene) => ({
        ...scene,
        isProgram: false,
        isPreview: false,
      }));

    const sourceResults = await Promise.allSettled(
      scenes.map(async (scene) => {
        const response = await this.obs.call('GetSceneItemList', {
          sceneName: scene.name,
        });
        return Array.isArray(response.sceneItems) ? response.sceneItems : [];
      }),
    );

    const sources = [];
    for (let index = 0; index < scenes.length; index += 1) {
      const result = sourceResults[index];
      if (result.status !== 'fulfilled') {
        continue;
      }
      for (const item of result.value) {
        const sourceName = cleanString(item.sourceName, '');
        const sceneItemId = toInt(item.sceneItemId, -1);
        if (!sourceName || sceneItemId < 0) {
          continue;
        }
        sources.push({
          id: `${scenes[index].name}::${sceneItemId}`,
          name: sourceName,
          sceneId: scenes[index].name,
          isVisible: item.sceneItemEnabled !== false,
        });
      }
    }

    this.updateState({
      current_scene: currentProgram,
      preview_scene: currentPreview,
      scenes,
      sources,
    });

    await this.refreshInputs();
  }

  async refreshInputs() {
    if (!this.obs || !this.connected) {
      return;
    }

    const response = await this.obs.call('GetInputList');
    const inputs = Array.isArray(response.inputs) ? response.inputs : [];
    const existingById = new Map(
      this.state.audio_sources.map((source) => [source.id, source]),
    );

    const audioSources = [];
    for (const input of inputs) {
      const inputName = cleanString(input.inputName, '');
      if (!inputName || this.unsupportedMuteInputs.has(inputName)) {
        continue;
      }

      try {
        const [muteResult, volumeResult] = await Promise.all([
          this.obs.call('GetInputMute', { inputName }),
          this.obs.call('GetInputVolume', { inputName }).catch(() => ({})),
        ]);

        const previous = existingById.get(inputName);
        audioSources.push({
          id: inputName,
          name: inputName,
          isMuted: !!muteResult.inputMuted,
          volume:
            typeof volumeResult.inputVolumeMul === 'number'
              ? volumeResult.inputVolumeMul
              : previous?.volume || 0,
          levelDb: previous?.levelDb ?? AUDIO_METER_FLOOR_DB,
          hasLiveMeter: previous?.hasLiveMeter ?? false,
        });
      } catch (error) {
        const code = error && typeof error === 'object' ? error.code : null;
        if (String(code) === '604') {
          this.unsupportedMuteInputs.add(inputName);
        }
      }
    }

    this.updateAudioState(audioSources);
  }

  async refreshStudioMode() {
    if (!this.obs || !this.connected) {
      return;
    }
    try {
      const response = await this.obs.call('GetStudioModeEnabled');
      this.updateState({
        studio_mode_enabled: !!response.studioModeEnabled,
      });
    } catch (_) {}
  }

  async refreshVirtualCameraStatus() {
    if (!this.obs || !this.connected) {
      return;
    }
    try {
      const response = await this.obs.call('GetVirtualCamStatus');
      this.updateState({
        virtual_camera_active: this.resolveVirtualCameraActive(response),
      });
    } catch (_) {}
  }

  async refreshVideoSettings() {
    if (!this.obs || !this.connected) {
      return;
    }
    try {
      const response = await this.obs.call('GetVideoSettings');
      const numerator = toFloat(response.fpsNumerator, NaN);
      const denominator = toFloat(response.fpsDenominator, NaN);
      let targetFps = null;
      if (Number.isFinite(numerator) && Number.isFinite(denominator) && denominator > 0) {
        targetFps = numerator / denominator;
      } else if (Number.isFinite(response.fps)) {
        targetFps = response.fps;
      }

      this.updateState({
        target_fps: targetFps,
        output_width: toInt(response.outputWidth ?? response.baseWidth, null),
        output_height: toInt(response.outputHeight ?? response.baseHeight, null),
      });
    } catch (_) {}
  }

  async refreshStats() {
    if (!this.obs || !this.connected) {
      return;
    }

    const [statsData, streamData, recordData] = await Promise.all([
      this.obs.call('GetStats').catch(() => ({})),
      this.obs.call('GetStreamStatus').catch(() => ({})),
      this.obs.call('GetRecordStatus').catch(() => ({})),
    ]);

    const streamActive = !!streamData.outputActive;
    const recordActive = !!recordData.outputActive;
    const outputSkippedFrames = toInt(
      streamData.outputSkippedFrames ?? statsData.outputSkippedFrames,
      0,
    );
    const outputTotalFrames = toInt(
      streamData.outputTotalFrames ?? statsData.outputTotalFrames,
      0,
    );
    const droppedFramesPercent =
      outputTotalFrames > 0 ? (outputSkippedFrames / outputTotalFrames) * 100 : 0;
    const streamOutputBytes = toInt(streamData.outputBytes, this.lastOutputBytes || 0);

    this.updateState({
      stream_status: mapStreamStatus(streamActive, streamData.outputState),
      recording_status: mapRecordingStatus(recordActive, recordData.outputState),
      bitrate_kbps: this.deriveBitrateKbps(streamActive, streamOutputBytes),
      dropped_frames_percent: streamActive ? droppedFramesPercent : 0,
      cpu_usage_percent: toFloat(statsData.cpuUsage, 0),
      active_fps: toFloat(statsData.activeFps, 0),
      average_frame_render_time_ms: toFloat(statsData.averageFrameRenderTime, 0),
      render_skipped_frames: toInt(statsData.renderSkippedFrames, 0),
      render_total_frames: toInt(statsData.renderTotalFrames, 0),
      uptime_ms: streamActive ? toInt(streamData.outputDuration, 0) : 0,
      stream_timecode:
        streamActive && typeof streamData.outputTimecode === 'string'
          ? streamData.outputTimecode
          : null,
      stream_output_bytes: streamActive ? streamOutputBytes : 0,
      output_reconnecting: !!streamData.outputReconnecting,
      output_congestion: toFloat(streamData.outputCongestion, 0),
      output_skipped_frames: streamActive ? outputSkippedFrames : 0,
      output_total_frames: streamActive ? outputTotalFrames : 0,
      recording_duration_ms: recordActive ? toInt(recordData.outputDuration, 0) : 0,
      recording_timecode:
        recordActive && typeof recordData.outputTimecode === 'string'
          ? recordData.outputTimecode
          : null,
      last_error: null,
    });
  }

  deriveBitrateKbps(streamActive, outputBytes) {
    if (!streamActive) {
      this.recentBitrateSamples = [];
      this.lastOutputBytes = null;
      this.lastOutputBytesAt = null;
      return 0;
    }

    const now = Date.now();
    const previousBytes = this.lastOutputBytes;
    const previousAt = this.lastOutputBytesAt;

    this.lastOutputBytes = outputBytes;
    this.lastOutputBytesAt = now;

    if (previousBytes === null || previousAt === null || outputBytes < previousBytes) {
      return this.smoothedBitrateKbps();
    }

    const deltaBytes = outputBytes - previousBytes;
    const deltaMs = now - previousAt;
    if (deltaMs <= 0) {
      return this.smoothedBitrateKbps();
    }

    const kbps = (deltaBytes * 8) / deltaMs;
    if (Number.isFinite(kbps) && kbps >= 0) {
      this.recentBitrateSamples.push(kbps);
      while (this.recentBitrateSamples.length > 5) {
        this.recentBitrateSamples.shift();
      }
    }

    return this.smoothedBitrateKbps();
  }

  smoothedBitrateKbps() {
    if (this.recentBitrateSamples.length === 0) {
      return 0;
    }
    const total = this.recentBitrateSamples.reduce((sum, entry) => sum + entry, 0);
    return Math.round(total / this.recentBitrateSamples.length);
  }

  resolveVirtualCameraActive(data) {
    if (typeof data.outputActive === 'boolean') {
      return data.outputActive;
    }
    const outputState = cleanString(data.outputState).toUpperCase();
    if (
      outputState.includes('START') ||
      outputState.includes('RUNNING') ||
      outputState.includes('ACTIVE')
    ) {
      return true;
    }
    if (
      outputState.includes('STOP') ||
      outputState.includes('INACTIVE') ||
      outputState === 'OFF'
    ) {
      return false;
    }
    return this.state.virtual_camera_active;
  }

  applyInputMeters(entries) {
    if (!Array.isArray(entries) || entries.length === 0) {
      return;
    }

    const existing = new Map(
      this.state.audio_sources.map((source) => [source.id, { ...source }]),
    );
    let hasMeter = false;

    for (const entry of entries) {
      const inputName = cleanString(entry.inputName, '');
      if (!inputName || !existing.has(inputName)) {
        continue;
      }
      const levelDb = extractMeterLevelDb(entry);
      if (levelDb === null) {
        continue;
      }
      hasMeter = true;
      if (levelDb > MICROPHONE_SILENCE_THRESHOLD_DB) {
        this.lastAudibleAtByInput.set(inputName, Date.now());
      }
      existing.set(inputName, {
        ...existing.get(inputName),
        levelDb,
        hasLiveMeter: true,
      });
    }

    if (!hasMeter) {
      return;
    }

    this.updateState({ audio_meters_available: true });
    this.updateAudioState(Array.from(existing.values()));
  }

  selectPrimaryMicrophone(audioSources) {
    if (!Array.isArray(audioSources) || audioSources.length === 0) {
      return null;
    }
    const preferred = audioSources.find((source) => {
      const name = normalizeName(source.name);
      return name.includes('mic') || name.includes('microphone');
    });
    return preferred || audioSources[0];
  }

  resolveSceneName(targetIdOrName) {
    const target = cleanString(targetIdOrName, '');
    if (!target) {
      return null;
    }

    const direct = this.state.scenes.find(
      (scene) => scene.id === target || normalizeName(scene.name) === normalizeName(target),
    );
    if (direct) {
      return direct.name;
    }

    const normalizedTarget = normalizeName(target).replace(/^scene/, '');
    const fuzzy = this.state.scenes.find((scene) => {
      const normalizedScene = normalizeName(scene.name);
      return (
        normalizedScene === normalizedTarget ||
        normalizedScene.includes(normalizedTarget) ||
        normalizedTarget.includes(normalizedScene)
      );
    });
    return fuzzy ? fuzzy.name : null;
  }

  resolveAudioInputName(targetIdOrName) {
    const target = cleanString(targetIdOrName, '');
    if (!target) {
      return null;
    }

    const direct = this.state.audio_sources.find(
      (source) => source.id === target || normalizeName(source.name) === normalizeName(target),
    );
    if (direct) {
      return direct.id;
    }

    const normalizedTarget = normalizeName(target).replace(/^audio/, '');
    const fuzzy = this.state.audio_sources.find((source) => {
      const normalizedSource = normalizeName(source.name);
      return (
        normalizedSource === normalizedTarget ||
        normalizedSource.includes(normalizedTarget) ||
        normalizedTarget.includes(normalizedSource)
      );
    });
    return fuzzy ? fuzzy.id : null;
  }

  resolveSourceTarget(targetIdOrName) {
    const target = cleanString(targetIdOrName, '');
    if (!target) {
      return null;
    }

    if (target.includes('::')) {
      const [sceneName, itemIdRaw] = target.split('::');
      const sceneItemId = toInt(itemIdRaw, -1);
      const direct = this.state.sources.find((source) => source.id === target);
      if (direct && sceneItemId >= 0) {
        return {
          sceneName,
          sceneItemId,
          sourceName: direct.name,
          sceneItemKey: direct.id,
        };
      }
    }

    const direct = this.state.sources.find(
      (source) => source.id === target || normalizeName(source.name) === normalizeName(target),
    );
    if (direct) {
      const itemId = toInt(direct.id.split('::')[1], -1);
      if (itemId >= 0) {
        return {
          sceneName: direct.sceneId,
          sceneItemId: itemId,
          sourceName: direct.name,
          sceneItemKey: direct.id,
        };
      }
    }

    const normalizedTarget = normalizeName(target);
    const fuzzy = this.state.sources.find((source) => {
      const normalizedSource = normalizeName(source.name);
      return (
        normalizedSource === normalizedTarget ||
        normalizedSource.includes(normalizedTarget) ||
        normalizedTarget.includes(normalizedSource)
      );
    });
    if (!fuzzy) {
      return null;
    }

    const itemId = toInt(fuzzy.id.split('::')[1], -1);
    if (itemId < 0) {
      return null;
    }

    return {
      sceneName: fuzzy.sceneId,
      sceneItemId: itemId,
      sourceName: fuzzy.name,
      sceneItemKey: fuzzy.id,
    };
  }

  resolveSourceName(targetIdOrName) {
    const target = this.resolveSourceTarget(targetIdOrName);
    return target ? target.sourceName : null;
  }

  async executeButtonAction(action) {
    if (!this.obs || !this.connected) {
      throw new Error('Connect to OBS before executing actions.');
    }

    switch (action.type) {
      case 'switchScene': {
        const sceneName = this.resolveSceneName(action.targetId || action.targetName);
        if (!sceneName) {
          throw new Error('Scene not found.');
        }
        await this.obs.call('SetCurrentProgramScene', { sceneName });
        await this.refreshTopology();
        return;
      }
      case 'setPreviewScene': {
        const sceneName = this.resolveSceneName(action.targetId || action.targetName);
        if (!sceneName) {
          throw new Error('Scene not found.');
        }
        if (!this.state.studio_mode_enabled) {
          await this.obs.call('SetStudioModeEnabled', { studioModeEnabled: true });
        }
        await this.obs.call('SetCurrentPreviewScene', { sceneName });
        await this.refreshTopology();
        return;
      }
      case 'showSource':
        await this.setSceneItemVisibility(action.targetId || action.targetName, 'show');
        return;
      case 'hideSource':
        await this.setSceneItemVisibility(action.targetId || action.targetName, 'hide');
        return;
      case 'toggleSourceVisibility':
        await this.setSceneItemVisibility(action.targetId || action.targetName, 'toggle');
        return;
      case 'mute':
        await this.setMute(action.targetId || action.targetName, 'mute');
        return;
      case 'unmute':
        await this.setMute(action.targetId || action.targetName, 'unmute');
        return;
      case 'toggleMute':
        await this.setMute(action.targetId || action.targetName, 'toggle');
        return;
      case 'startStream':
        await this.obs.call('StartStream');
        await this.refreshStats();
        return;
      case 'stopStream':
        await this.obs.call('StopStream');
        await this.refreshStats();
        return;
      case 'toggleStream':
        await this.obs.call('ToggleStream');
        await this.refreshStats();
        return;
      case 'startRecording':
        await this.obs.call('StartRecord');
        await this.refreshStats();
        return;
      case 'stopRecording':
        await this.obs.call('StopRecord');
        await this.refreshStats();
        return;
      case 'pauseRecording':
        await this.obs.call('PauseRecord');
        await this.refreshStats();
        return;
      case 'resumeRecording':
        await this.obs.call('ResumeRecord');
        await this.refreshStats();
        return;
      case 'toggleRecording':
        await this.obs.call('ToggleRecord');
        await this.refreshStats();
        return;
      case 'startVirtualCamera':
        await this.obs.call('StartVirtualCam');
        await this.refreshVirtualCameraStatus();
        return;
      case 'stopVirtualCamera':
        await this.obs.call('StopVirtualCam');
        await this.refreshVirtualCameraStatus();
        return;
      case 'toggleVirtualCamera':
        await this.obs.call('ToggleVirtualCam');
        await this.refreshVirtualCameraStatus();
        return;
      case 'enableStudioMode':
        await this.obs.call('SetStudioModeEnabled', { studioModeEnabled: true });
        await this.refreshStudioMode();
        return;
      case 'disableStudioMode':
        await this.obs.call('SetStudioModeEnabled', { studioModeEnabled: false });
        await this.refreshStudioMode();
        return;
      case 'toggleStudioMode':
        await this.obs.call('SetStudioModeEnabled', {
          studioModeEnabled: !this.state.studio_mode_enabled,
        });
        await this.refreshStudioMode();
        return;
      default:
        throw new Error(`Unsupported OBS action: ${action.type}`);
    }
  }

  async setMute(targetIdOrName, mode) {
    if (!this.obs || !this.connected) {
      throw new Error('Connect to OBS before muting audio.');
    }
    const inputName = this.resolveAudioInputName(targetIdOrName);
    if (!inputName) {
      throw new Error('Audio source not found.');
    }

    if (mode === 'toggle') {
      await this.obs.call('ToggleInputMute', { inputName });
    } else {
      await this.obs.call('SetInputMute', {
        inputName,
        inputMuted: mode === 'mute',
      });
    }
    await this.refreshInputs();
  }

  async setInputVolume(targetIdOrName, volumeMultiplier) {
    if (!this.obs || !this.connected) {
      throw new Error('Connect to OBS before changing audio volume.');
    }
    const inputName = this.resolveAudioInputName(targetIdOrName);
    if (!inputName) {
      throw new Error('Audio source not found.');
    }
    await this.obs.call('SetInputVolume', {
      inputName,
      inputVolumeMul: Math.max(0, Math.min(1, volumeMultiplier)),
    });
    await this.refreshInputs();
  }

  async setSceneItemVisibility(targetIdOrName, mode) {
    if (!this.obs || !this.connected) {
      throw new Error('Connect to OBS before toggling sources.');
    }
    const target = this.resolveSourceTarget(targetIdOrName);
    if (!target) {
      throw new Error('Source not found.');
    }

    const current = this.state.sources.find((source) => source.id === target.sceneItemKey);
    const nextVisible =
      mode === 'toggle' ? !(current?.isVisible ?? false) : mode === 'show';

    await this.obs.call('SetSceneItemEnabled', {
      sceneName: target.sceneName,
      sceneItemId: target.sceneItemId,
      sceneItemEnabled: nextVisible,
    });
    await this.refreshTopology();
  }

  async setCurrentTransition(transitionName) {
    if (!this.obs || !this.connected) {
      throw new Error('Connect to OBS before changing transitions.');
    }
    const target = cleanString(transitionName, '');
    if (!target) {
      return;
    }
    await this.obs.call('SetCurrentSceneTransition', {
      transitionName: target,
    });
  }

  async setCurrentTransitionDuration(durationMs) {
    if (!this.obs || !this.connected) {
      throw new Error('Connect to OBS before changing transitions.');
    }
    const safeDuration = Math.max(1, toInt(durationMs, 300));
    await this.obs.call('SetCurrentSceneTransitionDuration', {
      transitionDuration: safeDuration,
    });
  }

  async controlMediaSource(targetIdOrName, action) {
    if (!this.obs || !this.connected) {
      throw new Error('Connect to OBS before controlling media sources.');
    }
    const inputName = this.resolveSourceName(targetIdOrName);
    if (!inputName) {
      throw new Error('Media source not found.');
    }
    const mediaAction = {
      play: 'OBS_WEBSOCKET_MEDIA_INPUT_ACTION_PLAY',
      pause: 'OBS_WEBSOCKET_MEDIA_INPUT_ACTION_PAUSE',
      restart: 'OBS_WEBSOCKET_MEDIA_INPUT_ACTION_RESTART',
    }[action];
    if (!mediaAction) {
      throw new Error(`Unsupported media action: ${action}`);
    }
    await this.obs.call('TriggerMediaInputAction', {
      inputName,
      mediaAction,
    });
  }

  async reloadBrowserSource(targetIdOrName) {
    if (!this.obs || !this.connected) {
      throw new Error('Connect to OBS before reloading browser sources.');
    }
    const inputName = this.resolveSourceName(targetIdOrName);
    if (!inputName) {
      throw new Error('Browser source not found.');
    }
    try {
      await this.obs.call('PressInputPropertiesButton', {
        inputName,
        propertyName: 'refreshnocache',
      });
    } catch (_) {
      await this.obs.call('PressInputPropertiesButton', {
        inputName,
        propertyName: 'refresh',
      });
    }
  }
}

class DesktopNotificationService {
  constructor({ isEnabled }) {
    this.isEnabled = isEnabled;
  }

  async notify(payload) {
    if (!this.isEnabled()) {
      return { ok: false, skipped: true, provider: 'disabled' };
    }

    const title = truncateText(payload?.title || 'DeckPilot Desktop', 80);
    const message = truncateText(payload?.message || 'Automation alert');
    const severity = cleanString(payload?.severity, 'info');
    const sound = severity === 'warning' || severity === 'error';

    return this.notifyWithPlatformFallback({ title, message, sound });
  }

  async notifyWithPlatformFallback({ title, message, sound }) {
    const platform = os.platform();
    if (platform === 'darwin') {
      let script = `display notification ${appleScriptString(message)} with title ${appleScriptString(title)}`;
      if (sound) {
        script += ' sound name "Glass"';
      }
      await execFileAsync('osascript', ['-e', script], { timeout: 5000 });
      return { ok: true, provider: 'osascript' };
    }

    if (platform === 'win32') {
      const script = [
        `$title = ${powerShellString(title)}`,
        `$message = ${powerShellString(message)}`,
        'Add-Type -AssemblyName System.Windows.Forms',
        'Add-Type -AssemblyName System.Drawing',
        '$notification = New-Object System.Windows.Forms.NotifyIcon',
        '$notification.Icon = [System.Drawing.SystemIcons]::Information',
        '$notification.BalloonTipIcon = [System.Windows.Forms.ToolTipIcon]::Info',
        '$notification.BalloonTipTitle = $title',
        '$notification.BalloonTipText = $message',
        '$notification.Visible = $true',
        '$notification.ShowBalloonTip(8000)',
        'Start-Sleep -Seconds 9',
        '$notification.Dispose()',
      ].join('; ');
      const encoded = Buffer.from(script, 'utf16le').toString('base64');
      const child = spawn(
        'powershell.exe',
        ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-EncodedCommand', encoded],
        { detached: true, stdio: 'ignore', windowsHide: true },
      );
      child.unref();
      return { ok: true, provider: 'windows-notifyicon' };
    }

    if (platform === 'linux') {
      await execFileAsync('notify-send', [title, message], { timeout: 5000 });
      return { ok: true, provider: 'notify-send' };
    }

    throw new Error(`Desktop notifications are not supported on ${platform}.`);
  }
}

class AutomationRuntime {
  constructor(options) {
    this.getRules = options.getRules;
    this.isPaused = options.isPaused;
    this.getObsState = options.getObsState;
    this.executeMacro = options.executeMacro;
    this.executeButtonAction = options.executeButtonAction;
    this.setInputVolume = options.setInputVolume;
    this.setCurrentTransition = options.setCurrentTransition;
    this.setCurrentTransitionDuration = options.setCurrentTransitionDuration;
    this.controlMediaSource = options.controlMediaSource;
    this.reloadBrowserSource = options.reloadBrowserSource;
    this.reconnectObs = options.reconnectObs;
    this.refreshObs = options.refreshObs;
    this.notifyDesktop =
      typeof options.notifyDesktop === 'function'
        ? options.notifyDesktop
        : async () => ({ ok: false, skipped: true, provider: 'unconfigured' });
    this.log = options.log;
    this.previousProgramSceneName = null;
    this.latestState = createInitialObsState();
    this.seenConnected = false;
    this.seenLive = false;
    this.lastTriggeredAt = new Map();
    this.activeSince = new Map();
    this.armedRules = new Map();
    this.executionQueue = Promise.resolve();
  }

  handleObsState(obsState) {
    const previousState = this.latestState;
    const previousScene = cleanString(previousState.current_scene, '');
    const nextScene = cleanString(obsState.current_scene, '');
    if (previousScene && nextScene && previousScene !== nextScene) {
      this.previousProgramSceneName = previousScene;
    }

    if (obsState.connection_status === 'connected') {
      this.seenConnected = true;
    }
    if (obsState.stream_status === 'live') {
      this.seenLive = true;
    }

    if (this.isPaused()) {
      return;
    }

    const rules = this.getRules().filter((rule) => rule && rule.isEnabled !== false);
    if (rules.length === 0) {
      return;
    }

    const matches = [];
    for (const rule of rules) {
      const match = this.matchRule(rule, previousState, obsState);
      if (match) {
        matches.push(match);
      }
    }

    this.latestState = shallowCloneState(obsState);

    if (matches.length === 0) {
      return;
    }

    this.executionQueue = this.executionQueue.then(async () => {
      for (const match of matches) {
        await this.executeRule(match);
      }
    });
  }

  matchRule(rule, previous, current) {
    const trigger = cleanString(rule.trigger, '');
    const now = Date.now();

    if (isLegacyTrigger(trigger)) {
      return this.matchLegacyRule(rule, previous, current, now);
    }

    switch (trigger) {
      case 'obsConnectionLost':
        return this.persistentCondition(
          rule,
          now,
          this.seenConnected && current.connection_status !== 'connected',
          'OBS connection lost.',
        );
      case 'streamEndedUnexpectedly':
        return this.persistentCondition(
          rule,
          now,
          this.seenLive &&
            current.stream_status !== 'live' &&
            (current.connection_status !== 'connected' ||
              current.output_reconnecting ||
              !!cleanString(current.last_error, '')),
          'Stream ended unexpectedly.',
        );
      case 'cameraSourceLost': {
        const source = this.findSource(current, rule.triggerCondition);
        const targetName =
          cleanString(rule.triggerCondition?.targetName, '') ||
          source?.name ||
          'selected camera source';
        return this.persistentCondition(
          rule,
          now,
          current.stream_status === 'live' &&
            this.hasConfiguredTarget(rule.triggerCondition) &&
            (!source || !source.isVisible),
          `${targetName} is unavailable.`,
        );
      }
      case 'droppedFramesHigh': {
        const threshold = this.thresholdForRule(rule, defaultThreshold(trigger) || 5);
        return this.persistentCondition(
          rule,
          now,
          current.stream_status === 'live' &&
            current.dropped_frames_percent >= threshold,
          `Dropped frames stayed above ${this.formatNumber(threshold)}%.`,
        );
      }
      case 'bitrateLowForDuration': {
        const threshold = this.thresholdForRule(rule, defaultThreshold(trigger) || 3000);
        return this.persistentCondition(
          rule,
          now,
          current.stream_status === 'live' &&
            current.bitrate_kbps > 0 &&
            current.bitrate_kbps <= threshold,
          `Bitrate stayed below ${Math.round(threshold)} kbps.`,
        );
      }
      case 'cpuEncodingOverload': {
        const threshold = this.thresholdForRule(rule, defaultThreshold(trigger) || 85);
        const overloaded =
          current.stream_status === 'live' &&
          (current.cpu_usage_percent >= threshold ||
            current.average_frame_render_time_ms >= 18 ||
            this.renderSkippedFramesPercent(current) >= 2);
        return this.persistentCondition(
          rule,
          now,
          overloaded,
          'Computer or encoder load stayed too high.',
        );
      }
      case 'micSilentWhileLive': {
        const sceneMatches = this.matchesSceneFilter(current, rule.triggerCondition);
        const micName = current.silent_microphone_name || 'Microphone';
        return this.persistentCondition(
          rule,
          now,
          current.stream_status === 'live' &&
            current.microphone_silent &&
            sceneMatches,
          `${micName} stayed silent while live.`,
        );
      }
      case 'micMutedOnSpeakingScene': {
        const microphone = this.selectedMicrophone(current.audio_sources, rule.triggerCondition);
        const microphoneName = microphone?.name || 'Microphone';
        return this.persistentCondition(
          rule,
          now,
          current.stream_status === 'live' &&
            this.matchesSceneFilter(current, rule.triggerCondition) &&
            !!microphone?.isMuted,
          `${microphoneName} is muted on a speaking scene.`,
        );
      }
      case 'streamLiveButRecordingOff':
        return this.persistentCondition(
          rule,
          now,
          current.stream_status === 'live' && current.recording_status === 'stopped',
          'Stream is live while recording is off.',
        );
      case 'brbSceneActiveTooLong': {
        const targetScene = this.triggerTargetLabel(current, rule.triggerCondition);
        return this.persistentCondition(
          rule,
          now,
          current.stream_status === 'live' &&
            this.hasConfiguredTarget(rule.triggerCondition) &&
            this.matchesNamedScene(current.current_scene, targetScene),
          `${targetScene} has stayed live too long.`,
        );
      }
      default:
        return null;
    }
  }

  matchLegacyRule(rule, previous, current, now) {
    const trigger = cleanString(rule.trigger, '');
    const cooldown = 6000;

    switch (trigger) {
      case 'streamStarted':
        if (
          previous.stream_status !== 'live' &&
          current.stream_status === 'live' &&
          this.canTrigger(rule.id, now, cooldown)
        ) {
          return this.fire(rule, now, 'Stream started.');
        }
        return null;
      case 'streamStopped':
        if (
          previous.stream_status === 'live' &&
          current.stream_status !== 'live' &&
          this.canTrigger(rule.id, now, cooldown)
        ) {
          return this.fire(rule, now, 'Stream stopped.');
        }
        return null;
      case 'recordingStarted':
        if (
          previous.recording_status !== 'recording' &&
          current.recording_status === 'recording' &&
          this.canTrigger(rule.id, now, cooldown)
        ) {
          return this.fire(rule, now, 'Recording started.');
        }
        return null;
      case 'recordingStopped':
        if (
          previous.recording_status === 'recording' &&
          current.recording_status !== 'recording' &&
          this.canTrigger(rule.id, now, cooldown)
        ) {
          return this.fire(rule, now, 'Recording stopped.');
        }
        return null;
      case 'sceneChanged': {
        const previousScene = cleanString(previous.current_scene, '');
        const currentScene = cleanString(current.current_scene, '');
        if (
          previousScene &&
          currentScene &&
          previousScene !== currentScene &&
          this.canTrigger(rule.id, now, cooldown)
        ) {
          return this.fire(rule, now, `Scene changed to ${currentScene}.`);
        }
        return null;
      }
      case 'micMuted': {
        const previousMic = this.primaryMicrophone(previous.audio_sources);
        const currentMic = this.primaryMicrophone(current.audio_sources);
        if (
          !(previousMic?.isMuted) &&
          !!currentMic?.isMuted &&
          this.canTrigger(rule.id, now, cooldown)
        ) {
          return this.fire(rule, now, `${currentMic?.name || 'Microphone'} muted.`);
        }
        return null;
      }
      case 'micUnmuted': {
        const previousMic = this.primaryMicrophone(previous.audio_sources);
        const currentMic = this.primaryMicrophone(current.audio_sources);
        if (
          !!previousMic?.isMuted &&
          !currentMic?.isMuted &&
          this.canTrigger(rule.id, now, cooldown)
        ) {
          return this.fire(rule, now, `${currentMic?.name || 'Microphone'} unmuted.`);
        }
        return null;
      }
      case 'droppedFramesDetected':
        return this.persistentCondition(
          rule,
          now,
          current.stream_status === 'live' && current.dropped_frames_percent > 0.5,
          'Dropped frames detected.',
        );
      case 'bitrateLow':
        return this.persistentCondition(
          rule,
          now,
          current.stream_status === 'live' &&
            current.bitrate_kbps > 0 &&
            current.bitrate_kbps <= 3000,
          'Bitrate dropped below target.',
        );
      case 'obsDisconnected':
        return this.persistentCondition(
          rule,
          now,
          this.seenConnected && current.connection_status !== 'connected',
          'OBS disconnected.',
        );
      case 'networkInstabilityDetected':
        return this.persistentCondition(
          rule,
          now,
          (current.connection_status === 'connected' &&
            (current.output_congestion >= 0.1 ||
              current.dropped_frames_percent >= 2 ||
              (current.bitrate_kbps > 0 && current.bitrate_kbps < 2500))) ||
            current.output_reconnecting,
          'Network instability detected.',
        );
      default:
        return null;
    }
  }

  persistentCondition(rule, now, active, summary) {
    if (!active) {
      this.activeSince.delete(rule.id);
      this.armedRules.set(rule.id, true);
      return null;
    }

    if (!this.activeSince.has(rule.id)) {
      this.activeSince.set(rule.id, now);
    }

    const debounceMs = this.debounceFor(rule) * 1000;
    if (now - this.activeSince.get(rule.id) < debounceMs) {
      return null;
    }

    const armed = this.armedRules.has(rule.id) ? this.armedRules.get(rule.id) : true;
    if (!armed) {
      return null;
    }

    const cooldownMs = this.cooldownFor(rule) * 1000;
    if (!this.canTrigger(rule.id, now, cooldownMs)) {
      return null;
    }

    this.armedRules.set(rule.id, false);
    return this.fire(rule, now, summary);
  }

  fire(rule, now, summary) {
    this.lastTriggeredAt.set(rule.id, now);
    return { rule, summary };
  }

  canTrigger(ruleId, now, cooldownMs) {
    const lastTriggeredAt = this.lastTriggeredAt.get(ruleId);
    if (!lastTriggeredAt) {
      return true;
    }
    return now - lastTriggeredAt >= cooldownMs;
  }

  debounceFor(rule) {
    return toInt(
      rule.triggerCondition?.durationSeconds,
      defaultDurationSeconds(rule.trigger),
    );
  }

  cooldownFor(rule) {
    return toInt(
      rule.triggerCondition?.cooldownSeconds,
      defaultCooldownSeconds(rule.trigger),
    );
  }

  thresholdForRule(rule, fallback) {
    return toFloat(rule.triggerCondition?.threshold, fallback);
  }

  renderSkippedFramesPercent(state) {
    if (state.render_total_frames <= 0) {
      return 0;
    }
    return (state.render_skipped_frames / state.render_total_frames) * 100;
  }

  hasConfiguredTarget(condition) {
    const target =
      cleanString(condition?.targetId, '') || cleanString(condition?.targetName, '');
    return !!target;
  }

  triggerTargetLabel(state, condition) {
    const targetName = cleanString(condition?.targetName, '');
    if (targetName) {
      return targetName;
    }

    const targetId = cleanString(condition?.targetId, '');
    if (!targetId) {
      return 'Selected scene';
    }

    const matchingScene = state.scenes.find(
      (scene) => scene.id === targetId || normalizeName(scene.name) === normalizeName(targetId),
    );
    return matchingScene?.name || targetId;
  }

  matchesSceneFilter(state, condition) {
    const configuredScene = this.configuredSceneName(state, condition);
    if (!configuredScene) {
      return true;
    }
    return this.matchesNamedScene(state.current_scene, configuredScene);
  }

  configuredSceneName(state, condition) {
    const sceneName = cleanString(condition?.sceneName, '');
    if (sceneName) {
      return sceneName;
    }

    const sceneId = cleanString(condition?.sceneId, '');
    if (!sceneId) {
      return null;
    }

    const scene = state.scenes.find(
      (entry) => entry.id === sceneId || normalizeName(entry.name) === normalizeName(sceneId),
    );
    return scene?.name || null;
  }

  matchesNamedScene(currentScene, configuredScene) {
    return normalizeName(currentScene) === normalizeName(configuredScene);
  }

  primaryMicrophone(audioSources) {
    if (!Array.isArray(audioSources) || audioSources.length === 0) {
      return null;
    }
    const preferred = audioSources.find((source) => {
      const name = normalizeName(source.name);
      return name.includes('mic') || name.includes('microphone');
    });
    return preferred || audioSources[0];
  }

  selectedMicrophone(audioSources, condition) {
    const target =
      cleanString(condition?.audioSourceId, '') || cleanString(condition?.audioSourceName, '');
    if (target) {
      const direct = audioSources.find(
        (source) => source.id === target || normalizeName(source.name) === normalizeName(target),
      );
      if (direct) {
        return direct;
      }
    }
    return this.primaryMicrophone(audioSources);
  }

  findSource(state, condition) {
    const target =
      cleanString(condition?.targetId, '') || cleanString(condition?.targetName, '');
    if (!target) {
      return null;
    }
    return (
      state.sources.find(
        (source) =>
          source.id === target || normalizeName(source.name) === normalizeName(target),
      ) || null
    );
  }

  formatNumber(value) {
    if (Math.round(value) === value) {
      return String(Math.round(value));
    }
    return value.toFixed(1);
  }

  async executeRule(match) {
    this.log('automation', `Triggered "${match.rule.name}": ${match.summary}`);
    try {
      await this.executeAction(match.rule, match.summary);
      this.log('success', `Automation "${match.rule.name}" completed.`);
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      this.log('error', `Automation "${match.rule.name}" failed: ${message}`);
    }
  }

  async executeAction(rule, triggerSummary = '') {
    const action = isPlainObject(rule.action) ? rule.action : {};
    const actionType = cleanString(action.type, '');

    switch (actionType) {
      case 'runMacro': {
        const macroId = this.requiredTarget(action, 'No macro selected for this automation.');
        await this.executeMacro(macroId);
        return;
      }
      case 'switchScene':
        await this.switchScene(action);
        return;
      case 'switchSceneAfterDelay':
        await this.countdownWait(requiredMetadataInt(action, 3), 'Switching scene in');
        await this.switchScene(action);
        return;
      case 'returnToPreviousScene': {
        if (!this.previousProgramSceneName) {
          throw new Error('No previous scene is available yet.');
        }
        await this.executeButtonAction({
          type: 'switchScene',
          targetId: this.previousProgramSceneName,
          targetName: this.previousProgramSceneName,
        });
        return;
      }
      case 'enableStudioMode':
        await this.executeButtonAction({ type: 'enableStudioMode' });
        return;
      case 'disableStudioMode':
        await this.executeButtonAction({ type: 'disableStudioMode' });
        return;
      case 'setTransition':
        await this.setCurrentTransition(this.requiredTarget(action, 'No transition selected.'));
        return;
      case 'setTransitionDuration':
        await this.setCurrentTransitionDuration(requiredMetadataInt(action, 300));
        return;
      case 'startStream':
        await this.executeButtonAction({ type: 'startStream' });
        return;
      case 'stopStream':
        await this.executeButtonAction({ type: 'stopStream' });
        return;
      case 'restartStream':
        await this.executeButtonAction({ type: 'stopStream' });
        await this.countdownWait(2, 'Restarting stream in');
        await this.executeButtonAction({ type: 'startStream' });
        return;
      case 'showAlert':
      case 'showWarning':
      case 'showAlertBanner':
      case 'sendNotification':
        await this.notifyDesktop(this.notificationForRule(rule, actionType, triggerSummary));
        return;
      case 'muteAudioSource':
        await this.executeMuteAction(rule, 'mute');
        return;
      case 'unmuteAudioSource':
        await this.executeMuteAction(rule, 'unmute');
        return;
      case 'toggleMute':
        await this.executeMuteAction(rule, 'toggleMute');
        return;
      case 'setAudioVolume':
        await this.setInputVolume(
          this.requiredTarget(action, 'No audio source selected.'),
          Math.max(0, Math.min(1, requiredMetadataFloat(action, 100) / 100)),
        );
        return;
      case 'fadeAudioIn':
        await this.fadeAudio(rule, 1);
        return;
      case 'fadeAudioOut':
        await this.fadeAudio(rule, 0);
        return;
      case 'showSource':
        await this.executeSourceAction(rule, 'showSource');
        return;
      case 'hideSource':
        await this.executeSourceAction(rule, 'hideSource');
        return;
      case 'toggleSourceVisibility':
        await this.executeSourceAction(rule, 'toggleSourceVisibility');
        return;
      case 'playMediaSource':
        await this.controlMediaSource(
          this.requiredTarget(action, 'No media source selected.'),
          'play',
        );
        return;
      case 'pauseMediaSource':
        await this.controlMediaSource(
          this.requiredTarget(action, 'No media source selected.'),
          'pause',
        );
        return;
      case 'restartMediaSource':
        await this.controlMediaSource(
          this.requiredTarget(action, 'No media source selected.'),
          'restart',
        );
        return;
      case 'delay':
      case 'countdown':
        await this.countdownWait(
          requiredMetadataInt(action, actionType === 'countdown' ? 5 : 3),
          actionType === 'countdown' ? 'Countdown' : 'Waiting',
        );
        return;
      case 'startRecording':
        await this.executeButtonAction({ type: 'startRecording' });
        return;
      case 'stopRecording':
        await this.executeButtonAction({ type: 'stopRecording' });
        return;
      case 'pauseRecording':
        await this.executeButtonAction({ type: 'pauseRecording' });
        return;
      case 'resumeRecording':
        await this.executeButtonAction({ type: 'resumeRecording' });
        return;
      case 'toggleRecording':
        await this.executeButtonAction({ type: 'toggleRecording' });
        return;
      case 'reconnectObs':
        await this.reconnectObs();
        return;
      case 'refreshScenes':
        await this.refreshObs();
        return;
      case 'reloadBrowserSource':
        await this.reloadBrowserSource(
          this.requiredTarget(action, 'No browser source selected.'),
        );
        return;
      default:
        throw new Error(`Unsupported automation action: ${actionType}`);
    }
  }

  previewAction(rule) {
    const target =
      cleanString(rule.action?.targetName, '') || cleanString(rule.action?.targetId, '');
    switch (rule.action?.type) {
      case 'runMacro':
        return target ? `Run macro ${target}` : 'Run macro';
      case 'switchScene':
      case 'switchSceneAfterDelay':
        return target ? `Switch to ${target}` : 'Switch scene';
      case 'muteAudioSource':
        return target ? `Mute ${target}` : 'Mute audio source';
      case 'unmuteAudioSource':
        return target ? `Unmute ${target}` : 'Unmute audio source';
      case 'toggleMute':
        return target ? `Toggle mute for ${target}` : 'Toggle mute';
      case 'showAlert':
      case 'showWarning':
      case 'showAlertBanner':
        return 'Show desktop alert';
      case 'sendNotification':
        return 'Send desktop notification';
      default:
        return cleanString(rule.name, 'Automation action');
    }
  }

  notificationForRule(rule, actionType, triggerSummary) {
    const action = isPlainObject(rule.action) ? rule.action : {};
    const metadata = isPlainObject(action.metadata) ? action.metadata : {};
    const severity = actionType === 'sendNotification' ? 'info' : 'warning';
    const defaultTitle =
      actionType === 'sendNotification' ? 'Automation Notice' : 'Automation Alert';
    const title = cleanString(metadata.title, defaultTitle) || defaultTitle;
    const message =
      cleanString(metadata.message, '') ||
      `${cleanString(rule.name, 'Automation')}: ${cleanString(
        triggerSummary,
        this.previewAction(rule),
      )}`;

    return {
      title,
      message,
      severity,
      ruleId: cleanString(rule.id, ''),
      actionType,
    };
  }

  async switchScene(action) {
    const target = this.requiredTarget(action, 'No scene selected for this automation.');
    await this.executeButtonAction({
      type: 'switchScene',
      targetId: target,
      targetName: action.targetName || target,
    });
  }

  async executeMuteAction(rule, buttonType) {
    const action = isPlainObject(rule.action) ? rule.action : {};
    const target = this.requiredTarget(action, 'No audio source selected for this automation.');
    await this.executeButtonAction({
      type: buttonType,
      targetId: target,
      targetName: action.targetName || target,
    });
  }

  async executeSourceAction(rule, buttonType) {
    const action = isPlainObject(rule.action) ? rule.action : {};
    const target = this.requiredTarget(action, 'No source selected for this automation.');
    await this.executeButtonAction({
      type: buttonType,
      targetId: target,
      targetName: action.targetName || target,
    });
  }

  async fadeAudio(rule, targetVolume) {
    const action = isPlainObject(rule.action) ? rule.action : {};
    const target = this.requiredTarget(action, 'No audio source selected for this automation.');
    const durationSeconds = requiredMetadataInt(action, 2);
    const currentSource = this.latestState.audio_sources.find(
      (source) => source.id === target || normalizeName(source.name) === normalizeName(target),
    );
    const startVolume =
      typeof currentSource?.volume === 'number'
        ? currentSource.volume
        : targetVolume > 0
          ? 0
          : 1;
    const steps = 6;
    const stepDurationMs = Math.max(80, Math.min(5000, Math.round((durationSeconds * 1000) / steps)));

    for (let step = 1; step <= steps; step += 1) {
      const progress = step / steps;
      const nextVolume = startVolume + (targetVolume - startVolume) * progress;
      await this.setInputVolume(target, Math.max(0, Math.min(1, nextVolume)));
      if (step < steps) {
        await sleep(stepDurationMs);
      }
    }
  }

  requiredTarget(action, message) {
    const target =
      cleanString(action.targetId, '') || cleanString(action.targetName, '');
    if (!target) {
      throw new Error(message);
    }
    return target;
  }

  async countdownWait(seconds, prefix) {
    const safeSeconds = Math.max(1, Math.min(60, toInt(seconds, 1)));
    for (let remaining = safeSeconds; remaining > 0; remaining -= 1) {
      this.log('automation', `${prefix} ${remaining}s`);
      await sleep(1000);
    }
  }
}

class DeckPilotWsServer {
  constructor({
    getObsState,
    executeButtonAction,
    executeMacro,
    setInputVolume,
    isAuthorized,
    getDesktopInfo,
    getLocalAuthSecret,
    log,
  }) {
    this.getObsState = getObsState;
    this.executeButtonAction = executeButtonAction;
    this.executeMacro = executeMacro;
    this.setInputVolume = setInputVolume;
    this.isAuthorized = isAuthorized;
    this.getDesktopInfo = getDesktopInfo;
    this.getLocalAuthSecret = getLocalAuthSecret;
    this.log = log;
    this.wss = null;
    this.clients = new Map();
    this.stateRevision = 0;
    this._commandDedupe = new Map();
    this._reconcileTimer = null;
    this._authFailures = new Map();
    this._usedNonces = new Map();
    this._activeChallenges = new Map();
  }

  static MAX_MESSAGE_BYTES = 1024 * 1024;
  static HELLO_TIMEOUT_MS = 5000;
  static RECONCILE_INTERVAL_MS = 30000;
  static PING_INTERVAL_MS = 25000;
  static PONG_TIMEOUT_MS = 10000;
  static DEDUPE_MAX_ENTRIES = 200;
  static DEDUPE_TTL_MS = 60000;
  static AUTH_RATE_LIMIT_WINDOW_MS = 30000;
  static AUTH_RATE_LIMIT_MAX_FAILURES = 5;
  static CHALLENGE_TTL_MS = 30000;

  attach(server) {
    this.wss = new WebSocketServer({ server, path: '/ws', maxPayload: DeckPilotWsServer.MAX_MESSAGE_BYTES });

    this.wss.on('connection', (ws, request) => {
      const clientId = `dp_${crypto.randomBytes(8).toString('hex')}`;
      const now = Date.now();
      const isLocalhost = isLoopbackAddress(request.socket.remoteAddress);
      const client = {
        id: clientId,
        ws,
        deviceId: null,
        authenticated: false,
        remoteAddress: request.socket.remoteAddress,
        connectedAt: now,
        lastPongAt: now,
        latency: null,
        timedOut: false,
        isLocalhost,
      };
      this.clients.set(ws, client);

      this.log('info', `WebSocket client connected: ${clientId}`);

      if (!isLocalhost) {
        const sessionId = crypto.randomBytes(16).toString('hex');
        const nonce = crypto.randomBytes(32).toString('hex');
        const desktopInfo = this.getDesktopInfo();
        this._activeChallenges.set(clientId, {
          sessionId,
          nonce,
          createdAt: now,
        });
        ws.send(buildAuthChallenge({
          sessionId,
          nonce,
          desktopDeviceId: desktopInfo.id,
          protocolVersion: PROTOCOL_VERSION,
        }));
      }

      const helloTimeout = setTimeout(() => {
        if (!client.authenticated) {
          this.log('warn', `Hello timeout for client ${clientId}`);
          client.timedOut = true;
          try { ws.close(4001, 'Hello timeout'); } catch (_) {}
        }
      }, DeckPilotWsServer.HELLO_TIMEOUT_MS);

      ws.on('message', (data) => {
        this._handleMessage(ws, client, data.toString()).catch((err) => {
          this.log('error', `WS message error [${clientId}]: ${err.message}`);
        });
      });

      ws.on('pong', () => {
        client.lastPongAt = Date.now();
      });

      ws.on('close', () => {
        clearTimeout(helloTimeout);
        this._cleanupClient(client);
        this.log('info', `WebSocket client disconnected: ${clientId}`);
      });

      ws.on('error', (err) => {
        this.log('error', `WebSocket error [${clientId}]: ${err.message}`);
      });

      const pingTimer = setInterval(() => {
        if (ws.readyState === ws.OPEN) {
          const delta = Date.now() - client.lastPongAt;
          if (delta > DeckPilotWsServer.PONG_TIMEOUT_MS) {
            this.log('warn', `Heartbeat lost for client ${clientId} (${delta}ms)`);
            try { ws.close(4002, 'Heartbeat lost'); } catch (_) {}
            return;
          }
          ws.ping();
        }
      }, DeckPilotWsServer.PING_INTERVAL_MS);

      ws.on('close', () => {
        clearInterval(pingTimer);
      });
    });

    this._startReconcile();
  }

  _cleanupClient(client) {
    this.clients.delete(client.ws);
    for (const [id, entry] of this._commandDedupe) {
      if (entry.clientId === client.id) {
        this._commandDedupe.delete(id);
      }
    }
  }

  _pruneDedupeCache() {
    if (this._commandDedupe.size <= DeckPilotWsServer.DEDUPE_MAX_ENTRIES) return;
    const sorted = [...this._commandDedupe.entries()]
      .sort((a, b) => a[1].timestamp - b[1].timestamp);
    for (let i = 0; i < sorted.length - DeckPilotWsServer.DEDUPE_MAX_ENTRIES; i += 1) {
      this._commandDedupe.delete(sorted[i][0]);
    }
  }

  _pruneExpiredNonces() {
    const now = Date.now();
    for (const [nonce, expiry] of this._usedNonces) {
      if (expiry < now) {
        this._usedNonces.delete(nonce);
      }
    }
  }

  _pruneExpiredDedupe() {
    const cutoff = Date.now() - DeckPilotWsServer.DEDUPE_TTL_MS;
    for (const [id, entry] of this._commandDedupe) {
      if (entry.timestamp < cutoff) {
        this._commandDedupe.delete(id);
      }
    }
  }

  async _handleMessage(ws, client, raw) {
    if (client.timedOut) return;

    let parsed;
    try {
      parsed = JSON.parse(raw);
    } catch {
      ws.send(buildError(null, ERROR_CODE.INVALID_PAYLOAD, 'Invalid JSON'));
      return;
    }

    const type = cleanString(parsed.type, '');

    if (!client.authenticated && type !== MESSAGE_TYPE.HELLO && type !== MESSAGE_TYPE.PING) {
      ws.send(buildError(parsed.id || null, ERROR_CODE.UNAUTHORIZED, 'Send hello first'));
      return;
    }

    switch (type) {
      case MESSAGE_TYPE.HELLO:
        await this._handleHello(ws, client, parsed);
        break;
      case MESSAGE_TYPE.AUTH_RESPONSE:
        await this._handleAuthResponse(ws, client, parsed);
        break;
      case MESSAGE_TYPE.COMMAND:
        await this._handleCommand(ws, client, parsed);
        break;
      case MESSAGE_TYPE.PING:
        ws.send(buildMessage(MESSAGE_TYPE.PONG));
        break;
      case MESSAGE_TYPE.RESYNC_REQUEST:
        await this._handleResync(ws, client);
        break;
      default:
        ws.send(buildError(parsed.id || null, ERROR_CODE.UNKNOWN_COMMAND, `Unknown message type: ${type}`));
    }
  }

  async _handleHello(ws, client, parsed) {
    if (client.authenticated) {
      ws.send(buildHelloAck(
        this.getDesktopInfo().id,
        this.getDesktopInfo().name,
        this.getDesktopInfo().obsConnected,
      ));
      return;
    }

    const token = cleanString(parsed.token, '');
    const deviceId = cleanString(parsed.deviceId, '');
    const protocolVersion = toInt(parsed.protocolVersion, 0);

    if (protocolVersion !== PROTOCOL_VERSION) {
      ws.send(buildError(
        null,
        ERROR_CODE.PROTOCOL_VERSION_UNSUPPORTED,
        `Server protocol v${PROTOCOL_VERSION}, client sent v${protocolVersion}`,
      ));
      ws.close(4000, 'Protocol version unsupported');
      return;
    }

    if (!deviceId) {
      ws.send(buildError(null, ERROR_CODE.INVALID_PAYLOAD, 'deviceId is required'));
      ws.close(4000, 'Missing deviceId');
      return;
    }

    const isLocalhost = isLoopbackAddress(client.remoteAddress);

    if (isLocalhost) {
      client.authenticated = true;
    } else if (token) {
      const authorized = this.isAuthorized(token);
      if (!authorized) {
        this._recordAuthFailure(client.remoteAddress);
        ws.send(buildError(null, ERROR_CODE.UNAUTHORIZED, 'Invalid token'));
        ws.close(4003, 'Unauthorized');
        return;
      }
      client.authenticated = true;
    } else {
      const blocked = this._checkAuthRateLimit(client.remoteAddress);
      if (blocked) {
        ws.send(buildError(null, ERROR_CODE.UNAUTHORIZED, 'Rate limited. Please wait.'));
        ws.close(4003, 'Rate limited');
        return;
      }
      this._recordAuthFailure(client.remoteAddress);
      ws.send(buildError(null, ERROR_CODE.UNAUTHORIZED, 'Authentication required'));
      ws.close(4003, 'Unauthorized');
      return;
    }

    client.deviceId = deviceId;

    const desktopInfo = this.getDesktopInfo();
    ws.send(buildHelloAck(
      desktopInfo.id,
      desktopInfo.name,
      desktopInfo.obsConnected,
    ));

    const obsState = this.getObsState();
    this.stateRevision += 1;
    ws.send(buildStateSnapshot(this.stateRevision, obsState));

    this.log('success', `Device ${deviceId} authenticated via WebSocket`);
  }

  async _handleAuthResponse(ws, client, parsed) {
    if (client.authenticated) return;

    const mobileDeviceId = cleanString(parsed.mobileDeviceId, '');
    const proof = cleanString(parsed.proof, '');

    if (!mobileDeviceId || !proof) {
      ws.send(buildError(null, ERROR_CODE.INVALID_PAYLOAD, 'mobileDeviceId and proof are required'));
      ws.close(4000, 'Invalid auth response');
      return;
    }

    const challenge = this._activeChallenges.get(client.id);
    if (!challenge) {
      ws.send(buildError(null, ERROR_CODE.UNAUTHORIZED, 'No active challenge'));
      ws.close(4003, 'No challenge');
      return;
    }

    if (Date.now() - challenge.createdAt > DeckPilotWsServer.CHALLENGE_TTL_MS) {
      this._activeChallenges.delete(client.id);
      ws.send(buildError(null, ERROR_CODE.UNAUTHORIZED, 'Challenge expired'));
      ws.close(4003, 'Challenge expired');
      return;
    }

    const nonceKey = challenge.nonce;
    this._pruneExpiredNonces();
    if (this._usedNonces.has(nonceKey)) {
      ws.send(buildError(null, ERROR_CODE.UNAUTHORIZED, 'Nonce already used'));
      ws.close(4003, 'Replayed nonce');
      return;
    }

    let localSecret;
    if (typeof this.getLocalAuthSecret === 'function') {
      localSecret = await this.getLocalAuthSecret(mobileDeviceId);
    }

    if (!localSecret) {
      this._recordAuthFailure(client.remoteAddress);
      ws.send(buildError(null, ERROR_CODE.UNAUTHORIZED, 'Device not authorized'));
      ws.close(4003, 'Unauthorized');
      return;
    }

    const desktopInfo = this.getDesktopInfo();
    const expectedData = `${challenge.sessionId}:${challenge.nonce}:${mobileDeviceId}:${desktopInfo.id}:${PROTOCOL_VERSION}`;
    const expectedProof = crypto
      .createHmac('sha256', localSecret)
      .update(expectedData)
      .digest('hex');

    if (!crypto.timingSafeEqual(Buffer.from(proof, 'hex'), Buffer.from(expectedProof, 'hex'))) {
      this._recordAuthFailure(client.remoteAddress);
      ws.send(buildError(null, ERROR_CODE.UNAUTHORIZED, 'Invalid proof'));
      ws.close(4003, 'Unauthorized');
      return;
    }

    this._usedNonces.set(nonceKey, Date.now() + DeckPilotWsServer.CHALLENGE_TTL_MS);
    this._activeChallenges.delete(client.id);

    client.authenticated = true;
    client.deviceId = mobileDeviceId;

    ws.send(buildHelloAck(
      desktopInfo.id,
      desktopInfo.name,
      desktopInfo.obsConnected,
    ));

    const obsState = this.getObsState();
    this.stateRevision += 1;
    ws.send(buildStateSnapshot(this.stateRevision, obsState));

    this.log('success', `Device ${mobileDeviceId} authenticated via challenge-response`);
  }

  _recordAuthFailure(remoteAddress) {
    const now = Date.now();
    const entry = this._authFailures.get(remoteAddress) || { count: 0, firstAt: now };
    entry.count += 1;
    if (now - entry.firstAt > DeckPilotWsServer.AUTH_RATE_LIMIT_WINDOW_MS) {
      entry.count = 1;
      entry.firstAt = now;
    }
    this._authFailures.set(remoteAddress, entry);
  }

  _checkAuthRateLimit(remoteAddress) {
    const now = Date.now();
    const entry = this._authFailures.get(remoteAddress);
    if (!entry) return false;
    if (now - entry.firstAt > DeckPilotWsServer.AUTH_RATE_LIMIT_WINDOW_MS) {
      this._authFailures.delete(remoteAddress);
      return false;
    }
    return entry.count >= DeckPilotWsServer.AUTH_RATE_LIMIT_MAX_FAILURES;
  }

  async _handleResync(ws, client) {
    if (!client.authenticated) return;
    const obsState = this.getObsState();
    this.stateRevision += 1;
    ws.send(buildStateSnapshot(this.stateRevision, obsState));
  }

  async _handleCommand(ws, client, parsed) {
    if (!client.authenticated) {
      ws.send(buildError(parsed.id || null, ERROR_CODE.UNAUTHORIZED, 'Not authenticated'));
      return;
    }

    const commandId = cleanString(parsed.id, '');
    const command = cleanString(parsed.command, '');
    const payload = isPlainObject(parsed.payload) ? parsed.payload : {};

    if (!commandId || !command) {
      ws.send(buildError(null, ERROR_CODE.INVALID_PAYLOAD, 'id and command are required'));
      return;
    }

    const deduped = this._commandDedupe.get(commandId);
    if (deduped) {
      if (Date.now() - deduped.timestamp < DeckPilotWsServer.DEDUPE_TTL_MS) {
        ws.send(deduped.result);
        return;
      }
      this._commandDedupe.delete(commandId);
    }

    this._pruneExpiredDedupe();

    if (command === COMMAND.OBS_REFRESH) {
      await this._executeRefresh(ws, client, commandId);
      return;
    }

    if (command === COMMAND.SOURCE_SET_VOLUME) {
      await this._executeSetVolume(ws, client, commandId, payload);
      return;
    }

    const obsAction = COMMAND_TO_OBS_ACTION[command];
    if (!obsAction) {
      ws.send(buildError(commandId, ERROR_CODE.UNKNOWN_COMMAND, `Unknown command: ${command}`));
      return;
    }

    await this._executeObsAction(ws, client, commandId, obsAction, payload);
  }

  async _executeRefresh(ws, client, commandId) {
    try {
      const obsState = this.getObsState();
      this.stateRevision += 1;
      const result = buildCommandResult(commandId, true);
      ws.send(result);
      ws.send(buildStateSnapshot(this.stateRevision, obsState));
      this._storeDedupe(commandId, result, client.id);
    } catch (err) {
      const result = buildCommandResult(commandId, false, { error: err.message });
      ws.send(result);
      this._storeDedupe(commandId, result, client.id);
    }
  }

  async _executeObsAction(ws, client, commandId, obsAction, payload) {
    try {
      const action = this._buildObsAction(obsAction, payload);
      await this.executeButtonAction(action);
      const result = buildCommandResult(commandId, true);
      ws.send(result);
      this._storeDedupe(commandId, result, client.id);
    } catch (err) {
      const result = buildCommandResult(commandId, false, { error: err.message });
      ws.send(result);
      this._storeDedupe(commandId, result, client.id);
    }
  }

  async _executeSetVolume(ws, client, commandId, payload) {
    try {
      const target = cleanString(payload.targetId || payload.targetName, '');
      const volume = toFloat(payload.volume, null);
      if (!target || volume === null) {
        ws.send(buildError(commandId, ERROR_CODE.INVALID_PAYLOAD, 'targetId and volume are required'));
        return;
      }
      await this.setInputVolume(target, Math.max(0, Math.min(1, volume)));
      const result = buildCommandResult(commandId, true);
      ws.send(result);
      this._storeDedupe(commandId, result, client.id);
    } catch (err) {
      const result = buildCommandResult(commandId, false, { error: err.message });
      ws.send(result);
      this._storeDedupe(commandId, result, client.id);
    }
  }

  _storeDedupe(commandId, result, clientId) {
    this._commandDedupe.set(commandId, {
      result,
      timestamp: Date.now(),
      clientId,
    });
    this._pruneDedupeCache();
  }

  _buildObsAction(obsAction, payload) {
    const action = {
      type: obsAction,
      targetId: cleanString(payload.targetId, ''),
      targetName: cleanString(payload.targetName, ''),
    };

    if (obsAction === 'switchScene' || obsAction === 'setPreviewScene') {
      const sceneName = cleanString(payload.sceneName, '');
      if (sceneName) {
        action.targetId = sceneName;
        action.targetName = sceneName;
      }
    }

    if (obsAction === 'setCurrentTransition') {
      action.targetId = cleanString(payload.transitionName, '');
      action.targetName = action.targetId;
    }

    return action;
  }

  _startReconcile() {
    this._reconcileTimer = setInterval(() => {
      if (this.clients.size === 0) return;
      const current = this.getObsState();
      if (!current) return;
      this.stateRevision += 1;
      const snapshot = buildStateSnapshot(this.stateRevision, current);
      this._broadcastToAll(snapshot);
    }, DeckPilotWsServer.RECONCILE_INTERVAL_MS);
  }

  onObsStatePatch(changes) {
    if (this.clients.size === 0) return;
    if (!changes || Object.keys(changes).length === 0) return;
    this.stateRevision += 1;
    const patch = buildStatePatch(this.stateRevision, changes);
    this._broadcastToAll(patch);
  }

  _broadcastToAll(message) {
    for (const [, client] of this.clients) {
      if (client.authenticated && client.ws.readyState === client.ws.OPEN) {
        try {
          client.ws.send(message);
        } catch (_) {}
      }
    }
  }

  get connectedCount() {
    let count = 0;
    for (const [, client] of this.clients) {
      if (client.authenticated && client.ws.readyState === client.ws.OPEN) {
        count += 1;
      }
    }
    return count;
  }

  close() {
    if (this._reconcileTimer) {
      clearInterval(this._reconcileTimer);
      this._reconcileTimer = null;
    }
    if (this.wss) {
      this.wss.close();
      this.wss = null;
    }
    this.clients.clear();
    this._commandDedupe.clear();
    this._authFailures.clear();
    this._usedNonces.clear();
    this._activeChallenges.clear();
  }

  getClientInfo(clientId) {
    for (const [, client] of this.clients) {
      if (client.id === clientId) {
        return {
          deviceId: client.deviceId,
          remoteAddress: client.remoteAddress,
          authenticated: client.authenticated,
          lastPongAt: client.lastPongAt,
          connectedAt: client.connectedAt,
        };
      }
    }
    return null;
  }
}

class DesktopAgent {
  constructor() {
    this.store = new StateStore(STATE_FILE);
    this.state = createDefaultState();
    this.server = null;
    this.wsServer = null;
    this.discoverySocket = null;
    this.logs = [];
    this.relayPollTimer = null;
    this.relayRefreshTimer = null;
    this.workspacePullTimer = null;
    this.notifications = new DesktopNotificationService({
      isEnabled: () => this.state.config.desktop_notifications !== false,
    });

    this.obs = new ObsConnector({
      log: (type, message) => this.log(type, message),
      onStateChange: (obsState) => {
        this.automation.handleObsState(obsState);
      },
      onStatePatch: (patch) => {
        if (this.wsServer) {
          this.wsServer.onObsStatePatch(patch);
        }
        if (this.cloudRelay) {
          this.cloudRelay.sendObsStatePatch(patch);
        }
      },
    });

    this.automation = new AutomationRuntime({
      getRules: () => this.state.automations,
      isPaused: () => !!this.state.config.automation_paused,
      getObsState: () => this.obs.getState(),
      executeMacro: (macroId) => this.executeMacro(macroId),
      executeButtonAction: (action) => this.obs.executeButtonAction(action),
      setInputVolume: (target, volume) => this.obs.setInputVolume(target, volume),
      setCurrentTransition: (transitionName) =>
        this.obs.setCurrentTransition(transitionName),
      setCurrentTransitionDuration: (durationMs) =>
        this.obs.setCurrentTransitionDuration(durationMs),
      controlMediaSource: (target, action) => this.obs.controlMediaSource(target, action),
      reloadBrowserSource: (target) => this.obs.reloadBrowserSource(target),
      reconnectObs: async () => {
        const config = this.currentObsConfig();
        if (!config) {
          throw new Error('No saved OBS connection is available.');
        }
        await this.obs.disconnect({ manual: false });
        await sleep(400);
        await this.obs.connect(config);
      },
      refreshObs: () => this.obs.refreshState(),
      notifyDesktop: (payload) => this.showDesktopNotification(payload),
      log: (type, message) => this.log(type, message),
    });

    this.wsServer = new DeckPilotWsServer({
      getObsState: () => this.obs.getState(),
      executeButtonAction: (action) => this.obs.executeButtonAction(action),
      executeMacro: (macroId) => this.executeMacro(macroId),
      setInputVolume: (target, volume) => this.obs.setInputVolume(target, volume),
      isAuthorized: (token) => this._isAuthorizedToken(token),
      getDesktopInfo: () => ({
        id: this.state.desktopId,
        name: this.state.desktopName || os.hostname(),
        obsConnected: this.obs.connected,
      }),
      log: (type, message) => this.log(type, message),
      getLocalAuthSecret: (mobileDeviceId) => this._getLocalAuthSecret(mobileDeviceId),
    });

    this.mdnsAdvertiser = null;
    this.cloudRelay = null;
  }

  get port() {
    if (this.server?.address() && typeof this.server.address().port === 'number') {
      return this.server.address().port;
    }
    return this.state.config.sync_port;
  }

  async start() {
    this.state = await this.store.load();
    await this.pullWorkspaceState({ silent: true });

    await this.bindServer(this.state.config.sync_port);
    await this.startDiscovery();

    if (this.wsServer) {
      this.wsServer.attach(this.server);
    }

    this._startMdns();

    this._startCloudRelay();

    this.log('info', `Desktop agent listening on port ${this.port}.`);

    if (this.state.config.auto_connect && cleanString(this.state.config.obs_host, '')) {
      try {
        await this.obs.startAutoConnect(this.currentObsConfig());
      } catch (_) {}
    }

    await this.registerRelay({ force: true });
    this.startWorkspacePullTimer();
  }

  async stop() {
    if (this.relayPollTimer) {
      clearInterval(this.relayPollTimer);
      this.relayPollTimer = null;
    }
    if (this.relayRefreshTimer) {
      clearInterval(this.relayRefreshTimer);
      this.relayRefreshTimer = null;
    }
    if (this.workspacePullTimer) {
      clearInterval(this.workspacePullTimer);
      this.workspacePullTimer = null;
    }
    if (this.discoverySocket) {
      this.discoverySocket.close();
      this.discoverySocket = null;
    }
    if (this.wsServer) {
      this.wsServer.close();
      this.wsServer = null;
    }
    this._stopMdns();
    this._stopCloudRelay();
    await this.obs.stop();
    if (this.server) {
      await new Promise((resolve) => this.server.close(resolve));
      this.server = null;
    }
  }

  async bindServer(requestedPort) {
    const safePort = requestedPort > 0 ? requestedPort : 8080;
    this.server = createServer((request, response) => {
      this.handleRequest(request, response).catch((error) => {
        const message = error instanceof Error ? error.message : String(error);
        this.log('error', `Request failed: ${message}`);
        sendJson(response, 500, { error: message });
      });
    });

    await new Promise((resolve) => {
      this.server.listen(safePort, '0.0.0.0', resolve);
    });
  }

  async startDiscovery() {
    const socket = dgram.createSocket('udp4');
    socket.on('message', async (message, remote) => {
      try {
        if (!this.state.config.allow_discovery) {
          return;
        }
        const data = JSON.parse(message.toString('utf8'));
        if (data?.type !== 'deckpilot_discovery_query') {
          return;
        }
        const ip = await this.resolveLocalIp();
        if (!ip) {
          return;
        }
        const payload = Buffer.from(
          JSON.stringify({
            type: 'deckpilot_discovery_response',
            host: ip,
            port: this.port,
            name: 'DeckPilot Desktop',
          }),
        );
        socket.send(payload, remote.port, remote.address);
      } catch (_) {}
    });

    await new Promise((resolve, reject) => {
      socket.once('error', reject);
      socket.bind(this.port, '0.0.0.0', () => {
        socket.removeAllListeners('error');
        resolve();
      });
    });

    this.discoverySocket = socket;
  }

  currentObsConfig() {
    if (!cleanString(this.state.config.obs_host, '')) {
      return null;
    }
    return {
      host: this.state.config.obs_host,
      port: this.state.config.obs_port,
      password: this.state.config.obs_password,
    };
  }

  _startMdns() {
    const desktopName = this.state.desktopName || os.hostname();
    const deviceId = this.state.desktopId;

    this.mdnsAdvertiser = new MDNSAdvertiser({
      instanceName: desktopName,
      serviceType: '_deckpilot._tcp',
      port: this.port,
      txtProps: {
        deviceId,
        displayName: desktopName,
        protocolVersion: String(PROTOCOL_VERSION),
        port: String(this.port),
      },
      log: (type, message) => this.log(type, message),
    });

    this.mdnsAdvertiser.start(1000, 30000);
    this.log('info', `mDNS advertising as "${desktopName}" (_deckpilot._tcp)`);
  }

  _stopMdns() {
    if (this.mdnsAdvertiser) {
      this.mdnsAdvertiser.stop();
      this.mdnsAdvertiser = null;
    }
  }

  _startCloudRelay() {
    if (this.cloudRelay) return;
    this.cloudRelay = new CloudRelayClient({
      getObsState: () => this.obs.getState(),
      executeButtonAction: (action) => this.obs.executeButtonAction(action),
      executeMacro: (macroId) => this.executeMacro(macroId),
      setInputVolume: (target, volume) => this.obs.setInputVolume(target, volume),
      log: (type, message) => this.log(type, message),
      relayUrl: RELAY_BASE_URL,
    });
    this.cloudRelay.connect();
  }

  _stopCloudRelay() {
    if (this.cloudRelay) {
      this.cloudRelay.dispose();
      this.cloudRelay = null;
    }
  }

  log(logType, message) {
    const entry = {
      timestamp: new Date().toISOString(),
      log_type: logType,
      message,
    };
    this.logs.push(entry);
    if (this.logs.length > MAX_LOGS) {
      this.logs.shift();
    }
    process.stdout.write(`[${logType}] ${message}\n`);
  }

  async showDesktopNotification(payload) {
    const result = await this.notifications.notify(payload);
    if (result.skipped) {
      this.log('automation', 'Desktop notification skipped because notifications are disabled.');
      return result;
    }

    this.log(
      'success',
      `Desktop notification shown (${result.provider}): ${payload.title || 'DeckPilot Desktop'}`,
    );
    return result;
  }

  async persistState() {
    await this.store.save(this.state);
  }

  isAuthorized(request) {
    const remoteAddress = request.socket.remoteAddress;
    if (isLoopbackAddress(remoteAddress)) {
      return true;
    }
    const authHeader = request.headers.authorization || '';
    return authHeader === `Bearer ${this.state.pairingSecret}`;
  }

  _isAuthorizedToken(token) {
    const secret = cleanString(this.state.pairingSecret, '');
    return !!secret && token === secret;
  }

  appStatePayload() {
    const obs = this.obs.getState();
    return {
      config: {
        ...this.state.config,
        sync_port: this.port,
      },
      automations_paused: this.state.config.automation_paused,
      last_sync_at: this.state.lastSyncAt,
      obs: {
        connected: obs.connection_status === 'connected',
        connection_status: obs.connection_status,
        current_scene: obs.current_scene,
        preview_scene: obs.preview_scene,
        scenes: obs.scenes.map((scene) => scene.name),
        stream_status: obs.stream_status,
        recording_status: obs.recording_status,
      },
      relay: {
        registered: !!cleanString(this.state.roomCode, ''),
        roomCode: this.state.roomCode,
      },
      automations: Array.isArray(this.state.automations) ? this.state.automations : [],
      workspace: {
        id: this.state.workspaceId,
        revision: this.state.workspaceRevision,
        last_cloud_sync_at: this.state.lastCloudSyncAt,
      },
      notifications: {
        permission_asked: this.state.notificationPermissionAsked,
      },
    };
  }

  detailedObsState() {
    return this.obs.getState();
  }

  async handleRequest(request, response) {
    if (request.method === 'OPTIONS') {
      sendJson(response, 204, {});
      return;
    }

    const url = new URL(request.url, `http://${request.headers.host || '127.0.0.1'}`);
    if (url.pathname.startsWith('/api/')) {
      await this.routeApi(request, response, url);
      return;
    }

    await this.serveStatic(response, url.pathname);
  }

  async routeApi(request, response, url) {
    const { pathname } = url;

    if (pathname === '/api/consent/status' && request.method === 'GET') {
      sendJson(response, 200, {
        accepted: this.state.firstRunConsentAccepted,
        desktopId: this.state.desktopId,
        desktopName: this.state.desktopName,
      });
      return;
    }

    if (pathname === '/api/consent/accept' && request.method === 'POST') {
      this.state.firstRunConsentAccepted = true;
      await this.persistState();
      this.addActivityEntry('consent', 'Desktop agent consent accepted');
      sendJson(response, 200, { accepted: true });
      return;
    }

    if (pathname === '/api/desktop/info' && request.method === 'GET') {
      const uptime = Math.floor((Date.now() - AGENT_STARTED_AT) / 1000);
      sendJson(response, 200, {
        version: AGENT_VERSION,
        uptime,
        hostname: os.hostname(),
        platform: os.platform(),
        release: os.release(),
        desktopName: this.state.desktopName,
        desktopId: this.state.desktopId,
      });
      return;
    }

    if (pathname === '/api/account/status' && request.method === 'GET') {
      sendJson(response, 200, {
        linked: this.state.accountLinked,
        email: this.state.accountEmail,
        workspaceId: this.state.workspaceId,
        workspaceName: this.state.workspaceName,
        desktopName: this.state.desktopName,
        lastSyncAt: this.state.lastCloudSyncAt,
        lastCloudSyncStatus: this.state.lastCloudSyncStatus,
        hasDeviceToken: !!this.state.deviceToken,
      });
      return;
    }

    if (pathname === '/api/account/link/start' && request.method === 'POST') {
      const result = await this.startAccountLinking();
      if (!result) {
        sendJson(response, 502, { error: 'Failed to start account linking.' });
        return;
      }
      sendJson(response, 200, result);
      return;
    }

    if (pathname === '/api/account/link/status' && request.method === 'GET') {
      const status = await this.pollAccountLinking();
      sendJson(response, 200, status);
      return;
    }

    if (pathname === '/api/account/link/cancel' && request.method === 'POST') {
      this.state = {
        ...this.state,
        accountLinkingRequestId: null,
        accountLinkingCode: null,
        accountLinkingExpiresAt: null,
        accountLinkError: null,
      };
      await this.persistState();
      sendJson(response, 200, { cancelled: true });
      return;
    }

    if (pathname === '/api/account/unlink' && request.method === 'POST') {
      if (!this.isAuthorized(request)) {
        sendUnauthorized(response);
        return;
      }
      await this.unlinkAccount();
      sendJson(response, 200, { unlinked: true });
      return;
    }

    if (pathname === '/api/account/workspace/sync' && request.method === 'POST') {
      if (!this.isAuthorized(request)) {
        sendUnauthorized(response);
        return;
      }
      const result = await this.syncWorkspaceFromCloud();
      sendJson(response, 200, result);
      return;
    }

    if (pathname === '/api/account/activity' && request.method === 'GET') {
      sendJson(response, 200, this.state.activityLog);
      return;
    }

    if (pathname === '/api/account/exchange' && request.method === 'POST') {
      const body = await readJsonBody(request);
      const exchangeToken = cleanString(body.exchangeToken, '');
      if (!exchangeToken) {
        sendJson(response, 400, { error: 'exchangeToken is required.' });
        return;
      }
      const result = await this.exchangeAccountToken(exchangeToken);
      if (!result) {
        sendJson(response, 502, { error: 'Token exchange failed.' });
        return;
      }
      sendJson(response, 200, result);
      return;
    }

    if (pathname === '/api/health' && request.method === 'GET') {
      sendJson(response, 200, {
        status: 'ok',
        timestamp: new Date().toISOString(),
      });
      return;
    }

    if (pathname === '/api/app/state' && request.method === 'GET') {
      sendJson(response, 200, this.appStatePayload());
      return;
    }

    if (pathname === '/api/notifications/test' && request.method === 'POST') {
      if (!this.isAuthorized(request)) {
        sendUnauthorized(response);
        return;
      }
      const result = await this.showDesktopNotification({
        title: 'DeckPilot Desktop',
        message: 'Desktop notifications are ready for automation alerts.',
        severity: 'info',
      });
      sendJson(response, 200, result);
      return;
    }

    if (pathname === '/api/notifications/permission' && request.method === 'POST') {
      if (!this.isAuthorized(request)) {
        sendUnauthorized(response);
        return;
      }
      const body = await readJsonBody(request);
      const enabled = body.enabled !== false;
      this.state = {
        ...this.state,
        config: {
          ...this.state.config,
          desktop_notifications: enabled,
        },
        notificationPermissionAsked: true,
      };
      await this.persistState();
      this.log(
        'info',
        `Desktop automation notifications ${enabled ? 'enabled' : 'disabled'}.`,
      );
      if (!enabled) {
        sendJson(response, 200, { ok: true, enabled: false });
        return;
      }
      const result = await this.showDesktopNotification({
        title: 'DeckPilot Desktop',
        message: 'Automation notifications are enabled on this computer.',
        severity: 'info',
      });
      sendJson(response, 200, { ...result, enabled: true });
      return;
    }

    if (pathname === '/api/logs' && request.method === 'GET') {
      const filter = cleanString(url.searchParams.get('filter'), '');
      const logs = filter
        ? this.logs.filter((entry) => normalizeName(entry.log_type) === normalizeName(filter))
        : this.logs;
      sendJson(response, 200, logs);
      return;
    }

    if (pathname === '/api/logs' && request.method === 'DELETE') {
      if (!this.isAuthorized(request)) {
        sendUnauthorized(response);
        return;
      }
      this.logs = [];
      sendJson(response, 200, { cleared: true });
      return;
    }

    if (pathname === '/api/local-ip' && request.method === 'GET') {
      sendJson(response, 200, {
        ip: await this.resolveLocalIp(),
      });
      return;
    }

    if (pathname === '/api/relay/state' && request.method === 'GET') {
      sendJson(response, 200, {
        registered: !!cleanString(this.state.roomCode, ''),
        roomCode: this.state.roomCode,
      });
      return;
    }

    if (pathname === '/api/relay/register' && request.method === 'POST') {
      if (!this.isAuthorized(request)) {
        sendUnauthorized(response);
        return;
      }
      const code = await this.registerRelay({ force: true });
      if (!code) {
        sendJson(response, 502, { error: 'Relay registration failed.' });
        return;
      }
      sendJson(response, 200, { code });
      return;
    }

    if (pathname === '/api/relay/poll' && request.method === 'POST') {
      if (!this.isAuthorized(request)) {
        sendUnauthorized(response);
        return;
      }
      sendJson(response, 200, { paired: await this.pollRelayOnce() });
      return;
    }

    if (pathname === '/api/pair/pin' && request.method === 'GET') {
      sendJson(response, 200, { pin: this.state.pairingPin });
      return;
    }

    if (pathname === '/api/pair/device' && request.method === 'GET') {
      sendJson(response, 200, this.state.pairedDevice);
      return;
    }

    if (pathname === '/api/pair/regenerate' && request.method === 'POST') {
      if (!this.isAuthorized(request)) {
        sendUnauthorized(response);
        return;
      }
      await this.rotatePairing({ resetRoomCode: true });
      sendJson(response, 200, { pin: this.state.pairingPin });
      return;
    }

    if (pathname === '/api/pair' && request.method === 'DELETE') {
      if (!this.isAuthorized(request)) {
        sendUnauthorized(response);
        return;
      }
      await this.rotatePairing({ resetRoomCode: true });
      sendJson(response, 200, { unpaired: true });
      return;
    }

    if (pathname === '/api/pair' && request.method === 'POST') {
      const body = await readJsonBody(request);
      const pin = cleanString(body.pin, '');
      if (pin !== this.state.pairingPin) {
        sendJson(response, 401, { error: 'Invalid PIN.' });
        return;
      }

      const userId = cleanString(body.token, 'local-device') || 'local-device';
      this.state = {
        ...this.state,
        pairedDevice: {
          user_id: userId,
          paired_at: new Date().toISOString(),
        },
      };
      await this.persistState();
      this.log('success', 'Local device paired.');
      sendJson(response, 200, {
        status: 'paired',
        token: this.state.pairingSecret,
        pairedDevice: this.state.pairedDevice,
      });
      return;
    }

    if (pathname === '/api/settings' && request.method === 'GET') {
      if (!this.isAuthorized(request)) {
        sendUnauthorized(response);
        return;
      }
      sendJson(response, 200, {
        ...this.state.config,
        sync_port: this.port,
      });
      return;
    }

    if (pathname === '/api/settings' && request.method === 'POST') {
      if (!this.isAuthorized(request)) {
        sendUnauthorized(response);
        return;
      }
      const body = await readJsonBody(request);
      const notificationPreferenceProvided =
        typeof body.desktop_notifications === 'boolean';
      this.state = {
        ...this.state,
        config: mergeSettingsInput(this.state.config, body, this.port),
        notificationPermissionAsked: notificationPreferenceProvided
          ? true
          : this.state.notificationPermissionAsked,
      };
      await this.persistState();
      this.log('info', 'Desktop agent settings updated.');
      sendJson(response, 200, {
        ...this.state.config,
        sync_port: this.port,
      });

      const obsHost = cleanString(this.state.config.obs_host, '');
      const obsPort = toInt(this.state.config.obs_port, 4455);
      if (obsHost && this.obs) {
        this.obs.lastConfig = { host: obsHost, port: obsPort, password: this.state.config.obs_password };
        if (this.obs.obs) {
          this.obs.disconnect().catch(() => {});
          setTimeout(() => this.obs.connect(this.obs.lastConfig).catch(() => {}), 500);
        }
      }
      return;
    }

    if (pathname === '/api/settings/reset' && request.method === 'POST') {
      if (!this.isAuthorized(request)) {
        sendUnauthorized(response);
        return;
      }
      this.state = {
        ...this.state,
        config: {
          ...DEFAULT_CONFIG,
          sync_port: this.port,
          automation_paused: false,
        },
        notificationPermissionAsked: false,
      };
      await this.persistState();
      sendJson(response, 200, {
        ...this.state.config,
        sync_port: this.port,
      });
      return;
    }

    if (pathname === '/api/obs/connect' && request.method === 'POST') {
      if (!this.isAuthorized(request)) {
        sendUnauthorized(response);
        return;
      }
      const body = await readJsonBody(request);
      try {
        await this.obs.connect({
          host: cleanString(body.host, this.state.config.obs_host),
          port: toInt(body.port, this.state.config.obs_port),
          password:
            typeof body.password === 'string'
              ? body.password
              : this.state.config.obs_password,
        });
        sendJson(response, 200, { connected: true });
      } catch (error) {
        const message = error instanceof Error ? error.message : String(error);
        sendJson(response, 502, { error: message });
      }
      return;
    }

    if (pathname === '/api/obs/disconnect' && request.method === 'POST') {
      if (!this.isAuthorized(request)) {
        sendUnauthorized(response);
        return;
      }
      await this.obs.disconnect();
      sendJson(response, 200, { disconnected: true });
      return;
    }

    if (pathname === '/api/obs/test-connection' && request.method === 'POST') {
      if (!this.isAuthorized(request)) {
        sendUnauthorized(response);
        return;
      }
      const body = await readJsonBody(request);
      await this.obs.testConnection({
        host: cleanString(body.host, this.state.config.obs_host),
        port: toInt(body.port, this.state.config.obs_port),
        password:
          typeof body.password === 'string'
            ? body.password
            : this.state.config.obs_password,
      });
      sendJson(response, 200, { ok: true });
      return;
    }

    if (pathname === '/api/obs/stream/toggle' && request.method === 'POST') {
      if (!this.isAuthorized(request)) {
        sendUnauthorized(response);
        return;
      }
      await this.obs.executeButtonAction({ type: 'toggleStream' });
      sendJson(response, 200, { ok: true });
      return;
    }

    if (pathname === '/api/obs/scene/switch' && request.method === 'POST') {
      if (!this.isAuthorized(request)) {
        sendUnauthorized(response);
        return;
      }
      const body = await readJsonBody(request);
      const sceneName = cleanString(body.scene_name || body.sceneName, '');
      if (!sceneName) {
        sendJson(response, 400, { error: 'scene_name is required.' });
        return;
      }
      await this.obs.executeButtonAction({
        type: 'switchScene',
        targetId: sceneName,
        targetName: sceneName,
      });
      sendJson(response, 200, { ok: true });
      return;
    }

    if (pathname === '/api/obs/state' && request.method === 'GET') {
      if (!this.isAuthorized(request)) {
        sendUnauthorized(response);
        return;
      }
      sendJson(response, 200, this.detailedObsState());
      return;
    }

    if (pathname === '/api/automations/toggle' && request.method === 'POST') {
      if (!this.isAuthorized(request)) {
        sendUnauthorized(response);
        return;
      }
      this.state = {
        ...this.state,
        config: {
          ...this.state.config,
          automation_paused: !this.state.config.automation_paused,
        },
      };
      await this.persistState();
      sendJson(response, 200, {
        automation_paused: this.state.config.automation_paused,
      });
      return;
    }

    const automationRuleToggle = pathname.match(
      /^\/api\/automations\/(.+)\/toggle$/
    );
    if (automationRuleToggle && request.method === 'POST') {
      if (!this.isAuthorized(request)) {
        sendUnauthorized(response);
        return;
      }
      const ruleId = decodeURIComponent(automationRuleToggle[1]);
      const idx = Array.isArray(this.state.automations)
        ? this.state.automations.findIndex((r) => r.id === ruleId)
        : -1;
      if (idx === -1) {
        sendJson(response, 404, { error: 'Automation rule not found.' });
        return;
      }
      const rule = { ...this.state.automations[idx] };
      rule.isEnabled = !(rule.isEnabled !== false);
      this.state = {
        ...this.state,
        automations: [
          ...this.state.automations.slice(0, idx),
          rule,
          ...this.state.automations.slice(idx + 1),
        ],
      };
      await this.persistState();
      this.log(
        'sync',
        `Toggled automation "${rule.name || rule.id}" ${rule.isEnabled ? 'on' : 'off'}.`
      );
      sendJson(response, 200, {
        id: ruleId,
        isEnabled: rule.isEnabled,
      });
      return;
    }

    if (pathname === '/api/sync' && request.method === 'POST') {
      if (!this.isAuthorized(request)) {
        sendUnauthorized(response);
        return;
      }
      const body = await readJsonBody(request);
      this.state = {
        ...this.state,
        macros: Array.isArray(body.macros) ? body.macros : [],
        automations: sortAutomations(
          Array.isArray(body.automations) ? body.automations : [],
        ),
        pages: Array.isArray(body.pages) ? body.pages : [],
        pinnedIds: Array.isArray(body.pinnedIds)
          ? body.pinnedIds.filter((entry) => typeof entry === 'string')
          : [],
        lastSyncAt: new Date().toISOString(),
      };
      await this.persistState();
      this.log(
        'sync',
        `Synced ${this.state.macros.length} macros and ${this.state.automations.length} automations from mobile.`,
      );
      sendJson(response, 200, {
        ok: true,
        macros: this.state.macros.length,
        automations: this.state.automations.length,
      });
      return;
    }

    if (pathname === '/api/macro/execute' && request.method === 'POST') {
      if (!this.isAuthorized(request)) {
        sendUnauthorized(response);
        return;
      }
      const body = await readJsonBody(request);
      const macroId = cleanString(body.macroId, '');
      if (!macroId) {
        sendJson(response, 400, { error: 'macroId is required.' });
        return;
      }
      await this.executeMacro(macroId);
      this.log('automation', `Executed macro ${macroId} on desktop.`);
      sendJson(response, 200, { ok: true });
      return;
    }

    sendNotFound(response);
  }

  async serveStatic(response, requestPath) {
    const safePath = requestPath === '/' ? 'index.html' : requestPath.replace(/^\/+/, '');
    const resolvedPath = path.normalize(path.join(STATIC_ROOT, safePath));

    if (!resolvedPath.startsWith(STATIC_ROOT)) {
      sendNotFound(response);
      return;
    }

    try {
      const stats = await fs.stat(resolvedPath);
      if (!stats.isFile()) {
        sendNotFound(response);
        return;
      }
    } catch (_) {
      sendNotFound(response);
      return;
    }

    response.statusCode = 200;
    response.setHeader('Content-Type', contentTypeFor(resolvedPath));
    response.setHeader('Cache-Control', 'no-cache');
    createReadStream(resolvedPath).pipe(response);
  }

  async resolveLocalIp() {
    const interfaces = os.networkInterfaces();
    const candidates = [];

    for (const addresses of Object.values(interfaces)) {
      for (const address of addresses || []) {
        if (address.family !== 'IPv4' || address.internal) {
          continue;
        }
        if (address.address.startsWith('169.254.')) {
          continue;
        }
        candidates.push(address.address);
      }
    }

    const preferred = candidates.find((address) => {
      return (
        address.startsWith('192.168.') ||
        address.startsWith('10.') ||
        /^172\.(1[6-9]|2\d|3[01])\./.test(address)
      );
    });

    return preferred || candidates[0] || null;
  }

  async registerRelay({ force = false } = {}) {
    if (!force && cleanString(this.state.roomCode, '')) {
      return this.state.roomCode;
    }

    const ip = await this.resolveLocalIp();
    if (!ip) {
      this.log('error', 'Unable to determine a local IP address for relay pairing.');
      return null;
    }

    try {
      const response = await fetch(`${RELAY_BASE_URL}/api/pair/register`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          ip,
          port: this.port,
          pin: this.state.pairingPin,
          hmacSecret: this.state.pairingSecret,
          desktopId: this.state.desktopId,
        }),
      });

      if (!response.ok) {
        this.log('error', `Relay registration failed with status ${response.status}.`);
        return null;
      }

      const data = await response.json();
      const roomCode = cleanString(data.code, '');
      if (!roomCode) {
        this.log('error', 'Relay registration returned an empty room code.');
        return null;
      }

      this.state = {
        ...this.state,
        roomCode,
      };
      await this.persistState();
      this.startRelayTimers();
      this.log('relay', `Relay room code registered: ${roomCode}`);
      return roomCode;
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      this.log('error', `Relay registration failed: ${message}`);
      return null;
    }
  }

  startRelayTimers() {
    if (this.relayPollTimer) {
      clearInterval(this.relayPollTimer);
    }
    if (this.relayRefreshTimer) {
      clearInterval(this.relayRefreshTimer);
    }

    this.relayPollTimer = setInterval(() => {
      this.pollRelayOnce().catch(() => {});
    }, RELAY_POLL_MS);

    this.relayRefreshTimer = setInterval(() => {
      this.registerRelay({ force: true }).catch(() => {});
    }, RELAY_REFRESH_MS);
  }

  startWorkspacePullTimer() {
    if (this.workspacePullTimer) {
      clearInterval(this.workspacePullTimer);
    }

    this.workspacePullTimer = setInterval(() => {
      this.pullWorkspaceState({ silent: true }).catch(() => {});
    }, WORKSPACE_PULL_MS);
  }

  async pollRelayOnce() {
    const roomCode = cleanString(this.state.roomCode, '');
    if (!roomCode || this.state.pairedDevice) {
      return false;
    }

    try {
      const response = await fetch(`${RELAY_BASE_URL}/api/pair/poll/${roomCode}`);
      if (!response.ok) {
        return false;
      }
      const data = await response.json();
      if (!data?.paired) {
        return false;
      }

      const userId = cleanString(data.token, 'room-code-device') || 'room-code-device';
      this.state = {
        ...this.state,
        pairedDevice: {
          user_id: userId,
          paired_at: new Date().toISOString(),
        },
        workspaceId: cleanString(data.workspaceId, '') || this.state.workspaceId,
        workspaceToken: cleanString(data.desktopToken, '') || this.state.workspaceToken,
      };
      await this.persistState();
      await this.pullWorkspaceState({ silent: true });
      this.log('success', 'Mobile device paired through relay room code.');
      return true;
    } catch (_) {
      return false;
    }
  }

  async rotatePairing({ resetRoomCode }) {
    this.state = {
      ...this.state,
      pairingPin: randomPin(),
      pairingSecret: randomSecret(),
      pairedDevice: null,
      roomCode: resetRoomCode ? null : this.state.roomCode,
    };
    await this.persistState();
    this.log('info', 'Pairing credentials rotated.');
    if (resetRoomCode) {
      await this.registerRelay({ force: true });
    }
  }

  async pullWorkspaceState({ silent = false } = {}) {
    const workspaceToken = cleanString(this.state.workspaceToken, '');
    if (!workspaceToken) {
      return false;
    }

    try {
      const response = await fetch(`${RELAY_BASE_URL}/api/workspace/state`, {
        headers: {
          Authorization: `Bearer ${workspaceToken}`,
        },
      });
      if (!response.ok) {
        if (!silent) {
          this.log('error', `Workspace sync pull failed with status ${response.status}.`);
        }
        return false;
      }

      const data = await response.json();
      const revision = toInt(data.revision, 0);
      if (revision <= this.state.workspaceRevision) {
        return false;
      }

      this.state = {
        ...this.state,
        workspaceId: cleanString(data.workspaceId, '') || this.state.workspaceId,
        workspaceRevision: revision,
        macros: Array.isArray(data.macros) ? data.macros : this.state.macros,
        automations: Array.isArray(data.automations)
          ? sortAutomations(data.automations)
          : this.state.automations,
        pages: Array.isArray(data.pages) ? data.pages : this.state.pages,
        pinnedIds: Array.isArray(data.pinnedIds)
          ? data.pinnedIds.filter((entry) => typeof entry === 'string')
          : this.state.pinnedIds,
        lastSyncAt:
          typeof data.lastUpdatedAt === 'string' && data.lastUpdatedAt.trim()
            ? data.lastUpdatedAt
            : this.state.lastSyncAt,
        lastCloudSyncAt:
          typeof data.lastUpdatedAt === 'string' && data.lastUpdatedAt.trim()
            ? data.lastUpdatedAt
            : this.state.lastCloudSyncAt,
      };
      await this.persistState();
      if (!silent) {
        this.log(
          'sync',
          `Pulled workspace revision ${revision} from cloud (${this.state.automations.length} automations, ${this.state.macros.length} macros).`,
        );
      }
      return true;
    } catch (error) {
      if (!silent) {
        const message = error instanceof Error ? error.message : String(error);
        this.log('error', `Workspace sync pull failed: ${message}`);
      }
      return false;
    }
  }

  macroById() {
    return new Map(this.state.macros.map((macro) => [macro.id, macro]));
  }

  async executeMacro(macroId, options = {}) {
    const macrosById = this.macroById();
    const macro = macrosById.get(macroId);
    if (!macro) {
      throw new Error(`Macro "${macroId}" was not found.`);
    }

    const activeStack = options.activeStack || new Set();
    if (activeStack.has(macroId)) {
      return;
    }

    activeStack.add(macroId);
    try {
      for (const step of Array.isArray(macro.steps) ? macro.steps : []) {
        await this.executeMacroStep(step, macrosById, activeStack);
      }
    } finally {
      activeStack.delete(macroId);
    }
  }

  async executeMacroStep(step, macrosById, activeStack) {
    const stepType = cleanString(step.type, '');
    switch (stepType) {
      case 'delay':
        await sleep(Math.max(0, toInt(step.delayMs, 500)));
        return;
      case 'runMacro': {
        const targetMacroId = cleanString(step.targetId, '');
        if (!targetMacroId) {
          return;
        }
        if (activeStack.has(targetMacroId)) {
          return;
        }
        const nestedMacro = macrosById.get(targetMacroId);
        if (!nestedMacro) {
          return;
        }
        await this.executeMacro(targetMacroId, { activeStack });
        return;
      }
      case 'switchScene':
      case 'setPreviewScene':
      case 'showSource':
      case 'hideSource':
      case 'toggleSourceVisibility':
      case 'mute':
      case 'unmute':
      case 'toggleMute':
      case 'startStream':
      case 'stopStream':
      case 'startRecording':
      case 'stopRecording':
      case 'startVirtualCamera':
      case 'stopVirtualCamera':
      case 'enableStudioMode':
      case 'disableStudioMode':
        await this.obs.executeButtonAction({
          type: stepType,
          targetId: step.targetId,
          targetName: step.targetName,
        });
        return;
      default:
        throw new Error(`Unsupported macro step: ${stepType}`);
    }
  }

  async startAccountLinking() {
    try {
      const response = await fetch(`${RELAY_BASE_URL}/desktop/pairing/start`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          desktopDeviceId: this.state.desktopId,
          displayName: this.state.desktopName || os.hostname(),
          appVersion: AGENT_VERSION,
          protocolVersion: PROTOCOL_VERSION,
          platform: os.platform(),
        }),
      });

      if (!response.ok) {
        this.addActivityEntry('account', `Account linking start failed with status ${response.status}.`);
        return null;
      }

      const data = await response.json();
      const requestId = cleanString(data.pairingRequestId ?? data.requestId, '');
      const code = cleanString(data.manualCode ?? data.code, '');
      if (!requestId || !code) {
        this.addActivityEntry('account', 'Account linking start returned incomplete data.');
        return null;
      }

      const expiresAt = data.expiresAt || new Date(Date.now() + 300 * 1000).toISOString();
      const expiresIn = data.expiresIn || 300;

      this.state = {
        ...this.state,
        accountLinkingRequestId: requestId,
        accountLinkingCode: code,
        accountLinkingExpiresAt: expiresAt,
        accountLinkError: null,
      };
      await this.persistState();
      this.addActivityEntry('account', 'Account linking process started.');

      return {
        requestId,
        pairingRequestId: requestId,
        code,
        manualCode: code,
        qrPayload: data.qrPayload || null,
        expiresAt,
        pollIntervalSeconds: data.pollIntervalSeconds || 2,
      };
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      this.state = { ...this.state, accountLinkError: message };
      await this.persistState();
      this.addActivityEntry('account', `Account linking start failed: ${message}`);
      return null;
    }
  }

  async pollAccountLinking() {
    const requestId = cleanString(this.state.accountLinkingRequestId, '');
    if (!requestId) {
      return { status: 'none' };
    }

    try {
      const response = await fetch(`${RELAY_BASE_URL}/desktop/pairing/status/${requestId}`);
      if (!response.ok) {
        if (response.status === 404) {
          this.state = { ...this.state, accountLinkingRequestId: null, accountLinkingCode: null, accountLinkingExpiresAt: null };
          await this.persistState();
          return { status: 'expired' };
        }
        return { status: 'error', error: `Poll failed with status ${response.status}` };
      }

      const data = await response.json();
      const status = cleanString(data.status, 'pending');

      if (status === 'approved') {
        const exchangeToken = cleanString(data.exchangeToken, '');
        if (exchangeToken) {
          const exchangeResult = await this.exchangeAccountToken(exchangeToken);
          if (exchangeResult) {
            return { status: 'approved', ...exchangeResult };
          }
          return { status: 'exchange_failed' };
        }
        return { status: 'approved' };
      }

      if (status === 'expired') {
        this.state = { ...this.state, accountLinkingRequestId: null, accountLinkingCode: null, accountLinkingExpiresAt: null };
        await this.persistState();
      }

      return { status };
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      return { status: 'error', error: message };
    }
  }

  async exchangeAccountToken(exchangeToken) {
    try {
      const step1Response = await fetch(`${RELAY_BASE_URL}/desktop/pairing/exchange`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          pairingRequestId: this.state.accountLinkingRequestId,
          exchangeToken,
        }),
      });

      if (!step1Response.ok) {
        this.addActivityEntry('account', `Token exchange step 1 failed with status ${step1Response.status}.`);
        return null;
      }

      const step1Data = await step1Response.json();
      const exchangeCredential = cleanString(step1Data.exchangeCredential, '');
      if (!exchangeCredential) {
        this.addActivityEntry('account', 'Token exchange step 1 returned no exchange credential.');
        return null;
      }

      const step2Response = await fetch(`${RELAY_BASE_URL}/desktop/pairing/token`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ exchangeToken: exchangeCredential }),
      });

      if (!step2Response.ok) {
        this.addActivityEntry('account', `Token exchange step 2 failed with status ${step2Response.status}.`);
        return null;
      }

      const data = await step2Response.json();
      const deviceToken = cleanString(data.deviceToken, '');
      const workspaceId = cleanString(data.workspaceId, '');
      const localSharedSecret = cleanString(data.localSharedSecret, '');
      const mobileDeviceId = cleanString(data.mobileDeviceId, '');

      if (!deviceToken) {
        this.addActivityEntry('account', 'Token exchange returned no device token.');
        return null;
      }

      await secureStore('device_token', deviceToken);
      await secureStore('workspace_id', workspaceId);
      if (localSharedSecret && mobileDeviceId) {
        await secureStore(`local_secret:${mobileDeviceId}`, localSharedSecret);
      }

      this.state = {
        ...this.state,
        deviceToken: '',
        accountLinked: true,
        workspaceId: workspaceId || this.state.workspaceId,
        accountLinkingRequestId: null,
        accountLinkingCode: null,
        accountLinkingExpiresAt: null,
        accountLinkError: null,
      };
      await this.persistState();
      this.addActivityEntry('account', 'Desktop linked to account.');

      await this.syncWorkspaceFromCloud();

      return {
        linked: true,
        workspaceId: this.state.workspaceId,
        workspaceName: this.state.workspaceName,
      };
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      this.state = { ...this.state, accountLinkError: message };
      await this.persistState();
      this.addActivityEntry('account', `Token exchange failed: ${message}`);
      return null;
    }
  }

  async unlinkAccount() {
    const deviceToken = await secureLoad('device_token');
    if (deviceToken) {
      try {
        await fetch(`${RELAY_BASE_URL}/desktop/token/revoke`, {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            Authorization: `Bearer ${deviceToken}`,
          },
        });
      } catch (_) {}
    }

    await secureDelete('device_token');
    await secureDelete('workspace_id');

    this.state = {
      ...this.state,
      accountEmail: null,
      accountLinked: false,
      deviceToken: null,
      accountLinkingRequestId: null,
      accountLinkingCode: null,
      accountLinkingExpiresAt: null,
      accountLinkError: null,
      lastCloudSyncStatus: null,
    };
    await this.persistState();
    this.addActivityEntry('account', 'Desktop unlinked from account.');
  }

  async syncWorkspaceFromCloud() {
    const deviceToken = cleanString(this.state.deviceToken, '');
    if (!deviceToken) {
      return { synced: false, error: 'No device token. Link your account first.' };
    }

    try {
      const response = await fetch(`${RELAY_BASE_URL}/api/workspace/state`, {
        headers: {
          Authorization: `Bearer ${deviceToken}`,
        },
      });

      if (!response.ok) {
        const message = `Cloud sync failed with status ${response.status}.`;
        this.state = { ...this.state, lastCloudSyncStatus: message };
        await this.persistState();
        this.addActivityEntry('sync', message);
        return { synced: false, error: message };
      }

      const data = await response.json();
      const cloudRevision = toInt(data.revision, 0);
      const localRevision = this.state.workspaceRevision;
      const cloudLastSyncRevision = this.state.lastCloudSyncRevision;

      let conflict = false;

      if (cloudRevision > localRevision) {
        this.state = {
          ...this.state,
          workspaceId: cleanString(data.workspaceId, '') || this.state.workspaceId,
          workspaceRevision: cloudRevision,
          lastCloudSyncRevision: cloudRevision,
          macros: Array.isArray(data.macros) ? data.macros : this.state.macros,
          automations: Array.isArray(data.automations)
            ? sortAutomations(data.automations)
            : this.state.automations,
          pages: Array.isArray(data.pages) ? data.pages : this.state.pages,
          pinnedIds: Array.isArray(data.pinnedIds)
            ? data.pinnedIds.filter((entry) => typeof entry === 'string')
            : this.state.pinnedIds,
          lastSyncAt: typeof data.lastUpdatedAt === 'string' && data.lastUpdatedAt.trim()
            ? data.lastUpdatedAt
            : this.state.lastSyncAt,
          lastCloudSyncAt: typeof data.lastUpdatedAt === 'string' && data.lastUpdatedAt.trim()
            ? data.lastUpdatedAt
            : this.state.lastCloudSyncAt,
          lastCloudSyncStatus: 'Synced from cloud.',
        };
        await this.persistState();
        this.addActivityEntry('sync', `Workspace synced from cloud (revision ${cloudRevision}).`);
      } else if (localRevision > cloudLastSyncRevision && localRevision > cloudRevision) {
        conflict = true;
        this.state = { ...this.state, lastCloudSyncStatus: 'Conflict detected: local changes newer than cloud.' };
        await this.persistState();
        this.addActivityEntry('sync', 'Conflict detected: local workspace has changes newer than cloud.');
      } else {
        this.state = { ...this.state, lastCloudSyncStatus: 'Already up to date.' };
        await this.persistState();
      }

      return {
        synced: !conflict,
        conflict,
        cloudRevision,
        localRevision,
        lastCloudSyncRevision: this.state.lastCloudSyncRevision,
      };
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      this.state = { ...this.state, lastCloudSyncStatus: `Sync error: ${message}` };
      await this.persistState();
      this.addActivityEntry('sync', `Cloud sync failed: ${message}`);
      return { synced: false, error: message };
    }
  }

  async _getLocalAuthSecret(mobileDeviceId) {
    if (!mobileDeviceId) return null;
    try {
      return await secureLoad(`local_secret:${mobileDeviceId}`);
    } catch (_) {
      return null;
    }
  }

  addActivityEntry(type, message) {
    const entry = { type, message, timestamp: new Date().toISOString() };
    this.state = {
      ...this.state,
      activityLog: [...this.state.activityLog, entry].slice(-50),
    };
  }
}

const agent = new DesktopAgent();

async function main() {
  process.on('SIGINT', async () => {
    await agent.stop();
    process.exit(0);
  });
  process.on('SIGTERM', async () => {
    await agent.stop();
    process.exit(0);
  });

  await agent.start();
  process.stdout.write(`DeckPilot Desktop Agent ready at http://127.0.0.1:${agent.port}/\n`);
}

main().catch((error) => {
  process.stderr.write(`${error instanceof Error ? error.stack || error.message : String(error)}\n`);
  process.exit(1);
});
