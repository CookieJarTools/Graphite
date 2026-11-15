// Turns the Graphite tokens.json into linux/quickshell/config/Theme.qml: a QML singleton with
// every colour (dark and light, following Theme.dark), sizes and spacing as numbers,
// durations in milliseconds and easings as bezier curves for QML animations. The Linux shell
// draws from it exactly as the Windows one draws from renderer/tokens.css.
const fs = require('fs');
const path = require('path');

const root = path.join(__dirname, '..');
const source = path.join(root, 'design', 'graphite', 'tokens.json');
const target = path.join(root, 'linux', 'quickshell', 'config', 'Theme.qml');

// The Linux shell now has its own look (Vesper), written by hand in Theme.qml: this would put
// Graphite's tokens back over it, so it stops unless the file is still a generated one.
if (fs.existsSync(target) && !fs.readFileSync(target, 'utf8').includes('generated from design/graphite/tokens.json')) {
  console.error('linux/quickshell/config/Theme.qml is written by hand now (Vesper); not replaced.');
  process.exit(1);
}

const tokens = JSON.parse(fs.readFileSync(source, 'utf8'));

// "surface-200" -> "surface200", "ease-enter" -> "easeEnter"
const qmlName = (name) => name.replace(/-([a-z0-9])/g, (_, letter) => letter.toUpperCase());

// QML colours are "#RRGGBB" or "#AARRGGBB"; CSS rgba(r, g, b, a) becomes the latter.
function qmlColor(value) {
  const match = /^rgba?\(([^)]+)\)$/.exec(value.trim());
  if (!match) return value;
  const [r, g, b, a = 1] = match[1].split(',').map((part) => Number(part.trim()));
  const hex = (number) => Math.round(number).toString(16).padStart(2, '0');
  return '#' + hex(a * 255) + hex(r) + hex(g) + hex(b);
}

function colorProperties() {
  return tokens.color.tokens.map((token) => {
    const name = qmlName(token.name);
    if (typeof token.value === 'string') return `    readonly property color ${name}: "${qmlColor(token.value)}"`;
    return `    readonly property color ${name}: dark ? "${qmlColor(token.value.dark)}" : "${qmlColor(token.value.light)}"`;
  });
}

// "8px" -> 8, "140ms" -> 140; anything else is skipped (shadows, for one, are drawn in QML).
function numberProperties() {
  const lines = [];
  for (const [family, body] of Object.entries(tokens)) {
    if (family === 'color' || family === 'type' || family === 'easing' || !body || !Array.isArray(body.tokens)) continue;
    for (const token of body.tokens) {
      const match = /^(-?\d+(?:\.\d+)?)(px|ms)$/.exec(String(token.value).trim());
      if (match) lines.push(`    readonly property real ${qmlName(token.name)}: ${match[1]}`);
    }
  }
  return lines;
}

// cubic-bezier(a, b, c, d) -> [a, b, c, d, 1, 1], the form Easing.BezierSpline takes.
function easingProperties() {
  return (tokens.easing.tokens || []).flatMap((token) => {
    const match = /cubic-bezier\(([^)]+)\)/.exec(token.value);
    if (!match) return [];
    const points = match[1].split(',').map((value) => Number(value.trim()));
    return [`    readonly property var ${qmlName(token.name)}: [${points.join(', ')}, 1, 1]`];
  });
}

function typeProperties() {
  const first = (stack) => stack.split(',')[0].trim().replace(/^"|"$/g, '');
  const lines = Object.entries(tokens.type.families).map(([name, stack]) => `    readonly property string font${qmlName('-' + name)}: "${first(stack)}"`);
  for (const group of tokens.type.groups) {
    for (const style of group.styles) {
      const name = qmlName(style.name);
      lines.push(`    readonly property real ${name}Size: ${parseFloat(style.fontSize)}`);
      lines.push(`    readonly property real ${name}Line: ${parseFloat(style.lineHeight)}`);
      lines.push(`    readonly property int ${name}Weight: ${parseInt(style.fontWeight, 10)}`);
      lines.push(`    readonly property string ${name}Family: font${qmlName('-' + group.family)}`);
    }
  }
  return lines;
}

const qml = `// ${tokens.name}, generated from design/graphite/tokens.json by scripts/gen-qml-theme.js.
// Do not edit: change the tokens and run \`npm run build:qml-theme\`.
pragma Singleton

import QtQuick
import Quickshell

Singleton {
    // Dark unless the shell is told otherwise (Settings, or the system's colour scheme).
    property bool dark: true

${colorProperties().join('\n')}

${typeProperties().join('\n')}

${numberProperties().join('\n')}

${easingProperties().join('\n')}
}
`;

fs.mkdirSync(path.dirname(target), { recursive: true });
fs.writeFileSync(target, qml);
console.log('wrote ' + target);
