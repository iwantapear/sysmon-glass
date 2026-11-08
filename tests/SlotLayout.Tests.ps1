param()
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '../glass.ps1') -PrepareOnly
function A($c,$m){if(-not $c){throw $m}}
try {
 A ($cards.Count -eq $script:defaultCardKeys.Count) 'card count'
 Initialize-CardSlots
 A ($script:cfg.cardSlots.Count -eq $cards.Count) 'slots migration'
 $before=Copy-CardSlots
 A (Set-CardSlot 'cpu' 4 3) 'empty slot placement'
 A ($script:cfg.cardSlots.cpu.row -eq 4 -and $script:cfg.cardSlots.cpu.column -eq 3) 'hole not retained'
 A ((Get-CardPacking $script:cardOrder 4 | Where-Object key -eq cpu).row -eq 4) 'packing lost explicit row'
 $shape=(Get-CardShape 'cpu'); Set-CardShape cpu long $false|Out-Null
 A ((Get-CardShape cpu)-eq 'long') 'shape'
 A (-not (Set-CardSlot cpu 0 3)) 'long overflow accepted'
 $seen=@{}
 foreach($p in Get-CardPacking $script:cardOrder 4){$span=$p.span;for($c=$p.column;$c -lt $p.column+$span;$c++){A (-not $seen.ContainsKey("$($p.row):$c")) "overlap $($p.key)";$seen["$($p.row):$c"]=$p.key}}
 A ($script:desktopCardRows -ge 5) 'minimum blank rows'
 'PASS: slot migration, empty drop, long bounds and non-overlap'
} finally {$script:exiting=$true;$window.Close();if($script:tray){$script:tray.Dispose()};if($menu){$menu.Dispose()};if($script:trayFont){$script:trayFont.Dispose()};if($script:trayBitmap){$script:trayBitmap.Dispose()}}
