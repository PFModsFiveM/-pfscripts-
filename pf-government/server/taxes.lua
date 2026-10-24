-- =====================================================
-- TAX SYSTEM
-- =====================================================

local TaxCache = {}

local function roundCurrency(value)
    value = tonumber(value) or 0
    return math.floor((value * 100) + 0.5) / 100
end

local function normalizeTaxType(taxType)
    if taxType == nil then
        return ''
    end
    return tostring(taxType):lower()
end

local function toBoolFlag(value)
    local valueType = type(value)
    if valueType == 'boolean' then
        return value
    end
    if valueType == 'number' then
        return value == 1
    end
    if valueType == 'string' then
        local lowered = value:lower()
        return lowered == '1' or lowered == 'true'
    end
    return false
end

local function getConfiguredTaxBounds(taxType, fallbackMin, fallbackMax)
    local normalizedType = normalizeTaxType(taxType)
    local enforcement = Config.Taxes and Config.Taxes.Enforcement and Config.Taxes.Enforcement[normalizedType] or nil

    local minRate = tonumber(fallbackMin) or 0
    local maxRate = tonumber(fallbackMax) or 100

    if enforcement then
        minRate = tonumber(enforcement.min) or minRate
        maxRate = tonumber(enforcement.max) or maxRate
    end

    return minRate, maxRate
end

local function cloneTaxCache()
    local copy = {}
    for taxType, tax in pairs(TaxCache) do
        copy[taxType] = {
            rate = tonumber(tax.rate) or 0,
            min_rate = tonumber(tax.min_rate) or 0,
            max_rate = tonumber(tax.max_rate) or 0,
            enabled = tax.enabled == true,
            description = tax.description
        }
    end
    return copy
end

local function getTaxDefaultFromConfig(taxType)
    local normalizedType = normalizeTaxType(taxType)
    for _, tax in ipairs(Config.Taxes.Defaults or {}) do
        if normalizeTaxType(tax.type) == normalizedType then
            return {
                tax_type = normalizedType,
                rate = tonumber(tax.rate) or 0,
                min_rate = tonumber(tax.min) or 0,
                max_rate = tonumber(tax.max) or 100,
                enabled = 1,
                description = tax.description
            }
        end
    end
    return nil
end

local function hydrateTaxIntoCache(taxType)
    local normalizedType = normalizeTaxType(taxType)
    if normalizedType == '' then
        return nil
    end

    if TaxCache[normalizedType] then
        return TaxCache[normalizedType]
    end

    local row = MySQL.single.await(
        'SELECT tax_type, rate, min_rate, max_rate, enabled, description FROM pf_gov_taxes WHERE tax_type = ? LIMIT 1',
        { normalizedType }
    )

    if not row then
        local seeded = getTaxDefaultFromConfig(normalizedType)
        if seeded then
            MySQL.insert.await(
                'INSERT IGNORE INTO pf_gov_taxes (tax_type, rate, min_rate, max_rate, enabled, description) VALUES (?, ?, ?, ?, ?, ?)',
                {
                    seeded.tax_type,
                    seeded.rate,
                    seeded.min_rate,
                    seeded.max_rate,
                    seeded.enabled,
                    seeded.description
                }
            )
            row = MySQL.single.await(
                'SELECT tax_type, rate, min_rate, max_rate, enabled, description FROM pf_gov_taxes WHERE tax_type = ? LIMIT 1',
                { normalizedType }
            )
        end
    end

    if not row then
        return nil
    end

    TaxCache[normalizedType] = {
        rate = tonumber(row.rate) or 0,
        min_rate = tonumber(row.min_rate) or 0,
        max_rate = tonumber(row.max_rate) or 100,
        enabled = toBoolFlag(row.enabled),
        description = row.description
    }

    return TaxCache[normalizedType]
end

