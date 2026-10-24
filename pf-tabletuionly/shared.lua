-- Configuration
Config = Config or {}

-- Mechanic job names (case-insensitive)
Config.MechanicJobs = {
    'mechanic',
    'mechanic2',
    'mechanic3',
    'bennys',
    'beeker'
}

-- Job-specific apps
Config.JobApps = {
    mechanic = {'work-orders', 'cash-register'},
    mechanic2 = {'work-orders', 'cash-register'},
    mechanic3 = {'work-orders', 'cash-register'},
    bennys = {'work-orders', 'cash-register'},
    beeker = {'work-orders', 'cash-register'},
    garbage = {'garbage-job'},
    taxi = {'taxi-job'},
    bus = {'bus-job'},
    gruppe6 = {'gruppe6-job'},
}
