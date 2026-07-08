[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [string]$ConfigPath = '',
    [switch]$NoElevate
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'WslVhd.Common.ps1')

if (-not (Test-WslVhdAdministrator)) {
    if ($NoElevate) {
        throw "Execute como Administrador para alterar auto-unlock do BitLocker."
    }

    $elevatedArgs = @()
    if (-not [string]::IsNullOrWhiteSpace($ConfigPath)) {
        $elevatedArgs += @('-ConfigPath', $ConfigPath)
    }

    Invoke-WslVhdSelfElevation -ScriptPath $PSCommandPath -ArgumentList $elevatedArgs
}

$configArgs = @{}
if (-not [string]::IsNullOrWhiteSpace($ConfigPath)) {
    $configArgs['ConfigPath'] = $ConfigPath
}

$config = Get-WslVhdConfig @configArgs
$projectRoot = [string]$config['ProjectRoot']
$vhdPath = Resolve-WslVhdPath -Path ([string](Get-WslVhdConfigValue -Config $config -Name 'VhdPath')) -BasePath $projectRoot
$driveRoot = [System.IO.Path]::GetPathRoot($vhdPath)

if ([string]::IsNullOrWhiteSpace($driveRoot)) {
    throw "Nao consegui descobrir o drive do VHDX: $vhdPath"
}

$mountPoint = $driveRoot.TrimEnd('\')
$volume = Get-BitLockerVolume -MountPoint $mountPoint -ErrorAction Stop

Write-Host "Drive do VHDX: $mountPoint"
Write-Host "Status atual: LockStatus=$($volume.LockStatus), ProtectionStatus=$($volume.ProtectionStatus), AutoUnlockEnabled=$($volume.AutoUnlockEnabled)"

if ($volume.LockStatus -ne 'Unlocked') {
    throw "O drive $mountPoint esta bloqueado. Desbloqueie o BitLocker antes de habilitar auto-unlock."
}

if ($volume.AutoUnlockEnabled) {
    Write-Host "OK: auto-unlock ja esta habilitado para $mountPoint."
    return
}

if ($PSCmdlet.ShouldProcess($mountPoint, 'Enable-BitLockerAutoUnlock')) {
    Enable-BitLockerAutoUnlock -MountPoint $mountPoint -ErrorAction Stop
    Write-Host "OK: auto-unlock habilitado para $mountPoint."
}
