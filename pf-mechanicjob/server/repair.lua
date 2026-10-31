local QBCore = exports['pfm-core']:GetCoreObject()

-- Preview pads needed/available and how many will be used
QBCore.Functions.CreateCallback('pf-mechanicjob:server:calcBrakeRepair', function(source, cb, vehNet)
    local Player = QBCore.Functions.GetPlayer(source)
    if not Player then cb(nil) return end

    local veh = NetworkGetEntityFromNetworkId(vehNet or -1)
    if not veh or veh == 0 then cb(nil) return end
    if PFMech and PFMech.EnsureVehicleRestored then PFMech.EnsureVehicleRestored(veh) end

    local st = Entity(veh).state
    local pd = st.partDamage or {}
    local brakeDmg = tonumber(pd.brakes) or 0            -- stored damage percent (0‑100)

    local have = 0
    local itm = Player.Functions.GetItemByName('brake_pads')
    if itm and itm.amount then have = tonumber(itm.amount) or 0 end

    -- Each pad repairs 25% damage (configurable if needed)
    local padsNeeded = math.ceil(brakeDmg / 25)
    local toUse = math.max(0, math.min(padsNeeded, have, 4))

    cb({
        padsNeeded = padsNeeded,
        havePads = have,
        toUse = toUse,
        brakeDmg = brakeDmg
    })
end)

-- Apply repair: remove items and update state, return result
RegisterNetEvent('pf-mechanicjob:server:applyBrakeRepair', function(vehNet, requestedUse)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player then return end

    local veh = NetworkGetEntityFromNetworkId(vehNet or -1)
    if not veh or veh == 0 then
        TriggerClientEvent('pf-mechanicjob:client:brakeRepairResult', src, 0, nil, 'Vehicle not found.')
        return
    end

    -- the car's saved wear first, or a later load would undo the repair
    if PFMech and PFMech.EnsureVehicleRestored then PFMech.EnsureVehicleRestored(veh) end
    local st = Entity(veh).state
    local pd = st.partDamage or {}
    local brakeDmg = tonumber(pd.brakes) or 0
    if brakeDmg <= 0 then
        TriggerClientEvent('pf-mechanicjob:client:brakeRepairResult', src, 0, 0, 'Brakes already perfect.')
        return
    end

    local have = 0
    local itm = Player.Functions.GetItemByName('brake_pads')
    if itm and itm.amount then have = tonumber(itm.amount) or 0 end

    local want = math.max(0, tonumber(requestedUse) or 0)
    local maxCanUse = math.ceil(brakeDmg / 25)
    local toUse = math.max(0, math.min(want, have, 4, maxCanUse))

    if toUse <= 0 then
        TriggerClientEvent('pf-mechanicjob:client:brakeRepairResult', src, 0, brakeDmg, 'No brake pads.')
        return
    end

    if not Player.Functions.RemoveItem('brake_pads', toUse) then
        TriggerClientEvent('pf-mechanicjob:client:brakeRepairResult', src, 0, brakeDmg, 'Failed to remove items.')
        return
    end
    if QBCore.Shared.Items and QBCore.Shared.Items['brake_pads'] then
        TriggerClientEvent('inventory:client:ItemBox', src, QBCore.Shared.Items['brake_pads'], 'remove', toUse)
    end

    -- Reduce damage
    pd.brakes = math.max(0, brakeDmg - (25 * toUse))
    st:set('partDamage', pd, true)

    -- NEW: Tell client to reset brake cache immediately
    TriggerClientEvent('pf_mech:client:resetBrakeCache', src, vehNet)

    TriggerClientEvent('pf-mechanicjob:client:brakeRepairResult', src, toUse, pd.brakes, nil)
end)
