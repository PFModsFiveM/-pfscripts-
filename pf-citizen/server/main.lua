-- PF Citizen: exports, start-up and the background work (new bills, reminders, broadcasts, trash).
--
-- Exports for other resources (server side):
--   SendMail(citizenid, { sender, subject, message, senderType = 'person'|'business'|'government'|'system',
--            senderCid, senderAddress, attachments = { { type = 'document', id } | { type = 'bill', ref = 'gov:12' } },
--            button, ref, quiet }) -> mailId | nil, error            (works for offline citizens)
--   SendMailToJob(job, opts, ondutyOnly) -> count                    (ondutyOnly: online and on duty)
--   SendMailToBusiness(businessId, opts) -> count, error             (owner and bosses, pf-government registry)
--   SendMailAs(src, { to, subject, message, attachments, replyTo, draftId }) -> { ok, id, delivered } | { ok = false, error }
--            a player's own mail (the Mail app's send): server identity, rate limit, sent copy, thread
--   SendMailToAll({ sender, senderType, subject, message, ref }) -> ok, ref   (every citizen once, online or later)
--   BroadcastMail(ref, { sender, senderType, subject, message, keepDays }) -> ok   (every citizen once)
--   RemoveBroadcastMail(ref) -> ok
--   SyncGovernmentAnnouncement(announcement) / RemoveGovernmentAnnouncement(id) / SyncGovernmentLaw(law, action)
--            the payloads pf-government sends to pf-computer; also handled from its events directly
--   sendNewMailToOffline(citizenid, { sender, subject, message, button })   (pfm-phone's signature)
--   GetUnreadMail(citizenid) -> number
--   CreateDocument(citizenid, { title, body }) -> documentId | nil, error
--   AddCalendarEvent(scope, owner, { title, description, location, starts, ends, remind }, byName) -> eventId | nil, error

PFCitizen = PFCitizen or {}
local C = PFCitizen
local M, B, D, K = C.Mail, C.Bills, C.Documents, C.Calendar

exports('SendMail', function(cid, opts) return M.Send(cid, opts) end)
exports('SendMailToJob', function(job, opts, ondutyOnly) return M.SendToJob(job, opts, ondutyOnly == true) end)
exports('SendMailToBusiness', function(businessId, opts) return M.SendToBusiness(businessId, opts) end)
exports('SendMailAs', function(src, payload)
    if type(payload) ~= 'table' then return { ok = false, error = 'bad_request' } end
    return M.SendFromPlayer(src, payload)
end)
exports('SendMailToAll', function(mail) return M.SendToAll(mail) end)
exports('BroadcastMail', function(ref, opts) return M.Broadcast(ref, opts) end)
exports('RemoveBroadcastMail', function(ref) return M.RemoveBroadcast(ref) end)
exports('SyncGovernmentAnnouncement', function(a) return M.SyncGovernmentAnnouncement(a) end)
exports('RemoveGovernmentAnnouncement', function(id) return M.RemoveGovernmentAnnouncement(id) end)
exports('SyncGovernmentLaw', function(law, action) return M.SyncGovernmentLaw(law, action) end)
exports('sendNewMailToOffline', function(cid, mail)
    if type(mail) ~= 'table' then return nil, 'bad_request' end
    return M.Send(cid, { sender = mail.sender, subject = mail.subject, message = mail.message, button = mail.button, senderType = 'system' })
end)
exports('GetUnreadMail', function(cid)
    if type(cid) ~= 'string' then return 0 end
    return M.Counts(cid).unread
end)
exports('CreateDocument', function(cid, doc)
    if type(doc) ~= 'table' or not C.Citizen(cid) then return nil, 'bad_request' end
    local title = C.Text(doc.title, CitizenConfig.Documents.MaxTitle)
    if not title then return nil, 'no_title' end
    local id = MySQL.insert.await('INSERT INTO pf_citizen_documents (owner_cid, title, body) VALUES (?, ?, ?)',
        { cid, title, C.Text(doc.body, CitizenConfig.Documents.MaxBody, true) or '' })
    if id then C.Push(cid, 'documents', 'changed', {}) end
    return tonumber(id)
end)
exports('AddCalendarEvent', function(scope, owner, p, byName) return K.AddEvent(scope, owner, p, byName) end)

-- ── events from other resources (server-only: AddEventHandler, never a net event) ─────────

-- pf-government raises these for pf-computer; the citizen mailboxes get the same announcements.
AddEventHandler('pf-computer:gov:announcements:sync', function(payload)
    if type(payload) ~= 'table' then return end
    if payload.action == 'create' or payload.action == 'update' then M.SyncGovernmentAnnouncement(payload.announcement)
    elseif payload.action == 'delete' then M.RemoveGovernmentAnnouncement(payload.announcementId) end
end)

AddEventHandler('pf-computer:gov:laws:sync', function(payload)
    if type(payload) ~= 'table' or type(payload.law) ~= 'table' then return end
    M.SyncGovernmentLaw(payload.law, payload.action)
end)

-- pfm-phone: an invoice was paid or declined (the phone deletes the row; the history keeps it)
AddEventHandler('pfm-phone:server:invoiceSettled', function(invoice, outcome)
    B.RecordSettled(invoice, outcome)
end)

AddEventHandler('QBCore:Server:PlayerLoaded', function(Player)
    local cid = type(Player) == 'table' and Player.PlayerData and Player.PlayerData.citizenid
    if cid then CreateThread(function() M.DeliverBroadcasts(cid) end) end
end)

-- ── start-up ────────────────────────────────────────────────────────

C.ready = false

function C.Start()
    local ok, err = pcall(function() return exports['pfm-core']:RunMigrations(GetCurrentResourceName(), C.Migrations) end)
    if not ok or err == false then
        print('^1[pf-citizen]^7 migrations failed: ' .. tostring(err))
        return false
    end
    C.ready = true
    B.InitWatch()
    C.RegisterApps()
    return true
end

-- A deleted character's private rows go with it. Documents it shared stay for the people they
-- were shared with (a signed contract is theirs too); its signatures on other people's
-- documents stay as part of those documents.
PFCitizen.CharacterCleanupQueries = {
    'DELETE FROM pf_citizen_broadcast_receipts WHERE citizenid = ?',
    'DELETE FROM pf_citizen_document_shares WHERE citizenid = ?',
    [[UPDATE pf_citizen_documents d SET d.deleted_at = NOW() WHERE d.owner_cid = ? AND d.deleted_at IS NULL
        AND NOT EXISTS (SELECT 1 FROM pf_citizen_document_shares s WHERE s.document_id = d.id)]],
    "DELETE FROM pf_citizen_events WHERE scope = 'personal' AND owner = ?",
    'DELETE FROM pf_citizen_event_subs WHERE citizenid = ?',
    'DELETE FROM pf_citizen_event_reminders WHERE citizenid = ?',
    'DELETE FROM pf_citizen_bill_history WHERE citizenid = ?',
}

AddEventHandler('pfm-core:server:characterDeleted', function(citizenid)
    if type(citizenid) ~= 'string' or citizenid == '' then return end
    for _, q in ipairs(PFCitizen.CharacterCleanupQueries) do
        pcall(function() MySQL.query.await(q, { citizenid }) end)
    end
end)

AddEventHandler('onResourceStart', function(resource)
    if resource == GetCurrentResourceName() then
        CreateThread(C.Start)
    elseif resource == 'pf-devices' and C.ready then
        CreateThread(C.RegisterApps)
    end
end)

AddEventHandler('pf-devices:server:ready', function()
    if C.ready then C.RegisterApps() end
end)

local function loop(seconds, fn, label)
    CreateThread(function()
        while true do
            Wait(seconds * 1000)
            if C.ready then
                local ok, err = pcall(fn)
                if not ok then print(('^1[pf-citizen]^7 %s failed: %s'):format(label, tostring(err))) end
            end
        end
    end)
end

loop(CitizenConfig.Bills.PollSeconds, B.Watch, 'bill watch')
loop(CitizenConfig.Calendar.ReminderCheckSeconds, K.Remind, 'reminders')
loop(3600, M.PurgeTrash, 'trash purge')
