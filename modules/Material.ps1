# Material is independent of the color theme. Each mode scales the palette's own
# card alphas so the three choices are visibly distinct on every theme:
#   glass   -> 0.62x  (real see-through; the backdrop blur shows through)
#   frosted -> 0.88x  (heavier, softly diffused face)
#   solid   -> 1.00x  (fully opaque, specular gloss removed)
$script:materialOrder=@('glass','frosted','solid')
$script:materialProfile=@{
    glass=@{scale=0.62; gloss=0.45}
    frosted=@{scale=0.88; gloss=0.20}
    solid=@{scale=1.00; gloss=0.00}
}
function Get-CardMaterialProfile {
    $mode=if($script:cfg.material -in $script:materialOrder){[string]$script:cfg.material}else{'glass'}
    $script:materialProfile[$mode]
}
function Set-Material([ValidateSet('glass','frosted','solid')][string]$Mode,[bool]$Persist=$true) {
    $script:cfg.material=$Mode
    Set-Theme ([string]$script:cfg.theme)
    if($Persist){Save-Config}
}
function Update-CardMaterial {
    $profile=Get-CardMaterialProfile
    # Always scale the palette's authored alphas, never the values already
    # written onto the brushes: repeated calls must stay idempotent.
    $authored=@($script:theme.card | ForEach-Object { [Windows.Media.ColorConverter]::ConvertFromString($_).A })
    if($authored.Count -eq 0){ return }
    foreach($ctl in $script:controls.Values) {
        if($null -eq $ctl.bg -or $null -eq $ctl.bg.GradientStops){continue}
        for($i=0;$i -lt $ctl.bg.GradientStops.Count;$i++) {
            $source=$authored[[math]::Min($i,$authored.Count-1)]
            $color=$ctl.bg.GradientStops[$i].Color
            $color.A=[byte][math]::Round([double]$source*$profile.scale)
            $ctl.bg.GradientStops[$i].Color=$color
        }
        $ctl.gloss.Opacity=$profile.gloss
        if($ctl.sheen){$ctl.sheen.Opacity=0}
    }
}
