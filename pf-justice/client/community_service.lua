-- Community service on the client (PF_ARCHITECTURE 4.7.9). Shows what the server says: sign-in desks
-- while the citizen has an open order, the work list (pfm-menu, which escapes every string), the task
-- site and the next step point the server chose. Every press only sends an intent; the server checks
-- position, timing, items and the order, and answers with pf-justice:client:CsState.
--
-- Commands: /cs (status, find work, abandon, sign out), /csverify <server id> (supervisors).

local C = PFJusticeClient
local state = nil
local siteBlip, blipTask = nil, nil
local stepping = false
local shownTask = nil   -- 'taskId:stepsDone' of the prompts on screen

local STEP_MS = 6000    -- how long the step animation plays before the step is sent

local function sync() TriggerServerEvent('pf-justice:server:CsSync') end

local function groundAt(p)
    local found, z = GetGroundZFor_3dCoord(p.x + 0.0, p.y + 0.0, p.z + 5.0, false)
    return vector3(p.x + 0.0, p.y + 0.0, (found and z or p.z) + 0.0)
end

local function clearSite()
    if siteBlip then RemoveBlip(siteBlip) siteBlip = nil end
    blipTask = nil
end

local function dueText(order)
    if order.state == 'overdue' then return 'overdue (referred to the court)' end
    local s = tonumber(order.dueIn)
    if not s then return 'no deadline' end
    if s <= 0 then return 'due now' end
    local d, h = math.floor(s / 86400), math.floor((s % 86400) / 3600)
    if d > 0 then return ('due in %d d %d h'):format(d, h) end
    return ('due in %d h %d min'):format(h, math.floor((s % 3600) / 60))
end

local function doStep(task, step)
    if stepping then return end
    stepping = true
    CreateThread(function()
        local ped = PlayerPedId()
        if task.scenario then TaskStartScenarioInPlace(ped, task.scenario, 0, true) end
        Wait(STEP_MS)
        ClearPedTasks(ped)
        TriggerServerEvent('pf-justice:server:CsTaskStep', task.id, step)
        stepping = false
    end)
end

local function refreshTask()
    local task = state and state.task
    local tag = task and (task.id .. ':' .. task.stepsDone) or nil
    if tag == shownTask then return end
    shownTask = tag
    C.RemovePromptsWithPrefix('cs_task')
    if not task then clearSite() return end
    if blipTask ~= task.id then
        clearSite()
        blipTask = task.id
        siteBlip = AddBlipForRadius(task.site.x + 0.0, task.site.y + 0.0, task.site.z + 0.0, task.site.r + 0.0)
        SetBlipColour(siteBlip, 5)
        SetBlipAlpha(siteBlip, 90)
        SetNewWaypoint(task.site.x + 0.0, task.site.y + 0.0)
    end
    local abandon = { label = 'Abandon task', key = 'G', control = 47, holdMs = 1500, icon = 'warning',
        onPress = function() TriggerServerEvent('pf-justice:server:CsAbandonTask', task.id) end }
    if task.stepsDone < task.stepsNeeded then
        local step = task.stepsDone + 1
        local p = task.points[step]
        C.AddPrompt('cs_task_step', {
            coords = groundAt(p) + vector3(0.0, 0.0, 0.6), distance = 2.5, showDistance = 25.0,
            options = {
                { label = ('%s (%d/%d)'):format(task.stepLabel or 'Work', step, task.stepsNeeded),
                  canInteract = function() return not stepping end, onPress = function() doStep(task, step) end },
                abandon,
            },
        })
    else
        C.AddPrompt('cs_task_finish', {
            coords = groundAt(task.site) + vector3(0.0, 0.0, 0.8), distance = math.max(3.0, task.site.r + 0.0), showDistance = 40.0,
            options = {
                { label = 'Finish task', onPress = function() TriggerServerEvent('pf-justice:server:CsCompleteTask', task.id) end },
                abandon,
            },
        })
    end
end

