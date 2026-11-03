// Launcher: Start and search in one panel (design/graphite/components/Launcher).
// home.html loads this same script in Home mode: the idle state is just the search
// field and recent rows on the backdrop, and the panel never closes.

const $ = (selector) => document.querySelector(selector);

const isHome = document.body.classList.contains('home');
// The palette (Alt+Space) is this same page, compact and results-only.
const isPalette = () => document.body.classList.contains('palette');

let state = { apps: [], pinned: [], recent: [], lastUsed: {}, counts: {}, quickLinks: [], recentItems: [], labels: {}, aliases: {}, user: '', displayName: '', dev: false };
let activeScope = 'All';
let selectedIndex = 0;
let visibleRows = [];
let aliasIndex = new Map();

const scopes = ['All', 'Apps', 'Files', 'Folders', 'Commands'];
const maximumRowsPerGroup = 4;
const maximumRowsPerScope = 40;
const recentRowCount = isHome ? 6 : 4;
const confirmWindowMilliseconds = 3000;

const tagColours = { Dev: 'var(--tag-blue)', Media: 'var(--tag-green)', Games: 'var(--tag-violet)', Social: 'var(--tag-rose)', System: 'var(--tag-teal)' };

const iconPaths = {
  folder: '<path d="M2.5 4.5h4l1.5 1.5h5.5v6.5h-11z"/>',
  file: '<path d="M4 2.5h5.5L12 5v8.5H4z"/><path d="M9.5 2.5V5H12"/>',
  app: '<rect x="2.5" y="2.5" width="4.5" height="4.5" rx="1"/><rect x="9" y="2.5" width="4.5" height="4.5" rx="1"/><rect x="2.5" y="9" width="4.5" height="4.5" rx="1"/><rect x="9" y="9" width="4.5" height="4.5" rx="1"/>',
  command: '<path d="m4 5.5 3 2.5-3 2.5M8.5 11H12"/>',
  settings: '<circle cx="8" cy="8" r="2"/><path d="M8 2v1.5M8 12.5V14M2 8h1.5M12.5 8H14M3.8 3.8l1 1M11.2 11.2l1 1M3.8 12.2l1-1M11.2 4.8l1-1"/>',
  lock: '<rect x="3.5" y="7" width="9" height="6.5" rx="1.5"/><path d="M5.5 7V5.5a2.5 2.5 0 0 1 5 0V7"/>',
  signout: '<path d="M9.5 3H4v10h5.5M7 8h6.5M11 5.5 13.5 8 11 10.5"/>',
  sleep: '<path d="M12.5 9.5A5 5 0 0 1 6.5 3.5a5 5 0 1 0 6 6z"/>',
  restart: '<path d="M3 8a5 5 0 1 0 1.5-3.5M3 2.5v2.5h2.5"/>',
  power: '<path d="M8 2.5V8M5 4.5a5 5 0 1 0 6 0"/>',
  display: '<rect x="2" y="3" width="12" height="8" rx="1.5"/><path d="M6 13.5h4M8 11v2.5"/>',
  sound: '<path d="M3 6h2.5L9 3v10L5.5 10H3zM11.5 6a3 3 0 0 1 0 4"/>',
  wifi: '<path d="M2 6.5a9 9 0 0 1 12 0M4 9a6 6 0 0 1 8 0M6 11.3a3 3 0 0 1 4 0"/>',
  bluetooth: '<path d="m5 5 6 6-3 2.5v-11L11 5l-6 6"/>',
  activity: '<path d="M2 8h3l2-4 2 8 2-4h3"/>',
  moon: '<path d="M12.5 9.5A5 5 0 0 1 6.5 3.5a5 5 0 1 0 6 6z"/>',
  web: '<circle cx="8" cy="8" r="5.5"/><path d="M2.5 8h11M8 2.5c1.6 1.6 2.3 3.4 2.3 5.5S9.6 11.9 8 13.5C6.4 11.9 5.7 10.1 5.7 8S6.4 4.1 8 2.5z"/>',
};

