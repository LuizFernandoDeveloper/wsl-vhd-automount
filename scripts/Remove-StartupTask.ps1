[CmdletBinding()]
param(
    [string]$ConfigPath = '',
    [string]$TaskName = '',
    [switch]$KeepBootstrap,
    [switch]$NoElevate
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'WslVhd.Common.ps1')

if (-not (Test-WslVhdAdministrator)) {
    if ($NoElevate) {
        throw "Execute este script como Administrador para remover a Tarefa Agendada."
    }

    $elevatedArgs = @()
    if (-not [string]::IsNullOrWhiteSpace($ConfigPath)) {
        $elevatedArgs += @('-ConfigPath', $ConfigPath)
    }
    if (-not [string]::IsNullOrWhiteSpace($TaskName)) {
        $elevatedArgs += @('-TaskName', $TaskName)
    }
    if ($KeepBootstrap) { $elevatedArgs += '-KeepBootstrap' }

    Invoke-WslVhdSelfElevation -ScriptPath $PSCommandPath -ArgumentList $elevatedArgs
}

$configArgs = @{}
if (-not [string]::IsNullOrWhiteSpace($ConfigPath)) {
    $configArgs['ConfigPath'] = $ConfigPath
}

$config = Get-WslVhdConfig @configArgs

if ([string]::IsNullOrWhiteSpace($TaskName)) {
    $TaskName = [string](Get-WslVhdConfigValue -Config $config -Name 'TaskName' -Default 'WSL VHD Automount')
}

$task = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
if ($null -ne $task) {
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
    Write-WslVhdTerminal -Level OK -Message "Tarefa removida: $TaskName"
}
else {
    Write-WslVhdTerminal -Level WARN -Message "Tarefa nao encontrada: $TaskName"
}

if (-not $KeepBootstrap) {
    $bootstrapPath = Join-Path (Join-Path $env:LOCALAPPDATA 'WslVhdAutomount') 'Start-WslVhdAutomount.ps1'
    if (Test-Path -LiteralPath $bootstrapPath) {
        Remove-Item -LiteralPath $bootstrapPath -Force
        Write-WslVhdTerminal -Level OK -Message "Bootstrap removido: $bootstrapPath"
    }
}
