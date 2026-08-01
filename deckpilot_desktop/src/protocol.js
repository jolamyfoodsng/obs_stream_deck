export const PROTOCOL_VERSION = 1;

export const MESSAGE_TYPE = Object.freeze({
  HELLO: 'hello',
  HELLO_ACK: 'hello.ack',
  AUTH_CHALLENGE: 'auth.challenge',
  AUTH_RESPONSE: 'auth.response',
  COMMAND: 'command',
  COMMAND_RESULT: 'command.result',
  STATE_SNAPSHOT: 'state.snapshot',
  STATE_PATCH: 'state.patch',
  RESYNC_REQUEST: 'state.resync.request',
  PING: 'ping',
  PONG: 'pong',
  ERROR: 'error',
});

export const COMMAND = Object.freeze({
  SCENE_SWITCH: 'scene.switch',
  SCENE_PREVIEW: 'scene.preview',
  SOURCE_SHOW: 'source.show',
  SOURCE_HIDE: 'source.hide',
  SOURCE_TOGGLE: 'source.toggle',
  AUDIO_MUTE: 'audio.mute',
  AUDIO_UNMUTE: 'audio.unmute',
  AUDIO_TOGGLE_MUTE: 'audio.toggleMute',
  STREAM_START: 'stream.start',
  STREAM_STOP: 'stream.stop',
  STREAM_TOGGLE: 'stream.toggle',
  RECORDING_START: 'recording.start',
  RECORDING_STOP: 'recording.stop',
  RECORDING_PAUSE: 'recording.pause',
  RECORDING_RESUME: 'recording.resume',
  RECORDING_TOGGLE: 'recording.toggle',
  VIRTUALCAM_START: 'virtualcam.start',
  VIRTUALCAM_STOP: 'virtualcam.stop',
  VIRTUALCAM_TOGGLE: 'virtualcam.toggle',
  STUDIO_ENABLE: 'studio.enable',
  STUDIO_DISABLE: 'studio.disable',
  STUDIO_TOGGLE: 'studio.toggle',
  SOURCE_SET_VOLUME: 'source.setVolume',
  OBS_REFRESH: 'obs.refresh',
});

export const ERROR_CODE = Object.freeze({
  UNKNOWN_COMMAND: 'UNKNOWN_COMMAND',
  INVALID_PAYLOAD: 'INVALID_PAYLOAD',
  UNAUTHORIZED: 'UNAUTHORIZED',
  PROTOCOL_VERSION_UNSUPPORTED: 'PROTOCOL_VERSION_UNSUPPORTED',
  OBS_UNAVAILABLE: 'OBS_UNAVAILABLE',
  OBS_ERROR: 'OBS_ERROR',
  INTERNAL_ERROR: 'INTERNAL_ERROR',
});

export const COMMAND_TO_OBS_ACTION = Object.freeze({
  [COMMAND.SCENE_SWITCH]: 'switchScene',
  [COMMAND.SCENE_PREVIEW]: 'setPreviewScene',
  [COMMAND.SOURCE_SHOW]: 'showSource',
  [COMMAND.SOURCE_HIDE]: 'hideSource',
  [COMMAND.SOURCE_TOGGLE]: 'toggleSourceVisibility',
  [COMMAND.AUDIO_MUTE]: 'mute',
  [COMMAND.AUDIO_UNMUTE]: 'unmute',
  [COMMAND.AUDIO_TOGGLE_MUTE]: 'toggleMute',
  [COMMAND.STREAM_START]: 'startStream',
  [COMMAND.STREAM_STOP]: 'stopStream',
  [COMMAND.STREAM_TOGGLE]: 'toggleStream',
  [COMMAND.RECORDING_START]: 'startRecording',
  [COMMAND.RECORDING_STOP]: 'stopRecording',
  [COMMAND.RECORDING_PAUSE]: 'pauseRecording',
  [COMMAND.RECORDING_RESUME]: 'resumeRecording',
  [COMMAND.RECORDING_TOGGLE]: 'toggleRecording',
  [COMMAND.VIRTUALCAM_START]: 'startVirtualCamera',
  [COMMAND.VIRTUALCAM_STOP]: 'stopVirtualCamera',
  [COMMAND.VIRTUALCAM_TOGGLE]: 'toggleVirtualCamera',
  [COMMAND.STUDIO_ENABLE]: 'enableStudioMode',
  [COMMAND.STUDIO_DISABLE]: 'disableStudioMode',
  [COMMAND.STUDIO_TOGGLE]: 'toggleStudioMode',
});

export function buildMessage(type, fields = {}) {
  return JSON.stringify({ type, ...fields });
}

export function buildError(id, code, message) {
  return buildMessage(MESSAGE_TYPE.ERROR, { id, code, message });
}

export function buildCommandResult(id, success, data) {
  return buildMessage(MESSAGE_TYPE.COMMAND_RESULT, { id, success, data: data ?? {} });
}

export function buildStateSnapshot(revision, state) {
  return buildMessage(MESSAGE_TYPE.STATE_SNAPSHOT, { revision, state });
}

export function buildStatePatch(revision, changes) {
  return buildMessage(MESSAGE_TYPE.STATE_PATCH, { revision, changes });
}

export function buildHelloAck(desktopId, desktopName, obsConnected) {
  return buildMessage(MESSAGE_TYPE.HELLO_ACK, {
    protocolVersion: PROTOCOL_VERSION,
    desktopId,
    desktopName,
    obsConnected,
  });
}

export function buildAuthChallenge({ sessionId, nonce, desktopDeviceId, protocolVersion }) {
  return buildMessage(MESSAGE_TYPE.AUTH_CHALLENGE, {
    sessionId,
    nonce,
    desktopDeviceId,
    protocolVersion: protocolVersion || PROTOCOL_VERSION,
  });
}

export function buildAuthResponse({ mobileDeviceId, proof }) {
  return buildMessage(MESSAGE_TYPE.AUTH_RESPONSE, {
    mobileDeviceId,
    proof,
  });
}
