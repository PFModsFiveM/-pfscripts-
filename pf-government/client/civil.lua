-- =====================================================
-- PF GOVERNMENT - CIVIL SERVICES (merged from pfm-cityhall)
-- =====================================================
-- Citizen-facing city hall desk: ID card / license purchase, job center and
-- driving school. Legacy 'qb-cityhall:*' event names are kept as compat
-- aliases so other resources keep working.

if not Config.CivilServices or not Config.CivilServices.Enabled then return end

-- Safety: if the deprecated pfm-cityhall resource is still running, let it keep
-- ownership of these events/peds to avoid duplicates. Remove pfm-cityhall from
-- your server start list to activate this module.
if GetResourceState('pfm-cityhall') == 'started' then
    print('^3[PF-GOVERNMENT]^7 pfm-cityhall is still running - civil services module disabled to avoid duplicates. Remove pfm-cityhall from your server.cfg.')
    return
end

local QBCore = exports['pfm-core']:GetCoreObject()
local Civil = Config.CivilServices

local civilPlayerData = QBCore.Functions.GetPlayerData()
local civilLoggedIn = LocalPlayer.state.isLoggedIn
local civilCoords = GetEntityCoords(PlayerPedId())
local closestCityhall = nil
local closestDrivingSchool = nil
local inRangeCityhall = false
local inRangeDrivingSchool = false
local pedsSpawned = false
local civilBlips = {}

-- =====================================================
-- HELPERS
-- =====================================================

local function getClosestHall()
    local distance = #(civilCoords - Civil.Cityhalls[1].coords)
    local closest = 1
    for i = 1, #Civil.Cityhalls do
        local dist = #(civilCoords - Civil.Cityhalls[i].coords)
        if dist < distance then
            distance = dist
            closest = i
        end
    end
    return closest
end

local function getClosestSchool()
    local distance = #(civilCoords - Civil.DrivingSchools[1].coords)
    local closest = 1
    for i = 1, #Civil.DrivingSchools do
        local dist = #(civilCoords - Civil.DrivingSchools[i].coords)
        if dist < distance then
            distance = dist
            closest = i
        end
    end
    return closest
end

local function createCivilBlip(options)
    local blip = AddBlipForCoord(options.coords.x, options.coords.y, options.coords.z)
    SetBlipSprite(blip, options.sprite or 1)
    SetBlipDisplay(blip, options.display or 4)
    SetBlipScale(blip, options.scale or 1.0)
    SetBlipColour(blip, options.colour or 1)
    SetBlipAsShortRange(blip, true)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentSubstringPlayerName(options.title or 'City Services')
    EndTextCommandSetBlipName(blip)
    return blip
end

local function deleteCivilBlips()
    for i = 1, #civilBlips do
        if DoesBlipExist(civilBlips[i]) then
            RemoveBlip(civilBlips[i])
        end
    end
    civilBlips = {}
end

local function initCivilBlips()
    for i = 1, #Civil.Cityhalls do
        local hall = Civil.Cityhalls[i]
        if hall.showBlip then
            civilBlips[#civilBlips + 1] = createCivilBlip({
                coords = hall.coords,
                sprite = hall.blipData.sprite,
                display = hall.blipData.display,
                scale = hall.blipData.scale,
                colour = hall.blipData.colour,
                title = hall.blipData.title
            })
        end
    end
    for i = 1, #Civil.DrivingSchools do
        local school = Civil.DrivingSchools[i]
        if school.showBlip then
            civilBlips[#civilBlips + 1] = createCivilBlip({
                coords = school.coords,
                sprite = school.blipData.sprite,
                display = school.blipData.display,
                scale = school.blipData.scale,
                colour = school.blipData.colour,
                title = school.blipData.title
            })
        end
    end
end

-- =====================================================
-- MENUS (pfm-menu, same approach as the old cityhall)
-- =====================================================

local function openCityhallMenu()
    local mainMenu = {
        {
            header = 'City Hall',
            isMenuHeader = true
        },
        {
            header = 'ID Card',
            txt = 'Get your ID Card',
            params = {
                event = 'qb-cityhall:client:openIdentityMenu'
            }
        },
        {
            header = 'Job Center',
            txt = 'Available Jobs',
            params = {
                event = 'qb-cityhall:client:openJobMenu'
            }
        },
        {
            header = 'Close Menu',
            txt = '',
            params = {
                event = 'qb-menu:client:closeMenu'
            }
        }
    }

    exports['pfm-menu']:openMenu(mainMenu)
end

