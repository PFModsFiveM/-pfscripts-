-- ═══════════════════════════════════════════════════════════════════════════════
--                    COMPATIBILITY & INTEGRATION SETTINGS
--              Centralized configuration for all third-party scripts
-- ═══════════════════════════════════════════════════════════════════════════════

Config = Config or {}

PFMdt = PFMdt or {}

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║ FRAMEWORK                                                                     ║
-- ║ Core framework selection (QBCore or ESX)                                      ║
-- ╚════════════════════════════════════════════════════════════════════════════╝
-- Supported: 'qbcore', 'qb-core', 'qb' or 'esx', 'es_extended'
-- Leave as nil for auto-detection (checks for qb-core or es_extended resource)
--
-- ═══════════════════════════════════════════════════════════════════════════════
-- HOW TO ADD A NEW FRAMEWORK:
-- ═══════════════════════════════════════════════════════════════════════════════
-- 1. Set Config.Framework in config.lua:
--    Config.Framework = 'custom-framework'
--
-- 2. Add normalization to normalizeFramework() function below:
--    if val == 'custom' or val == 'custom-framework' then return 'custom-framework' end
--
-- 3. Add detection to detectFramework() function:
--    if GetResourceState('custom-framework') == 'started' then return 'custom-framework' end
--
-- 4. Create compatibility wrapper functions in buildCustomCompatClient/Server sections
--    following the same pattern as ESX/QBCore wrappers
-- ═══════════════════════════════════════════════════════════════════════════════
--
-- REQUIRED: Set this in config.lua
Config.Framework = Config.Framework

-- ═══════════════════════════════════════════════════════════════════════════════
-- FRAMEWORK COMPATIBILITY IMPLEMENTATION
-- ═══════════════════════════════════════════════════════════════════════════════

--- Normalize framework name to standardized format
local function normalizeFramework(val)
    val = tostring(val or ''):lower()
    if val == 'qb' or val == 'qb-core' or val == 'qbcore' or val == 'qbc' then return 'qbcore' end
    if val == 'esx' or val == 'es_extended' or val == 'es' then return 'esx' end
    -- Add custom framework normalization here:
    -- if val == 'custom' or val == 'custom-framework' then return 'custom-framework' end
    return val
end

--- Auto-detect framework if not specified in config
local function detectFramework()
    local cfg = Config and Config.Framework or nil
    cfg = normalizeFramework(cfg)
    if cfg == 'qbcore' or cfg == 'esx' then return cfg end

    if GetResourceState then
        if GetResourceState('pfm-core') == 'started' then return 'qbcore' end
        if GetResourceState('es_extended') == 'started' then return 'esx' end
        -- Add custom framework detection here:
        -- if GetResourceState('custom-framework') == 'started' then return 'custom-framework' end
    end

    return 'qbcore'
end

--- Get ESX shared object
local function getESXSharedObject()
    if PFMdt._esx then return PFMdt._esx end

    local obj = nil

    local okExport = pcall(function()
        if exports and exports['es_extended'] and exports['es_extended'].getSharedObject then
            obj = exports['es_extended']:getSharedObject()
        end
    end)

    if not obj then
        TriggerEvent('esx:getSharedObject', function(o)
            obj = o
        end)

        local timeoutAt = GetGameTimer() + 7500
        while not obj and GetGameTimer() < timeoutAt do
            Wait(50)
        end
    end

    if not obj and okExport then
        if not PFMdt._esxWarned then
            PFMdt._esxWarned = true
            print('[pf-policemdt] WARNING: ESX selected but could not get shared object yet (es_extended not started?). Will retry.')
        end
        return nil
    end

    if obj then
        PFMdt._esx = obj
    end
    return obj
end

--- Split full name into first and last name
local function splitName(full)
    full = tostring(full or ''):gsub('^%s*(.-)%s*$', '%1')
    if full == '' then return '', '' end
    local first, last = full:match('^(%S+)%s+(.+)$')
    if first then return first, last end
    return full, ''
end

--- Build ESX player data in QBCore format
local function buildESXPlayerData(xPlayer, source)
    if not xPlayer then return nil end

    local identifier = xPlayer.identifier or (xPlayer.getIdentifier and xPlayer.getIdentifier())

    local job = nil
    if xPlayer.getJob then
        job = xPlayer.getJob()
    elseif xPlayer.job then
        job = xPlayer.job
    end
    job = job or {}

    local jobName = job.name or 'unemployed'
    local gradeLevel = tonumber(job.grade) or tonumber(job.grade_level) or 0
    local jobLabel = job.label or jobName

    local firstName = ''
    local lastName = ''

    if xPlayer.get then
        firstName = xPlayer.get('firstName') or xPlayer.get('firstname') or ''
        lastName = xPlayer.get('lastName') or xPlayer.get('lastname') or ''
    end

    if (firstName == '' and lastName == '') and xPlayer.getName then
        firstName, lastName = splitName(xPlayer.getName())
    end

    return {
        source = source,
        citizenid = identifier,
        charinfo = {
            firstname = firstName,
            lastname = lastName,
        },
        job = {
            name = jobName,
            label = jobLabel,
            grade = {
                level = gradeLevel,
                name = job.grade_name or job.grade_label or tostring(gradeLevel),
            }
        },
        metadata = {},
    }
end

