local QBCore = exports['pfm-core']:GetCoreObject()

-- Detect active helpers
local function resourceStarted(name)
    local st = GetResourceState(name)
    return st == 'started' or st == 'starting'
end

local useOx   = resourceStarted('ox_lib') and lib
local useQbIn = resourceStarted('qb-input') and exports['pfm-input']

local function isMechanic()
    local d = QBCore.Functions.GetPlayerData()
    return d and d.job and Config.IsMechanicJob(d.job.name)
end

local function nearbyVeh(radius)
    local ped = PlayerPedId()
    local pos = GetEntityCoords(ped)
    local veh = GetClosestVehicle(pos.x, pos.y, pos.z, radius or 6.0, 0, 70)
    if veh ~= 0 and DoesEntityExist(veh) then return veh end
    return 0
end

local function normPlate(veh)
    if veh == 0 or not DoesEntityExist(veh) then return nil end
    return GetVehicleNumberPlateText(veh):gsub('%s+',''):upper()
end

-- Helper: get readable model name
local function vehicleDisplayName(veh)
    local hash = GetEntityModel(veh)
    local key = GetDisplayNameFromVehicleModel(hash)
    local label = key and GetLabelText(key)
    if label and label ~= 'NULL' then return label end
    return key or ('0x'..string.format('%X', hash))
end

-- Helper: primary color (RGB or index)
local function vehiclePrimaryColor(veh)
    if not veh or not DoesEntityExist(veh) then return 'UNKNOWN' end
    local r,g,b = GetVehicleCustomPrimaryColour(veh)
    if r and g and b then
        return string.format('RGB(%d,%d,%d)', r,g,b)
    end
    local colorPrimary, colorSecondary = GetVehicleColours(veh)
    return string.format('IDX(%d)', colorPrimary or 0)
end

-- Helper: paint descriptor (NEW)
local function vehiclePaintDescriptor(veh)
    if not veh or not DoesEntityExist(veh) then return 'UNKNOWN' end
    local p1, p2 = GetVehicleColours(veh)
    local pr,pg,pb = GetVehicleCustomPrimaryColour(veh)
    local sr,sg,sb = GetVehicleCustomSecondaryColour(veh)
    local customPrim = (pr and pg and pb) and (pr+pg+pb) > 0
    local customSec  = (sr and sg and sb) and (sr+sg+sb) > 0
    if customPrim or customSec then
        return string.format('PRGB(%d,%d,%d)|SRGB(%d,%d,%d)', pr or 0, pg or 0, pb or 0, sr or 0, sg or 0, sb or 0)
    end
    return string.format('IDX(%d,%d)', p1 or 0, p2 or 0)
end

