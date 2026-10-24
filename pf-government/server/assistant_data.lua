-- =====================================================
-- PF GOVERNMENT - ASSISTANT LOCATION DATA
-- =====================================================
-- All known city locations organized by category.
-- AssistantGetNearest() uses Euclidean distance to find the closest.

local BUSINESS_CATEGORY_MAP = {
    mechanic = 'mechanic',
    mechanicshop = 'mechanic',
    auto = 'mechanic',
    garage = 'mechanic',

    gas = 'gas',
    gasstation = 'gas',
    fuel = 'gas',

    store = 'store',
    grocery = 'store',
    supermarket = 'store',
    convenience = 'store',
    shop = 'store',

    hospital = 'hospital',
    clinic = 'hospital',
    medical = 'hospital',

    police = 'police',
    sheriff = 'police',

    government = 'government',
    courthouse = 'government',
    cityhall = 'government',
    municipal = 'government'
}

function MapBusinessCategory(raw)
    local key = string.lower(tostring(raw or '')):gsub('[^%w]', '')
    return BUSINESS_CATEGORY_MAP[key] or 'business'
end

local function buildDynamicLocationEntry(loc, forceCategory)
    local x = tonumber(loc and loc.x)
    local y = tonumber(loc and loc.y)
    if not x or not y then
        return nil
    end

    return {
        name = tostring(loc.name or 'Location'),
        x = x,
        y = y,
        z = tonumber(loc.z) or 0,
        category = forceCategory or tostring(loc.category or 'location'),
        description = tostring(loc.description or (forceCategory or loc.category or 'location')),
        keywords = type(loc.keywords) == 'table' and loc.keywords or { tostring(forceCategory or loc.category or 'location') },
        url = loc.url
    }
end