local function loadTaxesFromDatabase()
    TaxCache = {}

    local rows = MySQL.query.await('SELECT tax_type, rate, min_rate, max_rate, enabled, description FROM pf_gov_taxes ORDER BY tax_type', {})
    for _, row in ipairs(rows or {}) do
        local key = normalizeTaxType(row.tax_type)
        if key ~= '' then
            TaxCache[key] = {
                rate = tonumber(row.rate) or 0,
                min_rate = tonumber(row.min_rate) or 0,
                max_rate = tonumber(row.max_rate) or 100,
                enabled = toBoolFlag(row.enabled),
                description = row.description
            }
        end
    end

    return #rows
end

-- Older installs made rate/min_rate/max_rate DECIMAL(5,2) (at most 999.99), which cannot hold the
-- flat vehicle registration fee (max 5000) and makes the defaults below fail on a strict database.
local function WidenTaxColumns()
    local precision = MySQL.scalar.await([[
        SELECT NUMERIC_PRECISION FROM information_schema.COLUMNS
        WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'pf_gov_taxes' AND COLUMN_NAME = 'max_rate'
    ]])
    if precision and tonumber(precision) < 10 then
        MySQL.query.await([[
            ALTER TABLE pf_gov_taxes
                MODIFY `rate` DECIMAL(10,2) NOT NULL DEFAULT 0.00,
                MODIFY `min_rate` DECIMAL(10,2) NOT NULL DEFAULT 0.00,
                MODIFY `max_rate` DECIMAL(10,2) NOT NULL DEFAULT 100.00
        ]])
        print('^2[PF-GOVERNMENT]^7 Widened pf_gov_taxes rate columns to DECIMAL(10,2)')
    end
end

