-- ═══════════════════════════════════════════════════════════════════════════════
--                    AUTO-DETECTION SYSTEM
--              Automatically detect running resources/scripts
-- ═══════════════════════════════════════════════════════════════════════════════

PFMdt = PFMdt or {}
PFMdt.AutoDetect = {}

-- Helper to check if a resource is running
local function IsResourceRunning(resourceName)
    if not GetResourceState then return false end
    local state = GetResourceState(resourceName)
    return state == 'started' or state == 'starting'
end

-- ═══════════════════════════════════════════════════════════════════════════════
-- FRAMEWORK DETECTION
-- ═══════════════════════════════════════════════════════════════════════════════
function PFMdt.AutoDetect.Framework()
    -- QBCore variants
    if IsResourceRunning('qb-core') or IsResourceRunning('qbcore') then
        return 'qb-core'
    end
    
    -- ESX variants
    if IsResourceRunning('es_extended') or IsResourceRunning('esx') then
        return 'esx'
    end
    
    -- Default fallback
    print('^3[PF-MDT AutoDetect] No framework detected, defaulting to qb-core^0')
    return 'qb-core'
end

-- ═══════════════════════════════════════════════════════════════════════════════
-- PHONE DETECTION
-- ═══════════════════════════════════════════════════════════════════════════════
function PFMdt.AutoDetect.Phone()
    -- Check for phone resources in order of priority
    if IsResourceRunning('lb-phone') then
        return 'lb-phone'
    end
    
    if IsResourceRunning('yseries') or IsResourceRunning('tgg-phone') then
        return 'tgg-phone'
    end
    
    if IsResourceRunning('qb-phone') then
        return 'qb-phone'
    end
    
    -- Check for other common phone scripts
    if IsResourceRunning('gksphone') then
        return 'qb-phone' -- Uses similar structure
    end
    
    if IsResourceRunning('d-phone') then
        return 'qb-phone' -- Uses similar structure
    end
    
    -- Default fallback
    print('^3[PF-MDT AutoDetect] No phone resource detected, defaulting to qb-phone^0')
    return 'qb-phone'
end

-- ═══════════════════════════════════════════════════════════════════════════════
-- HOUSING DETECTION
-- ═══════════════════════════════════════════════════════════════════════════════
function PFMdt.AutoDetect.Housing()
    if IsResourceRunning('nolag-properties') or IsResourceRunning('nolag_properties') then
        return 'nolag-properties'
    end
    
    if IsResourceRunning('qb-houses') or IsResourceRunning('qb-housing') then
        return 'qb'
    end
    
    if IsResourceRunning('esx_property') then
        return 'none' -- ESX property not directly supported
    end
    
    -- Default fallback
    print('^3[PF-MDT AutoDetect] No housing resource detected, defaulting to qb^0')
    return 'qb'
end

-- ═══════════════════════════════════════════════════════════════════════════════
-- GARAGE DETECTION
-- ═══════════════════════════════════════════════════════════════════════════════
function PFMdt.AutoDetect.Garage()
    if IsResourceRunning('cd_garage') or IsResourceRunning('cd-garage') or IsResourceRunning('cd-garages') then
        return 'cd-garages'
    end
    
    if IsResourceRunning('qb-garages') or IsResourceRunning('qb-garage') then
        return 'qb-garages'
    end
    
    if IsResourceRunning('esx_advancedgarage') then
        return 'none' -- ESX garage not directly supported
    end
    
    -- Default fallback
    print('^3[PF-MDT AutoDetect] No garage resource detected, defaulting to qb-garages^0')
    return 'qb-garages'
end

-- ═══════════════════════════════════════════════════════════════════════════════
-- BANKING DETECTION
-- ═══════════════════════════════════════════════════════════════════════════════
function PFMdt.AutoDetect.Banking()
    if IsResourceRunning('wasabi_banking') or IsResourceRunning('wasabi-banking') then
        return 'wasabi_banking'
    end
    
    if IsResourceRunning('tgg-banking') or IsResourceRunning('tgg_banking') then
        return 'tgg-banking'
    end
    
    if IsResourceRunning('qb-banking') or IsResourceRunning('qb-management') then
        return 'qb-banking'
    end
    
    if IsResourceRunning('okokBanking') or IsResourceRunning('okok-banking') then
        return 'none' -- Not directly supported
    end
    
    -- Default fallback
    print('^3[PF-MDT AutoDetect] No banking resource detected, defaulting to qb-banking^0')
    return 'qb-banking'
end

