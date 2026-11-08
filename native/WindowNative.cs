using System;
using System.Diagnostics;
using System.Threading;
using System.Collections.Concurrent;
using System.Collections.Generic;
using System.Runtime.InteropServices;
namespace SysMonGlass {
    public static class Native {
        [StructLayout(LayoutKind.Sequential)] public struct Margins { public int left, right, top, bottom; }
        [StructLayout(LayoutKind.Sequential)] public struct AccentPolicy { public int state, flags, color, animation; }
        [StructLayout(LayoutKind.Sequential)] public struct CompositionData { public int attribute; public IntPtr data; public int size; }
        [DllImport("dwmapi.dll")] public static extern int DwmSetWindowAttribute(IntPtr hwnd, int attribute, ref int value, int size);
        [DllImport("dwmapi.dll")] public static extern int DwmExtendFrameIntoClientArea(IntPtr hwnd, ref Margins margins);
        [DllImport("user32.dll")] private static extern int SetWindowCompositionAttribute(IntPtr hwnd, ref CompositionData data);
        [DllImport("user32.dll")] public static extern bool DestroyIcon(IntPtr icon);
        [DllImport("user32.dll")] public static extern bool SetProcessDpiAwarenessContext(IntPtr value);
        [DllImport("user32.dll")] public static extern IntPtr SetThreadDpiAwarenessContext(IntPtr value);
        [DllImport("kernel32.dll")] private static extern void SetLastError(uint error);
        [DllImport("user32.dll", SetLastError=true)] private static extern IntPtr GetWindowLongPtr(IntPtr hwnd, int index);
        [DllImport("user32.dll", SetLastError=true)] private static extern IntPtr SetWindowLongPtr(IntPtr hwnd, int index, IntPtr value);
        [DllImport("user32.dll", SetLastError=true)] private static extern bool SetWindowPos(IntPtr hwnd, IntPtr insertAfter, int x, int y, int cx, int cy, uint flags);
        [DllImport("user32.dll")] private static extern IntPtr GetParent(IntPtr child);
        // --- Chrome hit-test subclass -------------------------------------------------
        // A PowerShell HwndSource hook cannot control hit-testing: its `handled` ref
        // never reaches the native layer, so WPF discards the hook's return value.
        // Subclassing the WndProc is the only reliable way to claim the window rim
        // for dragging, and it also lets us swallow the caption double-click.
        [DllImport("user32.dll", EntryPoint="CallWindowProcW")] private static extern IntPtr CallWindowProc(IntPtr previous, IntPtr hwnd, uint msg, IntPtr wParam, IntPtr lParam);
        [DllImport("user32.dll")] private static extern bool IsWindowVisible(IntPtr hwnd);
        private delegate IntPtr WndProcDelegate(IntPtr hwnd, uint msg, IntPtr wParam, IntPtr lParam);
        private static WndProcDelegate chromeProc;
        private static IntPtr chromePrevious;
        private static IntPtr chromeHwnd;
        private static volatile bool chromeEnabled;
        private static uint lastSysCommand;
        /// <summary>Raised with true when a modal MOVE begins, false when it ends.</summary>
        public static Action<bool> DragPhaseChanged;
        public static bool ChromeDragEnabled { get { return chromeEnabled; } }
        /// <summary>Claim the 8px window rim as caption and swallow caption double-clicks.</summary>
        private static IntPtr ChromeWndProc(IntPtr hwnd, uint msg, IntPtr wParam, IntPtr lParam) {
            // Move lifecycle: lets the UI freeze expensive effects for the duration
            // of a drag. Resizes are deliberately excluded.
            if (msg == 0x0112) { lastSysCommand = (uint)(wParam.ToInt64() & 0xFFF0); }
            else if (msg == 0x0231 || msg == 0x0232) {
                bool isMove = lastSysCommand == 0xF010;
                var callback = DragPhaseChanged;
                if (isMove && callback != null) {
                    try { callback(msg == 0x0231); } catch { /* never break the message loop */ }
                }
            }
            if (chromeEnabled && (msg == 0x0084 || msg == 0x00A3) && IsWindowVisible(hwnd)) {
                if (msg == 0x00A3) return IntPtr.Zero; // never maximize this borderless panel
                long packed = lParam.ToInt64();
                int x = (short)(packed & 0xFFFF);
                int y = (short)((packed >> 16) & 0xFFFF);
                ScreenRect rect;
                if (GetWindowRect(hwnd, out rect)) {
                    int cx = x - rect.Left, cy = y - rect.Top;
                    int width = rect.Right - rect.Left, height = rect.Bottom - rect.Top;
                    bool inGrip = cx >= width - 64 && cy >= height - 64;
                    bool onRim = cx < 8 || cx >= width - 8 || cy < 8 || cy >= height - 8;
                    if (onRim && !inGrip) return new IntPtr(2); // HTCAPTION
                }
            }
            return CallWindowProc(chromePrevious, hwnd, msg, wParam, lParam);
        }
        public static void InstallChromeHitTest(IntPtr hwnd) {
            if (hwnd == IntPtr.Zero || hwnd == chromeHwnd) return;
            chromeProc = ChromeWndProc; // keep the delegate alive for the process lifetime
            chromePrevious = SetWindowLongPtr(hwnd, -4, Marshal.GetFunctionPointerForDelegate(chromeProc));
            if (chromePrevious == IntPtr.Zero) throw new InvalidOperationException("Unable to subclass the window procedure.");
            chromeHwnd = hwnd;
        }
        public static void SetChromeDragEnabled(bool enabled) { chromeEnabled = enabled; }
        /// <summary>Toggle the blurred backdrop. Dropping it during a drag removes the
        /// per-step blur recomposition; the window's own gradient stays visible.</summary>
        public static bool SetBackdropBlur(IntPtr hwnd, bool enabled, bool light) {
            if (hwnd == IntPtr.Zero) return false;
            if (!enabled) return ApplyAccent(hwnd, 0, 0);
            return ApplyAccent(hwnd, 4, light ? 0xB8EEF3FAu : 0x99241D18u);
        }
        private delegate bool EnumerateWindow(IntPtr hwnd, IntPtr parameter);
        [DllImport("user32.dll")] private static extern bool EnumWindows(EnumerateWindow callback, IntPtr parameter);
        [DllImport("user32.dll", CharSet=CharSet.Unicode)] private static extern IntPtr FindWindowEx(IntPtr parent, IntPtr after, string className, string name);
        public static IntPtr GetDesktopIconList() {
            IntPtr result=IntPtr.Zero;
            EnumWindows((top, parameter) => {
                IntPtr view=FindWindowEx(top,IntPtr.Zero,"SHELLDLL_DefView",null);
                if(view != IntPtr.Zero) {
                    result=FindWindowEx(view,IntPtr.Zero,"SysListView32",null);
                    if(result != IntPtr.Zero) return false;
                }
                return true;
            },IntPtr.Zero);
            return result;
        }
        private static void WriteWindowLong(IntPtr hwnd, int index, long value) {
            SetLastError(0);
            IntPtr previous=SetWindowLongPtr(hwnd, index, new IntPtr(value));
            int error=Marshal.GetLastWin32Error();
            if(previous == IntPtr.Zero && error != 0) throw new InvalidOperationException("SetWindowLongPtr failed: "+error);
        }
        public static long GetExtendedStyle(IntPtr hwnd) {
            SetLastError(0);
            IntPtr value=GetWindowLongPtr(hwnd, -20);
            int error=Marshal.GetLastWin32Error();
            if(value == IntPtr.Zero && error != 0) throw new InvalidOperationException("GetWindowLongPtr failed: "+error);
            return value.ToInt64();
        }
        [StructLayout(LayoutKind.Sequential)] public struct ScreenPoint { public int X, Y; }
        [StructLayout(LayoutKind.Sequential)] public struct ScreenRect { public int Left, Top, Right, Bottom; }
        [DllImport("user32.dll")] private static extern bool GetWindowRect(IntPtr hwnd, out ScreenRect rect);
        [DllImport("user32.dll")] private static extern bool GetCursorPos(out ScreenPoint point);
        [DllImport("user32.dll")] private static extern bool ScreenToClient(IntPtr hwnd, ref ScreenPoint point);
        public static ScreenRect GetWindowBounds(IntPtr hwnd) { ScreenRect rect; if(!GetWindowRect(hwnd,out rect)) throw new InvalidOperationException("GetWindowRect failed."); return rect; }
        public static ScreenPoint GetCursorPosition() { ScreenPoint point; if(!GetCursorPos(out point)) throw new InvalidOperationException("GetCursorPos failed."); return point; }
        public static void SetScreenPosition(IntPtr hwnd, int x, int y) {
            IntPtr parent=GetParent(hwnd); var point=new ScreenPoint { X=x, Y=y };
            if(parent != IntPtr.Zero) ScreenToClient(parent, ref point);
            if(!SetWindowPos(hwnd,IntPtr.Zero,point.X,point.Y,0,0,0x0001|0x0004|0x0010))
                throw new InvalidOperationException("Unable to move desktop window.");
        }
        [StructLayout(LayoutKind.Sequential)] public struct IconRect { public int Left,Top,Right,Bottom; }
        [DllImport("gdi32.dll")] private static extern IntPtr CreateRectRgn(int left,int top,int right,int bottom);
        [DllImport("gdi32.dll")] private static extern int CombineRgn(IntPtr destination,IntPtr first,IntPtr second,int mode);
        [DllImport("gdi32.dll")] private static extern bool DeleteObject(IntPtr obj);
        [DllImport("user32.dll")] private static extern int SetWindowRgn(IntPtr hwnd,IntPtr region,bool redraw);
        public static void ClearDesktopMask(IntPtr hwnd) { SetWindowRgn(hwnd,IntPtr.Zero,true); }
        public static void SetDesktopEmptyRegion(IntPtr hwnd) {
            IntPtr region=CreateRectRgn(0,0,0,0);
            if(SetWindowRgn(hwnd,region,true) == 0) { DeleteObject(region); throw new InvalidOperationException("Unable to hide the widget region safely."); }
        }
        public static void SetDesktopIconMask(IntPtr hwnd,IconRect[] icons) {
            var bounds=GetWindowBounds(hwnd); int width=bounds.Right-bounds.Left, height=bounds.Bottom-bounds.Top;
            IntPtr region=CreateRectRgn(0,0,width,height);
            try {
                foreach(var icon in icons) {
                    int left=Math.Max(0,icon.Left-bounds.Left), top=Math.Max(0,icon.Top-bounds.Top);
                    int right=Math.Min(width,icon.Right-bounds.Left), bottom=Math.Min(height,icon.Bottom-bounds.Top);
                    if(right <= left || bottom <= top) continue;
                    IntPtr hole=CreateRectRgn(left,top,right,bottom);
                    CombineRgn(region,region,hole,4); // RGN_DIFF: desktop icons remain visible and clickable.
                    DeleteObject(hole);
                }
                if(SetWindowRgn(hwnd,region,true) == 0) throw new InvalidOperationException("SetWindowRgn failed.");
            } catch { DeleteObject(region); throw; }
        }
        // Interaction model: the window exists only inside its cards, minus icon
        // holes. Clicks on cards reach WPF normally; gaps fall through to desktop.
        public static void SetCardRegion(IntPtr hwnd,IconRect[] cards,IconRect[] icons) {
            var bounds=GetWindowBounds(hwnd); int width=bounds.Right-bounds.Left, height=bounds.Bottom-bounds.Top;
            IntPtr region=CreateRectRgn(0,0,0,0);
            try {
                if(cards != null) foreach(var card in cards) {
                    int left=Math.Max(0,card.Left-bounds.Left), top=Math.Max(0,card.Top-bounds.Top);
                    int right=Math.Min(width,card.Right-bounds.Left), bottom=Math.Min(height,card.Bottom-bounds.Top);
                    if(right <= left || bottom <= top) continue;
                    IntPtr rect=CreateRectRgn(left,top,right,bottom);
                    CombineRgn(region,region,rect,2); // RGN_OR
                    DeleteObject(rect);
                }
                if(icons != null) foreach(var icon in icons) {
                    int left=Math.Max(0,icon.Left-bounds.Left), top=Math.Max(0,icon.Top-bounds.Top);
                    int right=Math.Min(width,icon.Right-bounds.Left), bottom=Math.Min(height,icon.Bottom-bounds.Top);
                    if(right <= left || bottom <= top) continue;
                    IntPtr hole=CreateRectRgn(left,top,right,bottom);
                    CombineRgn(region,region,hole,4); // RGN_DIFF keeps icons visible.
                    DeleteObject(hole);
                }
                if(SetWindowRgn(hwnd,region,true) == 0) throw new InvalidOperationException("SetWindowRgn failed.");
            } catch { DeleteObject(region); throw; }
        }
        public static void SetWindowBounds(IntPtr hwnd, int x, int y, int width, int height) {
            IntPtr parent=GetParent(hwnd); var point=new ScreenPoint { X=x, Y=y };
            if(parent != IntPtr.Zero) ScreenToClient(parent,ref point);
            if(!SetWindowPos(hwnd,IntPtr.Zero,point.X,point.Y,width,height,0x0004|0x0010))
                throw new InvalidOperationException("Unable to resize the window.");
        }
        public static void SetTopmost(IntPtr hwnd, bool enabled) {
            if(!SetWindowPos(hwnd,new IntPtr(enabled ? -1 : -2),0,0,0,0,0x0001|0x0002|0x0010))
                throw new InvalidOperationException("Unable to set topmost: "+Marshal.GetLastWin32Error());
        }
        public static void SetDesktopMode(IntPtr hwnd, bool enabled) {
            // Cards stay interactive: the window region is clipped to the card
            // shapes instead of making the whole window click-through.
            const long NoActivate=0x08000000, ClickThrough=0x20;
            long style=GetExtendedStyle(hwnd);
            style=(style | NoActivate) & ~ClickThrough;
            if(!enabled) style&=~NoActivate;
            WriteWindowLong(hwnd,-20,style);
            long expected=enabled ? NoActivate : 0;
            if((GetExtendedStyle(hwnd) & (NoActivate)) != expected) throw new InvalidOperationException("Desktop style verification failed.");
            // HWND_BOTTOM is below the wallpaper on this shell; normal Z-order keeps cards visible.
            IntPtr zOrder=new IntPtr(-2);
            if(!SetWindowPos(hwnd,zOrder,0,0,0,0,0x0001|0x0002|0x0010|0x0020))
                throw new InvalidOperationException("SetWindowPos failed: "+Marshal.GetLastWin32Error());
        }
        // DWMWA_BORDER_COLOR=34; 0xFFFFFFFE (DWMWA_COLOR_NONE) removes the 1px system outline
        // that DWM draws around every top-level window.
        public static void SetBorderColor(IntPtr hwnd, bool hidden) {
            int color = hidden ? unchecked((int)0xFFFFFFFE) : 5; // DWMWA_COLOR_NONE / DWMWA_COLOR_DEFAULT
            DwmSetWindowAttribute(hwnd, 34, ref color, 4);
        }
        [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
        [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hwnd);
        public static void SetDesktopAdjustment(IntPtr hwnd, bool enabled) {
            const long NoActivate=0x08000000;
            long style=GetExtendedStyle(hwnd);
            style|=NoActivate;
            WriteWindowLong(hwnd,-20,style);
            IntPtr zOrder=enabled ? new IntPtr(-1) : new IntPtr(-2); // Topmost only while positioning.
            if(!SetWindowPos(hwnd,zOrder,0,0,0,0,0x0001|0x0002|0x0010|0x0020))
                throw new InvalidOperationException("Unable to change position-adjustment mode.");
        }
        [DllImport("dwmapi.dll")] private static extern int DwmGetWindowAttribute(IntPtr hwnd, int attribute, out int value, int size);
        [DllImport("user32.dll")] public static extern uint GetDpiForWindow(IntPtr hwnd);
        public static int ReadDwmAttribute(IntPtr hwnd, int attribute) {
            int value; int result=DwmGetWindowAttribute(hwnd,attribute,out value,4);
            if(result != 0) Marshal.ThrowExceptionForHR(result);
            return value;
        }
        private static bool ApplyAccent(IntPtr hwnd, int state, uint tint) {
            var accent=new AccentPolicy { state=state, color=unchecked((int)tint) };
            int size=Marshal.SizeOf(typeof(AccentPolicy)); IntPtr p=Marshal.AllocHGlobal(size);
            try {
                Marshal.StructureToPtr(accent,p,false);
                var data=new CompositionData { attribute=19,data=p,size=size };
                return SetWindowCompositionAttribute(hwnd,ref data) != 0;
            } finally { Marshal.FreeHGlobal(p); }
        }
        // One complete, idempotent transition owns all compositor properties.
        public static string ApplyBackground(IntPtr hwnd, bool desktop, bool light) {
            int dark=light ? 0 : 1, corner=desktop ? 1 : 2, none=1;
            DwmSetWindowAttribute(hwnd,20,ref dark,4);
            DwmSetWindowAttribute(hwnd,33,ref corner,4);
            SetBorderColor(hwnd,true);
            DwmSetWindowAttribute(hwnd,38,ref none,4);
            ApplyAccent(hwnd,0,0);
            var margins=new Margins();
            DwmExtendFrameIntoClientArea(hwnd,ref margins);
            if(desktop) return "desktop transparent";
            // Prefer the existing composition acrylic; never stack two backdrops.
            if(ApplyAccent(hwnd,4,light ? 0xB8EEF3FAu : 0x99241D18u)) return "composition acrylic";
            margins=new Margins { left=-1,right=-1,top=-1,bottom=-1 };
            int acrylic=3;
            if(DwmExtendFrameIntoClientArea(hwnd,ref margins)==0 && DwmSetWindowAttribute(hwnd,38,ref acrylic,4)==0)
                return "DWM acrylic";
            DwmSetWindowAttribute(hwnd,38,ref none,4);
            margins=new Margins(); DwmExtendFrameIntoClientArea(hwnd,ref margins);
            return "opaque fallback";
        }
    }
}
