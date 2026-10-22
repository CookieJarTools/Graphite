using System.Collections.Specialized;
using System.IO;
using System.Runtime.InteropServices;
using System.Text.Json;
using System.Windows.Forms;

namespace WinKeyHelper;

/// <summary>
/// Puts files the Files app copied or cut on the Windows clipboard, the way Explorer does
/// (a file list plus "Preferred DropEffect"), so Explorer and the shell's own Paste see them.
/// </summary>
internal static class FileClipboard
{
    private const int DropEffectCopy = 1;
    private const int DropEffectMove = 2;

    // "setclipfiles copy|move ["C:\\a", ...]"; call on the UI thread (the clipboard needs STA).
    public static void Set(string arg)
    {
        var parts = arg.Split(' ', 2);
        if (parts.Length != 2) return;
        string[]? paths;
        try
        {
            paths = JsonSerializer.Deserialize<string[]>(parts[1]);
        }
        catch (JsonException)
        {
            return;
        }
        if (paths is null || paths.Length == 0) return;

        var files = new StringCollection();
        files.AddRange(paths);
        var data = new DataObject();
        data.SetFileDropList(files);
        int effect = parts[0] == "move" ? DropEffectMove : DropEffectCopy;
        data.SetData("Preferred DropEffect", new MemoryStream(BitConverter.GetBytes(effect)));
        try
        {
            Clipboard.SetDataObject(data, true, 5, 50);
        }
        catch (ExternalException)
        {
            // Another app holds the clipboard; the Files app's own paste still works.
        }
    }
}
