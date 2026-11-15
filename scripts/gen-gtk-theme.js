// Writes the apps' GTK colours for the Linux desktop (linux/gtk): libadwaita's named colours
// and GTK 3's in graphite-dark.css and graphite-light.css, and for GTK 4 the same again as the
// CSS variables libadwaita 1.6 and later read, in graphite-dark-gtk4.css and
// graphite-light-gtk4.css (GTK 3 can't read those: they're kept apart so it doesn't complain).
// Dark is Vesper, the shell's look (its colours copied below from
// linux/quickshell/config/Theme.qml); light is still Graphite's, from design/graphite/tokens.json,
// as Vesper has no light theme yet. Each comes with the indigo accent; linux/gtk/apply.sh puts
// the accent chosen in the shell over it.
const fs = require('fs');
const path = require('path');

const root = path.join(__dirname, '..');
const tokens = JSON.parse(fs.readFileSync(path.join(root, 'design', 'graphite', 'tokens.json'), 'utf8'));
const targetDir = path.join(root, 'linux', 'gtk');

const colour = (name, scheme) => {
  const token = tokens.color.tokens.find((candidate) => candidate.name === name);
  if (!token) throw new Error('no colour token ' + name);
  return typeof token.value === 'string' ? token.value : token.value[scheme];
};

// Vesper, as config/Theme.qml has it.
const vesper = {
  sidebar: '#0b0c0e',
  window: '#0f1012',
  panel: '#131417',
  raised: '#16171b',
  ink: '#edeef0',
  inkMuted: '#a0a3ab',
  accent: '#6e79f2',
  accentFill: '#5b63e6',
  accentText: '#9aa2ff',
  onAccent: '#ffffff',
  success: '#6fd3a4',
  warning: '#edb96b',
  danger: '#f08a8a',
  border: 'rgba(255, 255, 255, 0.09)',
  divider: 'rgba(255, 255, 255, 0.07)',
  card: 'rgba(255, 255, 255, 0.03)',
};

// libadwaita's names -> Vesper's colours. The red, green and amber fills are darker than the
// colours themselves, so white words on them stay readable (4.5:1 or better).
function darkNames() {
  const v = vesper;
  return {
    accent_color: v.accentText,
    accent_bg_color: v.accentFill,
    accent_fg_color: v.onAccent,
    destructive_color: v.danger,
    destructive_bg_color: '#c24d4d',
    destructive_fg_color: '#ffffff',
    success_color: v.success,
    success_bg_color: '#277a55',
    success_fg_color: '#ffffff',
    warning_color: v.warning,
    warning_bg_color: '#8f611a',
    warning_fg_color: '#ffffff',
    error_color: v.danger,
    error_bg_color: '#c24d4d',
    error_fg_color: '#ffffff',
    window_bg_color: v.window,
    window_fg_color: v.ink,
    view_bg_color: v.window,
    view_fg_color: v.ink,
    headerbar_bg_color: v.window,
    headerbar_fg_color: v.ink,
    headerbar_border_color: v.divider,
    headerbar_backdrop_color: v.window,
    headerbar_shade_color: v.divider,
    sidebar_bg_color: v.sidebar,
    sidebar_fg_color: v.ink,
    sidebar_backdrop_color: v.sidebar,
    sidebar_border_color: v.divider,
    sidebar_shade_color: v.divider,
    secondary_sidebar_bg_color: v.sidebar,
    secondary_sidebar_fg_color: v.ink,
    secondary_sidebar_backdrop_color: v.sidebar,
    secondary_sidebar_border_color: v.divider,
    card_bg_color: v.card,
    card_fg_color: v.ink,
    card_shade_color: v.divider,
    popover_bg_color: v.panel,
    popover_fg_color: v.ink,
    popover_shade_color: 'rgba(0, 0, 0, 0.25)',
    dialog_bg_color: v.panel,
    dialog_fg_color: v.ink,
    thumbnail_bg_color: v.raised,
    thumbnail_fg_color: v.ink,
    shade_color: 'rgba(0, 0, 0, 0.36)',
    borders: v.border,
  };
}