Config.AssistantLocations = {

    police = {
        { name = "Mission Row PD",       x =  425.1,   y =  -979.5,  z = 30.7,  description = "Main LSPD station in downtown Los Santos" },
        { name = "Paleto Bay Sheriff",    x = -444.4,   y =  6014.7,  z = 31.7,  description = "Sheriff station in Paleto Bay" },
        { name = "Sandy Shores Sheriff",  x = 1853.1,   y =  3689.2,  z = 34.3,  description = "Sheriff station in Sandy Shores" },
        { name = "Rockford Hills Police", x = -1108.9,  y =  -845.1,  z = 19.3,  description = "Police sub-station in Rockford Hills" },
        { name = "Davis Police Post",     x =  83.8,    y = -1388.8,  z = 29.3,  description = "Police outpost in Davis" },
    },

    hospital = {
        { name = "Pillbox Medical Center",        x =  307.1,  y =  -595.2, z = 43.3,  description = "Main public hospital serving Los Santos" },
        { name = "Sandy Shores Medical Center",   x = 1839.4,  y =  3672.9, z = 34.3,  description = "Rural medical center in Sandy Shores" },
        { name = "Paleto Bay Medical Center",     x = -275.0,  y =  6635.0, z = 7.4,   description = "Medical facility in Paleto Bay" },
        { name = "Central EMS Station",           x = -449.7,  y =  -340.5, z = 34.5,  description = "EMS dispatch and care station" },
    },

    mechanic = {
        { name = "Hayes Autos",                  x = -1415.9, y =  -446.2, z = 35.9,  description = "Full vehicle repair and service" },
        { name = "Premium Deluxe Motorsport",    x =  -45.0,  y = -1098.4, z = 26.4,  description = "Vehicle dealership and repairs" },
        { name = "Benny's Original Motor Works", x = -183.2,  y = -1321.9, z = 31.3,  description = "Custom vehicle upgrades and repairs" },
        { name = "Sandy Shores Auto",            x = 1967.7,  y =  3812.9, z = 32.5,  description = "Auto repair shop in Sandy Shores" },
        { name = "Paleto Bay Mechanic",          x = -334.3,  y =  6082.0, z = 31.4,  description = "Vehicle service in Paleto Bay" },
    },

    store = {
        { name = "24/7 Supermarket (Mission Row)", x =   29.4,  y = -1344.4, z = 29.5,  description = "24-hour convenience store" },
        { name = "24/7 Supermarket (Little Seoul)", x = -705.8, y =  -913.5, z = 19.2,  description = "24-hour convenience store" },
        { name = "24/7 Supermarket (Strawberry)",  x = -48.2,  y =  -1757.2, z = 29.4, description = "24-hour convenience store" },
        { name = "Rob's Liquor (Vinewood)",        x =  372.8,  y =   328.8, z = 103.6, description = "Convenience store and liquor" },
        { name = "LTD Gasoline & Store",           x = -1228.4, y =  -905.6, z = 13.0,  description = "Convenience store and gas" },
        { name = "Sandy Shores Store",             x = 1731.1,  y =  3727.7, z = 34.2,  description = "General store in Sandy Shores" },
    },

    gas = {
        { name = "Gas Station (Davis)",             x =  176.0,  y = -1562.0, z = 29.3,  description = "Fuel station in Davis" },
        { name = "Gas Station (Sandy Shores)",      x = 1787.2,  y =  3330.0, z = 41.2,  description = "Fuel station in Sandy Shores" },
        { name = "Gas Station (Airport Road)",      x = -2554.3, y =  -358.9, z = 14.9,  description = "Fuel station near the airport" },
        { name = "Gas Station (Cypress Flats)",     x =  999.9,  y =  -980.4, z = 42.2,  description = "Fuel station in Cypress Flats" },
        { name = "Gas Station (Strawberry Ave)",    x = -719.7,  y = -935.6,  z = 19.2,  description = "Fuel station on Strawberry Ave" },
        { name = "Gas Station (Route 68)",          x = -1437.6, y =  3042.5, z = 32.7,  description = "Fuel station on Route 68" },
    },

    cityhall = {
        { name = "City Hall",                x = -544.67, y = -204.25, z = 38.22, description = "Main government administration building" },
        { name = "Rockford Hills City Hall", x = -557.6,  y =  -191.2, z = 38.2,  description = "Government services and permits" },
    },

    bank = {
        { name = "Fleeca Bank (Legion Square)",      x =  149.0,  y = -1044.1, z = 29.4,  description = "Main Fleeca Bank branch" },
        { name = "Fleeca Bank (Little Seoul)",       x = -350.8,  y =  -49.8,  z = 49.0,  description = "Little Seoul Fleeca Bank" },
        { name = "Pacific Standard Bank",            x =  232.3,  y =  220.9,  z = 106.3, description = "Pacific Standard Bank, downtown" },
        { name = "Blaine County Savings Bank",       x = 1175.1,  y =  2706.7, z = 38.1,  description = "Rural bank in Blaine County" },
        { name = "Union Depository",                 x =   28.5,  y =  -666.0, z = 16.5,  description = "Central banking facility" },
    },

    taxi = {
        { name = "Taxi Depot",            x = -68.7,   y = -1764.7, z = 29.4,  description = "Yellow Cab taxi headquarters" },
        { name = "Taxi Stand (Airport)",  x = -1076.3, y = -2730.0, z = 13.8,  description = "Taxi pickup at the airport" },
    },

    airport = {
        { name = "Los Santos Intl Airport", x = -1037.6, y = -2737.7, z = 20.2, description = "Main international airport" },
        { name = "Sandy Shores Airfield",   x = 1755.8,  y = 3243.8,  z = 41.3, description = "Regional airfield in Sandy Shores" },
    },
}

-- =====================================================
-- HELPER: Get all locations as a flat list
-- =====================================================

function AssistantGetAllLocations()
    local all = {}
    for category, locs in pairs(Config.AssistantLocations or {}) do
        for _, loc in ipairs(locs) do
            all[#all + 1] = {
                name        = loc.name,
                x           = loc.x,
                y           = loc.y,
                z           = loc.z,
                category    = category,
                description = loc.description or category,
                keywords    = { category, string.lower(loc.name) }
            }
        end
    end

    if type(AssistantGetDynamicLocations) == 'function' then
        for _, loc in ipairs(AssistantGetDynamicLocations()) do
            local mapped = buildDynamicLocationEntry(loc)
            if mapped then
                all[#all + 1] = mapped
            end
        end
    end

    return all
end

print('^2[PF-GOVERNMENT]^7 Assistant location data loaded')
