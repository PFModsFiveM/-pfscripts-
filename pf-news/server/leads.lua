-- Newsroom leads: city events a reporter may cover (crime, court, business gossip, and the full story
-- behind a breaking bulletin). A lead is never published by itself. Flow:
--   open -> claimed (one on-duty reporter, waypoint to the scene) -> covered (their article published)
--   open/claimed -> expired (too old) or dismissed (an editor)
-- Events of the same kind in the same district close together merge into one lead (hits + 1).

PFNews = PFNews or {}
PFNews.SQL = PFNews.SQL or {}
local U = PFNews.U
local SQL = PFNews.SQL
local L = {}
PFNews.Leads = L

local COLS = [[id, event_id, kind, category, title, details, district, x, y, z, status, hits, claimed_cid, claimed_name,
 UNIX_TIMESTAMP(claimed_at) AS claimed_at, article_id, UNIX_TIMESTAMP(created_at) AS created_at,
 UNIX_TIMESTAMP(expires_at) AS expires_at, UNIX_TIMESTAMP(covered_at) AS covered_at]]

SQL.getLead = 'SELECT ' .. COLS .. ' FROM pf_news_leads WHERE id = ?'
SQL.leadByEvent = 'SELECT id FROM pf_news_leads WHERE event_id = ?'
SQL.findMergeLead = [[SELECT id FROM pf_news_leads WHERE kind = ? AND COALESCE(district, '') = ? AND status IN ('open', 'claimed')
    AND created_at >= FROM_UNIXTIME(?) ORDER BY id DESC LIMIT 1]]
SQL.mergeLead = [[UPDATE pf_news_leads SET hits = hits + 1, updated_at = FROM_UNIXTIME(?), expires_at = GREATEST(COALESCE(expires_at, FROM_UNIXTIME(?)), FROM_UNIXTIME(?))
    WHERE id = ?]]
SQL.insertLead = [[INSERT IGNORE INTO pf_news_leads (event_id, kind, category, title, details, district, x, y, z, status, hits, created_at, updated_at, expires_at)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 'open', 1, FROM_UNIXTIME(?), FROM_UNIXTIME(?), FROM_UNIXTIME(?))]]
SQL.linkEventLead = 'UPDATE pf_news_events SET lead_id = ? WHERE event_id = ? AND lead_id IS NULL'
SQL.countClaimed = "SELECT COUNT(*) FROM pf_news_leads WHERE claimed_cid = ? AND status = 'claimed'"
SQL.claimLead = [[UPDATE pf_news_leads SET status = 'claimed', claimed_cid = ?, claimed_name = ?, claimed_at = FROM_UNIXTIME(?), expires_at = FROM_UNIXTIME(?)
    WHERE id = ? AND status = 'open' AND expires_at >= FROM_UNIXTIME(?)]]
SQL.releaseLead = [[UPDATE pf_news_leads SET status = 'open', claimed_cid = NULL, claimed_name = NULL, claimed_at = NULL,
    expires_at = GREATEST(expires_at, FROM_UNIXTIME(?)) WHERE id = ? AND status = 'claimed' AND claimed_cid = ?]]
SQL.coverLead = [[UPDATE pf_news_leads SET status = 'covered', article_id = ?, covered_at = FROM_UNIXTIME(?)
    WHERE id = ? AND status = 'claimed' AND claimed_cid = ?]]
SQL.dismissLead = "UPDATE pf_news_leads SET status = 'dismissed', updated_at = FROM_UNIXTIME(?) WHERE id = ? AND status IN ('open', 'claimed')"
SQL.expireLeads = "UPDATE pf_news_leads SET status = 'expired' WHERE status IN ('open', 'claimed') AND expires_at < FROM_UNIXTIME(?)"
SQL.countOpenLeads = "SELECT COUNT(*) FROM pf_news_leads WHERE status = 'open'"
SQL.trimOpenLeads = "UPDATE pf_news_leads SET status = 'expired' WHERE status = 'open' ORDER BY id ASC LIMIT %d"
SQL.activeLeads = 'SELECT ' .. COLS .. " FROM pf_news_leads WHERE status IN ('open', 'claimed') ORDER BY id DESC LIMIT 80"
SQL.recentCovered = 'SELECT ' .. COLS .. " FROM pf_news_leads WHERE status = 'covered' ORDER BY covered_at DESC LIMIT 10"

local function norm(r)
    if type(r) ~= 'table' then return nil end
    for _, k in ipairs({ 'id', 'event_id', 'hits', 'article_id', 'claimed_at', 'created_at', 'expires_at', 'covered_at', 'x', 'y', 'z' }) do r[k] = tonumber(r[k]) end
    return r
end

function L.Get(id)
    id = U.int(id, 1)
    if not id then return nil end
    return norm(MySQL.single.await(SQL.getLead, { id }))
end

--- What the newsroom sees: no coordinates until the lead is yours.
function L.View(r, cid)
    local mine = cid ~= nil and r.claimed_cid == cid
    return {
        id = r.id, kind = r.kind, category = r.category, title = r.title, details = r.details, district = r.district,
        status = r.status, hits = r.hits, claimedBy = r.claimed_name, mine = mine, hasLocation = r.x ~= nil,
        createdAt = r.created_at, expiresAt = r.expires_at, articleId = r.article_id,
        coords = (mine and r.x) and { x = r.x, y = r.y, z = r.z } or nil,
    }
end

