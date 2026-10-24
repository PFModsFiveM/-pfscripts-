-- ============================================================================
-- PF Police MDT - Server Item Handler
-- ============================================================================
-- Registers the mdt item and triggers client-side open when used

local Core = PFMdt.GetCore()

local function notifyNoPermission(src)
    -- Works for both QBCore and ESX (client has an ESX shim for QBCore:Notify).
    TriggerClientEvent('QBCore:Notify', src, "You don't have permission to use this device.", 'error')
end

local function refreshESXInventoryUsableFlag(itemName)
    itemName = tostring(itemName or '')
    if itemName == '' then return end

    local ESX = nil
    pcall(function()
        if exports and exports['es_extended'] and exports['es_extended'].getSharedObject then
            ESX = exports['es_extended']:getSharedObject()
        end
    end)

    if not ESX then
        TriggerEvent('esx:getSharedObject', function(o) ESX = o end)
        local timeoutAt = GetGameTimer() + 2000
        while not ESX and GetGameTimer() < timeoutAt do
            Wait(25)
        end
    end

    if not ESX or not ESX.GetExtendedPlayers then
        return
    end

    local xPlayers = ESX.GetExtendedPlayers()
    for i = 1, #xPlayers do
        local xPlayer = xPlayers[i]
        if xPlayer and xPlayer.inventory and xPlayer.source then
            local updated = false
            for j = 1, #xPlayer.inventory do
                local it = xPlayer.inventory[j]
                if it and it.name == itemName then
                    if it.usable ~= true then
                        it.usable = true
                        updated = true
                    end
                    break
                end
            end
            if updated then
                TriggerClientEvent('esx:setInventory', xPlayer.source, xPlayer.inventory)
            end
        end
    end
end

local function openCitationPaperWithLatestStatus(src, info)
    local citationInfo = (type(info) == 'table') and info or {}

    local function resolveSentenceId(payload)
        if type(payload) ~= 'table' then return 0 end

        local id = tonumber(payload.sentenceId or payload.sentenceID or payload.sentence_id or payload.sentence)
        if id and id > 0 then return math.floor(id) end

        local nestedInfo = payload.info
        if type(nestedInfo) == 'table' then
            id = tonumber(nestedInfo.sentenceId or nestedInfo.sentenceID or nestedInfo.sentence_id or nestedInfo.sentence)
            if id and id > 0 then return math.floor(id) end
        end

        local metadata = payload.metadata
        if type(metadata) == 'table' then
            id = tonumber(metadata.sentenceId or metadata.sentenceID or metadata.sentence_id or metadata.sentence)
            if id and id > 0 then return math.floor(id) end
        end

        return 0
    end

    local sentenceId = resolveSentenceId(citationInfo)

    if sentenceId <= 0 or not (exports and exports.oxmysql) then
        TriggerClientEvent('pf-policemdt:client:OpenCitationPaper', src, citationInfo)
        return
    end

    exports.oxmysql:execute(
        'SELECT fineSuccess FROM pf_mdt_sentences WHERE id = ? LIMIT 1',
        { sentenceId },
        function(rows)
            local row = rows and rows[1] or nil
            if row then
                local fineSuccess = tonumber(row.fineSuccess)
                if fineSuccess == nil then
                    local raw = tostring(row.fineSuccess or ''):lower()
                    if raw == 'true' or raw == 'paid' or raw == 'success' or raw == '1' then
                        fineSuccess = 1
                    else
                        fineSuccess = 0
                    end
                end
                citationInfo.finePaid = fineSuccess == 1
                citationInfo.fineSuccess = fineSuccess
            end
            TriggerClientEvent('pf-policemdt:client:OpenCitationPaper', src, citationInfo)
        end
    )
end

-- Register the MDT item as usable (QBCore via CreateUseableItem, ESX via RegisterUsableItem through compat).
CreateThread(function()
    if not Config or not Config.Item or Config.Item.Enabled ~= true then
        return
    end

    local itemName = tostring(Config.Item.Name or 'mdt')
    if itemName == '' then itemName = 'mdt' end

    if not Core or not Core.Functions or not Core.Functions.CreateUseableItem then
        print('[pf-policemdt] ERROR: Core.Functions.CreateUseableItem missing; cannot register MDT item')
        return
    end

    local fw = (PFMdt.GetFrameworkName and PFMdt.GetFrameworkName()) or 'qbcore'
    local maxWaitMs = (fw == 'esx') and 60000 or 0
    local startedAt = GetGameTimer()

    while true do
        local ok, registered = pcall(function()
            return Core.Functions.CreateUseableItem(itemName, function(source, _item)
                local src = tonumber(source) or 0
                local Player = Core.Functions.GetPlayer(src)

                local jobName = Player and Player.PlayerData and Player.PlayerData.job and Player.PlayerData.job.name or nil
                if jobName and Config.AllowedJobs and Config.AllowedJobs[jobName] then
                    TriggerClientEvent('pf-policemdt:client:openMDT', src)
                else
                    notifyNoPermission(src)
                end
            end)
        end)

        -- QBCore doesn't return anything; assume success if no error.
        if fw ~= 'esx' then
            if ok then
                print(('[pf-policemdt] Registered usable item (qbcore): %s'):format(itemName))
            else
                print(('[pf-policemdt] ERROR: Failed registering usable item (qbcore): %s'):format(itemName))
            end
            break
        end

        -- ESX compat returns true/false.
        if ok and registered == true then
            print(('[pf-policemdt] Registered usable item (esx): %s'):format(itemName))
            -- ESX inventories cache the `usable` flag in PlayerData.inventory.
            -- If we registered after a player already loaded, push an update so "Use" shows up without relog.
            refreshESXInventoryUsableFlag(itemName)
            break
        end

        if GetGameTimer() - startedAt > maxWaitMs then
            print(('[pf-policemdt] ERROR: Timed out registering usable item (esx): %s'):format(itemName))
            break
        end

        Wait(1000)
    end
end)

-- Register citation paper as usable for all players.
CreateThread(function()
    if not Core or not Core.Functions or not Core.Functions.CreateUseableItem then
        return
    end

    local itemName = 'citation_paper'

    local ok, err = pcall(function()
        Core.Functions.CreateUseableItem(itemName, function(source, item)
            local src = tonumber(source) or 0
            if src <= 0 then return end

            local info = {}
            if item and type(item.info) == 'table' then
                info = item.info
            elseif item and type(item.metadata) == 'table' then
                info = item.metadata
            end

            openCitationPaperWithLatestStatus(src, info)
        end)
    end)

    if not ok then
        print(('[pf-policemdt] ERROR: Failed registering usable item (%s): %s'):format(itemName, tostring(err)))
    else
        print(('[pf-policemdt] Registered usable item: %s'):format(itemName))
    end
end)
