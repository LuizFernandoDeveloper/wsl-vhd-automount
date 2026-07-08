[CmdletBinding()]
param(
    [string]$ConfigPath = '',
    [string]$TaskName = '',
    [int]$InitialDelaySeconds = -1,
    [int]$RetryMinutes = -1,
    [int]$RetryIntervalSeconds = -1,
    [int]$TaskPriority = -1,
    [string]$TaskMode = '',
    [switch]$RunNow,
    [switch]$NoElevate,
    [string]$InstallLogPath = ''
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'WslVhd.Common.ps1')

$script:InstallTranscriptStarted = $false

function Stop-WslVhdInstallTranscript {
    if ($script:InstallTranscriptStarted) {
        try {
            Stop-Transcript | Out-Null
        }
        catch {
            Write-WslVhdTerminal -Level WARN -Message "Nao foi possivel encerrar o log do instalador: $($_.Exception.Message)"
        }
        finally {
            $script:InstallTranscriptStarted = $false
        }
    }
}

if (-not [string]::IsNullOrWhiteSpace($InstallLogPath)) {
    try {
        $installLogDirectory = Split-Path -Parent $InstallLogPath
        if (-not [string]::IsNullOrWhiteSpace($installLogDirectory)) {
            New-Item -ItemType Directory -Force -Path $installLogDirectory | Out-Null
        }

        Start-Transcript -Path $InstallLogPath -Append | Out-Null
        $script:InstallTranscriptStarted = $true
        Write-WslVhdTerminal -Level INFO -Message "Log do instalador: $InstallLogPath"
    }
    catch {
        Write-WslVhdTerminal -Level WARN -Message "Nao foi possivel iniciar o log do instalador em '$InstallLogPath': $($_.Exception.Message)"
    }
}

trap {
    Write-WslVhdTerminal -Level ERROR -Message $_.Exception.Message
    Stop-WslVhdInstallTranscript
    exit 1
}

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
    if (-not [string]::IsNullOrWhiteSpace($TaskMode)) {
        $elevatedArgs += @('-TaskMode', $TaskMode)
    }
    if ($RunNow) { $elevatedArgs += '-RunNow' }
    if (-not [string]::IsNullOrWhiteSpace($InstallLogPath)) {
        $elevatedArgs += @('-InstallLogPath', $InstallLogPath)
    }

    Write-WslVhdTerminal -Level INFO -Message "Solicitando permissao de Administrador para registrar a Tarefa Agendada..."
    Stop-WslVhdInstallTranscript

    try {
        Invoke-WslVhdSelfElevation -ScriptPath $PSCommandPath -ArgumentList $elevatedArgs -ThrowOnFailure
    }
    catch {
        if (-not [string]::IsNullOrWhiteSpace($InstallLogPath)) {
            try {
                Start-Transcript -Path $InstallLogPath -Append | Out-Null
                $script:InstallTranscriptStarted = $true
            }
            catch {
                Write-WslVhdTerminal -Level WARN -Message "Nao foi possivel reabrir o log do instalador em '$InstallLogPath': $($_.Exception.Message)"
            }
        }

        Write-WslVhdTerminal -Level ERROR -Message "Falha ao abrir permissao de Administrador/UAC: $($_.Exception.Message)"
        Stop-WslVhdInstallTranscript
        exit 1
    }
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
if ([string]::IsNullOrWhiteSpace($TaskMode)) {
    $TaskMode = [string](Get-WslVhdConfigValue -Config $config -Name 'StartupTaskMode' -Default 'Direct')
}

$validTaskModes = @('Logged', 'Direct', 'Bootstrap')
if ($TaskMode -notin $validTaskModes) {
    throw "StartupTaskMode invalido: '$TaskMode'. Use Logged, Direct ou Bootstrap."
}

$bootstrapDir = Join-Path $env:LOCALAPPDATA 'WslVhdAutomount'
$bootstrapPath = Join-Path $bootstrapDir 'Start-WslVhdAutomount.ps1'
$bootstrapLog = Join-Path $bootstrapDir 'bootstrap.log'

$taskHidden = [bool](Get-WslVhdConfigValue -Config $config -Name 'TaskHidden' -Default $true)

