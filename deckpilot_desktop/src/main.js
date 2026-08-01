// DeckPilot Desktop - Main JavaScript
let currentPage = 'dashboard';
let refreshInterval = null;
let latestAppState = null;
let mobilePollInterval = null;
let mobileRequestId = null;

async function apiRequest(path, options) {
  const response = await fetch(path, Object.assign({
    headers: {
      'Content-Type': 'application/json'
    }
  }, options || {}));

  let data = null;
  const text = await response.text();
  if (text) {
    try {
      data = JSON.parse(text);
    } catch (_) {
      data = text;
    }
  }

  if (!response.ok) {
    const message = data && data.error ? data.error : ('Request failed: ' + response.status);
    throw new Error(message);
  }

  return data;
}

function invoke(cmd, args) {
  switch (cmd) {
    case 'get_app_state':
      return apiRequest('/api/app/state', { method: 'GET' });
    case 'connect_obs':
      return apiRequest('/api/obs/connect', {
        method: 'POST',
        body: JSON.stringify(args || {})
      });
    case 'disconnect_obs':
      return apiRequest('/api/obs/disconnect', { method: 'POST' });
    case 'switch_scene':
      return apiRequest('/api/obs/scene/switch', {
        method: 'POST',
        body: JSON.stringify({ sceneName: args && args.sceneName })
      });
    case 'toggle_streaming':
      return apiRequest('/api/obs/stream/toggle', { method: 'POST' });
    case 'toggle_automations':
      return apiRequest('/api/automations/toggle', { method: 'POST' });
    case 'toggle_automation_rule':
      return apiRequest('/api/automations/' + encodeURIComponent(args.id) + '/toggle', { method: 'POST' });
    case 'save_config':
      return apiRequest('/api/settings', {
        method: 'POST',
        body: JSON.stringify(args && args.config ? args.config : {})
      });
    case 'reset_config':
      return apiRequest('/api/settings/reset', { method: 'POST' });
    case 'test_desktop_notification':
      return apiRequest('/api/notifications/test', { method: 'POST' });
    case 'set_notification_permission':
      return apiRequest('/api/notifications/permission', {
        method: 'POST',
        body: JSON.stringify({ enabled: !!(args && args.enabled) })
      });
    case 'test_connection':
      return apiRequest('/api/obs/test-connection', {
        method: 'POST',
        body: JSON.stringify(args || {})
      });
    case 'get_logs': {
      var filter = args && args.filter ? '?filter=' + encodeURIComponent(args.filter) : '';
      return apiRequest('/api/logs' + filter, { method: 'GET' });
    }
    case 'clear_logs':
      return apiRequest('/api/logs', { method: 'DELETE' });
    case 'get_pairing_pin':
      return apiRequest('/api/pair/pin', { method: 'GET' }).then(function(data) {
        return data ? data.pin : null;
      });
    case 'get_paired_device':
      return apiRequest('/api/pair/device', { method: 'GET' });
    case 'get_local_ip':
      return apiRequest('/api/local-ip', { method: 'GET' }).then(function(data) {
        return data ? data.ip : null;
      });
    case 'get_relay_state':
      return apiRequest('/api/relay/state', { method: 'GET' });
    case 'register_relay':
      return apiRequest('/api/relay/register', { method: 'POST' }).then(function(data) {
        return data ? data.code : null;
      });
    case 'regenerate_pin':
      return apiRequest('/api/pair/regenerate', { method: 'POST' });
    case 'unpair_device':
      return apiRequest('/api/pair', { method: 'DELETE' });
    case 'poll_relay':
      return apiRequest('/api/relay/poll', { method: 'POST' }).then(function(data) {
        return !!(data && data.paired);
      });
    case 'tauri_check_update':
      return invokeTauri('check_for_update');
    case 'tauri_install_update':
      return invokeTauri('install_update');
    case 'get_account_status':
      return apiRequest('/api/account/status');
    case 'account_link_start':
      return apiRequest('/api/account/link/start', { method: 'POST' });
    case 'account_link_status':
      return apiRequest('/api/account/link/status');
    case 'account_link_cancel':
      return apiRequest('/api/account/link/cancel', { method: 'POST' });
    case 'account_unlink':
      return apiRequest('/api/account/unlink', { method: 'POST' });
    case 'account_sync_workspace':
      return apiRequest('/api/account/workspace/sync', { method: 'POST' });
    case 'get_account_activity':
      return apiRequest('/api/account/activity');
    default:
      return Promise.reject(new Error('Unsupported desktop command: ' + cmd));
  }
}

function invokeTauri(cmd) {
  try {
    const tauri = window.__TAURI__;
    if (tauri && tauri.core && tauri.core.invoke) {
      return tauri.core.invoke(cmd);
    }
    if (tauri && tauri.invoke) {
      return tauri.invoke(cmd);
    }
  } catch (_) {}
  return Promise.reject(new Error('Not running in Tauri shell'));
}

// --- Account Linking API ---
async function getAccountStatus() {
  return invoke('get_account_status');
}

async function startAccountLink() {
  return invoke('account_link_start');
}

async function pollAccountLinkStatus() {
  return invoke('account_link_status');
}

async function cancelAccountLink() {
  return invoke('account_link_cancel');
}

async function unlinkAccount() {
  return invoke('account_unlink');
}

async function syncWorkspaceFromCloud() {
  return invoke('account_sync_workspace');
}

async function getAccountActivity() {
  return invoke('get_account_activity');
}

// --- Toast ---
function showToast(message, type) {
  type = type || 'info';
  const container = document.getElementById('toast-container');
  const toast = document.createElement('div');
  toast.className = 'toast toast-' + type;

  const icons = {
    success: '<svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M22 11.08V12a10 10 0 1 1-5.93-9.14"/><polyline points="22 4 12 14.01 9 11.01"/></svg>',
    error: '<svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><circle cx="12" cy="12" r="10"/><line x1="15" y1="9" x2="9" y2="15"/><line x1="9" y1="9" x2="15" y2="15"/></svg>',
    info: '<svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><circle cx="12" cy="12" r="10"/><line x1="12" y1="16" x2="12" y2="12"/><line x1="12" y1="8" x2="12.01" y2="8"/></svg>',
    loading: '<svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" class="spinner"><path d="M21 12a9 9 0 1 1-6.219-8.56"/></svg>'
  };

  toast.innerHTML = '<span class="toast-icon">' + (icons[type] || icons.info) + '</span><span class="toast-message">' + escapeHtml(message) + '</span>';
  container.appendChild(toast);

  requestAnimationFrame(function() { toast.classList.add('toast-visible'); });

  if (type !== 'loading') {
    setTimeout(function() {
      toast.classList.remove('toast-visible');
      setTimeout(function() { toast.remove(); }, 300);
    }, 4000);
  }

  return toast;
}

