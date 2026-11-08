$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '../glass.ps1') -PrepareOnly
$configPath=Join-Path $script:AppRoot 'evidence/ipad-interaction/scroll-test-settings.json'
function Pump { $window.Dispatcher.Invoke([Action]{},[Windows.Threading.DispatcherPriority]::Background);$window.UpdateLayout() }
try {
 $window.Show();Set-DesktopMode $false;Pump
 $canvas=$window.FindName('CardCanvas');$scroll=$window.FindName('CardScroll')
 $height=$window.FindName('DashboardGrid').Height
 $width=$script:controls.cpu.face.ActualWidth
 $script:cfg.freePlacement=$true
if(-not (Set-CardSlot cpu 10 0)){throw 'Could not place deep card'}
 Apply-DesktopCardLayout;Pump
 if($window.FindName('DashboardGrid').Height -ne $height){throw 'Page viewport grew with content'}
 if([math]::Abs($script:controls.cpu.face.ActualWidth-$width) -gt 1){throw 'Card width shrank'}
 if($scroll.ScrollableHeight -le 0){throw 'No scrollable extent'}
 $scroll.ScrollToVerticalOffset(2000);Pump;Pump
 if($scroll.VerticalOffset -le 0){throw 'Scroll offset did not change'}
 $point=$script:controls.cpu.face.TranslatePoint([Windows.Point]::new(0,0),$scroll)
 if($point.Y -lt -184 -or $point.Y -gt $scroll.ActualHeight){throw 'Deep card cannot scroll into viewport'}
 "PASS: fixed card width=$width fixed viewport=$height extent=$($scroll.ExtentHeight) offset=$($scroll.VerticalOffset); deep card visible"
} finally {$script:exiting=$true;$window.Close();$script:tray.Dispose();$menu.Dispose();$script:trayFont.Dispose();$script:trayBitmap.Dispose()}
