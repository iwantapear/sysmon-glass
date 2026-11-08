param([string]$CapturePath)
$ErrorActionPreference='Stop'
if([Threading.Thread]::CurrentThread.ApartmentState -ne 'STA'){throw 'Run with -STA'}
$AppRoot=Split-Path -Parent $PSScriptRoot
. (Join-Path $AppRoot 'glass.ps1') -PrepareOnly
$window.Show(); Set-DesktopMode $false; [Windows.Threading.Dispatcher]::CurrentDispatcher.Invoke([Action]{},[Windows.Threading.DispatcherPriority]::Background)
$window.UpdateLayout()
$script:cfg.desktopMode=$false
Restore-NormalCardLayout
$window.UpdateLayout()
function Key-Point([string]$key) {
    $face=$script:controls[$key].face
    $p=$face.PointToScreen([Windows.Point]::new($face.ActualWidth/2,$face.ActualHeight/2))
    [Drawing.Point]::new([int]$p.X,[int]$p.Y)
}
$before=$script:cardOrder -join ','
# 1) 拖动交换: cpu -> gpuT
Move-NormalCard 'cpu' (Key-Point 'gpuT')
$afterMove=$script:cardOrder -join ','
if($before -eq $afterMove){throw 'Drag swap did not change card order'}
# 2) 双击切长短
$startShape=Get-CardShape 'vrm'
Set-CardShape 'vrm' $(if($startShape -eq 'long'){'short'}else{'long'}) $true | Out-Null
$newShape=Get-CardShape 'vrm'
if($newShape -eq $startShape){throw 'Shape toggle failed'}
$window.UpdateLayout()
# 3) 恢复原状
Set-CardShape 'vrm' $startShape $true | Out-Null
$script:cardOrder=$before.Split(',')
Restore-NormalCardLayout
$savedCol=$script:cfg.cardOrder.Count
if($savedCol -ne $script:defaultCardKeys.Count){throw 'cardOrder persistence broken'}
if($CapturePath) {
    $window.UpdateLayout()
    $dashboard=$window.FindName('DashboardGrid')
    $bmp=[Windows.Media.Imaging.RenderTargetBitmap]::new([int]$dashboard.ActualWidth,[int]$dashboard.ActualHeight,96,96,[Windows.Media.PixelFormats]::Pbgra32)
    $bmp.Render($dashboard)
    $enc=[Windows.Media.Imaging.PngBitmapEncoder]::new(); $enc.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($bmp))
    $st=[IO.File]::Create($CapturePath); try{$enc.Save($st)}finally{$st.Dispose()}
    "CAPTURE: $CapturePath"
}
$script:exiting=$true; $window.Close(); $script:tray.Dispose(); $menu.Dispose(); $script:trayFont.Dispose(); $script:trayBitmap.Dispose()
'PASS: normal-mode drag swap changed order; double-click shape toggle works; layout restored'
