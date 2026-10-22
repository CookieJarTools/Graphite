using System.Drawing;
using System.Runtime.InteropServices;
using System.Text.Json;
using System.Windows.Forms;

namespace WinKeyHelper;

/// <summary>
/// Live window previews for the switcher. DWM only paints thumbnails into windows the
/// calling process owns, so the helper keeps its own invisible, click-through overlay
/// laid exactly over Electron's switcher window and has DWM draw each source window
/// into it at the rectangles the renderer laid out. Previews are real-time and cost
/// nothing in Chromium; clicks fall through the overlay to the cards underneath.
/// Everything here runs on the UI thread (Program posts the calls there).
/// </summary>
internal static class Thumbnails
{
    private static readonly List<IntPtr> Registered = new();
    private static Overlay? _overlay;

    private sealed record Slot(string hwnd, int x, int y, int w, int h);

    /// <summary>
    /// Covers <paramref name="bounds"/> (physical pixels, the switcher window's screen
    /// rectangle) and replaces every preview with the given slots, which are relative to it.
    /// </summary>
    public static void Show(Rectangle bounds, string slotsJson)
    {
        var slots = JsonSerializer.Deserialize<Slot[]>(slotsJson) ?? Array.Empty<Slot>();
        _overlay ??= new Overlay();
        ClearRegistrations();

        _overlay.Bounds = bounds;
        if (!_overlay.Visible) _overlay.Show();
        SetWindowPos(_overlay.Handle, HWND_TOPMOST, 0, 0, 0, 0, SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE);

        foreach (var slot in slots)
        {
            if (!long.TryParse(slot.hwnd, out long source)) continue;
            int result = DwmRegisterThumbnail(_overlay.Handle, (IntPtr)source, out IntPtr thumbnail);
            if (result != 0)
            {
                Program.Emit(new { @event = "error", message = $"thumbnail for {source}: 0x{result:X8}" });
                continue;
            }
            Registered.Add(thumbnail);
            Place(thumbnail, slot);
        }
    }

    public static void Clear()
    {
        ClearRegistrations();
        _overlay?.Hide();
    }

    // ---------- merge animation (WindowMerge) ----------

    private const int MergeMilliseconds = 280; // duration-merge
    private const int FrameMilliseconds = 15;
    private static System.Windows.Forms.Timer? _mergeTimer;

    /// <summary>
    /// Shrinks a live picture of <paramref name="source"/> from <paramref name="from"/> into
    /// <paramref name="to"/> (screen pixels) while fading it out, then calls <paramref name="done"/>.
    /// The caller moves the real window out of sight first; DWM keeps drawing it there.
    /// </summary>
    public static void AnimateMerge(IntPtr source, Rectangle from, Rectangle to, Action done)
    {
        _mergeTimer?.Stop();
        _overlay ??= new Overlay();
        ClearRegistrations();

        var screen = SystemInformation.VirtualScreen;
        _overlay.Bounds = screen;
        if (!_overlay.Visible) _overlay.Show();
        SetWindowPos(_overlay.Handle, HWND_TOPMOST, 0, 0, 0, 0, SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE);

        if (DwmRegisterThumbnail(_overlay.Handle, source, out IntPtr thumbnail) != 0)
        {
            Clear();
            done();
            return;
        }
        Registered.Add(thumbnail);

        long start = Environment.TickCount64;
        _mergeTimer = new System.Windows.Forms.Timer { Interval = FrameMilliseconds };
        _mergeTimer.Tick += (_, _) =>
        {
            double progress = Math.Min(1, (Environment.TickCount64 - start) / (double)MergeMilliseconds);
            double eased = EaseEnter(progress);
            int Lerp(int a, int b) => (int)Math.Round(a + (b - a) * eased);
            var properties = new DWM_THUMBNAIL_PROPERTIES
            {
                dwFlags = DWM_TNP_RECTDESTINATION | DWM_TNP_VISIBLE | DWM_TNP_OPACITY | DWM_TNP_SOURCECLIENTAREAONLY,
                rcDestination = new RECT
                {
                    Left = Lerp(from.Left, to.Left) - screen.Left,
                    Top = Lerp(from.Top, to.Top) - screen.Top,
                    Right = Lerp(from.Right, to.Right) - screen.Left,
                    Bottom = Lerp(from.Bottom, to.Bottom) - screen.Top,
                },
                opacity = (byte)Math.Round(230 * (1 - eased)), // starts at the dragged window's 90%
                fVisible = true,
                fSourceClientAreaOnly = false,
            };
            DwmUpdateThumbnailProperties(thumbnail, ref properties);
            if (progress < 1) return;
            _mergeTimer!.Stop();
            Clear();
            done();
        };
        _mergeTimer.Start();
    }

    // ease-enter, cubic-bezier(0.16, 1, 0.3, 1): fast start, long soft settle.
    private static double EaseEnter(double x)
    {
        const double x1 = 0.16, y1 = 1, x2 = 0.3, y2 = 1;
        double Bezier(double t, double p1, double p2) => 3 * (1 - t) * (1 - t) * t * p1 + 3 * (1 - t) * t * t * p2 + t * t * t;
        double t = x;
        for (int iteration = 0; iteration < 8; iteration++)
        {
            double error = Bezier(t, x1, x2) - x;
            double slope = 3 * (1 - t) * (1 - t) * x1 + 6 * (1 - t) * t * (x2 - x1) + 3 * t * t * (1 - x2);
            if (Math.Abs(slope) < 1e-6) break;
            t = Math.Clamp(t - error / slope, 0, 1);
        }
        return Bezier(t, y1, y2);
    }

