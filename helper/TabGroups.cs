using System.Runtime.InteropServices;

namespace WinKeyHelper;

/// <summary>
/// Window tabs (TabStrip and WindowMerge in the design). A group is a set of windows
/// sharing one place on screen: only the active tab's window is shown, the rest are
/// hidden, and switching copies the active window's placement onto the next one.
/// Electron draws one strip window per group; this class keeps it glued just above the
/// group's window and does every window operation.
///
/// Stacking: Windows will not let a background process raise a window above the
/// foreground one, so while the group's window has focus its strip is made topmost, and
/// when focus moves elsewhere the strip is dropped to just below the newly focused
/// window, which leaves it directly above its own window either way.
///
/// Grouping happens by dragging: while a window is being moved, the drop target under
/// the pointer (another window's title band, or a group's strip) is reported so the
/// strip can show a slot tab, and letting go there folds the dragged window in.
///
/// Hidden windows are the risk here, so everything that ends the helper calls
/// <see cref="RestoreAll"/>, and Electron keeps its own list to restore after a crash.
/// All methods run on the UI thread: WinEvent callbacks arrive there and Program posts
/// commands there.
/// </summary>
internal static class TabGroups
{
    private const int StripHeight = 40;          // strip-height
    private const int CaptionButtonsWidth = 150; // left clear when the strip overlaps a title bar
    private const int SplitOffset = 40;

    private sealed class Group
    {
        public int Id;
        public readonly List<IntPtr> Tabs = new();
        public IntPtr Active;
        public IntPtr Strip;
        public bool Topmost;
    }

    private static readonly List<Group> Groups = new();
    private static readonly List<IntPtr> Hooks = new();
    private static readonly HashSet<IntPtr> ShownByUs = new();
    private static readonly Dictionary<IntPtr, (int Width, int Height)> StripSizes = new();
    // Windows with tabs of their own (Files): never dragged into, or out as, a window group.
    private static readonly HashSet<IntPtr> OwnTabs = new();
    private static WinEventDelegate? _proc;
    private static System.Windows.Forms.Timer? _titleDebounce;
    private static System.Windows.Forms.Timer? _raiseLater;
    private static int _nextId = 1;
    private static bool _enabled;
    private static uint _ownPid;
    private static IntPtr _hoverStrip;
    private static IntPtr _dragging;
    private static RECT _dragStartRect;
    private static bool _dragIsMove;
    private static bool _dragStartedZoomed;
    private static IntPtr _hoverTarget;
    private static IntPtr _mergingWindow;   // off screen while its merge animation plays
    private static RECT _mergingFrom;

    public static uint OwnPid
    {
        set => _ownPid = value;
    }

    public static void Install()
    {
        _proc = OnWinEvent;
        _titleDebounce = new System.Windows.Forms.Timer { Interval = 250 };
        _titleDebounce.Tick += (_, _) =>
        {
            _titleDebounce.Stop();
            EmitState();
        };
        // An activated window finishes coming to the top a moment after we hear about it,
        // which would bury its strip, so the strip is raised once more shortly after.
        _raiseLater = new System.Windows.Forms.Timer { Interval = 80 };
        _raiseLater.Tick += (_, _) =>
        {
            _raiseLater.Stop();
            IntPtr foreground = GetForegroundWindow();
            var group = Groups.Find((candidate) => candidate.Active == foreground);
            if (group is not null && group.Strip != IntPtr.Zero && !IsIconic(group.Active)) MakeStripTopmost(group);
            LowerStripsBelow(foreground, group);
        };

        Hook(EVENT_SYSTEM_FOREGROUND, EVENT_SYSTEM_FOREGROUND);
        Hook(EVENT_SYSTEM_MOVESIZESTART, EVENT_SYSTEM_MOVESIZEEND);
        Hook(EVENT_SYSTEM_MINIMIZESTART, EVENT_SYSTEM_MINIMIZEEND);
        Hook(EVENT_OBJECT_DESTROY, EVENT_OBJECT_SHOW);
        Hook(EVENT_OBJECT_LOCATIONCHANGE, EVENT_OBJECT_NAMECHANGE);
    }

    public static void SetEnabled(bool enabled)
    {
        _enabled = enabled;
        if (!enabled) RestoreAll();
    }

    public static void SetStrip(int groupId, IntPtr strip)
    {
        var group = Groups.Find((candidate) => candidate.Id == groupId);
        if (group is null) return;
        group.Strip = strip;
        PlaceStrip(group, true);
    }