function L.Active(cid)
    local out = {}
    for _, r in ipairs(MySQL.query.await(SQL.activeLeads) or {}) do out[#out + 1] = L.View(norm(r), cid) end
    return out
end

--- A lead from a city event (snapshot from PFNews.Presets.Snapshot). Exactly once per event id:
--- the pf_news_events row links the event to the lead it made or joined.
function L.FromEvent(snap)
    local now = os.time()
    local C = Config.Leads
    local district = snap.district or ''
    local merge = MySQL.single.await(SQL.findMergeLead, { snap.kind, district, now - (C.mergeSeconds or 300) })
    if merge and tonumber(merge.id) then
        local leadId = tonumber(merge.id)
        if snap.id then
            local n = U.affected(MySQL.update.await(SQL.linkEventLead, { leadId, snap.id }))
            if n ~= 1 then return leadId, false end
        end
        MySQL.update.await(SQL.mergeLead, { now, now, now + (C.openMinutes or 90) * 60, leadId })
        U.pushNewsroom('refresh', { what = 'leads', id = leadId })
        return leadId, false
    end

    local text = PFNews.Presets.LeadText(snap)
    local c = snap.coords
    local category = (snap.category and U.categoryOk(snap.category)) and snap.category or (Config.DefaultCategory or 'city')
    local id = tonumber(MySQL.insert.await(SQL.insertLead, {
        snap.id, snap.kind, category, text.title, text.details, snap.district,
        c and c.x or nil, c and c.y or nil, c and c.z or nil, now, now, now + (C.openMinutes or 90) * 60,
    }))
    if (not id or id < 1) and snap.id then id = tonumber(MySQL.scalar.await(SQL.leadByEvent, { snap.id })) end
    if not id or id < 1 then return nil end
    if snap.id then MySQL.update.await(SQL.linkEventLead, { id, snap.id }) end

    -- the newsroom keeps a bounded list: the oldest open leads give way
    local open = tonumber(MySQL.scalar.await(SQL.countOpenLeads)) or 0
    local max = C.maxOpen or 60
    if open > max then MySQL.update.await(SQL.trimOpenLeads:format(open - max)) end

    U.pushNewsroom('refresh', { what = 'leads', id = id })
    return id, true
end

--- A reporter (on duty, write role) takes an open lead. Returns its coordinates for the waypoint.
function L.Claim(src, id)
    local Player, job = U.reporter(src)
    if not Player or not U.hasRole(job, 'write') then return { ok = false, error = 'not_authorized' } end
    if Config.Leads.requireOnDuty and not job.onduty then return { ok = false, error = 'off_duty' } end
    id = U.int(id, 1)
    if not id then return { ok = false, error = 'bad_request' } end
    local cid = U.cidOf(Player)
    local held = tonumber(MySQL.scalar.await(SQL.countClaimed, { cid })) or 0
    if held >= (Config.Leads.maxClaimedPerReporter or 2) then return { ok = false, error = 'too_many_leads' } end
    local now = os.time()
    local n = U.affected(MySQL.update.await(SQL.claimLead, {
        cid, U.nameOf(Player), now, now + (Config.Leads.claimedMinutes or 120) * 60, id, now,
    }))
    if n ~= 1 then return { ok = false, error = 'lead_taken' } end
    local r = L.Get(id)
    U.pushNewsroom('refresh', { what = 'leads', id = id })
    return { ok = true, lead = L.View(r, cid), coords = r.x and { x = r.x, y = r.y } or nil }
end

function L.Release(src, id)
    local Player = U.reporter(src)
    if not Player then return { ok = false, error = 'not_authorized' } end
    id = U.int(id, 1)
    if not id then return { ok = false, error = 'bad_request' } end
    local n = U.affected(MySQL.update.await(SQL.releaseLead, { os.time() + 15 * 60, id, U.cidOf(Player) }))
    if n ~= 1 then return { ok = false, error = 'not_yours' } end
    U.pushNewsroom('refresh', { what = 'leads', id = id })
    return { ok = true }
end

--- Coordinates of a lead you hold (the client sets the waypoint).
function L.Waypoint(src, id)
    local Player = U.reporter(src)
    if not Player then return { ok = false, error = 'not_authorized' } end
    local r = L.Get(id)
    if not r or r.status ~= 'claimed' or r.claimed_cid ~= U.cidOf(Player) then return { ok = false, error = 'not_yours' } end
    if not r.x then return { ok = false, error = 'no_location' } end
    return { ok = true, coords = { x = r.x, y = r.y } }
end

function L.Dismiss(src, id)
    local Player, job = U.reporter(src)
    if not Player or not U.hasRole(job, 'editor') then return { ok = false, error = 'not_authorized' } end
    id = U.int(id, 1)
    if not id then return { ok = false, error = 'bad_request' } end
    local n = U.affected(MySQL.update.await(SQL.dismissLead, { os.time(), id }))
    if n ~= 1 then return { ok = false, error = 'not_active' } end
    U.pushNewsroom('refresh', { what = 'leads', id = id })
    return { ok = true }
end

--- Marks the lead covered when its claimer's article is published. True when it was.
function L.Cover(leadId, authorCid, articleId)
    leadId = U.int(leadId, 1)
    if not leadId or type(authorCid) ~= 'string' then return false end
    return U.affected(MySQL.update.await(SQL.coverLead, { articleId, os.time(), leadId, authorCid })) == 1
end

function L.Sweep()
    return U.affected(MySQL.update.await(SQL.expireLeads, { os.time() }))
end
