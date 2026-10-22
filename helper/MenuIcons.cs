using System.Drawing;
using System.Drawing.Imaging;
using System.IO;
using System.Runtime.InteropServices;

namespace WinKeyHelper;

/// <summary>
/// A menu item's bitmap (the small icons extensions put on their items) as a PNG data URL.
/// Menu bitmaps are 32-bit with premultiplied alpha; one with no alpha at all is opaque.
/// </summary>
internal static class MenuIcons
{
    public static string? ToDataUrl(IntPtr bitmap)
    {
        // 0 is none; -1 and 1..11 are owner-drawn or system glyphs, not real bitmaps.
        if (bitmap == IntPtr.Zero || (long)bitmap is -1 or (>= 1 and <= 11)) return null;
        try
        {
            if (GetObject(bitmap, Marshal.SizeOf<BITMAP>(), out var info) == 0 || info.bmWidth <= 0 || info.bmHeight == 0) return null;
            int width = info.bmWidth, height = Math.Abs(info.bmHeight);
            if (width > 64 || height > 64) return null;

            var header = new BITMAPINFOHEADER
            {
                biSize = Marshal.SizeOf<BITMAPINFOHEADER>(),
                biWidth = width,
                biHeight = -height, // top-down
                biPlanes = 1,
                biBitCount = 32,
            };
            var pixels = new byte[width * height * 4];
            IntPtr screen = GetDC(IntPtr.Zero);
            try
            {
                if (GetDIBits(screen, bitmap, 0, (uint)height, pixels, ref header, 0) == 0) return null;
            }
            finally
            {
                ReleaseDC(IntPtr.Zero, screen);
            }

            bool hasAlpha = false;
            for (int index = 3; index < pixels.Length && !hasAlpha; index += 4) hasAlpha = pixels[index] != 0;
            if (!hasAlpha) for (int index = 3; index < pixels.Length; index += 4) pixels[index] = 255;

            using var image = new Bitmap(width, height, PixelFormat.Format32bppPArgb);
            var data = image.LockBits(new Rectangle(0, 0, width, height), ImageLockMode.WriteOnly, PixelFormat.Format32bppPArgb);
            Marshal.Copy(pixels, 0, data.Scan0, pixels.Length);
            image.UnlockBits(data);
            using var stream = new MemoryStream();
            image.Save(stream, ImageFormat.Png);
            return "data:image/png;base64," + Convert.ToBase64String(stream.ToArray());
        }
        catch
        {
            return null;
        }
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

    [DllImport("gdi32.dll")]
    private static extern int GetObject(IntPtr handle, int size, out BITMAP bitmap);

    [DllImport("gdi32.dll")]
    private static extern int GetDIBits(IntPtr dc, IntPtr bitmap, uint start, uint lines, byte[] bits, ref BITMAPINFOHEADER info, uint usage);

    [DllImport("user32.dll")]
    private static extern IntPtr GetDC(IntPtr hwnd);

    [DllImport("user32.dll")]
    private static extern int ReleaseDC(IntPtr hwnd, IntPtr dc);
}
