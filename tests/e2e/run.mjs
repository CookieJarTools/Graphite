// End-to-end tests: `npm run test:e2e` (add `-- --no-build` to skip the build).
//
// Runs the helper and the app for real, against a throwaway profile and a temporary
// folder, with two plain test windows to manage. Your settings and files are not
// touched; the Windows taskbar is hidden for a few seconds and then put back. Test
// windows take focus while it runs, so leave the mouse and keyboard alone.
//
// What it cannot do: press the real shortcuts. The hooks ignore simulated keys on
// purpose, so the Win key, Alt+Space, Alt+Tab and Win+E are in the manual checklist
// (tests/MANUAL.md), along with real mouse drags between windows.

import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { execSync } from 'node:child_process';
import { createRequire } from 'node:module';
import { root, sleep, waitFor, win32, openTestWindow, startHelper, startApp, findPage, allPages, pageCount } from './lib.mjs';

const results = [];
let current = '';

async function test(name, body) {
  current = name;
  const started = Date.now();
  try {
    await body();
    results.push({ name, ok: true });
    console.log(`  pass  ${name} (${Date.now() - started} ms)`);
  } catch (error) {
    results.push({ name, ok: false, error: error.message });
    console.log(`  FAIL  ${name}\n        ${error.message}`);
  }
}

function assert(condition, message) {
  if (!condition) throw new Error(message);
}

function equal(actual, expected, what) {
  assert(JSON.stringify(actual) === JSON.stringify(expected), `${what}: expected ${JSON.stringify(expected)}, got ${JSON.stringify(actual)}`);
}

// ---------- setup ----------

if (!process.argv.includes('--no-build')) {
  console.log('Building helper, icon and tokens...');
  execSync('npm run build', { cwd: root, stdio: 'ignore' });
}

const work = fs.mkdtempSync(path.join(os.tmpdir(), 'graphite-e2e-'));
const profile = path.join(work, 'profile');
const fixture = path.join(work, 'files');
fs.mkdirSync(path.join(fixture, 'gamma'), { recursive: true });
fs.writeFileSync(path.join(fixture, 'alpha.txt'), 'alpha');
fs.writeFileSync(path.join(fixture, 'beta.png'), Buffer.alloc(64));

// ---------- taskbar model (no windows needed) ----------

console.log('Taskbar model');
const model = createRequire(import.meta.url)(path.join(root, 'taskbar-model.js'));
const sampleApps = [{ id: 'app.one', name: 'One', icon: null }, { id: 'app.two', name: 'Two', icon: null }, { id: 'app.three', name: 'Three', icon: null }];
const context = (windows, labels = {}) => ({ windows, foreground: '', flashing: new Set(), tabCounts: new Map(), apps: sampleApps, labels });
const windowOf = (hwnd, key) => ({ hwnd, key, name: key, title: `${key} ${hwnd}`, icon: null });

await test('combines windows of one app, or not', async () => {
  const windows = [windowOf('1', 'app.one'), windowOf('2', 'app.one'), windowOf('3', 'app.two')];
  const combined = model.buildModel(model.emptyConfig(), context(windows));
  equal(combined.map((item) => [item.key, item.windows.length]), [['app.one', 2], ['app.two', 1]], 'combined');
  const separate = model.buildModel({ ...model.emptyConfig(), combine: false }, context(windows));
  equal(separate.length, 3, 'pills when not combining');
  const config = model.emptyConfig();
  model.setSeparate(config, 'app.one', true);
  equal(model.buildModel(config, context(windows)).length, 3, 'one app shown separately');
  model.setSeparate(config, 'app.one', false);
  equal(model.buildModel(config, context(windows)).length, 2, 'grouped again');
});

await test('pinned apps stay when closed', async () => {
  const config = model.emptyConfig();
  model.setPinned(config, { key: 'app.three', name: 'Three' }, true);
  const items = model.buildModel(config, context([]));
  equal(items.map((item) => [item.key, item.running, item.pinned]), [['app.three', false, true]], 'pinned, not running');
  model.setPinned(config, { key: 'app.three' }, false);
  equal(model.buildModel(config, context([])).length, 0, 'unpinned and closed');
});

const tags = createRequire(import.meta.url)(path.join(root, 'window-tags.js'));
const placed = (hwnd, key, x, title, zoomed = false) => ({ ...windowOf(hwnd, key), title, zoomed, bounds: { x, y: 100, width: 1200, height: 800 } });

