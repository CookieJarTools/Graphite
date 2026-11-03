// Graphite's third addition to hyprbars: apps' own minimise buttons work (Discord, Steam,
// any app that draws its own title bar). Hyprland 0.57 hears the request (xdg_toplevel
// set_minimized, or an X11 app's) but does nothing with it; here the window goes where the shell
// keeps minimised windows, the special workspace "minimized" (services/Taskbar.qml), as the
// bar's own Minimise does. The move is made just after the request, not while it's handled.
#include <algorithm>
#include <format>
#include <vector>
#include <hyprland/src/plugins/PluginAPI.hpp>
#include <hyprland/src/event/EventBus.hpp>
#include <hyprland/src/helpers/signal/Signal.hpp>
#include <hyprland/src/managers/eventLoop/EventLoopManager.hpp>
#include <hyprland/src/desktop/state/WindowState.hpp>
#include <hyprland/src/desktop/view/window/Window.hpp>

namespace {
    struct SWatched {
        PHLWINDOWREF        window;
        CHyprSignalListener listener;
    };

    std::vector<SWatched> watched;
    CHyprSignalListener   openListener;

    void minimize(PHLWINDOWREF weak) {
        g_pEventLoopManager->doLater([weak] {
            const auto window = weak.lock();
            if (!window)
                return;
            HyprlandAPI::invokeHyprctlCommand("dispatch",
                                              std::format(R"(hl.dsp.window.move({{ workspace = "special:minimized", window = "address:0x{:x}", follow = false }}))",
                                                          reinterpret_cast<uintptr_t>(window.get())));
        });
    }

    void watch(PHLWINDOW window) {
        if (!window)
            return;
        std::erase_if(watched, [](const SWatched& entry) { return entry.window.expired(); });
        PHLWINDOWREF weak = window;
        watched.push_back({weak, window->backend().m_events.stateRequest.listen([weak](const Desktop::View::SBackendStateRequest& request) {
                               if (request.minimized.value_or(false))
                                   minimize(weak);
                           })});
    }
}

void graphiteHookMinimize(HANDLE handle) {
    for (const auto& window : Desktop::windowState()->windows())
        watch(window);
    openListener = Event::bus()->m_events.window.open.listen([](PHLWINDOW window) { watch(window); });
}
