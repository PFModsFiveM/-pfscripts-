-- Damage Detection System
-- Tracks player damage and identifies weapon/location

local lastDamageTime = 0
local damageHistory = {}
local previousHealth = 0
local lastWeapon = nil

-- Initialize health tracking
function InitializeDamageTracking()
    local ped = PlayerPedId()
    previousHealth = GetEntityHealth(ped)
    
    SetTimeout(1000, function()
        DamageDetectionTick()
    end)
end

-- Main damage detection loop
function DamageDetectionTick()
    local ped = PlayerPedId()
    local currentHealth = GetEntityHealth(ped)
    
    if currentHealth < previousHealth then
        local damageTaken = previousHealth - currentHealth
        local lastWeapon = GetSelectedPedWeapon(ped)
        
        DetectDamageSource(ped, damageTaken, lastWeapon)
        previousHealth = currentHealth
    else
        previousHealth = currentHealth
    end
    
    -- Continue tracking
    SetTimeout(Config.DamageTracking.UpdateInterval, DamageDetectionTick)
end

-- Detect damage source and location
function DetectDamageSource(ped, damageTaken, weaponHash)
    local currentTime = GetGameTimer()
    
    -- Get weapon info
    local weaponInfo = Config.WeaponInjuryTypes[weaponHash]
    if not weaponInfo then
        weaponInfo = {
            type = 'blunt_trauma',
            severity = DetermineSeverity(damageTaken)
        }
    end
    
    -- Detect body part hit (raycasting)
    local bodyPartHit = DetectBodyPartHit(ped)
    local bodyZone = bodyPartHit and bodyPartHit.zone or 'torso'
    
    -- Store damage event
    table.insert(damageHistory, {
        timestamp = currentTime,
        damageTaken = damageTaken,
        weapon = weaponHash,
        weaponLabel = GetWeaponLabel(weaponHash),
        injuryType = weaponInfo.type,
        severity = weaponInfo.severity,
        bodyZone = bodyZone,
        bodyPartName = bodyPartHit and bodyPartHit.name or 'Unknown',
        healthAtTime = GetEntityHealth(ped)
    })
    
    -- Clean old entries
    if #damageHistory > 100 then
        table.remove(damageHistory, 1)
    end
    
    PFAmbulance.DebugPrint("Damage detected: " .. tostring(damageTaken) .. " damage, Weapon: " .. GetWeaponLabel(weaponHash) .. ", Zone: " .. bodyZone)
end

-- Detect which body part was hit using raycasting
function DetectBodyPartHit(ped)
    local boneId = GetPedLastDamageBone(ped)
    
    -- Map bone to body zone
    for boneName, boneData in pairs(Config.BodyParts) do
        if tonumber(boneName) == boneId then
            return boneData
        end
    end
    
    -- Default to torso if unknown
    return { name = 'Torso', zone = 'torso', damage_multiplier = 1.0 }
end

-- Determine severity based on damage amount
function DetermineSeverity(damage)
    if damage > 40 then
        return 'critical'
    elseif damage > 25 then
        return 'severe'
    elseif damage > 10 then
        return 'moderate'
    else
        return 'minor'
    end
end

-- Get weapon label from hash
function GetWeaponLabel(weaponHash)
    local weapons = {
        [`weapon_pistol`] = "Pistol",
        [`weapon_combat_pistol`] = "Combat Pistol",
        [`weapon_appistol`] = "AP Pistol",
        [`weapon_carbinerifle`] = "Carbine Rifle",
        [`weapon_assaultrifle`] = "Assault Rifle",
        [`weapon_shotgun`] = "Shotgun",
        [`weapon_sniperrifle`] = "Sniper Rifle",
        [`weapon_knife`] = "Knife",
        [`weapon_nightstick`] = "Nightstick",
        [`weapon_bat`] = "Baseball Bat",
        [`weapon_crowbar`] = "Crowbar",
        [`weapon_fire`] = "Fire",
        [`weapon_fall`] = "Fall Damage",
        [`weapon_explosion`] = "Explosion"
    }
    
    return weapons[weaponHash] or "Unknown Weapon"
end

-- Get damage history
function GetDamageHistory()
    return damageHistory
end

-- Clear damage history
function ClearDamageHistory()
    damageHistory = {}
end

-- Get recent damage (within last X seconds)
function GetRecentDamage(timeWindow)
    timeWindow = timeWindow or 60000 -- 60 seconds default
    local currentTime = GetGameTimer()
    local recent = {}
    
    for _, damage in ipairs(damageHistory) do
        if (currentTime - damage.timestamp) < timeWindow then
            table.insert(recent, damage)
        end
    end
    
    return recent
end

-- Initialize damage tracking when player loads
AddEventHandler('playerSpawned', function()
    InitializeDamageTracking()
end)

-- Initialize on resource start
InitializeDamageTracking()