await test('a tag comes back when its window reopens in the same place, after a restart too', async () => {
  const config = model.emptyConfig();
  let state = tags.createState();
  const work = placed('1', 'app.one', 0, 'Mail - Work');
  const play = placed('2', 'app.one', 1400, 'Video - Play');
  tags.resolve(config, state, [work, play]);
  const workTag = tags.createTag(config, 'Work');
  const playTag = tags.createTag(config, 'Play');
  tags.tagWindow(config, state, work, workTag.id);
  tags.tagWindow(config, state, play, playTag.id);
  equal([tags.tagOf(config, state, '1').name, tags.tagOf(config, state, '2').name], ['Work', 'Play'], 'tagged');
  equal(workTag.color !== playTag.color, true, 'each new tag gets its own colour');

  // The machine restarts: a fresh session, the settings as saved, the windows reopened
  // where they were with new handles and new titles.
  const saved = JSON.parse(JSON.stringify(config));
  state = tags.createState();
  const reopened = [placed('11', 'app.one', 1405, 'News - Play'), placed('12', 'app.one', 3, 'Inbox - Work'), placed('13', 'app.one', 700, 'New tab')];
  tags.resolve(saved, state, reopened);
  equal(['11', '12', '13'].map((hwnd) => (tags.tagOf(saved, state, hwnd) || {}).name || null), ['Play', 'Work', null], 'tags back on the right windows; a new window untagged');
});

await test('maximised windows of one app: the title breaks the tie', async () => {
  const config = model.emptyConfig();
  let state = tags.createState();
  const dev = placed('1', 'app.one', 0, 'GitHub - Dev', true);
  const work = placed('2', 'app.one', 0, 'Docs - Work', true);
  tags.tagWindow(config, state, dev, tags.createTag(config, 'Dev').id);
  tags.tagWindow(config, state, work, tags.createTag(config, 'Work').id);
  state = tags.createState();
  tags.resolve(config, state, [placed('21', 'app.one', 0, 'Docs - Work', true), placed('22', 'app.one', 0, 'GitHub - Dev', true)]);
  equal([tags.tagOf(config, state, '21').name, tags.tagOf(config, state, '22').name], ['Work', 'Dev'], 'matched by title');
});

await test('tagged windows get their own pills; deleting a tag puts them back', async () => {
  const config = model.emptyConfig();
  const state = tags.createState();
  const windows = [placed('1', 'app.one', 0, 'a'), placed('2', 'app.one', 500, 'b'), placed('3', 'app.one', 900, 'c'), windowOf('4', 'app.two')];
  const work = tags.createTag(config, 'Work');
  tags.tagWindow(config, state, windows[1], work.id);
  tags.tagWindow(config, state, windows[2], work.id);
  const withTags = () => windows.map((window) => ({ ...window, tag: tags.tagOf(config, state, window.hwnd) }));
  const items = model.buildModel(config, context(withTags()));
  equal(items.map((item) => [item.key, item.tag ? item.tag.name : null, item.windows.length]), [['app.one', null, 1], ['app.one', 'Work', 2], ['app.two', null, 1]], 'pills');
  // Pinned, with every open window tagged: no empty pinned pill beside the tagged one,
  // which carries the pin instead.
  model.setPinned(config, { key: 'app.two', name: 'Two' }, true);
  const two = windows[3];
  tags.tagWindow(config, state, two, work.id);
  const pinnedItems = model.buildModel(config, context(withTags())).filter((item) => item.key === 'app.two');
  equal(pinnedItems.map((item) => [item.tag ? item.tag.name : null, item.pinned, item.windows.length]), [['Work', true, 1]], 'one pill for the pinned app, tagged');
  tags.tagWindow(config, state, two, null);
  equal(model.buildModel(config, context(withTags())).filter((item) => item.key === 'app.two').map((item) => [item.tag, item.pinned]), [[null, true]], 'untagged again: the pinned pill holds it');
  model.setPinned(config, { key: 'app.two' }, false);
  tags.deleteTag(config, state, work.id);
  equal(model.buildModel(config, context(withTags())).map((item) => item.windows.length), [3, 1], 'back in one pill');
  equal(config.tagged.length, 0, 'nothing left remembered');
});

await test('a folder keeps its apps while they are closed, and takes them back when they open', async () => {
  const config = model.emptyConfig();
  const windows = [windowOf('1', 'app.one'), windowOf('2', 'app.two')];
  const visible = model.buildModel(config, context(windows));
  model.merge(config, visible[1].ref, visible[0].ref, visible);
  // Both close, the settings are saved and read back (a restart).
  const saved = JSON.parse(JSON.stringify(config));
  equal(model.buildModel(saved, context([])).length, 0, 'an unpinned folder with nothing open hides');
  equal(saved.items.filter((item) => item.type === 'folder').length, 1, 'but is kept');
  // One app opens again: it goes straight back into its folder.
  const items = model.buildModel(saved, context([windowOf('9', 'app.two')]));
  equal(items.map((item) => [item.type, item.type === 'folder' ? item.apps.filter((app) => app.running).map((app) => app.key) : item.key]), [['folder', ['app.two']]], 'in its folder');
});

