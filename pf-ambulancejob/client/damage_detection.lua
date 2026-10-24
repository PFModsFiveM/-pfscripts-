-- Damage Detection: records the injuries this player receives and reports them to the server
-- (the server checks the values against the config and rate-limits them).
-- The weapon comes from the game's damage event (it was the victim's own selected weapon before) and
-- the bone from GetPedLastDamageBone's second return value; reports were never sent before.

local damageHistory = {}
local previousHealth = nil
local lastReportAt = 0

local function trackHealth()
    previousHealth = GetEntityHealth(PlayerPedId())
end

CreateThread(function()
    while true do
        if Config.DamageTracking.Enabled then trackHealth() end
        Wait(Config.DamageTracking.UpdateInterval or 250)
    end
end)

local function recordDamage(weaponHash)
    local ped = PlayerPedId()
    local current = GetEntityHealth(ped)
    local damage = (previousHealth or current) - current
    previousHealth = current
    if damage < (Config.DamageTracking.MinDamage or 5) then return end

    local _, bone = GetPedLastDamageBone(ped)
    local part = PFAmbulance.BodyPartForBone(bone)
    local entry = {
        timestamp = GetGameTimer(),
        damageTaken = damage,
        weapon = weaponHash,
        injuryType = PFAmbulance.InjuryTypeForWeapon(weaponHash),
        severity = PFAmbulance.SeverityForDamage(damage),
        bodyZone = part.zone,
        bodyPartName = part.name,
        healthAtTime = current,
    }
    damageHistory[#damageHistory + 1] = entry
    if #damageHistory > 100 then table.remove(damageHistory, 1) end

    local now = GetGameTimer()
    if now - lastReportAt < (Config.DamageTracking.ReportCooldown or 2000) then return end
    lastReportAt = now
    local weaponData = QBCore and QBCore.Shared and QBCore.Shared.Weapons and QBCore.Shared.Weapons[weaponHash]
    TriggerServerEvent('pf-ambulancejob:server:processDamage', {
        injuryType = entry.injuryType,
        severity = entry.severity,
        bodyZone = entry.bodyZone,
        health = math.max(0, math.min(100, current - 100)),
        weapon = weaponData and weaponData.label or 'Unknown',
    })
    PFAmbulance.DebugPrint(('Damage %d, %s, %s'):format(damage, entry.injuryType, entry.bodyZone))
end

AddEventHandler('gameEventTriggered', function(event, data)
    if event ~= 'CEventNetworkEntityDamage' or not Config.DamageTracking.Enabled then return end
    if data[1] ~= PlayerPedId() then return end
    recordDamage(data[7])
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

AddEventHandler('playerSpawned', trackHealth)
