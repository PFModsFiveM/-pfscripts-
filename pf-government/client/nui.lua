-- =====================================================
-- PF GOVERNMENT - NUI BRIDGE
-- =====================================================

-- This file handles NUI callback routing to server
-- All NUI callbacks are forwarded to server with source tracking

local pendingCallbacks = {}
local callbackId = 0

-- =====================================================
-- CALLBACK SYSTEM
-- =====================================================

local function MakeServerCallback(action, data, cb)
    callbackId = callbackId + 1
    local  currentId = callbackId
    
    -- Add source tracking
    data = data or {}
    data.source = GetPlayerServerId(PlayerId())
    
    pendingCallbacks[currentId] = cb
    
    TriggerServerEvent('pf-government:server:nuiCallback', currentId, action, data)
end

RegisterNetEvent('pf-government:client:nuiCallback', function(id, result)
    if pendingCallbacks[id] then
        pendingCallbacks[id](result)
        pendingCallbacks[id] = nil
    end
end)

-- =====================================================
-- NUI CALLBACK FORWARDING
-- =====================================================

-- Dashboard
RegisterNUICallback('dashboard:getData', function(data, cb)
    MakeServerCallback('dashboard:getData', data, cb)
end)

-- User info
RegisterNUICallback('user:getInfo', function(data, cb)
    MakeServerCallback('user:getInfo', data, cb)
end)

-- Config
RegisterNUICallback('config:get', function(data, cb)
    MakeServerCallback('config:get', data, cb)
end)

-- Treasury
RegisterNUICallback('treasury:getBalance', function(data, cb)
    MakeServerCallback('treasury:getBalance', data, cb)
end)

RegisterNUICallback('treasury:getTransactions', function(data, cb)
    MakeServerCallback('treasury:getTransactions', data, cb)
end)

RegisterNUICallback('treasury:deposit', function(data, cb)
    MakeServerCallback('treasury:deposit', data, cb)
end)

RegisterNUICallback('treasury:withdraw', function(data, cb)
    MakeServerCallback('treasury:withdraw', data, cb)
end)

-- Taxes
RegisterNUICallback('tax:getAll', function(data, cb)
    MakeServerCallback('tax:getAll', data, cb)
end)

RegisterNUICallback('tax:update', function(data, cb)
    MakeServerCallback('tax:update', data, cb)
end)

RegisterNUICallback('tax:toggle', function(data, cb)
    MakeServerCallback('tax:toggle', data, cb)
end)

-- Budgets
RegisterNUICallback('budget:getAll', function(data, cb)
    MakeServerCallback('budget:getAll', data, cb)
end)

RegisterNUICallback('budget:update', function(data, cb)
    MakeServerCallback('budget:update', data, cb)
end)

RegisterNUICallback('budget:allocate', function(data, cb)
    MakeServerCallback('budget:allocate', data, cb)
end)

RegisterNUICallback('budget:reset', function(data, cb)
    MakeServerCallback('budget:reset', data, cb)
end)

-- Laws
RegisterNUICallback('law:getAll', function(data, cb)
    MakeServerCallback('law:getAll', data, cb)
end)

RegisterNUICallback('law:get', function(data, cb)
    MakeServerCallback('law:get', data, cb)
end)

RegisterNUICallback('law:create', function(data, cb)
    MakeServerCallback('law:create', data, cb)
end)

RegisterNUICallback('law:update', function(data, cb)
    MakeServerCallback('law:update', data, cb)
end)

RegisterNUICallback('law:publish', function(data, cb)
    MakeServerCallback('law:publish', data, cb)
end)

RegisterNUICallback('law:repeal', function(data, cb)
    MakeServerCallback('law:repeal', data, cb)
end)

RegisterNUICallback('law:delete', function(data, cb)
    MakeServerCallback('law:delete', data, cb)
end)

RegisterNUICallback('law:getCategories', function(data, cb)
    MakeServerCallback('law:getCategories', data, cb)
end)

RegisterNUICallback('law:setDisplayEnabled', function(data, cb)
    MakeServerCallback('law:setDisplayEnabled', data, cb)
end)

-- Licenses
RegisterNUICallback('license:getAll', function(data, cb)
    MakeServerCallback('license:getAll', data, cb)
end)

RegisterNUICallback('license:issue', function(data, cb)
    MakeServerCallback('license:issue', data, cb)
end)

RegisterNUICallback('license:renew', function(data, cb)
    MakeServerCallback('license:renew', data, cb)
end)

RegisterNUICallback('license:suspend', function(data, cb)
    MakeServerCallback('license:suspend', data, cb)
end)

RegisterNUICallback('license:revoke', function(data, cb)
    MakeServerCallback('license:revoke', data, cb)
end)

RegisterNUICallback('license:getTypes', function(data, cb)
    MakeServerCallback('license:getTypes', data, cb)
end)

