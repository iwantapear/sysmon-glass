# Pure chrome hit-test decision (physical pixels, window-relative).
# 'grip'    -> bottom-right 64px resize corner
# 'caption' -> 8px rim band: drag the panel from anywhere along its edge
# $null     -> interactive client area
function Get-ChromeHitTest([int]$Cx,[int]$Cy,[int]$Width,[int]$Height) {
    if($Cx -ge $Width-64 -and $Cy -ge $Height-64) { return 'grip' }
    if($Cx -lt 8 -or $Cx -ge $Width-8 -or $Cy -lt 8 -or $Cy -ge $Height-8) { return 'caption' }
    return $null
}
# Drag smoothness: while a modal move runs, WPF re-renders 14 glass cards, their
# shadows and the ambient gradients on every step. Caching the dashboard at 1.0
# (pixel-identical, text stays crisp) and dropping the shadow effects turns each
# step into a cheap composite.
$script:dragOptimized=$false
function Start-PanelDragOptimization {
    if($script:dragOptimized){return}
    $script:dragOptimized=$true
    try {
        $view=$window.FindName('DashboardView')
        if($view){
            $cache=[Windows.Media.BitmapCache]::new(1.0)
            $cache.EnableClearType=$true
            $view.CacheMode=$cache
        }
    } catch { }
}
function Stop-PanelDragOptimization {
    if(-not $script:dragOptimized){return}
    $script:dragOptimized=$false
    try {
        $view=$window.FindName('DashboardView')
        if($view){ $view.CacheMode=$null }
    } catch { }
}
# True when a press on this element should move the whole panel: any non-interactive
# chrome surface (margins, header text, footer, ambient area). Cards, buttons,
# scroll regions, the edit toolbar and the resize actions must never drag.
function Test-PanelDragSurface($Element) {
    $node=$Element
    while($null -ne $node -and $node -ne $window) {
        if($node -is [Windows.Controls.Primitives.ButtonBase] -or
           $node -is [Windows.Controls.Primitives.TextBoxBase] -or
           $node -is [Windows.Controls.Primitives.ScrollBar] -or
           $node -is [Windows.Controls.ScrollViewer] -or
           $node -is [Windows.Controls.ProgressBar] -or
           $node -is [Windows.Controls.ComboBox] -or
           $node -is [Windows.Controls.Menu]) { return $false }
        if($node -is [Windows.FrameworkElement] -and [string]$node.Name -in @('ContentArea','CardScroll','CardCanvas','CardScrollViewer','EditToolbar','ResizeActions','SystemCards','LocalCards','RemoteCards')) { return $false }
        $node=[Windows.Media.VisualTreeHelper]::GetParent($node)
    }
    return $true
}

