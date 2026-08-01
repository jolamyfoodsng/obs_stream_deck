import { WebSocket } from 'ws';
import { secureLoad } from './secure-storage.js';

const CLOUD_RECONNECT_BASE_MS = 1000;
const CLOUD_RECONNECT_MAX_MS = 30000;
const CLOUD_RECONNECT_JITTER = 0.2;
const CLOUD_PING_INTERVAL_MS = 25000;
const CLOUD_PONG_TIMEOUT_MS = 10000;

export class CloudRelayClient {
  constructor({
    getObsState,
    executeButtonAction,
    executeMacro,
    setInputVolume,
    log,
    relayUrl,
  }) {
    this.getObsState = getObsState;
    this.executeButtonAction = executeButtonAction;
    this.executeMacro = executeMacro;
    this.setInputVolume = setInputVolume;
    this.log = log;
    this.relayUrl = relayUrl;

    this.ws = null;
    this.connected = false;
    this.disposed = false;
    this.reconnectAttempts = 0;
    this.reconnectTimer = null;
    this.lastPongAt = 0;
    this.sessionId = null;
    this.workspaceId = null;
  }

  async connect() {
    if (this.disposed) return;

    const deviceToken = await secureLoad('device_token');
    const deviceId = await secureLoad('device_id');
    const wsId = await secureLoad('workspace_id');

    if (!deviceToken || !deviceId || !wsId) {
      this.log('info', 'Cloud relay: not linked — skipping');
      return;
    }

    this.workspaceId = wsId;
    this._doConnect(deviceToken, deviceId, wsId);
  }

  _doConnect(token, deviceId, wsId) {
    if (this.disposed) return;

    const url = `${this.relayUrl}/connect/desktop?deviceId=${encodeURIComponent(deviceId)}&workspaceId=${encodeURIComponent(wsId)}`;

    try {
      this.ws = new WebSocket(url, {
        headers: { 'Authorization': `Bearer ${token}` },
      });
    } catch (err) {
      this.log('error', `Cloud relay connect failed: ${err.message}`);
      this._scheduleReconnect();
      return;
    }

    this.ws.on('open', () => {
      this.connected = true;
      this.reconnectAttempts = 0;
      this.lastPongAt = Date.now();
      this.log('success', 'Cloud relay connected');
    });

    this.ws.on('message', (data) => {
      try {
        this._handleMessage(JSON.parse(data.toString()));
      } catch (err) {
        this.log('error', `Cloud relay message error: ${err.message}`);
      }
    });

    this.ws.on('pong', () => {
      this.lastPongAt = Date.now();
    });

    this.ws.on('close', () => {
      this.connected = false;
      this.ws = null;
      this.log('info', 'Cloud relay disconnected');
      this._scheduleReconnect();
    });

    this.ws.on('error', (err) => {
      this.log('error', `Cloud relay error: ${err.message}`);
    });

    const pingTimer = setInterval(() => {
      if (!this.connected || !this.ws) { clearInterval(pingTimer); return; }
      const delta = Date.now() - this.lastPongAt;
      if (delta > CLOUD_PONG_TIMEOUT_MS) {
        try { this.ws.close(4002, 'Pong timeout'); } catch (_) {}
        clearInterval(pingTimer);
        return;
      }
      try { this.ws.send(JSON.stringify({ type: 'ping' })); } catch (_) {}
    }, CLOUD_PING_INTERVAL_MS);

    this.ws.on('close', () => clearInterval(pingTimer));
  }

  disconnect() {
    this.reconnectAttempts = 9999;
    this.connected = false;
    if (this.reconnectTimer) {
      clearTimeout(this.reconnectTimer);
      this.reconnectTimer = null;
    }
    if (this.ws) {
      try { this.ws.close(1000, 'Client disconnect'); } catch (_) {}
      this.ws = null;
    }
  }

  dispose() {
    this.disposed = true;
    this.disconnect();
  }

