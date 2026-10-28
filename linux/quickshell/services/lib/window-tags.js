.pragma library
// Generated from window-tags.js by scripts/gen-qml-lib.js. Do not edit: change window-tags.js and run
// `npm run build:qml-lib`.

if (!Array.prototype.flatMap) Array.prototype.flatMap = function (map, self) { return [].concat.apply([], this.map(map, self)); };

// Tags on windows: a name and a colour put on one window, shown on its taskbar button, and
// kept for when the window comes back. A window's handle is new every time an app opens it,
// so a tag is remembered by the app and where the window sat (its normal position and
// size, or maximised) plus its last title; when that app opens a window in the same place
// again (browsers reopen theirs where they were, after a restart too), the tag goes back on.
// Pure data in, data out, so it can be tested without any windows.
//
// Stored in settings.taskbar:
//   tags:   [{ id, name, color }]                       color: one of COLORS
//   tagged: [{ id, tag, key, bounds: { x, y, width, height }, zoomed, title }]
// A live session also keeps which open window holds which remembered entry (state.live).

const COLORS = ['blue', 'green', 'rose', 'teal', 'violet', 'amber'];
const MATCH_DISTANCE = 160; // px of position and size difference still taken as "the same place"
const NAME_LENGTH = 24;

function createState() {
  return { live: new Map(), seen: new Set() }; // hwnd -> remembered entry id; hwnds already looked at
}

function ensure(config) {
  if (!Array.isArray(config.tags)) config.tags = [];
  if (!Array.isArray(config.tagged)) config.tagged = [];
}

const newId = (prefix) => prefix + Date.now().toString(36) + Math.random().toString(36).slice(2, 6);

// How far apart two placements are; maximised windows only match maximised ones.
function distance(entry, window) {
  if (Boolean(entry.zoomed) !== Boolean(window.zoomed)) return Infinity;
  if (!entry.bounds || !window.bounds) return Infinity;
  const a = entry.bounds;
  const b = window.bounds;
  return Math.abs(a.x - b.x) + Math.abs(a.y - b.y) + Math.abs(a.width - b.width) + Math.abs(a.height - b.height);
}

/**
 * Brings the session up to date with the open windows: forgets closed ones, notes where
 * tagged ones are now, and gives new windows the tag remembered for their place.
 * Returns true when the stored entries changed (to be saved).
 * @param {object} config   settings.taskbar
 * @param {object} state    createState()
 * @param {Array} windows   [{ hwnd, key, title, zoomed, bounds }]
 */
function resolve(config, state, windows) {
  ensure(config);
  let changed = false;
  const open = new Set(windows.map((window) => window.hwnd));
  for (const hwnd of [...state.live.keys()]) if (!open.has(hwnd)) state.live.delete(hwnd);
  for (const hwnd of [...state.seen]) if (!open.has(hwnd)) state.seen.delete(hwnd);

  for (const window of windows) {
    const entryId = state.live.get(window.hwnd);
    if (entryId) {
      changed = remember(config, entryId, window) || changed;
      continue;
    }
    if (state.seen.has(window.hwnd)) continue;
    state.seen.add(window.hwnd);
    // Only entries of this app not already on an open window; the nearest place wins, a
    // matching title breaking ties (several maximised windows, say).
    const held = new Set(state.live.values());
    const candidates = config.tagged
      .filter((entry) => entry.key === window.key && !held.has(entry.id))
      .map((entry) => ({ entry, distance: distance(entry, window) - (entry.title && entry.title === window.title ? 1 : 0) }))
      .filter((candidate) => candidate.distance <= MATCH_DISTANCE)
      .sort((a, b) => a.distance - b.distance);
    if (candidates.length) state.live.set(window.hwnd, candidates[0].entry.id);
  }
  return changed;
}

// The tagged window's latest place and title; true if they changed.
function remember(config, entryId, window) {
  const entry = config.tagged.find((item) => item.id === entryId);
  if (!entry || !window.bounds) return false;
  const same = entry.title === window.title && Boolean(entry.zoomed) === Boolean(window.zoomed)
    && entry.bounds && distance(entry, window) === 0;
  if (same) return false;
  entry.title = window.title;
  entry.zoomed = Boolean(window.zoomed);
  entry.bounds = Object.assign({}, window.bounds); // not spread: the Linux shell's QML JavaScript has none
  return true;
}

/** The tag on an open window, or null. */
function tagOf(config, state, hwnd) {
  ensure(config);
  const entryId = state.live.get(hwnd);
  const entry = entryId && config.tagged.find((item) => item.id === entryId);
  return (entry && config.tags.find((tag) => tag.id === entry.tag)) || null;
}

/** Puts a tag on a window (null takes it off). */
function tagWindow(config, state, window, tagId) {
  ensure(config);
  const entryId = state.live.get(window.hwnd);
  if (!tagId) {
    if (entryId) config.tagged = config.tagged.filter((item) => item.id !== entryId);
    state.live.delete(window.hwnd);
    return;
  }
  const existing = entryId && config.tagged.find((item) => item.id === entryId);
  if (existing) {
    existing.tag = tagId;
    return;
  }
  const entry = { id: newId('w'), tag: tagId, key: window.key, title: window.title, zoomed: Boolean(window.zoomed), bounds: window.bounds ? Object.assign({}, window.bounds) : null };
  config.tagged.push(entry);
  state.live.set(window.hwnd, entry.id);
  state.seen.add(window.hwnd);
}

/** A new tag; returns it. The colour is the first one not yet used, when none is given. */
function createTag(config, name, color) {
  ensure(config);
  const used = new Set(config.tags.map((tag) => tag.color));
  const tag = {
    id: newId('t'),
    name: String(name).trim().slice(0, NAME_LENGTH) || 'Tag',
    color: COLORS.includes(color) ? color : COLORS.find((candidate) => !used.has(candidate)) || COLORS[0],
  };
  config.tags.push(tag);
  return tag;
}

/** Deletes a tag, and every window's memory of it. */
function deleteTag(config, state, tagId) {
  ensure(config);
  const gone = new Set(config.tagged.filter((item) => item.tag === tagId).map((item) => item.id));
  config.tags = config.tags.filter((tag) => tag.id !== tagId);
  config.tagged = config.tagged.filter((item) => item.tag !== tagId);
  for (const [hwnd, entryId] of state.live) if (gone.has(entryId)) state.live.delete(hwnd);
}

