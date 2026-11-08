$script:themes = @{
    dark = @{
        bg=@('#B01A2C50','#A81C4A68','#98202C82'); card=@('#DC38607A','#C0284E60','#D42C6A70')
        rim=@('#8FBFD5EE','#4D8DAFCD','#3F7797B7'); gloss='#27C4DDFF'; reflection='#1B95C5FF'
        text='#FFF5F9FF'; secondary='#FFE1ECF8'; muted='#FFB6CADF'; label='#FFE5F0FC'
        pillBg='#7044617E'; pillBorder='#68B9D9EE'; buttonBg='#5449697C'; adjustButton='#F336536D'
        local='#FF86C9FF'; remote='#FF83E7DD'; glowTop='#4B76AFFF'; glowBottom='#3676E7DA'
        shadow='#050D1C'; shadowOpacity=0.42; track='#558AA1BC'; warn='#FFFFD77C'; bad='#FFFF8D91'
    }
    light = @{
        bg=@('#A8DCEEFF','#B8C8F4FF','#E0D0F0FF'); card=@('#F9FBFDFF','#E4F0FAFF','#F0E8FAFF')
        rim=@('#F9FFFFFF','#A8BECFE4','#83A7BED7'); gloss='#82FFFFFF'; reflection='#65FFFFFF'
        text='#FF19334F'; secondary='#FF45617E'; muted='#FF6A829B'; label='#FF3B5874'
        pillBg='#96F5FBFF'; pillBorder='#8CAECDE4'; buttonBg='#8CEEFFFF'; adjustButton='#F2E5F2FD'
        local='#FF2478C2'; remote='#FF137E7C'; glowTop='#55C3ABFF'; glowBottom='#558DE5DB'
        shadow='#536E9B'; shadowOpacity=0.27; track='#5099B5CF'; warn='#FF9B5600'; bad='#FFB92338'
    }
}
$customPalettes=@{
    ocean=@{
        bg=@('#D01A2E55','#B11C4270','#C117344B'); card=@('#E0294A75','#CC203653','#DC1F4260')
        rim=@('#9AB2D7FF','#5486B5E5','#4885BACE'); gloss='#309CC6FF'; reflection='#236CE7FF'
        local='#FF95CFFF'; remote='#FF83EDD9'; glowTop='#596686FF'; glowBottom='#4279E6DF'
        pillBg='#8D285C86'; buttonBg='#82416991'; adjustButton='#F32A527D'
    }
    forest=@{
        bg=@('#D019392F','#BA254A3E','#C616342B'); card=@('#E035584B','#CD233F37','#D3274B3E')
        rim=@('#A6C8E9D4','#5E83B9A5','#4885A99B'); gloss='#2FB1ECD4'; reflection='#226FFFC1'
        local='#FF9DE6C3'; remote='#FFDCF0AB'; glowTop='#4E73CDA7'; glowBottom='#375CBE97'
        text='#FFF2FFF7'; muted='#FFC0D7C8'; secondary='#FFE0EFE4'; label='#FFE4F6EA'
        pillBg='#88476C54'; buttonBg='#80507762'; adjustButton='#F33B6351'
    }
    amber=@{
        bg=@('#D04C3028','#B755382D','#C2402B2D'); card=@('#E06C4D3F','#CF48342E','#DB4D3836')
        rim=@('#A5EBD0AF','#619E7A66','#568E6A6B'); gloss='#32FFD6A2'; reflection='#2BFFA974'
        local='#FFFFCC91'; remote='#FFF4B9AF'; glowTop='#56DC9B5B'; glowBottom='#48CC7770'
        text='#FFFFFAEF'; muted='#FFE0C8B6'; secondary='#FFF4E3D5'; label='#FFF5E8DC'
        pillBg='#886C4C3C'; buttonBg='#88765547'; adjustButton='#F36D4C3A'
    }
    sunset=@{
        bg=@('#D06B2C6E','#C89A3A78','#BE3C5C82'); card=@('#E0B05878','#CA884860','#D8A04070')
        rim=@('#A8FFE0C8','#68FFC8A8','#58E09888'); gloss='#38FFE2B8'; reflection='#2BFFC890'
        local='#FFFFD9A8'; remote='#FFFFB8A0'; glowTop='#4AFF9E60'; glowBottom='#4AFF6E9A'
        pillBg='#8DA04A66'; buttonBg='#83A05870'; adjustButton='#F3B05A6E'
    }
    rose=@{
        bg=@('#D0A0306A','#C8B84872','#BE902878'); card=@('#E0C86880','#CAB05868','#D8B8607A')
        rim=@('#A8FFD8F0','#60E8B8D8','#50D098C0'); gloss='#35FFE8F5'; reflection='#28FFD0E0'
        local='#FFFFD0E8'; remote='#FFFFC8B8'; glowTop='#4AFF90B8'; glowBottom='#3AFF6898'
        pillBg='#8DC04878'; buttonBg='#83C05888'; adjustButton='#F3D05A88'
    }
    violet=@{
        bg=@('#D04A2C8E','#C43A4494','#B8526C9A'); card=@('#E05A4498','#CA48387E','#D8546C90')
        rim=@('#A8D0E8FF','#5890C8E0','#4870A8C8'); gloss='#30B8D8FF'; reflection='#2488A8F5'
        local='#FFC8A8FF'; remote='#FF8FC8FF'; glowTop='#4A8860FF'; glowBottom='#3A48D8E8'
        pillBg='#8D483088'; buttonBg='#82385292'; adjustButton='#F35A3A80'
    }
    aurora=@{
        bg=@('#D0146858','#BA1C7074','#C82A9882'); card=@('#DE14705E','#C810604C','#D4208064')
        rim=@('#9AF0E0D8','#58C8D8B0','#4890B898'); gloss='#2EF0F0D0'; reflection='#22C0E0C0'
        local='#FF8FFFE0'; remote='#FFC0A8FF'; glowTop='#4040FFA0'; glowBottom='#35B060E0'
        pillBg='#8D186850'; buttonBg='#80207058'; adjustButton='#F330A880'
    }
    neon=@{
        bg=@('#D007081C','#B60C0C26','#C0101832'); card=@('#DC141438','#C60C0C30','#D8183048')
        rim=@('#A800F0FF','#48E8A0E0','#38C080C8'); gloss='#3020F0FF'; reflection='#2410C0FF'
        local='#FF00E5FF'; remote='#FFFF40C8'; glowTop='#3B00C8FF'; glowBottom='#30FF30C8'
        pillBg='#8D101848'; buttonBg='#82182850'; adjustButton='#F300E5A0'
    }
    flame=@{
        bg=@('#D0A81622','#BC981830','#C8A82038'); card=@('#E0C22030','#CAA01824','#D5B02030')
        rim=@('#A8FFD0D0','#60F0A0B0','#50D08898'); gloss='#32FFD0C0'; reflection='#28FFA890'
        local='#FFFFB8A8'; remote='#FFFFD8B0'; glowTop='#45FF8050'; glowBottom='#38E04040'
        pillBg='#8DA02030'; buttonBg='#82B02838'; adjustButton='#F3E04A50'
    }
}
$script:themeOrder=@('light','dark','sunset','rose','violet','aurora','neon','flame','ocean','forest','amber')
foreach($name in $customPalettes.Keys) {
    $palette=$script:themes.dark.Clone()
    foreach($key in $customPalettes[$name].Keys){$palette[$key]=$customPalettes[$name][$key]}
    $script:themes[$name]=$palette
}
function Set-Theme([string]$Mode,[bool]$Persist=$false) {
    if(-not $script:themes.ContainsKey($Mode)) { throw "Unknown theme: $Mode" }
    $script:cfg.theme=$Mode; $script:theme=$script:themes[$Mode]; $t=$script:theme
    $window.FindName('GlowTop0').Color=[Windows.Media.ColorConverter]::ConvertFromString($t.glowTop)
    $window.FindName('GlowBottom0').Color=[Windows.Media.ColorConverter]::ConvertFromString($t.glowBottom)
    $window.FindName('HeaderTitle').Foreground=Brush $t.text
    $window.FindName('HeaderEyebrow').Foreground=Brush $t.local
    $window.FindName('LocalEyebrow').Foreground=Brush $t.local
    $window.FindName('RemoteEyebrow').Foreground=Brush $t.remote
    $window.FindName('LocalTitle').Foreground=Brush $t.secondary
    $window.FindName('RemoteTitle').Foreground=Brush $t.secondary
    $window.FindName('FooterText').Foreground=Brush $t.muted
    $backdropText.Foreground=Brush $t.muted; $statusText.Foreground=Brush $t.secondary
    $window.FindName('ResizeGrip').Foreground=Brush $t.muted
    $doneButton=$window.FindName('DesktopAdjustDone')
    $doneButton.Foreground=Brush $t.text
    $doneButton.Background=Brush $t.adjustButton
    $doneButton.BorderBrush=Brush $t.pillBorder
    $window.FindName('StatusBorder').Background=Brush $t.pillBg
    $window.FindName('StatusBorder').BorderBrush=Brush $t.pillBorder
    foreach($name in @('ThemeButton','HideButton')) {
        $button=$window.FindName($name); $button.Background=Brush $t.buttonBg
        $button.BorderBrush=Brush $t.rim[1]; $button.Foreground=Brush $t.secondary
    }
    $themeButton=$window.FindName('ThemeButton')
    $themeButton.Content=if($Mode -eq 'light'){"$([char]0xE706)"}else{"$([char]0xE708)"}
    $themeButton.ToolTip=L 'switchTheme'
    foreach($cell in $cards) {
        $ctl=$script:controls[$cell.key]
        for($i=0;$i -lt 3;$i++) {
            $ctl.bg.GradientStops[$i].Color=[Windows.Media.ColorConverter]::ConvertFromString($t.card[$i])
            $ctl.rim.GradientStops[$i].Color=[Windows.Media.ColorConverter]::ConvertFromString($t.rim[$i])
        }
        $ctl.gloss.Background.GradientStops[0].Color=[Windows.Media.ColorConverter]::ConvertFromString($t.gloss)
        $ctl.sheen.Fill.GradientStops[0].Color=[Windows.Media.ColorConverter]::ConvertFromString($t.reflection)
        # Vector shadow: the halo colour lives in the radial brush's inner stop.
        $shadowColor=[Windows.Media.ColorConverter]::ConvertFromString($t.shadow)
        $shadowAlpha=[byte][math]::Min(255,[math]::Round(255*[double]$t.shadowOpacity*0.55))
        $shadowColor.A=$shadowAlpha
        $ctl.shadow.GradientStops[0].Color=$shadowColor
        $accent=[Windows.Media.ColorConverter]::ConvertFromString($cell.color)
        if($Mode -eq 'light') { $accent.R=[byte]($accent.R*0.62); $accent.G=[byte]($accent.G*0.73); $accent.B=[byte]($accent.B*0.84) }
        $accentBrush=[Windows.Media.SolidColorBrush]::new($accent)
        $ctl.dot.Fill=$accentBrush; $ctl.spark.Stroke=$accentBrush; $ctl.progress.Foreground=$accentBrush
        $ctl.progress.Background=Brush $t.track
        $ctl.label.Foreground=Brush $t.label; $ctl.unit.Foreground=Brush $t.muted; $ctl.sub.Foreground=Brush $t.secondary
        $ctl.number.Foreground=Brush $t.text
    }
    Set-Background
    if(Get-Command Update-CardMaterial -ErrorAction SilentlyContinue){Update-CardMaterial}
    if($null -ne $themeMenu) { foreach($item in $themeMenu.DropDownItems) { $item.Checked=($item.Tag -eq $Mode) } }
    if($Persist) { Save-Config }
    Update-Display
}
