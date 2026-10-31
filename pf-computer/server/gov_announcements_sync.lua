-- City Hall announcements -> every citizen's Mail.
-- pf-government raises 'pf-computer:gov:announcements:sync' (server-only, with TriggerEvent) when an
-- announcement is created, updated or deleted. A new announcement is mailed through pf-citizen to every
-- character, online or not (PFComputerMailEveryone in main.lua). Updates and deletions are not
-- mailed again: delivered mail stays as it was, and the announcement itself is current on
-- los-santos.gov and in the government announcements app.
-- (This used to write emails into the computer's data file, only for mailboxes that already had mail,
-- and no app ever showed them.)

local mailed = {}   -- announcement id -> true, so a repeated 'create' is not mailed twice in a session

AddEventHandler('pf-computer:gov:announcements:sync', function(payload)
    if type(payload) ~= 'table' or payload.action ~= 'create' then return end
    local a = payload.announcement
    if type(a) ~= 'table' or a.id == nil then return end
    local id = tostring(a.id)
    if mailed[id] then return end
    mailed[id] = true

    local title = type(a.title) == 'string' and a.title:sub(1, 100) or 'Government Announcement'
    local body = a.body or a.content
    body = type(body) == 'string' and body:sub(1, 4000) or ''
    if type(PFComputerMailEveryone) == 'function' then
        PFComputerMailEveryone({
            sender = 'City Hall', senderType = 'government',
            subject = '[City Hall] ' .. title,
            message = body,
        })
    end
end)
