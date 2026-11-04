-- =====================================================
-- PF GOVERNMENT - SERVER MAIN (INITIALIZATION ORCHESTRATOR)
-- =====================================================

-- Note: Core functions and globals are in server/core.lua

-- =====================================================
-- INITIALIZATION
-- =====================================================

print('^3[PF-GOVERNMENT]^7 Main.lua loaded, setting up initialization...')

-- Use AddEventHandler instead of CreateThread for more reliable initialization
AddEventHandler('onResourceStart', function(resourceName)
    if GetCurrentResourceName() ~= resourceName then
        return
    end
    
    print('^2[PF-GOVERNMENT]^7 Resource started - initializing Government Framework...')
    
    -- Initialize all systems
    print('^3[PF-GOVERNMENT]^7 Calling InitializeTreasury()...')
    InitializeTreasury()
    
    print('^3[PF-GOVERNMENT]^7 Calling InitializeTaxes()...')
    InitializeTaxes()
    
    print('^3[PF-GOVERNMENT]^7 Calling InitializeBudgets()...')
    InitializeBudgets()
    
    print('^3[PF-GOVERNMENT]^7 Calling InitializeLaws()...')
    InitializeLaws()
    
    print('^3[PF-GOVERNMENT]^7 Calling InitializeLicenses()...')
    InitializeLicenses()
    
    print('^3[PF-GOVERNMENT]^7 Calling InitializeUtilities()...')
    InitializeUtilities()
    
    print('^3[PF-GOVERNMENT]^7 Calling InitializeBills()...')
    InitializeBills()
    
    print('^3[PF-GOVERNMENT]^7 Calling InitializeBusinesses()...')
    InitializeBusinesses()
    
    print('^3[PF-GOVERNMENT]^7 Calling InitializeStaff()...')
    InitializeStaff()

    print('^3[PF-GOVERNMENT]^7 Calling InitializeInfrastructure()...')
    InitializeInfrastructure()

    -- municipal work orders: open claims back into the position sampler
    if InitializeWorkOrders then InitializeWorkOrders() end
    
    print('^2[PF-GOVERNMENT]^7 Government Framework loaded successfully!')
    
    -- Start background tasks
    print('^3[PF-GOVERNMENT]^7 Starting background tasks...')
    StartBackgroundTasks()
end)

-- =====================================================
-- ADDITIONAL UTILITY FUNCTIONS
-- =====================================================

function GetPlayerRole(source)
    local job = GetPlayerJob(source)
    if not job or job.name ~= Config.GovernmentJob then
        return nil
    end
    
    local roleConfig = Config.Roles[job.grade.level]
    if roleConfig then
        return roleConfig.name
    end
    
    return nil
end

function IsGovernmentEmployee(source)
    local job = GetPlayerJob(source)
    return job and job.name == Config.GovernmentJob
end

function NotifyGovernment(message, type)
    type = type or 'primary'
    local Players = QBCore.Functions.GetQBPlayers()
    for _, Player in pairs(Players) do
        if Player.PlayerData.job.name == Config.GovernmentJob then
            TriggerClientEvent('QBCore:Notify', Player.PlayerData.source, message, type)
        end
    end
end

-- =====================================================
-- BACKGROUND TASKS
-- =====================================================

-- One run of a background job. The jobs wait on the database, and oxmysql raises on a SQL error (a
-- deadlock, a lost connection): caught here, so one failed run is logged and the loop carries on.
local function runJob(name, fn, ...)
    local ok, res = pcall(fn, ...)
    if not ok then
        print(('^1[PF-GOVERNMENT]^7 %s failed: %s'):format(name, tostring(res)))
        return nil
    end
    return res
end

function StartBackgroundTasks()
    StartInfrastructureTasks()

    -- Auto tax collection: the weekly property tax on owned houses (server/property_tax.lua). Every
    -- run bills only the houses without a bill this week, so the first run after a restart or a new
    -- week catches up and the others change nothing. A run skipped because pfm-houses was still
    -- starting (or its read failed) is tried again after RetrySeconds, not a whole interval later.
    if Config.Taxes.AutoCollection.enabled then
        CreateThread(function()
            Wait(60000) -- pfm-houses has loaded its houses by then
            while true do
                DebugPrint('Running auto tax collection...')
                local res = PropertyTax.Run()
                local retry = type(res) == 'table' and res.retry == true
                Wait(retry and math.max(10, tonumber(Config.Taxes.PropertyTax.RetrySeconds) or 120) * 1000
                    or math.max(1, tonumber(Config.Taxes.AutoCollection.interval) or 30) * 60000)
            end
        end)
    end
    
    -- Budget reset
    if Config.Budgets.AutoReset then
        CreateThread(function()
            while true do
                Wait(60000) -- Check every minute
                CheckBudgetReset()
            end
        end)
    end
    
    -- License expiration checking
    if Config.Licenses.CheckExpiration then
        CreateThread(function()
            while true do
                Wait(Config.Licenses.ExpirationCheckInterval * 1000)
                CheckLicenseExpiration()
            end
        end)
    end
    
    -- Bill payments the bank settled late: credited to their bill (or dropped) once the ledger knows
    CreateThread(function()
        while true do
            Wait(math.max(10, tonumber(Config.Bills.PaymentReconcileSeconds) or 60) * 1000)
            runJob('bill payment reconcile', ReconcileBillPayments)
        end
    end)

    -- keyed department society moves the bank settled late: booked once the ledger knows
    CreateThread(function()
        while true do
            Wait(60000)
            runJob('budget move reconcile', ReconcileBudgetMoves)
        end
    end)

    -- municipal work orders: claimant position sampler, expiry sweep and payouts
    if StartWorkOrderTasks then StartWorkOrderTasks() end

    -- Utility billing. Houses that could not be read (pfm-houses still starting) are billed for the
    -- same cycle a few minutes later; their bills are keyed by cycle, so a retry never bills twice.
    if Config.Utilities.EnablePower or Config.Utilities.EnableWater then
        CreateThread(function()
            while true do
                Wait(Config.Utilities.BillingInterval * 1000)
                local res = runJob('utility billing', ProcessUtilityBilling)
                local tries = 0
                while type(res) == 'table' and res.housesPending and tries < 10 do
                    tries = tries + 1
                    Wait(math.max(10, tonumber(Config.Taxes.PropertyTax.RetrySeconds) or 120) * 1000)
                    res = runJob('utility billing', ProcessUtilityBilling, nil, { housesOnly = true, period = res.period })
                end
            end
        end)
    end
    
    -- Bill late fees and delinquency
    if Config.Bills.LateFeeEnabled or Config.Bills.EscalationEnabled then
        CreateThread(function()
            while true do
                Wait(3600000) -- Check every hour
                runJob('late fees', ProcessBillLateFees)
                runJob('bill escalation', ProcessBillEscalation)
            end
        end)
    end