    public static void SetHoverStrip(IntPtr strip) => _hoverStrip = strip;

    public static void ExcludeFromGrouping(IntPtr hwnd) => OwnTabs.Add(hwnd);

    // ---------- commands from the strip ----------

    public static void Activate(IntPtr hwnd)
    {
        var group = GroupOf(hwnd);
        if (group is null) return;
        if (group.Active == hwnd)
        {
            WindowList.Activate(hwnd);
            return;
        }

        IntPtr previous = group.Active;
        CopyPlacement(previous, hwnd);
        WindowList.Activate(hwnd);
        group.Active = hwnd;
        ShowWindow(previous, SW_HIDE);
        PlaceStrip(group, true);
        EmitState();
    }

    // A hidden window could open a save prompt nobody sees, so it is brought forward first.
    public static void Close(IntPtr hwnd)
    {
        var group = GroupOf(hwnd);
        if (group is not null && group.Active != hwnd) Activate(hwnd);
        WindowList.Close(hwnd);
    }

    public static void Split(IntPtr hwnd)
    {
        var group = GroupOf(hwnd);
        if (group is null) return;
        if (group.Active == hwnd) Activate(Neighbour(group, hwnd));

        group.Tabs.Remove(hwnd);
        var placement = Placement(group.Active);
        int offset = Scaled(SplitOffset, hwnd);
        placement.rcNormalPosition.Left += offset;
        placement.rcNormalPosition.Top += offset;
        placement.rcNormalPosition.Right += offset;
        placement.rcNormalPosition.Bottom += offset;
        placement.showCmd = SW_SHOWNORMAL;
        ShownByUs.Add(hwnd);
        SetWindowPlacement(hwnd, ref placement);
        WindowList.Activate(hwnd);

        DissolveIfSingle(group);
        EmitState();
    }

    /// <summary>Groups two windows without a drag (the tabmerge command).</summary>
    public static void MergeWindows(IntPtr source, IntPtr target)
    {
        if (_enabled && source != target) Merge(source, target);
    }

    /// <summary>Starts the window's own move loop, so dragging the strip drags the group.</summary>
    public static void DragMove(IntPtr hwnd)
    {
        if (GroupOf(hwnd) is null) return;
        PostMessage(hwnd, WM_SYSCOMMAND, (IntPtr)SC_DRAGMOVE, IntPtr.Zero);
    }

    /// <summary>Shows every hidden tab. Called whenever the helper is about to stop managing them.</summary>
    public static void RestoreAll()
    {
        // A window caught mid-merge is still off screen: put it back where it was dropped.
        if (_mergingWindow != IntPtr.Zero && IsWindow(_mergingWindow))
            SetWindowPos(_mergingWindow, IntPtr.Zero, _mergingFrom.Left, _mergingFrom.Top, 0, 0, SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE);
        _mergingWindow = IntPtr.Zero;

        foreach (var group in Groups)
        {
            foreach (var tab in group.Tabs)
            {
                if (tab != group.Active && IsWindow(tab)) ShowWindow(tab, SW_SHOWNA);
            }
            if (group.Strip != IntPtr.Zero) ShowWindow(group.Strip, SW_HIDE);
        }
        Groups.Clear();
        EmitState();
    }

    /// <summary>After a crash: shows a window Electron remembers hiding, if it is still the same window.</summary>
    public static void RestoreRemembered(IntPtr hwnd, string exe)
    {
        if (!IsWindow(hwnd) || IsWindowVisible(hwnd) || GroupOf(hwnd) is not null) return;
        GetWindowThreadProcessId(hwnd, out uint pid);
        if (!string.Equals(WindowList.ProcessPath(pid), exe, StringComparison.OrdinalIgnoreCase)) return;
        ShowWindow(hwnd, SW_SHOWNA);
        Program.Emit(new { @event = "tabrestored" });
    }

    // ---------- events ----------

    private static void Hook(uint eventMin, uint eventMax)
    {
        var hook = SetWinEventHook(eventMin, eventMax, IntPtr.Zero, _proc!, 0, 0, WINEVENT_OUTOFCONTEXT | WINEVENT_SKIPOWNPROCESS);
        if (hook != IntPtr.Zero) Hooks.Add(hook);
    }