-- Utilities
RegisterNUICallback('utility:getAll', function(data, cb)
    MakeServerCallback('utility:getAll', data, cb)
end)

RegisterNUICallback('utility:disconnect', function(data, cb)
    MakeServerCallback('utility:disconnect', data, cb)
end)

RegisterNUICallback('utility:restore', function(data, cb)
    MakeServerCallback('utility:restore', data, cb)
end)

-- Bills
RegisterNUICallback('bill:getAll', function(data, cb)
    MakeServerCallback('bill:getAll', data, cb)
end)

RegisterNUICallback('bill:create', function(data, cb)
    MakeServerCallback('bill:create', data, cb)
end)

RegisterNUICallback('bill:pay', function(data, cb)
    MakeServerCallback('bill:pay', data, cb)
end)

RegisterNUICallback('bill:waive', function(data, cb)
    MakeServerCallback('bill:waive', data, cb)
end)

-- Businesses
RegisterNUICallback('business:getAll', function(data, cb)
    MakeServerCallback('business:getAll', data, cb)
end)

RegisterNUICallback('business:get', function(data, cb)
    MakeServerCallback('business:get', data, cb)
end)

RegisterNUICallback('business:getStats', function(data, cb)
    MakeServerCallback('business:getStats', data, cb)
end)

RegisterNUICallback('business:setCompliance', function(data, cb)
    MakeServerCallback('business:setCompliance', data, cb)
end)

RegisterNUICallback('business:register', function(data, cb)
    MakeServerCallback('business:register', data, cb)
end)

RegisterNUICallback('business:updateOwner', function(data, cb)
    MakeServerCallback('business:updateOwner', data, cb)
end)

RegisterNUICallback('business:updateLocation', function(data, cb)
    MakeServerCallback('business:updateLocation', data, cb)
end)

RegisterNUICallback('business:getJobOptions', function(data, cb)
    MakeServerCallback('business:getJobOptions', data, cb)
end)

RegisterNUICallback('business:save', function(data, cb)
    MakeServerCallback('business:save', data, cb)
end)

RegisterNUICallback('business:delete', function(data, cb)
    MakeServerCallback('business:delete', data, cb)
end)

RegisterNUICallback('business:setStatus', function(data, cb)
    MakeServerCallback('business:setStatus', data, cb)
end)

RegisterNUICallback('business:licenses:list', function(data, cb)
    MakeServerCallback('business:licenses:list', data, cb)
end)

RegisterNUICallback('business:licenses:grant', function(data, cb)
    MakeServerCallback('business:licenses:grant', data, cb)
end)

RegisterNUICallback('business:inspections:list', function(data, cb)
    MakeServerCallback('business:inspections:list', data, cb)
end)

RegisterNUICallback('business:inspections:file', function(data, cb)
    MakeServerCallback('business:inspections:file', data, cb)
end)

RegisterNUICallback('business:loans:list', function(data, cb)
    MakeServerCallback('business:loans:list', data, cb)
end)

RegisterNUICallback('business:loans:grant', function(data, cb)
    MakeServerCallback('business:loans:grant', data, cb)
end)

RegisterNUICallback('business:loans:pay', function(data, cb)
    MakeServerCallback('business:loans:pay', data, cb)
end)

-- Staff
RegisterNUICallback('staff:getAll', function(data, cb)
    MakeServerCallback('staff:getAll', data, cb)
end)

RegisterNUICallback('staff:add', function(data, cb)
    MakeServerCallback('staff:add', data, cb)
end)

RegisterNUICallback('staff:remove', function(data, cb)
    MakeServerCallback('staff:remove', data, cb)
end)

RegisterNUICallback('staff:updateRole', function(data, cb)
    MakeServerCallback('staff:updateRole', data, cb)
end)

RegisterNUICallback('staff:getRoles', function(data, cb)
    MakeServerCallback('staff:getRoles', data, cb)
end)

-- Audit Log
RegisterNUICallback('audit:getLogs', function(data, cb)
    MakeServerCallback('audit:getLogs', data, cb)
end)

RegisterNUICallback('audit:getStats', function(data, cb)
    MakeServerCallback('audit:getStats', data, cb)
end)

RegisterNUICallback('audit:getActionTypes', function(data, cb)
    MakeServerCallback('audit:getActionTypes', data, cb)
end)

-- Announcements
RegisterNUICallback('announcement:getAll', function(data, cb)
    MakeServerCallback('announcement:getAll', data, cb)
end)

RegisterNUICallback('gov:getAnnouncements', function(data, cb)
    MakeServerCallback('gov:getAnnouncements', data, cb)
end)

RegisterNUICallback('announcement:create', function(data, cb)
    MakeServerCallback('announcement:create', data, cb)
end)

RegisterNUICallback('gov:createAnnouncement', function(data, cb)
    MakeServerCallback('gov:createAnnouncement', data, cb)
end)

RegisterNUICallback('website:getState', function(data, cb)
    MakeServerCallback('website:getState', data, cb)
end)

