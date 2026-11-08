function Show-RemoteHostSettings {
    $dialog=[Windows.Forms.Form]::new()
    $dialog.Text='远程主机 · SSH 配置'; $dialog.Width=660; $dialog.Height=640
    $dialog.StartPosition='CenterScreen'; $dialog.FormBorderStyle='FixedDialog'; $dialog.MaximizeBox=$false; $dialog.MinimizeBox=$false
    $list=[Windows.Forms.ListBox]::new(); $list.SetBounds(18,18,585,110)
    $dialog.Controls.Add($list)
    $fields=@{}
    $labels=@(@('id','配置 ID'),@('name','显示名称'),@('sshHost','SSH 别名 / 主机名'),@('user','用户名（可留空）'),@('port','端口'),@('probe','POSIX 探针路径'))
    $row=0
    foreach($entry in $labels) {
        $label=[Windows.Forms.Label]::new(); $label.Text=$entry[1]; $label.SetBounds(18,(145+$row*34),165,26); $dialog.Controls.Add($label)
        $input=[Windows.Forms.TextBox]::new(); $input.SetBounds(190,(142+$row*34),413,26); $dialog.Controls.Add($input); $fields[$entry[0]]=$input; $row++
    }
    $help=[Windows.Forms.Label]::new(); $help.Text='填 IP 或主机名即可（支持 user@host、IPv6）。密钥登录，不保存密码。三步：信任主机密钥 → 部署探针 → 测试连接。'; $help.SetBounds(18,352,625,36); $dialog.Controls.Add($help)
    $statusBox=[Windows.Forms.TextBox]::new(); $statusBox.Multiline=$true; $statusBox.ReadOnly=$true; $statusBox.ScrollBars='Vertical'
    $statusBox.SetBounds(18,392,620,96); $statusBox.BackColor=[Drawing.Color]::FromArgb(28,32,40); $statusBox.ForeColor=[Drawing.Color]::FromArgb(210,225,240)
    $statusBox.Font=[Drawing.Font]::new('Consolas',9); $dialog.Controls.Add($statusBox)
    $trust=[Windows.Forms.Button]::new(); $trust.Text='① 信任主机密钥'; $trust.SetBounds(18,500,132,32); $dialog.Controls.Add($trust)
    $deploy=[Windows.Forms.Button]::new(); $deploy.Text='② 部署探针'; $deploy.SetBounds(156,500,120,32); $dialog.Controls.Add($deploy)
    $test=[Windows.Forms.Button]::new(); $test.Text='③ 测试连接'; $test.SetBounds(282,500,110,32); $dialog.Controls.Add($test)
    $new=[Windows.Forms.Button]::new(); $new.Text='新增'; $new.SetBounds(18,544,90,32); $dialog.Controls.Add($new)
    $remove=[Windows.Forms.Button]::new(); $remove.Text='删除'; $remove.SetBounds(114,544,90,32); $dialog.Controls.Add($remove)
    $save=[Windows.Forms.Button]::new(); $save.Text='保存并连接'; $save.SetBounds(398,544,132,32); $dialog.Controls.Add($save)
    $close=[Windows.Forms.Button]::new(); $close.Text='关闭'; $close.SetBounds(536,544,100,32); $dialog.Controls.Add($close)
    $script:hostSettingsList=$list; $script:hostSettingsFields=$fields; $script:hostSettingsStatus=$statusBox
    $report={ param([string]$text) $script:hostSettingsStatus.Text=$text; $script:hostSettingsStatus.SelectionStart=$script:hostSettingsStatus.Text.Length; $script:hostSettingsStatus.ScrollToCaret() }
    $current={ param($f) @{ host=$f.sshHost.Text.Trim(); user=$f.user.Text.Trim(); port=(& { $p=0; if([int]::TryParse($f.port.Text,[ref]$p)){$p}else{22} }); probe=$f.probe.Text.Trim() } }
    $refresh={
        $script:hostSettingsList.Items.Clear()
        foreach($profile in @($script:cfg.hosts)) { $null=$script:hostSettingsList.Items.Add([string]$profile.id) }
    }
    & $refresh
    $list.Add_SelectedIndexChanged({
        $id=[string]$script:hostSettingsList.SelectedItem
        $profile=@($script:cfg.hosts | Where-Object id -eq $id | Select-Object -First 1)
        if($profile.Count) { foreach($key in @('id','name','sshHost','user','port','probe')) { $script:hostSettingsFields[$key].Text=[string]$profile[0][$key] } }
    })
    $new.Add_Click({
        $script:hostSettingsList.ClearSelected()
        foreach($key in @('id','name','sshHost','user','port','probe')) { $script:hostSettingsFields[$key].Text='' }
        $script:hostSettingsFields.port.Text='22'; $script:hostSettingsFields.probe.Text='~/.sysmon.sh'
    })
    $save.Add_Click({
        try {
            $f=$script:hostSettingsFields
            $port=0; if(-not [int]::TryParse($f.port.Text,[ref]$port)){throw '端口必须是整数。'}
            $profile=ConvertTo-RemoteHostProfile @{id=$f.id.Text;name=$f.name.Text;sshHost=$f.sshHost.Text;user=$f.user.Text;port=$port;probe=$f.probe.Text;enabled=$true}
            $script:cfg.hosts=@($script:cfg.hosts | Where-Object { $_.id -ne $profile.id })+@($profile)
            Set-RemoteHost $profile.id $true
            $script:hostSettingsList.Items.Clear()
            foreach($p in @($script:cfg.hosts)) { $null=$script:hostSettingsList.Items.Add([string]$p.id) }
            $script:hostSettingsList.SelectedItem=$profile.id
        } catch { [Windows.Forms.MessageBox]::Show($_.Exception.Message,'远程主机配置')|Out-Null }
    })
    $remove.Add_Click({
        $id=[string]$script:hostSettingsList.SelectedItem
        if(-not $id){return}
        $script:cfg.hosts=@($script:cfg.hosts | Where-Object { $_.id -ne $id })
        Initialize-RemoteHosts
        Set-RemoteHost ([string]$script:cfg.activeHostId) $true
        $script:hostSettingsList.Items.Clear()
        foreach($p in @($script:cfg.hosts)) { $null=$script:hostSettingsList.Items.Add([string]$p.id) }
    })
    $trust.Add_Click({
        $c=& $current $script:hostSettingsFields
        try { $r=Trust-RemoteHostKey $c.host $c.port; & $report ("信任主机密钥：新增 {0} / 共 {1} 条`r`n{2}" -f $r.added,$r.total,$r.sample) }
        catch { & $report ("信任主机密钥失败：`r`n" + $_.Exception.Message) }
    })
    $deploy.Add_Click({
        $c=& $current $script:hostSettingsFields
        try { $r=Deploy-RemoteProbe $c.host $c.user $c.port $c.probe; & $report ("探针已部署到 {0}（{1} 字节，权限 700）" -f $r.path,$script:remoteProbeScript.Length) }
        catch { & $report ("部署探针失败：`r`n" + $_.Exception.Message) }
    })
    $test.Add_Click({
        $c=& $current $script:hostSettingsFields
        try { $r=Test-RemoteConnection $c.host $c.user $c.port $c.probe; & $report ("连接成功，收到字段：{0}`r`n--- 探针输出 ---`r`n{1}" -f ($r.keys -join ','),$r.sample) }
        catch { & $report ("测试连接失败：`r`n" + $_.Exception.Message) }
    })
    $close.Add_Click({ $script:hostSettingsList.FindForm().Close() })
    try { $null=$dialog.ShowDialog() } finally { $dialog.Dispose(); $script:hostSettingsList=$null; $script:hostSettingsFields=$null }
}