$window.Add_SourceInitialized({
    $hwnd=([Windows.Interop.WindowInteropHelper]::new($window)).Handle
    [SysMonGlass.Native]::InstallChromeHitTest($hwnd)
    [SysMonGlass.Native]::DragPhaseChanged=[Action[bool]]{
        param($moving)
        if($moving){ Start-PanelDragOptimization } else { Stop-PanelDragOptimization }
    }
    $source=[Windows.Interop.HwndSource]::FromHwnd($hwnd); $source.CompositionTarget.BackgroundColor=[Windows.Media.Colors]::Transparent
    $source.AddHook({
        param($hwnd,$msg,$wParam,$lParam,[ref]$handled)
        if($msg -eq [SysMonGlass.DesktopContextMenu]::MenuMessage) {
            $handled.Value=$true
            if($window.IsVisible -and $script:cfg.desktopMode -and -not $script:desktopAdjusting) {
                Show-DesktopContextMenu ([Drawing.Point]::new([int]$wParam.ToInt64(),[int]$lParam.ToInt64()))
            }
        }
        if($msg -eq [SysMonGlass.DesktopContextMenu]::CloseMenuMessage) {
            $handled.Value=$true
            if($null -ne $menu -and $menu.Visible) { $menu.Close() }
        }
        if($msg -eq [SysMonGlass.DesktopContextMenu]::CardClickMessage -and $window.IsVisible) {
            $handled.Value=$true
            $index=[int]$wParam.ToInt64()
            if($index -ge 0 -and $index -lt $cards.Count) {
                $face=$script:controls[$cards[$index].key].face
                $center=$face.PointToScreen([Windows.Point]::new($face.ActualWidth/2,$face.ActualHeight/2))
                Show-CardDetail $cards[$index].key ([Drawing.Point]::new([int]$center.X,[int]$center.Y))
            }
        }
        if($msg -eq [SysMonGlass.DesktopContextMenu]::CardDragMessage -and $window.IsVisible) {
            $handled.Value=$true
            $index=[int]$wParam.ToInt64()
            $packed=$lParam.ToInt64()
            $x=[int]($packed -band 0x7FFFFFFF); if(($packed -band 0x80000000) -ne 0){$x=[int]([long]$x-2147483648)}
            $y=[int]($packed -shr 32)
            Move-CardInCanvas $index $x $y
        }
        if($msg -eq [SysMonGlass.DesktopContextMenu]::CardDragEndMessage -and $window.IsVisible) {
            $handled.Value=$true
            Save-DesktopCardLayout; Update-DesktopIconMask
        }
        if($msg -eq [SysMonGlass.DesktopContextMenu]::ShapeToggleMessage -and $window.IsVisible) {
            $handled.Value=$true
            Toggle-CardShapeByIndex ([int]$wParam.ToInt64())
        }
        if($msg -eq 0x7E -or ($msg -eq 0x1A -and $wParam.ToInt64() -eq 0x2F)) {
            Request-DpiLayout
        }
        # Normal mode: the chrome edge (8px band, outside the bottom-right resize
        # corner) behaves like a title bar so the panel can be dragged from anywhere
        # along its rim. Bottom mode leaves hit-testing to the card region.
        return [IntPtr]::Zero
    })
    if($script:cfg.layerMode -in @('top','normal','bottom')){Set-WindowLayer ([string]$script:cfg.layerMode) $false}else{Set-DesktopMode ([bool]$script:cfg.desktopMode)}
})
function Apply-PendingResize {
    $state=$script:resizeState
    if(-not $state -or $null -eq $state.pendingCursor) { return }
    $cursor=$state.pendingCursor
    $state.pendingCursor=$null
    if($script:cfg.desktopMode) { Resize-DesktopWindow $state $cursor }
    else {
        $width=[math]::Max(800,$state.width+$cursor.X-$state.x)
        $height=[math]::Max(450,$state.height+$cursor.Y-$state.y)
        [SysMonGlass.Native]::SetWindowBounds($state.handle,$state.left,$state.top,[int]$width,[int]$height)
    }
}
$script:renderResize=[EventHandler]{ Apply-PendingResize }
function Stop-PanelGesture {
    $state=$script:resizeState
    if($state) {
        [Windows.Media.CompositionTarget]::remove_Rendering($script:renderResize)
        Apply-PendingResize
        $script:resizeState=$null
        if($state.preview) {
            Complete-DesktopResizePreview $state
            Update-ScaleMenu
        } elseif(-not $script:cfg.desktopMode) {
            Save-PanelPlacement -ManualResize
            Update-ScaleMenu
        }
    }
    $capture=if($state){$state.capture}else{$script:dragState.capture}
    $script:resizeState=$null; $script:dragState=$null
    if($capture -and $capture.IsMouseCaptured) { $capture.ReleaseMouseCapture() }
    # Panel move finished: normalise the preset and rebuild the icon mask once.
    if($script:panelMovePending){
        $script:panelMovePending=$false
        Apply-Preset -UseCurrentPosition
    }
}
$window.Add_PreviewMouseLeftButtonUp({
    if($script:cardGesture) { Complete-CardGesture; $_.Handled=$true; return }
    if($script:resizeState) { $script:resizeState.pendingCursor=[SysMonGlass.Native]::GetCursorPosition() }
    Stop-PanelGesture
})
$window.Add_LostMouseCapture({
    if($script:cardGesture -and -not $script:cardGesture.capture.IsMouseCaptured) { Complete-CardGesture $true }
    if(($script:resizeState -and -not $script:resizeState.capture.IsMouseCaptured) -or
       ($script:dragState -and -not $script:dragState.capture.IsMouseCaptured)) { Stop-PanelGesture }
})
$window.Add_IsVisibleChanged({
    if($window.IsVisible){Update-DesktopIconMask}
    elseif($script:desktopContext){$script:desktopContext.ClearTargets()}
})
$window.Add_Closed({ if($script:desktopContext){$script:desktopContext.Dispose()} })
$window.Add_DpiChanged({ Request-DpiLayout })
$window.FindName('CardScroll').Add_ScrollChanged({
    if($script:cfg.desktopMode){$script:desktopRegionSignature=$null;Update-DesktopIconMask}
})
$window.Add_SizeChanged({
    if(-not $script:layoutBusy -and $script:cfg.desktopMode) { Update-DesktopIconMask }
})
# Any non-interactive chrome surface (header strip, window margins, footer, ambient
# glow) drags the whole panel. Cards, buttons and scrollers answer false and keep
# their own behaviour, so the rim of the UI is draggable everywhere in normal mode.
$window.FindName('Root').Add_MouseLeftButtonDown({
    param($s,$e)
    if($e.Handled -or $script:cardEditing -or $script:cardGesture -or $script:resizeState -or $script:dragState) { return }
    if($script:cfg.desktopMode -and -not $script:desktopAdjusting) { return }
    if($script:desktopAdjusting) { return }
    if(-not (Test-PanelDragSurface $e.OriginalSource)) { return }
    $e.Handled=$true
    try { $window.DragMove() } catch { return }
    Save-PanelPlacement
})
$window.FindName('HideButton').Add_Click({ Hide-Panel })
$window.Add_PreviewMouseLeftButtonDown({
    param($s,$e)
    $cdp=$script:cardDetailPopup
    if($cdp -and $cdp.IsOpen -and $null -ne $cdp.Child){
        # Close the flyout on outside presses; presses inside keep it open for its buttons.
        $pos=$e.GetPosition($cdp.Child)
        if($pos.X -lt 0 -or $pos.Y -lt 0 -or $pos.X -gt $cdp.Child.ActualWidth -or $pos.Y -gt $cdp.Child.ActualHeight){$cdp.IsOpen=$false}
    }
    if($script:dragState -or $script:resizeState) { return }
    if($script:cfg.desktopMode -and -not $script:desktopAdjusting) { return }
    $hwnd=([Windows.Interop.WindowInteropHelper]::new($window)).Handle
    if($hwnd -eq [IntPtr]::Zero) { return }
    $cursor=[SysMonGlass.Native]::GetCursorPosition(); $bounds=[SysMonGlass.Native]::GetWindowBounds($hwnd)
    $onGrip=if($script:cfg.desktopMode){$window.FindName('ResizeGrip').IsMouseOver}else{
        $cursor.X -ge $bounds.Right-64 -and $cursor.Y -ge $bounds.Bottom-64
    }
    if($onGrip -and $s.CaptureMouse()) {
        $script:resizeState=@{handle=$hwnd;x=$cursor.X;y=$cursor.Y;left=$bounds.Left;top=$bounds.Top;width=$bounds.Right-$bounds.Left;height=$bounds.Bottom-$bounds.Top;capture=$s}
        if($script:cfg.desktopMode) { Start-DesktopResizePreview $script:resizeState }
        [Windows.Media.CompositionTarget]::add_Rendering($script:renderResize)
        $e.Handled=$true
        return
    }
})
$window.Add_PreviewMouseMove({
    param($s,$e)
    if($script:resizeState -and $e.LeftButton -eq [Windows.Input.MouseButtonState]::Pressed) {
        $script:resizeState.pendingCursor=[SysMonGlass.Native]::GetCursorPosition()
        $e.Handled=$true
    }
})
function Save-VisiblePanelPlacement {
    if(-not $window.IsVisible) { return }
    if($script:cardEditing){Complete-Editing}
    Complete-CardGesture $true
    Stop-PanelGesture
    if($script:desktopAdjusting){Set-DesktopAdjustment $false}
    else { Save-PanelPlacement }
}
function Hide-Panel {
    Save-VisiblePanelPlacement
    $window.Hide()
}
$window.Add_Closing({
    Save-VisiblePanelPlacement
    if(-not $script:exiting) { $_.Cancel=$true; $window.Hide() }
})

