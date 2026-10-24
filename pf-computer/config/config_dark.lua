Config = Config or {}

Config.Security = {
    Enabled = true,

    Default = {
        lockscreenEnabled = false,
        allowPassword = true,
        allowPin = true,
        allowFingerprint = true,
        lockdownOnHackFail = true,
        maxHackFailuresBeforeLockdown = 3,
        lockdownMinutes = 10,
        allowAdminRecovery = true
    },

    AdminRecoveryJobs = {
        'police',
        'sheriff',
        'government',
        'mayor'
    },

    AdminAce = 'pf-computer.admin'
}
