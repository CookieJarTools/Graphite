// Graphite Desk's addition to hyprbars (titlebars/build.sh compiles it in): a bar only for the
// windows that leave their title bar to the desktop, which Hyprland knows from what each app
// agreed through the decoration protocols. Apps that draw their own (GTK 4, Firefox, Electron
// with its own frame) keep theirs, without a second bar over it.
#include <unordered_map>
#include <vector>
#include <hyprland/src/protocols/XDGDecoration.hpp>
#include <hyprland/src/protocols/ServerDecorationKDE.hpp>
#include <hyprland/src/protocols/XDGShell.hpp>
#include <hyprland/src/protocols/core/Compositor.hpp>
#include <hyprland/src/desktop/view/window/Window.hpp>
#include "graphite-expose.hpp"

// The protocols keep each window's agreement in private lists.
struct SXdgDecorations {
    using type = std::unordered_map<wl_resource*, UP<CXDGDecoration>> CXDGDecorationProtocol::*;
    friend type member(SXdgDecorations);
};
template struct SExpose<SXdgDecorations, &CXDGDecorationProtocol::m_decorations>;

struct SKdeDecorations {
    using type = std::vector<UP<CServerDecorationKDE>> CServerDecorationKDEProtocol::*;
    friend type member(SKdeDecorations);
};
template struct SExpose<SKdeDecorations, &CServerDecorationKDEProtocol::m_decos>;

bool graphiteWantsServerTitleBar(PHLWINDOW window) {
    const auto& backend = window->backend();
    // X11 apps say so through their hints (Steam draws its own).
    if (backend.type() == Desktop::View::eBackendType::WINDOW_BACKEND_X11)
        return !backend.traits().suggestsNoBorder;

    const auto surface = backend.surface();
    if (!surface)
        return false;

    const auto* role     = surface->m_role ? dynamic_cast<CXDGSurfaceRole*>(surface->m_role.get()) : nullptr;
    const auto  xdg      = role ? role->m_xdgSurface.lock() : nullptr;
    const auto  toplevel = xdg ? xdg->m_toplevel.lock() : nullptr;
    if (toplevel && PROTO::xdgDecoration) {
        for (const auto& [resource, decoration] : (*PROTO::xdgDecoration).*member(SXdgDecorations{})) {
            if (decoration && CXDGToplevelResource::fromResource(resource) == toplevel)
                return decoration->mostRecentlySent == ZXDG_TOPLEVEL_DECORATION_V1_MODE_SERVER_SIDE;
        }
    }

    // GTK 3 asks through KDE's older protocol.
    if (PROTO::serverDecorationKDE) {
        for (const auto& decoration : (*PROTO::serverDecorationKDE).*member(SKdeDecorations{})) {
            if (decoration && decoration->m_surf == surface)
                return decoration->m_mostRecentlySent == ORG_KDE_KWIN_SERVER_DECORATION_MODE_SERVER;
        }
    }

    // Asked for neither: it draws its own.
    return false;
}
