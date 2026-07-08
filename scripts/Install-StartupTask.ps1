[CmdletBinding()]
param(
    [string]$ConfigPath = '',
    [string]$TaskName = '',
    [switch]$RunNow,
    [switch]$NoElevate
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'WslVhd.Common.ps1')

if (-not (Test-WslVhdAdministrator)) {
    if ($NoElevate) {
        throw "Execute este script como Administrador para registrar a Tarefa Agendada."
    }

    $elevatedArgs = @()
    if (-not [string]::IsNullOrWhiteSpace($ConfigPath)) {
        $elevatedArgs += @('-ConfigPath', $ConfigPath)
    }
    if (-not [string]::IsNullOrWhiteSpace($TaskName)) {
        $elevatedArgs += @('-TaskName', $TaskName)
    }
    if ($RunNow) { $elevatedArgs += '-RunNow' }

    Invoke-WslVhdSelfElevation -ScriptPath $PSCommandPath -ArgumentList $elevatedArgs
}

$configArgs = @{}
if (-not [string]::IsNullOrWhiteSpace($ConfigPath)) {
    $configArgs['ConfigPath'] = $ConfigPath
}

$config = Get-WslVhdConfig @configArgs
$projectRoot = [string]$config['ProjectRoot']

if ([string]::IsNullOrWhiteSpace($TaskName)) {
    $TaskName = [string](Get-WslVhdConfigValue -Config $config -Name 'TaskName' -Default 'WSL VHD Automount')
}

$mountScript = Join-Path $projectRoot 'scripts\Mount-WslVhd.ps1'
$driveRoot = [System.IO.Path]::GetPathRoot($projectRoot)
$relativeProjectRoot = $projectRoot.Substring($driveRoot.Length).TrimStart('\')
$relativeMountScript = Join-Path $relativeProjectRoot 'scripts\Mount-WslVhd.ps1'

$bootstrapDir = Join-Path $env:LOCALAPPDATA 'WslVhdAutomount'
$bootstrapPath = Join-Path $bootstrapDir 'Start-WslVhdAutomount.ps1'
$bootstrapLog = Join-Path $bootstrapDir 'bootstrap.log'

New-Item -ItemType Directory -Force -Path $bootstrapDir | Out-Null

$bootstrap = @"
`$ErrorActionPreference = 'Stop'
`$relativeMountScript = '$($relativeMountScript -replace "'", "''")'
`$fallbackMountScript = '$($mountScript -replace "'", "''")'
`$logPath = '$($bootstrapLog -replace "'", "''")'

function Write-BootstrapLog {
    param([string]`$Message)
    `$timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    Add-Content -Path `$logPath -Value "[`$timestamp] `$Message"
}

try {
    `$mountScript = `$null

    foreach (`$drive in Get-PSDrive -PSProvider FileSystem) {
        `$candidate = Join-Path `$drive.Root `$relativeMountScript
        if (Test-Path -LiteralPath `$candidate) {
            `$mountScript = `$candidate
            break
        }
    }

    if (-not `$mountScript -and (Test-Path -LiteralPath `$fallbackMountScript)) {
        `$mountScript = `$fallbackMountScript
    }

    if (-not `$mountScript) {
        throw "Nao encontrei o script de montagem: `$relativeMountScript"
    }

    Write-BootstrapLog "Executando `$mountScript"
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File `$mountScript
    exit `$LASTEXITCODE
}
catch {
    Write-BootstrapLog `$_.Exception.Message
    exit 1
}
"@

Set-Content -LiteralPath $bootstrapPath -Value $bootstrap -Encoding ASCII

$powershell = (Get-Command powershell.exe -ErrorAction Stop).Source
$actionArgs = Join-WslVhdCommandLine -ArgumentList @(
    '-NoProfile',
    '-ExecutionPolicy', 'Bypass',
    '-WindowStyle', 'Hidden',
    '-File', $bootstrapPath
)

$action = New-ScheduledTaskAction -Execute $powershell -Argument $actionArgs
$userId = "$env:USERDOMAIN\$env:USERNAME"
$trigger = New-ScheduledTaskTrigger -AtLogOn -User $userId
$principal = New-ScheduledTaskPrincipal -UserId $userId -LogonType Interactive -RunLevel Highest
$settings = New-ScheduledTaskSettingsSet `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries `
    -StartWhenAvailable `
    -MultipleInstances IgnoreNew `
    -ExecutionTimeLimit (New-TimeSpan -Minutes 15)

Register-ScheduledTask `
    -TaskName $TaskName `
    -Action $action `
    -Trigger $trigger `
    -Principal $principal `
    -Settings $settings `
    -Description 'Monta automaticamente um VHDX ext4 no WSL 2 ao fazer logon.' `
    -Force | Out-Null

Write-Host "OK: tarefa registrada: $TaskName"
Write-Host "Bootstrap: $bootstrapPath"

if ($RunNow) {
    Start-ScheduledTask -TaskName $TaskName
    Write-Host "Tarefa iniciada agora. Veja logs em: $bootstrapDir"
}
