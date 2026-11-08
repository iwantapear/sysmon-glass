$script:tray=[Windows.Forms.NotifyIcon]::new(); $script:tray.Visible=$true
$script:trayBitmap=[Drawing.Bitmap]::new(16,16); $script:trayFont=[Drawing.Font]::new('Segoe UI',10,[Drawing.FontStyle]::Bold,[Drawing.GraphicsUnit]::Pixel)
$script:trayIcon=$null
function Update-Tray {
    $t=if($script:values.ContainsKey('cpu')) { $script:values['cpu'] } else { $null }
    $color=if($null -eq $t){[Drawing.Color]::LightGray} elseif($t -ge 80){[Drawing.Color]::Salmon} elseif($t -ge 65){[Drawing.Color]::Gold} else {[Drawing.Color]::LightGreen}
    $g=[Drawing.Graphics]::FromImage($script:trayBitmap); $brush=[Drawing.SolidBrush]::new($color)
    try { $g.Clear([Drawing.Color]::Transparent); $text=if($null -eq $t){'--'}else{[string][math]::Min(99,[int][math]::Round($t))}; $sz=$g.MeasureString($text,$script:trayFont); $g.DrawString($text,$script:trayFont,$brush,(16-$sz.Width)/2,(16-$sz.Height)/2) } finally { $brush.Dispose(); $g.Dispose() }
    $handle=$script:trayBitmap.GetHicon()
    try { $temp=[Drawing.Icon]::FromHandle($handle); $icon=[Drawing.Icon]$temp.Clone() } finally { [SysMonGlass.Native]::DestroyIcon($handle)|Out-Null }
    $old=$script:trayIcon; $script:trayIcon=$icon; $script:tray.Icon=$icon; if($old){$old.Dispose()}
    $remote=if($script:dgx.AgeSec -ge 0 -and $script:dgx.AgeSec -lt 8){Format-Value 'dgxGpuT'}else{'—'}
    $script:tray.Text=((L 'trayStatus') -f (Format-Value 'cpu'),(Format-Value 'gpuT'),$remote)
}
function Toggle-Window {
    if($window.IsVisible) { Hide-Panel; return }
    $window.Show()
    if($script:cfg.desktopMode) {
        $hwnd=([Windows.Interop.WindowInteropHelper]::new($window)).Handle
        if($hwnd -ne [IntPtr]::Zero) {
            if($script:desktopAdjusting) { [SysMonGlass.Native]::SetDesktopAdjustment($hwnd,$true) }
            else { [SysMonGlass.Native]::SetDesktopMode($hwnd,$true) }
        }
        Apply-Preset -UseCurrentPosition:$script:desktopAdjusting
    } else { $window.Activate()|Out-Null }
}
$script:tray.Add_MouseDoubleClick({ Toggle-Window })
$menu=[Windows.Forms.ContextMenuStrip]::new(); $toggleItem=$menu.Items.Add((L 'toggleWindow')); $toggleItem.Add_Click({ Toggle-Window })
$desktopMenuItem=$menu.Items.Add($(if($script:cfg.desktopMode){L 'exitDesktop'}else{L 'desktopMode'}))
$desktopMenuItem.Checked=[bool]$script:cfg.desktopMode
$desktopMenuItem.Add_Click({ Set-WindowLayer $(if($script:cfg.desktopMode){'normal'}else{'bottom'}) $true })
$positionMenuItem=$menu.Items.Add('编辑卡片 / Edit cards')
$positionMenuItem.Enabled=$true
$positionMenuItem.Add_Click({ if($script:cardEditing){Complete-Editing}else{Set-CardEditing $true} })
$movePanelMenuItem=$menu.Items.Add('移动面板 / Move panel')
$movePanelMenuItem.Enabled=[bool]$script:cfg.desktopMode
$movePanelMenuItem.Add_Click({if($script:cardEditing){Complete-Editing};Set-DesktopAdjustment (-not [bool]$script:desktopAdjusting)})
$res=[Windows.Forms.ToolStripMenuItem]::new((L 'scale'))
function Update-ScaleMenu {
    $manualScale=if($script:desktopAdjusting){$script:desktopDraftScale}else{$script:cfg.desktopScale}
    $manual=if($script:cfg.desktopMode){$null -ne $manualScale}else{$script:cfg.normalWidthDip -and $script:cfg.normalHeightDip}
    $res.Text=if($manual){L 'manualScale'}else{L 'scale'}
    foreach($item in $res.DropDownItems) { $item.Checked=(-not $manual -and $item.Tag -eq $script:cfg.preset) }
}
foreach($p in @('auto','1080p','2k','4k')) {
    $mi=[Windows.Forms.ToolStripMenuItem]::new($(if($p -eq 'auto'){L 'autoScale'}else{$p.ToUpper()}))
    $mi.Tag=$p
    $mi.Add_Click({
        param($s,$e)
        $script:cfg.preset=[string]$s.Tag
        if($script:cfg.desktopMode) {
            $script:cfg.Remove('desktopScale')
            $script:desktopDraftScale=$null
        } else {
            $script:cfg.Remove('normalWidthDip'); $script:cfg.Remove('normalHeightDip')
        }
        Apply-Preset -UseCurrentPosition
        Update-ScaleMenu
        Save-Config
    })
    $res.DropDownItems.Add($mi)|Out-Null
}
Update-ScaleMenu
$menu.Items.Add($res)|Out-Null
$rate=[Windows.Forms.ToolStripMenuItem]::new((L 'refresh'))
foreach($iv in @(1000,2000,3000,5000)) { $mi=[Windows.Forms.ToolStripMenuItem]::new(((L 'seconds') -f ($iv/1000))); $mi.Tag=$iv; $mi.Checked=$iv -eq [int]$script:cfg.interval; $mi.Add_Click({param($s,$e) $script:cfg.interval=[int]$s.Tag; $script:timer.Interval=[TimeSpan]::FromMilliseconds([int]$s.Tag); foreach($i in $s.Owner.Items){$i.Checked=($i -eq $s)}; Save-Config}); $rate.DropDownItems.Add($mi)|Out-Null }
$menu.Items.Add($rate)|Out-Null
$themeMenu=[Windows.Forms.ToolStripMenuItem]::new((L 'theme'))
foreach($id in $script:themeOrder) {
    $option=[Windows.Forms.ToolStripMenuItem]::new((L $id))
    $option.Tag=$id; $option.Checked=$id -eq $script:cfg.theme
    $option.Add_Click({param($s,$e) Set-Theme ([string]$s.Tag) $true})
    $themeMenu.DropDownItems.Add($option)|Out-Null
}
$menu.Items.Add($themeMenu)|Out-Null
$languageMenu=[Windows.Forms.ToolStripMenuItem]::new((L 'language'))
foreach($id in $script:languages.Keys) {
    $option=[Windows.Forms.ToolStripMenuItem]::new($script:languages[$id])
    $option.Tag=$id; $option.Checked=$id -eq $script:cfg.language
    $option.Add_Click({param($s,$e) Set-Language ([string]$s.Tag) $true})
    $languageMenu.DropDownItems.Add($option)|Out-Null
}
$menu.Items.Add($languageMenu)|Out-Null
$remoteHostsItem=$menu.Items.Add('远程主机 / Remote hosts…')
$remoteHostsItem.Add_Click({ Show-RemoteHostSettings })
$cardManagerItem=$menu.Items.Add('硬件卡片 / Hardware cards…')
$cardManagerItem.Add_Click({ Show-CardManager })
$exit=$menu.Items.Add((L 'exit'))
$exit.Add_Click({ $script:exiting=$true; $window.Close() })
$script:tray.ContextMenuStrip=$menu
$menu.Add_Closed({ if($script:desktopContext) { $script:desktopContext.ClearMenuBounds() } })

