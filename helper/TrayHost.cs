using System.Drawing;
using System.Drawing.Imaging;
using System.IO;
using System.Runtime.InteropServices;
using System.Text.Json;

namespace WinKeyHelper;

/// <summary>
/// Hosts the notification-area icons ("tray icons") for our own hidden-icons flyout.
///
/// Apps add and change their icons with Shell_NotifyIcon, which sends a WM_COPYDATA to the
/// first window of class Shell_TrayWnd. The helper keeps its own (hidden) window of that class
/// above Explorer's, so every icon reaches it first, and forwards every message on to
/// Explorer, which so keeps a complete copy: if the helper goes, nothing is lost. App-bar
/// messages (SHAppBarMessage, our reserved strip among them) travel the same way and are
/// forwarded with Explorer's answer returned. Starting and stopping, it announces
/// "TaskbarCreated", the signal apps answer by adding their icons again.
///
/// Clicks on our flyout are passed to an app exactly as Explorer would send them.
/// Everything here runs on the UI thread.
/// </summary>
internal static class TrayHost
{
    private const string TrayClass = "Shell_TrayWnd";
    private const string NotifyClass = "TrayNotifyWnd";
    private const int RaiseCheckMilliseconds = 500;
    private const int ReportDelayMilliseconds = 80;
    private const uint ForwardTimeoutMilliseconds = 2000;

    private static readonly Dictionary<string, TrayIcon> Icons = new();
    private static WndProc? _proc; // kept referenced for the GC
    private static IntPtr _tray;
    private static IntPtr _notify;
    private static System.Windows.Forms.Timer? _raise;
    private static System.Windows.Forms.Timer? _report;
    private static RECT _anchor; // where "the icon" is, for apps that ask (Shell_NotifyIconGetRect)

    /// <summary>Explorer's own taskbar window, never ours.</summary>
    public static IntPtr NativeTray()
    {
        IntPtr window = IntPtr.Zero;
        while ((window = FindWindowEx(IntPtr.Zero, window, TrayClass, null)) != IntPtr.Zero)
        {
            if (window != _tray) return window;
        }
        return IntPtr.Zero;
    }

    /// <summary>
    /// Runs <paramref name=action/> with Explorer's taskbar window first in line again. Explorer
    /// takes app-bar requests relayed through ours but does not apply a reservation made that
    /// way, so the helper's own (AppBar.cs) go to it directly.
    /// </summary>
    public static void StepAside(Action action)
    {
        if (_tray == IntPtr.Zero)
        {
            action();
            return;
        }
        SetWindowPos(_tray, HWND_BOTTOM, 0, 0, 0, 0, SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE);
        try
        {
            action();
        }
        finally
        {
            RaiseAboveExplorer();
        }
    }

    public static void Start()
    {
        if (_tray != IntPtr.Zero) return;
        _proc = WindowProc;
        IntPtr instance = GetModuleHandle(null);
        Register(TrayClass, instance);
        Register(NotifyClass, instance);
        _tray = CreateWindowEx(WS_EX_TOPMOST | WS_EX_TOOLWINDOW, TrayClass, "", WS_POPUP, 0, 0, 0, 0, IntPtr.Zero, IntPtr.Zero, instance, IntPtr.Zero);
        _notify = CreateWindowEx(0, NotifyClass, "", WS_CHILD, 0, 0, 0, 0, _tray, IntPtr.Zero, instance, IntPtr.Zero);
        RaiseAboveExplorer();

        // Explorer raises its own window now and then (a restart, say); ours goes back on top.
        _raise = new System.Windows.Forms.Timer { Interval = RaiseCheckMilliseconds };
        _raise.Tick += (_, _) =>
        {
            if (FindWindow(TrayClass, null) != _tray) RaiseAboveExplorer();
            var gone = Icons.Values.Where((icon) => !IsWindow(icon.Window)).Select((icon) => icon.Key).ToList();
            gone.ForEach((key) => Icons.Remove(key)); // apps that quit without removing their icon
            if (gone.Count > 0) ScheduleReport();
        };
        _raise.Start();
        _report = new System.Windows.Forms.Timer { Interval = ReportDelayMilliseconds };
        _report.Tick += (_, _) =>
        {
            _report.Stop();
            Report();
        };
        AnnounceTaskbarCreated();
    }