function removeToast(toast) {
  if (toast) {
    toast.classList.remove('toast-visible');
    setTimeout(function() { toast.remove(); }, 300);
  }
}

// --- Sidebar ---
function handleNav(e, page) {
  e.preventDefault();
  navigateTo(page);
}

function toggleSidebar() {
  const sidebar = document.getElementById('sidebar');
  const closeIcon = document.getElementById('toggle-icon-close');
  const openIcon = document.getElementById('toggle-icon-open');
  sidebar.classList.toggle('collapsed');
  const collapsed = sidebar.classList.contains('collapsed');
  closeIcon.style.display = collapsed ? 'none' : '';
  openIcon.style.display = collapsed ? '' : 'none';
  localStorage.setItem('sidebar-collapsed', collapsed);
}

document.getElementById('sidebar-toggle').addEventListener('click', toggleSidebar);

// --- Button loading state ---
function setLoading(btn, loading) {
  if (loading) {
    btn.dataset.originalText = btn.innerHTML;
    btn.disabled = true;
    btn.innerHTML = '<svg class="spinner" width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5"><path d="M21 12a9 9 0 1 1-6.219-8.56"/></svg>';
  } else {
    btn.disabled = false;
    btn.innerHTML = btn.dataset.originalText || btn.textContent;
  }
}

// --- Navigation ---
function navigateTo(page) {
  currentPage = page;

  document.querySelectorAll('.nav-link').forEach(function(l) { l.classList.remove('active'); });
  document.querySelector('.nav-link[data-page="' + page + '"]').classList.add('active');

  document.querySelectorAll('.page').forEach(function(p) { p.classList.remove('active'); });
  document.getElementById('page-' + page).classList.add('active');

  if (page === 'dashboard') loadDashboard();
  else if (page === 'automations') loadAutomations();
  else if (page === 'settings') loadSettings();
  else if (page === 'logs') loadLogs();
}

// --- Dashboard ---
async function loadDashboard() {
  try {
    const [state, accountStatus, pairedDevice] = await Promise.all([
      invoke('get_app_state'),
      getAccountStatus().catch(() => ({ linked: false })),
      invoke('get_paired_device').catch(() => null),
    ]);
    latestAppState = Object.assign({}, state, {
      accountEmail: accountStatus && accountStatus.linked ? accountStatus.email : null,
      accountLinked: !!(accountStatus && accountStatus.linked),
      pairedDevice: pairedDevice || null,
    });
    updateDashboard(latestAppState);
    if (state.config.auto_connect !== false && !state.obs.connected) {
      try {
        const c = state.config;
        await invoke('connect_obs', { host: c.obs_host || '127.0.0.1', port: c.obs_port || 4455, password: c.obs_password || '' });
        refreshCurrentPage();
      } catch (_) {}
    }
  } catch (err) {
    console.error('Failed to load state:', err);
  }
}

function updateDashboard(state) {
  const accountLinked = !!(latestAppState && latestAppState.accountLinked);
  const obsConnected = state.obs.connected;
  
  if (accountLinked) {
    document.getElementById('setup-mode').style.display = 'none';
    document.getElementById('ready-mode').style.display = '';
    updateReadyMode(state);
    updateActivityCard();
    document.getElementById('home-status').textContent = 'Linked';
    document.getElementById('home-status').className = 'status-pill status-pill-ready';
  } else {
    document.getElementById('setup-mode').style.display = '';
    document.getElementById('ready-mode').style.display = 'none';
    updateSetupMode(state);
    document.getElementById('home-status').textContent = 'Not linked';
    document.getElementById('home-status').className = 'status-pill';
  }
  
  updateObsIndicators(state);
  syncAutomationToggles(state);
}

function updateSetupMode(state) {
  const accountLinked = !!(latestAppState && latestAppState.accountLinked);
  const hero = document.getElementById('setup-mode');
  if (!hero) return;

  if (accountLinked) {
    hero.innerHTML =
      '<div class="setup-hero setup-hero-linked">' +
        '<div class="setup-hero-icon">' +
          '<svg width="48" height="48" viewBox="0 0 24 24" fill="none" stroke="var(--success)" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round">' +
            '<path d="M22 11.08V12a10 10 0 1 1-5.93-9.14" />' +
            '<polyline points="22 4 12 14.01 9 11.01" />' +
          '</svg>' +
        '</div>' +
        '<h2 class="setup-hero-title" style="color:var(--text-primary)">Account linked</h2>' +
        '<p class="setup-hero-desc">This computer is connected to your DeckPilot account. Sync automations and manage from your mobile app.</p>' +
        '<div class="setup-hero-actions">' +
          '<button class="btn btn-primary" onclick="openMobileModal()">Manage Connection</button>' +
        '</div>' +
      '</div>';
    return;
  }

  // Show default hero (already in HTML)
  document.getElementById('btn-connect-mobile').textContent = 'Link with Mobile App';
}

function updateReadyMode(state) {
  const email = latestAppState ? (latestAppState.accountEmail || '--') : '--';
  document.getElementById('ready-account-email').textContent = email;
  document.getElementById('ready-account-workspace').textContent = (state.workspace && state.workspace.id) ? (state.workspace.name || 'Connected') : '--';
  document.getElementById('ready-account-last-sync').textContent = formatTimestamp(state.workspace && state.workspace.last_cloud_sync_at ? state.workspace.last_cloud_sync_at : state.last_sync_at);
  
  const device = latestAppState ? latestAppState.pairedDevice : null;
  document.getElementById('ready-phone-name').textContent = device ? (device.deviceName || 'Phone') : '--';
  document.getElementById('ready-phone-type').textContent = device ? 'Local Wi-Fi' : '--';
  document.getElementById('ready-phone-last').textContent = device ? (device.lastSeen ? formatTimestamp(device.lastSeen) : 'Just now') : '--';
  
  document.getElementById('ready-obs-status').textContent = state.obs.connected ? 'Connected' : 'Disconnected';
  document.getElementById('ready-obs-scene').textContent = state.obs.current_scene || '--';
  document.getElementById('ready-obs-count').textContent = (state.obs.scenes || []).length;
  
  document.getElementById('ready-auto-status').textContent = state.automations_paused ? 'Paused' : 'Running';
  document.getElementById('ready-auto-count').textContent = Array.isArray(state.automations) ? state.automations.length : 0;
  document.getElementById('ready-auto-last').textContent = '--';
}

async function loadAutomations() {
  try {
    const state = await invoke('get_app_state');
    latestAppState = state;
    updateAutomationPage(state);
  } catch (err) {
    console.error('Failed to load automations:', err);
  }
}