  _handleMessage(msg) {
    const type = msg.type || '';

    if (type === 'hello.ack') {
      this.sessionId = msg.sessionId;
      return;
    }

    if (type === 'ping') {
      try { this.ws.send(JSON.stringify({ type: 'pong' })); } catch (_) {}
      return;
    }

    if (type === 'pong') {
      this.lastPongAt = Date.now();
      return;
    }

    if (type === 'command') {
      this._handleRelayedCommand(msg);
      return;
    }

    if (type === 'state.resync.request') {
      this._sendStateSnapshot(msg.targetSessionId);
      return;
    }
  }

  async _handleRelayedCommand(msg) {
    const commandId = msg.id || '';
    const command = msg.command || '';
    const payload = msg.payload || {};
    const sourceSessionId = msg.sourceSessionId || '';

    const result = { id: commandId, type: 'command.result' };
    if (sourceSessionId) result.sourceSessionId = sourceSessionId;

    try {
      const obsAction = this._commandToObsAction(command);
      if (!obsAction) {
        result.success = false;
        result.data = { error: `Unknown command: ${command}` };
        try { this.ws.send(JSON.stringify(result)); } catch (_) {}
        return;
      }

      const action = this._buildObsAction(obsAction, payload);
      await this.executeButtonAction(action);
      result.success = true;
      result.data = {};
      try { this.ws.send(JSON.stringify(result)); } catch (_) {}
    } catch (err) {
      result.success = false;
      result.data = { error: err.message };
      try { this.ws.send(JSON.stringify(result)); } catch (_) {}
    }
  }

  _sendStateSnapshot(targetSessionId) {
    const obsState = this.getObsState();
    const msg = { type: 'state.snapshot', revision: Date.now(), state: obsState };
    if (targetSessionId) msg.targetSessionId = targetSessionId;
    try { this.ws.send(JSON.stringify(msg)); } catch (_) {}
  }

  sendObsStatePatch(changes) {
    if (!this.connected || !this.ws) return;
    const msg = { type: 'state.patch', revision: Date.now(), changes };
    try { this.ws.send(JSON.stringify(msg)); } catch (_) {}
  }

  _commandToObsAction(command) {
    const map = {
      'scene.switch': 'switchScene',
      'scene.preview': 'setPreviewScene',
      'source.show': 'showSource',
      'source.hide': 'hideSource',
      'source.toggle': 'toggleSourceVisibility',
      'audio.mute': 'mute',
      'audio.unmute': 'unmute',
      'audio.toggleMute': 'toggleMute',
      'source.setVolume': 'setInputVolume',
      'stream.start': 'startStream',
      'stream.stop': 'stopStream',
      'stream.toggle': 'toggleStream',
      'recording.start': 'startRecording',
      'recording.stop': 'stopRecording',
      'recording.pause': 'pauseRecording',
      'recording.resume': 'resumeRecording',
      'recording.toggle': 'toggleRecording',
      'virtualcam.start': 'startVirtualCamera',
      'virtualcam.stop': 'stopVirtualCamera',
      'virtualcam.toggle': 'toggleVirtualCamera',
      'studio.enable': 'enableStudioMode',
      'studio.disable': 'disableStudioMode',
      'studio.toggle': 'toggleStudioMode',
      'obs.refresh': 'obsRefresh',
    };
    return map[command] || null;
  }

  _buildObsAction(obsAction, payload) {
    const action = {
      type: obsAction,
      targetId: payload.targetId || '',
      targetName: payload.targetName || '',
    };
    if (obsAction === 'switchScene' || obsAction === 'setPreviewScene') {
      action.targetId = payload.sceneName || action.targetId;
      action.targetName = action.targetId;
    }
    return action;
  }

  _scheduleReconnect() {
    if (this.reconnectAttempts >= 9999) return;
    if (this.reconnectTimer) return;

    this.reconnectAttempts += 1;
    const wait = Math.min(CLOUD_RECONNECT_BASE_MS * Math.pow(2, this.reconnectAttempts - 1), CLOUD_RECONNECT_MAX_MS);
    const jitter = Math.floor(Math.random() * wait * CLOUD_RECONNECT_JITTER);

    this.reconnectTimer = setTimeout(() => {
      this.reconnectTimer = null;
      this.connect();
    }, wait + jitter);
  }

  get connectedCount() {
    return this.connected ? 1 : 0;
  }
}
