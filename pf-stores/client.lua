local QBCore = exports['pfm-core']:GetCoreObject()

local function dbg(...)
    if not (Config and Config.Debug) then return end
    print('[pf-stores]', ...)
end

local spawnedEntities = {}
local spawnedBlips = {}

local purchaseProps = {}
local storeNpcs = {}

local purchaseTargets = {}
local npcTargets = {}

local purchaseStateCache = {}

local storefrontOpen = false

local function hasValidImage(sharedItem, configuredImage)
    local img = configuredImage
    if (img == nil or tostring(img) == '') and sharedItem and sharedItem.image ~= nil then
        img = sharedItem.image
    end
    if img == nil then return false end
    img = tostring(img)
    if img == '' then return false end
    if img == 'placeholder.png' then return false end
    return true
end

local function isConsumable(sharedItem)
    if type(sharedItem) ~= 'table' then return false end
    if sharedItem.useable == true then return true end
    local name = tostring(sharedItem.name or ''):lower()
    if name:find('water') or name:find('cola') or name:find('coffee') or name:find('juice') or name:find('beer') or name:find('whiskey') or name:find('vodka') or name:find('wine') then
        return true
    end
    if name:find('sandwich') or name:find('tosti') or name:find('candy') or name:find('chips') or name:find('milk') then
        return true
    end
    return false
end

