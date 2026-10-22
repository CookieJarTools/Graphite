// Files: tabs, sidebar, path-and-search field, sortable list with three densities.
// The main process (files-main.js) does all file system work.

const $ = (selector) => document.querySelector(selector);

const RECENTS = 'recents:';
const maximumStaggeredRows = 12;

const icons = {
  folder: '<svg class="glyph" viewBox="0 0 16 16"><path d="M2.5 4.5h4l1.5 1.5h5.5v6.5h-11z"/></svg>',
  file: '<svg class="glyph" viewBox="0 0 16 16"><path d="M4 2.5h5.5L12 5v8.5H4z"/><path d="M9.5 2.5V5H12"/></svg>',
  image: '<svg class="glyph" viewBox="0 0 16 16"><rect x="2.5" y="3" width="11" height="10" rx="1.5"/><circle cx="6" cy="6.5" r="1"/><path d="m3 12 3.5-3.5 2.5 2.5 1.5-1.5L13 12"/></svg>',
  code: '<svg class="glyph" viewBox="0 0 16 16"><path d="M4 2.5h5.5L12 5v8.5H4z"/><path d="m7 8-1.2 1.2L7 10.4M9 8l1.2 1.2L9 10.4"/></svg>',
  media: '<svg class="glyph" viewBox="0 0 16 16"><rect x="2" y="3.5" width="12" height="9" rx="1.5"/><path d="m6.5 6 3.5 2-3.5 2z"/></svg>',
  archive: '<svg class="glyph" viewBox="0 0 16 16"><rect x="2.5" y="3" width="11" height="10" rx="1.5"/><path d="M8 3v5M7 4.5h2M7 6.5h2"/></svg>',
  app: '<svg class="glyph" viewBox="0 0 16 16"><rect x="2.5" y="2.5" width="4.5" height="4.5" rx="1"/><rect x="9" y="2.5" width="4.5" height="4.5" rx="1"/><rect x="2.5" y="9" width="4.5" height="4.5" rx="1"/><rect x="9" y="9" width="4.5" height="4.5" rx="1"/></svg>',
  clock: '<svg class="glyph" viewBox="0 0 16 16"><circle cx="8" cy="8" r="5.5"/><path d="M8 5v3l2 1.5"/></svg>',
  drive: '<svg class="glyph" viewBox="0 0 16 16"><rect x="2" y="5" width="12" height="6" rx="1.5"/><path d="M11 8h0"/></svg>',
  chevron: '<svg class="glyph" viewBox="0 0 16 16"><path d="m5 6.5 3 3 3-3"/></svg>',
  close: '<svg class="glyph" viewBox="0 0 16 16"><path d="m4.5 4.5 7 7M11.5 4.5l-7 7"/></svg>',
};

const kinds = [
  [/\.(png|jpe?g|gif|webp|bmp|svg|ico|psd|tiff?)$/i, 'image', 'Image'],
  [/\.(mp4|mkv|mov|avi|webm|mp3|wav|flac|ogg|m4a)$/i, 'media', 'Media'],
  [/\.(zip|rar|7z|tar|gz|unitypackage)$/i, 'archive', 'Archive'],
  [/\.(exe|msi|lnk|bat|cmd|ps1)$/i, 'app', 'Application'],
  [/\.(js|ts|tsx|jsx|cs|cpp|c|h|py|json|html|css|md|xml|yml|yaml|sh|ahk|shader|hlsl)$/i, 'code', null],
];

const win = $('#win');
const listElement = $('#list');
const pathInput = $('#pathInput');

let tabs = [];
let activeTabId = 0;
let nextTabId = 1;
let entries = [];
let visible = [];
let selected = new Set();
let anchorIndex = -1;
let sort = { key: 'name', ascending: true };
let filter = '';
let clipboardFiles = null; // { mode: 'copy' | 'move', paths }
let places = [];
let draggingTabId = null;
let tabDetached = false;
let slotTitle = null; // a tab from elsewhere hovering over this strip

// ---------- helpers ----------

