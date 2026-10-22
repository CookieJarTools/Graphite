// Files: the file manager from the Explorer design (design/graphite-desk/components/Explorer).
// Main-process side: one frameless window per Files instance, and the file system work
// the renderer asks for. Deleting always goes to the Recycle Bin.

const { BrowserWindow, ipcMain, shell, clipboard, app, nativeImage, screen } = require('electron');
const path = require('path');
const fs = require('fs');

const HIDDEN_NAMES = new Set(['desktop.ini', 'thumbs.db', '$recycle.bin', 'system volume information']);

// Where a Files window takes drops (files.css): its header, right of the sidebar. That
// is the tab strip and the toolbar under it, the same area a dragged tab stays attached
// in, so the slot tab stays put until the pointer leaves it.
const SIDEBAR_WIDTH = 220;
const HEADER_HEIGHT = 96; // strip-height 40 + toolbar 56

let options = null;
const filesWindows = new Set();
let slotWindow = null; // the window currently showing a slot tab for an incoming drop
const pendingMerges = new Map(); // source webContents id -> { source, target }, awaiting its tabs

// A torn-off tab floats under the pointer in its own small window, so it can leave the
// Files window it came from. Made once and reused, so it appears without delay.
const GHOST_PADDING = 16; // room for the overlay shadow around the tab
const GHOST_TAB_HEIGHT = 28;
let ghost = null;

/**
 * @param {object} setup
 * @param {string} setup.preload       preload script path
 * @param {() => object} setup.settings  the live settings object
 * @param {() => void} setup.save       persists settings
 * @param {() => object[]} setup.recentItems  recent files and folders (from the Recent folder)
 * @param {string} setup.dragIcon      PNG shown while dragging files out
 * @param {(win: BrowserWindow) => void} setup.onCreated  called for each new Files window
 */
function setupFiles(setup) {
  options = setup;
  registerIpc();
  createGhost();
}

function createGhost() {
  ghost = new BrowserWindow({
    width: 240,
    height: GHOST_TAB_HEIGHT + GHOST_PADDING * 2,
    show: false,
    frame: false,
    transparent: true,
    backgroundColor: '#00000000',
    resizable: false,
    focusable: false,
    skipTaskbar: true,
    hasShadow: false,
    alwaysOnTop: true,
    webPreferences: { preload: options.preload, backgroundThrottling: false },
  });
  ghost.setAlwaysOnTop(true, 'pop-up-menu');
  ghost.setIgnoreMouseEvents(true);
  ghost.loadFile(path.join(__dirname, 'renderer', 'tabghost.html'));
  ghost.on('close', (e) => {
    if (!ghost.allowClose) e.preventDefault();
  });
  app.on('before-quit', () => {
    ghost.allowClose = true;
  });
}

// Keeps the floating tab exactly where the user grabbed it, relative to the pointer.
function moveGhost(drag) {
  if (!ghost || ghost.isDestroyed()) return;
  ghost.setBounds({
    x: Math.round(drag.x - drag.grab.x - GHOST_PADDING),
    y: Math.round(drag.y - drag.grab.y - GHOST_PADDING),
    width: Math.round(drag.grab.width + GHOST_PADDING * 2),
    height: GHOST_TAB_HEIGHT + GHOST_PADDING * 2,
  });
  send(ghost, 'files-ghost', drag.title);
  if (!ghost.isVisible()) ghost.showInactive();
}

function hideGhost() {
  if (!ghost || ghost.isDestroyed() || !ghost.isVisible()) return;
  ghost.hide();
  send(ghost, 'files-ghost-hidden');
}

/**
 * Opens a Files window on `folder`. `at` places it (a tab torn off at the pointer);
 * `tab` carries that tab's history so back and forward still work in its new window.
 */
function openFiles(folder, at, tab) {
  const filesWindow = new BrowserWindow({
    width: 1100,
    height: 680,
    ...(at ? { x: Math.round(at.x), y: Math.round(at.y) } : {}),
    minWidth: 640,
    minHeight: 400,
    frame: false,
    title: 'Files',
    backgroundColor: '#00000000',
    backgroundMaterial: 'mica',
    autoHideMenuBar: true,
    show: false,
    webPreferences: { preload: options.preload },
  });
  filesWindow.loadFile(path.join(__dirname, 'renderer', 'files.html'), {
    query: { path: folder || app.getPath('home'), ...(tab ? { tab: JSON.stringify(tab) } : {}) },
  });
  filesWindows.add(filesWindow);
  filesWindow.on('closed', () => filesWindows.delete(filesWindow));
  watchWindowDrag(filesWindow);
  filesWindow.once('ready-to-show', () => filesWindow.show());
  filesWindow.on('maximize', () => filesWindow.webContents.send('files-maximized', true));
  filesWindow.on('unmaximize', () => filesWindow.webContents.send('files-maximized', false));
  options.onCreated(filesWindow);
  return filesWindow;
}

