const { app, BrowserWindow, Tray, Menu, screen, ipcMain, nativeImage, nativeTheme, shell, globalShortcut, systemPreferences } = require('electron');
const { spawn, execFile, execFileSync } = require('child_process');
const readline = require('readline');
const path = require('path');
const fs = require('fs');
const os = require('os');
const { setupFiles, openFiles, onShellMenu } = require('./files-main');
const taskbarModel = require('./taskbar-model');
const windowTags = require('./window-tags');

const WIDTH = 620;
const HEIGHT = 760;

// Dev mode (`npm run dev`): an ordinary resizable window, hooks off until switched on
// from the tray, power actions stubbed out, live reload, and its own settings folder
// so it runs alongside the installed app without touching its pins or startup entry.
const DEV = process.argv.includes('--dev');
// The startup entry passes --login, so the sign-in Intro plays only then, never on a manual start.
const LOGIN_START = process.argv.includes('--login');
const PANIC_SHORTCUT = 'Control+Alt+Shift+Q';
const INTRO_MILLISECONDS = 1700; // duration-intro plus a frame or two of settle

if (DEV) app.setPath('userData', path.join(app.getPath('appData'), 'custom-start-dev'));
// `--test-profile=<dir>` (dev only): a throwaway settings folder for the end-to-end tests,
// so they never touch your pins or recents, and run alongside your own dev instance.
const TEST_PROFILE = DEV ? (process.argv.find((arg) => arg.startsWith('--test-profile=')) || '').slice('--test-profile='.length) : '';
if (TEST_PROFILE) app.setPath('userData', path.resolve(TEST_PROFILE));

let win = null;
let homeWin = null;
let switcherWin = null;
let taskbarWin = null;
let toastWin = null;
let tray = null;
let helper = null;
let quitting = false;
let apps = [];
let settings = null;

const settingsFile = () => path.join(app.getPath('userData'), 'settings.json');
const iconCacheDir = () => path.join(app.getPath('userData'), 'icon-cache');
const appsCacheFile = () => path.join(app.getPath('userData'), 'apps-cache.json');

// ---------- settings ----------

function loadSettings() {
  const defaults = {
    interceptWinKey: true,
    replaceAltTab: true,
    paletteHotkey: true,
    filesOnWinE: true,
    filesDensity: 'comfy',
    windowTabs: true,
    customTaskbar: true,
    taskbar: { ...taskbarModel.emptyConfig(), showLabels: true },
    nativeTaskbar: null, // { hidden, originalAutoHide } while ours replaces it, for crash recovery
    hiddenTabs: [],
    showHome: true,
    runAtStartup: true,
    pinned: [],
    recent: [],
    launchCounts: {},
    lastUsed: {},
    labels: {},
    aliases: {},
    quickLinks: [
      { name: 'AppData', path: '%APPDATA%' },
      { name: 'Local', path: '%LOCALAPPDATA%' },
      { name: 'Temp', path: '%TEMP%' },
      { name: 'Home', path: '%USERPROFILE%' },
      { name: 'Downloads', path: '%USERPROFILE%\\Downloads' },
    ],
  };
  try {
    return { ...defaults, ...JSON.parse(fs.readFileSync(settingsFile(), 'utf8')) };
  } catch {
    return defaults;
  }
}

function saveSettings() {
  try {
    fs.mkdirSync(app.getPath('userData'), { recursive: true });
    fs.writeFileSync(settingsFile(), JSON.stringify(settings, null, 2));
  } catch { /* non-fatal */ }
}

function saveAppsCache() {
  try {
    fs.mkdirSync(app.getPath('userData'), { recursive: true });
    fs.writeFileSync(appsCacheFile(), JSON.stringify(apps));
  } catch { /* non-fatal */ }
}

// ---------- window ----------

function createWindow() {
  if (DEV) return createDevWindow();
  win = new BrowserWindow({
    width: WIDTH,
    height: HEIGHT,
    show: false,
    frame: false,
    transparent: true,
    backgroundColor: '#00000000',
    resizable: false,
    skipTaskbar: true,
    alwaysOnTop: true,
    fullscreenable: false,
    webPreferences: {
      preload: path.join(__dirname, 'preload.js'),
      // Keep rendering while hidden so the reset-on-hide paints before next show
      backgroundThrottling: false,
    },
  });

  // 'screen-saver' is the highest always-on-top band — above the taskbar and
  // other merely-topmost windows.
  win.setAlwaysOnTop(true, 'screen-saver');

  win.loadFile('renderer/index.html');
  registerShellWindow(win);
  win.on('blur', () => hideMenu());
  win.on('close', (e) => {
    if (!quitting) {
      e.preventDefault();
      hideMenu();
    }
  });
  win.webContents.on('did-finish-load', () => {
    pushState();
    if (!menuVisible) parkWindow();
  });
}

// Dev previews swap the dev window between the launcher and Home pages.
// `npm run dev -- --preview=home` or `--preview=intro` starts on one of them;
// `--preview=switcher` opens the Alt+Tab switcher once the helper is up.
const DEV_PREVIEW = (process.argv.find((arg) => arg.startsWith('--preview=')) || '').slice('--preview='.length);
let devPage = DEV_PREVIEW === 'home' || DEV_PREVIEW === 'intro' ? 'home.html' : 'index.html';
let devIntroPending = DEV_PREVIEW === 'intro';
let devPaletteMode = DEV_PREVIEW === 'palette';

function previewInDevWindow(page, withIntro, asPalette = false) {
  devPage = page;
  devIntroPending = withIntro;
  devPaletteMode = asPalette;
  win.loadFile(path.join('renderer', page));
  win.show();
  win.focus();
}

function createDevWindow() {
  win = new BrowserWindow({
    width: 1100,
    height: 800,
    title: 'Custom Start (dev)',
    backgroundColor: '#141516',
    autoHideMenuBar: true,
    webPreferences: {
      preload: path.join(__dirname, 'preload.js'),
    },
  });
  win.loadFile(path.join('renderer', devPage));
  registerShellWindow(win);
  win.on('page-title-updated', (e) => e.preventDefault());
  win.webContents.on('console-message', (e) => console.log(`[renderer:${e.level}] ${e.message}`));
  win.webContents.on('did-fail-load', (_e, code, desc) => console.error('[renderer] load failed:', code, desc));
  win.webContents.on('render-process-gone', (_e, d) => console.error('[renderer] gone:', d.reason));
  win.on('closed', () => quitApp());
  win.webContents.on('did-finish-load', () => {
    pushState();
    if (devIntroPending) send(win, 'intro');
    else send(win, 'shown', devPaletteMode ? 'palette' : 'launcher');
    devIntroPending = false;
  });
  menuVisible = true;
}

// ---------- Home ----------

// Home stands in for the desktop: a full-screen backdrop with one search field,
// shown whenever the helper reports that no real app window is visible. It is an
// ordinary (not topmost) window, so the taskbar stays above it and any window that
// opens covers it, at which point the helper reports a non-empty screen and it hides.
let homeVisible = false;
let screenEmpty = false;
let introPlaying = false;
// `npm run dev -- --home` turns the real empty-screen Home on for that run.
let devHomeOn = process.argv.includes('--home');

function homeEnabled() {
  return DEV ? devHomeOn : settings.showHome;
}

// Home is a pixel short of the whole screen: Windows takes any window covering a screen for
// a full-screen app (a game, a presentation) and holds every notification back while one
// is up, which Home, standing in for the desktop, must not do. The row it leaves shows the
// wallpaper, which is the same backdrop.
function homeBounds() {
  return shortOfFullScreen(screen.getPrimaryDisplay().bounds);
}

function shortOfFullScreen(bounds) {
  return { ...bounds, height: bounds.height - 1 };
}

function createHomeWindow() {
  homeWin = new BrowserWindow({
    ...homeBounds(),
    show: false,
    frame: false,
    resizable: false,
    movable: false,
    minimizable: false,
    maximizable: false,
    fullscreenable: false,
    skipTaskbar: true,
    backgroundColor: nativeTheme.shouldUseDarkColors ? '#141516' : '#dcdad6',
    webPreferences: {
      preload: path.join(__dirname, 'preload.js'),
      backgroundThrottling: false,
    },
  });
  homeWin.loadFile('renderer/home.html');
  registerShellWindow(homeWin);
  homeWin.on('close', (e) => {
    if (!quitting) e.preventDefault();
  });
  homeWin.webContents.on('did-finish-load', () => {
    pushState();
    if (LOGIN_START && !DEV) playIntro();
    else sendToHelper('checkempty');
  });
}

function showHome() {
  if (!homeWin || homeVisible) return;
  homeVisible = true;
  homeWin.setBounds(homeBounds());
  homeWin.show();
  sendToHelper('focushwnd ' + nativeHandle(homeWin));
  send(homeWin, 'shown');
  setImmediate(refreshRecentItems);
}

function hideHome() {
  if (!homeWin || !homeVisible || introPlaying) return;
  homeVisible = false;
  homeWin.hide();
  send(homeWin, 'reset'); // clean frame for the next time the screen empties
}

function setHomeEnabled(enabled) {
  if (DEV) devHomeOn = enabled;
  else {
    settings.showHome = enabled;
    saveSettings();
  }
  if (enabled && !homeWin) createHomeWindow();
  else if (enabled) sendToHelper('checkempty');
  else hideHome();
}

// The Intro covers the whole screen, taskbar included, then hands over to Home.
// Skipped when Windows "Animation effects" is off.
function playIntro() {
  if (!systemPreferences.getAnimationSettings().shouldRenderRichAnimation) {
    sendToHelper('checkempty');
    return;
  }
  introPlaying = true;
  homeVisible = true;
  homeWin.setBounds(homeBounds());
  homeWin.setAlwaysOnTop(true, 'screen-saver');
  homeWin.show();
  sendToHelper('focushwnd ' + nativeHandle(homeWin));
  send(homeWin, 'intro');
  setTimeout(() => {
    introPlaying = false;
    homeWin.setAlwaysOnTop(false);
    sendToHelper('checkempty'); // hides Home if windows were restored during sign-in
  }, INTRO_MILLISECONDS);
}

// ---------- Switcher (Alt+Tab) ----------

// The helper's hook owns the keys; this side owns the window list and the selection.
// Like the launcher, the switcher window is parked invisible rather than hidden so it
// appears the instant Tab is pressed. It is never focusable: the app you are leaving
// keeps focus until you pick, so nothing flickers.
let switcherWindows = [];
let switcherIndex = 0;
let switcherVisible = false;
let switcherPreviewPending = false;
let switcherLoaded = false;
// `npm run dev -- --alttab` turns the real Alt+Tab replacement on for that run.
let devAltTabOn = process.argv.includes('--alttab');
let appAliases = {};

// ---------- Window tabs ----------

// The helper groups windows and keeps each group's strip glued to it; this side owns
// one strip window per group, plus a spare "hover strip" that shows a slot tab over an
// ungrouped window while another is dragged onto it.
const strips = new Map(); // group id -> BrowserWindow
let hoverStrip = null;
let tabGroups = [];
// `npm run dev -- --tabs` turns window tabs on for that run.
let devTabsOn = process.argv.includes('--tabs');

function tabsEnabled() {
  return DEV ? devTabsOn : settings.windowTabs;
}

function createStripWindow() {
  const strip = new BrowserWindow({
    width: 400,
    height: 40,
    show: false,
    frame: false,
    transparent: true,
    backgroundColor: '#00000000',
    resizable: false,
    skipTaskbar: true,
    focusable: false,
    hasShadow: false,
    fullscreenable: false,
    webPreferences: {
      preload: path.join(__dirname, 'preload.js'),
      backgroundThrottling: false,
    },
  });
  strip.loadFile('renderer/tabstrip.html');
  registerShellWindow(strip);
  // Windows keeps a frameless window taller than asked, and that invisible band would
  // swallow clicks meant for the title bar underneath. So the strip lets the mouse
  // through until the pointer is over the visible tabs (see tabstrip.js).
  strip.setIgnoreMouseEvents(true, { forward: true });
  strip.on('close', (e) => {
    if (!quitting && !strip.allowClose) e.preventDefault();
  });
  return strip;
}

function closeStrip(strip) {
  unregisterShellWindow(strip);
  strip.allowClose = true;
  strip.destroy();
}

function decorateTabs(group) {
  return { id: group.id, active: group.active, tabs: decorateWindows(group.tabs) };
}

