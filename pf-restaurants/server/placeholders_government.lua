-- Government integration placeholders

-- Tax calculation stub
function GetSalesTaxRate(businessId)
    if GetResourceState('pf-government') == 'started' then
        local ok, rate = pcall(function()
            return exports['pf-government']:GetSalesTaxRate()
        end)
        if ok and type(rate) == 'number' then
            return rate
        end
    end

    return Config.Orders.TaxRate or 0.0
end

exports('GetSalesTaxRate', GetSalesTaxRate)

function ComputeTaxPlaceholder(subtotal, businessId)
    return subtotal * GetSalesTaxRate(businessId)
end

exports('ComputeTaxPlaceholder', ComputeTaxPlaceholder)

QBCore.Functions.CreateCallback('pf-restaurants:server:getSalesTaxRate', function(source, cb, businessId)
    cb(GetSalesTaxRate(businessId))
end)

-- Policy placeholders
function GetPolicyPlaceholder(businessId)
    return {
        minimumWage = 15,
        maxEmployees = 50,
        healthInspectionRequired = true,
        businessLicenseValid = true
    }
end

exports('GetPolicyPlaceholder', GetPolicyPlaceholder)

-- Loan placeholders
QBCore.Functions.CreateCallback('pf-restaurants:server:getLoans', function(source, cb, businessId)
    -- Placeholder for future business loan system
    cb({
        loans = {},
        totalOwed = 0,
        nextPayment = nil
    })
end)

-- License check: asks pf-government; without it the answer is no (fails closed)
function CheckBusinessLicense(businessId)
    if GetResourceState('pf-government') ~= 'started' then return false end
    local ok, licensed = pcall(function() return exports['pf-government']:CheckBusinessLicense(businessId) end)
    return ok and licensed == true
end

exports('CheckBusinessLicense', CheckBusinessLicense)

-- Health department report placeholder
-- Not connected to a government system yet: says so instead of pretending it worked
function SubmitHealthReport(businessId, reportData)
    return false, 'not_implemented'
end

exports('SubmitHealthReport', SubmitHealthReport)

-- Fine system placeholder
-- Not connected: business fines go through pf-government's bills, which this does not call yet
function IssueFine(businessId, amount, reason)
    return false, 'not_implemented'
end

exports('IssueFine', IssueFine)

-- Business closure placeholder
-- Not connected to government enforcement yet
function CloseBusiness(businessId, reason, duration)
    return false, 'not_implemented'
end

exports('CloseBusiness', CloseBusiness)
