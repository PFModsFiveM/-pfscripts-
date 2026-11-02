local QBCore = exports['pfm-core']:GetCoreObject()

-- Cosmetic preview: an on-duty mechanic driving a car opens a session for it; the server keeps the
-- car's look as it was at the start (the snapshot, cosmetic parts only). While the session is open
-- the mechanic's preview changes are shown to every player, for cosmetic mod types only; ending the
-- session (or walking away) puts the stored look back. Nothing is saved. Any player within 30 m used
-- to be able to send any mod type (engine, armour...) or any "snapshot" to every client, so a
-- passer-by could strip another player's paid upgrades.
local REACH = 8.0
local MOD_TYPES = { [0] = true, [1] = true, [2] = true, [3] = true, [4] = true, [6] = true, [7] = true,
    [8] = true, [9] = true, [10] = true, [23] = true, [48] = true }
local PAINT_SLOTS = { primary = true, secondary = true, pearl = true, wheel = true }
local MOD_INDEX_MAX, COLOR_MAX, TINT_MAX, WHEEL_TYPE_MAX = 255, 242, 6, 12

local Sessions = {}   -- [src] = { veh, netId, snapshot }

local function int(v, lo, hi)
    v = tonumber(v)
    if not v or v ~= math.floor(v) or v < lo or v > hi then return nil end
    return v
end

local function rgb(c)
    if type(c) ~= 'table' then return nil end
    local r, g, b = int(c.r, 0, 255), int(c.g, 0, 255), int(c.b, 0, 255)
    if not r or not g or not b then return nil end
    return { r = r, g = g, b = b }
end

-- Only the parts the preview changes, each from a fixed range (client/preview.lua applySnapshot).
local function cleanSnapshot(snap)
    if type(snap) ~= 'table' then return nil end
    local out = { mods = {}, colors = { classic = {} } }
    for k, v in pairs(type(snap.mods) == 'table' and snap.mods or {}) do
        local m = int(k, 0, 99)
        local idx = int(v, -1, MOD_INDEX_MAX)
        if m and MOD_TYPES[m] and idx then out.mods[m] = idx end
    end
    out.wheelType = int(snap.wheelType, -1, WHEEL_TYPE_MAX)
    out.windowTint = int(snap.windowTint, -1, TINT_MAX)
    local colors = type(snap.colors) == 'table' and snap.colors or {}
    local classic = type(colors.classic) == 'table' and colors.classic or {}
    for _, key in ipairs({ 'primary', 'secondary', 'pearl', 'wheel' }) do
        out.colors.classic[key] = int(classic[key], 0, COLOR_MAX) or 0
    end
    out.colors.customPrimary = rgb(colors.customPrimary)
    out.colors.customSecondary = rgb(colors.customSecondary)
    return out
end

local function carOf(netId)
    netId = tonumber(netId)
    if not netId or netId <= 0 then return nil end
    local veh = NetworkGetEntityFromNetworkId(netId)
    if not veh or veh == 0 or not DoesEntityExist(veh) then return nil end
    return veh
end

local function endSession(src, restore)
    local s = Sessions[src]
    Sessions[src] = nil
    if s and restore and DoesEntityExist(s.veh) then
        TriggerClientEvent('pf_mech:preview:restoreSnapshotClient', -1, s.netId, s.snapshot)
    end
end

-- The open session for this car, while the mechanic is still at it; a session left behind is ended
-- and the car's look put back.
local function sessionFor(src, netId)
    local s = Sessions[src]
    if not s or carOf(netId) ~= s.veh then return nil end
    if #(GetEntityCoords(GetPlayerPed(src)) - GetEntityCoords(s.veh)) > REACH then
        endSession(src, true)
        return nil
    end
    return s
end

RegisterNetEvent('pf_mech:preview:begin', function(netId, snapshot)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    local job = Player and Player.PlayerData.job
    if not job or not Config.IsMechanicJob(job.name) or job.onduty ~= true then return end
    local veh = carOf(netId)
    if not veh or GetPedInVehicleSeat(veh, -1) ~= GetPlayerPed(src) then return end
    local snap = cleanSnapshot(snapshot)
    if not snap then return end
    if Sessions[src] and Sessions[src].veh ~= veh then endSession(src, true) end
    Sessions[src] = Sessions[src] or { veh = veh, netId = tonumber(netId), snapshot = snap }
end)

-- Broadcast preview changes so everyone sees them, never persisted
RegisterNetEvent('pf_mech:preview:syncMod', function(netId, modType, index)
    local src = source
    modType, index = int(modType, 0, 99), int(index, -1, MOD_INDEX_MAX)
    if not modType or not MOD_TYPES[modType] or not index then return end
    local s = sessionFor(src, netId)
    if not s then return end
    TriggerClientEvent('pf_mech:preview:applyModClient', -1, s.netId, modType, index)
end)

RegisterNetEvent('pf_mech:preview:syncTint', function(netId, tint)
    local src = source
    tint = int(tint, 0, TINT_MAX)
    if not tint then return end
    local s = sessionFor(src, netId)
    if not s then return end
    TriggerClientEvent('pf_mech:preview:applyTintClient', -1, s.netId, tint)
end)

-- which: 'primary' | 'secondary' | 'pearl' | 'wheel'
RegisterNetEvent('pf_mech:preview:syncPaint', function(netId, which, index)
    local src = source
    index = int(index, 0, COLOR_MAX)
    if not PAINT_SLOTS[which] or not index then return end
    local s = sessionFor(src, netId)
    if not s then return end
    TriggerClientEvent('pf_mech:preview:applyPaintClient', -1, s.netId, which, index)
end)

-- Ends the session: every viewer gets the look stored when it began (never a client's snapshot).
RegisterNetEvent('pf_mech:preview:restore', function(netId)
    local src = source
    local s = Sessions[src]
    if not s or carOf(netId) ~= s.veh then return end
    endSession(src, true)
end)

AddEventHandler('playerDropped', function()
    endSession(source, true)
end)