    public static bool AnimationsEnabled()
    {
        int enabled = 1;
        SystemParametersInfo(SPI_GETCLIENTAREAANIMATION, 0, ref enabled, 0);
        return enabled != 0;
    }

    private static void ClearRegistrations()
    {
        foreach (var thumbnail in Registered) DwmUnregisterThumbnail(thumbnail);
        Registered.Clear();
    }

    // Letterboxes the source into the slot so the preview keeps the window's shape.
    private static void Place(IntPtr thumbnail, Slot slot)
    {
        DwmQueryThumbnailSourceSize(thumbnail, out SIZE source);
        double scale = source.cx > 0 && source.cy > 0 ? Math.Min((double)slot.w / source.cx, (double)slot.h / source.cy) : 1;
        int width = (int)Math.Round(source.cx * scale);
        int height = (int)Math.Round(source.cy * scale);
        int left = slot.x + (slot.w - width) / 2;
        int top = slot.y + (slot.h - height) / 2;

        var properties = new DWM_THUMBNAIL_PROPERTIES
        {
            dwFlags = DWM_TNP_RECTDESTINATION | DWM_TNP_VISIBLE | DWM_TNP_OPACITY | DWM_TNP_SOURCECLIENTAREAONLY,
            rcDestination = new RECT { Left = left, Top = top, Right = left + width, Bottom = top + height },
            opacity = 255,
            fVisible = true,
            fSourceClientAreaOnly = false,
        };
        DwmUpdateThumbnailProperties(thumbnail, ref properties);
    }

    /// <summary>A borderless, fully transparent, click-through, never-activated host for the previews.</summary>
    private sealed class Overlay : Form
    {
        public Overlay()
        {
            FormBorderStyle = FormBorderStyle.None;
            ShowInTaskbar = false;
            StartPosition = FormStartPosition.Manual;
            TopMost = true;
            BackColor = Color.Magenta;
            TransparencyKey = Color.Magenta;
        }

        protected override bool ShowWithoutActivation => true;

        protected override CreateParams CreateParams
        {
            get
            {
                var parameters = base.CreateParams;
                parameters.ExStyle |= WS_EX_LAYERED | WS_EX_TRANSPARENT | WS_EX_NOACTIVATE | WS_EX_TOOLWINDOW | WS_EX_TOPMOST;
                return parameters;
            }
        }
    }

    #region interop

    private const uint DWM_TNP_RECTDESTINATION = 0x00000001;
    private const uint DWM_TNP_OPACITY = 0x00000004;
    private const uint DWM_TNP_VISIBLE = 0x00000008;
    private const uint DWM_TNP_SOURCECLIENTAREAONLY = 0x00000010;
    private const int WS_EX_TOPMOST = 0x00000008;
    private const int WS_EX_TRANSPARENT = 0x00000020;
    private const int WS_EX_TOOLWINDOW = 0x00000080;
    private const int WS_EX_LAYERED = 0x00080000;
    private const int WS_EX_NOACTIVATE = 0x08000000;
    private static readonly IntPtr HWND_TOPMOST = new(-1);
    private const uint SWP_NOSIZE = 0x0001;
    private const uint SWP_NOMOVE = 0x0002;
    private const uint SWP_NOACTIVATE = 0x0010;
    private const uint SPI_GETCLIENTAREAANIMATION = 0x1042;

    [StructLayout(LayoutKind.Sequential)]
    private struct RECT
    {
        public int Left, Top, Right, Bottom;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct SIZE
    {
        public int cx, cy;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct DWM_THUMBNAIL_PROPERTIES
    {
        public uint dwFlags;
        public RECT rcDestination;
        public RECT rcSource;
        public byte opacity;
        [MarshalAs(UnmanagedType.Bool)] public bool fVisible;
        [MarshalAs(UnmanagedType.Bool)] public bool fSourceClientAreaOnly;
    }

    [DllImport("dwmapi.dll")]
    private static extern int DwmRegisterThumbnail(IntPtr dest, IntPtr src, out IntPtr thumbnail);

    [DllImport("dwmapi.dll")]
    private static extern int DwmUnregisterThumbnail(IntPtr thumbnail);

    [DllImport("dwmapi.dll")]
    private static extern int DwmUpdateThumbnailProperties(IntPtr thumbnail, ref DWM_THUMBNAIL_PROPERTIES properties);

    [DllImport("dwmapi.dll")]
    private static extern int DwmQueryThumbnailSourceSize(IntPtr thumbnail, out SIZE size);

    [DllImport("user32.dll")]
    private static extern bool SetWindowPos(IntPtr hWnd, IntPtr hWndInsertAfter, int x, int y, int cx, int cy, uint flags);

    [DllImport("user32.dll")]
    private static extern bool SystemParametersInfo(uint action, uint param, ref int value, uint winIni);

    #endregion
}
