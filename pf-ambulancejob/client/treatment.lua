-- Treatment on the client: menus, progress bars and the CPR rhythm. Nothing here decides anything:
-- every action is a request to the server (pf-ambulancejob:server:treat / cprTick), which checks the
-- provider, distance, items and the patient's state again and answers with what happened.
--   /treat [id]   treatment menu for a patient (the closest one within reach without an id)
--   /cpr [id]     start CPR on a patient in cardiac arrest (stop by moving or cancelling)
-- Self-care items (bandage, IFAK, painkillers...) arrive as pf-ambulancejob:client:SelfTreat from the
-- server after it checked the item can be used now.

local Treatments = PFMed.Treatments
local reqCount = 0
local busy = false
local cprTarget = nil

local function notify(text, kind) QBCore.Functions.Notify(text, kind or 'primary') end

local function nextReq()
    reqCount = reqCount + 1
    return ('t%d_%d'):format(GetGameTimer(), reqCount)
end

local function closestPlayer(maxDist)
    local players = QBCore.Functions.GetPlayersFromCoords()
    local me = PlayerId()
    local coords = GetEntityCoords(PlayerPedId())
    local best, bestDist = nil, maxDist
    for _, pl in ipairs(players) do
        if pl ~= me then
            local d = #(GetEntityCoords(GetPlayerPed(pl)) - coords)
            if d <= bestDist then best, bestDist = pl, d end
        end
    end
    return best and GetPlayerServerId(best) or nil
end

local function resolveTarget(arg)
    local id = tonumber(arg)
    if id then return math.floor(id) end
    return closestPlayer(Treatments.Defaults.TouchDistance)
end

local function animFor(action)
    if action.name == 'cpr' then return { dict = 'mini@cpr@char_a@cpr_str', anim = 'cpr_pumpchest', flags = 1 } end
    return { dict = 'amb@medic@standing@tendtodead@idle_a', anim = 'idle_a', flags = 49 }
end

--- Runs the progress bar for an action, then asks the server. cb(result) gets the server's answer.
local function perform(target, actionName, extra, cb)
    local action = Treatments.Actions[actionName]
    if not action or busy then return end
    busy = true
    local anim = animFor(action)
    QBCore.Functions.Progressbar('pf_treat_' .. actionName, action.label .. '...', action.duration or 4000, false, true,
        { disableMovement = true, disableCarMovement = true, disableMouse = false, disableCombat = true },
        { animDict = anim.dict, anim = anim.anim, flags = anim.flags }, {}, {}, function()
            StopAnimTask(PlayerPedId(), anim.dict, anim.anim, 1.0)
            local data = { target = target, action = actionName, req = nextReq() }
            for k, v in pairs(extra or {}) do data[k] = v end
            QBCore.Functions.TriggerCallback('pf-ambulancejob:server:treat', function(res)
                busy = false
                res = type(res) == 'table' and res or {}
                local msg = res.ok and res.result and res.result.message or res.message
                if msg then notify(tostring(msg), res.ok and 'success' or 'error') end
                if cb then cb(res) end
            end, data)
        end, function()
            busy = false
            StopAnimTask(PlayerPedId(), anim.dict, anim.anim, 1.0)
            notify(Lang:t('error.canceled'), 'error')
        end)
end

-- ── CPR: one server tick every CprTickSeconds while the medic stays put ───────────────────────

local function stopCpr()
    if not cprTarget then return end
    cprTarget = nil
    ClearPedTasks(PlayerPedId())
end

function StartCpr(target)
    if cprTarget then return stopCpr() end
    target = tonumber(target)
    if not target then return notify(Lang:t('error.no_player'), 'error') end
    cprTarget = target
    local anim = animFor({ name = 'cpr' })
    RequestAnimDict(anim.dict)
    CreateThread(function()
        local started = GetGameTimer()
        while cprTarget == target do
            if HasAnimDictLoaded(anim.dict) and not IsEntityPlayingAnim(PlayerPedId(), anim.dict, anim.anim, 3) then
                TaskPlayAnim(PlayerPedId(), anim.dict, anim.anim, 8.0, -8.0, -1, anim.flags, 0, false, false, false)
            end
            if GetGameTimer() - started >= Treatments.Defaults.CprTickSeconds * 1000 then
                started = GetGameTimer()
                QBCore.Functions.TriggerCallback('pf-ambulancejob:server:cprTick', function(res)
                    res = type(res) == 'table' and res or {}
                    if not res.ok then
                        if res.error ~= 'rate_limited' then
                            notify(tostring(res.message or 'CPR stopped'), 'error')
                            stopCpr()
                        end
                    elseif res.result and res.result.changed and res.result.changed.rosc then
                        notify(tostring(res.result.message), 'success')
                        stopCpr()
                    end
                end, target)
            end
            -- moving (or pressing X) stops compressions
            if IsControlJustPressed(0, 73) or IsControlPressed(0, 32) or IsControlPressed(0, 33) then stopCpr() end
            Wait(0)
        end
    end)