local function openIdentityMenu()
    QBCore.Functions.TriggerCallback('qb-cityhall:server:getIdentityData', function(licenses)
        local identityMenu = {
            {
                header = 'Identity',
                isMenuHeader = true
            },
            {
                header = '← Go Back',
                params = {
                    event = 'qb-cityhall:client:openCityhallMenu'
                }
            }
        }

        for license, data in pairs(licenses) do
            identityMenu[#identityMenu + 1] = {
                header = data.label,
                txt = 'Cost: $' .. data.cost,
                params = {
                    event = 'qb-cityhall:client:requestId',
                    args = {
                        type = license,
                        cost = data.cost
                    }
                }
            }
        end

        exports['pfm-menu']:openMenu(identityMenu)
    end, closestCityhall)
end

local function openJobMenu()
    QBCore.Functions.TriggerCallback('qb-cityhall:server:receiveJobs', function(jobs)
        local jobMenu = {
            {
                header = 'Job Center',
                isMenuHeader = true
            },
            {
                header = '← Go Back',
                params = {
                    event = 'qb-cityhall:client:openCityhallMenu'
                }
            }
        }

        for jobName, jobData in pairs(jobs) do
            jobMenu[#jobMenu + 1] = {
                header = jobData.label,
                txt = 'Apply for this job',
                params = {
                    event = 'qb-cityhall:client:applyJob',
                    args = {
                        job = jobName
                    }
                }
            }
        end

        exports['pfm-menu']:openMenu(jobMenu)
    end)
end

-- =====================================================
-- PEDS / ZONES / TARGET
-- =====================================================

local function spawnCivilPeds()
    if not Civil.Peds or not next(Civil.Peds) or pedsSpawned then return end
    for i = 1, #Civil.Peds do
        local current = Civil.Peds[i]
        current.model = type(current.model) == 'string' and joaat(current.model) or current.model
        RequestModel(current.model)
        while not HasModelLoaded(current.model) do
            Wait(0)
        end
        local ped = CreatePed(0, current.model, current.coords.x, current.coords.y, current.coords.z, current.coords.w, false, false)
        FreezeEntityPosition(ped, true)
        SetEntityInvincible(ped, true)
        SetBlockingOfNonTemporaryEvents(ped, true)
        TaskStartScenarioInPlace(ped, current.scenario, true, true)
        current.pedHandle = ped
        if Civil.UseTarget then
            local opts = nil
            if current.drivingschool then
                opts = {
                    label = 'Take Driving Lessons',
                    icon = 'fa-solid fa-car-side',
                    action = function()
                        TriggerServerEvent('qb-cityhall:server:sendDriverTest', Civil.DrivingSchools[closestDrivingSchool].instructors)
                    end
                }
            elseif current.cityhall then
                opts = {
                    label = 'Open Cityhall',
                    icon = 'fa-solid fa-city',
                    action = function()
                        inRangeCityhall = true
                        openCityhallMenu()
                    end
                }
            end
            if opts then
                exports['pfm-target']:AddTargetEntity(ped, {
                    options = { opts },
                    distance = 2.0
                })
            end
        else
            local options = current.zoneOptions
            if options then
                local zone = BoxZone:Create(current.coords.xyz, options.length, options.width, {
                    name = 'zone_gov_civil_' .. ped,
                    heading = current.coords.w,
                    debugPoly = options.debugPoly or false,
                    minZ = current.coords.z - 3.0,
                    maxZ = current.coords.z + 2.0
                })
                zone:onPlayerInOut(function(inside)
                    if civilLoggedIn and closestCityhall and closestDrivingSchool then
                        if inside then
                            if current.drivingschool then
                                inRangeDrivingSchool = true
                                exports['pfm-core']:DrawText('[E] Take Driving Lessons')
                            elseif current.cityhall then
                                inRangeCityhall = true
                                exports['pfm-core']:DrawText('[E] Open Cityhall')
                            end
                        else
                            exports['pfm-core']:HideText()
                            if current.drivingschool then
                                inRangeDrivingSchool = false
                            elseif current.cityhall then
                                inRangeCityhall = false
                            end
                        end
                    end
                end)
            end
        end
    end
    pedsSpawned = true
end

local function deleteCivilPeds()
    if not Civil.Peds or not next(Civil.Peds) or not pedsSpawned then return end
    for i = 1, #Civil.Peds do
        local current = Civil.Peds[i]
        if current.pedHandle then
            DeletePed(current.pedHandle)
        end
    end
    pedsSpawned = false
end

-- =====================================================
-- EVENTS (legacy qb-cityhall names kept for compatibility)
-- =====================================================

RegisterNetEvent('QBCore:Client:OnPlayerLoaded', function()
    civilPlayerData = QBCore.Functions.GetPlayerData()
    civilLoggedIn = true
    spawnCivilPeds()
end)

