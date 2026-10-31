-- Job Board: real vacancies of real businesses, and hiring from them.
--
-- A post belongs to a business its poster manages, checked on the server every time:
--   job:<job>   the poster is the boss of that job (pfm-core job isboss); a hire gives the applicant
--               that job at the grade the boss picks (never above the boss's own grade), through
--               pfm-core's SetJob like pfm-management's boss menu.
--   gov:<id>    the poster owns the business on pf-government's registry (pf_gov_businesses.owner_id).
--               When the registry business is a job shop (mechanic:<job>) a hire gives that job; other
--               businesses (stores, restaurants with their own staff lists) can only accept an
--               applicant, who is told by mail, and add them in their own staff app.
-- Applicants are the player's own character (name and phone from the server, never typed in).
-- A hire needs the applicant's consent: online, they accept the offer in the Job Board; an offer
-- made while they were offline is applied when they next log in (applying was their consent).
-- The poster is mailed about each application and the applicant about every decision (pf-citizen
-- Mail when it runs). Tables: pf_computer_job_posts, pf_computer_job_applications (main.lua
-- migration 1).

local C = PFComputer
local handlers = C.handlers
local clean = C.cleanText
local QBCore = C.QBCore

local MAX_OPEN_POSTS_PER_BUSINESS = 10
local OFFER_DAYS = 7
-- jobs anyone can take at the City Hall job centre (pf-government Config.CivilServices.AvailableJobs)
local PUBLIC_JOBS = (Config.JobBoard and Config.JobBoard.PublicJobs) or { 'trucker', 'taxi', 'tow', 'reporter', 'garbage', 'bus', 'hotdog' }

for _, name in ipairs({ 'jobs:list', 'jobs:catalog', 'jobs:businesses', 'jobs:create', 'jobs:myJobs', 'jobs:getApplicants',
    'jobs:apply', 'jobs:myApplications', 'jobs:withdraw', 'jobs:hire', 'jobs:respond', 'jobs:reject', 'jobs:close' }) do
    C.WRITE_ACTIONS[name] = true   -- every job board call needs the tables
end

local function dbReady() return C.DB.mode == 'ready' end

local function jobsTable()
    return QBCore and QBCore.Shared and QBCore.Shared.Jobs or {}
end

local function me(src)
    local P = C.GetPlayer(src)
    local pd = P and P.PlayerData
    if not pd or not pd.citizenid then return nil end
    return P, pd.citizenid, C.playerName(src), pd.charinfo and pd.charinfo.phone or nil
end

--- The registry businesses this citizen owns: { { id, name, hireJob } }.
local function ownedRegistryBusinesses(cid)
    if GetResourceState('pf-government') ~= 'started' then return {} end
    local ok, rows = pcall(function()
        return MySQL.query.await('SELECT business_id, business_name FROM pf_gov_businesses WHERE owner_id = ? LIMIT 20', { cid })
    end)
    local out = {}
    for _, r in ipairs(ok and type(rows) == 'table' and rows or {}) do
        local kind, localId = tostring(r.business_id):match('^(%a+):(.+)$')
        local hireJob = (kind == 'mechanic' and jobsTable()[localId]) and localId or nil
        out[#out + 1] = { id = r.business_id, name = r.business_name, hireJob = hireJob }
    end
    return out
end

--- The businesses the player may post for and hire into right now.
local function managedBusinesses(src)
    local P, cid = me(src)
    if not P then return {} end
    local out = {}
    local job = P.PlayerData.job
    if job and job.isboss == true and jobsTable()[job.name] then
        out[#out + 1] = { key = 'job:' .. job.name, kind = 'job', id = job.name, name = job.label or job.name, hireJob = job.name }
    end
    for _, b in ipairs(ownedRegistryBusinesses(cid)) do
        out[#out + 1] = { key = 'gov:' .. b.id, kind = 'gov', id = b.id, name = b.name, hireJob = b.hireJob }
    end
    return out
end

local function managesPost(src, post)
    if not post or post.business_kind == 'legacy' then return false end
    for _, b in ipairs(managedBusinesses(src)) do
        if b.kind == post.business_kind and b.id == post.business_id then return true, b end
    end
    return false
end

local function getPost(id)
    id = tonumber(id)
    if not id then return nil end
    local row = MySQL.single.await('SELECT * FROM pf_computer_job_posts WHERE id = ?', { math.floor(id) })
    return type(row) == 'table' and row.id and row or nil
end

local function getApplication(id)
    id = tonumber(id)
    if not id then return nil end
    local row = MySQL.single.await('SELECT * FROM pf_computer_job_applications WHERE id = ?', { math.floor(id) })
    return type(row) == 'table' and row.id and row or nil
end

local function gradeName(job, grade)
    local j = jobsTable()[job]
    local g = j and j.grades and j.grades[tostring(grade)]
    return g and g.name or ('grade ' .. tostring(grade))
end

local function postView(r, cid)
    local tags = {}
    for t in tostring(r.tags or ''):gmatch('[^,]+') do tags[#tags + 1] = t end
    return {
        id = r.id, title = r.title, company = r.business_name, business = r.business_kind .. ':' .. r.business_id,
        location = r.location, salary = r.salary, type = r.employment, category = r.category,
        description = r.description, tags = tags, status = r.status, createdAt = r.created_at,
        posterName = r.poster_name, hires = r.hire_job ~= nil, hireJob = r.hire_job,
        isMine = cid ~= nil and r.poster_cid == cid,
    }
end

local function online(cid)
    local P = QBCore.Functions.GetPlayerByCitizenId(cid)
    return P and P.PlayerData and P.PlayerData.source or nil
end

local function notify(cid, text, kind)
    local s = online(cid)
    if s then TriggerClientEvent('QBCore:Notify', s, text, kind or 'primary') end
end

local function mail(cid, subject, message, senderName)
    C.sendMail(cid, { sender = senderName or 'Job Board', senderType = 'business', subject = subject, message = message })
end

-- news: a new vacancy is a classified (pf-services city timeline)
local hiringKindRegistered = false
local function emitHiring(post)
    if GetResourceState('pf-services') ~= 'started' then return end
    pcall(function()
        if not hiringKindRegistered then
            exports['pf-services']:RegisterEventKind('business.hiring', { label = 'Now hiring', news = 'auto', category = 'business' })
            hiringKindRegistered = true
        end
        exports['pf-services']:Emit('business.hiring', { postId = post.id, business = post.business_name, title = post.title, salary = post.salary },
            { title = ('Now hiring: %s seeks %s'):format(post.business_name, post.title), dedupe = 'jobpost:' .. post.id, actor = post.poster_cid })
    end)
end

-- ── reading ────────────────────────────────────────────────────────────────────
handlers['jobs:list'] = function(payload, src)
    if not dbReady() then return { ok = false, error = 'storage_unavailable' } end
    local _, cid = me(src)
    local rows = MySQL.query.await("SELECT * FROM pf_computer_job_posts WHERE status = 'open' ORDER BY id DESC LIMIT 100") or {}
    local applied = {}
    if cid then
        for _, a in ipairs(MySQL.query.await("SELECT post_id, status FROM pf_computer_job_applications WHERE applicant_cid = ?", { cid }) or {}) do
            applied[a.post_id] = a.status
        end
    end
    local out = {}
    for _, r in ipairs(rows) do
        local v = postView(r, cid)
        v.myApplication = applied[r.id]
        out[#out + 1] = v
    end
    return { ok = true, data = out }
end

--- Every job in the city (pfm-core's job list): whether anyone can take it at the job centre, and how
--- many vacancies are posted for it on the board.
handlers['jobs:catalog'] = function()
    local open = {}
    if dbReady() then
        for _, r in ipairs(MySQL.query.await("SELECT hire_job, COUNT(*) AS n FROM pf_computer_job_posts WHERE status = 'open' AND hire_job IS NOT NULL GROUP BY hire_job") or {}) do
            open[r.hire_job] = tonumber(r.n) or 0
        end
    end
    local public = {}
    for _, n in ipairs(PUBLIC_JOBS) do public[n] = true end
    local out = {}
    for name, j in pairs(jobsTable()) do
        if name ~= 'unemployed' then
            local grades, hasBoss = 0, false
            for _, g in pairs(j.grades or {}) do
                grades = grades + 1
                if g.isboss then hasBoss = true end
            end
            local posts = open[name] or 0
            out[#out + 1] = {
                job = name, label = j.label or name, grades = grades, managed = hasBoss,
                jobCentre = public[name] == true, openPosts = posts,
                openForHire = public[name] == true or posts > 0,
            }
        end
    end
    table.sort(out, function(a, b) return a.label < b.label end)
    return { ok = true, data = out }
end

handlers['jobs:businesses'] = function(_, src)
    local out = {}
    for _, b in ipairs(managedBusinesses(src)) do
        local grades = {}
        if b.hireJob then
            local P = C.GetPlayer(src)
            local bossLevel = (P and P.PlayerData.job.name == b.hireJob and tonumber(P.PlayerData.job.grade.level)) or nil
            for level, g in pairs((jobsTable()[b.hireJob] or {}).grades or {}) do
                local lv = tonumber(level) or 0
                if bossLevel == nil or lv <= bossLevel then grades[#grades + 1] = { level = lv, label = g.name or ('Grade ' .. level) } end
            end
            table.sort(grades, function(x, y) return x.level < y.level end)
        end
        out[#out + 1] = { key = b.key, name = b.name, hires = b.hireJob ~= nil, grades = grades }
    end
    return { ok = true, data = out }
end

-- ── posting ────────────────────────────────────────────────────────────────────
handlers['jobs:create'] = function(payload, src)
    if not dbReady() then return { ok = false, error = 'storage_unavailable' } end
    local P, cid, name = me(src)
    if not P then return { ok = false, error = 'no_identifier' } end
    local business
    local wanted = type(payload.business) == 'string' and payload.business or nil
    for _, b in ipairs(managedBusinesses(src)) do
        if wanted == nil or b.key == wanted then business = b break end
    end
    if not business then return { ok = false, error = 'not_business_manager' } end
    local title = clean(payload.title, 80, nil)
    if not title or title:gsub('%s', '') == '' then return { ok = false, error = 'missing_title' } end
    local open = tonumber(MySQL.scalar.await("SELECT COUNT(*) FROM pf_computer_job_posts WHERE business_id = ? AND status = 'open'", { business.id })) or 0
    if open >= MAX_OPEN_POSTS_PER_BUSINESS then return { ok = false, error = 'too_many_posts' } end

    local tags = {}
    for _, tag in ipairs(type(payload.tags) == 'table' and payload.tags or {}) do
        if #tags >= 8 then break end
        local t = clean(tag, 24, nil)
        if t and t ~= '' then tags[#tags + 1] = t:gsub(',', ' ') end
    end
    local post = {
        business_kind = business.kind, business_id = business.id, business_name = clean(business.name, 100, business.id),
        hire_job = business.hireJob, title = title, location = clean(payload.location, 80, 'Los Santos'),
        salary = clean(payload.salary, 40, 'Negotiable'), employment = clean(payload.type, 30, 'Full-time'),
        category = clean(payload.category, 30, 'general'), description = clean(payload.description, 2000, ''),
        tags = table.concat(tags, ','), poster_cid = cid, poster_name = name, created_at = os.time(),
    }
    local id = MySQL.insert.await([[INSERT INTO pf_computer_job_posts (business_kind, business_id, business_name, hire_job, title, location,
        salary, employment, category, description, tags, poster_cid, poster_name, status, created_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'open', ?)]],
        { post.business_kind, post.business_id, post.business_name, post.hire_job, post.title, post.location, post.salary,
          post.employment, post.category, post.description, post.tags, post.poster_cid, post.poster_name, post.created_at })
    if not tonumber(id) then return { ok = false, error = 'db_error' } end
    post.id = tonumber(id)
    post.status = 'open'
    emitHiring(post)
    return { ok = true, data = postView(post, cid) }
end

--- Posts of the businesses the player manages (not only those they wrote: a new boss sees the shop's
--- open posts), with their application counts.
handlers['jobs:myJobs'] = function(_, src)
    if not dbReady() then return { ok = false, error = 'storage_unavailable' } end
    local _, cid = me(src)
    local ids = {}
    for _, b in ipairs(managedBusinesses(src)) do ids[#ids + 1] = b.id end
    if #ids == 0 then return { ok = true, data = {} } end
    local marks = string.rep('?,', #ids):sub(1, -2)
    local rows = MySQL.query.await(([[SELECT p.*, (SELECT COUNT(*) FROM pf_computer_job_applications a WHERE a.post_id = p.id) AS applicants,
        (SELECT COUNT(*) FROM pf_computer_job_applications a WHERE a.post_id = p.id AND a.status = 'pending') AS waiting
        FROM pf_computer_job_posts p WHERE p.business_kind <> 'legacy' AND p.business_id IN (%s) ORDER BY p.id DESC LIMIT 100]]):format(marks), ids) or {}
    local out = {}
    for _, r in ipairs(rows) do
        local v = postView(r, cid)
        v.applicantCount, v.waiting = tonumber(r.applicants) or 0, tonumber(r.waiting) or 0
        out[#out + 1] = v
    end
    return { ok = true, data = out }
end

handlers['jobs:getApplicants'] = function(payload, src)
    if not dbReady() then return { ok = false, error = 'storage_unavailable' } end
    local post = getPost(payload.jobId)
    if not post then return { ok = false, error = 'job_not_found' } end
    if not managesPost(src, post) then return { ok = false, error = 'not_authorized' } end
    local rows = MySQL.query.await('SELECT * FROM pf_computer_job_applications WHERE post_id = ? ORDER BY id DESC LIMIT 200', { post.id }) or {}
    local out = {}
    for _, a in ipairs(rows) do
        out[#out + 1] = {
            id = a.id, name = a.applicant_name, phone = a.applicant_phone, experience = a.experience, message = a.message,
            status = a.status, createdAt = a.created_at, online = online(a.applicant_cid) ~= nil,
            offerGrade = a.offer_grade, offerRank = a.offer_grade and post.hire_job and gradeName(post.hire_job, a.offer_grade) or nil,
        }
    end
    return { ok = true, data = out, post = postView(post) }
end

-- ── applying ───────────────────────────────────────────────────────────────────
handlers['jobs:apply'] = function(payload, src)
    if not dbReady() then return { ok = false, error = 'storage_unavailable' } end
    local P, cid, name, phone = me(src)
    if not P then return { ok = false, error = 'no_identifier' } end
    local post = getPost(payload.jobId)
    if not post or post.status ~= 'open' then return { ok = false, error = 'job_not_found' } end
    if managesPost(src, post) then return { ok = false, error = 'own_business' } end
    if post.hire_job and P.PlayerData.job and P.PlayerData.job.name == post.hire_job then return { ok = false, error = 'already_employed' } end
    local experience = clean(payload.experience, 1000, '')
    local message = clean(payload.message, 1000, '')
    local ok, id = pcall(function()
        return MySQL.insert.await([[INSERT INTO pf_computer_job_applications (post_id, applicant_cid, applicant_name, applicant_phone,
            experience, message, status, created_at) VALUES (?, ?, ?, ?, ?, ?, 'pending', ?)]],
            { post.id, cid, name, phone and tostring(phone):sub(1, 20) or nil, experience, message, os.time() })
    end)
    if not ok then
        -- one application per post and character (uq_post_applicant)
        if tostring(id):find('Duplicate', 1, true) then return { ok = false, error = 'already_applied' } end
        return { ok = false, error = 'db_error' }
    end
    if not tonumber(id) then return { ok = false, error = 'db_error' } end
    mail(post.poster_cid, ('New application: %s'):format(post.title),
        ('%s applied for %s at %s.\n\n%s\n\nOpen the Job Board on a computer to review it.'):format(name, post.title, post.business_name, message),
        'Job Board')
    notify(post.poster_cid, ('%s applied for %s'):format(name, post.title), 'primary')
    return { ok = true, data = { id = tonumber(id), jobId = post.id, name = name, status = 'pending' } }
end

handlers['jobs:myApplications'] = function(_, src)
    if not dbReady() then return { ok = false, error = 'storage_unavailable' } end
    local _, cid = me(src)
    if not cid then return { ok = false, error = 'no_identifier' } end
    local rows = MySQL.query.await([[SELECT a.id, a.status, a.offer_grade, a.created_at, a.decided_at, p.id AS post_id, p.title,
        p.business_name, p.hire_job, p.status AS post_status FROM pf_computer_job_applications a
        JOIN pf_computer_job_posts p ON p.id = a.post_id WHERE a.applicant_cid = ? ORDER BY a.id DESC LIMIT 100]], { cid }) or {}
    local out = {}
    for _, r in ipairs(rows) do
        out[#out + 1] = {
            id = r.id, jobId = r.post_id, title = r.title, company = r.business_name, status = r.status,
            postStatus = r.post_status, createdAt = r.created_at, decidedAt = r.decided_at,
            offerRank = r.offer_grade and r.hire_job and gradeName(r.hire_job, r.offer_grade) or nil,
        }
    end
    return { ok = true, data = out }
end

handlers['jobs:withdraw'] = function(payload, src)
    if not dbReady() then return { ok = false, error = 'storage_unavailable' } end
    local _, cid = me(src)
    local app = getApplication(payload.applicationId)
    if not app or app.applicant_cid ~= cid then return { ok = false, error = 'application_not_found' } end
    local n = MySQL.update.await("UPDATE pf_computer_job_applications SET status = 'withdrawn', decided_at = ? WHERE id = ? AND status IN ('pending', 'offered', 'hire_pending')", { os.time(), app.id })
    if (tonumber(n) or 0) < 1 then return { ok = false, error = 'not_pending' } end
    return { ok = true }
end

-- ── deciding ───────────────────────────────────────────────────────────────────
local function giveJob(src, job, grade)
    local P = C.GetPlayer(src)
    if not P or not P.Functions.SetJob(job, grade) then return false end
    if P.Functions.Save then P.Functions.Save() end
    return true
end

--- The boss hires: a job-shop post makes an offer (accepted by the applicant now, or applied at their
--- next login when they are offline); a post of a business without a job accepts the applicant.
handlers['jobs:hire'] = function(payload, src)
    if not dbReady() then return { ok = false, error = 'storage_unavailable' } end
    local app = getApplication(payload.applicationId)
    local post = app and getPost(app.post_id)
    if not post then return { ok = false, error = 'application_not_found' } end
    local manages, business = managesPost(src, post)
    if not manages then return { ok = false, error = 'not_authorized' } end
    if app.status ~= 'pending' then return { ok = false, error = 'not_pending' } end
    local _, bossCid, bossName = me(src)

    if not business.hireJob then
        MySQL.update.await("UPDATE pf_computer_job_applications SET status = 'accepted', decided_by = ?, decided_at = ? WHERE id = ?", { bossCid, os.time(), app.id })
        mail(app.applicant_cid, ('Application accepted: %s'):format(post.title),
            ('%s accepted your application for %s. Contact %s to start.'):format(post.business_name, post.title, bossName), post.business_name)
        notify(app.applicant_cid, ('%s accepted your application'):format(post.business_name), 'success')
        return { ok = true, data = { status = 'accepted' } }
    end

    local grade = math.floor(tonumber(payload.grade) or 0)
    local grades = (jobsTable()[business.hireJob] or {}).grades or {}
    if not grades[tostring(grade)] then return { ok = false, error = 'invalid_grade' } end
    local Boss = C.GetPlayer(src)
    if Boss.PlayerData.job.name == business.hireJob and grade > (tonumber(Boss.PlayerData.job.grade.level) or 0) then
        return { ok = false, error = 'grade_above_yours' }
    end
    local applicantSrc = online(app.applicant_cid)
    local status = applicantSrc and 'offered' or 'hire_pending'
    MySQL.update.await('UPDATE pf_computer_job_applications SET status = ?, offer_grade = ?, decided_by = ?, decided_at = ? WHERE id = ?',
        { status, grade, bossCid, os.time(), app.id })
    local rank = gradeName(business.hireJob, grade)
    if applicantSrc then
        TriggerClientEvent('QBCore:Notify', applicantSrc, ('%s offers you the job of %s (%s). Accept it in the Job Board.'):format(post.business_name, post.title, rank), 'success')
    end
    mail(app.applicant_cid, ('Job offer: %s'):format(post.title),
        applicantSrc and ('%s offers you the job of %s as %s. Open the Job Board on a computer to accept or decline (the offer lasts %d days).'):format(post.business_name, post.title, rank, OFFER_DAYS)
            or ('%s hired you as %s (%s). The job is yours when you next sign in.'):format(post.business_name, post.title, rank),
        post.business_name)
    return { ok = true, data = { status = status, rank = rank } }
end

--- The applicant answers an offer.
handlers['jobs:respond'] = function(payload, src)
    if not dbReady() then return { ok = false, error = 'storage_unavailable' } end
    local P, cid, name = me(src)
    local app = getApplication(payload.applicationId)
    if not P or not app or app.applicant_cid ~= cid then return { ok = false, error = 'application_not_found' } end
    if app.status ~= 'offered' then return { ok = false, error = 'no_offer' } end
    local post = getPost(app.post_id)
    if payload.accept ~= true then
        MySQL.update.await("UPDATE pf_computer_job_applications SET status = 'declined', decided_at = ? WHERE id = ?", { os.time(), app.id })
        if post then mail(post.poster_cid, ('Offer declined: %s'):format(post.title), ('%s declined your offer for %s.'):format(name, post.title)) end
        return { ok = true, data = { status = 'declined' } }
    end
    if (tonumber(app.decided_at) or 0) < os.time() - OFFER_DAYS * 86400 then
        MySQL.update.await("UPDATE pf_computer_job_applications SET status = 'closed' WHERE id = ?", { app.id })
        return { ok = false, error = 'offer_expired' }
    end
    if not post or not post.hire_job or not jobsTable()[post.hire_job] then return { ok = false, error = 'job_not_found' } end
    -- claim the offer first so a double click cannot run the hire twice
    local claimed = MySQL.update.await("UPDATE pf_computer_job_applications SET status = 'hired', decided_at = ? WHERE id = ? AND status = 'offered'", { os.time(), app.id })
    if (tonumber(claimed) or 0) < 1 then return { ok = false, error = 'no_offer' } end
    if not giveJob(src, post.hire_job, app.offer_grade or 0) then
        MySQL.update.await("UPDATE pf_computer_job_applications SET status = 'offered' WHERE id = ?", { app.id })
        return { ok = false, error = 'hire_failed' }
    end
    mail(post.poster_cid, ('Hired: %s'):format(post.title), ('%s accepted your offer and now works for %s.'):format(name, post.business_name))
    notify(post.poster_cid, ('%s accepted your job offer'):format(name), 'success')
    return { ok = true, data = { status = 'hired', job = post.hire_job, grade = app.offer_grade or 0 } }
end

handlers['jobs:reject'] = function(payload, src)
    if not dbReady() then return { ok = false, error = 'storage_unavailable' } end
    local app = getApplication(payload.applicationId)
    local post = app and getPost(app.post_id)
    if not post then return { ok = false, error = 'application_not_found' } end
    if not managesPost(src, post) then return { ok = false, error = 'not_authorized' } end
    local _, bossCid = me(src)
    local n = MySQL.update.await("UPDATE pf_computer_job_applications SET status = 'rejected', decided_by = ?, decided_at = ? WHERE id = ? AND status IN ('pending', 'offered', 'hire_pending')",
        { bossCid, os.time(), app.id })
    if (tonumber(n) or 0) < 1 then return { ok = false, error = 'not_pending' } end
    mail(app.applicant_cid, ('Application update: %s'):format(post.title), ('%s did not take your application for %s further.'):format(post.business_name, post.title), post.business_name)
    return { ok = true }
end

handlers['jobs:close'] = function(payload, src)
    if not dbReady() then return { ok = false, error = 'storage_unavailable' } end
    local post = getPost(payload.jobId)
    if not post then return { ok = false, error = 'job_not_found' } end
    if not managesPost(src, post) then return { ok = false, error = 'not_authorized' } end
    if post.status ~= 'open' then return { ok = false, error = 'already_closed' } end
    MySQL.update.await("UPDATE pf_computer_job_posts SET status = 'closed', closed_at = ? WHERE id = ?", { os.time(), post.id })
    -- open applications end with the post (offers already made stand)
    MySQL.update.await("UPDATE pf_computer_job_applications SET status = 'closed', decided_at = ? WHERE post_id = ? AND status = 'pending'", { os.time(), post.id })
    return { ok = true }
end

-- ── at login: offers made while the applicant was away ─────────────────────────
function PFComputerJobBoardLogin(src)
    if not dbReady() then return end
    local P, cid = me(src)
    if not P then return end
    local rows = MySQL.query.await([[SELECT a.id, a.offer_grade, a.decided_at, p.title, p.business_name, p.hire_job, p.poster_cid
        FROM pf_computer_job_applications a JOIN pf_computer_job_posts p ON p.id = a.post_id
        WHERE a.applicant_cid = ? AND a.status IN ('hire_pending', 'offered') ORDER BY a.id]], { cid }) or {}
    for _, r in ipairs(rows) do
        if r.hire_job and jobsTable()[r.hire_job] and (tonumber(r.decided_at) or 0) >= os.time() - OFFER_DAYS * 86400 then
            -- the newest pending hire wins if there were several; each is claimed before it is applied
            local claimed = MySQL.update.await("UPDATE pf_computer_job_applications SET status = 'hired' WHERE id = ? AND status = 'hire_pending'", { r.id })
            if (tonumber(claimed) or 0) > 0 then
                if giveJob(src, r.hire_job, r.offer_grade or 0) then
                    TriggerClientEvent('QBCore:Notify', src, ('You now work for %s as %s'):format(r.business_name, gradeName(r.hire_job, r.offer_grade or 0)), 'success')
                    mail(r.poster_cid, ('Hired: %s'):format(r.title), ('Your new hire for %s has started.'):format(r.title))
                else
                    MySQL.update.await("UPDATE pf_computer_job_applications SET status = 'hire_pending' WHERE id = ?", { r.id })
                end
            elseif tonumber(r.decided_at) then
                TriggerClientEvent('QBCore:Notify', src, ('You have a job offer from %s: open the Job Board on a computer'):format(r.business_name), 'primary')
            end
        else
            MySQL.update.await("UPDATE pf_computer_job_applications SET status = 'closed' WHERE id = ? AND status IN ('hire_pending', 'offered')", { r.id })
        end
    end
end

AddEventHandler('QBCore:Server:PlayerLoaded', function(Player)
    local src = Player and Player.PlayerData and Player.PlayerData.source
    if not src then return end
    CreateThread(function()
        Wait(5000)   -- let the character finish loading before its job changes
        local ok, err = pcall(PFComputerJobBoardLogin, src)
        if not ok then print(('^1[pf-computer]^7 job board login check failed: %s'):format(tostring(err))) end
    end)
end)
