// Copies the shell's pure logic shared by both versions (taskbar-model.js, window-tags.js) into
// linux/quickshell/services/lib as QML JavaScript libraries, so the Linux bar arranges apps,
// folders and tags exactly as the Windows one does. Their `module.exports` line goes: every
// top-level function and constant of a `.pragma library` file is already its export.
const fs = require('fs');
const path = require('path');

const root = path.join(__dirname, '..');
const targetDir = path.join(root, 'linux', 'quickshell', 'services', 'lib');
const files = ['taskbar-model.js', 'window-tags.js'];

fs.mkdirSync(targetDir, { recursive: true });
for (const file of files) {
  const source = fs.readFileSync(path.join(root, file), 'utf8').replace(/\r\n/g, '\n');
  const body = source.replace(/^module\.exports = .*\n?/m, '');
  if (body === source) throw new Error(file + ': no module.exports line to take out');
  // QML's JavaScript lacks Array.prototype.flatMap (and object spread, which the sources avoid).
  const header = `.pragma library\n// Generated from ${file} by scripts/gen-qml-lib.js. Do not edit: change ${file} and run\n// \`npm run build:qml-lib\`.\n\n`
    + 'if (!Array.prototype.flatMap) Array.prototype.flatMap = function (map, self) { return [].concat.apply([], this.map(map, self)); };\n\n';
  fs.writeFileSync(path.join(targetDir, file), header + body);
  console.log('wrote ' + path.join(targetDir, file));
}
