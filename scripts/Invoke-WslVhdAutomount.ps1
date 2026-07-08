[CmdletBinding()]
param(
    [string]$ConfigPath = '',
    [switch]$NoElevate
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'WslVhd.Common.ps1')

if (-not (Test-WslVhdAdministrator)) {
    if ($NoElevate) {
        throw "Execute como Administrador para montar VHDX no WSL."
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
$logDirectory = Resolve-WslVhdPath -Path ([string](Get-WslVhdConfigValue -Config $config -Name 'LogDirectory' -Default '.\logs')) -BasePath $projectRoot
$errorLogDirectory = Resolve-WslVhdPath -Path ([string](Get-WslVhdConfigValue -Config $config -Name 'ErrorLogDirectory' -Default '.\logs\errors')) -BasePath $projectRoot
$latestLogName = [string](Get-WslVhdConfigValue -Config $config -Name 'LatestLogName' -Default 'automount.latest.log')

New-Item -ItemType Directory -Force -Path $logDirectory | Out-Null
New-Item -ItemType Directory -Force -Path $errorLogDirectory | Out-Null

$latestLogPath = Join-Path $logDirectory $latestLogName
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$tempLogPath = Join-Path $logDirectory "automount.$stamp.tmp.log"

function Test-WslVhdLogHasError {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        return $false
    }

    $content = Get-Content -Raw -LiteralPath $Path -ErrorAction SilentlyContinue
    return ($content -match '(?m)^Result:\s*ERROR\b')
}

function Write-WslVhdRunLog {
    param([string]$Message)

    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff'
    Add-Content -LiteralPath $tempLogPath -Value "[$timestamp] $Message"
}

if (Test-WslVhdLogHasError -Path $latestLogPath) {
    $previousErrorPath = Join-Path $errorLogDirectory "automount.$stamp.previous-error.log"
    Move-Item -LiteralPath $latestLogPath -Destination $previousErrorPath -Force
}

$exitCode = 1

try {
    $vhdPath = Resolve-WslVhdPath -Path ([string](Get-WslVhdConfigValue -Config $config -Name 'VhdPath')) -BasePath $projectRoot -MustExist
    $mountName = [string](Get-WslVhdConfigValue -Config $config -Name 'MountName' -Default 'media-removivel')
    $fileSystem = [string](Get-WslVhdConfigValue -Config $config -Name 'FileSystem' -Default 'ext4')
    $partition = Get-WslVhdConfigValue -Config $config -Name 'Partition'
    $mountOptions = [string](Get-WslVhdConfigValue -Config $config -Name 'MountOptions' -Default '')
    $distroName = [string](Get-WslVhdConfigValue -Config $config -Name 'DistroName' -Default '')

    Assert-WslVhdMountName -MountName $mountName

    $wslExe = Join-Path $env:WINDIR 'System32\wsl.exe'
    $mountArgs = @('--mount', $vhdPath, '--vhd')

    if (-not [string]::IsNullOrWhiteSpace($fileSystem)) {
        $mountArgs += @('--type', $fileSystem)
    }
    if (-not [string]::IsNullOrWhiteSpace($mountName)) {
        $mountArgs += @('--name', $mountName)
    }
    if ($null -ne $partition -and "$partition" -ne '') {
        $mountArgs += @('--partition', "$partition")
    }
    if (-not [string]::IsNullOrWhiteSpace($mountOptions)) {
        $mountArgs += @('--options', $mountOptions)
    }

    Write-WslVhdRunLog "ProjectRoot: $projectRoot"
    Write-WslVhdRunLog "ConfigPath: $($config['ConfigPath'])"
    Write-WslVhdRunLog "Program: $wslExe"
    Write-WslVhdRunLog "Arguments: $(Join-WslVhdCommandLine -ArgumentList $mountArgs)"

    $output = & $wslExe @mountArgs 2>&1
    $exitCode = $LASTEXITCODE

    if ($null -ne $output) {
        $output | ForEach-Object { Write-WslVhdRunLog "wsl: $_" }
    }

    if ($exitCode -ne 0) {
        if (Test-WslVhdMountAvailable -MountName $mountName -DistroName $distroName) {
            Write-WslVhdRunLog "wsl.exe saiu com codigo $exitCode, mas /mnt/wsl/$mountName ja esta montado."
            $exitCode = 0
        }
        else {
            throw "wsl.exe saiu com codigo $exitCode."
        }
    }

    Write-WslVhdRunLog "MountPath: /mnt/wsl/$mountName"
    Add-Content -LiteralPath $tempLogPath -Value 'Result: SUCCESS'
    Add-Content -LiteralPath $tempLogPath -Value 'ExitCode: 0'
    Move-Item -LiteralPath $tempLogPath -Destination $latestLogPath -Force
    exit 0
}
catch {
    Write-WslVhdRunLog "ERROR: $($_.Exception.Message)"
    Add-Content -LiteralPath $tempLogPath -Value 'Result: ERROR'
    Add-Content -LiteralPath $tempLogPath -Value "ExitCode: $exitCode"

    $errorLogPath = Join-Path $errorLogDirectory "automount.$stamp.error.log"
    Copy-Item -LiteralPath $tempLogPath -Destination $errorLogPath -Force
    Move-Item -LiteralPath $tempLogPath -Destination $latestLogPath -Force
    exit $exitCode
}