    public static void Stop()
    {
        if (_tray == IntPtr.Zero) return;
        _raise?.Stop();
        _report?.Stop();
        DestroyWindow(_tray); // its child goes with it
        _tray = _notify = IntPtr.Zero;
        Icons.Clear();
        Report();
        AnnounceTaskbarCreated(); // apps re-add their icons to Explorer, which already has them
    }

    // "trayclick {json}": { id, button: left|right|double, x, y } with x, y the icon's centre
    // in physical screen pixels.
    public static void Click(string json)
    {
        ClickRequest? request;
        try
        {
            request = JsonSerializer.Deserialize<ClickRequest>(json, new JsonSerializerOptions { PropertyNameCaseInsensitive = true });
        }
        catch (JsonException)
        {
            return;
        }
        if (request?.Id is null || !Icons.TryGetValue(request.Id, out var icon) || !IsWindow(icon.Window)) return;
        _anchor = new RECT { Left = request.X - 12, Top = request.Y - 12, Right = request.X + 12, Bottom = request.Y + 12 };

        // The app opens a menu or window next: it is allowed to come to the front.
        GetWindowThreadProcessId(icon.Window, out uint processId);
        Program.AllowForeground(processId);

        var messages = request.Button switch
        {
            "right" => new[] { WM_RBUTTONDOWN, WM_RBUTTONUP, icon.Version >= 3 ? WM_CONTEXTMENU : 0 },
            "double" => new[] { WM_LBUTTONDBLCLK, WM_LBUTTONUP },
            _ => new[] { WM_LBUTTONDOWN, WM_LBUTTONUP, icon.Version >= 3 ? NIN_SELECT : 0 },
        };
        foreach (uint message in messages.Where((message) => message != 0)) Notify(icon, message, request.X, request.Y);
    }

    // Version 4 icons get the anchor point and the message in the low word; older ones the id.
    private static void Notify(TrayIcon icon, uint message, int x, int y)
    {
        IntPtr wParam, lParam;
        if (icon.Version >= 4)
        {
            wParam = (IntPtr)((x & 0xFFFF) | ((y & 0xFFFF) << 16));
            lParam = (IntPtr)((message & 0xFFFF) | ((icon.Id & 0xFFFF) << 16));
        }
        else
        {
            wParam = (IntPtr)icon.Id;
            lParam = (IntPtr)message;
        }
        SendNotifyMessage(icon.Window, icon.CallbackMessage, wParam, lParam);
    }

    // ---------- the window ----------

    private static void Register(string className, IntPtr instance)
    {
        var windowClass = new WNDCLASSEX
        {
            cbSize = Marshal.SizeOf<WNDCLASSEX>(),
            lpfnWndProc = Marshal.GetFunctionPointerForDelegate(_proc!),
            hInstance = instance,
            lpszClassName = className,
        };
        RegisterClassEx(ref windowClass);
    }

    private static void RaiseAboveExplorer()
    {
        SetWindowPos(_tray, HWND_TOPMOST, 0, 0, 0, 0, SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE);
    }

    private static void AnnounceTaskbarCreated()
    {
        uint taskbarCreated = RegisterWindowMessage("TaskbarCreated");
        if (taskbarCreated != 0) SendNotifyMessage(HWND_BROADCAST, taskbarCreated, IntPtr.Zero, IntPtr.Zero);
    }

