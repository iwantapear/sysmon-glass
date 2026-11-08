$xaml = Get-Content -LiteralPath (Join-Path $script:AppRoot 'ui/Dashboard.xaml') -Raw
$reader = [System.Xml.XmlReader]::Create([System.IO.StringReader]::new($xaml))
try { $script:window = [Windows.Markup.XamlReader]::Load($reader) } finally { $reader.Dispose() }
$window = $script:window
$root = $window.FindName('Root')
$statusText = $window.FindName('StatusText'); $statusDot = $window.FindName('StatusDot')
$backdropText = $window.FindName('BackdropText')
$script:values = @{}
$script:history = @{ cpu=[Collections.Generic.List[double]]::new(); dgx=[Collections.Generic.List[double]]::new() }
$script:controls = @{}
$script:dgx = [SysMonGlass.DgxPoller]::new(); $script:gpu = [SysMonGlass.GpuPoller]::new()
$script:activeRemoteHost = $null
function Set-RemoteHost([string]$Id, [bool]$Persist=$true) {
    if([string]::IsNullOrEmpty($Id)) {
        $script:dgx.Stop()
        $script:activeRemoteHost=$null; $script:cfg.activeHostId=''
        foreach($key in @($script:values.Keys)) { if($key -like 'dgx*'){$script:values.Remove($key)} }
        $script:history.dgx.Clear()
        if($Persist) { Save-Config }
        return
    }
    $candidate=@($script:cfg.hosts | Where-Object { $_.enabled -and $_.id -eq $Id } | Select-Object -First 1)
    if($candidate.Count -eq 0) { throw "Remote host is not enabled or does not exist: $Id" }
    $selected=ConvertTo-RemoteHostProfile $candidate[0]
    $script:dgx.Stop()
    $script:dgx.Configure($selected.sshHost,$selected.user,[int]$selected.port,$selected.probe)
    $script:activeRemoteHost=$selected; $script:cfg.activeHostId=$selected.id
    foreach($key in @($script:values.Keys)) { if($key -like 'dgx*'){$script:values.Remove($key)} }
    $script:history.dgx.Clear()
    if($script:remotePollingStarted) { $script:dgx.Start() }
    if($Persist) { Save-Config }
}
$initial=@($script:cfg.hosts | Where-Object { $_.enabled -and $_.id -eq $script:cfg.activeHostId } | Select-Object -First 1)
if($initial.Count -gt 0) { $script:dgx.Configure($initial[0].sshHost,$initial[0].user,[int]$initial[0].port,$initial[0].probe); $script:activeRemoteHost=$initial[0] }

