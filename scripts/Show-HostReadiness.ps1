[CmdletBinding()]
param(
    [string]$ConfigPath = '',
    [switch]$NoElevate
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'WslVhd.Common.ps1')

if (-not (Test-WslVhdAdministrator)) {
    if ($NoElevate) {
        Write-WslVhdTerminal -Level WARN -Message "Sem Administrador: BitLocker pode negar status detalhado."
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

Write-WslVhdSection -Title 'Host readiness'
Write-WslVhdTerminal -Level INFO -Message "Projeto: $projectRoot"
Write-WslVhdTerminal -Level INFO -Message "VHDX: $vhdPath"

Write-WslVhdSection -Title 'Volumes'
Get-Volume |
    Select-Object DriveLetter, FileSystemLabel, FileSystem, DriveType, HealthStatus, SizeRemaining, Size |
    Format-Table -AutoSize

Write-WslVhdSection -Title 'Discos'
Get-Disk |
    Select-Object Number, FriendlyName, BusType, OperationalStatus, PartitionStyle, Size |
    Format-Table -AutoSize

Write-WslVhdSection -Title 'BitLocker'
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

Write-WslVhdSection -Title 'VHDX'
try {
    if (Test-Path -LiteralPath $vhdPath) {
        Get-DiskImage -ImagePath $vhdPath |
            Select-Object ImagePath, Attached, Size, FileSize |
            Format-List
    }
    else {
        Write-WslVhdTerminal -Level WARN -Message "VHDX nao encontrado. Se o drive usa BitLocker, talvez ainda esteja bloqueado."
    }
}
catch {
    Write-WslVhdTerminal -Level WARN -Message "Nao consegui ler o VHDX: $($_.Exception.Message)"
}

Write-WslVhdSection -Title 'WSL'
try {
    Invoke-WslVhdNativeCommand -FilePath 'wsl.exe' -ArgumentList @('--version') -IgnoreExitCode | Out-Null
    Invoke-WslVhdNativeCommand -FilePath 'wsl.exe' -ArgumentList @('--list', '--verbose') -IgnoreExitCode | Out-Null
}
catch {
    Write-WslVhdTerminal -Level WARN -Message "Nao consegui consultar WSL: $($_.Exception.Message)"
}

Write-WslVhdSection -Title 'Tarefa Agendada'
$previousErrorActionPreference = $ErrorActionPreference
$nativePreference = Get-Variable -Name PSNativeCommandUseErrorActionPreference -ErrorAction SilentlyContinue
$previousNativePreference = $null
if ($nativePreference) {
    $previousNativePreference = $PSNativeCommandUseErrorActionPreference
    $PSNativeCommandUseErrorActionPreference = $false
}

try {
    $ErrorActionPreference = 'Continue'
    $taskOutputRaw = & schtasks.exe /Query /TN $taskName /FO LIST /V 2>&1
    $taskExitCode = $LASTEXITCODE
    $taskOutput = foreach ($line in $taskOutputRaw) {
        if ($line -is [System.Management.Automation.ErrorRecord]) {
            $line.Exception.Message
        }
        else {
            [string]$line
        }
    }
}
finally {
    $ErrorActionPreference = $previousErrorActionPreference
    if ($nativePreference) {
        $PSNativeCommandUseErrorActionPreference = $previousNativePreference
    }
}

if ($taskExitCode -ne 0) {
    Write-WslVhdTerminal -Level WARN -Message "Tarefa nao encontrada: $taskName"
    if ($taskOutput) {
        $taskOutput | ForEach-Object { Write-Host $_ }
    }
}
else {
    Write-WslVhdTerminal -Level OK -Message "Tarefa encontrada: $taskName"
    $taskOutput | ForEach-Object { Write-Host $_ }
}
