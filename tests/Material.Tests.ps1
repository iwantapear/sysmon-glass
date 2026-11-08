$ErrorActionPreference='Stop'
if([Threading.Thread]::CurrentThread.ApartmentState -ne 'STA'){throw 'Run with -STA'}
$env:SYSMON_CONFIG_HOME=Join-Path $env:TEMP ('sysmon-mat-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $env:SYSMON_CONFIG_HOME -Force | Out-Null
. (Join-Path $PSScriptRoot '../glass.ps1') -PrepareOnly
function Assert($ok,[string]$msg){ if(-not $ok){ throw $msg } }
$window.Visibility='Hidden'; $window.Show()
$window.Dispatcher.Invoke([Action]{},[Windows.Threading.DispatcherPriority]::Background)
function Render-MeanAlpha($element){
    $element.UpdateLayout()
    $w=[int][math]::Ceiling($element.ActualWidth); $h=[int][math]::Ceiling($element.ActualHeight)
    $rtb=[Windows.Media.Imaging.RenderTargetBitmap]::new($w,$h,96,96,[Windows.Media.PixelFormats]::Pbgra32)
    $rtb.Render($element)
    $px=[byte[]]::new($w*$h*4); $rtb.CopyPixels($px,$w*4,0)
    $sum=0L; for($i=3;$i -lt $px.Length;$i+=4){ $sum+=$px[$i] }
    [int]($sum/($w*$h))
}
$face=$script:controls['cpu'].face
$alphas=@{}
foreach($mode in @('glass','frosted','solid')){
    Set-Material $mode $false
    $window.Dispatcher.Invoke([Action]{},[Windows.Threading.DispatcherPriority]::Background)
    $alphas[$mode]=Render-MeanAlpha $face
    Assert ($script:cfg.material -eq $mode) "material $mode not recorded in config"
}
# The three choices must be visibly distinct, not a 6% point spread.
Assert ($alphas['solid'] -gt $alphas['frosted']) "frosted must be more opaque than glass (f=$($alphas['frosted']) s=$($alphas['solid']))"
Assert ($alphas['frosted'] -gt $alphas['glass']) "solid must be the most opaque (g=$($alphas['glass']) f=$($alphas['frosted']))"
Assert (($alphas['solid'] - $alphas['glass']) -ge 25) "glass->solid spread too small: $($alphas['solid']-$alphas['glass']) (expected >= 25 alpha levels)"
$glossGlass=$null; Set-Material 'glass' $false; $window.Dispatcher.Invoke([Action]{},[Windows.Threading.DispatcherPriority]::Background); $glossGlass=$script:controls['cpu'].gloss.Opacity
Set-Material 'solid' $false; $window.Dispatcher.Invoke([Action]{},[Windows.Threading.DispatcherPriority]::Background); $glossSolid=$script:controls['cpu'].gloss.Opacity
Assert ($glossSolid -lt $glossGlass) 'solid must drop the specular gloss'
# Idempotence: the alpha must not compound when the same material is applied twice.
Set-Material 'glass' $false; $window.Dispatcher.Invoke([Action]{},[Windows.Threading.DispatcherPriority]::Background)
$a1=@($script:controls['cpu'].bg.GradientStops | ForEach-Object { $_.Color.A }) -join ','
Set-Material 'glass' $false
$window.Dispatcher.Invoke([Action]{},[Windows.Threading.DispatcherPriority]::Background)
$a2=@($script:controls['cpu'].bg.GradientStops | ForEach-Object { $_.Color.A }) -join ','
Assert ($a1 -eq $a2) "re-applying a material must be idempotent ([$a1] vs [$a2])"
$script:exiting=$true; $window.Close(); $script:tray.Dispose(); $menu.Dispose(); $script:trayFont.Dispose(); $script:trayBitmap.Dispose()
Remove-Item -Path $env:SYSMON_CONFIG_HOME -Recurse -Force -ErrorAction SilentlyContinue
"Material regression PASS: glass=$($alphas['glass']) frosted=$($alphas['frosted']) solid=$($alphas['solid'])"