    private static void OnWinEvent(IntPtr hWinEventHook, uint eventType, IntPtr hwnd,
        int idObject, int idChild, uint dwEventThread, uint dwmsEventTime)
    {
        if (idObject != OBJID_WINDOW || idChild != 0 || hwnd == IntPtr.Zero) return;

        switch (eventType)
        {
            case EVENT_SYSTEM_MOVESIZESTART: OnMoveStart(hwnd); break;
            case EVENT_OBJECT_LOCATIONCHANGE: OnLocationChange(hwnd); break;
            case EVENT_SYSTEM_MOVESIZEEND: OnMoveEnd(hwnd); break;
            case EVENT_SYSTEM_FOREGROUND: OnForeground(hwnd); break;
            case EVENT_OBJECT_SHOW: OnShow(hwnd); break;
            case EVENT_OBJECT_DESTROY: OnDestroy(hwnd); break;
            case EVENT_SYSTEM_MINIMIZESTART: OnMinimize(hwnd, true); break;
            case EVENT_SYSTEM_MINIMIZEEND: OnMinimize(hwnd, false); break;
            case EVENT_OBJECT_NAMECHANGE:
                if (GroupOf(hwnd) is not null)
                {
                    _titleDebounce!.Stop();
                    _titleDebounce.Start();
                }
                break;
        }
    }

    private static void OnMoveStart(IntPtr hwnd)
    {
        if (!_enabled || OwnTabs.Contains(hwnd) || !WindowList.IsSwitchable(hwnd, _ownPid)) return;
        _dragging = hwnd;
        GetWindowRect(hwnd, out _dragStartRect);
        _dragIsMove = true;
        _dragStartedZoomed = IsZoomed(hwnd);
    }

    private static void OnLocationChange(IntPtr hwnd)
    {
        if (hwnd == _dragging && _dragIsMove)
        {
            GetWindowRect(hwnd, out var rect);
            bool resized = rect.Right - rect.Left != _dragStartRect.Right - _dragStartRect.Left
                || rect.Bottom - rect.Top != _dragStartRect.Bottom - _dragStartRect.Top;
            // Dragging a maximised window restores it, which changes its size once; any
            // other size change means the user is resizing, which never merges.
            if (resized && _dragStartedZoomed)
            {
                _dragStartedZoomed = false;
                _dragStartRect = rect;
            }
            else if (resized)
            {
                _dragIsMove = false;
                SetHover(IntPtr.Zero);
            }
            if (_dragIsMove) UpdateHover();
        }

        var group = Groups.Find((candidate) => candidate.Active == hwnd);
        if (group is not null) PlaceStrip(group, false);
    }

    private static void OnMoveEnd(IntPtr hwnd)
    {
        if (hwnd != _dragging) return;
        IntPtr target = _hoverTarget;
        _dragging = IntPtr.Zero;
        if (target == IntPtr.Zero)
        {
            SetHover(IntPtr.Zero);
            return;
        }
        if (!Thumbnails.AnimationsEnabled())
        {
            SetHover(IntPtr.Zero);
            Merge(hwnd, target);
            return;
        }

        // WindowMerge: the dropped window shrinks into the slot tab and fades, then the
        // group takes it in. The real window waits off screen meanwhile (DWM still draws it).
        var from = WindowRect(hwnd);
        var to = SlotRect(target);
        var screen = System.Windows.Forms.SystemInformation.VirtualScreen;
        _mergingWindow = hwnd;
        _mergingFrom = from;
        SetWindowPos(hwnd, IntPtr.Zero, screen.Right + 200, from.Top, 0, 0, SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE);
        Thumbnails.AnimateMerge(hwnd,
            System.Drawing.Rectangle.FromLTRB(from.Left, from.Top, from.Right, from.Bottom),
            System.Drawing.Rectangle.FromLTRB(to.Left, to.Top, to.Right, to.Bottom),
            () =>
            {
                _mergingWindow = IntPtr.Zero;
                SetHover(IntPtr.Zero);
                Merge(hwnd, target);
            });
    }

