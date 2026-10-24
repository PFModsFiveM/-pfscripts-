-- =====================================================
-- PF-COMPUTER & PF-GOVERNMENT ANNOUNCEMENTS SYNC
-- Automatically syncs government announcements to emails
-- =====================================================

local SYNC_ENABLED = true
local ANNOUNCEMENT_EMAIL_MAILBOX = 'announcements@los-santos.gov'
local SYNC_CHECK_INTERVAL = 30000 -- Check for updates every 30 seconds

-- Initialize announcement sync data in memory
local announcementEmailMap = {} -- Maps announcement ID to email ID for tracking

-- Helper: Create or update announcement email
local function syncAnnouncementToEmail(announcementData)
    local data = loadData()
    
    if not announcementData or not announcementData.id then
        return false
    end
    
    local announcementId = tostring(announcementData.id)
    local title = announcementData.title or 'Government Announcement'
    local body = announcementData.body or announcementData.content or ''
    local author = announcementData.author or announcementData.created_by_name or 'Government'
    local createdAt = announcementData.created_at or announcementData.createdAt or nowIso()
    
    -- Check if we already have an email for this announcement
    local existingEmailId = nil
    for i, email in ipairs(data.emails) do
        -- Look for emails with matching announcement ID in metadata
        if email.metadata and email.metadata.gov_announcement_id == announcementId then
            existingEmailId = email.id
            -- Update existing email
            email.subject = '[City Hall] ' .. title
            email.body = body
            email.preview = string.sub(body, 1, 120)
            email.time = createdAt
            email.unread = false -- Keep as read if updating
            break
        end
    end
    
    -- If no existing email, create new one
    if not existingEmailId then
        -- Send to all mailboxes that should receive announcements
        local mailboxes = {}
        
        -- Add all government mailboxes
        for _, email in ipairs(data.emails) do
            if email.mailbox and email.mailbox:find('@los-santos.gov') then
                if not mailboxes[email.mailbox] then
                    mailboxes[email.mailbox] = true
                end
            end
        end
        
        -- If no government mailboxes, add the main announcements mailbox
        if not next(mailboxes) then
            mailboxes[ANNOUNCEMENT_EMAIL_MAILBOX] = true
        end
        
        -- Create email for each mailbox
        for mailbox, _ in pairs(mailboxes) do
            local newEmailId = nextId('emails')
            local emailEntry = {
                id = newEmailId,
                mailbox = mailbox,
                folder = 'inbox',
                from = author,
                to = mailbox,
                subject = '[City Hall] ' .. title,
                body = body,
                preview = string.sub(body, 1, 120),
                time = createdAt,
                unread = true,
                threadId = newEmailId,
                metadata = {
                    gov_announcement_id = announcementId,
                    gov_announcement = true,
                    priority = announcementData.priority or 'normal'
                }
            }
            data.emails[#data.emails + 1] = emailEntry
        end
        
        existingEmailId = nextId('emails')
    end
    
    announcementEmailMap[announcementId] = existingEmailId
    saveData()
    
    return true, existingEmailId
end

-- Helper: Remove announcement email
local function removeAnnouncementEmail(announcementId)
    local data = loadData()
    announcementId = tostring(announcementId)
    
    local modified = false
    for i = #data.emails, 1, -1 do
        local email = data.emails[i]
        if email.metadata and email.metadata.gov_announcement_id == announcementId then
            table.remove(data.emails, i)
            modified = true
        end
    end
    
    if modified then
        saveData()
    end
    
    announcementEmailMap[announcementId] = nil
    return modified
end

-- =====================================================
-- EVENT HANDLERS
-- =====================================================

-- Listen for government announcements. Server-only: pf-government raises it with TriggerEvent (as a
-- net event any client could create, edit or delete City Hall mail).
AddEventHandler('pf-computer:gov:announcements:sync', function(payload)
    if not SYNC_ENABLED or not payload then
        return
    end
    
    if payload.action == 'create' or payload.action == 'update' then
        syncAnnouncementToEmail(payload.announcement)
    elseif payload.action == 'delete' then
        removeAnnouncementEmail(payload.announcementId)
    end
end)

-- The 'pf-computer:announcements:create' net event that was here took a title, body and author from
-- any client with no checks; nothing used it, so it is gone.

-- =====================================================
-- EXPORT FUNCTIONS
-- =====================================================

-- Allow other scripts to trigger announcement sync
function SyncGovernmentAnnouncement(announcementData)
    syncAnnouncementToEmail(announcementData)
end

function RemoveGovernmentAnnouncement(announcementId)
    removeAnnouncementEmail(announcementId)
end

-- =====================================================
-- LIVE SYNC CHECK (Optional - for MySQL-backed systems)
-- =====================================================

-- If you want automatic syncing from pf-government database
function EnableLiveAnnouncementSync()
    if not SYNC_ENABLED then
        return
    end
    
    CreateThread(function()
        while SYNC_ENABLED do
            Wait(SYNC_CHECK_INTERVAL)
            
            local data = loadData()
            
            -- Check if pf-government resource is running
            if GetResourceState('pf-government') == 'started' then
                -- Try to get announcements from pf-government
                local success, announcements = pcall(function()
                    return exports['pf-government']:GetActiveAnnouncements()
                end)
                
                if success and announcements then
                    for _, announcement in ipairs(announcements) do
                        syncAnnouncementToEmail(announcement)
                    end
                end
            end
        end
    end)
end

print('^2[PF-COMPUTER]^7 Government announcements sync loaded')

