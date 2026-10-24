# PF Government - Integration Guide

This guide provides detailed examples for integrating your existing scripts with the PF Government system.

## 🎯 Table of Contents

1. [Restaurant Integration](#restaurant-integration)
2. [Business Scripts Integration](#business-scripts-integration)
3. [Housing/Property Integration](#housingproperty-integration)
4. [MDT/Police Integration](#mdtpolice-integration)
5. [Job Payment Integration](#job-payment-integration)
6. [Vehicle Shop Integration](#vehicle-shop-integration)
7. [Custom Script Integration](#custom-script-integration)

---

## 🍽️ Restaurant Integration

### For `pf-restaurants` or Similar

**Location:** `server/main.lua` or wherever revenue is processed

```lua
-- When a sale occurs
RegisterNetEvent('restaurant:server:processSale', function(restaurantId, amount, paymentType)
    local src = source
    
    -- Your existing sale logic...
    local success = ProcessSale(src, amount)
    
    if success then
        -- GOVERNMENT INTEGRATION: Track revenue
        exports['pf-government']:UpdateBusinessRevenue(restaurantId, amount)
        
        -- This automatically:
        -- 1. Updates business total revenue
        -- 2. Collects business tax (if auto-collection enabled)
        -- 3. Flags suspicious revenue spikes
        -- 4. Updates government business oversight
    end
end)
```

**When Restaurant Opens/Registers:**

```lua
RegisterNetEvent('restaurant:server:register', function(restaurantData)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    
    -- Your registration logic...
    
    -- GOVERNMENT INTEGRATION: Register business
    exports['pf-government']:RegisterBusiness(
        restaurantData.id,          -- Unique business ID
        restaurantData.name,         -- Business name
        'restaurant',                -- Business type
        Player.PlayerData.citizenid, -- Owner citizenid
        GetPlayerName(src)           -- Owner name
    )
    
    -- This creates:
    -- 1. Business registry entry
    -- 2. Utility account (power/water)
    -- 3. Tax tracking record
end)
```

**Check Business Power Before Operations:**

```lua
-- In your restaurant access/cooking functions
RegisterNetEvent('restaurant:server:startCooking', function(restaurantId, recipe)
    local src = source
    
    -- GOVERNMENT INTEGRATION: Check if restaurant has power
    local hasPower = exports['pf-government']:HasBusinessPower(restaurantId)
    
    if not hasPower then
        TriggerClientEvent('QBCore:Notify', src, 'Restaurant power is disconnected. Pay utility bills!', 'error')
        return
    end
    
    -- Continue with cooking...
end)
```

---

## 🏢 Business Scripts Integration

### Generic Business Template

**For any business script (mechanic shops, dealerships, etc.):**

```lua
-- Server-side

-- 1. Register Business on Creation
function CreateBusiness(ownerId, businessType, businessName)
    local businessId = GenerateUniqueId()
    
    -- Your business creation code...
    
    -- GOVERNMENT INTEGRATION
    local Player = QBCore.Functions.GetPlayer(ownerId)
    if Player then
        exports['pf-government']:RegisterBusiness(
            businessId,
            businessName,
            businessType,
            Player.PlayerData.citizenid,
            Player.PlayerData.charinfo.firstname .. ' ' .. Player.PlayerData.charinfo.lastname
        )
    end
    
    return businessId
end

-- 2. Track Revenue on Sales
RegisterNetEvent('business:server:makeSale', function(businessId, amount, item)
    -- Your sale processing...
    
    -- GOVERNMENT INTEGRATION
    exports['pf-government']:UpdateBusinessRevenue(businessId, amount)
end)

-- 3. Check License Status Before Operations
function CanBusinessOperate(businessId)
    local licenseStatus = exports['pf-government']:GetBusinessLicenseStatus(businessId)
    
    if licenseStatus == 'suspended' or licenseStatus == 'revoked' then
        return false, 'Business license is ' .. licenseStatus
    end
    
    if licenseStatus == 'expired' then
        return false, 'Business license has expired'
    end
    
    return true
end

-- 4. Update Employee Count
RegisterNetEvent('business:server:hireEmployee', function(businessId, employeeCitizenid)
    -- Your hire logic...
    
    local employeeCount = GetBusinessEmployeeCount(businessId)
    exports['pf-government']:UpdateBusinessEmployees(businessId, employeeCount)
end)
```

---

## 🏠 Housing/Property Integration

### For `qb-houses`, `qb-apartments`, or Custom Housing

**Register Property on Purchase:**

```lua
-- Server-side
RegisterNetEvent('housing:server:purchaseProperty', function(propertyId, propertyData)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    
    -- Your purchase logic...
    
    -- GOVERNMENT INTEGRATION: Create utility account
    exports['pf-government']:RegisterProperty(
        propertyId,
        propertyData.label or propertyData.address,
        Player.PlayerData.citizenid,
        Player.PlayerData.charinfo.firstname .. ' ' .. Player.PlayerData.charinfo.lastname
    )
end)
```

**Check Power/Water on Entry:**

```lua
-- Server-side
RegisterNetEvent('housing:server:enterProperty', function(propertyId)
    local src = source
    
    -- GOVERNMENT INTEGRATION: Check utilities
    local hasPower = exports['pf-government']:HasPower(propertyId)
    local hasWater = exports['pf-government']:PropertyHasWater(propertyId)
    
    -- Send status to client
    TriggerClientEvent('housing:client:setUtilities', src, {
        power = hasPower,
        water = hasWater
    })
end)
```

**Client-side Implementation:**

```lua
-- Client-side
RegisterNetEvent('housing:client:setUtilities', function(utilities)
    CurrentPropertyUtilities = utilities
    
    if not utilities.power then
        -- Disable lights
        SetArtificialLightsState(false)
        
        -- Disable electrical appliances
        DisableElectricalDevices()
        
        QBCore.Functions.Notify('This property has no power. Utility bills may be overdue.', 'error')
    end
    
    if not utilities.water then
        -- Disable water-related features
        DisableBathrooms()
        DisableKitchenSink()
    end
end)
```

**Property Transfer:**

```lua
-- When property is sold/transferred
RegisterNetEvent('housing:server:transferProperty', function(propertyId, newOwnerId)
    local newOwner = QBCore.Functions.GetPlayer(newOwnerId)
    
    -- Your transfer logic...
    
    -- GOVERNMENT INTEGRATION: Update utility account owner
    exports['pf-government']:RegisterProperty(
        propertyId,
        propertyData.label,
        newOwner.PlayerData.citizenid,
        newOwner.PlayerData.charinfo.firstname .. ' ' .. newOwner.PlayerData.charinfo.lastname
    )
end)
```

---

## 👮 MDT/Police Integration

### For `pf-policemdt`, `pf-emsmdt`, or Custom MDT

**Receive Laws from Government:**

In your MDT server file:

```lua
-- Export function for government to call
exports('SyncLaws', function(laws)
    -- Update your MDT database with laws
    for _, law in ipairs(laws) do
        MySQL.insert('INSERT INTO mdt_laws (law_id, title, category, content, penalty_min, penalty_max, fine_min, fine_max, status) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?) ON DUPLICATE KEY UPDATE title=VALUES(title), content=VALUES(content), penalty_min=VALUES(penalty_min), penalty_max=VALUES(penalty_max), fine_min=VALUES(fine_min), fine_max=VALUES(fine_max), status=VALUES(status)',
            {law.id, law.title, law.category, law.content, law.penalty_min, law.penalty_max, law.fine_min, law.fine_max, law.status})
    end
    
    print('[MDT] Synced ' .. #laws .. ' laws from government')
    
    -- Notify online officers
    TriggerClientEvent('mdt:client:lawsUpdated', -1)
end)
```

**Get Laws on MDT Startup:**

```lua
-- When MDT initializes
CreateThread(function()
    Wait(2000) -- Wait for government to load
    
    if GetResourceState('pf-government') == 'started' then
        local laws = exports['pf-government']:GetActiveLaws()
        exports['pf-policemdt']:SyncLaws(laws)
    end
end)
```

**Create Fines/Bills When Issuing Citations:**

```lua
RegisterNetEvent('mdt:server:issueFine', function(targetCitizenid, amount, reason)
    local src = source
    local Officer = QBCore.Functions.GetPlayer(src)
    
    -- Your fine logic...
    
    -- GOVERNMENT INTEGRATION: Create bill in government system
    local dueDate = os.date('%Y-%m-%d %H:%M:%S', os.time() + 604800) -- 7 days
    
    exports['pf-government']:CreateBill(
        'citizen',           -- Target type
        targetCitizenid,     -- Target ID
        amount,              -- Amount
        'fine',              -- Bill type
        dueDate,             -- Due date
        reason,              -- Description
        Officer.PlayerData.citizenid,
        Officer.PlayerData.charinfo.firstname .. ' ' .. Officer.PlayerData.charinfo.lastname
    )
end)
```

---

## 💼 Job Payment Integration

### Paycheck Tax Collection

**QBCore Boss Menu Integration:**

```lua
-- This is handled automatically if enabled in config:
Config.Integrations.PaycheckTax.enabled = true
```

**Manual Integration for Custom Payment Systems:**

```lua
RegisterNetEvent('job:server:receivePayment', function(amount, jobName)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    
    -- Calculate income tax
    local taxRate = exports['pf-government']:GetTaxRate('income')
    local taxAmount = math.floor(amount * (taxRate / 100))
    local netAmount = amount - taxAmount
    
    -- Give net payment to player
    Player.Functions.AddMoney('bank', netAmount, 'Job payment')
    
    -- Tax is automatically collected by government export
    -- Just notify the player
    TriggerClientEvent('QBCore:Notify', src, 'Received $' .. netAmount .. ' (Tax: $' .. taxAmount .. ')', 'success')
end)
```

---

## 🚗 Vehicle Shop Integration

### Vehicle Registration Fees

```lua
RegisterNetEvent('vehicleshop:server:purchaseVehicle', function(vehicleData)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    
    -- Your purchase logic...
    
    -- GOVERNMENT INTEGRATION: Charge registration fee
    local success, fee = exports['pf-government']:ChargeVehicleRegistration(
        Player.PlayerData.citizenid,
        {
            model = vehicleData.model,
            plate = vehicleData.plate,
            type = vehicleData.type
        }
    )
    
    if success and fee > 0 then
        TriggerClientEvent('QBCore:Notify', src, 'Vehicle registration fee: $' .. fee .. ' (Bill sent)', 'primary')
    end
end)
```

---

## 🔧 Custom Script Integration

### Example: Nightclub Script

**Complete integration example:**

```lua
-- =====================================
-- NIGHTCLUB SERVER INTEGRATION
-- =====================================

local Nightclubs = {}

-- Initialize nightclub
function CreateNightclub(ownerId, clubName, location)
    local src = ownerId
    local Player = QBCore.Functions.GetPlayer(src)
    local clubId = 'nightclub_' .. Player.PlayerData.citizenid .. '_' .. os.time()
    
    Nightclubs[clubId] = {
        id = clubId,
        name = clubName,
        owner = Player.PlayerData.citizenid,
        location = location,
        employees = {},
        revenue = 0
    }
    
    -- GOVERNMENT: Register business
    exports['pf-government']:RegisterBusiness(
        clubId,
        clubName,
        'nightclub',
        Player.PlayerData.citizenid,
        Player.PlayerData.charinfo.firstname .. ' ' .. Player.PlayerData.charinfo.lastname
    )
    
    -- GOVERNMENT: Check if needs license
    local licenseStatus = exports['pf-government']:GetBusinessLicenseStatus(clubId)
    if licenseStatus == 'none' then
        TriggerClientEvent('QBCore:Notify', src, '⚠️ You need to obtain a Nightclub License from City Hall', 'warning')
    end
    
    return clubId
end

-- Door access check
function CanEnterNightclub(clubId)
    -- GOVERNMENT: Check license
    local licenseStatus = exports['pf-government']:GetBusinessLicenseStatus(clubId)
    if licenseStatus ~= 'active' then
        return false, 'Nightclub license is not active'
    end
    
    -- GOVERNMENT: Check power
    local hasPower = exports['pf-government']:HasBusinessPower(clubId)
    if not hasPower then
        return false, 'Nightclub power is disconnected'
    end
    
    return true
end

-- Entry fee payment
RegisterNetEvent('nightclub:server:payEntryFee', function(clubId, amount)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    
   -- Check if can enter
    local canEnter, reason = CanEnterNightclub(clubId)
    if not canEnter then
        TriggerClientEvent('QBCore:Notify', src, reason, 'error')
        return
    end
    
    -- Process payment
    if Player.Functions.RemoveMoney('cash', amount, 'Nightclub entry') then
        -- GOVERNMENT: Track revenue
        exports['pf-government']:UpdateBusinessRevenue(clubId, amount)
        
        Nightclubs[clubId].revenue = Nightclubs[clubId].revenue + amount
        
        TriggerClientEvent('nightclub:client:gainEntry', src, clubId)
    end
end)

-- Bar sales
RegisterNetEvent('nightclub:server:purchaseDrink', function(clubId, drinkName, price)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    
    -- Check power for bar operations
    local hasPower = exports['pf-government']:HasBusinessPower(clubId)
    if not hasPower then
        TriggerClientEvent('QBCore:Notify', src, 'Bar is closed - no power', 'error')
        return
    end
    
    -- Process sale
    if Player.Functions.RemoveMoney('cash', price, 'Bought ' .. drinkName) then
        Player.Functions.AddItem(drinkName, 1)
        
        -- GOVERNMENT: Track revenue
        exports['pf-government']:UpdateBusinessRevenue(clubId, price)
    end
end)

-- Hire employee
RegisterNetEvent('nightclub:server:hireEmployee', function(clubId, citizenid)
    local nightclub = Nightclubs[clubId]
    table.insert(nightclub.employees, citizenid)
    
    -- GOVERNMENT: Update employee count
    exports['pf-government']:UpdateBusinessEmployees(clubId, #nightclub.employees)
end)
```

---

## 📊 Best Practices

### 1. **Always Check Exports Exist**

```lua
if GetResourceState('pf-government') ~= 'started' then
    print('[YourScript] Government system not found - running without integration')
    return
end
```

### 2. **Handle Export Failures Gracefully**

```lua
local success, result = pcall(function()
    return exports['pf-government']:UpdateBusinessRevenue(businessId, amount)
end)

if not success then
    print('[YourScript] Failed to update government revenue: ' .. tostring(result))
end
```

### 3. **Cache Government Data When Possible**

```lua
local TaxRates = {}

CreateThread(function()
    while true do
        Wait(60000) -- Update every minute
        if GetResourceState('pf-government') == 'started' then
            TaxRates = exports['pf-government']:GetTaxRates()
        end
    end
end)
```

### 4. **Provide Fallbacks**

```lua
function GetIncomeTaxRate()
    if GetResourceState('pf-government') == 'started' then
        return exports['pf-government']:GetTaxRate('income')
    else
        return 15.00 -- Default fallback
    end
end
```

---

## 🆘 Testing Integration

### Test Checklist

After integrating, test these scenarios:

- [ ] Business registers successfully
- [ ] Revenue tracking updates government stats
- [ ] Tax collection works
- [ ] Utility cutoff prevents operations
- [ ] License checks block unauthorized activities
- [ ] Bills are created correctly
- [ ] No server errors in console
- [ ] Client receives proper notifications

---

## 📞 Support

If you need help integrating your custom script:

1. Check the export exists in `server/main.lua`
2. Review this guide for similar examples
3. Enable debug mode: `Config.Debug = true`
4. Check server console for errors

---

**Happy Integrating! 🎉**
