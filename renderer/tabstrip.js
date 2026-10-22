// Tab strip for one window group. The helper owns the windows and keeps this strip in
// place; this page draws the tabs and turns clicks and drags into tab commands.

const stripElement = document.getElementById('strip');
const splitDistance = 16; // pull a tab this far down to split it out
const closeGlyph = '<svg viewBox="0 0 16 16"><path d="m4.5 4.5 7 7M11.5 4.5l-7 7"/></svg>';

let group = { active: '', tabs: [] };
let slot = null;
let knownTabs = new Set();

function escapeHtml(text) {
  return String(text).replace(/[&<>"]/g, (character) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' })[character]);
}

function fileUrl(filePath) {
  return 'file:///' + encodeURI(filePath.replace(/\\/g, '/'));
}

function tabMarkup(tab, className) {
  const icon = tab.icon ? `<img src="${fileUrl(tab.icon)}" draggable="false">` : '';
  const close = className === 'slot' ? '' : `<button class="x" aria-label="Close tab">${closeGlyph}</button>`;
  return `<div class="tab ${className}" data-hwnd="${escapeHtml(tab.hwnd)}" title="${escapeHtml(tab.title)}">${icon}<span class="title">${escapeHtml(tab.title)}</span>${close}</div>`;
}

function render() {
  stripElement.classList.toggle('target', Boolean(slot));
  stripElement.innerHTML = group.tabs.map((tab) => {
    const classes = [tab.hwnd === group.active ? 'on' : '', knownTabs.has(tab.hwnd) ? '' : 'entering'].join(' ').trim();
    return tabMarkup(tab, classes);
  }).join('') + (slot ? tabMarkup(slot, 'slot') : '');
  knownTabs = new Set(group.tabs.map((tab) => tab.hwnd));
}

// Press on a tab: release in place activates it, pulling it down splits it out.
stripElement.addEventListener('pointerdown', (event) => {
  const closeButton = event.target.closest('.x');
  const tab = event.target.closest('.tab:not(.slot)');
  if (closeButton && tab) {
    window.api.tabClose(tab.dataset.hwnd);
    return;
  }
  if (!tab) {
    window.api.stripDrag(group.active); // empty strip moves the whole group
    return;
  }

  const hwnd = tab.dataset.hwnd;
  const startY = event.clientY;
  let split = false;
  stripElement.setPointerCapture(event.pointerId);
  const onMove = (moveEvent) => {
    if (!split && moveEvent.clientY - startY > splitDistance) {
      split = true;
      window.api.tabSplit(hwnd);
    }
  };
  const onUp = () => {
    stripElement.removeEventListener('pointermove', onMove);
    stripElement.removeEventListener('pointerup', onUp);
    if (!split) window.api.tabActivate(hwnd);
  };
  stripElement.addEventListener('pointermove', onMove);
  stripElement.addEventListener('pointerup', onUp);
});

// The window is taller than the strip (Windows keeps frameless windows a little taller
// than asked); only the strip takes the mouse, and a drag keeps it until release.
function regionOf(element) {
  const rect = element.getBoundingClientRect();
  return { x: Math.floor(rect.left), y: Math.floor(rect.top), width: Math.ceil(rect.width), height: Math.ceil(rect.height) };
}

function reportHitRegions(capture) {
  window.api.setHitRegions(capture ? 'capture' : [regionOf(stripElement)]);
}

new ResizeObserver(() => reportHitRegions(false)).observe(stripElement);
stripElement.addEventListener('pointerdown', () => reportHitRegions(true), true);
window.addEventListener('pointerup', () => reportHitRegions(false), true);
window.addEventListener('pointercancel', () => reportHitRegions(false), true);
reportHitRegions(false);

window.api.onStripState((state) => {
  group = state;
  slot = state.slot || null;
  render();
});

window.api.onStripSlot((incoming) => {
  slot = incoming;
  render();
});