function escapeHtml(text) {
  return String(text).replace(/[&<>"]/g, (character) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' })[character]);
}

const activeTab = () => tabs.find((tab) => tab.id === activeTabId);
const currentPath = () => activeTab().history[activeTab().index];

function folderName(folder) {
  if (folder === RECENTS) return 'Recents';
  const trimmed = folder.replace(/[\\/]+$/, '');
  return trimmed.split(/[\\/]/).pop() || folder;
}

function parentOf(folder) {
  if (folder === RECENTS) return null;
  const trimmed = folder.replace(/[\\/]+$/, '');
  const index = trimmed.lastIndexOf('\\');
  if (index < 0) return null;
  return index === 2 ? trimmed.slice(0, 3) : trimmed.slice(0, index); // "C:\" keeps its slash
}

function kindOf(entry) {
  if (entry.isDir) return { icon: 'folder', type: 'Folder' };
  for (const [pattern, icon, type] of kinds) {
    if (pattern.test(entry.name)) return { icon, type: type || entry.name.split('.').pop().toUpperCase() + ' file' };
  }
  const extension = entry.name.includes('.') ? entry.name.split('.').pop().toUpperCase() : '';
  return { icon: 'file', type: extension ? extension + ' file' : 'File' };
}

function formatSize(bytes) {
  if (bytes < 1024) return bytes + ' B';
  const units = ['KB', 'MB', 'GB', 'TB'];
  let value = bytes / 1024;
  let unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  return (value < 10 ? value.toFixed(1) : Math.round(value)) + ' ' + units[unit];
}

function formatDate(timestamp) {
  const date = new Date(timestamp);
  const today = new Date();
  const time = date.toLocaleTimeString(undefined, { hour: '2-digit', minute: '2-digit' });
  if (date.toDateString() === today.toDateString()) return 'Today, ' + time;
  const yesterday = new Date(today);
  yesterday.setDate(today.getDate() - 1);
  if (date.toDateString() === yesterday.toDateString()) return 'Yesterday, ' + time;
  return date.toLocaleDateString(undefined, { day: 'numeric', month: 'short', year: date.getFullYear() === today.getFullYear() ? undefined : 'numeric' });
}

let messageTimer = null;

function showMessage(text, isError) {
  const message = $('#message');
  message.textContent = text;
  message.classList.toggle('error', Boolean(isError));
  clearTimeout(messageTimer);
  messageTimer = setTimeout(() => { message.textContent = ''; }, 4000);
}

// ---------- sidebar ----------

async function renderSidebar() {
  const sidebar = await window.api.files.sidebar();
  places = sidebar.places;
  const section = (title, items) =>
    `<button class="sec" aria-expanded="true">${title}${icons.chevron}</button><div class="group">`
    + items.map((item) => `<button class="nav" data-path="${escapeHtml(item.path)}">${icons[item.icon]}${escapeHtml(item.name)}</button>`).join('')
    + '</div>';
  $('#nav').innerHTML =
    section('Quick access', [{ name: 'Recents', path: RECENTS, icon: 'clock' }, ...places.map((place) => ({ ...place, icon: 'folder' }))])
    + section('Devices', sidebar.drives.map((drive) => ({ name: `Local Disk (${drive.slice(0, 2)})`, path: drive, icon: 'drive' })));
  markSidebar();
}

function markSidebar() {
  const folder = currentPath().toLowerCase();
  document.querySelectorAll('.nav').forEach((item) => item.classList.toggle('on', item.dataset.path.toLowerCase() === folder));
}

$('#nav').addEventListener('click', (event) => {
  const section = event.target.closest('.sec');
  if (section) {
    const expanded = section.getAttribute('aria-expanded') === 'true';
    section.setAttribute('aria-expanded', String(!expanded));
    section.nextElementSibling.hidden = expanded;
    return;
  }
  const item = event.target.closest('.nav');
  if (item) navigate(item.dataset.path);
});

// ---------- tabs ----------

function renderTabs(enteringId) {
  $('.top').classList.toggle('target', Boolean(slotTitle));
  $('#tabs').innerHTML = tabs.map((tab) => {
    const dragState = tab.id === draggingTabId ? (tabDetached ? ' detached' : ' dragging') : '';
    return `<div class="tab${tab.id === activeTabId ? ' on' : ''}${tab.id === enteringId ? ' entering' : ''}${dragState}" data-id="${tab.id}">`
      + `${tab.history[tab.index] === RECENTS ? icons.clock : icons.folder}<span>${escapeHtml(folderName(tab.history[tab.index]))}</span>`
      + `<button class="x" title="Close tab (Ctrl+W)">${icons.close}</button></div>`;
  }).join('') + (slotTitle ? `<div class="tab slot">${icons.folder}<span>${escapeHtml(slotTitle)}</span></div>` : '');
}

function openTab(folder, history, index) {
  const tab = { id: nextTabId++, history: history || [folder], index: history ? index : 0, scroll: 0 };
  tabs.push(tab);
  activeTabId = tab.id;
  renderTabs(tab.id);
  load();
}

function closeTab(id) {
  if (tabs.length === 1) {
    window.api.files.window('close');
    return;
  }
  const index = tabs.findIndex((tab) => tab.id === id);
  tabs.splice(index, 1);
  if (id === activeTabId) activeTabId = tabs[Math.min(index, tabs.length - 1)].id;
  renderTabs();
  load();
}

function selectTab(id) {
  activeTab().scroll = listElement.scrollTop;
  activeTabId = id;
  renderTabs();
  load(true);
}

// Press on a tab: release in place selects it. Dragging slides the tab along the strip
// under the pointer, reordering as it passes the others, and it stays attached anywhere
// in the window's top area (tab strip and toolbar). Leave that area and the tab tears
// off: it floats under the pointer, outside the window if need be, until it is dropped
// on another Files window's strip, or anywhere else for a window of its own.
const dragThreshold = 5;
const reattachMargin = 8; // a torn-off tab rejoins only over the strip itself, so the edge never flickers

$('#tabs').addEventListener('pointerdown', (event) => {
  const tabElement = event.target.closest('.tab:not(.slot)');
  if (!tabElement || event.button !== 0) return;
  const id = Number(tabElement.dataset.id);
  if (event.target.closest('.x')) {
    closeTab(id);
    return;
  }

  const tabsElement = $('#tabs');
  const grabRect = tabElement.getBoundingClientRect();
  const grab = { x: event.clientX - grabRect.left, y: event.clientY - grabRect.top, width: grabRect.width };
  const startX = event.clientX;
  const startY = event.clientY;
  let moved = false;
  tabsElement.setPointerCapture(event.pointerId);

  const draggedTab = () => tabs.find((tab) => tab.id === id);

  // The tab sits under the pointer, kept within the strip.
  const followPointer = (pointerX) => {
    const element = tabsElement.querySelector(`.tab[data-id="${id}"]`);
    if (!element) return;
    element.style.transform = 'none';
    const natural = element.getBoundingClientRect().left;
    const strip = tabsElement.getBoundingClientRect();
    const left = Math.min(Math.max(pointerX - grab.x, strip.left), strip.right - element.offsetWidth);
    element.style.transform = `translateX(${left - natural}px)`;
  };

  const isInTopArea = (moveEvent) => moveEvent.clientX >= 0 && moveEvent.clientX <= innerWidth
    && moveEvent.clientY >= 0 && moveEvent.clientY <= $('.bar').getBoundingClientRect().bottom;

  const onMove = (moveEvent) => {
    if (!moved && Math.hypot(moveEvent.clientX - startX, moveEvent.clientY - startY) < dragThreshold) return;
    if (!moved) {
      moved = true;
      draggingTabId = id;
      renderTabs();
    }

    const overStrip = isInTopArea(moveEvent) && moveEvent.clientY <= $('.top').getBoundingClientRect().bottom + reattachMargin;
    const detached = tabDetached ? !overStrip : !isInTopArea(moveEvent);
    if (detached !== tabDetached) {
      tabDetached = detached;
      renderTabs();
      if (!detached) window.api.files.tabDrag(null);
    }

    if (detached) {
      const tab = draggedTab();
      window.api.files.tabDrag({ x: moveEvent.screenX, y: moveEvent.screenY, grab, title: folderName(tab.history[tab.index]) });
      return;
    }
    if (reorderTab(id, moveEvent.clientX)) renderTabs();
    followPointer(moveEvent.clientX);
  };

  const onUp = async (upEvent) => {
    tabsElement.removeEventListener('pointermove', onMove);
    tabsElement.removeEventListener('pointerup', onUp);
    tabsElement.removeEventListener('pointercancel', onUp);
    const wasDetached = tabDetached;
    draggingTabId = null;
    tabDetached = false;
    if (!moved) {
      selectTab(id);
      return;
    }
    if (wasDetached) {
      const tab = draggedTab();
      const result = await window.api.files.tabDrop({
        x: upEvent.screenX,
        y: upEvent.screenY,
        tabCount: tabs.length,
        tab: { history: tab.history, index: tab.index },
      });
      if (result !== 'none') {
        closeTab(id);
        return;
      }
    }
    renderTabs();
  };

  tabsElement.addEventListener('pointermove', onMove);
  tabsElement.addEventListener('pointerup', onUp);
  tabsElement.addEventListener('pointercancel', onUp);
});

// Moves the dragged tab to wherever the pointer sits among the others. True if it moved.
function reorderTab(id, pointerX) {
  const others = [...$('#tabs').querySelectorAll('.tab:not(.slot)')].filter((element) => Number(element.dataset.id) !== id);
  const targetIndex = others.filter((element) => {
    const rect = element.getBoundingClientRect();
    return rect.left + rect.width / 2 < pointerX;
  }).length;
  const currentIndex = tabs.findIndex((tab) => tab.id === id);
  if (currentIndex === targetIndex) return false;
  const [tab] = tabs.splice(currentIndex, 1);
  tabs.splice(targetIndex, 0, tab);
  return true;
}

window.api.files.onDropSlot((title) => {
  const next = title || null;
  if (next === slotTitle) return; // already showing it: leave the slot (and its animation) alone
  slotTitle = next;
  renderTabs();
});

// A tab dragged in from another Files window.
window.api.files.onAdoptTab((tab) => {
  slotTitle = null;
  openTab(tab.history[tab.index], tab.history, tab.index);
});

// This window was dropped onto another one, which takes all its tabs.
window.api.files.onExportTabs(() => {
  window.api.files.exportedTabs(tabs.map((tab) => ({ history: tab.history, index: tab.index })));
});

$('#tabs').addEventListener('auxclick', (event) => {
  const tab = event.target.closest('.tab');
  if (tab && event.button === 1) closeTab(Number(tab.dataset.id));
});

$('#newTab').addEventListener('click', () => openTab(currentPath()));

// ---------- navigation ----------

function navigate(folder) {
  const tab = activeTab();
  if (tab.history[tab.index] === folder) return;
  tab.history = tab.history.slice(0, tab.index + 1);
  tab.history.push(folder);
  tab.index++;
  tab.scroll = 0;
  load();
}

function goBack() {
  if (activeTab().index === 0) return;
  activeTab().index--;
  load();
}

function goForward() {
  if (activeTab().index >= activeTab().history.length - 1) return;
  activeTab().index++;
  load();
}

function goUp() {
  const parent = parentOf(currentPath());
  if (parent) navigate(parent);
}

// Several loads can overlap (start-up, a tab, a refresh); only the latest may draw the list,
// or an older one finishing late would wipe what came after it, such as a new folder's
// rename field.
let loadGeneration = 0;

async function load(keepScroll) {
  const generation = ++loadGeneration;
  const folder = currentPath();
  filter = '';
  pathInput.value = folder === RECENTS ? '' : folder;
  pathInput.placeholder = folder === RECENTS ? 'Search recent files and folders' : 'Search this folder, or type a path';
  document.title = `${folderName(folder)} - Files`;
  renderTabs();
  markSidebar();
  $('#back').disabled = activeTab().index === 0;
  $('#forward').disabled = activeTab().index >= activeTab().history.length - 1;
  $('#up').disabled = !parentOf(folder);
  let listed;
  try {
    listed = await window.api.files.list(folder);
  } catch (error) {
    if (generation !== loadGeneration) return;
    listed = [];
    showMessage(`Can't open ${folderName(folder)}: ${error.message.replace(/^Error invoking remote method '[^']+': (Error: )?/, '')}`, true);
  }
  if (generation !== loadGeneration) return;
  entries = listed;
  selected.clear();
  anchorIndex = -1;
  renderList(true);
  listElement.scrollTop = keepScroll ? activeTab().scroll : 0;
}

// ---------- list ----------

function sortEntries(items) {
  const direction = sort.ascending ? 1 : -1;
  const byName = (first, second) => first.name.localeCompare(second.name, undefined, { numeric: true, sensitivity: 'base' });
  const compare = {
    name: byName,
    type: (first, second) => kindOf(first).type.localeCompare(kindOf(second).type) || byName(first, second),
    size: (first, second) => first.size - second.size || byName(first, second),
    modified: (first, second) => first.modified - second.modified || byName(first, second),
  }[sort.key];
  const sorted = [...items].sort((first, second) => direction * compare(first, second));
  // Folders stay on top in name order, as in Explorer; Recents is newest first.
  if (currentPath() === RECENTS && sort.key === 'name' && sort.ascending) return [...items].sort((first, second) => second.modified - first.modified);
  return [...sorted.filter((item) => item.isDir), ...sorted.filter((item) => !item.isDir)];
}

function renderList(fresh) {
  const lowerFilter = filter.toLowerCase();
  visible = sortEntries(entries.filter((entry) => !lowerFilter || entry.name.toLowerCase().includes(lowerFilter)));
  const cutPaths = clipboardFiles && clipboardFiles.mode === 'move' ? new Set(clipboardFiles.paths) : new Set();

  listElement.innerHTML = visible.length
    ? visible.map((entry, index) => {
      const kind = kindOf(entry);
      const detail = entry.isDir ? (entry.folder || 'Folder') : (entry.folder || entry.path);
      const classes = ['row', selected.has(entry.path) ? 'sel' : '', cutPaths.has(entry.path) ? 'cut' : ''].join(' ').trim();
      return `<div class="${classes}" data-index="${index}" draggable="true" style="--i:${Math.min(index, maximumStaggeredRows)}">`
        + `<span class="name">${icons[kind.icon]}<span class="label"><span class="title">${escapeHtml(entry.name)}</span><span class="detail">${escapeHtml(detail)}</span></span></span>`
        + `<span class="meta type">${kind.type}</span><span class="meta size">${entry.isDir ? '' : formatSize(entry.size)}</span>`
        + `<span class="meta date">${entry.modified ? formatDate(entry.modified) : ''}</span></div>`;
    }).join('')
    : `<div class="empty">${filter ? `Nothing here matches "${escapeHtml(filter)}".` : 'This folder is empty.'}</div>`;

  if (fresh) {
    listElement.classList.remove('fresh');
    void listElement.offsetWidth;
    listElement.classList.add('fresh');
  }
  const folders = visible.filter((entry) => entry.isDir).length;
  $('#count').textContent = `${visible.length} items` + (selected.size ? `, ${selected.size} selected` : '') + (folders && folders !== visible.length ? ` (${folders} folders)` : '');
  document.querySelectorAll('.cols button').forEach((button) => {
    button.classList.toggle('sorted', button.dataset.sort === sort.key);
    button.classList.toggle('asc', button.dataset.sort === sort.key && sort.ascending);
  });
  if (win.dataset.density === 'spacious') fillFolderCounts();
}

// Spacious rows show a folder's item count, read lazily for the folders on screen.
async function fillFolderCounts() {
  const rows = [...listElement.querySelectorAll('.row')];
  for (const row of rows) {
    const entry = visible[Number(row.dataset.index)];
    if (!entry || !entry.isDir) continue;
    const count = await window.api.files.count(entry.path);
    const detail = row.querySelector('.detail');
    if (detail && count !== null) detail.textContent = `${count} item${count === 1 ? '' : 's'}${entry.folder ? ', ' + entry.folder : ''}`;
  }
}

function updateSelection() {
  listElement.querySelectorAll('.row').forEach((row) => row.classList.toggle('sel', selected.has(visible[Number(row.dataset.index)].path)));
  $('#count').textContent = `${visible.length} items` + (selected.size ? `, ${selected.size} selected` : '');
}

function selectIndex(index, event) {
  const entry = visible[index];
  if (!entry) return;
  if (event && event.shiftKey && anchorIndex >= 0) {
    const [from, to] = [Math.min(anchorIndex, index), Math.max(anchorIndex, index)];
    if (!event.ctrlKey) selected.clear();
    for (let rowIndex = from; rowIndex <= to; rowIndex++) selected.add(visible[rowIndex].path);
  } else if (event && event.ctrlKey) {
    if (selected.has(entry.path)) selected.delete(entry.path);
    else selected.add(entry.path);
    anchorIndex = index;
  } else {
    selected = new Set([entry.path]);
    anchorIndex = index;
  }
  updateSelection();
  const row = listElement.querySelector(`.row[data-index="${index}"]`);
  if (row) row.scrollIntoView({ block: 'nearest' });
}

function selectedPaths() {
  return visible.filter((entry) => selected.has(entry.path)).map((entry) => entry.path);
}

function openEntry(entry) {
  if (entry.isDir) navigate(entry.path);
  else window.api.files.open(entry.path);
}

listElement.addEventListener('mousedown', (event) => {
  const row = event.target.closest('.row');
  if (!row) {
    // A press on empty space, left or right, clears the selection (a right-click then gets
    // the folder's own menu, as in Explorer).
    if (event.button === 0 || event.button === 2) {
      selected.clear();
      updateSelection();
    }
    return;
  }
  const index = Number(row.dataset.index);
  if (event.button === 2 && selected.has(visible[index].path)) return; // keep the selection for its menu
  selectIndex(index, event);
});

listElement.addEventListener('dblclick', (event) => {
  const row = event.target.closest('.row');
  if (row) openEntry(visible[Number(row.dataset.index)]);
});

listElement.addEventListener('dragstart', (event) => {
  event.preventDefault();
  const paths = selectedPaths();
  if (paths.length) window.api.files.drag(paths);
});

listElement.addEventListener('contextmenu', (event) => {
  event.preventDefault();
  showContextMenu(event.clientX, event.clientY);
});

// ---------- context menu ----------

// From the keyboard (Ctrl+K): beside the first selected row, or the list's top corner.
function keyboardMenuPoint() {
  const row = listElement.querySelector('.row.sel') || listElement;
  const rect = row.getBoundingClientRect();
  return { x: rect.left + 48, y: rect.top + Math.min(rect.height, 32) };
}

// Where the menu opens: the right-click, or the selected row for the keyboard's menu key.
let menuPoint = { x: 0, y: 0 };

const menuGlyphs = {
  open: '<path d="M2.5 4.5h4l1.5 1.5h5.5v6.5h-11z"/>',
  'open-tab': '<rect x="2.5" y="4" width="11" height="9" rx="1.5"/><path d="M2.5 6.5h11M6 4v2.5"/>',
  'open-window': '<rect x="2.5" y="3" width="11" height="10" rx="1.5"/><path d="M2.5 5.5h11"/>',
  cut: '<circle cx="4.5" cy="11.5" r="2"/><circle cx="11.5" cy="11.5" r="2"/><path d="M6 10 12 2.5M10 10 4 2.5"/>',
  copy: '<rect x="5.5" y="5.5" width="8" height="8" rx="1.5"/><path d="M10.5 3.5v-1h-8v8h1"/>',
  paste: '<rect x="3.5" y="3" width="9" height="11" rx="1.5"/><path d="M6 3V2h4v1"/>',
  rename: '<path d="M2.5 11.5 10 4l2 2-7.5 7.5h-2zM9 5l2 2"/>',
  recycle: '<path d="M3 4.5h10M6.5 4.5V3h3v1.5M4.5 4.5l.5 9h6l.5-9"/>',
  'copy-path': '<path d="M6.5 9.5 9.5 6.5M7 4.5l1-1a2.5 2.5 0 0 1 3.5 3.5l-1 1M9 11.5l-1 1A2.5 2.5 0 0 1 4.5 9l1-1"/>',
  copyaspath: '<path d="M6.5 9.5 9.5 6.5M7 4.5l1-1a2.5 2.5 0 0 1 3.5 3.5l-1 1M9 11.5l-1 1A2.5 2.5 0 0 1 4.5 9l1-1"/>',
  reveal: '<path d="M2.5 4.5h4l1.5 1.5h5.5v6.5h-11z"/><path d="m7 9.5 2-2-2-2"/>',
  link: '<path d="M5.5 10.5 10.5 5.5M6.5 5.5h4v4"/><rect x="2.5" y="2.5" width="11" height="11" rx="2"/>',
  properties: '<circle cx="8" cy="8" r="5.5"/><path d="M8 7.5v3.5M8 5h0"/>',
  'windows.modernshare': '<path d="M8 2.5v8M5 5.5l3-3 3 3M3.5 9v3.5h9V9"/>',
  'refresh-view': '<path d="M12.5 8a4.5 4.5 0 1 1-1.3-3.2M12.5 3v2.5H10"/>',
  'new-folder': '<path d="M2.5 4.5h4l1.5 1.5h5.5v6.5h-11zM8 8v3M6.5 9.5h3"/>',
};

function withGlyphs(items) {
  return items.map((item) => {
    const name = item.action || item.verb;
    const glyph = !item.icon && menuGlyphs[name] ? `<svg viewBox="0 0 16 16">${menuGlyphs[name]}</svg>` : null;
    return { ...item, glyph, children: item.children && withGlyphs(item.children) };
  });
}

window.api.files.onContextMenu(({ session, items }) => {
  ContextMenu.show(withGlyphs(items), menuPoint.x, menuPoint.y, {
    // The app's own items run here; Windows' items run in the helper.
    onPick: (item) => {
      if (item.action) {
        runMenuAction(item.action);
        if (session !== null) window.api.files.menuDone(session, 0);
      } else if (session !== null) {
        window.api.files.menuDone(session, item.id);
      }
    },
    onClose: () => {
      if (session !== null) window.api.files.menuDone(session, 0);
    },
  });
});

// ---------- actions ----------

function startRename() {
  const paths = selectedPaths();
  if (paths.length !== 1 || currentPath() === RECENTS) return;
  const index = visible.findIndex((entry) => entry.path === paths[0]);
  const row = listElement.querySelector(`.row[data-index="${index}"]`);
  if (!row) return;
  const title = row.querySelector('.title');
  const entry = visible[index];
  const input = document.createElement('input');
  input.className = 'rename';
  input.value = entry.name;
  title.replaceWith(input);
  input.focus();
  // Select the name without its extension, like Explorer.
  const dot = entry.isDir ? -1 : entry.name.lastIndexOf('.');
  input.setSelectionRange(0, dot > 0 ? dot : entry.name.length);

  let done = false;
  const finish = async (commit) => {
    if (done) return;
    done = true;
    const newName = input.value.trim();
    if (commit && newName && newName !== entry.name) {
      try {
        const newPath = await window.api.files.rename(entry.path, newName);
        await load(true);
        selected = new Set([newPath]);
        updateSelection();
        return;
      } catch (error) {
        showMessage(error.message.replace(/^Error invoking remote method '[^']+': (Error: )?/, ''), true);
      }
    }
    renderList(false);
    listElement.focus();
  };
  input.addEventListener('keydown', (event) => {
    event.stopPropagation();
    if (event.key === 'Enter') finish(true);
    if (event.key === 'Escape') finish(false);
  });
  input.addEventListener('blur', () => finish(true));
}

async function newFolder() {
  if (currentPath() === RECENTS) return;
  try {
    const created = await window.api.files.mkdir(currentPath());
    await load(true);
    selected = new Set([created]);
    updateSelection();
    startRename();
  } catch (error) {
    showMessage(`Couldn't create a folder here: ${error.message}`, true);
  }
}

async function recycle() {
  const paths = selectedPaths();
  if (!paths.length) return;
  try {
    await window.api.files.trash(paths);
    showMessage(`${paths.length === 1 ? 'Moved 1 item' : `Moved ${paths.length} items`} to the Recycle Bin`);
  } catch (error) {
    showMessage(`Couldn't recycle: ${error.message}`, true);
  }
  load(true);
}

function copySelection(mode) {
  const paths = selectedPaths();
  if (!paths.length) return;
  clipboardFiles = { mode, paths };
  window.api.files.setClipboard(mode, paths); // Explorer and the shell's own Paste see them too
  showMessage(`${mode === 'copy' ? 'Copied' : 'Cut'} ${paths.length} item${paths.length === 1 ? '' : 's'}`);
  renderList(false);
}

async function pasteHere() {
  if (!clipboardFiles || currentPath() === RECENTS) return;
  try {
    await window.api.files.paste(clipboardFiles.mode, clipboardFiles.paths, currentPath());
    if (clipboardFiles.mode === 'move') clipboardFiles = null;
  } catch (error) {
    showMessage(`Couldn't paste: ${error.message}`, true);
  }
  load(true);
}

// ---------- context menu ----------

function showContextMenu(x, y) {
  menuPoint = x === undefined ? keyboardMenuPoint() : { x, y };
  const paths = selectedPaths();
  const single = paths.length === 1 ? visible.find((entry) => entry.path === paths[0]) : null;
  window.api.files.menu({
    paths,
    folder: currentPath(),
    hasSelection: paths.length > 0,
    single: Boolean(single),
    isDir: Boolean(single && single.isDir),
    canPaste: Boolean(clipboardFiles) && currentPath() !== RECENTS,
    inRecents: currentPath() === RECENTS,
  });
}

window.api.files.onMenu((action) => runMenuAction(action));

function runMenuAction(action) {
  const paths = selectedPaths();
  const single = paths.length === 1 ? visible.find((entry) => entry.path === paths[0]) : null;
  switch (action) {
    case 'open': if (single) openEntry(single); break;
    case 'open-tab': if (single) openTab(single.path); break;
    case 'open-window': if (single) window.api.files.newWindow(single.path); break;
    case 'reveal': if (single) window.api.files.reveal(single.path); break;
    case 'copy-path': if (single) window.api.files.copyPath(single.path); break;
    case 'rename': startRename(); break;
    case 'copy': copySelection('copy'); break;
    case 'cut': copySelection('move'); break;
    case 'paste': pasteHere(); break;
    case 'recycle': recycle(); break;
    case 'new-folder': newFolder(); break;
    case 'refresh': load(true); setTimeout(() => load(true), 1500); break; // a shell command may finish a moment later
    case 'refresh-view': load(true); break;
  }
}

// ---------- toolbar ----------

$('#back').addEventListener('click', goBack);
$('#forward').addEventListener('click', goForward);
$('#up').addEventListener('click', goUp);

document.querySelectorAll('[data-window]').forEach((button) => button.addEventListener('click', () => window.api.files.window(button.dataset.window)));

document.querySelectorAll('.density button').forEach((button) => button.addEventListener('click', () => setDensity(button.dataset.density)));

function setDensity(density) {
  win.dataset.density = density;
  document.querySelectorAll('.density button').forEach((button) => button.setAttribute('aria-pressed', String(button.dataset.density === density)));
  window.api.files.setDensity(density);
  renderList(true);
}

$('#cols').addEventListener('click', (event) => {
  const button = event.target.closest('button');
  if (!button) return;
  sort = { key: button.dataset.sort, ascending: sort.key === button.dataset.sort ? !sort.ascending : true };
  renderList(false);
});

// The field is both the path and a filter: text that looks like a path navigates on
// Enter, anything else filters the current folder as you type.
const looksLikePath = (text) => /^([a-z]:[\\/]?|\\\\|%)/i.test(text);

pathInput.addEventListener('focus', () => pathInput.select());
pathInput.addEventListener('input', () => {
  const text = pathInput.value.trim();
  const isCurrentPath = text.toLowerCase() === currentPath().toLowerCase();
  filter = looksLikePath(text) || isCurrentPath ? '' : text;
  renderList(false);
});
pathInput.addEventListener('keydown', (event) => {
  if (event.key === 'Enter') {
    const text = pathInput.value.trim();
    if (looksLikePath(text)) navigate(text.replace(/\//g, '\\'));
    else if (visible.length) {
      selectIndex(0);
      listElement.focus();
    }
  } else if (event.key === 'Escape') {
    filter = '';
    pathInput.value = currentPath() === RECENTS ? '' : currentPath();
    renderList(false);
    listElement.focus();
  } else if (event.key === 'ArrowDown') {
    event.preventDefault();
    selectIndex(0);
    listElement.focus();
  }
});

// ---------- keyboard ----------

window.addEventListener('keydown', (event) => {
  if (event.target === pathInput) return;
  const key = event.key;
  const ctrl = event.ctrlKey;
  const focusIndex = anchorIndex >= 0 ? anchorIndex : -1;

  if (ctrl && key.toLowerCase() === 't') { event.preventDefault(); openTab(currentPath()); }
  else if (ctrl && key.toLowerCase() === 'w') { event.preventDefault(); closeTab(activeTabId); }
  else if (ctrl && key.toLowerCase() === 'l') { event.preventDefault(); pathInput.focus(); }
  else if (ctrl && key === 'Tab') { event.preventDefault(); const index = tabs.findIndex((tab) => tab.id === activeTabId); selectTab(tabs[(index + (event.shiftKey ? tabs.length - 1 : 1)) % tabs.length].id); }
  else if (ctrl && event.shiftKey && key.toLowerCase() === 'n') { event.preventDefault(); newFolder(); }
  else if (ctrl && key.toLowerCase() === 'a') { event.preventDefault(); selected = new Set(visible.map((entry) => entry.path)); updateSelection(); }
  else if (ctrl && key.toLowerCase() === 'c') copySelection('copy');
  else if (ctrl && key.toLowerCase() === 'x') copySelection('move');
  else if (ctrl && key.toLowerCase() === 'v') pasteHere();
  else if (ctrl && key.toLowerCase() === 'k') showContextMenu();
  else if (event.altKey && key === 'ArrowLeft') goBack();
  else if (event.altKey && key === 'ArrowRight') goForward();
  else if (event.altKey && key === 'ArrowUp') goUp();
  else if (key === 'Backspace') goBack();
  else if (key === 'F2') startRename();
  else if (key === 'Delete') recycle();
  else if (key === 'F5') load(true);
  else if (key === 'Enter') {
    const paths = selectedPaths();
    if (paths.length === 1) openEntry(visible.find((entry) => entry.path === paths[0]));
  } else if (key === 'ArrowDown' || key === 'ArrowUp') {
    event.preventDefault();
    const next = Math.max(0, Math.min(visible.length - 1, focusIndex + (key === 'ArrowDown' ? 1 : -1)));
    selectIndex(focusIndex < 0 ? 0 : next, event.shiftKey ? { shiftKey: true } : null);
  } else if (key.length === 1 && !ctrl && !event.altKey && /\S/.test(key)) {
    // Typing jumps to the first name starting with that letter, like Explorer.
    const index = visible.findIndex((entry, entryIndex) => entryIndex > focusIndex && entry.name.toLowerCase().startsWith(key.toLowerCase()));
    const wrapped = index >= 0 ? index : visible.findIndex((entry) => entry.name.toLowerCase().startsWith(key.toLowerCase()));
    if (wrapped >= 0) selectIndex(wrapped);
  }
});

// ---------- start ----------

(async () => {
  const query = new URLSearchParams(location.search);
  const startPath = query.get('path') || 'C:\\';
  const tornOffTab = query.get('tab') ? JSON.parse(query.get('tab')) : null;
  const settings = await window.api.files.settings();
  win.dataset.density = settings.density;
  document.querySelectorAll('.density button').forEach((button) => button.setAttribute('aria-pressed', String(button.dataset.density === settings.density)));
  tabs = [tornOffTab
    ? { id: nextTabId++, history: tornOffTab.history, index: tornOffTab.index, scroll: 0 }
    : { id: nextTabId++, history: [startPath], index: 0, scroll: 0 }];
  activeTabId = tabs[0].id;
  await renderSidebar();
  await load();
  listElement.focus();
})();
