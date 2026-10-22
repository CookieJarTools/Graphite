using System.Collections.Concurrent;
using System.Runtime.InteropServices;
using System.Text;
using System.Text.Json;
using System.Windows.Forms;

namespace WinKeyHelper;

/// <summary>
/// Windows' own context menu for files (or a folder's empty space), for the Files app to
/// draw in its own style: every item Explorer has is there (Open with, Send to, Share,
/// Properties, third-party extensions). The helper reads the menu, sends its items, and runs
/// whichever the user picks. Items the Files app does itself (open, rename, cut, copy, paste,
/// delete) carry its action instead and never reach the shell.
///
/// Each menu lives on its own STA thread until it is picked from or dismissed: a shell
/// command can block for a long time, which the thread carrying the keyboard hook must not.
/// </summary>
internal static class ShellMenu
{
    private const uint ShellFirst = 1;
    private const uint ShellLast = 0x7FFF;
    private const int PlaceholderWaitMilliseconds = 800;
    private const int SteadyMilliseconds = 100;
    private static readonly TimeSpan Abandoned = TimeSpan.FromMinutes(5);

    private static Session? _open;
    private static int _nextSession;

    // "shellmenu {json}"; see Request.
    public static void Show(string json)
    {
        Request? request;
        try
        {
            request = JsonSerializer.Deserialize<Request>(json, new JsonSerializerOptions { PropertyNameCaseInsensitive = true });
        }
        catch (JsonException)
        {
            return;
        }
        if (request is null || !long.TryParse(request.Owner, out long owner)) return;

        var session = new Session(Interlocked.Increment(ref _nextSession));
        Interlocked.Exchange(ref _open, session)?.Choices.Add(0); // one menu at a time
        var thread = new Thread(() =>
        {
            try
            {
                if (!Run(request, (IntPtr)owner, session)) EmitAction(request, "fallback");
            }
            catch (Exception error)
            {
                Program.Emit(new { @event = "log", message = "shell menu: " + error.Message });
                EmitAction(request, "fallback");
            }
            finally
            {
                Interlocked.CompareExchange(ref _open, null, session);
            }
        });
        thread.SetApartmentState(ApartmentState.STA);
        thread.IsBackground = true;
        thread.Start();
    }

    // "shellmenupick <session> <id>", or id 0 when the menu closed without a pick.
    public static void Pick(string arg)
    {
        var parts = arg.Split(' ');
        if (parts.Length != 2 || !int.TryParse(parts[0], out int session) || !uint.TryParse(parts[1], out uint id)) return;
        var open = _open;
        if (open is not null && open.Id == session) open.Choices.Add(id);
    }

    // False when Windows has no menu for this (the Files app shows its own).
    private static bool Run(Request request, IntPtr filesWindow, Session session)
    {
        var menuObject = request.Paths is { Length: > 0 } ? ForItems(request.Paths, filesWindow) : ForFolder(request.Folder, filesWindow);
        if (menuObject is null) return false;
        var contextMenu = (IContextMenu)menuObject;
        IntPtr menu = CreatePopupMenu();
        GetCursorPos(out var point);
        try
        {
            uint flags = CMF_NORMAL | (request.CanRename ? CMF_CANRENAME : 0) | (Control.ModifierKeys.HasFlag(Keys.Shift) ? CMF_EXTENDEDVERBS : 0);
            if (contextMenu.QueryContextMenu(menu, 0, ShellFirst, ShellLast, flags) < 0) return false;
            var items = ReadMenu(menu, menuObject, contextMenu, request.Verbs ?? new(), topLevel: true);
            AddOurs(items, request.Ours ?? Array.Empty<OurItem>());
            Program.Emit(new { @event = "shellmenu", owner = request.Owner, session = session.Id, items = Tidy(items) });

            if (!session.Choices.TryTake(out uint chosen, Abandoned) || chosen < ShellFirst || chosen > ShellLast) return true;
            using var foreground = new ForegroundWindow(); // so what the command opens comes to the front
            Invoke(contextMenu, chosen - ShellFirst, filesWindow, request.Folder, point);
            EmitAction(request, "refresh");
            return true;
        }
        finally
        {
            DestroyMenu(menu);
            Marshal.ReleaseComObject(menuObject);
        }
    }