function onTabGroups(groups) {
  tabGroups = groups;
  rememberHiddenTabs(groups);
  for (const group of groups) {
    const state = decorateTabs(group);
    let strip = strips.get(group.id);
    if (!strip) {
      strip = createStripWindow();
      strips.set(group.id, strip);
      strip.webContents.once('did-finish-load', () => {
        sendToHelper(`stripwin ${group.id} ${nativeHandle(strip)}`);
        const latest = tabGroups.find((candidate) => candidate.id === group.id);
        if (latest) send(strip, 'strip-state', decorateTabs(latest));
      });
    } else if (!strip.webContents.isLoading()) {
      send(strip, 'strip-state', state);
    }
  }
  for (const [id, strip] of strips) {
    if (groups.some((group) => group.id === id)) continue;
    strips.delete(id);
    closeStrip(strip);
  }
}

// Saved on every change, so a crash can never strand a hidden window: the next start
// shows them again (the helper checks each is still the same app before touching it).
function rememberHiddenTabs(groups) {
  settings.hiddenTabs = groups.flatMap((group) => group.tabs
    .filter((tab) => tab.hwnd !== group.active)
    .map((tab) => ({ hwnd: tab.hwnd, exe: tab.exe })));
  saveSettings();
}

function restoreRememberedTabs() {
  const remembered = (settings.hiddenTabs || []).filter((tab) => tab.hwnd && tab.exe);
  for (const tab of remembered) sendToHelper(`restorewindow ${tab.hwnd} ${tab.exe}`);
  settings.hiddenTabs = [];
  saveSettings();
}

function onMergeHover(msg) {
  for (const strip of strips.values()) {
    if (!strip.webContents.isLoading()) send(strip, 'strip-slot', null);
  }
  if (!msg.target) return;
  const [source] = decorateWindows([msg.source]);
  if (msg.group && strips.has(msg.group)) {
    send(strips.get(msg.group), 'strip-slot', source);
  } else if (hoverStrip) {
    const [target] = decorateWindows([msg.target]);
    send(hoverStrip, 'strip-state', { id: 0, active: target.hwnd, tabs: [target], slot: source });
  }
}

function createHoverStrip() {
  hoverStrip = createStripWindow();
  hoverStrip.webContents.once('did-finish-load', () => sendToHelper('hoverstrip ' + nativeHandle(hoverStrip)));
}

function setTabsEnabled(enabled) {
  if (DEV) devTabsOn = enabled;
  else {
    settings.windowTabs = enabled;
    saveSettings();
  }
  sendToHelper('tabs ' + (enabled ? 1 : 0));
}

// ---------- Taskbar ----------

// The helper feeds the running windows (shell hook) and hides the native taskbar; this
// side keeps their order stable, marks focus, attention and tab counts, and hides the bar
// while a maximised window has focus, bringing it back when the pointer hits the edge.
const TASKBAR_HEIGHT = 64; // taskbar-height plus the space-2 float on both sides
// The window reaches higher than the bar to give popovers and hover previews room; the
// part above the bar lets the mouse through unless one of them is open.
const TASKBAR_WINDOW_HEIGHT = 640; // room above the bar for popovers, previews and panels
const TASKBAR_REVEAL_POLL = 150;
let taskWindowOrder = [];
let lastTaskState = null;
let taskbarAutoHidden = false;
let taskbarPeekingNative = false;
let taskbarPeeking = false;
let taskbarRevealTimer = null;
// `npm run dev -- --taskbar` swaps in the Graphite taskbar for that run.
let devTaskbarOn = process.argv.includes('--taskbar');

function taskbarEnabled() {
  return DEV ? devTaskbarOn : settings.customTaskbar;
}

function taskbarBounds() {
  const display = screen.getPrimaryDisplay().bounds;
  return { x: display.x, y: display.y + display.height - TASKBAR_WINDOW_HEIGHT, width: display.width, height: TASKBAR_WINDOW_HEIGHT };
}

function createTaskbarWindow() {
  taskbarWin = new BrowserWindow({
    ...taskbarBounds(),
    show: false,
    frame: false,
    transparent: true,
    backgroundColor: '#00000000',
    resizable: false,
    movable: false,
    skipTaskbar: true,
    focusable: false,
    hasShadow: false,
    fullscreenable: false,
    alwaysOnTop: true,
    webPreferences: {
      preload: path.join(__dirname, 'preload.js'),
      backgroundThrottling: false,
    },
  });
  taskbarWin.setAlwaysOnTop(true, 'pop-up-menu');
  taskbarWin.setIgnoreMouseEvents(true, { forward: true });
  taskbarWin.loadFile('renderer/taskbar.html');
  registerShellWindow(taskbarWin);
  taskbarWin.on('close', (e) => {
    if (!quitting && !taskbarWin.allowClose) e.preventDefault();
  });
  taskbarWin.webContents.once('did-finish-load', () => {
    taskbarWin.showInactive();
    sendTaskbarState(); // pinned items show before any window news arrives
    send(taskbarWin, 'tray-icons', trayIcons);
    pollNotifications(NOTIFICATION_POLL_IDLE);
    sendToHelper('taskbar 1');
    sendToHelper('tray 1'); // our own home for the apps' tray icons
    hideNativeTaskbar();
    reserveTaskbarSpace();
  });
}

// Hiding the Windows taskbar changes the work area, which fires this, sometimes while the
// app is quitting and the bar is already gone; hence the check. Registered once, when the
// app is ready (Electron's screen module cannot be used before).
// Signing out or shutting down: the helper leaves the native taskbar hidden (see Program.cs).
app.on('browser-window-created', (_e, browserWindow) => {
  browserWindow.on('query-session-end', () => {
    sessionEnding = true;
    sendToHelper('sessionending');
  });
});

// ---------- desktop backdrop ----------

// Home's backdrop is also the desktop wallpaper, and the desktop icons are hidden, so
// whatever shows behind windows is the surface Home sits on: opening a window never feels
// like stepping out into Windows. The wallpaper is rendered from renderer/backdrop.html at
// each screen's size, again when the theme or the screens change. What was there before is
// kept in settings.desktopOriginal and put back when this is turned off, on a normal quit,
// and on the next start after a crash; a sign-out leaves it, so the next sign-in starts on
// the backdrop.
const BACKDROP_FILE_PREFIX = 'backdrop-';
const BACKDROP_VERSION = 2; // in the file name: a new look gets new files
const WALLPAPER_FILL = 4; // DWPOS_FILL
let sessionEnding = false;
let backdropFiles = null; // rendered images waiting for the helper's wallpaper state
let backdropTimer = null;

function desktopBackdropEnabled() {
  return DEV ? process.argv.includes('--backdrop') : settings.desktopBackdrop !== false;
}

function scheduleDesktopBackdrop() {
  clearTimeout(backdropTimer);
  backdropTimer = setTimeout(applyDesktopBackdrop, 500); // screens change in bursts
}

async function applyDesktopBackdrop() {
  if (!desktopBackdropEnabled()) {
    restoreDesktop();
    return;
  }
  backdropFiles = await renderBackdrops();
  sendToHelper('wallpaper state'); // answered in onWallpaperState
}

// One image per screen, at its full physical resolution.
async function renderBackdrops() {
  const theme = nativeTheme.shouldUseDarkColors ? 'dark' : 'light';
  const folder = app.getPath('userData');
  const rendered = [];
  for (const display of screen.getAllDisplays()) {
    const rect = screen.dipToScreenRect(null, display.bounds);
    // Windows caches a wallpaper by its path, so every look gets its own file name.
    const file = path.join(folder, `${BACKDROP_FILE_PREFIX}v${BACKDROP_VERSION}-${theme}-${rect.width}x${rect.height}@${display.scaleFactor}.png`);
    if (!fs.existsSync(file)) fs.writeFileSync(file, await renderBackdrop(rect, display.scaleFactor));
    rendered.push({ ...rect, file });
  }
  for (const name of fs.readdirSync(folder)) {
    const file = path.join(folder, name);
    if (name.startsWith(BACKDROP_FILE_PREFIX) && !rendered.some((item) => item.file === file)) fs.rm(file, () => {});
  }
  return rendered;
}

async function renderBackdrop(rect, scaleFactor) {
  const page = new BrowserWindow({
    show: false,
    width: rect.width,
    height: rect.height,
    useContentSize: true,
    frame: false,
    webPreferences: { offscreen: true },
  });
  try {
    await page.loadFile('renderer/backdrop.html', { query: { scale: String(scaleFactor) } });
    const drawn = () => page.webContents.executeJavaScript("document.body.dataset.ready === '1'");
    for (let tries = 0; tries < 100 && !(await drawn()); tries++) await new Promise((resolve) => setTimeout(resolve, 50));
    await new Promise((resolve) => setTimeout(resolve, 100)); // the drawn frame reaches the capture
    let image = await page.webContents.capturePage();
    const size = image.getSize();
    if (size.width !== rect.width || size.height !== rect.height) image = image.resize({ width: rect.width, height: rect.height });
    return image.toPNG();
  } finally {
    page.destroy();
  }
}

// Any of our backdrop images, from this profile or another (dev and installed copies).
function isBackdropFile(file) {
  return Boolean(file) && /^backdrop-.*\.png$/i.test(path.basename(file));
}

// Windows re-encodes every wallpaper as a JPEG, at 85% unless told otherwise, which turns a
// gradient this subtle into blocks and rings. While the backdrop is on it keeps full quality.
const DESKTOP_KEY = 'HKCU\\Control Panel\\Desktop';

function readJpegQuality() {
  try {
    const out = execFileSync('reg.exe', ['query', DESKTOP_KEY, '/v', 'JPEGImportQuality'], { encoding: 'utf8', windowsHide: true });
    const match = out.match(/JPEGImportQuality\s+REG_DWORD\s+0x([0-9a-f]+)/i);
    return match ? parseInt(match[1], 16) : null;
  } catch {
    return null; // not set: Windows uses 85
  }
}

function writeJpegQuality(quality) {
  const args = quality === null
    ? ['delete', DESKTOP_KEY, '/v', 'JPEGImportQuality', '/f']
    : ['add', DESKTOP_KEY, '/v', 'JPEGImportQuality', '/t', 'REG_DWORD', '/d', String(quality), '/f'];
  try {
    execFileSync('reg.exe', args, { windowsHide: true, stdio: 'ignore' });
  } catch {
    // Deleting a value that is not there: already as wanted.
  }
}

function onWallpaperState(msg) {
  if (!backdropFiles) return;
  const files = backdropFiles;
  backdropFiles = null;
  // The first time only, and never our own images (after a crash that lost the settings).
  if (!settings.desktopOriginal && !msg.monitors.some((monitor) => isBackdropFile(monitor.path))) {
    settings.desktopOriginal = {
      monitors: msg.monitors.map((monitor) => ({ id: monitor.id, path: monitor.path })),
      position: msg.position,
      color: msg.color,
      icons: msg.icons,
      jpegQuality: readJpegQuality(),
    };
    saveSettings();
  }
  if (readJpegQuality() !== 100) writeJpegQuality(100); // before the wallpaper is set
  sendToHelper('desktopicons 0');
  const imageFor = (monitor) => files.find((item) => item.x === monitor.x && item.y === monitor.y)
    || files.find((item) => item.width === monitor.width && item.height === monitor.height)
    || files[0];
  const backdrop = (nativeTheme.shouldUseDarkColors ? '#141516' : '#dcdad6').slice(1);
  const colorref = parseInt(backdrop.slice(4, 6) + backdrop.slice(2, 4) + backdrop.slice(0, 2), 16); // 0x00BBGGRR
  const monitors = msg.monitors.map((monitor) => ({ id: monitor.id, path: imageFor(monitor).file }));
  if (monitors.every((monitor, index) => monitor.path === msg.monitors[index].path) && msg.position === WALLPAPER_FILL) return; // already ours
  sendToHelper('wallpaper set ' + JSON.stringify({ monitors, position: WALLPAPER_FILL, color: colorref }));
}

function restoreDesktop() {
  const original = settings.desktopOriginal;
  if (!original) return;
  sendToHelper('wallpaper set ' + JSON.stringify(original));
  sendToHelper('desktopicons ' + (original.icons ? 1 : 0));
  writeJpegQuality(original.jpegQuality ?? null); // not recorded (an older save): it was unset
  settings.desktopOriginal = null;
  saveSettings();
}

function setDesktopBackdropEnabled(enabled) {
  settings.desktopBackdrop = enabled;
  saveSettings();
  applyDesktopBackdrop();
}

function watchDisplayChanges() {
  screen.on('display-added', scheduleDesktopBackdrop);
  screen.on('display-removed', scheduleDesktopBackdrop);
  nativeTheme.on('updated', scheduleDesktopBackdrop);
  screen.on('display-metrics-changed', (_e, _display, changed) => {
    if (changed.includes('bounds') || changed.includes('scaleFactor')) scheduleDesktopBackdrop(); // not work-area changes
    if (taskbarWin && !taskbarWin.isDestroyed()) taskbarWin.setBounds(taskbarBounds());
    reserveTaskbarSpace();
  });
}

