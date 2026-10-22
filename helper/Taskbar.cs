using System.Runtime.InteropServices;
using System.Windows.Forms;

namespace WinKeyHelper;

/// <summary>
/// Everything the Graphite taskbar needs from Windows:
///   - the running windows, refreshed from the shell hook (the notifications Explorer's
///     own taskbar gets: created, destroyed, activated, title changed, flashing);
///   - whether the focused window is maximised, so the bar can hide;
///   - hiding the native taskbar (and turning on its auto-hide so maximised windows get
///     the whole screen), always undone by <see cref="RestoreNative"/>;
///   - pressing Win+A / Win+N for the quick settings and notification panels.
/// Runs on the UI thread.
/// </summary>
internal static class Taskbar
{
    private const int DebounceMilliseconds = 120;
    private const int ReassertMilliseconds = 1000;

    private static ShellHookWindow? _shellHook;
    private static System.Windows.Forms.Timer? _debounce;
    private static System.Windows.Forms.Timer? _keepNativeHidden;
    private static WinEventDelegate? _proc;
    private static IntPtr _locationHook;
    private static readonly HashSet<IntPtr> Flashing = new();
    private static bool _enabled;
    private static uint _ownPid;
    private static bool _lastZoomed;
    private static bool _nativeHidden;
    private static bool _nativeWasAutoHide;

    // Peek: the Windows taskbar shown for a moment (its tray icons), ended once the pointer
    // has left it and none of its menus has focus.
    private const int PeekPollMilliseconds = 250;
    private const int PeekLeaveMilliseconds = 1200;
    private const int PeekUnusedMilliseconds = 8000;
    private static System.Windows.Forms.Timer? _peekTimer;
    private static bool _peeking;
    private static long _peekStarted;
    private static long _peekLastInside;
    private static bool _peekEntered;

    public static uint OwnPid
    {
        set => _ownPid = value;
    }

    public static void SetEnabled(bool enabled)
    {
        _enabled = enabled;
        if (!enabled) return;
        if (_shellHook is null)
        {
            _debounce = new System.Windows.Forms.Timer { Interval = DebounceMilliseconds };
            _debounce.Tick += (_, _) =>
            {
                _debounce.Stop();
                EmitWindows();
            };
            _shellHook = new ShellHookWindow(OnShellEvent);
            _proc = OnLocationChange;
            _locationHook = SetWinEventHook(EVENT_OBJECT_LOCATIONCHANGE, EVENT_OBJECT_LOCATIONCHANGE, IntPtr.Zero, _proc, 0, 0, WINEVENT_OUTOFCONTEXT | WINEVENT_SKIPOWNPROCESS);
        }
        EmitWindows();
    }

    public static void Refresh() => EmitWindows();

    public static void Minimize(IntPtr hwnd) => PostMessage(hwnd, WM_SYSCOMMAND, (IntPtr)SC_MINIMIZE, IntPtr.Zero);

    // ---------- native taskbar ----------

    /// <param name="originalAutoHide">
    /// The native taskbar's own setting when an earlier session left it auto-hidden (at sign-out
    /// it is not put back, so it stays out of sight at the next sign-in); null to read it now.
    /// </param>
    public static void HideNative(bool? originalAutoHide = null)
    {
        if (!_nativeHidden)
        {
            _nativeWasAutoHide = originalAutoHide ?? (AppBarState() & ABS_AUTOHIDE) != 0;
            SetAppBarState(ABS_AUTOHIDE);
            _nativeHidden = true;
            Program.Emit(new { @event = "nativetaskbar", hidden = true, originalAutoHide = _nativeWasAutoHide });
        }
        ShowNativeWindows(false);

        // Explorer re-shows its taskbar now and then (a restart, a full-screen app ending),
        // so it is pushed back out of sight while ours is active.
        if (_keepNativeHidden is null)
        {
            _keepNativeHidden = new System.Windows.Forms.Timer { Interval = ReassertMilliseconds };
            _keepNativeHidden.Tick += (_, _) =>
            {
                if (_nativeHidden) ShowNativeWindows(false);
            };
        }
        _keepNativeHidden.Start();
    }

