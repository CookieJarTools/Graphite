// Graphite's second addition to hyprbars, dragging windows:
//
// X11 apps that draw their own title bar (Steam) can be dragged by it. They ask the window
// manager to move or resize them with _NET_WM_MOVERESIZE, which Hyprland 0.57 says it supports
// but never acts on; this hands the request on as the one a Wayland app makes
// (xdg_toplevel.move), which Hyprland does act on.
//
// A drag keeps going when Shift or Ctrl goes down (window zones: services/Zones.qml), where
// Hyprland ends it on any key. Those keys don't reach Hyprland's binds while a window is being
// dragged; hyprland.lua's keyboard event, which tells the shell, still hears them.
//
// The left button going down and up is told to the shell from here (its "pointer-down"
// shortcut), not by a bind in hyprland.lua: hyprbars takes the clicks on its bars before any
// bind sees them, so a window dragged by one of its title bars never showed the zones.
//
// `hyprctl -j titlebars` says which windows have a title bar of hyprbars' and how tall it is
// ({ "0x…": 32 }), for the shell to fit a window to a zone or half the screen with its bar
// inside it: Hyprland places a window by what's under the bar.
#include <format>
#include <string>
#include <vector>
#include <linux/input-event-codes.h>
#include <hyprland/src/plugins/PluginAPI.hpp>
#include <hyprland/src/plugins/HookSystem.hpp>
#include <hyprland/src/event/EventBus.hpp>
#include <hyprland/src/devices/IPointer.hpp>
#include <hyprland/src/protocols/GlobalShortcuts.hpp>
#include <hyprland/src/helpers/signal/Signal.hpp>
#include <hyprland/src/layout/LayoutManager.hpp>
#include <hyprland/src/layout/supplementary/DragController.hpp>
#include <hyprland/src/xwayland/XWayland.hpp>
#include <hyprland/src/xwayland/XWM.hpp>
#include <hyprland/src/xwayland/XSurface.hpp>
#include <hyprland/src/desktop/state/WindowState.hpp>
#include <hyprland/src/desktop/view/window/Window.hpp>
#include "graphite-expose.hpp"
#include "globals.hpp"
#include "barDeco.hpp"

// The X11 windows, which the window manager keeps to itself.
struct SXwmSurfaces {
    using type = std::vector<SP<CXWaylandSurface>> CXWM::*;
    friend type member(SXwmSurfaces);
};
template struct SExpose<SXwmSurfaces, &CXWM::m_surfaces>;

namespace {
    using Desktop::View::eBackendResizeEdge;
    using FClientMessage = void (*)(CXWM*, xcb_client_message_event_t*);

    CFunctionHook*                 clientMessageHook = nullptr;
    CHyprSignalListener            keyListener;
    CHyprSignalListener            buttonListener;
    SP<IPC::Socket1::SCommand>     titleBarsCommand;

    IPC::Socket1::SResponse titleBars(const IPC::Socket1::SRequest&) {
        std::string json = "{";
        for (const auto& weak : g_pGlobalState->bars) {
            const auto bar    = weak.lock();
            const auto window = bar ? bar->getOwner() : nullptr;
            const int  height = bar ? (int)bar->getPositioningInfo().desiredExtents.topLeft.y : 0;
            if (!window || height <= 0)
                continue;
            json += std::format("{}\"0x{:x}\":{}", json.size() > 1 ? "," : "", (uintptr_t)window.get(), height);
        }
        return json + "}";
    }

    // _NET_WM_MOVERESIZE's directions 0 to 7: the corners and edges clockwise from the top left;
    // 8 is a move.
    constexpr eBackendResizeEdge EDGES[] = {
        eBackendResizeEdge::BACKEND_RESIZE_EDGE_TOP_LEFT, eBackendResizeEdge::BACKEND_RESIZE_EDGE_TOP,
        eBackendResizeEdge::BACKEND_RESIZE_EDGE_TOP_RIGHT, eBackendResizeEdge::BACKEND_RESIZE_EDGE_RIGHT,
        eBackendResizeEdge::BACKEND_RESIZE_EDGE_BOTTOM_RIGHT, eBackendResizeEdge::BACKEND_RESIZE_EDGE_BOTTOM,
        eBackendResizeEdge::BACKEND_RESIZE_EDGE_BOTTOM_LEFT, eBackendResizeEdge::BACKEND_RESIZE_EDGE_LEFT,
    };
    constexpr uint32_t MOVE = 8;

    void onClientMessage(CXWM* wm, xcb_client_message_event_t* event) {
        if (event->type != HYPRATOMS["_NET_WM_MOVERESIZE"] || event->format != 32) {
            ((FClientMessage)clientMessageHook->m_original)(wm, event);
            return;
        }

        const auto direction = event->data.data32[2];
        if (direction > MOVE)
            return; // the keyboard ways and cancelling: nothing was started

        for (const auto& surface : (*wm).*member(SXwmSurfaces{})) {
            if (!surface || surface->m_xID != event->window)
                continue;

            const auto wlSurface = surface->m_surface.lock();
            for (const auto& window : Desktop::windowState()->windows()) {
                if (!window || !window->backend().isX11() || !wlSurface || window->backend().surface() != wlSurface)
                    continue;

                if (direction == MOVE)
                    window->backend().m_events.moveRequest.emit();
                else
                    window->backend().m_events.resizeRequest.emit(EDGES[direction]);
                return;
            }
        }
    }
}

void graphiteHookDrags(HANDLE handle) {
    for (const auto& match : HyprlandAPI::findFunctionsByName(handle, "handleClientMessage")) {
        if (match.demangled.find("CXWM::handleClientMessage") == std::string::npos)
            continue;

        clientMessageHook = HyprlandAPI::createFunctionHook(handle, match.address, (void*)&onClientMessage);
        if (clientMessageHook && !clientMessageHook->hook())
            clientMessageHook = nullptr;
        break;
    }

    keyListener = Event::bus()->m_events.input.keyboard.key.listen([](IKeyboard::SKeyEvent event, Event::SCallbackInfo& info) {
        const bool modifier = event.keycode == KEY_LEFTSHIFT || event.keycode == KEY_RIGHTSHIFT || event.keycode == KEY_LEFTCTRL || event.keycode == KEY_RIGHTCTRL;
        if (modifier && g_layoutManager && g_layoutManager->dragController()->target())
            info.cancelled = true;
    });

    // Every listener hears an event, whichever cancelled it, so this hears clicks hyprbars took.
    buttonListener = Event::bus()->m_events.input.mouse.button.listen([](IPointer::SButtonEvent event, Event::SCallbackInfo&) {
        if (event.button == BTN_LEFT && PROTO::globalShortcuts)
            PROTO::globalShortcuts->sendGlobalShortcutEvent("quickshell", "pointer-down", event.state == WL_POINTER_BUTTON_STATE_PRESSED);
    });

    titleBarsCommand = HyprlandAPI::registerHyprCtlCommand(handle, IPC::Socket1::SCommand{"titlebars", IPC::Socket1::COMMAND_MATCH_EXACT, titleBars});
}
