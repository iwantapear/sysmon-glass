# Standalone WPF regression: no pollers, tray, live config, or existing dashboard touched.
param([string]$CapturePath)
$ErrorActionPreference='Stop'
if([Threading.Thread]::CurrentThread.ApartmentState -ne 'STA'){throw 'Run with pwsh -NoProfile -STA -File tests/CardLayoutRegression.Tests.ps1'}
Add-Type -AssemblyName PresentationFramework,PresentationCore,WindowsBase
$script:AppRoot=Split-Path -Parent $PSScriptRoot
$script:cfg=@{language='zh-CN';cardShapes=@{};cardLayout=@{};desktopMode=$false}
$script:controls=@{}; $script:values=@{}; $script:history=@{cpu=[Collections.Generic.List[double]]::new();dgx=[Collections.Generic.List[double]]::new()}
$script:dgx=@{AgeSec=-1}
function Brush([string]$Color){[Windows.Media.BrushConverter]::new().ConvertFromString($Color)}
function Save-Config { $script:savedConfig=$script:cfg | ConvertTo-Json -Depth 10 }
function Apply-Preset { }
function Update-DesktopIconMask { }
. (Join-Path $script:AppRoot 'modules/Locale.ps1')
[xml]$xaml=Get-Content -LiteralPath (Join-Path $script:AppRoot 'ui/Dashboard.xaml') -Raw
$window=[Windows.Markup.XamlReader]::Load([Xml.XmlNodeReader]::new($xaml))
$statusText=$window.FindName('StatusText'); $statusDot=$window.FindName('StatusDot')
. (Join-Path $script:AppRoot 'modules/LocalIO.ps1')
. (Join-Path $script:AppRoot 'modules/Display.ps1')
. (Join-Path $script:AppRoot 'modules/Cards.ps1')
$script:theme=@{text='#FFF5F9FF';bad='#FFFF8D91';warn='#FFFFD77C';card=@('#FF172334')}
function Assert([bool]$Condition,[string]$Message){if(-not $Condition){throw $Message}}
function Layout-TestWindow {
    $window.Width=1600; $window.Height=$window.FindName('DashboardGrid').Height
    $window.UpdateLayout()
}
function Assert-Geometry([string]$Stage) {
    Layout-TestWindow
    $dashboard=$window.FindName('DashboardGrid'); $rects=@()
    foreach($cell in $cards) {
        $ctl=$script:controls[$cell.key]; $face=$ctl.face
        $point=$face.TranslatePoint([Windows.Point]::new(0,0),$dashboard)
        $rect=[Windows.Rect]::new($point.X,$point.Y,$face.ActualWidth,$face.ActualHeight)
        Assert ($rect.Width -ge 300 -and $rect.Height -ge 180) "$Stage $($cell.key) is clipped/undersized: $rect"
        Assert ($rect.X -ge 0 -and $rect.Y -ge 0 -and $rect.Right -le 1600.1 -and $rect.Bottom -le $dashboard.Height+0.1) "$Stage $($cell.key) escaped dashboard: $rect"
        foreach($previous in $rects){Assert (-not $rect.IntersectsWith($previous.rect)) "$Stage overlap: $($cell.key) / $($previous.key)"}
        $rects+=@{key=$cell.key;rect=$rect}
        # There is no hidden detail column: short-card data gets full content width.
        $grid=$face.Child.Children | Where-Object {$_ -is [Windows.Controls.Grid]}
        Assert ($grid.ColumnDefinitions.Count -eq 0) "$Stage hidden details column reserves width"
        Assert ($grid.ActualWidth -ge $face.ActualWidth-55) "$Stage short-card content narrowed"
    }
    Write-Output "PASS: $Stage 14 in-bounds, non-overlapping faces; no hidden detail column"
}
try {
    Assert ($cards.Count -eq $script:defaultCardKeys.Count -and $script:controls.Count -eq $script:defaultCardKeys.Count) 'Missing cards'
    foreach($cell in $cards){Assert ($cell.labelKey -and $script:strings.ContainsKey($cell.labelKey)) "Unlocalized card $($cell.key)"}
    # Validate malformed persisted data without trusting old pixel coordinates.
    $script:cfg.cardOrder=@('unknown','diskPct','diskPct','netDown')
    $script:cfg.cardShapes=@{cpu='bad';diskPct='long'}
    Initialize-CardLayoutConfig
    Assert ($script:cardOrder.Count -eq $script:defaultCardKeys.Count -and $script:cardOrder[0] -eq 'diskPct') 'Order sanitization failed'
    Assert ((Get-CardShape cpu) -eq 'short') 'Invalid shape accepted'
    Restore-NormalCardLayout
    $window.Show(); Assert-Geometry 'normal mixed'
    foreach($key in $cards.key){Set-CardShape $key long | Out-Null}
    Assert-Geometry 'normal all-long'
    $script:cfg.desktopMode=$true
    foreach($name in @('Header','Footer','LocalSection','RemoteSection','ContentArea')){$window.FindName($name).Visibility='Collapsed'}
    $dashboard=$window.FindName('DashboardGrid')
    $dashboard.RowDefinitions[0].Height=[Windows.GridLength]::new(0);$dashboard.RowDefinitions[2].Height=[Windows.GridLength]::new(0)
    $window.FindName('CardCanvas').Visibility='Visible'
    Apply-DesktopCardLayout; Assert-Geometry 'desktop all-long'
    Assert ($script:desktopCardRows -eq 7) 'All-long desktop must use 7 rows'
    foreach($key in $cards.key){Set-CardShape $key short | Out-Null}
    Assert-Geometry 'desktop all-short'
    Assert ($script:desktopCardRows -eq 4) 'Short desktop must use 4 rows'
    foreach($key in @('netDown','diskPct')) {
        $index=[array]::IndexOf([string[]]$cards.key,$key)
        $point=$window.FindName('CardCanvas').PointToScreen([Windows.Point]::new(2,2))
        Move-CardInCanvas $index $point.X $point.Y
        Assert ($script:cardOrder[0] -eq $key) "$key cannot reorder to first slot"
        Toggle-CardShapeByIndex $index
        Assert ((Get-CardShape $key) -eq 'long') "$key cannot toggle shape"
        Assert-Geometry "desktop reordered $key"
    }
    $before=$script:cardOrder -join ','
    Move-CardInCanvas -1 0 0; Move-CardInCanvas 0 ([double]::NaN) 0; Move-CardInCanvas 0 1e100 1e100
    Assert (($script:cardOrder -join ',') -eq $before) 'Invalid drag mutated layout'
    $script:values.netDown=2048; $script:values.netUp=1024
    $script:values.diskPct=40; $script:values.diskUsed=40GB; $script:values.diskTotal=100GB
    Update-Display
    Assert ($script:controls.netDown.number.Text -eq '2.0' -and $script:controls.netDown.unit.Text -eq 'KiB/s') 'Network presentation broken'
    Assert ($script:controls.diskPct.number.Text -eq '40') 'Disk presentation broken'
    Save-DesktopCardLayout
    Assert ($script:cfg.cardLayout.Count -eq 0 -and $script:cfg.cardOrder.Count -eq $script:defaultCardKeys.Count) 'Persistence retained legacy pixels'
    if($CapturePath) {
        Layout-TestWindow
        $bitmap=[Windows.Media.Imaging.RenderTargetBitmap]::new(1600,[int]$window.Height,96,96,[Windows.Media.PixelFormats]::Pbgra32)
        $bitmap.Render($window.FindName('Root'))
        $encoder=[Windows.Media.Imaging.PngBitmapEncoder]::new();$encoder.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($bitmap))
        $stream=[IO.File]::Create($CapturePath);try{$encoder.Save($stream)}finally{$stream.Dispose()}
        Write-Output "CAPTURE: $CapturePath"
    }
    'PASS: localized network/disk presentations, guarded drag, reorder, shape toggle and persistence'
} finally {$window.Close()}