await test('drop and hold makes a folder; more apps join it; renaming; ungrouping', async () => {
  const config = model.emptyConfig();
  const windows = [windowOf('1', 'app.one'), windowOf('2', 'app.two'), windowOf('3', 'app.three')];
  let visible = model.buildModel(config, context(windows));
  const created = model.merge(config, 'app:app.two', 'app:app.one', visible);
  assert(created && created.created, 'a new folder');
  visible = model.buildModel(config, context(windows));
  equal(visible.map((item) => item.type), ['folder', 'app'], 'folder in the first app\'s place');
  equal(visible[0].apps.map((app) => app.key), ['app.one', 'app.two'], 'folder members');
  model.merge(config, 'app:app.three', visible[0].ref, visible);
  visible = model.buildModel(config, context(windows));
  equal(visible.length, 1, 'third app joined the folder');
  model.rename(config, created.id, '  Work  ');
  equal(model.buildModel(config, context(windows))[0].name, 'Work', 'renamed');
  model.removeFromFolder(config, created.id, 'app.three');
  model.removeFromFolder(config, created.id, 'app.two');
  equal(model.buildModel(config, context(windows)).map((item) => item.type), ['app', 'app', 'app'], 'a one-app folder ungroups itself');
});

await test('a pinned category gathers every app with that label', async () => {
  const config = model.emptyConfig();
  model.pinCategory(config, 'Dev');
  const items = model.buildModel(config, context([], { 'app.one': 'Dev', 'app.three': 'Dev', 'app.two': 'Media' }));
  equal(items.map((item) => [item.name, item.apps.map((app) => app.key)]), [['Dev', ['app.one', 'app.three']]], 'category folder');
});

await test('reordering keeps running apps in their new place', async () => {
  const config = model.emptyConfig();
  const windows = [windowOf('1', 'app.one'), windowOf('2', 'app.two')];
  const visible = model.buildModel(config, context(windows));
  model.reorder(config, ['app:app.two', 'app:app.one'], visible);
  equal(model.buildModel(config, context(windows)).map((item) => item.key), ['app.two', 'app.one'], 'order');
});

const trayBefore = win32('tray');
console.log('Opening test windows...');
const windowA = await openTestWindow('E2E Window A', 300, 300);
const windowB = await openTestWindow('E2E Window B', 760, 380);
const stateOf = (testWindow) => win32('state', testWindow.hwnd);
let app = null;