// ---------- moving tabs between windows (Explorer and WindowMerge in the design) ----------

function stripRect(filesWindow) {
  const bounds = filesWindow.getContentBounds();
  return { x: bounds.x + SIDEBAR_WIDTH, y: bounds.y, width: bounds.width - SIDEBAR_WIDTH, height: HEADER_HEIGHT };
}

const inside = (rect, point) => point.x >= rect.x && point.x < rect.x + rect.width && point.y >= rect.y && point.y < rect.y + rect.height;

// The Files window whose tab strip is under the point, frontmost first.
function stripAt(point, except) {
  const candidates = BrowserWindow.getAllWindows().filter((candidate) => filesWindows.has(candidate) && candidate !== except && candidate.isVisible() && !candidate.isMinimized());
  return candidates.find((candidate) => inside(stripRect(candidate), point)) || null;
}

function send(target, channel, ...args) {
  if (target && !target.isDestroyed()) target.webContents.send(channel, ...args);
}

// Shows the slot tab ("this is where it will land") on one window and clears it elsewhere.
// Drag events arrive on every pointer move; only a change is passed on, so the slot is
// drawn once and stays steady rather than being rebuilt (and re-animated) each time.
let slotTitle = null;

function showSlot(target, title) {
  const nextTitle = target ? title : null;
  if (target === slotWindow && nextTitle === slotTitle) return;
  if (slotWindow && slotWindow !== target) send(slotWindow, 'files-drop-slot', null);
  slotWindow = target;
  slotTitle = nextTitle;
  if (target) send(target, 'files-drop-slot', title);
}

// Dragging a whole Files window by its strip onto another one folds all its tabs in.
function watchWindowDrag(filesWindow) {
  const titleOf = () => filesWindow.getTitle().replace(/ - Files$/, '');
  // 'move' and 'moved' also fire when a window is placed by code (a torn-off tab opening
  // at the pointer, Windows restoring it); only a move the user is making may merge.
  // Electron emits 'will-move' for manual moves alone.
  let userMoving = false;
  filesWindow.on('will-move', () => {
    userMoving = true;
  });
  filesWindow.on('move', () => {
    if (userMoving) showSlot(stripAt(screen.getCursorScreenPoint(), filesWindow), titleOf());
  });
  filesWindow.on('moved', () => {
    if (!userMoving) return;
    userMoving = false;
    const target = stripAt(screen.getCursorScreenPoint(), filesWindow);
    showSlot(null);
    if (!target) return;
    pendingMerges.set(filesWindow.webContents.id, { source: filesWindow, target });
    send(filesWindow, 'files-export-tabs');
  });
}

// ---------- file system ----------

async function list(folder) {
  const entries = await fs.promises.readdir(folder, { withFileTypes: true });
  const items = await Promise.all(entries
    .filter((entry) => !HIDDEN_NAMES.has(entry.name.toLowerCase()))
    .map(async (entry) => {
      const fullPath = path.join(folder, entry.name);
      try {
        const stats = await fs.promises.stat(fullPath);
        return { name: entry.name, path: fullPath, isDir: stats.isDirectory(), size: stats.size, modified: stats.mtimeMs };
      } catch {
        return null; // vanished, or locked down (pagefile, system folders)
      }
    }));
  return items.filter(Boolean);
}

function drives() {
  const letters = [];
  for (let code = 65; code <= 90; code++) {
    const root = String.fromCharCode(code) + ':\\';
    try {
      fs.accessSync(root);
      letters.push(root);
    } catch {
      // no drive with this letter
    }
  }
  return letters;
}

function places() {
  const known = [['Home', 'home'], ['Downloads', 'downloads'], ['Documents', 'documents'], ['Pictures', 'pictures'], ['Music', 'music'], ['Videos', 'videos']];
  return known.map(([name, key]) => ({ name, path: app.getPath(key) }));
}

// "name", "name (2)", "name (3)"… so pasting or creating never overwrites anything.
function uniquePath(folder, name) {
  const extension = path.extname(name);
  const stem = name.slice(0, name.length - extension.length);
  let candidate = path.join(folder, name);
  for (let number = 2; fs.existsSync(candidate); number++) candidate = path.join(folder, `${stem} (${number})${extension}`);
  return candidate;
}

