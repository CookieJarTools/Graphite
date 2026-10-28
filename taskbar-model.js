// The taskbar's arrangement: pinned apps, folders (named, or a category that gathers every
// app with a launcher label), running windows combined per app, and the user's order.
// Pure data in, data out, so it can be tested without any windows.
//
// Stored in settings.taskbar:
//   { combine: true, separate: [appKey, ...], items: [AppItem | FolderItem, ...] }   (in bar order)
//   `separate` lists apps whose windows stay separate pills even when combining.
//   AppItem:    { type: 'app', key, name, icon, pinned }
//   FolderItem: { type: 'folder', id, name, label, pinned, apps: [{ key, name, icon }] }
// An app's key is its Start entry id when known, otherwise its AppUserModelID or exe path.
// Running apps nobody has placed are not stored; they join the end of the bar.

const LABELS = ['Dev', 'Media', 'Games', 'Social', 'System'];

function emptyConfig() {
  return { combine: true, separate: [], items: [] };
}

const appRef = (key) => 'app:' + key;
const folderRef = (id) => 'folder:' + id;
const refOf = (item) => (item.type === 'folder' ? folderRef(item.id) : appRef(item.key));

/**
 * Builds what the bar shows.
 * @param {object} config    settings.taskbar
 * @param {object} context   { windows: [{ hwnd, key, name, title, icon, tag? }], foreground, flashing: Set,
 *                             tabCounts: Map hwnd -> tabs, apps: [{ id, name, icon }], labels: { appId: label } }
 */
function buildModel(config, context) {
  const appsById = new Map(context.apps.map((entry) => [entry.id, entry]));
  const windowsByKey = new Map();
  for (const window of context.windows) {
    if (!windowsByKey.has(window.key)) windowsByKey.set(window.key, []);
    windowsByKey.get(window.key).push(window);
  }

  const describeApp = (key, stored = {}) => {
    const windows = windowsByKey.get(key) || [];
    const entry = appsById.get(key);
    const described = windows.map((window) => ({
      hwnd: window.hwnd,
      title: window.title,
      minimized: Boolean(window.minimized),
      focused: window.hwnd === context.foreground,
      attention: context.flashing.has(window.hwnd),
      tabs: context.tabCounts.get(window.hwnd) || 1,
      tag: window.tag || null,
    }));
    return {
      type: 'app',
      ref: appRef(key),
      key,
      name: (entry && entry.name) || stored.name || (windows[0] && windows[0].name) || key,
      icon: (entry && entry.icon) || stored.icon || (windows[0] && windows[0].icon) || null,
      pinned: Boolean(stored.pinned),
      windows: described,
      running: described.length > 0,
      focused: described.some((window) => window.focused),
      attention: described.some((window) => window.attention),
    };
  };

  const placed = new Set();
  const items = [];

  for (const stored of config.items) {
    if (stored.type === 'app') {
      placed.add(stored.key);
      const item = describeApp(stored.key, stored);
      if (item.pinned || item.running) items.push(item);
      continue;
    }
    // A category folder also gathers every app carrying its label.
    const members = [...stored.apps];
    if (stored.label) {
      for (const entry of context.apps) {
        if (context.labels[entry.id] === stored.label && !members.some((member) => member.key === entry.id)) members.push({ key: entry.id, name: entry.name, icon: entry.icon });
      }
    }
    members.forEach((member) => placed.add(member.key));
    const apps = members.map((member) => describeApp(member.key, member));
    if (!stored.pinned && !apps.some((app) => app.running)) continue;
    items.push({
      type: 'folder',
      ref: folderRef(stored.id),
      id: stored.id,
      name: stored.name,
      label: stored.label || null,
      pinned: Boolean(stored.pinned),
      apps,
      running: apps.some((app) => app.running),
      focused: apps.some((app) => app.focused),
      attention: apps.some((app) => app.attention),
    });
  }

  for (const window of context.windows) {
    if (placed.has(window.key)) continue;
    placed.add(window.key);
    items.push(describeApp(window.key));
  }

  // Not combining (for every app, or for the apps listed in `separate`): an app with
  // several windows becomes one pill per window.
  const separate = new Set(config.separate || []);
  return items.flatMap(splitByTag).flatMap((item) => (item.type === 'app' && item.windows.length > 1 && (!config.combine || separate.has(item.key))
    ? item.windows.map((window) => Object.assign({}, item, { ref: item.ref + '#' + window.hwnd, windows: [window], focused: window.focused, attention: window.attention }))
    : [item]));
}