    private static void EmitAction(Request request, string action) => Program.Emit(new { @event = "shellmenu", owner = request.Owner, action });

    // ---------- reading the menu ----------

    // The menu as items for the Files app. Top-level shell items whose verb it handles get
    // its action; a verb mapped to "" is left out (opening a folder in Explorer, say).
    private static List<MenuItem> ReadMenu(IntPtr menu, object menuObject, IContextMenu contextMenu, Dictionary<string, string> verbs, bool topLevel)
    {
        var items = new List<MenuItem>();
        int count = GetMenuItemCount(menu);
        for (int position = 0; position < count; position++)
        {
            var info = new MENUITEMINFO
            {
                cbSize = (uint)Marshal.SizeOf<MENUITEMINFO>(),
                fMask = MIIM_FTYPE | MIIM_STATE | MIIM_ID | MIIM_SUBMENU | MIIM_BITMAP,
            };
            if (!GetMenuItemInfo(menu, (uint)position, true, ref info)) continue;
            if ((info.fType & MFT_SEPARATOR) != 0)
            {
                items.Add(new MenuItem { Separator = true });
                continue;
            }
            var item = ReadItem(menu, position, info);
            if (item is null) continue;
            if (info.hSubMenu != IntPtr.Zero)
            {
                FillSubmenu(menuObject, info.hSubMenu, position);
                item.Children = ReadMenu(info.hSubMenu, menuObject, contextMenu, verbs, topLevel: false);
                if (item.Children.Count == 0) continue;
            }
            else if (topLevel && info.wID >= ShellFirst && info.wID <= ShellLast)
            {
                item.Verb = VerbOf(contextMenu, info.wID - ShellFirst);
                if (verbs.TryGetValue(item.Verb, out var action))
                {
                    if (action.Length == 0) continue;
                    item.Action = action;
                }
            }
            items.Add(item);
        }
        return items;
    }

    private static MenuItem? ReadItem(IntPtr menu, int position, MENUITEMINFO info)
    {
        var text = new StringBuilder(260);
        GetMenuString(menu, (uint)position, text, text.Capacity, MF_BYPOSITION);
        var (label, mnemonic, shortcut) = ParseText(text.ToString());
        if (label.Length == 0) return null; // owner-drawn without text: nothing to show
        return new MenuItem
        {
            Id = info.wID,
            Label = label,
            Mnemonic = mnemonic,
            Shortcut = shortcut,
            Disabled = (info.fState & MFS_DISABLED) != 0,
            Default = (info.fState & MFS_DEFAULT) != 0,
            Checked = (info.fState & MFS_CHECKED) != 0,
            Icon = MenuIcons.ToDataUrl(info.hbmpItem),
        };
    }

    // "Open &with\tCtrl+W" -> ("Open with", "w", "Ctrl+W"); "&&" is a literal ampersand.
    private static (string Label, string? Mnemonic, string? Shortcut) ParseText(string text)
    {
        string? shortcut = null;
        int tab = text.IndexOf('\t');
        if (tab >= 0)
        {
            shortcut = text[(tab + 1)..].Trim();
            text = text[..tab];
        }
        var label = new StringBuilder();
        string? mnemonic = null;
        for (int index = 0; index < text.Length; index++)
        {
            if (text[index] == '&' && index + 1 < text.Length)
            {
                index++;
                if (text[index] != '&' && mnemonic is null) mnemonic = char.ToLowerInvariant(text[index]).ToString();
            }
            label.Append(text[index]);
        }
        return (label.ToString().Trim(), mnemonic, string.IsNullOrEmpty(shortcut) ? null : shortcut);
    }

