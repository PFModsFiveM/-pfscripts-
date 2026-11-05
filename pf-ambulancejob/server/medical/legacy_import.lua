-- One-time import of the legacy injury records (player_injuries, written by the old client
-- self-report) into the medical engine (pf_med_injuries). Migration v4 runs it once; it is
-- idempotent on its own: every imported row carries `legacy_id` (UNIQUE) and the extra row of a
-- blast injury carries an idempotency key, and INSERT IGNORE skips what is already there. After the
-- import player_injuries is frozen history (PF_DATABASE_MIGRATIONS.md section 11).
--
-- An old record is a past injury whose acute phase is over: it is imported without bleeding, on the
-- skin or a non-vital bone of its zone, and at a severity that starts no acute threat (airway,
-- breathing, head injury) on the next login. Its pain, functional effects and healing time stay.

PFMed = PFMed or {}
PFMed.LegacyImport = PFMed.LegacyImport or {}
local LI = PFMed.LegacyImport

local T_INJURIES = Config.Database.PlayerInjuries

LI.BATCH = 500

-- legacy injury_type -> engine type and subtype
LI.TypeMap = {
    gunshot_wound = { 'gunshot', 'penetrating' },
    laceration = { 'laceration', 'deep' },
    blunt_trauma = { 'bruising', 'contusion' },
    burn = { 'burn', 'second' },
    fracture = { 'fracture', 'closed' },
    respiratory = { 'respiratory', 'smoke_inhalation' },
    electrical_burn = { 'electrical', 'low_voltage' },
    blast_injury = { 'burn', 'second', blast = true },   -- plus a bruise (second row)
}
-- legacy body_zone -> region
LI.ZoneMap = { head = 'head', torso = 'chest_l', left_arm = 'upper_arm_l', right_arm = 'upper_arm_r', left_leg = 'thigh_l', right_leg = 'thigh_r' }
-- the bone a legacy fracture of a zone is put on (the head's is the jaw: a skull fracture would
-- impair consciousness on login)
LI.FractureBone = { head = { 'face', 'face_jaw' }, chest_l = { 'chest_l', 'ribs_l' }, upper_arm_l = { 'upper_arm_l', 'humerus_l' },
    upper_arm_r = { 'upper_arm_r', 'humerus_r' }, thigh_l = { 'thigh_l', 'femur_l' }, thigh_r = { 'thigh_r', 'femur_r' } }
LI.SeverityMap = { minor = 1, moderate = 2, severe = 4, critical = 5 }

-- what an imported record must not start (I.Physiology of the injury)
local function acute(spec)
    local f = PFMed.Injuries.Physiology(spec)
    return f.airway ~= nil or f.tension or f.tamponade or f.lethal or f.arrest or f.arrhythmia or f.spinalShock
        or (f.headPenalty or 0) > 1 or (f.breathing or 0) > 0.1
end

--- Engine rows for one legacy row ({} when it cannot be mapped). Pure; specs call it directly.
function LI.Map(row)
    local I, A = PFMed.Injuries, PFMed.Anatomy
    local cid = row.citizen_id
    if not PFMed.Store.ValidCitizenId(cid) then return {} end
    local t = LI.TypeMap[row.injury_type]
    local region = LI.ZoneMap[row.body_zone]
    local sev = LI.SeverityMap[row.severity]
    if not t or not region or not sev then return {} end
    local typeName, subtype = t[1], t[2]
    local structure = nil
    if typeName == 'fracture' then
        local fb = LI.FractureBone[region]
        region, structure = fb[1], fb[2]
    elseif typeName == 'respiratory' then
        region, structure = nil, 'airway'
    end
    local spec = { type = typeName, subtype = subtype, region = region, structure = structure, severity = sev, attrs = {}, treatments = {} }
    while sev > 1 and acute(spec) do sev = sev - 1; spec.severity = sev end
    local created = tonumber(row.created_ts) or os.time()
    local weapon = type(row.weapon) == 'string' and row.weapon:gsub('%c', ''):sub(1, 64) or nil
    local function out(s, legacyId, key)
        local attrs = { legacy = true, legacyType = row.injury_type, legacySeverity = row.severity, weaponLabel = weapon, blast = t.blast or nil }
        return {
            citizenid = cid, type = s.type, subtype = s.subtype, region = s.region, structure = s.structure, severity = s.severity,
            stage = 'injured', bleed_ml_min = 0, pain = I.Pain(s.type, s.subtype, s.severity), mechanism = 'legacy',
            attrs = json.encode(attrs), legacy_id = legacyId, idem_key = key, created_at = created,
        }
    end
    local rows = { out(spec, tonumber(row.id)) }
    if t.blast then
        local bruise = { type = 'bruising', subtype = 'contusion', region = region or 'chest_l', severity = math.max(1, sev - 1) }
        rows[2] = out(bruise, nil, ('pf-ambulancejob:legacy:%d:blast'):format(tonumber(row.id)))
    end
    -- every row must pass the engine's own checks
    local okRows = {}
    for _, r in ipairs(rows) do
        if I.AllowsStructure(r.type, r.subtype, r.structure) and (not r.region or A.IsRegion(r.region)) then okRows[#okRows + 1] = r end
    end
    return okRows
end

local COLS = { 'citizenid', 'type', 'subtype', 'region', 'structure', 'severity', 'stage', 'bleed_ml_min', 'pain', 'mechanism', 'attrs',
    'legacy_id', 'idem_key', 'created_at' }

local function insert(rows)
    if #rows == 0 then return 0 end
    local params, tuples = {}, {}
    for i, r in ipairs(rows) do
        local vals = {}
        for j, c in ipairs(COLS) do vals[j] = r[c] end
        tuples[i] = PFMed.SQL.BindRow(vals, #COLS, params)
    end
    local n = MySQL.update.await(('INSERT IGNORE INTO `pf_med_injuries` (`%s`) VALUES %s'):format(table.concat(COLS, '`, `'), table.concat(tuples, ', ')), params)
    return tonumber(n) or 0
end

--- Imports every open legacy row that has no engine row yet, in batches by id. Returns
--- { rows = legacy rows read, inserted = engine rows written, skipped = rows that could not be mapped }.
--- Raises on a database error (the migration step is then retried at the next start).
function LI.Run()
    local out = { rows = 0, inserted = 0, skipped = 0 }
    local after = 0
    while true do
        local rows = MySQL.query.await(([[
            SELECT p.`id`, p.`citizen_id`, p.`injury_type`, p.`severity`, p.`body_zone`, p.`weapon`,
                   UNIX_TIMESTAMP(p.`created_at`) AS `created_ts`
            FROM `%s` p LEFT JOIN `pf_med_injuries` m ON m.`legacy_id` = p.`id`
            WHERE p.`deleted_at` IS NULL AND m.`id` IS NULL AND p.`id` > ?
            ORDER BY p.`id` LIMIT %d]]):format(T_INJURIES, LI.BATCH), { after }) or {}
        if #rows == 0 then break end
        local batch = {}
        for _, row in ipairs(rows) do
            local mapped = LI.Map(row)
            if #mapped == 0 then out.skipped = out.skipped + 1 end
            for _, r in ipairs(mapped) do batch[#batch + 1] = r end
            after = math.max(after, tonumber(row.id) or after)
        end
        out.rows = out.rows + #rows
        out.inserted = out.inserted + insert(batch)
        if #rows < LI.BATCH then break end
    end
    if out.rows > 0 then
        print(('^2[pf-ambulancejob]^7 legacy injuries imported: %d records -> %d engine injuries (%d not mappable)'):format(out.rows, out.inserted, out.skipped))
    end
    return out
end
