param([string]$EvidenceDir=(Join-Path $PSScriptRoot '../evidence/ipad-interaction'))
$ErrorActionPreference='Stop'
# Isolated config: real-mouse drags persist layout and must not touch the repo's sysmon.json.
$env:SYSMON_CONFIG_HOME=Join-Path $env:TEMP ('sysmon-ipad-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $env:SYSMON_CONFIG_HOME -Force | Out-Null
. (Join-Path $PSScriptRoot '../glass.ps1') -PrepareOnly
$configPath=Join-Path $EvidenceDir 'test-settings.json'
[IO.Directory]::CreateDirectory([IO.Path]::GetFullPath($EvidenceDir))|Out-Null
Add-Type @'
using System; using System.Runtime.InteropServices;
public static class IPadMouse {
 [DllImport("user32.dll")]public static extern bool SetCursorPos(int x,int y);
 [DllImport("user32.dll")]public static extern void mouse_event(uint f,uint x,uint y,uint d,UIntPtr e);
}
'@
function Pump([int]$ms=200) {
 $until=[datetime]::UtcNow.AddMilliseconds($ms)
 do {$window.Dispatcher.Invoke([Action]{},[Windows.Threading.DispatcherPriority]::Background)} while([datetime]::UtcNow -lt $until)
}
function Assert($ok,$msg){if(-not $ok){throw $msg};Write-Output "PASS: $msg"}
function Point($element){$element.PointToScreen([Windows.Point]::new($element.ActualWidth/2,$element.ActualHeight/2))}
function Click($point,[bool]$right=$false){[IPadMouse]::SetCursorPos([int]$point.X,[int]$point.Y)|Out-Null;Pump 80;[IPadMouse]::mouse_event($(if($right){8}else{2}),0,0,0,[UIntPtr]::Zero);Pump 70;[IPadMouse]::mouse_event($(if($right){16}else{4}),0,0,0,[UIntPtr]::Zero);Pump 250}
function Drag($a,$b){[IPadMouse]::SetCursorPos([int]$a.X,[int]$a.Y)|Out-Null;Pump 80;[IPadMouse]::mouse_event(2,0,0,0,[UIntPtr]::Zero);try{Pump 100;foreach($i in 1..15){[IPadMouse]::SetCursorPos([int]($a.X+($b.X-$a.X)*$i/15),[int]($a.Y+($b.Y-$a.Y)*$i/15))|Out-Null;Pump 35}}finally{[IPadMouse]::mouse_event(4,0,0,0,[UIntPtr]::Zero)};Pump 300}
function MenuItem($action){@($script:cardContextMenu.Items | Where-Object {$_ -is [Windows.Controls.MenuItem] -and $_.Tag.action -eq $action})[0]}
try {
 $window.Show();Pump 400
 # The insights rail claims the last canvas lane; these interaction tests target
 # 4-column geometry, so turn the rail off for the duration.
 $script:cfg.insightsRail=$false;if(Get-Command Update-InsightsRailLayout -ErrorAction SilentlyContinue){Update-InsightsRailLayout}
 foreach($desktop in @($false,$true)){
  Set-DesktopMode $desktop;Pump 400
  # Put the test window above the editor so native pointers reach actual cards.
  $window.Topmost=$true;Pump 200
  if($script:cfg.cardSlots.cpu){$window.FindName('CardScroll').ScrollToVerticalOffset([double]$script:cfg.cardSlots.cpu.row*200);Pump 300}
  $face=$script:controls.cpu.face
  Click (Point $face) $true
  Assert ($script:cardContextMenu.IsOpen) "right click opens WPF menu desktop=$desktop"
  $edit=MenuItem 'edit';Assert ($null -ne $edit) 'menu contains edit cards'
  Click (Point $edit)
  Assert $script:cardEditing "actual menu click enters card edit desktop=$desktop"
  Assert (-not $script:desktopAdjusting) 'card editing is not panel positioning'
  Assert $script:controls.cpu.sizeButton.IsVisible 'visible card size control'
  $oldShape=Get-CardShape cpu
  Click (Point $script:controls.cpu.sizeButton)
  Assert ((Get-CardShape cpu) -ne $oldShape) "actual size button toggles shape desktop=$desktop"
  Set-CardShape cpu short $false|Out-Null;Pump 200
  $oldOrder=$script:cardOrder -join ','
  $oldSlot=if($script:cfg.cardSlots[$script:controls.cpu.cell.key]){"$($script:cfg.cardSlots[$script:controls.cpu.cell.key].row),$($script:cfg.cardSlots[$script:controls.cpu.cell.key].column)"}else{''}
  $a=Point $script:controls.cpu.face;$b=Point $script:controls.gpuT.face
  $hwnd=([Windows.Interop.WindowInteropHelper]::new($window)).Handle
  $oldBounds=[SysMonGlass.Native]::GetWindowBounds($hwnd)
  Drag $a $b
  $newSlot=if($script:cfg.cardSlots[$script:controls.cpu.cell.key]){"$($script:cfg.cardSlots[$script:controls.cpu.cell.key].row),$($script:cfg.cardSlots[$script:controls.cpu.cell.key].column)"}else{''}
  Assert ((($script:cardOrder -join ',') -ne $oldOrder) -or ($newSlot -ne $oldSlot)) "actual card drag changes slot/order desktop=$desktop"
  $bounds=[SysMonGlass.Native]::GetWindowBounds($hwnd)
  Assert ($bounds.Left -eq $oldBounds.Left -and $bounds.Top -eq $oldBounds.Top) 'card drag never moves whole panel'
  $canvas=$window.FindName('CardCanvas')
  # Drop into the first free 1x1 slot: a fixed target breaks whenever the
  # loaded layout happens to occupy it (long cards span two columns).
  $free=$null
  for($r=0;$r -lt 12 -and -not $free;$r++){ for($c=0;$c -lt 4 -and -not $free;$c++){ if(Test-CardSlotFree $script:cfg.cardSlots 'cpu' $r $c 1){$free=@{row=$r;column=$c}} } }
  if(-not $free){throw 'no free slot for empty-drop test'}
  $destination=$canvas.PointToScreen([Windows.Point]::new($free.column*376+188,$free.row*200+85))
  Drag (Point $script:controls.cpu.face) $destination
  Write-Output ("EMPTY target={0},{1} screen={2},{3} result={4},{5} gesture={6}" -f $free.column,$free.row,$destination.X,$destination.Y,$script:cfg.cardSlots.cpu.row,$script:cfg.cardSlots.cpu.column,([bool]$script:cardGesture))
  Assert ($script:cfg.cardSlots.cpu.row -eq $free.row -and $script:cfg.cardSlots.cpu.column -eq $free.column) "real mouse drop retains empty slot desktop=$desktop"
  Click (Point $window.FindName('DesktopAdjustDone'))
  Assert (-not $script:cardEditing) "actual Done exits edit desktop=$desktop"
  Assert (-not $script:controls.cpu.sizeButton.IsVisible) 'size controls hide after Done'
  Assert ((Get-Content $configPath -Raw|ConvertFrom-Json).cardOrder.Count -eq $cards.Count) 'order persisted'
 }
 'PASS: real mouse normal+desktop context menu/edit/size/drag/Done regression'
} finally {
 if($script:cardContextMenu){$script:cardContextMenu.IsOpen=$false}
 if($script:cardEditing){Complete-Editing}
 $script:exiting=$true;$window.Close()
 $script:tray.Dispose();$menu.Dispose();$script:trayFont.Dispose();$script:trayBitmap.Dispose()
 Remove-Item -Path $env:SYSMON_CONFIG_HOME -Recurse -Force -ErrorAction SilentlyContinue
}