    /// <summary>Stops (or resumes) pushing the native taskbar out of sight, while it is shown on purpose.</summary>
    public static void PauseKeepingHidden(bool pause)
    {
        if (pause) _keepNativeHidden?.Stop();
        else if (_nativeHidden) _keepNativeHidden?.Start();
    }

    /// <summary>Puts the native taskbar back exactly as it was. Safe to call at any time.</summary>
    public static void RestoreNative()
    {
        _keepNativeHidden?.Stop();
        StopPeekTimer();
        if (!_nativeHidden) return;
        _nativeHidden = false;
        if (!_nativeWasAutoHide) SetAppBarState(0);
        ShowNativeWindows(true);
        Program.Emit(new { @event = "nativetaskbar", hidden = false, originalAutoHide = _nativeWasAutoHide });
    }

    /// <summary>After a crash: undoes what an earlier run did to the native taskbar.</summary>
    public static void RestoreAfterCrash(bool originalAutoHide)
    {
        bool wasHidden = !IsWindowVisible(TrayHost.NativeTray());
        if (!originalAutoHide) SetAppBarState(0);
        ShowNativeWindows(true);
        if (wasHidden) Program.Emit(new { @event = "taskbarrestored" });
    }

    /// <summary>Shows the Windows taskbar for a moment (its tray icons), or ends the peek.</summary>
    public static void ToggleNativePeek()
    {
        if (!_nativeHidden) return;
        if (_peeking) EndPeek();
        else StartPeek();
    }

    // Auto-hide has to come off too: with it on, a shown taskbar stays tucked off the edge.
    private static void StartPeek()
    {
        _peeking = true;
        _peekEntered = false;
        _peekStarted = _peekLastInside = Environment.TickCount64;
        _keepNativeHidden?.Stop();
        SetAppBarState(0);
        ShowNativeWindows(true);
        Program.Emit(new { @event = "peek", on = true });

        _peekTimer ??= new System.Windows.Forms.Timer { Interval = PeekPollMilliseconds };
        _peekTimer.Tick -= OnPeekTick;
        _peekTimer.Tick += OnPeekTick;
        _peekTimer.Start();
    }

    private static void OnPeekTick(object? sender, EventArgs e)
    {
        long now = Environment.TickCount64;
        GetCursorPos(out POINT cursor);
        GetWindowRect(TrayHost.NativeTray(), out RECT bar);
        bool inside = cursor.X >= bar.Left && cursor.X < bar.Right && cursor.Y >= bar.Top && cursor.Y < bar.Bottom;
        // A tray menu or the hidden-icons flyout belongs to Explorer and has focus while in use.
        if (inside || ForegroundIsExplorer())
        {
            _peekEntered |= inside;
            _peekLastInside = now;
            return;
        }
        bool leftAfterUse = _peekEntered && now - _peekLastInside > PeekLeaveMilliseconds;
        bool neverUsed = !_peekEntered && now - _peekStarted > PeekUnusedMilliseconds;
        if (leftAfterUse || neverUsed) EndPeek();
    }

    private static void EndPeek()
    {
        StopPeekTimer();
        if (!_nativeHidden) return;
        SetAppBarState(ABS_AUTOHIDE);
        ShowNativeWindows(false);
        _keepNativeHidden?.Start();
    }

    private static void StopPeekTimer()
    {
        _peekTimer?.Stop();
        if (!_peeking) return;
        _peeking = false;
        Program.Emit(new { @event = "peek", on = false });
    }

    private static bool ForegroundIsExplorer()
    {
        GetWindowThreadProcessId(GetForegroundWindow(), out uint pid);
        return WindowList.ProcessPath(pid).EndsWith("\\explorer.exe", StringComparison.OrdinalIgnoreCase);
    }

