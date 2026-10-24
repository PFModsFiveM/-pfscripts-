-- VERIFICATION SCRIPT
-- Use this to verify your installation is correct
-- Place in your console and run /verify_outfitbag

local function CheckResource()
    local status = GetResourceState('pf-outfitbag')
    print("^2[PF Outfit Bag] Resource Status: " .. status .. "^7")
    return status == 'started'
end

local function CheckDependencies()
    print("^3[PF Outfit Bag] Checking Dependencies:^7")
    
    local qbcore = GetResourceState('pfm-core')
    print("  - qb-core: " .. qbcore .. (qbcore == 'started' and " ^2✓^7" or " ^1✗^7"))
    
    local oxtarget = GetResourceState('ox_target')
    local qbtarget = GetResourceState('pfm-target')
    print("  - ox_target: " .. oxtarget .. (oxtarget == 'started' and " ^2✓^7" or " (optional)"))
    print("  - qb-target: " .. qbtarget .. (qbtarget == 'started' and " ^2✓^7" or " (optional)"))
    
    local qbclothing = GetResourceState('pfm-clothing')
    local illenium = GetResourceState('illenium_appearance')
    print("  - qb-clothing: " .. qbclothing .. (qbclothing == 'started' and " ^2✓^7" or " (optional)"))
    print("  - illenium_appearance: " .. illenium .. (illenium == 'started' and " ^2✓^7" or " (optional)"))
end

local function CheckConfig()
    print("^3[PF Outfit Bag] Configuration:^7")
    print("  - Item Name: " .. Config.ItemName)
    print("  - Prop Model: " .. Config.PropModel)
    print("  - Target System: " .. Config.TargetSystem)
    print("  - Clothing System: " .. Config.ClothingSystem)
    print("  - Interact Distance: " .. Config.InteractDistance)
    print("  - Debug Mode: " .. (Config.Debug and "^2ON^7" or "^1OFF^7"))
end

RegisterCommand('verify_outfitbag', function(source, args, rawCommand)
    print("^3===================================^7")
    print("^3 PF Outfit Bag - Verification^7")
    print("^3===================================^7")
    
    if CheckResource() then
        CheckDependencies()
        CheckConfig()
        print("^3===================================^7")
        print("^2[✓] All checks complete!^7")
        print("^3===================================^7")
    else
        print("^1[✗] Resource is not running!^7")
        print("^3===================================^7")
    end
end, false)

RegisterCommand('test_outfitbag', function(source, args, rawCommand)
    print("^3[PF Outfit Bag] Testing:^7")
    TriggerEvent('pf-outfitbag:useItem')
    print("^2[✓] Placed test bag!^7")
end, false)

print("^2[PF Outfit Bag] Verification script loaded!^7")
print("^2Use /verify_outfitbag to check installation^7")
print("^2Use /test_outfitbag to spawn a test bag^7")