    private static IntPtr WindowProc(IntPtr hwnd, uint message, IntPtr wParam, IntPtr lParam)
    {
        if (hwnd == _tray && message == WM_COPYDATA)
        {
            var copy = Marshal.PtrToStructure<COPYDATASTRUCT>(lParam);
            if (copy.dwData == (IntPtr)1 && copy.cbData >= 8 + 24)
            {
                bool handled = OnNotifyIcon(copy.lpData, copy.cbData);
                Forward(message, wParam, lParam);
                return handled ? (IntPtr)1 : IntPtr.Zero;
            }
            if (copy.dwData == (IntPtr)3 && copy.cbData >= 8) return IconRect(copy.lpData);
            return Forward(message, wParam, lParam);
        }
        if (hwnd == _tray && message == WM_WINDOWPOSCHANGING)
        {
            // Never shown: something asking every Shell_TrayWnd to show must not reveal ours.
            var position = Marshal.PtrToStructure<WINDOWPOS>(lParam);
            if ((position.flags & SWP_SHOWWINDOW) != 0)
            {
                position.flags = (position.flags & ~SWP_SHOWWINDOW) | SWP_HIDEWINDOW;
                Marshal.StructureToPtr(position, lParam, false);
            }
        }
        if (hwnd == _tray && (message >= WM_USER || message == WM_COMMAND || message == WM_ACTIVATEAPP))
        {
            return Forward(message, wParam, lParam);
        }
        return DefWindowProc(hwnd, message, wParam, lParam);
    }

    // Explorer answers (app bars, timer messages, anything addressed to "the taskbar").
    private static IntPtr Forward(uint message, IntPtr wParam, IntPtr lParam)
    {
        IntPtr explorer = NativeTray();
        if (explorer == IntPtr.Zero) return IntPtr.Zero;
        SendMessageTimeout(explorer, message, wParam, lParam, SMTO_ABORTIFHUNG, ForwardTimeoutMilliseconds, out var result);
        return result;
    }

    // Shell_NotifyIconGetRect: where the icon is. Answered with the last clicked icon, or the
    // pointer, so apps place their windows next to our flyout rather than Explorer's
    // hidden taskbar.
    private static IntPtr IconRect(IntPtr data)
    {
        int request = Marshal.ReadInt32(data, 4);
        var rect = _anchor;
        if (rect.Right == 0)
        {
            GetCursorPos(out var cursor);
            rect = new RECT { Left = cursor.X - 12, Top = cursor.Y - 12, Right = cursor.X + 12, Bottom = cursor.Y + 12 };
        }
        return request == 1
            ? (IntPtr)((rect.Left & 0xFFFF) | ((rect.Top & 0xFFFF) << 16))
            : (IntPtr)(((rect.Right - rect.Left) & 0xFFFF) | (((rect.Bottom - rect.Top) & 0xFFFF) << 16));
    }

    // ---------- the icons ----------

    // SHELLTRAYDATA: a magic number, the NIM_ message, then NOTIFYICONDATA with 32-bit handles.
    private static bool OnNotifyIcon(IntPtr data, int length)
    {
        uint command = (uint)Marshal.ReadInt32(data, 4);
        IntPtr nid = data + 8;
        int size = Math.Min(Marshal.ReadInt32(nid, 0), length - 8);
        var window = (IntPtr)(uint)Marshal.ReadInt32(nid, 4);
        uint id = (uint)Marshal.ReadInt32(nid, 8);
        uint flags = (uint)Marshal.ReadInt32(nid, 12);
        Guid? guid = (flags & NIF_GUID) != 0 && size >= 952 ? new Guid(ReadBytes(nid + 936, 16)) : null;
        string key = guid is Guid value && value != Guid.Empty ? value.ToString() : $"{(long)window}:{id}";
        Icons.TryGetValue(key, out var icon);

        switch (command)
        {
            case NIM_ADD:
                icon ??= Icons[key] = new TrayIcon { Key = key, Window = window, Id = id };
                Apply(icon, nid, flags, size);
                break;
            case NIM_MODIFY:
                if (icon is null) return false;
                icon.Window = window;
                Apply(icon, nid, flags, size);
                break;
            case NIM_DELETE:
                if (icon is null) return false;
                Icons.Remove(key);
                break;
            case NIM_SETVERSION:
                if (icon is null) return false;
                icon.Version = size >= 804 ? (uint)Marshal.ReadInt32(nid, 800) : 0;
                return true;
            case NIM_SETFOCUS:
                return true;
            default:
                return false;
        }
        ScheduleReport();
        return true;
    }

