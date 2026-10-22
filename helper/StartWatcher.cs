using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Text;

namespace WinKeyHelper;

/// <summary>
/// Safety net for the paths the keyboard hook can't cover: clicking the taskbar
/// Start button or Ctrl+Esc. Watches foreground-window changes; when the Windows
/// Start menu (StartMenuExperienceHost) takes focus we notify Electron, whose menu
/// steals focus back — the Windows Start menu is light-dismiss, so it closes itself.
/// </summary>
internal static class StartWatcher
{
    private static IntPtr _hook = IntPtr.Zero;
    private static WinEventDelegate? _proc; // kept referenced for the GC
    private static Action? _onStartOpened;

    public static void Install(Action onStartOpened)
    {
        if (_hook != IntPtr.Zero) return;
        _onStartOpened = onStartOpened;
        _proc = OnWinEvent;
        _hook = SetWinEventHook(EVENT_SYSTEM_FOREGROUND, EVENT_SYSTEM_FOREGROUND,
            IntPtr.Zero, _proc, 0, 0, WINEVENT_OUTOFCONTEXT);
    }

    private static void OnWinEvent(IntPtr hWinEventHook, uint eventType, IntPtr hwnd,
        int idObject, int idChild, uint dwEventThread, uint dwmsEventTime)
    {
        if (hwnd == IntPtr.Zero) return;

        // Anything other than our menu taking foreground → light-dismiss signal.
        // Independent of Enabled: the menu can be open via tray even when the
        // Win-key interception is switched off. Also fires reliably when the
        // focus-force failed and the menu never had focus to lose (no blur event).
        var sb = new StringBuilder(256);
        GetClassName(hwnd, sb, sb.Capacity);
        if (hwnd != Program.TargetHwnd)
            Program.Emit(new { @event = "focuslost", hwnd = hwnd.ToInt64().ToString(), className = sb.ToString() });

        if (!Program.Enabled) return;

        if (sb.ToString() != "Windows.UI.Core.CoreWindow") return;

        GetWindowThreadProcessId(hwnd, out uint pid);
        try
        {
            using var p = Process.GetProcessById((int)pid);
            if (p.ProcessName.Equals("StartMenuExperienceHost", StringComparison.OrdinalIgnoreCase))
                _onStartOpened?.Invoke();
        }
        catch { /* process already gone */ }
    }

    #region interop

    private const uint EVENT_SYSTEM_FOREGROUND = 0x0003;
    private const uint WINEVENT_OUTOFCONTEXT = 0x0000;

    private delegate void WinEventDelegate(IntPtr hWinEventHook, uint eventType, IntPtr hwnd,
        int idObject, int idChild, uint dwEventThread, uint dwmsEventTime);

    [DllImport("user32.dll")]
    private static extern IntPtr SetWinEventHook(uint eventMin, uint eventMax, IntPtr hmodWinEventProc,
        WinEventDelegate pfnWinEventProc, uint idProcess, uint idThread, uint dwFlags);

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    private static extern int GetClassName(IntPtr hWnd, StringBuilder lpClassName, int nMaxCount);

    [DllImport("user32.dll")]
    private static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint lpdwProcessId);

    #endregion
}
