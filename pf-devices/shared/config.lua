Config = Config or {}

-- The devices that can host platform apps. A shell registers itself under one of these names.
Config.Devices = {
    tablet   = { label = 'Tablet' },
    computer = { label = 'Computer' },
}

-- RPC calls a player may make per second (token bucket: `burst` tokens, refilled at `perSecond`).
Config.Rpc = {
    perSecond = 15,
    burst = 40,
    maxPayloadBytes = 32 * 1024,
}

-- Categories shown by the shells, in this order.
Config.Categories = {
    { id = 'system',     label = 'System' },
    { id = 'jobs',       label = 'Jobs' },
    { id = 'business',   label = 'Business' },
    { id = 'government', label = 'Government' },
    { id = 'media',      label = 'Media' },
    { id = 'apps',       label = 'Apps' },
}

Config.Debug = false