// libadwaita's names -> the Graphite tokens they take.
function lightNames() {
  const c = (name) => colour(name, 'light');
  return {
    accent_color: c('accent'),
    accent_bg_color: c('accent'),
    accent_fg_color: c('on-accent'),
    destructive_color: c('danger'),
    destructive_bg_color: c('danger'),
    destructive_fg_color: c('on-accent'),
    success_color: c('success'),
    success_bg_color: c('success'),
    success_fg_color: c('on-accent'),
    error_color: c('danger'),
    window_bg_color: c('surface-100'),
    window_fg_color: c('ink'),
    view_bg_color: c('surface-200'),
    view_fg_color: c('ink'),
    headerbar_bg_color: c('header'),
    headerbar_fg_color: c('ink'),
    headerbar_border_color: c('line'),
    headerbar_backdrop_color: c('header'),
    headerbar_shade_color: c('line'),
    sidebar_bg_color: c('surface-100'),
    sidebar_fg_color: c('ink'),
    sidebar_backdrop_color: c('surface-100'),
    sidebar_border_color: c('line'),
    secondary_sidebar_bg_color: c('surface-100'),
    secondary_sidebar_fg_color: c('ink'),
    card_bg_color: c('surface-200'),
    card_fg_color: c('ink'),
    card_shade_color: c('line'),
    popover_bg_color: c('surface-200'),
    popover_fg_color: c('ink'),
    dialog_bg_color: c('surface-200'),
    dialog_fg_color: c('ink'),
    thumbnail_bg_color: c('surface-300'),
    thumbnail_fg_color: c('ink'),
    shade_color: 'rgba(0, 0, 0, 0.25)',
    borders: c('line'),
  };
}

function names(scheme) {
  const named = scheme === 'dark' ? darkNames() : lightNames();
  // GTK 3 apps take the older names.
  const gtk3 = {
    theme_bg_color: named.window_bg_color,
    theme_fg_color: named.window_fg_color,
    theme_base_color: named.view_bg_color,
    theme_text_color: named.view_fg_color,
    theme_selected_bg_color: named.accent_bg_color,
    theme_selected_fg_color: named.accent_fg_color,
    insensitive_fg_color: scheme === 'dark' ? vesper.inkMuted : colour('ink-muted', 'light'),
  };
  return { named, gtk3 };
}

const header = (scheme, what) => `/* ${scheme === 'dark' ? 'Vesper' : 'Graphite'} (${scheme})${what}, generated by scripts/gen-gtk-theme.js.
   Do not edit: change the script and run \`npm run build:gtk-theme\`. */`;

// GTK 3 and 4: the named colours, and the selection in the accent, as in the shell.
function namedCss(scheme) {
  const { named, gtk3 } = names(scheme);
  const lines = Object.entries({ ...named, ...gtk3 }).map(([name, value]) => `@define-color ${name} ${value};`);
  return `${header(scheme, '')}
${lines.join('\n')}

/* The selection and focus in the accent, as in the shell. */
selection, *:selected { background-color: alpha(@accent_bg_color, 0.32); color: @window_fg_color; }
`;
}

// GTK 4: the named colours, then the same as libadwaita's variables (borders is border-color).
function variablesCss(scheme) {
  const { named } = names(scheme);
  const variable = (name) => '--' + (name === 'borders' ? 'border_color' : name).replace(/_/g, '-');
  const lines = Object.entries(named).map(([name, value]) => `  ${variable(name)}: ${value};`);
  return `${header(scheme, ', for GTK 4')}
@import url("graphite-${scheme}.css");

:root {
${lines.join('\n')}
}
`;
}

fs.mkdirSync(targetDir, { recursive: true });
for (const scheme of ['dark', 'light']) {
  for (const [file, text] of [[`graphite-${scheme}.css`, namedCss(scheme)], [`graphite-${scheme}-gtk4.css`, variablesCss(scheme)]]) {
    fs.writeFileSync(path.join(targetDir, file), text);
    console.log('wrote ' + path.join(targetDir, file));
  }
}
