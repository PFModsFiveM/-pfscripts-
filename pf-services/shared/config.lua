Config = Config or {}

Config.Events = {
    keepDays = 30,        -- timeline rows older than this are deleted at start-up
    dedupeSeconds = 120,  -- the same event (kind + dedupe key) inside this window is recorded once
}

Config.Requests = {
    maxActivePerWorker = 2,      -- requests one worker may hold at a time
    maxOpenPerCitizen = 2,       -- open requests one citizen may have made
    citizenCooldown = 60,        -- seconds between two requests from one citizen
    expireCheckSeconds = 30,     -- how often expired requests are swept
    acceptRange = nil,           -- optional: max distance (m) from the request to accept it
}

-- Jobs whose on-duty members see the Dispatch app even if no request kind targets them yet.
Config.DispatchJobs = { 'police', 'ambulance', 'mechanic', 'tow', 'taxi', 'government', 'reporter' }

Config.Debug = false
