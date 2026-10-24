local QBCore = exports['pfm-core']:GetCoreObject()

-- =========================
-- COSMETIC PREVIEW SYSTEM (MOVED FROM damage.lua)
-- =========================
local PreviewSessions = PreviewSessions or {}
local PreviewVeh = PreviewVeh or nil

-- GTA 5 paint color tables (MOVED UP - MUST BE BEFORE getColorName())
local GTA5PaintColors = {
    classic = {
        { name = "Black", index = 0 }, { name = "Graphite", index = 1 }, { name = "Black Steel", index = 2 }, { name = "Dark Steel", index = 3 },
        { name = "Silver", index = 4 }, { name = "Bluish Silver", index = 5 }, { name = "Rolled Steel", index = 6 }, { name = "Shadow Silver", index = 7 },
        { name = "Stone Silver", index = 8 }, { name = "Midnight Silver", index = 9 }, { name = "Cast Iron Silver", index = 10 },
        { name = "Red", index = 27 }, { name = "Torino Red", index = 28 }, { name = "Formula Red", index = 29 }, { name = "Lava Red", index = 150 },
        { name = "Blaze Red", index = 30 }, { name = "Grace Red", index = 31 }, { name = "Garnet Red", index = 32 }, { name = "Sunset Red", index = 33 },
        { name = "Cabernet Red", index = 34 }, { name = "Candy Red", index = 35 }, { name = "Hot Pink", index = 135 }, { name = "Pfsiter Pink", index = 137 },
        { name = "Salmon Pink", index = 136 }, { name = "Sunrise Orange", index = 36 }, { name = "Orange", index = 38 }, { name = "Bright Orange", index = 138 },
        { name = "Gold", index = 99 }, { name = "Bronze", index = 90 }, { name = "Yellow", index = 88 }, { name = "Race Yellow", index = 89 },
        { name = "Dew Yellow", index = 91 }, { name = "Dark Green", index = 49 }, { name = "Racing Green", index = 50 }, { name = "Sea Green", index = 51 },
        { name = "Olive Green", index = 52 }, { name = "Bright Green", index = 53 }, { name = "Gasoline Green", index = 54 },
        { name = "Lime Green", index = 92 }, { name = "Midnight Blue", index = 141 }, { name = "Galaxy Blue", index = 61 },
        { name = "Dark Blue", index = 62 }, { name = "Saxon Blue", index = 63 }, { name = "Blue", index = 64 }, { name = "Mariner Blue", index = 65 },
        { name = "Harbor Blue", index = 66 }, { name = "Diamond Blue", index = 67 }, { name = "Surf Blue", index = 68 }, { name = "Nautical Blue", index = 69 },
        { name = "Racing Blue", index = 73 }, { name = "Ultra Blue", index = 70 }, { name = "Light Blue", index = 74 }, { name = "Chocolate Brown", index = 96 },
        { name = "Bison Brown", index = 101 }, { name = "Creeen Brown", index = 95 }, { name = "Feltzer Brown", index = 94 }, { name = "Maple Brown", index = 97 },
        { name = "Beechwood Brown", index = 103 }, { name = "Sienna Brown", index = 104 }, { name = "Saddle Brown", index = 98 }, { name = "Moss Brown", index = 100 },
        { name = "Woodbeech Brown", index = 102 }, { name = "Straw Brown", index = 99 }, { name = "Sandy Brown", index = 105 }, { name = "Bleached Brown", index = 106 },
        { name = "Schafter Purple", index = 71 }, { name = "Spinnaker Purple", index = 72 }, { name = "Midnight Purple", index = 142 },
        { name = "Bright Purple", index = 145 }, { name = "Cream", index = 107 }, { name = "Ice White", index = 111 }, { name = "Frost White", index = 112 }
    },
    metallic = {
        { name = "Black", index = 0 }, { name = "Graphite", index = 1 }, { name = "Black Steel", index = 2 }, { name = "Dark Steel", index = 3 },
        { name = "Silver", index = 4 }, { name = "Bluish Silver", index = 5 }, { name = "Rolled Steel", index = 6 }, { name = "Shadow Silver", index = 7 },
        { name = "Stone Silver", index = 8 }, { name = "Midnight Silver", index = 9 }, { name = "Cast Iron Silver", index = 10 },
        { name = "Red", index = 27 }, { name = "Torino Red", index = 28 }, { name = "Formula Red", index = 29 }, { name = "Lava Red", index = 150 },
        { name = "Blaze Red", index = 30 }, { name = "Grace Red", index = 31 }, { name = "Garnet Red", index = 32 }, { name = "Sunset Red", index = 33 },
        { name = "Cabernet Red", index = 34 }, { name = "Candy Red", index = 35 }, { name = "Hot Pink", index = 135 }, { name = "Pfsiter Pink", index = 137 },
        { name = "Salmon Pink", index = 136 }, { name = "Sunrise Orange", index = 36 }, { name = "Orange", index = 38 }, { name = "Bright Orange", index = 138 },
        { name = "Gold", index = 99 }, { name = "Bronze", index = 90 }, { name = "Yellow", index = 88 }, { name = "Race Yellow", index = 89 },
        { name = "Dew Yellow", index = 91 }, { name = "Dark Green", index = 49 }, { name = "Racing Green", index = 50 }, { name = "Sea Green", index = 51 },
        { name = "Olive Green", index = 52 }, { name = "Bright Green", index = 53 }, { name = "Gasoline Green", index = 54 },
        { name = "Lime Green", index = 92 }, { name = "Midnight Blue", index = 141 }, { name = "Galaxy Blue", index = 61 },
        { name = "Dark Blue", index = 62 }, { name = "Saxon Blue", index = 63 }, { name = "Blue", index = 64 }, { name = "Mariner Blue", index = 65 },
        { name = "Harbor Blue", index = 66 }, { name = "Diamond Blue", index = 67 }, { name = "Surf Blue", index = 68 }, { name = "Nautical Blue", index = 69 },
        { name = "Racing Blue", index = 73 }, { name = "Ultra Blue", index = 70 }, { name = "Light Blue", index = 74 }, { name = "Chocolate Brown", index = 96 },
        { name = "Bison Brown", index = 101 }, { name = "Creeen Brown", index = 95 }, { name = "Feltzer Brown", index = 94 }, { name = "Maple Brown", index = 97 },
        { name = "Beechwood Brown", index = 103 }, { name = "Sienna Brown", index = 104 }, { name = "Saddle Brown", index = 98 }, { name = "Moss Brown", index = 100 },
        { name = "Woodbeech Brown", index = 102 }, { name = "Straw Brown", index = 99 }, { name = "Sandy Brown", index = 105 }, { name = "Bleached Brown", index = 106 },
        { name = "Schafter Purple", index = 71 }, { name = "Spinnaker Purple", index = 72 }, { name = "Midnight Purple", index = 142 },
        { name = "Bright Purple", index = 145 }, { name = "Cream", index = 107 }, { name = "Ice White", index = 111 }, { name = "Frost White", index = 112 }
    },
    matte = {
        { name = "Matte Black", index = 12 }, { name = "Matte Gray", index = 13 }, { name = "Matte Light Gray", index = 14 },
        { name = "Matte Ice White", index = 131 }, { name = "Matte Blue", index = 83 }, { name = "Matte Dark Blue", index = 82 },
        { name = "Matte Midnight Blue", index = 84 }, { name = "Matte Midnight Purple", index = 149 }, { name = "Matte Schafter Purple", index = 148 },
        { name = "Matte Red", index = 39 }, { name = "Matte Dark Red", index = 40 }, { name = "Matte Orange", index = 41 },
        { name = "Matte Yellow", index = 42 }, { name = "Matte Lime Green", index = 55 }, { name = "Matte Green", index = 128 },
        { name = "Matte Forest Green", index = 151 }, { name = "Matte Foliage Green", index = 155 }, { name = "Matte Olive Darb", index = 152 },
        { name = "Matte Desert Brown", index = 153 }, { name = "Matte Foilage Brown", index = 154 }, { name = "Matte White", index = 131 }
    },
    metals = {
        { name = "Brushed Steel", index = 117 }, { name = "Brushed Black Steel", index = 118 }, { name = "Brushed Aluminum", index = 119 },
        { name = "Pure Gold", index = 158 }, { name = "Brushed Gold", index = 159 }
    },
    util = {
        { name = "Util Black", index = 15 }, { name = "Util Black Poly", index = 16 }, { name = "Util Dark Silver", index = 17 },
        { name = "Util Silver", index = 18 }, { name = "Util Gun Metal", index = 19 }, { name = "Util Shadow Silver", index = 20 },
        { name = "Util Red", index = 33 }, { name = "Util Bright Red", index = 34 }, { name = "Util Garnet Red", index = 35 },
        { name = "Util Dark Green", index = 51 }, { name = "Util Green", index = 52 }, { name = "Util Light Green", index = 53 },
        { name = "Util Dark Blue", index = 62 }, { name = "Util Midnight Blue", index = 63 }, { name = "Util Blue", index = 64 },
        { name = "Util Sea Foam Blue", index = 65 }, { name = "Util Lightning Blue", index = 66 }, { name = "Util Maui Blue Poly", index = 67 },
        { name = "Util Bright Blue", index = 68 }, { name = "Util Purple", index = 70 }, { name = "Util Dark Purple", index = 71 },
        { name = "Util Garnet Red", index = 72 }, { name = "Util Yellow", index = 88 }, { name = "Util Brown", index = 89 },
        { name = "Util Medium Brown", index = 90 }, { name = "Util Light Brown", index = 91 }, { name = "Util Cream", index = 93 }
    },
    chameleon = {
        { name = "Anod Red", index = 161 }, { name = "Anod Blue", index = 162 }, { name = "Anod Gold", index = 163 },
        { name = "Green/Blue Flip", index = 164 }, { name = "Purple/Green Flip", index = 165 }, { name = "Orange/Purple Flip", index = 166 },
        { name = "Red/Green Flip", index = 167 }, { name = "Blue/Green Flip", index = 168 }, { name = "Copper/Orange Flip", index = 169 },
        { name = "Silver/Purple Flip", index = 170 }, { name = "Magenta/Green Flip", index = 171 }, { name = "Gold/Purple Flip", index = 172 },
        { name = "Red/Orange Flip", index = 173 }, { name = "Blue/Purple Flip", index = 174 }, { name = "Green/Red Flip", index = 175 },
        { name = "Orange/Blue Flip", index = 176 }, { name = "Purple/Orange Flip", index = 177 }, { name = "Green/Yellow Flip", index = 178 },
        { name = "Blue/Red Flip", index = 179 }, { name = "Copper/Green Flip", index = 180 }, { name = "Silver/Blue Flip", index = 181 },
        { name = "Magenta/Blue Flip", index = 182 }, { name = "Gold/Green Flip", index = 183 }, { name = "Red/Blue Flip", index = 184 },
        { name = "Blue/Gold Flip", index = 185 }, { name = "Green/Blue/Red Flip", index = 186 }, { name = "Orange/Green Flip", index = 187 },
        { name = "Purple/Blue Flip", index = 188 }, { name = "Green/Orange Flip", index = 189 }, { name = "Blue/Orange Flip", index = 190 },
        { name = "Copper/Blue Flip", index = 191 }, { name = "Silver/Green Flip", index = 192 }, { name = "Magenta/Orange Flip", index = 193 },
        { name = "Gold/Blue Flip", index = 194 }, { name = "Red/Gold Flip", index = 195 }, { name = "Blue/Green/Gold Flip", index = 196 },
        { name = "Green/Red/Blue Flip", index = 197 }, { name = "Orange/Blue/Green Flip", index = 198 }, { name = "Purple/Green/Blue Flip", index = 199 }
    }
}

