-- =====================================================
-- UTILITIES AND SERVICES SYSTEM
-- =====================================================

function InitializeUtilities()
    print('^2[PF-GOVERNMENT]^7 Utilities system initialized')
end

function HasPower(propertyType, propertyId)
    local result = MySQL.query.await('SELECT power_status FROM pf_gov_utilities WHERE property_type = ? AND property_id = ?',
        {propertyType, propertyId})
    
    if result and #result > 0 then
        return result[1].power_status == 'active'
    end
    
    -- No utility record = assume active (for backwards compatibility)
    return true
end

function HasWater(propertyType, propertyId)
    local result = MySQL.query.await('SELECT water_status FROM pf_gov_utilities WHERE property_type = ? AND property_id = ?',
        {propertyType, propertyId})
    
    if result and #result > 0 then
        return result[1].water_status == 'active'
    end
    
    -- No utility record = assume active
    return true
end

function RegisterUtilityAccount(propertyType, propertyId, propertyName, ownerId, ownerName)
    -- Check if already exists
    local existing = MySQL.query.await('SELECT * FROM pf_gov_utilities WHERE property_type = ? AND property_id = ?',
        {propertyType, propertyId})
    
    if existing and #existing > 0 then
        -- Update owner info
        MySQL.update.await('UPDATE pf_gov_utilities SET owner_id = ?, owner_name = ?, property_name = ? WHERE property_type = ? AND property_id = ?',
            {ownerId, ownerName, propertyName, propertyType, propertyId})
        -- a house's unpaid bills are its previous owner's: a cut-off made for them does not pass to
        -- the new owner (a business keeps its bills, and its cut-off, whoever owns it)
        if propertyType == 'property' and existing[1].owner_id ~= ownerId and existing[1].disconnected_by == 'system' then
            RestoreService(propertyType, propertyId, 'both', 'system', 'System')
        end
        return true, 'Utility account updated'
    end
    
    -- Create new utility account
    local insertId = MySQL.insert.await('INSERT INTO pf_gov_utilities (property_type, property_id, property_name, owner_id, owner_name) VALUES (?, ?, ?, ?, ?)',
        {propertyType, propertyId, propertyName, ownerId, ownerName})
    
    if insertId then
        DebugPrint('Utility account created: ' .. propertyType .. ' ' .. propertyId)
        return true, 'Utility account created', insertId
    end
    
    return false, 'Database error'
end

