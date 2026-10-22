// Context menu in the app's own style. Items: { label, icon?, glyph?, shortcut?, mnemonic?,
// disabled?, default?, checked?, separator?, children? }. Opens at a point in the page,
// flipping to stay inside the window; submenus open on hover or the Right arrow. Keyboard:
// arrows, Enter, Escape, Left, and an item's underlined letter.

const ContextMenu = (() => {
  const submenuDelay = 220;
  const edgeMargin = 8;
  const chevron = '<svg class="cm-chevron" viewBox="0 0 16 16"><path d="m6.5 4 4 4-4 4"/></svg>';
  const check = '<svg viewBox="0 0 16 16"><path d="m3.5 8.5 3 3 6-7"/></svg>';

  let levels = [];      // open menus, outermost first: { element, items, active }
  let handlers = null;  // { onPick, onClose }
  let submenuTimer = null;

  function escapeHtml(text) {
    return String(text).replace(/[&<>"]/g, (character) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' })[character]);
  }

  // The label with its access letter underlined.
  function labelMarkup(item) {
    const label = escapeHtml(item.label);
    if (!item.mnemonic) return label;
    const at = item.label.toLowerCase().indexOf(item.mnemonic);
    if (at < 0) return label;
    return escapeHtml(item.label.slice(0, at)) + `<u>${escapeHtml(item.label[at])}</u>` + escapeHtml(item.label.slice(at + 1));
  }

  function itemMarkup(item, index) {
    if (item.separator) return '<div class="cm-separator" role="separator"></div>';
    const icon = item.icon ? `<img src="${escapeHtml(item.icon)}" alt="">` : item.checked ? check : item.glyph || '';
    const classes = ['cm-item', item.disabled && 'disabled', item.default && 'default'].filter(Boolean).join(' ');
    return `<div class="${classes}" role="menuitem" data-index="${index}" aria-disabled="${Boolean(item.disabled)}"${item.children ? ' aria-haspopup="menu"' : ''}>
      <span class="cm-icon">${icon}</span>
      <span class="cm-label">${labelMarkup(item)}</span>
      ${item.shortcut ? `<span class="cm-shortcut">${escapeHtml(item.shortcut)}</span>` : ''}
      ${item.children ? chevron : ''}
    </div>`;
  }

  function openLevel(items, x, y, anchor) {
    const element = document.createElement('div');
    element.className = 'cm';
    element.setAttribute('role', 'menu');
    element.innerHTML = items.map(itemMarkup).join('');
    document.body.appendChild(element);

    // Inside the window: a submenu flips to the parent's left; the root flips up or left.
    const width = element.offsetWidth;
    const height = Math.min(element.offsetHeight, window.innerHeight - edgeMargin * 2);
    element.style.maxHeight = height + 'px';
    let left = x;
    let top = y;
    if (left + width > window.innerWidth - edgeMargin) left = anchor ? anchor.left - width + 4 : x - width;
    if (top + height > window.innerHeight - edgeMargin) top = anchor ? window.innerHeight - edgeMargin - height : y - height;
    element.style.left = Math.max(edgeMargin, left) + 'px';
    element.style.top = Math.max(edgeMargin, top) + 'px';

    const level = { element, items, active: -1 };
    const depth = levels.length;
    levels.push(level);
    element.addEventListener('mousemove', (event) => {
      const row = event.target.closest('.cm-item');
      if (row) hover(depth, Number(row.dataset.index));
    });
    element.addEventListener('click', (event) => {
      const row = event.target.closest('.cm-item');
      if (row) activate(depth, Number(row.dataset.index), false);
    });
    return level;
  }

  function closeFrom(depth) {
    while (levels.length > depth) levels.pop().element.remove();
  }

  function setActive(depth, index) {
    const level = levels[depth];
    level.active = index;
    level.element.querySelectorAll('.cm-item').forEach((row) => row.classList.toggle('active', Number(row.dataset.index) === index));
    const row = level.element.querySelector(`.cm-item[data-index="${index}"]`);
    if (row) row.scrollIntoView({ block: 'nearest' });
  }

  function hover(depth, index) {
    if (levels[depth].active === index && levels.length > depth + 1) return;
    setActive(depth, index);
    clearTimeout(submenuTimer);
    submenuTimer = setTimeout(() => {
      closeFrom(depth + 1);
      const item = levels[depth] && levels[depth].items[index];
      if (item && item.children && !item.disabled) openSubmenu(depth, index, false);
    }, submenuDelay);
  }

  function openSubmenu(depth, index, focusFirst) {
    closeFrom(depth + 1);
    const row = levels[depth].element.querySelector(`.cm-item[data-index="${index}"]`).getBoundingClientRect();
    const level = openLevel(levels[depth].items[index].children, row.right - 4, row.top - 5, row);
    if (focusFirst) setActive(depth + 1, step(level.items, -1, 1));
  }

  function activate(depth, index, fromKeyboard) {
    const item = levels[depth].items[index];
    if (!item || item.disabled || item.separator) return;
    if (item.children) {
      openSubmenu(depth, index, fromKeyboard);
      return;
    }
    const done = handlers;
    close(false);
    done.onPick(item);
  }

  // The next enabled item from `from` in direction `direction`, wrapping round.
  function step(items, from, direction) {
    for (let offset = 1; offset <= items.length; offset++) {
      const index = (from + direction * offset + items.length * 2) % items.length;
      if (!items[index].separator && !items[index].disabled) return index;
    }
    return -1;
  }

  function onKey(event) {
    if (!levels.length) return;
    const depth = levels.length - 1;
    const level = levels[depth];
    const key = event.key;
    event.preventDefault();
    event.stopPropagation();
    if (key === 'Escape') {
      if (depth > 0) closeFrom(depth);
      else close(true);
    } else if (key === 'ArrowDown' || key === 'ArrowUp') {
      setActive(depth, step(level.items, level.active, key === 'ArrowDown' ? 1 : -1));
    } else if (key === 'ArrowRight') {
      const item = level.items[level.active];
      if (item && item.children) openSubmenu(depth, level.active, true);
    } else if (key === 'ArrowLeft') {
      if (depth > 0) closeFrom(depth);
    } else if (key === 'Enter' || key === ' ') {
      if (level.active >= 0) activate(depth, level.active, true);
    } else if (key.length === 1) {
      const letter = key.toLowerCase();
      const index = level.items.findIndex((item) => !item.disabled && (item.mnemonic === letter || (!item.mnemonic && item.label && item.label[0].toLowerCase() === letter)));
      if (index >= 0) {
        setActive(depth, index);
        activate(depth, index, true);
      }
    }
  }

  function onPointerDown(event) {
    if (!event.target.closest('.cm')) close(true);
  }

  function close(cancelled) {
    if (!handlers) return;
    clearTimeout(submenuTimer);
    closeFrom(0);
    const done = handlers;
    handlers = null;
    window.removeEventListener('keydown', onKey, true);
    window.removeEventListener('pointerdown', onPointerDown, true);
    window.removeEventListener('blur', onBlur);
    window.removeEventListener('resize', onBlur);
    if (cancelled) done.onClose();
  }

  function onBlur() {
    close(true);
  }

  function show(items, x, y, callbacks) {
    close(true);
    if (!items.length) return;
    handlers = callbacks;
    openLevel(items, x, y, null);
    window.addEventListener('keydown', onKey, true);
    window.addEventListener('pointerdown', onPointerDown, true);
    window.addEventListener('blur', onBlur);
    window.addEventListener('resize', onBlur);
  }

  return { show, close: () => close(true), isOpen: () => Boolean(handlers) };
})();
