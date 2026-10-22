using System.IO;
using System.Runtime.InteropServices;
using System.Text;

namespace WinKeyHelper;

/// <summary>
/// The windows Alt+Tab would show, most recently used first (EnumWindows walks the
/// z-order top down). Each entry carries what the switcher needs to draw a card:
/// title, owning executable, AppUserModelID (so Store apps match their Start entry)
/// and an icon PNG from the shared icon cache.
/// </summary>
internal static class WindowList
{
    private static readonly string[] IgnoredClasses =
    {
        "Progman", "WorkerW", "Shell_TrayWnd", "Shell_SecondaryTrayWnd", "NotifyIconOverflowWindow",
        "Windows.UI.Core.CoreWindow", "Shell_InputSwitchTopLevelWindow", "XamlExplorerHostIslandWindow",
    };

    // Electron's own shell surfaces (launcher, Home, switcher, strips, taskbar). They are
    // never app windows; Electron's other windows (Files) are, so this is a list of
    // handles rather than the whole process.
    private static readonly HashSet<IntPtr> ShellWindows = new();
    private static readonly object ShellWindowsGate = new();

    public static void AddShellWindow(IntPtr hwnd)
    {
        lock (ShellWindowsGate) ShellWindows.Add(hwnd);
    }

    public static void RemoveShellWindow(IntPtr hwnd)
    {
        lock (ShellWindowsGate) ShellWindows.Remove(hwnd);
    }

    public static bool IsShellWindow(IntPtr hwnd)
    {
        lock (ShellWindowsGate) return ShellWindows.Contains(hwnd);
    }

    public static List<object> Enumerate(uint ownPid)
    {
        var windows = new List<object>();
        EnumWindows((hwnd, _) =>
        {
            if (IsSwitchable(hwnd, ownPid)) windows.Add(Describe(hwnd));
            return true;
        }, IntPtr.Zero);
        return windows;
    }

    /// <summary>Brings a window to the front and gives it focus, restoring it if minimised.</summary>
    public static void Activate(IntPtr hwnd)
    {
        if (!IsWindow(hwnd)) return;
        if (IsIconic(hwnd)) ShowWindow(hwnd, SW_RESTORE);

        // Windows refuses SetForegroundWindow to a background process unless its input is
        // briefly attached to the thread that currently has the foreground.
        uint foregroundThread = GetWindowThreadProcessId(GetForegroundWindow(), out _);
        uint ownThread = GetCurrentThreadId();
        bool attached = foregroundThread != ownThread && AttachThreadInput(ownThread, foregroundThread, true);
        try
        {
            SetForegroundWindow(hwnd);
            BringWindowToTop(hwnd);
        }
        finally
        {
            if (attached) AttachThreadInput(ownThread, foregroundThread, false);
        }

        // Fallback: what Alt+Tab itself uses, in case the attach was refused.
        if (GetForegroundWindow() != hwnd) SwitchToThisWindow(hwnd, true);
    }

    public static void Close(IntPtr hwnd)
    {
        if (IsWindow(hwnd)) PostMessage(hwnd, WM_CLOSE, IntPtr.Zero, IntPtr.Zero);
    }

    /// <summary>
    /// A window that is technically visible but drawn at zero opacity or passes clicks
    /// through, like a launcher parked out of sight. Nobody can see or use it.
    /// </summary>
    public static bool IsInvisibleOverlay(IntPtr hwnd)
    {
        int exStyle = GetWindowLong(hwnd, GWL_EXSTYLE);
        if ((exStyle & WS_EX_LAYERED) == 0) return false;
        if ((exStyle & WS_EX_TRANSPARENT) != 0) return true;
        return GetLayeredWindowAttributes(hwnd, out _, out byte alpha, out uint flags) && (flags & LWA_ALPHA) != 0 && alpha == 0;
    }

    public static bool IsSwitchable(IntPtr hwnd, uint ownPid)
    {
        if (!IsWindowVisible(hwnd) || GetWindowTextLength(hwnd) == 0) return false;
        if (IsInvisibleOverlay(hwnd)) return false;
        int exStyle = GetWindowLong(hwnd, GWL_EXSTYLE);
        if ((exStyle & WS_EX_TOOLWINDOW) != 0 || (exStyle & WS_EX_NOACTIVATE) != 0) return false;
        // Owned windows (dialogs, palettes) ride along with their owner unless they ask for a taskbar button.
        if (GetWindow(hwnd, GW_OWNER) != IntPtr.Zero && (exStyle & WS_EX_APPWINDOW) == 0) return false;
        if (IgnoredClasses.Contains(ClassName(hwnd))) return false;
        if (DwmGetWindowAttribute(hwnd, DWMWA_CLOAKED, out int cloaked, sizeof(int)) == 0 && cloaked != 0) return false;
        return !IsShellWindow(hwnd);
    }

