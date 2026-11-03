// Switcher: the Alt+Tab replacement (design/graphite/components/Switcher).
// The main process owns the window list and the selection; this page only draws the
// cards and reports where each preview well sits, so the helper can have DWM paint
// the live window pictures into them.

const root = document.getElementById('root');
const cardsElement = document.getElementById('cards');
const maximumColumns = 5;

let windows = [];
let selectedIndex = 0;

function escapeHtml(text) {
  return String(text).replace(/[&<>"]/g, (character) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' })[character]);
}

function fileUrl(filePath) {
  return 'file:///' + encodeURI(filePath.replace(/\\/g, '/'));
}

function iconMarkup(item) {
  return item.icon ? `<img src="${fileUrl(item.icon)}" draggable="false">` : '<span></span>';
}

function render() {
  cardsElement.style.setProperty('--columns', Math.min(Math.max(windows.length, 1), maximumColumns));
  cardsElement.innerHTML = windows.map((item, index) => {
    const preview = item.minimized ? `${iconMarkup(item)}<span class="state">Minimised</span>` : '';
    return `<div class="card${index === selectedIndex ? ' sel' : ''}" data-index="${index}">`
      + `<div class="preview">${preview}</div>`
      + `<div class="caption">${iconMarkup(item)}<span class="title">${escapeHtml(item.title)}</span><span class="id">${escapeHtml(item.alias || '')}</span></div>`
      + '</div>';
  }).join('');
  reportLayout();
}

// Preview wells in physical pixels, relative to this full-screen window.
function reportLayout() {
  const scale = window.devicePixelRatio;
  const slots = [...cardsElement.querySelectorAll('.card')]
    .map((card) => ({ card, item: windows[Number(card.dataset.index)] }))
    .filter(({ item }) => !item.minimized)
    .map(({ card, item }) => {
      const rect = card.querySelector('.preview').getBoundingClientRect();
      const inset = 4;
      return {
        hwnd: item.hwnd,
        x: Math.round((rect.left + inset) * scale),
        y: Math.round((rect.top + inset) * scale),
        w: Math.round((rect.width - inset * 2) * scale),
        h: Math.round((rect.height - inset * 2) * scale),
      };
    });
  window.api.switcherLayout(slots);
}

function select(index) {
  selectedIndex = index;
  cardsElement.querySelectorAll('.card').forEach((card) => card.classList.toggle('sel', Number(card.dataset.index) === index));
}

cardsElement.addEventListener('mousedown', (event) => {
  const card = event.target.closest('.card');
  if (card) window.api.switcherPick(Number(card.dataset.index));
});

document.getElementById('scrim').addEventListener('mousedown', () => window.api.switcherCancel());

window.api.onSwitcherState((state) => {
  windows = state.windows;
  selectedIndex = state.index;
  root.classList.add('open');
  render();
});

window.api.onSwitcherSelect(select);

window.api.onSwitcherReset(() => {
  root.classList.remove('open');
  windows = [];
  cardsElement.innerHTML = '';
});
