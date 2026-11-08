# SysMon Glass entry point. Components share this application's script scope.
# Keep this path stable: Startup\SysMon.lnk points here.
param(
    [ValidateSet('auto','1080p','2k','4k')][string]$Preset,
    [switch]$ValidateOnly,
    [switch]$PrepareOnly
)
$ErrorActionPreference='Stop'
$script:AppRoot=$PSScriptRoot
if([Threading.Thread]::CurrentThread.ApartmentState -ne 'STA') { throw 'SysMon Glass requires pwsh -STA.' }
Add-Type -AssemblyName PresentationFramework,PresentationCore,WindowsBase,System.Windows.Forms,System.Drawing,UIAutomationClient,UIAutomationTypes
Add-Type -Path (Join-Path $AppRoot 'native/WindowNative.cs'),(Join-Path $AppRoot 'native/Pollers.cs'),(Join-Path $AppRoot 'native/DesktopContextMenu.cs')
[SysMonGlass.Native]::SetThreadDpiAwarenessContext([IntPtr](-4)) | Out-Null
# Hot path: called dozens of times per tick. Cache frozen brushes by color string.
$script:brushCache=@{}
function Brush([string]$color) {
    $cached=$script:brushCache[$color]
    if($cached){return $cached}
    $brush=[Windows.Media.BrushConverter]::new().ConvertFromString($color)
    if($brush.CanFreeze){$brush.Freeze()}
    $script:brushCache[$color]=$brush
    $brush
}
foreach($component in @('Locale','Theme','RemoteProvision','Config','View','LocalIO','Data','Display','Interaction','Cards','Background','Layout','Desktop','RemoteHostSettings','Material','CardManager','Insights')) {
    . (Join-Path $AppRoot "modules/$component.ps1")
}
Apply-Preset
Set-Theme $script:cfg.theme
Set-Language $script:cfg.language
if($ValidateOnly) { . (Join-Path $AppRoot 'tests/Validate.ps1'); return }
. (Join-Path $AppRoot 'modules/Events.ps1')
. (Join-Path $AppRoot 'modules/Tray.ps1')
# In-process integration tests own lifetime; no polling starts in this mode.
if($PrepareOnly) { return }
. (Join-Path $AppRoot 'modules/Lifecycle.ps1')
