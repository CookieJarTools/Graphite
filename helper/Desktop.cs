using System.Runtime.InteropServices;
using System.Text.Json;

namespace WinKeyHelper;

/// <summary>
/// The desktop behind every window: the wallpaper on each monitor (IDesktopWallpaper) and the
/// desktop icons. Electron keeps what was there before and asks for it back; the helper only
/// reads and sets. All calls run on the UI thread (the wallpaper object is apartment-bound).
/// </summary>
internal static class Desktop
{
    // "wallpaper state": each monitor's wallpaper and rectangle, the fit, the colour behind,
    // whether a slideshow runs, and whether the desktop icons show.
    public static void ReportState()
    {
        var wallpaper = Create();
        try
        {
            wallpaper.GetMonitorDevicePathCount(out uint count);
            var monitors = new List<object>();
            for (uint index = 0; index < count; index++)
            {
                if (wallpaper.GetMonitorDevicePathAt(index, out var id) != 0) continue;
                if (wallpaper.GetMonitorRECT(id, out var rect) != 0) continue; // not attached
                wallpaper.GetWallpaper(id, out var path);
                monitors.Add(new { id, path = path ?? "", x = rect.Left, y = rect.Top, width = rect.Right - rect.Left, height = rect.Bottom - rect.Top });
            }
            wallpaper.GetPosition(out int position);
            wallpaper.GetBackgroundColor(out uint color);
            wallpaper.GetStatus(out int status);
            Program.Emit(new
            {
                @event = "wallpaper",
                monitors,
                position,
                color,
                slideshow = (status & DSS_SLIDESHOW) != 0,
                icons = IconsVisible(),
            });
        }
        finally
        {
            Marshal.ReleaseComObject(wallpaper);
        }
    }

    // "wallpaper set {json}": { monitors: [{ id, path }], position?, color? }. Restoring the
    // original goes through here too.
    public static void Set(string json)
    {
        WallpaperRequest? request;
        try
        {
            request = JsonSerializer.Deserialize<WallpaperRequest>(json, new JsonSerializerOptions { PropertyNameCaseInsensitive = true });
        }
        catch (JsonException)
        {
            return;
        }
        if (request?.Monitors is null) return;
        var wallpaper = Create();
        try
        {
            if (request.Color is uint color) wallpaper.SetBackgroundColor(color);
            if (request.Position is int position) wallpaper.SetPosition(position);
            foreach (var monitor in request.Monitors)
            {
                if (!string.IsNullOrEmpty(monitor.Id)) wallpaper.SetWallpaper(monitor.Id, monitor.Path ?? "");
            }
        }
        catch (COMException error)
        {
            Program.Emit(new { @event = "log", message = "wallpaper: " + error.Message });
        }
        finally
        {
            Marshal.ReleaseComObject(wallpaper);
        }
    }

    // "desktopicons 0|1": Explorer's own "Show desktop icons" (it persists, like the View menu's).
    public static void ShowIcons(bool show)
    {
        if (IconsVisible() == show) return;
        IntPtr view = DesktopView();
        if (view != IntPtr.Zero) SendMessage(view, WM_COMMAND, (IntPtr)ToggleDesktopIcons, IntPtr.Zero);
    }

    private static bool IconsVisible()
    {
        IntPtr view = DesktopView();
        IntPtr list = view == IntPtr.Zero ? IntPtr.Zero : FindWindowEx(view, IntPtr.Zero, "SysListView32", null);
        return list != IntPtr.Zero && IsWindowVisible(list);
    }

    // The desktop's folder view lives under Progman, or under a WorkerW once a wallpaper
    // animation has run.
    private static IntPtr DesktopView()
    {
        IntPtr view = FindWindowEx(FindWindow("Progman", null), IntPtr.Zero, "SHELLDLL_DefView", null);
        IntPtr worker = IntPtr.Zero;
        while (view == IntPtr.Zero && (worker = FindWindowEx(IntPtr.Zero, worker, "WorkerW", null)) != IntPtr.Zero)
        {
            view = FindWindowEx(worker, IntPtr.Zero, "SHELLDLL_DefView", null);
        }
        return view;
    }

    private static IDesktopWallpaper Create() => (IDesktopWallpaper)new DesktopWallpaperClass();

    private sealed class WallpaperRequest
    {
        public MonitorWallpaper[]? Monitors { get; set; }
        public int? Position { get; set; }
        public uint? Color { get; set; }
    }

    private sealed class MonitorWallpaper
    {
        public string? Id { get; set; }
        public string? Path { get; set; }
    }

    // ---------- interop ----------

    private const int DSS_SLIDESHOW = 0x2;
    private const int WM_COMMAND = 0x111;
    private const int ToggleDesktopIcons = 0x7402;

    [StructLayout(LayoutKind.Sequential)]
    private struct RECT
    {
        public int Left, Top, Right, Bottom;
    }

    [ComImport, Guid("C2CF3110-460E-4fc1-B9D0-8A1C0C9CC4BD")]
    private class DesktopWallpaperClass
    {
    }

    [ComImport, Guid("B92B56A9-8B55-4E14-9A89-0199BBB6F93B"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    private interface IDesktopWallpaper
    {
        [PreserveSig] int SetWallpaper([MarshalAs(UnmanagedType.LPWStr)] string monitorId, [MarshalAs(UnmanagedType.LPWStr)] string wallpaper);
        [PreserveSig] int GetWallpaper([MarshalAs(UnmanagedType.LPWStr)] string monitorId, [MarshalAs(UnmanagedType.LPWStr)] out string wallpaper);
        [PreserveSig] int GetMonitorDevicePathAt(uint index, [MarshalAs(UnmanagedType.LPWStr)] out string monitorId);
        [PreserveSig] int GetMonitorDevicePathCount(out uint count);
        [PreserveSig] int GetMonitorRECT([MarshalAs(UnmanagedType.LPWStr)] string monitorId, out RECT rect);
        [PreserveSig] int SetBackgroundColor(uint color);
        [PreserveSig] int GetBackgroundColor(out uint color);
        [PreserveSig] int SetPosition(int position);
        [PreserveSig] int GetPosition(out int position);
        [PreserveSig] int SetSlideshow(IntPtr items);
        [PreserveSig] int GetSlideshow(out IntPtr items);
        [PreserveSig] int SetSlideshowOptions(int options, uint slideshowTick);
        [PreserveSig] int GetSlideshowOptions(out int options, out uint slideshowTick);
        [PreserveSig] int AdvanceSlideshow([MarshalAs(UnmanagedType.LPWStr)] string monitorId, int direction);
        [PreserveSig] int GetStatus(out int state);
        [PreserveSig] int Enable([MarshalAs(UnmanagedType.Bool)] bool enable);
    }

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    private static extern IntPtr FindWindow(string className, string? windowName);

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    private static extern IntPtr FindWindowEx(IntPtr parent, IntPtr after, string className, string? windowName);

    [DllImport("user32.dll")]
    private static extern bool IsWindowVisible(IntPtr hwnd);

    [DllImport("user32.dll")]
    private static extern IntPtr SendMessage(IntPtr hwnd, int message, IntPtr wParam, IntPtr lParam);
}
