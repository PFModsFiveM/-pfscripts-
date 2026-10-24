PFMdt = PFMdt or {}

local function normalizeFramework(val)
    val = tostring(val or ''):lower()
    if val == 'qb' or val == 'qb-core' or val == 'qbcore' or val == 'qbc' then return 'qbcore' end
    if val == 'esx' or val == 'es_extended' or val == 'es' then return 'esx' end
    return val
end

local function detectFramework()
    local cfg = Config and Config.Framework or nil
    cfg = normalizeFramework(cfg)
    if cfg == 'qbcore' or cfg == 'esx' then return cfg end

    if GetResourceState then
        if GetResourceState('pfm-core') == 'started' then return 'qbcore' end
        if GetResourceState('es_extended') == 'started' then return 'esx' end
    end

    return 'qbcore'
end

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
            print('[pf-emsmdt] WARNING: ESX selected but could not get shared object yet (es_extended not started?). Will retry.')
        end
        return nil
    end

    if obj then
        PFMdt._esx = obj
    end
    return obj
end

local function splitName(full)
    full = tostring(full or ''):gsub('^%s*(.-)%s*$', '%1')
    if full == '' then return '', '' end
    local first, last = full:match('^(%S+)%s+(.+)$')
    if first then return first, last end
    return full, ''
end

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
                -- ESX other accounts
                return getAccountBalance(account)
            end,
            AddMoney = addMoney,
            RemoveMoney = removeMoney,
            SetJob = function(jobName, grade)
                jobName = tostring(jobName or 'unemployed')
                grade = tonumber(grade) or 0
                if xPlayer.setJob then
                    xPlayer.setJob(jobName, grade)
                    -- best-effort update of our cached PlayerData
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
        print(('[pf-emsmdt] ERROR: ESX.TriggerServerCallback not available for %s'):format(tostring(name)))
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
        print(('[pf-emsmdt] ERROR: ESX.RegisterServerCallback missing for %s'):format(tostring(name)))
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
            print(('[pf-emsmdt] WARNING: Could not register usable item %s yet (ESX not ready?). Will retry from caller.'):format(tostring(itemName)))
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

function PFMdt.GetFrameworkName()
    PFMdt._frameworkName = PFMdt._frameworkName or detectFramework()
    return PFMdt._frameworkName
end

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
        PFMdt._core = exports['pfm-core']:GetCoreObject()
    end

    return PFMdt._core
end

-- ESX: allow server code still using TriggerClientEvent('QBCore:Notify', ...) to work.
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
