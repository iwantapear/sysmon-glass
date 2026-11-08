using System;
using System.Runtime.InteropServices;
using System.Threading;

namespace SysMonGlass {
    public sealed class DesktopContextMenu : IDisposable {
        public const int MenuMessage = 0x8000 + 0x321;
        public const int CloseMenuMessage = 0x8000 + 0x324;
        public const int CardClickMessage = 0x8000 + 0x325;
        public const int CardDragMessage = 0x8000 + 0x326; // LParam=card index, WParam=POINT.
        public const int ShapeToggleMessage = 0x8000 + 0x327; // LParam=card index.
        public const int CardDragEndMessage = 0x8000 + 0x328; // LParam=card index.
        public const int MenuClickMessage = 0x8000 + 0x329; // WParam/LParam=screen point.
        private const int WhMouseLl = 14, RightDown = 0x204, RightUp = 0x205, LeftDown = 0x201, LeftUp = 0x202;
        private const int MenuPad = 2;
        private const uint WmQuit = 0x12, RefreshHook = 0x8000 + 0x322, RootAncestor = 2;

        [StructLayout(LayoutKind.Sequential)] public struct CardArea {
            public int Left, Top, Right, Bottom;
            public double Radius;
            public bool Contains(Native.ScreenPoint p) {
                if (p.X < Left || p.X >= Right || p.Y < Top || p.Y >= Bottom) return false;
                double dx = Math.Max(0, Math.Max(Left + Radius - p.X, p.X - (Right - Radius)));
                double dy = Math.Max(0, Math.Max(Top + Radius - p.Y, p.Y - (Bottom - Radius)));
                return dx * dx + dy * dy <= Radius * Radius;
            }
        }
        private sealed class Targets {
            public readonly IntPtr DesktopRoot;
            public readonly CardArea[] Cards;
            public readonly Native.IconRect[] Icons;
            public Targets(IntPtr desktopRoot, CardArea[] cards, Native.IconRect[] icons) {
                DesktopRoot = desktopRoot; Cards = cards; Icons = icons;
            }
        }
        [StructLayout(LayoutKind.Sequential)] private struct Message {
            public IntPtr Hwnd; public uint Id; public IntPtr WParam, LParam;
            public uint Time; public Native.ScreenPoint Point; public uint Private;
        }
        private delegate IntPtr MouseHook(int code, IntPtr message, IntPtr data);
        [DllImport("user32.dll", SetLastError=true)] private static extern IntPtr SetWindowsHookEx(int id, MouseHook callback, IntPtr module, uint threadId);
        [DllImport("user32.dll")] private static extern bool UnhookWindowsHookEx(IntPtr hook);
        [DllImport("user32.dll")] private static extern IntPtr CallNextHookEx(IntPtr hook, int code, IntPtr message, IntPtr data);
        [DllImport("user32.dll")] private static extern IntPtr WindowFromPoint(Native.ScreenPoint point);
        [DllImport("user32.dll")] private static extern IntPtr GetAncestor(IntPtr hwnd, uint flags);
        [DllImport("user32.dll")] private static extern IntPtr GetShellWindow();
        [DllImport("user32.dll")] private static extern bool IsWindowVisible(IntPtr hwnd);
        [DllImport("user32.dll")] private static extern bool IsIconic(IntPtr hwnd);
        [DllImport("dwmapi.dll")] private static extern int DwmGetWindowAttribute(IntPtr hwnd, int attribute, out int value, int size);
        [DllImport("user32.dll")] private static extern bool PostMessage(IntPtr hwnd, uint message, IntPtr wParam, IntPtr lParam);
        [DllImport("user32.dll")] private static extern bool PostThreadMessage(uint threadId, uint message, IntPtr wParam, IntPtr lParam);
        [DllImport("user32.dll")] private static extern bool PeekMessage(out Message msg, IntPtr hwnd, uint min, uint max, uint flags);
        [DllImport("user32.dll")] private static extern int GetMessage(out Message msg, IntPtr hwnd, uint min, uint max);
        [DllImport("kernel32.dll", CharSet=CharSet.Unicode)] private static extern IntPtr GetModuleHandle(string module);
        [DllImport("kernel32.dll")] private static extern uint GetCurrentThreadId();