    private static void Apply(TrayIcon icon, IntPtr nid, uint flags, int size)
    {
        if ((flags & NIF_MESSAGE) != 0) icon.CallbackMessage = (uint)Marshal.ReadInt32(nid, 16);
        if ((flags & NIF_ICON) != 0) icon.Image = ToDataUrl((IntPtr)(uint)Marshal.ReadInt32(nid, 20));
        if ((flags & NIF_TIP) != 0) icon.Tip = (Marshal.PtrToStringUni(nid + 24, 128) ?? "").Split('\0')[0].Trim();
        if ((flags & NIF_STATE) != 0 && size >= 288)
        {
            uint state = (uint)Marshal.ReadInt32(nid, 280);
            uint mask = (uint)Marshal.ReadInt32(nid, 284);
            if ((mask & NIS_HIDDEN) != 0) icon.Hidden = (state & NIS_HIDDEN) != 0;
        }
    }

    private static byte[] ReadBytes(IntPtr from, int count)
    {
        var bytes = new byte[count];
        Marshal.Copy(from, bytes, 0, count);
        return bytes;
    }

    private static string? ToDataUrl(IntPtr handle)
    {
        if (handle == IntPtr.Zero) return null;
        try
        {
            using var icon = Icon.FromHandle(handle);
            using var bitmap = icon.ToBitmap();
            using var stream = new MemoryStream();
            bitmap.Save(stream, ImageFormat.Png);
            return "data:image/png;base64," + Convert.ToBase64String(stream.ToArray());
        }
        catch
        {
            return null; // the app already destroyed it
        }
    }

    private static void ScheduleReport()
    {
        _report?.Stop();
        _report?.Start();
    }

    private static void Report()
    {
        var icons = Icons.Values
            .Where((icon) => !icon.Hidden && icon.Image is not null && IsWindow(icon.Window))
            .Select((icon) => new { id = icon.Key, title = icon.Tip, app = AppName(icon), icon = icon.Image })
            .ToList();
        Program.Emit(new { @event = "trayicons", icons });
    }

    // The app's own name (its file description), for icons without tooltip text.
    private static string AppName(TrayIcon icon)
    {
        if (icon.App is not null) return icon.App;
        try
        {
            GetWindowThreadProcessId(icon.Window, out uint processId);
            using var process = System.Diagnostics.Process.GetProcessById((int)processId);
            var file = process.MainModule?.FileVersionInfo;
            icon.App = !string.IsNullOrWhiteSpace(file?.FileDescription) ? file!.FileDescription!.Trim() : process.ProcessName;
        }
        catch
        {
            icon.App = ""; // gone, or not ours to inspect
        }
        return icon.App;
    }

    private sealed class TrayIcon
    {
        public string? App { get; set; }
        public string Key { get; init; } = "";
        public IntPtr Window { get; set; }
        public uint Id { get; init; }
        public uint CallbackMessage { get; set; }
        public uint Version { get; set; }
        public string? Image { get; set; }
        public string Tip { get; set; } = "";
        public bool Hidden { get; set; }
    }

    private sealed class ClickRequest
    {
        public string? Id { get; set; }
        public string Button { get; set; } = "left";
        public int X { get; set; }
        public int Y { get; set; }
    }

    // ---------- interop ----------

