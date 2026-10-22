using System.Drawing;
using System.Drawing.Imaging;
using System.IO;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Text;

namespace WinKeyHelper;

/// <summary>
/// Enumerates shell:AppsFolder — the same virtual folder the Windows Start menu's
/// "All apps" list is built from (covers classic and Store apps; every entry can be
/// launched via "shell:AppsFolder\{id}"). Emits the app list immediately, then
/// extracts missing icons to a PNG cache and emits per-icon updates as they land.
/// </summary>
internal static class Indexer
{
    /// <summary>Where icon PNGs live; the window list caches executable icons here too.</summary>
    public static string? CacheDir { get; private set; }

    public static void Run(string cacheDir)
    {
        CacheDir = cacheDir;
        // Shell COM wants an STA thread.
        var t = new Thread(() => Index(cacheDir)) { IsBackground = true };
        t.SetApartmentState(ApartmentState.STA);
        t.Start();
    }

    private sealed record Entry(string Name, string Id, string IconFile, bool HasIcon);

    private static void Index(string cacheDir)
    {
        var apps = new List<Entry>();
        try
        {
            Directory.CreateDirectory(cacheDir);
            var type = Type.GetTypeFromProgID("Shell.Application");
            if (type is not null)
            {
                dynamic shell = Activator.CreateInstance(type)!;
                dynamic folder = shell.NameSpace("shell:AppsFolder");
                dynamic items = folder.Items();
                int count = items.Count;
                var seen = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
                for (int i = 0; i < count; i++)
                {
                    dynamic item = items.Item(i);
                    string? name = item?.Name as string;
                    string? id = item?.Path as string;
                    if (string.IsNullOrWhiteSpace(name) || string.IsNullOrWhiteSpace(id) || !seen.Add(id!)) continue;
                    string iconFile = Path.Combine(cacheDir, Hash(id!) + ".png");
                    apps.Add(new Entry(name!, id!, iconFile, File.Exists(iconFile)));
                }
            }
        }
        catch (Exception ex)
        {
            Program.Emit(new { @event = "error", message = "index: " + ex.Message });
        }

        apps.Sort((a, b) => string.Compare(a.Name, b.Name, StringComparison.CurrentCultureIgnoreCase));
        Program.Emit(new
        {
            @event = "apps",
            apps = apps.Select(a => new { name = a.Name, id = a.Id, icon = a.HasIcon ? a.IconFile : null })
        });

        foreach (var a in apps)
        {
            if (a.HasIcon) continue;
            if (IconSaver.Save(@"shell:AppsFolder\" + a.Id, a.IconFile, 48))
                Program.Emit(new { @event = "icon", id = a.Id, icon = a.IconFile });
        }
        Program.Emit(new { @event = "indexed" });
    }

    public static string Hash(string s) =>
        Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(s)))[..24];
}

/// <summary>
/// Extracts an app icon via IShellItemImageFactory and saves it as a PNG. The
/// HBITMAP is read out through GetDIBits so the alpha channel survives (the naive
/// Bitmap.FromHbitmap route drops it and leaves black squares behind icons).
/// </summary>
internal static class IconSaver
{
    public static bool Save(string parsingName, string file, int size)
    {
        IntPtr hbm = IntPtr.Zero;
        try
        {
            Guid riid = typeof(IShellItemImageFactory).GUID;
            var factory = (IShellItemImageFactory)SHCreateItemFromParsingName(parsingName, IntPtr.Zero, ref riid);
            int hr = factory.GetImage(new SIZE { cx = size, cy = size }, SIIGBF_RESIZETOFIT, out hbm);
            Marshal.ReleaseComObject(factory);
            if (hr != 0 || hbm == IntPtr.Zero) return false;
            return SavePng(hbm, file);
        }
        catch
        {
            return false;
        }
        finally
        {
            if (hbm != IntPtr.Zero) DeleteObject(hbm);
        }
    }

