using System.Runtime.InteropServices;
using System.Text;
using System.Text.Json;

namespace WinKeyHelper;

/// <summary>
/// Headless sidecar for the Electron app. Does the three things Chromium can't:
///   1. Low-level keyboard hook that intercepts a bare Win-key press
///   2. Detects the real Windows Start menu opening (Start button / Ctrl+Esc)
///   3. Enumerates shell:AppsFolder and extracts app icons as PNGs
///   4. Reports when the screen becomes empty, so Home can replace the desktop
///   5. Replaces Alt+Tab: lists windows, draws live DWM previews, switches and closes
///   6. Window tabs: groups windows dragged onto each other and keeps their strips in place
///   7. Taskbar: running windows from the shell hook, hiding and restoring the native bar
/// Protocol: JSON lines on stdout ({"event":"winkey"} etc.), plain-text commands
/// on stdin (enable 0|1, hwnd N, focus, focushwnd N, ownpid N, checkempty,
/// shellwindow N, unshellwindow N, alttab 0|1, palette 0|1, filese 0|1, listwindows, activate N, closewin N, thumbs X Y W H JSON, thumbsclear,
/// switcherdone, tabs 0|1, stripwin ID N, hoverstrip N, notabs N, tabactivate N, tabclose N,
/// tabsplit N, tabmerge SRC DEST, dragmove N, restorewindow N EXE, taskbar 0|1,
/// taskrefresh, nativetaskbar hide|show|peek|restore 0|1, minimize N, winkey A|N,
/// index DIR, sleep, quit).
/// </summary>
internal static class Program
{
    private static volatile bool _enabled = true;
    private static volatile bool _switcherEnabled;
    private static volatile bool _paletteEnabled;
    private static volatile bool _filesOnWinE;
    private static uint _ownPid;
    private static System.Windows.Forms.Control? _ui;
    private static long _targetHwnd;
    private static readonly object OutLock = new();

    public static bool Enabled => _enabled;
    public static bool SwitcherEnabled => _switcherEnabled;
    public static bool PaletteEnabled => _paletteEnabled;
    public static bool FilesOnWinE => _filesOnWinE;
    public static IntPtr TargetHwnd => (IntPtr)_targetHwnd;

    [STAThread]
    private static void Main()
    {
        Console.OutputEncoding = new UTF8Encoding(false); // a BOM would corrupt the first JSON line
        // Real pixels everywhere, so window rectangles and the preview overlay line up with Electron's.
        System.Windows.Forms.Application.SetHighDpiMode(System.Windows.Forms.HighDpiMode.PerMonitorV2);

        // Work that must not run inside the keyboard hook (it has a few hundred ms before
        // Windows drops it) is posted to the UI thread through this hidden control.
        _ui = new System.Windows.Forms.Control();
        _ui.CreateControl();
        _ = _ui.Handle;

        KeyboardHook.Install(
            () => Emit(new { @event = "winkey" }),
            OnSwitcherKey,
            () => Emit(new { @event = "palette" }),
            () => Emit(new { @event = "wine" }));
        StartWatcher.Install(() => Emit(new { @event = "startopened" }));
        EmptyScreenWatcher.Install((empty) => Emit(new { @event = "screen", empty }));
        TabGroups.Install();

        // Commands start flowing only once everything they can touch exists.
        var stdin = new Thread(StdinLoop) { IsBackground = true };
        stdin.Start();

        Emit(new { @event = "ready" });
        Microsoft.Win32.SystemEvents.SessionEnding += (_, _) => _sessionEnding = true;
        System.Windows.Forms.Application.Run(); // message pump both hooks require
    }

    private static void StdinLoop()
    {
        string? line;
        while ((line = Console.ReadLine()) is not null)
        {
            try { Handle(line.Trim()); }
            catch (Exception ex) { Emit(new { @event = "error", message = ex.Message }); }
        }
        Shutdown(); // stdin closed => parent died
    }

    // Signing out or shutting down: the native taskbar stays auto-hidden, so it is not seen
    // at the next sign-in before ours starts (that start puts its true setting back on quit).
    private static volatile bool _sessionEnding;

    // Hidden tab windows must never outlive the helper, so every exit shows them first.
    // Bounded, so a hung UI thread cannot keep the process alive.
    private static void Shutdown()
    {
        try
        {
            _ui!.BeginInvoke(() =>
            {
                TabGroups.RestoreAll();
                TrayHost.Stop(); // apps hand their icons back to Explorer
                AppBar.Release();
                if (!_sessionEnding) Taskbar.RestoreNative();
            }).AsyncWaitHandle.WaitOne(2000);
        }
        catch
        {
            // UI thread already gone: nothing left to restore from here; Electron's list covers it.
        }
        Environment.Exit(0);
    }

