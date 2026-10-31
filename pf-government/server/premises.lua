-- =====================================================
-- BUSINESS PREMISES: APPROVED SLOTS AND EQUIPMENT
-- =====================================================
-- Government staff approve where a registered business may put each kind of equipment (a slot:
-- type + position, taken from where the official stands). The business owner can then buy equipment
-- of the matching type for an approved slot: paid once from the business's own ledger account, and
-- installed as a persistent prop (pfm-worldobjects fixture) at the slot's position. Business resources
-- read what is installed (GetInstalledEquipment) and react to 'pf-government:server:equipmentChanged'
-- (pf-restaurants raises its storage capacity for fridges, freezers and shelves).
--
-- pf_gov_premises_slots     id, business_id, slot_type, x/y/z/heading, label, approved_by, active
-- pf_gov_premises_equipment id, slot_id (unique), business_id, equipment_type, fixture_id, payment_tx,
--                           installed_by, installed_at

Premises = Premises or {}
local P = Premises

local function cfg() return Config.Premises or {} end
local SLOT_TYPES = {}

local schemaReady, schemaBusy = false, false
function P.EnsureSchema()
    if schemaReady then return end
    while schemaBusy do Wait(0) end
    if schemaReady then return end
    schemaBusy = true
    local ok, err = pcall(function()
        MySQL.query.await([[
            CREATE TABLE IF NOT EXISTS `pf_gov_premises_slots` (
                `id` INT NOT NULL AUTO_INCREMENT,
                `business_id` VARCHAR(100) NOT NULL,
                `slot_type` VARCHAR(32) NOT NULL,
                `x` DOUBLE NOT NULL, `y` DOUBLE NOT NULL, `z` DOUBLE NOT NULL,
                `heading` DOUBLE NOT NULL DEFAULT 0,
                `label` VARCHAR(64) NULL,
                `approved_by` VARCHAR(50) NULL,
                `approved_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
                `active` TINYINT(1) NOT NULL DEFAULT 1,
                PRIMARY KEY (`id`),
                KEY `idx_business` (`business_id`, `active`)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
        ]])
        MySQL.query.await([[
            CREATE TABLE IF NOT EXISTS `pf_gov_premises_equipment` (
                `id` INT NOT NULL AUTO_INCREMENT,
                `slot_id` INT NOT NULL,
                `business_id` VARCHAR(100) NOT NULL,
                `equipment_type` VARCHAR(48) NOT NULL,
                `fixture_id` VARCHAR(48) NULL,
                `payment_tx` VARCHAR(40) NULL,
                `installed_by` VARCHAR(50) NULL,
                `installed_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
                PRIMARY KEY (`id`),
                UNIQUE KEY `uq_slot` (`slot_id`),
                KEY `idx_business` (`business_id`)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
        ]])
    end)
    schemaBusy = false
    if ok then schemaReady = true else print('^1[PF-GOVERNMENT]^7 premises schema: ' .. tostring(err)) end
end

local function slotTypeKnown(t)
    if not next(SLOT_TYPES) then for _, k in ipairs(cfg().SlotTypes or {}) do SLOT_TYPES[k] = true end end
    return SLOT_TYPES[t] == true
end

local function playerCid(src)
    local Player = QBCore.Functions.GetPlayer(src)
    return Player and Player.PlayerData.citizenid or nil
end

local function pedPosition(src)
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return nil end
    local c = GetEntityCoords(ped)
    return { x = c.x, y = c.y, z = c.z, heading = GetEntityHeading(ped) or 0.0 }
end

local function business(businessId)
    if type(businessId) ~= 'string' or businessId == '' then return nil end
    return MySQL.single.await('SELECT * FROM pf_gov_businesses WHERE business_id = ?', { businessId })
end

--- Staff approve a slot where they stand. Returns ok, slot id or error.
function P.ApproveSlot(src, businessId, slotType, label)
    P.EnsureSchema()
    if not HasPermission(src, 'businesses') then return false, 'no_permission' end
    if not business(businessId) then return false, 'business_not_found' end
    if type(slotType) ~= 'string' or not slotTypeKnown(slotType) then return false, 'invalid_slot_type' end
    local pos = pedPosition(src)
    if not pos then return false, 'no_position' end
    local count = tonumber(MySQL.scalar.await('SELECT COUNT(*) FROM pf_gov_premises_slots WHERE business_id = ? AND active = 1', { businessId })) or 0
    if count >= (cfg().MaxSlotsPerBusiness or 40) then return false, 'too_many_slots' end
    -- slots do not overlap
    local spacing = cfg().MinSlotSpacing or 1.0
    for _, s in ipairs(MySQL.query.await('SELECT x, y, z FROM pf_gov_premises_slots WHERE business_id = ? AND active = 1', { businessId }) or {}) do
        if #(vector3(s.x, s.y, s.z) - vector3(pos.x, pos.y, pos.z)) < spacing then return false, 'too_close' end
    end
    label = label ~= nil and tostring(label):gsub('[%c<>]', ''):sub(1, 64) or nil
    local id = MySQL.insert.await('INSERT INTO pf_gov_premises_slots (business_id, slot_type, x, y, z, heading, label, approved_by) VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
        { businessId, slotType, pos.x, pos.y, pos.z, pos.heading, label, playerCid(src) })
    if not id then return false, 'db_error' end
    LogAudit('premises_slot_approved', playerCid(src) or 'system', GetPlayerName(src), 'business', businessId, { slot = id, type = slotType })
    return true, id
end

--- Staff withdraw approval for an empty slot.
function P.RemoveSlot(src, slotId)
    P.EnsureSchema()
    if not HasPermission(src, 'businesses') then return false, 'no_permission' end
    slotId = tonumber(slotId)
    local slot = slotId and MySQL.single.await('SELECT * FROM pf_gov_premises_slots WHERE id = ? AND active = 1', { slotId })
    if not slot then return false, 'slot_not_found' end
    if MySQL.scalar.await('SELECT id FROM pf_gov_premises_equipment WHERE slot_id = ?', { slotId }) then return false, 'slot_in_use' end
    MySQL.update.await('UPDATE pf_gov_premises_slots SET active = 0 WHERE id = ?', { slotId })
    LogAudit('premises_slot_removed', playerCid(src) or 'system', GetPlayerName(src), 'business', slot.business_id, { slot = slotId })
    return true
end

--- Who may buy equipment for a business: its owner on the government record; for a restaurant, its
--- owner role in pf-restaurants (permission premises.buy, which only 'all' grants); for a job-owned
--- business (owner job:<name>), a boss of that job.
local function mayManagePremises(src, biz, cid)
    if biz.owner_id == cid then return true end
    local kind, localId = tostring(biz.business_id):match('^(%a+):(.+)$')
    if kind == 'restaurant' and GetResourceState('pf-restaurants') == 'started' then
        local ok, allowed = pcall(function() return exports['pf-restaurants']:HasPermission(src, localId, 'premises.buy') end)
        return ok and allowed == true
    end
    if type(biz.owner_id) == 'string' and biz.owner_id:sub(1, 4) == 'job:' then
        local Player = QBCore.Functions.GetPlayer(src)
        local job = Player and Player.PlayerData.job
        return job ~= nil and job.name == biz.owner_id:sub(5) and job.isboss == true
    end
    return false
end

--- For the field apps: the same "who manages this business" rule.
function P.MayManage(src, biz, cid) return mayManagePremises(src, biz, cid) end
P.SlotTypeKnown = function(t) return slotTypeKnown(t) end

local buying = {}

--- The business owner buys equipment for an approved slot. Checks: owner of the business on the
--- government record, the business may trade, standing at the slot, the slot is approved, empty and of
--- the equipment's type; payment is one keyed ledger transfer from the business account.
function P.BuyEquipment(src, slotId, equipmentType)
    P.EnsureSchema()
    slotId = tonumber(slotId)
    local equipment = type(equipmentType) == 'string' and (cfg().Equipment or {})[equipmentType]
    if not slotId or not equipment then return false, 'invalid_request' end
    local cid = playerCid(src)
    if not cid then return false, 'no_player' end
    if buying[slotId] then return false, 'busy' end
    buying[slotId] = true
    local ok, res, err = pcall(function()
        local slot = MySQL.single.await('SELECT * FROM pf_gov_premises_slots WHERE id = ? AND active = 1', { slotId })
        if not slot then return false, 'slot_not_found' end
        local biz = business(slot.business_id)
        if not biz or not mayManagePremises(src, biz, cid) then return false, 'not_owner' end
        if not CanBusinessTrade(slot.business_id) then return false, 'business_closed' end
        if equipment.slotType ~= slot.slot_type then return false, 'wrong_slot_type' end
        local pos = pedPosition(src)
        if not pos or #(vector3(pos.x, pos.y, pos.z) - vector3(slot.x, slot.y, slot.z)) > (cfg().InstallRange or 5.0) then return false, 'too_far' end
        if MySQL.scalar.await('SELECT id FROM pf_gov_premises_equipment WHERE slot_id = ?', { slotId }) then return false, 'slot_in_use' end
        if not biz.account_ref or biz.account_ref == '' then return false, 'no_business_account' end

        local key = ('gov:equipment:%d:%s'):format(slotId, equipmentType)
        local price = tonumber(equipment.price) or 0
        local txId = nil
        if price > 0 then
            local pay = PFPayout.Transfer({ from = biz.account_ref, to = 'system:pf-government-equipment', amount = price,
                key = key, kind = 'purchase', reason = ('%s for %s'):format(equipment.label or equipmentType, slot.business_id), actor = cid })
            if not pay.ok then return false, pay.error == 'insufficient_funds' and 'insufficient_funds' or 'payment_failed' end
            txId = pay.txId
        end
        local inserted = MySQL.insert.await('INSERT IGNORE INTO pf_gov_premises_equipment (slot_id, business_id, equipment_type, payment_tx, installed_by) VALUES (?, ?, ?, ?, ?)',
            { slotId, slot.business_id, equipmentType, txId, cid })
        if not inserted or inserted == 0 then
            -- someone else filled the slot meanwhile: the money goes back under its own key
            if price > 0 then
                PFPayout.Transfer({ from = 'system:pf-government-equipment', to = biz.account_ref, amount = price, key = key .. ':refund', kind = 'refund', reason = 'Slot already filled' })
            end
            return false, 'slot_in_use'
        end
        -- the prop stands at the approved position, never at a client position
        if equipment.model and GetResourceState('pfm-worldobjects') == 'started' then
            local okF, fixtureId = pcall(function()
                return exports['pfm-worldobjects']:CreateFixture({ model = equipment.model, ownerRef = slot.business_id,
                    coords = { x = slot.x, y = slot.y, z = slot.z }, heading = slot.heading })
            end)
            if okF and fixtureId then
                MySQL.update.await('UPDATE pf_gov_premises_equipment SET fixture_id = ? WHERE slot_id = ?', { fixtureId, slotId })
            end
        end
        LogAudit('premises_equipment_bought', cid, GetPlayerName(src), 'business', slot.business_id, { slot = slotId, equipment = equipmentType, price = price })
        TriggerEvent('pf-government:server:equipmentChanged', slot.business_id)
        return true, slotId
    end)
    buying[slotId] = nil
    if not ok then
        print('^1[PF-GOVERNMENT]^7 equipment purchase failed: ' .. tostring(res))
        return false, 'internal_error'
    end
    return res, err
end

--- Slots of a business with what is installed in each.
function P.GetPremises(businessId)
    P.EnsureSchema()
    local slots = MySQL.query.await([[SELECT s.id, s.slot_type, s.x, s.y, s.z, s.heading, s.label, e.equipment_type, e.installed_at
        FROM pf_gov_premises_slots s LEFT JOIN pf_gov_premises_equipment e ON e.slot_id = s.id
        WHERE s.business_id = ? AND s.active = 1 ORDER BY s.id]], { businessId }) or {}
    return slots
end

--- Installed equipment of a business: list of { equipmentType, slotType, storage = {...} }.
function P.GetInstalledEquipment(businessId)
    P.EnsureSchema()
    local out = {}
    for _, row in ipairs(MySQL.query.await([[SELECT e.equipment_type, e.slot_id, s.x, s.y, s.z, s.heading
        FROM pf_gov_premises_equipment e JOIN pf_gov_premises_slots s ON s.id = e.slot_id
        WHERE e.business_id = ? AND s.active = 1 ORDER BY e.slot_id]], { businessId }) or {}) do
        local def = (cfg().Equipment or {})[row.equipment_type] or {}
        out[#out + 1] = { equipmentType = row.equipment_type, slotType = def.slotType, storage = def.storage, station = def.station,
            label = def.label, model = def.model, slotId = row.slot_id,
            coords = { x = tonumber(row.x) or 0.0, y = tonumber(row.y) or 0.0, z = tonumber(row.z) or 0.0 }, heading = tonumber(row.heading) or 0.0 }
    end
    return out
end

exports('GetPremises', function(businessId) return P.GetPremises(businessId) end)
exports('GetInstalledEquipment', function(businessId) return P.GetInstalledEquipment(businessId) end)

-- ── NUI actions (government app; the router sets data.source to the real sender) ─────────────────

--- What a player may see of a business's premises: staff, or whoever may manage them (owner, owner
--- role, job boss). Returns { ok, data = { slots, catalog, slotTypes } }.
function P.ListFor(src, businessId)
    P.EnsureSchema()
    local biz = business(tostring(businessId or ''))
    if not biz or not (IsGovernmentEmployee(src) or mayManagePremises(src, biz, playerCid(src))) then
        return { ok = false, error = 'no_permission' }
    end
    local catalog = {}
    for key, def in pairs(cfg().Equipment or {}) do
        catalog[#catalog + 1] = { key = key, label = def.label, slotType = def.slotType, price = def.price }
    end
    table.sort(catalog, function(x, y) return x.key < y.key end)
    return { ok = true, data = { businessId = biz.business_id, slots = P.GetPremises(biz.business_id), catalog = catalog, slotTypes = cfg().SlotTypes or {} } }
end

-- for business apps (PF Computer): src is the player the calling resource authenticated
exports('ListPremisesFor', function(src, businessId) return P.ListFor(src, businessId) end)
exports('BuyPremisesEquipment', function(src, slotId, equipmentType)
    local ok, err = P.BuyEquipment(src, slotId, equipmentType)
    return { ok = ok, error = not ok and err or nil }
end)

RegisterNUICallback('premises:list', function(data, cb)
    cb(P.ListFor(data.source or source, data.businessId))
end)

RegisterNUICallback('premises:slot:approve', function(data, cb)
    local ok, res = P.ApproveSlot(data.source or source, tostring(data.businessId or ''), data.slotType, data.label)
    cb(ok and { ok = true, data = { slotId = res } } or { ok = false, error = res })
end)

RegisterNUICallback('premises:slot:remove', function(data, cb)
    local ok, err = P.RemoveSlot(data.source or source, data.slotId)
    cb({ ok = ok, error = err })
end)

RegisterNUICallback('premises:equipment:buy', function(data, cb)
    local ok, err = P.BuyEquipment(data.source or source, data.slotId, data.equipmentType)
    cb({ ok = ok, error = not ok and err or nil })
end)
