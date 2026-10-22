using System.Runtime.InteropServices;
using System.Text;

namespace WinKeyHelper;

/// <summary>
/// Tells Electron when the screen becomes empty (no real app window visible, as after Win+D
/// or Win+M) and when it stops being empty, so Home can
/// stand in for the desktop. Driven by WinEvent hooks rather than polling: any
/// show/hide/minimise/cloak/foreground change restarts a short debounce, then the
/// window list is evaluated once.
/// </summary>
internal static class EmptyScreenWatcher
{
    private const int DebounceMilliseconds = 150;

    private static readonly string[] IgnoredClasses =
    {
        "Progman", "WorkerW", "Shell_TrayWnd", "Shell_SecondaryTrayWnd", "NotifyIconOverflowWindow",
        "Windows.UI.Core.CoreWindow", "Shell_InputSwitchTopLevelWindow", "XamlExplorerHostIslandWindow",
    };

    private static readonly List<IntPtr> Hooks = new();
    private static WinEventDelegate? _proc; // kept referenced for the GC
    private static System.Windows.Forms.Timer? _debounce;
    private static Action<bool>? _onChange;
    private static bool? _lastEmpty;
    private static volatile uint _ownPid;

    /// <summary>Electron's main process: its windows (Home, launcher) never count as app windows.</summary>
    public static uint OwnPid
    {
        set => _ownPid = value;
    }

    public static void Install(Action<bool> onChange)
    {
        _onChange = onChange;
        _proc = OnWinEvent;
        _debounce = new System.Windows.Forms.Timer { Interval = DebounceMilliseconds };
        _debounce.Tick += (_, _) =>
        {
            _debounce.Stop();
            Evaluate(false);
        };

        Hook(EVENT_SYSTEM_FOREGROUND, EVENT_SYSTEM_FOREGROUND);
        Hook(EVENT_SYSTEM_MINIMIZESTART, EVENT_SYSTEM_MINIMIZEEND);
        Hook(EVENT_OBJECT_DESTROY, EVENT_OBJECT_HIDE);
        Hook(EVENT_OBJECT_CLOAKED, EVENT_OBJECT_UNCLOAKED);
    }

    /// <summary>Re-evaluates and always reports, even when nothing changed.</summary>
    public static void Report() => Evaluate(true);

    private static void Hook(uint eventMin, uint eventMax)
    {
        var hook = SetWinEventHook(eventMin, eventMax, IntPtr.Zero, _proc!, 0, 0, WINEVENT_OUTOFCONTEXT | WINEVENT_SKIPOWNPROCESS);
        if (hook != IntPtr.Zero) Hooks.Add(hook);
    }

    private static void OnWinEvent(IntPtr hWinEventHook, uint eventType, IntPtr hwnd,
        int idObject, int idChild, uint dwEventThread, uint dwmsEventTime)
    {
        // Only whole windows matter; caret, cursor and control events are noise.
        if (idObject != OBJID_WINDOW || idChild != 0) return;
        _debounce!.Stop();
        _debounce.Start();
    }

    private static void Evaluate(bool force)
    {
        bool empty = IsScreenEmpty();
        if (!force && empty == _lastEmpty) return;
        _lastEmpty = empty;
        _onChange?.Invoke(empty);
    }

    // Empty means no app window shows. The desktop merely having focus does not count: that is
    // also what a click on the wallpaper does, and Home must not jump in front of open
    // windows then (Win+D minimises them, so it is caught by the first test anyway).
    private static bool IsScreenEmpty() => !HasVisibleAppWindow();

    private static bool HasVisibleAppWindow()
    {
        bool found = false;
        EnumWindows((hwnd, _) =>
        {
            found = IsAppWindow(hwnd);
            return !found;
        }, IntPtr.Zero);
        return found;
    }