    // Where the slot tab sits on the target's strip: after its existing tabs. The strip
    // is drawn by Electron, so this is the layout's arithmetic rather than a measurement.
    private static RECT SlotRect(IntPtr target)
    {
        var strip = StripRect(target);
        int tabCount = GroupOf(target)?.Tabs.Count ?? 1;
        int padding = Scaled(16, target);
        int tabWidth = Scaled(160, target);
        int tabHeight = Scaled(28, target);
        int left = Math.Min(strip.Left + padding + tabCount * tabWidth, strip.Right - tabWidth);
        int top = strip.Top + (strip.Bottom - strip.Top - tabHeight) / 2;
        return new RECT { Left = left, Top = top, Right = left + tabWidth, Bottom = top + tabHeight };
    }

    private static void OnForeground(IntPtr hwnd)
    {
        var group = GroupOf(hwnd);
        // Settle the stacking once the newly focused window has finished coming to the top.
        _raiseLater!.Stop();
        _raiseLater.Start();
        if (group is null) return;
        if (group.Active != hwnd) Activate(hwnd);
        else PlaceStrip(group, true);
    }

    // An app showing one of its hidden tabs by itself (a notification click, say) makes it the active tab.
    private static void OnShow(IntPtr hwnd)
    {
        if (ShownByUs.Remove(hwnd)) return;
        var group = GroupOf(hwnd);
        if (group is not null && group.Active != hwnd) Activate(hwnd);
    }

    private static void OnDestroy(IntPtr hwnd)
    {
        OwnTabs.Remove(hwnd);
        if (hwnd == _dragging)
        {
            SetHover(IntPtr.Zero);
            _dragging = IntPtr.Zero;
        }
        var group = GroupOf(hwnd);
        if (group is null) return;

        bool wasActive = group.Active == hwnd;
        IntPtr next = wasActive ? Neighbour(group, hwnd) : IntPtr.Zero;
        group.Tabs.Remove(hwnd);
        if (wasActive && next != IntPtr.Zero)
        {
            group.Active = next;
            ShownByUs.Add(next);
            ShowWindow(next, SW_SHOW);
            WindowList.Activate(next);
        }
        DissolveIfSingle(group);
        if (Groups.Contains(group)) PlaceStrip(group, true);
        EmitState();
    }

    private static void OnMinimize(IntPtr hwnd, bool minimized)
    {
        var group = Groups.Find((candidate) => candidate.Active == hwnd);
        if (group is null || group.Strip == IntPtr.Zero) return;
        if (minimized) ShowWindow(group.Strip, SW_HIDE);
        else PlaceStrip(group, true);
    }

    // ---------- merging ----------

    private static void UpdateHover()
    {
        GetCursorPos(out POINT point);
        SetHover(FindDropTarget(point));
    }

    private static void SetHover(IntPtr target)
    {
        if (target == _hoverTarget) return;
        _hoverTarget = target;

        if (target == IntPtr.Zero)
        {
            if (_hoverStrip != IntPtr.Zero) ShowWindow(_hoverStrip, SW_HIDE);
            Program.Emit(new { @event = "mergehover", group = (int?)null });
            return;
        }

        var group = GroupOf(target);
        if (group is null && _hoverStrip != IntPtr.Zero)
            ApplyStripRect(_hoverStrip, 0, StripRect(target), HWND_TOPMOST, SWP_NOACTIVATE | SWP_SHOWWINDOW);
        Program.Emit(new
        {
            @event = "mergehover",
            group = group?.Id,
            target = WindowList.Describe(target),
            source = WindowList.Describe(_dragging),
        });
    }

    // Walks the z-order from the top: the first window under the pointer decides. Its title
    // band (or its group's strip) is a drop target; anywhere else on it hides what is below.
    private static IntPtr FindDropTarget(POINT point)
    {
        var draggedGroup = GroupOf(_dragging);
        IntPtr found = IntPtr.Zero;
        EnumWindows((hwnd, _) =>
        {
            if (hwnd == _dragging || hwnd == _hoverStrip) return true;

            var stripGroup = Groups.Find((candidate) => candidate.Strip == hwnd);
            if (stripGroup is not null)
            {
                if (!IsWindowVisible(hwnd) || !Contains(WindowRect(hwnd), point)) return true;
                if (stripGroup != draggedGroup) found = stripGroup.Active;
                return false;
            }

            if (!WindowList.IsSwitchable(hwnd, _ownPid) || IsIconic(hwnd)) return true;
            var frame = FrameRect(hwnd);
            if (OwnTabs.Contains(hwnd)) return !Contains(frame, point); // covers what is below, takes no drops
            var band = StripRect(hwnd);
            var titleBand = frame with { Bottom = frame.Top + Scaled(StripHeight, hwnd) };
            if (Contains(band, point) || Contains(titleBand, point))
            {
                if (GroupOf(hwnd) is not { } group || group != draggedGroup) found = hwnd;
                return false;
            }
            return !Contains(frame, point);
        }, IntPtr.Zero);
        return found;
    }

