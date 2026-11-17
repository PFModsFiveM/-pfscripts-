-- EMS equipment (server/ems/equipment.lua, client/ems_equipment.lua): stretchers, wheelchairs and
-- medbags. Every prop is spawned by the server; every distance below is checked against server
-- positions. Shared file: the client reads the models, offsets and animations.
Config = Config or {}
Config.EMS = Config.EMS or {}
local E = Config.EMS

-- Jobs that may use the equipment (they must also be on duty). Defaults to Config.AllowedJobs.
E.Jobs = E.Jobs or Config.AllowedJobs or { ambulance = true }

E.RatePerSecond = 2            -- equipment actions per player per second (architecture 6.3)
E.TouchRange = 2.5             -- medic to patient / medic to equipment / equipment to patient
E.RigRange = 4.0               -- medic and stretcher to the rig's rear doors (load, unload, spawn, return)
E.StockRange = 6.0             -- medic to the rig's rear doors for the medbag
E.MaxProps = 64                -- all equipment props on the server at once
E.TickSeconds = 1              -- safety pass (prop/rig gone, pusher walked off, patient out of the rig)

-- Ambulances ("rigs"): model name -> rear door offset along the vehicle's length (negative = behind
-- the centre), the rear seats a loaded patient is put in, and the height of a spawned prop relative
-- to the vehicle's origin.
E.Rigs = E.Rigs or {
    ambulance = { rear = -3.6, seats = { 1, 2 }, groundZ = -0.9 },
}

E.Stretchers = E.Stretchers or {
    Model = 'v_med_emptybed',  -- base-game hospital bed (the old bin-bag replacement model is retired)
    PerRig = 1,                -- one stretcher per rig
    AllowConscious = true,     -- a conscious patient can be placed; they can always get off themselves
    SpawnBehind = 1.2,         -- metres behind the rear doors
    PusherMaxDistance = 4.0,   -- a pusher further than this from the stretcher (server positions) stops pushing
    PatientMaxDistance = 3.0,  -- a patient further than this from their stretcher is released (detached)
    FarTicks = 2,              -- consecutive safety passes beyond those distances before acting
    -- client presentation
    PatientOffset = { x = 0.0, y = 0.0, z = 1.05, rx = 0.0, ry = 0.0, rz = 180.0 },
    PushOffset = { x = 0.0, y = 1.25, z = -0.95, rx = 0.0, ry = 0.0, rz = 180.0 },
    PatientAnim = { dict = 'anim@gangops@morgue@table@', name = 'body_search', flag = 1 },
    PushAnim = { dict = 'anim@heists@box_carry@', name = 'idle', flag = 50 },
}

E.Wheelchairs = E.Wheelchairs or {
    Model = 'prop_wheelchair_01',
    PerRig = 1,
    MaxPerMedic = 2,
    PointRange = 3.0,          -- a medic within this of a hospital point may take a wheelchair there
    Points = nil,              -- nil: the hospital reception desks (Config.Locations['checking'], which config_hospital.lua keeps up to date)
    PatientOffset = { x = 0.0, y = 0.05, z = 0.45, rx = 0.0, ry = 0.0, rz = 180.0 },
    PushOffset = { x = 0.0, y = 0.75, z = -0.45, rx = 0.0, ry = 0.0, rz = 180.0 },
    PatientAnim = { dict = 'missfinale_c2leadinoutfin_c_int', name = '_leadin_loop2_lester', flag = 1 },
    PushAnim = { dict = 'anim@heists@box_carry@', name = 'idle', flag = 50 },
}

E.Medbags = E.Medbags or {
    Model = 'xm_prop_x17_bag_med_01a',
    PerRig = 1,                -- the rig's bag; its contents are the stash pf_medbag_<plate> and stay with the rig
    Slots = 20,
    MaxWeight = 40000,
    Label = 'Medbag',
}
