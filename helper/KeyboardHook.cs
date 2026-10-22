using System.Runtime.InteropServices;

namespace WinKeyHelper;

/// <summary>
/// Low-level keyboard hook that intercepts a *bare* Windows-key press (no other key
/// while held). Win+R, Win+L, Win+Shift+S etc. pass through untouched.
///
/// The real Start menu opens on the *release* of a bare Win key. When we see that
/// release we swallow it, inject a harmless dummy key (VK 0xE8, unassigned) and then
/// re-inject the Win key-up. Windows sees Win+dummy — a combo — so its Start menu
/// never opens, and keyboard state stays consistent.
///
/// It also replaces Alt+Tab when the switcher is enabled: Tab with Alt held opens the
/// switcher instead of Windows' own, and while it is open every non-modifier key is
/// swallowed and reported (next, prev, close, cancel, commit). Releasing Alt commits;
/// that release gets the same dummy-key treatment so the target app's menu bar does
/// not light up from a lone Alt press.
///
/// Alt+Space (when the palette is enabled) opens the command palette instead of the
/// window menu, again with a dummy key before the Alt release.
///
/// Win+E (when Files is enabled) opens Files instead of Explorer. The E is swallowed,
/// so the Win release also gets the dummy key, or Windows would see a bare Win press.
/// </summary>
internal static class KeyboardHook
{
    private static IntPtr _hookId = IntPtr.Zero;
    private static LowLevelKeyboardProc? _proc; // kept referenced so the GC can't collect the delegate
    private static Action? _onBareWinKey;
    private static bool _winDown;
    private static bool _comboUsed;
    private static Action<string>? _onSwitcher;
    private static bool _switcherOpen;
    private static Action? _onPalette;
    private static bool _altSpaceUsed;
    private static Action? _onWinE;
    private static bool _winComboSwallowed;

    public static void Install(Action onBareWinKey, Action<string> onSwitcher, Action onPalette, Action onWinE)
    {
        if (_hookId != IntPtr.Zero) return;
        _onBareWinKey = onBareWinKey;
        _onSwitcher = onSwitcher;
        _onPalette = onPalette;
        _onWinE = onWinE;
        _proc = HookCallback;
        _hookId = SetWindowsHookEx(WH_KEYBOARD_LL, _proc, GetModuleHandle(null), 0);
    }

    private static IntPtr HookCallback(int nCode, IntPtr wParam, IntPtr lParam)
    {
        if (nCode < 0)
            return CallNextHookEx(_hookId, nCode, wParam, lParam);

        var kb = Marshal.PtrToStructure<KBDLLHOOKSTRUCT>(lParam);

        // Ignore injected events (including our own re-injections below).
        if ((kb.flags & LLKHF_INJECTED) != 0)
            return CallNextHookEx(_hookId, nCode, wParam, lParam);

        int msg = (int)wParam;
        int vk = (int)kb.vkCode;
        bool isWin = vk == VK_LWIN || vk == VK_RWIN;

        if (HandleSwitcherKey(msg, vk, kb.flags) || HandlePaletteKey(msg, vk, kb.flags))
            return (IntPtr)1;

        if (_winDown && vk == VK_E && Program.FilesOnWinE)
        {
            if (msg == WM_KEYDOWN || msg == WM_SYSKEYDOWN)
            {
                if (!_winComboSwallowed) _onWinE?.Invoke(); // key repeat opens only one window
                _winComboSwallowed = true;
                _comboUsed = true;
            }
            return (IntPtr)1;
        }

        if (msg == WM_KEYDOWN || msg == WM_SYSKEYDOWN)
        {
            if (isWin) { _winDown = true; _comboUsed = false; _winComboSwallowed = false; }
            else if (_winDown) { _comboUsed = true; }
        }
        else if (msg == WM_KEYUP || msg == WM_SYSKEYUP)
        {
            if (isWin && _winComboSwallowed)
            {
                _winDown = false;
                _winComboSwallowed = false;
                SendDummyAndWinUp(vk);
                return (IntPtr)1;
            }
            if (isWin)
            {
                bool bare = _winDown && !_comboUsed;
                _winDown = false;
                if (bare && Program.Enabled)
                {
                    SendDummyAndWinUp(vk);
                    _onBareWinKey?.Invoke();
                    return (IntPtr)1; // swallow the real key-up
                }
            }
        }

        return CallNextHookEx(_hookId, nCode, wParam, lParam);
    }