local function getStorefrontItems(storeDef)
    local out = {}
    local sf = storeDef and storeDef.storefront or nil
    if not sf or type(sf.items) ~= 'table' then return out end

    for _, it in ipairs(sf.items) do
        if type(it) == 'table' and it.name then
            local key = tostring(it.name):lower()
            local sharedItem = QBCore and QBCore.Shared and QBCore.Shared.Items and QBCore.Shared.Items[key] or nil
            if sharedItem and isConsumable(sharedItem) then
                if hasValidImage(sharedItem, it.image) then
                    out[#out + 1] = it
                end
            else
                out[#out + 1] = it
            end
        end
    end

    return out
end

local function addSpawnedEntity(ent)
    if not ent or ent == 0 then return end
    spawnedEntities[#spawnedEntities + 1] = ent
end

local function addSpawnedBlip(blip)
    if not blip or blip == 0 then return end
    spawnedBlips[#spawnedBlips + 1] = blip
end

local function loadModel(model)
    local hash = model
    if type(model) == 'string' then
        hash = joaat(model)
    end
    if not IsModelInCdimage(hash) then return false end
    if not IsModelValid(hash) then return false end
    RequestModel(hash)
    local waited = 0
    while not HasModelLoaded(hash) and waited < 5000 do
        Wait(25)
        waited = waited + 25
    end
    return HasModelLoaded(hash)
end

local function vec4ToVec3(v4)
    if not v4 then return vector3(0.0, 0.0, 0.0) end
    return vector3(v4.x + 0.0, v4.y + 0.0, v4.z + 0.0)
end

local function ensurePurchaseProp(storeId, storeDef)
    local purchase = storeDef and storeDef.purchase or nil
    if not purchase or not purchase.coords or not purchase.propModel then
        return nil
    end

    local coords = purchase.coords
    local pos = vec4ToVec3(coords)
    local heading = coords.w + 0.0
    local model = purchase.propModel
    local hash = joaat(model)

    -- Slightly larger radius in case the prop was placed/streamed with a small offset.
    local existing = GetClosestObjectOfType(pos.x, pos.y, pos.z, 5.0, hash, false, false, false)
    if existing and existing ~= 0 then
        purchaseProps[storeId] = existing
        return existing
    end

    if not loadModel(model) then
        dbg('failed to load prop model', model)
        return nil
    end

    -- Create the prop locally when near it.
    local ent = CreateObjectNoOffset(hash, pos.x, pos.y, pos.z, false, false, false)
    if not ent or ent == 0 then
        -- Fallback for environments where NoOffset behaves oddly.
        ent = CreateObject(hash, pos.x, pos.y, pos.z, false, false, false)
    end
    if not ent or ent == 0 then
        return nil
    end

    SetEntityHeading(ent, heading)

    -- In some interiors/MLOs, ground placement can snap the prop to an exterior ground far away.
    -- Keep ground placement only if it doesn't move the prop significantly.
    local shouldPlaceOnGround = purchase.placeOnGround
    if shouldPlaceOnGround == nil then
        shouldPlaceOnGround = true
    end
    if shouldPlaceOnGround then
        local before = GetEntityCoords(ent)
        PlaceObjectOnGroundProperly(ent)
        local after = GetEntityCoords(ent)
        if #(after - before) > 2.0 then
            SetEntityCoordsNoOffset(ent, pos.x, pos.y, pos.z, false, false, false)
        end
    else
        SetEntityCoordsNoOffset(ent, pos.x, pos.y, pos.z, false, false, false)
    end

    FreezeEntityPosition(ent, true)
    SetEntityInvincible(ent, true)
    SetEntityAsMissionEntity(ent, true, true)
    addSpawnedEntity(ent)
    purchaseProps[storeId] = ent
    return ent
end

local function ensureStoreNpc(storeId, storeDef)
    local npc = storeDef and storeDef.npc or nil
    if not npc or not npc.coords then
        return nil
    end

    local coords = npc.coords
    local pos = vec4ToVec3(coords)
    local heading = coords.w + 0.0
    local model = npc.model or 'mp_m_shopkeep_01'
    local hash = joaat(model)

    if not loadModel(model) then
        dbg('failed to load npc model', model)
        return nil
    end

    local ped = CreatePed(4, hash, pos.x, pos.y, pos.z - 1.0, heading, false, false)
    if not ped or ped == 0 then
        return nil
    end

    SetEntityAsMissionEntity(ped, true, true)
    SetBlockingOfNonTemporaryEvents(ped, true)
    SetPedFleeAttributes(ped, 0, false)
    SetPedDiesWhenInjured(ped, false)
    SetEntityInvincible(ped, true)
    FreezeEntityPosition(ped, true)
    TaskStartScenarioInPlace(ped, 'WORLD_HUMAN_STAND_IMPATIENT', 0, true)
    addSpawnedEntity(ped)
    storeNpcs[storeId] = ped
    return ped
end

local function ensureStoreBlip(storeDef)
    local blipCfg = storeDef and storeDef.blip or nil
    local npc = storeDef and storeDef.npc or nil
    if not blipCfg or blipCfg.enabled == false or not npc or not npc.coords then
        return nil
    end

    local pos = vec4ToVec3(npc.coords)
    local blip = AddBlipForCoord(pos.x, pos.y, pos.z)
    SetBlipSprite(blip, blipCfg.sprite or 59)
    SetBlipScale(blip, blipCfg.scale or 0.8)
    SetBlipColour(blip, blipCfg.color or 2)
    SetBlipAsShortRange(blip, true)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentString(blipCfg.label or storeDef.label or 'Store')
    EndTextCommandSetBlipName(blip)
    addSpawnedBlip(blip)
    return blip
end

local function attachPurchaseTarget(storeId, storeDef, entity)
    if not entity or entity == 0 then return end
    if GetResourceState('pfm-target') ~= 'started' then
        dbg('qb-target not started; cannot attach purchase target')
        return
    end

    if purchaseTargets[storeId] == entity then
        return
    end

    local label = ('Purchase %s'):format(storeDef.label or storeId)

    exports['pfm-target']:AddTargetEntity(entity, {
        options = {
            {
                type = 'client',
                event = 'pf-stores:client:purchaseStore',
                icon = 'fas fa-dollar-sign',
                label = label,
                storeId = storeId,
            }
        },
        distance = 2.0,
    })

    purchaseTargets[storeId] = entity
end

local function attachNpcTarget(storeId, storeDef, ped)
    if not ped or ped == 0 then return end
    if GetResourceState('pfm-target') ~= 'started' then return end

    if npcTargets[storeId] == ped then
        return
    end

    exports['pfm-target']:AddTargetEntity(ped, {
        options = {
            {
                type = 'client',
                event = 'pf-stores:client:openStorefront',
                icon = 'fas fa-store',
                label = ('Shop at %s'):format(storeDef.label or storeId),
                storeId = storeId,
            },
        },
        distance = 2.0,
    })

    npcTargets[storeId] = ped
end

local function removePurchaseProp(storeId)
    local ent = purchaseProps[storeId]
    if ent and ent ~= 0 then
        -- Remove qb-target option first to prevent interaction.
        if GetResourceState('pfm-target') == 'started' then
            local storeDef = Config and Config.Stores and Config.Stores[storeId] or nil
            local label = ('Purchase %s'):format((storeDef and storeDef.label) or storeId)
            exports['pfm-target']:RemoveTargetEntity(ent, label)
        end

        -- Try deleting; if it's a map object, hide it.
        if DoesEntityExist(ent) then
            SetEntityAsMissionEntity(ent, true, true)
            DeleteEntity(ent)
        end
        if DoesEntityExist(ent) then
            SetEntityVisible(ent, false, false)
            SetEntityCollision(ent, false, false)
            FreezeEntityPosition(ent, true)
        end
    end
    purchaseProps[storeId] = nil
    purchaseTargets[storeId] = nil
end

local function removeStoreNpc(storeId)
    local ped = storeNpcs[storeId]
    if ped and ped ~= 0 then
        if GetResourceState('pfm-target') == 'started' then
            local storeDef = Config and Config.Stores and Config.Stores[storeId] or nil
            local label = ('Shop at %s'):format((storeDef and storeDef.label) or storeId)
            exports['pfm-target']:RemoveTargetEntity(ped, label)
        end

        if DoesEntityExist(ped) then
            SetEntityAsMissionEntity(ped, true, true)
            DeleteEntity(ped)
        end
    end
    storeNpcs[storeId] = nil
    npcTargets[storeId] = nil
end

local function getPurchaseStateCached(storeId, cb)
    local now = GetGameTimer()
    local cached = purchaseStateCache[storeId]
    if cached and cached.ts and (now - cached.ts) < 10000 then
        cb(cached.owned == true)
        return
    end

    QBCore.Functions.TriggerCallback('pf-stores:server:getStorePurchaseState', function(stateRes)
        local owned = stateRes and stateRes.ok and stateRes.data and stateRes.data.owned == true
        purchaseStateCache[storeId] = { owned = owned, ts = GetGameTimer() }
        cb(owned)
    end, storeId)
end

RegisterNetEvent('pf-stores:client:onStorePurchased', function(storeId)
    storeId = tostring(storeId or '')
    if storeId == '' then return end
    removePurchaseProp(storeId)
end)

RegisterNetEvent('pf-stores:client:purchaseStore', function(data)
    local storeId = data and (data.storeId or data.storeid) or nil
    storeId = tostring(storeId or '')
    if storeId == '' then return end

    QBCore.Functions.TriggerCallback('pf-stores:server:purchaseStore', function(purchaseRes)
        if not purchaseRes or not purchaseRes.ok then
            local err = purchaseRes and purchaseRes.error or 'unknown'
            if err == 'not_enough_money' then
                QBCore.Functions.Notify('Not enough money.', 'error')
            elseif err == 'already_owned' then
                QBCore.Functions.Notify('This store is already owned.', 'error')
            else
                QBCore.Functions.Notify('Purchase failed.', 'error')
            end
            return
        end

        local storeDef = Config and Config.Stores and Config.Stores[storeId] or nil
        QBCore.Functions.Notify(('You purchased %s.'):format((storeDef and storeDef.label) or storeId), 'success')
        removePurchaseProp(storeId)
    end, storeId)
end)

RegisterNetEvent('pf-stores:client:openStorefront', function(data)
    local storeId = data and (data.storeId or data.storeid) or nil
    storeId = tostring(storeId or '')
    if storeId == '' then return end

    if storefrontOpen then return end

    local storeDef = Config and Config.Stores and Config.Stores[storeId] or nil
    if not storeDef or not storeDef.storefront or storeDef.storefront.enabled == false then
        QBCore.Functions.Notify(((storeDef and storeDef.label) or 'Store') .. ' storefront not configured yet.', 'error')
        return
    end

    QBCore.Functions.TriggerCallback('pf-stores:server:getStorefrontStock', function(stockRes)
            local stock = (stockRes and stockRes.ok and stockRes.data and stockRes.data.stock) or {}
            local prices = (stockRes and stockRes.ok and stockRes.data and stockRes.data.prices) or {}
            local isOwner = (stockRes and stockRes.ok and stockRes.data and stockRes.data.isOwner) == true

            -- Apply server-resolved effective prices (owner overrides) to the display items.
            -- The server re-validates prices at checkout either way.
            local items = {}
            for _, it in ipairs(getStorefrontItems(storeDef)) do
                local copy = {}
                for k, v in pairs(it) do copy[k] = v end
                local key = tostring(it.name or ''):lower()
                local p = tonumber(prices[key])
                if p ~= nil then copy.price = p end
                items[#items + 1] = copy
            end

            local sf = storeDef.storefront or {}
            local moneyTypes = {}
            if type(sf.moneyTypes) == 'table' then
                for _, mt in ipairs(sf.moneyTypes) do
                    local v = tostring(mt or '')
                    if v == 'cash' or v == 'bank' then
                        moneyTypes[#moneyTypes + 1] = v
                    end
                end
            elseif sf.moneyType ~= nil then
                local v = tostring(sf.moneyType or '')
                if v == 'cash' or v == 'bank' then
                    moneyTypes = { v }
                end
            end
            if #moneyTypes == 0 then
                moneyTypes = { 'cash' }
            end

            local defaultMoneyType = tostring(sf.defaultMoneyType or moneyTypes[1] or 'cash')
            if defaultMoneyType ~= 'cash' and defaultMoneyType ~= 'bank' then
                defaultMoneyType = moneyTypes[1] or 'cash'
            end

            storefrontOpen = true
            SetNuiFocus(true, true)
            SendNUIMessage({
                action = 'open',
                payload = {
                    storeId = storeId,
                    label = storeDef.label or storeId,
                    moneyType = defaultMoneyType,
                    moneyTypes = moneyTypes,
                    brand = storeDef.storefront.brand or nil,
                    categories = storeDef.storefront.categories or {},
                    items = items,
                    stock = stock,
                    isOwner = isOwner,
                }
            })
    end, storeId)
end)

RegisterNUICallback('close', function(_, cb)
    storefrontOpen = false
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'close' })
    cb({ ok = true })
end)

RegisterNUICallback('checkout', function(data, cb)
    if not storefrontOpen then
        cb({ ok = false, error = 'not_open' })
        return
    end

    local storeId = data and data.storeId or nil
    local cart = data and data.cart or nil
    local moneyType = data and (data.moneyType or data.paymentMoneyType) or nil

    QBCore.Functions.TriggerCallback('pf-stores:server:storefrontCheckout', function(res)
        res = res or { ok = false, error = 'no_response', errorMessage = 'No response.' }
        if res.ok then
            QBCore.Functions.Notify(res.message or 'Purchase complete.', 'success')
        else
            QBCore.Functions.Notify(res.errorMessage or 'Purchase failed.', 'error')
        end
        cb(res)
    end, storeId, cart, moneyType)
end)

-- Owner management pass-throughs (NUI -> server callbacks)

RegisterNUICallback('getManagement', function(data, cb)
    if not storefrontOpen then
        cb({ ok = false, error = 'not_open' })
        return
    end

    QBCore.Functions.TriggerCallback('pf-stores:server:getManagementData', function(res)
        cb(res or { ok = false, error = 'no_response' })
    end, { storeId = data and data.storeId or nil })
end)

RegisterNUICallback('setPrice', function(data, cb)
    if not storefrontOpen then
        cb({ ok = false, error = 'not_open' })
        return
    end

    QBCore.Functions.TriggerCallback('pf-stores:server:setItemPrice', function(res)
        res = res or { ok = false, error = 'no_response' }
        if not res.ok and res.error == 'cooldown' then
            QBCore.Functions.Notify('Please wait a moment.', 'error')
        end
        cb(res)
    end, {
        storeId = data and data.storeId or nil,
        item = data and data.item or nil,
        price = data and data.price or nil,
    })
end)

RegisterNUICallback('deposit', function(data, cb)
    if not storefrontOpen then
        cb({ ok = false, error = 'not_open' })
        return
    end

    QBCore.Functions.TriggerCallback('pf-stores:server:depositBalance', function(res)
        res = res or { ok = false, error = 'no_response' }
        if res.ok then
            local amount = res.data and res.data.amount or 0
            QBCore.Functions.Notify(('Deposited $%s into the store account.'):format(amount), 'success')
        elseif res.error == 'insufficient_bank' then
            QBCore.Functions.Notify('Not enough money in your bank account.', 'error')
        elseif res.error == 'cooldown' then
            QBCore.Functions.Notify('Please wait a moment.', 'error')
        elseif res.error == 'invalid_amount' then
            QBCore.Functions.Notify('Invalid amount.', 'error')
        else
            QBCore.Functions.Notify('Deposit failed.', 'error')
        end
        cb(res)
    end, {
        storeId = data and data.storeId or nil,
        amount = data and data.amount or nil,
    })
end)

RegisterNUICallback('withdraw', function(data, cb)
    if not storefrontOpen then
        cb({ ok = false, error = 'not_open' })
        return
    end

    QBCore.Functions.TriggerCallback('pf-stores:server:withdrawBalance', function(res)
        res = res or { ok = false, error = 'no_response' }
        if res.ok then
            local amount = res.data and res.data.amount or 0
            QBCore.Functions.Notify(('Withdrew $%s to your bank account.'):format(amount), 'success')
        elseif res.error == 'insufficient_balance' then
            QBCore.Functions.Notify('Not enough store balance.', 'error')
        elseif res.error == 'cooldown' then
            QBCore.Functions.Notify('Please wait a moment.', 'error')
        elseif res.error == 'invalid_amount' then
            QBCore.Functions.Notify('Invalid amount.', 'error')
        else
            QBCore.Functions.Notify('Withdrawal failed.', 'error')
        end
        cb(res)
    end, {
        storeId = data and data.storeId or nil,
        amount = data and data.amount or nil,
    })
end)

CreateThread(function()
    Wait(1000)

    if not (Config and Config.Stores) then
        dbg('no stores configured')
        return
    end

    for storeId, storeDef in pairs(Config.Stores) do
        if type(storeId) == 'string' and type(storeDef) == 'table' then
            ensureStoreBlip(storeDef)
        end
    end

    -- Proximity-based spawning: creating entities far away is unreliable due to streaming.
    CreateThread(function()
        local spawnDist = (Config and Config.SpawnDistance) or 120.0
        local despawnDist = (Config and Config.DespawnDistance) or 200.0

        while true do
            Wait(1500)

            if not (Config and Config.Stores) then
                Wait(2500)
            else
                local playerPed = PlayerPedId()
                local pcoords = GetEntityCoords(playerPed)

                for storeId, storeDef in pairs(Config.Stores) do
                    if type(storeId) == 'string' and type(storeDef) == 'table' then
                        local purchase = storeDef.purchase
                        local npc = storeDef.npc

                        -- Spawn/cleanup NPC
                        if npc and npc.coords then
                            local npos = vec4ToVec3(npc.coords)
                            local nd = #(pcoords - npos)
                            if nd <= spawnDist then
                                local ped = storeNpcs[storeId]
                                if not ped or ped == 0 or not DoesEntityExist(ped) then
                                    ped = ensureStoreNpc(storeId, storeDef)
                                end
                                if ped and ped ~= 0 then
                                    attachNpcTarget(storeId, storeDef, ped)
                                end
                            elseif nd >= despawnDist then
                                if storeNpcs[storeId] and storeNpcs[storeId] ~= 0 then
                                    removeStoreNpc(storeId)
                                end
                            end
                        end

                        -- Spawn/cleanup purchase prop
                        if purchase and purchase.coords and purchase.propModel then
                            local ppos = vec4ToVec3(purchase.coords)
                            local pd = #(pcoords - ppos)
                            if pd <= spawnDist then
                                getPurchaseStateCached(storeId, function(owned)
                                    if owned then
                                        if purchaseProps[storeId] then
                                            removePurchaseProp(storeId)
                                        end
                                        return
                                    end

                                    local prop = purchaseProps[storeId]
                                    if not prop or prop == 0 or not DoesEntityExist(prop) then
                                        prop = ensurePurchaseProp(storeId, storeDef)
                                    end
                                    if prop and prop ~= 0 then
                                        attachPurchaseTarget(storeId, storeDef, prop)
                                    end
                                end)
                            elseif pd >= despawnDist then
                                if purchaseProps[storeId] then
                                    removePurchaseProp(storeId)
                                end
                            end
                        end
                    end
                end
            end
        end
    end)

    dbg('client started')
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end

    if storefrontOpen then
        storefrontOpen = false
        SetNuiFocus(false, false)
        SendNUIMessage({ action = 'close' })
    end

    for _, blip in ipairs(spawnedBlips) do
        if blip and blip ~= 0 then
            RemoveBlip(blip)
        end
    end

    for _, ent in ipairs(spawnedEntities) do
        if ent and ent ~= 0 then
            if DoesEntityExist(ent) then
                DeleteEntity(ent)
            end
        end
    end
end)