local function refreshDesks()
    C.RemovePromptsWithPrefix('cs_desk')
    if not state then return end
    for _, d in ipairs(state.signIns or {}) do
        local options
        if state.shift then
            options = {
                { label = 'Find community service work', onPress = function() TriggerServerEvent('pf-justice:server:CsListWork') end },
                { label = 'Sign out', onPress = function() TriggerServerEvent('pf-justice:server:CsEndShift') end },
            }
        else
            options = { { label = 'Sign in for community service', onPress = function() TriggerServerEvent('pf-justice:server:CsStartShift') end } }
        end
        C.AddPrompt('cs_desk_' .. tostring(d.id), { coords = vector3(d.x + 0.0, d.y + 0.0, d.z + 0.0), distance = 2.5, showDistance = 10.0, options = options })
    end
end

RegisterNetEvent('pf-justice:client:CsState', function(s)
    state = type(s) == 'table' and s or nil
    refreshDesks()
    refreshTask()
end)

-- the work list from the server: pfm-menu shows every string as text
RegisterNetEvent('pf-justice:client:CsWorkList', function(list)
    if type(list) ~= 'table' or #list == 0 then return end
    local menu = { { header = 'Community service work', isMenuHeader = true } }
    for _, w in ipairs(list) do
        menu[#menu + 1] = {
            header = tostring(w.label or w.kind),
            txt = ('%s, %s - %d m - %d unit(s) open'):format(tostring(w.site or '?'), tostring(w.district or '?'),
                tonumber(w.distance) or 0, tonumber(w.unitsOpen) or 0),
            params = { event = 'pf-justice:client:CsPick', args = tonumber(w.id) },
        }
    end
    exports['pfm-menu']:openMenu(menu)
end)

-- local only (pfm-menu raises it with TriggerEvent): never a net event
AddEventHandler('pf-justice:client:CsPick', function(id)
    if tonumber(id) then TriggerServerEvent('pf-justice:server:CsClaimTask', tonumber(id)) end
end)
AddEventHandler('pf-justice:client:CsMenuAction', function(action)
    if action == 'list' then TriggerServerEvent('pf-justice:server:CsListWork')
    elseif action == 'abandon' and state and state.task then TriggerServerEvent('pf-justice:server:CsAbandonTask', state.task.id)
    elseif action == 'signout' then TriggerServerEvent('pf-justice:server:CsEndShift') end
end)

RegisterCommand('cs', function()
    if not state then C.Notify('You have no community service order', 'primary') return end
    local menu = { { header = 'Community service', isMenuHeader = true } }
    for _, o in ipairs(state.orders or {}) do
        menu[#menu + 1] = { header = ('Order #%d: %d of %d units'):format(o.id, o.unitsDone or 0, o.units or 0), txt = dueText(o), disabled = true }
    end
    if state.shift then
        menu[#menu + 1] = { header = state.shift.supervised and 'Signed in (supervised)' or 'Signed in', disabled = true }
        if state.task then
            menu[#menu + 1] = { header = ('Task: %s'):format(tostring(state.task.label)),
                txt = ('Steps %d of %d'):format(state.task.stepsDone, state.task.stepsNeeded), disabled = true }
            menu[#menu + 1] = { header = 'Abandon task', params = { event = 'pf-justice:client:CsMenuAction', args = 'abandon' } }
        else
            menu[#menu + 1] = { header = 'Find work nearby', params = { event = 'pf-justice:client:CsMenuAction', args = 'list' } }
        end
        menu[#menu + 1] = { header = 'Sign out', params = { event = 'pf-justice:client:CsMenuAction', args = 'signout' } }
    else
        menu[#menu + 1] = { header = 'Sign in at a community service desk', txt = 'City Hall and the county sheriff desks', disabled = true }
    end
    exports['pfm-menu']:openMenu(menu)
end, false)

RegisterCommand('csverify', function(_, args)
    local id = tonumber(args and args[1])
    if not id then C.Notify('Usage: /csverify <server id>', 'error') return end
    TriggerServerEvent('pf-justice:server:CsVerifyShift', id)
end, false)

RegisterNetEvent('QBCore:Client:OnPlayerLoaded', function() sync() end)
AddEventHandler('onClientResourceStart', function(res)
    if res == GetCurrentResourceName() then sync() end
end)
AddEventHandler('onClientResourceStop', function(res)
    if res == GetCurrentResourceName() then clearSite() end
end)
