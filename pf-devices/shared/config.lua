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

-- Apps that open a resource's own screen (the MDTs keep their full-screen UI). Each is registered
-- while one of its resources is started; the server checks the access rule before firing the event.
Config.Launchers = {
    {
        id = 'policemdt', name = 'Police MDT', icon = '🚓', category = 'jobs', order = 8,
        resources = { 'pf-policemdt', 'pf-policemdt-DEV' },
        launch = { event = 'pf-policemdt:client:TriggerMainOpen' },
        access = { jobs = { police = 0, sheriff = 0, bcso = 0 } },
        description = 'Records, warrants, reports and dispatch',
    },
    {
        id = 'emsmdt', name = 'EMS MDT', icon = '🚑', category = 'jobs', order = 9,
        resources = { 'pf-emsmdt' },
        launch = { event = 'pf_emsmdt:client:TriggerMainOpen' },
        access = { jobs = { ambulance = 0, ems = 0, fire = 0 } },
        description = 'Patients, reports and dispatch',
    },
}

Config.Debug = false
