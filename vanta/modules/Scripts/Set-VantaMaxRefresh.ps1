<#
  Põe cada monitor ligado na taxa máxima que o próprio monitor oferece para a resolução atual.
  Roda na sessão do usuário (RunOnce da fase Monitors, ou chamado pelo Vanta Tools depois do driver da GPU).
  A taxa é DETECTADA no destino; nenhum valor de Hz vem do PC de origem. Idempotente.
  Sem monitor ou sem driver: não faz nada e sai com 0.
#>
param([string]$LogPath = (Join-Path $env:LOCALAPPDATA 'Vanta\Logs\monitors.log'))

function Get-VantaBestRefresh {
    <# Maior taxa entre os modos que têm a mesma resolução do modo atual; a atual se nenhum for maior. #>
    param(
        [Parameter(Mandatory = $true)][int]$Width,
        [Parameter(Mandatory = $true)][int]$Height,
        [Parameter(Mandatory = $true)][int]$CurrentHz,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][object[]]$Modes
    )
    $best = $CurrentHz
    foreach ($mode in $Modes) {
        if ([int]$mode.Width -eq $Width -and [int]$mode.Height -eq $Height -and [int]$mode.Hz -gt $best) { $best = [int]$mode.Hz }
    }
    return $best
}

function Set-VantaMaxRefresh {
    param([string]$LogPath)
    function Log($m) {
        $null = New-Item -ItemType Directory -Force -Path (Split-Path $LogPath -Parent)
        "$(Get-Date -f 'yyyy-MM-dd HH:mm:ss') $m" | Add-Content -LiteralPath $LogPath -Encoding UTF8
    }
    Add-Type -TypeDefinition @'
using System; using System.Runtime.InteropServices;
public class VantaScreen {
  [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Unicode)] public struct DEVMODE {
    [MarshalAs(UnmanagedType.ByValTStr, SizeConst=32)] public string dmDeviceName; public short dmSpecVersion, dmDriverVersion, dmSize, dmDriverExtra;
    public int dmFields, dmPositionX, dmPositionY, dmDisplayOrientation, dmDisplayFixedOutput; public short dmColor, dmDuplex, dmYResolution, dmTTOption, dmCollate;
    [MarshalAs(UnmanagedType.ByValTStr, SizeConst=32)] public string dmFormName; public short dmLogPixels; public int dmBitsPerPel, dmPelsWidth, dmPelsHeight, dmDisplayFlags, dmDisplayFrequency,
    dmICMMethod, dmICMIntent, dmMediaType, dmDitherType, dmReserved1, dmReserved2, dmPanningWidth, dmPanningHeight; }
  [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Unicode)] public struct DISPLAY_DEVICE { public int cb;
    [MarshalAs(UnmanagedType.ByValTStr, SizeConst=32)] public string DeviceName; [MarshalAs(UnmanagedType.ByValTStr, SizeConst=128)] public string DeviceString;
    public int StateFlags; [MarshalAs(UnmanagedType.ByValTStr, SizeConst=128)] public string DeviceID; [MarshalAs(UnmanagedType.ByValTStr, SizeConst=128)] public string DeviceKey; }
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern bool EnumDisplayDevices(string dev, int i, ref DISPLAY_DEVICE d, int f);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern bool EnumDisplaySettings(string dev, int mode, ref DEVMODE dm);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int ChangeDisplaySettingsEx(string dev, ref DEVMODE dm, IntPtr h, int flags, IntPtr p);
}
'@ -ErrorAction SilentlyContinue
    $found = 0
    for ($i = 0; $i -lt 16; $i++) {
        $dd = New-Object VantaScreen+DISPLAY_DEVICE; $dd.cb = [Runtime.InteropServices.Marshal]::SizeOf($dd)
        if (-not [VantaScreen]::EnumDisplayDevices($null, $i, [ref]$dd, 0)) { break }
        if (($dd.StateFlags -band 1) -eq 0) { continue }   # não está ligado na área de trabalho
        $found++
        $cur = New-Object VantaScreen+DEVMODE; $cur.dmSize = [Runtime.InteropServices.Marshal]::SizeOf($cur)
        [void][VantaScreen]::EnumDisplaySettings($dd.DeviceName, -1, [ref]$cur)
        $modes = @(); $m = 0
        while ($true) {
            $dm = New-Object VantaScreen+DEVMODE; $dm.dmSize = $cur.dmSize
            if (-not [VantaScreen]::EnumDisplaySettings($dd.DeviceName, $m++, [ref]$dm)) { break }
            $modes += [pscustomobject]@{ Width = $dm.dmPelsWidth; Height = $dm.dmPelsHeight; Hz = $dm.dmDisplayFrequency }
        }
        $best = Get-VantaBestRefresh -Width $cur.dmPelsWidth -Height $cur.dmPelsHeight -CurrentHz $cur.dmDisplayFrequency -Modes $modes
        if ($best -gt $cur.dmDisplayFrequency) {
            $cur.dmDisplayFrequency = $best; $cur.dmFields = 0x400000   # DM_DISPLAYFREQUENCY
            $rc = [VantaScreen]::ChangeDisplaySettingsEx($dd.DeviceName, [ref]$cur, [IntPtr]::Zero, 1, [IntPtr]::Zero)   # CDS_UPDATEREGISTRY
            Log "monitor $($dd.DeviceName): $($cur.dmPelsWidth)x$($cur.dmPelsHeight) -> $best Hz (rc=$rc)"
        }
        else { Log "monitor $($dd.DeviceName): já na taxa máxima ($best Hz)" }
    }
    if ($found -eq 0) { Log 'nenhum monitor ligado encontrado' }
}

# Quando é dot-sourced (testes), só define as funções.
if ($MyInvocation.InvocationName -ne '.') { Set-VantaMaxRefresh -LogPath $LogPath }