    public static object Describe(IntPtr hwnd)
    {
        var title = new StringBuilder(512);
        GetWindowText(hwnd, title, title.Capacity);
        GetWindowThreadProcessId(hwnd, out uint pid);
        string exe = ProcessPath(pid);
        // Where it sits when not minimised or maximised: with its state, what lets a tag find
        // the same window again when the app reopens it (main.js, window-tags.js).
        var placement = new WINDOWPLACEMENT { length = Marshal.SizeOf<WINDOWPLACEMENT>() };
        GetWindowPlacement(hwnd, ref placement);
        var normal = placement.rcNormalPosition;
        return new
        {
            hwnd = hwnd.ToInt64().ToString(),
            title = title.ToString(),
            exe,
            aumid = AppUserModelId(hwnd) ?? PackageAppId(pid),
            minimized = IsIconic(hwnd),
            zoomed = IsZoomedWindow(hwnd),
            bounds = new { x = normal.Left, y = normal.Top, width = normal.Right - normal.Left, height = normal.Bottom - normal.Top },
            icon = ExeIcon(exe),
        };
    }

    public static string ProcessPath(uint pid)
    {
        IntPtr process = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, false, pid);
        if (process == IntPtr.Zero) return "";
        try
        {
            var path = new StringBuilder(1024);
            int size = path.Capacity;
            return QueryFullProcessImageName(process, 0, path, ref size) ? path.ToString() : "";
        }
        finally
        {
            CloseHandle(process);
        }
    }

    // Store apps (WhatsApp, for one) often leave the AppUserModelID off their window; the
    // process still knows it, which is what ties the window to its Start entry and icon.
    private static string? PackageAppId(uint pid)
    {
        IntPtr process = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, false, pid);
        if (process == IntPtr.Zero) return null;
        try
        {
            int length = 512;
            var id = new StringBuilder(length);
            return GetApplicationUserModelId(process, ref length, id) == 0 && id.Length > 0 ? id.ToString() : null;
        }
        finally
        {
            CloseHandle(process);
        }
    }

    // Extracted once per executable into the same cache the app indexer uses.
    private static string? ExeIcon(string exe)
    {
        if (exe.Length == 0 || Indexer.CacheDir is null) return null;
        string file = Path.Combine(Indexer.CacheDir, "exe-" + Indexer.Hash(exe.ToLowerInvariant()) + ".png");
        if (File.Exists(file)) return file;
        return IconSaver.Save(exe, file, 48) ? file : null;
    }

    private static string? AppUserModelId(IntPtr hwnd)
    {
        Guid iid = typeof(IPropertyStore).GUID;
        if (SHGetPropertyStoreForWindow(hwnd, ref iid, out IPropertyStore? store) != 0 || store is null) return null;
        try
        {
            var key = new PROPERTYKEY { fmtid = new Guid("9F4C2855-9F79-4B39-A8D0-E1D42DE1D5F3"), pid = 5 };
            if (store.GetValue(ref key, out PROPVARIANT value) != 0) return null;
            string? id = value.vt == VT_LPWSTR ? Marshal.PtrToStringUni(value.pointer) : null;
            PropVariantClear(ref value);
            return string.IsNullOrEmpty(id) ? null : id;
        }
        finally
        {
            Marshal.ReleaseComObject(store);
        }
    }

    private static string ClassName(IntPtr hwnd)
    {
        var sb = new StringBuilder(256);
        GetClassName(hwnd, sb, sb.Capacity);
        return sb.ToString();
    }

    #region interop

    private const int GWL_EXSTYLE = -20;
    private const int WS_EX_TOOLWINDOW = 0x00000080;
    private const int WS_EX_APPWINDOW = 0x00040000;
    private const int WS_EX_NOACTIVATE = 0x08000000;
    private const int WS_EX_LAYERED = 0x00080000;
    private const int WS_EX_TRANSPARENT = 0x00000020;
    private const uint LWA_ALPHA = 0x2;
    private const uint GW_OWNER = 4;
    private const int DWMWA_CLOAKED = 14;
    private const uint WM_CLOSE = 0x0010;
    private const int SW_RESTORE = 9;
    private const uint PROCESS_QUERY_LIMITED_INFORMATION = 0x1000;
    private const ushort VT_LPWSTR = 31;

    private delegate bool EnumWindowsProc(IntPtr hwnd, IntPtr lParam);

    [StructLayout(LayoutKind.Sequential)]
    private struct PROPERTYKEY
    {
        public Guid fmtid;
        public uint pid;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct PROPVARIANT
    {
        public ushort vt;
        public ushort reserved1;
        public ushort reserved2;
        public ushort reserved3;
        public IntPtr pointer;
        public IntPtr padding;
    }

    [ComImport, Guid("886D8EEB-8CF2-4446-8D02-CDBA1DBDCF99"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    private interface IPropertyStore
    {
        [PreserveSig] int GetCount(out uint count);
        [PreserveSig] int GetAt(uint index, out PROPERTYKEY key);
        [PreserveSig] int GetValue(ref PROPERTYKEY key, out PROPVARIANT value);
        [PreserveSig] int SetValue(ref PROPERTYKEY key, ref PROPVARIANT value);
        [PreserveSig] int Commit();
    }

    [DllImport("user32.dll")]
    private static extern bool EnumWindows(EnumWindowsProc lpEnumFunc, IntPtr lParam);

    [DllImport("user32.dll")]
    private static extern bool IsWindow(IntPtr hWnd);

    [DllImport("user32.dll")]
    private static extern bool IsWindowVisible(IntPtr hWnd);

    [DllImport("user32.dll")]
    private static extern bool IsIconic(IntPtr hWnd);

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    private static extern int GetWindowTextLength(IntPtr hWnd);

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    private static extern int GetWindowText(IntPtr hWnd, StringBuilder lpString, int nMaxCount);

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    private static extern int GetClassName(IntPtr hWnd, StringBuilder lpClassName, int nMaxCount);

    [DllImport("user32.dll")]
    private static extern int GetWindowLong(IntPtr hWnd, int nIndex);

    [DllImport("user32.dll")]
    private static extern IntPtr GetWindow(IntPtr hWnd, uint uCmd);

    [DllImport("user32.dll")]
    private static extern bool GetLayeredWindowAttributes(IntPtr hwnd, out uint key, out byte alpha, out uint flags);

    [DllImport("user32.dll")]
    private static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint lpdwProcessId);

    [DllImport("user32.dll")]
    private static extern void SwitchToThisWindow(IntPtr hWnd, bool fUnknown);

    [DllImport("user32.dll")]
    private static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);

    [DllImport("user32.dll")]
    private static extern IntPtr GetForegroundWindow();

    [DllImport("user32.dll")]
    private static extern bool SetForegroundWindow(IntPtr hWnd);

    [DllImport("user32.dll")]
    private static extern bool BringWindowToTop(IntPtr hWnd);

    [DllImport("user32.dll")]
    private static extern bool AttachThreadInput(uint idAttach, uint idAttachTo, bool fAttach);

    [DllImport("kernel32.dll")]
    private static extern uint GetCurrentThreadId();

    [DllImport("user32.dll")]
    private static extern bool PostMessage(IntPtr hWnd, uint msg, IntPtr wParam, IntPtr lParam);

    [DllImport("dwmapi.dll")]
    private static extern int DwmGetWindowAttribute(IntPtr hwnd, int dwAttribute, out int pvAttribute, int cbAttribute);

    [DllImport("kernel32.dll")]
    private static extern IntPtr OpenProcess(uint access, bool inherit, uint pid);

    [DllImport("kernel32.dll")]
    private static extern bool CloseHandle(IntPtr handle);

    [DllImport("kernel32.dll", CharSet = CharSet.Unicode)]
    private static extern bool QueryFullProcessImageName(IntPtr process, int flags, StringBuilder path, ref int size);

    [DllImport("kernel32.dll", CharSet = CharSet.Unicode)]
    private static extern int GetApplicationUserModelId(IntPtr process, ref int length, StringBuilder id);

    [DllImport("shell32.dll")]
    private static extern int SHGetPropertyStoreForWindow(IntPtr hwnd, ref Guid iid, out IPropertyStore? store);

    [DllImport("ole32.dll")]
    private static extern int PropVariantClear(ref PROPVARIANT pvar);

    #endregion

    [StructLayout(LayoutKind.Sequential)]
    private struct PlacementRect
    {
        public int Left, Top, Right, Bottom;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct WINDOWPLACEMENT
    {
        public int length;
        public int flags;
        public int showCmd;
        public int minX, minY;
        public int maxX, maxY;
        public PlacementRect rcNormalPosition;
    }

    [DllImport("user32.dll")]
    private static extern bool GetWindowPlacement(IntPtr hwnd, ref WINDOWPLACEMENT placement);

    [DllImport("user32.dll", EntryPoint = "IsZoomed")]
    private static extern bool IsZoomedWindow(IntPtr hwnd);
}
