[CmdletBinding()]
param(
    [string]$ConfigPath = '',
    [switch]$SkipWslProbe
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'WslVhd.Common.ps1')

$configArgs = @{}
if (-not [string]::IsNullOrWhiteSpace($ConfigPath)) {
    $configArgs['ConfigPath'] = $ConfigPath
}

$config = Get-WslVhdConfig @configArgs
$projectRoot = [string]$config['ProjectRoot']
$vhdPath = Resolve-WslVhdPath -Path ([string](Get-WslVhdConfigValue -Config $config -Name 'VhdPath')) -BasePath $projectRoot -MustExist
$mountName = [string](Get-WslVhdConfigValue -Config $config -Name 'MountName' -Default 'media-removivel')
$distroName = [string](Get-WslVhdConfigValue -Config $config -Name 'DistroName' -Default '')

Assert-WslVhdMountName -MountName $mountName

Write-WslVhdSection -Title 'Status'
Write-WslVhdTerminal -Level INFO -Message "Projeto: $projectRoot"
Write-WslVhdTerminal -Level INFO -Message "Config: $($config['ConfigPath'])"
Write-WslVhdTerminal -Level INFO -Message "VHDX: $vhdPath"

$image = Get-DiskImage -ImagePath $vhdPath -ErrorAction Stop
$sizeGb = [math]::Round($image.Size / 1GB, 2)
$fileSizeGb = [math]::Round($image.FileSize / 1GB, 2)

Write-WslVhdTerminal -Level INFO -Message "Tamanho virtual: $sizeGb GB"
Write-WslVhdTerminal -Level INFO -Message "Tamanho em disco: $fileSizeGb GB"
if ($image.Attached) {
    Write-WslVhdTerminal -Level OK -Message 'Anexado no Windows: True'
}
else {
    Write-WslVhdTerminal -Level WARN -Message 'Anexado no Windows: False'
}

if ($image.Attached) {
    try {
        $disk = Get-WslVhdDisk -VhdPath $vhdPath -TimeoutSeconds 3
        Write-WslVhdTerminal -Level INFO -Message "PhysicalDrive atual: $(Get-WslVhdDiskPath -Disk $disk)"
    }
    catch {
        Write-WslVhdTerminal -Level WARN -Message $_.Exception.Message
    }
}

Write-WslVhdTerminal -Level INFO -Message "Mount WSL esperado: /mnt/wsl/$mountName"

if (-not $SkipWslProbe) {
    $mounted = Test-WslVhdMountAvailable -MountName $mountName -DistroName $distroName
    if ($mounted) {
        Write-WslVhdTerminal -Level OK -Message 'Montado no WSL: True'
    }
    else {
        Write-WslVhdTerminal -Level WARN -Message 'Montado no WSL: False'
    }
}

Write-WslVhdSection -Title 'Distribuicoes WSL'
Invoke-WslVhdNativeCommand -FilePath 'wsl.exe' -ArgumentList @('--list', '--verbose') -IgnoreExitCode | Out-Null