    /// <summary>Returns true when the key belongs to the switcher and must be swallowed.</summary>
    private static bool HandleSwitcherKey(int msg, int vk, uint flags)
    {
        bool isDown = msg == WM_KEYDOWN || msg == WM_SYSKEYDOWN;
        bool isAlt = vk == VK_MENU || vk == VK_LMENU || vk == VK_RMENU;

        if (!_switcherOpen)
        {
            bool altHeld = (flags & LLKHF_ALTDOWN) != 0;
            bool ctrlHeld = (GetAsyncKeyState(VK_CONTROL) & 0x8000) != 0;
            if (!Program.SwitcherEnabled || !isDown || vk != VK_TAB || !altHeld || ctrlHeld) return false;
            _switcherOpen = true;
            _onSwitcher?.Invoke(ShiftHeld() ? "open-reverse" : "open");
            return true;
        }

        if (isAlt)
        {
            if (isDown) return true;
            _switcherOpen = false;
            SendDummyAndKeyUp(vk);
            _onSwitcher?.Invoke("commit");
            return true;
        }

        if (vk is VK_LSHIFT or VK_RSHIFT or VK_SHIFT or VK_LCONTROL or VK_RCONTROL or VK_CONTROL or VK_LWIN or VK_RWIN)
            return false;
        if (!isDown) return true;

        switch (vk)
        {
            case VK_TAB: _onSwitcher?.Invoke(ShiftHeld() ? "prev" : "next"); break;
            case VK_LEFT or VK_UP: _onSwitcher?.Invoke("prev"); break;
            case VK_RIGHT or VK_DOWN: _onSwitcher?.Invoke("next"); break;
            case VK_W: _onSwitcher?.Invoke("close"); break;
            case VK_ESCAPE:
                _switcherOpen = false;
                _onSwitcher?.Invoke("cancel");
                break;
            case VK_RETURN:
                _switcherOpen = false;
                _onSwitcher?.Invoke("commit");
                break;
        }
        return true;
    }

    /// <summary>Returns true when the key is Alt+Space (or the Alt release after it) and must be swallowed.</summary>
    private static bool HandlePaletteKey(int msg, int vk, uint flags)
    {
        bool isDown = msg == WM_KEYDOWN || msg == WM_SYSKEYDOWN;
        bool isAlt = vk == VK_MENU || vk == VK_LMENU || vk == VK_RMENU;

        if (isAlt && !isDown && _altSpaceUsed)
        {
            _altSpaceUsed = false;
            SendDummyAndKeyUp(vk);
            return true;
        }

        if (vk != VK_SPACE || !Program.PaletteEnabled) return false;
        bool altHeld = (flags & LLKHF_ALTDOWN) != 0;
        bool ctrlHeld = (GetAsyncKeyState(VK_CONTROL) & 0x8000) != 0;
        if (!altHeld || ctrlHeld || _winDown) return false;

        // Holding Space repeats the key-down; only the first press opens the palette.
        if (isDown && !_altSpaceUsed) _onPalette?.Invoke();
        if (isDown) _altSpaceUsed = true;
        return true;
    }

    /// <summary>Electron closed the switcher itself (a click on a card): stop capturing keys.</summary>
    public static void EndSwitcher() => _switcherOpen = false;

    private static bool ShiftHeld() => (GetAsyncKeyState(VK_SHIFT) & 0x8000) != 0;

    private static void SendDummyAndWinUp(int winVk) => SendDummyAndKeyUp(winVk);

