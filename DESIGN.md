# SysMon Glass design contract

## Intent
Preserve the local/DGX dashboard, visual hierarchy and light/dark themes. Desktop mode should look like separate cards with transparent space around them. Coalesce pointer updates into render frames. During desktop resize, transform a cached dashboard preview inside a stable native window, then commit the geometry and redraw the vector text on release. Refreshing numbers does not animate opacity.

## Tokens
Existing theme dictionaries are the palette source. Font Microsoft YaHei UI; number 44, label/unit 15, detail 14. Card radius 20, border 1.2, margin 0/0/18/16; content padding 24/19/24/17. Dashboard base canvas is 1600 by 900, desktop 1600 by 700. Each supplemental row adds 200 units in both modes. Ordinary shadow blur 24, depth 5, direction 270 with theme color/opacity. Card highlights use a low-contrast linear wash and a soft radial reflection inside the rounded clip.

## Components
Window XAML owns the shell. Reused card factory owns card anatomy. Theme module owns palette changes. Background module exclusively owns window composition and desktop-vs-panel effects. Data module owns values and freshness. Layout module owns device-pixel geometry.

## States
Normal: full panel, acrylic when supported, opaque fallback, card shadows, header/footer controls. Desktop: transparent window/root, no window backdrop/frame/rounding, no external card shadows; retain gradient faces, rim and inner highlights. Show the completion button beside the resize grip during desktop adjustment. The two controls follow the preview during resize. Completion saves geometry and restores icon cutouts and input pass-through.

## Interaction
Preserve tray show/hide, theme, preset, refresh, desktop toggle, adjustment and exit. Preserve data refresh without opacity animations. Offline values show em dash and no stale charts. Do not change sensor semantics or fan behavior. A right click on an exposed desktop card opens the tray settings menu at the cursor. The hook uses the rendered card bounds and desktop icon cutouts, and passes other input through.

## Scaling
Each mode saves its own physical screen position and restores it within the monitor working area. WPF dimensions are device-independent units. Compute screen fit in pixels, convert dimensions using current HWND DPI. Use current coordinates for monitor and DPI changes. Desktop resize scales the 1600 × 700 card canvas as a unit. Save the manual scale in device-independent units when adjustment ends. Choosing a preset clears the desktop override.

## QA and limitations
Exercise both themes and modes, repeat transitions, inspect alpha at gap locations, verify actual HWND attributes and real data. Two connected 2560x1440 displays are available; record actual DPI. Synthetic geometry tests supplement but do not substitute for differing physical monitor DPI. Use native mouse drags in the real WPF window to verify repeated desktop gestures.