$window.FindName('ThemeButton').Add_Click({
    $index=[array]::IndexOf($script:themeOrder,[string]$script:cfg.theme)
    if($index -lt 0) { $index=0 }
    Set-Theme $script:themeOrder[(($index+1) % $script:themeOrder.Count)] $true
})

$window.FindName('DesktopAdjustDone').Add_Click({
    if($script:cardEditing){Complete-Editing}else{Set-DesktopAdjustment $false}
})
function Step-EditScale([double]$Delta) {
    if([bool]$script:cfg.desktopMode){
        $current=if($null -ne $script:desktopDraftScale){[double]$script:desktopDraftScale}elseif($null -ne $script:cfg.desktopScale){[double]$script:cfg.desktopScale}else{1.0}
        $script:desktopDraftScale=[math]::Min(2.0,[math]::Max(0.4,$current+$Delta))
        Apply-Preset -UseCurrentPosition
    } else {
        $w=if($script:cfg.normalWidthDip){[double]$script:cfg.normalWidthDip}else{1600.0}
        $w=[math]::Min(3840.0,[math]::Max(800.0,$w*(1+$Delta)))
        $script:cfg.normalWidthDip=$w; $script:cfg.normalHeightDip=$w*(Get-PanelBaseHeight $false)/1600.0
        Apply-Preset
    }
    Update-EditToolbar
}
$window.FindName('EditScaleDown').Add_Click({ Step-EditScale -0.05 })
$window.FindName('EditScaleUp').Add_Click({ Step-EditScale 0.05 })
$window.FindName('EditModeSwitch').Add_Click({
    if($script:cardEditing){Set-DesktopAdjustment $true}
    elseif($script:desktopAdjusting){Set-CardEditing $true}
})
$window.FindName('EditLayerButton').Add_Click({
    $next=@{top='normal';normal='bottom';bottom='top'}[[string]$script:cfg.layerMode]
    Set-WindowLayer $next
    if(Get-Command Update-EditToolbar -ErrorAction SilentlyContinue){Update-EditToolbar}
})
$window.Add_KeyDown({
    param($s,$e)
    if($e.Key -eq [Windows.Input.Key]::Escape) {
        if($script:cardDetailPopup -and $script:cardDetailPopup.IsOpen){$script:cardDetailPopup.IsOpen=$false}
        elseif($script:cardGesture){Complete-CardGesture $true}
        elseif($script:cardEditing){Complete-Editing}
        elseif($script:desktopAdjusting){Set-DesktopAdjustment $false}
        $e.Handled=$true
    }
})
$window.Add_MouseRightButtonUp({
    param($s,$e)
    if(-not $e.Handled -and -not $script:cardGesture -and -not $script:resizeState -and -not $script:dragState) {
        Show-PanelContextMenu $window.FindName('Root')
        $e.Handled=$true
    }
})
