-- Hospital supplies and rig restock (batch 20C; architecture 2 AJ, integration matrix "Supplies").
--
-- Where the stock comes from: each hospital has a supply room stash (pf_hosp_supply_<hospital>).
-- Departments buy into it through pf-government procurement (the pf-stores buyer kind 'facility',
-- buyer ids ems:pillbox / ems:paleto): a trucker brings the pallet, on-duty staff unpack it into the
-- stash. Staff open the supply room with pf-government's /supplyroom at its stash point.
--
-- Rig restock: a medic who parks an ambulance ("rig") at the hospital's ambulance bay tops up the
-- rig's medbag stock (pf_medbag_<plate>, the stash 17D's medbag opens) to the par levels below, from
-- the supply room stash: items leave the supply room first and are put back if the rig cannot take
-- them, so nothing is created or lost. Everything is read on the server: the medic's job and duty,
-- the medic's and the rig's positions, the rig's model and plate, the stash counts. The client only
-- asks (/restockrig or the net event, no arguments).
--
-- Every stock movement in or out of a hospital stash is one row in pf_hosp_supply_usage
-- (20A's medical schema v8): reason 'rig_restock' per item moved, 'delivery' per item a purchase
-- brought (pf-government:server:facilityStockDelivered, ref_id = the supply order id, keyed
-- pf-ambulancejob:supply:delivery:<orderId>:<item> so a repeated notice is logged once).

PFHospital = PFHospital or {}
local H = PFHospital
H.Supplies = H.Supplies or {}
local S = H.Supplies

-- Config.Hospital.Supplies overrides any of these. The stash ids and sizes must match pf-government's
-- procurement buyers (Config.Procurement.Buyers), which deliver into them. Positions are first
-- placements: check each in game.
S.DEFAULTS = {
    Rooms = {
        pillbox = {
            stash = { id = 'pf_hosp_supply_pillbox', label = 'Pillbox supply room', slots = 50, maxweight = 600000 },
            bay = vector3(299.84, -577.28, 43.26), bayRadius = 18.0,
        },
        paleto = {
            stash = { id = 'pf_hosp_supply_paleto', label = 'Paleto supply room', slots = 40, maxweight = 400000 },
            bay = vector3(-240.6, 6334.4, 32.4), bayRadius = 18.0,
        },
    },
    -- what a restocked rig carries (items in its medbag stock)
    RigPar = {
        bandage = 10, ifaks = 4, painkillers = 6, tourniquet = 2, pressure_dressing = 4, hemostatic_gauze = 2,
        chest_seal = 2, splint = 2, c_collar = 1, iv_kit = 2, saline_bag = 2, burn_dressing = 2,
    },
    RigReach = 8.0,     -- medic to the rig (server positions) when not sitting in it
    RateSeconds = 5,
}

local function merged(base, over)
    if type(over) ~= 'table' then return base end
    local out = {}
    for k, v in pairs(base) do out[k] = v end
    for k, v in pairs(over) do out[k] = v end
    return out
end
function S.Cfg() return merged(S.DEFAULTS, (Config.Hospital or {}).Supplies) end
local cfg = S.Cfg

local function inventory(name, ...)
    local args, n = { ... }, select('#', ...)
    local ok, res = pcall(function()
        local e = exports['pfm-inventory']
        return e[name](e, table.unpack(args, 1, n))
    end)
    if not ok then return nil end
    return res
end
S.Inventory = inventory

local function ensureStash(s)
    if not inventory('GetInventory', s.id) then inventory('CreateInventory', s.id, { label = s.label, maxweight = s.maxweight, slots = s.slots }) end
    return inventory('GetInventory', s.id) ~= nil
end

--- How many of `item` a stash holds now.
function S.Count(stashId, item)
    local stash = inventory('GetInventory', stashId)
    local n = 0
    for _, it in pairs(stash and stash.items or {}) do
        if type(it) == 'table' and it.name == item then n = n + (tonumber(it.amount) or 0) end
    end
    return n
end

-- ── usage log (pf_hosp_supply_usage) ────────────────────────────────────────────────────────────

local warnedTable = false
--- One usage row. `key` (optional) makes the row once-only (UNIQUE idem_key): a repeated
--- delivery notice logs nothing more.
function S.Log(facility, item, qty, reason, refId, key)
    local ok, err = pcall(MySQL.insert.await,
        'INSERT IGNORE INTO pf_hosp_supply_usage (facility, item, qty, reason, ref_id, at, idem_key) VALUES (?, ?, ?, ?, ?, ?, ?)',
        { facility, item, qty, reason, refId, os.time(), key })
    if not ok and not warnedTable then
        warnedTable = true
        print('^3[pf-ambulancejob]^7 supply usage not logged (pf_hosp_supply_usage): ' .. tostring(err))
    end
    return ok
end

-- ── rigs ────────────────────────────────────────────────────────────────────────────────────────

local function h32(v)
    v = math.tointeger(tonumber(v) or 0) or 0
    return v & 0xFFFFFFFF
end
local function isRig(veh)
    if not veh or veh == 0 or not DoesEntityExist(veh) then return false end
    local model = h32(GetEntityModel(veh))
    for name in pairs((Config.EMS or {}).Rigs or {}) do
        if h32(GetHashKey(name)) == model then return true end
    end
    return false
end
S.IsRig = isRig

--- The rig's stock id, the same as 17D's medbag (pf_medbag_<plate>).
function S.RigStash(veh)
    local plate = tostring(GetVehicleNumberPlateText(veh) or ''):gsub('[^%w]', ''):upper():sub(1, 8)
    if plate == '' then return nil end
    return 'pf_medbag_' .. plate, plate
end

--- The room whose ambulance bay contains `pos`.
function S.RoomAt(pos)
    if not pos then return nil end
    for id, r in pairs(cfg().Rooms) do
        if r.bay and H.Dist(pos, r.bay) <= (tonumber(r.bayRadius) or 15.0) then return id, r end
    end
    return nil
end

local function rigFor(src, pos)
    local ped = GetPlayerPed(src)
    local inside = ped and ped ~= 0 and GetVehiclePedIsIn(ped, false) or 0
    if inside ~= 0 and isRig(inside) then return inside end
    local best, bestD
    for _, veh in ipairs(GetAllVehicles() or {}) do
        if isRig(veh) then
            local d = H.Dist(pos, GetEntityCoords(veh))
            if d <= cfg().RigReach and (not best or d < bestD) then best, bestD = veh, d end
        end
    end
    return best
end

local function restockLocked(roomId, room, rigStash, plate)
    local moved, short = {}, {}
    local items = {}
    for item in pairs(cfg().RigPar) do items[#items + 1] = item end
    table.sort(items)
    for _, item in ipairs(items) do
        local par = math.floor(tonumber(cfg().RigPar[item]) or 0)
        local need = par - S.Count(rigStash, item)
        if need > 0 then
            local n = math.min(need, S.Count(room.stash.id, item))
            local done = false
            if n > 0 and inventory('RemoveItem', room.stash.id, item, n, nil, 'pf-ambulancejob:rig-restock') == true then
                if inventory('AddItem', rigStash, item, n, nil, nil, 'pf-ambulancejob:rig-restock') == true then
                    done = true
                    moved[#moved + 1] = { item = item, qty = n }
                    S.Log(roomId, item, n, 'rig_restock', nil)
                else
                    -- the rig could not take it: back to the supply room, nothing lost
                    inventory('AddItem', room.stash.id, item, n, nil, nil, 'pf-ambulancejob:rig-restock-undo')
                end
            end
            local missing = need - (done and n or 0)
            if missing > 0 then short[#short + 1] = { item = item, qty = missing } end
        end
    end
    inventory('SaveStash', room.stash.id)
    inventory('SaveStash', rigStash)
    return { ok = true, hospital = roomId, plate = plate, moved = moved, short = short }
end

--- Tops up the medic's rig at a hospital bay from that hospital's supply room.
--- Returns { ok, hospital, plate, moved = { { item, qty } }, short = { { item, qty } } } or a failure.
function S.RestockRig(src)
    src = H.Int(src, 1, 65535)
    local P = src and H.Player(src)
    if not P then return H.Fail('offline', 'You are not loaded.') end
    if not H.IsStaff(P) then return H.Fail('no_permission', 'Only on-duty hospital staff can restock an ambulance.') end
    if H.Limited(src, 'rig_restock', cfg().RateSeconds) then return H.Fail('rate_limited', 'Wait a moment.') end
    local pos = H.Pos(src)
    local roomId, room = S.RoomAt(pos)
    if not room then return H.Fail('too_far', 'Restock at a hospital ambulance bay.') end
    local veh = rigFor(src, pos)
    if not veh then return H.Fail('not_found', 'Bring the ambulance to the bay.') end
    if H.Dist(GetEntityCoords(veh), room.bay) > (tonumber(room.bayRadius) or 15.0) then return H.Fail('too_far', 'Park the ambulance in the bay.') end
    local rigStash, plate = S.RigStash(veh)
    if not rigStash then return H.Fail('not_found', 'This ambulance has no plate.') end
    if not ensureStash(room.stash) then return H.Fail('unavailable', 'The supply room is unavailable right now.') end
    local B = (Config.EMS or {}).Medbags or {}
    if not ensureStash({ id = rigStash, label = B.Label or 'Medbag', maxweight = B.MaxWeight or 40000, slots = B.Slots or 20 }) then
        return H.Fail('unavailable', 'The ambulance stock is unavailable right now.')
    end
    -- both stocks are read and changed with inventory calls in between: one restock per rig and
    -- per supply room at a time
    local res, busy = H.WithLock('rigstock:' .. plate, function()
        local inner, busy2 = H.WithLock('supplyroom:' .. roomId, function() return restockLocked(roomId, room, rigStash, plate) end)
        if inner == nil then return H.Fail(busy2 == 'busy' and 'busy' or 'unavailable', 'The supply room is busy. Try again.') end
        return inner
    end)
    if res == nil then return H.Fail(busy == 'busy' and 'busy' or 'unavailable', 'This ambulance is being restocked.') end
    return res
end

-- ── deliveries (pf-government procurement) ──────────────────────────────────────────────────────

--- Which hospital stock a stash id is: a supply room, or a custody infirmary stash (19G).
function S.FacilityOfStash(stashId)
    for id, r in pairs(cfg().Rooms) do if r.stash and r.stash.id == stashId then return id end end
    for id, s in pairs(((Config.Hospital or {}).Custody or {}).Stashes or {}) do if s.id == stashId then return id end end
    return nil
end

function S.OnDelivered(data)
    if type(data) ~= 'table' then return 0 end
    local facility = S.FacilityOfStash(data.stash)
    if not facility then return 0 end
    local n = 0
    for _, it in ipairs(type(data.items) == 'table' and data.items or {}) do
        local qty = H.Int(it.qty, 1, 1000000)
        local orderId = H.Int(data.orderId, 1, 2147483647)
        if type(it.item) == 'string' and #it.item <= 48 and it.item:match('^[%w_]+$') and qty then
            S.Log(facility, it.item, qty, 'delivery', orderId, orderId and ('pf-ambulancejob:supply:delivery:%d:%s'):format(orderId, it.item) or nil)
            n = n + 1
        end
    end
    return n
end

-- server-only (no RegisterNetEvent): pf-government raises it after a purchase is unpacked
AddEventHandler('pf-government:server:facilityStockDelivered', function(data)
    local src = tonumber(source)
    if src and src > 0 then return end
    S.OnDelivered(data)
end)

function S.Boot()
    for _, r in pairs(cfg().Rooms) do if r.stash then ensureStash(r.stash) end end
    return true
end

local function tell(src, res)
    if not res.ok then return H.Notify(src, res.message or res.error, 'error') end
    if #res.moved == 0 then
        return H.Notify(src, #res.short > 0 and 'The supply room has nothing this ambulance needs.' or 'This ambulance is fully stocked.', #res.short > 0 and 'error' or 'primary')
    end
    local parts = {}
    for _, m in ipairs(res.moved) do parts[#parts + 1] = ('%d %s'):format(m.qty, m.item) end
    H.Notify(src, 'Restocked: ' .. table.concat(parts, ', ') .. (#res.short > 0 and ' (the supply room ran short)' or ''), 'success')
end
S.Tell = tell

RegisterNetEvent('pf-ambulancejob:server:RestockRig', function()
    local src = source
    tell(src, S.RestockRig(src))
end)

CreateThread(function()
    local okCore, core = pcall(PFAmbulance.GetCore)
    if okCore and core and core.Commands and core.Commands.Add then
        core.Commands.Add('restockrig', 'Restock your ambulance from the hospital supply room (at the ambulance bay)', {}, false, function(src)
            tell(src, S.RestockRig(src))
        end)
    end
    S.Boot()
end)