function DisconnectService(propertyType, propertyId, serviceType, disconnectedBy, disconnectedByName, reason)
    local service = tostring(serviceType or 'power'):lower()
    -- a business cut off is public; read its state first so a repeat cut-off is not news again
    local before = nil
    if propertyType == 'business' and GovEventsOn() then
        before = GovSafe(function()
            return MySQL.single.await('SELECT power_status, water_status, property_name FROM pf_gov_utilities WHERE property_type = ? AND property_id = ? LIMIT 1',
                { propertyType, propertyId })
        end)
    end
    local affected
    if service == 'both' then
        affected = MySQL.update.await('UPDATE pf_gov_utilities SET power_status = ?, water_status = ?, disconnected_by = ?, disconnected_at = NOW() WHERE property_type = ? AND property_id = ?',
            {'disconnected', 'disconnected', disconnectedBy, propertyType, propertyId})
    else
        local statusField = service == 'power' and 'power_status' or 'water_status'
        affected = MySQL.update.await('UPDATE pf_gov_utilities SET ' .. statusField .. ' = ?, disconnected_by = ?, disconnected_at = NOW() WHERE property_type = ? AND property_id = ?',
            {'disconnected', disconnectedBy, propertyType, propertyId})
    end

    if type(before) == 'table' and (tonumber(affected) or 0) > 0 then
        local cut = {}
        if (service == 'both' or service == 'power') and before.power_status ~= 'disconnected' then cut[#cut + 1] = 'power' end
        if (service == 'both' or service == 'water') and before.water_status ~= 'disconnected' then cut[#cut + 1] = 'water' end
        if #cut > 0 then
            GovEmit('gov.utility.disconnected', function()
                local facts = GovBusinessFacts(propertyId)
                local name = before.property_name or facts.business
                local utility = table.concat(cut, ' and ')
                return {
                    businessId = propertyId, business = name, businessType = facts.businessType,
                    utility = utility, services = cut, reason = GovExcerpt(reason, 160),
                    bySystem = disconnectedBy == 'system',
                    businessName = name, type = facts.businessType, service = utility, district = facts.district,
                }, { title = ('%s cut off from %s'):format(tostring(name), utility), district = facts.district, coords = facts.coords,
                    actor = disconnectedBy ~= 'system' and disconnectedBy or nil }
            end)
        end
    end
    
    -- Log audit
    LogAudit('utility_disconnect', disconnectedBy, disconnectedByName, 'utility', propertyType .. '_' .. propertyId, {
        property_type = propertyType,
        property_id = propertyId,
        service_type = service,
        reason = reason
    })
    
    DebugPrint('Service disconnected: ' .. service .. ' for ' .. propertyType .. ' ' .. propertyId)
    return true, 'Service disconnected'
end

function RestoreService(propertyType, propertyId, serviceType, restoredBy, restoredByName)
    local service = tostring(serviceType or 'power'):lower()
    if service == 'both' then
        MySQL.update('UPDATE pf_gov_utilities SET power_status = ?, water_status = ?, disconnected_by = NULL, disconnected_at = NULL WHERE property_type = ? AND property_id = ?',
            {'active', 'active', propertyType, propertyId})
    else
        local statusField = service == 'power' and 'power_status' or 'water_status'
        MySQL.update('UPDATE pf_gov_utilities SET ' .. statusField .. ' = ?, disconnected_by = NULL, disconnected_at = NULL WHERE property_type = ? AND property_id = ?',
            {'active', propertyType, propertyId})
    end
    
    -- Log audit
    LogAudit('utility_restore', restoredBy, restoredByName, 'utility', propertyType .. '_' .. propertyId, {
        property_type = propertyType,
        property_id = propertyId,
        service_type = service
    })
    
    DebugPrint('Service restored: ' .. service .. ' for ' .. propertyType .. ' ' .. propertyId)
    return true, 'Service restored'
end

--- Pays a business utility bill from the business's ledger account straight into the treasury.
function AutoPayBusinessUtility(utility, billId, amount)
    if EnsureBusinessSchema then EnsureBusinessSchema() end
    local treasury = Config.Treasury and Config.Treasury.UseSocietyAccount and Config.Treasury.SocietyAccount
    if not treasury or treasury == '' or not billId then return false end
    local row = MySQL.single.await('SELECT account_ref FROM pf_gov_businesses WHERE business_id = ?', { utility.property_id })
    local account = row and row.account_ref
    if not account or account == '' then return false end
    local res = PFPayout.Transfer({
        from = account, to = 'society:' .. treasury, amount = amount,
        key = ('gov:utility:%s:%s'):format(tostring(utility.id), os.date('%Y%m%d')), kind = 'utility',
        reason = 'Utility bill #' .. billId,
    })
    if not res.ok then return false end
    MySQL.update.await("UPDATE pf_gov_bills SET amount_paid = amount, status = 'paid', paid_at = NOW() WHERE id = ?", { billId })
    return true
end

--- The utility account whose power a bill's delinquency cuts and its payment restores. A house
--- utility bill (ref 'utility:property:<house>', billed to the owner) is the house's while that same
--- citizen still owns it, and nothing once the house changed hands; any other bill is its target's own
--- account (a business; citizens have none, so nothing is cut).
function UtilityAccountOfBill(bill)
    if type(bill) ~= 'table' then return nil end
    local house = type(bill.bill_ref) == 'string' and bill.bill_ref:match('^utility:property:(.+)$')
    if house then
        if bill.target_type ~= 'citizen' then return nil end
        local owner = MySQL.scalar.await("SELECT owner_id FROM pf_gov_utilities WHERE property_type = 'property' AND property_id = ? LIMIT 1", { house })
        if owner == nil or owner ~= bill.target_id then return nil end
        return 'property', house
    end
    return bill.target_type, bill.target_id
end

--- The billing cycle `now` falls in, as a bill period: a house gets one utility bill per cycle,
--- whatever runs twice (the unique key of schema v2).
function UtilityPeriod(now)
    local interval = math.max(60, math.floor(tonumber(Config.Utilities.BillingInterval) or 86400))
    return ('u%d:%d'):format(interval, math.floor((tonumber(now) or os.time()) / interval))
end

local function utilityCharge(utility)
    local amount, parts = 0, {}
    if utility.power_status == 'active' and Config.Utilities.EnablePower then
        amount = amount + (tonumber(Config.Utilities.PowerBillAmount) or 0)
        parts[#parts + 1] = 'Power'
    end
    if utility.water_status == 'active' and Config.Utilities.EnableWater then
        amount = amount + (tonumber(Config.Utilities.WaterBillAmount) or 0)
        parts[#parts + 1] = 'Water'
    end
    return amount, 'Utility bill: ' .. table.concat(parts, ' + ')
end

-- Houses: pf_gov_bills has no house payer (target_type is 'citizen' or 'business'), so a house's
-- utilities are billed to its current owner, as pfm-houses says (GetOwnedHouses, through
-- PropertyTax.Houses), with ref 'utility:property:<house>' and the cycle as period. The account
-- follows the owner too: a house nobody owns is not billed, and a cut-off made for the previous
-- owner's bills is lifted when the house changes hands.
local function billHouses(accounts, period, due, out)
    local list, why
    if PropertyTax and PropertyTax.Houses then list, why = PropertyTax.Houses() else why = 'no_housing' end
    if not list then
        -- still starting or its export failed: worth another try this cycle (not when it is not running)
        out.houses, out.housesPending = why, why == 'not_ready' or why == 'export_failed'
        return
    end
    local owners = {}
    for _, h in ipairs(list) do owners[h.house] = h end
    for _, utility in ipairs(accounts) do
        local h = owners[utility.property_id]
        local owner = h and h.citizenid or nil
        if utility.owner_id ~= owner then
            MySQL.update.await('UPDATE pf_gov_utilities SET owner_id = ?, owner_name = NULL WHERE id = ?', { owner, utility.id })
            if utility.disconnected_by == 'system' then
                RestoreService('property', utility.property_id, 'both', 'system', 'System')
                utility.power_status, utility.water_status = 'active', 'active'
            end
        end
        if owner then
            local amount, description = utilityCharge(utility)
            if amount > 0 then
                local label = utility.property_name and tostring(utility.property_name) ~= '' and tostring(utility.property_name) or h.label or utility.property_id
                local created, msg = CreateBill('citizen', owner, amount, 'utility', due, description .. ' · ' .. label, 'system', 'Utilities Department',
                    { ref = 'utility:property:' .. utility.property_id, period = period })
                if created then
                    out.billed = out.billed + 1
                    out.amount = out.amount + amount
                    MySQL.update.await('UPDATE pf_gov_utilities SET last_bill_date = NOW() WHERE id = ?', { utility.id })
                elseif msg == 'duplicate' then
                    out.existing = out.existing + 1
                else
                    out.failed = out.failed + 1
                end
            end
        end
    end
end

--- Bills every utility account for the cycle of `now`: businesses as before (paid from the business
--- account when it can), houses to their owner (above). opts.housesOnly bills only the houses, for
--- opts.period: the retry of a cycle whose houses could not be read. Returns { period, billed,
--- existing, failed, amount, houses = why houses were skipped, housesPending = worth retrying }.
function ProcessUtilityBilling(now, opts)
    if not Config.Utilities.EnablePower and not Config.Utilities.EnableWater then
        return { off = 'disabled' }
    end
    now = math.floor(tonumber(now) or os.time())
    opts = type(opts) == 'table' and opts or {}
    local period = type(opts.period) == 'string' and opts.period or UtilityPeriod(now)
    local dueDate = os.date('%Y-%m-%d %H:%M:%S', now + 604800) -- 7 days
    local out = { period = period, billed = 0, existing = 0, failed = 0, amount = 0 }

    if not opts.housesOnly then
        local result = MySQL.query.await("SELECT * FROM pf_gov_utilities WHERE property_type = 'business' AND (power_status = ? OR water_status = ?)",
            {'active', 'active'}) or {}
        for _, utility in ipairs(result) do
            local billAmount, description = utilityCharge(utility)
            if billAmount > 0 then
                local _, _, billId = CreateBill(utility.property_type, utility.property_id, billAmount, 'utility',
                    dueDate, description, 'system', 'Utilities Department')
                -- a registered business pays from its own account when it can (one payment per
                -- utility account and billing day); otherwise the bill stays open as before
                if billId then
                    out.billed = out.billed + 1
                    pcall(AutoPayBusinessUtility, utility, tonumber(billId), billAmount)
                end
                MySQL.update.await('UPDATE pf_gov_utilities SET last_bill_date = NOW() WHERE id = ?', {utility.id})
                out.amount = out.amount + billAmount
            end
        end
    end

    local houses = MySQL.query.await("SELECT * FROM pf_gov_utilities WHERE property_type = 'property'", {}) or {}
    if #houses > 0 then billHouses(houses, period, dueDate, out) end

    DebugPrint(('Utility billing %s: %d bills, $%s%s'):format(period, out.billed, tostring(out.amount),
        out.houses and (' (houses skipped: ' .. out.houses .. ')') or ''))
    return out
end

function GetUtilityOverview()
    local rows = MySQL.query.await('SELECT power_status, water_status FROM pf_gov_utilities', {}) or {}

    local power = { active = 0, delinquent = 0, disconnected = 0 }
    local water = { active = 0, delinquent = 0, disconnected = 0 }

    for _, row in ipairs(rows) do
        local p = tostring(row.power_status or 'active')
        local w = tostring(row.water_status or 'active')

        power[p] = (power[p] or 0) + 1
        water[w] = (water[w] or 0) + 1
    end

    return {
        power = power,
        water = water,
        totalAccounts = #rows
    }
end

function GetUtilityDelinquentAccounts()
    -- house utility bills go to the owner: the current owner's, found by their ref (schema v2)
    local houseBills = (GovSchema and GovSchema.Ensure and GovSchema.Ensure())
        and "OR (u.property_type = 'property' AND b.bill_ref = CONCAT('utility:property:', u.property_id) AND b.target_id = u.owner_id)" or ''
    local rows = MySQL.query.await([[ 
        SELECT
            u.property_type,
            u.property_id,
            u.property_name,
            u.owner_id,
            u.owner_name,
            u.power_status,
            u.water_status,
            COALESCE(SUM(CASE WHEN b.bill_type = 'utility' AND b.status IN ('unpaid', 'partial', 'delinquent') THEN (b.amount - b.amount_paid) ELSE 0 END), 0) as amount_owed,
            COALESCE(MAX(TIMESTAMPDIFF(DAY, b.due_date, NOW())), 0) as days_overdue
        FROM pf_gov_utilities u
        LEFT JOIN pf_gov_bills b ON (b.target_type = u.property_type AND b.target_id = u.property_id) ]] .. houseBills .. [[
        GROUP BY u.property_type, u.property_id, u.property_name, u.owner_id, u.owner_name, u.power_status, u.water_status
        HAVING amount_owed > 0 OR u.power_status = 'delinquent' OR u.water_status = 'delinquent'
        ORDER BY amount_owed DESC, days_overdue DESC
    ]], {}) or {}

    return rows
end

-- =====================================================
-- NUI CALLBACKS - UTILITIES
-- =====================================================

RegisterNUICallback('utility:getAll', function(data, cb)
    MySQL.query('SELECT * FROM pf_gov_utilities ORDER BY property_type, property_id', {}, function(result)
        cb({
            ok = true,
            utilities = result or {}
        })
    end)
end)

RegisterNUICallback('utility:disconnect', function(data, cb)
    local src = data.source or source
    
    if not HasPermission(src, 'utilities') then
        cb({ ok = false, error = 'no_permission' })
        return
    end
    
    local citizenid = GetPlayerIdentifier(src)
    local name = GetPlayerName(src)
    
    local success, message = DisconnectService(
        data.propertyType,
        data.propertyId,
        data.serviceType,
        citizenid,
        name,
        data.reason
    )
    
    if success then
        NotifyPlayer(src, 'Service disconnected', 'success')
    end
    
    cb({
        ok = success,
        message = message
    })
end)

RegisterNUICallback('utility:restore', function(data, cb)
    local src = data.source or source
    
    if not HasPermission(src, 'utilities') then
        cb({ ok = false, error = 'no_permission' })
        return
    end
    
    local citizenid = GetPlayerIdentifier(src)
    local name = GetPlayerName(src)
    
    local success, message = RestoreService(
        data.propertyType,
        data.propertyId,
        data.serviceType,
        citizenid,
        name
    )
    
    if success then
        NotifyPlayer(src, 'Service restored', 'success')
    end
    
    cb({
        ok = success,
        message = message
    })
end)

print('^2[PF-GOVERNMENT]^7 Utilities system loaded')

exports('GetUtilityOverview', function()
    return GetUtilityOverview()
end)

exports('GetUtilityDelinquentAccounts', function()
    return GetUtilityDelinquentAccounts()
end)

exports('DisconnectService', function(propertyType, propertyId, serviceType, disconnectedBy, disconnectedByName, reason)
    return DisconnectService(propertyType, propertyId, serviceType, disconnectedBy, disconnectedByName, reason)
end)

exports('RestoreService', function(propertyType, propertyId, serviceType, restoredBy, restoredByName)
    return RestoreService(propertyType, propertyId, serviceType, restoredBy, restoredByName)
end)
