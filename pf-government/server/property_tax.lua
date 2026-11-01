-- =====================================================
-- WEEKLY PROPERTY TAX
-- =====================================================
-- Every owned house is billed once a week: a 'tax' bill to its owner (a citizen bill, so it shows in
-- the citizen Bills app), the 'property' tax rate of the house value with a minimum (config.lua,
-- Config.Taxes.PropertyTax). The houses come from pfm-houses' read-only export GetOwnedHouses();
-- this resource never reads the housing tables. Each bill carries ref 'house:<name>' and the week
-- as its period, and the database holds one bill per ref and period (schema v2), so a second run,
-- a restart or a run racing another one never bills a house twice in a week. Paying, overdue, late
-- fees and delinquency are the ordinary bill paths (server/bills.lua); a house is never taken back.
-- While pfm-houses is still setting up its tables it reports no houses (it could not read the prices
-- paid yet): the run is skipped and tried again RetrySeconds later, never billed on listing prices.

PropertyTax = PropertyTax or {}
local P = PropertyTax

local WEEK = 604800
local MONDAY = 345600    -- 1970-01-05 00:00 UTC was a Monday: weeks run Monday to Sunday, UTC
local MAX_VALUE = 1e9    -- a house value above this is a data error, not a price

local function cents(n) return math.floor((tonumber(n) or 0) * 100 + 0.5) / 100 end
local function money(n)
    n = cents(n)
    if n % 1 == 0 then return ('$%d'):format(math.floor(n)) end
    return ('$%.2f'):format(n)
end

local function settings() return (Config.Taxes and Config.Taxes.PropertyTax) or {} end