    // The dropped window becomes the active tab at the target's place; the target hides.
    private static void Merge(IntPtr source, IntPtr target)
    {
        if (!IsWindow(source) || !IsWindow(target)) return;
        var group = GroupOf(target);
        if (group is null)
        {
            group = new Group { Id = _nextId++, Active = target };
            group.Tabs.Add(target);
            Groups.Add(group);
        }
        if (group.Tabs.Contains(source)) return;

        var oldGroup = GroupOf(source);
        if (oldGroup is not null)
        {
            if (oldGroup.Active == source && oldGroup.Tabs.Count > 1)
            {
                IntPtr next = Neighbour(oldGroup, source);
                oldGroup.Active = next;
                ShownByUs.Add(next);
                ShowWindow(next, SW_SHOWNA);
            }
            oldGroup.Tabs.Remove(source);
            DissolveIfSingle(oldGroup);
        }

        CopyPlacement(group.Active, source);
        WindowList.Activate(source);
        ShowWindow(group.Active, SW_HIDE);
        group.Tabs.Add(source);
        group.Active = source;
        PlaceStrip(group, true);
        EmitState();
    }

    private static void DissolveIfSingle(Group group)
    {
        if (group.Tabs.Count > 1) return;
        foreach (var tab in group.Tabs)
        {
            if (IsWindow(tab) && !IsWindowVisible(tab)) ShowWindow(tab, SW_SHOWNA);
        }
        if (group.Strip != IntPtr.Zero) ShowWindow(group.Strip, SW_HIDE);
        Groups.Remove(group);
    }

    // ---------- geometry ----------

    private static void PlaceStrip(Group group, bool raise)
    {
        if (group.Strip == IntPtr.Zero || !IsWindow(group.Active)) return;
        if (IsIconic(group.Active))
        {
            ShowWindow(group.Strip, SW_HIDE);
            return;
        }
        bool focused = raise && GetForegroundWindow() == group.Active;
        uint flags = SWP_NOACTIVATE | SWP_SHOWWINDOW | (focused ? 0 : SWP_NOZORDER);
        ApplyStripRect(group.Strip, group.Id, StripRect(group.Active), HWND_TOPMOST, flags);
        if (focused)
        {
            group.Topmost = true;
            _raiseLater!.Stop();
            _raiseLater.Start();
        }
    }

    private static void MakeStripTopmost(Group group)
    {
        group.Topmost = true;
        SetWindowPos(group.Strip, HWND_TOPMOST, 0, 0, 0, 0, SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE);
    }

    // Focus moved to `foreground`: every other group's topmost strip drops to just below it,
    // which is still above that strip's own window (the window that had focus until now).
    private static void LowerStripsBelow(IntPtr foreground, Group? focusedGroup)
    {
        foreach (var group in Groups)
        {
            if (group == focusedGroup || !group.Topmost || group.Strip == IntPtr.Zero || group.Strip == foreground) continue;
            group.Topmost = false;
            SetWindowPos(group.Strip, foreground, 0, 0, 0, 0, SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE);
        }
    }

    // The helper moves strips itself so they keep up with a dragged window, but sizing a
    // Chromium window from outside leaves its page short, so size changes go to Electron.
    private static void ApplyStripRect(IntPtr strip, int id, RECT rect, IntPtr insertAfter, uint flags)
    {
        int width = rect.Right - rect.Left;
        int height = rect.Bottom - rect.Top;
        if (!StripSizes.TryGetValue(strip, out var size) || size.Width != width || size.Height != height)
        {
            StripSizes[strip] = (width, height);
            Program.Emit(new { @event = "stripbounds", id, x = rect.Left, y = rect.Top, w = width, h = height });
        }
        SetWindowPos(strip, insertAfter, rect.Left, rect.Top, 0, 0, flags | SWP_NOSIZE);
    }

