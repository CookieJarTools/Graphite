// Toasts: the shell's own notifications, stacking down from the top-right corner.

const stack = document.getElementById('stack');
const maximumVisibleToasts = 3;
const autoDismissMilliseconds = 6000;
const stackEasing = 'cubic-bezier(0.2, 0, 0, 1)'; // ease-standard
const stackReflowMilliseconds = 320; // duration-slow

const glyphs = {
  close: '<svg class="glyph" viewBox="0 0 16 16"><path d="m4.5 4.5 7 7M11.5 4.5l-7 7"/></svg>',
  danger: '<svg class="glyph" viewBox="0 0 16 16"><circle cx="8" cy="8" r="6"/><path d="M8 5v3.5M8 11h0"/></svg>',
  shell: '<svg class="glyph" viewBox="0 0 16 16"><rect x="2.5" y="2.5" width="4.5" height="4.5" rx="1"/><rect x="9" y="2.5" width="4.5" height="4.5" rx="1"/><rect x="2.5" y="9" width="4.5" height="4.5" rx="1"/><rect x="9" y="9" width="4.5" height="4.5" rx="1"/></svg>',
};

function escapeHtml(text) {
  return String(text).replace(/[&<>"]/g, (character) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' })[character]);
}

// FLIP: record positions, change the stack, then ease each survivor from its old spot.
function animateStackReflow(changeStack) {
  const previousTops = new Map([...stack.children].map((toast) => [toast, toast.getBoundingClientRect().top]));
  changeStack();
  for (const toast of stack.children) {
    if (!previousTops.has(toast) || toast.classList.contains('leaving')) continue;
    const offset = previousTops.get(toast) - toast.getBoundingClientRect().top;
    if (offset !== 0) toast.animate([{ transform: `translateY(${offset}px)` }, { transform: 'none' }], { duration: stackReflowMilliseconds, easing: stackEasing });
  }
}

// Only the cards take the mouse; the rest of the corner lets clicks through.
function regionOf(element) {
  const rect = element.getBoundingClientRect();
  return { x: Math.floor(rect.left), y: Math.floor(rect.top), width: Math.ceil(rect.width), height: Math.ceil(rect.height) };
}

function reportHitRegions() {
  window.api.setHitRegions([...stack.children].filter((card) => !card.classList.contains('leaving')).map(regionOf));
}

function dismiss(toast) {
  if (toast.classList.contains('leaving')) return;
  toast.classList.remove('arriving');
  toast.classList.add('leaving');
  toast.addEventListener('animationend', () => {
    animateStackReflow(() => toast.remove());
    reportHitRegions();
    if (stack.children.length === 0) window.api.toastEmpty();
  }, { once: true });
}

function show(message) {
  const toast = document.createElement('div');
  toast.className = 'card arriving';
  const actions = (message.actions || []).slice(0, 2);
  toast.innerHTML =
    `<div class="strip">${glyphs.shell}<span class="app">${escapeHtml(message.app || 'Graphite Desk')}</span>`
    + `<span class="time">now</span><button class="dismiss" aria-label="Dismiss">${glyphs.close}</button></div>`
    + `<div class="body"><p class="title">${message.kind === 'error' ? `<span class="bad">${glyphs.danger}</span>` : ''}${escapeHtml(message.title)}</p>`
    + (message.text ? `<p class="text">${escapeHtml(message.text)}</p>` : '') + '</div>'
    + (actions.length ? `<div class="actions">${actions.map((action) => `<button class="ghost" data-action="${escapeHtml(action.id)}">${escapeHtml(action.label)}</button>`).join('')}</div>` : '');

  toast.querySelector('.dismiss').addEventListener('click', () => dismiss(toast));
  toast.querySelectorAll('[data-action]').forEach((button) => button.addEventListener('click', () => {
    window.api.toastAction(button.dataset.action);
    dismiss(toast);
  }));

  // Hovering pauses the auto-dismiss.
  let timer = setTimeout(() => dismiss(toast), autoDismissMilliseconds);
  toast.addEventListener('mouseenter', () => clearTimeout(timer));
  toast.addEventListener('mouseleave', () => {
    timer = setTimeout(() => dismiss(toast), autoDismissMilliseconds);
  });

  animateStackReflow(() => stack.prepend(toast));
  [...stack.children].filter((item) => !item.classList.contains('leaving')).slice(maximumVisibleToasts).forEach(dismiss);
  toast.addEventListener('animationend', reportHitRegions, { once: true });
  reportHitRegions();
}

window.api.onToast(show);
