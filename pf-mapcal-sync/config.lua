Config = {}

-- JSON output consumed by AMBWeb tools.
Config.OutputFilePath = 'F:/AMBWeb/data/fivem-live-coords.json'
Config.SyncFilePath = 'F:/AMBWeb/data/mapcal-sync.json'
Config.SyncResourceFile = 'mapcal-sync.json'
Config.SyncWaitSeconds = 180

-- ACE permission required to use commands below.
Config.RequiredAce = 'mapcal.admin'

-- Optional whitelist if you prefer IDs over ACE.
-- Example: Config.IdentifierAllowlist = { ['license:abc123'] = true }
Config.IdentifierAllowlist = {}

-- Command names.
Config.Commands = {
    Add = 'mapcal_add',
    Sync = 'mapcal_sync',
    SyncLocation = 'mapcal_synclocation',
    Remove = 'mapcal_remove',
    List = 'mapcal_list',
    Clear = 'mapcal_clear',
    Export = 'mapcal_export'
}
