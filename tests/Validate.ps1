    Put-Number 'cpu' 53; Put-Number 'dgxGpuT' 48; Put-Number 'cpuDuty' 40
    foreach ($n in 1..3) { $script:history.cpu.Add([double](50+$n)); $script:history.dgx.Add([double](45+$n)) }
    Update-Display
    if ($script:controls.Count -ne $script:defaultCardKeys.Count -or $script:controls['cpu'].number.Text -ne '53' -or
        $script:controls['cpuRpm'].progress.Value -ne 40 -or $script:controls['cpu'].spark.Points.Count -ne 3) { throw 'Card validation failed.' }
    $configPath=Join-Path $env:TEMP ('sysmon-theme-validation-'+[guid]::NewGuid().ToString('N')+'.json')
    Set-Theme 'light' $true
    if($script:controls['cpu'].number.Foreground.Color.R -ne 0x19 -or $script:controls['cpu'].shadow.GradientStops[0].Color.A -le 0) { throw 'Light theme tokens were not applied.' }
    if((Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json).theme -ne 'light') { throw 'Light theme was not persisted to the intended path.' }
    Set-Theme 'dark' $true
    if($script:controls['cpu'].number.Foreground.Color.R -lt 0xF0 -or $script:cfg.theme -ne 'dark') { throw 'Dark theme tokens were not restored.' }
    if((Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json).theme -ne 'dark') { throw 'Dark theme was not persisted to the intended path.' }
    Set-DesktopMode $true $true
    if(-not $script:cfg.desktopMode -or -not $window.IsEnabled) { throw 'Desktop mode was not applied.' }
    if($root.Background -ne [Windows.Media.Brushes]::Transparent -or $window.FindName('DashboardGrid').Height -ne (Get-CardLayoutBaseHeight $true) -or $window.FindName('Header').Visibility -ne [Windows.Visibility]::Collapsed) { throw 'Cards-only layout was not applied.' }
    if($script:controls['cpu'].face.BorderThickness.Top -lt 1 -or $script:controls['cpu'].shadowHost.Visibility -ne [Windows.Visibility]::Collapsed -or $script:controls['cpu'].gloss.Visibility -ne [Windows.Visibility]::Visible) { throw 'Desktop card highlights were not preserved.' }
    if($window.WindowStyle -ne [Windows.WindowStyle]::None) { throw 'Unexpected outer window frame.' }
    if((Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json).desktopMode -ne $true) { throw 'Desktop mode was not persisted.' }
    Set-DesktopMode $false $true
    if($script:cfg.desktopMode -or -not $window.IsEnabled) { throw 'Desktop mode was not released.' }
    if($window.FindName('DashboardGrid').Height -ne (Get-CardLayoutBaseHeight $false) -or $window.FindName('Header').Visibility -ne [Windows.Visibility]::Visible -or $root.Background -isnot [Windows.Media.LinearGradientBrush]) { throw 'Full dashboard was not restored.' }
    if($script:controls['cpu'].face.BorderThickness.Top -lt 1 -or $script:controls['cpu'].shadowHost.Visibility -ne [Windows.Visibility]::Visible) { throw 'Normal glass effects were not restored.' }
    Remove-Item -LiteralPath $configPath -Force
    $historyCount=$script:history.dgx.Count
    $script:values['dgxGpuT']=67
    Read-Values
    if($script:values.ContainsKey('dgxGpuT') -or $script:history.dgx.Count -ne $historyCount) { throw 'Offline DGX data was retained or added to history.' }
    $script:values.Remove('cpu')
    Update-Display
    if($script:controls['cpu'].spark.Visibility -ne [Windows.Visibility]::Collapsed) { throw 'Unavailable CPU sparkline is visible.' }
    'XAML, '+$script:controls.Count+' cards, sample values, offline handling and preset sizing OK'; return
