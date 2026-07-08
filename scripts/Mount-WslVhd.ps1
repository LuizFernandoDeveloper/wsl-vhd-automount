[CmdletBinding()]
param(
    [string]$ConfigPath = '',
    [switch]$NoStartDistro,
    [switch]$ForceRemount,
    [switch]$NoElevate,
    [switch]$NoTranscript
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'WslVhd.Common.ps1')

if (-not (Test-WslVhdAdministrator)) {
    if ($NoElevate) {
        throw "Execute este script como Administrador para usar Mount-VHD e wsl --mount."
    }

    $elevatedArgs = @()
    if (-not [string]::IsNullOrWhiteSpace($ConfigPath)) {
        $elevatedArgs += @('-ConfigPath', $ConfigPath)
    }
    if ($NoStartDistro) { $elevatedArgs += '-NoStartDistro' }
    if ($ForceRemount) { $elevatedArgs += '-ForceRemount' }
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
$mountName = [string](Get-WslVhdConfigValue -Config $config -Name 'MountName' -Default 'media-removivel')
$fileSystem = [string](Get-WslVhdConfigValue -Config $config -Name 'FileSystem' -Default 'ext4')
$partition = Get-WslVhdConfigValue -Config $config -Name 'Partition'
$mountOptions = [string](Get-WslVhdConfigValue -Config $config -Name 'MountOptions' -Default '')
$distroName = [string](Get-WslVhdConfigValue -Config $config -Name 'DistroName' -Default '')
$startDistro = [bool](Get-WslVhdConfigValue -Config $config -Name 'StartDistro' -Default $false)
$preferDirectVhdMount = [bool](Get-WslVhdConfigValue -Config $config -Name 'PreferDirectVhdMount' -Default $false)
$warmWslService = [bool](Get-WslVhdConfigValue -Config $config -Name 'WarmWslService' -Default $true)

Assert-WslVhdMountName -MountName $mountName

$transcriptStarted = $false
try {
    if (-not $NoTranscript) {
        $logPath = Start-WslVhdLog -Config $config
        $transcriptStarted = $true
        Write-WslVhdTerminal -Level INFO -Message "Log: $logPath"
    }

    Get-Command wsl.exe -ErrorAction Stop | Out-Null

    if ($warmWslService) {
        try {
            $service = Get-Service -Name 'LxssManager' -ErrorAction Stop
            if ($service.Status -ne 'Running') {
                Write-WslVhdTerminal -Level INFO -Message "Acordando servico WSL: LxssManager"
                Start-Service -Name 'LxssManager' -ErrorAction Stop
            }
        }
        catch {
            Write-WslVhdTerminal -Level WARN -Message "Nao foi possivel acordar LxssManager antes do mount: $($_.Exception.Message)"
        }
    }

    if ($ForceRemount) {
        Write-WslVhdTerminal -Level INFO -Message "Forcando remontagem anterior, se existir."
        if ($preferDirectVhdMount) {
            Invoke-WslVhdNativeCommand -FilePath 'wsl.exe' -ArgumentList @('--unmount', $vhdPath) -IgnoreExitCode | Out-Null
        }
        else {
            $existingImage = Get-DiskImage -ImagePath $vhdPath -ErrorAction SilentlyContinue
            if ($null -ne $existingImage -and $existingImage.Attached) {
                $existingDisk = Get-WslVhdDisk -VhdPath $vhdPath
                $existingDiskPath = Get-WslVhdDiskPath -Disk $existingDisk
                Invoke-WslVhdNativeCommand -FilePath 'wsl.exe' -ArgumentList @('--unmount', $existingDiskPath) -IgnoreExitCode | Out-Null
            }
        }
    }

    if ($preferDirectVhdMount) {
        $diskPath = $vhdPath
        $mountArgs = @('--mount', $vhdPath, '--vhd')
    }
    else {
        Get-Command Mount-VHD -ErrorAction Stop | Out-Null

        $image = Get-DiskImage -ImagePath $vhdPath -ErrorAction Stop
        if (-not $image.Attached) {
            Write-WslVhdTerminal -Level INFO -Message "Anexando VHD no Windows: $vhdPath"
            Mount-VHD -Path $vhdPath -ErrorAction Stop | Out-Null
        }
        else {
            Write-WslVhdTerminal -Level OK -Message "VHD ja estava anexado no Windows."
        }

        $disk = Get-WslVhdDisk -VhdPath $vhdPath
        $diskPath = Get-WslVhdDiskPath -Disk $disk
        Write-WslVhdTerminal -Level INFO -Message "Disco detectado dinamicamente: $diskPath"
        $mountArgs = @('--mount', $diskPath)
    }

    if (-not [string]::IsNullOrWhiteSpace($fileSystem)) {
        $mountArgs += @('--type', $fileSystem)
    }

    $mountArgs += @('--name', $mountName)

    if ($null -ne $partition -and "$partition" -ne '') {
        $mountArgs += @('--partition', "$partition")
    }

    if (-not [string]::IsNullOrWhiteSpace($mountOptions)) {
        $mountArgs += @('--options', $mountOptions)
    }

    $result = Invoke-WslVhdNativeCommand -FilePath 'wsl.exe' -ArgumentList $mountArgs -IgnoreExitCode
    if ($result.ExitCode -ne 0) {
        if (Test-WslVhdMountAvailable -MountName $mountName -DistroName $distroName) {
            Write-WslVhdTerminal -Level WARN -Message "O WSL retornou aviso/erro, mas o ponto /mnt/wsl/$mountName ja esta montado."
        }
        else {
            throw "Falha ao montar o disco no WSL. Veja o log para a saida completa."
        }
    }

    if ($startDistro -and -not $NoStartDistro -and -not [string]::IsNullOrWhiteSpace($distroName)) {
        Write-WslVhdTerminal -Level INFO -Message "Acordando distro configurada: $distroName"
        Invoke-WslVhdNativeCommand -FilePath 'wsl.exe' -ArgumentList @('-d', $distroName, '--exec', 'sh', '-lc', 'true') | Out-Null
    }

    if (Test-WslVhdMountAvailable -MountName $mountName -DistroName $distroName) {
        Write-WslVhdTerminal -Level OK -Message "Disponivel em /mnt/wsl/$mountName"
    }
    else {
        Write-WslVhdTerminal -Level WARN -Message "Montagem concluida, mas nao consegui confirmar /mnt/wsl/$mountName pelo probe do WSL."
    }
}
finally {
    if ($transcriptStarted) {
        Stop-Transcript | Out-Null
    }
}