    private static void SendDummyAndKeyUp(int vk)
    {
        var inputs = new INPUT[3];
        inputs[0] = KeyInput(VK_DUMMY, 0);
        inputs[1] = KeyInput(VK_DUMMY, KEYEVENTF_KEYUP);
        inputs[2] = KeyInput((ushort)vk, KEYEVENTF_KEYUP);
        SendInput((uint)inputs.Length, inputs, Marshal.SizeOf<INPUT>());
    }

    private static INPUT KeyInput(ushort vk, uint flags) => new()
    {
        type = INPUT_KEYBOARD,
        U = new InputUnion { ki = new KEYBDINPUT { wVk = vk, dwFlags = flags } }
    };

    #region interop

    private const int WH_KEYBOARD_LL = 13;
    private const int WM_KEYDOWN = 0x0100;
    private const int WM_KEYUP = 0x0101;
    private const int WM_SYSKEYDOWN = 0x0104;
    private const int WM_SYSKEYUP = 0x0105;
    private const int VK_LWIN = 0x5B;
    private const int VK_RWIN = 0x5C;
    private const int VK_TAB = 0x09;
    private const int VK_SPACE = 0x20;
    private const int VK_E = 0x45;
    private const int VK_RETURN = 0x0D;
    private const int VK_SHIFT = 0x10;
    private const int VK_CONTROL = 0x11;
    private const int VK_MENU = 0x12;
    private const int VK_ESCAPE = 0x1B;
    private const int VK_LEFT = 0x25;
    private const int VK_UP = 0x26;
    private const int VK_RIGHT = 0x27;
    private const int VK_DOWN = 0x28;
    private const int VK_W = 0x57;
    private const int VK_LSHIFT = 0xA0;
    private const int VK_RSHIFT = 0xA1;
    private const int VK_LCONTROL = 0xA2;
    private const int VK_RCONTROL = 0xA3;
    private const int VK_LMENU = 0xA4;
    private const int VK_RMENU = 0xA5;
    private const ushort VK_DUMMY = 0xE8; // unassigned virtual key
    private const uint LLKHF_INJECTED = 0x10;
    private const uint LLKHF_ALTDOWN = 0x20;
    private const uint KEYEVENTF_KEYUP = 0x0002;
    private const uint INPUT_KEYBOARD = 1;

    private delegate IntPtr LowLevelKeyboardProc(int nCode, IntPtr wParam, IntPtr lParam);

    [StructLayout(LayoutKind.Sequential)]
    private struct KBDLLHOOKSTRUCT
    {
        public uint vkCode;
        public uint scanCode;
        public uint flags;
        public uint time;
        public IntPtr dwExtraInfo;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct INPUT
    {
        public uint type;
        public InputUnion U;
    }

    [StructLayout(LayoutKind.Explicit)]
    private struct InputUnion
    {
        [FieldOffset(0)] public KEYBDINPUT ki;
        [FieldOffset(0)] public MOUSEINPUT mi;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct KEYBDINPUT
    {
        public ushort wVk;
        public ushort wScan;
        public uint dwFlags;
        public uint time;
        public IntPtr dwExtraInfo;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct MOUSEINPUT
    {
        public int dx;
        public int dy;
        public uint mouseData;
        public uint dwFlags;
        public uint time;
        public IntPtr dwExtraInfo;
    }

    [DllImport("user32.dll", SetLastError = true)]
    private static extern IntPtr SetWindowsHookEx(int idHook, LowLevelKeyboardProc lpfn, IntPtr hMod, uint dwThreadId);

    [DllImport("user32.dll")]
    private static extern IntPtr CallNextHookEx(IntPtr hhk, int nCode, IntPtr wParam, IntPtr lParam);

    [DllImport("kernel32.dll", CharSet = CharSet.Unicode)]
    private static extern IntPtr GetModuleHandle(string? lpModuleName);

    [DllImport("user32.dll", SetLastError = true)]
    private static extern uint SendInput(uint nInputs, INPUT[] pInputs, int cbSize);

    [DllImport("user32.dll")]
    private static extern short GetAsyncKeyState(int vKey);

    #endregion
}
