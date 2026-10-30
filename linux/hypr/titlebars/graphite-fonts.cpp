// Graphite Desk's fourth addition to hyprbars: font settings changed since Hyprland started (as
// fonts/fonts.conf's grey smoothing for Hyprland's own text) apply when the plugin loads, not
// only at the next sign-in. Hyprland draws text with Pango's default font map, so it's told
// that fontconfig's settings changed, the way GTK does it when they do.
#include <fontconfig/fontconfig.h>
#include <pango/pangocairo.h>
#include <pango/pangofc-fontmap.h>

void graphiteReloadFonts() {
    if (FcConfigUptoDate(nullptr) || !FcInitReinitialize())
        return;
    PangoFontMap* fontMap = pango_cairo_font_map_get_default();
    if (PANGO_IS_FC_FONT_MAP(fontMap))
        pango_fc_font_map_config_changed(PANGO_FC_FONT_MAP(fontMap));
}
