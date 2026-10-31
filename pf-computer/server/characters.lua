-- A deleted character (pfm-core raises pfm-core:server:characterDeleted after the delete) leaves no
-- private data in the computer's tables, and nothing other people rely on is lost:
--   deleted   their job applications, lock screen and desktop layouts, dark-web messages, pickup run
--   kept      job posts they wrote for a business (the business still hires through them), the
--             websites they owned (visitors still read them) and the stash points they placed: the row
--             stays, the link to the character is dropped
-- While the tables are still loading at start the clean-up waits for them.

local C = PFComputer
local DB = C.DB
local data = C.dataStore

local GONE_ID, GONE_NAME = 'deleted', 'Former owner'

local function forgetInMemory(cid)
    if data.pickupRuns[cid] then
        data.pickupRuns[cid] = nil
        C.persist('pickup', cid)
    end
    for _, d in ipairs(data.browserDomains) do
        if d.ownerIdentifier == cid then
            d.ownerIdentifier, d.ownerName = GONE_ID, GONE_NAME
            local site = data.browserWebsites[d.domain]
            if type(site) == 'table' and type(site.owner) == 'table' then site.owner.name = GONE_NAME end
            C.persist('domain', d.domain)
        end
    end
    for job, b in pairs(data.businesses) do
        local changed = false
        for _, loc in ipairs(b.stashLocations or {}) do
            if loc.createdBy == cid then loc.createdBy, changed = nil, true end
        end
        if changed then C.persist('business', job) end
    end
    -- their dark-web messages (the handle is a pseudonym of the citizen id)
    local handle = C.chatHandle(cid)
    for _, room in pairs(data.chatRooms) do
        local kept = {}
        for _, m in ipairs(room.messages or {}) do if m.author ~= handle then kept[#kept + 1] = m end end
        room.messages = kept
    end
    for id, item in pairs(DB.dirty) do
        if item.kind == 'chat' and type(item.value) == 'table' and item.value.cid == cid then DB.dirty[id] = nil end
    end
end

local function forgetInDatabase(cid)
    MySQL.query.await('DELETE FROM pf_computer_job_applications WHERE applicant_cid = ?', { cid })
    MySQL.query.await('UPDATE pf_computer_job_applications SET decided_by = NULL WHERE decided_by = ?', { cid })
    MySQL.query.await("UPDATE pf_computer_job_posts SET poster_cid = ?, poster_name = 'Former staff' WHERE poster_cid = ?", { GONE_ID, cid })
    MySQL.query.await('DELETE FROM pf_computer_chat WHERE citizenid = ?', { cid })
    MySQL.query.await('UPDATE pf_computer_chat SET hidden_by = NULL WHERE hidden_by = ?', { cid })
    MySQL.query.await('DELETE FROM pf_computer_pickup_runs WHERE citizenid = ?', { cid })
end

function C.ForgetCharacter(cid)
    if type(cid) ~= 'string' or cid == '' or #cid > 50 then return false end
    forgetInMemory(cid)
    C.ForgetProfiles(cid)
    if DB.mode == 'memory' then return true end
    forgetInDatabase(cid)
    return true
end

AddEventHandler('pfm-core:server:characterDeleted', function(citizenid)
    if type(citizenid) ~= 'string' or citizenid == '' or #citizenid > 50 then return end
    if DB.mode == 'ready' or DB.mode == 'memory' then
        local ok, err = pcall(C.ForgetCharacter, citizenid)
        if not ok then print(('^1[pf-computer]^7 clean-up of deleted character failed: %s'):format(tostring(err))) end
    elseif DB.mode == 'starting' then
        C.onStorageReady[#C.onStorageReady + 1] = function() pcall(C.ForgetCharacter, citizenid) end
    end
end)
