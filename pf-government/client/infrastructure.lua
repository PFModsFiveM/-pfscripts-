-- Switches the lights off around the player when their district has no power.
-- pfm-weathersync owns the light state; this only tells it about the local outage.

local zoneToDistrict = {}
do
    local world = Config.InfrastructureWorld
    for district, zones in pairs((world and world.ZoneDistricts) or {}) do
        for _, zone in ipairs(zones) do zoneToDistrict[zone] = district end
    end
end

local current = false

local function setOutage(out)
    if out == current then return end
    current = out
    if GetResourceState('pfm-weathersync') == 'started' then
        pcall(function() exports['pfm-weathersync']:setDistrictOutage(out) end)
    end
end

CreateThread(function()
    local world = Config.InfrastructureWorld
    if not world or world.Enabled == false then return end
    while true do
        local power = GlobalState.pfGovDistrictPower
        local out = false
        if type(power) == 'table' then
            local coords = GetEntityCoords(PlayerPedId())
            local district = zoneToDistrict[GetNameOfZone(coords.x, coords.y, coords.z)]
            out = district ~= nil and power[district] == 0
        end
        setOutage(out)
        Wait(2000)
    end
end)

AddEventHandler('onResourceStop', function(name)
    if name == GetCurrentResourceName() then setOutage(false) end
end)