    private static void ShowNativeWindows(bool show)
    {
        int command = show ? SW_SHOWNA : SW_HIDE;
        IntPtr primary = TrayHost.NativeTray();
        if (primary != IntPtr.Zero && IsWindowVisible(primary) != show) ShowWindow(primary, command);
        IntPtr secondary = IntPtr.Zero;
        while ((secondary = FindWindowEx(IntPtr.Zero, secondary, "Shell_SecondaryTrayWnd", null)) != IntPtr.Zero)
        {
            if (IsWindowVisible(secondary) != show) ShowWindow(secondary, command);
        }
    }

    private static uint AppBarState()
    {
        var data = new APPBARDATA { cbSize = Marshal.SizeOf<APPBARDATA>() };
        return (uint)SHAppBarMessage(ABM_GETSTATE, ref data);
    }

    private static void SetAppBarState(uint state)
    {
        var data = new APPBARDATA { cbSize = Marshal.SizeOf<APPBARDATA>(), lParam = (IntPtr)state };
        SHAppBarMessage(ABM_SETSTATE, ref data);
    }

    // ---------- keys ----------

    /// <summary>Presses Win plus a letter, for example 'A' (quick settings) or 'N' (notifications).</summary>
    public static void PressWinAnd(char letter)
    {
        ushort key = char.ToUpperInvariant(letter);
        var inputs = new[]
        {
            KeyInput(VK_LWIN, 0),
            KeyInput(key, 0),
            KeyInput(key, KEYEVENTF_KEYUP),
            KeyInput(VK_LWIN, KEYEVENTF_KEYUP),
        };
        SendInput((uint)inputs.Length, inputs, Marshal.SizeOf<INPUT>());
    }

    private static INPUT KeyInput(ushort vk, uint flags) => new()
    {
        type = INPUT_KEYBOARD,
        U = new InputUnion { ki = new KEYBDINPUT { wVk = vk, dwFlags = flags } },
    };

    // ---------- window list ----------

    private static void OnShellEvent(int code, IntPtr hwnd)
    {
        if (!_enabled) return;
        if (code == HSHELL_FLASH) Flashing.Add(hwnd);
        if (code is HSHELL_WINDOWACTIVATED or HSHELL_RUDEAPPACTIVATED) Flashing.Remove(hwnd);
        if (code == HSHELL_WINDOWDESTROYED) Flashing.Remove(hwnd);
        _debounce!.Stop();
        _debounce.Start();
    }

    // Maximising or restoring the focused window changes whether the bar should hide.
    private static void OnLocationChange(IntPtr hook, uint eventType, IntPtr hwnd, int idObject, int idChild, uint thread, uint time)
    {
        if (!_enabled || idObject != 0 || hwnd != GetForegroundWindow()) return;
        if (IsZoomed(hwnd) == _lastZoomed) return;
        _debounce!.Stop();
        _debounce.Start();
    }

    private static void EmitWindows()
    {
        if (!_enabled) return;
        IntPtr foreground = GetForegroundWindow();
        _lastZoomed = foreground != IntPtr.Zero && IsZoomed(foreground);
        Program.Emit(new
        {
            @event = "taskwindows",
            windows = WindowList.Enumerate(_ownPid),
            foreground = foreground.ToInt64().ToString(),
            flashing = Flashing.Select((hwnd) => hwnd.ToInt64().ToString()).ToList(),
            zoomed = _lastZoomed,
        });
    }

    /// <summary>A hidden window registered for the shell hook messages.</summary>
    private sealed class ShellHookWindow : NativeWindow
    {
        private readonly Action<int, IntPtr> _onEvent;
        private readonly uint _shellHookMessage;

        public ShellHookWindow(Action<int, IntPtr> onEvent)
        {
            _onEvent = onEvent;
            CreateHandle(new CreateParams());
            _shellHookMessage = RegisterWindowMessage("SHELLHOOK");
            RegisterShellHookWindow(Handle);
        }

        protected override void WndProc(ref Message m)
        {
            if ((uint)m.Msg == _shellHookMessage)
            {
                _onEvent((int)(m.WParam.ToInt64() & 0xFFFF), m.LParam);
                return;
            }
            base.WndProc(ref m);
        }
    }