function updateAutomationPage(state) {
  updateObsIndicators(state);
  syncAutomationToggles(state);

  const syncTime = state.workspace && state.workspace.last_cloud_sync_at
    ? state.workspace.last_cloud_sync_at
    : state.last_sync_at;
  const obsBanner = document.getElementById('automations-obs-banner');
  obsBanner.classList.toggle('visible', !state.obs.connected);

  document.getElementById('automation-page-status').textContent = state.automations_paused ? 'Paused' : 'Active';
  document.getElementById('automation-page-count').textContent = Array.isArray(state.automations) ? state.automations.length : 0;
  document.getElementById('automation-page-scene').textContent = state.obs.current_scene || '--';
  document.getElementById('automation-page-last-sync').textContent = formatTimestamp(syncTime);

  renderAutomationList(Array.isArray(state.automations) ? state.automations : []);
  renderSceneGrid('scene-grid-automation', state.obs.scenes || [], state.obs.current_scene);
}

function updateObsIndicators(state) {
  const obsClass = state.obs.connected ? 'connected' : 'disconnected';

  const dot = document.getElementById('obs-status-dot');
  if (dot) dot.className = 'status-dot ' + obsClass;
  const autoDot = document.getElementById('automation-status-dot');
  if (autoDot) autoDot.className = 'status-dot ' + (state.automations_paused ? 'disconnected' : 'connected');
}

function syncAutomationToggles(state) {
  const isActive = !state.automations_paused;
  ['toggle-automations-dashboard', 'toggle-automations-page'].forEach(function(id) {
    const input = document.getElementById(id);
    if (input) input.checked = isActive;
  });
}

function renderSceneGrid(containerId, scenes, currentScene) {
  const sceneGrid = document.getElementById(containerId);
  if (!sceneGrid) return;

  sceneGrid.innerHTML = '';
  if (!scenes || scenes.length === 0) {
    sceneGrid.innerHTML = '<div class="empty-state">No scenes available yet.</div>';
    return;
  }

  scenes.forEach(function(scene) {
    const btn = document.createElement('button');
    btn.className = 'scene-btn' + (scene === currentScene ? ' active' : '');
    btn.textContent = scene;
    btn.onclick = function() { switchScene(scene); };
    sceneGrid.appendChild(btn);
  });
}

function renderAutomationList(automations) {
  const container = document.getElementById('automation-list');
  if (!container) return;

  if (!automations.length) {
    container.innerHTML = '<div class="empty-state">No synced automations yet. Create them on the phone and they will appear here.</div>';
    return;
  }

  container.innerHTML = automations.map(function(rule) {
    const enabled = rule.isEnabled !== false;
    const stateClass = enabled ? 'automation-pill-enabled' : 'automation-pill-disabled';
    const stateText = enabled ? 'Enabled' : 'Disabled';
    const starterPill = rule.isStarter ? '<span class="automation-pill automation-pill-starter">Starter</span>' : '';

    return ''
      + '<div class="automation-item">'
      + '  <div class="automation-item-head">'
      + '    <div class="automation-title-block">'
      + '      <div class="automation-title-row">'
      + '        <span class="automation-name">' + escapeHtml(rule.name || 'Untitled automation') + '</span>'
      +          starterPill
      + '      </div>'
      + '      <div class="automation-detail"><strong>When:</strong> ' + escapeHtml(describeAutomationTrigger(rule)) + '</div>'
      + '      <div class="automation-detail"><strong>Then:</strong> ' + escapeHtml(describeAutomationAction(rule)) + '</div>'
      + '    </div>'
      + '    <label class="toggle-label automation-rule-toggle">'
      + '      <input type="checkbox" ' + (enabled ? 'checked' : '') + ' onchange="toggleAutomationRule(\'' + escapeHtmlAttr(rule.id) + '\', this)">'
      + '      <span class="toggle-slider"></span>'
      + '      <span class="toggle-label-text">' + stateText + '</span>'
      + '    </label>'
      + '  </div>'
      + '</div>';
  }).join('');
}

function describeAutomationTrigger(rule) {
  const trigger = humanizeAutomationKey(rule && rule.trigger ? rule.trigger : 'unknownTrigger');
  const condition = rule && rule.triggerCondition ? rule.triggerCondition : {};
  const details = [];

  if (condition.sceneName) details.push('scene ' + condition.sceneName);
  else if (condition.audioSourceName) details.push('audio ' + condition.audioSourceName);
  else if (condition.targetName) details.push(condition.targetName);

  if (condition.threshold !== undefined && condition.threshold !== null) {
    details.push('threshold ' + condition.threshold);
  }
  if (condition.durationSeconds) {
    details.push('for ' + condition.durationSeconds + 's');
  }
  if (condition.cooldownSeconds) {
    details.push('cooldown ' + condition.cooldownSeconds + 's');
  }

  return details.length ? trigger + ' | ' + details.join(' | ') : trigger;
}

function describeAutomationAction(rule) {
  const action = rule && rule.action ? rule.action : {};
  const actionType = action.type || 'unknownAction';
  const label = humanizeAutomationKey(actionType);
  const target = action.targetName || action.targetId || '';
  const details = [];

  if (target) details.push(target);

  if (action.metadata && typeof action.metadata === 'object') {
    if (action.metadata.delaySeconds) details.push('delay ' + action.metadata.delaySeconds + 's');
    else if (action.metadata.delayMs) details.push('delay ' + action.metadata.delayMs + 'ms');
    if (action.metadata.message) details.push(String(action.metadata.message));
  }

  return details.length ? label + ' | ' + details.join(' | ') : label;
}

function humanizeAutomationKey(value) {
  return String(value || '')
    .replace(/([a-z0-9])([A-Z])/g, '$1 $2')
    .replace(/[_-]+/g, ' ')
    .replace(/\s+/g, ' ')
    .trim()
    .replace(/\b\w/g, function(match) { return match.toUpperCase(); })
    .replace(/\bObs\b/g, 'OBS')
    .replace(/\bBrb\b/g, 'BRB')
    .replace(/\bCpu\b/g, 'CPU');
}

function refreshCurrentPage() {
  if (currentPage === 'dashboard') loadDashboard();
  else if (currentPage === 'automations') loadAutomations();
  else if (currentPage === 'settings') loadSettings();
  else if (currentPage === 'logs') loadLogs();
}

async function reconnectObs(btn) {
  setLoading(btn, true);
  const toast = showToast('Connecting to OBS...', 'loading');
  try {
    const state = await invoke('get_app_state');
    const c = state.config;
    await invoke('connect_obs', { host: c.obs_host || '127.0.0.1', port: c.obs_port || 4455, password: c.obs_password || '' });
    removeToast(toast);
    showToast('Connected to OBS', 'success');
    const reconnectBtn = document.getElementById('btn-reconnect');
    if (reconnectBtn) reconnectBtn.style.display = 'none';
    const disconnectBtn = document.getElementById('btn-disconnect');
    if (disconnectBtn) disconnectBtn.style.display = '';
    refreshCurrentPage();
  } catch (err) {
    removeToast(toast);
    showToast('Connection failed: ' + err, 'error');
    console.error('Connect failed:', err);
  } finally {
    setLoading(btn, false);
  }
}

