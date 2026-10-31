-- pf-computer's apps on pf-devices.
--
-- Business Manager, Order Supplies and the Job Board are shared apps: one module each
-- (html/apps/*.js) that runs on the tablet and in the computer's windows. Their RPCs call the
-- computer's own server actions through PFComputer.dispatch, so every check those actions make
-- (job and grade, boss-only actions, government permissions, storage state) applies exactly as it did
-- in the computer's old windows. Who sees an app is decided by the same functions:
--   businessmanager  the business's management (getAuthorizedBusiness), or government staff with the
--                    'businesses' permission for the city registry section (was the tablet's own app)
--   ordersupplies    whoever the supply handlers serve (resolveSuppliesBusiness: an authorised job
--                    business or an owned store)
--   jobboard         everyone
-- Positions (blip, stash point) are read on the server; the delivery point is placed in the world.
--
-- pf-government's management screens (City Hall, Business Oversight) are computer launchers: they open
-- pf-government's own page in a computer window (the client event pf-computer:client:openGovernmentProgram).

local C = PFComputer

local function call(action, payload, src) return C.dispatch(action, type(payload) == 'table' and payload or {}, src) end

local function playerPos(src)
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return nil end
    local c = GetEntityCoords(ped)
    if not c then return nil end
    return { x = c.x + 0.0, y = c.y + 0.0, z = c.z + 0.0 }
end

local function canManageBusiness(src) return C.getAuthorizedBusiness(src, {}) ~= nil end
local function canSeeRegistry(src) return C.govCan(src, 'businesses') end
local function canOrderSupplies(src) return C.resolveSuppliesBusiness(src, {}) ~= nil end

-- method -> computer action; the payload is passed on (each action validates what it reads)
local function routes(map)
    local out = {}
    for method, action in pairs(map) do
        out[method] = function(src, payload) return call(action, payload, src) end
    end
    return out
end

--- The delivery point is placed in the world with a preview truck (client/main.lua): only the boss
--- of an authorised business may start it; the position is checked again when it is saved.
local function startDeliveryPlacement(src)
    local job = C.getAuthorizedBusiness(src, {})
    if not job or not C.isBusinessBoss(src) then return { ok = false, error = 'not_boss' } end
    if not C.storageWritable() then return { ok = false, error = 'storage_unavailable' } end
    TriggerClientEvent('pf-devices:client:closeShells', src)
    TriggerClientEvent('pf-computer:client:placeDeliveryPoint', src)
    return { ok = true }
end

-- ── Business Manager ─────────────────────────────────────────────────────────
local BM = routes({
    config = 'business:getConfig', data = 'business:getData', analytics = 'business:analytics',
    transactions = 'business:transactions:list', employees = 'business:employees:list',
    employeeGrade = 'business:employees:update', employeeFire = 'business:employees:fire',
    menu = 'business:menu:list', menuAdd = 'business:menu:add', menuUpdate = 'business:menu:update',
    menuEdit = 'business:menu:editItem', menuDelete = 'business:menu:delete',
    categories = 'business:menu:categories:list', categoryAdd = 'business:menu:categories:add',
    categoryDelete = 'business:menu:categories:delete', categoryRename = 'business:menu:categories:rename',
    meals = 'business:meals:list', mealAdd = 'business:meals:add', mealUpdate = 'business:meals:update',
    mealDelete = 'business:meals:delete', stock = 'business:stock:get',
    wages = 'business:wages:get', wagesSet = 'business:wages:set',
    account = 'business:account:list', deposit = 'business:account:deposit', withdraw = 'business:account:withdraw',
    premises = 'business:premises:list', premisesBuy = 'business:premises:buy', access = 'business:access',
    registry = 'registry:overview', registryEmployees = 'registry:employees', registryTransfer = 'registry:transfer',
})

BM.__access = function(src) return canManageBusiness(src) or canSeeRegistry(src) end

--- Everything the first screen needs in one call (each part through its own action and checks).
BM.init = function(src)
    local access = call('business:access', {}, src)
    local out = { ok = true, access = access and access.data or {}, registry = canSeeRegistry(src), business = canManageBusiness(src) }
    if not out.business then return out end
    out.config = call('business:getConfig', {}, src)
    out.data = call('business:getData', {}, src)
    out.employees = call('business:employees:list', {}, src)
    out.transactions = call('business:transactions:list', { limit = 100 }, src)
    out.menu = call('business:menu:list', {}, src)
    out.meals = call('business:meals:list', {}, src)
    return out
end

--- Name, logo, blip colour; with blipHere the blip moves to where the boss stands (read here).
BM.settings = function(src, payload)
    local p = { name = payload.name, logoUrl = payload.logoUrl, blipColor = payload.blipColor }
    if payload.blipHere == true then
        p.blipCoords = playerPos(src)
        if not p.blipCoords then return { ok = false, error = 'invalid_coords' } end
    end
    return call('business:update:settings', p, src)
end

BM.blipHere = function(src, payload)
    local job = C.getAuthorizedBusiness(src, {})
    local pos = playerPos(src)
    if not job then return { ok = false, error = 'not_authorized' } end
    if not pos then return { ok = false, error = 'invalid_coords' } end
    return call('business:blips:save', { businessId = job, name = payload.name, color = payload.color, coords = pos }, src)
end

BM.stashHere = function(src)
    local pos = playerPos(src)
    if not pos then return { ok = false, error = 'invalid_coords' } end
    return call('business:stash:place', { coords = pos }, src)
end

BM.deliveryPoint = function(src) return startDeliveryPlacement(src) end

-- ── Order Supplies ───────────────────────────────────────────────────────────
local function supplyPayload(payload)
    local p = {}
    if payload.mode == 'store' or payload.mode == 'job' then p.mode = payload.mode end
    if type(payload.storeId) == 'string' or type(payload.storeId) == 'number' then p.storeId = tostring(payload.storeId):sub(1, 64) end
    if payload.orderId ~= nil then p.orderId = tonumber(payload.orderId) end
    if payload.fulfillment == 'delivery' or payload.fulfillment == 'pickup' then p.fulfillment = payload.fulfillment end
    if type(payload.items) == 'table' then
        p.items = {}
        for i, it in ipairs(payload.items) do
            if i > 50 then break end
            if type(it) == 'table' and (type(it.item) == 'string') then
                p.items[#p.items + 1] = { item = it.item:sub(1, 64), quantity = tonumber(it.quantity) or 0 }
            end
        end
    end
    return p
end

local OS = {
    __access = function(src) return canOrderSupplies(src) end,
    catalog = function(src, payload) return call('business:supplies:catalog', supplyPayload(payload), src) end,
    orders = function(src, payload) return call('business:supplies:orders:list', supplyPayload(payload), src) end,
    create = function(src, payload) return call('business:supplies:orders:create', supplyPayload(payload), src) end,
    cancel = function(src, payload) return call('business:supplies:orders:cancel', supplyPayload(payload), src) end,
    pickup = function(src, payload) return call('business:supplies:orders:pickup', supplyPayload(payload), src) end,
    deliveryPoint = function(src) return startDeliveryPlacement(src) end,
}

-- ── Job Board ────────────────────────────────────────────────────────────────
local JB = routes({
    list = 'jobs:list', catalog = 'jobs:catalog', businesses = 'jobs:businesses', create = 'jobs:create',
    myJobs = 'jobs:myJobs', applicants = 'jobs:getApplicants', apply = 'jobs:apply',
    myApplications = 'jobs:myApplications', withdraw = 'jobs:withdraw', hire = 'jobs:hire',
    respond = 'jobs:respond', reject = 'jobs:reject', close = 'jobs:close',
})

PFComputerApps = {
    {
        def = {
            id = 'businessmanager', name = 'Business Manager', icon = '📊', category = 'business', order = 10,
            devices = { 'tablet', 'computer' }, entry = 'html/apps/businessmanager.js', styles = { 'html/apps/business.css' },
            access = { handler = true }, window = { width = 1120, height = 720 },
            description = 'Run your business: sales, staff, wages, menu, stock, premises and the company account',
        },
        handlers = BM,
    },
    {
        def = {
            id = 'ordersupplies', name = 'Order Supplies', icon = '📦', category = 'business', order = 11,
            devices = { 'tablet', 'computer' }, entry = 'html/apps/ordersupplies.js', styles = { 'html/apps/business.css' },
            access = { handler = true }, window = { width = 1040, height = 700 },
            description = 'Order stock for your business or store, collected or delivered by truckers',
        },
        handlers = OS,
    },
    {
        def = {
            id = 'jobboard', name = 'Job Board', icon = '💼', category = 'business', order = 12,
            devices = { 'tablet', 'computer' }, entry = 'html/apps/jobboard.js', styles = { 'html/apps/business.css' },
            access = { anyone = true }, window = { width = 980, height = 680 },
            description = 'Vacancies in the city: apply, and hire for the business you run',
        },
        handlers = JB,
    },
}

local LAUNCHERS = {
    {
        id = 'cityhall-admin', name = 'City Hall', icon = '🏛️', category = 'government', order = 5,
        program = 'pf-government-city-hall', access = { gov = 'audit' },
        description = 'Laws, taxes, budgets, utilities and staff (pf-government)',
    },
    {
        id = 'cityhall-businesses', name = 'Business Oversight', icon = '🏢', category = 'government', order = 6,
        program = 'pf-government-businesses', access = { gov = 'businesses' },
        description = 'Business registry, licences and inspections (pf-government)',
    },
}

local function registerApps()
    if GetResourceState('pf-devices') ~= 'started' then return false end
    local all = true
    for _, a in ipairs(PFComputerApps) do
        local ok = pcall(function()
            exports['pf-devices']:RegisterApp(a.def)
            exports['pf-devices']:RegisterAppHandlers(a.def.id, a.handlers)
        end)
        all = all and ok
    end
    return all
end

local function registerLaunchers()
    if GetResourceState('pf-devices') ~= 'started' or GetResourceState('pf-government') ~= 'started' then return false end
    local all = true
    for _, a in ipairs(LAUNCHERS) do
        local ok = pcall(function()
            exports['pf-devices']:RegisterApp({
                id = a.id, name = a.name, icon = a.icon, category = a.category, order = a.order,
                devices = { 'computer' }, kind = 'launch',
                launch = { event = 'pf-computer:client:openGovernmentProgram', args = { a.program } },
                access = a.access, description = a.description,
            })
        end)
        all = all and ok
    end
    return all
end

function PFComputerRegisterApps()
    local apps = registerApps()
    local launchers = registerLaunchers()
    return apps, launchers
end

AddEventHandler('onResourceStart', function(resource)
    if resource == GetCurrentResourceName() or resource == 'pf-devices' or resource == 'pf-government' then
        SetTimeout(1000, PFComputerRegisterApps)
    end
end)
AddEventHandler('pf-devices:server:ready', PFComputerRegisterApps)

-- ── live refresh: staff lists follow duty and job changes ────────────────────
local lastStaffPush = {}
local function pushStaff(job)
    if type(job) ~= 'string' or job == '' or job == 'unemployed' then return end
    local now = GetGameTimer()
    if lastStaffPush[job] and now - lastStaffPush[job] < 1000 then return end
    lastStaffPush[job] = now
    C.push('job', job, 'businessmanager', 'staff', { businessId = job })
end

local function jobOf(src)
    local P = C.GetPlayer(src)
    return P and P.PlayerData and P.PlayerData.job and P.PlayerData.job.name or nil
end

-- pfm-core raises both on the server (server/events.lua)
AddEventHandler('QBCore:Server:SetDuty', function(src) pushStaff(jobOf(src)) end)
AddEventHandler('QBCore:Server:OnJobUpdate', function(_, job)
    pushStaff(type(job) == 'table' and job.name or nil)
end)
