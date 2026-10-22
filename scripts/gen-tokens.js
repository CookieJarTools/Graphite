// Turns the Graphite Desk tokens.json into renderer/tokens.css: one custom property per
// token, dark values on :root and light values when Windows is in light app mode.
const fs = require('fs');
const path = require('path');

const root = path.join(__dirname, '..');
const source = path.join(root, 'design', 'graphite-desk', 'tokens.json');
const target = path.join(root, 'renderer', 'tokens.css');

const tokens = JSON.parse(fs.readFileSync(source, 'utf8'));
const [primaryTheme, ...otherThemes] = tokens.color.themes.map((t) => t.id);

const lines = (entries) => entries.map(([name, value]) => `  --${name}: ${value};`).join('\n');

function colorsFor(themeId) {
  return tokens.color.tokens
    .filter((t) => typeof t.value === 'string' ? themeId === primaryTheme : t.value[themeId])
    .map((t) => [t.name, typeof t.value === 'string' ? t.value : t.value[themeId]]);
}

function otherFamilies() {
  return Object.entries(tokens)
    .filter(([family, body]) => family !== 'color' && family !== 'type' && body && Array.isArray(body.tokens))
    .flatMap(([, body]) => body.tokens.map((t) => [t.name, t.value]));
}

function typeEntries() {
  const families = Object.entries(tokens.type.families).map(([name, stack]) => [`font-${name}`, stack]);
  const styles = tokens.type.groups.flatMap((group) => group.styles.flatMap((style) => [
    [`type-${style.name}-size`, style.fontSize],
    [`type-${style.name}-line`, style.lineHeight],
    [`type-${style.name}-weight`, style.fontWeight],
    [`type-${style.name}-family`, `var(--font-${group.family})`],
  ]));
  return [...families, ...styles];
}

let css = `/* ${tokens.name} — generated from design/graphite-desk/tokens.json by scripts/gen-tokens.js. Do not edit. */\n`;
css += `:root {\n${lines([...colorsFor(primaryTheme), ...typeEntries(), ...otherFamilies()])}\n}\n`;
for (const themeId of otherThemes) {
  css += `@media (prefers-color-scheme: ${themeId}) {\n  :root {\n${lines(colorsFor(themeId)).replace(/^/gm, '  ')}\n  }\n}\n`;
}

fs.writeFileSync(target, css);
console.log('wrote', target);