async function disconnectObs(btn) {
  setLoading(btn, true);
  try {
    await invoke('disconnect_obs');
    showToast('Disconnected from OBS', 'info');
    const reconnectBtn = document.getElementById('btn-reconnect');
    if (reconnectBtn) reconnectBtn.style.display = '';
    const disconnectBtn = document.getElementById('btn-disconnect');
    if (disconnectBtn) disconnectBtn.style.display = 'none';
    refreshCurrentPage();
  } catch (err) {
    showToast('Disconnect failed: ' + err, 'error');
    console.error('Disconnect failed:', err);
  } finally {
    setLoading(btn, false);
  }
}

async function switchScene(sceneName) {
  try {
    await invoke('switch_scene', { sceneName });
    showToast('Switched to ' + sceneName, 'success');
    refreshCurrentPage();
  } catch (err) {
    showToast('Scene switch failed: ' + err, 'error');
    console.error('Scene switch failed:', err);
  }
}

async function toggleStream(btn) {
  setLoading(btn, true);
  try {
    await invoke('toggle_streaming');
    refreshCurrentPage();
  } catch (err) {
    showToast('Toggle stream failed: ' + err, 'error');
    console.error('Toggle stream failed:', err);
  } finally {
    setLoading(btn, false);
  }
}

async function toggleAutomations() {
  try {
    await invoke('toggle_automations');
    refreshCurrentPage();
  } catch (err) {
    showToast('Toggle failed: ' + err, 'error');
    console.error('Toggle automations failed:', err);
  }
}

async function toggleAutomationRule(ruleId, checkbox) {
  checkbox.disabled = true;
  try {
    const result = await invoke('toggle_automation_rule', { id: ruleId });
    const label = checkbox.closest('.toggle-label');
    if (label) {
      const textSpan = label.querySelector('.toggle-label-text');
      if (textSpan) textSpan.textContent = result.isEnabled ? 'Enabled' : 'Disabled';
    }
    showToast('Automation ' + (result.isEnabled ? 'enabled' : 'disabled'), 'success');
  } catch (err) {
    checkbox.checked = !checkbox.checked;
    showToast('Failed to toggle: ' + err, 'error');
    console.error('Toggle rule failed:', err);
  } finally {
    checkbox.disabled = false;
  }
}

// --- Settings ---
async function loadSettings() {
  try {
    const state = await invoke('get_app_state');
    latestAppState = state;
    const c = state.config;
    document.getElementById('obs-host').value = c.obs_host || '127.0.0.1';
    document.getElementById('obs-port').value = c.obs_port || 4455;
    document.getElementById('obs-password').value = c.obs_password || '';
    document.getElementById('auto-connect').checked = c.auto_connect !== false;
    document.getElementById('allow-discovery').checked = c.allow_discovery || false;
    document.getElementById('desktop-notifications').checked = c.desktop_notifications !== false;
    updateNotificationStatus(c.desktop_notifications !== false);
  } catch (err) {
    console.error('Failed to load settings:', err);
  }
}

async function saveSettings(btn) {
  setLoading(btn, true);
  const currentConfig = latestAppState && latestAppState.config ? latestAppState.config : {};
  const config = {
    obs_host: document.getElementById('obs-host').value,
    obs_port: parseInt(document.getElementById('obs-port').value) || 4455,
    obs_password: document.getElementById('obs-password').value,
    auto_connect: document.getElementById('auto-connect').checked,
    allow_discovery: document.getElementById('allow-discovery').checked,
    desktop_notifications: document.getElementById('desktop-notifications').checked,
    sync_port: currentConfig.sync_port || 8080,
    pinned_macro_ids: Array.isArray(currentConfig.pinned_macro_ids) ? currentConfig.pinned_macro_ids : [],
    macro_names: currentConfig.macro_names || {},
    automation_paused: latestAppState ? latestAppState.automations_paused : false,
  };
  try {
    await invoke('save_config', { config });
    showToast('Settings saved', 'success');
  } catch (err) {
    showToast('Failed to save: ' + err, 'error');
    console.error('Failed to save settings:', err);
  } finally {
    setLoading(btn, false);
  }
}

async function resetSettings() {
  if (!confirm('Reset all settings to defaults?')) return;
  try {
    const config = await invoke('reset_config');
    latestAppState = latestAppState || {};
    latestAppState.automations_paused = !!config.automation_paused;
    latestAppState.config = config;
    document.getElementById('obs-host').value = config.obs_host;
    document.getElementById('obs-port').value = config.obs_port;
    document.getElementById('obs-password').value = config.obs_password;
    document.getElementById('auto-connect').checked = config.auto_connect;
    document.getElementById('allow-discovery').checked = config.allow_discovery;
    document.getElementById('desktop-notifications').checked = config.desktop_notifications !== false;
    updateNotificationStatus(config.desktop_notifications !== false);
    showToast('Settings reset to defaults', 'info');
  } catch (err) {
    showToast('Failed to reset: ' + err, 'error');
    console.error('Failed to reset settings:', err);
  }
}

function updateNotificationStatus(enabled) {
  const status = document.getElementById('notification-status-text');
  if (status) {
    status.textContent = enabled ? 'Enabled' : 'Off';
  }
}

async function testDesktopNotification(btn) {
  setLoading(btn, true);
  try {
    const result = await invoke('test_desktop_notification');
    if (result && result.skipped) {
      showToast('Notifications are disabled', 'info');
      return;
    }
    showToast('Test notification sent', 'success');
  } catch (err) {
    showToast('Notification failed: ' + err.message, 'error');
    console.error('Notification test failed:', err);
  } finally {
    setLoading(btn, false);
  }
}

async function checkNotificationPermission() {
  try {
    const consentModal = document.getElementById('consent-modal');
    if (consentModal && consentModal.classList.contains('active')) {
      setTimeout(checkNotificationPermission, 1000);
      return;
    }

    const state = await invoke('get_app_state');
    const asked = !!(state.notifications && state.notifications.permission_asked);
    if (asked) {
      return;
    }

    const modal = document.getElementById('notification-permission-modal');
    if (modal) {
      modal.style.display = 'flex';
      modal.classList.add('active');
    }
  } catch (_) {}
}