function closeTaskbarWindow() {
  if (!taskbarWin) return;
  unregisterShellWindow(taskbarWin);
  taskbarWin.allowClose = true;
  taskbarWin.destroy();
  taskbarWin = null;
  clearInterval(taskbarRevealTimer);
  taskbarRevealTimer = null;
}

function onTaskWindows(msg) {
  const present = new Set(msg.windows.map((item) => item.hwnd));
  // Keep each window where it first appeared; new windows join at the end.
  taskWindowOrder = taskWindowOrder.filter((hwnd) => present.has(hwnd));
  for (const item of msg.windows) if (!taskWindowOrder.includes(item.hwnd)) taskWindowOrder.push(item.hwnd);
  lastTaskState = msg;
  sendTaskbarState();
  updateTaskbarHiding();
}

// "Always auto-hide": the bar stays tucked away until the pointer reaches the bottom edge,
// as with the Windows taskbar's own setting. Otherwise, if chosen, only while a window is
// maximised.
function alwaysAutoHide() {
  return taskbarConfig().alwaysAutoHide === true;
}

function updateTaskbarHiding() {
  const zoomed = Boolean(lastTaskState && lastTaskState.zoomed);
  setTaskbarAutoHidden(alwaysAutoHide() || (zoomed && autoHideWhenMaximised()));
  reserveTaskbarSpace();
}

// Unless the bar hides for maximised windows, Windows is told to keep its strip free, so
// maximised windows end above it rather than under it.
function autoHideWhenMaximised() {
  return taskbarConfig().autoHideWhenMaximised === true;
}

let reservedTaskbarSpace = -1;

function reserveTaskbarSpace() {
  const reserve = taskbarWin && !autoHideWhenMaximised() && !alwaysAutoHide();
  const height = reserve ? Math.round(TASKBAR_HEIGHT * screen.getPrimaryDisplay().scaleFactor) : 0;
  if (height === reservedTaskbarSpace) return;
  reservedTaskbarSpace = height;
  sendToHelper('reserve ' + height);
}

let lastTaskbarItems = [];

function taskbarConfig() {
  if (!settings.taskbar) settings.taskbar = { ...taskbarModel.emptyConfig(), showLabels: true };
  return settings.taskbar;
}

// Tags on windows (window-tags.js): which open window holds which remembered tag lives
// here; the tags themselves and where tagged windows sat are kept in settings.taskbar.
const tagState = windowTags.createState();
const TAG_SAVE_DELAY = 2000; // tagged windows move often; their place is saved a little after
let tagSaveTimer = null;
let lastTaskWindows = []; // the bar's windows as last described, for tagging by hwnd

function sendTaskbarState() {
  if (!taskbarWin) return;
  const state = lastTaskState || { windows: [], foreground: '', flashing: [] };
  const byHwnd = new Map(state.windows.map((item) => [item.hwnd, item]));
  const tabCounts = new Map(tabGroups.map((group) => [group.active, group.tabs.length]));
  const windows = decorateWindows(taskWindowOrder.filter((hwnd) => byHwnd.has(hwnd)).map((hwnd) => byHwnd.get(hwnd)));
  if (windowTags.resolve(taskbarConfig(), tagState, windows)) {
    clearTimeout(tagSaveTimer);
    tagSaveTimer = setTimeout(saveSettings, TAG_SAVE_DELAY);
  }
  for (const window of windows) window.tag = windowTags.tagOf(taskbarConfig(), tagState, window.hwnd);
  lastTaskWindows = windows;
  lastTaskbarItems = taskbarModel.buildModel(taskbarConfig(), {
    windows,
    foreground: state.foreground,
    flashing: new Set(state.flashing),
    tabCounts,
    apps,
    labels: settings.labels,
  });
  send(taskbarWin, 'taskbar-state', { items: lastTaskbarItems, showLabels: taskbarConfig().showLabels !== false });
}

function changeTaskbar(change) {
  change(taskbarConfig());
  saveSettings();
  sendTaskbarState();
}

function launchApp(id) {
  spawn('explorer.exe', ['shell:AppsFolder\\' + id], { windowsHide: true, detached: true }).unref();
  settings.recent = [id, ...settings.recent.filter((x) => x !== id)].slice(0, 8);
  settings.launchCounts[id] = (settings.launchCounts[id] || 0) + 1;
  settings.lastUsed[id] = Date.now();
  saveSettings();
  pushState();
}

// Typing needs focus, which the bar never takes; it is allowed it while a name is edited.
let focusBeforeRename = '';

function renameTaskbarFolder(id) {
  // Started from the bar's menu, which had focus itself: the window from before the menu.
  focusBeforeRename = focusBeforeMenu || (lastTaskState ? lastTaskState.foreground : '');
  renamingFolder = true;
  taskbarWin.setFocusable(true);
  sendToHelper('focushwnd ' + nativeHandle(taskbarWin));
  send(taskbarWin, 'taskbar-rename', id);
}

function setTaskbarAutoHidden(hidden) {
  if (hidden === taskbarAutoHidden) return;
  taskbarAutoHidden = hidden;
  taskbarPeeking = false;
  if (taskbarWin) send(taskbarWin, 'taskbar-hidden', hidden || taskbarPeekingNative);
  clearInterval(taskbarRevealTimer);
  taskbarRevealTimer = hidden ? setInterval(checkTaskbarReveal, TASKBAR_REVEAL_POLL) : null;
}

// While hidden: the pointer on the bottom edge reveals the bar, leaving it hides it again.
function checkTaskbarReveal() {
  if (!taskbarWin) return;
  const display = screen.getPrimaryDisplay().bounds;
  const bottom = display.y + display.height;
  const cursor = screen.getCursorScreenPoint();
  const onThisDisplay = cursor.x >= display.x && cursor.x < display.x + display.width;
  if (!taskbarPeeking && onThisDisplay && cursor.y >= bottom - 2) {
    taskbarPeeking = true;
    send(taskbarWin, 'taskbar-hidden', false);
  } else if (taskbarPeeking && (cursor.y < bottom - TASKBAR_HEIGHT || !onThisDisplay) && !taskbarInUse()) {
    taskbarPeeking = false;
    send(taskbarWin, 'taskbar-hidden', true);
  }
}

// Revealed, the bar stays while the pointer is on any of its live parts (a popover, the
// previews, a panel) or one of its menus or panels is open.
function taskbarInUse() {
  const entry = taskbarWin && hitRegions.get(taskbarWin);
  return Boolean((entry && entry.interactive) || openPanel || focusBeforeMenu || renamingFolder);
}

function setTaskbarEnabled(enabled) {
  if (DEV) devTaskbarOn = enabled;
  else {
    settings.customTaskbar = enabled;
    saveSettings();
  }
  if (enabled && !taskbarWin) createTaskbarWindow();
  if (!enabled) {
    closeTaskbarWindow();
    reserveTaskbarSpace();
    sendToHelper('taskbar 0');
    sendToHelper('tray 0');
    sendToHelper('nativetaskbar show');
  }
}

// Remembered so a crash can never leave the Windows taskbar hidden: the next start puts
// it back before (perhaps) hiding it again.
function onNativeTaskbar(msg) {
  settings.nativeTaskbar = msg.hidden ? { hidden: true, originalAutoHide: msg.originalAutoHide } : null;
  saveSettings();
}

// An earlier session that ended with a sign-out (or a crash) left the native taskbar hidden;
// its original setting is passed on, since what the helper would read now is ours.
function hideNativeTaskbar() {
  const remembered = settings.nativeTaskbar;
  sendToHelper('nativetaskbar hide' + (remembered && remembered.hidden ? ' ' + (remembered.originalAutoHide ? 1 : 0) : ''));
}

function restoreNativeTaskbarAfterCrash() {
  const remembered = settings.nativeTaskbar;
  if (!remembered || !remembered.hidden) return;
  sendToHelper('nativetaskbar restore ' + (remembered.originalAutoHide ? 1 : 0));
  settings.nativeTaskbar = null;
  saveSettings();
}

ipcMain.on('taskbar-click', (_e, hwnd) => {
  // Clicking the focused window's pill minimises it, like the Windows taskbar.
  if (lastTaskState && hwnd === lastTaskState.foreground) sendToHelper('minimize ' + hwnd);
  else sendToHelper('activate ' + hwnd);
});

// A pinned app that is not running: start it.
ipcMain.on('taskbar-launch', (_e, key) => {
  if (apps.some((entry) => entry.id === key)) launchApp(key);
  else if (/^[a-z]:\\/i.test(key)) shell.openPath(key);
});

ipcMain.on('taskbar-reorder', (_e, refs) => changeTaskbar((config) => taskbarModel.reorder(config, refs, lastTaskbarItems)));

// Dropped one item on another and held: a folder (or into an existing one).
ipcMain.on('taskbar-merge', (_e, sourceRef, targetRef) => {
  let result = null;
  changeTaskbar((config) => {
    result = taskbarModel.merge(config, sourceRef, targetRef, lastTaskbarItems);
  });
  if (result && result.created) renameTaskbarFolder(result.id);
});

ipcMain.on('taskbar-rename', (_e, id, name) => {
  renamingFolder = false;
  if (taskbarWin) taskbarWin.setFocusable(false);
  // Typing is done: the window that had focus before gets it back.
  if (focusBeforeRename) sendToHelper('activate ' + focusBeforeRename);
  focusBeforeRename = '';
  if (name) changeTaskbar((config) => taskbarModel.rename(config, id, name));
});

// ---------- quick settings and calendar ----------

// Our own panels for the status glyphs and the clock, drawn in the taskbar's window above
// the bar. While one is open that window has focus, and another window becoming the
// foreground one (a click anywhere else) closes it, as with the Windows flyouts. Electron's
// own blur is no use here: switching click-through on and off fires it spuriously.
const SYSTEM_POLL_MILLISECONDS = 1500;
const TOAST_HISTORY_LIMIT = 20;
const toastHistory = []; // newest first; the calendar panel lists them
let openPanel = null;
let focusBeforePanel = '';
let systemPollTimer = null;

function openTaskbarPanel(kind, extra = {}) {
  if (!taskbarWin || taskbarWin.isDestroyed()) return;
  // Opened from the bar's menu (New tag...), the window to go back to is the one from
  // before the menu, and the menu must not hand focus back itself: the panel would see that
  // as a click elsewhere and close.
  if (!openPanel) focusBeforePanel = focusBeforeMenu || (lastTaskState ? lastTaskState.foreground : '');
  focusBeforeMenu = '';
  openPanel = kind;
  taskbarWin.setFocusable(true);
  if (!taskbarWin.isFocused()) sendToHelper('focushwnd ' + nativeHandle(taskbarWin)); // already focused when switching panels
  clearInterval(systemPollTimer);
  systemPollTimer = null;
  if (kind === 'quick') {
    refreshSystemState(true);
    systemPollTimer = setInterval(() => refreshSystemState(false), SYSTEM_POLL_MILLISECONDS);
  } else if (kind === 'calendar') {
    pollNotifications(NOTIFICATION_POLL_OPEN);
  }
  send(taskbarWin, 'panel', {
    kind,
    notifications: toastHistory,
    windowsNotifications,
    tags: taskbarConfig().tags || [],
    colors: windowTags.COLORS,
    ...extra,
  });
}

// `restoreFocus`: closed from the panel itself (Escape, its button), so the window that
// had focus gets it back; a click elsewhere has already put focus where it belongs.
function closeTaskbarPanel(restoreFocus) {
  if (!openPanel) return;
  if (openPanel === 'calendar') pollNotifications(NOTIFICATION_POLL_IDLE);
  openPanel = null;
  clearInterval(systemPollTimer);
  systemPollTimer = null;
  if (taskbarWin && !taskbarWin.isDestroyed()) {
    taskbarWin.setFocusable(false);
    send(taskbarWin, 'panel', null);
  }
  if (restoreFocus && focusBeforePanel) sendToHelper('activate ' + focusBeforePanel);
  focusBeforePanel = '';
}

function refreshSystemState(withNetwork) {
  sendToHelper('system');
  if (withNetwork) readWifi().then((wifi) => send(taskbarWin, 'network-state', wifi));
}