    private static void Handle(string line)
    {
        if (line.Length == 0) return;
        int sp = line.IndexOf(' ');
        string cmd = sp < 0 ? line : line[..sp];
        string arg = sp < 0 ? "" : line[(sp + 1)..];

        switch (cmd)
        {
            case "enable": _enabled = arg == "1"; break;
            case "hwnd": long.TryParse(arg, out _targetHwnd); break;
            case "focus": ForceFocus((IntPtr)_targetHwnd); break;
            case "focushwnd": ForceFocus(long.TryParse(arg, out long hwnd) ? (IntPtr)hwnd : IntPtr.Zero); break;
            case "ownpid":
                _ownPid = uint.TryParse(arg, out uint pid) ? pid : 0;
                EmptyScreenWatcher.OwnPid = _ownPid;
                TabGroups.OwnPid = _ownPid;
                Taskbar.OwnPid = _ownPid;
                break;
            case "shellwindow": WindowList.AddShellWindow(ParseHandle(arg)); break;
            case "unshellwindow": WindowList.RemoveShellWindow(ParseHandle(arg)); break;
            case "alttab": _switcherEnabled = arg == "1"; break;
            case "palette": _paletteEnabled = arg == "1"; break;
            case "filese": _filesOnWinE = arg == "1"; break;
            case "activate": WindowList.Activate(ParseHandle(arg)); break;
            case "closewin": WindowList.Close(ParseHandle(arg)); break;
            case "listwindows": _ui!.BeginInvoke(() => Emit(new { @event = "windows", windows = WindowList.Enumerate(_ownPid) })); break;
            case "switcherdone": KeyboardHook.EndSwitcher(); break;
            case "thumbs": ShowThumbnails(arg); break;
            case "thumbsclear": _ui!.BeginInvoke(Thumbnails.Clear); break;
            case "checkempty": EmptyScreenWatcher.Report(); break;
            case "index": Indexer.Run(arg); break;
            case "sleep": SetSuspendState(false, false, false); break;
            case "tabs":
                {
                    bool on = arg == "1";
                    _ui!.BeginInvoke(() => TabGroups.SetEnabled(on));
                    break;
                }
            case "stripwin":
                {
                    var parts = arg.Split(' ');
                    if (parts.Length == 2 && int.TryParse(parts[0], out int groupId))
                    {
                        IntPtr strip = ParseHandle(parts[1]);
                        _ui!.BeginInvoke(() => TabGroups.SetStrip(groupId, strip));
                    }
                    break;
                }
            case "hoverstrip": OnUi(TabGroups.SetHoverStrip, arg); break;
            case "notabs": OnUi(TabGroups.ExcludeFromGrouping, arg); break;
            case "tabactivate": OnUi(TabGroups.Activate, arg); break;
            case "tabclose": OnUi(TabGroups.Close, arg); break;
            case "tabsplit": OnUi(TabGroups.Split, arg); break;
            case "dragmove": OnUi(TabGroups.DragMove, arg); break;
            case "tabmerge":
                {
                    var parts = arg.Split(' ');
                    if (parts.Length == 2)
                    {
                        IntPtr source = ParseHandle(parts[0]);
                        IntPtr target = ParseHandle(parts[1]);
                        _ui!.BeginInvoke(() => TabGroups.MergeWindows(source, target));
                    }
                    break;
                }
            case "restorewindow":
                {
                    // "HWND EXE-PATH": the path may contain spaces, so it is everything after the first one.
                    int split = arg.IndexOf(' ');
                    if (split > 0)
                    {
                        IntPtr window = ParseHandle(arg[..split]);
                        string exe = arg[(split + 1)..];
                        _ui!.BeginInvoke(() => TabGroups.RestoreRemembered(window, exe));
                    }
                    break;
                }
            case "taskbar":
                {
                    bool on = arg == "1";
                    _ui!.BeginInvoke(() => Taskbar.SetEnabled(on));
                    break;
                }
            case "taskrefresh": _ui!.BeginInvoke(Taskbar.Refresh); break;
            case "nativetaskbar":
                switch (arg)
                {
                    case "hide": _ui!.BeginInvoke(() => Taskbar.HideNative()); break;
                    case "hide 0": _ui!.BeginInvoke(() => Taskbar.HideNative(false)); break;
                    case "hide 1": _ui!.BeginInvoke(() => Taskbar.HideNative(true)); break;
                    case "show": _ui!.BeginInvoke(Taskbar.RestoreNative); break;
                    case "peek": _ui!.BeginInvoke(Taskbar.ToggleNativePeek); break;
                    case "restore 0": _ui!.BeginInvoke(() => Taskbar.RestoreAfterCrash(false)); break;
                    case "restore 1": _ui!.BeginInvoke(() => Taskbar.RestoreAfterCrash(true)); break;
                }
                break;
            case "minimize": OnUi(Taskbar.Minimize, arg); break;
            case "system": SystemControls.Report(); break;
            case "notifications": NotificationCentre.Command(arg); break;
            case "tray": _ui!.BeginInvoke(arg == "1" ? TrayHost.Start : TrayHost.Stop); break;
            case "trayclick": _ui!.BeginInvoke(() => TrayHost.Click(arg)); break;
            case "wallpaper":
                if (arg == "state") _ui!.BeginInvoke(Desktop.ReportState);
                else if (arg.StartsWith("set ")) _ui!.BeginInvoke(() => Desktop.Set(arg[4..]));
                break;
            case "desktopicons": _ui!.BeginInvoke(() => Desktop.ShowIcons(arg == "1")); break;
            case "shellmenu": ShellMenu.Show(arg); break;
            case "shellmenupick": ShellMenu.Pick(arg); break;
            case "setclipfiles": _ui!.BeginInvoke(() => FileClipboard.Set(arg)); break;
            case "volume": SystemControls.SetVolume(arg); break;
            case "mute": SystemControls.SetMute(arg); break;
            case "radio": SystemControls.SetRadio(arg); break;
            case "media": SystemControls.Media(arg); break;
            case "reserve": if (int.TryParse(arg, out int reserve)) _ui!.BeginInvoke(() => AppBar.Reserve(reserve)); break;
            case "winkey": if (arg.Length == 1) Taskbar.PressWinAnd(arg[0]); break;
            case "sessionending": _sessionEnding = true; break;
            case "quit": Shutdown(); break;
        }
    }

