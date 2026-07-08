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

    # Keep this false for maximum compatibility with the old Mount-VHD flow.
    # If you want to try direct WSL VHD mounting, set this to true.
    PreferDirectVhdMount = $false

    LogDirectory = '.\logs'
    TaskName = 'WSL VHD Automount'

    # BitLocker/removable disks can take a moment to unlock after logon.
    StartupInitialDelaySeconds = 20
    StartupRetryMinutes = 10
    StartupRetryIntervalSeconds = 15
}
