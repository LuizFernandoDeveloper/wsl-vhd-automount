[CmdletBinding()]
param(
    [string]$ConfigPath = '',
    [string]$TaskName = '',
    [int]$InitialDelaySeconds = -1,
    [int]$RetryMinutes = -1,
    [int]$RetryIntervalSeconds = -1,
    [int]$TaskPriority = -1,
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
    if ($InitialDelaySeconds -ge 0) {
        $elevatedArgs += @('-InitialDelaySeconds', "$InitialDelaySeconds")
    }
    if ($RetryMinutes -ge 0) {
        $elevatedArgs += @('-RetryMinutes', "$RetryMinutes")
    }
    if ($RetryIntervalSeconds -ge 0) {
        $elevatedArgs += @('-RetryIntervalSeconds', "$RetryIntervalSeconds")
    }
    if ($TaskPriority -ge 0) {
        $elevatedArgs += @('-TaskPriority', "$TaskPriority")
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

if ($InitialDelaySeconds -lt 0) {
    $InitialDelaySeconds = [int](Get-WslVhdConfigValue -Config $config -Name 'StartupInitialDelaySeconds' -Default 0)
}
if ($RetryMinutes -lt 0) {
    $RetryMinutes = [int](Get-WslVhdConfigValue -Config $config -Name 'StartupRetryMinutes' -Default 10)
}
if ($RetryIntervalSeconds -lt 0) {
    $RetryIntervalSeconds = [int](Get-WslVhdConfigValue -Config $config -Name 'StartupRetryIntervalSeconds' -Default 3)
}
if ($TaskPriority -lt 0) {
    $TaskPriority = [int](Get-WslVhdConfigValue -Config $config -Name 'TaskPriority' -Default 4)
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
`$initialDelaySeconds = $InitialDelaySeconds
`$retryMinutes = $RetryMinutes
`$retryIntervalSeconds = $RetryIntervalSeconds

function Write-BootstrapLog {
    param([string]`$Message)
    `$timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    Add-Content -Path `$logPath -Value "[`$timestamp] `$Message"
}

function Find-MountScript {
    `$mountScript = `$null

    foreach (`$drive in Get-PSDrive -PSProvider FileSystem) {
        try {
            `$candidate = Join-Path `$drive.Root `$relativeMountScript
            if (Test-Path -LiteralPath `$candidate) {
                return `$candidate
            }
        }
        catch {
            Write-BootstrapLog "Drive ainda indisponivel: `$(`$drive.Root)"
        }
    }

    if (Test-Path -LiteralPath `$fallbackMountScript) {
        return `$fallbackMountScript
    }

    return `$null
}

try {
    if (`$initialDelaySeconds -gt 0) {
        Write-BootstrapLog "Aguardando `$initialDelaySeconds segundos pelo logon/BitLocker."
        Start-Sleep -Seconds `$initialDelaySeconds
    }

    `$deadline = (Get-Date).AddMinutes(`$retryMinutes)
    `$lastError = ''

    do {
        `$mountScript = Find-MountScript

        if (-not `$mountScript) {
            `$lastError = "Nao encontrei o script de montagem: `$relativeMountScript"
            Write-BootstrapLog "`$lastError. O volume pode estar bloqueado pelo BitLocker."
        }
        else {
            Write-BootstrapLog "Executando `$mountScript"
            & powershell.exe -NoProfile -ExecutionPolicy Bypass -File `$mountScript -NoElevate
            `$exitCode = `$LASTEXITCODE

            if (`$exitCode -eq 0) {
                Write-BootstrapLog "Montagem concluida com sucesso."
                exit 0
            }

            `$lastError = "Script de montagem saiu com codigo `$exitCode"
            Write-BootstrapLog "`$lastError. Tentando novamente."
        }

        Start-Sleep -Seconds `$retryIntervalSeconds
    } while ((Get-Date) -lt `$deadline)

    throw "`$lastError"
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
    -Priority $TaskPriority `
    -RestartCount 20 `
    -RestartInterval (New-TimeSpan -Seconds 15) `
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
Write-Host "Politica BitLocker/logon: inicio imediato, atraso inicial de $InitialDelaySeconds s, tentativas por $RetryMinutes min a cada $RetryIntervalSeconds s, prioridade $TaskPriority."

if ($RunNow) {
    Start-ScheduledTask -TaskName $TaskName
    Write-Host "Tarefa iniciada agora. Veja logs em: $bootstrapDir"
}
