-- The four citizen apps on pf-devices (tablet and computer). Handlers run with the player's real
-- id after pf-devices checked access; each one still checks ownership itself.

PFCitizen = PFCitizen or {}
local C = PFCitizen

local APPS = {
    { id = 'mail', name = 'Mail', icon = '✉️', entry = 'html/apps/mail.js', order = 2,
      description = 'Your mailbox: the same mail as on your phone', window = { width = 960, height = 640 } },
    { id = 'bills', name = 'Bills', icon = '🧾', entry = 'html/apps/bills.js', order = 3,
      description = 'Every bill and fine you owe, paid in one place', window = { width = 860, height = 620 } },
    { id = 'documents', name = 'Documents', icon = '📄', entry = 'html/apps/documents.js', order = 4,
      description = 'Write, share and sign documents and contracts', window = { width = 940, height = 640 } },
    { id = 'calendar', name = 'Calendar', icon = '📅', entry = 'html/apps/calendar.js', order = 5,
      description = 'Your events, city events and events at work', window = { width = 900, height = 640 } },
}

function C.RegisterApps()
    if not C.Started('pf-devices') then return end
    local devices = exports['pf-devices']
    for _, app in ipairs(APPS) do
        devices:RegisterApp({
            id = app.id, name = app.name, icon = app.icon, entry = app.entry, styles = { 'html/apps/citizen.css' },
            devices = { 'tablet', 'computer' }, category = 'apps', order = app.order, access = { anyone = true },
            window = app.window, description = app.description,
        })
    end

    local M, B, D, K = C.Mail, C.Bills, C.Documents, C.Calendar
    devices:RegisterAppHandlers('mail', {
        list = function(src, p) return M.List(src, p) end,
        get = function(src, p) return M.Get(src, p) end,
        send = function(src, p) return M.SendFromPlayer(src, p) end,
        saveDraft = function(src, p) return M.SaveDraft(src, p) end,
        markRead = function(src, p) return M.MarkRead(src, p) end,
        delete = function(src, p) return M.Delete(src, p) end,
        restore = function(src, p) return M.Restore(src, p) end,
        emptyTrash = function(src) return M.EmptyTrash(src) end,
        addressBook = function(src) return M.AddressBook(src) end,
        documents = function(src) return D.List(src) end,
    })
    devices:RegisterAppHandlers('bills', {
        list = function(src) return B.List(src) end,
        pay = function(src, p) return B.Pay(src, p) end,
        decline = function(src, p) return B.Decline(src, p) end,
    })
    devices:RegisterAppHandlers('documents', {
        list = function(src) return D.List(src) end,
        get = function(src, p) return D.Get(src, p) end,
        save = function(src, p) return D.Save(src, p) end,
        delete = function(src, p) return D.Delete(src, p) end,
        share = function(src, p) return D.Share(src, p) end,
        unshare = function(src, p) return D.Unshare(src, p) end,
        sign = function(src, p) return D.Sign(src, p) end,
        addressBook = function(src) return M.AddressBook(src) end,
    })
    devices:RegisterAppHandlers('calendar', {
        list = function(src, p) return K.List(src, p) end,
        create = function(src, p) return K.Create(src, p) end,
        update = function(src, p) return K.Update(src, p) end,
        cancel = function(src, p) return K.Cancel(src, p) end,
        subscribe = function(src, p) return K.Subscribe(src, p) end,
    })
end
