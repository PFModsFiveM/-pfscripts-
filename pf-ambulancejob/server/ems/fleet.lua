-- Rig fleet maintenance (batch 20C; integration matrix "DEP / fleet").
--
-- A worn ambulance is sent to a mechanic without anyone filling in a form: every CheckSeconds the
-- server reads the health of each rig on the map (server natives GetVehicleBodyHealth /
-- GetVehicleEngineHealth, never a client value) and, for one below DueBody / DueEngine, asks
-- pf-government for fleet service (export RequestFleetService). pf-government checks the plate is an
-- ambulance fleet vehicle (pf-jobgarages), marks it due, and posts the pf-services request
-- 'mechanic.fleet' paid from society:ambulance; the mechanic's completion counts only when the server
-- reads the rig repaired next to them and pf-jobgarages records the service (SetServiceState 'ok').
-- A medic can also report a rig by hand with pf-government's /fleetservice.
-- One ask per plate per RequestCooldown: pf-government keeps one open request per vehicle anyway.

PFEms = PFEms or {}
PFEms.Fleet = PFEms.Fleet or {}
local Fl = PFEms.Fleet

Fl.DEFAULTS = {
    Enabled = true,
    CheckSeconds = 60,
    DueBody = 850,          -- the same thresholds pf-government applies (Config.Procurement.Fleet)
    DueEngine = 850,
    RequestCooldown = 600,  -- seconds between two asks for one plate
}
function Fl.Cfg()
    local over = (Config.EMS or {}).Fleet
    if type(over) ~= 'table' then return Fl.DEFAULTS end
    local out = {}
    for k, v in pairs(Fl.DEFAULTS) do out[k] = v end
    for k, v in pairs(over) do out[k] = v end
    return out
end
local cfg = Fl.Cfg

Fl.asked = Fl.asked or {} -- [plate] = os.time() of the last ask

local function started(res)
    local ok, state = pcall(GetResourceState, res)
    return ok and state == 'started'
end

local function h32(v)
    v = math.tointeger(tonumber(v) or 0) or 0
    return v & 0xFFFFFFFF
end
local function rigModels()
    local set = {}
    for name in pairs((Config.EMS or {}).Rigs or {}) do set[h32(GetHashKey(name))] = true end
    return set
end

-- pf-jobgarages' plate form: upper case, trimmed, at most 8 characters
local function normPlate(plate)
    if type(plate) ~= 'string' then return '' end
    plate = plate:upper():gsub('^%s+', ''):gsub('%s+$', '')
    if #plate > 8 then return '' end
    return plate
end

--- One pass over the rigs on the map. Returns how many service asks were made.
function Fl.Tick(t)
    local c = cfg()
    if not c.Enabled or not started('pf-government') then return 0 end
    t = t or os.time()
    local models, asked = rigModels(), 0
    for _, veh in ipairs(GetAllVehicles() or {}) do
        if DoesEntityExist(veh) and models[h32(GetEntityModel(veh))] then
            local plate = normPlate(GetVehicleNumberPlateText(veh))
            local body = tonumber(GetVehicleBodyHealth(veh)) or 1000
            local engine = tonumber(GetVehicleEngineHealth(veh)) or 1000
            local last = Fl.asked[plate]
            if plate ~= '' and (body < c.DueBody or engine < c.DueEngine) and (not last or t - last >= c.RequestCooldown) then
                Fl.asked[plate] = t
                local ok, res = pcall(function() return exports['pf-government']:RequestFleetService(plate, { reason = 'rig wear' }) end)
                if ok and type(res) == 'table' and res.ok and not res.existing then asked = asked + 1 end
            end
        end
    end
    -- forget plates that were not asked for in a long time (bounded memory)
    for plate, at in pairs(Fl.asked) do
        if t - at > 4 * c.RequestCooldown then Fl.asked[plate] = nil end
    end
    return asked
end

CreateThread(function()
    while true do
        Wait(math.max(15, tonumber(cfg().CheckSeconds) or 60) * 1000)
        local ok, err = pcall(Fl.Tick)
        if not ok then print('^1[pf-ambulancejob]^7 rig fleet check failed: ' .. tostring(err)) end
    end
end)