local WindowTints = {
    {label='None', val=0},{label='Pure Black',val=1},{label='Dark Smoke',val=2},
    {label='Light Smoke',val=3},{label='Stock',val=4},{label='Limo',val=5},{label='Green',val=6}
}

local function isMechanicJob()
    local pd = QBCore.Functions.GetPlayerData()
    return pd and pd.job and pd.job.name and Config.IsMechanicJob(pd.job.name) or false
end

local function getModDisplayName(veh, modType, index)
    if index == -1 then return 'Stock' end
    local lbl = GetModTextLabel(veh, modType, index)
    if lbl and lbl ~= '' then
        local nice = GetLabelText(lbl)
        if nice and nice ~= 'NULL' then return nice end
        return lbl
    end
    return ('Option %d'):format(index + 1)
end

-- Helper: Detect paint type from color index
local function detectPaintType(colorIndex)
    colorIndex = tonumber(colorIndex) or 0
    
    -- Check each paint type's valid range
    -- Chameleon: 161-199
    if colorIndex >= 161 and colorIndex <= 199 then return 'chameleon' end
    
    -- Metals: 117-119, 158-159
    if (colorIndex >= 117 and colorIndex <= 119) or (colorIndex >= 158 and colorIndex <= 159) then return 'metals' end
    
    -- Matte: 12-14, 55, 82-84, 128, 131, 148-155
    if colorIndex == 12 or colorIndex == 13 or colorIndex == 14 or colorIndex == 55 or 
       (colorIndex >= 82 and colorIndex <= 84) or colorIndex == 128 or colorIndex == 131 or
       (colorIndex >= 148 and colorIndex <= 155) then return 'matte' end
    
    -- Util: 15-20, 33-35, 51-53, 62-72, 88-93
    if (colorIndex >= 15 and colorIndex <= 20) or 
       (colorIndex >= 33 and colorIndex <= 35) or
       (colorIndex >= 51 and colorIndex <= 53) or
       (colorIndex >= 62 and colorIndex <= 72) or
       (colorIndex >= 88 and colorIndex <= 93) then return 'util' end
    
    -- Everything else is classic/metallic (they share the same indexes)
    -- We can't distinguish between classic and metallic without additional data,
    -- so default to metallic which has more colors
    return 'metallic'