    // Submenus such as Send to and Open with are filled only when told they are opening.
    // Send to answers with a blank placeholder and fills it in from the background, item by
    // item, while messages run.
    private static void FillSubmenu(object menuObject, IntPtr submenu, int position)
    {
        try
        {
            if (menuObject is IContextMenu3 menu3) menu3.HandleMenuMsg2(WM_INITMENUPOPUP, submenu, (IntPtr)position, out _);
            else if (menuObject is IContextMenu2 menu2) menu2.HandleMenuMsg(WM_INITMENUPOPUP, submenu, (IntPtr)position);
            if (!OnlyPlaceholder(submenu)) return;

            // Wait for the real items, then until no more arrive.
            var deadline = Environment.TickCount64 + PlaceholderWaitMilliseconds;
            int count = -1, steadyFor = 0;
            while (Environment.TickCount64 < deadline && steadyFor < SteadyMilliseconds)
            {
                Application.DoEvents();
                Thread.Sleep(25);
                int now = OnlyPlaceholder(submenu) ? -1 : GetMenuItemCount(submenu);
                steadyFor = now >= 0 && now == count ? steadyFor + 25 : 0;
                count = now;
            }
        }
        catch
        {
            // A broken extension's submenu stays as it is.
        }
    }

    private static bool OnlyPlaceholder(IntPtr submenu)
    {
        if (GetMenuItemCount(submenu) != 1) return false;
        var text = new StringBuilder(260);
        return GetMenuString(submenu, 0, text, text.Capacity, MF_BYPOSITION) == 0;
    }

    private static string VerbOf(IContextMenu contextMenu, uint offset)
    {
        IntPtr buffer = Marshal.AllocHGlobal(512);
        try
        {
            Marshal.WriteInt16(buffer, 0);
            return contextMenu.GetCommandString((UIntPtr)offset, GCS_VERBW, IntPtr.Zero, buffer, 255) == 0
                ? (Marshal.PtrToStringUni(buffer) ?? "").ToLowerInvariant()
                : "";
        }
        catch
        {
            return ""; // some extensions throw here
        }
        finally
        {
            Marshal.FreeHGlobal(buffer);
        }
    }

    // The app's own items go right after the item carrying their "after" action, or first;
    // one the shell already has (say, Open in new tab) is not added twice.
    private static void AddOurs(List<MenuItem> items, OurItem[] ours)
    {
        for (int index = ours.Length - 1; index >= 0; index--)
        {
            var our = ours[index];
            if (items.Any((item) => item.Action == our.Id)) continue;
            int anchor = our.After is null ? -1 : items.FindIndex((item) => item.Action == our.After);
            items.Insert(anchor + 1, new MenuItem { Label = our.Label, Action = our.Id });
        }
    }

    // No separator first, last or twice in a row once items were left out, and no item twice.
    private static List<MenuItem> Tidy(List<MenuItem> items)
    {
        var tidy = new List<MenuItem>();
        foreach (var item in items)
        {
            if (item.Separator && (tidy.Count == 0 || tidy[^1].Separator)) continue;
            if (!item.Separator && item.Children is null && tidy.Any((other) => other.Children is null && other.Label == item.Label)) continue; // an extension listed twice
            if (item.Children is not null) item.Children = Tidy(item.Children);
            tidy.Add(item);
        }
        if (tidy.Count > 0 && tidy[^1].Separator) tidy.RemoveAt(tidy.Count - 1);
        return tidy;
    }

    // ---------- the shell objects ----------

    // The selected items' menu. They must share one folder, as in a folder view.
    private static object? ForItems(string[] paths, IntPtr window)
    {
        var pidls = new List<IntPtr>();
        try
        {
            foreach (var path in paths)
            {
                if (SHParseDisplayName(path, IntPtr.Zero, out var pidl, 0, out _) != 0) return null;
                pidls.Add(pidl);
            }
            var shellFolderId = typeof(IShellFolder).GUID;
            if (SHBindToParent(pidls[0], ref shellFolderId, out var folderPointer, out _) != 0) return null;
            var folder = (IShellFolder)Marshal.GetObjectForIUnknown(folderPointer);
            Marshal.Release(folderPointer);
            try
            {
                var children = pidls.Select(ILFindLastID).ToArray();
                var menuId = typeof(IContextMenu).GUID;
                return folder.GetUIObjectOf(window, (uint)children.Length, children, ref menuId, IntPtr.Zero, out var menuPointer) == 0
                    ? TakeObject(menuPointer)
                    : null;
            }
            finally
            {
                Marshal.ReleaseComObject(folder);
            }
        }
        finally
        {
            pidls.ForEach(Marshal.FreeCoTaskMem);
        }
    }