RegisterNetEvent('QBCore:Client:OnPlayerUnload', function()
    civilPlayerData = {}
    civilLoggedIn = false
    deleteCivilPeds()
end)

RegisterNetEvent('QBCore:Client:OnPlayerUpdated', function(key, val)
    if key ~= 'all' then return end
    civilPlayerData = val
end)

RegisterNetEvent('qb-cityhall:client:openCityhallMenu', function()
    openCityhallMenu()
end)

RegisterNetEvent('qb-cityhall:client:openIdentityMenu', function()
    openIdentityMenu()
end)

RegisterNetEvent('qb-cityhall:client:openJobMenu', function()
    openJobMenu()
end)

RegisterNetEvent('qb-cityhall:client:getIds', function()
    TriggerServerEvent('qb-cityhall:server:getIDs')
end)

RegisterNetEvent('qb-cityhall:client:requestId', function(data)
    if inRangeCityhall then
        local license = Civil.Cityhalls[closestCityhall].licenses[data.type]
        if license and data.cost == license.cost then
            TriggerServerEvent('qb-cityhall:server:requestId', data.type, closestCityhall)
            QBCore.Functions.Notify(('You have received your %s for $%s'):format(license.label, data.cost), 'success', 3500)
        else
            QBCore.Functions.Notify('City hall is not within range of you', 'error')
        end
    else
        QBCore.Functions.Notify('City hall is not within range of you', 'error')
    end
end)

RegisterNetEvent('qb-cityhall:client:applyJob', function(data)
    if inRangeCityhall then
        TriggerServerEvent('qb-cityhall:server:ApplyJob', data.job, Civil.Cityhalls[closestCityhall].coords)
    else
        QBCore.Functions.Notify('City hall is not within range of you', 'error')
    end
end)

RegisterNetEvent('qb-cityhall:client:sendDriverEmail', function(charinfo)
    SetTimeout(math.random(2500, 4000), function()
        local gender = 'Mr.'
        if civilPlayerData.charinfo and civilPlayerData.charinfo.gender == 1 then
            gender = 'Mrs.'
        end
        TriggerServerEvent('qb-phone:server:sendNewMail', {
            sender = 'Township',
            subject = 'Driving lessons request',
            message = ('Hello %s %s,<br><br>We just received a request from someone who wants driving lessons!<br>Name: <strong>%s %s</strong><br>Phone Number: <strong>%s</strong><br><br>Kind regards,<br>Township Los Santos'):format(gender, civilPlayerData.charinfo and civilPlayerData.charinfo.lastname or '', charinfo.firstname, charinfo.lastname, charinfo.phone),
            button = {}
        })
    end)
end)

-- pf-government aliases (forward to the same implementations)
RegisterNetEvent('pf-government:client:openCivilMenu', function()
    openCityhallMenu()
end)

RegisterNetEvent('pf-government:client:openIdentityMenu', function()
    openIdentityMenu()
end)

RegisterNetEvent('pf-government:client:openJobMenu', function()
    openJobMenu()
end)

RegisterNetEvent('pf-government:client:getIds', function()
    TriggerServerEvent('qb-cityhall:server:getIDs')
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    deleteCivilBlips()
    deleteCivilPeds()
end)

-- =====================================================
-- THREADS
-- =====================================================

CreateThread(function()
    while true do
        if civilLoggedIn then
            civilCoords = GetEntityCoords(PlayerPedId())
            closestCityhall = getClosestHall()
            closestDrivingSchool = getClosestSchool()
        end
        Wait(1000)
    end
end)

CreateThread(function()
    initCivilBlips()
    spawnCivilPeds()
    if not Civil.UseTarget then
        while true do
            local sleep = 1000
            if civilLoggedIn and closestCityhall and closestDrivingSchool then
                if inRangeCityhall then
                    sleep = 0
                    if IsControlJustPressed(0, 38) then
                        openCityhallMenu()
                        exports['pfm-core']:KeyPressed()
                        Wait(500)
                        exports['pfm-core']:HideText()
                        sleep = 1000
                    end
                elseif inRangeDrivingSchool then
                    sleep = 0
                    if IsControlJustPressed(0, 38) then
                        TriggerServerEvent('qb-cityhall:server:sendDriverTest', Civil.DrivingSchools[closestDrivingSchool].instructors)
                        sleep = 5000
                        exports['pfm-core']:KeyPressed()
                        Wait(500)
                        exports['pfm-core']:HideText()
                    end
                end
            end
            Wait(sleep)
        end
    end
end)

print('^2[PF-GOVERNMENT]^7 Civil services (cityhall) client loaded')
