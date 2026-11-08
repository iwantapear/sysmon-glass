# Explicit Browse / CardEdit / PanelAdjust state controller. WPF menus only.
$script:cardEditing=$false
$script:cardGesture=$null
function Sync-CardPresentation {
    $unified=$true
    $bare=$script:cardEditing -or $script:cfg.desktopMode
    $scroll=$window.FindName('CardScroll')
    $savedOffset=$scroll.VerticalOffset
    $scroll.Visibility=if($unified){'Visible'}else{'Collapsed'}
    $scroll.ScrollToVerticalOffset($savedOffset)
    $window.FindName('CardCanvas').Visibility='Visible'
    $window.FindName('ContentArea').Visibility=if($unified){'Collapsed'}else{'Visible'}
    $dashboard=$window.FindName('DashboardGrid')
    $dashboard.RowDefinitions[0].Height=[Windows.GridLength]::new($(if($bare){0}else{94}))
    $dashboard.RowDefinitions[2].Height=[Windows.GridLength]::new($(if($bare){0}else{46}))
    foreach($name in @('Header','Footer')){$window.FindName($name).Visibility=if($bare){'Collapsed'}else{'Visible'}}
    $window.FindName('DesktopAdjustDone').Visibility=if($script:cardEditing -or $script:desktopAdjusting){'Visible'}else{'Collapsed'}
    $window.FindName('DesktopAdjustDone').IsHitTestVisible=($script:cardEditing -or $script:desktopAdjusting)
    $window.FindName('DesktopAdjustDone').Content=if($script:cardEditing){'完成编辑 / Done'}else{L 'done'}
    if(Get-Command Update-EditToolbar -ErrorAction SilentlyContinue){Update-EditToolbar}
    foreach($ctl in $script:controls.Values){$ctl.sizeButton.Visibility=if($script:cardEditing){'Visible'}else{'Collapsed'};$ctl.surface.Cursor=if($script:cardEditing -or $script:desktopAdjusting){'SizeAll'}else{'Arrow'}}
    if($unified){Apply-DesktopCardLayout}else{Restore-NormalCardLayout}
    $script:desktopRegionSignature=$null
}
function Update-EditToolbar {
    $bar=$window.FindName('EditToolbar')
    $editing=[bool]$script:cardEditing; $adjusting=[bool]$script:desktopAdjusting
    $bar.Visibility=if($editing -or $adjusting){[Windows.Visibility]::Visible}else{[Windows.Visibility]::Collapsed}
    $switch=$window.FindName('EditModeSwitch')
    $switch.Visibility=if([bool]$script:cfg.desktopMode){[Windows.Visibility]::Visible}else{[Windows.Visibility]::Collapsed}
    $switch.Content=if($editing){'面板调整'}else{'卡片编辑'}
    $layer=$window.FindName('EditLayerButton')
    $layer.Visibility=$switch.Visibility
    $layer.Content=@{top='置顶';normal='普通';bottom='置底'}[[string]$script:cfg.layerMode]
    $pct=if([bool]$script:cfg.desktopMode){
        $v=if($null -ne $script:desktopDraftScale){[double]$script:desktopDraftScale}elseif($null -ne $script:cfg.desktopScale){[double]$script:cfg.desktopScale}else{1.0}
        [int][math]::Round($v*100)
    } else {
        $w=if($script:cfg.normalWidthDip){[double]$script:cfg.normalWidthDip}else{1600}
        [int][math]::Round($w/16)
    }
    $window.FindName('EditScaleLabel').Text="$pct%"
}
function Set-CardEditing([bool]$Enabled) {
    if($Enabled -eq [bool]$script:cardEditing){return}
    Complete-CardGesture $true
    if($Enabled -and $script:desktopAdjusting){Set-DesktopAdjustment $false}
    if(-not $Enabled){$script:cfg.customLayout=$true}
    $script:cardEditing=$Enabled
    Sync-CardPresentation
    if($null -ne $positionMenuItem){$positionMenuItem.Text=if($Enabled){'完成编辑 / Done'}else{'编辑卡片 / Edit cards'}}
    if($window.IsLoaded){Apply-Preset -UseCurrentPosition;Update-DesktopIconMask}
}
function Complete-Editing {if($script:cardEditing){Set-CardEditing $false;Save-DesktopCardLayout};if($script:cfg.desktopMode){Update-DesktopIconMask}}
function Complete-CardGesture([bool]$Cancel=$false) {
    $g=$script:cardGesture;if(-not $g){return};$script:cardGesture=$null
    if($Cancel -and $g.moved){
        $script:cardOrder=@($g.beforeOrder)
        if($g.beforeSlots){$script:cfg.cardSlots=@{};foreach($k in $g.beforeSlots.Keys){$script:cfg.cardSlots[$k]=@{row=$g.beforeSlots[$k].row;column=$g.beforeSlots[$k].column}}}
        Apply-DesktopCardLayout
    }
    if($g.surface.IsMouseCaptured){$g.surface.ReleaseMouseCapture()};$g.surface.Opacity=1
    if(-not $Cancel -and $g.target) {
        # Commit the slot the pointer finished on, then re-pack exactly once.
        $null=Set-CardSlot ([string]$g.key) ([int]$g.target.row) ([int]$g.target.column)
        Apply-DesktopCardLayout
    }
    if(-not $Cancel -and $g.moved){Save-DesktopCardLayout;Update-DesktopIconMask}
}
function Start-CardGesture($Surface,$Event) {
    if($script:desktopAdjusting){Start-PanelMoveGesture $Surface $Event|Out-Null;return}
    if(-not $script:cardEditing){$script:cardPressKey=[string]$Surface.Tag;return}
    if($script:cardGesture -or $script:resizeState -or $script:dragState){return}
    $screen=$Surface.PointToScreen($Event.GetPosition($Surface));if(-not $Surface.CaptureMouse()){return}
    $slotSnapshot=@{}
    if($script:cfg.cardSlots){foreach($k in $script:cfg.cardSlots.Keys){$v=$script:cfg.cardSlots[$k];$slotSnapshot[$k]=@{row=[int]$v.row;column=[int]$v.column}}}
    $canvas=$window.FindName('CardCanvas')
    $a=$canvas.PointToScreen([Windows.Point]::new(0,0));$b=$canvas.PointToScreen([Windows.Point]::new($canvas.ActualWidth,$canvas.ActualHeight))
    $script:cardGesture=@{key=[string]$Surface.Tag;surface=$Surface;capture=$Surface;beforeOrder=@($script:cardOrder);beforeSlots=$slotSnapshot;x=[int]$screen.X;y=[int]$screen.Y;originX=$a.X;originY=$a.Y;scaleX=$canvas.ActualWidth/[math]::Max(1,$b.X-$a.X);scaleY=$canvas.ActualHeight/[math]::Max(1,$b.Y-$a.Y);rows=$script:desktopCardRows;moved=$false;active=$true};$Event.Handled=$true
}
function Update-CardGesture($Surface,$Event) {
    if($script:desktopAdjusting){Update-PanelMoveGesture $Surface $Event;return}
    $g=$script:cardGesture;if(-not $g -or $g.surface -ne $Surface -or $Event.LeftButton -ne [Windows.Input.MouseButtonState]::Pressed){return}
    $screen=$Surface.PointToScreen($Event.GetPosition($Surface));if([math]::Abs($screen.X-$g.x)-gt 8 -or [math]::Abs($screen.Y-$g.y)-gt 8){$g.moved=$true}
    if($g.moved){$Surface.Opacity=.62;Move-CardInCanvas ([array]::IndexOf([string[]]$cards.key,$g.key)) $screen.X $screen.Y};$Event.Handled=$true
}
function End-CardGesture($Surface,$Event) {
    if($script:desktopAdjusting){return}
    if($script:cardEditing){Complete-CardGesture $false;$Event.Handled=$true;return}
    if($script:cardPressKey -ne [string]$Surface.Tag){return};$script:cardPressKey=$null
    $point=$Surface.PointToScreen($Event.GetPosition($Surface));Show-CardDetail ([string]$Surface.Tag) ([Drawing.Point]::new([int]$point.X,[int]$point.Y));$Event.Handled=$true
}
function Set-WindowLayer([ValidateSet('top','normal','bottom')][string]$Mode,[bool]$Persist=$true) {
    Complete-CardGesture $true
    if($script:cardEditing){Complete-Editing}
    $script:cfg.layerMode=$Mode
    $script:cfg.alwaysOnTop=($Mode -eq 'top')
    Set-DesktopMode ($Mode -eq 'bottom') $false
    $hwnd=([Windows.Interop.WindowInteropHelper]::new($window)).Handle
    if($hwnd -ne [IntPtr]::Zero){[SysMonGlass.Native]::SetTopmost($hwnd,$Mode -eq 'top')}
    if($Persist){Save-Config}
}
function Set-Topmost([bool]$Enabled) { Set-WindowLayer $(if($Enabled){'top'}else{'normal'}) }


