-- =====================================================
-- PF GOVERNMENT - CIVIL SERVICES (merged from pfm-cityhall)
-- =====================================================
-- ID card / license issuance (physical items via pfm-inventory), job center,
-- driving school hookup and starter items. Legacy 'qb-cityhall:*' event and
-- callback names are kept so other resources keep working unchanged.

if not Config.CivilServices or not Config.CivilServices.Enabled then
    return
end

-- Safety: if the deprecated pfm-cityhall resource is still running it already
-- registers these events; skip to avoid double item issuance.
if GetResourceState('pfm-cityhall') == 'started' then
    print('^3[PF-GOVERNMENT]^7 pfm-cityhall is still running - civil services module disabled to avoid duplicate events. Remove pfm-cityhall from your server.cfg.')
    return
end

local Civil = Config.CivilServices
local availableJobs = Civil.AvailableJobs

-- =====================================================
-- EXPORTS
-- =====================================================

-- Same export the old cityhall offered: lets other resources add jobs to the
-- job center at runtime. exports['pf-government']:AddCityJob(name, { label = ..., isManaged = ... })
local function AddCityJob(jobName, toCH)
    if availableJobs[jobName] then return false, 'already added' end
    availableJobs[jobName] = {
        label = toCH.label,
        isManaged = toCH.isManaged
    }
    return true, 'success'
end

exports('AddCityJob', AddCityJob)

-- =====================================================
-- ITEM METADATA (exact shape other scripts rely on, e.g. .info.citizenid)
-- =====================================================

local function buildDocumentInfo(Player, item)
    local charinfo = Player.PlayerData.charinfo
    local info = {}
    if item == 'id_card' then
        info.citizenid = Player.PlayerData.citizenid
        info.firstname = charinfo.firstname
        info.lastname = charinfo.lastname
        info.birthdate = charinfo.birthdate
        info.gender = charinfo.gender
        info.nationality = charinfo.nationality
    elseif item == 'driver_license' then
        info.firstname = charinfo.firstname
        info.lastname = charinfo.lastname
        info.birthdate = charinfo.birthdate
        info.type = 'Class C Driver License'
    elseif item == 'weaponlicense' then
        info.firstname = charinfo.firstname
        info.lastname = charinfo.lastname
        info.birthdate = charinfo.birthdate
    else
        return nil
    end
    return info
end

-- Server-only: starter documents for a player (another server script passes the player). The
-- 'getIDs' events were network events with no checks, so any client could ask for a free phone, ID
-- card and driver license as often as it liked (pfm-multicharacter gives new characters their items).
local function giveStarterItems(target)
    local src = tonumber(target)
    if not src then return end
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player then return end
    for _, v in pairs(QBCore.Shared.StarterItems) do
        local info = buildDocumentInfo(Player, v.item) or {}
        exports['pfm-inventory']:AddItem(src, v.item, 1, false, info, 'qb-cityhall:giveStarterItems')
    end
end

-- =====================================================
-- CALLBACKS (legacy qb-cityhall names kept)
-- =====================================================

QBCore.Functions.CreateCallback('qb-cityhall:server:receiveJobs', function(_, cb)
    cb(availableJobs)
end)

QBCore.Functions.CreateCallback('qb-cityhall:server:getIdentityData', function(source, cb, hallId)
    local Player = QBCore.Functions.GetPlayer(source)
    if not Player then return cb({}) end

    local hall = Civil.Cityhalls[hallId]
    if not hall then return cb({}) end

    local licensesMeta = Player.PlayerData.metadata['licences'] or {}
    local availableLicenses = {}

    for license, data in pairs(hall.licenses) do
        if not data.metadata or licensesMeta[data.metadata] then
            availableLicenses[license] = data
        end
    end

    cb(availableLicenses)
end)

-- =====================================================
-- EVENTS (legacy qb-cityhall names kept)
-- =====================================================

RegisterNetEvent('qb-cityhall:server:requestId', function(item, hall)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player then return end
    local hallData = Civil.Cityhalls[hall]
    if not hallData then return end
    local itemInfo = hallData.licenses[item]
    if not itemInfo then return end
    local info = buildDocumentInfo(Player, item)
    if not info then return end
    -- paid through the pfm-banking ledger; refunded when the document cannot be handed over (the
    -- fee used to be kept even when the inventory was full)
    local key = ('pf-government:id:%s:%s'):format(Player.PlayerData.citizenid, PFPayout.NewId())
    if not PFPayout.Charge(Player, 'cash', itemInfo.cost, { key = key, kind = 'fee', reason = 'City hall: ' .. tostring(item), quiet = true }) then
        return NotifyPlayer(src, ('You don\'t have enough money on you, you need %s cash'):format(itemInfo.cost), 'error')
    end
    if not exports['pfm-inventory']:AddItem(src, item, 1, false, info, 'qb-cityhall:server:requestId') then
        PFPayout.Pay(Player, 'cash', itemInfo.cost, { key = key .. ':refund', kind = 'refund', reason = 'City hall: not handed over' })
        return
    end
    TriggerClientEvent('qb-inventory:client:ItemBox', src, QBCore.Shared.Items[item], 'add')
    DebugPrint('Civil document issued: ' .. item .. ' to ' .. Player.PlayerData.citizenid)
end)

