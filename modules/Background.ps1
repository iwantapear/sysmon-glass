function Set-Background {
    $desktop=[bool]$script:cfg.desktopMode
    $t=$script:theme
    $hwnd=([Windows.Interop.WindowInteropHelper]::new($window)).Handle
    if($hwnd -ne [IntPtr]::Zero) {
        $script:backdropMode=[SysMonGlass.Native]::ApplyBackground($hwnd,$desktop,$script:cfg.theme -eq 'light')
        Update-BackdropLabel
    }
    $window.Background=[Windows.Media.Brushes]::Transparent
    if($desktop) { $root.Background=[Windows.Media.Brushes]::Transparent }
    else {
        $root.Background=[Windows.Media.LinearGradientBrush]::new()
        $root.Background.StartPoint='0,0'; $root.Background.EndPoint='1,1'
        for($i=0;$i -lt 3;$i++) {
            $offset=@(0,0.52,1)[$i]
            $root.Background.GradientStops.Add([Windows.Media.GradientStop]::new([Windows.Media.ColorConverter]::ConvertFromString($t.bg[$i]),$offset))
        }
        if($script:backdropMode -eq 'opaque fallback') { $window.Background=Brush ($t.bg[1] -replace '^#..','#FF') }
    }
    foreach($ctl in $script:controls.Values) {
        # Desktop mode replaces the whole surface with the icon mask; the halo
        # would only bleed into the transparent gaps.
        $ctl.shadowHost.Visibility=if($desktop){[Windows.Visibility]::Collapsed}else{[Windows.Visibility]::Visible}
    }
}