async function paste(mode, sources, destination) {
  for (const source of sources) {
    if (path.dirname(source).toLowerCase() === destination.toLowerCase() && mode === 'move') continue;
    if (destination.toLowerCase().startsWith(source.toLowerCase() + path.sep)) continue; // into itself
    const target = uniquePath(destination, path.basename(source));
    if (mode === 'copy') {
      await fs.promises.cp(source, target, { recursive: true, errorOnExist: true });
      continue;
    }
    try {
      await fs.promises.rename(source, target);
    } catch (error) {
      if (error.code !== 'EXDEV') throw error;
      // Across drives a move is a copy, then the original goes to the Recycle Bin.
      await fs.promises.cp(source, target, { recursive: true, errorOnExist: true });
      await shell.trashItem(source);
    }
  }
}

// ---------- ipc ----------

function registerIpc() {
  ipcMain.handle('files:list', async (_e, folder) => {
    if (folder === 'recents:') {
      return options.recentItems().map((item) => ({ name: item.name, path: item.target, isDir: item.kind === 'folder', size: 0, modified: item.time, folder: item.folder }));
    }
    return list(folder);
  });
  ipcMain.handle('files:count', async (_e, folder) => {
    try {
      return (await fs.promises.readdir(folder)).length;
    } catch {
      return null;
    }
  });
  ipcMain.handle('files:sidebar', () => ({ places: places(), drives: drives() }));
  ipcMain.handle('files:settings', () => ({ density: options.settings().filesDensity || 'comfy' }));
  ipcMain.on('files:density', (_e, density) => {
    options.settings().filesDensity = density;
    options.save();
  });
  ipcMain.on('files:open', (_e, filePath) => shell.openPath(filePath));
  ipcMain.on('files:reveal', (_e, filePath) => shell.showItemInFolder(filePath));
  ipcMain.on('files:copy-path', (_e, filePath) => clipboard.writeText(filePath));
  ipcMain.on('files:new-window', (_e, folder) => openFiles(folder));
  ipcMain.handle('files:trash', async (_e, paths) => {
    for (const filePath of paths) await shell.trashItem(filePath);
  });
  ipcMain.handle('files:rename', async (_e, from, newName) => {
    if (!newName || /[\\/:*?"<>|]/.test(newName)) throw new Error('A name cannot contain \\ / : * ? " < > |');
    const target = path.join(path.dirname(from), newName);
    if (target.toLowerCase() !== from.toLowerCase() && fs.existsSync(target)) throw new Error(`"${newName}" already exists here`);
    await fs.promises.rename(from, target);
    return target;
  });
  ipcMain.handle('files:mkdir', async (_e, folder) => {
    const target = uniquePath(folder, 'New folder');
    await fs.promises.mkdir(target);
    return target;
  });
  ipcMain.handle('files:paste', (_e, mode, sources, destination) => paste(mode, sources, destination));
  ipcMain.on('files:drag', (e, paths) => {
    e.sender.startDrag({ files: paths, icon: nativeImage.createFromPath(options.dragIcon) });
  });
  ipcMain.on('files:window', (e, action) => {
    const filesWindow = BrowserWindow.fromWebContents(e.sender);
    if (!filesWindow) return;
    if (action === 'minimize') filesWindow.minimize();
    else if (action === 'maximize') filesWindow.isMaximized() ? filesWindow.unmaximize() : filesWindow.maximize();
    else if (action === 'close') filesWindow.close();
  });
  // The tabs of a window dropped onto another one: the target adopts them all.
  ipcMain.on('files:exported-tabs', (e, tabs) => {
    const merge = pendingMerges.get(e.sender.id);
    pendingMerges.delete(e.sender.id);
    if (!merge || merge.target.isDestroyed()) return;
    for (const tab of tabs) send(merge.target, 'files-adopt-tab', tab);
    merge.target.focus();
    merge.source.destroy();
  });

  // A tab being dragged: show where it would land.
  ipcMain.on('files:tab-drag', (e, drag) => {
    const source = BrowserWindow.fromWebContents(e.sender);
    showSlot(drag ? stripAt(drag, source) : null, drag && drag.title);
    if (drag) moveGhost(drag);
    else hideGhost();
  });

  // A tab let go outside its own strip: into another window's strip, or into a new window
  // at the pointer. Returns what happened so the source can drop the tab.
  ipcMain.handle('files:tab-drop', (e, drop) => {
    const source = BrowserWindow.fromWebContents(e.sender);
    const target = stripAt(drop, source);
    showSlot(null);
    hideGhost();
    if (target) {
      send(target, 'files-adopt-tab', drop.tab);
      target.focus();
      return 'moved';
    }
    if (drop.tabCount < 2) return 'none'; // tearing off the only tab would just be the same window
    const folder = drop.tab.history[drop.tab.index];
    openFiles(folder, { x: drop.x - 160, y: drop.y - 20 }, drop.tab);
    return 'split';
  });

  ipcMain.on('files:set-clipboard', (_e, mode, paths) => {
    if (options.setClipboardFiles) options.setClipboardFiles(mode, paths);
  });

  // The renderer says what is selected and what is possible. Windows' own menu is shown when
  // the helper can (every Explorer item, extensions included), ours otherwise.
  ipcMain.on('files:menu', (e, state) => {
    const filesWindow = BrowserWindow.fromWebContents(e.sender);
    if (!filesWindow) return;
    const paths = state.paths || [];
    const oneFolder = paths.every((item) => path.dirname(item) === path.dirname(paths[0] || ''));
    const hasFolder = !state.inRecents || paths.length > 0;
    if (options.showShellMenu && oneFolder && hasFolder) {
      const owner = handleOf(filesWindow);
      pendingMenus.set(owner, { webContents: e.sender, state });
      options.showShellMenu(shellMenuRequest(owner, state));
      return;
    }
    showOwnMenu(e.sender, state);
  });

  // The menu closed: what was picked from Windows' items (0 for nothing, or one of ours).
  ipcMain.on('files:menu-done', (_e, session, id) => {
    if (options.pickShellMenu && Number.isInteger(session)) options.pickShellMenu(session, Number.isInteger(id) ? id : 0);
  });
}

const pendingMenus = new Map(); // Files window handle -> the menu request, until the helper answers

function handleOf(browserWindow) {
  return browserWindow.getNativeWindowHandle().readBigUInt64LE(0).toString();
}

// Shell verbs the Files app does itself, so they act on its own view: open a folder here
// rather than in Explorer, rename in place, cut and copy with its own clipboard.
function shellMenuRequest(owner, state) {
  const verbs = {
    open: 'open',
    opennewwindow: 'open-window',
    opennewtab: 'open-tab',
    explore: '',
    opennewprocess: '',
    rename: 'rename',
    delete: 'recycle',
    cut: 'cut',
    copy: 'copy',
  };
  // Files copied here paste through the app (its own progress and messages); anything else on
  // the clipboard, copied in Explorer say, the shell pastes itself.
  if (state.canPaste) verbs.paste = 'paste';
  const ours = [];
  if (state.single && state.isDir) ours.push({ id: 'open-tab', label: 'Open in new tab', after: 'open' });
  if (state.single && state.inRecents) ours.push({ id: 'reveal', label: 'Open file location', after: 'open' });
  if (!state.hasSelection) ours.push({ id: 'refresh-view', label: 'Refresh' });
  return {
    owner,
    paths: state.paths || [],
    folder: state.inRecents ? null : state.folder,
    canRename: Boolean(state.single && !state.inRecents),
    verbs,
    ours,
  };
}

// From the helper: the menu's items to draw, "fallback" when Windows had no menu for this,
// or "refresh" once a picked shell command has run.
function onShellMenu(msg) {
  const pending = pendingMenus.get(msg.owner);
  if (!pending || pending.webContents.isDestroyed()) return;
  if (msg.items) {
    pending.webContents.send('files-context-menu', { session: msg.session, items: msg.items });
    return;
  }
  pendingMenus.delete(msg.owner);
  if (msg.action === 'fallback') showOwnMenu(pending.webContents, pending.state);
  else pending.webContents.send('files-menu', msg.action);
}

// Our own items, for what Windows has no menu for (Recents' empty space, items from
// different folders). The same shape as the helper's, drawn by the same menu.
function ownMenuItems(state) {
  const item = (label, action, shortcut) => ({ label, action, shortcut });
  const items = state.hasSelection
    ? [
      state.single && item('Open', 'open'),
      state.single && state.isDir && item('Open in new tab', 'open-tab'),
      state.single && state.isDir && item('Open in new window', 'open-window'),
      state.single && item('Open file location', 'reveal'),
      { separator: true },
      !state.inRecents && item('Cut', 'cut', 'Ctrl+X'),
      item('Copy', 'copy', 'Ctrl+C'),
      state.single && item('Copy as path', 'copy-path'),
      state.single && !state.inRecents && item('Rename', 'rename', 'F2'),
      { separator: true },
      item('Delete', 'recycle', 'Del'),
    ]
    : [
      !state.inRecents && { ...item('Paste', 'paste', 'Ctrl+V'), disabled: !state.canPaste },
      !state.inRecents && item('New folder', 'new-folder', 'Ctrl+Shift+N'),
      item('Refresh', 'refresh-view', 'F5'),
    ];
  return items.filter(Boolean);
}

function showOwnMenu(webContents, state) {
  webContents.send('files-context-menu', { session: null, items: ownMenuItems(state) });
}

module.exports = { setupFiles, openFiles, onShellMenu };