-- 'YYYY-MM-DD' of a day number since 1970-01-01, by the calendar alone (os.date would use the
-- server's time zone, and the week key must not move with it)
local function civilDate(days)
    local z = days + 719468
    local era = (z >= 0 and z or z - 146096) // 146097
    local doe = z - era * 146097
    local yoe = (doe - doe // 1460 + doe // 36524 - doe // 146096) // 365
    local doy = doe - (365 * yoe + yoe // 4 - yoe // 100)
    local mp = (5 * doy + 2) // 153
    local d = doy - (153 * mp + 2) // 5 + 1
    local m = mp < 10 and mp + 3 or mp - 9
    local y = yoe + era * 400 + (m <= 2 and 1 or 0)
    return ('%04d-%02d-%02d'):format(math.floor(y), math.floor(m), math.floor(d))
end

--- The week `now` (unix seconds) falls in: its key, the date of its Monday ('YYYY-MM-DD'), and the
--- unix time it starts.
function P.Period(now)
    now = math.floor(tonumber(now) or os.time())
    local start = MONDAY + ((now - MONDAY) // WEEK) * WEEK
    return civilDate(start // 86400), start
end

--- One week's tax on a house worth `value`: the property rate of the value, at least the minimum,
--- in cents. 0 while the tax is off (disabled by the mayor or at 0%).
function P.Amount(value)
    if (tonumber(GetTaxRate('property')) or 0) <= 0 then return 0 end
    value = tonumber(value) or 0
    if value ~= value or value < 0 then value = 0 end
    local tax = tonumber(CalculateTax(math.min(value, MAX_VALUE), 'property')) or 0
    return cents(math.max(tax, tonumber(settings().Minimum) or 0))
end

-- A row of the housing export, checked: it comes from another resource
local function cleanHouse(row)
    if type(row) ~= 'table' then return nil end
    local house, cid = row.house, row.citizenid
    if type(house) ~= 'string' or house == '' or #house > 64 then return nil end
    if type(cid) ~= 'string' or cid == '' or #cid > 50 or not cid:match('^[%w]+$') then return nil end
    local value = tonumber(row.value) or 0
    if value ~= value or value < 0 or value > MAX_VALUE then value = 0 end
    local label = type(row.label) == 'string' and row.label ~= '' and row.label:sub(1, 100) or house
    return { house = house, citizenid = cid, value = math.floor(value), label = label }
end

local function housingResource()
    local res = settings().Resource
    return type(res) == 'string' and res ~= '' and res or 'pfm-houses'
end

local notReadySaid = false

--- Every owned house from the housing resource's read-only export, each row checked (the house
--- utilities use it too): list, skipped rows; or nil and why: 'no_housing' (not running),
--- 'not_ready' (still setting up its tables) or 'export_failed'.
function P.Houses()
    local resource = housingResource()
    if GetResourceState(resource) ~= 'started' then return nil, 'no_housing' end
    local ok, houses, why = pcall(function() return exports[resource]:GetOwnedHouses() end)
    if not ok then
        print(('^1[PF-GOVERNMENT]^7 %s:GetOwnedHouses failed (%s)'):format(resource, tostring(houses)))
        return nil, 'export_failed'
    end
    if type(houses) ~= 'table' then
        -- false is "not ready yet" (also when the reason did not make it across the export boundary)
        if houses == false or why == 'not_ready' then
            if not notReadySaid then print(('^3[PF-GOVERNMENT]^7 %s is not ready yet; house billing waits for it'):format(resource)) end
            notReadySaid = true
            return nil, 'not_ready'
        end
        print(('^1[PF-GOVERNMENT]^7 %s:GetOwnedHouses returned no list (%s)'):format(resource, tostring(why or houses)))
        return nil, 'export_failed'
    end
    notReadySaid = false
    local list, skipped = {}, 0
    for _, row in ipairs(houses) do
        local h = cleanHouse(row)
        if h then list[#list + 1] = h else skipped = skipped + 1 end
    end
    return list, skipped
end

local function notifyOwner(citizenid, label, amount, dueDays)
    pcall(function()
        local Player = QBCore.Functions.GetPlayerByCitizenId(citizenid)
        if Player then
            NotifyPlayer(Player.PlayerData.source, ('Property tax for %s: %s, due in %d days (Bills app)'):format(label, money(amount), dueDays), 'primary')
        end
    end)
end

local function billWeek(now)
    local cfg = settings()
    local out = { billed = 0, existing = 0, skipped = 0, failed = 0, amount = 0 }
    if cfg.Enabled == false then out.off = 'disabled' return out end
    if GetResourceState(housingResource()) ~= 'started' then out.off = 'no_housing' return out end
    if (tonumber(GetTaxRate('property')) or 0) <= 0 then out.off = 'tax_off' return out end
    if not (GovSchema and GovSchema.Ensure and GovSchema.Ensure()) then out.off = 'no_schema' return out end

    local houses, skipped = P.Houses()
    if not houses then
        -- `retry`: the scheduled task tries again RetrySeconds later instead of a whole interval
        out.off, out.retry = skipped == 'not_ready' and 'not_ready' or 'no_housing', skipped ~= 'no_housing'
        return out
    end
    out.skipped = skipped

    local period = P.Period(now)
    out.period = period
    -- the houses billed this week already (by an earlier run or before a restart)
    local billed = {}
    for _, r in ipairs(MySQL.query.await("SELECT bill_ref FROM pf_gov_bills WHERE bill_period = ? AND bill_ref LIKE 'house:%'", { period }) or {}) do
        billed[r.bill_ref] = true
    end

    local dueDays = math.max(1, math.floor(tonumber(cfg.DueDays) or 7))
    local due = os.date('%Y-%m-%d %H:%M:%S', now + dueDays * 86400)
    local issuer = type(cfg.IssuerName) == 'string' and cfg.IssuerName ~= '' and cfg.IssuerName or 'Tax Office'
    for _, h in ipairs(houses) do
        local ref = 'house:' .. h.house
        if billed[ref] then
            out.existing = out.existing + 1
        else
            billed[ref] = true   -- a house listed twice is billed once
            local amount = P.Amount(h.value)
            if amount <= 0 then
                out.skipped = out.skipped + 1
            else
                -- the unique key still decides: another run may have billed it since the read above
                local created, msg = CreateBill('citizen', h.citizenid, amount, 'tax', due,
                    ('Property tax: %s, week of %s'):format(h.label, period), 'system', issuer, { ref = ref, period = period })
                if created then
                    out.billed = out.billed + 1
                    out.amount = cents(out.amount + amount)
                    notifyOwner(h.citizenid, h.label, amount, dueDays)
                elseif msg == 'duplicate' then
                    out.existing = out.existing + 1
                else
                    out.failed = out.failed + 1
                end
            end
        end
    end
    return out
end

local running = false

--- Bills every owned house not billed yet for the week of `now` (default: now). Safe to call any
--- number of times. Returns { period, billed, existing, skipped, failed, amount } or { off = reason },
--- with retry = true when it is worth trying again soon (housing still starting, a failed read).
function P.Run(now)
    if running then return { off = 'running' } end
    running = true
    local ok, res = pcall(billWeek, math.floor(tonumber(now) or os.time()))
    running = false
    if not ok then
        print('^1[PF-GOVERNMENT]^7 property tax run failed: ' .. tostring(res))
        return { off = 'error', error = tostring(res), retry = true }
    end
    if (res.billed or 0) > 0 or (res.failed or 0) > 0 then
        print(('^2[PF-GOVERNMENT]^7 property tax %s: %d house(s) billed (%s), %d already billed, %d failed')
            :format(tostring(res.period), res.billed, money(res.amount), res.existing, res.failed))
    end
    return res
end

-- Server console only: bill this week now (the scheduled run does the same every interval)
RegisterCommand('govpropertytax', function(source)
    if tonumber(source) ~= 0 then return end
    local res = P.Run()
    print(('[PF-GOVERNMENT] property tax: %s'):format(res.off and ('not run (' .. res.off .. ')')
        or ('%s: %d billed, %d already billed, %d skipped, %d failed'):format(res.period, res.billed, res.existing, res.skipped, res.failed)))
end, true)
