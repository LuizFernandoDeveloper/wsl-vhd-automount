Set-StrictMode -Version 2.0

function Get-WslVhdProjectRoot {
    return (Split-Path -Parent $PSScriptRoot)
}

function Resolve-WslVhdPath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [string]$BasePath = (Get-WslVhdProjectRoot),

        [switch]$MustExist
    )

    if ([System.IO.Path]::IsPathRooted($Path)) {
        $candidate = $Path
    }
    else {
        $candidate = Join-Path -Path $BasePath -ChildPath $Path
    }

    if ($MustExist) {
        return (Resolve-Path -LiteralPath $candidate -ErrorAction Stop).ProviderPath
    }

    return $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($candidate)
}

function Get-WslVhdConfig {
    param(
        [string]$ConfigPath = (Join-Path (Get-WslVhdProjectRoot) 'config\wsl-vhd.config.ps1')
    )

    $resolvedConfigPath = Resolve-WslVhdPath -Path $ConfigPath -BasePath (Get-WslVhdProjectRoot) -MustExist
    $WslVhdConfig = $null
    . $resolvedConfigPath

    if ($null -eq $WslVhdConfig -or -not ($WslVhdConfig -is [hashtable])) {
        throw "Config invalida. O arquivo precisa definir `$WslVhdConfig como hashtable: $resolvedConfigPath"
    }

    $config = @{}
    foreach ($key in $WslVhdConfig.Keys) {
        $config[$key] = $WslVhdConfig[$key]
    }

    $config['ConfigPath'] = $resolvedConfigPath
    $config['ProjectRoot'] = Get-WslVhdProjectRoot

    return $config
}

function Get-WslVhdConfigValue {
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Config,

        [Parameter(Mandatory = $true)]
        [string]$Name,

        $Default = $null
    )

    if ($Config.ContainsKey($Name) -and $null -ne $Config[$Name]) {
        return $Config[$Name]
    }

    return $Default
}

function Test-WslVhdAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Write-WslVhdTerminal {
    param(
        [ValidateSet('INFO', 'OK', 'WARN', 'ERROR', 'RUN')]
        [string]$Level = 'INFO',

        [Parameter(Mandatory = $true)]
        [string]$Message
    )

    $colors = @{
        INFO = 'Cyan'
        OK = 'Green'
        WARN = 'Yellow'
        ERROR = 'Red'
        RUN = 'DarkCyan'
    }

    $line = "[$Level] $Message"
    if ($colors.ContainsKey($Level)) {
        Write-Host $line -ForegroundColor $colors[$Level]
    }
    else {
        Write-Host $line
    }
}

function Write-WslVhdSection {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Title
    )

    Write-Host ""
    Write-WslVhdTerminal -Level INFO -Message "== $Title =="
}

function Join-WslVhdCommandLine {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$ArgumentList
    )

    $quoted = foreach ($arg in $ArgumentList) {
        if ($arg -match '[\s"]') {
            '"' + ($arg -replace '"', '\"') + '"'
        }
        else {
            $arg
        }
    }

    return ($quoted -join ' ')
}

function Invoke-WslVhdSelfElevation {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ScriptPath,

        [string[]]$ArgumentList = @(),

        [switch]$ThrowOnFailure
    )

    $powershell = (Get-Command powershell.exe -ErrorAction Stop).Source
    $args = @(
        '-NoProfile',
        '-ExecutionPolicy', 'Bypass',
        '-File', $ScriptPath
    ) + $ArgumentList

    try {
        $process = Start-Process -FilePath $powershell `
            -ArgumentList (Join-WslVhdCommandLine -ArgumentList $args) `
            -Verb RunAs `
            -PassThru `
            -Wait
    }
    catch {
        if ($ThrowOnFailure) {
            throw
        }

        Write-WslVhdTerminal -Level ERROR -Message "Falha ao abrir permissao de Administrador/UAC: $($_.Exception.Message)"
        exit 1
    }

    exit $process.ExitCode
}

function Start-WslVhdLog {
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Config,

        [string]$Name = 'wsl-vhd-automount.log'
    )

    $projectRoot = [string]$Config['ProjectRoot']
    $logDirectoryValue = [string](Get-WslVhdConfigValue -Config $Config -Name 'LogDirectory' -Default '.\logs')
    $logDirectory = Resolve-WslVhdPath -Path $logDirectoryValue -BasePath $projectRoot

    New-Item -ItemType Directory -Force -Path $logDirectory | Out-Null

    $logPath = Join-Path -Path $logDirectory -ChildPath $Name
    Start-Transcript -Path $logPath -Append | Out-Null

    return $logPath
}

function Invoke-WslVhdNativeCommand {
    param(
        [Parameter(Mandatory = $true)]
        [string]$FilePath,

        [string[]]$ArgumentList = @(),

        [switch]$IgnoreExitCode
    )

    Write-WslVhdTerminal -Level RUN -Message "$FilePath $($ArgumentList -join ' ')"
    $rawOutput = & $FilePath @ArgumentList 2>&1
    $exitCode = $LASTEXITCODE
    $output = foreach ($line in $rawOutput) {
        if ($line -is [System.Management.Automation.ErrorRecord]) {
            $text = $line.Exception.Message
        }
        else {
            $text = [string]$line
        }

        $text -replace "`0", ''
    }

    if ($null -ne $output) {
        $output | Where-Object { $_ -ne '' } | ForEach-Object { Write-Host $_ }
    }

    if (-not $IgnoreExitCode -and $exitCode -ne 0) {
        throw "$FilePath saiu com codigo $exitCode."
    }

    return [pscustomobject]@{
        ExitCode = $exitCode
        Output = ($output -join [Environment]::NewLine)
    }
}

function Get-WslVhdDisk {
    param(
        [Parameter(Mandatory = $true)]
        [string]$VhdPath,

        [int]$TimeoutSeconds = 20
    )

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)

    do {
        $image = Get-DiskImage -ImagePath $VhdPath -ErrorAction Stop

        if ($image.Attached) {
            try {
                $disk = $image | Get-Disk -ErrorAction Stop | Select-Object -First 1
                if ($null -ne $disk) {
                    return $disk
                }
            }
            catch {
                Start-Sleep -Milliseconds 500
            }
        }
        else {
            Start-Sleep -Milliseconds 500
        }
    } while ((Get-Date) -lt $deadline)

    throw "Nao foi possivel descobrir o disco fisico anexado ao VHD: $VhdPath"
}

function Get-WslVhdDiskPath {
    param(
        [Parameter(Mandatory = $true)]
        $Disk
    )

    return "\\.\PHYSICALDRIVE$($Disk.Number)"
}

function Test-WslVhdMountAvailable {
    param(
        [Parameter(Mandatory = $true)]
        [string]$MountName,

        [string]$DistroName = ''
    )

    $wslPath = "/mnt/wsl/$MountName"
    $probe = "grep -Fqs ' $wslPath ' /proc/mounts"
    $args = @()

    if (-not [string]::IsNullOrWhiteSpace($DistroName)) {
        $args += @('-d', $DistroName)
    }

    $args += @('--exec', 'sh', '-lc', $probe)

    & wsl.exe @args *> $null
    return ($LASTEXITCODE -eq 0)
}

function Assert-WslVhdMountName {
    param(
        [Parameter(Mandatory = $true)]
        [string]$MountName
    )

    if ($MountName -notmatch '^[A-Za-z0-9_.-]+$') {
        throw "MountName invalido: '$MountName'. Use apenas letras, numeros, ponto, hifen e underscore."
    }
}
