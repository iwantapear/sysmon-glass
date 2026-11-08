# All geometry inputs and outputs here are physical screen pixels, including saved positions.
function Get-PanelBaseHeight([bool]$Desktop) {
    if(Get-Command Get-CardLayoutBaseHeight -ErrorAction SilentlyContinue) { return Get-CardLayoutBaseHeight $Desktop }
    $base=if($Desktop){700}else{900}
    $base+200*$script:systemCardRows
}

function Save-PanelPlacement([switch]$ManualResize) {
    if($window.WindowState -eq 'Minimized' -or $script:resizeState.preview) { return }
    $hwnd=([Windows.Interop.WindowInteropHelper]::new($window)).Handle
    if($hwnd -eq [IntPtr]::Zero) { return }
    $bounds=[SysMonGlass.Native]::GetWindowBounds($hwnd)
    # Position is shared across modes (only size differs per mode): writing one
    # mode's key alone made layer switches teleport the panel to stale coords.
    $script:cfg.normalX=$bounds.Left; $script:cfg.normalY=$bounds.Top
    $script:cfg.desktopX=$bounds.Left; $script:cfg.desktopY=$bounds.Top
    if($ManualResize -and -not $script:cfg.desktopMode) {
        $dpi=[SysMonGlass.Native]::GetDpiForWindow($hwnd)
        $dip=if($dpi -gt 0){96.0/$dpi}else{1.0}
        $script:cfg.normalWidthDip=($bounds.Right-$bounds.Left)*$dip
        $script:cfg.normalHeightDip=($bounds.Bottom-$bounds.Top)*$dip
    }
    Save-Config
}

function Get-PanelGeometry {
    param($Area,[string]$Preset,[bool]$Desktop,[double]$X,[double]$Y,[double]$ManualWidth,[double]$ManualHeight)
    $baseHeight=Get-PanelBaseHeight $Desktop
    $factor=if($ManualWidth -gt 0) { $ManualWidth/1600 }
    elseif($Preset -eq 'auto') {
        [math]::Min(2.0,[math]::Min($Area.Width*0.94/1600,$Area.Height*0.92/$baseHeight))
    } else { @{'1080p'=1.0;'2k'=1.4;'4k'=2.0}[$Preset] }
    $width=1600*$factor
    $height=if($ManualWidth -gt 0 -and $ManualHeight -gt 0){$ManualHeight}else{$baseHeight*$factor}
    $fit=[math]::Min(1.0,[math]::Min(($Area.Width-20)/$width,($Area.Height-20)/$height))
    $width=[math]::Max(1,[math]::Floor($width*$fit)); $height=[math]::Max(1,[math]::Floor($height*$fit))
    $padding=if($Desktop){8}else{0}
    @{
        Width=$width; Height=$height
        X=[math]::Min([math]::Max($X,$Area.Left+$padding),$Area.Right-$width-$padding)
        Y=[math]::Min([math]::Max($Y,$Area.Top+$padding),$Area.Bottom-$height-$padding)
    }
}
function Apply-Preset {
    param([switch]$UseCurrentPosition,[Drawing.Point]$DesktopPosition)
    if($script:layoutBusy -or $script:resizeState.preview) { return }
    $script:layoutBusy=$true
    try {
        $hwnd=([Windows.Interop.WindowInteropHelper]::new($window)).Handle
        if($hwnd -eq [IntPtr]::Zero) {
            # Do not interpret saved device pixels as DIP before an HWND exists.
            $window.Width=1000; $window.Height=1000*(Get-PanelBaseHeight $script:cfg.desktopMode)/1600
            return
        }
        $bounds=[SysMonGlass.Native]::GetWindowBounds($hwnd)
        $x=$bounds.Left; $y=$bounds.Top
        $mode=if($script:cfg.desktopMode){'desktop'}else{'normal'}
        $storedX=$script:cfg[$mode+'X']; $storedY=$script:cfg[$mode+'Y']
        $restore=-not $UseCurrentPosition -and -not $script:desktopAdjusting -and $null -ne $storedX -and $null -ne $storedY
        if($restore){$x=[int]$storedX; $y=[int]$storedY}
        if($PSBoundParameters.ContainsKey('DesktopPosition')) {
            $x=$DesktopPosition.X; $y=$DesktopPosition.Y
        }
        $screen=if($script:cfg.desktopMode -or $restore){[Windows.Forms.Screen]::FromPoint([Drawing.Point]::new($x,$y))}else{[Windows.Forms.Screen]::FromHandle($hwnd)}
        $area=$screen.WorkingArea
        $dpi=[SysMonGlass.Native]::GetDpiForWindow($hwnd)
        $scale=if($dpi -gt 0){96.0/$dpi}else{1.0}
        $desktopScale=if($script:desktopAdjusting){$script:desktopDraftScale}else{$script:cfg.desktopScale}
        $manualWidth=0; $manualHeight=0
        if($script:cfg.desktopMode) { $manualWidth=[double]$desktopScale*1600/$scale }
        elseif($script:cfg.normalWidthDip -and $script:cfg.normalHeightDip) {
            $manualWidth=$script:cfg.normalWidthDip/$scale
            $manualHeight=$script:cfg.normalHeightDip/$scale
        }
        $geometry=Get-PanelGeometry $area $script:cfg.preset ([bool]$script:cfg.desktopMode) $x $y $manualWidth $manualHeight
        if(-not $script:cfg.desktopMode -and -not $restore -and -not $UseCurrentPosition -and -not $script:normalPositionSet) {
            $geometry.X=$area.Left+($area.Width-$geometry.Width)/2
            $geometry.Y=$area.Top+($area.Height-$geometry.Height)/2
        }
        if(-not $script:cfg.desktopMode){$script:normalPositionSet=$true}
        $window.MinWidth=[math]::Min(600,$geometry.Width*$scale)
        $window.MinHeight=[math]::Min(350,$geometry.Height*$scale)
        $window.Width=$geometry.Width*$scale; $window.Height=$geometry.Height*$scale
        $window.UpdateLayout()
        if([int]$geometry.X -ne $bounds.Left -or [int]$geometry.Y -ne $bounds.Top) {
            [SysMonGlass.Native]::SetScreenPosition($hwnd,[int]$geometry.X,[int]$geometry.Y)
        }
        if($script:cfg.desktopMode) {
            Update-DesktopIconMask
        }
    } finally { $script:layoutBusy=$false }
}

