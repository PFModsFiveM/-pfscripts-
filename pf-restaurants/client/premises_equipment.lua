-- Targets for registers and cooking stations bought as premises equipment.
-- The server sends what is installed; ids start with 'prem_'.

local zones = {}        -- [businessId] = { { kind = 'pfm' | 'ox', id = name or ox id } }
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

local function strip(list)
    local out = {}
    for _, e in ipairs(list or {}) do
        if not isPremisesId(e.registerId or e.stationId) then out[#out + 1] = e end
    end
    return out
end

local function clearZones(businessId)
    for _, z in ipairs(zones[businessId] or {}) do
        pcall(function()
            if z.kind == 'pfm' then exports['pfm-target']:RemoveZone(z.id) else exports.ox_target:removeZone(z.id) end
        end)
    end
    zones[businessId] = {}
end

local function addRegisterTarget(businessId, reg)
    local option = {
        type = 'client', event = 'pf-restaurants:client:openPOS', icon = 'fas fa-cash-register',
        label = 'Open Register', businessId = businessId, registerId = reg.registerId,
    }
    if Config.TargetScript == 'qb-target' then
        local name = 'restaurant_register_' .. reg.registerId
        exports['pfm-target']:AddBoxZone(name, reg.coords, 0.6, 0.6, {
            name = name, heading = reg.heading, debugPoly = Config.Debug,
            minZ = reg.coords.z - 0.5, maxZ = reg.coords.z + 0.5,
        }, { options = { option }, distance = 1.5 })
        table.insert(zones[businessId], { kind = 'pfm', id = name })
    elseif Config.TargetScript == 'ox_target' then
        option.name = 'restaurant_register_' .. reg.registerId
        local id = exports.ox_target:addBoxZone({ coords = reg.coords, size = vec3(0.6, 0.6, 0.6), rotation = reg.heading, debug = Config.Debug, options = { option } })
        table.insert(zones[businessId], { kind = 'ox', id = id })
    end
end

local function addStationTarget(businessId, st)
    if Config.TargetScript == 'qb-target' then
        local name = 'restaurant_station_' .. st.stationId
        exports['pfm-target']:AddBoxZone(name, st.coords, 1.5, 1.5, {
            name = name, heading = st.heading, debugPoly = Config.Debug,
            minZ = st.coords.z - 1.0, maxZ = st.coords.z + 1.0,
        }, { options = BuildStationOptions(businessId, st), distance = st.interaction.distance or 2.0 })
        table.insert(zones[businessId], { kind = 'pfm', id = name })
    elseif Config.TargetScript == 'ox_target' then
        local id = exports.ox_target:addBoxZone({ coords = st.coords, size = vec3(1.5, 1.5, 1.5), rotation = st.heading, debug = Config.Debug, options = BuildStationOptions(businessId, st) })
        table.insert(zones[businessId], { kind = 'ox', id = id })
    end
end

RegisterNetEvent('pf-restaurants:client:premisesEquipment', function(businessId, data)
    if type(businessId) ~= 'string' or type(data) ~= 'table' then return end
    buildTemplates()
    clearZones(businessId)
    Config.Registers = Config.Registers or {}
    Config.Stations = Config.Stations or {}
    local registers = strip(Config.Registers[businessId])
    local stations = strip(Config.Stations[businessId])

    for _, r in ipairs(data.registers or {}) do
        local reg = { registerId = r.registerId, coords = vector3(r.coords.x, r.coords.y, r.coords.z), heading = r.heading or 0.0 }
        registers[#registers + 1] = reg
        if Config.UseTarget then addRegisterTarget(businessId, reg) end
    end
    for _, s in ipairs(data.stations or {}) do
        local tpl = templates[s.type]
        if tpl then
            local st = {
                stationId = s.stationId, type = s.type, label = s.label, coords = vector3(s.coords.x, s.coords.y, s.coords.z),
                heading = s.heading or 0.0, slots = tpl.slots, propModel = tpl.propModel, propOffsets = tpl.propOffsets,
                interaction = tpl.interaction,
            }
            stations[#stations + 1] = st
            if Config.UseTarget then addStationTarget(businessId, st) end
        end
    end
    Config.Registers[businessId] = registers
    Config.Stations[businessId] = stations
end)

CreateThread(function()
    Wait(3000)
    TriggerServerEvent('pf-restaurants:server:requestPremisesEquipment')
end)

AddEventHandler('onResourceStop', function(name)
    if name ~= GetCurrentResourceName() then return end
    for businessId in pairs(zones) do clearZones(businessId) end
end)