const commands = [
  { name: 'Settings', alias: 'set', glyph: 'settings', keys: ['Win', 'I'] },
  { name: 'Display settings', alias: 'disp', glyph: 'display', keys: [] },
  { name: 'Sound settings', alias: 'snd', glyph: 'sound', keys: [] },
  { name: 'Wi-Fi and network', alias: 'net', glyph: 'wifi', keys: [] },
  { name: 'Bluetooth and devices', alias: 'bt', glyph: 'bluetooth', keys: [] },
  { name: 'Task Manager', alias: 'tm', glyph: 'activity', keys: ['Ctrl', 'Shift', 'Esc'] },
  { name: 'Toggle dark mode', alias: 'dark', glyph: 'moon', keys: [] },
  { name: 'Graphite settings', alias: 'gs', glyph: 'settings', keys: [] },
  { name: 'Lock', alias: 'lock', glyph: 'lock', keys: ['Win', 'L'] },
  { name: 'Sleep', alias: 'sleep', glyph: 'sleep', keys: [] },
  { name: 'Sign out', alias: 'out', glyph: 'signout', keys: [] },
  { name: 'Restart', alias: 'reboot', glyph: 'restart', keys: [] },
  { name: 'Shut down', alias: 'off', glyph: 'power', keys: [] },
];

// Destructive power actions need a second press within three seconds, so a stray click never restarts the machine.
const powerActions = [
  { name: 'Lock', action: 'lock', glyph: 'lock', keys: ['Win', 'L'], needsConfirm: false },
  { name: 'Sign out', action: 'signout', glyph: 'signout', keys: [], needsConfirm: true },
  { name: 'Sleep', action: 'sleep', glyph: 'sleep', keys: [], needsConfirm: false },
  { name: 'Restart', action: 'restart', glyph: 'restart', keys: [], needsConfirm: true },
  { name: 'Shut down', action: 'shutdown', glyph: 'power', keys: [], needsConfirm: true },
];

const root = $('#root');
const launcher = $('#launcher');
const queryInput = $('#query');
const bodyElement = $('#body');

const icon = (name) => `<svg class="i" viewBox="0 0 16 16">${iconPaths[name]}</svg>`;
const key = (label) => `<span class="key">${label}</span>`;

