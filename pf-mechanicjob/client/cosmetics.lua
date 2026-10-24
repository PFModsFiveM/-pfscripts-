local QBCore = exports['pfm-core']:GetCoreObject()

-- Map item name -> GTA mod type
local CosmeticItemToModType = {
    spoiler = 0,
    bumper = 1,
    vehicle_bumper = 1,     -- ADDED explicit alias
    skirts = 3,
    exhaust = 4,
    rollcage = 5,
    grille = 6,
    hood = 7,
    fenders = 8,
    roof = 10
}

local function useOx()
    return Config and Config.MenuSystem == 'ox_lib' and lib and lib.registerContext
end

local function openCosmeticModPicker(itemName, veh)
    if Config.Debug then
        print(('[COSMETICS] openCosmeticModPicker item=%s veh=%s'):format(tostring(itemName), veh))
    end
    if not veh or not DoesEntityExist(veh) then
        QBCore.Functions.Notify('Vehicle not found', 'error')
        return
    end
    local modType = CosmeticItemToModType[itemName]
    if not modType then
        QBCore.Functions.Notify('Unknown cosmetic type: '..tostring(itemName), 'error')
        return
    end
    SetVehicleModKit(veh, 0)
    local count = GetNumVehicleMods(veh, modType)

    -- Build rows
    local rows = {
        { header = ('Install %s'):format(itemName:gsub('_',' ')), txt = ('Mod Type %d'):format(modType), isMenuHeader = true }
    }

    if count and count > 0 then
        for i = 0, count - 1 do
            rows[#rows+1] = {
                header = ('Option #%d'):format(i + 1),
                txt = 'Install this modification',
                params = {
                    event = 'pf-mechanicjob:client:installCosmeticMod',
                    args = {
                        vehicle = NetworkGetNetworkIdFromEntity(veh),
                        item = itemName,
                        modType = modType,
                        modIndex = i
                    }
                }
            }
        end
    else
        rows[#rows+1] = { header = 'No variants', txt = 'No modifications available', params = {} }
    end

    if not useOx() then
        rows[#rows+1] = { header = 'Close', params = { event = 'qb-menu:client:closeMenu' } }
        exports['pfm-menu']:openMenu(rows)
        return
    end

    -- ox_lib context
    local ctx = 'cosm_'..itemName..'_'..GetGameTimer()
    local opts = {}
    for _, r in ipairs(rows) do
        if r.isMenuHeader then
            -- First header becomes title
            opts.title = r.header
        else
            opts[#opts+1] = {
                title = r.header,
                description = r.txt,
                disabled = not (r.params and r.params.event),
                onSelect = function()
                    if r.params and r.params.event then
                        TriggerEvent(r.params.event, r.params.args)
                    end
                end
            }
        end
    end
    lib.registerContext({ id = ctx, title = opts.title or 'Cosmetics', options = opts })
    lib.showContext(ctx)
end

-- Install cosmetic mod (consume item via server)
RegisterNetEvent('pf-mechanicjob:client:installCosmeticMod', function(data)
    local veh = NetworkGetEntityFromNetworkId(data.vehicle or 0)
    if not DoesEntityExist(veh) then
        QBCore.Functions.Notify('Vehicle not found', 'error')
        return
    end
    if GetIsVehicleEngineRunning(veh) then
        QBCore.Functions.Notify('Turn engine off first', 'error')
        return
    end

    local ped = PlayerPedId()
    RequestAnimDict('mini@repair')
    while not HasAnimDictLoaded('mini@repair') do Wait(0) end
    TaskPlayAnim(ped, 'mini@repair', 'fixing_a_ped', 8.0, -8.0, -1, 49, 0, false, false, false)

    QBCore.Functions.Progressbar('installing_cosmetic', 'Installing modification...', 5000, false, true,
        { disableMovement=true, disableCarMovement=true, disableMouse=false, disableCombat=true },
        { animDict='mini@repair', anim='fixing_a_ped', flags=49 }, {}, {},
        function()
            ClearPedTasks(ped)
            TriggerServerEvent('pf_mech:server:applyMod', {
                vehicle  = data.vehicle,
                item     = data.item,
                modType  = data.modType,
                modIndex = data.modIndex
            })
        end,
        function()
            ClearPedTasks(ped)
            QBCore.Functions.Notify('Installation cancelled', 'error')
        end
    )
end)

-- Server broadcast: apply mod visually
RegisterNetEvent('pf_mech:client:modApplied', function(data)
    local veh = NetworkGetEntityFromNetworkId(data.vehicle or 0)
    if not DoesEntityExist(veh) then return end
    SetVehicleModKit(veh, 0)
    SetVehicleMod(veh, data.modType, data.modIndex, false)
end)

-- Picker entrypoint (from item use)
RegisterNetEvent('pf-mechanicjob:client:openCosmeticPicker', function(itemName, veh)
    openCosmeticModPicker(itemName, veh)
end)

-- Debug command
if Config.Debug then
    RegisterCommand('debug_cosm', function()
        local veh = GetVehiclePedIsIn(PlayerPedId(), false)
        if veh == 0 then QBCore.Functions.Notify('No vehicle','error') return end
        openCosmeticModPicker('spoiler', veh)
    end)
end
