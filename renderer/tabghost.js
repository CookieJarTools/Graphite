// The floating tab: shows the dragged tab's title, and replays its lift each time it appears.
const tabElement = document.getElementById('tab');

window.api.files.onGhost((title) => {
  if (document.getElementById('title').textContent === title && tabElement.dataset.shown === '1') return;
  document.getElementById('title').textContent = title;
  tabElement.dataset.shown = '1';
  tabElement.style.animation = 'none';
  void tabElement.offsetWidth;
  tabElement.style.animation = '';
});

window.api.files.onGhostHidden(() => {
  tabElement.dataset.shown = '0';
});
