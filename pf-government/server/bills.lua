-- =====================================================
-- BILLS AND FINES SYSTEM
-- =====================================================

function InitializeBills()
    print('^2[PF-GOVERNMENT]^7 Bills system initialized')
end

function CreateBill(targetType, targetId, amount, billType, dueDate, description, issuedBy, issuedByName)
    amount = tonumber(amount)
    
    if not amount or amount <= 0 then
        return false, 'Invalid amount'
    end
    
    if not targetType or not targetId then
        return false, 'Missing target information'
    end
    
    -- Default due date if not provided (7 days)
    if not dueDate then
        dueDate = os.date('%Y-%m-%d %H:%M:%S', os.time() + 604800)
    end
    
    local insertId = MySQL.insert.await('INSERT INTO pf_gov_bills (bill_type, target_type, target_id, amount, description, due_date, issued_by, issued_by_name) VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
        {billType, targetType, targetId, amount, description, dueDate, issuedBy, issuedByName})
    
    if insertId then
        -- Log audit
        LogAudit('bill_create', issuedBy, issuedByName, 'bill', insertId, {
            bill_id = insertId,
            bill_type = billType,
            target_type = targetType,
            target_id = targetId,
            amount = amount
        })
        
        DebugPrint('Bill created: ' .. billType .. ' for ' .. targetType .. ' ' .. targetId .. ' - $' .. amount)
        return true, 'Bill created successfully', insertId
    end
    
    return false, 'Database error'
end

function PayBill(billId, amount, paidBy, paidByName)
    billId = tonumber(billId)
    amount = tonumber(amount)
    
    if not billId or not amount or amount <= 0 then
        return false, 'Invalid parameters'
    end
    
    -- Get bill info
    local bill = MySQL.query.await('SELECT * FROM pf_gov_bills WHERE id = ?', {billId})
    
    if not bill or #bill == 0 then
        return false, 'Bill not found'
    end
    
    bill = bill[1]
    
    -- Check if bill is already paid
    if bill.status == 'paid' then
        return false, 'Bill already paid'
    end
    
    local remaining = tonumber(bill.amount) - tonumber(bill.amount_paid)
    
    if amount > remaining then
        amount = remaining
    end
    
    local newAmountPaid = tonumber(bill.amount_paid) + amount
    local newStatus = 'partial'
    
    if newAmountPaid >= tonumber(bill.amount) then
        newStatus = 'paid'
    end
    
    -- Update bill
    MySQL.update('UPDATE pf_gov_bills SET amount_paid = ?, status = ?, paid_at = NOW() WHERE id = ?',
        {newAmountPaid, newStatus, billId})
    
    -- Deposit to treasury
    DepositToTreasury(amount, bill.bill_type, 'Bill payment #' .. billId, paidBy)
    
    -- Log audit
    LogAudit('bill_payment', paidBy, paidByName, 'bill', billId, {
        bill_id = billId,
        amount_paid = amount,
        total_paid = newAmountPaid,
        status = newStatus
    })
    
    DebugPrint('Bill payment: #' .. billId .. ' - $' .. amount)
    return true, 'Payment successful', newStatus
end

function WaiveBill(billId, waivedBy, waivedByName, reason)
    billId = tonumber(billId)
    
    MySQL.update('UPDATE pf_gov_bills SET status = ?, notes = ? WHERE id = ?',
        {'waived', reason, billId})
    
    -- Log audit
    LogAudit('bill_waive', waivedBy, waivedByName, 'bill', billId, {
        bill_id = billId,
        reason = reason
    })
    
    DebugPrint('Bill waived: #' .. billId)
    return true, 'Bill waived'
end

function GetBillsByTarget(targetType, targetId)
    local result = MySQL.query.await('SELECT * FROM pf_gov_bills WHERE target_type = ? AND target_id = ? ORDER BY issued_at DESC',
        {targetType, targetId})
    
    return result or {}
end

local function decodeMoney(payload)
    if type(payload) == 'table' then
        return payload
    end
    if type(payload) == 'string' and payload ~= '' then
        local ok, decoded = pcall(json.decode, payload)
        if ok and type(decoded) == 'table' then
            return decoded
        end
    end
    return { cash = 0, bank = 0 }
end