// The connected Wi-Fi network's name and signal, or null (wired, or not connected).
function readWifi() {
  return new Promise((resolve) => {
    execFile('netsh', ['wlan', 'show', 'interfaces'], { windowsHide: true, timeout: 3000 }, (error, stdout) => {
      if (error) return resolve(null);
      const field = (name) => {
        const match = String(stdout).match(new RegExp('^\\s*' + name + '\\s*:\\s*(.+)$', 'm'));
        return match ? match[1].trim() : '';
      };
      const ssid = field('SSID');
      const signal = parseInt(field('Signal'), 10);
      resolve(ssid ? { ssid, signal: Number.isFinite(signal) ? signal : null } : null);
    });
  });
}

function onSystemState(msg) {
  const media = msg.media && { ...msg.media, appName: (apps.find((item) => item.id === msg.media.app) || {}).name || '' };
  send(taskbarWin, 'system-state', { speakers: msg.speakers, wifi: msg.wifi, bluetooth: msg.bluetooth, media });
}

const PANEL_SETTINGS_PAGES = {
  network: 'ms-settings:network-wifi',
  bluetooth: 'ms-settings:bluetooth',
  sound: 'ms-settings:sound',
  notifications: 'ms-settings:notifications',
  datetime: 'ms-settings:dateandtime',
  settings: 'ms-settings:',
};

ipcMain.on('panel-open', (_e, kind) => {
  if (kind === 'quick' || kind === 'calendar' || kind === 'tray') openTaskbarPanel(kind);
});
ipcMain.on('panel-close', () => closeTaskbarPanel(true));

// ---------- tray icons ----------

// The apps' notification-area icons, hosted by the helper (TrayHost.cs), shown in the
// chevron's flyout. A click goes back to the app as Explorer would send it, with the
// icon's centre in physical pixels for apps that place a menu there.
let trayIcons = [];

function onTrayIcons(icons) {
  trayIcons = icons;
  send(taskbarWin, 'tray-icons', trayIcons);
}

ipcMain.on('tray-click', (_e, id, button, x, y) => {
  if (!['left', 'right', 'double'].includes(button)) return;
  const point = screen.dipToScreenPoint({ x: Math.round(x), y: Math.round(y) });
  sendToHelper('trayclick ' + JSON.stringify({ id: String(id), button, x: point.x, y: point.y }));
});
ipcMain.on('system-set', (_e, line) => {
  const command = String(line);
  if (/^(volume \d{1,3}|mute [01]|radio (wifi|bluetooth) [01]|media (playpause|next|previous))$/.test(command)) sendToHelper(command);
});
ipcMain.on('open-settings', (_e, page) => {
  if (!PANEL_SETTINGS_PAGES[page]) return;
  closeTaskbarPanel(false);
  shell.openExternal(PANEL_SETTINGS_PAGES[page]);
});
ipcMain.on('clear-notifications', () => {
  toastHistory.length = 0;
  sendToHelper('notifications clear'); // Windows' notification centre too
});

// Windows' own notifications (NotificationCentre.cs), listed in the calendar panel with ours.
// Windows takes a couple of seconds to list them and does not say when they change, so the
// list is kept up to date in the background, more often while the calendar is open, and
// the panel opens with it at once.
const NOTIFICATION_POLL_IDLE = 10000;
const NOTIFICATION_POLL_OPEN = 3000;
let windowsNotifications = [];
let notificationTimer = null;

function pollNotifications(every) {
  clearInterval(notificationTimer);
  notificationTimer = taskbarWin ? setInterval(() => sendToHelper('notifications'), every) : null;
  if (taskbarWin) sendToHelper('notifications');
}

ipcMain.on('notification-dismiss', (_e, source, id) => {
  if (source === 'windows' && /^\d+$/.test(String(id))) sendToHelper('notifications dismiss ' + id);
  if (source === 'ours') {
    const index = toastHistory.findIndex((note) => String(note.time) === String(id));
    if (index >= 0) toastHistory.splice(index, 1);
  }
});