    // The menu for a folder's empty space: New, Paste, Open in Terminal, Properties...
    private static object? ForFolder(string? path, IntPtr window)
    {
        if (string.IsNullOrEmpty(path) || SHParseDisplayName(path, IntPtr.Zero, out var pidl, 0, out _) != 0) return null;
        try
        {
            if (SHGetDesktopFolder(out var desktop) != 0) return null;
            try
            {
                var shellFolderId = typeof(IShellFolder).GUID;
                if (desktop.BindToObject(pidl, IntPtr.Zero, ref shellFolderId, out var folderPointer) != 0) return null;
                var folder = (IShellFolder)TakeObject(folderPointer);
                try
                {
                    var menuId = typeof(IContextMenu).GUID;
                    return folder.CreateViewObject(window, ref menuId, out var menuPointer) == 0 ? TakeObject(menuPointer) : null;
                }
                finally
                {
                    Marshal.ReleaseComObject(folder);
                }
            }
            finally
            {
                Marshal.ReleaseComObject(desktop);
            }
        }
        finally
        {
            Marshal.FreeCoTaskMem(pidl);
        }
    }

    private static object TakeObject(IntPtr pointer)
    {
        var instance = Marshal.GetObjectForIUnknown(pointer);
        Marshal.Release(pointer);
        return instance;
    }

    private static void Invoke(IContextMenu contextMenu, uint offset, IntPtr window, string? folder, POINT point)
    {
        IntPtr directory = folder is null ? IntPtr.Zero : Marshal.StringToHGlobalUni(folder);
        try
        {
            var keys = Control.ModifierKeys;
            var info = new CMINVOKECOMMANDINFOEX
            {
                cbSize = Marshal.SizeOf<CMINVOKECOMMANDINFOEX>(),
                fMask = CMIC_MASK_UNICODE | CMIC_MASK_PTINVOKE
                    | (keys.HasFlag(Keys.Control) ? CMIC_MASK_CONTROL_DOWN : 0)
                    | (keys.HasFlag(Keys.Shift) ? CMIC_MASK_SHIFT_DOWN : 0),
                hwnd = window,
                lpVerb = (IntPtr)offset,
                lpVerbW = (IntPtr)offset,
                lpDirectoryW = directory,
                nShow = SW_SHOWNORMAL,
                ptInvoke = point,
            };
            contextMenu.InvokeCommand(ref info);
        }
        finally
        {
            if (directory != IntPtr.Zero) Marshal.FreeHGlobal(directory);
        }
    }

    // ---------- types ----------

    private sealed class Session
    {
        public Session(int id) => Id = id;

        public int Id { get; }

        public BlockingCollection<uint> Choices { get; } = new();
    }

    /// <summary>What the Files app asks for.</summary>
    private sealed class Request
    {
        public string Owner { get; set; } = "";        // the Files window
        public string[]? Paths { get; set; }           // selected items; none: the folder's empty space
        public string? Folder { get; set; }            // the folder on show
        public bool CanRename { get; set; }
        public Dictionary<string, string>? Verbs { get; set; } // shell verb -> the app's action ("" leaves it out)
        public OurItem[]? Ours { get; set; }
    }

    private sealed class OurItem
    {
        public string Id { get; set; } = "";
        public string Label { get; set; } = "";
        public string? After { get; set; }
    }

    /// <summary>One menu item as the Files app gets it (camelCase JSON).</summary>
    private sealed class MenuItem
    {
        [System.Text.Json.Serialization.JsonPropertyName("id")] public uint Id { get; set; }
        [System.Text.Json.Serialization.JsonPropertyName("label")] public string? Label { get; set; }
        [System.Text.Json.Serialization.JsonPropertyName("mnemonic")] public string? Mnemonic { get; set; }
        [System.Text.Json.Serialization.JsonPropertyName("shortcut")] public string? Shortcut { get; set; }
        [System.Text.Json.Serialization.JsonPropertyName("icon")] public string? Icon { get; set; }
        [System.Text.Json.Serialization.JsonPropertyName("disabled")] public bool Disabled { get; set; }
        [System.Text.Json.Serialization.JsonPropertyName("default")] public bool Default { get; set; }
        [System.Text.Json.Serialization.JsonPropertyName("checked")] public bool Checked { get; set; }
        [System.Text.Json.Serialization.JsonPropertyName("separator")] public bool Separator { get; set; }
        [System.Text.Json.Serialization.JsonPropertyName("verb")] public string? Verb { get; set; } // the shell's name for it, for a fitting glyph
        [System.Text.Json.Serialization.JsonPropertyName("action")] public string? Action { get; set; }
        [System.Text.Json.Serialization.JsonPropertyName("children")] public List<MenuItem>? Children { get; set; }
    }

