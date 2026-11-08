function Move-DesktopWindow([int]$X,[int]$Y) {
    if(-not $script:cfg.desktopMode) { return }
    $hwnd=([Windows.Interop.WindowInteropHelper]::new($window)).Handle
    if($hwnd -eq [IntPtr]::Zero) { return }
    # Per pointer move: reposition only (0.5 ms). The preset re-layout and the icon
    # mask are recomputed once when the gesture ends, not on every step.
    [SysMonGlass.Native]::SetScreenPosition($hwnd,$X,$Y)
    $script:panelMovePending=$true
}
function Start-PanelMoveGesture($Surface,$Event) {
    if(-not $script:cfg.desktopMode -or -not $script:desktopAdjusting -or $script:cardEditing -or $script:resizeState -or $script:dragState){return $false}
    $hwnd=([Windows.Interop.WindowInteropHelper]::new($window)).Handle
    if($hwnd -eq [IntPtr]::Zero){return $false}
    $cursor=[SysMonGlass.Native]::GetCursorPosition();$bounds=[SysMonGlass.Native]::GetWindowBounds($hwnd)
    if(-not $Surface.CaptureMouse()){return $false}
    $script:dragState=@{handle=$hwnd;x=$cursor.X;y=$cursor.Y;left=$bounds.Left;top=$bounds.Top;capture=$Surface;panel=$true}
    $Event.Handled=$true;return $true
}
function Update-PanelMoveGesture($Surface,$Event) {
    if(-not $script:dragState -or -not $script:dragState.panel -or $script:dragState.capture -ne $Surface -or $Event.LeftButton -ne [Windows.Input.MouseButtonState]::Pressed){return}
    $cursor=[SysMonGlass.Native]::GetCursorPosition();Move-DesktopWindow ($script:dragState.left+$cursor.X-$script:dragState.x) ($script:dragState.top+$cursor.Y-$script:dragState.y);$Event.Handled=$true
}
function Set-DesktopAdjustment([bool]$Enabled) {
    $script:desktopRegionSignature=$null
    if($Enabled -and $script:cardEditing){Complete-Editing}
    if(-not $script:cfg.desktopMode -or $Enabled -eq [bool]$script:desktopAdjusting) { return }
    $hwnd=([Windows.Interop.WindowInteropHelper]::new($window)).Handle
    if($hwnd -eq [IntPtr]::Zero) { return }
    if($Enabled) {
        if($script:desktopContext){$script:desktopContext.ClearTargets()}
        $script:previousForeground=[SysMonGlass.Native]::GetForegroundWindow()
        [SysMonGlass.Native]::ClearDesktopMask($hwnd)
        [SysMonGlass.Native]::SetDesktopAdjustment($hwnd,$true)
        $script:desktopDraftScale=$script:cfg.desktopScale
        $script:desktopAdjusting=$true
    } else {
        if(Get-Command Stop-PanelGesture -ErrorAction SilentlyContinue){Stop-PanelGesture}
        [SysMonGlass.Native]::SetDesktopAdjustment($hwnd,$false)
        $script:desktopAdjusting=$false
        if($null -eq $script:desktopDraftScale) { $script:cfg.Remove('desktopScale') }
        else { $script:cfg.desktopScale=$script:desktopDraftScale }
        $script:desktopDraftScale=$null
        Save-PanelPlacement
    }
    $visibility=if($Enabled){[Windows.Visibility]::Visible}else{[Windows.Visibility]::Collapsed}
    $window.FindName('ResizeGrip').Visibility=$visibility
    # Visibility alone is not enough: Sync-CardPresentation may have left hit-testing off
    # from a previous mode; a visible but non-hit-testable Done button ignores clicks.
    $done=$window.FindName('DesktopAdjustDone')
    $done.Visibility=$visibility
    $done.IsHitTestVisible=$Enabled
    if(Get-Command Update-EditToolbar -ErrorAction SilentlyContinue){Update-EditToolbar}
    if($null -ne $res) { Update-ScaleMenu }
    if(-not $Enabled) { Update-DesktopIconMask }
    if(-not $Enabled -and $script:previousForeground -and $script:previousForeground -ne [IntPtr]::Zero) {
        [SysMonGlass.Native]::SetForegroundWindow($script:previousForeground) | Out-Null
        $script:previousForeground=[IntPtr]::Zero
    }
    if($null -ne $movePanelMenuItem) { $movePanelMenuItem.Text=if($script:desktopAdjusting){'完成移动 / Done'}else{'移动面板 / Move panel'} }
}
function Update-DesktopIconMask {
    if(-not $script:cfg.desktopMode -or $script:desktopAdjusting) { return }
    $hwnd=([Windows.Interop.WindowInteropHelper]::new($window)).Handle
    if($hwnd -eq [IntPtr]::Zero) { return }
    try {
        # UI Automation flattens SHELLDLL_DefView out of its tree on Windows 11.
        # Resolve the real HWND hierarchy first, then enumerate only that desktop list.
        # Desktop icons rarely move: poll UIA at most every 3s and reuse the cached rects.
        $now=[Diagnostics.Stopwatch]::GetTimestamp()
        $icons=$script:iconRectsCache
        if($null -eq $icons -or -not $script:iconRectsStamp -or ($now-$script:iconRectsStamp)/[double][Diagnostics.Stopwatch]::Frequency -ge 3) {
            $listHandle=[SysMonGlass.Native]::GetDesktopIconList()
            $icons=[SysMonGlass.Native+IconRect[]]@()
            if($listHandle -ne [IntPtr]::Zero) {
                $list=[System.Windows.Automation.AutomationElement]::FromHandle($listHandle)
                if($null -ne $list) {
                    $items=$list.FindAll([System.Windows.Automation.TreeScope]::Children,[System.Windows.Automation.PropertyCondition]::new([System.Windows.Automation.AutomationElement]::ControlTypeProperty,[System.Windows.Automation.ControlType]::ListItem))
                    $rects=[System.Collections.Generic.List[SysMonGlass.Native+IconRect]]::new()
                    for($i=0;$i -lt $items.Count;$i++) {
                        $r=$items.Item($i).Current.BoundingRectangle
                        if($r.Width -le 0 -or $r.Height -le 0) { continue }
                        $rect=[SysMonGlass.Native+IconRect]::new(); $rect.Left=[int]$r.X; $rect.Top=[int]$r.Y
                        $rect.Right=[int]($r.X+$r.Width); $rect.Bottom=[int]($r.Y+$r.Height)
                        $rects.Add($rect)
                    }
                    $icons=$rects.ToArray()
                }
            }
            $script:iconRectsCache=$icons; $script:iconRectsStamp=$now
        }
        # Interactive card-shaped window region: cards receive mouse input in WPF,
        # gaps and icon holes pass through to the desktop.
        $scroll=$window.FindName('CardScroll')
        $v0=$scroll.PointToScreen([Windows.Point]::new(0,0));$v1=$scroll.PointToScreen([Windows.Point]::new($scroll.ActualWidth,$scroll.ActualHeight))
        $cardRects=[System.Collections.Generic.List[SysMonGlass.Native+IconRect]]::new()
        foreach($cell in $cards) {
            $face=$script:controls[$cell.key].face
            if($face.ActualWidth -le 0 -or $face.ActualHeight -le 0) { continue }
            $tl=$face.PointToScreen([Windows.Point]::new(0,0))
            $br=$face.PointToScreen([Windows.Point]::new($face.ActualWidth,$face.ActualHeight))
            $rect=[SysMonGlass.Native+IconRect]::new()
            $rect.Left=[int][math]::Max($tl.X,$v0.X); $rect.Top=[int][math]::Max($tl.Y,$v0.Y)
            $rect.Right=[int][math]::Min($br.X,$v1.X); $rect.Bottom=[int][math]::Min($br.Y,$v1.Y)
            if($rect.Right -gt $rect.Left -and $rect.Bottom -gt $rect.Top){$cardRects.Add($rect)}
        }
        if($script:cardEditing) {
            $canvas=$window.FindName('CardCanvas')
            $tl=$canvas.PointToScreen([Windows.Point]::new(0,0));$br=$canvas.PointToScreen([Windows.Point]::new($canvas.ActualWidth,$canvas.ActualHeight))
            $r=[SysMonGlass.Native+IconRect]::new();$r.Left=[int][math]::Max($tl.X,$v0.X);$r.Top=[int][math]::Max($tl.Y,$v0.Y);$r.Right=[int][math]::Min($br.X,$v1.X);$r.Bottom=[int][math]::Min($br.Y,$v1.Y)
            if($r.Right -gt $r.Left -and $r.Bottom -gt $r.Top){$cardRects.Add($r)}
            $actions=$window.FindName('ResizeActions')
            if($actions.ActualWidth -gt 0 -and $actions.ActualHeight -gt 0){$tl=$actions.PointToScreen([Windows.Point]::new(0,0));$br=$actions.PointToScreen([Windows.Point]::new($actions.ActualWidth,$actions.ActualHeight));$a=[SysMonGlass.Native+IconRect]::new();$a.Left=[int]$tl.X;$a.Top=[int]$tl.Y;$a.Right=[int]$br.X;$a.Bottom=[int]$br.Y;$cardRects.Add($a)}
        }
        # The unified edit toolbar is interactive during both editing states.
        $toolbar=$window.FindName('EditToolbar')
        if($toolbar -and $toolbar.Visibility -eq [Windows.Visibility]::Visible -and $toolbar.ActualWidth -gt 0 -and $toolbar.IsHitTestVisible) {
            $tl=$toolbar.PointToScreen([Windows.Point]::new(0,0))
            $br=$toolbar.PointToScreen([Windows.Point]::new($toolbar.ActualWidth,$toolbar.ActualHeight))
            $r=[SysMonGlass.Native+IconRect]::new();$r.Left=[int][math]::Max($tl.X,$v0.X);$r.Top=[int][math]::Max($tl.Y,$v0.Y);$r.Right=[int][math]::Min($br.X,$v1.X);$r.Bottom=[int][math]::Min($br.Y,$v1.Y)
            if($r.Right -gt $r.Left -and $r.Bottom -gt $r.Top){$cardRects.Add($r)}
        }
        # The insights rail is interactive like a card: keep it inside the window region.
        if($script:insightsRailBorder -and $script:insightsRailBorder.Visibility -eq [Windows.Visibility]::Visible -and $script:insightsRailBorder.ActualWidth -gt 0) {
            $tl=$script:insightsRailBorder.PointToScreen([Windows.Point]::new(0,0))
            $br=$script:insightsRailBorder.PointToScreen([Windows.Point]::new($script:insightsRailBorder.ActualWidth,$script:insightsRailBorder.ActualHeight))
            $r=[SysMonGlass.Native+IconRect]::new();$r.Left=[int][math]::Max($tl.X,$v0.X);$r.Top=[int][math]::Max($tl.Y,$v0.Y);$r.Right=[int][math]::Min($br.X,$v1.X);$r.Bottom=[int][math]::Min($br.Y,$v1.Y)
            if($r.Right -gt $r.Left -and $r.Bottom -gt $r.Top){$cardRects.Add($r)}
        }
        $signature=($cardRects.ToArray() | ForEach-Object { "$($_.Left),$($_.Top),$($_.Right),$($_.Bottom)" }) -join ';'
        $signature+= '|' + (($icons | ForEach-Object { "$($_.Left),$($_.Top),$($_.Right),$($_.Bottom)" }) -join ';')
        if($signature -ne $script:desktopRegionSignature) {
            [SysMonGlass.Native]::SetCardRegion($hwnd,$cardRects.ToArray(),$icons)
            $script:desktopRegionSignature=$signature
        }
        # The global mouse hook is no longer used for card input.
        if($script:desktopContext){$script:desktopContext.ClearTargets()}    } catch {
        if($script:desktopContext){$script:desktopContext.ClearTargets()}
        $script:maskError=$_.Exception.Message
        # Keep the last valid region during transient shell/UIA failures; never hide all cards.
    }
}
function Set-DesktopMode([bool]$Enabled,[bool]$Persist=$false) {
    if($window.IsLoaded -and $Enabled -ne [bool]$script:cfg.desktopMode -and -not $script:desktopAdjusting) {
        Save-PanelPlacement
        # A layer switch keeps the panel exactly where it is: overwrite any stale
        # saved coordinates for the target mode with the current physical position,
        # so the Apply-Preset restore at the end of this function cannot teleport it.
        $switchHwnd=([Windows.Interop.WindowInteropHelper]::new($window)).Handle
        if($switchHwnd -ne [IntPtr]::Zero) {
            $current=[SysMonGlass.Native]::GetWindowBounds($switchHwnd)
            $script:cfg.normalX=[double]$current.Left; $script:cfg.normalY=[double]$current.Top
            $script:cfg.desktopX=[double]$current.Left; $script:cfg.desktopY=[double]$current.Top
        }
    }
    if(-not $Enabled -and $script:desktopAdjusting) { Set-DesktopAdjustment $false }
    $hwnd=([Windows.Interop.WindowInteropHelper]::new($window)).Handle
    if($Enabled -and ($null -eq $script:cfg.desktopX -or $null -eq $script:cfg.desktopY)) {
        if($hwnd -ne [IntPtr]::Zero) {
            $bounds=[SysMonGlass.Native]::GetWindowBounds($hwnd)
            $script:cfg.desktopX=[double]$bounds.Left; $script:cfg.desktopY=[double]$bounds.Top
        } else { $script:cfg.desktopX=[double]$window.Left; $script:cfg.desktopY=[double]$window.Top }
    }
    # Native flags are verified before committing UI or persisted state.
    if($hwnd -ne [IntPtr]::Zero) {
        try {
            [SysMonGlass.Native]::SetDesktopMode($hwnd,$Enabled)
        }
        catch { [Windows.MessageBox]::Show(((L 'desktopError') -f $_.Exception.Message),(L 'appTitle')) | Out-Null; return }
    }
    if(-not $Enabled -and $script:desktopContext){$script:desktopContext.ClearTargets()}
    $script:cfg.desktopMode=$Enabled
    $window.IsEnabled=$true
    $visibility=if($Enabled){[Windows.Visibility]::Collapsed}else{[Windows.Visibility]::Visible}
    foreach($name in @('AmbientTop','AmbientBottom','Header','Footer','LocalSectionHeader','RemoteSectionHeader','ResizeGrip')) {
        $window.FindName($name).Visibility=$visibility
    }
    $dashboard=$window.FindName('DashboardGrid')
    $dashboard.Height=Get-PanelBaseHeight $Enabled
    $dashboard.RowDefinitions[0].Height=[Windows.GridLength]::new($(if($Enabled){0}else{94}))
    $dashboard.RowDefinitions[2].Height=[Windows.GridLength]::new($(if($Enabled){0}else{46}))
    foreach($name in @('LocalSection','RemoteSection')) {
        $window.FindName($name).RowDefinitions[0].Height=[Windows.GridLength]::new($(if($Enabled){0}else{53}))
    }
    $window.FindName('ContentArea').Margin=if($Enabled){'48,20,48,0'}else{'48,12,48,0'}
    $window.FindName('CardCanvas').Visibility=if($Enabled){[Windows.Visibility]::Visible}else{[Windows.Visibility]::Collapsed}
    foreach($name in @('LocalSection','RemoteSection')) { $window.FindName($name).Visibility=if($Enabled){[Windows.Visibility]::Collapsed}else{[Windows.Visibility]::Visible} }
    $window.FindName('SystemRow').Height=[Windows.GridLength]::new($(if($Enabled){0}else{200*$script:systemCardRows}))
    if($Enabled) { Apply-DesktopCardLayout } else { Restore-NormalCardLayout }
    foreach($ctl in $script:controls.Values) {
        # Keep per-card glass highlights; only the outer panel/frame is removed.
        $ctl.face.BorderThickness=[Windows.Thickness]::new(1.2)
        $ctl.gloss.Visibility=[Windows.Visibility]::Visible; $ctl.sheen.Visibility=[Windows.Visibility]::Visible
        $ctl.surface.Cursor=if($Enabled){[Windows.Input.Cursors]::SizeAll}else{[Windows.Input.Cursors]::Arrow}
    }
    Update-CardLabels
    Set-Theme $script:cfg.theme
    if($null -ne $script:cardEditing -and (Get-Command Sync-CardPresentation -ErrorAction SilentlyContinue)) { Sync-CardPresentation }
    Apply-Preset
    if($Enabled) { Update-DesktopIconMask } elseif($hwnd -ne [IntPtr]::Zero) { [SysMonGlass.Native]::ClearDesktopMask($hwnd) }
    Update-BackdropLabel
    if($null -ne $desktopMenuItem) {
        $desktopMenuItem.Checked=$Enabled
        $desktopMenuItem.Text=if($Enabled){L 'exitDesktop'}else{L 'desktopMode'}
    }
    if(-not $Enabled) { $script:desktopAdjusting=$false }
    # Edit cards is available in both modes; only the desktop-only panel-move item follows desktopMode.
    if($null -ne $positionMenuItem) { $positionMenuItem.Enabled=$true }
    if($null -ne $movePanelMenuItem) { $movePanelMenuItem.Enabled=$Enabled }
    # The rim belongs to the caption only in normal mode; bottom mode keeps
    # the card-region hit-testing untouched.
    [SysMonGlass.Native]::SetChromeDragEnabled(-not $Enabled)
    if($hwnd -ne [IntPtr]::Zero){[SysMonGlass.Native]::SetTopmost($hwnd,([bool]$script:cfg.alwaysOnTop -or [bool]$script:desktopAdjusting))}
    if($null -ne $res) { Update-ScaleMenu }
    if($Persist) { Save-Config }
}