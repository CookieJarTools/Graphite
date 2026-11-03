# Setup

The order to apply Graphite on Windows 11. Make a restore point first; every step is reversible.

## 1. Strip Windows back

- Settings > Personalisation > Colours: Dark mode, Transparency effects **on** (the taskbar, toasts and Files sidebar use acrylic or Mica; the palette stays solid), custom accent `#e3ab4f`, accent on title bars **off** (cards stay grey).
- Settings > Personalisation > Background: Picture, using a dark image of `backdrop` `#141516` with a soft `backdrop-glow` `#25262a` radial in the centre. Solid colour `#141516` works too.
- Right-click desktop > View > untick "Show desktop icons". Move anything stored on the desktop into Documents.
- Settings > Personalisation > Taskbar: Search hidden, Task view off, Widgets off.
- Settings > Personalisation > Start: recommendations, recent files and tips off.
- Settings > System > Notifications: turn off "Suggest ways to get the most out of Windows" and tips; set Do not disturb rules for full-screen apps.

## 2. Install the tools

```
winget install Microsoft.PowerToys
winget install voidtools.Everything
winget install RamenSoftware.Windhawk
winget install Microsoft.WindowsTerminal
winget install AutoHotkey.AutoHotkey
```

Then install Files from files.community (or the Microsoft Store) and a tab tool: Groupy 2 (Stardock) or WindowTabs (GitHub). Check each tool's page for its current winget id.

## 3. GraphiteShell: intro, Home and the search scrim

Windows always has a desktop underneath and does not let you restyle the palette's surroundings, so one small AutoHotkey script does three jobs:

- **Intro:** at sign-in, covers the screen in `backdrop`, fades a greeting and the date in and out, then reveals Home.
- **Home:** whenever no real window is visible (all closed, all minimised, or `Win+D`), opens the Command Palette, so search replaces the desktop.
- **Scrim:** whenever the palette is open over other windows, fades a dark full-screen layer in behind it so its text is always readable, and fades it out when the palette closes.

If Windows "Animation effects" is off, the intro is skipped and the fades are instant.

1. In PowerToys > Command Palette, set the activation shortcut to `Alt+Space`, turn on the Everything, window walker, calculator, web search and shell extensions, and pick the most solid (least see-through) backdrop it offers.
2. Install the Inter font (optional; Segoe UI is used otherwise).
3. Save the script below as `GraphiteShell.ahk`, change `userName`, and run it. Put a shortcut to it in `shell:startup` so it runs, and plays the intro, at sign-in.
4. If Home keeps reopening or the scrim never shows, open Task Manager > Details, find the palette's process name and put it in `launcherProcessNames`.