function New-CardMenuItem([string]$Text,[string]$Action,[string]$Value='') {
    $i=[Windows.Controls.MenuItem]::new();$i.Header=$Text;$i.Tag=@{action=$Action;value=$Value};[Windows.Automation.AutomationProperties]::SetAutomationId($i,$Action)
    $i.Add_Click({param($s,$e) $c=$s.Tag;switch($c.action){
        edit {Set-CardEditing $true};editlayout {if([bool]$script:cfg.desktopMode){Set-DesktopAdjustment $true}else{Set-CardEditing $true}};done {Complete-Editing};detail {Show-CardDetail $c.value $null}
        short {Set-CardShape $c.value short $true|Out-Null};long {Set-CardShape $c.value long $true|Out-Null}
        theme {Set-Theme $c.value $true};material {Set-Material $c.value $true};desktop {Complete-Editing;Set-DesktopMode (-not [bool]$script:cfg.desktopMode) $true}
        insights {$script:cfg.insightsRail=-not [bool]$script:cfg.insightsRail;Save-Config;Update-InsightsRailLayout;Update-DesktopIconMask}
        free {Complete-CardGesture $true;$next=-not (Test-CardFreePlacementEnabled);$script:cfg.freePlacement=$next;Save-Config}
        arrange {Complete-CardGesture $true;Invoke-CardAutoArrange $c.value $true|Out-Null;Sync-CardPresentation;Apply-Preset -UseCurrentPosition;Update-DesktopIconMask}
        top {Set-WindowLayer top};normal {Set-WindowLayer normal};bottom {Set-WindowLayer bottom}
        move {Complete-Editing;Set-DesktopAdjustment (-not [bool]$script:desktopAdjusting)};hosts {Show-RemoteHostSettings};hide {Complete-Editing;Hide-Panel}
    };$e.Handled=$true});return $i
}
function Add-PanelMenuItems($Menu) {
    $Menu.Items.Add((New-CardMenuItem $(if($script:cardEditing -or $script:desktopAdjusting){'完成编辑 / Done'}else{'编辑布局 / Edit layout'}) $(if($script:cardEditing -or $script:desktopAdjusting){'done'}else{'edit'})))|Out-Null
    $theme=[Windows.Controls.MenuItem]::new();$theme.Header=L 'theme';foreach($id in $script:themeOrder){$theme.Items.Add((New-CardMenuItem (L $id) theme $id))|Out-Null};$Menu.Items.Add($theme)|Out-Null
    $mat=[Windows.Controls.MenuItem]::new();$mat.Header='材质 / Material'
    $active=if($script:cfg.material -in $script:materialOrder){[string]$script:cfg.material}else{'glass'}
    foreach($m in @('glass','frosted','solid')){
        $item=New-CardMenuItem $m material $m
        $item.IsCheckable=$true; $item.IsChecked=($active -eq $m)
        $mat.Items.Add($item)|Out-Null
    }
    $Menu.Items.Add($mat)|Out-Null
    $free=New-CardMenuItem '完全自由放置 / Free placement' 'free';$free.IsCheckable=$true;$free.IsChecked=(Test-CardFreePlacementEnabled);$Menu.Items.Add($free)|Out-Null
    if([bool]$script:cfg.desktopMode){$rail=New-CardMenuItem '洞察栏 / Insights rail' 'insights';$rail.IsCheckable=$true;$rail.IsChecked=[bool]$script:cfg.insightsRail;$Menu.Items.Add($rail)|Out-Null}
    $arr=[Windows.Controls.MenuItem]::new();$arr.Header='自动整理 / Auto arrange';$arr.Items.Add((New-CardMenuItem '按主机归类 / By host' 'arrange' 'HostPriority'))|Out-Null;$arr.Items.Add((New-CardMenuItem '按硬件重要性 / By importance' 'arrange' 'HardwarePriority'))|Out-Null;$Menu.Items.Add($arr)|Out-Null
    $layers=[Windows.Controls.MenuItem]::new();$layers.Header='窗口图层 / Window layer'
    foreach($entry in @(@('置顶 / Top','top'),@('普通 / Normal','normal'),@('置底（底层模式）/ Bottom','bottom'))) {
        $item=New-CardMenuItem $entry[0] $entry[1];$item.IsCheckable=$true;$item.IsChecked=($script:cfg.layerMode -eq $entry[1]);$layers.Items.Add($item)|Out-Null
    }
    $Menu.Items.Add($layers)|Out-Null
    $Menu.Items.Add((New-CardMenuItem '远程主机 / Remote hosts…' hosts))|Out-Null;$Menu.Items.Add((New-CardMenuItem (L 'hide') hide))|Out-Null
}
function Open-CardMenu($Menu,$Target) {
    if($script:cardContextMenu){$script:cardContextMenu.IsOpen=$false}
    $Menu.PlacementTarget=if($Target){$Target}else{$window.FindName('Root')}
    $Menu.Placement='MousePoint'
    $script:cardContextMenu=$Menu; $Menu.IsOpen=$true
}
function Show-CardContextMenu([string]$Key,$Target=$null) {
    if($Key -notin $cards.key){return};$m=[Windows.Controls.ContextMenu]::new()
    if(-not $script:cardEditing){$m.Items.Add((New-CardMenuItem '显示详情 / Details' detail $Key))|Out-Null}
    foreach($shape in @('short','long')){$i=New-CardMenuItem $(if($shape -eq 'short'){'短卡 / Short'}else{'长卡 / Long'}) $shape $Key;$i.IsCheckable=$true;$i.IsChecked=(Get-CardShape $Key)-eq $shape;$m.Items.Add($i)|Out-Null}
    $m.Items.Add([Windows.Controls.Separator]::new())|Out-Null;Add-PanelMenuItems $m;Open-CardMenu $m $(if($Target){$Target}else{$script:controls[$Key].surface})
}
function Show-PanelContextMenu($Target=$null){$m=[Windows.Controls.ContextMenu]::new();Add-PanelMenuItems $m;Open-CardMenu $m $Target}
