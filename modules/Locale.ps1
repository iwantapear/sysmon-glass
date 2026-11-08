$script:languages=[ordered]@{'zh-CN'='简体中文';'zh-TW'='繁體中文';en='English'}
$script:strings=@{}
foreach($entry in (Import-Csv -LiteralPath (Join-Path $script:AppRoot 'locale/strings.psv') -Delimiter '|')) {
    $script:strings[$entry.Key]=$entry
}
function L([string]$Key) {
    $entry=$script:strings[$Key]
    if(-not $entry){return $Key}
    $language=$script:cfg.language
    if($language -and $entry.$language){return $entry.$language}
    return $entry.'zh-CN'
}
function Update-CardLabels {
    foreach($ctl in $script:controls.Values) {
        $label=if($ctl.cell.labelKey){L $ctl.cell.labelKey}else{$ctl.cell.label}
        if($ctl.cell.side -in @('L','R') -or $ctl.cell.side -eq 'S') {
            $device=if($ctl.cell.side -eq 'R'){'DGX'}else{L 'localMachine'}
            $label="$device · $label"
        }
        $ctl.label.Text=$label
    }
}
function Update-BackdropLabel {
    # The backdrop badge ("亚克力") carried no action and cluttered the footer corner.
    $backdropText.Text=''
    $backdropText.Visibility='Collapsed'
}
function Set-Language([string]$Language,[bool]$Persist=$false) {
    if(-not $script:languages.Contains($Language)){throw "Unknown language: $Language"}
    $script:cfg.language=$Language
    $window.Title="$(L 'appTitle') · Glass"
    $window.FindName('HeaderTitle').Text=L 'appTitle'
    $window.FindName('HeaderEyebrow').Text=(L 'monitor').ToUpperInvariant()
    $window.FindName('LocalEyebrow').Text=(L 'localMachine').ToUpperInvariant()
    $window.FindName('LocalTitle').Text='i9-13900KF + RTX 4070'
    $window.FindName('RemoteEyebrow').Text=(L 'remoteCompute').ToUpperInvariant()
    $window.FindName('FooterText').Text=L 'footer'
    $window.FindName('HideButton').ToolTip=L 'hide'
    $window.FindName('ResizeGrip').ToolTip=L 'resize'
    $window.FindName('DesktopAdjustDone').Content=L 'done'
    $window.FindName('DesktopAdjustDone').ToolTip=L 'saveGeometry'
    $window.FindName('ThemeButton').ToolTip=L 'switchTheme'
    Update-CardLabels
    Update-BackdropLabel
    Update-Display
    if($null -ne $menu){Update-MenuText; Update-Tray}
    if($Persist){Save-Config}
}