local function collectFineFromCitizen(citizenid, amount)
    amount = tonumber(amount) or 0
    if amount <= 0 then
        return 0
    end

    if QBCore and QBCore.Functions and QBCore.Functions.GetPlayerByCitizenId then
        local onlinePlayer = QBCore.Functions.GetPlayerByCitizenId(citizenid)
        if onlinePlayer then
            local bank = tonumber(onlinePlayer.PlayerData.money.bank or 0) or 0
            local cash = tonumber(onlinePlayer.PlayerData.money.cash or 0) or 0
            local totalAvailable = bank + cash
            local collectAmount = math.min(amount, totalAvailable)

            if collectAmount <= 0 then
                return 0
            end

            local bankTake = math.min(bank, collectAmount)
            local remaining = collectAmount - bankTake
            local cashTake = math.min(cash, remaining)

            if bankTake > 0 then
                onlinePlayer.Functions.RemoveMoney('bank', bankTake, 'government-fine-collection')
            end
            if cashTake > 0 then
                onlinePlayer.Functions.RemoveMoney('cash', cashTake, 'government-fine-collection')
            end

            return collectAmount
        end
    end

    local row = MySQL.single.await('SELECT money FROM players WHERE citizenid = ? LIMIT 1', { citizenid })
    if not row then
        return 0
    end

    local money = decodeMoney(row.money)
    local bank = tonumber(money.bank or 0) or 0
    local cash = tonumber(money.cash or 0) or 0
    local totalAvailable = bank + cash
    local collectAmount = math.min(amount, totalAvailable)

    if collectAmount <= 0 then
        return 0
    end

    local bankTake = math.min(bank, collectAmount)
    local remaining = collectAmount - bankTake
    local cashTake = math.min(cash, remaining)

    money.bank = bank - bankTake
    money.cash = cash - cashTake

    MySQL.update.await('UPDATE players SET money = ? WHERE citizenid = ?', { json.encode(money), citizenid })

    return collectAmount
end

function IssueFineImmediate(targetCitizenId, amount, description, issuedBy, issuedByName, dueDate)
    if not targetCitizenId or targetCitizenId == '' then
        return false, 'invalid_target'
    end

    local ok, msg, billId = CreateBill('citizen', targetCitizenId, amount, 'fine', dueDate, description or 'City fine', issuedBy, issuedByName)
    if not ok then
        return false, msg
    end

    local collected = collectFineFromCitizen(targetCitizenId, amount)
    if collected > 0 then
        PayBill(billId, collected, issuedBy, issuedByName)
    end

    local remaining = math.max(0, (tonumber(amount) or 0) - collected)

    return true, {
        billId = billId,
        collected = collected,
        remaining = remaining,
        status = remaining <= 0 and 'paid' or (collected > 0 and 'partial' or 'unpaid')
    }
end

function ProcessBillLateFees()
    if not Config.Bills.LateFeeEnabled then
        return
    end
    
    MySQL.query('SELECT * FROM pf_gov_bills WHERE status IN (?, ?) AND due_date < NOW()',
        {'unpaid', 'partial'}, function(result)
            if result and #result > 0 then
                local feesApplied = 0
                
                for _, bill in ipairs(result) do
                    local dueTime = os.time(bill.due_date)
                    local currentTime = os.time()
                    local daysLate = math.floor((currentTime - dueTime) / 86400)
                    
                    if daysLate > 0 then
                        local lateFee = tonumber(bill.amount) * (Config.Bills.LateFeePercentage / 100)
                        lateFee = math.floor(lateFee)
                        
                        if lateFee > 0 then
                            -- Add late fee to bill amount
                            local newAmount = tonumber(bill.amount) + lateFee
                            
                            MySQL.update('UPDATE pf_gov_bills SET amount = ? WHERE id = ?', {newAmount, bill.id})
                            
                            feesApplied = feesApplied + 1
                            DebugPrint('Late fee applied: Bill #' .. bill.id .. ' +$' .. lateFee)
                        end
                    end
                end
                
                if feesApplied > 0 then
                    DebugPrint('Late fees applied to ' .. feesApplied .. ' bills')
                end
            end
        end)
end