    private static bool IsAppWindow(IntPtr hwnd)
    {
        if (!IsWindowVisible(hwnd) || IsIconic(hwnd)) return false;
        if (GetWindowTextLength(hwnd) == 0) return false;
        if ((GetWindowLong(hwnd, GWL_EXSTYLE) & WS_EX_TOOLWINDOW) != 0) return false;
        if (IgnoredClasses.Contains(ClassName(hwnd))) return false;
        if (IsCloaked(hwnd)) return false;
        if (WindowList.IsInvisibleOverlay(hwnd)) return false;

        if (WindowList.IsShellWindow(hwnd)) return false;

        GetWindowRect(hwnd, out var rect);
        return rect.Right - rect.Left > 0 && rect.Bottom - rect.Top > 0;
    }

    // Suspended Store apps and windows on other virtual desktops are "cloaked": present but not drawn.
    private static bool IsCloaked(IntPtr hwnd)
    {
        return DwmGetWindowAttribute(hwnd, DWMWA_CLOAKED, out int cloaked, sizeof(int)) == 0 && cloaked != 0;
    }

    private static string ClassName(IntPtr hwnd)
    {
        var sb = new StringBuilder(256);
        GetClassName(hwnd, sb, sb.Capacity);
        return sb.ToString();
    }

    #region interop

    private const uint EVENT_SYSTEM_FOREGROUND = 0x0003;
    private const uint EVENT_SYSTEM_MINIMIZESTART = 0x0016;
    private const uint EVENT_SYSTEM_MINIMIZEEND = 0x0017;
    private const uint EVENT_OBJECT_DESTROY = 0x8001;
    private const uint EVENT_OBJECT_HIDE = 0x8003;
    private const uint EVENT_OBJECT_CLOAKED = 0x8017;
    private const uint EVENT_OBJECT_UNCLOAKED = 0x8018;
    private const uint WINEVENT_OUTOFCONTEXT = 0x0000;
    private const uint WINEVENT_SKIPOWNPROCESS = 0x0002;
    private const int OBJID_WINDOW = 0;
    private const int GWL_EXSTYLE = -20;
    private const int WS_EX_TOOLWINDOW = 0x00000080;
    private const int DWMWA_CLOAKED = 14;

    private delegate void WinEventDelegate(IntPtr hWinEventHook, uint eventType, IntPtr hwnd,
        int idObject, int idChild, uint dwEventThread, uint dwmsEventTime);

    private delegate bool EnumWindowsProc(IntPtr hwnd, IntPtr lParam);

    [StructLayout(LayoutKind.Sequential)]
    private struct RECT
    {
        public int Left, Top, Right, Bottom;
    }

    [DllImport("user32.dll")]
    private static extern IntPtr SetWinEventHook(uint eventMin, uint eventMax, IntPtr hmodWinEventProc,
        WinEventDelegate pfnWinEventProc, uint idProcess, uint idThread, uint dwFlags);

    [DllImport("user32.dll")]
    private static extern bool EnumWindows(EnumWindowsProc lpEnumFunc, IntPtr lParam);

    [DllImport("user32.dll")]
    private static extern bool IsWindowVisible(IntPtr hWnd);

    [DllImport("user32.dll")]
    private static extern bool IsIconic(IntPtr hWnd);

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    private static extern int GetWindowTextLength(IntPtr hWnd);

    [DllImport("user32.dll")]
    private static extern int GetWindowLong(IntPtr hWnd, int nIndex);

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    private static extern int GetClassName(IntPtr hWnd, StringBuilder lpClassName, int nMaxCount);

    [DllImport("user32.dll")]
    private static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint lpdwProcessId);

    [DllImport("user32.dll")]
    private static extern bool GetWindowRect(IntPtr hWnd, out RECT lpRect);

    [DllImport("dwmapi.dll")]
    private static extern int DwmGetWindowAttribute(IntPtr hwnd, int dwAttribute, out int pvAttribute, int cbAttribute);

    #endregion
}