-- Only configured instructors are mailed (the client sends the list, so any citizen could be
-- mailed), at most once a minute per player.
local driverTestSentAt = {}
local function isInstructor(citizenid)
    for _, school in ipairs(Civil.DrivingSchools or {}) do
        for _, cid in ipairs(school.instructors or {}) do
            if cid == citizenid then return true end
        end
    end
    return false
end

RegisterNetEvent('qb-cityhall:server:sendDriverTest', function(instructors)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player then return end
    if type(instructors) ~= 'table' then return end
    if driverTestSentAt[src] and os.time() - driverTestSentAt[src] < 60 then return end
    driverTestSentAt[src] = os.time()
    local targets, seen = {}, {}
    for i = 1, math.min(#instructors, 20) do
        local cid = instructors[i]
        if type(cid) == 'string' and not seen[cid] and isInstructor(cid) then
            seen[cid] = true
            targets[#targets + 1] = cid
        end
    end
    for i = 1, #targets do
        local citizenid = targets[i]
        local SchoolPlayer = QBCore.Functions.GetPlayerByCitizenId(citizenid)
        if SchoolPlayer then
            TriggerClientEvent('qb-cityhall:client:sendDriverEmail', SchoolPlayer.PlayerData.source, Player.PlayerData.charinfo)
        else
            local mailData = {
                sender = 'Township',
                subject = 'Driving lessons request',
                message = 'Hello,<br><br>We have just received a message that someone wants to take driving lessons.<br>If you are willing to teach, please contact them:<br>Name: <strong>' .. Player.PlayerData.charinfo.firstname .. ' ' .. Player.PlayerData.charinfo.lastname .. '<br />Phone Number: <strong>' .. Player.PlayerData.charinfo.phone .. '</strong><br><br>Kind regards,<br>Township Los Santos',
                button = {}
            }
            exports['pfm-phone']:sendNewMailToOffline(citizenid, mailData)
        end
    end
    NotifyPlayer(src, 'An email has been sent to driving schools, and you will be contacted automatically', 'success')
end)

RegisterNetEvent('qb-cityhall:server:ApplyJob', function(job, cityhallCoords)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player then return end
    local pedCoords = GetEntityCoords(GetPlayerPed(src))

    -- at a configured city hall (the client used to send the coordinates to compare with)
    local atHall = false
    for _, hall in ipairs(Civil.Cityhalls or {}) do
        if hall.coords and #(pedCoords - vector3(hall.coords.x, hall.coords.y, hall.coords.z)) < 20.0 then
            atHall = true
            break
        end
    end
    if not atHall or type(job) ~= 'string' or not availableJobs[job] then
        return
    end

    local JobInfo = QBCore.Shared.Jobs[job]
    if not JobInfo then return end
    Player.Functions.SetJob(job, 0)
    NotifyPlayer(src, ('Congratulations with your new job! (%s)'):format(JobInfo.label), 'success')
end)

AddEventHandler('qb-cityhall:server:getIDs', giveStarterItems)

-- pf-government aliases (forward to the same implementations)
RegisterNetEvent('pf-government:server:requestId', function(item, hall)
    TriggerEvent('qb-cityhall:server:requestId', item, hall)
end)

RegisterNetEvent('pf-government:server:applyJob', function(job, cityhallCoords)
    TriggerEvent('qb-cityhall:server:ApplyJob', job, cityhallCoords)
end)

RegisterNetEvent('pf-government:server:sendDriverTest', function(instructors)
    TriggerEvent('qb-cityhall:server:sendDriverTest', instructors)
end)

AddEventHandler('pf-government:server:getIDs', giveStarterItems)

-- =====================================================
-- COMMANDS
-- =====================================================

QBCore.Commands.Add('drivinglicense', 'Give a drivers license to someone', { { name = 'id', help = 'ID of a person' } }, true, function(source, args)
    local Player = QBCore.Functions.GetPlayer(source)
    local SearchedPlayer = QBCore.Functions.GetPlayer(tonumber(args[1]))
    if not Player then return end
    if SearchedPlayer then
        if not SearchedPlayer.PlayerData.metadata['licences']['driver'] then
            for i = 1, #Civil.DrivingSchools do
                local school = Civil.DrivingSchools[i]
                for id = 1, #school.instructors do
                    if school.instructors[id] == Player.PlayerData.citizenid then
                        SearchedPlayer.PlayerData.metadata['licences']['driver'] = true
                        SearchedPlayer.Functions.SetMetaData('licences', SearchedPlayer.PlayerData.metadata['licences'])
                        NotifyPlayer(SearchedPlayer.PlayerData.source, 'You have passed! Pick up your drivers license at the town hall', 'success')
                        NotifyPlayer(source, ('Player with ID %s has been granted access to a driving license'):format(SearchedPlayer.PlayerData.source), 'success')
                        break
                    end
                end
            end
        else
            NotifyPlayer(source, "Can't give permission for a drivers license, this person already has permission", 'error')
        end
    else
        NotifyPlayer(source, 'Player Not Online', 'error')
    end
end)

print('^2[PF-GOVERNMENT]^7 Civil services (cityhall) server loaded')
