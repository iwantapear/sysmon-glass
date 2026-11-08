$ErrorActionPreference='Stop'
if([Threading.Thread]::CurrentThread.ApartmentState -ne 'STA'){throw 'Run with -STA'}
$env:SYSMON_CONFIG_HOME=Join-Path $env:TEMP ('sysmon-catalog-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $env:SYSMON_CONFIG_HOME -Force | Out-Null
. (Join-Path $PSScriptRoot '../glass.ps1') -PrepareOnly
function Assert($ok,[string]$msg){ if(-not $ok){ throw $msg } }

# 1) Catalog integrity: unique keys, every card has a side and a resolvable label.
$keys=@($script:cardCatalog.key)
Assert ($keys.Count -eq @($keys | Select-Object -Unique).Count) 'catalog keys must be unique'
Assert (@($script:cardCatalog | Where-Object { $_.side -notin @('L','R','S') }).Count -eq 0) 'every catalog card needs a side'
$blank=@()
foreach($cell in $script:cardCatalog){
    if(-not $cell.labelKey){ continue }
    $label=L $cell.labelKey
    if([string]::IsNullOrWhiteSpace([string]$label) -or $label -eq $cell.labelKey -and $cell.labelKey -match '^[a-z]'){ $blank+=$cell.key }
}
Assert ($blank.Count -eq 0) ("catalog cards without a locale label: " + ($blank -join ', '))

# 2) Enabled set must be a subset of the catalog, and the live cards must match it.
$cfgKeys=@($script:cfg.enabledCards | Where-Object { $_ })
if($cfgKeys.Count -gt 0){
    $unknown=@($cfgKeys | Where-Object { $_ -notin $keys })
    Assert ($unknown.Count -eq 0) ("enabled cards missing from the catalog (silently dropped): " + ($unknown -join ', '))
}
Assert ($cards.Count -eq $script:controls.Count) "live card count ($($cards.Count)) must match created controls ($($script:controls.Count))"
foreach($cell in $cards){ Assert ($script:controls.ContainsKey($cell.key)) "card $($cell.key) has no control" }

# 3) Every live card is placed: a slot and an order entry must exist.
Initialize-CardLayoutConfig
foreach($key in $cards.key){
    Assert ($script:cardOrder -contains $key) "card $key missing from the running order"
}
Initialize-CardSlots
foreach($key in $cards.key){
    Assert ($script:cfg.cardSlots.ContainsKey($key)) "card $key never received a slot"
}

# 4) Network info: download and upload both exist as default cards, and the wait text is used.
Assert (@($cards | Where-Object { $_.key -eq 'netDown' }).Count -eq 1) 'download card missing from the defaults'
Assert (@($cards | Where-Object { $_.key -eq 'netUp' }).Count -eq 1) 'upload card missing from the defaults'
$netCard=$cards | Where-Object { $_.key -eq 'netDown' } | Select-Object -First 1
$script:values.Remove('netDown')
$presentation=& $netCard.presentation
Assert ($presentation.Detail -eq (L 'networkWait')) 'download card must ask for samples instead of inventing a value'
$upCard=$cards | Where-Object { $_.key -eq 'netUp' } | Select-Object -First 1
$script:values.Remove('netUp')
$upPresentation=& $upCard.presentation
Assert ($upPresentation.Detail -eq (L 'networkWait')) 'upload card must ask for samples instead of inventing a value'

# 5) The manager dialog must be tall enough to reach the System group, with a visible scrollbar.
$area=[Windows.SystemParameters]::WorkArea
$expected=[math]::Min(820,[math]::Max(420,$area.Height*0.82))
Assert ($expected -ge 420) 'dialog height must stay usable on small screens'
$hint=L 'cardManagerHint'
Assert ($hint -match '\{0\}') 'the item-count hint must carry a placeholder'

$script:exiting=$true; $window.Close(); $script:tray.Dispose(); $menu.Dispose(); $script:trayFont.Dispose(); $script:trayBitmap.Dispose()
Remove-Item -Path $env:SYSMON_CONFIG_HOME -Recurse -Force -ErrorAction SilentlyContinue
"Catalog regression PASS: $($script:cardCatalog.Count) catalog / $($cards.Count) live cards / 0 unplaced"