-- Color name map + fallback family (covers most GTA palette indices)
local COLOR_NAMES = {
	[0]='Black',[1]='Graphite',[2]='Black Steel',[3]='Dark Steel',[4]='Silver',[5]='Bluish Silver',[6]='Rolled Steel',
	[7]='Shadow Silver',[8]='Stone Silver',[9]='Midnight Silver',[10]='Cast Iron Silver',
	[11]='Red',[12]='Torino Red',[13]='Formula Red',[14]='Lava Red',[15]='Blaze Red',[16]='Grace Red',
	[17]='Garnet Red',[18]='Sunset Red',[19]='Cabernet Red',[20]='Candy Red',[21]='Sunrise Orange',
	[22]='Orange',[23]='Bright Orange',[24]='Gold',[25]='Bronze',
	[26]='Yellow',[27]='Race Yellow',[28]='Dew Yellow',
	[29]='Dark Green',[30]='Racing Green',[31]='Sea Green',[32]='Olive Green',[33]='Bright Green',[34]='Gasoline Green',[35]='Lime Green',
	[36]='Midnight Blue',[37]='Galaxy Blue',[38]='Dark Blue',[39]='Saxon Blue',[40]='Blue',[41]='Mariner Blue',
	[42]='Harbor Blue',[43]='Diamond Blue',[44]='Surf Blue',[45]='Nautical Blue',[46]='Racing Blue',[47]='Ultra Blue',[48]='Light Blue',
	[49]='Chocolate Brown',[50]='Bison Brown',[51]='Creek Brown',[52]='Feltzer Brown',[53]='Maple Brown',[54]='Beechwood Brown',
	[55]='Sienna Brown',[56]='Saddle Brown',[57]='Moss Brown',[58]='Woodbeech Brown',[59]='Straw Brown',[60]='Sandy Brown',[61]='Bleached Brown',
	[62]='Schafter Purple',[63]='Spinnaker Purple',[64]='Midnight Purple',[65]='Bright Purple',
	[66]='Cream',[67]='Ice White',[68]='Frost White',
	[136]='Hot Pink',[137]='Salmon Pink',[138]='Pfister Pink',[139]='Bright Pink'
}
local function colorFamily(idx)
	idx = tonumber(idx) or 0
	if idx <= 10 then return 'Grey' end
	if idx >= 11 and idx <= 28 then
		if idx >= 26 then return 'Yellow' end
		if idx >= 21 and idx <= 23 then return 'Orange' end
		return 'Red'
	end
	if idx >= 29 and idx <= 35 then return 'Green' end
	if idx >= 36 and idx <= 48 then return 'Blue' end
	if idx >= 49 and idx <= 61 then return 'Brown' end
	if idx >= 62 and idx <= 65 then return 'Purple' end
	if idx >= 66 and idx <= 68 then return 'White' end
	if idx >= 136 and idx <= 139 then return 'Pink' end
	return ('Color #%d'):format(idx)
end
local function colorNameFromIndex(idx)
	return COLOR_NAMES[tonumber(idx) or 0] or colorFamily(idx)
end
-- Helper: get Primary/Secondary color names; “Custom” if RGB custom is set
local function vehicleColorNames(veh)
	if not veh or not DoesEntityExist(veh) then return 'Unknown','Unknown' end
	local isCustomP = GetIsVehiclePrimaryColourCustom(veh)
	local isCustomS = GetIsVehicleSecondaryColourCustom(veh)
	local pIdx, sIdx = GetVehicleColours(veh)
	local pName = isCustomP and 'Custom' or colorNameFromIndex(pIdx or 0)
	local sName = isCustomS and 'Custom' or colorNameFromIndex(sIdx or 0)
	return pName, sName
end

-- Helper: get readable model name
local function vehicleDisplayName(veh)
    local hash = GetEntityModel(veh)
    local key = GetDisplayNameFromVehicleModel(hash)
    local label = key and GetLabelText(key)
    if label and label ~= 'NULL' then return label end
    return key or ('0x'..string.format('%X', hash))
end

-- Helper: primary color (RGB or index)
local function vehiclePrimaryColor(veh)
    if not veh or not DoesEntityExist(veh) then return 'UNKNOWN' end
    local r,g,b = GetVehicleCustomPrimaryColour(veh)
    if r and g and b then
        return string.format('RGB(%d,%d,%d)', r,g,b)
    end
    local colorPrimary, colorSecondary = GetVehicleColours(veh)
    return string.format('IDX(%d)', colorPrimary or 0)
end

-- Helper: paint descriptor (NEW)
local function vehiclePaintDescriptor(veh)
    if not veh or not DoesEntityExist(veh) then return 'UNKNOWN' end
    local p1, p2 = GetVehicleColours(veh)
    local pr,pg,pb = GetVehicleCustomPrimaryColour(veh)
    local sr,sg,sb = GetVehicleCustomSecondaryColour(veh)
    local customPrim = (pr and pg and pb) and (pr+pg+pb) > 0
    local customSec  = (sr and sg and sb) and (sr+sg+sb) > 0
    if customPrim or customSec then
        return string.format('PRGB(%d,%d,%d)|SRGB(%d,%d,%d)', pr or 0, pg or 0, pb or 0, sr or 0, sg or 0, sb or 0)
    end
    return string.format('IDX(%d,%d)', p1 or 0, p2 or 0)
end