    // Above the window when there is room; otherwise over the left of its title bar,
    // leaving the minimise, maximise and close buttons clear.
    private static RECT StripRect(IntPtr hwnd)
    {
        var frame = FrameRect(hwnd);
        int height = Scaled(StripHeight, hwnd);
        var work = WorkArea(hwnd);
        if (frame.Top - height >= work.Top)
            return new RECT { Left = frame.Left, Top = frame.Top - height, Right = frame.Right, Bottom = frame.Top };
        int top = Math.Max(frame.Top, work.Top);
        int right = Math.Max(frame.Left + Scaled(200, hwnd), frame.Right - Scaled(CaptionButtonsWidth, hwnd));
        return new RECT { Left = frame.Left, Top = top, Right = right, Bottom = top + height };
    }

    // The visible frame, without the invisible resize borders Windows adds around it.
    private static RECT FrameRect(IntPtr hwnd)
    {
        if (DwmGetWindowAttribute(hwnd, DWMWA_EXTENDED_FRAME_BOUNDS, out RECT frame, Marshal.SizeOf<RECT>()) == 0) return frame;
        return WindowRect(hwnd);
    }

    private static RECT WindowRect(IntPtr hwnd)
    {
        GetWindowRect(hwnd, out var rect);
        return rect;
    }

    private static RECT WorkArea(IntPtr hwnd)
    {
        var info = new MONITORINFO { cbSize = Marshal.SizeOf<MONITORINFO>() };
        GetMonitorInfo(MonitorFromWindow(hwnd, MONITOR_DEFAULTTONEAREST), ref info);
        return info.rcWork;
    }

    private static int Scaled(int value, IntPtr hwnd)
    {
        uint dpi = GetDpiForWindow(hwnd);
        return (int)Math.Round(value * (dpi == 0 ? 96 : dpi) / 96.0);
    }

    private static bool Contains(RECT rect, POINT point) =>
        point.X >= rect.Left && point.X < rect.Right && point.Y >= rect.Top && point.Y < rect.Bottom;

    private static WINDOWPLACEMENT Placement(IntPtr hwnd)
    {
        var placement = new WINDOWPLACEMENT { length = Marshal.SizeOf<WINDOWPLACEMENT>() };
        GetWindowPlacement(hwnd, ref placement);
        return placement;
    }

    // Puts `to` exactly where `from` is (normal rectangle and maximised state) and shows it.
    private static void CopyPlacement(IntPtr from, IntPtr to)
    {
        var source = Placement(from);
        var target = Placement(to);
        target.rcNormalPosition = source.rcNormalPosition;
        target.showCmd = IsZoomed(from) ? SW_SHOWMAXIMIZED : SW_SHOWNORMAL;
        target.flags = 0;
        ShownByUs.Add(to);
        SetWindowPlacement(to, ref target);
    }

    // ---------- state ----------

    private static Group? GroupOf(IntPtr hwnd) => Groups.Find((group) => group.Tabs.Contains(hwnd));

    private static IntPtr Neighbour(Group group, IntPtr hwnd)
    {
        int index = group.Tabs.IndexOf(hwnd);
        if (group.Tabs.Count < 2) return IntPtr.Zero;
        return index + 1 < group.Tabs.Count ? group.Tabs[index + 1] : group.Tabs[index - 1];
    }

    private static void EmitState()
    {
        // Whatever happened, a group's active window must be on screen: a hidden active tab
        // would be a window nobody can reach.
        foreach (var group in Groups)
        {
            if (IsWindow(group.Active) && !IsWindowVisible(group.Active)) ShowWindow(group.Active, SW_SHOWNA);
        }

        Program.Emit(new
        {
            @event = "tabs",
            groups = Groups.Select((group) => new
            {
                id = group.Id,
                active = group.Active.ToInt64().ToString(),
                tabs = group.Tabs.Where(IsWindow).Select(WindowList.Describe).ToList(),
            }).ToList(),
        });
    }

    #region interop

