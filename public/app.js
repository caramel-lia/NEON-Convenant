'use strict';

(() => {
  const $ = (id) => document.getElementById(id);
  const app = { mode: 'create', role: 'netrunner', approach: 'hack', code: null, token: null, state: null, busy: false, filter: 'all', sceneKey: null, eventKey: null, toastTimer: null };
  const ROLES = { netrunner: 'NETRUNNER', solo: 'SOLO', ghost: 'GHOST', techie: 'TECHIE', fixer: 'FIXER' };
  const MODE_LABELS = { create: 'INITIALIZE CAMPAIGN', join: 'LINK TO CREW' };

  const el = (tag, cls, text) => {
    const n = document.createElement(tag);
    if (cls) n.className = cls;
    if (text !== undefined) n.textContent = String(text);
    return n;
  };

  function toast(message, error = false) {
    const box = $('toast');
    box.textContent = message;
    box.classList.toggle('error', error);
    box.hidden = false;
    clearTimeout(app.toastTimer);
    app.toastTimer = setTimeout(() => { box.hidden = true; }, 5500);
  }

  async function api(path, method = 'GET', data = null, token = app.token) {
    const headers = { 'Accept': 'application/json' };
    if (token) headers.Authorization = `Bearer ${token}`;
    if (data !== null) headers['Content-Type'] = 'application/json';
    const response = await fetch(path, { method, headers, body: data === null ? undefined : JSON.stringify(data), cache: 'no-store' });
    let payload;
    try { payload = await response.json(); }
    catch { throw new Error(`Server returned HTTP ${response.status} without JSON.`); }
    if (!response.ok) throw new Error(payload.error || `HTTP ${response.status}`);
    return payload;
  }

  function setEntryMode(mode) {
    app.mode = mode;
    $('tab-create').classList.toggle('selected', mode === 'create');
    $('tab-join').classList.toggle('selected', mode === 'join');
    $('tab-create').setAttribute('aria-selected', String(mode === 'create'));
    $('tab-join').setAttribute('aria-selected', String(mode === 'join'));
    $('create-fields').hidden = mode !== 'create';
    $('join-fields').hidden = mode !== 'join';
    $('entry-button').firstElementChild.textContent = MODE_LABELS[mode];
    $('join-code').required = mode === 'join';
  }

  function chooseRole(role) {
    app.role = role;
    document.querySelectorAll('[data-role]').forEach((button) => button.classList.toggle('chosen', button.dataset.role === role));
  }

  function chooseApproach(approach) {
    app.approach = approach;
    document.querySelectorAll('[data-approach]').forEach((button) => button.classList.toggle('active', button.dataset.approach === approach));
  }

  function setBusy(value) {
    app.busy = value;
    $('entry-button').disabled = value;
    renderControls();
  }

  function saveSession(code, token) {
    app.code = code;
    app.token = token;
    localStorage.setItem(`neon:token:${code}`, token);
    localStorage.setItem('neon:lastRoom', code);
    history.replaceState(null, '', `/?room=${encodeURIComponent(code)}`);
  }

  function enterGame() {
    $('landing').hidden = true;
    $('game').hidden = false;
    window.scrollTo(0, 0);
    $('room-code').textContent = app.code;
  }

  function backToEntry() {
    app.code = null; app.token = null; app.state = null;
    app.sceneKey = null; app.eventKey = null; app.busy = false;
    $('landing').hidden = false;
    $('game').hidden = true;
    $('scene-view').hidden = true;
    history.replaceState(null, '', '/');
    renderControls();
  }

  function afterJoin(payload) {
    saveSession(payload.code, payload.token);
    enterGame();
    updateState(payload.state);
    toast(`RELAY CONNECTED // ${payload.code}`);
  }

  async function submitEntry(event) {
    event.preventDefault();
    if (app.busy) return;
    setBusy(true);
    try {
      const data = { name: $('handle').value.trim(), role: app.role };
      const payload = app.mode === 'create'
        ? await api('/api/rooms', 'POST', { ...data, theme: $('theme').value }, null)
        : await api(`/api/rooms/${$('join-code').value.trim().toUpperCase()}/join`, 'POST', data, null);
      afterJoin(payload);
    } catch (error) { toast(error.message, true); }
    finally { setBusy(false); }
  }

  function drawRoster(state) {
    const roster = $('roster-list');
    const frag = document.createDocumentFragment();
    state.players.forEach((player) => {
      const member = el('div', `roster-member${player.id === state.me ? ' me' : ''}`);
      const header = el('div', 'member-line');
      header.append(el('span', 'member-name', `${player.name}${player.host ? ' ✦' : ''}`));
      header.append(el('span', `member-status${player.ready ? ' ready' : ''}`, state.status === 'lobby' ? 'LINKED' : (player.ready ? 'READY' : 'IDLE')));
      member.append(header, el('div', 'member-role', `${ROLES[player.role] || player.role} // Lv.01`));
      const track = el('div', 'hp-track');
      const fill = el('div', 'hp-fill');
      fill.style.width = `${Math.max(0, Math.min(100, (player.hp / player.max_hp) * 100))}%`;
      track.append(fill); member.append(track);
      const footer = el('div', 'hp-caption');
      footer.append(el('span', '', `HP ${player.hp}/${player.max_hp}`), el('span', '', `STRESS ${player.stress}/6`));
      member.append(footer); frag.append(member);
    });
    for (let i = state.players.length; i < state.max_players; i++) frag.append(el('div', 'empty-slot', `+ AVAILABLE SLOT [0${i + 1}]`));
    roster.replaceChildren(frag);
    $('capacity').textContent = `${state.players.length} / ${state.max_players}`;
  }

  function drawStats(state) {
    const player = state.players.find((item) => item.id === state.me);
    if (!player) return;
    const holder = $('my-stats');
    const frag = document.createDocumentFragment();
    const heading = el('div', 'stat-row');
    heading.append(el('span', '', 'ROLE'), el('strong', '', ROLES[player.role] || player.role));
    frag.append(heading);
    const stats = el('div', 'stat-badges');
    [['EDGE', player.edge], ['GHOST', player.ghost], ['TECH', player.tech]].forEach(([label, num]) => {
      const badge = el('div', 'stat-badge');
      badge.append(el('b', '', `+${num}`), el('small', '', label));
      stats.append(badge);
    });
    frag.append(stats);
    [['CREDITS', `₡ ${player.credits}`], ['STRESS', `${player.stress} / 6`]].forEach(([key, value]) => {
      const row = el('div', 'stat-row'); row.append(el('span', '', key), el('strong', '', value)); frag.append(row);
    });
    const gear = el('div', 'gear-list');
    gear.append(el('div', 'field-label', 'LOADOUT'));
    (player.gear || []).forEach((item) => gear.append(el('div', '', `↳ ${item}`)));
    frag.append(gear); holder.replaceChildren(frag);
  }

  function drawScene(state) {
    const scene = state.scene;
    if (!scene) return;
    const key = `${state.round}:${scene.title}:${scene.narration}`;
    if (key === app.sceneKey) return;
    app.sceneKey = key;
    $('scene-title').textContent = scene.title;
    $('scene-objective').textContent = scene.objective;
    const narrative = $('scene-narration');
    narrative.replaceChildren(...scene.narration.split(/\n{2,}/).map((paragraph) => el('p', '', paragraph)));
    const grid = $('suggestions');
    const choices = (scene.choices || []).slice(0, 4).map((choice, index) => {
      const button = el('button', 'suggestion'); button.type = 'button';
      button.append(el('span', '', `[0${index + 1}]`), document.createTextNode(` ${choice}`));
      button.addEventListener('click', () => { $('action-text').value = choice; $('action-text').focus(); });
      return button;
    });
    grid.replaceChildren(...choices);
    $('action-text').value = '';
  }

  function drawEvents(state) {
    const signature = `${app.filter}:` + state.events.map((e) => e.id).join(',');
    if (signature === app.eventKey) return;
    app.eventKey = signature;
    const stream = $('event-stream');
    const atBottom = stream.scrollHeight - stream.scrollTop - stream.clientHeight < 80 || !stream.firstChild;
    const fragment = document.createDocumentFragment();
    state.events.filter((event) => {
      if (app.filter === 'all') return true;
      return event.kind === app.filter;
    }).forEach((event) => {
      const item = el('div', `event event-${event.kind}`);
      const header = el('div', 'event-meta');
      const t = new Date(event.at);
      const time = Number.isNaN(t.getTime()) ? '--:--' : t.toLocaleTimeString([], {hour: '2-digit', minute:'2-digit'});
      header.append(el('span', 'event-type', event.kind.toUpperCase()), el('span', '', time));
      item.append(header, el('div', 'event-body', event.text));
      fragment.append(item);
    });
    stream.replaceChildren(fragment);
    if (atBottom) stream.scrollTop = stream.scrollHeight;
  }

  function renderControls() {
    const state = app.state;
    const player = state?.players.find((p) => p.id === state.me);
    const inLobby = state?.status === 'lobby' || state?.status === 'starting';
    const active = !!state && state.status === 'active';
    const hasAction = !!state?.actions.some((a) => a.player_id === state.me);
    const locked = app.busy || !!state?.pending;
    $('lobby-view').hidden = !inLobby;
    $('scene-view').hidden = !active || !state.scene;
    $('gm-pending').hidden = !state?.pending && !app.busy;
    $('start-game').hidden = !player?.host;
    $('start-game').disabled = locked || state?.status !== 'lobby';
    $('host-instruction').textContent = player?.host ? 'Start anytime. Invite up to four more before booting.' : 'Waiting for the host to initialize the simulation…';
    $('submit-action').disabled = !active || locked || hasAction;
    $('action-text').disabled = !active || locked || hasAction;
    document.querySelectorAll('.approach').forEach((button) => { button.disabled = !active || locked || hasAction; });
    $('ready-state').textContent = locked ? 'GM PROCESSING…' : hasAction ? '✓ ACTION LOCKED' : '● YOUR MOVE';
    $('force-resolve').hidden = !active || !player?.host || state.actions.length === 0 || locked || state.actions.length === state.players.length;
    $('sim-status').textContent = state?.pending ? '◌ GENERATING WORLD…' : active ? '● SIMULATION LIVE' : '● GM STANDBY';
    $('session-indicator').textContent = locked ? '◌ PROCESSING' : '● CONNECTED';
    $('send-chat').disabled = !state || app.busy;
    $('chat-input').disabled = !state || app.busy;
  }

  function updateState(state) {
    app.state = state;
    $('room-code').textContent = state.code;
    $('operation-name').textContent = state.scene?.title || 'AWAITING BOOT SEQUENCE';
    $('sector').textContent = state.scene?.location || 'MERIDIAN-9';
    $('round-number').textContent = String(state.round).padStart(2, '0');
    $('alert-level').textContent = state.scene?.threat || 'UNDETECTED';
    drawRoster(state); drawStats(state); drawScene(state); drawEvents(state); renderControls();
  }

  async function refresh() {
    if (!app.code || !app.token) return;
    try {
      const state = await api(`/api/rooms/${app.code}`);
      // A stale tab's reply must not overwrite a newer active session.
      if (state.code === app.code) updateState(state);
      $('session-indicator').classList.remove('offline');
    } catch (err) {
      $('session-indicator').textContent = '○ LINK LOST';
      if (err.message.includes('session invalid') || err.message.includes('session missing')) {
        toast(err.message, true);
        backToEntry();
      }
    }
  }

  async function operation(route, payload = {}) {
    if (app.busy || !app.code) return;
    setBusy(true);
    try {
      const result = await api(`/api/rooms/${app.code}/${route}`, 'POST', payload);
      updateState(result);
      if (route === 'action') toast('ACTION REGISTERED // ROLL COMMITTED');
    } catch (err) {
      toast(err.message, true);
      await refresh();
    } finally { setBusy(false); }
  }

  async function sendChat() {
    const text = $('chat-input').value.trim();
    if (!text || !app.code) return;
    $('chat-input').value = '';
    try { updateState(await api(`/api/rooms/${app.code}/chat`, 'POST', { text })); }
    catch (err) { $('chat-input').value = text; toast(err.message, true); }
  }

  async function copyInvite() {
    const url = `${location.origin}/?room=${encodeURIComponent(app.code)}`;
    try { await navigator.clipboard.writeText(url); toast('INVITE LINK COPIED TO CLIPBOARD'); }
    catch { window.prompt('COPY THIS CREW INVITE LINK:', url); }
  }

  async function disconnect() {
    if (!app.code) return;
    if (!window.confirm('Disconnect from this crew? Rejoining a running campaign is not supported.')) return;
    const code = app.code;
    try { await api(`/api/rooms/${code}/leave`, 'POST', {}); }
    catch (err) { toast(`Could not leave room: ${err.message}`, true); return; }
    localStorage.removeItem(`neon:token:${code}`);
    localStorage.removeItem('neon:lastRoom');
    backToEntry();
  }

  function init() {
    $('tab-create').addEventListener('click', () => setEntryMode('create'));
    $('tab-join').addEventListener('click', () => setEntryMode('join'));
    $('entry-form').addEventListener('submit', submitEntry);
    document.querySelectorAll('[data-role]').forEach((button) => button.addEventListener('click', () => chooseRole(button.dataset.role)));
    document.querySelectorAll('[data-approach]').forEach((button) => button.addEventListener('click', () => chooseApproach(button.dataset.approach)));
    $('start-game').addEventListener('click', () => operation('start'));
    $('submit-action').addEventListener('click', () => {
      const intent = $('action-text').value.trim();
      if (!intent) { toast('Describe your move before committing.', true); return; }
      operation('action', { approach: app.approach, intent });
    });
    $('action-text').addEventListener('keydown', (event) => {
      if (event.key === 'Enter' && (event.ctrlKey || event.metaKey)) { event.preventDefault(); $('submit-action').click(); }
    });
    $('force-resolve').addEventListener('click', () => {
      if (window.confirm('Advance now? Operatives who have not acted will skip this round.')) operation('resolve');
    });
    document.querySelectorAll('.filter').forEach((button) => button.addEventListener('click', () => {
      app.filter = button.dataset.filter;
      document.querySelectorAll('.filter').forEach((btn) => btn.classList.toggle('active', btn === button));
      app.eventKey = null;
      if (app.state) drawEvents(app.state);
    }));
    $('chat-input').addEventListener('keydown', (event) => { if (event.key === 'Enter') { event.preventDefault(); sendChat(); } });
    $('send-chat').addEventListener('click', sendChat);
    $('copy-room').addEventListener('click', copyInvite);
    $('exit-room').addEventListener('click', disconnect);
    const fromUrl = new URLSearchParams(location.search).get('room')?.trim().toUpperCase();
    const remembered = fromUrl || localStorage.getItem('neon:lastRoom');
    if (remembered && /^[A-HJ-NP-Z2-9]{8}$/.test(remembered)) {
      $('join-code').value = remembered;
      setEntryMode('join');
      const token = localStorage.getItem(`neon:token:${remembered}`);
      if (token) { app.code = remembered; app.token = token; enterGame(); refresh(); }
    }
    setInterval(() => { if (app.code) refresh(); }, 2600);
    const tick = () => { $('footer-clock').textContent = new Date().toLocaleTimeString('en-GB', {hour12:false}); };
    tick(); setInterval(tick, 1000);
    renderControls();
  }
  init();
})();
