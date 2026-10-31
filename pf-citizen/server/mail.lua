-- Mail: one mailbox per citizen in `player_mails` (the phone's table), shown by the phone, the
-- tablet and the computer. Folders: inbox, sent, drafts, trash. Every copy of a conversation shares
-- a `thread` key; the sender keeps a copy in sent.
--
-- Other resources send with the exports in main.lua (SendMail, SendMailToJob, SendMailToBusiness,
-- BroadcastMail). Players send from the Mail app: the sender name, citizen id and reply address
-- are always the server's, never the client's.

PFCitizen = PFCitizen or {}
PFCitizen.Mail = PFCitizen.Mail or {}
local C = PFCitizen
local M = PFCitizen.Mail
local CFG = CitizenConfig.Mail

local SENDER_TYPES = { person = true, business = true, government = true, system = true }
local FOLDERS = { inbox = true, sent = true, drafts = true, trash = true }

local COLUMNS = 'id, sender, subject, message, `read`, folder, thread, sender_type, sender_cid, sender_address, recipients, attachments, UNIX_TIMESTAMP(`date`) AS at'

local function newThread() return ('t%d%06d'):format(os.time(), math.random(0, 999999)) end

local function decodeJson(s)
    if type(s) ~= 'string' or s == '' then return nil end
    local ok, v = pcall(json.decode, s)
    return ok and v or nil
end

--- A mail row as the apps see it.
local function view(r, full)
    local out = {
        id = tonumber(r.id), sender = r.sender, subject = r.subject, read = tonumber(r.read) == 1,
        folder = r.folder or 'inbox', thread = r.thread, senderType = r.sender_type or 'system',
        mine = r.sender_cid ~= nil and r.sender_cid == r.__me or nil,
        replyTo = r.sender_address, recipients = r.recipients, at = tonumber(r.at),
        attachments = decodeJson(r.attachments) or {},
    }
    local msg = tostring(r.message or '')
    if full then out.message = msg else out.preview = C.Cut(msg:gsub('%s+', ' '), 140) end
    return out
end

--- Validates attachments: documents by id, and bills (server senders only) by key such as gov:12.
function M.CleanAttachments(list, allowBills)
    if list == nil then return {} end
    if type(list) ~= 'table' then return nil, 'bad_attachments' end
    local out = {}
    for i, a in ipairs(list) do
        if i > CFG.MaxAttachments then return nil, 'too_many_attachments' end
        if type(a) ~= 'table' then return nil, 'bad_attachments' end
        if a.type == 'document' then
            local id = C.Int(a.id or a.ref, 1)
            if not id then return nil, 'bad_attachments' end
            out[#out + 1] = { type = 'document', ref = tostring(id), title = C.Text(a.title, 120) or ('Document #' .. id) }
        elseif a.type == 'bill' and allowBills then
            local key = C.Token(a.ref or a.key, 40)
            if not key or not key:match('^%a+:%d+$') then return nil, 'bad_attachments' end
            out[#out + 1] = { type = 'bill', ref = key, title = C.Text(a.title, 120) or 'Bill' }
        else
            return nil, 'bad_attachments'
        end
    end
    return out
end

--- Stores one mail row. Returns the new id, or nil (a duplicate ref inserts nothing).
function M.Insert(cid, m)
    local attachments = (m.attachments and #m.attachments > 0) and json.encode(m.attachments) or nil
    local sql = ('INSERT %s INTO player_mails (`citizenid`, `sender`, `subject`, `message`, `mailid`, `read`, `button`, `folder`, `thread`, `sender_type`, `sender_cid`, `sender_address`, `recipients`, `attachments`, `ref`) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)')
        :format(m.ref and 'IGNORE' or '')
    local id = MySQL.insert.await(sql, {
        cid, m.sender, m.subject, m.message, math.random(100000, 999999), m.read and 1 or 0, m.button,
        m.folder or 'inbox', m.thread, m.senderType or 'system', m.senderCid, m.senderAddress, m.recipients, attachments, m.ref,
    })
    id = tonumber(id)
    if not id or id < 1 then return nil end
    return id
end

--- Tells the citizen's open devices and phone about a new inbox mail.
local function announce(cid, id, m)
    C.Push(cid, 'mail', 'new', { id = id, sender = m.sender, subject = m.subject, senderType = m.senderType,
        preview = C.Cut(tostring(m.message or ''):gsub('%s+', ' '), 140) })
    if C.Started('pfm-phone') then
        pcall(function() exports['pfm-phone']:RefreshMails(cid, { sender = m.sender, subject = m.subject, message = m.message }) end)
    end
end

--- Delivers to a citizen's inbox (online or not) and announces it. Returns the mail id.
function M.Deliver(cid, m)
    local id = M.Insert(cid, m)
    if id and not m.quiet then announce(cid, id, m) end
    return id
end

--- Server-side send (exports). opts: sender, subject, message, senderType, senderCid, senderAddress,
--- attachments, button, ref (one copy per citizen), quiet. `known` skips the citizen lookup when
--- the id came from the database already.
function M.Send(cid, opts, known)
    if type(cid) ~= 'string' or cid == '' or #cid > 50 or type(opts) ~= 'table' then return nil, 'bad_request' end
    local subject = C.Text(opts.subject, CFG.MaxSubject)
    local message = C.Text(opts.message, CFG.MaxMessage, true)
    if not subject or not message then return nil, 'bad_request' end
    if not known and not C.Citizen(cid) then return nil, 'unknown_recipient' end
    local atts, err = M.CleanAttachments(opts.attachments, true)
    if not atts then return nil, err end
    local button
    if opts.button ~= nil and opts.button ~= '' then
        if type(opts.button) ~= 'table' then return nil, 'bad_request' end
        button = json.encode(opts.button)
        if #button > 2000 then return nil, 'bad_request' end
    end
    local ref = opts.ref ~= nil and C.Token(tostring(opts.ref), 100) or nil
    if opts.ref ~= nil and not ref then return nil, 'bad_request' end
    local m = {
        sender = C.Text(opts.sender, CFG.MaxSender) or 'System', subject = subject, message = message,
        senderType = SENDER_TYPES[opts.senderType] and opts.senderType or 'system',
        senderCid = type(opts.senderCid) == 'string' and C.Token(opts.senderCid, 50) or nil,
        senderAddress = type(opts.senderAddress) == 'string' and C.Token(opts.senderAddress, 120) or nil,
        attachments = atts, button = button, ref = ref, thread = C.Token(opts.thread, 40) or newThread(),
        quiet = opts.quiet == true,
    }
    -- a document attached by a server sender is opened by the recipient through a read-only link
    for _, a in ipairs(atts) do
        if a.type == 'document' and C.Documents then C.Documents.ShareInternal(tonumber(a.ref), cid, m.senderCid or 'system') end
    end
    local id = M.Deliver(cid, m)
    if not id then return nil, ref and 'duplicate' or 'not_stored' end
    return id
end

--- Mails every member of a job: on duty and online only, or everyone employed there.
function M.SendToJob(job, opts, ondutyOnly)
    if type(job) ~= 'string' or job == '' or #job > 50 then return 0, 'bad_request' end
    local seen, cids = {}, {}
    local function add(cid) if cid and not seen[cid] then seen[cid] = true; cids[#cids + 1] = cid end end
    for _, P in pairs(C.QB().Functions.GetQBPlayers() or {}) do
        local j = P.PlayerData.job
        if j and j.name == job and (not ondutyOnly or j.onduty) then add(P.PlayerData.citizenid) end
    end
    if not ondutyOnly then
        local rows = MySQL.query.await([[SELECT citizenid FROM players WHERE JSON_UNQUOTE(JSON_EXTRACT(job, '$.name')) = ? LIMIT 300]], { job }) or {}
        for _, r in ipairs(rows) do add(r.citizenid) end
    end
    local sent = 0
    for _, cid in ipairs(cids) do
        if M.Send(cid, opts, true) then sent = sent + 1 end
    end
    return sent
end

--- Mails the owner and bosses of a registered business (pf-government registry).
function M.SendToBusiness(businessId, opts)
    local bosses = C.BusinessBosses(businessId)
    if not bosses then return 0, 'unknown_business' end
    if #bosses == 0 then return 0, 'no_recipients' end
    local sent = 0
    for _, cid in ipairs(bosses) do
        if M.Send(cid, opts, true) then sent = sent + 1 end
    end
    return sent
end

-- ── broadcasts (announcements every citizen gets once) ──────────────

--- Every active broadcast the citizen has not had yet goes into their inbox (on login, on create).
function M.DeliverBroadcasts(cid)
    if type(cid) ~= 'string' then return 0 end
    local rows = MySQL.query.await([[SELECT b.id, b.ref, b.sender, b.sender_type, b.subject, b.message
        FROM pf_citizen_mail_broadcasts b
        LEFT JOIN pf_citizen_broadcast_receipts r ON r.broadcast_id = b.id AND r.citizenid = ?
        WHERE r.broadcast_id IS NULL AND b.active = 1 AND (b.expires_at IS NULL OR b.expires_at > NOW())
        ORDER BY b.id LIMIT 20]], { cid }) or {}
    local n = 0
    for _, b in ipairs(rows) do
        -- the receipt is the claim: two deliveries racing store one copy
        local claimed = MySQL.update.await('INSERT IGNORE INTO pf_citizen_broadcast_receipts (broadcast_id, citizenid) VALUES (?, ?)', { b.id, cid })
        if C.Affected(claimed) > 0 then
            if M.Deliver(cid, { sender = b.sender, subject = b.subject, message = b.message, senderType = b.sender_type,
                ref = 'bc:' .. b.ref, thread = 'bc' .. b.id }) then n = n + 1 end
        end
    end
    return n
end

--- Creates or updates a broadcast. Copies already delivered are updated in place.
function M.Broadcast(ref, opts)
    ref = C.Token(ref, 90)
    if not ref or type(opts) ~= 'table' then return false, 'bad_request' end
    local subject = C.Text(opts.subject, CFG.MaxSubject)
    local message = C.Text(opts.message, CFG.MaxMessage, true)
    if not subject or not message then return false, 'bad_request' end
    local sender = C.Text(opts.sender, CFG.MaxSender) or 'City Hall'
    local stype = SENDER_TYPES[opts.senderType] and opts.senderType or 'government'
    local days = C.Int(opts.keepDays, 1, 365) or CFG.BroadcastKeepDays
    MySQL.query.await([[INSERT INTO pf_citizen_mail_broadcasts (ref, sender, sender_type, subject, message, active, expires_at)
        VALUES (?, ?, ?, ?, ?, 1, NOW() + INTERVAL ? DAY)
        ON DUPLICATE KEY UPDATE sender = VALUES(sender), sender_type = VALUES(sender_type), subject = VALUES(subject),
            message = VALUES(message), active = 1, expires_at = VALUES(expires_at)]], { ref, sender, stype, subject, message, days })
    MySQL.update.await('UPDATE player_mails SET sender = ?, subject = ?, message = ? WHERE ref = ?', { sender, subject, message, 'bc:' .. ref })
    for _, P in pairs(C.QB().Functions.GetQBPlayers() or {}) do
        M.DeliverBroadcasts(P.PlayerData.citizenid)
    end
    return true
end

--- Withdraws a broadcast: nobody else gets it and the copies leave inboxes.
function M.RemoveBroadcast(ref)
    ref = C.Token(ref, 90)
    if not ref then return false end
    MySQL.update.await('UPDATE pf_citizen_mail_broadcasts SET active = 0 WHERE ref = ?', { ref })
    MySQL.update.await("DELETE FROM player_mails WHERE ref = ? AND folder IN ('inbox', 'trash')", { 'bc:' .. ref })
    return true
end

--- pf-government announcements (the payload pf-government sends to pf-computer).
function M.SyncGovernmentAnnouncement(a)
    if type(a) ~= 'table' or a.id == nil then return false end
    local id = C.Token(tostring(a.id), 40)
    if not id then return false end
    local title = C.Text(tostring(a.title or ''), 100) or 'Government announcement'
    local body = C.Text(tostring(a.body or a.content or ''), CFG.MaxMessage - 120, true) or title
    local author = C.Text(tostring(a.author or a.created_by_name or ''), 60)
    return M.Broadcast('gov:announcement:' .. id, {
        sender = 'City Hall', senderType = 'government', subject = '[City Hall] ' .. title,
        message = author and (body .. '\n\n— ' .. author) or body,
    })
end

function M.RemoveGovernmentAnnouncement(id)
    id = id ~= nil and C.Token(tostring(id), 40) or nil
    if not id then return false end
    return M.RemoveBroadcast('gov:announcement:' .. id)
end

function M.SyncGovernmentLaw(law, action)
    if type(law) ~= 'table' or law.id == nil then return false end
    local id = C.Token(tostring(law.id), 40)
    if not id then return false end
    action = action == 'repeal' and 'repeal' or 'publish'
    local title = C.Text(tostring(law.title or ''), 90) or ('Law #' .. id)
    return M.Broadcast(('gov:law:%s:%s'):format(id, action), {
        sender = 'City Hall', senderType = 'government',
        subject = ('[City Hall Laws] %s: %s'):format(action == 'repeal' and 'Repealed' or 'Published', title),
        message = C.Text(tostring(law.content or ''), CFG.MaxMessage, true) or title,
    })
end

-- ── the Mail app (player side) ──────────────────────────────────────

local function me(src)
    local P = C.Player(src)
    if not P then return nil end
    return P, P.PlayerData.citizenid
end

local function ownRow(cid, id)
    id = C.Int(id, 1)
    if not id then return nil end
    return MySQL.single.await('SELECT ' .. COLUMNS .. ', citizenid, prev_folder FROM player_mails WHERE id = ? AND citizenid = ? LIMIT 1', { id, cid })
end

local function splitRecipients(to)
    local list = {}
    if type(to) == 'string' then
        for tok in to:gmatch('[^,;%s]+') do list[#list + 1] = tok end
    elseif type(to) == 'table' then
        for _, tok in ipairs(to) do if type(tok) == 'string' then list[#list + 1] = tok end end
    end
    return list
end

function M.MyAddress(P)
    return C.AddressOf({ cid = P.PlayerData.citizenid, phone = C.PhoneOfPlayer(P) })
end

function M.Counts(cid)
    local out = { inbox = 0, unread = 0, sent = 0, drafts = 0, trash = 0 }
    for _, r in ipairs(MySQL.query.await('SELECT folder, COUNT(*) AS n, SUM(`read` = 0) AS unread FROM player_mails WHERE citizenid = ? GROUP BY folder', { cid }) or {}) do
        if FOLDERS[r.folder] then out[r.folder] = tonumber(r.n) or 0 end
        if r.folder == 'inbox' then out.unread = tonumber(r.unread) or 0 end
    end
    return out
end

function M.List(src, p)
    local P, cid = me(src)
    if not P then return { ok = false, error = 'no_player' } end
    local folder = FOLDERS[p.folder] and p.folder or 'inbox'
    local sql = 'SELECT ' .. COLUMNS .. ' FROM player_mails WHERE citizenid = ? AND folder = ?'
    local params = { cid, folder }
    local before = C.Int(p.before, 1)
    if before then sql = sql .. ' AND id < ?'; params[#params + 1] = before end
    local search = C.Text(p.search, 60)
    if search then
        local like = '%' .. C.LikeEscape(search) .. '%'
        sql = sql .. ' AND (subject LIKE ? OR sender LIKE ? OR message LIKE ? OR recipients LIKE ?)'
        for _ = 1, 4 do params[#params + 1] = like end
    end
    sql = sql .. ' ORDER BY id DESC LIMIT ' .. CFG.PageSize
    local out = {}
    for _, r in ipairs(MySQL.query.await(sql, params) or {}) do r.__me = cid; out[#out + 1] = view(r, false) end
    return { ok = true, folder = folder, mails = out, counts = M.Counts(cid), address = M.MyAddress(P), more = #out >= CFG.PageSize }
end

function M.Get(src, p)
    local P, cid = me(src)
    if not P then return { ok = false, error = 'no_player' } end
    local row = ownRow(cid, p.id)
    if not row then return { ok = false, error = 'not_found' } end
    if tonumber(row.read) ~= 1 then
        MySQL.update.await('UPDATE player_mails SET `read` = 1 WHERE id = ? AND citizenid = ?', { row.id, cid })
        row.read = 1
    end
    row.__me = cid
    local thread = {}
    if row.thread and row.folder ~= 'drafts' then
        for _, r in ipairs(MySQL.query.await('SELECT ' .. COLUMNS .. " FROM player_mails WHERE citizenid = ? AND thread = ? AND folder <> 'drafts' ORDER BY id ASC LIMIT 50", { cid, row.thread }) or {}) do
            r.__me = cid
            thread[#thread + 1] = view(r, true)
        end
    end
    return { ok = true, mail = view(row, true), thread = thread, counts = M.Counts(cid) }
end

function M.MarkRead(src, p)
    local _, cid = me(src)
    local id = C.Int(p.id, 1)
    if not cid or not id then return { ok = false, error = 'bad_request' } end
    local n = MySQL.update.await('UPDATE player_mails SET `read` = ? WHERE id = ? AND citizenid = ?', { p.read == false and 0 or 1, id, cid })
    if C.Affected(n) < 1 then return { ok = false, error = 'not_found' } end
    return { ok = true, counts = M.Counts(cid) }
end

--- Delete: into the trash, and from the trash for good.
function M.Delete(src, p)
    local _, cid = me(src)
    local row = cid and ownRow(cid, p.id)
    if not row then return { ok = false, error = 'not_found' } end
    if row.folder == 'trash' or row.folder == 'drafts' then
        MySQL.update.await('DELETE FROM player_mails WHERE id = ? AND citizenid = ?', { row.id, cid })
        return { ok = true, deleted = true, counts = M.Counts(cid) }
    end
    MySQL.update.await("UPDATE player_mails SET prev_folder = folder, folder = 'trash', moved_at = NOW() WHERE id = ? AND citizenid = ?", { row.id, cid })
    return { ok = true, trashed = true, counts = M.Counts(cid) }
end

function M.Restore(src, p)
    local _, cid = me(src)
    local row = cid and ownRow(cid, p.id)
    if not row or row.folder ~= 'trash' then return { ok = false, error = 'not_found' } end
    local folder = (row.prev_folder == 'sent') and 'sent' or 'inbox'
    MySQL.update.await('UPDATE player_mails SET folder = ?, prev_folder = NULL, moved_at = NULL WHERE id = ? AND citizenid = ?', { folder, row.id, cid })
    return { ok = true, folder = folder, counts = M.Counts(cid) }
end

function M.EmptyTrash(src)
    local _, cid = me(src)
    if not cid then return { ok = false, error = 'no_player' } end
    local n = MySQL.update.await("DELETE FROM player_mails WHERE citizenid = ? AND folder = 'trash'", { cid })
    return { ok = true, deleted = C.Affected(n), counts = M.Counts(cid) }
end

--- Documents a player attaches must be ones they can read.
local function playerAttachments(cid, list)
    local atts, err = M.CleanAttachments(list, false)
    if not atts then return nil, err end
    for _, a in ipairs(atts) do
        local doc = C.Documents and C.Documents.Readable(cid, tonumber(a.ref))
        if not doc then return nil, 'attachment_not_allowed' end
        a.title = doc.title
    end
    return atts
end

function M.SaveDraft(src, p)
    local P, cid = me(src)
    if not P then return { ok = false, error = 'no_player' } end
    local subject = C.Text(p.subject, CFG.MaxSubject) or '(no subject)'
    local message = C.Text(p.message, CFG.MaxMessage, true) or ''
    local to = C.Text(type(p.to) == 'string' and p.to or table.concat(splitRecipients(p.to), ', '), 380)
    local atts, err = playerAttachments(cid, p.attachments)
    if not atts then return { ok = false, error = err } end
    local encoded = #atts > 0 and json.encode(atts) or nil
    local id = C.Int(p.id, 1)
    if id then
        local n = MySQL.update.await("UPDATE player_mails SET subject = ?, message = ?, recipients = ?, attachments = ?, `date` = NOW() WHERE id = ? AND citizenid = ? AND folder = 'drafts'",
            { subject, message, to, encoded, id, cid })
        if C.Affected(n) < 1 then return { ok = false, error = 'not_found' } end
        return { ok = true, id = id }
    end
    if M.Counts(cid).drafts >= CFG.DraftLimit then return { ok = false, error = 'too_many_drafts' } end
    id = M.Insert(cid, { folder = 'drafts', read = true, sender = C.NameOfPlayer(P), subject = subject, message = message,
        recipients = to, attachments = atts, senderType = 'person', senderCid = cid, senderAddress = M.MyAddress(P) })
    if not id then return { ok = false, error = 'not_stored' } end
    return { ok = true, id = id }
end

--- A player's mail to people (phone number, citizen id, address book) and businesses.
function M.SendFromPlayer(src, p)
    local P, cid = me(src)
    if not P then return { ok = false, error = 'no_player' } end
    local tokens = splitRecipients(p.to)
    if #tokens == 0 then return { ok = false, error = 'no_recipients' } end
    if #tokens > CFG.MaxRecipients then return { ok = false, error = 'too_many_recipients' } end
    local subject = C.Text(p.subject, CFG.MaxSubject)
    local message = C.Text(p.message, CFG.MaxMessage, true)
    if not subject then return { ok = false, error = 'no_subject' } end
    if not message then return { ok = false, error = 'no_message' } end
    local atts, aerr = playerAttachments(cid, p.attachments)
    if not atts then return { ok = false, error = aerr } end

    -- every recipient must exist before anything is sent (no half-sent mail)
    local recipients, seen = {}, {}
    for _, tok in ipairs(tokens) do
        local r, err = C.ResolveRecipient(tok)
        if not r then return { ok = false, error = err, recipient = C.Cut(tok, 60) } end
        local key = r.kind .. ':' .. (r.cid or r.id)
        if not seen[key] then seen[key] = true; recipients[#recipients + 1] = r end
    end
    if not C.Allow(cid, 'mail:send', CFG.SendBurst, CFG.SendRefillSeconds, #recipients) then
        return { ok = false, error = 'rate_limited' }
    end

    local thread
    local replyRow = p.replyTo ~= nil and ownRow(cid, p.replyTo) or nil
    if p.replyTo ~= nil and not replyRow then return { ok = false, error = 'not_found' } end
    if replyRow then
        thread = replyRow.thread or ('m' .. replyRow.id)
        if not replyRow.thread then MySQL.update.await('UPDATE player_mails SET thread = ? WHERE id = ? AND citizenid = ?', { thread, replyRow.id, cid }) end
    else
        thread = newThread()
    end

    local senderName, address = C.NameOfPlayer(P), M.MyAddress(P)
    local names = {}
    for _, r in ipairs(recipients) do names[#names + 1] = ('%s <%s>'):format(r.name, r.address) end
    local toLine = C.Cut(table.concat(names, ', '), 400)
    local delivered = 0
    for _, r in ipairs(recipients) do
        local targets = r.kind == 'business' and (C.BusinessBosses(r.id) or {}) or { r.cid }
        for _, target in ipairs(targets) do
            for _, a in ipairs(atts) do C.Documents.ShareInternal(tonumber(a.ref), target, cid) end
            if M.Deliver(target, { sender = senderName, subject = subject, message = message, senderType = 'person', senderCid = cid,
                senderAddress = address, recipients = toLine, thread = thread, attachments = atts }) then
                delivered = delivered + 1
            end
        end
    end
    if delivered == 0 then return { ok = false, error = 'no_recipients' } end
    local sentId = M.Insert(cid, { folder = 'sent', read = true, sender = senderName, subject = subject, message = message,
        senderType = 'person', senderCid = cid, senderAddress = address, recipients = toLine, thread = thread, attachments = atts })
    local draftId = C.Int(p.draftId, 1)
    if draftId then MySQL.update.await("DELETE FROM player_mails WHERE id = ? AND citizenid = ? AND folder = 'drafts'", { draftId, cid }) end
    return { ok = true, id = sentId, delivered = delivered, counts = M.Counts(cid) }
end

--- People and businesses a player can write to: phone contacts, recent correspondents, businesses.
function M.AddressBook(src)
    local P, cid = me(src)
    if not P then return { ok = false, error = 'no_player' } end
    local out, seen = {}, {}
    local function add(e)
        if not e.address or seen[e.address] then return end
        seen[e.address] = true
        out[#out + 1] = e
    end
    local okC, contacts = pcall(MySQL.query.await, 'SELECT name, number FROM player_contacts WHERE citizenid = ? ORDER BY name LIMIT 100', { cid })
    for _, c in ipairs(okC and contacts or {}) do
        local number = tostring(c.number or '')
        if C.IsPhoneNumber(number) then add({ kind = 'contact', name = tostring(c.name or number), address = number .. '@' .. CFG.Domain }) end
    end
    local recent = MySQL.query.await([[SELECT sender, sender_address, MAX(id) AS last FROM player_mails
        WHERE citizenid = ? AND sender_address IS NOT NULL AND sender_type IN ('person', 'business') AND (sender_cid IS NULL OR sender_cid <> ?)
        GROUP BY sender, sender_address ORDER BY last DESC LIMIT 15]], { cid, cid }) or {}
    for _, r in ipairs(recent) do add({ kind = 'recent', name = r.sender, address = r.sender_address }) end
    local okB, biz = pcall(MySQL.query.await, 'SELECT business_id, business_name FROM pf_gov_businesses ORDER BY business_name LIMIT 150')
    for _, b in ipairs(okB and biz or {}) do add({ kind = 'business', name = b.business_name, address = 'biz:' .. b.business_id }) end
    return { ok = true, entries = out, address = M.MyAddress(P) }
end

function M.PurgeTrash()
    return MySQL.update.await("DELETE FROM player_mails WHERE folder = 'trash' AND moved_at IS NOT NULL AND moved_at < NOW() - INTERVAL ? DAY", { CFG.TrashKeepDays })
end