// Tagged windows (window-tags.js) leave their app's pill for one of their own per tag, right
// after it: three browser windows tagged Play, Work and Dev are three pills. The app's own
// pill stays for its untagged windows; with every open window tagged it goes, even when
// pinned, and the first tagged pill carries the pin (and so its place and its Unpin).
function splitByTag(item) {
  if (item.type !== 'app' || !item.windows.some((window) => window.tag)) return [item];
  const groups = new Map();
  for (const window of item.windows) {
    if (!window.tag) continue;
    if (!groups.has(window.tag.id)) groups.set(window.tag.id, []);
    groups.get(window.tag.id).push(window);
  }
  const untagged = item.windows.filter((window) => !window.tag);
  const withWindows = (windows) => ({
    windows,
    running: windows.length > 0,
    focused: windows.some((window) => window.focused),
    attention: windows.some((window) => window.attention),
  });
  // Object.assign rather than object spread: the Linux shell's QML JavaScript has no spread.
  const pills = untagged.length ? [Object.assign({}, item, withWindows(untagged))] : [];
  for (const [tagId, windows] of groups) {
    const carriesPin = item.pinned && pills.length === 0;
    pills.push(Object.assign({}, item, withWindows(windows), { ref: item.ref + '#tag:' + tagId, tag: windows[0].tag, pinned: carriesPin }));
  }
  return pills;
}

// ---------- changes ----------

function findApp(config, key) {
  return config.items.find((item) => item.type === 'app' && item.key === key);
}

function findFolder(config, id) {
  return config.items.find((item) => item.type === 'folder' && item.id === id);
}

function setPinned(config, app, pinned) {
  const stored = findApp(config, app.key);
  if (stored) stored.pinned = pinned;
  else if (pinned) config.items.push({ type: 'app', key: app.key, name: app.name, icon: app.icon, pinned: true });
  pruneApps(config);
}

// An unpinned app that is not running has nothing to show; its stored place goes.
function pruneApps(config, runningKeys) {
  config.items = config.items.filter((item) => item.type !== 'app' || item.pinned || (runningKeys && runningKeys.has(item.key)));
}

/**
 * Puts the bar in the order shown, given as refs ("app:<key>" / "folder:<id>"). Running
 * apps that were only there by being open get stored so they keep their place.
 * `visible` describes what the bar currently shows, for those apps' names and icons.
 */
function reorder(config, refs, visible) {
  const byRef = new Map(visible.map((item) => [item.ref.split('#')[0], item]));
  const ordered = [];
  for (const ref of refs) {
    const base = ref.split('#')[0];
    if (ordered.some((item) => refOf(item) === base)) continue;
    const [kind, value] = [base.slice(0, base.indexOf(':')), base.slice(base.indexOf(':') + 1)];
    if (kind === 'folder') {
      const folder = findFolder(config, value);
      if (folder) ordered.push(folder);
    } else {
      const shown = byRef.get(base);
      ordered.push(findApp(config, value) || { type: 'app', key: value, name: shown && shown.name, icon: shown && shown.icon, pinned: false });
    }
  }
  const rest = config.items.filter((item) => !ordered.includes(item) && !ordered.some((placed) => refOf(placed) === refOf(item)));
  config.items = [...ordered, ...rest];
}