-- REPLACE: color name map + family fallback (covers most GTA palette indices)
local COLOR_NAMES = {
    [0]='Black',[1]='Graphite',[2]='Black Steel',[3]='Dark Steel',[4]='Silver',[5]='Bluish Silver',[6]='Rolled Steel',
    [7]='Shadow Silver',[8]='Stone Silver',[9]='Midnight Silver',[10]='Cast Iron Silver',
    [11]='Red',[12]='Torino Red',[13]='Formula Red',[14]='Lava Red',[15]='Blaze Red',[16]='Grace Red',
    [17]='Garnet Red',[18]='Sunset Red',[19]='Cabernet Red',[20]='Candy Red',[21]='Sunrise Orange',
    [22]='Orange',[23]='Bright Orange',[24]='Gold',[25]='Bronze',
    [26]='Yellow',[27]='Race Yellow',[28]='Dew Yellow',
    [29]='Dark Green',[30]='Racing Green',[31]='Sea Green',[32]='Olive Green',[33]='Bright Green',[34]='Gasoline Green',[35]='Lime Green',
    [36]='Midnight Blue',[37]='Galaxy Blue',[38]='Dark Blue',[39]='Saxon Blue',[40]='Blue',[41]='Mariner Blue',
    [42]='Harbor Blue',[43]='Diamond Blue',[44]='Surf Blue',[45]='Nautical Blue',[46]='Racing Blue',[47]='Ultra Blue',[48]='Light Blue',
    [49]='Chocolate Brown',[50]='Bison Brown',[51]='Creeen Brown',[52]='Feltzer Brown',[53]='Maple Brown',[54]='Beechwood Brown',
    [55]='Sienna Brown',[56]='Saddle Brown',[57]='Moss Brown',[58]='Woodbeech Brown',[59]='Straw Brown',[60]='Sandy Brown',[61]='Bleached Brown',
    [62]='Schafter Purple',[63]='Spinnaker Purple',[64]='Midnight Purple',[65]='Bright Purple',
    [66]='Cream',[67]='Ice White',[68]='Frost White',
    -- Popular extended indices (from LSC palettes)
    [69]='Black',[70]='Graphite',[71]='Black Steel',[72]='Dark Steel',[73]='Silver',[74]='Bluish Silver',[75]='Rolled Steel',
    [76]='Shadow Silver',[77]='Stone Silver',[78]='Midnight Silver',[79]='Cast Iron Silver',
    [80]='Red',[81]='Torino Red',[82]='Formula Red',[83]='Lava Red',[84]='Blaze Red',[85]='Grace Red',[86]='Garnet Red',
    [87]='Sunset Red',[88]='Cabernet Red',[89]='Candy Red',[90]='Sunrise Orange',[91]='Orange',[92]='Bright Orange',
    [93]='Yellow',[94]='Race Yellow',[95]='Dew Yellow',
    [96]='Dark Green',[97]='Racing Green',[98]='Sea Green',[99]='Olive Green',[100]='Bright Green',[101]='Gasoline Green',[102]='Lime Green',
    [103]='Midnight Blue',[104]='Galaxy Blue',[105]='Dark Blue',[106]='Saxon Blue',[107]='Blue',[108]='Mariner Blue',
    [109]='Harbor Blue',[110]='Diamond Blue',[111]='Surf Blue',[112]='Nautical Blue',[113]='Racing Blue',[114]='Ultra Blue',[115]='Light Blue',
    [116]='Chocolate Brown',[117]='Bison Brown',[118]='Creek Brown',[119]='Feltzer Brown',[120]='Maple Brown',[121]='Beechwood Brown',
    [122]='Sienna Brown',[123]='Saddle Brown',[124]='Moss Brown',[125]='Woodbeech Brown',[126]='Straw Brown',[127]='Sandy Brown',[128]='Bleached Brown',
    [129]='Schafter Purple',[130]='Spinnaker Purple',[131]='Midnight Purple',[132]='Bright Purple',
    [133]='Cream',[134]='Ice White',[135]='Frost White',
    -- Some special slots often used by modkits
    [136]='Hot Pink',[137]='Salmon Pink',[138]='Pfister Pink',[139]='Bright Pink',
    [140]='Midnight Blue',[141]='Dark Blue',[142]='Saxon Blue',[143]='Blue',[144]='Mariner Blue',[145]='Harbor Blue',
    [146]='Diamond Blue',[147]='Surf Blue',[148]='Nautical Blue',[149]='Racing Blue',[150]='Ultra Blue',[151]='Light Blue',
    [152]='Chocolate Brown',[153]='Bison Brown',[154]='Creek Brown',[155]='Feltzer Brown',[156]='Maple Brown',[157]='Beechwood Brown',
    [158]='Straw Brown',[159]='Sandy Brown'
}

