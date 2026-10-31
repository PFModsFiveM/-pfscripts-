-- Announcements (tablet and computer): everyone reads the active City Hall announcements; officials
-- with Config.GovApps.AnnouncementPermission post and withdraw them through announcement:create /
-- announcement:delete (which also sync to pf-computer mail and reach the city timeline).

local A = GovApps

local PRIORITIES = { low = true, normal = true, high = true, urgent = true }

local function perm() return A.cfg().AnnouncementPermission or 'laws' end

local handlers = {}

function handlers.list(src)
    local rows = MySQL.query.await([[SELECT id, title, content, priority, category, created_by_name, UNIX_TIMESTAMP(created_at) AS created,
        UNIX_TIMESTAMP(expires_at) AS expires FROM pf_gov_announcements WHERE active = 1 AND (expires_at IS NULL OR expires_at > NOW())
        ORDER BY created_at DESC LIMIT 50]]) or {}
    local out = {}
    for _, r in ipairs(rows) do
        out[#out + 1] = { id = tonumber(r.id), title = r.title, body = r.content, priority = r.priority, category = r.category,
            author = r.created_by_name, created = tonumber(r.created), expires = tonumber(r.expires) }
    end
    return { ok = true, announcements = out, canPost = HasPermission(src, perm()) }
end

--- payload = { title, body, priority, days }
function handlers.create(src, p)
    if not HasPermission(src, perm()) then return { ok = false, error = 'no_permission' } end
    local title = A.Text(p.title, 120)
    local body = type(p.body) == 'string' and p.body:gsub('[\1-\8\11\12\14-\31\127]', ''):sub(1, 4000) or nil
    if not title or not body or body:gsub('%s', '') == '' then return { ok = false, error = 'missing_fields' } end
    local priority = PRIORITIES[p.priority] and p.priority or 'normal'
    local days = math.floor(tonumber(p.days) or 7)
    days = math.max(1, math.min(days, 30))
    local res = A.CallNui('announcement:create', src, { title = title, content = body, priority = priority, category = 'general', duration = days * 86400 })
    if not res.ok then return { ok = false, error = res.error or 'create_failed' } end
    return { ok = true, id = res.announcementId }
end

function handlers.delete(src, p)
    if not HasPermission(src, perm()) then return { ok = false, error = 'no_permission' } end
    local id = tonumber(p.id)
    if not id or id ~= math.floor(id) then return { ok = false, error = 'bad_request' } end
    if not MySQL.scalar.await('SELECT 1 FROM pf_gov_announcements WHERE id = ? AND active = 1 LIMIT 1', { id }) then
        return { ok = false, error = 'not_found' }
    end
    local res = A.CallNui('announcement:delete', src, { announcementId = id })
    if not res.ok then return { ok = false, error = res.error or 'delete_failed' } end
    return { ok = true }
end

A.Define({
    id = 'govannouncements', name = 'Announcements', icon = '📢',
    devices = { 'tablet', 'computer' },
    entry = 'html/apps/announcements.js', styles = { 'html/apps/gov.css' },
    category = 'government', order = 24,
    access = { anyone = true },
    description = 'City Hall announcements',
    window = { width = 860, height = 620 },
}, handlers)

GovApps.Announcements = handlers
