[CmdletBinding()]
param(
    [string]$ConfigPath = '',
    [switch]$NoElevate
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'WslVhd.Common.ps1')

if (-not (Test-WslVhdAdministrator)) {
    if ($NoElevate) {
        Write-Warning "Sem Administrador: BitLocker pode negar status detalhado."
    }
    else {
        $elevatedArgs = @()
        if (-not [string]::IsNullOrWhiteSpace($ConfigPath)) {
            $elevatedArgs += @('-ConfigPath', $ConfigPath)
        }

        Invoke-WslVhdSelfElevation -ScriptPath $PSCommandPath -ArgumentList $elevatedArgs
    }
}

$configArgs = @{}
if (-not [string]::IsNullOrWhiteSpace($ConfigPath)) {
    $configArgs['ConfigPath'] = $ConfigPath
}

$config = Get-WslVhdConfig @configArgs
$projectRoot = [string]$config['ProjectRoot']
$vhdPath = Resolve-WslVhdPath -Path ([string](Get-WslVhdConfigValue -Config $config -Name 'VhdPath')) -BasePath $projectRoot
$taskName = [string](Get-WslVhdConfigValue -Config $config -Name 'TaskName' -Default 'WSL VHD Automount')

Write-Host "== Host readiness =="
Write-Host "Projeto: $projectRoot"
Write-Host "VHDX:    $vhdPath"
Write-Host ""

Write-Host "== Volumes =="
Get-Volume |
    Select-Object DriveLetter, FileSystemLabel, FileSystem, DriveType, HealthStatus, SizeRemaining, Size |
    Format-Table -AutoSize

Write-Host ""
Write-Host "== Discos =="
Get-Disk |
    Select-Object Number, FriendlyName, BusType, OperationalStatus, PartitionStyle, Size |
    Format-Table -AutoSize

Write-Host ""
Write-Host "== BitLocker =="
$bitLockerRows = @()
foreach ($volume in Get-Volume | Where-Object { $null -ne $_.DriveLetter }) {
    $mountPoint = "$($volume.DriveLetter):"
    try {
        $bitLockerVolume = Get-BitLockerVolume -MountPoint $mountPoint -ErrorAction Stop 2>$null
        $bitLockerRows += [pscustomobject]@{
            MountPoint = $bitLockerVolume.MountPoint
            VolumeStatus = $bitLockerVolume.VolumeStatus
            ProtectionStatus = $bitLockerVolume.ProtectionStatus
            LockStatus = $bitLockerVolume.LockStatus
            EncryptionPercentage = $bitLockerVolume.EncryptionPercentage
            AutoUnlockEnabled = $bitLockerVolume.AutoUnlockEnabled
            Note = ''
        }
    }
    catch {
        $bitLockerRows += [pscustomobject]@{
            MountPoint = $mountPoint
            VolumeStatus = ''
            ProtectionStatus = ''
            LockStatus = ''
            EncryptionPercentage = ''
            AutoUnlockEnabled = ''
            Note = $_.Exception.Message
        }
    }
}

$bitLockerRows | Format-Table -AutoSize

Write-Host ""
Write-Host "== VHDX =="
try {
    if (Test-Path -LiteralPath $vhdPath) {
        Get-DiskImage -ImagePath $vhdPath |
            Select-Object ImagePath, Attached, Size, FileSize |
            Format-List
    }
    else {
        Write-Warning "VHDX nao encontrado. Se o drive usa BitLocker, talvez ainda esteja bloqueado."
    }
}
catch {
    Write-Warning "Nao consegui ler o VHDX: $($_.Exception.Message)"
}

Write-Host ""
Write-Host "== WSL =="
try {
    Invoke-WslVhdNativeCommand -FilePath 'wsl.exe' -ArgumentList @('--version') -IgnoreExitCode | Out-Null
    Invoke-WslVhdNativeCommand -FilePath 'wsl.exe' -ArgumentList @('--list', '--verbose') -IgnoreExitCode | Out-Null
}
catch {
    Write-Warning "Nao consegui consultar WSL: $($_.Exception.Message)"
}

Write-Host ""
Write-Host "== Tarefa Agendada =="
$taskOutput = & schtasks.exe /Query /TN $taskName /FO LIST /V 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Warning "Tarefa nao encontrada: $taskName"
}
else {
    $taskOutput | ForEach-Object { Write-Host $_ }
}
