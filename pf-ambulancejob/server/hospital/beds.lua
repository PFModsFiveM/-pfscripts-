-- Hospital beds: server-side occupancy (batch 17E, architecture 4.5, 5.3).
--
-- A bed is held by exactly one open admission. Occupancy lives in memory under the facility and
-- bed id and is rebuilt at start from the admissions whose state holds a bed (in_treatment,
-- admitted): a unique key cannot express "one open row per bed". Claims never wait on the
-- database, so two patients can never be given the same bed. This replaces the client-kept
-- `taken` flags of the old flow, whose bed keys mixed hospital indexes with the prison beds (an
-- inmate's bed was never freed, and freeing it freed the hospital bed with the same number), and
-- whose target zones were named by bed number only (two hospitals clashed).
--
-- The client only shows the bed: `pf-ambulancejob:client:Bed` ('enter' | 'leave') tells it where.
-- A patient may get up whenever they like; the server reads positions (the AI works only while
-- the patient is in their bed) and lets them lie down again only in their own bed.

PFHospital = PFHospital or {}
local H = PFHospital
H.Beds = H.Beds or {}
local B = H.Beds

local occ = {}  -- [facilityId] = { [bedId] = { cid, admissionId } }

local function cfg() return Config.Hospital end

--- bed config, department id for a facility and bed id (nil when unknown).
function B.Def(fid, bedId)
    local f = cfg().Facilities[fid]
    if not f or type(bedId) ~= 'string' then return nil end
    for dept, d in pairs(f.departments) do
        for _, b in ipairs(d.beds) do
            if b.id == bedId then return b, dept end
        end
    end
    return nil
end

function B.Occupant(fid, bedId)
    return occ[fid] and occ[fid][bedId] or nil
end

--- First free bed in a department (nil when all are held).
function B.FindFree(fid, dept)
    local f = cfg().Facilities[fid]
    local d = f and f.departments[dept]
    if not d then return nil end
    for _, b in ipairs(d.beds) do
        if not B.Occupant(fid, b.id) then return b.id end
    end
    return nil
end

--- Holds a bed for an admission. Returns true | nil, 'conflict' (another admission holds it) or
--- 'not_found'. Re-claiming one's own bed is fine.
function B.Claim(fid, bedId, cid, admissionId)
    if not B.Def(fid, bedId) then return nil, 'not_found' end
    occ[fid] = occ[fid] or {}
    local cur = occ[fid][bedId]
    -- -1 is the hold a new admission takes before its row (and id) exists
    if cur and cur.admissionId ~= admissionId and not (cur.admissionId == -1 and cur.cid == cid) then return nil, 'conflict' end
    occ[fid][bedId] = { cid = cid, admissionId = admissionId }
    return true
end

--- Frees a bed held by this admission (another admission's bed is never freed).
function B.Release(fid, bedId, admissionId)
    local cur = fid and bedId and occ[fid] and occ[fid][bedId]
    if cur and (admissionId == nil or cur.admissionId == admissionId) then
        occ[fid][bedId] = nil
        return true
    end
    return false
end

--- Rebuilds occupancy from open admissions (list of { id, citizenid, hospital_id, bed_id, state }).
function B.Rebuild(list)
    occ = {}
    for _, a in ipairs(list or {}) do
        if a.bed_id and (a.state == 'in_treatment' or a.state == 'admitted') then
            occ[a.hospital_id] = occ[a.hospital_id] or {}
            if not occ[a.hospital_id][a.bed_id] then
                occ[a.hospital_id][a.bed_id] = { cid = a.citizenid, admissionId = a.id }
            end
        end
    end
end

--- What the client needs to show a bed.
function B.View(fid, bedId)
    local b, dept = B.Def(fid, bedId)
    if not b then return nil end
    local f = cfg().Facilities[fid]
    return { hospitalId = fid, bedId = bedId, dept = dept, coords = b.coords, model = b.model, label = f.label }
end

--- Puts the patient's client into the bed. extra = { token, reviveIn } for a respawn revive.
function B.SendEnter(src, fid, bedId, extra)
    local v = B.View(fid, bedId)
    if not v or not src then return false end
    for k, val in pairs(extra or {}) do v[k] = val end
    if PFMed and PFMed.Down and PFMed.Down.MoveGrace then PFMed.Down.MoveGrace(src, 15 + (tonumber(v.reviveIn) or 0)) end
    TriggerClientEvent('pf-ambulancejob:client:Bed', src, 'enter', v)
    return true
end

--- Lets the patient's client get up (discharge, transfer, bed released).
function B.SendLeave(src, reason)
    if src then TriggerClientEvent('pf-ambulancejob:client:Bed', src, 'leave', { reason = reason }) end
end

--- The bed an online player holds and lies in (server position within AI.BedDistance), or nil:
--- { hospitalId, bedId, dept, imaging, admissionId }. 17A uses this for imaging (patient in bed).
function B.PatientInBed(src)
    local cid = PFMed and PFMed.Store and PFMed.Store.CidOf(src)
    if not cid and H.Player(src) then cid = H.Player(src).PlayerData.citizenid end
    local a = cid and H.Admissions and H.Admissions.OpenOf(cid)
    if not a or not a.bed_id then return nil end
    local b, dept = B.Def(a.hospital_id, a.bed_id)
    if not b then return nil end
    if H.Dist(H.Pos(src), b.coords) > (cfg().AI.BedDistance or 3.0) then return nil end
    local d = cfg().Facilities[a.hospital_id].departments[dept]
    return { hospitalId = a.hospital_id, bedId = a.bed_id, dept = dept, imaging = d.imaging == true, admissionId = a.id }
end

--- A patient asks to lie down in their bed again (after getting up). Only their own bed, only
--- within reach of it.
function B.RequestEnter(src)
    if H.Limited(src, 'bed_enter', 2) then return false end
    local P = H.Player(src)
    if not P then return false end
    local a = H.Admissions and H.Admissions.OpenOf(P.PlayerData.citizenid)
    if not a or not a.bed_id then
        H.Notify(src, 'You have no bed here. Check in at the reception.', 'error')
        return false
    end
    local b = B.Def(a.hospital_id, a.bed_id)
    if not b or H.Dist(H.Pos(src), b.coords) > (cfg().AI.BedDistance or 3.0) + 2.0 then
        H.Notify(src, 'That is not your bed.', 'error')
        return false
    end
    if PFMed.Down.IsDown(src) then return false end
    return B.SendEnter(src, a.hospital_id, a.bed_id)
end

--- ListBeds(hospitalId): every bed of a facility in config order with whether it is held and by
--- which admission (no patient identity). Returns { ok, hospitalId, beds = { { id, dept, occupied,
--- admissionId } } }. Allowlisted (Config.Hospital.Services.Callers.ListBeds).
function B.List(hospitalId)
    local fid = H.Facility.Id(hospitalId)
    local f = fid and cfg().Facilities[fid]
    if not f then return H.Fail('bad_args', 'Unknown hospital.') end
    local depts = {}
    for dept in pairs(f.departments) do depts[#depts + 1] = dept end
    table.sort(depts)
    local out = {}
    for _, dept in ipairs(depts) do
        for _, b in ipairs(f.departments[dept].beds or {}) do
            local o = B.Occupant(fid, b.id)
            -- -1 is a hold taken while a new admission's row is written
            out[#out + 1] = { id = b.id, dept = dept, occupied = o ~= nil, admissionId = o and o.admissionId ~= -1 and o.admissionId or nil }
        end
    end
    return { ok = true, hospitalId = fid, beds = out }
end

exports('ListBeds', function(hospitalId)
    if not (H.ServiceAllowed and H.ServiceAllowed('ListBeds')) then return H.Fail('not_allowed', 'Not allowed.') end
    return B.List(hospitalId)
end)

RegisterNetEvent('pf-ambulancejob:server:EnterBed', function()
    local src = tonumber(source)
    if not src or src <= 0 then return end
    B.RequestEnter(src)
end)