try {
  // ---------- helper ----------

  console.log('\nHelper');
  const iconCache = path.join(work, 'icons');
  let helper = startHelper();
  helper.send('ownpid 1');
  helper.send(`index ${iconCache}`); // the app always gives the helper its icon cache
  let testWindowExe = '';

  await test('lists the open windows with their icons', async () => {
    const since = helper.events.length;
    helper.send('listwindows');
    const { windows } = await helper.next('a window list', (event) => event.event === 'windows', since);
    const ours = windows.filter((item) => item.title.startsWith('E2E Window'));
    testWindowExe = ours[0] ? ours[0].exe : '';
    equal(ours.map((item) => item.title).sort(), ['E2E Window A', 'E2E Window B'], 'test windows listed');
    assert(ours.every((item) => item.icon && fs.existsSync(item.icon)), 'every test window has an icon file');
  });

  await test('knows the screen is not empty', async () => {
    const since = helper.events.length;
    helper.send('checkempty');
    const event = await helper.next('a screen report', (item) => item.event === 'screen', since);
    equal(event.empty, false, 'screen empty');
  });

  await test('tab group: merge, switch, split', async () => {
    const targetBefore = stateOf(windowB);
    helper.send('tabs 1');
    helper.send(`tabmerge ${windowA.hwnd} ${windowB.hwnd}`);
    await waitFor('A shown in B\'s place, B hidden', () => {
      const a = stateOf(windowA);
      return a.visible && !stateOf(windowB).visible && a.left === targetBefore.left && a.top === targetBefore.top;
    });
    helper.send(`tabactivate ${windowB.hwnd}`);
    await waitFor('switching shows B and hides A', () => stateOf(windowB).visible && !stateOf(windowA).visible);
    helper.send(`tabsplit ${windowA.hwnd}`);
    await waitFor('splitting shows A again, offset', () => {
      const a = stateOf(windowA);
      return a.visible && stateOf(windowB).visible && a.left !== stateOf(windowB).left;
    });
  });

  await test('quitting the helper shows hidden tabs', async () => {
    helper.send(`tabmerge ${windowA.hwnd} ${windowB.hwnd}`);
    await waitFor('B hidden', () => !stateOf(windowB).visible);
    await helper.quit();
    await waitFor('B shown again', () => stateOf(windowB).visible);
  });

  await test('after a crash, hidden tabs come back (only for the same program)', async () => {
    helper = startHelper();
    helper.send('ownpid 1');
    helper.send('tabs 1');
    helper.send(`tabmerge ${windowA.hwnd} ${windowB.hwnd}`);
    await waitFor('B hidden', () => !stateOf(windowB).visible);
    helper.kill();
    await sleep(600);
    assert(!stateOf(windowB).visible, 'B stays hidden when the helper is killed outright');
    helper = startHelper();
    helper.send('ownpid 1');
    helper.send(`restorewindow ${windowB.hwnd} C:\\Windows\\notepad.exe`);
    await sleep(800);
    assert(!stateOf(windowB).visible, 'a different program\'s path must not restore it');
    helper.send(`restorewindow ${windowB.hwnd} ${testWindowExe}`);
    await waitFor('B restored', () => stateOf(windowB).visible);
  });

  // Whatever happened above, the next tests need both windows on screen.
  if (!stateOf(windowB).visible) win32('restore', windowB.hwnd);
  if (!stateOf(windowA).visible) win32('restore', windowA.hwnd);

  await test('taskbar feed lists running windows', async () => {
    const since = helper.events.length;
    helper.send('taskbar 1');
    const event = await helper.next('a taskbar list', (item) => item.event === 'taskwindows', since);
    const titles = event.windows.map((item) => item.title);
    assert(titles.includes('E2E Window A') && titles.includes('E2E Window B'), `test windows missing from ${JSON.stringify(titles)}`);
  });

  await test('hides the Windows taskbar, peeks it, and restores it exactly', async () => {
    helper.send('nativetaskbar hide');
    await waitFor('Windows taskbar hidden with auto-hide on', () => {
      const tray = win32('tray');
      return !tray.visible && tray.autoHide;
    });
    // The chevron's peek: shown with auto-hide off, then tucked away again.
    helper.send('nativetaskbar peek');
    await waitFor('the Windows taskbar peeking', () => {
      const tray = win32('tray');
      return tray.visible && !tray.autoHide;
    });
    helper.send('nativetaskbar peek');
    await waitFor('the peek ended', () => {
      const tray = win32('tray');
      return !tray.visible && tray.autoHide;
    });
    helper.send('nativetaskbar show');
    await waitFor('Windows taskbar back as it was', () => {
      const tray = win32('tray');
      return tray.visible === trayBefore.visible && tray.autoHide === trayBefore.autoHide;
    });
  });

  await helper.quit();

  // ---------- app ----------

  console.log('\nApp');
  app = await startApp(profile);
  const launcher = await findPage('index.html');

  await test('launcher lists installed apps and finds commands', async () => {
    await waitFor('apps from the helper', () => launcher.eval('state.apps.length > 10'), 30000, 500);
    const names = await launcher.eval("queryInput.value = 'set'; queryInput.dispatchEvent(new Event('input')); visibleRows.map((row) => row.name)");
    assert(names.includes('Settings'), `Settings missing from ${JSON.stringify(names)}`);
  });

  await test('an exact alias ranks first', async () => {
    const result = await launcher.eval(`(() => {
      const app = state.apps.find((candidate) => aliasOf(candidate.id).length === 2);
      queryInput.value = aliasOf(app.id).toLowerCase();
      queryInput.dispatchEvent(new Event('input'));
      return { want: app.name, got: visibleRows[0] && visibleRows[0].name };
    })()`);
    equal(result.got, result.want, 'first result');
  });

  await test('Esc clears the search; the scopes show and cycle only while searching', async () => {
    const afterEscape = await launcher.eval("queryInput.value = 'a'; queryInput.dispatchEvent(new Event('input')); window.dispatchEvent(new KeyboardEvent('keydown', { key: 'Escape' })); queryInput.value");
    equal(afterEscape, '', 'search after Esc');
    // Empty, the scopes are hidden and Tab leaves them be; typed, Tab cycles them.
    const idle = await launcher.eval("window.dispatchEvent(new KeyboardEvent('keydown', { key: 'Tab' })); ({ scope: activeScope, shown: getComputedStyle(document.getElementById('scopes')).display !== 'none' })");
    equal(idle, { scope: 'All', shown: false }, 'empty search');
    const typed = await launcher.eval("queryInput.value = 'a'; queryInput.dispatchEvent(new Event('input')); window.dispatchEvent(new KeyboardEvent('keydown', { key: 'Tab' })); ({ scope: activeScope, shown: getComputedStyle(document.getElementById('scopes')).display !== 'none' })");
    equal(typed, { scope: 'Apps', shown: true }, 'while searching');
    await launcher.eval("window.dispatchEvent(new KeyboardEvent('keydown', { key: 'Escape' })); 1");
  });

  await test('palette is compact and results-only', async () => {
    await launcher.eval("window.api.devPreview('palette')");
    await waitFor('palette mode', () => launcher.eval("document.body.classList.contains('palette')"));
    const layout = await launcher.eval("({ width: document.getElementById('launcher').offsetWidth, user: getComputedStyle(document.querySelector('.foot .user')).display, power: getComputedStyle(document.getElementById('power')).display })");
    equal(layout, { width: 640, user: 'none', power: 'none' }, 'palette layout');
  });

  await test('Home shows recent items, and typing turns it into the launcher', async () => {
    await launcher.eval("window.api.devPreview('home')");
    await waitFor('Home page', () => launcher.eval("document.body.classList.contains('home') && document.readyState === 'complete'"));
    // offsetWidth ignores the rise-in animation's scale, which getBoundingClientRect would include.
    const idle = await launcher.eval("({ field: document.getElementById('launcher').offsetWidth, searching: document.body.classList.contains('searching') })");
    equal(idle, { field: 560, searching: false }, 'Home at rest');
    const rows = await launcher.eval("queryInput.value = 'set'; queryInput.dispatchEvent(new Event('input')); document.body.classList.contains('searching') ? visibleRows.length : -1");
    assert(rows > 0, `typing on Home should show results, got ${rows}`);
  });

  await test('intro greets, then hands over to Home', async () => {
    await launcher.eval("window.api.devPreview('intro')");
    const greeting = await waitFor('the greeting', () => launcher.eval("document.getElementById('greetingText').textContent"));
    assert(/^Good (morning|afternoon|evening)/.test(greeting), `unexpected greeting "${greeting}"`);
    await sleep(2000);
    equal(await launcher.eval("getComputedStyle(document.getElementById('launcher')).opacity"), '1', 'Home field after the intro');
    await launcher.eval("window.api.devPreview('launcher')");
    await waitFor('launcher page back', () => launcher.eval("!document.body.classList.contains('home') && document.readyState === 'complete'"));
  });

  await test('switcher shows the open windows with live previews', async () => {
    const before = app.output.length;
    await launcher.eval("window.api.devPreview('switcher')");
    const switcher = await findPage('switcher.html');
    const titles = await waitFor('switcher cards', () => switcher.eval("root.classList.contains('open') && windows.map((item) => item.title)"));
    assert(titles.includes('E2E Window A') && titles.includes('E2E Window B'), `test windows missing from ${JSON.stringify(titles)}`);
    await sleep(500);
    const errors = app.output.slice(before).filter((line) => /thumbnail for/.test(line));
    equal(errors, [], 'preview errors');
    await switcher.eval('window.api.switcherCancel(); 1');
    switcher.close();
  });

  // ---------- Files ----------

  let files;
  await test('Files opens a folder', async () => {
    await launcher.eval(`window.api.openPath(${JSON.stringify(fixture)})`);
    files = await findPage('files.html');
    const names = await waitFor('the folder listing', () => files.eval('visible.length === 3 && visible.map((entry) => entry.name)'));
    equal(names, ['gamma', 'alpha.txt', 'beta.png'], 'listing (folders first)');
  });

  await test('Files: new folder, then rename it', async () => {
    await files.eval('newFolder(); 1');
    await waitFor('the rename field', () => files.eval("Boolean(document.querySelector('input.rename'))"));
    await files.eval("(() => { const input = document.querySelector('input.rename'); input.value = 'Renamed folder'; input.dispatchEvent(new KeyboardEvent('keydown', { key: 'Enter' })); return 1; })()");
    await waitFor('the folder on disk', () => fs.existsSync(path.join(fixture, 'Renamed folder')) && !fs.existsSync(path.join(fixture, 'New folder')));
  });

  await test('Files: copy a file and paste it into a folder', async () => {
    await files.eval(`selected = new Set([visible.find((entry) => entry.name === 'alpha.txt').path]); copySelection('copy'); navigate(${JSON.stringify(path.join(fixture, 'gamma'))}); 1`);
    await waitFor('gamma open', () => files.eval("folderName(currentPath()) === 'gamma'"));
    await files.eval('pasteHere()');
    await waitFor('the copy on disk', () => fs.existsSync(path.join(fixture, 'gamma', 'alpha.txt')));
    assert(fs.existsSync(path.join(fixture, 'alpha.txt')), 'the original must stay');
  });

  await test('Files: Delete sends to the Recycle Bin', async () => {
    await waitFor('the copy listed', () => files.eval("visible.some((entry) => entry.name === 'alpha.txt')"));
    await files.eval("selected = new Set([visible.find((entry) => entry.name === 'alpha.txt').path]); recycle()");
    await waitFor('the copy gone', () => !fs.existsSync(path.join(fixture, 'gamma', 'alpha.txt')));
  });

  await test('Files: filter and density', async () => {
    await files.eval('goBack(); 1');
    await waitFor('back in the fixture', () => files.eval(`currentPath() === ${JSON.stringify(fixture)}`));
    const filtered = await files.eval("pathInput.value = 'beta'; pathInput.dispatchEvent(new Event('input')); visible.map((entry) => entry.name)");
    equal(filtered, ['beta.png'], 'filtered listing');
    await files.eval("setDensity('spacious'); 1");
    await waitFor('density saved', () => JSON.parse(fs.readFileSync(path.join(profile, 'settings.json'), 'utf8')).filesDensity === 'spacious');
    await files.eval("pathInput.dispatchEvent(new KeyboardEvent('keydown', { key: 'Escape' })); setDensity('comfy'); 1");
  });

  // Real input events: a press on the first tab, moves, a release.
  async function dragTab(page, dx, dy) {
    const start = await page.eval("(() => { const r = document.querySelector('.tab').getBoundingClientRect(); return { x: r.left + 30, y: r.top + r.height / 2 }; })()");
    await page.mouse('mousePressed', start.x, start.y, 1);
    for (let step = 1; step <= 8; step++) {
      await page.mouse('mouseMoved', start.x + (dx * step) / 8, start.y + (dy * step) / 8, 1);
      await sleep(40);
    }
    await page.mouse('mouseReleased', start.x + dx, start.y + dy, 0);
    await sleep(400);
  }

  await test('Files: dragging a tab along the strip reorders it', async () => {
    await files.eval(`openTab(${JSON.stringify(path.join(fixture, 'gamma'))}); selectTab(tabs[0].id); 1`);
    await sleep(400);
    const before = await files.eval('tabs.map((tab) => folderName(tab.history[tab.index]))');
    await dragTab(files, 260, 0);
    const after = await files.eval('tabs.map((tab) => folderName(tab.history[tab.index]))');
    equal(after, [...before].reverse(), 'tab order after the drag');
  });

  await test('Files: pulling a tab off opens it in a new window', async () => {
    const windowsBefore = await pageCount('files.html');
    await dragTab(files, 60, 300);
    await waitFor('a new Files window', async () => (await pageCount('files.html')) === windowsBefore + 1);
    equal(await files.eval('tabs.length'), 1, 'tabs left in the original window');
  });

  await test('Files: the drop slot stays steady across another window\'s header', async () => {
    const [first, second] = await allPages('files.html');
    const origin = await second.eval('({ x: window.screenX, y: window.screenY })');
    const seen = new Set();
    for (const [dx, dy] of [[300, 20], [420, 30], [560, 80], [600, 90]]) {
      await first.eval(`window.api.files.tabDrag({ x: ${origin.x + dx}, y: ${origin.y + dy}, grab: { x: 20, y: 14, width: 140 }, title: 'E2E' }); 1`);
      await sleep(120);
      seen.add(await second.eval("(() => { const slot = document.querySelector('.tab.slot'); if (!slot) return 'none'; slot.dataset.e2e = slot.dataset.e2e || String(Math.random()); return slot.dataset.e2e; })()"));
    }
    assert(!seen.has('none') && seen.size === 1, `the slot should be one steady element, saw ${JSON.stringify([...seen])}`);
    await first.eval(`window.api.files.tabDrag({ x: ${origin.x + 600}, y: ${origin.y + 200}, grab: { x: 20, y: 14, width: 140 }, title: 'E2E' }); 1`);
    await waitFor('the slot gone below the header', () => second.eval("!document.querySelector('.tab.slot')"));
    await first.eval('window.api.files.tabDrag(null); 1');
    for (const page of [first, second]) {
      await page.eval("window.api.files.window('close'); 1").catch(() => {});
      page.close();
    }
  });

  await test('toasts appear in the corner', async () => {
    await launcher.eval("window.api.devToast({ title: 'E2E toast', text: 'From the test run' }); 1");
    const toast = await findPage('toast.html');
    const title = await waitFor('the toast card', () => toast.eval("document.querySelector('.card .title') && document.querySelector('.card .title').textContent"));
    equal(title, 'E2E toast', 'toast title');
    toast.close();
  });

  await test('no page reported an error', async () => {
    const errors = app.output.filter((line) => /\[(renderer|files):(error|3)\]|load failed|\] gone:|Uncaught/i.test(line));
    equal(errors, [], 'page errors');
  });

  await test('quits cleanly', async () => {
    await launcher.eval('window.api.devQuit(); 1').catch(() => {});
    await waitFor('the app to exit', () => app.exited(), 10000);
    await sleep(500);
    equal(win32('errordialogs'), 0, 'error dialogs');
  });
  launcher.close();

  // ---------- taskbar ----------

  console.log('\nTaskbar');
  app = await startApp(profile, ['--taskbar']);
  const taskbar = await findPage('taskbar.html', 15000);

  const testAppPill = "items.find((item) => item.type === 'app' && item.windows.some((window) => window.title === 'E2E Window A'))";

  await test('replaces the Windows taskbar; one pill for both test windows', async () => {
    await waitFor('the Windows taskbar hidden', () => !win32('tray').visible, 10000, 500);
    const titles = await waitFor('the test windows on the bar', () => taskbar.eval(`(() => { const app = ${testAppPill}; return app && app.windows.map((window) => window.title).sort(); })()`));
    equal(titles, ['E2E Window A', 'E2E Window B'], 'windows of the combined pill');
  });

  await test('clicking a pill with several windows lists them', async () => {
    const titles = await taskbar.eval(`(() => {
      const app = ${testAppPill};
      activateApp(app, document.querySelector('.item[data-ref="' + CSS.escape(app.ref) + '"]'));
      return [...document.querySelectorAll('#popover [data-hwnd] .name')].map((name) => name.textContent).sort();
    })()`);
    equal(titles, ['E2E Window A', 'E2E Window B'], 'popover rows');
    await taskbar.eval('closePopover(); 1');
  });

  await test('hovering a running pill shows live previews', async () => {
    win32('cursor', '400,200'); // the real pointer well away from the bar
    const before = app.output.length;
    const point = await taskbar.eval(`(() => { const r = document.querySelector('.item[data-ref="' + CSS.escape(${testAppPill}.ref) + '"]').getBoundingClientRect(); return { x: r.left + r.width / 2, y: r.top + r.height / 2 }; })()`);
    await taskbar.mouse('mouseMoved', point.x, point.y);
    const cards = await waitFor('preview cards', () => taskbar.eval("(((element) => getComputedStyle(element).display !== 'none' && element.getClientRects().length > 0)(document.getElementById('previews'))) && document.querySelectorAll('#previews .preview').length"));
    equal(cards, 2, 'preview cards');
    await sleep(400);
    equal(app.output.slice(before).filter((line) => /thumbnail for/.test(line)), [], 'preview errors');
  });

  await test('previews close by themselves once the pointer is really gone', async () => {
    // The page saw the pointer arrive but never leave (it left the window in one jump);
    // the bar asks where the real pointer is and closes them.
    await waitFor('the previews closed', () => taskbar.eval("!(((element) => getComputedStyle(element).display !== 'none' && element.getClientRects().length > 0)(document.getElementById('previews')))"), 4000);
  });

  await test('previews close when the pointer moves along the bar to something else', async () => {
    const pill = await taskbar.eval(`(() => { const r = document.querySelector('.item[data-ref="' + CSS.escape(${testAppPill}.ref) + '"]').getBoundingClientRect(); return { x: r.left + r.width / 2, y: r.top + r.height / 2 }; })()`);
    const origin = await taskbar.eval('({ x: window.screenX, y: window.screenY })');
    // The page still places the previous test's DevTools pointer on this pill; that one moves
    // off first, or the real pointer arriving at the same spot would be no change to it.
    await taskbar.mouse('mouseMoved', 5, 5);
    // The real pointer, as a hand would move it: off the bar first, so arriving is a fresh hover.
    win32('cursor', `${Math.round(origin.x + pill.x)},${Math.round(origin.y + pill.y - 300)}`);
    await sleep(150);
    win32('cursor', `${Math.round(origin.x + pill.x)},${Math.round(origin.y + pill.y)}`);
    await waitFor('previews for the hovered pill', () => taskbar.eval("(((element) => getComputedStyle(element).display !== 'none' && element.getClientRects().length > 0)(document.getElementById('previews')))"));
    // Still on the bar, but over the clock: the previews belong to the pill, so they go.
    const clock = await taskbar.eval("(() => { const r = document.getElementById('clock').getBoundingClientRect(); return { x: r.left + r.width / 2, y: r.top + r.height / 2 }; })()");
    win32('cursor', `${Math.round(origin.x + clock.x)},${Math.round(origin.y + clock.y)}`);
    await waitFor('the previews closed', () => taskbar.eval("!(((element) => getComputedStyle(element).display !== 'none' && element.getClientRects().length > 0)(document.getElementById('previews')))"), 4000);
    win32('cursor', '400,200');
  });

  await test('dropping a pill on another makes a folder that can be renamed', async () => {
    const refs = await waitFor('two pills', () => taskbar.eval(`(() => { const ours = ${testAppPill}; const other = items.find((item) => item.type === 'app' && item !== ours); return other && [ours.ref, other.ref]; })()`));
    await taskbar.eval(`window.api.taskbarMerge(${JSON.stringify(refs[0])}, ${JSON.stringify(refs[1])}); 1`);
    const folder = await waitFor('the folder', () => taskbar.eval("(() => { const folder = items.find((item) => item.type === 'folder'); return folder && { id: folder.id, apps: folder.apps.length }; })()"));
    equal(folder.apps, 2, 'apps in the new folder');
    await waitFor('the rename field', () => taskbar.eval("Boolean(document.getElementById('renameInput'))"));
    const live = await taskbar.eval("(() => { const input = document.getElementById('renameInput'); input.value = 'E2E folder'; input.dispatchEvent(new Event('input')); return document.querySelector('.item.renaming .label').textContent; })()");
    equal(live, 'E2E folder', 'the pill shows the name while it is typed');
    await taskbar.eval("(() => { const input = document.getElementById('renameInput'); input.dispatchEvent(new KeyboardEvent('keydown', { key: 'Enter' })); return 1; })()");
    await waitFor('the new name', () => taskbar.eval("(items.find((item) => item.type === 'folder') || {}).name === 'E2E folder'"));
    const saved = JSON.parse(fs.readFileSync(path.join(profile, 'settings.json'), 'utf8')).taskbar.items.find((item) => item.type === 'folder');
    equal(saved && saved.name, 'E2E folder', 'saved folder name');
  });

  await test('a maximised window ends above the bar, which stays', async () => {
    win32('maximize', windowA.hwnd);
    // Focus it the way a click on its pill does (a background script cannot take focus itself).
    await taskbar.eval(`window.api.devHelper('activate ${windowA.hwnd}'); 1`);
    const barTop = await taskbar.eval("Math.round((screenY + document.getElementById('bar').getBoundingClientRect().top) * devicePixelRatio)");
    const scale = await taskbar.eval('devicePixelRatio');
    // A maximised window hangs its invisible resize border (about 8 px) past the work area.
    await waitFor('window A to end above the bar', () => {
      const state = win32('state', windowA.hwnd);
      return state.zoomed && state.top + state.height <= barTop + 10 * scale;
    });
    await sleep(500);
    equal(await taskbar.eval("document.getElementById('dock').classList.contains('hidden')"), false, 'bar hidden');
    win32('restore', windowA.hwnd);
  });

  await test('with auto-hide on, it hides while a window is maximised, and comes back', async () => {
    await taskbar.eval('window.api.devTaskbarAutoHide(true); 1');
    win32('maximize', windowA.hwnd);
    await taskbar.eval(`window.api.devHelper('activate ${windowA.hwnd}'); 1`);
    try {
      await waitFor('the bar hidden', () => taskbar.eval("document.getElementById('dock').classList.contains('hidden')"));
    } catch (error) {
      const state = win32('state', windowA.hwnd);
      const focused = await taskbar.eval("items.flatMap((item) => item.type === 'folder' ? item.apps : [item]).flatMap((app) => app.windows).filter((window) => window.focused).map((window) => window.title)");
      throw new Error(`${error.message}; window A zoomed=${state.zoomed}, focused windows on the bar: ${JSON.stringify(focused)}`);
    }
    win32('restore', windowA.hwnd);
    await waitFor('the bar back', () => taskbar.eval("!document.getElementById('dock').classList.contains('hidden')"));
    await taskbar.eval('window.api.devTaskbarAutoHide(false); 1');
  });

  await test('quitting puts the Windows taskbar back, without errors', async () => {
    const launcherPage = await findPage('index.html');
    await launcherPage.eval('window.api.devQuit(); 1').catch(() => {});
    await waitFor('the app to exit', () => app.exited(), 10000);
    await waitFor('the Windows taskbar back as it was', () => {
      const tray = win32('tray');
      return tray.visible === trayBefore.visible && tray.autoHide === trayBefore.autoHide;
    }, 8000, 500);
    equal(win32('errordialogs'), 0, 'error dialogs');
  });
  taskbar.close();

  await test('a crash still puts the Windows taskbar back', async () => {
    app = await startApp(profile, ['--taskbar']);
    await waitFor('the Windows taskbar hidden', () => !win32('tray').visible, 15000, 500);
    app.stop(); // killed outright, no goodbye
    await waitFor('the Windows taskbar back as it was', () => {
      const tray = win32('tray');
      return tray.visible === trayBefore.visible && tray.autoHide === trayBefore.autoHide;
    }, 8000, 500);
  });
} catch (error) {
  console.log(`\nStopped early during "${current}": ${error.message}`);
  results.push({ name: current, ok: false, error: error.message });
} finally {
  if (app) app.stop();
  windowA.close();
  windowB.close();
  // Never leave the Windows taskbar hidden or its auto-hide changed, whatever happened above.
  const tray = win32('tray');
  if (!tray.visible || tray.autoHide !== trayBefore.autoHide) {
    const helper = startHelper();
    helper.send(`nativetaskbar restore ${trayBefore.autoHide ? 1 : 0}`);
    await sleep(800);
    await helper.quit();
  }
}

const failed = results.filter((result) => !result.ok);
console.log(`\n${results.length - failed.length} passed, ${failed.length} failed`);
if (!failed.length) fs.rmSync(work, { recursive: true, force: true });
else console.log(`Test files kept in ${work}`);
process.exit(failed.length ? 1 : 0);