    /// <summary>
    /// A hidden helper window brought to the front while a command runs: Windows lets only
    /// the foreground process hand the front to the windows a command opens.
    /// </summary>
    private sealed class ForegroundWindow : NativeWindow, IDisposable
    {
        public ForegroundWindow()
        {
            CreateHandle(new CreateParams { ExStyle = WS_EX_TOOLWINDOW });
            Program.ForceForeground(Handle);
        }

        public void Dispose() => DestroyHandle();
    }

    // ---------- interop ----------

    private const uint CMF_NORMAL = 0x0;
    private const uint CMF_CANRENAME = 0x10;
    private const uint CMF_EXTENDEDVERBS = 0x100;
    private const uint GCS_VERBW = 0x4;
    private const int CMIC_MASK_UNICODE = 0x4000;
    private const int CMIC_MASK_SHIFT_DOWN = 0x10000000;
    private const int CMIC_MASK_CONTROL_DOWN = 0x40000000;
    private const int CMIC_MASK_PTINVOKE = 0x20000000;
    private const int SW_SHOWNORMAL = 1;
    private const uint MF_BYPOSITION = 0x400;
    private const uint MIIM_STATE = 0x1;
    private const uint MIIM_ID = 0x2;
    private const uint MIIM_SUBMENU = 0x4;
    private const uint MIIM_BITMAP = 0x80;
    private const uint MIIM_FTYPE = 0x100;
    private const uint MFT_SEPARATOR = 0x800;
    private const uint MFS_DISABLED = 0x3;
    private const uint MFS_CHECKED = 0x8;
    private const uint MFS_DEFAULT = 0x1000;
    private const uint WM_INITMENUPOPUP = 0x117;
    private const int WS_EX_TOOLWINDOW = 0x80;