end

local function captureVehicleAppearance(veh)
    if not DoesEntityExist(veh) then return nil end
    SetVehicleModKit(veh, 0)
    local snap = { mods={}, wheelType=nil, windowTint=nil, colors={} }
    local modTypes = {0,1,2,3,4,6,7,8,9,10,23,48}
    for _, m in ipairs(modTypes) do snap.mods[m] = GetVehicleMod(veh, m) end
    snap.wheelType = GetVehicleWheelType(veh) or 0
    snap.windowTint = GetVehicleWindowTint(veh) or 0
    local p,s = GetVehicleColours(veh)
    local pearl,wheelCol = GetVehicleExtraColours(veh)
    snap.colors.classic = {primary=p or 0, secondary=s or 0, pearl=pearl or 0, wheel=wheelCol or 0}
    
    -- IMPROVED: Detect actual paint types from color indexes
    snap.colors.primaryType = detectPaintType(p or 0)
    snap.colors.secondaryType = detectPaintType(s or 0)
    snap.colors.pearlType = detectPaintType(pearl or 0)
    snap.colors.wheelType = detectPaintType(wheelCol or 0)
    
    -- Check if we already have stored paint types in session (user changed colors)
    if PreviewVeh and PreviewSessions[PreviewVeh] and PreviewSessions[PreviewVeh].appliedPaintTypes then
        local applied = PreviewSessions[PreviewVeh].appliedPaintTypes
        if applied.primary then snap.colors.primaryType = applied.primary end
        if applied.secondary then snap.colors.secondaryType = applied.secondary end
        if applied.pearl then snap.colors.pearlType = applied.pearl end
        if applied.wheel then snap.colors.wheelType = applied.wheel end
    end
    
    if GetIsVehiclePrimaryColourCustom(veh) then
        local r,g,b = GetVehicleCustomPrimaryColour(veh)
        snap.colors.customPrimary = {r=r,g=g,b=b}
        snap.colors.primaryType = 'custom' -- Mark as custom RGB
    end
    if GetIsVehicleSecondaryColourCustom(veh) then
        local r,g,b = GetVehicleCustomSecondaryColour(veh)
        snap.colors.customSecondary = {r=r,g=g,b=b}
        snap.colors.secondaryType = 'custom' -- Mark as custom RGB
    end
    return snap