if ($TaskMode -eq 'Logged') {
    $runnerScript = Join-Path $projectRoot 'scripts\Invoke-WslVhdAutomount.ps1'
    $powershell = (Get-Command powershell.exe -ErrorAction Stop).Source
    $runnerArgs = @(
        '-NoProfile',
        '-ExecutionPolicy', 'Bypass',
        '-WindowStyle', 'Hidden',
        '-File', $runnerScript
    )

    if (-not [string]::IsNullOrWhiteSpace($ConfigPath)) {
        $runnerArgs += @('-ConfigPath', $ConfigPath)
    }

    $action = New-ScheduledTaskAction -Execute $powershell -Argument (Join-WslVhdCommandLine -ArgumentList $runnerArgs)
}
elseif ($TaskMode -eq 'Direct') {
    $vhdPath = Resolve-WslVhdPath -Path ([string](Get-WslVhdConfigValue -Config $config -Name 'VhdPath')) -BasePath $projectRoot -MustExist
    $mountName = [string](Get-WslVhdConfigValue -Config $config -Name 'MountName' -Default 'media-removivel')
    $fileSystem = [string](Get-WslVhdConfigValue -Config $config -Name 'FileSystem' -Default 'ext4')
    $partition = Get-WslVhdConfigValue -Config $config -Name 'Partition'
    $mountOptions = [string](Get-WslVhdConfigValue -Config $config -Name 'MountOptions' -Default '')

    Assert-WslVhdMountName -MountName $mountName

    $wslExe = Join-Path $env:WINDIR 'System32\wsl.exe'
    $directArgs = @('--mount', $vhdPath, '--vhd')

    if (-not [string]::IsNullOrWhiteSpace($fileSystem)) {
        $directArgs += @('--type', $fileSystem)
    }

    if (-not [string]::IsNullOrWhiteSpace($mountName)) {
        $directArgs += @('--name', $mountName)
    }

    if ($null -ne $partition -and "$partition" -ne '') {
        $directArgs += @('--partition', "$partition")
    }

    if (-not [string]::IsNullOrWhiteSpace($mountOptions)) {
        $directArgs += @('--options', $mountOptions)
    }

    $action = New-ScheduledTaskAction -Execute $wslExe -Argument (Join-WslVhdCommandLine -ArgumentList $directArgs)
}
else {
    $mountScript = Join-Path $projectRoot 'scripts\Mount-WslVhd.ps1'
    $driveRoot = [System.IO.Path]::GetPathRoot($projectRoot)
    $relativeProjectRoot = $projectRoot.Substring($driveRoot.Length).TrimStart('\')
    $relativeMountScript = Join-Path $relativeProjectRoot 'scripts\Mount-WslVhd.ps1'

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
}
$userId = "$env:USERDOMAIN\$env:USERNAME"
$trigger = New-ScheduledTaskTrigger -AtLogOn -User $userId
$principal = New-ScheduledTaskPrincipal -UserId $userId -LogonType Interactive -RunLevel Highest
$effectiveRetryIntervalSeconds = [Math]::Max(1, $RetryIntervalSeconds)
$effectiveRestartCount = [Math]::Max(1, [int][Math]::Ceiling(($RetryMinutes * 60) / [double]$effectiveRetryIntervalSeconds))
$settingsArgs = @{
    AllowStartIfOnBatteries = $true
    DontStopIfGoingOnBatteries = $true
    StartWhenAvailable = $true
    MultipleInstances = 'IgnoreNew'
    Priority = $TaskPriority
    RestartCount = $effectiveRestartCount
    RestartInterval = (New-TimeSpan -Seconds $effectiveRetryIntervalSeconds)
    ExecutionTimeLimit = (New-TimeSpan -Minutes 15)
}
if ($taskHidden) {
    $settingsArgs['Hidden'] = $true
}
$settings = New-ScheduledTaskSettingsSet @settingsArgs

Register-ScheduledTask `
    -TaskName $TaskName `
    -Action $action `
    -Trigger $trigger `
    -Principal $principal `
    -Settings $settings `
    -Description 'Monta automaticamente um VHDX ext4 no WSL 2 ao fazer logon.' `
    -Force | Out-Null

Write-WslVhdTerminal -Level OK -Message "Tarefa registrada: $TaskName"
Write-WslVhdTerminal -Level INFO -Message "Modo: $TaskMode"
if ($TaskMode -eq 'Logged') {
    Write-WslVhdTerminal -Level INFO -Message "Programa/script: $powershell"
    Write-WslVhdTerminal -Level INFO -Message "Argumentos: $(Join-WslVhdCommandLine -ArgumentList $runnerArgs)"
    Write-WslVhdTerminal -Level INFO -Message "Log: $((Resolve-WslVhdPath -Path ([string](Get-WslVhdConfigValue -Config $config -Name 'LogDirectory' -Default '.\logs')) -BasePath $projectRoot))"
}
elseif ($TaskMode -eq 'Direct') {
    Write-WslVhdTerminal -Level INFO -Message "Programa/script: $wslExe"
    Write-WslVhdTerminal -Level INFO -Message "Argumentos: $(Join-WslVhdCommandLine -ArgumentList $directArgs)"
}
else {
    Write-WslVhdTerminal -Level INFO -Message "Bootstrap: $bootstrapPath"
}
Write-WslVhdTerminal -Level INFO -Message "Politica BitLocker/logon: inicio imediato, atraso inicial de $InitialDelaySeconds s, restart por $RetryMinutes min a cada $effectiveRetryIntervalSeconds s, prioridade $TaskPriority."

if ($RunNow) {
    Start-ScheduledTask -TaskName $TaskName
    if ($TaskMode -eq 'Bootstrap') {
        Write-WslVhdTerminal -Level OK -Message "Tarefa iniciada agora. Veja logs em: $bootstrapDir"
    }
    elseif ($TaskMode -eq 'Logged') {
        Write-WslVhdTerminal -Level OK -Message "Tarefa silenciosa iniciada agora. Veja logs na pasta configurada."
    }
    else {
        Write-WslVhdTerminal -Level OK -Message "Tarefa direta iniciada agora. Confira o resultado no Agendador de Tarefas ou rode .\scripts\Show-Status.ps1."
    }
}

Stop-WslVhdInstallTranscript
