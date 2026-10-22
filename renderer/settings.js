// Settings: draws the options main.js describes (settingsModel) and sends each change back.
// Main answers every change with the whole model again, so a switch that cannot change (or
// that turns another off) always shows the truth.

const sectionsElement = document.getElementById('sections');

function escapeHtml(text) {
  return String(text).replace(/[&<>"]/g, (character) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' })[character]);
}

function render(model) {
  document.getElementById('version').textContent = `Custom Start ${model.version}${model.dev ? ' (dev)' : ''}`;
  const focusedId = document.activeElement && document.activeElement.dataset.id;
  sectionsElement.innerHTML = model.sections.map((section) => `
    <section class="section">
      <h2>${escapeHtml(section.title)}</h2>
      <div class="card">${section.items.map((item) => `
        <label class="row${item.disabled ? ' disabled' : ''}">
          <span class="text">
            <span class="label">${escapeHtml(item.label)}</span>
            ${item.hint ? `<span class="hint">${escapeHtml(item.hint)}</span>` : ''}
          </span>
          <button class="switch" role="switch" data-id="${escapeHtml(item.id)}" aria-checked="${item.value}" aria-label="${escapeHtml(item.label)}"${item.disabled ? ' disabled' : ''}></button>
        </label>`).join('')}
      </div>
    </section>`).join('');

  sectionsElement.querySelectorAll('.switch').forEach((button) => {
    button.addEventListener('click', (event) => {
      event.preventDefault(); // the row's label would click it a second time
      const value = button.getAttribute('aria-checked') !== 'true';
      button.setAttribute('aria-checked', String(value)); // at once; main's answer confirms
      window.api.settings.set(button.dataset.id, value);
    });
  });
  // The row is the target: a click anywhere on it flips its switch.
  sectionsElement.querySelectorAll('.row').forEach((row) => row.addEventListener('click', (event) => {
    if (event.target.closest('.switch')) return;
    event.preventDefault();
    const button = row.querySelector('.switch');
    if (!button.disabled) button.click();
  }));
  if (focusedId) {
    const again = sectionsElement.querySelector(`.switch[data-id="${CSS.escape(focusedId)}"]`);
    if (again) again.focus();
  }
}

document.getElementById('minimize').addEventListener('click', () => window.api.settings.window('minimize'));
document.getElementById('close').addEventListener('click', () => window.api.settings.window('close'));
document.getElementById('quit').addEventListener('click', () => window.api.settings.quit());
document.addEventListener('keydown', (event) => {
  if (event.key === 'Escape') window.api.settings.window('close');
});

window.api.settings.onChanged(render);
window.api.settings.get().then(render);
