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

-- Loans: the restaurant's government loans (pf-government), for its managers
QBCore.Functions.CreateCallback('pf-restaurants:server:getLoans', function(source, cb, businessId)
    businessId = tostring(businessId or '')
    if not HasPermission(source, businessId, 'analytics.view') or GetResourceState('pf-government') ~= 'started' then
        return cb({ loans = {}, totalOwed = 0, nextPayment = nil, error = 'unavailable' })
    end
    local ok, loans = pcall(function() return exports['pf-government']:GetBusinessLoans('restaurant:' .. businessId) end)
    loans = ok and type(loans) == 'table' and loans or {}
    local owed, nextDue = 0, nil
    for _, l in ipairs(loans) do
        if l.status ~= 'paid' then
            owed = owed + (tonumber(l.remaining_amount) or 0)
            if l.next_due_at and (not nextDue or l.next_due_at < nextDue) then nextDue = l.next_due_at end
        end
    end
    cb({ loans = loans, totalOwed = owed, nextPayment = nextDue })
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