    // "thumbs X Y W H [slots]": the switcher's screen rectangle in physical pixels, then
    // the preview slots inside it. The overlay is a window, so it is handled on the UI thread.
    private static void ShowThumbnails(string arg)
    {
        var parts = arg.Split(' ', 5);
        if (parts.Length < 5 || !int.TryParse(parts[0], out int x) || !int.TryParse(parts[1], out int y)
            || !int.TryParse(parts[2], out int width) || !int.TryParse(parts[3], out int height)) return;
        string slots = parts[4];
        _ui!.BeginInvoke(() => Thumbnails.Show(new System.Drawing.Rectangle(x, y, width, height), slots));
    }

    private static void OnUi(Action<IntPtr> action, string handle)
    {
        IntPtr window = ParseHandle(handle);
        _ui!.BeginInvoke(() => action(window));
    }

    private static IntPtr ParseHandle(string text) => long.TryParse(text, out long value) ? (IntPtr)value : IntPtr.Zero;

    // Opening needs the window list, which can take a moment the first time (icons), so
    // it runs after the hook returns; the other actions are forwarded straight away.
    private static void OnSwitcherKey(string action)
    {
        if (action.StartsWith("open"))
        {
            _ui!.BeginInvoke(() => Emit(new { @event = "switcher", action, windows = WindowList.Enumerate(_ownPid) }));
            return;
        }
        Emit(new { @event = "switcher", action });
    }

    /// <summary>Runs <paramref name="action"/> on the UI thread (hooks, timers, windows).</summary>
    public static void OnUiThread(Action action) => _ui!.BeginInvoke(action);

    public static void Emit(object payload)
    {
        lock (OutLock) Console.WriteLine(JsonSerializer.Serialize(payload));
    }

    /// <summary>
    /// Windows refuses SetForegroundWindow from background processes; a transient
    /// synthetic Alt press is the classic unlock for that restriction.
    /// </summary>
    /// <summary>Brings one of the helper's own windows to the front (menus need it to close properly).</summary>
    public static void ForceForeground(IntPtr hwnd) => ForceFocus(hwnd);

    /// <summary>
    /// Lets another process bring its window to the front (a tray app opening its menu). Only a
    /// process the user just gave input may pass that on, hence the same synthetic Alt.
    /// </summary>
    public static void AllowForeground(uint processId)
    {
        keybd_event(VK_MENU, 0, 0, IntPtr.Zero);
        keybd_event(VK_MENU, 0, KEYEVENTF_KEYUP, IntPtr.Zero);
        AllowSetForegroundWindow(processId);
    }

    [DllImport("user32.dll")]
    private static extern bool AllowSetForegroundWindow(uint processId);

    private static void ForceFocus(IntPtr hwnd)
    {
        if (hwnd == IntPtr.Zero) return;
        keybd_event(VK_MENU, 0, 0, IntPtr.Zero);
        SetForegroundWindow(hwnd);
        keybd_event(VK_MENU, 0, KEYEVENTF_KEYUP, IntPtr.Zero);
    }

    private const byte VK_MENU = 0x12;
    private const uint KEYEVENTF_KEYUP = 0x0002;

    [DllImport("user32.dll")]
    private static extern bool SetForegroundWindow(IntPtr hWnd);

    [DllImport("user32.dll")]
    private static extern void keybd_event(byte bVk, byte bScan, uint dwFlags, IntPtr dwExtraInfo);

    [DllImport("powrprof.dll", SetLastError = true)]
    private static extern bool SetSuspendState(bool hibernate, bool forceCritical, bool disableWakeEvent);
}