function Request-DpiLayout {
    if($script:dpiLayoutQueued) { return }
    $script:dpiLayoutQueued=$true
    $window.Dispatcher.BeginInvoke([Action]{
        if($script:layoutBusy) {
            $script:dpiLayoutQueued=$false
            Request-DpiLayout
            return
        }
        try {
            if($script:resizeState.preview) { Stop-PanelGesture }
            Apply-Preset -UseCurrentPosition
        }
        finally { $script:dpiLayoutQueued=$false }
    },[Windows.Threading.DispatcherPriority]::Loaded) | Out-Null
}

function Start-DesktopResizePreview($State) {
    $area=[Windows.Forms.Screen]::FromHandle($State.handle).WorkingArea
    $dpi=[SysMonGlass.Native]::GetDpiForWindow($State.handle)
    $dipPerPixel=if($dpi -gt 0){96.0/$dpi}else{1.0}
    $view=$window.FindName('DashboardView')
    $actions=$window.FindName('ResizeActions')
    $dashboard=$window.FindName('DashboardGrid')
    $scale=[Windows.Media.ScaleTransform]::new(1,1)
    $offset=[Windows.Media.TranslateTransform]::new(($State.left-$area.Left)*$dipPerPixel,($State.top-$area.Top)*$dipPerPixel)
    $actionsOffset=[Windows.Media.TranslateTransform]::new(($State.left+$State.width-$area.Right)*$dipPerPixel,($State.top+$State.height-$area.Bottom)*$dipPerPixel)
    $transform=[Windows.Media.TransformGroup]::new()
    $transform.Children.Add($scale); $transform.Children.Add($offset)
    $State.preview=@{
        area=$area; dipPerPixel=$dipPerPixel; view=$view; actions=$actions; dashboard=$dashboard
        scale=$scale; offset=$offset; actionsOffset=$actionsOffset
        bounds=@{X=$State.left; Y=$State.top; Width=$State.width; Height=$State.height}
    }
    $view.Width=$State.width*$dipPerPixel; $view.Height=$State.height*$dipPerPixel
    $view.HorizontalAlignment='Left'; $view.VerticalAlignment='Top'
    $view.RenderTransform=$transform; $actions.RenderTransform=$actionsOffset
    $dashboard.CacheMode=[Windows.Media.BitmapCache]::new(1.25)
    [SysMonGlass.Native]::SetWindowBounds($State.handle,$area.Left,$area.Top,$area.Width,$area.Height)
}

function Resize-DesktopWindow($State,$Cursor) {
    $dx=$Cursor.X-$State.x; $dy=$Cursor.Y-$State.y
    if($dx -eq 0 -and $dy -eq 0 -and -not $State.moved) { return }
    $State.moved=$true
    # Project the pointer motion onto the diagonal of the original panel.
    $width=$State.width+($dx*$State.width+$dy*$State.height)*$State.width/($State.width*$State.width+$State.height*$State.height)
    $preview=$State.preview
    $area=$preview.area
    $dipPerPixel=$preview.dipPerPixel
    $geometry=Get-PanelGeometry $area $script:cfg.preset $true $State.left $State.top ([math]::Max(800.0,$width))
    if($preview.bounds.Width -eq $geometry.Width) { return }
    $preview.bounds=$geometry
    $script:desktopDraftScale=$geometry.Width*$dipPerPixel/1600
    $preview.scale.ScaleX=$geometry.Width/$State.width
    $preview.scale.ScaleY=$geometry.Height/$State.height
    $preview.offset.X=($geometry.X-$area.Left)*$dipPerPixel
    $preview.offset.Y=($geometry.Y-$area.Top)*$dipPerPixel
    $preview.actionsOffset.X=($geometry.X+$geometry.Width-$area.Right)*$dipPerPixel
    $preview.actionsOffset.Y=($geometry.Y+$geometry.Height-$area.Bottom)*$dipPerPixel
}

function Complete-DesktopResizePreview($State) {
    $preview=$State.preview
    $preview.dashboard.CacheMode=$null
    $preview.view.RenderTransform=[Windows.Media.Transform]::Identity
    $preview.view.Width=[double]::NaN; $preview.view.Height=[double]::NaN
    $preview.view.HorizontalAlignment='Stretch'; $preview.view.VerticalAlignment='Stretch'
    $preview.actions.RenderTransform=[Windows.Media.Transform]::Identity
    $geometry=$preview.bounds
    $window.MinWidth=[math]::Min(600.0,$geometry.Width*$preview.dipPerPixel)
    $window.MinHeight=[math]::Min(350.0,$geometry.Height*$preview.dipPerPixel)
    [SysMonGlass.Native]::SetWindowBounds($State.handle,[int]$geometry.X,[int]$geometry.Y,[int]$geometry.Width,[int]$geometry.Height)
}