// A notification's app: started (or brought back) the way the launcher starts apps.
ipcMain.on('notification-open', (_e, appId) => {
  if (typeof appId !== 'string' || !appId || /["\r\n]/.test(appId)) return; // passed as an argument, no shell
  closeTaskbarPanel(false);
  spawn('explorer.exe', ['shell:AppsFolder\\' + appId], { windowsHide: true, detached: true }).unref();
});

// Where the pointer is, relative to the bar's window: the page cannot see it once it
// leaves the window, so it asks while a popover or previews are open.
ipcMain.handle('taskbar-cursor', () => {
  if (!taskbarWin || taskbarWin.isDestroyed()) return null;
  const cursor = screen.getCursorScreenPoint();
  const bounds = taskbarWin.getBounds();
  return { x: cursor.x - bounds.x, y: cursor.y - bounds.y };
});

// Live window pictures above a hovered pill, drawn by the helper's DWM overlay.
ipcMain.on('taskbar-preview', (_e, slots) => {
  if (!taskbarWin) return;
  if (!slots || !slots.length) {
    sendToHelper('thumbsclear');
    return;
  }
  // The overlay covers just the wells, not the whole taskbar window, so it never hides
  // the bar from anything that checks what is on screen.
  const window = screen.dipToScreenRect(taskbarWin, taskbarWin.getBounds());
  const left = Math.min(...slots.map((slot) => slot.x));
  const top = Math.min(...slots.map((slot) => slot.y));
  const right = Math.max(...slots.map((slot) => slot.x + slot.w));
  const bottom = Math.max(...slots.map((slot) => slot.y + slot.h));
  const relative = slots.map((slot) => ({ ...slot, x: slot.x - left, y: slot.y - top }));
  sendToHelper(`thumbs ${window.x + left} ${window.y + top} ${right - left} ${bottom - top} ${JSON.stringify(relative)}`);
});

// A popup menu closes on a click elsewhere only while its window has focus, which the bar
// otherwise never takes. So it gets focus for as long as its menu is open; afterwards the
// window that had focus gets it back, unless a click elsewhere has already moved it on.
const MENU_FOCUS_WAIT = 300;
let focusBeforeMenu = '';
let renamingFolder = false; // Rename keeps the focus the menu had

function popupTaskbarMenu(menu) {
  focusBeforeMenu = lastTaskState ? lastTaskState.foreground : '';
  taskbarWin.setFocusable(true);
  sendToHelper('focushwnd ' + nativeHandle(taskbarWin));
  const startedAt = Date.now();
  const open = () => {
    if (!taskbarWin || taskbarWin.isDestroyed()) return;
    if (!taskbarWin.isFocused() && Date.now() - startedAt < MENU_FOCUS_WAIT) {
      setTimeout(open, 20);
      return;
    }
    menu.popup({ window: taskbarWin, callback: () => setTimeout(menuClosed, 0) }); // after the picked item's click
  };
  open();
}

function menuClosed() {
  // Rename and the panels (New tag...) take over the focus the menu had, and give it back
  // themselves.
  if (renamingFolder || openPanel || !taskbarWin || taskbarWin.isDestroyed()) return;
  const stillOurs = taskbarWin.isFocused();
  taskbarWin.setFocusable(false);
  if (stillOurs && focusBeforeMenu) sendToHelper('activate ' + focusBeforeMenu);
  focusBeforeMenu = '';
}

// The tags to choose from for one window, a new one, or none.
function tagMenu(hwnd) {
  const config = taskbarConfig();
  const current = windowTags.tagOf(config, tagState, hwnd);
  const tags = (config.tags || []).map((tag) => ({
    label: tag.name,
    type: 'checkbox',
    checked: Boolean(current && current.id === tag.id),
    click: () => setWindowTag(hwnd, current && current.id === tag.id ? null : tag.id),
  }));
  return [
    ...tags,
    { type: 'separator', visible: tags.length > 0 },
    { label: 'New tag...', click: () => openTaskbarPanel('tag', { hwnd, title: (lastTaskWindows.find((window) => window.hwnd === hwnd) || {}).title || '' }) },
    { label: 'Remove tag', visible: Boolean(current), click: () => setWindowTag(hwnd, null) },
  ];
}

function setWindowTag(hwnd, tagId) {
  const window = lastTaskWindows.find((item) => item.hwnd === hwnd);
  if (!window) return;
  changeTaskbar((config) => windowTags.tagWindow(config, tagState, window, tagId));
}

const menuTitle = (title) => (title.length > 48 ? title.slice(0, 47) + '…' : title) || 'Untitled window';

ipcMain.on('tag-create', (_e, hwnd, name, color) => {
  if (!String(name || '').trim()) return;
  const config = taskbarConfig();
  const tag = windowTags.createTag(config, name, color);
  setWindowTag(String(hwnd), tag.id);
  closeTaskbarPanel(true);
});

ipcMain.on('taskbar-context', (_e, target) => {
  const config = taskbarConfig();
  // The pin button in a folder's popover.
  if (target.kind === 'folder-pin') {
    const folder = config.items.find((stored) => stored.type === 'folder' && stored.id === target.id);
    if (folder) changeTaskbar((c) => taskbarModel.setFolderPinned(c, target.id, !folder.pinned));
    return;
  }
  const item = target.ref ? lastTaskbarItems.find((candidate) => candidate.ref === target.ref) : null;
  let template;
  if (target.kind === 'app' && item) {
    const app = target.folderId ? lastTaskbarItems.find((candidate) => candidate.id === target.folderId).apps.find((member) => member.key === target.key) : item;
    const separated = (config.separate || []).includes(app.key);
    template = [
      target.folderId
        ? { label: 'Remove from folder', click: () => changeTaskbar((c) => taskbarModel.removeFromFolder(c, target.folderId, app.key)) }
        : { label: app.pinned ? 'Unpin from taskbar' : 'Pin to taskbar', click: () => changeTaskbar((c) => taskbarModel.setPinned(c, app, !app.pinned)) },
      // Just this app: its windows as separate pills, or back into one.
      {
        label: 'Show windows separately',
        visible: !target.folderId && config.combine && !separated && app.windows.length > 1,
        click: () => changeTaskbar((c) => taskbarModel.setSeparate(c, app.key, true)),
      },
      {
        label: 'Group windows',
        visible: !target.folderId && config.combine && separated,
        click: () => changeTaskbar((c) => taskbarModel.setSeparate(c, app.key, false)),
      },
      { type: 'separator', visible: app.windows.length > 0 },
      app.windows.length === 1
        ? { label: 'Tag window', submenu: tagMenu(app.windows[0].hwnd) }
        : { label: 'Tag a window', visible: app.windows.length > 1, submenu: app.windows.map((window) => ({ label: menuTitle(window.title), submenu: tagMenu(window.hwnd) })) },
      { label: 'Minimise', visible: app.windows.length === 1, click: () => sendToHelper('minimize ' + app.windows[0].hwnd) },
      {
        label: app.windows.length > 1 ? `Close all ${app.windows.length} windows` : 'Close window',
        visible: app.windows.length > 0,
        click: () => app.windows.forEach((window) => sendToHelper('closewin ' + window.hwnd)),
      },
    ];
  } else if (target.kind === 'window' && target.hwnd) {
    // A window's row in a popover.
    template = [
      { label: 'Tag window', submenu: tagMenu(target.hwnd) },
      { type: 'separator' },
      { label: 'Minimise', click: () => sendToHelper('minimize ' + target.hwnd) },
      { label: 'Close window', click: () => sendToHelper('closewin ' + target.hwnd) },
    ];
  } else if (target.kind === 'folder' && item) {
    template = [
      { label: 'Rename', click: () => renameTaskbarFolder(item.id) },
      { label: item.pinned ? 'Unpin folder' : 'Pin folder', click: () => changeTaskbar((c) => taskbarModel.setFolderPinned(c, item.id, !item.pinned)) },
      { label: item.label ? 'Remove category' : 'Ungroup', click: () => changeTaskbar((c) => (item.label ? taskbarModel.setFolderPinned(c, item.id, false) : taskbarModel.ungroup(c, item.id))) },
    ];
  } else {
    template = [
      { label: 'Show app names', type: 'checkbox', checked: config.showLabels !== false, click: (menuItem) => changeTaskbar((c) => { c.showLabels = menuItem.checked; }) },
      { label: 'Combine windows of the same app', type: 'checkbox', checked: config.combine, click: (menuItem) => changeTaskbar((c) => { c.combine = menuItem.checked; }) },
      {
        label: 'Always auto-hide',
        type: 'checkbox',
        checked: config.alwaysAutoHide === true,
        click: (menuItem) => {
          changeTaskbar((c) => { c.alwaysAutoHide = menuItem.checked; });
          updateTaskbarHiding();
        },
      },
      {
        label: 'Auto-hide when a window is maximised',
        type: 'checkbox',
        checked: config.autoHideWhenMaximised === true,
        enabled: config.alwaysAutoHide !== true,
        click: (menuItem) => {
          changeTaskbar((c) => { c.autoHideWhenMaximised = menuItem.checked; });
          updateTaskbarHiding();
        },
      },
      { type: 'separator' },
      {
        label: 'Pin category',
        submenu: taskbarModel.LABELS.map((label) => ({
          label,
          type: 'checkbox',
          checked: config.items.some((stored) => stored.type === 'folder' && stored.label === label && stored.pinned),
          click: (menuItem) => changeTaskbar((c) => {
            if (menuItem.checked) taskbarModel.pinCategory(c, label);
            else {
              const folder = c.items.find((stored) => stored.type === 'folder' && stored.label === label);
              if (folder) taskbarModel.setFolderPinned(c, folder.id, false);
            }
          }),
        })),
      },
      { type: 'separator' },
      { label: 'Show the Windows taskbar', click: () => sendToHelper('nativetaskbar peek') },
      {
        label: 'Delete tag',
        visible: (config.tags || []).length > 0,
        submenu: (config.tags || []).map((tag) => ({ label: tag.name, click: () => changeTaskbar((c) => windowTags.deleteTag(c, tagState, tag.id)) })),
      },
      { type: 'separator' },
      { label: 'Taskbar settings', click: () => openSettingsWindow() },
    ];
  }
  popupTaskbarMenu(Menu.buildFromTemplate(template));
});

ipcMain.on('taskbar-home', () => toggleMenu('launcher'));
ipcMain.on('taskbar-key', (_e, letter) => {
  if (/^[AN]$/.test(letter)) sendToHelper('winkey ' + letter);
});
// The chevron: Windows' own hidden-icons flyout, without its taskbar.
ipcMain.on('taskbar-peek', () => sendToHelper('nativetaskbar overflow'));

ipcMain.on('tab-activate', (_e, hwnd) => sendToHelper('tabactivate ' + hwnd));
ipcMain.on('tab-close', (_e, hwnd) => sendToHelper('tabclose ' + hwnd));
ipcMain.on('tab-split', (_e, hwnd) => sendToHelper('tabsplit ' + hwnd));
ipcMain.on('strip-drag', (_e, hwnd) => sendToHelper('dragmove ' + hwnd));
// ---------- click-through overlays ----------

// The taskbar, tab strips and toasts are windows larger than what they draw, and must let
// clicks through everywhere else. Each page tells main which parts of it are live (the bar,
// an open card, a strip), and main makes the window take the mouse exactly while the
// pointer is over one of them. This is decided here from the real pointer position, never
// from forwarded mouse moves, which Windows does not deliver reliably.
const HIT_TEST_INTERVAL = 33;
const hitRegions = new Map(); // BrowserWindow -> { rects: [{ x, y, width, height }] | 'capture', interactive }
let hitTestTimer = null;

function updateHitTesting() {
  const cursor = screen.getCursorScreenPoint();
  for (const [browserWindow, entry] of hitRegions) {
    if (browserWindow.isDestroyed()) {
      hitRegions.delete(browserWindow);
      continue;
    }
    let inside = false;
    if (entry.rects === 'capture') inside = true; // a drag or a rename in progress keeps the mouse
    else if (browserWindow.isVisible()) {
      const bounds = browserWindow.getBounds();
      inside = entry.rects.some((rect) => cursor.x >= bounds.x + rect.x && cursor.x < bounds.x + rect.x + rect.width
        && cursor.y >= bounds.y + rect.y && cursor.y < bounds.y + rect.y + rect.height);
    }
    if (inside === entry.interactive) continue;
    entry.interactive = inside;
    // Windows tells a page neither that the pointer arrived (it may be resting there already:
    // it jumped, or the bar slid up under it) nor that it left once clicks pass through, so
    // the page is told both here and hover starts and ends where it should.
    const bounds = browserWindow.getBounds();
    if (!inside) browserWindow.webContents.sendInputEvent({ type: 'mouseLeave', x: -1, y: -1 });
    else if (entry.rects !== 'capture') browserWindow.webContents.sendInputEvent({ type: 'mouseMove', x: cursor.x - bounds.x, y: cursor.y - bounds.y });
    if (DEV) console.log('[hit] ' + browserWindow.webContents.getURL().split('/').pop() + ' ' + (inside ? 'takes' : 'passes') + ' the mouse at ' + cursor.x + ',' + cursor.y);
    browserWindow.setIgnoreMouseEvents(!inside, { forward: true });
  }
}

ipcMain.on('hit-regions', (e, rects) => {
  const browserWindow = BrowserWindow.fromWebContents(e.sender);
  if (!browserWindow) return;
  const entry = hitRegions.get(browserWindow) || { interactive: false };
  entry.rects = rects === 'capture' ? 'capture' : Array.isArray(rects) ? rects : [];
  hitRegions.set(browserWindow, entry);
  updateHitTesting();
  if (!hitTestTimer) hitTestTimer = setInterval(updateHitTesting, HIT_TEST_INTERVAL);
});

function switcherEnabled() {
  return DEV ? devAltTabOn : settings.replaceAltTab;
}

function createSwitcherWindow() {
  switcherWin = new BrowserWindow({
    width: 800,
    height: 600,
    show: false,
    frame: false,
    transparent: true,
    backgroundColor: '#00000000',
    resizable: false,
    skipTaskbar: true,
    focusable: false,
    alwaysOnTop: true,
    fullscreenable: false,
    webPreferences: {
      preload: path.join(__dirname, 'preload.js'),
      backgroundThrottling: false,
    },
  });
  switcherWin.setAlwaysOnTop(true, 'screen-saver');
  switcherWin.loadFile('renderer/switcher.html');
  registerShellWindow(switcherWin);
  switcherWin.on('close', (e) => {
    if (!quitting) e.preventDefault();
  });
  switcherWin.webContents.on('did-finish-load', () => {
    switcherLoaded = true;
    parkSwitcher();
    if (switcherPreviewPending) sendToHelper('listwindows');
  });
}

function parkSwitcher() {
  switcherWin.setBounds(parkedBounds());
  switcherWin.setOpacity(0);
  switcherWin.setIgnoreMouseEvents(true);
  switcherWin.showInactive();
}

// Match each window to its Start entry (Store apps by AppUserModelID, desktop apps by
// executable path) for the app's icon and identifier; otherwise use the exe's icon.
function decorateWindows(windows) {
  const byId = new Map(apps.map((entry) => [entry.id.toLowerCase(), entry]));
  return windows.map((item) => {
    const entry = (item.aumid && byId.get(item.aumid.toLowerCase())) || (item.exe && byId.get(item.exe.toLowerCase()));
    const exeName = item.exe ? path.basename(item.exe, path.extname(item.exe)) : '';
    return {
      hwnd: item.hwnd,
      title: item.title,
      minimized: item.minimized,
      zoomed: item.zoomed,
      bounds: item.bounds,
      icon: (entry && entry.icon) || item.icon,
      alias: entry ? appAliases[entry.id] || '' : '',
      key: entry ? entry.id : item.aumid || item.exe || item.hwnd,
      name: entry ? entry.name : exeName || item.title,
    };
  });
}

function showSwitcher(windows, reverse) {
  switcherWindows = decorateWindows(windows);
  if (switcherWindows.length === 0) {
    sendToHelper('switcherdone');
    return;
  }
  // The first window is the one you are in, so Alt+Tab lands on the one before it.
  switcherIndex = reverse ? switcherWindows.length - 1 : Math.min(1, switcherWindows.length - 1);
  switcherVisible = true;
  switcherWin.setBounds(menuBounds());
  switcherWin.setIgnoreMouseEvents(false);
  switcherWin.setOpacity(SHOWN_OPACITY);
  switcherWin.setAlwaysOnTop(true, 'screen-saver');
  switcherWin.moveTop();
  send(switcherWin, 'switcher-state', { windows: switcherWindows, index: switcherIndex });
}

function hideSwitcher() {
  if (!switcherVisible) return;
  switcherVisible = false;
  sendToHelper('thumbsclear');
  send(switcherWin, 'switcher-reset');
  parkSwitcher();
}

function moveSwitcherSelection(step) {
  if (!switcherVisible || switcherWindows.length === 0) return;
  switcherIndex = (switcherIndex + step + switcherWindows.length) % switcherWindows.length;
  send(switcherWin, 'switcher-select', switcherIndex);
}

function commitSwitcher(index) {
  const target = switcherWindows[index];
  hideSwitcher();
  if (target) sendToHelper('activate ' + target.hwnd);
}

function onSwitcherAction(msg) {
  switch (msg.action) {
    case 'open':
    case 'open-reverse':
      showSwitcher(msg.windows, msg.action === 'open-reverse');
      break;
    case 'next': moveSwitcherSelection(1); break;
    case 'prev': moveSwitcherSelection(-1); break;
    case 'commit': commitSwitcher(switcherIndex); break;
    case 'cancel': hideSwitcher(); break;
    case 'close': {
      const target = switcherWindows[switcherIndex];
      if (!target) break;
      sendToHelper('closewin ' + target.hwnd);
      // Give the app a moment to close (it may ask to save), then refresh the cards.
      setTimeout(() => sendToHelper('listwindows'), 300);
      break;
    }
  }
}

// A fresh window list arrives after closing a window, or for a dev preview.
function onWindowList(windows) {
  if (switcherPreviewPending) {
    switcherPreviewPending = false;
    showSwitcher(windows, false);
    return;
  }
  if (!switcherVisible) return;
  switcherWindows = decorateWindows(windows);
  if (switcherWindows.length === 0) {
    sendToHelper('switcherdone');
    hideSwitcher();
    return;
  }
  switcherIndex = Math.min(switcherIndex, switcherWindows.length - 1);
  send(switcherWin, 'switcher-state', { windows: switcherWindows, index: switcherIndex });
}

function previewSwitcher() {
  switcherPreviewPending = true;
  // Before the page has loaded, the list would arrive with nothing to draw it; the
  // load handler sends the request instead.
  if (switcherLoaded) sendToHelper('listwindows');
}

function setSwitcherEnabled(enabled) {
  if (DEV) devAltTabOn = enabled;
  else {
    settings.replaceAltTab = enabled;
    saveSettings();
  }
  sendToHelper('alttab ' + (enabled ? 1 : 0));
}

ipcMain.on('switcher-layout', (_e, slots) => {
  if (!switcherVisible) return;
  const bounds = screen.dipToScreenRect(switcherWin, switcherWin.getBounds());
  sendToHelper(`thumbs ${bounds.x} ${bounds.y} ${bounds.width} ${bounds.height} ${JSON.stringify(slots)}`);
});

ipcMain.on('switcher-pick', (_e, index) => {
  sendToHelper('switcherdone');
  commitSwitcher(index);
});

ipcMain.on('switcher-cancel', () => {
  sendToHelper('switcherdone');
  hideSwitcher();
});

ipcMain.on('aliases', (_e, aliases) => {
  appAliases = aliases;
});

// Windows can be destroyed while the helper is still talking (during quit, or a strip
// closing), and sending to one throws, so every send goes through here.
function send(target, channel, ...args) {
  if (target && !target.isDestroyed()) target.webContents.send(channel, ...args);
}

const nativeHandle = (browserWindow) => browserWindow.getNativeWindowHandle().readBigUInt64LE(0).toString();

// Shell surfaces (launcher, Home, switcher, strips, taskbar) are registered with the
// helper so it never mistakes them for app windows. Files windows are not registered:
// they are real windows that belong in Alt+Tab, the taskbar and tab groups.
const shellWindows = new Set();

function registerShellWindow(browserWindow) {
  shellWindows.add(browserWindow);
  // Dev: every shell page's console lands in the terminal, labelled with its page.
  if (DEV) {
    browserWindow.webContents.on('console-message', (event) => {
      const page = path.basename(new URL(browserWindow.webContents.getURL() || 'file:///unknown').pathname, '.html');
      if (browserWindow !== win) console.log(`[${page}:${event.level}] ${event.message}`); // the dev window logs its own
    });
  }
  sendToHelper('shellwindow ' + nativeHandle(browserWindow));
  browserWindow.once('closed', () => shellWindows.delete(browserWindow));
}

function unregisterShellWindow(browserWindow) {
  if (!shellWindows.delete(browserWindow)) return;
  sendToHelper('unshellwindow ' + nativeHandle(browserWindow));
}

// The greeting uses the account's full name ("Joe"), falling back to the username.
let displayName = '';

function loadDisplayName() {
  const script = '([adsi]"WinNT://$env:COMPUTERNAME/$env:USERNAME,user").FullName';
  execFile('powershell.exe', ['-NoProfile', '-Command', script], { windowsHide: true }, (error, stdout) => {
    const fullName = error ? '' : String(stdout).trim();
    displayName = fullName.split(/\s+/)[0] || '';
    pushState();
  });
}

let menuVisible = false;

// The menu window is never truly hidden. When "closed" it parks at opacity 0
// (click-through, unfocused) so Chromium's compositor keeps a warm surface with an
// already-reset frame — otherwise the surface is dropped while hidden and the next
// show paints stale content first, then repaints (a visible double-open flash).
// The window covers the whole display under the cursor: the renderer draws the
// dimming scrim across it and the launcher panel on top. Bounds are also applied
// when parking, so the pre-rendered frame already has the right size for the next
// show (a resize at show time would repaint and bring back the flash).
function menuBounds() {
  return screen.getDisplayNearestPoint(screen.getCursorScreenPoint()).bounds;
}

// Shown full-screen overlays stay a hair short of opaque. Browsers treat a fully opaque
// window covering theirs as the tab being hidden, and pop a playing video out into
// picture-in-picture; at 99% they still count as visible. The difference cannot be seen.
const SHOWN_OPACITY = 0.99;

// Parked overlays (the launcher, the switcher) wait unseen, ready to appear at once, a pixel
// short of the whole screen so Windows does not take them for a full-screen app and hold
// notifications back (see homeBounds). They take the full screen only while shown.
function parkedBounds() {
  return shortOfFullScreen(menuBounds());
}

function parkWindow() {
  win.setBounds(parkedBounds());
  win.setOpacity(0);
  win.setIgnoreMouseEvents(true);
  win.showInactive();
}

// The launcher window has two modes: the full launcher (Win key) and the compact,
// results-only command palette (Alt+Space).
let menuMode = 'launcher';

// Our overlays (the bar, toasts, strips, the launcher) pass focus among themselves while a
// panel opens; only a real app window becoming the foreground one counts as "elsewhere".
function isShellWindowHandle(hwnd) {
  for (const browserWindow of shellWindows) {
    if (!browserWindow.isDestroyed() && nativeHandle(browserWindow) === hwnd) return true;
  }
  return false;
}

function showMenu(mode = 'launcher') {
  closeTaskbarPanel(false);
  menuMode = mode;
  if (DEV) {
    win.show();
    win.focus();
    send(win, 'shown', mode);
    setImmediate(refreshRecentItems);
    return;
  }
  win.setBounds(menuBounds());
  win.setIgnoreMouseEvents(false);
  if (!win.isVisible()) win.showInactive();
  win.setOpacity(SHOWN_OPACITY);
  win.setAlwaysOnTop(true, 'screen-saver'); // re-assert in case another topmost window outranked us
  win.moveTop();
  // Windows blocks SetForegroundWindow from background processes, so the helper
  // does the synthetic-Alt unlock for us.
  sendToHelper('focus');
  send(win, 'shown', mode); // focus the search box
  menuVisible = true;
  setImmediate(refreshRecentItems);
}

function hideMenu() {
  if (DEV) {
    send(win, 'reset'); // the dev window stays put; just clear the UI
    return;
  }
  if (!menuVisible) return;
  menuVisible = false;
  win.hide(); // natural focus handoff back to the previously active window
  send(win, 'reset'); // repaint to a clean state while invisible
  parkWindow();
}

function toggleMenu(mode = 'launcher') {
  if (menuVisible && menuMode === mode) hideMenu();
  else showMenu(mode);
}

// ---------- Toasts ----------

// The shell's own notifications (Toast in the design): one click-through window in the
// top-right corner, shown only while a toast is on screen.
const TOAST_AREA = { width: 392, height: 560 }; // toast-width plus space-4 margins, three cards
const toastActions = new Map();
let restoredTabCount = 0;
let restoredTabTimer = null;
let nextToastAction = 1;

function createToastWindow() {
  toastWin = new BrowserWindow({
    width: TOAST_AREA.width,
    height: TOAST_AREA.height,
    show: false,
    frame: false,
    transparent: true,
    backgroundColor: '#00000000',
    resizable: false,
    skipTaskbar: true,
    focusable: false,
    hasShadow: false,
    fullscreenable: false,
    alwaysOnTop: true,
    webPreferences: {
      preload: path.join(__dirname, 'preload.js'),
      backgroundThrottling: false,
    },
  });
  toastWin.setAlwaysOnTop(true, 'pop-up-menu');
  toastWin.setIgnoreMouseEvents(true, { forward: true });
  toastWin.loadFile('renderer/toast.html');
  registerShellWindow(toastWin);
  toastWin.on('close', (e) => {
    if (!quitting) e.preventDefault();
  });
}

/**
 * Shows a toast. `actions` are up to two { label, run } buttons.
 * @param {{ title: string, text?: string, kind?: 'info' | 'error', actions?: { label: string, run: () => void }[] }} message
 */
function showToast(message) {
  if (!toastWin || toastWin.isDestroyed()) return;
  const deliver = () => {
    const area = screen.getPrimaryDisplay().workArea;
    toastWin.setBounds({ x: area.x + area.width - TOAST_AREA.width, y: area.y, ...TOAST_AREA });
    if (!toastWin.isVisible()) toastWin.showInactive();
    const actions = (message.actions || []).map((action) => {
      const id = String(nextToastAction++);
      toastActions.set(id, action.run);
      return { id, label: action.label };
    });
    send(toastWin, 'toast', { title: message.title, text: message.text, kind: message.kind, actions });
    toastHistory.unshift({ title: message.title, text: message.text || '', kind: message.kind || 'info', time: Date.now() });
    toastHistory.length = Math.min(toastHistory.length, TOAST_HISTORY_LIMIT);
  };
  if (toastWin.webContents.isLoading()) toastWin.webContents.once('did-finish-load', deliver);
  else deliver();
}

ipcMain.on('toast-action', (_e, id) => {
  const run = toastActions.get(id);
  toastActions.delete(id);
  if (run) run();
});

ipcMain.on('toast-empty', () => {
  if (toastWin) toastWin.hide();
  toastActions.clear();
});

// ---------- Files ----------

// Files windows are ordinary app windows (not registered as shell surfaces), so they show
// in Alt+Tab and on the taskbar and can be grouped into tabs like any other window.
const filesWindows = new Set();
// `npm run dev -- --files` makes Win+E open Files for that run.
let devFilesOn = process.argv.includes('--files');

function filesOnWinE() {
  return DEV ? devFilesOn : settings.filesOnWinE;
}

function setFilesOnWinE(enabled) {
  if (DEV) devFilesOn = enabled;
  else {
    settings.filesOnWinE = enabled;
    saveSettings();
  }
  sendToHelper('filese ' + (enabled ? 1 : 0));
}

function startFiles() {
  setupFiles({
    preload: path.join(__dirname, 'preload.js'),
    settings: () => settings,
    save: saveSettings,
    recentItems: () => recentItems,
    dragIcon: path.join(__dirname, 'assets', 'tray.png'),
    showShellMenu: (request) => sendToHelper('shellmenu ' + JSON.stringify(request)),
    pickShellMenu: (session, id) => sendToHelper(`shellmenupick ${session} ${id}`),
    setClipboardFiles: (mode, paths) => sendToHelper(`setclipfiles ${mode === 'move' ? 'move' : 'copy'} ${JSON.stringify(paths)}`),
    onCreated: (filesWindow) => {
      filesWindows.add(filesWindow);
      sendToHelper('notabs ' + nativeHandle(filesWindow)); // Files has tabs of its own
      filesWindow.on('closed', () => filesWindows.delete(filesWindow));
      if (DEV) filesWindow.webContents.on('console-message', (e) => console.log(`[files:${e.level}] ${e.message}`));
    },
  });
}

// `npm run dev -- --palette` turns the Alt+Space hook on for that run.
let devPaletteOn = process.argv.includes('--palette');

function paletteEnabled() {
  return DEV ? devPaletteOn : settings.paletteHotkey;
}

function setPaletteEnabled(enabled) {
  if (DEV) devPaletteOn = enabled;
  else {
    settings.paletteHotkey = enabled;
    saveSettings();
  }
  sendToHelper('palette ' + (enabled ? 1 : 0));
}

// ---------- helper sidecar ----------

function helperPath() {
  return app.isPackaged
    ? path.join(process.resourcesPath, 'helper', 'WinKeyHelper.exe')
    : path.join(__dirname, 'helper', 'bin', 'Release', 'net10.0-windows10.0.19041.0', 'WinKeyHelper.exe');
}

function startHelper() {
  // Detached: otherwise Windows ends the helper together with Electron if Electron is
  // killed, and it never gets to show hidden tabs or put the Windows taskbar back. On its
  // own it notices Electron is gone (stdin closes), restores everything, then exits.
  helper = spawn(helperPath(), [], { windowsHide: true, detached: true });

  readline.createInterface({ input: helper.stdout }).on('line', (line) => {
    let msg;
    try { msg = JSON.parse(line.replace(/^\uFEFF/, '')); } catch { return; }
    onHelperEvent(msg);
  });
  // A write racing the helper's exit (EPIPE) must not become an uncaught error.
  helper.stdin.on('error', () => {});
  helper.stderr.on('data', (d) => console.error('[helper]', d.toString().trim()));
  helper.on('exit', () => {
    helper = null;
    if (quitting) return;
    setTimeout(startHelper, 1000); // keep the hook alive
    showToast({ title: 'The helper stopped and was restarted', text: 'Shortcuts, tabs and the taskbar carry on as before.', kind: 'error' });
  });

  sendToHelper('enable ' + (hooksEnabled() ? 1 : 0));
  sendToHelper('hwnd ' + nativeHandle(win));
  sendToHelper('ownpid ' + process.pid);
  for (const browserWindow of shellWindows) {
    if (!browserWindow.isDestroyed()) sendToHelper('shellwindow ' + nativeHandle(browserWindow));
  }
  for (const filesWindow of filesWindows) {
    if (!filesWindow.isDestroyed()) sendToHelper('notabs ' + nativeHandle(filesWindow));
  }
  reservedTaskbarSpace = -1; // a fresh helper holds no reservation
  sendToHelper('alttab ' + (switcherEnabled() ? 1 : 0));
  sendToHelper('palette ' + (paletteEnabled() ? 1 : 0));
  sendToHelper('filese ' + (filesOnWinE() ? 1 : 0));
  // A fresh helper knows no groups: drop any strips left from a previous one and show
  // whatever it had hidden.
  for (const strip of strips.values()) closeStrip(strip);
  strips.clear();
  tabGroups = [];
  restoreRememberedTabs();
  sendToHelper('tabs ' + (tabsEnabled() ? 1 : 0));
  // With our taskbar on, a native one left hidden stays hidden (no flash of it at sign-in).
  if (!taskbarEnabled()) restoreNativeTaskbarAfterCrash();
  if (taskbarWin && !taskbarWin.webContents.isLoading()) {
    sendToHelper('taskbar 1');
    sendToHelper('tray 1'); // our own home for the apps' tray icons
    hideNativeTaskbar();
    reserveTaskbarSpace();
  }
  if (homeWin) sendToHelper('checkempty');
  applyDesktopBackdrop();
  sendToHelper('index ' + iconCacheDir());
}

// In dev the hooks start off every launch and the tray toggle is not saved.
let devHooksOn = false;

function hooksEnabled() {
  return DEV ? devHooksOn : settings.interceptWinKey;
}

function sendToHelper(line) {
  if (helper && helper.stdin.writable) helper.stdin.write(line + '\n');
}

function onHelperEvent(msg) {
  if (quitting) return; // windows are being torn down; nothing left to update
  if (DEV && msg.event !== 'icon') console.log('[helper]', msg.event, msg.action || msg.message || '');
  switch (msg.event) {
    case 'palette':
      toggleMenu('palette');
      break;
    case 'wine':
      openFiles();
      break;
    case 'winkey':
      toggleMenu();
      break;
    case 'startopened':
      showMenu();
      break;
    case 'focuslost':
      if (!DEV) hideMenu(); // no-op when already parked; the dev window ignores focus changes
      if (openPanel && !isShellWindowHandle(msg.hwnd)) closeTaskbarPanel(false);
      break;
    case 'ready':
      if (DEV && DEV_PREVIEW === 'switcher') previewSwitcher();
      break;
    case 'switcher':
      onSwitcherAction(msg);
      break;
    case 'tabs':
      onTabGroups(msg.groups);
      sendTaskbarState(); // tab counts on the pills
      break;
    case 'taskwindows':
      onTaskWindows(msg);
      break;
    case 'nativetaskbar':
      onNativeTaskbar(msg);
      break;
    case 'system':
      onSystemState(msg);
      break;
    case 'trayicons':
      onTrayIcons(msg.icons);
      break;
    case 'notifications':
      windowsNotifications = msg.items || [];
      send(taskbarWin, 'windows-notifications', windowsNotifications);
      break;
    case 'shellmenu':
      onShellMenu(msg);
      break;
    case 'wallpaper':
      onWallpaperState(msg);
      break;
    // While the Windows taskbar is peeking, ours steps aside (it would sit right on top).
    case 'peek':
      taskbarPeekingNative = msg.on;
      send(taskbarWin, 'taskbar-hidden', msg.on || taskbarAutoHidden);
      break;
    // Only what the helper actually had to undo after a crash is worth a toast.
    case 'tabrestored':
      restoredTabCount++;
      clearTimeout(restoredTabTimer);
      restoredTabTimer = setTimeout(() => {
        const count = restoredTabCount;
        restoredTabCount = 0;
        showToast({ title: `Brought back ${count} hidden tab window${count === 1 ? '' : 's'}`, text: 'They were hidden in a tab group when the shell last stopped.' });
      }, 500);
      break;
    case 'taskbarrestored':
      if (!taskbarEnabled()) showToast({ title: 'Windows taskbar restored', text: 'It was hidden when the shell last stopped.' });
      break;
    case 'mergehover':
      onMergeHover(msg);
      break;
    case 'stripbounds': {
      const strip = msg.id === 0 ? hoverStrip : strips.get(msg.id);
      if (strip) strip.setBounds(screen.screenToDipRect(null, { x: msg.x, y: msg.y, width: msg.w, height: msg.h }));
      break;
    }
    case 'windows':
      onWindowList(msg.windows);
      break;
    case 'screen':
      screenEmpty = msg.empty;
      if (!homeEnabled()) break;
      if (screenEmpty) showHome();
      else hideHome();
      break;
    case 'apps':
      apps = msg.apps;
      saveAppsCache();
      pushState();
      break;
    case 'icon': {
      const a = apps.find((x) => x.id === msg.id);
      if (a) a.icon = msg.icon;
      for (const target of [win, homeWin]) if (target) send(target, 'icon', { id: msg.id, icon: msg.icon });
      break;
    }
    case 'indexed':
      saveAppsCache(); // capture icon paths that streamed in after the list
      break;
    case 'error':
      console.error('[helper]', msg.message);
      break;
  }
}

// ---------- state → renderer ----------

function pushState() {
  const payload = {
    apps,
    pinned: settings.pinned,
    recent: settings.recent,
    counts: settings.launchCounts,
    quickLinks: settings.quickLinks,
    lastUsed: settings.lastUsed,
    labels: settings.labels,
    aliases: settings.aliases,
    recentItems,
    user: os.userInfo().username,
    displayName,
    dev: DEV,
  };
  for (const target of [win, homeWin]) if (target) send(target, 'state', payload);
  sendTaskbarState(); // labels and app names feed pins and category folders
}

// ---------- recent files and folders ----------

// Windows keeps a shortcut for every recently opened file and folder in the Recent
// folder. Resolving them gives the Files and Folders scopes something to search
// until a full file index (Everything) is wired in.
const RECENT_LIMIT = 150;
let recentItems = [];

function refreshRecentItems() {
  const recentDir = path.join(app.getPath('appData'), 'Microsoft', 'Windows', 'Recent');
  let entries;
  try {
    entries = fs.readdirSync(recentDir).filter((name) => name.toLowerCase().endsWith('.lnk'));
  } catch {
    return;
  }
  const shortcuts = entries
    .map((name) => {
      const file = path.join(recentDir, name);
      try { return { file, time: fs.statSync(file).mtimeMs }; } catch { return null; }
    })
    .filter(Boolean)
    .sort((a, b) => b.time - a.time)
    .slice(0, RECENT_LIMIT);

  const seen = new Set();
  recentItems = [];
  for (const shortcut of shortcuts) {
    let target;
    try { target = shell.readShortcutLink(shortcut.file).target; } catch { continue; }
    if (!target || seen.has(target.toLowerCase())) continue;
    let isFolder;
    try { isFolder = fs.statSync(target).isDirectory(); } catch { continue; } // deleted or offline
    seen.add(target.toLowerCase());
    recentItems.push({
      kind: isFolder ? 'folder' : 'file',
      name: path.basename(target) || target,
      folder: path.dirname(target),
      target,
      time: shortcut.time,
    });
  }
  pushState();
}

// Re-asserted on every launch so the login item survives node_modules reinstalls
// and path changes. Windows keeps its own "user disabled this in Task Manager"
// flag separately, so this never overrides an explicit disable there.
//
// The start itself is a scheduled task with a sign-in trigger, not the usual "Run" entry:
// Windows holds "Run" entries back until the desktop has settled (about ten seconds), while
// a sign-in task starts alongside Explorer. The task runs at normal priority (tasks default
// to below normal) and without the default three-day time limit.
const LOGIN_TASK_NAME = 'Custom Start';

function applyLoginItem() {
  if (DEV) return;
  const args = app.isPackaged ? ['--login'] : [path.resolve(__dirname), '--login'];
  app.setLoginItemSettings({ openAtLogin: false, path: process.execPath, args }); // the old "Run" entry
  setLoginTask(Boolean(settings.runAtStartup), args);
  removeDevLoginItem();
}

function setLoginTask(enabled, args) {
  const schtasks = (taskArgs, done) => execFile('schtasks.exe', taskArgs, { windowsHide: true, encoding: 'utf8' }, done);
  schtasks(['/Query', '/TN', LOGIN_TASK_NAME, '/XML'], (missing, existing) => {
    if (!enabled) {
      if (!missing) schtasks(['/Delete', '/TN', LOGIN_TASK_NAME, '/F'], () => {});
      return;
    }
    const xml = loginTaskXml(args);
    if (!missing && existing.includes(escapeXml(process.execPath)) && existing.includes('<Priority>4</Priority>')) return;
    const file = path.join(os.tmpdir(), 'custom-start-login-task.xml');
    fs.writeFileSync(file, '\ufeff' + xml, 'utf16le'); // schtasks reads task XML as UTF-16
    schtasks(['/Create', '/TN', LOGIN_TASK_NAME, '/XML', file, '/F'], (error) => {
      fs.rm(file, () => {});
      if (error) console.error('Could not create the sign-in task:', error.message);
    });
  });
}

function escapeXml(text) {
  return String(text).replace(/[<>&"']/g, (character) => ({ '<': '&lt;', '>': '&gt;', '&': '&amp;', '"': '&quot;', "'": '&apos;' })[character]);
}

function loginTaskXml(args) {
  const user = escapeXml((process.env.USERDOMAIN ? process.env.USERDOMAIN + '\\' : '') + os.userInfo().username);
  const argumentText = escapeXml(args.map((arg) => (/\s/.test(arg) ? `"${arg}"` : arg)).join(' '));
  return `<?xml version="1.0" encoding="UTF-16"?>
<Task version="1.2" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task">
  <RegistrationInfo><Description>Starts Custom Start when you sign in.</Description></RegistrationInfo>
  <Triggers><LogonTrigger><Enabled>true</Enabled><UserId>${user}</UserId></LogonTrigger></Triggers>
  <Principals><Principal id="Author"><UserId>${user}</UserId><LogonType>InteractiveToken</LogonType><RunLevel>LeastPrivilege</RunLevel></Principal></Principals>
  <Settings>
    <MultipleInstancesPolicy>IgnoreNew</MultipleInstancesPolicy>
    <DisallowStartIfOnBatteries>false</DisallowStartIfOnBatteries>
    <StopIfGoingOnBatteries>false</StopIfGoingOnBatteries>
    <AllowHardTerminate>true</AllowHardTerminate>
    <StartWhenAvailable>false</StartWhenAvailable>
    <IdleSettings><StopOnIdleEnd>false</StopOnIdleEnd><RestartOnIdle>false</RestartOnIdle></IdleSettings>
    <AllowStartOnDemand>true</AllowStartOnDemand>
    <Enabled>true</Enabled>
    <Hidden>false</Hidden>
    <ExecutionTimeLimit>PT0S</ExecutionTimeLimit>
    <Priority>4</Priority>
  </Settings>
  <Actions Context="Author"><Exec><Command>${escapeXml(process.execPath)}</Command><Arguments>${argumentText}</Arguments></Exec></Actions>
</Task>`;
}

// The installed app supersedes the dev-mode startup entry ("electron.app.Electron"
// pointing into the project folder). Only removes it if it points at this project.
function removeDevLoginItem() {
  if (!app.isPackaged) return;
  const { execFileSync } = require('child_process');
  const key = 'HKCU\\Software\\Microsoft\\Windows\\CurrentVersion\\Run';
  try {
    const out = execFileSync('reg.exe', ['query', key, '/v', 'electron.app.Electron'], { encoding: 'utf8' });
    if (out.toLowerCase().includes('startmenu'))
      execFileSync('reg.exe', ['delete', key, '/v', 'electron.app.Electron', '/f']);
  } catch { /* entry doesn't exist — nothing to clean */ }
}

// ---------- tray ----------

function createTray() {
  tray = new Tray(nativeImage.createFromPath(path.join(__dirname, 'assets', 'tray.png')));
  tray.setToolTip(DEV ? 'Custom Start (dev)' : 'Custom Start');
  const menu = Menu.buildFromTemplate([
    { label: 'Open menu', click: () => showMenu() },
    { label: 'Open Files', click: () => openFiles() },
    { visible: DEV, label: 'Preview launcher', click: () => previewInDevWindow('index.html', false) },
    { visible: DEV, label: 'Preview palette', click: () => previewInDevWindow('index.html', false, true) },
    { visible: DEV, label: 'Preview Home', click: () => previewInDevWindow('home.html', false) },
    { visible: DEV, label: 'Play intro', click: () => previewInDevWindow('home.html', true) },
    { visible: DEV, label: 'Preview switcher', click: () => previewSwitcher() },
    {
      visible: DEV,
      label: 'Test toast',
      click: () => showToast({ title: 'Build finished', text: '3 warnings in ContractGenerationService.cs', actions: [{ label: 'Open Files', run: () => openFiles() }] }),
    },
    { type: 'separator' },
    { label: 'Settings', click: () => openSettingsWindow() },
    { type: 'separator' },
    { label: 'Exit', click: () => quitApp() },
  ]);
  tray.setContextMenu(menu);
  tray.on('double-click', () => toggleMenu());
}

// ---------- settings window ----------

// Every option in one window. The model lists them with their current values; a change
// goes through the same setter the feature always used, and the model is sent again so
// the window always shows what is really in effect.
let settingsWin = null;

function openSettingsWindow() {
  if (settingsWin && !settingsWin.isDestroyed()) {
    if (settingsWin.isMinimized()) settingsWin.restore();
    settingsWin.show();
    sendToHelper('focushwnd ' + nativeHandle(settingsWin));
    return;
  }
  settingsWin = new BrowserWindow({
    width: 640,
    height: 720,
    minWidth: 480,
    minHeight: 400,
    frame: false,
    title: 'Settings',
    backgroundColor: nativeTheme.shouldUseDarkColors ? '#232427' : '#f4f3f1',
    show: false,
    webPreferences: { preload: path.join(__dirname, 'preload.js') },
  });
  settingsWin.loadFile('renderer/settings.html');
  settingsWin.once('ready-to-show', () => {
    settingsWin.show();
    sendToHelper('focushwnd ' + nativeHandle(settingsWin));
  });
  settingsWin.on('closed', () => {
    settingsWin = null;
  });
}

function settingsModel() {
  const config = taskbarConfig();
  const option = (id, label, hint, value, extra = {}) => ({ id, label, hint, value: Boolean(value), ...extra });
  const sections = [
    {
      title: 'Start and search',
      items: [
        option('startMenu', 'Replace the Start menu', 'The Win key opens the launcher instead of Windows Start.', hooksEnabled()),
        option('palette', 'Alt+Space search', 'A compact search for apps, files and commands, from anywhere.', paletteEnabled()),
        !DEV && option('startup', 'Start when you sign in', 'Opens straight away, before the Windows desktop shows.', settings.runAtStartup),
      ],
    },
    {
      title: 'Windows',
      items: [
        option('switcher', 'Replace Alt+Tab', 'Switch windows with live previews.', switcherEnabled()),
        option('tabs', 'Window tabs', 'Drag a window onto another\'s title bar to group them as tabs.', tabsEnabled()),
        option('filesWinE', 'Win+E opens Files', 'Instead of File Explorer.', filesOnWinE()),
      ],
    },
    {
      title: 'Desktop',
      items: [
        option('home', 'Home on an empty screen', 'With every window minimised, Home takes the desktop\'s place.', homeEnabled()),
        !DEV && option('backdrop', 'Backdrop as the wallpaper', 'Behind your windows, the same surface Home sits on. Desktop icons are hidden.', desktopBackdropEnabled()),
      ],
    },
    {
      title: 'Taskbar',
      items: [
        option('taskbar', 'Graphite taskbar', 'Replaces the Windows taskbar.', taskbarEnabled()),
        option('showLabels', 'Show app names', 'Off: icons only.', config.showLabels !== false),
        option('combine', 'Combine windows of the same app', 'One button per app, with its windows in a list.', config.combine),
        option('alwaysAutoHide', 'Always auto-hide', 'The taskbar slides away; move the pointer to the bottom edge to bring it back.', config.alwaysAutoHide === true),
        option('autoHideWhenMaximised', 'Auto-hide when a window is maximised', 'Gives a maximised window the whole screen.', config.autoHideWhenMaximised === true, { disabled: config.alwaysAutoHide === true }),
      ],
    },
  ];
  for (const section of sections) section.items = section.items.filter(Boolean);
  return { version: app.getVersion(), dev: DEV, sections };
}

function applySetting(id, value) {
  switch (id) {
    case 'startMenu': setHooksEnabled(value); break;
    case 'palette': setPaletteEnabled(value); break;
    case 'startup':
      settings.runAtStartup = value;
      saveSettings();
      applyLoginItem();
      break;
    case 'switcher': setSwitcherEnabled(value); break;
    case 'tabs': setTabsEnabled(value); break;
    case 'filesWinE': setFilesOnWinE(value); break;
    case 'home': setHomeEnabled(value); break;
    case 'backdrop': setDesktopBackdropEnabled(value); break;
    case 'taskbar': setTaskbarEnabled(value); break;
    case 'showLabels': changeTaskbar((config) => { config.showLabels = value; }); break;
    case 'combine': changeTaskbar((config) => { config.combine = value; }); break;
    case 'alwaysAutoHide':
      changeTaskbar((config) => { config.alwaysAutoHide = value; });
      updateTaskbarHiding();
      break;
    case 'autoHideWhenMaximised':
      changeTaskbar((config) => { config.autoHideWhenMaximised = value; });
      updateTaskbarHiding();
      break;
  }
}

function setHooksEnabled(enabled) {
  if (DEV) devHooksOn = enabled;
  else {
    settings.interceptWinKey = enabled;
    saveSettings();
  }
  sendToHelper('enable ' + (enabled ? 1 : 0));
}

ipcMain.handle('settings:get', () => settingsModel());
ipcMain.on('settings:set', (e, id, value) => {
  applySetting(String(id), Boolean(value));
  if (!e.sender.isDestroyed()) e.sender.send('settings-changed', settingsModel());
});
ipcMain.on('settings:window', (e, action) => {
  const window = BrowserWindow.fromWebContents(e.sender);
  if (!window) return;
  if (action === 'minimize') window.minimize();
  if (action === 'close') window.close();
});
ipcMain.on('settings:quit', () => quitApp());

// ---------- ipc from renderer ----------

function finishedWith(event) {
  hideMenu();
  if (homeWin && event.sender === homeWin.webContents) send(homeWin, 'reset');
}

ipcMain.on('launch', (e, id) => {
  finishedWith(e);
  launchApp(id);
});

ipcMain.on('launch-admin', (e, id) => {
  finishedWith(e);
  const target = ('shell:AppsFolder\\' + id).replace(/'/g, "''");
  spawn('powershell.exe', ['-NoProfile', '-Command', `Start-Process '${target}' -Verb RunAs`], { windowsHide: true, detached: true }).unref();
  settings.lastUsed[id] = Date.now();
  saveSettings();
});

ipcMain.on('web-search', (e, query) => {
  finishedWith(e);
  shell.openExternal('https://www.google.com/search?q=' + encodeURIComponent(query));
});

const SETTINGS_PAGES = {
  'Settings': 'ms-settings:',
  'Display settings': 'ms-settings:display',
  'Sound settings': 'ms-settings:sound',
  'Wi-Fi and network': 'ms-settings:network',
  'Bluetooth and devices': 'ms-settings:bluetooth',
};
const POWER_COMMANDS = { 'Lock': 'lock', 'Sleep': 'sleep', 'Sign out': 'signout', 'Restart': 'restart', 'Shut down': 'shutdown' };

ipcMain.on('command', (e, name) => {
  if (POWER_COMMANDS[name]) return runPower(POWER_COMMANDS[name]);
  finishedWith(e);
  if (name === 'Custom Start settings') return openSettingsWindow();
  if (SETTINGS_PAGES[name]) return shell.openExternal(SETTINGS_PAGES[name]);
  if (name === 'Task Manager') return spawn('taskmgr.exe', [], { detached: true }).unref();
  if (name === 'Toggle dark mode') return toggleDarkMode();
});

function toggleDarkMode() {
  if (DEV) {
    console.log('[dev] dark mode toggle skipped');
    return;
  }
  const key = 'HKCU\\Software\\Microsoft\\Windows\\CurrentVersion\\Themes\\Personalize';
  const { execFileSync } = require('child_process');
  let isLight = false;
  try {
    isLight = /AppsUseLightTheme\s+REG_DWORD\s+0x1/.test(execFileSync('reg.exe', ['query', key, '/v', 'AppsUseLightTheme'], { encoding: 'utf8' }));
  } catch { /* value missing: Windows treats it as light, but dark is the safer flip */ }
  const next = isLight ? '0' : '1';
  for (const value of ['AppsUseLightTheme', 'SystemUsesLightTheme'])
    spawn('reg.exe', ['add', key, '/v', value, '/t', 'REG_DWORD', '/d', next, '/f'], { windowsHide: true });
}

const LABELS = ['Dev', 'Media', 'Games', 'Social', 'System'];

ipcMain.on('context-menu', (e, id) => {
  const pinned = settings.pinned.includes(id);
  const setLabel = (label) => {
    if (label) settings.labels[id] = label;
    else delete settings.labels[id];
    saveSettings();
    pushState();
  };
  const entry = apps.find((candidate) => candidate.id === id);
  const onTaskbar = taskbarConfig().items.some((stored) => stored.type === 'app' && stored.key === id && stored.pinned);
  Menu.buildFromTemplate([
    {
      label: onTaskbar ? 'Unpin from taskbar' : 'Pin to taskbar',
      click: () => changeTaskbar((c) => taskbarModel.setPinned(c, { key: id, name: entry && entry.name, icon: entry && entry.icon }, !onTaskbar)),
    },
    {
      label: pinned ? 'Unpin' : 'Pin',
      click: () => {
        settings.pinned = pinned
          ? settings.pinned.filter((x) => x !== id)
          : [...settings.pinned, id];
        saveSettings();
        pushState();
      },
    },
    {
      label: 'Label',
      submenu: [
        ...LABELS.map((label) => ({ label, type: 'radio', checked: settings.labels[id] === label, click: () => setLabel(label) })),
        { type: 'separator' },
        { label: 'None', type: 'radio', checked: !settings.labels[id], click: () => setLabel(null) },
      ],
    },
  ]).popup({ window: BrowserWindow.fromWebContents(e.sender) });
});

ipcMain.on('power', (_e, action) => runPower(action));

function runPower(action) {
  hideMenu();
  if (DEV) {
    console.log('[dev] power action skipped:', action);
    return;
  }
  switch (action) {
    case 'lock': spawn('rundll32.exe', ['user32.dll,LockWorkStation']); break;
    case 'sleep': sendToHelper('sleep'); break;
    case 'signout': spawn('shutdown.exe', ['/l']); break;
    case 'restart': spawn('shutdown.exe', ['/r', '/t', '0']); break;
    case 'shutdown': spawn('shutdown.exe', ['/s', '/hybrid', '/t', '0']); break;
  }
}

ipcMain.on('open-path', (e, p) => {
  finishedWith(e);
  const resolved = p.replace(/%([^%]+)%/g, (m, v) => process.env[v] || m);
  let stats;
  try {
    stats = fs.statSync(resolved);
  } catch {
    // Handing a missing path to Windows gets its "Windows cannot find" dialog; a toast
    // says the same thing in the shell's own voice.
    showToast({ title: `Can't find ${path.basename(resolved) || resolved}`, text: `${resolved} has been moved, renamed or deleted.`, kind: 'error' });
    return;
  }
  if (stats.isDirectory()) openFiles(resolved);
  else shell.openPath(resolved);
});

ipcMain.on('hide', () => hideMenu());
ipcMain.on('request-state', () => pushState());

// ---------- safety and dev tooling ----------

// Quitting the helper removes its hooks, so this always hands the keyboard back.
function quitApp() {
  if (quitting) return;
  if (!sessionEnding) restoreDesktop(); // before the helper's quit, which it runs in order
  quitting = true;
  sendToHelper('quit');
  app.quit();
}

function registerPanicShortcut() {
  if (!globalShortcut.register(PANIC_SHORTCUT, quitApp))
    console.error('Could not register the panic shortcut ' + PANIC_SHORTCUT);
}

// Dev only: `api.devHelper('tabmerge 123 456')` from any page's DevTools console sends a
// raw command to the helper, for poking at it by hand.
// Dev only: what the tray's preview items and Exit do, callable from DevTools and the
// end-to-end tests (tests/e2e).
ipcMain.on('dev-preview', (_e, name) => {
  if (!DEV) return;
  if (name === 'launcher') previewInDevWindow('index.html', false);
  else if (name === 'palette') previewInDevWindow('index.html', false, true);
  else if (name === 'home') previewInDevWindow('home.html', false);
  else if (name === 'intro') previewInDevWindow('home.html', true);
  else if (name === 'switcher') previewSwitcher();
});

ipcMain.on('dev-toast', (_e, message) => {
  if (DEV) showToast(message);
});

ipcMain.on('dev-quit', () => {
  if (DEV) quitApp();
});

// The bar's "Auto-hide when a window is maximised" option, as its menu sets it.
ipcMain.on('dev-taskbar-autohide', (_e, on) => {
  if (!DEV) return;
  changeTaskbar((c) => { c.autoHideWhenMaximised = Boolean(on); });
  updateTaskbarHiding();
});

ipcMain.on('dev-helper', (_e, line) => {
  if (DEV) sendToHelper(String(line));
});

// Renderer edits reload the page; main-process edits restart the whole app.
function watchForChanges() {
  let timer = null;
  const debounce = (fn) => {
    clearTimeout(timer);
    timer = setTimeout(fn, 150);
  };
  fs.watch(path.join(__dirname, 'renderer'), { recursive: true }, () => debounce(() => {
    for (const target of [win, homeWin, switcherWin, taskbarWin, toastWin, hoverStrip, ...strips.values(), ...filesWindows]) if (target) target.webContents.reloadIgnoringCache();
  }));
  for (const file of ['main.js', 'files-main.js', 'preload.js']) {
    fs.watch(path.join(__dirname, file), () => debounce(() => {
      quitting = true; // stops the window's close handler and the helper auto-restart
      sendToHelper('quit'); // the helper shows hidden tab windows before it exits
      app.relaunch();
      app.exit(0);
    }));
  }
}

// ---------- lifecycle ----------

if (!app.requestSingleInstanceLock()) {
  app.quit();
} else {
  app.on('second-instance', () => showMenu());

  app.whenReady().then(() => {
    settings = loadSettings();
    // Last-known app list renders instantly on cold start (pins included);
    // the helper's fresh enumeration replaces it a moment later.
    try { apps = JSON.parse(fs.readFileSync(appsCacheFile(), 'utf8')); } catch { /* first run */ }
    applyLoginItem();
    startFiles();
    createToastWindow();
    createWindow();
    createSwitcherWindow();
    createHoverStrip();
    watchDisplayChanges();
    if (taskbarEnabled()) createTaskbarWindow();
    if (homeEnabled()) createHomeWindow();
    createTray();
    startHelper();
    loadDisplayName();
    registerPanicShortcut();
    setImmediate(refreshRecentItems);
    if (DEV) watchForChanges();
  });

  app.on('before-quit', () => {
    if (!quitting) sendToHelper('quit');
    quitting = true;
  });
  app.on('window-all-closed', () => { /* stay alive in the tray */ });
  app.on('will-quit', () => globalShortcut.unregisterAll());
  // No kill here: once Electron is gone the helper's stdin closes, and it restores any
  // hidden tab windows on its way out.
  app.on('quit', () => sendToHelper('quit'));
}