async function setNotificationPermission(enabled, btn) {
  setLoading(btn, true);
  try {
    await invoke('set_notification_permission', { enabled: enabled });
    const modal = document.getElementById('notification-permission-modal');
    if (modal) {
      modal.style.display = 'none';
      modal.classList.remove('active');
    }

    const checkbox = document.getElementById('desktop-notifications');
    if (checkbox) checkbox.checked = enabled;
    updateNotificationStatus(enabled);
    showToast(enabled ? 'Desktop notifications enabled' : 'Desktop notifications disabled', enabled ? 'success' : 'info');
  } catch (err) {
    showToast('Notification permission failed: ' + err.message, 'error');
  } finally {
    setLoading(btn, false);
  }
}

async function testConnection(btn) { testObsSettingsConnection(btn); }

async function testObsSettingsConnection(btn) {
  setLoading(btn, true);
  const toast = showToast('Testing connection...', 'loading');
  const host = document.getElementById('obs-host').value;
  const port = parseInt(document.getElementById('obs-port').value) || 4455;
  const password = document.getElementById('obs-password').value;
  try {
    await invoke('test_connection', { host: host, port: port, password: password });
    removeToast(toast);
    showToast('Connection successful', 'success');
  } catch (err) {
    removeToast(toast);
    showToast('Connection failed: ' + err, 'error');
  } finally {
    setLoading(btn, false);
  }
}

async function checkForUpdate(btn) {
  const statusText = document.getElementById('update-status-text');
  const installBtn = document.getElementById('btn-install-update');
  setLoading(btn, true);
  statusText.textContent = 'Checking...';
  installBtn.style.display = 'none';
  try {
    const message = await invoke('tauri_check_update');
    if (message) {
      statusText.textContent = message;
      installBtn.style.display = '';
      showToast(message, 'info');
    } else {
      statusText.textContent = 'Up to date';
      showToast('App is up to date', 'success');
    }
  } catch (err) {
    statusText.textContent = 'Update check unavailable';
    if (err.message && err.message.indexOf('tauri') === -1) {
      statusText.textContent = 'Error: ' + err.message;
    }
    console.error('Update check error:', err);
  } finally {
    setLoading(btn, false);
  }
}

async function installUpdate(btn) {
  setLoading(btn, true);
  try {
    await invoke('tauri_install_update');
    showToast('Update installed. The app will restart.', 'success');
  } catch (err) {
    showToast('Update install failed: ' + err, 'error');
    console.error('Update install error:', err);
  } finally {
    setLoading(btn, false);
  }
}

// --- Logs ---
async function loadLogs() {
  try {
    const filter = document.getElementById('log-filter').value || null;
    const logs = await invoke('get_logs', { filter: filter });
    renderLogs(logs);
  } catch (err) {
    console.error('Failed to load logs:', err);
  }
}

function renderLogs(logs) {
  const container = document.getElementById('logs-container');
  if (logs.length === 0) {
    container.innerHTML = '<div class="logs-empty">No logs yet</div>';
    return;
  }
  container.innerHTML = logs
    .sort(function(a, b) { return new Date(b.timestamp) - new Date(a.timestamp); })
    .map(function(log) {
      var time = new Date(log.timestamp).toLocaleTimeString();
      var type = log.log_type.toLowerCase();
      return '<div class="log-entry"><span class="log-time">' + time + '</span><span class="log-type ' + type + '">' + type.toUpperCase() + '</span><span class="log-message">' + escapeHtml(log.message) + '</span></div>';
    })
    .join('');
}

async function clearLogs() {
  try {
    await invoke('clear_logs');
    showToast('Logs cleared', 'info');
    loadLogs();
  } catch (err) {
    showToast('Failed to clear logs: ' + err, 'error');
    console.error('Failed to clear logs:', err);
  }
}

function escapeHtml(str) {
  var div = document.createElement('div');
  div.textContent = str;
  return div.innerHTML;
}