end

local function applySnapshot(veh, snap)
    if not veh or not DoesEntityExist(veh) or not snap then return end
    SetVehicleModKit(veh, 0)
    if snap.wheelType then SetVehicleWheelType(veh, snap.wheelType) end
    for m, idx in pairs(snap.mods) do SetVehicleMod(veh, m, idx, false) end
    ClearVehicleCustomPrimaryColour(veh)
    ClearVehicleCustomSecondaryColour(veh)
    local c = snap.colors.classic or {primary=0,secondary=0,pearl=0,wheel=0}
    SetVehicleColours(veh, c.primary, c.secondary)
    SetVehicleExtraColours(veh, c.pearl, c.wheel)
    if snap.colors.customPrimary then
        SetVehicleCustomPrimaryColour(veh, snap.colors.customPrimary.r, snap.colors.customPrimary.g, snap.colors.customPrimary.b)
    end
    if snap.colors.customSecondary then
        SetVehicleCustomSecondaryColour(veh, snap.colors.customSecondary.r, snap.colors.customSecondary.g, snap.colors.customSecondary.b)
    end
    if snap.windowTint then SetVehicleWindowTint(veh, snap.windowTint) end
end

-- Helper: Get color name by index and paintType (NOW GTA5PaintColors IS DEFINED)
local function getColorName(paintType, index)
    -- Handle custom RGB colors
    if paintType == 'custom' then
        return 'Custom RGB'
    end
    
    local list = GTA5PaintColors[paintType]
    if not list then
        -- Fallback: try to detect paint type from index
        paintType = detectPaintType(index)
        list = GTA5PaintColors[paintType]
        if not list then return tostring(index) end
    end
    
    for _, color in ipairs(list) do
        if color.index == index then return color.name end
    end
    
    -- If not found in specified type, search all types (last resort)
    for pType, colorList in pairs(GTA5PaintColors) do
        for _, color in ipairs(colorList) do
            if color.index == index then 
                return color.name .. ' (' .. pType .. ')'
            end
        end
    end
    
    return tostring(index)
end

-- Helper: Get window tint name
local function getTintName(idx)
    local tintNames = {[0]='None',[1]='Pure Black',[2]='Dark Smoke',[3]='Light Smoke',[4]='Stock',[5]='Limo',[6]='Green'}
    return tintNames[idx or 0] or tostring(idx)
end

