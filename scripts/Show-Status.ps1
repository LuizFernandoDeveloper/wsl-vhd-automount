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

Write-Host "Projeto: $projectRoot"
Write-Host "Config:  $($config['ConfigPath'])"
Write-Host "VHDX:    $vhdPath"

$image = Get-DiskImage -ImagePath $vhdPath -ErrorAction Stop
$sizeGb = [math]::Round($image.Size / 1GB, 2)
$fileSizeGb = [math]::Round($image.FileSize / 1GB, 2)

Write-Host "Tamanho virtual: $sizeGb GB"
Write-Host "Tamanho em disco: $fileSizeGb GB"
Write-Host "Anexado no Windows: $($image.Attached)"

if ($image.Attached) {
    try {
        $disk = Get-WslVhdDisk -VhdPath $vhdPath -TimeoutSeconds 3
        Write-Host "PhysicalDrive atual: $(Get-WslVhdDiskPath -Disk $disk)"
    }
    catch {
        Write-Warning $_.Exception.Message
    }
}

Write-Host "Mount WSL esperado: /mnt/wsl/$mountName"

if (-not $SkipWslProbe) {
    $mounted = Test-WslVhdMountAvailable -MountName $mountName -DistroName $distroName
    Write-Host "Montado no WSL: $mounted"
}

Write-Host ""
Write-Host "Distribuicoes WSL:"
Invoke-WslVhdNativeCommand -FilePath 'wsl.exe' -ArgumentList @('--list', '--verbose') -IgnoreExitCode | Out-Null
