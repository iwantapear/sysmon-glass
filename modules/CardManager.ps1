if(-not $script:defaultCardKeys){$script:defaultCardKeys=@('cpu','gpuT','cpuRpm','caseRpm','pumpRpm','vrm','dgxGpuT','dgxCpu','dgxFan','dgxNvme','dgxMem','dgxLoad','netDown','netUp','diskPct')}
function Show-CardManager {
    $dialog=[Windows.Window]::new();$dialog.Title='卡片管理 / Card manager';$dialog.Width=580;$dialog.WindowStartupLocation='CenterOwner';$dialog.Owner=$window
    # Size to the screen: the list is taller than any fixed dialog, and the System
    # group lives at the bottom, so a clipped view made network/disk look "missing".
    $area=[Windows.SystemParameters]::WorkArea
    $dialog.Height=[math]::Min(820,[math]::Max(420,$area.Height*0.82))
    $scroll=[Windows.Controls.ScrollViewer]::new()
    $scroll.VerticalScrollBarVisibility='Visible'
    $panel=[Windows.Controls.StackPanel]::new();$panel.Margin=18
    $total=@($script:cardCatalog).Count
    $hint=[Windows.Controls.TextBlock]::new();$hint.Text=((L 'cardManagerHint') -f $total);$hint.FontSize=12;$hint.Opacity=0.75;$hint.Margin='0,0,0,4';$panel.Children.Add($hint)|Out-Null
    foreach($group in @(@('本机 / Local',($script:cardCatalog|Where-Object side -eq 'L')),@('远程 / Remote',($script:cardCatalog|Where-Object side -eq 'R')),@('系统 / System',($script:cardCatalog|Where-Object side -eq 'S')))){
        $title=[Windows.Controls.TextBlock]::new();$title.Text=$group[0];$title.FontSize=18;$title.Margin='0,12,0,8';$panel.Children.Add($title)|Out-Null
        foreach($cell in @($group[1])){$cb=[Windows.Controls.CheckBox]::new();$cb.Content=if($cell.labelKey){L $cell.labelKey}else{$cell.key};$cb.Tag=$cell.key;$cb.IsChecked=($cards.key -contains $cell.key);$cb.Margin='4,4,4,4';$panel.Children.Add($cb)|Out-Null}
    }
    $buttons=[Windows.Controls.StackPanel]::new();$buttons.Orientation='Horizontal';$buttons.HorizontalAlignment='Right';$ok=[Windows.Controls.Button]::new();$ok.Content='应用 / Apply';$ok.Margin='4';$cancel=[Windows.Controls.Button]::new();$cancel.Content='取消 / Cancel';$cancel.Margin='4';$buttons.Children.Add($cancel)|Out-Null;$buttons.Children.Add($ok)|Out-Null;$panel.Children.Add($buttons)|Out-Null;$scroll.Content=$panel;$dialog.Content=$scroll
    $cancel.Add_Click({$dialog.DialogResult=$false;$dialog.Close()});$ok.Add_Click({$keys=@($panel.Children|Where-Object {$_ -is [Windows.Controls.CheckBox] -and $_.IsChecked}|ForEach-Object Tag);if(-not $keys){$keys=$defaultCardKeys};$script:cfg.enabledCards=$keys;Set-ActiveCards $keys;$dialog.DialogResult=$true;$dialog.Close()});$dialog.ShowDialog()|Out-Null
}
function Set-ActiveCards([string[]]$Keys) {
    $valid=@($script:cardCatalog|Where-Object {$_.key -in $Keys});$script:cfg.enabledCards=@($valid.key);$script:cards=@($valid)
    foreach($ctl in $script:controls.Values){if($ctl.surface.Parent){$ctl.surface.Parent.Children.Remove($ctl.surface)}}
    $script:controls=@{}
    foreach($name in @('LocalCards','RemoteCards','SystemCards')){$p=$window.FindName($name);$p.Children.Clear()}
    foreach($cell in $script:cards){New-Card $cell};Initialize-CardLayoutConfig;Initialize-CardSlots;Update-CardLayoutMetrics
    if($script:cfg.desktopMode -or $script:cardEditing -or $script:cfg.customLayout){Apply-DesktopCardLayout}else{Restore-NormalCardLayout};Update-CardLabels;Set-Theme $script:cfg.theme;Update-Display
}