/**
 * Drops `sourceRef` onto `targetRef`: two apps make a folder at the target's place; an app
 * dropped on a folder joins it; a folder dropped on a folder merges into it. Returns the
 * folder's id, so a new one can be named straight away (`created` says whether it is new).
 */
function merge(config, sourceRef, targetRef, visible) {
  const source = visible.find((item) => item.ref.split('#')[0] === sourceRef.split('#')[0]);
  const target = visible.find((item) => item.ref.split('#')[0] === targetRef.split('#')[0]);
  if (!source || !target || source.ref === target.ref) return null;
  reorder(config, visible.map((item) => item.ref), visible); // every shown item stored, in place

  const membersOf = (item) => (item.type === 'folder' ? item.apps.map(({ key, name, icon }) => ({ key, name, icon })) : [{ key: item.key, name: item.name, icon: item.icon }]);
  const removeItem = (item) => {
    config.items = config.items.filter((stored) => refOf(stored) !== item.ref.split('#')[0]);
  };

  if (target.type === 'folder') {
    const folder = findFolder(config, target.id);
    for (const member of membersOf(source)) if (!folder.apps.some((app) => app.key === member.key)) folder.apps.push(member);
    folder.pinned = folder.pinned || source.pinned;
    removeItem(source);
    return { id: folder.id, created: false };
  }

  // Two apps (or a folder dropped on an app): a new folder where the target was.
  const members = [...membersOf(target), ...membersOf(source)];
  const labels = new Set(members.map((member) => member.label).filter(Boolean));
  const id = 'f' + Date.now().toString(36);
  const folder = {
    type: 'folder',
    id,
    name: source.type === 'folder' ? source.name : labels.size === 1 ? [...labels][0] : 'New folder',
    label: null,
    pinned: Boolean(source.pinned || target.pinned),
    apps: members.map(({ key, name, icon }) => ({ key, name, icon })),
  };
  const index = config.items.findIndex((stored) => refOf(stored) === target.ref.split('#')[0]);
  config.items.splice(index, 1, folder);
  removeItem(source);
  return { id, created: true };
}

function setSeparate(config, key, separate) {
  const keys = new Set(config.separate || []);
  if (separate) keys.add(key);
  else keys.delete(key);
  config.separate = [...keys];
}

function rename(config, id, name) {
  const folder = findFolder(config, id);
  if (folder && name.trim()) folder.name = name.trim().slice(0, 40);
}

function setFolderPinned(config, id, pinned) {
  const folder = findFolder(config, id);
  if (folder) folder.pinned = pinned;
}

// A folder breaks back into its apps, in its place; pinned folders leave pinned apps.
function ungroup(config, id) {
  const index = config.items.findIndex((item) => item.type === 'folder' && item.id === id);
  if (index < 0) return;
  const folder = config.items[index];
  const apps = folder.apps.filter((app) => !findApp(config, app.key)).map((app) => ({ type: 'app', key: app.key, name: app.name, icon: app.icon, pinned: folder.pinned }));
  config.items.splice(index, 1, ...apps);
}

function removeFromFolder(config, id, key) {
  const folder = findFolder(config, id);
  if (!folder) return;
  folder.apps = folder.apps.filter((app) => app.key !== key);
  if (!folder.label && folder.apps.length < 2) ungroup(config, id);
}

// A category folder: named after the label, gathering every app that carries it.
function pinCategory(config, label) {
  const existing = config.items.find((item) => item.type === 'folder' && item.label === label);
  if (existing) existing.pinned = true;
  else config.items.push({ type: 'folder', id: 'c' + label.toLowerCase(), name: label, label, pinned: true, apps: [] });
}

module.exports = { LABELS, emptyConfig, buildModel, setPinned, setSeparate, pruneApps, reorder, merge, rename, setFolderPinned, ungroup, removeFromFolder, pinCategory };
