// Taskbar: Home button, pinned and running apps (windows of one app combined), folders,
// status glyphs and the clock. The main process builds the items (taskbar-model.js); this
// page draws them and turns clicks, drags and hovers into actions.

const dock = document.getElementById('dock');
const bar = document.getElementById('bar');
const appsElement = document.getElementById('apps');
const popover = document.getElementById('popover');
const previews = document.getElementById('previews');

const clockRefreshMilliseconds = 10000;
const previewDelay = 450;        // hover this long before window previews appear
const closeGrace = 600;          // popover and previews survive this long after the pointer leaves
const dragThreshold = 5;
const holdToFold = 500;          // hold a dragged pill over another this long to make a folder

const pinGlyph = '<svg class="i" viewBox="0 0 16 16"><path d="M6 2.5h4l-.5 4 2 2v1H4.5v-1l2-2zM8 9.5V14"/></svg>';

let items = [];
let showLabels = true;
let pending = null;              // state that arrived mid-drag or mid-rename, applied after
let knownRefs = new Set();
let openRef = null;              // the pill whose popover is open
let renamingId = null;
let finishRename = null;   // ends the rename in progress, if any
let dragging = false;

// ---------- helpers ----------

function escapeHtml(text) {
  return String(text).replace(/[&<>"]/g, (character) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' })[character]);
}

function fileUrl(filePath) {
  return 'file:///' + encodeURI(filePath.replace(/\\/g, '/'));
}

function iconMarkup(app) {
  return app.icon
    ? `<img src="${fileUrl(app.icon)}" draggable="false">`
    : `<span class="letter">${escapeHtml((app.name[0] || '?').toUpperCase())}</span>`;
}

const itemByRef = (ref) => items.find((item) => item.ref === ref);

// A tag's colour as a CSS value (tokens.css: --tag-blue ... ; amber is the accent).
const tagColor = (tag) => (tag.color === 'amber' ? 'var(--accent)' : `var(--tag-${tag.color})`);
const tagDot = (tag) => (tag ? `<span class="tag-dot" style="--tag: ${tagColor(tag)}" title="${escapeHtml(tag.name)}"></span>` : '');

// ---------- the bar ----------

function render() {
  appsElement.classList.toggle('icons-only', !showLabels);
  appsElement.innerHTML = items.map((item) => {
    const classes = ['item', item.type, item.focused ? 'on' : '', item.running ? 'running' : 'idle', knownRefs.has(item.ref) ? '' : 'entering', item.ref === openRef ? 'open' : ''].join(' ').replace(/\s+/g, ' ').trim();
    const dot = item.attention ? '<span class="dot"></span>' : '';
    if (item.type === 'folder') {
      const stack = item.apps.slice(0, 4).map(iconMarkup).join('');
      return `<button class="${classes}" data-ref="${escapeHtml(item.ref)}" title="${escapeHtml(item.name)}"><span class="stack">${stack}</span><span class="label">${escapeHtml(item.name)}</span>${dot}</button>`;
    }
    const windowCount = item.windows.length;
    const tabs = windowCount === 1 ? item.windows[0].tabs : 1;
    const count = windowCount > 1 ? windowCount : tabs > 1 ? tabs : 0;
    const label = item.tag ? item.tag.name : windowCount === 1 ? shortLabel(item.windows[0].title, item.name) : item.name;
    const title = (windowCount === 1 ? item.windows[0].title : item.name + (windowCount > 1 ? ` (${windowCount} windows)` : '')) + (item.tag ? ` · ${item.tag.name}` : '');
    return `<button class="${classes}${item.tag ? ' tagged' : ''}" data-ref="${escapeHtml(item.ref)}" title="${escapeHtml(title)}"${item.tag ? ` style="--tag: ${tagColor(item.tag)}"` : ''}><span class="icon-wrap">${iconMarkup(item)}${item.tag ? '<span class="tag-mark"></span>' : ''}</span><span class="label">${escapeHtml(label)}</span>${count ? `<span class="count">${count}</span>` : ''}${dot}</button>`;
  }).join('');
  knownRefs = new Set(items.map((item) => item.ref));
  if (openRef) renderPopover();
}

// Window titles read "Document - App"; the short label keeps the part people scan for.
function shortLabel(title, fallback) {
  const parts = title.split(/ [-—–] /);
  return (parts.length > 1 ? parts[parts.length - 1] : title) || fallback;
}

function applyState(state) {
  if (dragging || renamingId) {
    pending = state;
    return;
  }
  items = state.items;
  showLabels = state.showLabels;
  if (openRef && !itemByRef(openRef)) closePopover();
  render();
}

// ---------- acting on an app ----------

// No windows: launch it. One window: focus it, or minimise it if it already has focus.
// Several: the popover lists them.
function activateApp(app, pill) {
  if (app.windows.length === 0) window.api.taskbarLaunch(app.key);
  else if (app.windows.length === 1) window.api.taskbarClick(app.windows[0].hwnd);
  else {
    openPopover(app.ref, pill);
    return;
  }
  closePopover();
}

// ---------- popover ----------

function openPopover(ref, pill) {
  hidePreviews();
  if (openRef === ref) {
    closePopover();
    return;
  }
  openRef = ref;
  renderPopover(pill);
}

function closePopover() {
  if (finishRename) finishRename(true); // keep what was typed
  openRef = null;
  popover.hidden = true;
  appsElement.querySelectorAll('.item.open').forEach((element) => element.classList.remove('open'));
  updateInteractive();
}

function placeAbove(element, pill) {
  const anchor = pill || appsElement.querySelector(`.item[data-ref="${CSS.escape(openRef)}"]`);
  if (!anchor) return;
  const rect = anchor.getBoundingClientRect();
  const width = element.offsetWidth;
  const left = Math.min(Math.max(rect.left + rect.width / 2 - width / 2, 8), innerWidth - width - 8);
  element.style.left = left + 'px';
}

function appRows(app, folderId) {
  const meta = app.windows.length > 1 ? `${app.windows.length} windows` : app.running ? '' : 'Not running';
  const row = `<button class="row${app.focused ? ' on' : ''}${app.running ? '' : ' idle'}" data-key="${escapeHtml(app.key)}" data-folder="${escapeHtml(folderId || '')}">${iconMarkup(app)}<span class="name">${escapeHtml(app.name)}</span><span class="meta">${meta}</span></button>`;
  const windows = app.windows.length > 1 ? app.windows.map((window) => `<button class="row window${window.focused ? ' on' : ''}" data-hwnd="${escapeHtml(window.hwnd)}"><span class="name">${escapeHtml(window.title)}</span>${tagDot(window.tag)}</button>`).join('') : '';
  return row + windows;
}

function renderPopover(pill) {
  const item = itemByRef(openRef);
  if (!item) {
    closePopover();
    return;
  }
  appsElement.querySelectorAll('.item').forEach((element) => element.classList.toggle('open', element.dataset.ref === openRef));
  let head;
  let rows;
  if (item.type === 'folder') {
    const nameMarkup = renamingId === item.id
      ? `<input id="renameInput" value="${escapeHtml(item.name)}" maxlength="40" spellcheck="false" aria-label="Folder name">`
      : `<span class="name">${escapeHtml(item.name)}</span>`;
    head = `${nameMarkup}${item.label ? '<span class="meta">category</span>' : ''}<button class="pin${item.pinned ? ' pinned' : ''}" data-pin="${escapeHtml(item.id)}" title="${item.pinned ? 'Unpin folder' : 'Pin folder'}">${pinGlyph}</button>`;
    rows = item.apps.map((app) => appRows(app, item.id)).join('') || '<div class="row idle"><span class="name">No apps with this label yet</span></div>';
  } else {
    head = `<span class="name">${escapeHtml(item.name)}</span>`;
    rows = item.windows.map((window) => `<button class="row${window.focused ? ' on' : ''}" data-hwnd="${escapeHtml(window.hwnd)}">${iconMarkup(item)}<span class="name">${escapeHtml(window.title)}</span>${tagDot(window.tag)}</button>`).join('');
  }
  const renameHint = item.type === 'folder' && renamingId === item.id
    ? '<div class="rename-hint"><span class="key">Enter</span> Save <span class="key">Esc</span> Keep the old name</div>'
    : '';
  popover.innerHTML = `<div class="head${renameHint ? ' editing' : ''}">${head}</div>${renameHint}<div class="rows">${rows}</div>`;
  popover.hidden = false;
  placeAbove(popover, pill);

  const input = document.getElementById('renameInput');
  if (input) {
    window.focus();
    input.focus();
    input.select();
    const pillLabel = appsElement.querySelector(`.item[data-ref="${CSS.escape(openRef)}"] .label`);
    const pill = appsElement.querySelector(`.item[data-ref="${CSS.escape(openRef)}"]`);
    if (pill) pill.classList.add('renaming');
    input.addEventListener('input', () => {
      if (pillLabel) pillLabel.textContent = input.value || ' ';
    });
    const finish = (save) => {
      if (!renamingId) return;
      const id = renamingId;
      renamingId = null;
      finishRename = null;
      if (pill) pill.classList.remove('renaming');
      window.api.taskbarRename(id, save ? input.value : null);
      if (pending) applyState(pending);
      pending = null;
      renderPopover();
    };
    finishRename = finish;
    input.addEventListener('keydown', (event) => {
      if (event.key === 'Enter') finish(true);
      if (event.key === 'Escape') finish(false);
    });
    input.addEventListener('blur', () => finish(true));
  }
  updateInteractive();
}

popover.addEventListener('click', (event) => {
  const pin = event.target.closest('[data-pin]');
  if (pin) {
    window.api.taskbarContext({ kind: 'folder-pin', id: pin.dataset.pin });
    return;
  }
  const windowRow = event.target.closest('[data-hwnd]');
  if (windowRow) {
    window.api.taskbarClick(windowRow.dataset.hwnd);
    closePopover();
    return;
  }
  const appRow = event.target.closest('[data-key]');
  if (!appRow) return;
  const folder = itemByRef(openRef);
  const app = folder && folder.apps && folder.apps.find((member) => member.key === appRow.dataset.key);
  if (!app) return;
  if (app.windows.length > 1) return; // its windows are listed right under it
  activateApp(app);
});

popover.addEventListener('contextmenu', (event) => {
  const windowRow = event.target.closest('[data-hwnd]');
  if (windowRow) {
    event.preventDefault();
    window.api.taskbarContext({ kind: 'window', hwnd: windowRow.dataset.hwnd });
    return;
  }
  const appRow = event.target.closest('[data-key]');
  if (!appRow) return;
  event.preventDefault();
  window.api.taskbarContext({ kind: 'app', ref: openRef, key: appRow.dataset.key, folderId: appRow.dataset.folder });
});

window.api.onTaskbarRename((id) => {
  const folder = items.find((item) => item.type === 'folder' && item.id === id);
  if (!folder) return;
  renamingId = id;
  openRef = folder.ref;
  renderPopover();
});

// ---------- hover previews ----------

let previewTimer = null;
let previewRef = null;

// Trace of hover decisions, for chasing previews that stay open. Dev mode prints this
// page's console in its terminal; elsewhere nobody listens.
let lastTrace = '';
function trace(message) {
  if (message === lastTrace) return;
  lastTrace = message;
  console.log('hover: ' + message);
}

function scheduleUpdate(element) {
  clearTimeout(previewTimer);
  const item = element ? itemByRef(element.dataset.ref) : null;
  if (!item || item.type !== 'app' || !item.running || openRef || dragging) {
    previewTimer = setTimeout(hidePreviews, previewRef ? closeGrace / 3 : 0);
    return;
  }
  if (previewRef === item.ref) return;
  previewTimer = setTimeout(() => showPreviews(item, element), previewRef ? 80 : previewDelay);
}

function showPreviews(app, pill) {
  trace(`show previews for ${app.name} (${app.windows.length} windows)`);
  previewRef = app.ref;
  // Windows cannot draw a minimised window, so those show the app's icon instead.
  previews.innerHTML = app.windows.slice(0, 4).map((window) => {
    const well = window.minimized ? `<div class="well minimized">${iconMarkup(app)}<span>Minimised</span></div>` : '<div class="well"></div>';
    return `<div class="preview" data-hwnd="${escapeHtml(window.hwnd)}" data-minimized="${window.minimized ? 1 : 0}"><div class="title">${app.icon ? `<img src="${fileUrl(app.icon)}" draggable="false">` : ''}<span>${escapeHtml(window.title)}</span></div>${well}</div>`;
  }).join('');
  previews.hidden = false;
  placeAbove(previews, pill);
  updateInteractive();
  // The wells' places on screen, in physical pixels relative to this window, for DWM.
  requestAnimationFrame(() => requestAnimationFrame(() => {
    if (previewRef !== app.ref) return;
    const scale = window.devicePixelRatio;
    const slots = [...previews.querySelectorAll('.preview[data-minimized="0"]')].map((card) => {
      const rect = card.querySelector('.well').getBoundingClientRect();
      return { hwnd: card.dataset.hwnd, x: Math.round(rect.left * scale), y: Math.round(rect.top * scale), w: Math.round(rect.width * scale), h: Math.round(rect.height * scale) };
    });
    window.api.taskbarPreview(slots);
  }));
}

function hidePreviews(reason = 'pointer left the pill') {
  clearTimeout(previewTimer);
  if (!previewRef) return;
  trace('hide previews: ' + reason);
  previewRef = null;
  previews.hidden = true;
  window.api.taskbarPreview([]);
  updateInteractive();
}

previews.addEventListener('click', (event) => {
  const card = event.target.closest('[data-hwnd]');
  if (!card) return;
  hidePreviews();
  window.api.taskbarClick(card.dataset.hwnd);
});

appsElement.addEventListener('mouseover', (event) => scheduleUpdate(event.target.closest('.item')));
previews.addEventListener('mouseenter', () => clearTimeout(previewTimer));
previews.addEventListener('mouseleave', () => {
  previewTimer = setTimeout(hidePreviews, closeGrace / 3);
});

// ---------- dragging: reorder, or hold over another pill to fold them into a folder ----------

appsElement.addEventListener('pointerdown', (event) => {
  const pill = event.target.closest('.item');
  if (!pill || event.button !== 0) return;
  const ref = pill.dataset.ref;
  const grabX = event.clientX - pill.getBoundingClientRect().left;
  const startX = event.clientX;
  const startY = event.clientY;
  let moved = false;
  let holdTarget = null;
  let holdTimer = null;
  let foldTarget = null;
  let order = items.map((item) => item.ref);
  appsElement.setPointerCapture(event.pointerId);

  const element = () => appsElement.querySelector(`.item[data-ref="${CSS.escape(ref)}"]`);

  const clearFold = () => {
    clearTimeout(holdTimer);
    holdTarget = null;
    foldTarget = null;
    appsElement.querySelectorAll('.merge-target').forEach((target) => target.classList.remove('merge-target'));
  };

  const onMove = (moveEvent) => {
    if (!moved && Math.hypot(moveEvent.clientX - startX, moveEvent.clientY - startY) < dragThreshold) return;
    if (!moved) {
      moved = true;
      dragging = true;
      reportHitRegions();
      hidePreviews();
      closePopover();
      element().classList.add('dragging');
    }

    // Over the middle of another pill: start (or keep) the hold. Anywhere else: reorder.
    const others = [...appsElement.querySelectorAll('.item')].filter((other) => other.dataset.ref !== ref);
    const over = others.find((other) => {
      const rect = other.getBoundingClientRect();
      return moveEvent.clientX > rect.left + rect.width * 0.25 && moveEvent.clientX < rect.right - rect.width * 0.25;
    });
    if (over) {
      if (holdTarget !== over.dataset.ref) {
        clearFold();
        holdTarget = over.dataset.ref;
        holdTimer = setTimeout(() => {
          foldTarget = holdTarget;
          over.classList.add('merge-target');
        }, holdToFold);
      }
    } else {
      clearFold();
      const index = others.filter((other) => {
        const rect = other.getBoundingClientRect();
        return rect.left + rect.width / 2 < moveEvent.clientX;
      }).length;
      const without = order.filter((candidate) => candidate !== ref);
      const next = [...without.slice(0, index), ref, ...without.slice(index)];
      if (next.join('|') !== order.join('|')) {
        order = next;
        const byRef = new Map(items.map((item) => [item.ref, item]));
        items = order.map((candidate) => byRef.get(candidate));
        render();
        element().classList.add('dragging');
      }
    }

    // The pill follows the pointer along the bar.
    const dragged = element();
    dragged.style.transform = 'none';
    const natural = dragged.getBoundingClientRect().left;
    dragged.style.transform = `translateX(${moveEvent.clientX - grabX - natural}px)`;
  };

  const onUp = () => {
    appsElement.removeEventListener('pointermove', onMove);
    appsElement.removeEventListener('pointerup', onUp);
    appsElement.removeEventListener('pointercancel', onUp);
    const target = foldTarget;
    clearFold();
    dragging = false;
    reportHitRegions();
    if (!moved) {
      const item = itemByRef(ref);
      if (!item) return;
      if (item.type === 'folder') openPopover(ref, pill);
      else activateApp(item, pill);
      return;
    }
    if (target) window.api.taskbarMerge(ref, target);
    else window.api.taskbarReorder(order);
    if (pending) {
      applyState(pending);
      pending = null;
    } else {
      render();
    }
  };

  appsElement.addEventListener('pointermove', onMove);
  appsElement.addEventListener('pointerup', onUp);
  appsElement.addEventListener('pointercancel', onUp);
});

appsElement.addEventListener('contextmenu', (event) => {
  event.preventDefault();
  const pill = event.target.closest('.item');
  const item = pill ? itemByRef(pill.dataset.ref) : null;
  if (!item) return;
  window.api.taskbarContext({ kind: item.type, ref: item.ref, key: item.key, id: item.id });
});

// Right-click on an empty part of the bar: the bar's own settings.
bar.addEventListener('contextmenu', (event) => {
  if (event.target.closest('.item') || event.target.closest('button')) return;
  event.preventDefault();
  window.api.taskbarContext({ kind: 'bar' });
});

// ---------- the mouse: the window lets it through except over the bar and what is open ----------

let overSurface = false;
let leaveTimer = null;

// Main makes this window take the mouse only over the parts reported here: the bar, plus
// the popover, previews or a panel while open. A drag or a rename keeps it everywhere.
function regionOf(element) {
  const rect = element.getBoundingClientRect();
  return { x: Math.floor(rect.left), y: Math.floor(rect.top), width: Math.ceil(rect.width), height: Math.ceil(rect.height) };
}

function reportHitRegions() {
  // An open panel holds focus, and turning click-through on would pass that focus to the
  // window underneath; so the whole window takes the mouse, and a press outside the panel
  // closes it (see below).
  if (dragging || renamingId || panel) {
    window.api.setHitRegions('capture');
    return;
  }
  const regions = [];
  if (!dock.classList.contains('hidden')) regions.push(regionOf(bar));
  for (const surface of [popover, previews, panelElement]) if (!surface.hidden) regions.push(regionOf(surface));
  window.api.setHitRegions(regions);
}

function updateInteractive() {
  const open = !popover.hidden || !previews.hidden;
  reportHitRegions();
  watchPointer(open);
}

// Once the pointer leaves this window the page hears nothing more, so mouseleave alone can
// leave a popover or previews stuck open. While either is open, main is asked where the
// pointer really is. Each belongs to one pill: it stays while the pointer is on that pill,
// on the card itself, or crossing the gap between them, and closes a moment after the
// pointer is anywhere else (elsewhere on the bar included). A rename in progress keeps the
// popover only; nothing keeps the previews.
const pointerPoll = 200;
let pointerWatch = null;
const awaySince = { previews: 0, popover: 0 };

function pillFor(ref) {
  return ref ? appsElement.querySelector(`.item[data-ref="${CSS.escape(ref)}"]`) : null;
}

function pointerNear(point, pill, card) {
  const within = (element, reachUp) => {
    if (!element || element.hidden) return false;
    const rect = element.getBoundingClientRect();
    return point.x >= rect.left - 8 && point.x <= rect.right + 8 && point.y >= rect.top - reachUp && point.y <= rect.bottom + 8;
  };
  return within(pill, 24) || within(card, 8); // 24 spans the space-4 gap up to the card
}

// True once the pointer has been away for the grace period.
function goneFor(which, near) {
  if (near) {
    awaySince[which] = 0;
    return false;
  }
  if (!awaySince[which]) awaySince[which] = Date.now();
  return Date.now() - awaySince[which] >= closeGrace;
}

function watchPointer(open) {
  if (!open) {
    clearInterval(pointerWatch);
    pointerWatch = null;
    awaySince.previews = awaySince.popover = 0;
    return;
  }
  if (pointerWatch) return;
  pointerWatch = setInterval(async () => {
    let point;
    try {
      point = await window.api.taskbarCursor();
    } catch (error) {
      console.error('taskbar: pointer check failed', error);
      return;
    }
    if (!point) return;
    if (previewRef) {
      const pill = pillFor(previewRef);
      const near = pointerNear(point, pill, previews);
      if (goneFor('previews', near)) {
        overSurface = false;
        hidePreviews('pointer check: away from the pill and the previews');
      }
    }
    if (openRef && !renamingId && !dragging && goneFor('popover', pointerNear(point, pillFor(openRef), popover))) {
      overSurface = false;
      closePopover();
    }
  }, pointerPoll);
}

for (const surface of [bar, popover, previews]) {
  surface.addEventListener('mouseenter', () => {
    clearTimeout(leaveTimer);
    overSurface = true;
    updateInteractive();
  });
  surface.addEventListener('mouseleave', () => {
    overSurface = false;
    clearTimeout(leaveTimer);
    // Leaving everything: the popover closes after a moment (clicks outside never reach us).
    leaveTimer = setTimeout(() => {
      if (overSurface || renamingId || dragging) return;
      closePopover();
      hidePreviews();
      updateInteractive();
    }, closeGrace);
    updateInteractive();
  });
}

// ---------- tray and clock ----------

function renderClock() {
  const now = new Date();
  document.getElementById('time').textContent = now.toLocaleTimeString(undefined, { hour: '2-digit', minute: '2-digit' });
  document.getElementById('date').textContent = now.toLocaleDateString();
}

function renderNetwork() {
  document.getElementById('network').style.opacity = navigator.onLine ? '1' : '0.4';
}

// Desktops report a permanently full, charging "battery"; only a real one is shown.
async function renderBattery() {
  if (!navigator.getBattery) return;
  const battery = await navigator.getBattery();
  const update = () => {
    const isDesktop = battery.charging && battery.level === 1 && battery.chargingTime === 0;
    document.getElementById('battery').hidden = isDesktop;
    batteryState = isDesktop ? null : { level: battery.level, charging: battery.charging };
    renderPanelBattery();
    document.getElementById('batteryLevel').setAttribute('width', String(Math.max(0.5, 8.5 * battery.level)));
  };
  battery.addEventListener('levelchange', update);
  battery.addEventListener('chargingchange', update);
  update();
}

// ---------- quick settings and calendar ----------

// Our own versions of the Windows flyouts, centred above the bar. Main gives this window
// focus while one is open and closes it when focus moves elsewhere.
const panelElement = document.getElementById('panel');
const volumeSendMilliseconds = 60; // while the slider is dragged, at most this often

const panelGlyphs = {
  wifi: '<svg class="i" viewBox="0 0 16 16"><path d="M2 6.5a9 9 0 0 1 12 0M4 9a6 6 0 0 1 8 0M6 11.3a3 3 0 0 1 4 0"/></svg>',
  bluetooth: '<svg class="i" viewBox="0 0 16 16"><path d="m4.5 5 7 6-3.5 3V2l3.5 3-7 6"/></svg>',
  speaker: '<svg class="i" viewBox="0 0 16 16"><path d="M3 6h2.5L9 3v10L5.5 10H3zM11.5 6a3 3 0 0 1 0 4"/></svg>',
  muted: '<svg class="i" viewBox="0 0 16 16"><path d="M3 6h2.5L9 3v10L5.5 10H3zM11 6l3 4M14 6l-3 4"/></svg>',
  chevron: '<svg class="i" viewBox="0 0 16 16"><path d="m6.5 4 4 4-4 4"/></svg>',
  back: '<svg class="i" viewBox="0 0 16 16"><path d="m9.5 4-4 4 4 4"/></svg>',
  play: '<svg class="i" viewBox="0 0 16 16"><path d="M5 3.5v9l7-4.5z" fill="currentColor"/></svg>',
  pause: '<svg class="i" viewBox="0 0 16 16"><path d="M5.5 3.5v9M10.5 3.5v9"/></svg>',
  previous: '<svg class="i" viewBox="0 0 16 16"><path d="M4 3.5v9M12 3.5v9L6 8z"/></svg>',
  next: '<svg class="i" viewBox="0 0 16 16"><path d="M12 3.5v9M4 3.5v9L10 8z"/></svg>',
  music: '<svg class="i" viewBox="0 0 16 16"><path d="M6 12V3.5l7-1.5v8.5M6 12a2 2 0 1 1-4 0 2 2 0 0 1 4 0zM13 10.5a2 2 0 1 1-4 0 2 2 0 0 1 4 0z"/></svg>',
  settings: '<svg class="i" viewBox="0 0 16 16"><circle cx="8" cy="8" r="2"/><path d="M8 1.5v2M8 12.5v2M1.5 8h2M12.5 8h2M3.4 3.4l1.4 1.4M11.2 11.2l1.4 1.4M3.4 12.6l1.4-1.4M11.2 4.8l1.4-1.4"/></svg>',
};

let panel = null;          // { kind, notifications } while one is open
let systemState = null;    // from the helper: speakers, radios, media
let wifiState = null;      // connected network name and signal, or null
let batteryState = null;   // a real battery's level and charging, or null
let calendarMonth = null;  // the first day of the month on show
let volumeDragging = false;
let volumeSendTimer = null;
let mediaKey = '';

function togglePanel(kind) {
  if (panel && panel.kind === kind) {
    window.api.closePanel();
    return;
  }
  closePopover();
  hidePreviews();
  window.api.openPanel(kind);
}

window.api.onPanel((next) => {
  panel = next;
  if (panel && panel.windowsNotifications) windowsNotifications = panel.windowsNotifications;
  if (panel && panel.kind === 'calendar') markNotificationsSeen();
  if (panel && panel.kind === 'calendar') {
    const now = new Date();
    calendarMonth = new Date(now.getFullYear(), now.getMonth(), 1);
  }
  renderPanel();
});

window.api.onSystemState((state) => {
  systemState = state;
  if (panel && panel.kind === 'quick') updateQuick();
});

window.api.onNetworkState((wifi) => {
  wifiState = wifi;
  if (panel && panel.kind === 'quick') updateQuick();
});

function renderPanel() {
  document.getElementById('quick').classList.toggle('active', Boolean(panel && panel.kind === 'quick'));
  document.getElementById('clock').classList.toggle('active', Boolean(panel && panel.kind === 'calendar'));
  panelElement.hidden = !panel;
  alignPanel();
  document.getElementById('peek').classList.toggle('active', Boolean(panel && panel.kind === 'tray'));
  if (panel) {
    panelElement.className = 'panel ' + panel.kind;
    panelElement.setAttribute('aria-label', { quick: 'Quick settings', calendar: 'Calendar and notifications', tray: 'Hidden icons', tag: 'New tag' }[panel.kind]);
    if (panel.kind === 'quick') renderQuick();
    else if (panel.kind === 'tray') renderTray();
    else if (panel.kind === 'tag') renderTagPanel();
    else renderCalendar();
    alignPanel(); // its width is known now
  }
  reportHitRegions();
}

// Quick settings and the calendar line up with the bar's right end; the tray icons sit
// centred over the chevron that opened them.
function alignPanel() {
  if (!panel) return;
  let right = window.innerWidth - bar.getBoundingClientRect().right;
  if (panel.kind === 'tray') {
    const chevron = document.getElementById('peek').getBoundingClientRect();
    right = window.innerWidth - (chevron.left + chevron.width / 2) - panelElement.offsetWidth / 2;
  }
  panelElement.style.right = Math.max(8, Math.round(right)) + 'px';
}

// ---- new tag ----

// Names a tag and picks its colour; it goes straight onto the window it was made for.
function renderTagPanel() {
  const used = new Set((panel.tags || []).map((tag) => tag.color));
  let color = panel.colors.find((candidate) => !used.has(candidate)) || panel.colors[0];
  panelElement.innerHTML = `
    <div class="tag-head">New tag</div>
    <div class="tag-for">${escapeHtml(panel.title || 'This window')}</div>
    <input class="tag-name" id="tagName" maxlength="24" placeholder="Work, Play, Dev..." spellcheck="false">
    <div class="tag-colors" role="radiogroup" aria-label="Colour">${panel.colors.map((candidate) => `<button class="tag-color" role="radio" data-color="${candidate}" aria-label="${candidate}" style="--tag: ${tagColor({ color: candidate })}"></button>`).join('')}</div>
    <div class="tag-actions"><button class="link" id="tagCancel">Cancel</button><button class="tag-create" id="tagCreate">Create</button></div>`;
  const input = document.getElementById('tagName');
  const pick = (value) => {
    color = value;
    panelElement.querySelectorAll('.tag-color').forEach((button) => button.setAttribute('aria-checked', String(button.dataset.color === color)));
  };
  pick(color);
  panelElement.querySelectorAll('.tag-color').forEach((button) => button.addEventListener('click', () => pick(button.dataset.color)));
  const create = () => {
    if (input.value.trim()) window.api.createTag(panel.hwnd, input.value, color);
    else input.focus();
  };
  document.getElementById('tagCreate').addEventListener('click', create);
  document.getElementById('tagCancel').addEventListener('click', () => window.api.closePanel());
  input.addEventListener('keydown', (event) => {
    if (event.key === 'Enter') create();
  });
  setTimeout(() => input.focus(), 50); // once the window has focus
}

// ---- tray icons ----

// The apps' tray icons, as the helper hosts them; clicks go back to the app.
const trayColumns = 5;
let trayIcons = [];

function renderTray() {
  const label = (icon) => (icon.title || icon.app || '').split('\n')[0];
  panelElement.style.setProperty('--tray-columns', String(Math.max(1, Math.min(trayColumns, trayIcons.length))));
  panelElement.innerHTML = trayIcons.length
    ? `<div class="tray-grid">${trayIcons.map((icon) => `<button class="tray-icon" data-id="${escapeHtml(icon.id)}" aria-label="${escapeHtml(label(icon))}"><img src="${escapeHtml(icon.icon)}" alt=""></button>`).join('')}</div>
       <div class="tray-name" id="trayName"></div>`
    : '<div class="tray-empty">No hidden icons</div>';

  panelElement.querySelectorAll('.tray-icon').forEach((button) => {
    const icon = trayIcons.find((item) => item.id === button.dataset.id);
    const centre = () => {
      const rect = button.getBoundingClientRect();
      return [window.screenX + rect.left + rect.width / 2, window.screenY + rect.top + rect.height / 2];
    };
    button.addEventListener('mouseenter', () => { document.getElementById('trayName').textContent = label(icon); });
    button.addEventListener('mouseleave', () => { document.getElementById('trayName').textContent = ''; });
    button.addEventListener('click', () => window.api.trayClick(icon.id, 'left', ...centre()));
    button.addEventListener('dblclick', () => window.api.trayClick(icon.id, 'double', ...centre()));
    button.addEventListener('contextmenu', (event) => {
      event.preventDefault();
      window.api.trayClick(icon.id, 'right', ...centre());
    });
  });
}

window.api.onTrayIcons((icons) => {
  trayIcons = icons;
  if (panel && panel.kind === 'tray') {
    renderTray();
    alignPanel();
    reportHitRegions();
  }
});

// ---- quick settings ----

// Built once per opening, then updated in place, so a dragged slider or a focused button
// survives the regular refresh.
function renderQuick() {
  mediaKey = '';
  panelElement.innerHTML = `
    <div class="tiles">
      ${tileMarkup('wifi', 'Wi-Fi', 'network')}
      ${tileMarkup('bluetooth', 'Bluetooth', 'bluetooth')}
    </div>
    <div class="volume" id="volume">
      <button class="icon-button" id="mute" aria-label="Mute">${panelGlyphs.speaker}</button>
      <input type="range" id="volumeSlider" min="0" max="100" step="1" aria-label="Volume">
      <span class="level" id="volumeLevel"></span>
      <button class="icon-button" data-settings="sound" aria-label="Sound settings">${panelGlyphs.chevron}</button>
    </div>
    <div id="media"></div>
    <div class="foot">
      <span class="battery" id="panelBattery"></span>
      <button class="icon-button" data-settings="settings" aria-label="All settings" title="Settings">${panelGlyphs.settings}</button>
    </div>`;

  const slider = document.getElementById('volumeSlider');
  slider.addEventListener('pointerdown', () => { volumeDragging = true; });
  slider.addEventListener('pointerup', () => { volumeDragging = false; });
  slider.addEventListener('input', () => {
    showVolume(Number(slider.value), false);
    if (volumeSendTimer) return;
    volumeSendTimer = setTimeout(() => {
      volumeSendTimer = null;
      window.api.systemSet('volume ' + slider.value);
    }, volumeSendMilliseconds);
  });
  // The wheel anywhere on the row nudges the level.
  document.getElementById('volume').addEventListener('wheel', (event) => {
    event.preventDefault();
    const level = Math.max(0, Math.min(100, Number(slider.value) + (event.deltaY < 0 ? 2 : -2)));
    slider.value = String(level);
    showVolume(level, false);
    window.api.systemSet('volume ' + level);
  }, { passive: false });
  document.getElementById('mute').addEventListener('click', () => {
    const muted = !(systemState && systemState.speakers && systemState.speakers.muted);
    if (systemState && systemState.speakers) systemState.speakers.muted = muted;
    updateQuick();
    window.api.systemSet('mute ' + (muted ? 1 : 0));
  });
  panelElement.querySelectorAll('[data-radio]').forEach((button) => button.addEventListener('click', () => {
    const name = button.dataset.radio;
    if (!systemState || systemState[name] === null || systemState[name] === undefined) return;
    systemState[name] = !systemState[name]; // show it at once; the helper's report confirms
    updateQuick();
    window.api.systemSet(`radio ${name} ${systemState[name] ? 1 : 0}`);
  }));
  updateQuick();
}

function tileMarkup(name, label, settingsPage) {
  return `<div class="tile" id="tile-${name}">
    <button class="toggle" data-radio="${name}" aria-pressed="false">${panelGlyphs[name]}<span class="text"><span class="name">${label}</span><span class="detail"></span></span></button>
    <button class="more" data-settings="${settingsPage}" aria-label="${label} settings">${panelGlyphs.chevron}</button>
  </div>`;
}

function updateQuick() {
  if (!document.getElementById('volume')) return;
  const state = systemState || {};

  for (const name of ['wifi', 'bluetooth']) {
    const tile = document.getElementById('tile-' + name);
    const known = state[name] === true || state[name] === false;
    tile.classList.toggle('on', state[name] === true);
    tile.classList.toggle('unavailable', systemState !== null && !known);
    tile.querySelector('.toggle').setAttribute('aria-pressed', String(state[name] === true));
    let detail = !systemState ? '' : !known ? 'Unavailable' : state[name] ? 'On' : 'Off';
    if (name === 'wifi' && state.wifi && wifiState) detail = wifiState.ssid;
    if (name === 'wifi' && !state.wifi && navigator.onLine && known) detail = 'Off · wired';
    tile.querySelector('.detail').textContent = detail;
  }

  const speakers = state.speakers;
  const volumeRow = document.getElementById('volume');
  volumeRow.hidden = systemState !== null && !speakers;
  if (speakers) {
    volumeRow.classList.toggle('muted', speakers.muted);
    document.getElementById('mute').innerHTML = speakers.muted ? panelGlyphs.muted : panelGlyphs.speaker;
    document.getElementById('mute').setAttribute('aria-label', speakers.muted ? 'Unmute' : 'Mute');
    if (!volumeDragging && !volumeSendTimer) showVolume(speakers.volume, true);
  }

  renderMedia(state.media);
  renderPanelBattery();
}

function showVolume(level, moveSlider) {
  const slider = document.getElementById('volumeSlider');
  if (!slider) return;
  if (moveSlider) slider.value = String(level);
  slider.style.setProperty('--fill', level + '%');
  document.getElementById('volumeLevel').textContent = String(level);
}

function renderMedia(media) {
  const holder = document.getElementById('media');
  const key = media ? [media.title, media.artist, media.playing, media.canPrevious, media.canNext, Boolean(media.art)].join('\n') : '';
  if (key === mediaKey) return;
  mediaKey = key;
  if (!media) {
    holder.innerHTML = '';
    return;
  }
  const by = media.artist || media.appName || 'Now playing';
  holder.innerHTML = `<div class="media">
    ${media.art ? `<img class="art" src="${escapeHtml(media.art)}" alt="">` : `<span class="art">${panelGlyphs.music}</span>`}
    <span class="text"><span class="title" title="${escapeHtml(media.title)}">${escapeHtml(media.title)}</span><span class="by">${escapeHtml(by)}</span></span>
    <span class="controls">
      <button class="icon-button" data-media="previous" aria-label="Previous" ${media.canPrevious ? '' : 'disabled'}>${panelGlyphs.previous}</button>
      <button class="icon-button play" data-media="playpause" aria-label="${media.playing ? 'Pause' : 'Play'}">${media.playing ? panelGlyphs.pause : panelGlyphs.play}</button>
      <button class="icon-button" data-media="next" aria-label="Next" ${media.canNext ? '' : 'disabled'}>${panelGlyphs.next}</button>
    </span>
  </div>`;
  holder.querySelectorAll('[data-media]').forEach((button) => button.addEventListener('click', () => window.api.systemSet('media ' + button.dataset.media)));
}

function renderPanelBattery() {
  const holder = document.getElementById('panelBattery');
  if (!holder) return;
  holder.textContent = batteryState ? `Battery ${Math.round(batteryState.level * 100)}%${batteryState.charging ? ' · charging' : ''}` : '';
}

// ---- calendar ----

function renderCalendar() {
  const now = new Date();
  const locale = undefined; // the system's
  const month = calendarMonth;
  const firstWeekday = weekStart();
  const lead = (month.getDay() - firstWeekday + 7) % 7;
  const start = new Date(month.getFullYear(), month.getMonth(), 1 - lead);
  const weekdayNames = Array.from({ length: 7 }, (_, index) => new Date(2024, 0, 7 + ((firstWeekday + index) % 7)).toLocaleDateString(locale, { weekday: 'narrow' }));

  let dates = '';
  for (let index = 0; index < 42; index++) {
    const day = new Date(start.getFullYear(), start.getMonth(), start.getDate() + index);
    const classes = ['date'];
    if (day.getMonth() !== month.getMonth()) classes.push('other');
    if (day.toDateString() === now.toDateString()) classes.push('today');
    dates += `<span class="${classes.join(' ')}">${day.getDate()}</span>`;
  }

  panelElement.innerHTML = `
    <div class="today">
      <span class="day">${escapeHtml(now.toLocaleDateString(locale, { weekday: 'long' }))}</span>
      <span class="full">${escapeHtml(now.toLocaleDateString(locale, { day: 'numeric', month: 'long', year: 'numeric' }))}</span>
    </div>
    <div class="month-head">
      <span class="month-name">${escapeHtml(month.toLocaleDateString(locale, { month: 'long', year: 'numeric' }))}</span>
      <button class="icon-button" data-month="-1" aria-label="Previous month">${panelGlyphs.back}</button>
      <button class="icon-button" data-month="1" aria-label="Next month">${panelGlyphs.chevron}</button>
    </div>
    <div class="days">${weekdayNames.map((name) => `<span class="weekday">${escapeHtml(name)}</span>`).join('')}${dates}</div>
    <div class="notes-head" id="notesHead"></div>
    <div class="notes" id="notes"></div>
    <div class="foot">
      <button class="link" data-settings="datetime">Date and time settings</button>
      <button class="link" data-settings="notifications">Notification settings</button>
    </div>`;

  panelElement.querySelectorAll('[data-month]').forEach((button) => button.addEventListener('click', () => {
    calendarMonth = new Date(calendarMonth.getFullYear(), calendarMonth.getMonth() + Number(button.dataset.month), 1);
    renderCalendar();
    reportHitRegions();
  }));
  renderNotes();
}

// ---- notifications ----

// Windows' own notifications (from its notification centre, read by the helper) and the
// app's own toasts, newest first. A click opens the app that sent one; x dismisses it, from
// Windows too.
let windowsNotifications = [];

function notesList() {
  const ours = (panel.notifications || []).map((note) => ({ source: 'ours', id: String(note.time), app: 'Custom Start', title: note.title, body: note.text, time: note.time, error: note.kind === 'error' }));
  const theirs = windowsNotifications.map((note) => ({ source: 'windows', ...note, id: String(note.id) }));
  return [...ours, ...theirs].sort((first, second) => second.time - first.time);
}

function renderNotes() {
  const head = document.getElementById('notesHead');
  const list = document.getElementById('notes');
  if (!head || !list) return;
  const notes = notesList();
  head.innerHTML = `<span>Notifications</span>${notes.length ? '<button class="link" id="clearNotes">Clear all</button>' : ''}`;
  const scroll = list.scrollTop;
  list.innerHTML = notes.length
    ? notes.map((note) => `<div class="note${note.error ? ' error' : ''}${note.appId ? ' opens' : ''}" data-source="${note.source}" data-id="${escapeHtml(note.id)}" data-app="${escapeHtml(note.appId || '')}">
        <div class="note-app">
          ${note.icon ? `<img src="${escapeHtml(note.icon)}" alt="">` : `<span class="note-initial">${escapeHtml((note.app || '?').slice(0, 1))}</span>`}
          <span class="note-app-name">${escapeHtml(note.app || 'Notification')}</span>
          <span class="when">${escapeHtml(timeAgo(note.time))}</span>
          <button class="note-dismiss" aria-label="Dismiss"><svg class="i" viewBox="0 0 16 16"><path d="m4.5 4.5 7 7M11.5 4.5l-7 7"/></svg></button>
        </div>
        <div class="note-title">${escapeHtml(note.title)}</div>
        ${note.body ? `<div class="note-text">${escapeHtml(note.body)}</div>` : ''}
      </div>`).join('')
    : '<div class="empty">No new notifications</div>';
  list.scrollTop = scroll;

  list.querySelectorAll('.note').forEach((element) => {
    element.querySelector('.note-dismiss').addEventListener('click', (event) => {
      event.stopPropagation();
      dismissNote(element.dataset.source, element.dataset.id);
    });
    element.addEventListener('click', () => {
      if (element.dataset.app) window.api.openNotificationApp(element.dataset.app);
    });
  });
  const clear = document.getElementById('clearNotes');
  if (clear) clear.addEventListener('click', () => {
    window.api.clearNotifications();
    panel.notifications = [];
    windowsNotifications = [];
    renderNotes();
    reportHitRegions();
  });
}

function dismissNote(source, id) {
  window.api.dismissNotification(source, id);
  if (source === 'ours') panel.notifications = (panel.notifications || []).filter((note) => String(note.time) !== id);
  else windowsNotifications = windowsNotifications.filter((note) => String(note.id) !== id);
  renderNotes();
  reportHitRegions();
}

let lastNotesKey = '';
window.api.onWindowsNotifications((items) => {
  const key = items.map((note) => note.id).join(',');
  windowsNotifications = items;
  if (key === lastNotesKey) return; // polled: redraw only on change
  lastNotesKey = key;
  if (panel && panel.kind === 'calendar') {
    renderNotes();
    reportHitRegions();
    markNotificationsSeen();
  }
  showUnseen();
});

// A dot on the clock while a notification has come in since the calendar was last opened.
const seenKey = 'notifications-seen';
let seenUntil = Number(readStored(seenKey)) || Date.now();

function readStored(key) {
  try {
    return localStorage.getItem(key);
  } catch {
    return null;
  }
}

function markNotificationsSeen() {
  seenUntil = Date.now();
  try {
    localStorage.setItem(seenKey, String(seenUntil));
  } catch {
    // Not kept: the dot may come back after a restart.
  }
  showUnseen();
}

function showUnseen() {
  const newest = Math.max(0, ...windowsNotifications.map((note) => note.time));
  document.getElementById('clock').classList.toggle('unseen', newest > seenUntil);
}

// The first day of the week for the system's region (Monday unless it says otherwise).
function weekStart() {
  try {
    const info = new Intl.Locale(navigator.language).weekInfo || new Intl.Locale(navigator.language).getWeekInfo();
    return info.firstDay % 7;
  } catch {
    return 1;
  }
}

function timeAgo(time) {
  const minutes = Math.round((Date.now() - time) / 60000);
  if (minutes < 1) return 'now';
  if (minutes < 60) return minutes + ' min';
  const hours = Math.round(minutes / 60);
  if (hours < 24) return hours + ' h';
  return new Date(time).toLocaleDateString(undefined, { day: 'numeric', month: 'short' });
}

// Settings links in either panel.
panelElement.addEventListener('click', (event) => {
  const link = event.target.closest('[data-settings]');
  if (link) window.api.openSettings(link.dataset.settings);
});

document.addEventListener('keydown', (event) => {
  if (event.key === 'Escape' && panel && !renamingId) window.api.closePanel();
});

// A press anywhere but the panel and its own buttons closes it, as Windows does. On the bar
// the press goes on to do its job; in the empty space around, it only closes.
document.addEventListener('pointerdown', (event) => {
  if (panel && !event.target.closest('#panel, #quick, #clock')) window.api.closePanel();
}, true);

document.getElementById('home').addEventListener('click', () => window.api.taskbarHome());
document.getElementById('quick').addEventListener('click', () => togglePanel('quick'));
document.getElementById('clock').addEventListener('click', () => togglePanel('calendar'));
document.getElementById('peek').addEventListener('click', () => togglePanel('tray'));

window.addEventListener('online', renderNetwork);
window.addEventListener('offline', renderNetwork);

window.api.onTaskbarState(applyState);

// The bar changes width as pills come and go, and slides away when auto-hidden: its live
// area follows.
new ResizeObserver(() => {
  alignPanel();
  reportHitRegions();
}).observe(bar);
bar.addEventListener('transitionend', reportHitRegions);
window.addEventListener('resize', reportHitRegions);
window.api.onTaskbarHidden((hidden) => {
  dock.classList.toggle('hidden', hidden);
  reportHitRegions();
  if (hidden && panel) window.api.closePanel();
  if (hidden) {
    closePopover();
    hidePreviews();
  }
});

renderClock();
renderNetwork();
renderBattery();
reportHitRegions();
setInterval(renderClock, clockRefreshMilliseconds);
