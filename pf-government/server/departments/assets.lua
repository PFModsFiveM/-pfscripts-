-- =====================================================
-- DEPARTMENTS: ASSET REGISTER (batch 20, unit 20E)
-- =====================================================
-- Serial-tracked department equipment (radios, body cameras, AEDs, rig monitors, armory weapons)
-- in pf_gov_dept_assets, with one pf_gov_dept_asset_events row per change. A serial is unique
-- across the city, so an armory or a rig can look one up without knowing the department.
--
-- States: in_stock -> issued -> in_stock | maintenance | lost (a return)
--         in_stock -> maintenance | lost | retired; maintenance -> in_stock (repair) | lost | retired;
--         lost -> in_stock (found) | retired. issued never jumps to retired (return it first).
--
-- Exports (contract written for 20F, architecture 4.12): RegisterAsset, IssueAsset, ReturnAsset,
-- GetAsset, ListAssets; all through Config.Departments.Callers (fail closed). Every write takes
-- opts.key: a repeat with the same key and arguments returns the first result with
-- duplicate = true, other arguments key_reused. The key of a registration is stored on the asset
-- row, the key of every later change on its event row (both UNIQUE).
--
-- Who may act (read on the server, never from the caller): a player actor works for the asset's
-- department; issuing needs duty, and issuing to someone else (or a kind with selfIssue = false)
-- needs a manager (Config.Departments.ManagerGrade); the holder or a manager returns; only managers
-- register, repair, retire or mark found. Admins (ACE) and pf-government's own system actor pass.
--
-- Armory equipment (issue_ref = Config.Departments.Assets.ArmoryRef, 'armory', issued by
-- pfm-policejob): the item sits in the holder's inventory, so only the armory resource itself
-- (Config.Departments.Assets.ArmoryResources), which removes the item first, books it back in. Anyone
-- else may only have a manager mark it lost; that keeps the holder, the reference and the issue on the
-- row ("lost while held by"), and the armory issues nothing more to that holder until it is resolved:
-- the armory books the item back in when it turns up, or a manager writes it off (retire). A manager
-- cannot mark it found from the register (the item may still be in someone's inventory).

GovDept = GovDept or {}
local D = GovDept
local U = D.U
D.A = D.A or {}
local A = D.A

local function cfg() return (D.Cfg().Assets or {}) end

local STATES = { in_stock = true, issued = true, maintenance = true, lost = true, retired = true }
A.STATES = STATES

-- manager actions outside issue/return: event name -> { from states, to state }
local MOVES = {
    repair = { from = { maintenance = true }, to = 'in_stock' },
    found = { from = { lost = true }, to = 'in_stock' },
    maintenance = { from = { in_stock = true }, to = 'maintenance' },
    lost = { from = { in_stock = true, maintenance = true }, to = 'lost' },
    retire = { from = { in_stock = true, maintenance = true, lost = true }, to = 'retired' },
}
A.MOVES = MOVES

local RETURN_TO = { in_stock = 'return', maintenance = 'return', lost = 'lost' }

local COLUMNS = [[id, dept, kind, serial, item, label, state, holder_cid, location, cost, acquired_at, issued_at,
    issued_by, issue_ref, updated_at, idem_key]]

local function armoryRef() return cfg().ArmoryRef or 'armory' end

--- True when the row was issued by the armory (its item is in the holder's inventory).
function A.IsArmoryHeld(row)
    return type(row) == 'table' and row.issue_ref == armoryRef() and row.holder_cid ~= nil
end

local function isArmoryResource(invoker)
    return invoker ~= nil and type(cfg().ArmoryResources) == 'table' and cfg().ArmoryResources[invoker] == true
end

function A.Kind(kind)
    if type(kind) ~= 'string' or #kind > 24 then return nil end
    return (cfg().Kinds or {})[kind]
end

--- A serial as stored: 1..32 letters, digits and dashes, upper case. nil when invalid.
function A.NormSerial(s)
    if type(s) ~= 'string' or #s < 1 or #s > 32 or not s:match('^[%w%-]+$') then return nil end
    return s:upper()
end

local function optText(v, max, field)
    if v == nil then return true, nil end
    local t = U.cleanText(v, max)
    if not t then return false, U.fail('bad_args', 'Invalid ' .. field .. '.') end
    return true, t
end

--- The public view of an asset row.
function A.View(r)
    if not r then return nil end
    return {
        id = tonumber(r.id), dept = r.dept, kind = r.kind, serial = r.serial, item = r.item, label = r.label,
        state = r.state, holder = r.holder_cid, location = r.location, cost = tonumber(r.cost) or 0,
        acquiredAt = tonumber(r.acquired_at), issuedAt = tonumber(r.issued_at), issuedBy = r.issued_by,
        ref = r.issue_ref, updatedAt = tonumber(r.updated_at),
    }
end

local function bySerial(serial)
    return MySQL.single.await('SELECT ' .. COLUMNS .. ' FROM pf_gov_dept_assets WHERE serial = ? LIMIT 1', { serial })
end

local function byId(id)
    return MySQL.single.await('SELECT ' .. COLUMNS .. ' FROM pf_gov_dept_assets WHERE id = ? LIMIT 1', { id })
end

local function actorTag(actor)
    if actor.cid then return actor.cid end
    return ('system:' .. (actor.label or 'system')):sub(1, 64)
end

local function isDupErr(err) return tostring(err):lower():find('duplicate', 1, true) ~= nil end

local function changed(asset, event)
    TriggerEvent('pf-government:server:assetChanged', asset, event)
end

-- ── registration ────────────────────────────────────────────────────────

local SERIAL_CHARS = '0123456789ABCDEFGHJKLMNPQRSTUVWXYZ'

local function generateSerial(dept, kindDef)
    local prefix = (cfg().Prefix or {})[dept] or dept:upper():sub(1, 4)
    local tail = {}
    for i = 1, 6 do
        local n = math.random(1, #SERIAL_CHARS)
        tail[i] = SERIAL_CHARS:sub(n, n)
    end
    return A.NormSerial(('%s-%s-%s'):format(prefix, kindDef.code or 'AST', table.concat(tail)))
end

--- RegisterAsset(dept, spec, opts): a new asset in stock.
--- spec = { kind, serial?, item?, label?, location?, cost? }; opts = { key, actor }.
function A.Register(dept, spec, opts, invoker)
    opts = type(opts) == 'table' and opts or {}
    spec = type(spec) == 'table' and spec or {}
    if not D.IsDept(dept) then return U.fail('bad_args', 'Unknown department.') end
    local kindDef = A.Kind(spec.kind)
    if not kindDef then return U.fail('bad_args', 'Unknown asset kind.') end
    if type(kindDef.depts) ~= 'table' or kindDef.depts[dept] ~= true then
        return U.fail('bad_args', 'This department does not hold that kind of equipment.')
    end
    local key = opts.key
    if not U.validKey(key) then return U.fail('bad_args', 'A valid key is required.') end
    local serial
    if spec.serial ~= nil then
        serial = A.NormSerial(spec.serial)
        if not serial then return U.fail('bad_args', 'A serial is 1 to 32 letters, digits or dashes.') end
    end
    local item
    if spec.item ~= nil then
        if type(spec.item) ~= 'string' or #spec.item < 1 or #spec.item > 48 or not spec.item:match('^[%w_%-]+$') then
            return U.fail('bad_args', 'Invalid item name.')
        end
        item = spec.item
    end
    local okL, label = optText(spec.label, 64, 'label')
    if not okL then return label end
    local okP, location = optText(spec.location, 48, 'location')
    if not okP then return location end
    local cost = 0
    if spec.cost ~= nil then
        cost = U.int(spec.cost, 0, U.int(cfg().MaxCost, 0, 2147483647) or 1000000)
        if not cost then return U.fail('bad_args', 'Invalid cost.') end
    end

    local actor, aerr = D.ResolveActor(opts.actor, invoker)
    if not actor then return aerr end
    if actor.kind == 'player' and not D.IsManager(actor.member, dept) then
        return U.fail('no_permission', 'Only a manager of this department can register equipment.')
    end

    local lockNames = { 'dak:' .. key }
    if serial then lockNames[2] = 'das:' .. serial end
    return U.withLocks(lockNames, function()
        if not U.dbReady() then return U.fail('db_unavailable', 'Department records are unavailable right now.') end
        local prior = MySQL.single.await('SELECT ' .. COLUMNS .. ' FROM pf_gov_dept_assets WHERE idem_key = ? LIMIT 1', { key })
        if prior then
            if prior.dept == dept and prior.kind == spec.kind and (serial == nil or prior.serial == serial) then
                return { ok = true, duplicate = true, asset = A.View(prior) }
            end
            return U.fail('key_reused', 'This key was used for a different registration.')
        end
        if serial and bySerial(serial) then
            return U.fail('conflict', 'That serial is already registered.')
        end
        local t = U.now()
        local id, lastErr
        for _ = 1, serial and 1 or 5 do
            local s = serial or generateSerial(dept, kindDef)
            local ok, res = pcall(MySQL.insert.await, [[INSERT INTO pf_gov_dept_assets
                (dept, kind, serial, item, label, state, holder_cid, location, cost, acquired_at, updated_at, idem_key)
                VALUES (?, ?, ?, ?, ?, 'in_stock', NULL, ?, ?, ?, ?, ?)]],
                { dept, spec.kind, s, item, label, location, cost, t, t, key })
            if ok and res then id = res break end
            lastErr = res
            if not ok and not isDupErr(res) then error(res) end
            -- a duplicate: the key raced in (return its row) or a generated serial collided (try another)
            local again = MySQL.single.await('SELECT ' .. COLUMNS .. ' FROM pf_gov_dept_assets WHERE idem_key = ? LIMIT 1', { key })
            if again then return { ok = true, duplicate = true, asset = A.View(again) } end
            if serial then return U.fail('conflict', 'That serial is already registered.') end
        end
        if not id then error(lastErr or 'asset insert failed') end
        local row = byId(id)
        MySQL.insert.await([[INSERT INTO pf_gov_dept_asset_events
            (asset_id, dept, event, from_state, to_state, actor_cid, actor_resource, holder_cid, note, at, idem_key)
            VALUES (?, ?, 'register', NULL, 'in_stock', ?, ?, NULL, NULL, ?, NULL)]],
            { id, dept, actor.cid, invoker and invoker:sub(1, 48) or nil, t })
        D.Audit(dept, 'asset_register', actor.cid, row.serial, { kind = spec.kind, cost = cost, key = key, actorKind = actor.kind },
            invoker and invoker:sub(1, 48) or nil)
        local view = A.View(row)
        changed(view, 'register')
        return { ok = true, asset = view }
    end)
end

-- ── changes (issue, return, manager moves) ──────────────────────────────

--- The common path of every change of an existing asset. `plan(asset, actor)` checks the
--- transition and permissions and returns { event, to, holder, issued = bool, location?, ref?,
--- note? } or a failure table. The asset row is changed with a compare-and-set on its state, then
--- the event row stores the key; when that insert fails the change is put back.
local function change(serial, opts, invoker, sameCall, plan)
    serial = A.NormSerial(serial)
    if not serial then return U.fail('bad_args', 'Invalid serial.') end
    local key = opts.key
    if not U.validKey(key) then return U.fail('bad_args', 'A valid key is required.') end
    local actor, aerr = D.ResolveActor(opts.actor, invoker)
    if not actor then return aerr end
    return U.withLocks({ 'das:' .. serial, 'daek:' .. key }, function()
        if not U.dbReady() then return U.fail('db_unavailable', 'Department records are unavailable right now.') end
        local row = bySerial(serial)
        local prior = MySQL.single.await(
            'SELECT asset_id, event, to_state, holder_cid FROM pf_gov_dept_asset_events WHERE idem_key = ? LIMIT 1', { key })
        if prior then
            if row and tonumber(prior.asset_id) == tonumber(row.id) and sameCall(prior) then
                return { ok = true, duplicate = true, asset = A.View(row), holder = prior.holder_cid }
            end
            return U.fail('key_reused', 'This key was used for a different change.')
        end
        if not row then return U.fail('not_found', 'No asset has that serial.') end
        local p = plan(row, actor)
        if p.ok == false then return p end
        local t = U.now()
        local holder, issuedAt, issuedBy, ref
        if p.issued then
            holder, issuedAt, issuedBy, ref = p.holder, t, actorTag(actor), p.ref
        elseif p.keep then
            -- armory equipment marked lost: the row keeps who held it and how it was issued
            holder, issuedAt, issuedBy, ref = row.holder_cid, row.issued_at, row.issued_by, row.issue_ref
        end
        local n = MySQL.update.await([[UPDATE pf_gov_dept_assets SET state = ?, holder_cid = ?, issued_at = ?, issued_by = ?,
            issue_ref = ?, location = ?, updated_at = ? WHERE id = ? AND state = ?]],
            { p.to, holder, issuedAt, issuedBy, ref, p.location or row.location, t, row.id, row.state })
        if not n or n < 1 then return U.fail('busy', 'This asset changed meanwhile. Try again.') end
        local ok, err = pcall(MySQL.insert.await, [[INSERT INTO pf_gov_dept_asset_events
            (asset_id, dept, event, from_state, to_state, actor_cid, actor_resource, holder_cid, note, at, idem_key)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)]],
            { row.id, row.dept, p.event, row.state, p.to, actor.cid, invoker and invoker:sub(1, 48) or nil,
                p.holder or row.holder_cid, p.note, t, key })
        if not ok then
            -- no key stored: put the asset back so a retry with the same key starts clean
            MySQL.update.await([[UPDATE pf_gov_dept_assets SET state = ?, holder_cid = ?, issued_at = ?, issued_by = ?,
                issue_ref = ?, location = ?, updated_at = ? WHERE id = ? AND state = ?]],
                { row.state, row.holder_cid, row.issued_at, row.issued_by, row.issue_ref, row.location, row.updated_at, row.id, p.to })
            if isDupErr(err) then return U.fail('key_reused', 'This key was used for a different change.') end
            error(err)
        end
        D.Audit(row.dept, 'asset_' .. p.event, actor.cid, row.serial, {
            from = row.state, to = p.to, holder = p.holder or row.holder_cid, key = key, actorKind = actor.kind,
        }, invoker and invoker:sub(1, 48) or nil)
        local view = A.View(byId(row.id))
        changed(view, p.event)
        if p.notify then
            local P = U.getPlayerByCid(p.notify)
            if P and P.PlayerData and P.PlayerData.source then
                TriggerClientEvent('QBCore:Notify', P.PlayerData.source, p.notifyText, 'primary')
            end
        end
        return { ok = true, asset = view, holder = p.holder or row.holder_cid }
    end)
end

local function kindLabel(row)
    local k = A.Kind(row.kind)
    return (row.label or (k and k.label) or row.kind) .. ' ' .. row.serial
end

--- IssueAsset(serial, cid, opts): an in-stock asset to a member of its department.
--- opts = { key, actor, ref?, note?, location? }.
function A.Issue(serial, cid, opts, invoker)
    opts = type(opts) == 'table' and opts or {}
    if not U.validCid(cid) then return U.fail('bad_args', 'Invalid citizen id.') end
    local okR, ref = optText(opts.ref, 64, 'reference')
    if not okR then return ref end
    local okN, note = optText(opts.note, 200, 'note')
    if not okN then return note end
    local okP, location = optText(opts.location, 48, 'location')
    if not okP then return location end
    return change(serial, opts, invoker, function(prior)
        return prior.event == 'issue' and prior.holder_cid == cid
    end, function(row, actor)
        if row.state ~= 'in_stock' then
            return U.fail('invalid_state', 'This asset is ' .. tostring(row.state) .. ', not in stock.', { state = row.state })
        end
        local kindDef = A.Kind(row.kind) or {}
        if actor.kind == 'player' then
            local m = actor.member
            if m.dept ~= row.dept then return U.fail('no_permission', 'This equipment belongs to another department.') end
            if not m.onDuty then return U.fail('not_on_duty', 'You must be on duty.') end
            if (cid ~= m.cid or kindDef.selfIssue == false) and not D.IsManager(m, row.dept) then
                return U.fail('no_permission', 'Only a manager can issue this equipment to someone else.')
            end
        end
        local target = D.MemberByCid(cid)
        if target == false then error('players lookup failed') end
        if not target then return U.fail('not_found', 'No such citizen.') end
        if target.dept ~= row.dept then
            return U.fail('invalid_state', 'This citizen does not work for the department that owns the asset.')
        end
        if ref == armoryRef() then
            local lost = MySQL.single.await([[SELECT serial FROM pf_gov_dept_assets WHERE holder_cid = ? AND state = 'lost'
                AND issue_ref = ? LIMIT 1]], { cid, ref })
            if lost then
                return U.fail('conflict', 'Armory equipment lost while held by this officer is unresolved: ' .. tostring(lost.serial), { serial = lost.serial })
            end
        end
        return { event = 'issue', to = 'issued', holder = cid, issued = true, ref = ref, note = note, location = location,
            notify = cid ~= actor.cid and cid or nil, notifyText = 'Issued to you: ' .. kindLabel(row) }
    end)
end

--- ReturnAsset(serial, opts): an issued asset back (to = in_stock | maintenance | lost).
--- opts = { key, actor, to?, note?, location? }.
function A.Return(serial, opts, invoker)
    opts = type(opts) == 'table' and opts or {}
    local to = opts.to or 'in_stock'
    local event = RETURN_TO[to]
    if not event then return U.fail('bad_args', 'A return goes to in_stock, maintenance or lost.') end
    local okN, note = optText(opts.note, 200, 'note')
    if not okN then return note end
    local okP, location = optText(opts.location, 48, 'location')
    if not okP then return location end
    return change(serial, opts, invoker, function(prior)
        return prior.event == event and prior.to_state == to
    end, function(row, actor)
        local armory = row.issue_ref == armoryRef()
        local byArmory = armory and isArmoryResource(invoker)
        -- the armory books in armory equipment that was marked lost when the item turns up
        local lostArmory = row.state == 'lost' and A.IsArmoryHeld(row)
        if row.state ~= 'issued' and not (byArmory and lostArmory and to ~= 'lost') then
            return U.fail('invalid_state', 'This asset is ' .. tostring(row.state) .. ', not issued.', { state = row.state })
        end
        if actor.kind == 'player' then
            local m = actor.member
            if m.cid ~= row.holder_cid and not D.IsManager(m, row.dept) then
                return U.fail('no_permission', 'Only the holder or a manager can return this equipment.')
            end
        end
        if armory and not byArmory then
            -- the item is still in the holder's inventory: only the armory (which takes it first)
            -- books it in; elsewhere a manager may only report it lost, and the holder nothing
            if to ~= 'lost' then
                return U.fail('invalid_state', 'Armory equipment is returned at the armory.', { state = row.state })
            end
            if actor.kind == 'player' and not D.IsManager(actor.member, row.dept) then
                return U.fail('no_permission', 'Only a manager can report armory equipment lost.')
            end
        end
        if armory and to == 'lost' then
            return { event = event, to = to, holder = row.holder_cid, issued = false, keep = true, note = note, location = location }
        end
        return { event = event, to = to, holder = row.holder_cid, issued = false, note = note, location = location }
    end)
end

--- A manager move: repair, found, maintenance, lost, retire (MOVES).
function A.Move(serial, move, opts, invoker)
    opts = type(opts) == 'table' and opts or {}
    local def = type(move) == 'string' and MOVES[move] or nil
    if not def then return U.fail('bad_args', 'Unknown asset action.') end
    local okN, note = optText(opts.note, 200, 'note')
    if not okN then return note end
    local okP, location = optText(opts.location, 48, 'location')
    if not okP then return location end
    return change(serial, opts, invoker, function(prior)
        return prior.event == move
    end, function(row, actor)
        if not def.from[row.state] then
            return U.fail('invalid_state', 'This asset is ' .. tostring(row.state) .. '.', { state = row.state })
        end
        if actor.kind == 'player' and not D.IsManager(actor.member, row.dept) then
            return U.fail('no_permission', 'Only a manager of the department can do that.')
        end
        if move == 'found' and A.IsArmoryHeld(row) then
            -- the item may still be in the holder's inventory: the armory books it in when it is handed over
            return U.fail('invalid_state', 'Lost armory equipment is booked in at the armory when it is handed over.', { state = row.state })
        end
        return { event = move, to = def.to, issued = false, note = note, location = location }
    end)
end

-- ── reads ───────────────────────────────────────────────────────────────

--- GetAsset(serial) -> { ok, asset }.
function A.Get(serial)
    serial = A.NormSerial(serial)
    if not serial then return U.fail('bad_args', 'Invalid serial.') end
    if not U.dbReady() then return U.fail('db_unavailable', 'Department records are unavailable right now.') end
    local ok, row = pcall(bySerial, serial)
    if not ok then return U.fail('db_unavailable', 'Department records are unavailable right now.') end
    if not row then return U.fail('not_found', 'No asset has that serial.') end
    return { ok = true, asset = A.View(row) }
end

--- ListAssets(dept, filter): filter = { holder?, state?, kind?, location?, beforeId?, limit 1..100 }.
function A.List(dept, filter)
    if not D.IsDept(dept) then return U.fail('bad_args', 'Unknown department.') end
    filter = type(filter) == 'table' and filter or {}
    local where, params = { 'dept = ?' }, { dept }
    if filter.holder ~= nil then
        if not U.validCid(filter.holder) then return U.fail('bad_args', 'Invalid holder.') end
        where[#where + 1] = 'holder_cid = ?'; params[#params + 1] = filter.holder
    end
    if filter.state ~= nil then
        if not STATES[filter.state] then return U.fail('bad_args', 'Invalid state.') end
        where[#where + 1] = 'state = ?'; params[#params + 1] = filter.state
    end
    if filter.kind ~= nil then
        if not A.Kind(filter.kind) then return U.fail('bad_args', 'Unknown asset kind.') end
        where[#where + 1] = 'kind = ?'; params[#params + 1] = filter.kind
    end
    if filter.location ~= nil then
        local loc = U.cleanText(filter.location, 48)
        if not loc then return U.fail('bad_args', 'Invalid location.') end
        where[#where + 1] = 'location = ?'; params[#params + 1] = loc
    end
    if filter.beforeId ~= nil then
        local before = U.int(filter.beforeId, 1, 2147483647)
        if not before then return U.fail('bad_args', 'Invalid cursor.') end
        where[#where + 1] = 'id < ?'; params[#params + 1] = before
    end
    local limit = 50
    if filter.limit ~= nil then
        limit = U.int(filter.limit, 1, 100)
        if not limit then return U.fail('bad_args', 'The limit must be 1 to 100.') end
    end
    if not U.dbReady() then return U.fail('db_unavailable', 'Department records are unavailable right now.') end
    local ok, rows = pcall(MySQL.query.await, 'SELECT ' .. COLUMNS .. ' FROM pf_gov_dept_assets WHERE '
        .. table.concat(where, ' AND ') .. ' ORDER BY id DESC LIMIT ' .. limit, params)
    if not ok or type(rows) ~= 'table' then return U.fail('db_unavailable', 'Department records are unavailable right now.') end
    local list = {}
    for _, r in ipairs(rows) do list[#list + 1] = A.View(r) end
    return { ok = true, list = list, nextCursor = #list == limit and list[#list].id or nil }
end

--- The change history of one asset (newest first, at most 50 rows).
function A.History(serial)
    serial = A.NormSerial(serial)
    if not serial then return U.fail('bad_args', 'Invalid serial.') end
    if not U.dbReady() then return U.fail('db_unavailable', 'Department records are unavailable right now.') end
    local ok, rows = pcall(MySQL.query.await, [[SELECT e.id, e.event, e.from_state, e.to_state, e.actor_cid, e.actor_resource,
        e.holder_cid, e.note, e.at FROM pf_gov_dept_asset_events e JOIN pf_gov_dept_assets a ON a.id = e.asset_id
        WHERE a.serial = ? ORDER BY e.id DESC LIMIT 50]], { serial })
    if not ok or type(rows) ~= 'table' then return U.fail('db_unavailable', 'Department records are unavailable right now.') end
    local list = {}
    for _, r in ipairs(rows) do
        list[#list + 1] = { id = tonumber(r.id), event = r.event, from = r.from_state, to = r.to_state, actor = r.actor_cid,
            resource = r.actor_resource, holder = r.holder_cid, note = r.note, at = tonumber(r.at) }
    end
    return { ok = true, list = list }
end

--- Counts per state of a department's assets (the app overview).
function A.Counts(dept)
    if not D.IsDept(dept) or not U.dbReady() then return nil end
    local ok, rows = pcall(MySQL.query.await, 'SELECT state, COUNT(*) AS n FROM pf_gov_dept_assets WHERE dept = ? GROUP BY state', { dept })
    if not ok or type(rows) ~= 'table' then return nil end
    local out = {}
    for _, r in ipairs(rows) do out[r.state] = tonumber(r.n) or 0 end
    return out
end

-- ── deleted characters ──────────────────────────────────────────────────

--- Equipment still issued to a deleted character is marked lost (it left the city with them).
function A.RemoveCharacter(cid)
    if not U.validCid(cid) or not U.dbReady() then return 0 end
    local ok, rows = pcall(MySQL.query.await, "SELECT id, dept, serial FROM pf_gov_dept_assets WHERE holder_cid = ? AND state = 'issued'", { cid })
    if not ok or type(rows) ~= 'table' then return 0 end
    local t, n = U.now(), 0
    for _, r in ipairs(rows) do
        local okU, c = pcall(MySQL.update.await, [[UPDATE pf_gov_dept_assets SET state = 'lost', holder_cid = NULL, issued_at = NULL,
            issued_by = NULL, issue_ref = NULL, updated_at = ? WHERE id = ? AND state = 'issued']], { t, r.id })
        if okU and c and c > 0 then
            n = n + 1
            pcall(MySQL.insert.await, [[INSERT INTO pf_gov_dept_asset_events
                (asset_id, dept, event, from_state, to_state, actor_cid, actor_resource, holder_cid, note, at, idem_key)
                VALUES (?, ?, 'lost', 'issued', 'lost', NULL, NULL, ?, 'holder character deleted', ?, NULL)]], { r.id, r.dept, cid, t })
            D.Audit(r.dept, 'asset_lost', nil, r.serial, { holder = cid, reason = 'character_deleted' })
        end
    end
    return n
end

AddEventHandler('pfm-core:server:characterDeleted', function(citizenid)
    local src = tonumber(source)
    if src and src > 0 then return end
    A.RemoveCharacter(citizenid)
end)

-- ── exports ─────────────────────────────────────────────────────────────

exports('RegisterAsset', function(dept, spec, opts)
    local allowed, inv = U.callerAllowed('RegisterAsset')
    if not allowed then return U.notAllowed() end
    return A.Register(dept, spec, opts, inv)
end)

exports('IssueAsset', function(serial, cid, opts)
    local allowed, inv = U.callerAllowed('IssueAsset')
    if not allowed then return U.notAllowed() end
    return A.Issue(serial, cid, opts, inv)
end)

exports('ReturnAsset', function(serial, opts)
    local allowed, inv = U.callerAllowed('ReturnAsset')
    if not allowed then return U.notAllowed() end
    return A.Return(serial, opts, inv)
end)

exports('GetAsset', function(serial)
    local allowed = U.callerAllowed('GetAsset')
    if not allowed then return U.notAllowed() end
    return A.Get(serial)
end)

exports('ListAssets', function(dept, filter)
    local allowed = U.callerAllowed('ListAssets')
    if not allowed then return U.notAllowed() end
    return A.List(dept, filter)
end)
