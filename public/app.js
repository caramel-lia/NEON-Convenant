'use strict';

(() => {
  const $ = (id) => document.getElementById(id);
  const app = { mode: 'create', role: 'netrunner', approach: 'hack', code: null, token: null, state: null, busy: false, quickBusy: false, filter: 'all', sceneKey: null, eventKey: null, mapKey: null, mapMode: 'move', terrain: 'wall', toastTimer: null };
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
    app.sceneKey = null; app.eventKey = null; app.mapKey = null; app.mapMode = 'move'; app.busy = false; app.quickBusy = false;
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

  const TERRAIN_SYMBOL = { floor: '·', wall: '▥', cover: '▤', objective: '◇', hazard: '⚠' };

  function mapCoords(x, y) { return `${String.fromCharCode(65 + x)}${y + 1}`; }

  function drawMap(state) {
    const map = state.map;
    if (!map) return;
    const me = state.players.find((p) => p.id === state.me);
    if (!me?.host && app.mapMode === 'paint') app.mapMode = 'move';
    const signature = `${map.location}/${map.revision}/${app.mapMode}/${app.terrain}/${me?.host}`;
    $('map-edit').hidden = !me?.host;
    $('map-reset').hidden = !me?.host;
    $('map-palette').hidden = !me?.host || app.mapMode !== 'paint';
    $('map-move').classList.toggle('active', app.mapMode === 'move');
    $('map-edit').classList.toggle('active', app.mapMode === 'paint');
    $('map-location').textContent = `SECTOR // ${map.location}`;
    $('map-hint').textContent = app.mapMode === 'paint'
      ? 'HOST EDITOR // Choose terrain above, then click a cell. Crew tokens cannot be enclosed by a new wall.'
      : 'CLICK A TILE TO MOVE // 4 orthogonal squares per click. Walls and occupied cells block the route. Movement is a visual aid, not a narrative action.';
    document.querySelectorAll('[data-terrain]').forEach((button) => button.classList.toggle('active', button.dataset.terrain === app.terrain));
    if (app.mapKey === signature) return;
    app.mapKey = signature;
    const holder = $('map-grid');
    const frag = document.createDocumentFragment();
    frag.append(el('span', 'map-axis', '◤'));
    for (let x = 0; x < map.width; x++) frag.append(el('span', 'map-axis', String.fromCharCode(65 + x)));
    for (let y = 0; y < map.height; y++) {
      frag.append(el('span', 'map-axis', String(y + 1).padStart(2, '0')));
      for (let x = 0; x < map.width; x++) {
        const terrain = map.tiles[y * map.width + x] || 'floor';
        const idx = state.players.findIndex((p) => {
          const pos = map.positions[p.id];
          return pos && pos.x === x && pos.y === y;
        });
        const occupiedBy = idx >= 0 ? state.players[idx] : null;
        const cell = el('button', `map-cell terrain-${terrain}${idx >= 0 ? ` token-${idx + 1}` : ''}${occupiedBy?.id === state.me ? ' is-me' : ''}`);
        cell.type = 'button';
        cell.dataset.x = String(x);
        cell.dataset.y = String(y);
        const coordinate = mapCoords(x, y);
        const detail = `${coordinate} · ${terrain.toUpperCase()}${occupiedBy ? ` · ${occupiedBy.name}` : ''}`;
        cell.title = detail;
        cell.setAttribute('aria-label', detail);
        cell.append(el('span', 'map-glyph', TERRAIN_SYMBOL[terrain] || '·'));
        if (occupiedBy) cell.append(el('span', 'map-token', String(idx + 1)));
        frag.append(cell);
      }
    }
    holder.replaceChildren(frag);
    const roster = document.createDocumentFragment();
    state.players.forEach((player, n) => {
      const entry = el('span', 'map-party-member');
      entry.append(el('span', `map-party-marker token-${n + 1}`, String(n + 1)),
        el('span', '', `${player.name}${player.id === state.me ? ' [YOU]' : ''}`));
      roster.append(entry);
    });
    $('map-party').replaceChildren(roster);
  }

  function drawLastRoll(state) {
    const last = [...state.events].reverse().find((event) => event.kind === 'roll' && event.manual);
    $('last-roll').textContent = last
      ? `LAST ROLL // ${last.count || last.dice.length}D${last.sides || '?'}: [${last.dice.join(', ')}] ${last.modifier > 0 ? '+' : ''}${last.modifier ?? 0} = ${last.total}`
      : 'NO MANUAL ROLLS LOGGED';
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
    // Keep the shared map visible in the lobby, before any Gemini call.
    // Move the same DOM node; this preserves grid listeners and token state.
    const gridPanel = $('tactical-map');
    const anchor = state?.status === 'active' ? $('scene-grid-anchor') : $('lobby-grid-anchor');
    if (gridPanel && anchor && gridPanel.parentElement !== anchor) anchor.append(gridPanel);
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
    $('map-grid').querySelectorAll('.map-cell').forEach((cell) => { cell.disabled = !state || !!state.pending || app.quickBusy; });
    $('map-move').disabled = !state || !!state.pending || app.quickBusy;
    $('map-edit').disabled = !state || !!state.pending || app.quickBusy;
    $('map-reset').disabled = !state || !!state.pending || app.quickBusy;
    document.querySelectorAll('[data-terrain]').forEach((button) => { button.disabled = !state || !!state.pending || app.quickBusy; });
    $('roll-dice').disabled = !state || app.quickBusy;
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
    drawRoster(state); drawStats(state); drawScene(state); drawMap(state); drawEvents(state); drawLastRoll(state); renderControls();
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
    if (route === 'start') { $('gm-error').hidden = true; $('gm-error').textContent = ''; }
    try {
      const result = await api(`/api/rooms/${app.code}/${route}`, 'POST', payload);
      updateState(result);
      if (route === 'action') toast('ACTION REGISTERED // ROLL COMMITTED');
    } catch (err) {
      toast(err.message, true);
      if (route === 'start') {
        $('gm-error').textContent = `GM BOOT FAILED // ${err.message} // You can still use the grid and manual dice. Set DEMO_MODE=true in .env to play without Gemini.`;
        $('gm-error').hidden = false;
      }
      await refresh();
    } finally { setBusy(false); }
  }

  async function quickOperation(route, payload = {}) {
    if (app.quickBusy || !app.code) return false;
    app.quickBusy = true;
    renderControls();
    try {
      const state = await api(`/api/rooms/${app.code}/${route}`, 'POST', payload);
      updateState(state);
      return true;
    } catch (error) {
      toast(error.message, true);
      await refresh();
      return false;
    } finally {
      app.quickBusy = false;
      renderControls();
    }
  }

  function selectMapMode(mode) {
    const me = app.state?.players.find((player) => player.id === app.state.me);
    if (mode === 'paint' && !me?.host) return;
    app.mapMode = mode;
    app.mapKey = null;
    if (app.state) drawMap(app.state);
    renderControls();
  }

  async function gridClick(event) {
    const button = event.target.closest('button.map-cell');
    if (!button || !app.state || app.state.pending) return;
    const x = Number(button.dataset.x), y = Number(button.dataset.y);
    if (app.mapMode === 'paint') {
      await quickOperation('map/paint', { x, y, terrain: app.terrain });
    } else {
      await quickOperation('map/move', { x, y });
    }
  }

  async function manualRoll() {
    if (!app.state) return;
    const payload = { count: Number($('roll-count').value), sides: Number($('roll-sides').value),
      modifier: Number($('roll-mod').value), reason: $('roll-reason').value.trim() };
    const ok = await quickOperation('roll', payload);
    if (ok) $('roll-reason').value = '';
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

  async function checkHealth() {
    try {
      const data = await api('/health');
      const mode = data.gm_mode;
      $('server-health').textContent = mode === 'demo' ? '● DEMO GM ONLINE // NO API KEY REQUIRED'
        : mode === 'gemini' ? '● GEMINI KEY CONFIGURED // LIVE CALL NOT VERIFIED'
        : '⚠ GEMINI KEY MISSING // SET GEMINI_API_KEY OR ENABLE DEMO_MODE';
      $('server-health').classList.toggle('needs-setup', mode === 'unconfigured');
    } catch (err) {
      $('server-health').textContent = '⚠ BACKEND UNREACHABLE // START SINATRA SERVER';
      $('server-health').classList.add('needs-setup');
    }
  }

  function init() {
    checkHealth();
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
    $('map-grid').addEventListener('click', gridClick);
    $('map-move').addEventListener('click', () => selectMapMode('move'));
    $('map-edit').addEventListener('click', () => selectMapMode('paint'));
    $('map-reset').addEventListener('click', () => {
      if (window.confirm('Regenerate this sector grid? All painted terrain and current token positions will be reset.')) quickOperation('map/reset');
    });
    document.querySelectorAll('[data-terrain]').forEach((button) => button.addEventListener('click', () => {
      app.terrain = button.dataset.terrain;
      app.mapKey = null;
      if (app.state) drawMap(app.state);
    }));
    document.querySelectorAll('[data-preset]').forEach((button) => button.addEventListener('click', () => {
      const [count, sides, mod] = button.dataset.preset.split(',').map(Number);
      $('roll-count').value = String(count);
      $('roll-sides').value = String(sides);
      $('roll-mod').value = String(mod);
    }));
    $('roll-dice').addEventListener('click', manualRoll);
    $('roll-reason').addEventListener('keydown', (event) => {
      if (event.key === 'Enter') { event.preventDefault(); manualRoll(); }
    });
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
