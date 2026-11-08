$script:timer=[Windows.Threading.DispatcherTimer]::new(); $script:timer.Interval=[TimeSpan]::FromMilliseconds([int]$script:cfg.interval)
$script:timer.Add_Tick({ Read-Values; Update-Display; Update-Tray; Update-InsightsData })
$window.Add_Closed({ $window.Dispatcher.BeginInvokeShutdown([Windows.Threading.DispatcherPriority]::Background) })
# A modeless window plus a dispatcher loop keeps the tray alive when the window is hidden.
try { $script:remotePollingStarted=$true; if($script:activeRemoteHost){$script:dgx.Start()}; $script:gpu.Start(); Start-InsightsTopProcesses; Read-Values; Update-Display; Update-Tray; Update-InsightsData; $script:timer.Start(); $window.Show(); if($script:cfg.desktopMode){Apply-Preset}; [Windows.Threading.Dispatcher]::Run() }
finally {
    $script:timer.Stop(); $script:dgx.Stop(); $script:gpu.Stop(); Stop-InsightsTopProcesses
    $script:tray.Visible=$false; $script:tray.Dispose(); $menu.Dispose()
    if($script:trayIcon){$script:trayIcon.Dispose()}; $script:trayFont.Dispose(); $script:trayBitmap.Dispose()
}
