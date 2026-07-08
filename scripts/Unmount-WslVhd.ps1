[CmdletBinding()]
param(
    [string]$ConfigPath = '',
    [switch]$ShutdownWsl,
    [switch]$NoElevate,
    [switch]$NoTranscript
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'WslVhd.Common.ps1')

if (-not (Test-WslVhdAdministrator)) {
    if ($NoElevate) {
        throw "Execute este script como Administrador para desmontar o VHD."
    }

    $elevatedArgs = @()
    if (-not [string]::IsNullOrWhiteSpace($ConfigPath)) {
        $elevatedArgs += @('-ConfigPath', $ConfigPath)
    }
    if ($ShutdownWsl) { $elevatedArgs += '-ShutdownWsl' }
    if ($NoTranscript) { $elevatedArgs += '-NoTranscript' }

    Invoke-WslVhdSelfElevation -ScriptPath $PSCommandPath -ArgumentList $elevatedArgs
}

$configArgs = @{}
if (-not [string]::IsNullOrWhiteSpace($ConfigPath)) {
    $configArgs['ConfigPath'] = $ConfigPath
}

$config = Get-WslVhdConfig @configArgs
$projectRoot = [string]$config['ProjectRoot']
$vhdPath = Resolve-WslVhdPath -Path ([string](Get-WslVhdConfigValue -Config $config -Name 'VhdPath')) -BasePath $projectRoot -MustExist
$preferDirectVhdMount = [bool](Get-WslVhdConfigValue -Config $config -Name 'PreferDirectVhdMount' -Default $false)

$transcriptStarted = $false
try {
    if (-not $NoTranscript) {
        $logPath = Start-WslVhdLog -Config $config -Name 'wsl-vhd-unmount.log'
        $transcriptStarted = $true
        Write-WslVhdTerminal -Level INFO -Message "Log: $logPath"
    }

    if ($ShutdownWsl) {
        Write-WslVhdTerminal -Level INFO -Message "Encerrando WSL antes de desmontar."
        Invoke-WslVhdNativeCommand -FilePath 'wsl.exe' -ArgumentList @('--shutdown') -IgnoreExitCode | Out-Null
    }

    $image = Get-DiskImage -ImagePath $vhdPath -ErrorAction Stop

    if ($preferDirectVhdMount) {
        Invoke-WslVhdNativeCommand -FilePath 'wsl.exe' -ArgumentList @('--unmount', $vhdPath) -IgnoreExitCode | Out-Null
    }
    elseif ($image.Attached) {
        $disk = Get-WslVhdDisk -VhdPath $vhdPath
        $diskPath = Get-WslVhdDiskPath -Disk $disk
        Invoke-WslVhdNativeCommand -FilePath 'wsl.exe' -ArgumentList @('--unmount', $diskPath) -IgnoreExitCode | Out-Null
    }

    $image = Get-DiskImage -ImagePath $vhdPath -ErrorAction Stop
    if ($image.Attached) {
        Write-WslVhdTerminal -Level INFO -Message "Desanexando VHD do Windows: $vhdPath"
        Dismount-VHD -Path $vhdPath -ErrorAction Stop
    }
    else {
        Write-WslVhdTerminal -Level OK -Message "VHD ja estava desanexado no Windows."
    }

    Write-WslVhdTerminal -Level OK -Message "VHD desmontado."
}
finally {
    if ($transcriptStarted) {
        Stop-Transcript | Out-Null
    }
}