```autohotkey
#Requires AutoHotkey v2.0
#SingleInstance Force
Persistent

global userName := "Joe"
global launcherHotkey := "!{Space}"
global launcherProcessNames := ["Microsoft.CmdPal.UI.exe", "Flow.Launcher.exe"]
global ignoredWindowClasses := ["Progman", "WorkerW", "Shell_TrayWnd", "Shell_SecondaryTrayWnd", "NotifyIconOverflowWindow", "Windows.UI.Core.CoreWindow"]

global backdropColour := "141516"
global inkColour := "EDEDEC"
global mutedInkColour := "A6A7AA"
global scrimColour := "08080A"
global scrimOpacity := 158

global homeCheckIntervalMilliseconds := 400
global scrimCheckIntervalMilliseconds := 30
global scrimInMilliseconds := 220
global scrimOutMilliseconds := 140

global areAnimationsEnabled := GetAnimationsEnabled()
global wasScreenEmpty := false
global isScrimShown := false
global scrimWindow := CreateOverlayWindow(scrimColour, true)

PlayIntro()
SetTimer(CheckForEmptyScreen, homeCheckIntervalMilliseconds)
SetTimer(UpdateScrim, scrimCheckIntervalMilliseconds)

; ---------- Intro ----------

PlayIntro()
{
    if !areAnimationsEnabled
        return

    backdropWindow := CreateOverlayWindow(backdropColour, false)
    ShowCoveringScreen(backdropWindow, 255)

    greetingWindow := CreateOverlayWindow(backdropColour, false)
    SetPreferredFont(greetingWindow, "s26 w700 c" inkColour)
    greetingWindow.AddText("x0 y" (A_ScreenHeight // 2 - 48) " w" A_ScreenWidth " Center", GetGreeting())
    SetPreferredFont(greetingWindow, "s11 w400 c" mutedInkColour)
    greetingWindow.AddText("x0 y+6 w" A_ScreenWidth " Center", FormatTime(, "dddd d MMMM"))
    ShowOnPrimaryScreen(greetingWindow, 0)

    FadeWindow(greetingWindow, 0, 255, 400)
    Sleep(500)
    FadeWindow(greetingWindow, 255, 0, 250)
    greetingWindow.Destroy()
    FadeWindow(backdropWindow, 255, 0, 350)
    backdropWindow.Destroy()
}

GetGreeting()
{
    hour := Integer(A_Hour)
    partOfDay := hour < 12 ? "morning" : hour < 18 ? "afternoon" : "evening"
    return "Good " partOfDay ", " userName
}

; ---------- Home ----------

CheckForEmptyScreen()
{
    global wasScreenEmpty
    isScreenEmpty := !HasVisibleAppWindow()

    ; Only open on the change to empty, so closing the palette with Escape does not reopen it straight away.
    if (isScreenEmpty && !wasScreenEmpty)
        Send(launcherHotkey)

    wasScreenEmpty := isScreenEmpty
}

HasVisibleAppWindow()
{
    for windowHandle in WinGetList()
    {
        if IsAppWindow(windowHandle)
            return true
    }
    return false
}

IsAppWindow(windowHandle)
{
    try
    {
        if (WinGetTitle(windowHandle) = "")
            return false
        if (WinGetMinMax(windowHandle) = -1)
            return false
        if !(WinGetStyle(windowHandle) & 0x10000000)
            return false
        ; Tool windows (floating palettes, our own overlays) never count as a real window.
        if (WinGetExStyle(windowHandle) & 0x80)
            return false
        if IsInList(WinGetClass(windowHandle), ignoredWindowClasses)
            return false
        if IsInList(WinGetProcessName(windowHandle), launcherProcessNames)
            return false
        if IsCloaked(windowHandle)
            return false
        return true
    }
    catch
        return false
}

; Suspended Store apps and windows on other virtual desktops are "cloaked": present but not drawn.
IsCloaked(windowHandle)
{
    cloakedValue := 0
    DllCall("dwmapi\DwmGetWindowAttribute", "Ptr", windowHandle, "UInt", 14, "UInt*", &cloakedValue, "UInt", 4)
    return cloakedValue != 0
}

; ---------- Scrim ----------

UpdateScrim()
{
    isLauncherActive := IsLauncherActive()

    ; On the Home screen nothing sits behind the palette, so the scrim is only used over real windows.
    if (isLauncherActive && !isScrimShown && HasVisibleAppWindow())
        ShowScrim()
    else if (!isLauncherActive && isScrimShown)
        HideScrim()
}

IsLauncherActive()
{
    try
        return IsInList(WinGetProcessName("A"), launcherProcessNames)
    catch
        return false
}

ShowScrim()
{
    global isScrimShown := true
    launcherHandle := WinExist("A")
    ShowCoveringScreen(scrimWindow, 0)

    ; Slot the scrim directly beneath the palette (no move, no resize, no activation) so everything else sits under it.
    DllCall("SetWindowPos", "Ptr", scrimWindow.Hwnd, "Ptr", launcherHandle, "Int", 0, "Int", 0, "Int", 0, "Int", 0, "UInt", 0x0013)
    FadeWindow(scrimWindow, 0, scrimOpacity, scrimInMilliseconds)
}

HideScrim()
{
    global isScrimShown := false
    FadeWindow(scrimWindow, scrimOpacity, 0, scrimOutMilliseconds)
    scrimWindow.Hide()
}

; ---------- Shared ----------

CreateOverlayWindow(backgroundColour, isClickThrough)
{
    options := "+AlwaysOnTop -Caption +ToolWindow -DPIScale"
    if isClickThrough
        options .= " +E0x20"
    overlayWindow := Gui(options)
    overlayWindow.BackColor := backgroundColour
    overlayWindow.MarginX := 0
    overlayWindow.MarginY := 0
    return overlayWindow
}

; Sets the opacity while still hidden, so the overlay never flashes at full strength for a frame.
ShowWithOpacity(overlayWindow, position, opacity)
{
    DetectHiddenWindows(true)
    WinSetTransparent(opacity, overlayWindow.Hwnd)
    overlayWindow.Show(position " NoActivate")
}

ShowCoveringScreen(overlayWindow, opacity)
{
    ShowWithOpacity(overlayWindow, "x" SysGet(76) " y" SysGet(77) " w" SysGet(78) " h" SysGet(79), opacity)
}

ShowOnPrimaryScreen(overlayWindow, opacity)
{
    ShowWithOpacity(overlayWindow, "x0 y0 w" A_ScreenWidth " h" A_ScreenHeight, opacity)
}

; If Inter is not installed AutoHotkey keeps the previous face, so Segoe UI is set first as the fallback.
SetPreferredFont(overlayWindow, fontOptions)
{
    overlayWindow.SetFont(fontOptions, "Segoe UI Variable Display")
    overlayWindow.SetFont(fontOptions, "Inter")
}

FadeWindow(overlayWindow, fromOpacity, toOpacity, durationMilliseconds)
{
    if !areAnimationsEnabled
    {
        WinSetTransparent(toOpacity, overlayWindow.Hwnd)
        return
    }
    startTime := A_TickCount
    loop
    {
        progress := Min((A_TickCount - startTime) / durationMilliseconds, 1)
        easedProgress := 1 - (1 - progress) ** 3
        WinSetTransparent(Round(fromOpacity + (toOpacity - fromOpacity) * easedProgress), overlayWindow.Hwnd)
        if (progress >= 1)
            break
        Sleep(10)
    }
}

GetAnimationsEnabled()
{
    isEnabled := 1
    DllCall("SystemParametersInfo", "UInt", 0x1042, "UInt", 0, "Int*", &isEnabled, "UInt", 0)
    return isEnabled != 0
}

IsInList(value, list)
{
    for listItem in list
    {
        if (value = listItem)
            return true
    }
    return false
}
```

