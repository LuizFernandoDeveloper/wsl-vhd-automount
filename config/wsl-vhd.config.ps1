$WslVhdConfig = @{
    # Relative paths are resolved from this config-wsl project folder.
    VhdPath = '..\WSL_Drives.vhdx'

    # WSL will expose the disk at /mnt/wsl/<MountName>.
    MountName = 'media-removivel'
    FileSystem = 'ext4'

    # Leave empty to mount the whole disk. Use 1, 2, ... when the VHD has a partition table.
    Partition = $null

    # Optional filesystem-specific mount options passed to wsl --mount --options.
    MountOptions = ''

    # Optional distro to wake after mounting. Leave empty to use only the WSL mount.
    DistroName = ''
    StartDistro = $false

    # Fast path: let WSL mount the VHDX directly instead of attaching it first in Hyper-V.
    # Set to false only if an older WSL build needs the Mount-VHD + PhysicalDrive flow.
    PreferDirectVhdMount = $true

    # Start the WSL service before mounting so WSL is awake as early as possible.
    WarmWslService = $true

    LogDirectory = '.\logs'
    TaskName = 'WSL VHD Automount'

    # Run immediately at logon. Retries handle the small BitLocker/drive unlock race.
    StartupInitialDelaySeconds = 0
    StartupRetryMinutes = 10
    StartupRetryIntervalSeconds = 3

    # Task Scheduler priority: 0 is highest, 7 is the Windows background default.
    TaskPriority = 4
}
