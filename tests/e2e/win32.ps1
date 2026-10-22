# Small Win32 queries and actions for the end-to-end tests. Prints one JSON value.
#   find <title>          handle of the top-level window with exactly this title (0 if none)
#   state <hwnd>          { visible, iconic, zoomed, left, top, width, height }
#   maximize <hwnd>       maximise and focus it
#   restore <hwnd>        restore it
#   tray                  { visible, autoHide } for the Windows taskbar
#   errordialogs          number of visible windows titled "Error" (Electron's crash dialog)
#   cursor <x,y>          moves the real mouse pointer there
param([string]$Command, [string]$Argument = '')

Add-Type @'
using System; using System.Text; using System.Runtime.InteropServices;
public static class E2E {
  public delegate bool EnumProc(IntPtr h, IntPtr l);
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int L, T, R, B; }
  [StructLayout(LayoutKind.Sequential)] public struct APPBARDATA { public int cbSize; public IntPtr hWnd; public uint msg; public uint edge; public RECT rc; public IntPtr lParam; }
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc p, IntPtr l);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr h);
  [DllImport("user32.dll")] public static extern bool IsZoomed(IntPtr h);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern IntPtr FindWindow(string c, string n);
  [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern IntPtr FindWindowEx(IntPtr p, IntPtr a, string c, string n);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint p);
  // Explorer's taskbar; the helper keeps a hidden window of the same class (TrayHost.cs).
  public static IntPtr ExplorerTray() {
    IntPtr w = IntPtr.Zero;
    while ((w = FindWindowEx(IntPtr.Zero, w, "Shell_TrayWnd", null)) != IntPtr.Zero) {
      uint pid; GetWindowThreadProcessId(w, out pid);
      try { if (System.Diagnostics.Process.GetProcessById((int)pid).ProcessName == "explorer") return w; } catch { }
    }
    return IntPtr.Zero;
  }
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int c);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern void SwitchToThisWindow(IntPtr h, bool b);
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
  [DllImport("shell32.dll")] public static extern IntPtr SHAppBarMessage(uint m, ref APPBARDATA d);
  public static string Title(IntPtr h) { var sb = new StringBuilder(512); GetWindowText(h, sb, 512); return sb.ToString(); }
  public static long Find(string title) {
    long found = 0;
    EnumWindows((h, l) => { if (Title(h) == title) { found = h.ToInt64(); return false; } return true; }, IntPtr.Zero);
    return found;
  }
  public static int CountVisible(string title) {
    int count = 0;
    EnumWindows((h, l) => { if (IsWindowVisible(h) && Title(h) == title) count++; return true; }, IntPtr.Zero);
    return count;
  }
}
'@

function Handle($text) { [IntPtr][long]$text }

switch ($Command) {
  'find' { [E2E]::Find($Argument) | ConvertTo-Json -Compress }
  'state' {
    $h = Handle $Argument
    $r = New-Object E2E+RECT
    [E2E]::GetWindowRect($h, [ref]$r) | Out-Null
    @{ visible = [E2E]::IsWindowVisible($h); iconic = [E2E]::IsIconic($h); zoomed = [E2E]::IsZoomed($h); left = $r.L; top = $r.T; width = $r.R - $r.L; height = $r.B - $r.T } | ConvertTo-Json -Compress
  }
  'maximize' { $h = Handle $Argument; [E2E]::ShowWindow($h, 3) | Out-Null; [E2E]::SwitchToThisWindow($h, $true); 'true' }
  'restore' { [E2E]::ShowWindow((Handle $Argument), 9) | Out-Null; 'true' }
  'tray' {
    $data = New-Object E2E+APPBARDATA
    $data.cbSize = [Runtime.InteropServices.Marshal]::SizeOf($data)
    $state = [E2E]::SHAppBarMessage(4, [ref]$data).ToInt64()
    @{ visible = [E2E]::IsWindowVisible([E2E]::ExplorerTray()); autoHide = (($state -band 1) -ne 0) } | ConvertTo-Json -Compress
  }
  'errordialogs' { [E2E]::CountVisible('Error') | ConvertTo-Json -Compress }
  'cursor' { $p = $Argument.Split(','); [E2E]::SetCursorPos([int]$p[0], [int]$p[1]) | ConvertTo-Json -Compress }
  default { throw "unknown command $Command" }
}