## 4. Windows and tabs

- **FancyZones:** a wide main zone plus a right column split in two. Zone spacing `8`. Highlight `#3b3c40`, inactive `#232427`, border `#7a7c82`. Hold Shift to snap.
- **Workspaces:** save each working layout once windows are placed.
- **Tabs:** style the tab tool to the TabStrip component: tabs live inside the title strip, active tab `surface-200` with `ink` text, inactive `ink-muted`, `radius-sm`.

## 5. Taskbar

Windhawk > Windows 11 Taskbar Styler, aiming for the Taskbar component:

- Floating: margin `8` from the bottom and sides, corner radius `16`.
- Background: acrylic over `surface-200` at about 80% opacity, 1px `glass-edge` border.
- Height `48`, icons centred, labels on for running windows if your build supports them.
- Auto-hide when a window is maximised (Windhawk "Taskbar auto-hide when maximized" mod).

Add one mod at a time, restart Explorer, check, then add the next.

## 6. Toasts

Native toasts cannot take arbitrary CSS, so get them close: Dark mode and transparency handle the card; a Windhawk notification styler mod (search "notification" in Windhawk) can set radius `12`, padding and the `glass-edge` border. Keep at most two actions per toast and turn off sounds for all but calendar and messages.

## 7. Files

In Files > Settings > Appearance: Dark theme, backdrop Mica (gives the translucent sidebar), custom background colour `#232427`. Use the details layout with Type, Size and Date modified columns; pick its compact or default spacing to match Compact or Comfy. Tabs are on by default, and a tab can be dragged out into its own window. Set Files as the default file manager in its own settings if you want `Win+E` to open it.

## 8. Windows Terminal scheme

Add to `schemes` in settings.json; font `JetBrains Mono` or `Cascadia Code` 11pt, padding `16`, acrylic off.

```json
{
  "name": "Graphite",
  "background": "#232427",
  "foreground": "#EDEDEC",
  "cursorColor": "#E3AB4F",
  "selectionBackground": "#40331F",
  "black": "#2E2F32",
  "red": "#EC8276",
  "green": "#97C582",
  "yellow": "#E3AB4F",
  "blue": "#8EA6C6",
  "purple": "#B39AC2",
  "cyan": "#82B9B1",
  "white": "#CACAC8",
  "brightBlack": "#7A7C82",
  "brightRed": "#F29E94",
  "brightGreen": "#ADD49B",
  "brightYellow": "#F0C47E",
  "brightBlue": "#AABFDA",
  "brightPurple": "#C9B4D6",
  "brightCyan": "#9DCCC5",
  "brightWhite": "#F6F6F5"
}
```
