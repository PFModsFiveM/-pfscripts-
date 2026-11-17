-- Morgue on the client (batch 20B): a target zone at each morgue (and /morgue) opens the register
-- in pfm-menu (the shared look; pfm-menu escapes every string). Every decision is the server's
-- (server/hospital/morgue.lua): who may see, examine, link or release, the autopsy clock, the cause
-- and the suggested manner. The progress bar only shows the server's exam time.

PFMorgue = PFMorgue or {}
local QBCore = exports['pfm-core']:GetCoreObject()

local MANNERS = {
    { value = '', text = 'Keep the evidence-based suggestion' },
    { value = 'natural', text = 'Natural' }, { value = 'accident', text = 'Accident' }, { value = 'homicide', text = 'Homicide' },
    { value = 'suicide', text = 'Suicide' }, { value = 'undetermined', text = 'Undetermined' },
}
local STATE_LABEL = { intake = 'Awaiting examination', examined = 'Examined', released = 'Released' }

local function notify(text, kind) QBCore.Functions.Notify(tostring(text), kind or 'error') end

local function async(fn, ...)
    local args = table.pack(...)
    return function() CreateThread(function() fn(table.unpack(args, 1, args.n)) end) end
end

local function await(name, ...)
    local p = promise.new()
    PFAmbulance.Framework.TriggerCallback(name, function(res) p:resolve(res) end, ...)
    return Citizen.Await(p)
end

-- times arrive as text from the server (client scripts have no os.date)
local function todText(r) return tostring(r.todText or 'unknown') end

local function cap(s) s = tostring(s or '') return s:sub(1, 1):upper() .. s:sub(2) end

-- ── record view ──────────────────────────────────────────────────────────────────────────────