function escapeHtmlAttr(str) {
  return String(str).replace(/&/g, '&amp;').replace(/"/g, '&quot;').replace(/'/g, '&#39;');
}

function formatTimestamp(value) {
  if (!value) return 'Never';
  var date = new Date(value);
  if (isNaN(date.getTime())) return 'Never';
  return date.toLocaleString();
}

// --- Pairing ---
let _relayRegistered = false;

async function loadPairing() {
  try {
    const [pin, device, ip, relayState] = await Promise.all([
      invoke('get_pairing_pin'),
      invoke('get_paired_device'),
      invoke('get_local_ip').catch(() => 'Unknown'),
      invoke('get_relay_state'),
    ]);

    const pairingPin = document.getElementById('pairing-pin');
    if (pairingPin) pairingPin.textContent = pin;
    const desktopIp = document.getElementById('desktop-ip');
    if (desktopIp) desktopIp.textContent = ip || 'Unknown';

    const roomCode = document.getElementById('room-code');
    if (relayState.roomCode) {
      if (roomCode) roomCode.textContent = relayState.roomCode;
      _relayRegistered = true;
    } else if (!_relayRegistered) {
      registerWithRelay();
    }

    const pairingStatus = document.getElementById('pairing-status');
    const pairingDot = document.getElementById('pairing-status-dot');
    const pairedRow = document.getElementById('paired-device-row');
    const pairedId = document.getElementById('paired-device-id');
    const unpairedBtn = document.getElementById('btn-unpair');
    const refreshPin = document.getElementById('btn-refresh-pin');
    const refreshCode = document.getElementById('btn-refresh-code');
    const pairingBox = document.getElementById('online-pairing-box');

    if (device) {
      if (pairingStatus) pairingStatus.textContent = 'Paired';
      if (pairingDot) pairingDot.className = 'status-dot connected';
      if (pairedRow) pairedRow.style.display = '';
      if (pairedId) pairedId.textContent = summarizeDeviceId(device);
      if (unpairedBtn) unpairedBtn.style.display = '';
      if (refreshPin) refreshPin.style.display = 'none';
      if (refreshCode) refreshCode.style.display = 'none';
      if (pairingBox) pairingBox.style.borderColor = 'var(--success)';
    } else {
      if (pairingStatus) pairingStatus.textContent = relayState.registered ? 'Waiting for phone' : 'Preparing link...';
      if (pairingDot) pairingDot.className = 'status-dot disconnected';
      if (pairedRow) pairedRow.style.display = 'none';
      if (unpairedBtn) unpairedBtn.style.display = 'none';
      if (refreshPin) refreshPin.style.display = '';
      if (refreshCode) refreshCode.style.display = '';
      if (pairingBox) pairingBox.style.borderColor = 'var(--accent)';
    }
  } catch (err) {
    console.error('Failed to load pairing:', err);
  }
}

function summarizeDeviceId(device) {
  const value = device && (device.user_id || device.device_id || device.id || device.userId);
  if (!value) return '--';
  return value.length > 16 ? value.substring(0, 16) + '...' : value;
}

async function registerWithRelay() {
  try {
    const code = await invoke('register_relay');
    const roomCodeEl = document.getElementById('room-code');
    if (roomCodeEl) roomCodeEl.textContent = code;
    const pairingStatus = document.getElementById('pairing-status');
    if (pairingStatus) pairingStatus.textContent = 'Waiting for device';
    showToast('Room code: ' + code, 'info');
  } catch (err) {
    console.error('Failed to register with relay:', err);
    const roomCodeEl = document.getElementById('room-code');
    if (roomCodeEl) roomCodeEl.textContent = 'OFFLINE';
  }
}

async function refreshRoomCode(btn) {
  setLoading(btn, true);
  try {
    const code = await invoke('register_relay');
    const roomCodeEl = document.getElementById('room-code');
    if (roomCodeEl) roomCodeEl.textContent = code;
    showToast('New room code: ' + code, 'info');
  } catch (err) {
    showToast('Failed to refresh code: ' + err, 'error');
  } finally {
    setLoading(btn, false);
  }
}

async function refreshPin(btn) {
  setLoading(btn, true);
  try {
    await invoke('regenerate_pin');
    await loadPairing();
    showToast('New PIN generated', 'info');
  } catch (err) {
    showToast('Failed to refresh PIN: ' + err, 'error');
  } finally {
    setLoading(btn, false);
  }
}

async function unpairDevice(btn) {
  if (!confirm('Unpair the connected mobile device?')) return;
  setLoading(btn, true);
  try {
    await invoke('unpair_device');
    await loadPairing();
    showToast('Device unpaired', 'info');
  } catch (err) {
    showToast('Failed to unpair: ' + err, 'error');
  } finally {
    setLoading(btn, false);
  }
}

// --- Account Linking UI ---
function displayQRCode(containerId, text) {
  const container = document.getElementById(containerId);
  container.innerHTML = '';

  const img = document.createElement('img');
  img.alt = 'QR Code';
  img.style.width = '200px';
  img.style.height = '200px';
  img.style.borderRadius = '8px';
  img.style.imageRendering = 'pixelated';
  img.src = 'https://api.qrserver.com/v1/create-qr-code/?size=200x200&data=' + encodeURIComponent(text);

  img.onerror = function() {
    container.innerHTML = '<div style="text-align:center;padding:20px;color:var(--accent);font-family:monospace;word-break:break-all">'
      + escapeHtml(text) + '</div>';
  };

  container.appendChild(img);
}

async function openMobileModal() {
  const modal = document.getElementById('mobile-modal');
  const qrContainer = document.getElementById('mobile-qr-code');
  const codeDisplay = document.getElementById('mobile-manual-code');
  const countdownEl = document.getElementById('mobile-countdown');
  const statusEl = document.getElementById('mobile-status');
  const errorEl = document.getElementById('mobile-error');
  const infoEl = document.getElementById('mobile-desktop-info');
  const regenBtn = document.getElementById('btn-generate-new-code');
  const cancelBtn = document.getElementById('btn-cancel-mobile');
  const localOnlyBtn = document.getElementById('btn-local-only');

  modal.style.display = 'flex';
  modal.classList.add('active');
  if (qrContainer) qrContainer.innerHTML = '<div class="qr-placeholder" style="padding:40px;color:var(--text-muted)">Creating connection...</div>';
  if (codeDisplay) codeDisplay.textContent = '------';
  if (countdownEl) countdownEl.textContent = 'Expires in 5:00';
  if (statusEl) { statusEl.style.display = 'none'; statusEl.textContent = ''; }
  if (errorEl) { errorEl.style.display = 'none'; errorEl.textContent = ''; }
  if (regenBtn) regenBtn.style.display = 'none';
  if (cancelBtn) cancelBtn.style.display = '';
  if (localOnlyBtn) localOnlyBtn.style.display = 'none';

  // Load desktop info
  try {
    const info = await apiRequest('/api/desktop/info', { method: 'GET' });
    const osName = { darwin: 'macOS', linux: 'Linux', win32: 'Windows' }[info.platform] || info.platform;
    if (infoEl) infoEl.innerHTML = '<div class="link-desktop-detail"><span class="link-detail-label">This computer:</span><span class="link-detail-value">' + escapeHtml(info.hostname) + '</span></div><div class="link-desktop-detail"><span class="link-detail-value" style="font-size:12px;color:var(--text-muted)">' + escapeHtml(osName) + ' \u00B7 DeckPilot Desktop ' + escapeHtml(info.version) + '</span></div>';
  } catch (_) {}

  // Clean up any previous polling
  if (mobilePollInterval) {
    clearInterval(mobilePollInterval);
    mobilePollInterval = null;
  }

  // Check if we already have an active request
  if (mobileRequestId) {
    try { await cancelAccountLink(); } catch (_) {}
    mobileRequestId = null;
  }

  // Show loading on the setup button
  const connectBtn = document.getElementById('btn-connect-mobile');
  if (connectBtn) {
    connectBtn.disabled = true;
    connectBtn.textContent = 'Creating connection...';
  }

  try {
    const result = await startAccountLink();
    mobileRequestId = result.pairingRequestId || result.requestId || null;
    const linkUrl = result.qrPayload || '';
    const linkCode = result.manualCode || result.code || '';

    if (linkUrl) {
      displayQRCode('mobile-qr-code', linkUrl);
    }

    if (linkCode && codeDisplay) {
      codeDisplay.textContent = linkCode;
    }

    if (statusEl) {
      statusEl.style.display = '';
      statusEl.textContent = 'Waiting for phone to scan...';
    }
    if (regenBtn) regenBtn.style.display = '';

    // Update setup button to show waiting state
    if (connectBtn) {
      connectBtn.textContent = 'Waiting for phone...';
    }

    // Start countdown
    const expiresAt = result.expires_at || result.expiresAt || null;
    let countdownInterval = null;

    function updateCountdown() {
      if (!expiresAt) {
        if (countdownEl) countdownEl.textContent = 'Expires in --:--';
        return;
      }
      const remaining = Math.max(0, Math.floor((new Date(expiresAt).getTime() - Date.now()) / 1000));
      const mins = Math.floor(remaining / 60);
      const secs = remaining % 60;
      if (countdownEl) countdownEl.textContent = 'Expires in ' + mins + ':' + String(secs).padStart(2, '0');
      if (remaining <= 0) {
        if (countdownEl) countdownEl.textContent = 'Code expired';
        if (statusEl) { statusEl.textContent = 'Code has expired. Generate a new one.'; }
        if (regenBtn) regenBtn.style.display = '';
        if (connectBtn) { connectBtn.textContent = 'Link this computer'; connectBtn.disabled = false; }
        if (countdownInterval) clearInterval(countdownInterval);
      }
    }

    updateCountdown();
    countdownInterval = setInterval(updateCountdown, 1000);

    // Poll for approval - max 10 minutes (200 polls at 3s)
    var pollAttempts = 0;
    var maxPollAttempts = 200;
    mobilePollInterval = setInterval(async function() {
      pollAttempts++;
      try {
        const pollResult = await pollAccountLinkStatus();
        if (pollResult && (pollResult.linked || pollResult.status === 'linked' || pollResult.status === 'completed')) {
          clearInterval(mobilePollInterval);
          mobilePollInterval = null;
          if (countdownInterval) clearInterval(countdownInterval);
          if (statusEl) { statusEl.textContent = 'Account linked!'; statusEl.style.color = 'var(--success)'; }
          if (connectBtn) { connectBtn.textContent = 'Linked'; connectBtn.disabled = false; }
          setTimeout(function() {
            closeMobileModal();
            refreshCurrentPage();
          }, 2000);
          return;
        }
        if (pollResult && (pollResult.status === 'expired' || pollResult.status === 'error')) {
          clearInterval(mobilePollInterval);
          mobilePollInterval = null;
          if (countdownInterval) clearInterval(countdownInterval);
          if (statusEl) { statusEl.textContent = 'Code expired. Generate a new one.'; }
          if (regenBtn) regenBtn.style.display = '';
          if (connectBtn) { connectBtn.textContent = 'Link with Mobile App'; connectBtn.disabled = false; }
          return;
        }
      } catch (_) {}
      if (pollAttempts >= maxPollAttempts) {
        clearInterval(mobilePollInterval);
        mobilePollInterval = null;
        if (countdownInterval) clearInterval(countdownInterval);
        if (statusEl) { statusEl.textContent = 'Linking timed out. Generate a new code.'; }
        if (regenBtn) regenBtn.style.display = '';
        if (connectBtn) { connectBtn.textContent = 'Link with Mobile App'; connectBtn.disabled = false; }
      }
    }, 3000);

    // Show local-only option for users who want to skip account
    if (localOnlyBtn) localOnlyBtn.style.display = '';

  } catch (err) {
    if (statusEl) { statusEl.style.display = ''; statusEl.textContent = 'Failed to start'; }
    if (errorEl) { errorEl.style.display = ''; errorEl.textContent = err.message; }
    if (connectBtn) { connectBtn.textContent = 'Link this computer'; connectBtn.disabled = false; }
    console.error('Mobile connect failed:', err);
  }
}

async function openBrowserSignIn() {
  try {
    const url = window.location.origin + '/api/account/auth-url';
    window.open(url, '_blank');
  } catch (_) {
    window.open('https://deckpilot-relay.solitary-credit-34b2.workers.dev/auth/login', '_blank');
  }
}

async function closeMobileModal() {
  if (mobilePollInterval) {
    clearInterval(mobilePollInterval);
    mobilePollInterval = null;
  }
  if (mobileRequestId) {
    try { await cancelAccountLink(); } catch (_) {}
    mobileRequestId = null;
  }
  const modal = document.getElementById('mobile-modal');
  if (modal) { modal.style.display = 'none'; modal.classList.remove('active'); }
  const connectBtn = document.getElementById('btn-connect-mobile');
  if (connectBtn) { connectBtn.textContent = 'Link this computer'; connectBtn.disabled = false; }
}

async function openLocalPairingFallback() {
  closeMobileModal();
  
  const modal = document.getElementById('local-fallback-modal');
  modal.style.display = 'flex';
  modal.classList.add('active');
  
  const statusEl = document.getElementById('fallback-status');
  const errorEl = document.getElementById('fallback-error');
  if (statusEl) { statusEl.style.display = 'none'; }
  if (errorEl) { errorEl.style.display = 'none'; }
  
  try {
    const [pinResult, ipResult] = await Promise.all([
      invoke('get_pairing_pin').catch(() => null),
      invoke('get_local_ip').catch(() => 'Unknown'),
    ]);
    document.getElementById('fallback-local-pin').textContent = pinResult || '------';
    document.getElementById('fallback-local-ip').textContent = ipResult || 'Unknown';
  } catch (_) {
    document.getElementById('fallback-local-pin').textContent = '------';
    document.getElementById('fallback-local-ip').textContent = 'Unknown';
  }
}

function closeLocalFallback() {
  document.getElementById('local-fallback-modal').style.display = 'none';
  refreshCurrentPage();
}

async function retryLocalPairing(btn) {
  setLoading(btn, true);
  const statusEl = document.getElementById('fallback-status');
  const errorEl = document.getElementById('fallback-error');
  if (statusEl) { statusEl.style.display = ''; statusEl.textContent = 'Retrying local connection...'; }
  if (errorEl) { errorEl.style.display = 'none'; }
  
  try {
    await invoke('register_relay');
    if (statusEl) { statusEl.textContent = 'Local connection ready. Open DeckPilot on your phone to complete pairing.'; statusEl.style.color = 'var(--success)'; }
    setTimeout(function() { closeLocalFallback(); }, 3000);
  } catch (err) {
    if (errorEl) { errorEl.style.display = ''; errorEl.textContent = err.message; }
  } finally {
    setLoading(btn, false);
  }
}

async function updateAccountSection() {
  try {
    const status = await getAccountStatus();
    if (status && status.linked) {
      if (latestAppState) latestAppState.accountEmail = status.email;
    } else {
      if (latestAppState) latestAppState.accountEmail = null;
    }
  } catch (_) {}
}

async function updateStatusArea() {
  try {
    const info = await apiRequest('/api/desktop/info', { method: 'GET' }).catch(() => null);
    if (info) {
      const versionEl = document.querySelector('.sidebar-agent-version');
      if (versionEl) versionEl.textContent = 'DeckPilot Desktop ' + info.version;
    }
  } catch (_) {}
}

async function openPhoneModal() {
  const modal = document.getElementById('phone-modal');
  modal.style.display = 'flex';
  modal.classList.add('active');
  
  try {
    const [pinResult, deviceResult, ipResult] = await Promise.all([
      invoke('get_pairing_pin').catch(() => null),
      invoke('get_paired_device').catch(() => null),
      invoke('get_local_ip').catch(() => 'Unknown'),
    ]);
    
    const code = latestAppState && latestAppState.relay && latestAppState.relay.roomCode ? latestAppState.relay.roomCode : (deviceResult ? '------' : '------');
    
    document.getElementById('phone-code').textContent = code || '------';
    document.getElementById('phone-pin').textContent = pinResult || '------';
    document.getElementById('phone-ip').textContent = ipResult || 'Unknown';
  } catch (_) {
    document.getElementById('phone-code').textContent = '------';
    document.getElementById('phone-pin').textContent = '------';
    document.getElementById('phone-ip').textContent = 'Unknown';
  }
}

function closePhoneModal() {
  document.getElementById('phone-modal').style.display = 'none';
}

async function generatePhoneCodes(btn) {
  setLoading(btn, true);
  try {
    await invoke('regenerate_pin');
    await invoke('register_relay');
    await openPhoneModal();
    showToast('New codes generated', 'info');
  } catch (err) {
    showToast('Failed to generate codes: ' + err, 'error');
  } finally {
    setLoading(btn, false);
  }
}

async function openObsModal() {
  const modal = document.getElementById('obs-modal');
  modal.style.display = 'flex';
  modal.classList.add('active');
  
  const resultEl = document.getElementById('obs-test-result');
  if (resultEl) { resultEl.style.display = 'none'; resultEl.textContent = ''; }
  
  if (latestAppState && latestAppState.config) {
    const c = latestAppState.config;
    document.getElementById('obs-host').value = c.obs_host || '127.0.0.1';
    document.getElementById('obs-port').value = c.obs_port || 4455;
    document.getElementById('obs-password').value = c.obs_password || '';
  }
}

function closeObsModal() {
  document.getElementById('obs-modal').style.display = 'none';
}

async function testObsConnection(btn) {
  setLoading(btn, true);
  const resultEl = document.getElementById('obs-test-result');
  resultEl.style.display = '';
  resultEl.textContent = 'Testing...';
  resultEl.className = 'obs-test-result';
  
  const host = document.getElementById('obs-host').value;
  const port = parseInt(document.getElementById('obs-port').value) || 4455;
  const password = document.getElementById('obs-password').value;
  
  try {
    await invoke('test_connection', { host, port, password });
    resultEl.textContent = 'Connected successfully';
    resultEl.className = 'obs-test-result obs-test-success';
  } catch (err) {
    resultEl.textContent = 'Unable to connect to OBS. Check that OBS WebSocket is enabled and the password is correct.';
    resultEl.className = 'obs-test-result obs-test-error';
  } finally {
    setLoading(btn, false);
  }
}

async function saveObsConnection(btn) {
  setLoading(btn, true);
  try {
    const config = {
      obs_host: document.getElementById('obs-host').value,
      obs_port: parseInt(document.getElementById('obs-port').value) || 4455,
      obs_password: document.getElementById('obs-password').value,
    };
    await invoke('save_config', { config });
    await invoke('connect_obs', config);
    showToast('OBS connected', 'success');
    closeObsModal();
    refreshCurrentPage();
  } catch (err) {
    showToast('Failed to connect: ' + err, 'error');
  } finally {
    setLoading(btn, false);
  }
}

async function syncNow(btn) {
  setLoading(btn, true);
  try {
    await syncWorkspaceFromCloud();
    showToast('Workspace synced', 'success');
    refreshCurrentPage();
  } catch (err) {
    showToast('Sync failed: ' + err, 'error');
  } finally {
    setLoading(btn, false);
  }
}

async function updateActivityCard() {
  try {
    const activity = await getAccountActivity();
    const container = document.getElementById('activity-list');
    const empty = document.getElementById('activity-empty');
    if (!container) return;

    const items = Array.isArray(activity) ? activity : (activity && activity.items ? activity.items : []);

    if (!items.length) {
      if (container) container.style.display = 'none';
      if (empty) empty.style.display = '';
      return;
    }

    if (empty) empty.style.display = 'none';
    if (container) container.style.display = '';

    container.innerHTML = items.slice(0, 5).map(function(item) {
      const time = item.timestamp ? formatTimestamp(item.timestamp) : '';
      const icons = { account: 'account', sync: 'sync', pairing: 'pairing', obs: 'obs', consent: 'account', error: 'error' };
      const iconClass = icons[item.type] || 'account';
      const desc = item.message || item.description || item.action || item.event || '';
      return '<div class="activity-entry"><span class="activity-icon ' + iconClass + '">&#9679;</span><div class="activity-content"><div class="activity-message">' + escapeHtml(desc) + '</div><div class="activity-time">' + escapeHtml(time) + '</div></div></div>';
    }).join('');
  } catch (err) {
    console.error('Failed to load activity:', err);
  }
}

// --- Auto-refresh ---
function startAutoRefresh() {
  if (refreshInterval) clearInterval(refreshInterval);
  refreshInterval = setInterval(function() {
    // Poll mobile request if modal is open
    if (mobilePollInterval) {
      // already handled by the interval in openMobileModal
    }
    if (currentPage === 'dashboard') {
      loadDashboard();
      pollRelayForPairing();
    } else if (currentPage === 'automations') {
      loadAutomations();
    } else if (currentPage === 'logs') {
      loadLogs();
    }
    updateAccountSection();
    updateStatusArea();
  }, 2000);
}

async function pollRelayForPairing() {
  try {
    const paired = await invoke('poll_relay');
    if (paired) {
      loadPairing();
    }
  } catch (_) {}
}

// --- First-Run Consent ---
async function checkConsent() {
  try {
    const result = await apiRequest('/api/consent/status', { method: 'GET' });
    if (!result.accepted) {
      const modal = document.getElementById('consent-modal');
      if (modal) { modal.style.display = 'flex'; modal.classList.add('active'); }
      return false;
    }
    return true;
  } catch (_) {
    return true;
  }
}

async function acceptConsent(btn) {
  setLoading(btn, true);
  try {
    await apiRequest('/api/consent/accept', { method: 'POST' });
    const modal = document.getElementById('consent-modal');
    if (modal) { modal.style.display = 'none'; modal.classList.remove('active'); }
    showToast('Consent accepted. Desktop agent is now active.', 'success');
    checkNotificationPermission();
  } catch (err) {
    showToast('Failed to save consent: ' + err, 'error');
  } finally {
    setLoading(btn, false);
  }
}

Object.assign(window, {
  acceptConsent,
  checkForUpdate,
  clearLogs,
  closeLocalFallback,
  closeMobileModal,
  closeObsModal,
  closePhoneModal,
  generatePhoneCodes,
  handleNav,
  installUpdate,
  loadLogs,
  navigateTo,
  openBrowserSignIn,
  openMobileModal,
  openObsModal,
  openPhoneModal,
  resetSettings,
  retryLocalPairing,
  saveObsConnection,
  saveSettings,
  setNotificationPermission,
  syncNow,
  testDesktopNotification,
  testConnection,
  testObsConnection,
  toggleAutomationRule,
  unlinkAccount,
  updateNotificationStatus,
});

// --- Init ---
document.addEventListener('DOMContentLoaded', function() {
  if (localStorage.getItem('sidebar-collapsed') === 'true') toggleSidebar();
  checkConsent().then(function() {
    checkNotificationPermission();
  });
  loadDashboard();
  loadPairing();
  startAutoRefresh();
});
