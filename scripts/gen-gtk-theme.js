// Turns the Graphite Desk tokens.json into GTK colours for the Linux desktop's apps: libadwaita's
// named colours (Files, and every GTK 4 app) and the same for GTK 3, in a dark and a light file
// (linux/gtk/graphite-dark.css, graphite-light.css). The shell links ~/.config/gtk-4.0/gtk.css
// and ~/.config/gtk-3.0/gtk.css to the one its Dark mode setting picks.
const fs = require('fs');
const path = require('path');

const root = path.join(__dirname, '..');
const tokens = JSON.parse(fs.readFileSync(path.join(root, 'design', 'graphite-desk', 'tokens.json'), 'utf8'));
const targetDir = path.join(root, 'linux', 'gtk');

const colour = (name, scheme) => {
  const token = tokens.color.tokens.find((candidate) => candidate.name === name);
  if (!token) throw new Error('no colour token ' + name);
  return typeof token.value === 'string' ? token.value : token.value[scheme];
};

function css(scheme) {
  const c = (name) => colour(name, scheme);
  // libadwaita's names -> the Graphite tokens they take.
  const named = {
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
  const lines = Object.entries(named).map(([name, value]) => `@define-color ${name} ${value};`);
  // GTK 3 apps take the older names.
  const gtk3 = {
    theme_bg_color: c('surface-100'),
    theme_fg_color: c('ink'),
    theme_base_color: c('surface-200'),
    theme_text_color: c('ink'),
    theme_selected_bg_color: c('accent'),
    theme_selected_fg_color: c('on-accent'),
    insensitive_fg_color: c('ink-muted'),
  };
  lines.push(...Object.entries(gtk3).map(([name, value]) => `@define-color ${name} ${value};`));
  return `/* Graphite Desk (${scheme}), generated from design/graphite-desk/tokens.json by scripts/gen-gtk-theme.js.
   Do not edit: change the tokens and run \`npm run build:gtk-theme\`. */
${lines.join('\n')}

/* The selection and focus in the accent, as in the shell. */
selection, *:selected { background-color: alpha(${c('accent')}, 0.32); color: ${c('ink')}; }
`;
}

fs.mkdirSync(targetDir, { recursive: true });
for (const scheme of ['dark', 'light']) {
  const file = path.join(targetDir, `graphite-${scheme}.css`);
  fs.writeFileSync(file, css(scheme));
  console.log('wrote ' + file);
}
