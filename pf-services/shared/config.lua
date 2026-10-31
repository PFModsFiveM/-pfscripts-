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

-- Police and EMS work their dispatch in their MDT (an app on the tablet and the computer too):
-- requests of these kinds become calls on that MDT's dispatch board, and these jobs do not get
-- the separate Dispatch app while their MDT runs.
Config.MdtDispatch = {
    ['police.assist'] = { resources = { 'pf-policemdt', 'pf-policemdt-DEV' }, priority = 2, code = '911' },
    ['ems.patient']   = { resources = { 'pf-emsmdt' }, priority = 1, code = 'EMS' },
}
Config.MdtJobs = {
    police = { 'pf-policemdt', 'pf-policemdt-DEV' }, sheriff = { 'pf-policemdt', 'pf-policemdt-DEV' }, bcso = { 'pf-policemdt', 'pf-policemdt-DEV' },
    ambulance = { 'pf-emsmdt' }, ems = { 'pf-emsmdt' }, fire = { 'pf-emsmdt' },
}

Config.Debug = false
