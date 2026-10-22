using System;
using System.Runtime.InteropServices;
using System.Windows.Forms;

namespace WinKeyHelper;

/// <summary>
/// Registers a strip along the bottom of the primary screen as a Windows app bar, so the
/// work area ends above our taskbar and maximised windows stop there instead of under it.
/// The registration lives with this process: Windows drops it when the helper exits, and
/// <see cref="Release"/> drops it sooner.
/// </summary>
internal static class AppBar
{
    private static Holder? _holder;
    private static int _height;

    /// <summary>Reserves <paramref name="height"/> physical pixels at the bottom; 0 releases.</summary>
    public static void Reserve(int height)
    {
        if (height <= 0)
        {
            Release();
            return;
        }
        _height = height;
        if (_holder is null)
        {
            _holder = new Holder();
            var data = NewData();
            data.uCallbackMessage = Holder.CallbackMessage;
            AppBarMessage(ABM_NEW, ref data);
        }
        Position();
    }

    public static void Release()
    {
        if (_holder is null) return;
        var data = NewData();
        AppBarMessage(ABM_REMOVE, ref data);
        _holder.DestroyHandle();
        _holder = null;
    }

    // Asks Windows for the bottom strip, takes what it allows, and sets it.
    private static void Position()
    {
        if (_holder is null) return;
        var screen = Screen.PrimaryScreen!.Bounds;
        var data = NewData();
        data.uEdge = ABE_BOTTOM;
        data.rc = new RECT { Left = screen.Left, Right = screen.Right, Top = screen.Bottom - _height, Bottom = screen.Bottom };
        AppBarMessage(ABM_QUERYPOS, ref data);
        data.rc.Top = data.rc.Bottom - _height;
        AppBarMessage(ABM_SETPOS, ref data);
    }

    // Straight to Explorer, past our own tray window (TrayHost.StepAside).
    private static void AppBarMessage(uint message, ref APPBARDATA data)
    {
        var copy = data;
        TrayHost.StepAside(() => SHAppBarMessage(message, ref copy));
        data = copy;
    }

    private static APPBARDATA NewData() => new()
    {
        cbSize = Marshal.SizeOf<APPBARDATA>(),
        hWnd = _holder?.Handle ?? IntPtr.Zero,
    };

    // The hidden window Windows knows the app bar by; it is told when screens or other
    // app bars change and re-asserts the strip.
    private sealed class Holder : NativeWindow
    {
        public const uint CallbackMessage = 0x8000 + 0x51; // WM_APP + 0x51
        private const int WM_DISPLAYCHANGE = 0x007E;

        public Holder()
        {
            CreateHandle(new CreateParams { ExStyle = WS_EX_TOOLWINDOW });
        }

        protected override void WndProc(ref Message message)
        {
            if ((message.Msg == CallbackMessage && (uint)message.WParam == ABN_POSCHANGED) || message.Msg == WM_DISPLAYCHANGE)
                Position();
            base.WndProc(ref message);
        }
    }

    private const uint ABM_NEW = 0x0;
    private const uint ABM_REMOVE = 0x1;
    private const uint ABM_QUERYPOS = 0x2;
    private const uint ABM_SETPOS = 0x3;
    private const uint ABE_BOTTOM = 3;
    private const uint ABN_POSCHANGED = 0x1;
    private const int WS_EX_TOOLWINDOW = 0x80;

    [StructLayout(LayoutKind.Sequential)]
    private struct RECT
    {
        public int Left, Top, Right, Bottom;
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

    [DllImport("shell32.dll")]
    private static extern IntPtr SHAppBarMessage(uint message, ref APPBARDATA data);
}