-- Helper: Build a summary of all modifications done during preview
local function buildModificationSummary(veh, before, after)
    local changes = {}
    -- Mods
    for modType, oldIdx in pairs(before.mods or {}) do
        local newIdx = (after.mods or {})[modType]
        if newIdx ~= oldIdx then
            local nameMap = {
                [0]='Spoiler',[1]='Front Bumper',[2]='Rear Bumper',[3]='Side Skirts',
                [4]='Exhaust',[6]='Grille',[7]='Hood',[8]='Fender',[9]='Right Fender',
                [10]='Roof',[23]='Wheels',[48]='Livery'
            }
            local modName = nameMap[modType] or ('Mod '..modType)
            local from = getModDisplayName(veh, modType, oldIdx)
            local to = getModDisplayName(veh, modType, newIdx)
            changes[#changes+1] = ('%s: %s → %s'):format(modName, from, to)
        end
    end

    -- Colors (primary, secondary, pearl, wheel) - FIX: Use applied paint types
    local bcol, acol = before.colors.classic or {}, after.colors.classic or {}
    
    -- Get applied paint types from session tracking
    local appliedTypes = {}
    if PreviewSessions[veh] and PreviewSessions[veh].appliedPaintTypes then
        appliedTypes = PreviewSessions[veh].appliedPaintTypes
    end
    
    -- Primary Color
    if bcol.primary ~= acol.primary then
        local oldType = (before.colors or {}).primaryType or 'classic'
        local newType = appliedTypes.primary or (after.colors or {}).primaryType or 'classic'
        local oldName = getColorName(oldType, bcol.primary or 0)
        local newName = getColorName(newType, acol.primary or 0)
        changes[#changes+1] = ("Primary Color: %s → %s"):format(oldName, newName)
    end
    
    -- Secondary Color
    if bcol.secondary ~= acol.secondary then
        local oldType = (before.colors or {}).secondaryType or 'classic'
        local newType = appliedTypes.secondary or (after.colors or {}).secondaryType or 'classic'
        local oldName = getColorName(oldType, bcol.secondary or 0)
        local newName = getColorName(newType, acol.secondary or 0)
        changes[#changes+1] = ("Secondary Color: %s → %s"):format(oldName, newName)
    end
    
    -- Pearlescent
    if bcol.pearl ~= acol.pearl then
        local oldType = (before.colors or {}).pearlType or 'classic'
        local newType = appliedTypes.pearl or (after.colors or {}).pearlType or 'classic'
        local oldName = getColorName(oldType, bcol.pearl or 0)
        local newName = getColorName(newType, acol.pearl or 0)
        changes[#changes+1] = ("Pearlescent: %s → %s"):format(oldName, newName)
    end
    
    -- Wheel Color
    if bcol.wheel ~= acol.wheel then
        local oldType = (before.colors or {}).wheelType or 'classic'
        local newType = appliedTypes.wheel or (after.colors or {}).wheelType or 'classic'
        local oldName = getColorName(oldType, bcol.wheel or 0)
        local newName = getColorName(newType, acol.wheel or 0)
        changes[#changes+1] = ("Wheel Color: %s → %s"):format(oldName, newName)
    end

    -- Custom colors (RGB)
    local function rgbStr(rgb)
        if not rgb then return "None" end
        return ("RGB(%d,%d,%d)"):format(rgb.r or 0, rgb.g or 0, rgb.b or 0)
    end
    if (before.colors.customPrimary or false) ~= (after.colors.customPrimary or false) then
        changes[#changes+1] = ("Primary Custom: %s → %s"):format(
            rgbStr(before.colors.customPrimary), rgbStr(after.colors.customPrimary))
    end
    if (before.colors.customSecondary or false) ~= (after.colors.customSecondary or false) then
        changes[#changes+1] = ("Secondary Custom: %s → %s"):format(
            rgbStr(before.colors.customSecondary), rgbStr(after.colors.customSecondary))
    end

    -- Window tint
    if before.windowTint ~= after.windowTint then
        changes[#changes+1] = ("Window Tint: %s → %s"):format(
            getTintName(before.windowTint), getTintName(after.windowTint)
        )
    end

    return changes
end

local function endPreview(veh)
    if not veh or not DoesEntityExist(veh) then return end
    local sess = PreviewSessions[veh]
    if not sess or not sess.active then return end
    local before = sess.snapshot
    local after = captureVehicleAppearance(veh)
    applySnapshot(veh, before)
    PreviewSessions[veh] = nil
    pcall(function() TriggerEvent('qb-menu:client:closeMenu') end)
    QBCore.Functions.Notify('Preview ended. Vehicle restored.', 'primary')
    PreviewVeh = nil

    -- Build summary and give preview receipt
    local summary = buildModificationSummary(veh, before, after)
    if #summary > 0 then
        local desc = table.concat(summary, "\n")
        TriggerServerEvent('pf_mech:giveModificationSheet', {
            vehicle = GetDisplayNameFromVehicleModel(GetEntityModel(veh)),
            plate = GetVehicleNumberPlateText(veh),
            description = desc
        })
        QBCore.Functions.Notify('Preview Receipt given with all changes listed.', 'success')
    end
end

local function ensurePreviewSession(veh)
    if PreviewSessions[veh] and PreviewSessions[veh].active then return true end
    local snap = captureVehicleAppearance(veh)
    if not snap then return false end
    PreviewSessions[veh] = { active = true, snapshot = snap }
    PreviewVeh = veh
    CreateThread(function()
        local ped = PlayerPedId()
        while PreviewSessions[veh] and PreviewSessions[veh].active do
            if IsControlJustReleased(0,322) or IsControlJustReleased(0,177) or IsControlJustReleased(0,200) then
                endPreview(veh); break
            end
            if not IsPedInAnyVehicle(ped,false) or GetVehiclePedIsIn(ped,false) ~= veh or GetPedInVehicleSeat(veh,-1) ~= ped then
                endPreview(veh); break
            end
            Wait(120)
        end
    end)
    return true
end

local function buildModList(veh, modType)
    local list = {}
    SetVehicleModKit(veh,0)
    local count = GetNumVehicleMods(veh, modType) or 0
    list[#list+1] = { label = getModDisplayName(veh, modType, -1), index = -1 }
    for i=0,count-1 do
        list[#list+1] = { label = getModDisplayName(veh, modType, i), index = i }
    end
    return list
end

local function OpenQBMenu(entries)
    local ok = false
    local success = pcall(function()
        if exports and exports['pfm-menu'] and exports['pfm-menu'].openMenu then
            exports['pfm-menu']:openMenu(entries); ok = true
        end
    end)
    if not success or not ok then TriggerEvent('qb-menu:client:openMenu', entries); ok = true end
    return ok
end

local function openModMenu(veh, label, modType)
    local m = { { header = label, isMenuHeader = true }, }
    for _, it in ipairs(buildModList(veh, modType)) do
        m[#m+1] = {
            header = it.label, shouldClose = false,
            params = { event='pf_mech:preview:setMod', args={ modType=modType, index=it.index, label=label } }
        }
    end
    m[#m+1] = { header=L('menu_back'), shouldClose=false, params={ event='pf_mech:preview:openMain' } }
    OpenQBMenu(m)
end

local function openTintMenu(veh)
    local m = { { header=L('mod_window_tint'), isMenuHeader=true } }
    for _,t in ipairs(WindowTints) do
        m[#m+1] = {
            header=t.label, shouldClose=false,
            params={ event='pf_mech:preview:setTint', args={ tint=t.val } }
        }
    end
    m[#m+1] = { header=L('menu_back'), shouldClose=false, params={ event='pf_mech:preview:openMain' } }
    OpenQBMenu(m)
end

-- Show paint categories when clicking a color option (primary, secondary, etc)
local function openPaintCategoryMenu(veh, which)
    local menu = {
        { header = (which:gsub("^%l", string.upper)) .. " " .. L('paint_type'), isMenuHeader = true },
        { header = L('paint_classic'),    shouldClose = false, params = { event = "pf_mech:preview:openPaintColorList", args = { which = which, paintType = "classic" } } },
        { header = L('paint_metallic'),   shouldClose = false, params = { event = "pf_mech:preview:openPaintColorList", args = { which = which, paintType = "metallic" } } },
        { header = L('paint_matte'),      shouldClose = false, params = { event = "pf_mech:preview:openPaintColorList", args = { which = which, paintType = "matte" } } },
        { header = L('paint_metals'),     shouldClose = false, params = { event = "pf_mech:preview:openPaintColorList", args = { which = which, paintType = "metals" } } },
        { header = L('paint_util'),       shouldClose = false, params = { event = "pf_mech:preview:openPaintColorList", args = { which = which, paintType = "util" } } },
        { header = L('paint_chameleon'),  shouldClose = false, params = { event = "pf_mech:preview:openPaintColorList", args = { which = which, paintType = "chameleon" } } },
        { header = L('menu_back'),        shouldClose = false, params = { event = "pf_mech:preview:openPaintJobs" } }
    }
    OpenQBMenu(menu)
end

-- Show color list for a GTA 5 paint category
local function openPaintColorListMenu(veh, which, paintType)
    local colors = GTA5PaintColors[paintType] or {}
    local menu = {
        { header = ("%s - %s"):format(which:gsub("^%l", string.upper), L('paint_'..paintType)), isMenuHeader = true }
    }
    for _, color in ipairs(colors) do
        menu[#menu+1] = {
            header = color.name,
            shouldClose = false,
            params = { event = "pf_mech:preview:applyPaintColor", args = { which = which, paintType = paintType, index = color.index } }
        }
    end
    menu[#menu+1] = { header = L('menu_back'), shouldClose = false, params = { event = "pf_mech:preview:openPaintCategory", args = { which = which } } }
    OpenQBMenu(menu)
end

-- Event handlers
RegisterNetEvent('pf_mech:preview:setMod', function(d)
    if not PreviewVeh or not DoesEntityExist(PreviewVeh) then return end
    SetVehicleModKit(PreviewVeh, 0)
    SetVehicleMod(PreviewVeh, d.modType, d.index or -1, false)
    -- Sync to server
    local netId = VehToNet(PreviewVeh)
    if netId and netId ~= 0 then
        TriggerServerEvent('pf_mech:preview:syncMod', netId, d.modType, d.index or -1)
    end
end)

RegisterNetEvent('pf_mech:preview:setTint', function(d)
    if not PreviewVeh or not DoesEntityExist(PreviewVeh) then return end
    SetVehicleWindowTint(PreviewVeh, d.tint or 0)
    -- Sync to server
    local netId = VehToNet(PreviewVeh)
    if netId and netId ~= 0 then
        TriggerServerEvent('pf_mech:preview:syncTint', netId, d.tint or 0)
    end
end)

RegisterNetEvent("pf_mech:preview:applyPaintColor", function(d)
    if not PreviewVeh or not DoesEntityExist(PreviewVeh) then return end
    SetVehicleModKit(PreviewVeh, 0)
    
    -- CRITICAL FIX: Update the CURRENT snapshot (not just the stored one)
    if PreviewSessions[PreviewVeh] then
        local snap = PreviewSessions[PreviewVeh].snapshot
        if snap and snap.colors then
            -- Don't update the original snapshot - that's the "before" state
            -- We need to track the paint type separately for the "after" state
            
            -- Store paint type in a tracking table
            PreviewSessions[PreviewVeh].appliedPaintTypes = PreviewSessions[PreviewVeh].appliedPaintTypes or {}
            PreviewSessions[PreviewVeh].appliedPaintTypes[d.which] = d.paintType
        end
    end
    
    -- Apply the color
    if d.which == "primary" then
        ClearVehicleCustomPrimaryColour(PreviewVeh)
        SetVehicleColours(PreviewVeh, d.index, select(2, GetVehicleColours(PreviewVeh)))
    elseif d.which == "secondary" then
        ClearVehicleCustomSecondaryColour(PreviewVeh)
        SetVehicleColours(PreviewVeh, select(1, GetVehicleColours(PreviewVeh)), d.index)
    elseif d.which == "pearl" then
        local _, wheel = GetVehicleExtraColours(PreviewVeh)
        SetVehicleExtraColours(PreviewVeh, d.index, wheel)
    elseif d.which == "wheel" then
        local pearl, _ = GetVehicleExtraColours(PreviewVeh)
        SetVehicleExtraColours(PreviewVeh, pearl, d.index)
    end
    
    -- Sync to server
    local netId = VehToNet(PreviewVeh)
    if netId and netId ~= 0 then
        TriggerServerEvent('pf_mech:preview:syncPaint', netId, d.which, d.index)
    end
end)

RegisterNetEvent("pf_mech:preview:openPaintCategory", function(d)
    if not PreviewVeh or not DoesEntityExist(PreviewVeh) then return end
    openPaintCategoryMenu(PreviewVeh, d.which)
end)

RegisterNetEvent("pf_mech:preview:openPaintColorList", function(d)
    if not PreviewVeh or not DoesEntityExist(PreviewVeh) then return end
    openPaintColorListMenu(PreviewVeh, d.which, d.paintType)
end)

RegisterNetEvent('pf_mech:preview:openPaintJobs', function()
    if not PreviewVeh or not DoesEntityExist(PreviewVeh) then return end
    local menu = {
        { header = L('menu_paint'), isMenuHeader = true },
        { header = L('color_primary'),    shouldClose = false, params = { event = 'pf_mech:preview:openPaintCategory', args = { which = 'primary' } } },
        { header = L('color_secondary'),  shouldClose = false, params = { event = 'pf_mech:preview:openPaintCategory', args = { which = 'secondary' } } },
        { header = L('color_pearlescent'),shouldClose = false, params = { event = 'pf_mech:preview:openPaintCategory', args = { which = 'pearl' } } },
        { header = L('color_wheel'),      shouldClose = false, params = { event = 'pf_mech:preview:openPaintCategory', args = { which = 'wheel' } } },
        { header = L('menu_back'),        shouldClose = false, params = { event = 'pf_mech:preview:openMain' } }
    }
    OpenQBMenu(menu)
end)

RegisterNetEvent('pf_mech:preview:openMod', function(d)
    if not PreviewVeh or not DoesEntityExist(PreviewVeh) then return end
    openModMenu(PreviewVeh, d.label or 'Mod', d.modType)
end)

RegisterNetEvent('pf_mech:preview:openTint', function()
    if not PreviewVeh or not DoesEntityExist(PreviewVeh) then return end
    openTintMenu(PreviewVeh)
end)

RegisterNetEvent('pf_mech:preview:end', function()
    if not PreviewVeh or not DoesEntityExist(PreviewVeh) then return end
    endPreview(PreviewVeh)
end)

RegisterNetEvent('pf_mech:preview:openMain', function()
    local ped = PlayerPedId()
    local veh = PreviewVeh or GetVehiclePedIsIn(ped,false)
    if not veh or veh == 0 then return end
    if Config.MenuSystem ~= 'qb-menu' then
        QBCore.Functions.Notify(L('preview_requires_qbmenu'), 'error')
        return
    end
    local menu = {
        { header=L('menu_preview'), isMenuHeader=true },
        { header=L('mod_spoiler'),        txt=L('preview_desc'),        shouldClose=false, params={ event='pf_mech:preview:openMod', args={ label=L('mod_spoiler'), modType=0 } } },
        { header=L('mod_front_bumper'),   txt=L('preview_desc'),        shouldClose=false, params={ event='pf_mech:preview:openMod', args={ label=L('mod_front_bumper'), modType=1 } } },
        { header=L('mod_rear_bumper'),    txt=L('preview_desc'),        shouldClose=false, params={ event='pf_mech:preview:openMod', args={ label=L('mod_rear_bumper'), modType=2 } } },
        { header=L('mod_side_skirt'),     txt=L('preview_desc'),        shouldClose=false, params={ event='pf_mech:preview:openMod', args={ label=L('mod_side_skirt'), modType=3 } } },
        { header=L('mod_exhaust'),        txt=L('preview_desc'),        shouldClose=false, params={ event='pf_mech:preview:openMod', args={ label=L('mod_exhaust'), modType=4 } } },
        { header=L('mod_grille'),         txt=L('preview_desc'),        shouldClose=false, params={ event='pf_mech:preview:openMod', args={ label=L('mod_grille'), modType=6 } } },
        { header=L('mod_hood'),           txt=L('preview_desc'),        shouldClose=false, params={ event='pf_mech:preview:openMod', args={ label=L('mod_hood'), modType=7 } } },
        { header=L('mod_fenders'),        txt=L('preview_desc'),        shouldClose=false, params={ event='pf_mech:preview:openMod', args={ label=L('mod_fenders'), modType=8 } } },
        { header=L('mod_right_fender'),   txt=L('preview_desc'),        shouldClose=false, params={ event='pf_mech:preview:openMod', args={ label=L('mod_right_fender'), modType=9 } } },
        { header=L('mod_roof'),           txt=L('preview_desc'),        shouldClose=false, params={ event='pf_mech:preview:openMod', args={ label=L('mod_roof'), modType=10 } } },
        { header=L('mod_livery'),         txt=L('preview_desc'),        shouldClose=false, params={ event='pf_mech:preview:openMod', args={ label=L('mod_livery'), modType=48 } } },
        { header=L('mod_wheels'),         txt=L('preview_desc'),        shouldClose=false, params={ event='pf_mech:preview:openMod', args={ label=L('mod_wheels'), modType=23 } } },
        { header=L('menu_paint'),         txt=L('preview_paint_desc'),  shouldClose=false, params={ event='pf_mech:preview:openPaintJobs' } },
        { header=L('mod_window_tint'),    txt=L('preview_tint_desc'),   shouldClose=false, params={ event='pf_mech:preview:openTint' } },
        { header=L('preview_close_revert'), txt=L('preview_exit_desc'),     params={ event='pf_mech:preview:end' } },
    }
    OpenQBMenu(menu)
end)

RegisterCommand('preview', function()
    if Config.MenuSystem ~= 'qb-menu' then 
        QBCore.Functions.Notify(L('preview_requires_qbmenu'), 'error')
        return 
    end
    if not isMechanicJob() then 
        QBCore.Functions.Notify(L('not_mechanic'), 'error')
        return 
    end
    local ped = PlayerPedId()
    if not IsPedInAnyVehicle(ped,false) then 
        QBCore.Functions.Notify(L('not_in_vehicle'), 'error')
        return 
    end
    local veh = GetVehiclePedIsIn(ped,false)
    if GetPedInVehicleSeat(veh,-1) ~= ped then 
        QBCore.Functions.Notify(L('driver_seat_required'), 'error')
        return 
    end
    NetworkRequestControlOfEntity(veh)
    if not ensurePreviewSession(veh) then 
        QBCore.Functions.Notify(L('preview_init_failed'), 'error')
        return 
    end
    TriggerEvent('pf_mech:preview:openMain')
    QBCore.Functions.Notify(L('preview_started'), 'primary')
end, false)

-- Backward-compatible alias used by client/main.lua
RegisterNetEvent('pf_mech:preview:open', function()
    TriggerEvent('pf_mech:preview:openMain')
end)

-- Apply preview changes received from server so everyone sees them
RegisterNetEvent('pf_mech:preview:applyModClient', function(netId, modType, index)
    local veh = NetToVeh(netId)
    if not veh or veh == 0 or not DoesEntityExist(veh) then return end
    SetVehicleModKit(veh, 0)
    SetVehicleMod(veh, modType, index or -1, false)
end)

RegisterNetEvent('pf_mech:preview:applyTintClient', function(netId, tint)
    local veh = NetToVeh(netId)
    if not veh or veh == 0 or not DoesEntityExist(veh) then return end
    SetVehicleWindowTint(veh, tint or 0)
end)

RegisterNetEvent('pf_mech:preview:applyPaintClient', function(netId, which, index)
    local veh = NetToVeh(netId)
    if not veh or veh == 0 or not DoesEntityExist(veh) then return end
    SetVehicleModKit(veh, 0)
    if which == 'primary' then
        ClearVehicleCustomPrimaryColour(veh)
        SetVehicleColours(veh, index, select(2, GetVehicleColours(veh)))
    elseif which == 'secondary' then
        ClearVehicleCustomSecondaryColour(veh)
        SetVehicleColours(veh, select(1, GetVehicleColours(veh)), index)
    elseif which == 'pearl' then
        local _, wheel = GetVehicleExtraColours(veh)
        SetVehicleExtraColours(veh, index, wheel)
    elseif which == 'wheel' then
        local pearl, _ = GetVehicleExtraColours(veh)
        SetVehicleExtraColours(veh, pearl, index)
    end
end)

RegisterNetEvent('pf_mech:preview:restoreSnapshotClient', function(netId, snapshot)
    local veh = NetToVeh(netId)
    if not veh or veh == 0 or not DoesEntityExist(veh) then return end
    applySnapshot(veh, snapshot)
end)

-- Show preview receipt item using qb-menu (names not indexes)
RegisterNetEvent('pf_mech:previewReceipt:use', function(info)
    if not info then return end
    local title = (Config.PreviewReceipt and Config.PreviewReceipt.menuTitle) or 'Preview Receipt'
    local entries = { { header = title, isMenuHeader = true } }
    local desc = info.description or ''
    if desc ~= '' then
        for line in string.gmatch(desc, '([^\n]+)') do
            entries[#entries+1] = { header = line, isMenuHeader = true }
        end
    else
        entries[#entries+1] = { header = 'No details available', isMenuHeader = true }
    end
    entries[#entries+1] = { header = L('menu_close') or 'Close' }
    OpenQBMenu(entries)
end)