-- ═══════════════════════════════════════════════════════════════════════════════
-- BILLING DETECTION
-- ═══════════════════════════════════════════════════════════════════════════════
function PFMdt.AutoDetect.Billing()
    if IsResourceRunning('okok-billing') or IsResourceRunning('okokBilling') then
        return 'okok-billing'
    end
    
    if IsResourceRunning('renewed-billing') or IsResourceRunning('renewed_billing') then
        return 'renewed-billing'
    end
    
    if IsResourceRunning('vivum-billing') or IsResourceRunning('vivum_billing') then
        return 'vivum-billing'
    end
    
    if IsResourceRunning('qb-billing') or IsResourceRunning('qb-management') then
        return 'qb-billing'
    end
    
    -- Default fallback
    print('^3[PF-MDT AutoDetect] No billing resource detected, defaulting to qb-billing^0')
    return 'qb-billing'
end

-- ═══════════════════════════════════════════════════════════════════════════════
-- PRISON DETECTION
-- ═══════════════════════════════════════════════════════════════════════════════
function PFMdt.AutoDetect.Prison()
    if IsResourceRunning('rcore_prison') or IsResourceRunning('rcore-prison') then
        return 'rcore_prison'
    end
    
    if IsResourceRunning('qb-prison') or IsResourceRunning('esx_jail') then
        return 'default'
    end
    
    -- Default fallback
    return 'default'
end

-- ═══════════════════════════════════════════════════════════════════════════════
-- APPLY AUTO-DETECTION
-- Run detection for any config values set to 'auto'
-- ═══════════════════════════════════════════════════════════════════════════════
function PFMdt.AutoDetect.Apply()
    local detections = {}
    
    -- Framework
    if not Config.Framework or Config.Framework == '' or Config.Framework:lower() == 'auto' then
        Config.Framework = PFMdt.AutoDetect.Framework()
        detections.Framework = Config.Framework
    end
    
    -- Phone
    if not Config.Phone or Config.Phone == '' or Config.Phone:lower() == 'auto' then
        Config.Phone = PFMdt.AutoDetect.Phone()
        detections.Phone = Config.Phone
    end
    
    -- Housing
    if not Config.Housing or Config.Housing == '' or Config.Housing:lower() == 'auto' then
        Config.Housing = PFMdt.AutoDetect.Housing()
        detections.Housing = Config.Housing
    end
    
    -- Garage
    if not Config.Garage or Config.Garage == '' or Config.Garage:lower() == 'auto' then
        Config.Garage = PFMdt.AutoDetect.Garage()
        detections.Garage = Config.Garage
    end
    
    -- Banking
    if not Config.Banking or Config.Banking == '' or Config.Banking:lower() == 'auto' then
        Config.Banking = PFMdt.AutoDetect.Banking()
        detections.Banking = Config.Banking
    end
    
    -- Billing
    if not Config.Billing or Config.Billing == '' or Config.Billing:lower() == 'auto' then
        Config.Billing = PFMdt.AutoDetect.Billing()
        detections.Billing = Config.Billing
    end
    
    -- Prison
    if not Config.Prison or Config.Prison == '' or Config.Prison:lower() == 'auto' then
        Config.Prison = PFMdt.AutoDetect.Prison()
        detections.Prison = Config.Prison
    end
    
    -- Print detection results
    if next(detections) then
        print('^2[PF-MDT AutoDetect] Auto-detected the following resources:^0')
        for key, value in pairs(detections) do
            print('^2  • ' .. key .. ': ^3' .. value .. '^0')
        end
    end
end

-- ═══════════════════════════════════════════════════════════════════════════════
-- MANUAL RE-DETECTION
-- Useful for debugging or if resources are started after MDT
-- ═══════════════════════════════════════════════════════════════════════════════
RegisterCommand('mdt_redetect', function()
    print('^3[PF-MDT] Running manual resource detection...^0')
    PFMdt.AutoDetect.Apply()
    print('^2[PF-MDT] Detection complete! Current settings:^0')
    print('^2  Framework: ^3' .. (Config.Framework or 'none') .. '^0')
    print('^2  Phone: ^3' .. (Config.Phone or 'none') .. '^0')
    print('^2  Housing: ^3' .. (Config.Housing or 'none') .. '^0')
    print('^2  Garage: ^3' .. (Config.Garage or 'none') .. '^0')
    print('^2  Banking: ^3' .. (Config.Banking or 'none') .. '^0')
    print('^2  Billing: ^3' .. (Config.Billing or 'none') .. '^0')
    print('^2  Prison: ^3' .. (Config.Prison or 'none') .. '^0')
end, false)

-- Run auto-detection on load
CreateThread(function()
    Wait(100) -- Small delay to ensure resources are loaded
    PFMdt.AutoDetect.Apply()
end)

-- Export for external scripts
exports('RedetectResources', function()
    PFMdt.AutoDetect.Apply()
end)

print('^2[PF-MDT] Auto-detection system loaded^0')
print('^3[PF-MDT] Use /mdt_redetect to manually re-detect resources^0')