--- Wrap ESX player object for server-side compatibility
local function wrapESXPlayerServer(xPlayer, source)
    if not xPlayer then return nil end

    local pdata = buildESXPlayerData(xPlayer, source)

    local function getAccountBalance(account)
        account = tostring(account or '')
        if account == '' then return 0 end

        if xPlayer.getAccount then
            local acc = xPlayer.getAccount(account)
            if acc and acc.money ~= nil then
                return tonumber(acc.money) or 0
            end
        end

        if xPlayer.getAccounts then
            local ok, list = pcall(xPlayer.getAccounts)
            if ok and type(list) == 'table' then
                for _, acc in ipairs(list) do
                    if acc and acc.name == account then
                        return tonumber(acc.money) or 0
                    end
                end
            end
        end

        return 0
    end

    pdata.money = pdata.money or {
        cash = (xPlayer.getMoney and tonumber(xPlayer.getMoney()) or 0) or 0,
        bank = getAccountBalance('bank') or 0,
    }

    local function addMoney(account, amount)
        amount = tonumber(amount) or 0
        if amount == 0 then return true end

        if account == 'bank' or account == 'money' then
            if xPlayer.addAccountMoney then
                xPlayer.addAccountMoney('bank', amount)
                if pdata and pdata.money then
                    pdata.money.bank = (tonumber(pdata.money.bank) or 0) + amount
                end
                return true
            end
        end

        if account == 'cash' then
            if xPlayer.addMoney then
                xPlayer.addMoney(amount)
                if pdata and pdata.money then
                    pdata.money.cash = (tonumber(pdata.money.cash) or 0) + amount
                end
                return true
            end
        end

        if xPlayer.addAccountMoney then
            xPlayer.addAccountMoney(account, amount)
            return true
        end

        if xPlayer.addMoney then
            xPlayer.addMoney(amount)
            return true
        end

        return false
    end

    local function removeMoney(account, amount)
        amount = tonumber(amount) or 0
        if amount <= 0 then return true end

        if account == 'bank' or account == 'money' then
            if xPlayer.removeAccountMoney then
                xPlayer.removeAccountMoney('bank', amount)
                if pdata and pdata.money then
                    pdata.money.bank = (tonumber(pdata.money.bank) or 0) - amount
                end
                return true
            end
        end

        if account == 'cash' then
            if xPlayer.removeMoney then
                xPlayer.removeMoney(amount)
                if pdata and pdata.money then
                    pdata.money.cash = (tonumber(pdata.money.cash) or 0) - amount
                end
                return true
            end
        end

        if xPlayer.removeAccountMoney then
            xPlayer.removeAccountMoney(account, amount)
            return true
        end

        if xPlayer.removeMoney then
            xPlayer.removeMoney(amount)
            return true
        end

        return false
    end

    return {
        PlayerData = pdata,
        Functions = {
            GetMoney = function(account)
                account = tostring(account or ''):lower()
                if account == 'bank' or account == 'money' then
                    if pdata and pdata.money and pdata.money.bank ~= nil then
                        return tonumber(pdata.money.bank) or 0
                    end
                    return getAccountBalance('bank')
                end
                if account == 'cash' then
                    if pdata and pdata.money and pdata.money.cash ~= nil then
                        return tonumber(pdata.money.cash) or 0
                    end
                    return (xPlayer.getMoney and tonumber(xPlayer.getMoney()) or 0) or 0
                end
                return getAccountBalance(account)
            end,
            AddMoney = addMoney,
            RemoveMoney = removeMoney,
            SetJob = function(jobName, grade)
                jobName = tostring(jobName or 'unemployed')
                grade = tonumber(grade) or 0
                if xPlayer.setJob then
                    xPlayer.setJob(jobName, grade)
                    if pdata and pdata.job then
                        pdata.job.name = jobName
                        pdata.job.label = jobName
                        if pdata.job.grade then
                            pdata.job.grade.level = grade
                            pdata.job.grade.name = tostring(grade)
                        end
                    end
                    return true
                end
                return false
            end,
            SetMetaData = function(_, _) end,
        }
    }
end

--- Build ESX client compatibility layer
local function buildESXCompatClient()
    local compat = {}
    compat.Functions = {}

    compat.Functions.GetPlayerData = function()
        local ESX = getESXSharedObject()
        local pd = ESX and ESX.GetPlayerData and ESX.GetPlayerData() or {}
        local job = pd.job or {}

        return {
            job = {
                name = job.name,
                label = job.label or job.name,
                grade = {
                    level = tonumber(job.grade) or 0,
                    name = job.grade_name or job.grade_label or tostring(job.grade or 0),
                }
            },
            metadata = pd.metadata or {},
            charinfo = pd.charinfo or {
                firstname = pd.firstName or pd.firstname or '',
                lastname = pd.lastName or pd.lastname or '',
            },
            citizenid = pd.identifier or pd.citizenid or nil,
        }
    end

    compat.Functions.TriggerCallback = function(name, cb, ...)
        local ESX = getESXSharedObject()
        if ESX and ESX.TriggerServerCallback then
            return ESX.TriggerServerCallback(name, cb, ...)
        end
        print(('[pf-policemdt] ERROR: ESX.TriggerServerCallback not available for %s'):format(tostring(name)))
        if cb then cb(nil) end
    end

    compat.Functions.Notify = function(msg, _type, _length)
        msg = tostring(msg or '')
        local ESX = getESXSharedObject()
        if ESX and ESX.ShowNotification then
            ESX.ShowNotification(msg)
            return
        end
        TriggerEvent('esx:showNotification', msg)
    end

    return compat
end