    private const uint NIM_ADD = 0;
    private const uint NIM_MODIFY = 1;
    private const uint NIM_DELETE = 2;
    private const uint NIM_SETFOCUS = 3;
    private const uint NIM_SETVERSION = 4;
    private const uint NIF_MESSAGE = 0x1;
    private const uint NIF_ICON = 0x2;
    private const uint NIF_TIP = 0x4;
    private const uint NIF_STATE = 0x8;
    private const uint NIF_GUID = 0x20;
    private const uint NIS_HIDDEN = 0x1;
    private const uint WM_COPYDATA = 0x4A;
    private const uint WM_COMMAND = 0x111;
    private const uint WM_ACTIVATEAPP = 0x1C;
    private const uint WM_WINDOWPOSCHANGING = 0x46;
    private const uint WM_USER = 0x400;
    private const uint WM_CONTEXTMENU = 0x7B;
    private const uint WM_LBUTTONDOWN = 0x201;
    private const uint WM_LBUTTONUP = 0x202;
    private const uint WM_LBUTTONDBLCLK = 0x203;
    private const uint WM_RBUTTONDOWN = 0x204;
    private const uint WM_RBUTTONUP = 0x205;
    private const uint NIN_SELECT = 0x400;
    private const int WS_POPUP = unchecked((int)0x80000000);
    private const int WS_CHILD = 0x40000000;
    private const int WS_EX_TOPMOST = 0x8;
    private const int WS_EX_TOOLWINDOW = 0x80;
    private const uint SWP_NOSIZE = 0x1;
    private const uint SWP_NOMOVE = 0x2;
    private const uint SWP_NOACTIVATE = 0x10;
    private const uint SWP_SHOWWINDOW = 0x40;
    private const uint SWP_HIDEWINDOW = 0x80;
    private const uint SMTO_ABORTIFHUNG = 0x2;
    private static readonly IntPtr HWND_TOPMOST = new(-1);
    private static readonly IntPtr HWND_BOTTOM = new(1);
    private static readonly IntPtr HWND_BROADCAST = new(0xFFFF);

    private delegate IntPtr WndProc(IntPtr hwnd, uint message, IntPtr wParam, IntPtr lParam);

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
    private struct COPYDATASTRUCT
    {
        public IntPtr dwData;
        public int cbData;
        public IntPtr lpData;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct WINDOWPOS
    {
        public IntPtr hwnd;
        public IntPtr hwndInsertAfter;
        public int x, y, cx, cy;
        public uint flags;
    }

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    private struct WNDCLASSEX
    {
        public int cbSize;
        public uint style;
        public IntPtr lpfnWndProc;
        public int cbClsExtra;
        public int cbWndExtra;
        public IntPtr hInstance;
        public IntPtr hIcon;
        public IntPtr hCursor;
        public IntPtr hbrBackground;
        public string? lpszMenuName;
        public string lpszClassName;
        public IntPtr hIconSm;
    }

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    private static extern ushort RegisterClassEx(ref WNDCLASSEX windowClass);

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    private static extern IntPtr CreateWindowEx(int exStyle, string className, string windowName, int style, int x, int y, int width, int height, IntPtr parent, IntPtr menu, IntPtr instance, IntPtr param);

    [DllImport("user32.dll")]
    private static extern bool DestroyWindow(IntPtr hwnd);

    [DllImport("user32.dll")]
    private static extern IntPtr DefWindowProc(IntPtr hwnd, uint message, IntPtr wParam, IntPtr lParam);

    [DllImport("kernel32.dll", CharSet = CharSet.Unicode)]
    private static extern IntPtr GetModuleHandle(string? name);

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    private static extern IntPtr FindWindow(string className, string? windowName);

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    private static extern IntPtr FindWindowEx(IntPtr parent, IntPtr after, string className, string? windowName);

    [DllImport("user32.dll")]
    private static extern bool SetWindowPos(IntPtr hwnd, IntPtr insertAfter, int x, int y, int width, int height, uint flags);

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    private static extern uint RegisterWindowMessage(string name);

    [DllImport("user32.dll")]
    private static extern bool SendNotifyMessage(IntPtr hwnd, uint message, IntPtr wParam, IntPtr lParam);

    [DllImport("user32.dll")]
    private static extern IntPtr SendMessageTimeout(IntPtr hwnd, uint message, IntPtr wParam, IntPtr lParam, uint flags, uint timeout, out IntPtr result);

    [DllImport("user32.dll")]
    private static extern bool IsWindow(IntPtr hwnd);

    [DllImport("user32.dll")]
    private static extern uint GetWindowThreadProcessId(IntPtr hwnd, out uint processId);

    [DllImport("user32.dll")]
    private static extern bool GetCursorPos(out POINT point);
}