    [StructLayout(LayoutKind.Sequential)]
    private struct POINT
    {
        public int X, Y;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct CMINVOKECOMMANDINFOEX
    {
        public int cbSize;
        public int fMask;
        public IntPtr hwnd;
        public IntPtr lpVerb;
        public IntPtr lpParameters;
        public IntPtr lpDirectory;
        public int nShow;
        public int dwHotKey;
        public IntPtr hIcon;
        public IntPtr lpTitle;
        public IntPtr lpVerbW;
        public IntPtr lpParametersW;
        public IntPtr lpDirectoryW;
        public IntPtr lpTitleW;
        public POINT ptInvoke;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct MENUITEMINFO
    {
        public uint cbSize;
        public uint fMask;
        public uint fType;
        public uint fState;
        public uint wID;
        public IntPtr hSubMenu;
        public IntPtr hbmpChecked;
        public IntPtr hbmpUnchecked;
        public IntPtr dwItemData;
        public IntPtr dwTypeData;
        public uint cch;
        public IntPtr hbmpItem;
    }

    [ComImport, Guid("000214E6-0000-0000-C000-000000000046"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    private interface IShellFolder
    {
        [PreserveSig] int ParseDisplayName(IntPtr hwnd, IntPtr bindContext, [MarshalAs(UnmanagedType.LPWStr)] string displayName, IntPtr eaten, out IntPtr pidl, IntPtr attributes);
        [PreserveSig] int EnumObjects(IntPtr hwnd, int flags, out IntPtr enumerator);
        [PreserveSig] int BindToObject(IntPtr pidl, IntPtr bindContext, ref Guid riid, out IntPtr result);
        [PreserveSig] int BindToStorage(IntPtr pidl, IntPtr bindContext, ref Guid riid, out IntPtr result);
        [PreserveSig] int CompareIDs(IntPtr lParam, IntPtr pidl1, IntPtr pidl2);
        [PreserveSig] int CreateViewObject(IntPtr hwndOwner, ref Guid riid, out IntPtr result);
        [PreserveSig] int GetAttributesOf(uint count, [MarshalAs(UnmanagedType.LPArray)] IntPtr[] pidls, ref uint attributes);
        [PreserveSig] int GetUIObjectOf(IntPtr hwndOwner, uint count, [MarshalAs(UnmanagedType.LPArray)] IntPtr[] pidls, ref Guid riid, IntPtr reserved, out IntPtr result);
        [PreserveSig] int GetDisplayNameOf(IntPtr pidl, uint flags, IntPtr name);
        [PreserveSig] int SetNameOf(IntPtr hwnd, IntPtr pidl, [MarshalAs(UnmanagedType.LPWStr)] string name, uint flags, out IntPtr pidlOut);
    }

    [ComImport, Guid("000214E4-0000-0000-C000-000000000046"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    private interface IContextMenu
    {
        [PreserveSig] int QueryContextMenu(IntPtr menu, uint indexMenu, uint idCmdFirst, uint idCmdLast, uint flags);
        [PreserveSig] int InvokeCommand(ref CMINVOKECOMMANDINFOEX info);
        [PreserveSig] int GetCommandString(UIntPtr idCmd, uint type, IntPtr reserved, IntPtr name, uint maxChars);
    }

    [ComImport, Guid("000214F4-0000-0000-C000-000000000046"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    private interface IContextMenu2
    {
        [PreserveSig] int QueryContextMenu(IntPtr menu, uint indexMenu, uint idCmdFirst, uint idCmdLast, uint flags);
        [PreserveSig] int InvokeCommand(ref CMINVOKECOMMANDINFOEX info);
        [PreserveSig] int GetCommandString(UIntPtr idCmd, uint type, IntPtr reserved, IntPtr name, uint maxChars);
        [PreserveSig] int HandleMenuMsg(uint message, IntPtr wParam, IntPtr lParam);
    }

    [ComImport, Guid("BCFCE0A0-EC17-11D0-8D10-00A0C90F2719"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    private interface IContextMenu3
    {
        [PreserveSig] int QueryContextMenu(IntPtr menu, uint indexMenu, uint idCmdFirst, uint idCmdLast, uint flags);
        [PreserveSig] int InvokeCommand(ref CMINVOKECOMMANDINFOEX info);
        [PreserveSig] int GetCommandString(UIntPtr idCmd, uint type, IntPtr reserved, IntPtr name, uint maxChars);
        [PreserveSig] int HandleMenuMsg(uint message, IntPtr wParam, IntPtr lParam);
        [PreserveSig] int HandleMenuMsg2(uint message, IntPtr wParam, IntPtr lParam, out IntPtr result);
    }

    [DllImport("shell32.dll", CharSet = CharSet.Unicode)]
    private static extern int SHParseDisplayName(string name, IntPtr bindContext, out IntPtr pidl, uint attributesIn, out uint attributesOut);

    [DllImport("shell32.dll")]
    private static extern int SHBindToParent(IntPtr pidl, ref Guid riid, out IntPtr result, out IntPtr pidlLast);

    [DllImport("shell32.dll")]
    private static extern int SHGetDesktopFolder(out IShellFolder folder);

    [DllImport("shell32.dll")]
    private static extern IntPtr ILFindLastID(IntPtr pidl);

    [DllImport("user32.dll")]
    private static extern IntPtr CreatePopupMenu();

    [DllImport("user32.dll")]
    private static extern bool DestroyMenu(IntPtr menu);

    [DllImport("user32.dll")]
    private static extern int GetMenuItemCount(IntPtr menu);

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    private static extern bool GetMenuItemInfo(IntPtr menu, uint item, bool byPosition, ref MENUITEMINFO info);

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    private static extern int GetMenuString(IntPtr menu, uint item, StringBuilder text, int maxCount, uint flags);

    [DllImport("user32.dll")]
    private static extern bool GetCursorPos(out POINT point);
}