local function EnsureTaxDefaults()
    WidenTaxColumns()
    local defaults = Config.Taxes.Defaults or {}
    if #defaults == 0 then
        return
    end

    local allowed = {}
    for _, tax in ipairs(defaults) do
        local taxType = normalizeTaxType(tax.type)
        if taxType ~= '' and tax.rate ~= nil then
            allowed[#allowed + 1] = taxType

            -- Insert missing defaults only. Existing rates remain DB-authoritative.
            local minRate, maxRate = getConfiguredTaxBounds(taxType, tax.min, tax.max)

            MySQL.insert.await(
                'INSERT IGNORE INTO pf_gov_taxes (tax_type, rate, min_rate, max_rate, enabled, description) VALUES (?, ?, ?, ?, 1, ?)',
                {
                    taxType,
                    tonumber(tax.rate) or 0,
                    minRate,
                    maxRate,
                    tax.description
                }
            )

            -- Keep metadata aligned with config while preserving live rate/enabled values.
            MySQL.update.await(
                'UPDATE pf_gov_taxes SET min_rate = ?, max_rate = ?, description = ? WHERE tax_type = ?',
                {
                    minRate,
                    maxRate,
                    tax.description,
                    taxType
                }
            )
        end
    end

    if Config.Taxes.DisableUnknown and #allowed > 0 then
        local placeholders = {}
        for _ = 1, #allowed do
            placeholders[#placeholders + 1] = '?'
        end

        MySQL.update.await(
            'UPDATE pf_gov_taxes SET enabled = 0 WHERE tax_type NOT IN (' .. table.concat(placeholders, ',') .. ')',
            allowed
        )
    end
end

function InitializeTaxes()
    print('^3[PF-GOVERNMENT]^7 Initializing tax system...')

    EnsureTaxDefaults()
    local loaded = loadTaxesFromDatabase()

    print(('^2[PF-GOVERNMENT]^7 Tax system initialized with %s tax type(s) from database'):format(loaded))
end

function GetTaxRates()
    return cloneTaxCache()
end

function GetTaxRate(taxType)
    local normalizedType = normalizeTaxType(taxType)
    local tax = TaxCache[normalizedType] or hydrateTaxIntoCache(normalizedType)
    if tax and tax.enabled then
        return tonumber(tax.rate) or 0
    end
    return 0
end

function SetTaxRate(taxType, newRate, changedBy, changedByName)
    local normalizedType = normalizeTaxType(taxType)
    local taxConfig = TaxCache[normalizedType] or hydrateTaxIntoCache(normalizedType)
    if not taxConfig then
        return false, 'Invalid tax type'
    end

    local parsedRate = tonumber(newRate)
    if parsedRate == nil then
        return false, 'Invalid tax rate'
    end
    parsedRate = roundCurrency(parsedRate)

    local minRate, maxRate = getConfiguredTaxBounds(normalizedType, taxConfig.min_rate, taxConfig.max_rate)

    -- Keep cache bounds in sync with configured bounds for UI and validation consistency.
    taxConfig.min_rate = minRate
    taxConfig.max_rate = maxRate

    if parsedRate < minRate or parsedRate > maxRate then
        return false, ('Tax rate must be between %.2f and %.2f'):format(minRate, maxRate)
    end

    local oldRate = tonumber(taxConfig.rate) or 0

    local affectedRows = MySQL.update.await(
        'UPDATE pf_gov_taxes SET rate = ?, last_changed_by = ?, last_changed_at = NOW() WHERE tax_type = ?',
        { parsedRate, changedBy, normalizedType }
    )

    if not affectedRows or affectedRows < 1 then
        return false, 'Failed to update tax rate in database'
    end

    TaxCache[normalizedType].rate = parsedRate

    LogAudit('tax_change', changedBy, changedByName, 'tax', normalizedType, {
        tax_type = normalizedType,
        old_rate = oldRate,
        new_rate = parsedRate
    })

    DebugPrint(('Tax rate changed: %s %.2f -> %.2f'):format(normalizedType, oldRate, parsedRate))
    return true, 'Tax rate updated successfully'
end

function SetTaxEnabled(taxType, enabled, changedBy, changedByName)
    local normalizedType = normalizeTaxType(taxType)
    local taxConfig = TaxCache[normalizedType] or hydrateTaxIntoCache(normalizedType)
    if not taxConfig then
        return false, 'invalid_tax_type'
    end

    local enabledFlag = toBoolFlag(enabled)

    local affectedRows = MySQL.update.await(
        'UPDATE pf_gov_taxes SET enabled = ?, last_changed_by = ?, last_changed_at = NOW() WHERE tax_type = ?',
        { enabledFlag and 1 or 0, changedBy, normalizedType }
    )

    if not affectedRows or affectedRows < 1 then
        return false, 'database_error'
    end

    TaxCache[normalizedType].enabled = enabledFlag

    LogAudit('tax_toggle', changedBy, changedByName, 'tax', normalizedType, {
        tax_type = normalizedType,
        enabled = enabledFlag
    })

    return true, 'updated'
end

function GetTaxSchedule()
    local taxes = {}
    for taxType, tax in pairs(GetTaxRates()) do
        taxes[#taxes + 1] = {
            tax_type = taxType,
            rate = tonumber(tax.rate) or 0,
            min_rate = tonumber(tax.min_rate) or 0,
            max_rate = tonumber(tax.max_rate) or 100,
            enabled = tax.enabled == true,
            description = tax.description or ''
        }
    end

    table.sort(taxes, function(a, b)
        return tostring(a.tax_type or '') < tostring(b.tax_type or '')
    end)

    return taxes
end

function CalculateTax(amount, taxType)
    local normalizedType = normalizeTaxType(taxType)
    local taxConfig = TaxCache[normalizedType] or hydrateTaxIntoCache(normalizedType)
    if not taxConfig or not taxConfig.enabled then
        return 0
    end

    local baseAmount = tonumber(amount) or 0
    if baseAmount <= 0 then
        return 0
    end

    local rate = tonumber(taxConfig.rate) or 0
    if rate <= 0 then
        return 0
    end

    local maxRate = tonumber(taxConfig.max_rate) or 100
    if maxRate > 100 then
        -- Flat-fee style taxes (ex: registration fees)
        return roundCurrency(rate)
    end

    -- Percentage taxes are calculated against subtotal only.
    return roundCurrency(baseAmount * (rate / 100))
end

function GetSalesTaxBreakdown(subtotal)
    local safeSubtotal = roundCurrency(math.max(0, tonumber(subtotal) or 0))
    local taxAmount = CalculateTax(safeSubtotal, 'sales')
    local total = roundCurrency(safeSubtotal + taxAmount)

    return {
        subtotal = safeSubtotal,
        tax = taxAmount,
        total = total,
        rate = GetTaxRate('sales')
    }
end

--- Credits an already-charged tax amount to the treasury. Callers that took the tax from a player
--- pass the exact amount they charged and an idempotency key; a retry with the same key is not
--- credited or logged twice. Returns the amount credited (0 when it could not be credited).
function CollectTaxAmount(taxAmount, taxType, targetType, targetId, collectedBy, idempotencyKey, subtotal)
    local normalizedType = normalizeTaxType(taxType)
    taxAmount = roundCurrency(math.max(0, tonumber(taxAmount) or 0))
    local safeSubtotal = roundCurrency(math.max(0, tonumber(subtotal) or 0))

    if taxAmount <= 0 then
        return 0
    end

    -- moves exactly taxAmount (no read-then-set race) and reports what really happened
    local balanceBefore = GetTreasuryBalance()
    local credited, balanceAfter, duplicate = CreditTreasury(taxAmount, 'Tax collection: ' .. normalizedType, collectedBy or 'tax_system', idempotencyKey)
    if not credited then
        print(('^1[PF-GOVERNMENT]^7 Tax of %.2f (%s) could not be credited to the treasury'):format(taxAmount, normalizedType))
        return 0
    end
    if duplicate then
        return taxAmount
    end

    LogTransaction(
        'tax_collection',
        taxAmount,
        balanceBefore,
        balanceAfter,
        normalizedType,
        targetId,
        ('Tax collection: %s from %s %s (subtotal: %.2f)'):format(
            normalizedType,
            tostring(targetType or 'unknown'),
            tostring(targetId or 'unknown'),
            safeSubtotal
        ),
        collectedBy or 'system'
    )

    if type(TrackWeeklyRevenue) == 'function' then
        TrackWeeklyRevenue('tax', taxAmount)
    end

    DebugPrint(('Tax collected: %.2f (%s) from %s %s'):format(
        taxAmount,
        normalizedType,
        tostring(targetType or 'unknown'),
        tostring(targetId or 'unknown')
    ))

    return taxAmount
end

--- Calculates the tax on a subtotal and credits it to the treasury. Returns the amount credited.
function CollectTax(subtotal, taxType, targetType, targetId, collectedBy, idempotencyKey)
    local safeSubtotal = roundCurrency(math.max(0, tonumber(subtotal) or 0))
    local taxAmount = CalculateTax(safeSubtotal, normalizeTaxType(taxType))
    return CollectTaxAmount(taxAmount, taxType, targetType, targetId, collectedBy, idempotencyKey, safeSubtotal)
end

function ApplyIncomeTax(grossAmount, citizenid)
    if not Config.Integrations.PaycheckTax.enabled then
        return 0
    end

    grossAmount = tonumber(grossAmount) or 0
    if grossAmount <= 0 then
        return 0
    end

    local taxAmount = CalculateTax(grossAmount, 'income')
    if taxAmount > 0 then
        CollectTax(grossAmount, 'income', 'citizen', citizenid or 'unknown', 'system')
    end

    return taxAmount
end

-- =====================================================
-- NUI CALLBACKS - TAXES
-- =====================================================

RegisterNUICallback('tax:getAll', function(_, cb)
    local taxes = GetTaxSchedule()
    for _, tax in ipairs(taxes) do
        tax.enabled = tax.enabled and 1 or 0
    end

    cb({ ok = true, taxes = taxes })
end)

RegisterNUICallback('tax:update', function(data, cb)
    local src = data.source or source

    if not HasPermission(src, 'taxes') then
        cb({ ok = false, error = 'no_permission' })
        return
    end

    local taxType = data.taxType
    local newRate = data.rate
    local citizenid = GetPlayerIdentifier(src)
    local name = GetPlayerName(src)

    local success, message = SetTaxRate(taxType, newRate, citizenid, name)

    if success then
        NotifyPlayer(src, ('Tax rate updated: %s'):format(tostring(taxType)), 'success')
    end

    cb({
        ok = success,
        message = message
    })
end)

RegisterNUICallback('tax:toggle', function(data, cb)
    local src = data.source or source

    if not HasPermission(src, 'taxes') then
        cb({ ok = false, error = 'no_permission' })
        return
    end

    local taxType = normalizeTaxType(data.taxType)
    local enabled = toBoolFlag(data.enabled)
    local citizenid = GetPlayerIdentifier(src)
    local name = GetPlayerName(src)

    if taxType == '' then
        cb({ ok = false, error = 'invalid_tax_type' })
        return
    end

    local ok, message = SetTaxEnabled(taxType, enabled, citizenid, name)
    if not ok then
        cb({ ok = false, error = message })
        return
    end

    NotifyPlayer(src, ('Tax %s %s'):format(taxType, enabled and 'enabled' or 'disabled'), 'success')
    cb({ ok = true })
end)

-- =====================================================
-- EXPORTS
-- =====================================================

exports('GetTaxRates', function()
    return GetTaxRates()
end)

exports('GetTaxRate', function(taxType)
    return GetTaxRate(taxType)
end)

-- Kept for backward compatibility with scripts expecting decimal form.
exports('GetSalesTaxRate', function()
    local rate = GetTaxRate('sales')
    return (tonumber(rate) or 0) / 100
end)

exports('CalculateTax', function(amount, taxType)
    return CalculateTax(amount, taxType)
end)

exports('GetSalesTaxBreakdown', function(subtotal)
    return GetSalesTaxBreakdown(subtotal)
end)

exports('ApplyIncomeTax', function(amount, citizenid)
    return ApplyIncomeTax(amount, citizenid)
end)

exports('CollectTax', function(subtotal, taxType, targetType, targetId, collectedBy, idempotencyKey)
    return CollectTax(subtotal, taxType, targetType, targetId, collectedBy, idempotencyKey)
end)

exports('CollectTaxAmount', function(taxAmount, taxType, targetType, targetId, collectedBy, idempotencyKey, subtotal)
    return CollectTaxAmount(taxAmount, taxType, targetType, targetId, collectedBy, idempotencyKey, subtotal)
end)

exports('SetTaxRate', function(taxType, newRate, changedBy, changedByName)
    return SetTaxRate(taxType, newRate, changedBy, changedByName)
end)

exports('SetTaxEnabled', function(taxType, enabled, changedBy, changedByName)
    return SetTaxEnabled(taxType, enabled, changedBy, changedByName)
end)

exports('GetTaxSchedule', function()
    return GetTaxSchedule()
end)

-- =====================================================
-- INTEGRATION EVENTS
-- =====================================================

if Config.Integrations.PaycheckTax.enabled then
    AddEventHandler('qb-bossmenu:server:withdrawMoney', function(amount)
        local src = source
        local citizenid = GetPlayerIdentifier(src)

        local taxAmount = CalculateTax(amount, 'income')
        if taxAmount > 0 then
            CollectTax(amount, 'income', 'citizen', citizenid, 'system')
            NotifyPlayer(src, ('Income tax deducted: $%.2f'):format(taxAmount), 'primary')
        end
    end)
end

print('^2[PF-GOVERNMENT]^7 Tax system loaded')
