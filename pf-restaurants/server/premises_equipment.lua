-- Registers and cooking stations a restaurant bought as premises equipment (pf-government).
-- They are added to Config.Registers / Config.Stations and RestaurantData.stations like the
-- configured ones, so the POS range check, cooking sessions and cleaning all work at them.
-- Ids start with 'prem_' so they can be replaced when the equipment changes.

PremisesEquipment = PremisesEquipment or {}
local PE = PremisesEquipment

local applied = {}      -- [businessId] = { registers = {...}, stations = {...} } (what clients get)
local templates = nil   -- [stationType] = first configured station of that type

local function isPremisesId(id) return type(id) == 'string' and id:sub(1, 5) == 'prem_' end

local function buildTemplates()
    if templates then return end
    templates = {}
    for _, stations in pairs(Config.Stations or {}) do
        for _, st in ipairs(stations) do
            if not isPremisesId(st.stationId) and st.type and not templates[st.type] then templates[st.type] = st end
        end
    end
end

local function stripPremises(list)
    local out = {}
    for _, e in ipairs(list or {}) do
        if not isPremisesId(e.registerId or e.stationId) then out[#out + 1] = e end
    end
    return out
end

local function installed(businessId)
    if GetResourceState('pf-government') ~= 'started' then return {} end
    local ok, list = pcall(function() return exports['pf-government']:GetInstalledEquipment('restaurant:' .. businessId) end)
    return ok and type(list) == 'table' and list or {}
end

--- Rebuilds one restaurant's equipment-backed registers and stations and tells the clients.
function PE.Refresh(businessId)
    if not Config.Restaurants[businessId] then return end
    buildTemplates()
    Config.Registers = Config.Registers or {}
    Config.Stations = Config.Stations or {}
    local registers = stripPremises(Config.Registers[businessId])
    local stations = stripPremises(Config.Stations[businessId])
    local sendRegisters, sendStations = {}, {}

    -- forget stations that went away (keep sessions of ones still installed)
    RestaurantData.stations[businessId] = RestaurantData.stations[businessId] or {}
    RestaurantData.equipment[businessId] = RestaurantData.equipment[businessId] or {}
    local keep = {}

    for _, eq in ipairs(installed(businessId)) do
        local c = eq.coords
        if type(c) == 'table' and c.x then
            local coords = vector3(c.x + 0.0, c.y + 0.0, c.z + 0.0)
            if eq.slotType == 'register' then
                local reg = { registerId = 'prem_reg_' .. eq.slotId, coords = coords, heading = eq.heading or 0.0, model = eq.model }
                registers[#registers + 1] = reg
                sendRegisters[#sendRegisters + 1] = { registerId = reg.registerId, coords = c, heading = reg.heading }
            elseif eq.slotType == 'cooking_station' and type(eq.station) == 'table' then
                local tpl = templates[eq.station.type]
                if tpl then
                    local id = 'prem_st_' .. eq.slotId
                    local st = {
                        stationId = id, type = tpl.type, label = eq.label or tpl.label, coords = coords,
                        heading = eq.heading or 0.0, slots = tpl.slots, propModel = tpl.propModel,
                        propOffsets = tpl.propOffsets, interaction = tpl.interaction,
                    }
                    stations[#stations + 1] = st
                    keep[id] = true
                    if not RestaurantData.stations[businessId][id] then
                        local slots = {}
                        for i = 1, tonumber(tpl.slots) or 1 do slots[i] = { slotId = i, occupied = false, session = nil } end
                        RestaurantData.stations[businessId][id] = { stationId = id, type = tpl.type, coords = coords, slots = slots, sessions = {} }
                        RestaurantData.equipment[businessId][id] = RestaurantData.equipment[businessId][id] or {
                            cleanliness = 100, condition = 100, oilQuality = 100, iceLevel = 100, burntCount = 0, lastCleaned = os.time(),
                        }
                    end
                    sendStations[#sendStations + 1] = { stationId = id, type = tpl.type, label = st.label, coords = c, heading = st.heading }
                else
                    print(('^3[pf-restaurants]^7 no configured %s station to copy for premises equipment in %s'):format(tostring(eq.station.type), businessId))
                end
            end
        end
    end

    for id, station in pairs(RestaurantData.stations[businessId]) do
        if isPremisesId(id) and not keep[id] and not next(station.sessions or {}) then
            RestaurantData.stations[businessId][id] = nil
        end
    end

    Config.Registers[businessId] = registers
    Config.Stations[businessId] = stations
    applied[businessId] = { registers = sendRegisters, stations = sendStations }
    TriggerClientEvent('pf-restaurants:client:premisesEquipment', -1, businessId, applied[businessId])
end

function PE.RefreshAll()
    for businessId in pairs(Config.Restaurants or {}) do PE.Refresh(businessId) end
end

AddEventHandler('pf-government:server:equipmentChanged', function(govBusinessId)
    local businessId = type(govBusinessId) == 'string' and govBusinessId:match('^restaurant:(.+)$')
    if businessId then PE.Refresh(businessId) end
end)

AddEventHandler('onResourceStart', function(name)
    if name == 'pf-government' then SetTimeout(5000, PE.RefreshAll) end
end)

CreateThread(function()
    Wait(5000)   -- stations from config are loaded by main.lua first
    PE.RefreshAll()
end)

-- A client that joins later asks for what is installed.
local lastRequest = {}
RegisterNetEvent('pf-restaurants:server:requestPremisesEquipment', function()
    local src = source
    local now = GetGameTimer()
    if lastRequest[src] and now - lastRequest[src] < 10000 then return end
    lastRequest[src] = now
    for businessId, data in pairs(applied) do
        TriggerClientEvent('pf-restaurants:client:premisesEquipment', src, businessId, data)
    end
end)

AddEventHandler('playerDropped', function() lastRequest[source] = nil end)