        private readonly IntPtr panel;
        private readonly Thread worker;
        private volatile Targets targets;
        private volatile uint threadId;
        private volatile int startError;
        private volatile bool disposed;
        private volatile bool menuOpen;
        private Native.ScreenRect menuBounds;
        private bool capturedRight;
        private int capturedLeft = -1;
        private long pressedAt;
        private bool dragging;
        private long lastDragPost;
        private Native.ScreenPoint pressed;
        private Native.ScreenPoint pressedLeft;

        public DesktopContextMenu(IntPtr panel) {
            this.panel = panel;
            worker = new Thread(Run) { IsBackground = true, Name = "SysMon desktop context menu" };
            worker.Start();
        }
        public int StartError { get { return startError; } }
        public void SetTargets(IntPtr desktopList, CardArea[] cards, Native.IconRect[] icons) {
            if (disposed) return;
            bool wasInactive = targets == null;
            targets = new Targets(GetAncestor(desktopList, RootAncestor), cards, icons);
            if (wasInactive) SignalWorker(RefreshHook);
        }
        public void ClearTargets() {
            if (targets == null) return;
            targets = null;
            SignalWorker(RefreshHook);
        }
        public void SetMenuBounds(Native.ScreenRect bounds) {
            menuBounds = bounds;
            menuOpen = true;
        }
        public void ClearMenuBounds() {
            menuOpen = false;
            SignalWorker(RefreshHook);
        }
        private void SignalWorker(uint message) {
            uint id = threadId;
            if (id != 0) PostThreadMessage(id, message, IntPtr.Zero, IntPtr.Zero);
        }
        private IntPtr InstallHook(MouseHook callback) {
            IntPtr hook = SetWindowsHookEx(WhMouseLl, callback, GetModuleHandle(null), 0);
            startError = hook == IntPtr.Zero ? Marshal.GetLastWin32Error() : 0;
            return hook;
        }