function Update-MenuText {
    $toggleItem.Text=L 'toggleWindow'
    $desktopMenuItem.Text=if($script:cfg.desktopMode){L 'exitDesktop'}else{L 'desktopMode'}
    $positionMenuItem.Text=if($script:cardEditing){'完成编辑 / Done'}else{'编辑卡片 / Edit cards'}
    $movePanelMenuItem.Text=if($script:desktopAdjusting){'完成移动 / Done'}else{'移动面板 / Move panel'}
    $movePanelMenuItem.Enabled=[bool]$script:cfg.desktopMode
    Update-ScaleMenu
    $res.DropDownItems[0].Text=L 'autoScale'
    $rate.Text=L 'refresh'
    foreach($option in $rate.DropDownItems){$option.Text=(L 'seconds') -f ($option.Tag/1000)}
    $themeMenu.Text=L 'theme'
    foreach($option in $themeMenu.DropDownItems){$option.Text=L $option.Tag}
    $languageMenu.Text=L 'language'
    foreach($option in $languageMenu.DropDownItems){$option.Checked=$option.Tag -eq $script:cfg.language}
    $exit.Text=L 'exit'
}

function Show-DesktopContextMenu([Drawing.Point]$Point) {
    if($script:cardDetailPopup){$script:cardDetailPopup.IsOpen=$false}
    Show-PanelContextMenu
}