function ProcessBillEscalation()
    if not Config.Bills.EscalationEnabled then
        return
    end
    
    local escalationSeconds = Config.Bills.EscalationDays * 86400
    local escalationDate = os.date('%Y-%m-%d %H:%M:%S', os.time() - escalationSeconds)
    
    MySQL.query('SELECT * FROM pf_gov_bills WHERE status IN (?, ?) AND due_date < ?',
        {'unpaid', 'partial', escalationDate}, function(result)
            if result and #result > 0 then
                for _, bill in ipairs(result) do
                    -- Update status to delinquent
                    MySQL.update('UPDATE pf_gov_bills SET status = ? WHERE id = ?', {'delinquent', bill.id})
                    
                    -- Apply escalation actions
                    if Config.Bills.EscalationActions.license_suspension then
                        -- Suspend licenses for delinquent citizen/business
                        MySQL.query('SELECT * FROM pf_gov_licenses WHERE owner_type = ? AND owner_id = ? AND status = ?',
                            {bill.target_type, bill.target_id, 'active'}, function(licenses)
                                if licenses and #licenses > 0 then
                                    for _, license in ipairs(licenses) do
                                        SuspendLicense(license.id, 'system', 'System', 'Delinquent bill #' .. bill.id)
                                    end
                                end
                            end)
                    end
                    
                    if Config.Bills.EscalationActions.utility_cutoff then
                        -- Disconnect utilities
                        if Config.Utilities.EnablePower then
                            DisconnectService(bill.target_type, bill.target_id, 'power', 'system', 'System', 'Delinquent bill #' .. bill.id)
                        end
                    end
                    
                    if Config.Bills.EscalationActions.business_flag and bill.target_type == 'business' then
                        -- Flag business for non-compliance
                        MySQL.update('UPDATE pf_gov_businesses SET compliance_status = ? WHERE business_id = ?',
                            {'non_compliant', bill.target_id})
                    end
                    
                    DebugPrint('Bill escalated: #' .. bill.id)
                end
            end
        end)
end

-- =====================================================
-- NUI CALLBACKS - BILLS
-- =====================================================

RegisterNUICallback('bill:getAll', function(data, cb)
    local targetType = data.targetType
    local targetId = data.targetId
    local status = data.status
    
    local query = 'SELECT * FROM pf_gov_bills WHERE 1=1'
    local params = {}
    
    if targetType then
        query = query .. ' AND target_type = ?'
        table.insert(params, targetType)
    end
    
    if targetId then
        query = query .. ' AND target_id = ?'
        table.insert(params, targetId)
    end
    
    if status then
        query = query .. ' AND status = ?'
        table.insert(params, status)
    end
    
    query = query .. ' ORDER BY issued_at DESC'
    
    MySQL.query(query, params, function(result)
        cb({
            ok = true,
            bills = result or {}
        })
    end)
end)

RegisterNUICallback('bill:create', function(data, cb)
    local src = data.source or source
    
    if not HasPermission(src, 'fines') then
        cb({ ok = false, error = 'no_permission' })
        return
    end
    
    local citizenid = GetPlayerIdentifier(src)
    local name = GetPlayerName(src)
    
    local success, message, billId = CreateBill(
        data.targetType,
        data.targetId,
        data.amount,
        data.billType,
        data.dueDate,
        data.description,
        citizenid,
        name
    )
    
    if success then
        NotifyPlayer(src, 'Bill created', 'success')
    end
    
    cb({
        ok = success,
        message = message,
        billId = billId
    })
end)

RegisterNUICallback('bill:pay', function(data, cb)
    local src = data.source or source
    
    local citizenid = GetPlayerIdentifier(src)
    local name = GetPlayerName(src)
    
    local success, message, status = PayBill(data.billId, data.amount, citizenid, name)
    
    if success then
        NotifyPlayer(src, 'Payment successful', 'success')
    end
    
    cb({
        ok = success,
        message = message,
        status = status
    })
end)

RegisterNUICallback('bill:waive', function(data, cb)
    local src = data.source or source
    
    if not HasPermission(src, 'fines') then
        cb({ ok = false, error = 'no_permission' })
        return
    end
    
    local citizenid = GetPlayerIdentifier(src)
    local name = GetPlayerName(src)
    
    local success, message = WaiveBill(data.billId, citizenid, name, data.reason)
    
    if success then
        NotifyPlayer(src, 'Bill waived', 'success')
    end
    
    cb({
        ok = success,
        message = message
    })
end)

RegisterNUICallback('fine:issueImmediate', function(data, cb)
    local src = data.source or source

    if not HasPermission(src, 'fines') then
        cb({ ok = false, error = 'no_permission' })
        return
    end

    local citizenid = GetPlayerIdentifier(src)
    local name = GetPlayerName(src)

    local success, result = IssueFineImmediate(
        data.targetCitizenId,
        data.amount,
        data.description,
        citizenid,
        name,
        data.dueDate
    )

    cb({ ok = success, result = result })
end)

print('^2[PF-GOVERNMENT]^7 Bills system loaded')

exports('IssueFineImmediate', function(targetCitizenId, amount, description, issuedBy, issuedByName, dueDate)
    return IssueFineImmediate(targetCitizenId, amount, description, issuedBy, issuedByName, dueDate)
end)