end

-- =====================================================
-- EVENTS
-- =====================================================

-- Open Government UI
RegisterNetEvent('pf-government:client:openUI', function()
    local src = source
    
    if not IsGovernmentEmployee(src) then
        NotifyPlayer(src, 'You do not have access to the government system', 'error')
        return
    end
    
    TriggerClientEvent('pf-government:client:openUI', src)
end)

-- Player loaded - Check for government staff record
-- Server-only (pfm-core raises it): as a network event a client could send a made-up player and
-- create staff records for any citizen id.
AddEventHandler('QBCore:Server:PlayerLoaded', function(Player)
    local src = Player.PlayerData.source
    local citizenid = Player.PlayerData.citizenid
    
    if Player.PlayerData.job.name == Config.GovernmentJob then
        -- Check if staff record exists, create if not
        MySQL.query('SELECT * FROM pf_gov_staff WHERE citizenid = ?', {citizenid}, function(result)
            if not result or #result == 0 then
                local name = Player.PlayerData.charinfo.firstname .. ' ' .. Player.PlayerData.charinfo.lastname
                local role = GetPlayerRole(src) or 'Staff'
                
                MySQL.insert('INSERT INTO pf_gov_staff (citizenid, name, role, active) VALUES (?, ?, ?, ?)', 
                    {citizenid, name, role, 1})
            end
        end)
    end
end)

-- =====================================================
-- EXPORTS
-- =====================================================

-- Get all active laws
exports('GetActiveLaws', function()
    return GetActiveLaws()
end)

-- Check if citizen has a specific license
exports('HasLicense', function(citizenid, licenseType)
    return HasLicense(citizenid, licenseType)
end)

-- Get business license status
exports('GetBusinessLicenseStatus', function(businessId)
    return GetBusinessLicenseStatus(businessId)
end)

-- Check if property has power
exports('HasPower', function(propertyId)
    return HasPower('property', propertyId)
end)

-- Check if business has power
exports('HasBusinessPower', function(businessId)
    return HasPower('business', businessId)
end)

-- Get current tax rates
exports('GetTaxRates', function()
    return GetTaxRates()
end)

-- Get specific tax rate
exports('GetTaxRate', function(taxType)
    return GetTaxRate(taxType)
end)

-- Create a bill. All arguments pass through: issuedBy, issuedByName and recurring
-- ({ ref, period }: one bill per ref and period; a repeat returns false, 'duplicate', <existing id>).
-- Without issuedBy the bill names the calling resource (issued_by is NOT NULL: the documented
-- six-argument call used to fail with an SQL error).
exports('CreateBill', function(targetType, targetId, amount, billType, dueDate, description, issuedBy, issuedByName, recurring)
    if issuedBy == nil then
        issuedBy = ('resource:%s'):format(GetInvokingResource() or GetCurrentResourceName()):sub(1, 50)
        issuedByName = issuedByName or 'City system'
    end
    return CreateBill(targetType, targetId, amount, billType, dueDate, description, issuedBy, issuedByName, recurring)
end)

-- Pay a bill
exports('PayBill', function(billId, amount, paidBy)
    return PayBill(billId, amount, paidBy)
end)

-- Register a business
exports('RegisterBusiness', function(businessId, businessName, businessType, ownerId, ownerName)
    return RegisterBusiness(businessId, businessName, businessType, ownerId, ownerName)
end)

-- Update business revenue
exports('UpdateBusinessRevenue', function(businessId, amount)
    return UpdateBusinessRevenue(businessId, amount)
end)

-- Get treasury balance
exports('GetTreasuryBalance', function()
    return GetTreasuryBalance()
end)

-- Deposit to treasury. Pass idempotencyKey (5th) so a retried call cannot deposit twice.
exports('DepositToTreasury', function(amount, source, description, performedBy, idempotencyKey)
    return DepositToTreasury(amount, source, description, performedBy, idempotencyKey)
end)

-- Withdraw from treasury. Pass idempotencyKey (5th) so a retried call cannot withdraw twice.
exports('WithdrawFromTreasury', function(amount, reason, performedBy, performedByName, idempotencyKey)
    return WithdrawFromTreasury(amount, reason, performedBy, performedByName, idempotencyKey)
end)

-- Note: Tax-related exports (GetTaxRate, GetSalesTaxRate, ApplyIncomeTax, CollectTax) 
-- are defined in server/taxes.lua where the functions exist

print('^2[PF-GOVERNMENT]^7 Core functions and exports loaded')
