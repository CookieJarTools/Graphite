// Shared plumbing for the end-to-end tests: test windows, Win32 queries, driving the
// helper over stdio, and driving the app's pages over the Chrome DevTools Protocol.

import { spawn, execFileSync } from 'node:child_process';
import readline from 'node:readline';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

export const here = path.dirname(fileURLToPath(import.meta.url));
export const root = path.resolve(here, '..', '..');
export const helperExe = path.join(root, 'helper', 'bin', 'Release', 'net10.0-windows10.0.19041.0', 'WinKeyHelper.exe');
export const electronExe = path.join(root, 'node_modules', 'electron', 'dist', 'electron.exe');
export const debugPort = 9229;

export const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

/** Polls `check` until it returns something truthy, or throws after `timeout` ms. */
export async function waitFor(description, check, timeout = 8000, interval = 150) {
  const deadline = Date.now() + timeout;
  let last;
  while (Date.now() < deadline) {
    try {
      // A check that never settles (a request to an app that is closing) is cut off at the
      // deadline, so a run can fail but never hang.
      last = await Promise.race([check(), sleep(Math.max(0, deadline - Date.now())).then(() => { throw new Error('no answer'); })]);
      if (last) return last;
    } catch (error) {
      last = error;
    }
    await sleep(interval);
  }
  throw new Error(`timed out waiting for ${description}${last instanceof Error ? ` (${last.message})` : ''}`);
}

// ---------- Win32 ----------

export function win32(command, argument = '') {
  const output = execFileSync('powershell.exe', ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', path.join(here, 'win32.ps1'), command, String(argument)], { encoding: 'utf8' });
  return JSON.parse(output.trim());
}

/** Opens a plain test window and resolves to { hwnd, close }. */
export async function openTestWindow(title, x, y) {
  const process = spawn('powershell.exe', ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden', '-File', path.join(here, 'testwindow.ps1'), '-Title', title, '-X', String(x), '-Y', String(y)], { stdio: 'ignore' });
  const hwnd = await waitFor(`test window "${title}"`, () => win32('find', title), 15000, 400);
  return { hwnd: String(hwnd), title, close: () => process.kill() };
}

// ---------- the helper on its own ----------

export function startHelper() {
  const child = spawn(helperExe, [], { stdio: ['pipe', 'pipe', 'ignore'] });
  const events = [];
  readline.createInterface({ input: child.stdout }).on('line', (line) => {
    try { events.push(JSON.parse(line.replace(/^﻿/, ''))); } catch { /* not JSON */ }
  });
  return {
    events,
    send: (line) => child.stdin.write(line + '\n'),
    /** Waits for an event matching `predicate` that arrived after `since` (an events.length). */
    next: (description, predicate, since = 0, timeout = 8000) =>
      waitFor(description, () => events.slice(since).find(predicate), timeout, 50),
    kill: () => child.kill(),
    quit: async () => {
      child.stdin.write('quit\n');
      await waitFor('helper to exit', () => child.exitCode !== null, 5000, 100).catch(() => child.kill());
    },
  };
}

// ---------- the app ----------

/** Starts the app in dev mode with a throwaway profile; resolves once its launcher page is up. */
export async function startApp(profile, flags = []) {
  const output = [];
  const child = spawn(electronExe, ['.', '--dev', `--test-profile=${profile}`, `--remote-debugging-port=${debugPort}`, ...flags], { cwd: root, stdio: ['ignore', 'pipe', 'pipe'] });
  const collect = (data) => output.push(...String(data).split(/\r?\n/).filter(Boolean));
  child.stdout.on('data', collect);
  child.stderr.on('data', collect);
  const app = {
    child,
    output,
    exited: () => child.exitCode !== null,
    page: (name, timeout) => findPage(name, timeout),
    stop: () => {
      if (child.exitCode === null) child.kill();
    },
  };
  await app.page('index.html', 20000);
  return app;
}

async function listPages() {
  const response = await fetch(`http://127.0.0.1:${debugPort}/json`);
  return (await response.json()).filter((target) => target.type === 'page');
}

export async function pageCount(name) {
  return (await listPages()).filter((target) => target.url.includes(name)).length;
}

/** Resolves to a Page for the first page whose URL contains `name`. */
export async function findPage(name, timeout = 10000, index = 0) {
  const target = await waitFor(`page ${name}`, async () => (await listPages()).filter((candidate) => candidate.url.includes(name))[index], timeout, 200);
  return connect(target);
}

export async function allPages(name) {
  return Promise.all((await listPages()).filter((target) => target.url.includes(name)).map(connect));
}

async function connect(target) {
  const socket = new WebSocket(target.webSocketDebuggerUrl);
  await new Promise((resolve, reject) => {
    socket.onopen = resolve;
    socket.onerror = reject;
    setTimeout(() => reject(new Error('no connection to ' + target.url)), 10000);
  });
  let id = 0;
  const pending = new Map();
  socket.onmessage = (message) => {
    const data = JSON.parse(message.data);
    if (pending.has(data.id)) {
      pending.get(data.id)(data);
      pending.delete(data.id);
    }
  };
  // A page that closes mid-call (an app told to quit) never answers: calls fail after a while,
  // and at once when the connection drops, rather than hanging the run.
  const callTimeout = 15000;
  const call = (method, params = {}) => new Promise((resolve, reject) => {
    const callId = ++id;
    const timer = setTimeout(() => {
      pending.delete(callId);
      reject(new Error(`no answer to ${method}`));
    }, callTimeout);
    pending.set(callId, (data) => {
      clearTimeout(timer);
      resolve(data);
    });
    socket.send(JSON.stringify({ id: callId, method, params }));
  });
  socket.onclose = () => {
    for (const [callId, settle] of pending) {
      pending.delete(callId);
      settle({ error: { message: 'page closed' } });
    }
  };
  return {
    url: target.url,
    call,
    /** Evaluates `expression` in the page (promises awaited); throws on page errors. */
    async eval(expression) {
      const { result, error } = await call('Runtime.evaluate', { expression, returnByValue: true, awaitPromise: true });
      if (error) throw new Error(error.message);
      if (result.exceptionDetails) throw new Error(result.exceptionDetails.exception?.description || result.exceptionDetails.text);
      return result.result.value;
    },
    mouse: (type, x, y, buttons = 0) => call('Input.dispatchMouseEvent', { type, x, y, button: type === 'mouseMoved' && !buttons ? 'none' : 'left', buttons, clickCount: type === 'mouseMoved' ? 0 : 1 }),
    key: async (key, code = key, keyCode = 0) => {
      await call('Input.dispatchKeyEvent', { type: 'rawKeyDown', key, code, windowsVirtualKeyCode: keyCode });
      await call('Input.dispatchKeyEvent', { type: 'keyUp', key, code, windowsVirtualKeyCode: keyCode });
    },
    type: (text) => call('Input.insertText', { text }),
    close: () => socket.close(),
  };
}