local function findingsMenu(menu, f)
    if type(f) ~= 'table' then return end
    if f.declared then
        menu[#menu + 1] = { header = 'Time of death', txt = 'Declared at intake: the medical records show no death before it.', isMenuHeader = true }
    end
    menu[#menu + 1] = { header = 'Injuries present at death', isMenuHeader = true }
    if #(f.injuries or {}) == 0 then menu[#menu + 1] = { header = 'None recorded', isMenuHeader = true } end
    for _, inj in ipairs(f.injuries or {}) do
        local txt = ('Severity %s | %s | %s'):format(tostring(inj.severity), tostring(inj.mechanism or 'unknown'), tostring(inj.stage or ''))
        if inj.lethal then txt = txt .. ' | fatal' end
        if inj.attacker == 'other' then txt = txt .. ' | inflicted by another person' elseif inj.attacker == 'self' then txt = txt .. ' | self-inflicted' end
        menu[#menu + 1] = { header = tostring(inj.text or inj.type), txt = txt, isMenuHeader = true }
    end
    if #(f.toxins or {}) > 0 then
        menu[#menu + 1] = { header = 'Toxicology', isMenuHeader = true }
        for _, t in ipairs(f.toxins) do
            local txt = tostring(t.level) .. ' ' .. tostring(t.unit or '')
            if t.intensity then txt = txt .. (' (%d%% of the severe level)'):format(math.floor(t.intensity * 100 + 0.5)) end
            menu[#menu + 1] = { header = cap(tostring(t.name):gsub('_', ' ')), txt = txt, isMenuHeader = true }
        end
    end
    if #(f.interventions or {}) > 0 then
        menu[#menu + 1] = { header = 'Care before death', isMenuHeader = true }
        for _, c in ipairs(f.interventions) do
            menu[#menu + 1] = { header = tostring(c.action), txt = ('%s | %s | %s'):format(tostring(c.location or ''), tostring(c.result or ''), tostring(c.atText or '')), isMenuHeader = true }
        end
    end
end

function PFMorgue.View(id)
    local res = await('pf-ambulancejob:server:morgueGet', id)
    if not res or not res.ok then return notify((res and res.message) or 'Record unavailable') end
    local r = res.record
    local menu = {
        { header = ('Death record #%d: %s'):format(r.id, tostring(r.name)), txt = STATE_LABEL[r.state] or tostring(r.state), isMenuHeader = true },
        { header = 'Cause of death', txt = tostring(r.cause), isMenuHeader = true },
        { header = 'Manner of death', txt = cap(r.manner), isMenuHeader = true },
        { header = 'Time of death', txt = todText(r), isMenuHeader = true },
    }
    if r.caseRef then menu[#menu + 1] = { header = 'Police case', txt = tostring(r.caseRef), isMenuHeader = true } end
    local f = type(r.findings) == 'table' and r.findings or {}
    if f.autopsy then
        if f.autopsy.derivedManner and f.autopsy.derivedManner ~= r.manner then
            menu[#menu + 1] = { header = 'Evidence suggested', txt = cap(f.autopsy.derivedManner) .. ' (the examiner ruled otherwise)', isMenuHeader = true }
        end
        if f.autopsy.note then menu[#menu + 1] = { header = 'Examiner note', txt = tostring(f.autopsy.note), isMenuHeader = true } end
        findingsMenu(menu, f.autopsy)
    end
    if r.state == 'intake' and res.tier >= res.examTier then
        menu[#menu + 1] = { header = 'Perform autopsy', action = async(PFMorgue.Autopsy, r.id) }
    end
    if res.tier >= res.examTier then
        menu[#menu + 1] = { header = r.caseRef and 'Re-send to the police case' or 'Link to a police case', action = async(PFMorgue.Link, r.id, r.caseRef) }
    end
    if r.state == 'examined' and res.tier >= res.releaseTier then
        menu[#menu + 1] = { header = 'Release body', action = async(PFMorgue.Release, r.id) }
    end
    menu[#menu + 1] = { header = 'Back', action = async(PFMorgue.Open) }
    exports['pfm-menu']:openMenu(menu)
end

-- ── actions ──────────────────────────────────────────────────────────────────────────────────

function PFMorgue.Autopsy(id)
    local start = await('pf-ambulancejob:server:morgueAutopsyStart', id)
    if not start or not start.ok then return notify((start and start.message) or 'Cannot start the autopsy') end
    local done = promise.new()
    QBCore.Functions.Progressbar('pf_morgue_autopsy', 'Performing autopsy...', math.max(1, tonumber(start.seconds) or 1) * 1000 + 500, false, true,
        { disableMovement = true, disableCarMovement = true, disableMouse = false, disableCombat = true },
        { animDict = 'anim@gangops@morgue@table@', anim = 'body_search', flags = 49 }, {}, {},
        function() done:resolve(true) end, function() done:resolve(false) end)
    local finished = Citizen.Await(done)
    StopAnimTask(PlayerPedId(), 'anim@gangops@morgue@table@', 'body_search', 1.0)
    if not finished then return notify('Autopsy interrupted') end
    local p = start.preview or {}
    local options = {}
    for i, m in ipairs(MANNERS) do
        options[i] = { value = m.value, text = i == 1 and (m.text .. ': ' .. cap(p.derivedManner)) or m.text }
    end
    local input = exports['pfm-input']:ShowInput({
        header = 'Autopsy: ' .. tostring(p.cause or ''), submitText = 'Sign the report',
        inputs = {
            { text = 'Manner of death', name = 'manner', type = 'select', options = options },
            { text = 'Note (optional)', name = 'note', type = 'text' },
        },
    })
    if not input then return PFMorgue.View(id) end
    local res = await('pf-ambulancejob:server:morgueAutopsy', id, input.manner ~= '' and input.manner or nil, input.note ~= '' and input.note or nil)
    if not res or not res.ok then notify((res and res.message) or 'Not saved') else notify('Autopsy report signed', 'success') end
    PFMorgue.View(id)
end

function PFMorgue.Link(id, current)
    local input = exports['pfm-input']:ShowInput({
        header = 'Police case', submitText = 'Link',
        inputs = { { text = 'Case number or incident id', name = 'ref', type = 'text', isRequired = true, default = current } },
    })
    if not input or not input.ref or input.ref == '' then return PFMorgue.View(id) end
    local res = await('pf-ambulancejob:server:morgueLinkCase', id, input.ref)
    if not res or not res.ok then notify((res and res.message) or 'Not linked')
    elseif res.pending then notify('Saved; the MDT is unreachable and the link will be sent again', 'primary')
    else notify('Linked to ' .. tostring(res.caseRef), 'success') end
    PFMorgue.View(id)
end

function PFMorgue.Release(id)
    local input = exports['pfm-input']:ShowInput({
        header = 'Release body', submitText = 'Release',
        inputs = { { text = 'Released to (funeral home, family...)', name = 'note', type = 'text' } },
    })
    if not input then return PFMorgue.View(id) end
    local res = await('pf-ambulancejob:server:morgueRelease', id, input.note ~= '' and input.note or nil)
    if not res or not res.ok then notify((res and res.message) or 'Not released') else notify('Body released', 'success') end
    PFMorgue.Open()
end

function PFMorgue.Open()
    local res = await('pf-ambulancejob:server:morgueList')
    if not res or not res.ok then return notify((res and res.message) or 'Morgue unavailable') end
    local menu = { { header = 'Morgue register', txt = #res.list .. ' in the morgue', isMenuHeader = true } }
    if #res.list == 0 then menu[#menu + 1] = { header = 'No bodies', isMenuHeader = true } end
    for _, r in ipairs(res.list) do
        menu[#menu + 1] = { header = ('#%d %s'):format(r.id, tostring(r.name)), txt = (STATE_LABEL[r.state] or tostring(r.state)) .. ' | ' .. todText(r),
            action = async(PFMorgue.View, r.id) }
    end
    exports['pfm-menu']:openMenu(menu)
end

RegisterNetEvent('pf-ambulancejob:client:MorgueOpen', function() CreateThread(PFMorgue.Open) end)
RegisterCommand('morgue', function() CreateThread(PFMorgue.Open) end, false)

-- ── target zones (the server checks the position again) ─────────────────────────────────────

local function zones()
    local m = Config.Hospital and Config.Hospital.Morgue
    if type(m) == 'table' and type(m.Zones) == 'table' then return m.Zones end
    return { { id = 'pillbox_morgue', coords = vector3(275.45, -1361.11, 24.54) } }
end

if Config.UseTarget then
    CreateThread(function()
        for _, z in ipairs(zones()) do
            local c = z.coords
            if c then
                exports['pfm-target']:AddBoxZone('pf_morgue_' .. tostring(z.id), vector3(c.x, c.y, c.z), 2.5, 2.5, {
                    name = 'pf_morgue_' .. tostring(z.id), heading = 0, debugPoly = false, minZ = c.z - 1.5, maxZ = c.z + 1.5,
                }, {
                    options = { { type = 'client', icon = 'fas fa-file-medical', event = 'pf-ambulancejob:client:MorgueOpen', label = 'Morgue register', job = 'ambulance' } },
                    distance = 2.0,
                })
            end
        end
    end)
    AddEventHandler('onResourceStop', function(resource)
        if resource ~= GetCurrentResourceName() then return end
        for _, z in ipairs(zones()) do pcall(function() exports['pfm-target']:RemoveZone('pf_morgue_' .. tostring(z.id)) end) end
    end)
end