function escapeHtml(text) {
  return String(text).replace(/[&<>"]/g, (character) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' })[character]);
}

function fileUrl(filePath) {
  // encodeURI keeps the drive-letter colon intact (C%3A trips some Chromium paths)
  return 'file:///' + encodeURI(filePath.replace(/\\/g, '/'));
}

function restartAnimation(element, className) {
  element.classList.remove(className);
  void element.offsetWidth;
  element.classList.add(className);
}

function timeAgo(timestamp) {
  if (!timestamp) return '';
  const minutes = Math.round((Date.now() - timestamp) / 60000);
  if (minutes < 1) return 'now';
  if (minutes < 60) return minutes + 'm';
  const hours = Math.round(minutes / 60);
  if (hours < 24) return hours + 'h';
  const days = Math.round(hours / 24);
  return days === 1 ? 'Yesterday' : days < 7 ? days + 'd' : new Date(timestamp).toLocaleDateString('en-GB', { day: 'numeric', month: 'short' });
}

// ---- identifiers ----

// Two or three capitals from the name: "Prime Video" -> PV, "AppData" -> AD, "Steam" -> ST.
function baseAlias(name) {
  const words = name.replace(/([a-z])([A-Z])/g, '$1 $2').split(/[^A-Za-z0-9]+/).filter(Boolean);
  if (words.length >= 2) return words.slice(0, 3).map((word) => word[0]).join('').toUpperCase();
  return (words[0] || name).slice(0, 2).toUpperCase();
}

function buildAliases() {
  aliasIndex = new Map();
  const taken = new Set(commands.map((command) => command.alias.toUpperCase()));
  // A taken alias tries the first letter with each later letter (ST, SE, SA...), then a number.
  const assign = (id, name) => {
    const base = state.aliases[id] || baseAlias(name);
    const letters = name.replace(/[^A-Za-z0-9]/g, '').toUpperCase();
    let alias = base;
    for (let letterIndex = 2; taken.has(alias) && letterIndex < letters.length; letterIndex++) alias = letters[0] + letters[letterIndex];
    for (let suffix = 2; taken.has(alias); suffix++) alias = base + suffix;
    taken.add(alias);
    aliasIndex.set(id, alias);
  };
  state.quickLinks.forEach((place) => assign('place:' + place.path, place.name));
  // Most-used apps claim the short aliases first, so the ones you open daily get the clean two-letter ids.
  const usage = (app) => state.counts[app.id] || 0;
  [...state.apps].sort((first, second) => usage(second) - usage(first) || first.name.localeCompare(second.name)).forEach((app) => assign(app.id, app.name));
  // The switcher shows the same identifiers on its cards.
  if (!isHome) window.api.reportAliases(Object.fromEntries(aliasIndex));
}

const aliasOf = (id) => aliasIndex.get(id) || '';

// ---- items ----

function appItems() {
  return state.apps.map((app) => ({ kind: 'Apps', id: app.id, name: app.name, alias: aliasOf(app.id), app, time: state.lastUsed[app.id] }));
}

function placeItems() {
  return state.quickLinks.map((place) => ({ kind: 'Folders', id: 'place:' + place.path, name: place.name, alias: aliasOf('place:' + place.path), path: place.path }));
}

function recentItemsOfKind(kind) {
  return state.recentItems
    .filter((item) => item.kind === kind)
    .map((item) => ({ kind: kind === 'file' ? 'Files' : 'Folders', id: 'recent:' + item.target, name: item.name, alias: kind === 'file' ? (item.name.split('.').pop() || '').toUpperCase().slice(0, 6) : baseAlias(item.name), path: item.folder, target: item.target, time: item.time }));
}

function commandItems() {
  return commands.map((command) => ({ kind: 'Commands', id: 'command:' + command.name, name: command.name, alias: command.alias, command }));
}

function scoreItem(item, query) {
  const lowerQuery = query.toLowerCase();
  const name = item.name.toLowerCase();
  const alias = item.alias.toLowerCase();
  if (alias && alias === lowerQuery) return 4;
  if (name.startsWith(lowerQuery) || (alias && alias.startsWith(lowerQuery))) return 3;
  const index = name.indexOf(lowerQuery);
  if (index > 0 && /[^a-z0-9]/.test(name[index - 1])) return 2;
  return index >= 0 ? 1 : 0;
}

function collectGroups(query, scope) {
  const groups = [
    { kind: 'Apps', items: appItems() },
    { kind: 'Files', items: recentItemsOfKind('file') },
    { kind: 'Folders', items: [...placeItems(), ...recentItemsOfKind('folder')] },
    { kind: 'Commands', items: commandItems() },
  ];
  const usage = (item) => (item.app && state.counts[item.app.id]) || 0;
  return groups
    .filter((group) => scope === 'All' || scope === group.kind)
    .map((group) => {
      const matches = group.items
        .map((item) => ({ item, score: scoreItem(item, query) }))
        .filter((match) => match.score > 0)
        .sort((first, second) => second.score - first.score || usage(second.item) - usage(first.item) || (second.item.time || 0) - (first.item.time || 0) || first.item.name.localeCompare(second.item.name));
      return { kind: group.kind, total: matches.length, items: matches.slice(0, scope === 'All' ? maximumRowsPerGroup : maximumRowsPerScope).map((match) => match.item) };
    })
    .filter((group) => group.items.length > 0);
}

// ---- markup ----

function appMini(app) {
  return app.icon
    ? `<span class="mini"><img src="${fileUrl(app.icon)}" data-app="${escapeHtml(app.id)}" draggable="false"></span>`
    : `<span class="mini" data-app-letter="${escapeHtml(app.id)}">${escapeHtml(app.name[0].toUpperCase())}</span>`;
}

function highlightMatch(text, query) {
  const matchIndex = query ? text.toLowerCase().indexOf(query.toLowerCase()) : -1;
  if (matchIndex < 0) return escapeHtml(text);
  return escapeHtml(text.slice(0, matchIndex)) + '<mark>' + escapeHtml(text.slice(matchIndex, matchIndex + query.length)) + '</mark>' + escapeHtml(text.slice(matchIndex + query.length));
}

function tagMarkup(id) {
  const tagName = state.labels[id];
  return tagName && tagColours[tagName] ? `<span class="tag" style="--dot:${tagColours[tagName]}">${tagName}</span>` : '<span></span>';
}

function rowMarkup(item, query, index) {
  const kindGlyph = { Apps: 'app', Files: 'file', Folders: 'folder', Commands: 'command' }[item.kind];
  const mini = item.app ? appMini(item.app) : `<span class="mini">${icon(item.command ? item.command.glyph : kindGlyph)}</span>`;
  const path = item.path ? `<span class="path">${escapeHtml(item.path)}</span>` : '';
  const keys = item.command && item.command.keys.length ? `<span class="keys">${item.command.keys.map(key).join('')}</span>` : '<span></span>';
  const middle = item.app ? tagMarkup(item.id) : '<span></span>';
  return `<div class="row${index === selectedIndex ? ' sel' : ''}" data-index="${index}" style="--i:${Math.min(index, 6)}">`
    + `<span class="kind">${icon(kindGlyph)}</span><span class="id">${highlightMatch(item.alias, query)}</span>${mini}`
    + `<span class="name">${highlightMatch(item.name, query)}${path}</span>${middle}${keys}<span class="meta">${timeAgo(item.time)}</span></div>`;
}

function tileMarkup(app) {
  const iconMarkup = app.icon
    ? `<span class="app-icon"><img src="${fileUrl(app.icon)}" data-app="${escapeHtml(app.id)}" draggable="false"></span>`
    : `<span class="app-icon" data-app-letter="${escapeHtml(app.id)}">${escapeHtml(app.name[0].toUpperCase())}</span>`;
  return `<div class="tile" data-app-id="${escapeHtml(app.id)}"><span class="alias">${aliasOf(app.id)}</span>${iconMarkup}<span class="name">${escapeHtml(app.name)}</span></div>`;
}

// ---- rendering ----

function renderScopes(groupCounts) {
  $('#scopes').innerHTML = scopes.map((scope) =>
    `<button class="scope" data-scope="${scope}" aria-pressed="${scope === activeScope}">${scope}${groupCounts && scope !== 'All' ? `<span class="count">${groupCounts[scope] || 0}</span>` : ''}</button>`).join('');
}

function recentRows() {
  const appsById = new Map(state.apps.map((app) => [app.id, app]));
  const recentApps = state.recent.map((id) => appsById.get(id)).filter(Boolean)
    .map((app) => ({ kind: 'Apps', id: app.id, name: app.name, alias: aliasOf(app.id), app, time: state.lastUsed[app.id] || 0 }));
  const recentFiles = recentItemsOfKind('file');
  return [...recentApps, ...recentFiles].sort((first, second) => (second.time || 0) - (first.time || 0)).slice(0, recentRowCount);
}

function renderIdle() {
  renderScopes(null);
  if (isHome || isPalette()) {
    // Home and the palette stay quiet: nothing is highlighted until an arrow key picks a row.
    visibleRows = recentRows();
    selectedIndex = -1;
    bodyElement.innerHTML = visibleRows.length
      ? `<div class="section">Recent</div><div class="results">${visibleRows.map((item, index) => rowMarkup(item, '', index)).join('')}</div>`
      : '';
    setHints();
    return;
  }
  const appsById = new Map(state.apps.map((app) => [app.id, app]));
  const pinnedApps = state.pinned.map((id) => appsById.get(id)).filter(Boolean);
  visibleRows = recentRows();
  selectedIndex = Math.min(selectedIndex, Math.max(visibleRows.length - 1, 0));
  const places = state.quickLinks.slice(0, 9);
  bodyElement.innerHTML =
    `<div class="section">Places<span class="spacer"></span>${key('Alt')}<span class="note">+ number</span></div>`
    + `<div class="places">${places.map((place, placeIndex) => `<span class="place" data-place="${placeIndex}">${icon('folder')}${escapeHtml(place.name)}${key(placeIndex + 1)}</span>`).join('')}</div>`
    + `<div class="section">Pinned<span class="count">${pinnedApps.length}</span></div>`
    + (pinnedApps.length ? `<div class="grid">${pinnedApps.map(tileMarkup).join('')}</div>` : '<div class="empty-hint">Right-click any app in the results and choose Pin to add it here.</div>')
    + (visibleRows.length ? `<div class="section">Recent</div><div class="results">${visibleRows.map((item, index) => rowMarkup(item, '', index)).join('')}</div>` : '');
  setHints();
}

function renderResults(query) {
  const allGroups = collectGroups(query, 'All');
  renderScopes(Object.fromEntries(allGroups.map((group) => [group.kind, group.total])));
  const groups = activeScope === 'All' ? allGroups : collectGroups(query, activeScope);
  visibleRows = groups.flatMap((group) => group.items);
  selectedIndex = Math.min(selectedIndex, Math.max(visibleRows.length - 1, 0));
  if (visibleRows.length === 0) {
    bodyElement.innerHTML = `<div class="empty-state">Nothing matches "${escapeHtml(query)}". ${key('Enter')} searches the web.</div>`;
    setHints();
    return;
  }
  let index = 0;
  bodyElement.innerHTML = '<div class="results">' + groups.map((group) =>
    `<div class="section">${group.kind}<span class="count">${group.total}</span></div>`
    + group.items.map((item) => rowMarkup(item, query, index++)).join('')).join('') + '</div>';
  setHints();
}

function render() {
  const query = queryInput.value.trim();
  document.body.classList.toggle('searching', Boolean(query));
  if (query) renderResults(query);
  else renderIdle();
  bodyElement.scrollTop = 0;
}

function setHints(message) {
  const hints = $('#hints');
  if (message) {
    hints.innerHTML = `<span>${escapeHtml(message)}</span>`;
    return;
  }
  hints.innerHTML = queryInput.value.trim()
    ? `<span>${key('&uarr;')}${key('&darr;')} Move</span><span>${key('Enter')} Open</span><span>${key('Tab')} Scope</span><span>${key('Ctrl')}${key('Enter')} Run as admin</span>`
    : `<span>Type an alias like ${key(aliasOf(state.pinned[0]) || 'CL')} to jump</span><span>${key('Tab')} Scope</span>`;
}

let hintTimer = null;

function flashHint(message) {
  setHints(message);
  clearTimeout(hintTimer);
  hintTimer = setTimeout(() => setHints(), 1600);
}

function moveSelection(step) {
  if (visibleRows.length === 0) return;
  if (selectedIndex < 0) selectedIndex = step > 0 ? 0 : visibleRows.length - 1;
  else selectedIndex = (selectedIndex + step + visibleRows.length) % visibleRows.length;
  bodyElement.querySelectorAll('.row').forEach((rowElement) => rowElement.classList.toggle('sel', Number(rowElement.dataset.index) === selectedIndex));
  const selected = bodyElement.querySelector('.row.sel');
  if (selected) selected.scrollIntoView({ block: 'nearest' });
}

// ---- opening things ----

function openItem(item, asAdmin) {
  if (!item) return;
  const rowElement = bodyElement.querySelector(`.row[data-index="${visibleRows.indexOf(item)}"]`);
  if (rowElement) restartAnimation(rowElement, 'flash');
  if (item.app) {
    if (asAdmin) window.api.launchAdmin(item.app.id);
    else window.api.launch(item.app.id);
  } else if (item.command) {
    window.api.command(item.command.name);
  } else {
    window.api.openPath(item.target || item.path);
  }
}

function openSelected(asAdmin) {
  const query = queryInput.value.trim();
  if (query && visibleRows.length === 0) {
    window.api.webSearch(query);
    return;
  }
  openItem(visibleRows[selectedIndex], asAdmin);
}

function closeLauncher() {
  if (isHome || root.classList.contains('closing')) return;
  root.classList.remove('play');
  root.classList.add('closing');
  setTimeout(() => window.api.hide(), 140);
}

function resetLauncher() {
  queryInput.value = '';
  activeScope = 'All';
  selectedIndex = 0;
  root.classList.remove('closing', 'play', 'intro');
  // Primed: nothing is drawn until 'shown' starts the entrance, so the frame on screen
  // the moment the window turns visible is empty rather than the finished launcher.
  if (!isHome) root.classList.add('primed');
  launcher.classList.remove('alt-held');
  render();
}

// ---- power ----

function renderPower() {
  const powerElement = $('#power');
  powerElement.innerHTML = powerActions.map((action, actionIndex) =>
    `<button data-index="${actionIndex}" aria-label="${action.name}">${icon(action.glyph)}<span class="label">Press again to ${action.name.toLowerCase()}</span>`
    + `<span class="tooltip">${action.name}${action.keys.length ? `<span class="keys">${action.keys.map(key).join('')}</span>` : ''}</span></button>`).join('');
  powerElement.querySelectorAll('button').forEach((button) => {
    let confirmTimer = null;
    button.addEventListener('click', () => {
      const action = powerActions[Number(button.dataset.index)];
      if (action.needsConfirm && !button.classList.contains('confirming')) {
        button.classList.add('confirming');
        confirmTimer = setTimeout(() => button.classList.remove('confirming'), confirmWindowMilliseconds);
        return;
      }
      clearTimeout(confirmTimer);
      button.classList.remove('confirming');
      if (state.dev) flashHint(`${action.name} skipped in dev mode`);
      window.api.power(action.action);
    });
  });
}

// ---- events ----

queryInput.addEventListener('input', () => {
  selectedIndex = 0;
  render();
});

window.addEventListener('keydown', (event) => {
  launcher.classList.toggle('alt-held', event.altKey);
  if (event.altKey && /^[1-9]$/.test(event.key)) {
    const place = state.quickLinks[Number(event.key) - 1];
    if (place) window.api.openPath(place.path);
    event.preventDefault();
    return;
  }
  if (event.key === 'ArrowDown' || event.key === 'ArrowUp') {
    event.preventDefault();
    moveSelection(event.key === 'ArrowDown' ? 1 : -1);
  } else if (event.key === 'Enter') {
    event.preventDefault();
    openSelected(event.ctrlKey);
  } else if (event.key === 'Tab') {
    event.preventDefault();
    if (!document.body.classList.contains('searching')) return; // the scopes are hidden
    activeScope = scopes[(scopes.indexOf(activeScope) + (event.shiftKey ? scopes.length - 1 : 1)) % scopes.length];
    selectedIndex = 0;
    render();
  } else if (event.key === 'Escape') {
    event.preventDefault();
    if (queryInput.value) {
      queryInput.value = '';
      activeScope = 'All';
      render();
    } else {
      closeLauncher();
    }
  }
});

window.addEventListener('keyup', (event) => launcher.classList.toggle('alt-held', event.altKey));

$('#scopes').addEventListener('click', (event) => {
  const button = event.target.closest('.scope');
  if (!button) return;
  activeScope = button.dataset.scope;
  selectedIndex = 0;
  render();
  queryInput.focus();
});

bodyElement.addEventListener('click', (event) => {
  const row = event.target.closest('.row');
  const tile = event.target.closest('.tile');
  const place = event.target.closest('.place');
  if (row) {
    selectedIndex = Number(row.dataset.index);
    openItem(visibleRows[selectedIndex], event.ctrlKey);
  } else if (tile) {
    window.api.launch(tile.dataset.appId);
  } else if (place) {
    window.api.openPath(state.quickLinks[Number(place.dataset.place)].path);
  }
});

bodyElement.addEventListener('contextmenu', (event) => {
  const row = event.target.closest('.row');
  const tile = event.target.closest('.tile');
  const item = row ? visibleRows[Number(row.dataset.index)] : null;
  const appId = tile ? tile.dataset.appId : item && item.app ? item.app.id : null;
  if (!appId) return;
  event.preventDefault();
  window.api.contextMenu(appId);
});

// A click outside the panel closes it. Not in dev mode, where the launcher sits in an
// ordinary window that never hides, so closing would only replay the fade and reset.
function closeFromOutside(event) {
  if (state.dev || (event.currentTarget === $('#layer') && event.target !== $('#layer'))) return;
  closeLauncher();
}

if (!isHome) $('#scrim').addEventListener('mousedown', closeFromOutside);
$('#layer').addEventListener('mousedown', closeFromOutside);

window.addEventListener('focus', () => queryInput.focus());

window.api.onState((newState) => {
  state = { ...state, ...newState };
  buildAliases();
  $('#avatar').textContent = (state.user[0] || '?').toUpperCase();
  $('#username').textContent = state.user;
  render();
});

window.api.onIcon(({ id, icon: iconPath }) => {
  const app = state.apps.find((candidate) => candidate.id === id);
  if (app) app.icon = iconPath;
  document.querySelectorAll(`[data-app-letter="${CSS.escape(id)}"]`).forEach((element) => {
    element.removeAttribute('data-app-letter');
    element.innerHTML = `<img src="${fileUrl(iconPath)}" data-app="${escapeHtml(id)}" draggable="false">`;
  });
});

// The UI is reset while the window is hidden, so showing displays an already-clean frame.
window.api.onReset(resetLauncher);
if (!isHome) root.classList.add('primed'); // the first show too
window.api.onShown((mode) => {
  if (!isHome) {
    document.body.classList.toggle('palette', mode === 'palette');
    render();
  }
  root.classList.remove('primed');
  restartAnimation(root, 'play');
  queryInput.focus();
});

// Intro: plays once at sign-in. The greeting fades up and away while the glow
// blooms, then Home rises in; timings live in home.css.
function playIntro() {
  const hour = new Date().getHours();
  const partOfDay = hour < 12 ? 'morning' : hour < 18 ? 'afternoon' : 'evening';
  const name = state.displayName || state.user;
  $('#greetingText').textContent = `Good ${partOfDay}${name ? ', ' + name : ''}`;
  $('#dateText').textContent = new Date().toLocaleDateString(undefined, { weekday: 'long', day: 'numeric', month: 'long' });
  root.classList.remove('play');
  restartAnimation(root, 'intro');
  queryInput.focus();
}

window.api.onIntro(playIntro);

renderPower();
render();
window.api.requestState();