--- Build ESX server compatibility layer
local function buildESXCompatServer()
    local compat = {}
    compat.Functions = {}

    compat.Functions.GetPlayer = function(source)
        local ESX = getESXSharedObject()
        if not ESX or not ESX.GetPlayerFromId then return nil end
        local xPlayer = ESX.GetPlayerFromId(source)
        return wrapESXPlayerServer(xPlayer, source)
    end

    compat.Functions.GetQBPlayers = function()
        local out = {}
        for _, sid in ipairs(GetPlayers() or {}) do
            local src = tonumber(sid)
            local P = compat.Functions.GetPlayer(src)
            if P then out[#out + 1] = P end
        end
        return out
    end

    compat.Functions.GetPlayers = function()
        return GetPlayers() or {}
    end

    compat.Functions.GetPlayerByCitizenId = function(citizenid)
        citizenid = tostring(citizenid or '')
        for _, sid in ipairs(GetPlayers() or {}) do
            local src = tonumber(sid)
            local P = compat.Functions.GetPlayer(src)
            if P and P.PlayerData and tostring(P.PlayerData.citizenid or '') == citizenid then
                return P
            end
        end
        return nil
    end

    compat.Functions.CreateCallback = function(name, cb)
        local ESX = getESXSharedObject()
        if ESX and ESX.RegisterServerCallback then
            ESX.RegisterServerCallback(name, cb)
            return
        end
        print(('[pf-policemdt] ERROR: ESX.RegisterServerCallback missing for %s'):format(tostring(name)))
    end

    compat.Functions.CreateUseableItem = function(itemName, cb)
        local ESX = getESXSharedObject()
        if ESX and ESX.RegisterUsableItem then
            ESX.RegisterUsableItem(itemName, function(source)
                cb(source, { name = itemName })
            end)
            return true
        end
        if not PFMdt._esxUsableWarned then PFMdt._esxUsableWarned = {} end
        if not PFMdt._esxUsableWarned[itemName] then
            PFMdt._esxUsableWarned[itemName] = true
            print(('[pf-policemdt] WARNING: Could not register usable item %s yet (ESX not ready?). Will retry from caller.'):format(tostring(itemName)))
        end
        return false
    end

    compat.Commands = {}
    compat.Commands.Add = function(name, _help, _args, _restricted, cb, permission)
        RegisterCommand(name, function(source, args, _raw)
            local src = tonumber(source) or 0
            if src ~= 0 and permission and permission ~= '' then
                if not IsPlayerAceAllowed(src, permission) then
                    TriggerClientEvent('QBCore:Notify', src, 'No permission', 'error')
                    return
                end
            end
            cb(source, args)
        end, false)
    end

    return compat
end

--- Get framework name (cached)
function PFMdt.GetFrameworkName()
    PFMdt._frameworkName = PFMdt._frameworkName or detectFramework()
    return PFMdt._frameworkName
end

--- Get framework core object
function PFMdt.GetCore()
    if PFMdt._core then return PFMdt._core end

    local fw = PFMdt.GetFrameworkName()
    if fw == 'esx' then
        if IsDuplicityVersion() then
            PFMdt._core = buildESXCompatServer()
        else
            PFMdt._core = buildESXCompatClient()
        end
    else
        -- QBCore or custom framework
        local success, core = pcall(function()
            return exports['pfm-core']:GetCoreObject()
        end)
        
        if not success or not core then
            print('[pf-policemdt] ERROR: Failed to get QBCore object. Make sure qb-core is started before pf-policemdt-DEV')
            print('[pf-policemdt] Error details: ' .. tostring(core))
            return nil
        end
        
        PFMdt._core = core
    end

    return PFMdt._core
end

-- Client-side: ESX notification compatibility for QBCore:Notify events
if not IsDuplicityVersion() then
    CreateThread(function()
        local fw = PFMdt.GetFrameworkName()
        if fw ~= 'esx' then return end
        RegisterNetEvent('QBCore:Notify', function(msg, nType, length)
            local core = PFMdt.GetCore()
            if core and core.Functions and core.Functions.Notify then
                core.Functions.Notify(msg, nType, length)
            else
                TriggerEvent('esx:showNotification', tostring(msg or ''))
            end
        end)
    end)
end

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║ PHONE INTEGRATION                                                             ║
-- ║ Phone system for contacts, call history, and emergency calls                 ║
-- ╚════════════════════════════════════════════════════════════════════════════╝
-- Supported scripts:
--   'qb-phone'    - QB-Core phone system
--   'lb-phone'    - LB Scripts phone system (export prefix: 'lb-phone')
--   'tgg-phone'   - TeamsGG Y Series phone (export prefix: 'yseries')
--   'none'        - Disable phone integration
--
-- ═══════════════════════════════════════════════════════════════════════════════
-- HOW TO ADD A NEW PHONE SYSTEM:
-- ═══════════════════════════════════════════════════════════════════════════════
-- 1. Set Config.Phone in config.lua:
--    Config.Phone = 'custom-phone'
--
-- 2. Add integration logic in your server/client scripts:
--    if Config.Phone == 'custom-phone' then
--        -- Export calls or direct script references
--        exports['custom-phone']:AddContact(citizenid, contactData)
--    end
-- ═══════════════════════════════════════════════════════════════════════════════
--
-- REQUIRED: Set this in config.lua
Config.Phone = Config.Phone

-- ═══════════════════════════════════════════════════════════════════════════════
-- PHONE INTEGRATION IMPLEMENTATION
-- ═══════════════════════════════════════════════════════════════════════════════
-- Add phone system-specific implementation logic here
-- Example for custom phone:
--
-- function PFMdt.Phones.SendEmergencyCall(citizenid, callData)
--     if Config.Phone == 'custom-phone' then
--         exports['custom-phone']:DispatchCall(callData)
--     elseif Config.Phone == 'lb-phone' then
--         exports['lb-phone']:CreateDispatchCall(callData)
--     end
-- end

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║ HOUSING INTEGRATION                                                           ║
-- ║ Property/housing system for address lookups and ownership                    ║
-- ╚════════════════════════════════════════════════════════════════════════════╝
-- Supported scripts:
--   'qb'              - qb-houses or qb-properties
--   'nolag-properties' - NoLag Properties script
--   'none'            - Disable housing integration
--
-- ═══════════════════════════════════════════════════════════════════════════════
-- HOW TO ADD A NEW HOUSING SYSTEM:
-- ═══════════════════════════════════════════════════════════════════════════════
-- 1. Set Config.Housing in config.lua:
--    Config.Housing = 'custom-housing'
--
-- 2. Add integration logic:
--    if Config.Housing == 'custom-housing' then
--        local properties = exports['custom-housing']:GetPlayerProperties(citizenid)
--        return properties
--    end
-- ═══════════════════════════════════════════════════════════════════════════════
--
-- REQUIRED: Set this in config.lua
Config.Housing = Config.Housing

-- ═══════════════════════════════════════════════════════════════════════════════
-- HOUSING INTEGRATION IMPLEMENTATION
-- ═══════════════════════════════════════════════════════════════════════════════
-- Add housing system-specific implementation logic here
-- Example for custom housing:
--
-- function PFMdt.Housing.GetPlayerProperties(citizenid)
--     if Config.Housing == 'custom-housing' then
--         return exports['custom-housing']:GetProperties(citizenid)
--     elseif Config.Housing == 'qb' then
--         return exports['pfm-houses']:GetHouses(citizenid)
--     end
-- end

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║ GARAGE INTEGRATION                                                            ║
-- ║ Vehicle garage system for impound and retrieval                              ║
-- ╚════════════════════════════════════════════════════════════════════════════╝
-- Supported scripts:
--   'qb-garages'  - QB-Core garage system
--   'cd-garages'  - CodesignDev garage system
--   'none'        - Disable garage integration
--
-- ═══════════════════════════════════════════════════════════════════════════════
-- HOW TO ADD A NEW GARAGE SYSTEM:
-- ═══════════════════════════════════════════════════════════════════════════════
-- 1. Set Config.Garage in config.lua:
--    Config.Garage = 'custom-garage'
--
-- 2. Add integration logic:
--    if Config.Garage == 'custom-garage' then
--        exports['custom-garage']:ImpoundVehicle(plate, citizenid)
--    end
-- ═══════════════════════════════════════════════════════════════════════════════
--
-- REQUIRED: Set this in config.lua
Config.Garage = Config.Garage

-- ═══════════════════════════════════════════════════════════════════════════════
-- GARAGE INTEGRATION IMPLEMENTATION
-- ═══════════════════════════════════════════════════════════════════════════════
-- Add garage system-specific implementation logic here
-- Example for custom garage:
--
-- function PFMdt.Garage.ImpoundVehicle(plate, citizenid, reason)
--     if Config.Garage == 'custom-garage' then
--         exports['custom-garage']:Impound(plate, citizenid, reason)
--     elseif Config.Garage == 'qb-garages' then
--         TriggerServerEvent('qb-garages:server:UpdateVehicle', plate, 1)
--     end
-- end

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║ BANKING INTEGRATION                                                           ║
-- ║ Banking system for fines, account access, transactions                       ║
-- ╚════════════════════════════════════════════════════════════════════════════╝
-- Supported scripts:
--   'qb-banking'      - QB-Core banking system
--   'tgg-banking'     - TeamsGG banking system
--   'wasabi_banking'  - Wasabi banking system
--   'none'            - Disable banking integration
--
-- ═══════════════════════════════════════════════════════════════════════════════
-- HOW TO ADD A NEW BANKING SYSTEM:
-- ═══════════════════════════════════════════════════════════════════════════════
-- 1. Set Config.Banking in config.lua:
--    Config.Banking = 'custom-banking'
--
-- 2. Add integration logic:
--    if Config.Banking == 'custom-banking' then
--        exports['custom-banking']:RemoveMoney(citizenid, amount, 'fine')
--    end
-- ═══════════════════════════════════════════════════════════════════════════════
--
-- REQUIRED: Set this in config.lua
Config.Banking = Config.Banking

-- ═══════════════════════════════════════════════════════════════════════════════
-- BANKING INTEGRATION IMPLEMENTATION
-- ═══════════════════════════════════════════════════════════════════════════════
-- Add banking system-specific implementation logic here
-- Example for custom banking:
--
-- function PFMdt.Banking.RemoveMoney(citizenid, amount, reason)
--     if Config.Banking == 'custom-banking' then
--         exports['custom-banking']:Withdraw(citizenid, amount, reason)
--     elseif Config.Banking == 'qb-banking' then
--         exports['pfm-banking']:RemoveMoney(citizenid, amount, reason)
--     end
-- end

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║ BILLING INTEGRATION                                                           ║
-- ║ Invoice/billing system for fines and invoices                                ║
-- ╚════════════════════════════════════════════════════════════════════════════╝
-- Supported scripts:
--   'qb-billing'      - QB-Core billing system
--   'okok-billing'    - OkOk Scripts billing system
--   'renewed-billing' - Renewed Scripts billing system
--   'vivum-billing'   - Vivum billing system
--   'none'            - Disable billing integration
--
-- ═══════════════════════════════════════════════════════════════════════════════
-- HOW TO ADD A NEW BILLING SYSTEM:
-- ═══════════════════════════════════════════════════════════════════════════════
-- 1. Set Config.Billing in config.lua:
--    Config.Billing = 'custom-billing'
--
-- 2. Add normalization to normalizeBilling() function below:
--    if billing == 'custom' or billing == 'custom-billing' then return 'custom-billing' end
--
-- 3. Add integration in PFMdt.Billing functions:
--    if billing == 'custom-billing' then
--        exports['custom-billing']:SendInvoice(source, amount, reason)
--    end
-- ═══════════════════════════════════════════════════════════════════════════════
--
-- REQUIRED: Set this in config.lua
Config.Billing = Config.Billing

-- ═══════════════════════════════════════════════════════════════════════════════
-- BILLING INTEGRATION IMPLEMENTATION
-- ═══════════════════════════════════════════════════════════════════════════════

PFMdt.Billing = PFMdt.Billing or {}

--- Normalize billing name to standardized format
local function normalizeBilling(val)
    val = tostring(val or 'qb-billing'):lower()
    if val == '' then val = 'qb-billing' end
    if val == 'qb' or val == 'qb-billing' or val == 'qbilling' then return 'qb-billing' end
    if val == 'okok' or val == 'okok-billing' or val == 'okokbilling' then return 'okok-billing' end
    if val == 'renewed' or val == 'renewed-billing' or val == 'renewedbilling' then return 'renewed-billing' end
    if val == 'vivum' or val == 'vivum-billing' or val == 'vivumbilling' then return 'vivum-billing' end
    if val == 'wasabi' or val == 'wasabi_banking' or val == 'wasabi-banking' or val == 'wasabibanking' then return 'wasabi_banking' end
    if val == 'none' then return 'none' end
    -- Add custom billing normalization here:
    -- if val == 'custom' or val == 'custom-billing' then return 'custom-billing' end
    return val
end

--- Send an invoice to a player
--- @param source number Target player server ID
--- @param amount number Invoice amount
--- @param reason string Reason/description for invoice
--- @param society string? Society/organization issuing invoice (default: 'police')
--- @return boolean success Whether invoice was sent successfully
function PFMdt.Billing.SendInvoice(source, amount, reason, society)
    if not IsDuplicityVersion() then
        print('[pf-policemdt] ERROR: PFMdt.Billing.SendInvoice can only be called server-side')
        return false
    end

    source = tonumber(source) or 0
    amount = tonumber(amount) or 0
    reason = tostring(reason or 'Invoice')
    society = tostring(society or 'police')

    if source == 0 or amount <= 0 then
        print('[pf-policemdt] ERROR: Invalid parameters for SendInvoice')
        return false
    end

    local billing = normalizeBilling(Config.Billing)

    -- QB-Billing
    if billing == 'qb-billing' then
        TriggerEvent('qb-billing:server:sendInvoice', {
            playerId = source,
            amount = amount,
            reason = reason,
            society = society
        })
        return true
    end

    -- OkOk-Billing
    if billing == 'okok-billing' then
        exports['okokBilling']:CreateInvoice(source, amount, reason, society)
        return true
    end

    -- Renewed-Billing
    if billing == 'renewed-billing' then
        exports['Renewed-Lib']:addChargeId(source, amount, reason)
        return true
    end

    -- Vivum-Billing
    if billing == 'vivum-billing' then
        local Core = PFMdt.GetCore()
        local Player = Core.Functions.GetPlayer(source)
        if not Player then
            print('[pf-policemdt] ERROR: Could not get player for vivum-billing invoice')
            return false
        end

        local citizenid = Player.PlayerData.citizenid
        if not citizenid then
            print('[pf-policemdt] ERROR: Invalid citizenid for vivum-billing invoice')
            return false
        end

        exports['vivum-billing']:sendInvoice(citizenid, society, {
            amount = amount,
            reason = reason,
            date = os.date('%Y-%m-%d %H:%M:%S')
        })
        return true
    end

    -- Add custom billing integration here:
    -- if billing == 'custom-billing' then
    --     exports['custom-billing']:SendInvoice(source, amount, reason, society)
    --     return true
    -- end

    if billing ~= 'none' then
        print(('[pf-policemdt] WARNING: Billing system "%s" is not supported'):format(billing))
    end

    return false
end

--- Fetch unpaid invoices for a player
--- @param identifier string Player citizenid/identifier
--- @param callback function Callback function(invoices)
function PFMdt.Billing.FetchInvoices(identifier, callback)
    if not IsDuplicityVersion() then
        print('[pf-policemdt] ERROR: PFMdt.Billing.FetchInvoices can only be called server-side')
        if callback then callback({}) end
        return
    end

    identifier = tostring(identifier or '')
    if identifier == '' then
        print('[pf-policemdt] ERROR: Invalid identifier for FetchInvoices')
        if callback then callback({}) end
        return
    end

    local billing = normalizeBilling(Config.Billing)

    -- QB-Billing
    if billing == 'qb-billing' then
        -- Implementation depends on qb-billing's database structure
        if callback then callback({}) end
        return
    end

    -- OkOk-Billing
    if billing == 'okok-billing' then
        local invoices = exports['okokBilling']:GetInvoices(identifier) or {}
        if callback then callback(invoices) end
        return
    end

    -- Renewed-Billing
    if billing == 'renewed-billing' then
        local invoices = exports['Renewed-Lib']:getCharges(identifier) or {}
        if callback then callback(invoices) end
        return
    end

    -- Vivum-Billing
    if billing == 'vivum-billing' then
        local invoices = exports['vivum-billing']:getInvoices(identifier) or {}
        if callback then callback(invoices) end
        return
    end

    -- Add custom billing integration here:
    -- if billing == 'custom-billing' then
    --     local invoices = exports['custom-billing']:GetInvoices(identifier) or {}
    --     if callback then callback(invoices) end
    --     return
    -- end

    if callback then callback({}) end
end

--- Pay an invoice
--- @param invoiceId number Invoice ID to pay
--- @param callback function? Optional callback function(success)
function PFMdt.Billing.PayInvoice(invoiceId, callback)
    if not IsDuplicityVersion() then
        print('[pf-policemdt] ERROR: PFMdt.Billing.PayInvoice can only be called server-side')
        if callback then callback(false) end
        return
    end

    invoiceId = tonumber(invoiceId) or 0
    if invoiceId == 0 then
        print('[pf-policemdt] ERROR: Invalid invoiceId for PayInvoice')
        if callback then callback(false) end
        return
    end

    local billing = normalizeBilling(Config.Billing)

    -- QB-Billing
    if billing == 'qb-billing' then
        -- Implementation depends on qb-billing's API
        if callback then callback(false) end
        return
    end

    -- OkOk-Billing
    if billing == 'okok-billing' then
        local success = exports['okokBilling']:PayInvoice(invoiceId)
        if callback then callback(success) end
        return
    end

    -- Renewed-Billing
    if billing == 'renewed-billing' then
        local success = exports['Renewed-Lib']:payCharge(invoiceId)
        if callback then callback(success) end
        return
    end

    -- Vivum-Billing
    if billing == 'vivum-billing' then
        local success = exports['vivum-billing']:payInvoice(invoiceId)
        if callback then callback(success) end
        return
    end

    -- Add custom billing integration here:
    -- if billing == 'custom-billing' then
    --     local success = exports['custom-billing']:PayInvoice(invoiceId)
    --     if callback then callback(success) end
    --     return
    -- end

    if callback then callback(false) end
end

--- Cancel/delete an invoice
--- @param invoiceId number Invoice ID to cancel
--- @param callback function? Optional callback function(success)
function PFMdt.Billing.CancelInvoice(invoiceId, callback)
    if not IsDuplicityVersion() then
        print('[pf-policemdt] ERROR: PFMdt.Billing.CancelInvoice can only be called server-side')
        if callback then callback(false) end
        return
    end

    invoiceId = tonumber(invoiceId) or 0
    if invoiceId == 0 then
        print('[pf-policemdt] ERROR: Invalid invoiceId for CancelInvoice')
        if callback then callback(false) end
        return
    end

    local billing = normalizeBilling(Config.Billing)

    -- QB-Billing
    if billing == 'qb-billing' then
        -- Implementation depends on qb-billing's API
        if callback then callback(false) end
        return
    end

    -- OkOk-Billing
    if billing == 'okok-billing' then
        local success = exports['okokBilling']:DeleteInvoice(invoiceId)
        if callback then callback(success) end
        return
    end

    -- Renewed-Billing
    if billing == 'renewed-billing' then
        local success = exports['Renewed-Lib']:removeCharge(invoiceId)
        if callback then callback(success) end
        return
    end

    -- Vivum-Billing
    if billing == 'vivum-billing' then
        local success = exports['vivum-billing']:cancelInvoice(invoiceId)
        if callback then callback(success) end
        return
    end

    -- Add custom billing integration here:
    -- if billing == 'custom-billing' then
    --     local success = exports['custom-billing']:CancelInvoice(invoiceId)
    --     if callback then callback(success) end
    --     return
    -- end

    if callback then callback(false) end
end

--- Send a fine (immediate payment from player account)
--- @param source number Target player server ID
--- @param amount number Fine amount
--- @param reason string Reason for fine
--- @return boolean success Whether fine was applied successfully
function PFMdt.Billing.SendFine(source, amount, reason)
    if not IsDuplicityVersion() then
        print('[pf-policemdt] ERROR: PFMdt.Billing.SendFine can only be called server-side')
        return false
    end

    source = tonumber(source) or 0
    amount = tonumber(amount) or 0
    reason = tostring(reason or 'Fine')

    if source == 0 or amount <= 0 then
        print('[pf-policemdt] ERROR: Invalid parameters for SendFine')
        return false
    end

    local billing = normalizeBilling(Config.Billing)

    -- QB-Billing
    if billing == 'qb-billing' then
        local Core = PFMdt.GetCore()
        local Player = Core.Functions.GetPlayer(source)
        if Player and Player.Functions then
            Player.Functions.RemoveMoney('bank', amount, reason)
            return true
        end
        return false
    end

    -- OkOk-Billing
    if billing == 'okok-billing' then
        exports['okokBilling']:CreateFine(source, amount, reason)
        return true
    end

    -- Renewed-Billing
    if billing == 'renewed-billing' then
        exports['Renewed-Lib']:addCharge(source, amount, reason)
        return true
    end

    -- Vivum-Billing
    if billing == 'vivum-billing' then
        local Core = PFMdt.GetCore()
        local Player = Core.Functions.GetPlayer(source)
        if not Player then return false end

        local citizenid = Player.PlayerData.citizenid
        if not citizenid then return false end

        exports['vivum-billing']:sendInvoice(citizenid, 'police', {
            amount = amount,
            reason = reason,
            date = os.date('%Y-%m-%d %H:%M:%S')
        })
        return true
    end

    -- Wasabi Banking
    if billing == 'wasabi_banking' then
        local Core = PFMdt.GetCore()
        local Player = Core.Functions.GetPlayer(source)
        if not Player then return false end

        local citizenid = Player.PlayerData.citizenid
        if not citizenid then return false end

        -- Remove money from player's bank account
        -- Parameters: type, accountID, amount, source
        local success = exports['wasabi_banking']:RemoveMoney('bank', citizenid, amount, source)
        return success == true
    end

    -- Add custom billing integration here:
    -- if billing == 'custom-billing' then
    --     exports['custom-billing']:SendFine(source, amount, reason)
    --     return true
    -- end

    if billing ~= 'none' then
        print(('[pf-policemdt] WARNING: Billing system "%s" is not supported'):format(billing))
    end

    return false
end

--- Send a fine with payment plan
--- @param source number Target player server ID
--- @param amount number Fine amount
--- @param reason string Reason for fine
--- @param installments number Number of payment installments
--- @return boolean success Whether fine was created successfully
function PFMdt.Billing.SendFineWithPlan(source, amount, reason, installments)
    if not IsDuplicityVersion() then
        print('[pf-policemdt] ERROR: PFMdt.Billing.SendFineWithPlan can only be called server-side')
        return false
    end

    source = tonumber(source) or 0
    amount = tonumber(amount) or 0
    reason = tostring(reason or 'Fine')
    installments = tonumber(installments) or 1

    if source == 0 or amount <= 0 or installments < 1 then
        print('[pf-policemdt] ERROR: Invalid parameters for SendFineWithPlan')
        return false
    end

    local billing = normalizeBilling(Config.Billing)

    -- QB-Billing (no payment plan support - send full invoice)
    if billing == 'qb-billing' then
        return PFMdt.Billing.SendInvoice(source, amount, reason)
    end

    -- OkOk-Billing
    if billing == 'okok-billing' then
        exports['okokBilling']:CreateInvoiceWithPlan(source, amount, reason, installments)
        return true
    end

    -- Renewed-Billing (no payment plan support - send full invoice)
    if billing == 'renewed-billing' then
        return PFMdt.Billing.SendInvoice(source, amount, reason)
    end

    -- Vivum-Billing
    if billing == 'vivum-billing' then
        local Core = PFMdt.GetCore()
        local Player = Core.Functions.GetPlayer(source)
        if not Player then return false end

        local citizenid = Player.PlayerData.citizenid
        if not citizenid then return false end

        exports['vivum-billing']:sendInvoice(citizenid, 'police', {
            amount = amount,
            reason = reason,
            date = os.date('%Y-%m-%d %H:%M:%S'),
            installments = installments
        })
        return true
    end

    -- Wasabi Banking (no payment plan support - immediate charge)
    if billing == 'wasabi_banking' then
        return PFMdt.Billing.SendFine(source, amount, reason)
    end

    -- Add custom billing integration here:
    -- if billing == 'custom-billing' then
    --     exports['custom-billing']:SendFineWithPlan(source, amount, reason, installments)
    --     return true
    -- end

    if billing ~= 'none' then
        print(('[pf-policemdt] WARNING: Billing system "%s" is not supported'):format(billing))
    end

    return false
end

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║ PRISON INTEGRATION                                                            ║
-- ║ Prison system for inmate management and sentence tracking                    ║
-- ╚════════════════════════════════════════════════════════════════════════════╝
-- Supported scripts:
--   'default'       - Standard QB/ESX jail system
--   'rcore_prison'  - RCore prison system
--   'none'          - Disable prison integration
--
-- ═══════════════════════════════════════════════════════════════════════════════
-- HOW TO ADD A NEW PRISON SYSTEM:
-- ═══════════════════════════════════════════════════════════════════════════════
-- 1. Set Config.Prison in config.lua:
--    Config.Prison = 'custom-prison'
--
-- 2. Add normalization to normalizePrison() function below:
--    if val == 'custom' or val == 'custom-prison' then return 'custom-prison' end
--
-- 3. Add integration in PFMdt.Prison functions:
--    if prison == 'custom-prison' then
--        exports['custom-prison']:SendToPrison(source, time, reason)
--    end
-- ═══════════════════════════════════════════════════════════════════════════════
--
-- REQUIRED: Set this in config.lua
Config.Prison = Config.Prison

-- ═══════════════════════════════════════════════════════════════════════════════
-- PRISON INTEGRATION IMPLEMENTATION
-- ═══════════════════════════════════════════════════════════════════════════════

PFMdt.Prison = PFMdt.Prison or {}

--- Normalize prison name to standardized format
local function normalizePrison(val)
    val = tostring(val or ''):lower()
    if val == 'rcore' or val == 'rcore_prison' or val == 'rcore-prison' then return 'rcore' end
    if val == 'default' or val == 'qb' or val == 'esx' then return 'default' end
    if val == 'none' then return 'none' end
    -- Add custom prison normalization here:
    -- if val == 'custom' or val == 'custom-prison' then return 'custom-prison' end
    return val or 'default'
end

--- Get configured prison script
--- @return string prison script name ('rcore', 'default', etc.)
function PFMdt.Prison.GetScript()
    if not IsDuplicityVersion() then
        print('[pf-policemdt] ERROR: PFMdt.Prison.GetScript can only be called server-side')
        return 'default'
    end
    
    local script = (Config and Config.Sentencing and Config.Sentencing.PrisonScript) or (Config and Config.Prison) or 'default'
    return normalizePrison(script)
end

--- Send player to prison/jail
--- @param source number Target player server ID
--- @param minutes number Jail time in minutes
--- @param reason string Reason for jailing
--- @param officerSource number|nil Officer source ID (for some systems)
--- @return boolean success Whether jail was successful
--- @return string|nil error Error message if failed
function PFMdt.Prison.Jail(source, minutes, reason, officerSource)
    if not IsDuplicityVersion() then
        print('[pf-policemdt] ERROR: PFMdt.Prison.Jail can only be called server-side')
        return false, 'server_only'
    end

    source = tonumber(source) or 0
    minutes = tonumber(minutes) or 0
    reason = tostring(reason or 'Jail Sentence')

    if source == 0 or minutes <= 0 then
        print('[pf-policemdt] ERROR: Invalid parameters for Prison.Jail')
        return false, 'invalid_parameters'
    end

    local prison = PFMdt.Prison.GetScript()

    -- RCore Prison
    if prison == 'rcore' then
        local ok, err = pcall(function()
            exports['rcore_prison']:Jail(source, minutes, reason, officerSource)
        end)
        if not ok then
            print(('[pf-policemdt] ERROR: rcore_prison Jail failed: %s'):format(tostring(err)))
            return false, 'rcore_jail_failed'
        end
        return true, nil
    end

    -- Default (built-in MDT jail or QB/ESX default)
    if prison == 'default' then
        -- Trigger client-side jail handler
        TriggerClientEvent('pf_mdt:client:StartMdtSentence', source, {
            minutes = minutes,
            reason = reason
        })
        return true, nil
    end

    -- Add custom prison integration here:
    -- if prison == 'custom-prison' then
    --     exports['custom-prison']:SendToPrison(source, minutes, reason)
    --     return true, nil
    -- end

    if prison ~= 'none' then
        print(('[pf-policemdt] WARNING: Prison system "%s" is not supported'):format(prison))
    end

    return false, 'unsupported_prison'
end

--- Release player from prison/jail
--- @param source number Target player server ID
--- @param skipTeleport boolean|nil Skip teleport on release
--- @return boolean success Whether unjail was successful
--- @return string|nil error Error message if failed
function PFMdt.Prison.Unjail(source, skipTeleport)
    if not IsDuplicityVersion() then
        print('[pf-policemdt] ERROR: PFMdt.Prison.Unjail can only be called server-side')
        return false, 'server_only'
    end

    source = tonumber(source) or 0
    if source == 0 then
        print('[pf-policemdt] ERROR: Invalid source for Prison.Unjail')
        return false, 'invalid_source'
    end

    local prison = PFMdt.Prison.GetScript()

    -- RCore Prison
    if prison == 'rcore' then
        local ok, err = pcall(function()
            exports['rcore_prison']:Unjail(source, skipTeleport == true)
        end)
        if not ok then
            print(('[pf-policemdt] ERROR: rcore_prison Unjail failed: %s'):format(tostring(err)))
            return false, 'rcore_unjail_failed'
        end
        return true, nil
    end

    -- Default
    if prison == 'default' then
        TriggerClientEvent('pf_mdt:client:EndMdtSentence', source)
        return true, nil
    end

    -- Add custom prison integration here:
    -- if prison == 'custom-prison' then
    --     exports['custom-prison']:ReleasePrisoner(source)
    --     return true, nil
    -- end

    if prison ~= 'none' then
        print(('[pf-policemdt] WARNING: Prison system "%s" is not supported'):format(prison))
    end

    return false, 'unsupported_prison'
end

--- Edit prisoner sentence time
--- @param source number Target player server ID
--- @param minutes number New jail time in minutes
--- @return boolean success Whether edit was successful
--- @return string|nil error Error message if failed
function PFMdt.Prison.EditSentence(source, minutes)
    if not IsDuplicityVersion() then
        print('[pf-policemdt] ERROR: PFMdt.Prison.EditSentence can only be called server-side')
        return false, 'server_only'
    end

    source = tonumber(source) or 0
    minutes = tonumber(minutes) or 0

    if source == 0 or minutes < 0 then
        print('[pf-policemdt] ERROR: Invalid parameters for Prison.EditSentence')
        return false, 'invalid_parameters'
    end

    local prison = PFMdt.Prison.GetScript()

    -- RCore Prison
    if prison == 'rcore' then
        local ok, err = pcall(function()
            exports['rcore_prison']:EditPrisonerSentence(source, minutes)
        end)
        if not ok then
            print(('[pf-policemdt] ERROR: rcore_prison EditSentence failed: %s'):format(tostring(err)))
            return false, 'rcore_edit_failed'
        end
        return true, nil
    end

    -- Default - not typically supported
    if prison == 'default' then
        return false, 'not_supported'
    end

    -- Add custom prison integration here:
    -- if prison == 'custom-prison' then
    --     exports['custom-prison']:UpdateSentence(source, minutes)
    --     return true, nil
    -- end

    return false, 'unsupported_prison'
end

--- Check if player is currently imprisoned
--- @param source number Target player server ID
--- @return boolean isPrisoner Whether player is in prison
function PFMdt.Prison.IsPrisoner(source)
    if not IsDuplicityVersion() then
        print('[pf-policemdt] ERROR: PFMdt.Prison.IsPrisoner can only be called server-side')
        return false
    end

    source = tonumber(source) or 0
    if source == 0 then return false end

    local prison = PFMdt.Prison.GetScript()

    -- RCore Prison
    if prison == 'rcore' then
        local ok, result = pcall(function()
            return exports['rcore_prison']:IsPrisoner(source)
        end)
        if ok then return result == true end
        return false
    end

    -- Default - would need custom implementation
    if prison == 'default' then
        return false
    end

    -- Add custom prison integration here:
    -- if prison == 'custom-prison' then
    --     return exports['custom-prison']:IsInPrison(source)
    -- end

    return false
end

-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║ SOCIETY/MANAGEMENT INTEGRATION                                                ║
-- ║ Job society account management for fines, bonuses, etc.                      ║
-- ╚════════════════════════════════════════════════════════════════════════════╝
-- Supported scripts:
--   'qb-management'   - QB-Core management system
--   'tgg-banking'     - Tebex TGG Banking system
--   'wasabi_banking'  - Wasabi Banking system
--   'database'        - Direct database access (fallback)
--   'none'            - Disable society integration
--
-- ═══════════════════════════════════════════════════════════════════════════════
-- HOW TO ADD A NEW SOCIETY/MANAGEMENT SYSTEM:
-- ═══════════════════════════════════════════════════════════════════════════════
-- 1. Set Config.Management in config.lua:
--    Config.Management = 'custom-management'
--
-- 2. Add integration in PFMdt.Society functions below
-- ═══════════════════════════════════════════════════════════════════════════════
--
-- REQUIRED: Set this in config.lua (optional - auto-detects)
Config.Management = Config.Management

-- ═══════════════════════════════════════════════════════════════════════════════
-- SOCIETY/MANAGEMENT INTEGRATION IMPLEMENTATION
-- ═══════════════════════════════════════════════════════════════════════════════

PFMdt.Society = PFMdt.Society or {}

--- Add money to a society/job account
--- @param jobName string Job name (e.g., 'police', 'ambulance')
--- @param amount number Amount to add
--- @return boolean success Whether money was added
--- @return string|nil error Error message if failed
function PFMdt.Society.AddMoney(jobName, amount)
    if not IsDuplicityVersion() then
        print('[pf-policemdt] ERROR: PFMdt.Society.AddMoney can only be called server-side')
        return false, 'server_only'
    end

    amount = tonumber(amount) or 0
    if amount <= 0 then return true, nil end

    jobName = tostring(jobName or ''):gsub('^%s*(.-)%s*$', '%1')
    if jobName == '' then return false, 'invalid_job_name' end

    -- Try qb-management first
    if GetResourceState('pfm-management') == 'started' then
        local ok, res = pcall(function()
            return exports['pfm-management']:AddMoney(jobName, amount)
        end)
        if ok and (res == nil or res == true) then
            return true, nil
        end
    end

    -- Try tgg-banking
    if GetResourceState('tgg-banking') == 'started' then
        local ok, res = pcall(function()
            return exports['tgg-banking']:AddSocietyMoney(jobName, amount)
        end)
        if ok and res == true then
            return true, nil
        end
        
        -- Try creating account first then adding again
        pcall(function()
            exports['tgg-banking']:CreateBusinessAccount(jobName, 0, jobName)
        end)
        
        local ok2, res2 = pcall(function()
            return exports['tgg-banking']:AddSocietyMoney(jobName, amount)
        end)
        if ok2 and res2 == true then
            return true, nil
        end
    end

    -- Try wasabi_banking
    if GetResourceState('wasabi_banking') == 'started' or GetResourceState('wasabi-banking') == 'started' then
        local ok, res = pcall(function()
            -- AddMoney for society: type='society', accountID=jobName
            return exports['wasabi_banking']:AddMoney('society', jobName, amount)
        end)
        if ok and (res == nil or res == true) then
            return true, nil
        end
    end

    -- Add custom management integration here:
    -- if Config.Management == 'custom-management' then
    --     exports['custom-management']:DepositToSociety(jobName, amount)
    --     return true, nil
    -- end

    -- Fallback to database (requires oxmysql)
    if GetResourceState('oxmysql') == 'started' then
        local ok, res = pcall(function()
            exports.oxmysql:update(
                'INSERT INTO management_funds (job_name, amount) VALUES (?, ?) ON DUPLICATE KEY UPDATE amount = amount + ?',
                { jobName, amount, amount }
            )
        end)
        if ok then return true, nil end
    end

    return false, 'society_unavailable'
end

--- Remove money from a society/job account
--- @param jobName string Job name (e.g., 'police', 'ambulance')
--- @param amount number Amount to remove
--- @return boolean success Whether money was removed
--- @return string|nil error Error message if failed
function PFMdt.Society.RemoveMoney(jobName, amount)
    if not IsDuplicityVersion() then
        print('[pf-policemdt] ERROR: PFMdt.Society.RemoveMoney can only be called server-side')
        return false, 'server_only'
    end

    amount = tonumber(amount) or 0
    if amount <= 0 then return true, nil end

    jobName = tostring(jobName or ''):gsub('^%s*(.-)%s*$', '%1')
    if jobName == '' then return false, 'invalid_job_name' end

    -- Try qb-management first
    if GetResourceState('pfm-management') == 'started' then
        local ok, res = pcall(function()
            return exports['pfm-management']:RemoveMoney(jobName, amount)
        end)
        if ok and (res == nil or res == true) then
            return true, nil
        end
        if ok and res == false then
            return false, 'insufficient_funds'
        end
    end

    -- Try tgg-banking
    if GetResourceState('tgg-banking') == 'started' then
        local ok, res = pcall(function()
            return exports['tgg-banking']:RemoveSocietyMoney(jobName, amount)
        end)
        if ok and res == true then
            return true, nil
        end
        if ok and res == false then
            return false, 'insufficient_funds'
        end
    end

    -- Try wasabi_banking
    if GetResourceState('wasabi_banking') == 'started' or GetResourceState('wasabi-banking') == 'started' then
        local ok, res = pcall(function()
            -- RemoveMoney for society: type='society', accountID=jobName
            return exports['wasabi_banking']:RemoveMoney('society', jobName, amount)
        end)
        if ok and (res == nil or res == true) then
            return true, nil
        end
        if ok and res == false then
            return false, 'insufficient_funds'
        end
    end

    -- Add custom management integration here:
    -- if Config.Management == 'custom-management' then
    --     local success = exports['custom-management']:WithdrawFromSociety(jobName, amount)
    --     return success, (success and nil or 'insufficient_funds')
    -- end

    -- Fallback to database (requires oxmysql)
    if GetResourceState('oxmysql') == 'started' then
        local ok, res = pcall(function()
            local rows = exports.oxmysql:query_scalar(
                'SELECT amount FROM management_funds WHERE job_name = ? LIMIT 1',
                { jobName }
            )
            local currentAmount = tonumber(rows) or 0
            if currentAmount < amount then
                return false, 'insufficient_funds'
            end
            exports.oxmysql:update(
                'UPDATE management_funds SET amount = amount - ? WHERE job_name = ?',
                { amount, jobName }
            )
            return true, nil
        end)
        if ok and res then return true, nil end
        if ok and not res then return false, 'insufficient_funds' end
    end

    return false, 'society_unavailable'
end

--- Get society/job account balance
--- @param jobName string Job name (e.g., 'police', 'ambulance')
--- @return number|nil balance Account balance or nil if failed
function PFMdt.Society.GetBalance(jobName)
    if not IsDuplicityVersion() then
        print('[pf-policemdt] ERROR: PFMdt.Society.GetBalance can only be called server-side')
        return nil
    end

    jobName = tostring(jobName or ''):gsub('^%s*(.-)%s*$', '%1')
    if jobName == '' then return nil end

    -- Try qb-management first
    if GetResourceState('pfm-management') == 'started' then
        local ok, res = pcall(function()
            return exports['pfm-management']:GetAccount(jobName)
        end)
        if ok and type(res) == 'number' then
            return res
        end
    end

    -- Try tgg-banking
    if GetResourceState('tgg-banking') == 'started' then
        local ok, res = pcall(function()
            return exports['tgg-banking']:GetSocietyBalance(jobName)
        end)
        if ok and type(res) == 'number' then
            return res
        end
    end

    -- Try wasabi_banking
    if GetResourceState('wasabi_banking') == 'started' or GetResourceState('wasabi-banking') == 'started' then
        local ok, res = pcall(function()
            -- Wasabi banking uses GetMoney(type, accountID)
            -- For society accounts: type='society', accountID=jobName
            return exports['wasabi_banking']:GetMoney('society', jobName)
        end)
        if ok and type(res) == 'number' then
            return res
        end
    end

    -- Add custom management integration here:
    -- if Config.Management == 'custom-management' then
    --     return exports['custom-management']:GetSocietyBalance(jobName)
    -- end

    -- Fallback to database
    if GetResourceState('oxmysql') == 'started' then
        local ok, res = pcall(function()
            return exports.oxmysql:query_scalar(
                'SELECT amount FROM management_funds WHERE job_name = ? LIMIT 1',
                { jobName }
            )
        end)
        if ok and type(res) == 'number' then
            return res
        end
    end

    return nil
end