    private static bool SavePng(IntPtr hbm, string file)
    {
        if (GetObject(hbm, Marshal.SizeOf<BITMAP>(), out BITMAP bm) == 0) return false;
        if (bm.bmBitsPixel != 32 || bm.bmWidth <= 0 || bm.bmHeight <= 0) return false;

        var bmi = new BITMAPINFO
        {
            bmiHeader = new BITMAPINFOHEADER
            {
                biSize = Marshal.SizeOf<BITMAPINFOHEADER>(),
                biWidth = bm.bmWidth,
                biHeight = -bm.bmHeight, // negative = top-down rows
                biPlanes = 1,
                biBitCount = 32,
                biCompression = 0 // BI_RGB
            }
        };

        int stride = bm.bmWidth * 4;
        var pixels = new byte[stride * bm.bmHeight];
        IntPtr hdc = GetDC(IntPtr.Zero);
        int lines = GetDIBits(hdc, hbm, 0, (uint)bm.bmHeight, pixels, ref bmi, 0);
        ReleaseDC(IntPtr.Zero, hdc);
        if (lines == 0) return false;

        using var bmp = new Bitmap(bm.bmWidth, bm.bmHeight, PixelFormat.Format32bppArgb);
        var data = bmp.LockBits(new Rectangle(0, 0, bm.bmWidth, bm.bmHeight),
            ImageLockMode.WriteOnly, PixelFormat.Format32bppArgb);
        for (int y = 0; y < bm.bmHeight; y++)
            Marshal.Copy(pixels, y * stride, IntPtr.Add(data.Scan0, y * data.Stride), stride);
        bmp.UnlockBits(data);
        bmp.Save(file, ImageFormat.Png);
        return true;
    }

    #region interop

    private const int SIIGBF_RESIZETOFIT = 0x00;

    [ComImport, Guid("bcc18b79-ba16-442f-80c4-8a59c30c463b"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    private interface IShellItemImageFactory
    {
        [PreserveSig]
        int GetImage(SIZE size, int flags, out IntPtr phbm);
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct SIZE
    {
        public int cx;
        public int cy;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct BITMAP
    {
        public int bmType;
        public int bmWidth;
        public int bmHeight;
        public int bmWidthBytes;
        public ushort bmPlanes;
        public ushort bmBitsPixel;
        public IntPtr bmBits;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct BITMAPINFOHEADER
    {
        public int biSize;
        public int biWidth;
        public int biHeight;
        public ushort biPlanes;
        public ushort biBitCount;
        public uint biCompression;
        public uint biSizeImage;
        public int biXPelsPerMeter;
        public int biYPelsPerMeter;
        public uint biClrUsed;
        public uint biClrImportant;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct BITMAPINFO
    {
        public BITMAPINFOHEADER bmiHeader;
        public uint bmiColors;
    }

    [DllImport("shell32.dll", CharSet = CharSet.Unicode, PreserveSig = false)]
    [return: MarshalAs(UnmanagedType.Interface)]
    private static extern object SHCreateItemFromParsingName(string pszPath, IntPtr pbc, ref Guid riid);

    [DllImport("gdi32.dll", CharSet = CharSet.Unicode, EntryPoint = "GetObjectW")]
    private static extern int GetObject(IntPtr h, int c, out BITMAP bm);

    [DllImport("gdi32.dll")]
    private static extern int GetDIBits(IntPtr hdc, IntPtr hbm, uint start, uint cLines,
        byte[] lpvBits, ref BITMAPINFO lpbmi, uint usage);

    [DllImport("gdi32.dll")]
    private static extern bool DeleteObject(IntPtr ho);

    [DllImport("user32.dll")]
    private static extern IntPtr GetDC(IntPtr hWnd);

    [DllImport("user32.dll")]
    private static extern int ReleaseDC(IntPtr hWnd, IntPtr hDC);

    #endregion
}