        private void Run() {
            Native.SetThreadDpiAwarenessContext(new IntPtr(-4));
            Message message;
            PeekMessage(out message, IntPtr.Zero, 0, 0, 0); // Ensure PostThreadMessage has a queue.
            threadId = GetCurrentThreadId();
            if (disposed) return;
            MouseHook callback = FilterMouse;
            IntPtr hook = targets == null ? IntPtr.Zero : InstallHook(callback);
            try {
                while (!disposed && GetMessage(out message, IntPtr.Zero, 0, 0) > 0) {
                    if (message.Id != RefreshHook) continue;
                    if (targets != null && hook == IntPtr.Zero) hook = InstallHook(callback);
                    else if (targets == null && hook != IntPtr.Zero && capturedRight == false && capturedLeft < 0) {
                        UnhookWindowsHookEx(hook);
                        hook = IntPtr.Zero;
                    }
                }
            } finally {
                if (hook != IntPtr.Zero) UnhookWindowsHookEx(hook);
                GC.KeepAlive(callback);
            }
        }
        private bool CanOpen(Native.ScreenPoint point) {
            Targets snapshot = targets;
            if (snapshot == null || snapshot.DesktopRoot == IntPtr.Zero || !IsWindowVisible(panel)) return false;
            bool onCard = false;
            foreach (var card in snapshot.Cards) if (card.Contains(point)) { onCard = true; break; }
            if (!onCard || IsIconic(panel)) return false;
            const int DwmwaCloaked = 14;
            int cloaked;
            if (DwmGetWindowAttribute(panel, DwmwaCloaked, out cloaked, sizeof(int)) == 0 && cloaked != 0) return false;
            foreach (var icon in snapshot.Icons) {
                if (point.X >= icon.Left && point.X < icon.Right && point.Y >= icon.Top && point.Y < icon.Bottom) return false;
            }
            IntPtr root = GetAncestor(WindowFromPoint(point), RootAncestor);
            return root != IntPtr.Zero && (root == snapshot.DesktopRoot || root == GetShellWindow());
        }
        private IntPtr FilterMouse(int code, IntPtr message, IntPtr data) {
            if (code == 0) {
                int id = (int)message.ToInt64();
                bool isDown = id == 0x201 || id == 0x204; // Left/right down.
                if (capturedLeft >= 0 && id == 0x200) {
                    var point = Marshal.PtrToStructure<Native.ScreenPoint>(data);
                    long now = Environment.TickCount64;
                    if (!dragging && now - pressedAt >= 350 && (Math.Abs(point.X - pressedLeft.X) > 8 || Math.Abs(point.Y - pressedLeft.Y) > 8)) dragging = true;
                    if (dragging && now - lastDragPost >= 45) {
                        lastDragPost = now;
                        PostMessage(panel, CardDragMessage, (IntPtr)capturedLeft, new IntPtr(((long)(uint)point.Y << 32) | (uint)point.X));
                    }
                    // Never swallow moves: blocking them freezes the cursor. The
                    // pass-through move is harmless because the panel is click-through.
                }
                if (menuOpen && isDown) {
                    var point = Marshal.PtrToStructure<Native.ScreenPoint>(data);
                    bool inside = point.X >= menuBounds.Left + MenuPad && point.X < menuBounds.Right - MenuPad
                               && point.Y >= menuBounds.Top + MenuPad && point.Y < menuBounds.Bottom - MenuPad;
                    if (!inside) { PostMessage(panel, CloseMenuMessage, new IntPtr(point.X), new IntPtr(point.Y)); return new IntPtr(1); }
                    return CallNextHookEx(IntPtr.Zero, code, message, data);
                }
                if (id == RightDown && targets != null) {
                    var point = Marshal.PtrToStructure<Native.ScreenPoint>(data); // MSLLHOOKSTRUCT starts with POINT.
                    capturedRight = CanOpen(point);
                    if (capturedRight) { pressed = point; return new IntPtr(1); }
                } else if (id == RightUp && capturedRight) {
                    capturedRight = false;
                    var point = Marshal.PtrToStructure<Native.ScreenPoint>(data);
                    if (Math.Abs(point.X - pressed.X) <= 6 && Math.Abs(point.Y - pressed.Y) <= 6 && CanOpen(point)) {
                        PostMessage(panel, MenuMessage, new IntPtr(point.X), new IntPtr(point.Y));
                    } else if (Math.Abs(point.X - pressed.X) >= 24 && Math.Abs(point.Y - pressed.Y) <= 90 && CanOpen(point)) {
                        int index = CardIndexAt(pressed);
                        if (index >= 0) PostMessage(panel, ShapeToggleMessage, new IntPtr(index), IntPtr.Zero);
                    }
                    if (targets == null) SignalWorker(RefreshHook);
                    return new IntPtr(1);
                }
                if (id == 0x201 && targets != null) {
                    var point = Marshal.PtrToStructure<Native.ScreenPoint>(data);
                    int index = CardIndexAt(point);
                    if (index >= 0 && CanOpen(point) && !IsIconic(panel)) {
                        capturedLeft = index; pressedLeft = point; pressedAt = Environment.TickCount64; dragging = false; lastDragPost = 0;
                        return new IntPtr(1); // Swallow only genuine desktop-card clicks.
                    }
                    capturedLeft = -1;
                } else if (id == 0x202 && capturedLeft >= 0) {
                    var point = Marshal.PtrToStructure<Native.ScreenPoint>(data);
                    int index = capturedLeft; capturedLeft = -1;
                    bool wasDragging = dragging; dragging = false;
                    if (!wasDragging && Math.Abs(point.X - pressedLeft.X) <= 8 && Math.Abs(point.Y - pressedLeft.Y) <= 8) {
                        PostMessage(panel, CardClickMessage, new IntPtr(index), IntPtr.Zero);
                    } else {
                        PostMessage(panel, CardDragEndMessage, new IntPtr(index), IntPtr.Zero);
                    }
                    return new IntPtr(1);
                }
            }
            return CallNextHookEx(IntPtr.Zero, code, message, data);
        }
        private int CardIndexAt(Native.ScreenPoint point) {
            Targets snapshot = targets;
            if (snapshot == null) return -1;
            for (int i = 0; i < snapshot.Cards.Length; i++) if (snapshot.Cards[i].Contains(point)) return i;
            return -1;
        }
        public void Dispose() {
            disposed = true;
            targets = null;
            SignalWorker(WmQuit);
        }
    }
}