local function colorFamily(idx)
    idx = tonumber(idx) or 0
    if idx <= 10 or (idx >= 69 and idx <= 79) then return 'Grey' end
    if (idx >= 11 and idx <= 28) or (idx >= 80 and idx <= 95) then
        if idx >= 26 and idx <= 28 then return 'Yellow' end
        if (idx >= 21 and idx <= 23) or (idx >= 90 and idx <= 92) then return 'Orange' end
        return 'Red'
    end
    if (idx >= 29 and idx <= 35) or (idx >= 96 and idx <= 102) then return 'Green' end
    if (idx >= 36 and idx <= 48) or (idx >= 103 and idx <= 115) then return 'Blue' end
    if (idx >= 49 and idx <= 61) or (idx >= 116 and idx <= 128) then return 'Brown' end
    if (idx >= 62 and idx <= 65) or (idx >= 129 and idx <= 132) then return 'Purple' end
    if idx == 66 or idx == 67 or idx == 68 or (idx >= 133 and idx <= 135) then return 'White' end
    if idx >= 136 and idx <= 139 then return 'Pink' end
    return ('Color #%d'):format(idx)
end

local function colorNameFromIndex(idx)
    idx = tonumber(idx) or 0
    return COLOR_NAMES[idx] or colorFamily(idx)
end