end

-- ── menus (pfm-menu, the shared PF look) ───────────────────────────────────────────────────────

local REGION_ORDER = { 'head', 'face', 'neck', 'chest_l', 'chest_r', 'abdomen', 'back_upper', 'back_lower', 'pelvis',
    'shoulder_l', 'shoulder_r', 'upper_arm_l', 'upper_arm_r', 'forearm_l', 'forearm_r', 'hand_l', 'hand_r',
    'thigh_l', 'thigh_r', 'knee_l', 'knee_r', 'lower_leg_l', 'lower_leg_r', 'foot_l', 'foot_r' }

local function needsRegion(action)
    return action.target == 'region' or (action.regions ~= nil)
end

local function regionMenu(target, actionName)
    local action = Treatments.Actions[actionName]
    local menu = { { header = action.label .. ': where?', isMenuHeader = true } }
    for _, r in ipairs(REGION_ORDER) do
        local def = PFMed.Anatomy.Regions[r]
        if def and (not action.regions or action.regions[r]) then
            menu[#menu + 1] = { header = def.label, params = { event = 'pf-ambulancejob:client:treatPick',
                args = { target = target, action = actionName, region = r } } }
        end
    end
    if action.target ~= 'region' then
        menu[#menu + 1] = { header = 'Worst wound', params = { event = 'pf-ambulancejob:client:treatPick',
            args = { target = target, action = actionName, region = false } } }
    end
    menu[#menu + 1] = { header = Lang:t('menu.close'), params = { event = 'qb-menu:client:closeMenu' } }
    exports['pfm-menu']:openMenu(menu)
end

function OpenTreatmentMenu(target)
    if not target then return notify(Lang:t('error.no_player'), 'error') end
    QBCore.Functions.TriggerCallback('pf-ambulancejob:server:treatOptions', function(opts)
        if type(opts) ~= 'table' or not opts.ok then return notify('Treatment is not available', 'error') end
        local tier = tonumber(opts.tier) or 0
        local menu = { { header = 'Treatment', txt = 'Scope: ' .. tostring(Treatments.TierLabels[tier] or tier), isMenuHeader = true } }
        for _, name in ipairs(Treatments.ListFor(tier)) do
            local a = Treatments.Actions[name]
            local needs = {}
            for item in pairs(a.items or {}) do needs[#needs + 1] = item end
            for _, eq in ipairs(a.equipment or {}) do needs[#needs + 1] = eq end
            menu[#menu + 1] = { header = a.label, txt = #needs > 0 and table.concat(needs, ', ') or '',
                params = { event = 'pf-ambulancejob:client:treatPick', args = { target = target, action = name } } }
        end
        menu[#menu + 1] = { header = Lang:t('menu.close'), params = { event = 'qb-menu:client:closeMenu' } }
        exports['pfm-menu']:openMenu(menu)
    end, target)
end

-- local event from the menu (AddEventHandler: neither the server nor other clients can send it)
AddEventHandler('pf-ambulancejob:client:treatPick', function(args)
    if type(args) ~= 'table' then return end
    local action = Treatments.Actions[args.action]
    local target = tonumber(args.target)
    if not action or not target then return end
    if action.name == 'cpr' then return StartCpr(target) end
    if args.region == nil and needsRegion(action) then return regionMenu(target, action.name) end
    perform(target, action.name, { region = args.region or nil })
end)

-- ── self care and treatment results ────────────────────────────────────────────────────────────

-- The server checked the item can be used now; the item is used up when the server applies it.
RegisterNetEvent('pf-ambulancejob:client:SelfTreat', function(actionName, itemName)
    if type(actionName) ~= 'string' or not Treatments.Actions[actionName] then return end
    perform(GetPlayerServerId(PlayerId()), actionName, { item = type(itemName) == 'string' and itemName or nil })
end)

-- Sent by the server to the patient after a treatment it applied: a little of the ped's health back.
RegisterNetEvent('pf-ambulancejob:client:applyTreatmentEffects', function(actionName, healing)
    healing = tonumber(healing) or 0
    local ped = PlayerPedId()
    if healing > 0 and healing <= 25 and not IsEntityDead(ped) then
        SetEntityHealth(ped, math.min(GetEntityHealth(ped) + math.floor(healing), GetEntityMaxHealth(ped)))
    end
end)

RegisterCommand('treat', function(_, args)
    OpenTreatmentMenu(resolveTarget(args[1]))
end, false)

RegisterCommand('cpr', function(_, args)
    StartCpr(resolveTarget(args[1]))
end, false)

exports('OpenTreatmentMenu', function(target) OpenTreatmentMenu(tonumber(target)) end)
exports('StartCpr', function(target) StartCpr(tonumber(target)) end)
