-- Damage hints: when this player's ped takes damage, the client tells the server what only it can
-- see (the bone that was hit, the weapon, the attacking player, its own health and armour, a
-- fall's speed, the vehicle's speeds and seatbelt, water, fire: client/medical_hints.lua). The
-- server decides the injuries from what it observed itself (health and armour drops, the
-- attacker's weaponDamageEvent, its own velocity samples); these values are only a capped hint
-- (server/medical/ingest.lua). The old self-report (pf-ambulancejob:server:processDamage) and its
-- 250 ms health loop are gone.

local damageHistory = {}
local seq = 0
local lastHealth, lastArmour
local lastSentAt = 0

local function snapshot()
    local ped = PlayerPedId()
    lastHealth, lastArmour = GetEntityHealth(ped), GetPedArmour(ped)
end

local function attackerId(entity)
    if not entity or entity == 0 or not DoesEntityExist(entity) or not IsEntityAPed(entity) or not IsPedAPlayer(entity) then return nil end
    local index = NetworkGetPlayerIndexFromPed(entity)
    local id = index and index ~= -1 and GetPlayerServerId(index) or nil
    return id and id > 0 and id or nil
end

local function onDamage(data)
    local ped = PlayerPedId()
    local hp, ar = GetEntityHealth(ped), GetPedArmour(ped)
    local _, bone = GetPedLastDamageBone(ped)
    local weapon = data[7]
    local entry = { timestamp = GetGameTimer(), weapon = weapon, bone = bone, healthBefore = lastHealth, healthAt = hp }
    damageHistory[#damageHistory + 1] = entry
    if #damageHistory > 50 then table.remove(damageHistory, 1) end

    -- the server accepts 10 hints per second; several hits in one moment (pellets) share one
    local now = GetGameTimer()
    if now - lastSentAt >= 120 then
        lastSentAt = now
        seq = (seq + 1) % 2147483647
        local hint = PFMedHints and PFMedHints.Snapshot() or {}
        hint.seq = seq
        hint.weapon = weapon
        hint.bone = tonumber(bone) or 0
        hint.hpBefore, hint.hpAfter = lastHealth or hp, hp
        hint.armourBefore, hint.armourAfter = lastArmour or ar, ar
        hint.attacker = attackerId(data[2])
        TriggerServerEvent('pf-ambulancejob:server:DamageHint', hint)
    end
    lastHealth, lastArmour = hp, ar
end

AddEventHandler('gameEventTriggered', function(event, data)
    if event ~= 'CEventNetworkEntityDamage' or not Config.DamageTracking.Enabled then return end
    if data[1] ~= PlayerPedId() then return end
    onDamage(data)
end)

function GetDamageHistory() return damageHistory end
function ClearDamageHistory() damageHistory = {} end
function GetRecentDamage(timeWindow)
    timeWindow = timeWindow or 60000
    local now, recent = GetGameTimer(), {}
    for _, d in ipairs(damageHistory) do
        if now - d.timestamp < timeWindow then recent[#recent + 1] = d end
    end
    return recent
end

AddEventHandler('playerSpawned', snapshot)