-- Rebuild openServiceBook with New Entry gating
local function openServiceBook(plate)
    local ped = PlayerPedId()
    local veh = IsPedInAnyVehicle(ped,false) and GetVehiclePedIsIn(ped,false) or 0
    local canNew = veh ~= 0 and GetPedInVehicleSeat(veh,-1) == ped and plate == GetVehicleNumberPlateText(veh):gsub('%s+',''):upper() and isMechanic()
    QBCore.Functions.TriggerCallback('pf_mech:service:get', function(rows)
        local menu = {
            { header = ('Service Book • %s'):format(plate), txt = 'History entries (view-only)', isMenuHeader = true }
        }
        if #rows == 0 then
            menu[#menu+1] = { header = 'No Entries', txt = 'No service history found', params = {} }
        end
        for _, r in ipairs(rows) do
            menu[#menu+1] = {
                header = r.title,
                txt = (r.svc_date or '') .. ' • ' .. (tostring(r.mileage or 0) .. ' mi'),
                params = { event = 'pf_mech:service:showEntry', args = { plate = plate, entry = r } }
            }
        end
        if canNew then
            menu[#menu+1] = {
                header = 'New Entry',
                txt = 'Create new service record',
                params = { event = 'pf_mech:service:newEntry', args = { plate = plate } }
            }
        end
        menu[#menu+1] = { header = 'Close', params = { event = 'qb-menu:client:closeMenu' } }
        if useOx and Config.MenuSystem == 'ox_lib' then
            local opts = {}
            for _, item in ipairs(menu) do
                if not item.isMenuHeader then
                    opts[#opts+1] = {
                        title = item.header,
                        description = item.txt,
                        onSelect = function()
                            if item.params and item.params.event then
                                TriggerEvent(item.params.event, item.params.args)
                            end
                        end
                    }
                end
            end
            lib.registerContext({ id = 'svc_book_'..plate, title = ('Service Book • %s'):format(plate), options = opts })
            lib.showContext('svc_book_'..plate)
        else
            exports['pfm-menu']:openMenu(menu)
        end
    end, plate)
end

-- Item use: require driver seat (auto plate)
local activeServiceBookSlot = nil

RegisterNetEvent('pf-mechanicjob:client:use:service_book', function(lockedPlate, slot)
    local ped = PlayerPedId()
    if not IsPedInAnyVehicle(ped, false) then
        QBCore.Functions.Notify('Enter vehicle (driver) to view service book', 'error')
        return
    end
    local veh = GetVehiclePedIsIn(ped, false)
    if GetPedInVehicleSeat(veh, -1) ~= ped then
        QBCore.Functions.Notify('Driver seat required', 'error')
        return
    end
    local plate = GetVehicleNumberPlateText(veh):gsub('%s+',''):upper()
    
    -- If plate was passed (pre-validated), use it. Otherwise validate here
    if lockedPlate and lockedPlate ~= plate then
        QBCore.Functions.Notify(
            ('This service book is locked to vehicle %s\nCurrent: %s'):format(lockedPlate, plate), 
            'error')
        return
    end
    
    if not slot then
        local items = QBCore.Functions.GetPlayerData().items or {}
        for s, it in pairs(items) do
            if it and it.name == 'service_book' then
                if not lockedPlate or (it.info and it.info.lockedPlate == lockedPlate) then
                    slot = s
                    break
                end
            end
        end
    end
    activeServiceBookSlot = slot
    openServiceBook(plate)
end)

-- Client helper: get current vehicle plate and send to server for validation
RegisterCommand('test_service_book', function()
    local ped = PlayerPedId()
    if IsPedInAnyVehicle(ped, false) then
        local veh = GetVehiclePedIsIn(ped, false)
        local plate = GetVehicleNumberPlateText(veh):gsub('%s+',''):upper()
        TriggerServerEvent('pf-mechanicjob:server:checkServiceBookLock', plate)
    end
end)

-- New Entry (ADD serviced_by & location fields)
RegisterNetEvent('pf_mech:service:newEntry', function(data)
    local ped = PlayerPedId()
    if not IsPedInAnyVehicle(ped,false) then QBCore.Functions.Notify('Must be in vehicle','error') return end
    local veh = GetVehiclePedIsIn(ped,false)
    if GetPedInVehicleSeat(veh,-1) ~= ped then QBCore.Functions.Notify('Driver seat required','error') return end
    if not isMechanic() then QBCore.Functions.Notify('Not a mechanic','error') return end

    local livePlate = GetVehicleNumberPlateText(veh):gsub('%s+',''):upper()
    local modelName = vehicleDisplayName(veh)
    -- CHANGED: use name mapping (no RGB indices)
    local primaryName, secondaryName = vehicleColorNames(veh)
    local paintDesc = ('Primary: %s | Secondary: %s'):format(primaryName, secondaryName)
    local mileageState = Entity(veh).state and tonumber(Entity(veh).state.mileage) or 0

    local collect = {}
    if useQbIn then
        local input = exports['pfm-input']:ShowInput({
            header = ('New Entry • %s'):format(livePlate),
            submitText = 'Save',
            inputs = {
                { text = 'Title',        name = 'title',       type = 'text', isRequired = true },
                { text = 'Service Done (use || for new line)', name = 'service', type = 'text', isRequired = true },
                { text = 'Service Description (optional)', name = 'service_description', type = 'text' },
                { text = 'Serviced By (name)', name = 'serviced_by', type = 'text', isRequired = true },
                { text = 'Location (shop / place)', name = 'location', type = 'text', isRequired = true },
                -- mileage removed (auto)
            }
        })
        if not input then return end
        collect.title              = input.title
        collect.service            = (input.service or ''):gsub('||','\n')
        collect.service_description= (input.service_description or ''):gsub('||','\n')
        collect.serviced_by        = input.serviced_by
        collect.location           = input.location
        collect.mileage            = mileageState
    elseif useOx then
        local input = lib.inputDialog(('New Entry • %s'):format(livePlate), {
            { type='input',   label='Title', required=true },
            { type='textarea',label='Service Done', required=true },
            { type='textarea',label='Service Description (optional)', required=false },
            { type='input',   label='Serviced By (name)', required=true },
            { type='input',   label='Location (shop / place)', required=true },
            -- mileage auto
        })
        if not input then return end
        collect.title              = input[1]
        collect.service            = input[2]
        collect.service_description= input[3] or ''
        collect.serviced_by        = input[4]
        collect.location           = input[5]
        collect.mileage            = mileageState
    else
        QBCore.Functions.Notify('Input UI missing','error'); return
    end

    if (collect.title or ''):gsub('%s+','')=='' or
       (collect.service or ''):gsub('%s+','')=='' or
       (collect.serviced_by or ''):gsub('%s+','')=='' or
       (collect.location or ''):gsub('%s+','')=='' then
        QBCore.Functions.Notify('Required fields missing','error'); return
    end

    collect.model = modelName
    -- collect.color no longer needed (legacy); keep if your server expects it:
    -- collect.color = ''
    collect.paint = paintDesc
    collect.mileage = mileageState

    TriggerServerEvent('pf_mech:service:addEntry', livePlate, collect, activeServiceBookSlot)
end)

-- Detail view: render full entry; ensure handler exists so clicking does not just close
RegisterNetEvent('pf_mech:service:showEntry', function(data)
    local e = data and data.entry; if not e then return end
    local plate = data.plate or e.plate or ''
    local primTxt, secTxt = 'N/A','N/A'
    if type(e.paint) == 'string' and e.paint:find('Primary:') then
        primTxt = (e.paint:match('Primary:%s*([^|]+)') or 'N/A'):gsub('%s+$','')
        secTxt  = (e.paint:match('Secondary:%s*(.+)$') or 'N/A'):gsub('%s+$','')
    end

    local menu = {
        { header = (e.title or 'Service Entry'), txt = ('Plate: %s'):format(plate), isMenuHeader = true },
        { header = 'Service Done', txt = (e.service or 'N/A'):sub(1, 1500), params = {} },
    }
    if e.service_description and e.service_description ~= '' then
        menu[#menu+1] = { header = 'Service Description', txt = e.service_description:sub(1, 2000), params = {} }
    end
    menu[#menu+1] = { header = 'Serviced By', txt = e.serviced_by or 'N/A', params = {} }
    menu[#menu+1] = { header = 'Location', txt = e.location or 'N/A', params = {} }
    menu[#menu+1] = { header = 'Date', txt = e.svc_date or 'N/A', params = {} }
    menu[#menu+1] = { header = 'Mileage', txt = tostring(e.mileage or 0) .. ' mi', params = {} }
    menu[#menu+1] = { header = 'Colors', txt = ('Primary: %s\nSecondary: %s'):format(primTxt, secTxt), params = {} }
    menu[#menu+1] = { header = 'Model', txt = e.model or 'N/A', params = {} }
    menu[#menu+1] = { header = 'Back', params = { event = 'pf_mech:service:back', args = { plate = plate } } }
    if Config.MenuSystem ~= 'ox_lib' then
        menu[#menu+1] = { header = 'Close', params = { event = 'qb-menu:client:closeMenu' } }
        return exports['pfm-menu']:openMenu(menu)
    end

    -- ox_lib path
    local opts = {}
    for _, item in ipairs(menu) do
        if not item.isMenuHeader then
            opts[#opts+1] = {
                title = item.header or '',
                description = item.txt or '',
                onSelect = function()
                    if item.params and item.params.event then
                        TriggerEvent(item.params.event, item.params.args)
                    end
                end
            }
        end
    end
    lib.registerContext({ id='svc_view_'..(e.id or 0), title=e.title or 'Service Entry', options=opts })
    lib.showContext('svc_view_'..(e.id or 0))
end)

RegisterNetEvent('pf_mech:service:back', function(data)
    openServiceBook(data.plate)
end)

-- Refresh
RegisterNetEvent('pf_mech:service:refresh', function(plate)
    openServiceBook(plate)
end)