    #region interop

    private const int HSHELL_WINDOWDESTROYED = 2;
    private const int HSHELL_WINDOWACTIVATED = 4;
    private const int HSHELL_RUDEAPPACTIVATED = 0x8004;
    private const int HSHELL_FLASH = 0x8006;
    private const uint EVENT_OBJECT_LOCATIONCHANGE = 0x800B;
    private const uint WINEVENT_OUTOFCONTEXT = 0x0000;
    private const uint WINEVENT_SKIPOWNPROCESS = 0x0002;
    private const uint WM_SYSCOMMAND = 0x0112;
    private const int SC_MINIMIZE = 0xF020;
    private const int SW_HIDE = 0;
    private const int SW_SHOWNA = 8;
    private const uint ABM_GETSTATE = 0x4;
    private const uint ABM_SETSTATE = 0xA;
    private const uint ABS_AUTOHIDE = 0x1;
    private const ushort VK_LWIN = 0x5B;
    private const uint KEYEVENTF_KEYUP = 0x0002;
    private const uint INPUT_KEYBOARD = 1;

    private delegate void WinEventDelegate(IntPtr hWinEventHook, uint eventType, IntPtr hwnd,
        int idObject, int idChild, uint dwEventThread, uint dwmsEventTime);

    [StructLayout(LayoutKind.Sequential)]
    private struct RECT
    {
        public int Left, Top, Right, Bottom;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct POINT
    {
        public int X, Y;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct APPBARDATA
    {
        public int cbSize;
        public IntPtr hWnd;
        public uint uCallbackMessage;
        public uint uEdge;
        public RECT rc;
        public IntPtr lParam;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct INPUT
    {
        public uint type;
        public InputUnion U;
    }

    [StructLayout(LayoutKind.Explicit)]
    private struct InputUnion
    {
        [FieldOffset(0)] public KEYBDINPUT ki;
        [FieldOffset(0)] public MOUSEINPUT mi;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct KEYBDINPUT
    {
        public ushort wVk;
        public ushort wScan;
        public uint dwFlags;
        public uint time;
        public IntPtr dwExtraInfo;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct MOUSEINPUT
    {
        public int dx;
        public int dy;
        public uint mouseData;
        public uint dwFlags;
        public uint time;
        public IntPtr dwExtraInfo;
    }

    [DllImport("user32.dll")]
    private static extern IntPtr SetWinEventHook(uint eventMin, uint eventMax, IntPtr hmodWinEventProc,
        WinEventDelegate pfnWinEventProc, uint idProcess, uint idThread, uint dwFlags);

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    private static extern uint RegisterWindowMessage(string message);

    [DllImport("user32.dll")]
    private static extern bool RegisterShellHookWindow(IntPtr hwnd);

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    private static extern IntPtr FindWindow(string className, string? windowName);

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    private static extern IntPtr FindWindowEx(IntPtr parent, IntPtr childAfter, string className, string? windowName);

    [DllImport("user32.dll")]
    private static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);

    [DllImport("user32.dll")]
    private static extern bool IsWindowVisible(IntPtr hWnd);

    [DllImport("user32.dll")]
    private static extern bool IsZoomed(IntPtr hWnd);

    [DllImport("user32.dll")]
    private static extern IntPtr GetForegroundWindow();

    [DllImport("user32.dll")]
    private static extern bool PostMessage(IntPtr hWnd, uint msg, IntPtr wParam, IntPtr lParam);

    [DllImport("user32.dll", SetLastError = true)]
    private static extern uint SendInput(uint nInputs, INPUT[] pInputs, int cbSize);

    [DllImport("shell32.dll")]
    private static extern IntPtr SHAppBarMessage(uint message, ref APPBARDATA data);

    [DllImport("user32.dll")]
    private static extern bool GetCursorPos(out POINT point);

    [DllImport("user32.dll")]
    private static extern bool GetWindowRect(IntPtr hWnd, out RECT rect);

    [DllImport("user32.dll")]
    private static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint processId);

    #endregion
}