RegisterNUICallback('website:saveState', function(data, cb)
    MakeServerCallback('website:saveState', data, cb)
end)

RegisterNUICallback('announcement:delete', function(data, cb)
    MakeServerCallback('announcement:delete', data, cb)
end)

-- Search
RegisterNUICallback('search:citizen', function(data, cb)
    MakeServerCallback('search:citizen', data, cb)
end)

RegisterNUICallback('search:business', function(data, cb)
    MakeServerCallback('search:business', data, cb)
end)

-- Browser assistant
RegisterNUICallback('assistant:query', function(data, cb)
    -- Include player world coords so the server can calculate real distances
    local ped    = PlayerPedId()
    local coords = GetEntityCoords(ped)
    data = data or {}
    data.coords = { x = coords.x, y = coords.y, z = coords.z }
    MakeServerCallback('assistant:query', data, cb)
end)

RegisterNUICallback('assistant:setWaypoint', function(data, cb)
    local x = tonumber(data and data.x)
    local y = tonumber(data and data.y)

    if not x or not y then
        cb({ ok = false, error = 'invalid_coords' })
        return
    end

    SetNewWaypoint(x + 0.0, y + 0.0)
    cb({ ok = true })
end)

-- Statistics
RegisterNUICallback('stats:getRevenue', function(data, cb)
    MakeServerCallback('stats:getRevenue', data, cb)
end)

-- Infrastructure
RegisterNUICallback('infra:getOverview', function(data, cb)
    MakeServerCallback('infra:getOverview', data, cb)
end)

RegisterNUICallback('infra:getDepartmentState', function(data, cb)
    MakeServerCallback('infra:getDepartmentState', data, cb)
end)

RegisterNUICallback('infra:getDistrictState', function(data, cb)
    MakeServerCallback('infra:getDistrictState', data, cb)
end)

RegisterNUICallback('infra:runUpkeepNow', function(data, cb)
    MakeServerCallback('infra:runUpkeepNow', data, cb)
end)

RegisterNUICallback('infra:buyUpgrade', function(data, cb)
    MakeServerCallback('infra:buyUpgrade', data, cb)
end)

RegisterNUICallback('infra:uninstallUpgrade', function(data, cb)
    MakeServerCallback('infra:uninstallUpgrade', data, cb)
end)

-- Business owner update
RegisterNUICallback('business:updateOwner', function(data, cb)
    MakeServerCallback('business:updateOwner', data, cb)
end)

-- Civilians
RegisterNUICallback('civilian:search', function(data, cb)
    MakeServerCallback('civilian:search', data, cb)
end)

RegisterNUICallback('civilian:getProfile', function(data, cb)
    MakeServerCallback('civilian:getProfile', data, cb)
end)

RegisterNUICallback('civilian:getJobs', function(data, cb)
    MakeServerCallback('civilian:getJobs', data, cb)
end)

RegisterNUICallback('civilian:updateIdentity', function(data, cb)
    MakeServerCallback('civilian:updateIdentity', data, cb)
end)

RegisterNUICallback('civilian:updateJob', function(data, cb)
    MakeServerCallback('civilian:updateJob', data, cb)
end)

RegisterNUICallback('civilian:toggleLicense', function(data, cb)
    MakeServerCallback('civilian:toggleLicense', data, cb)
end)

RegisterNUICallback('civilian:seizeVehicle', function(data, cb)
    MakeServerCallback('civilian:seizeVehicle', data, cb)
end)

RegisterNUICallback('civilian:deleteRecord', function(data, cb)
    MakeServerCallback('civilian:deleteRecord', data, cb)
end)

RegisterNUICallback('civilian:clearConvictions', function(data, cb)
    MakeServerCallback('civilian:clearConvictions', data, cb)
end)

RegisterNUICallback('fine:issueImmediate', function(data, cb)
    MakeServerCallback('fine:issueImmediate', data, cb)
end)

print('^2[PF-GOVERNMENT]^7 NUI bridge loaded')


-- Browser vitals for homepage stats
RegisterNUICallback('browser:getVitals', function(data, cb)
    local ped = PlayerPedId()
    local currentHealth = GetEntityHealth(ped) or 200
    local maxHealth = GetEntityMaxHealth(ped) or 200
    local healthPercent = 100
    if maxHealth > 100 then
        healthPercent = math.floor(math.max(0, math.min(100, ((currentHealth - 100) / (maxHealth - 100)) * 100)))
    end

    local pData = QBCore and QBCore.Functions.GetPlayerData() or {}
    local meta = pData and pData.metadata or {}
    local hunger = tonumber(meta.hunger) or 100
    local thirst = tonumber(meta.thirst) or 100

    cb({
        ok = true,
        vitals = {
            health = healthPercent,
            hunger = math.floor(math.max(0, math.min(100, hunger))),
            thirst = math.floor(math.max(0, math.min(100, thirst)))
        }
    })
end)