    private const uint EVENT_SYSTEM_FOREGROUND = 0x0003;
    private const uint EVENT_SYSTEM_MOVESIZESTART = 0x000A;
    private const uint EVENT_SYSTEM_MOVESIZEEND = 0x000B;
    private const uint EVENT_SYSTEM_MINIMIZESTART = 0x0016;
    private const uint EVENT_SYSTEM_MINIMIZEEND = 0x0017;
    private const uint EVENT_OBJECT_DESTROY = 0x8001;
    private const uint EVENT_OBJECT_SHOW = 0x8002;
    private const uint EVENT_OBJECT_LOCATIONCHANGE = 0x800B;
    private const uint EVENT_OBJECT_NAMECHANGE = 0x800C;
    private const uint WINEVENT_OUTOFCONTEXT = 0x0000;
    private const uint WINEVENT_SKIPOWNPROCESS = 0x0002;
    private const int OBJID_WINDOW = 0;
    private const int SW_HIDE = 0;
    private const int SW_SHOWNORMAL = 1;
    private const int SW_SHOWMAXIMIZED = 3;
    private const int SW_SHOW = 5;
    private const int SW_SHOWNA = 8;
    private const uint SWP_NOSIZE = 0x0001;
    private const uint SWP_NOMOVE = 0x0002;
    private const uint SWP_NOZORDER = 0x0004;
    private const uint SWP_NOACTIVATE = 0x0010;
    private const uint SWP_SHOWWINDOW = 0x0040;
    private static readonly IntPtr HWND_TOP = IntPtr.Zero;
    private static readonly IntPtr HWND_TOPMOST = new(-1);
    private const uint WM_SYSCOMMAND = 0x0112;
    private const int SC_DRAGMOVE = 0xF012;
    private const int DWMWA_EXTENDED_FRAME_BOUNDS = 9;
    private const uint MONITOR_DEFAULTTONEAREST = 2;

    private delegate void WinEventDelegate(IntPtr hWinEventHook, uint eventType, IntPtr hwnd,
        int idObject, int idChild, uint dwEventThread, uint dwmsEventTime);

    private delegate bool EnumWindowsProc(IntPtr hwnd, IntPtr lParam);

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
    private struct WINDOWPLACEMENT
    {
        public int length;
        public int flags;
        public int showCmd;
        public POINT ptMinPosition;
        public POINT ptMaxPosition;
        public RECT rcNormalPosition;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct MONITORINFO
    {
        public int cbSize;
        public RECT rcMonitor;
        public RECT rcWork;
        public uint dwFlags;
    }

    [DllImport("user32.dll")]
    private static extern IntPtr SetWinEventHook(uint eventMin, uint eventMax, IntPtr hmodWinEventProc,
        WinEventDelegate pfnWinEventProc, uint idProcess, uint idThread, uint dwFlags);

    [DllImport("user32.dll")]
    private static extern bool EnumWindows(EnumWindowsProc lpEnumFunc, IntPtr lParam);

    [DllImport("user32.dll")]
    private static extern bool IsWindow(IntPtr hWnd);

    [DllImport("user32.dll")]
    private static extern bool IsWindowVisible(IntPtr hWnd);

    [DllImport("user32.dll")]
    private static extern bool IsIconic(IntPtr hWnd);

    [DllImport("user32.dll")]
    private static extern bool IsZoomed(IntPtr hWnd);

    [DllImport("user32.dll")]
    private static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);

    [DllImport("user32.dll")]
    private static extern bool SetWindowPos(IntPtr hWnd, IntPtr hWndInsertAfter, int x, int y, int cx, int cy, uint flags);

    [DllImport("user32.dll")]
    private static extern bool GetWindowRect(IntPtr hWnd, out RECT lpRect);

    [DllImport("user32.dll")]
    private static extern bool GetWindowPlacement(IntPtr hWnd, ref WINDOWPLACEMENT placement);

    [DllImport("user32.dll")]
    private static extern bool SetWindowPlacement(IntPtr hWnd, ref WINDOWPLACEMENT placement);

    [DllImport("user32.dll")]
    private static extern bool GetCursorPos(out POINT point);

    [DllImport("user32.dll")]
    private static extern IntPtr GetForegroundWindow();

    [DllImport("user32.dll")]
    private static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint lpdwProcessId);

    [DllImport("user32.dll")]
    private static extern bool PostMessage(IntPtr hWnd, uint msg, IntPtr wParam, IntPtr lParam);

    [DllImport("user32.dll")]
    private static extern uint GetDpiForWindow(IntPtr hwnd);

    [DllImport("user32.dll")]
    private static extern IntPtr MonitorFromWindow(IntPtr hwnd, uint flags);

    [DllImport("user32.dll")]
    private static extern bool GetMonitorInfo(IntPtr monitor, ref MONITORINFO info);

    [DllImport("dwmapi.dll")]
    private static extern int DwmGetWindowAttribute(IntPtr hwnd, int dwAttribute, out RECT pvAttribute, int cbAttribute);

    #endregion
}
