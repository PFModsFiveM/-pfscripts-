-- Exam flow on a patient (architecture 4.2; the full EMDT exam page comes in batch 21): a target
-- option and /checkinjuries open a menu of the exams this provider may do on this patient now (the
-- server builds the list), the chosen exam runs on the server while a progress bar plays, and the
-- findings, the chart and diagnoses are shown in pfm-menu (the shared look). Nothing here decides
-- anything: tier, distance, instruments, timing and results all come from the server.

PFExam = PFExam or {}
local running = false

local function notify(text, kind) QBCore.Functions.Notify(text, kind or 'error') end

-- menu and target actions arrive through another resource; run them on their own thread so the
-- callback awaits below can wait
local function async(fn, ...)
    local args = table.pack(...)
    return function() CreateThread(function() fn(table.unpack(args, 1, args.n)) end) end
end

local function await(name, ...)
    local p = promise.new()
    PFAmbulance.Framework.TriggerCallback(name, function(res) p:resolve(res) end, ...)
    return Citizen.Await(p)
end

local function regionLabel(id)
    local r = id and PFMed.Anatomy.Regions[id]
    return r and r.label or nil
end
local function structureLabel(id)
    local s = id and PFMed.Anatomy.Structures[id]
    return s and s.label or nil
end
local function typeLabel(id)
    local t = id and PFMed.Injuries.Types[id]
    return t and t.label or tostring(id)
end
local CERTAINTY = { observed = 'Observed', suspected = 'Suspected', confirmed = 'Confirmed' }

local function findingLine(f)
    local head = PFMed.Findings.Label(f.sign)
    if f.value and f.value ~= '' then head = head .. ': ' .. tostring(f.value) end
    local where = {}
    if f.structure then where[#where + 1] = structureLabel(f.structure) end
    if f.region and not f.structure then where[#where + 1] = regionLabel(f.region) end
    where[#where + 1] = CERTAINTY[f.certainty] or f.certainty
    return head, table.concat(where, ' | ')
end

-- ── results ────────────────────────────────────────────────────────────────────────────────────

local function showResult(target, res)
    local def = PFMed.Findings.Modalities[res.modality] or {}
    local menu = { { header = def.label or res.modality, txt = res.reused and 'Result from the last minute' or 'Exam result', isMenuHeader = true } }
    if #(res.findings or {}) == 0 then
        menu[#menu + 1] = { header = 'Nothing found', txt = 'An exam can miss things; it never shows what is not there.', isMenuHeader = true }
    end
    for _, f in ipairs(res.findings or {}) do
        local head, txt = findingLine(f)
        menu[#menu + 1] = { header = head, txt = txt, isMenuHeader = true }
    end
    menu[#menu + 1] = { header = 'Back to exams', action = async(PFExam.Open, target) }
    exports['pfm-menu']:openMenu(menu)
end

--- Runs one exam: the server waits the exam's time; the bar only shows it.
function PFExam.Run(target, modality, seconds)
    if running then return notify('Already examining') end
    running = true
    local result
    PFAmbulance.Framework.TriggerCallback('pf-ambulancejob:server:exam', function(res) result = res or { ok = false } end, target, modality)
    local anim = Config.CheckInjuries.Animation
    local finished = promise.new()
    QBCore.Functions.Progressbar('ems_exam', (PFMed.Findings.Modalities[modality] or {}).label or 'Examining...', math.max(1, tonumber(seconds) or 1) * 1000, false, true,
        { disableMovement = true, disableCarMovement = true, disableMouse = false, disableCombat = true },
        { animDict = anim.dict, anim = anim.anim, flags = 49 }, {}, {},
        function() finished:resolve(true) end, function() finished:resolve(false) end)
    Citizen.Await(finished)
    StopAnimTask(PlayerPedId(), anim.dict, anim.anim, 1.0)
    local deadline = GetGameTimer() + 10000
    while not result and GetGameTimer() < deadline do Wait(100) end
    running = false
    if not result then return notify('No answer from the server') end
    if not result.ok then return notify(result.message or 'Exam failed') end
    showResult(target, result)
end

-- ── chart and diagnoses ────────────────────────────────────────────────────────────────────────

function PFExam.Chart(target)
    local res = await('pf-ambulancejob:server:getChart', target)
    if not res or not res.ok then return notify((res and res.message) or 'Chart unavailable') end
    local menu = { { header = 'Chart' .. (res.patient and res.patient.name and (': ' .. res.patient.name) or ''), txt = 'Last 24 hours', isMenuHeader = true } }
    menu[#menu + 1] = { header = 'Diagnoses', isMenuHeader = true }
    if #res.diagnoses == 0 then menu[#menu + 1] = { header = 'None recorded', isMenuHeader = true } end
    for _, d in ipairs(res.diagnoses) do
        local txt = (d.status or '') .. ' (' .. (d.source or '') .. ')' .. (d.structure and (' | ' .. (structureLabel(d.structure) or d.structure)) or '')
        if d.status == 'suspected' and res.tier >= 2 then
            menu[#menu + 1] = { header = typeLabel(d.injuryType), txt = txt .. ' | select to rule out', action = async(function()
                local r = await('pf-ambulancejob:server:setDiagnosis', target, { injuryType = d.injuryType, structure = d.structure, injuryId = d.injuryId, status = 'ruled_out' })
                if not r or not r.ok then notify((r and r.message) or 'Not saved') else notify('Ruled out', 'success') end
                PFExam.Chart(target)
            end) }
        else
            menu[#menu + 1] = { header = typeLabel(d.injuryType), txt = txt, isMenuHeader = true }
        end
    end
    menu[#menu + 1] = { header = 'Findings', isMenuHeader = true }
    if #res.findings == 0 then menu[#menu + 1] = { header = 'None recorded', isMenuHeader = true } end
    for i, f in ipairs(res.findings) do
        if i > 30 then break end
        local head, txt = findingLine(f)
        menu[#menu + 1] = { header = head, txt = txt, isMenuHeader = true }
    end
    menu[#menu + 1] = { header = 'Treatments', isMenuHeader = true }
    if #res.treatments == 0 then menu[#menu + 1] = { header = 'None recorded', isMenuHeader = true } end
    for i, t in ipairs(res.treatments) do
        if i > 20 then break end
        menu[#menu + 1] = { header = tostring(t.action), txt = tostring(t.location or '') .. ' | ' .. tostring(t.result or ''), isMenuHeader = true }
    end
    if res.tier >= 2 then
        menu[#menu + 1] = { header = 'Add suspected diagnosis', action = async(function() PFExam.Suspect(target) end) }
    end
    menu[#menu + 1] = { header = 'Back to exams', action = async(PFExam.Open, target) }
    exports['pfm-menu']:openMenu(menu)
end

function PFExam.Suspect(target)
    local types, structures = {}, { { value = '', text = 'Not specified' } }
    for id, t in pairs(PFMed.Injuries.Types) do types[#types + 1] = { value = id, text = t.label } end
    table.sort(types, function(a, b) return a.text < b.text end)
    for id, s in pairs(PFMed.Anatomy.Structures) do structures[#structures + 1] = { value = id, text = s.label } end
    table.sort(structures, function(a, b) return a.value == '' or (b.value ~= '' and a.text < b.text) end)
    local input = exports['pfm-input']:ShowInput({
        header = 'Suspected diagnosis', submitText = 'Save',
        inputs = {
            { text = 'Injury', name = 'injuryType', type = 'select', options = types, isRequired = true },
            { text = 'Structure', name = 'structure', type = 'select', options = structures },
            { text = 'Note', name = 'note', type = 'text' },
        },
    })
    if not input or not input.injuryType then return PFExam.Chart(target) end
    local r = await('pf-ambulancejob:server:setDiagnosis', target, {
        injuryType = input.injuryType, structure = input.structure ~= '' and input.structure or nil,
        status = 'suspected', note = input.note ~= '' and input.note or nil,
    })
    if not r or not r.ok then notify((r and r.message) or 'Not saved') else notify('Diagnosis saved', 'success') end
    PFExam.Chart(target)
end

-- ── vitals monitor and the MDT patient page ───────────────────────────────────────────────────

local monitorOn = nil   -- server id of the patient our monitor is on (the server decides; this is only for the menu)

local function mdtStarted() return GetResourceState('pf-emsmdt') == 'started' end

--- Opens pf-emsmdt's patient care page on this patient (exam, treatment, chart, live monitor).
function PFExam.OpenMdt(target)
    if not mdtStarted() then return false end
    local ok, res = pcall(function() return exports['pf-emsmdt']:OpenPatientCare(target) end)
    return ok and res ~= false
end

function PFExam.AttachMonitor(target)
    local res = await('pf-ambulancejob:server:monitorAttach', target)
    if not res or not res.ok then return notify((res and res.message) or 'The monitor could not be attached') end
    monitorOn = target
    notify('Monitor attached', 'success')
    PFExam.OpenMdt(target)
end

function PFExam.DetachMonitor()
    local res = await('pf-ambulancejob:server:monitorDetach')
    monitorOn = nil
    if res and res.ok then notify('Monitor removed', 'success') end
end

-- the server's readings: only to the medic whose monitor is on that patient (the MDT page shows them)
RegisterNetEvent('pf-ambulancejob:client:Monitor', function(patientSrc)
    monitorOn = tonumber(patientSrc) or monitorOn
end)

-- ── the exam menu ──────────────────────────────────────────────────────────────────────────────

function PFExam.Open(target)
    target = tonumber(target)
    if not target or GetPlayerFromServerId(target) == -1 then return notify('Patient not found') end
    if target == GetPlayerServerId(PlayerId()) then return notify('You cannot examine yourself') end
    local res = await('pf-ambulancejob:server:examOptions', target)
    if not res or not res.ok then return notify((res and res.message) or 'Cannot examine') end
    local menu = { { header = 'Examine patient', txt = 'Your level: ' .. tostring(res.tierLabel), isMenuHeader = true } }
    for _, m in ipairs(res.modalities) do
        if m.available then
            menu[#menu + 1] = { header = m.label, txt = ('%d s'):format(m.seconds), action = async(function() PFExam.Run(target, m.id, m.seconds) end) }
        elseif m.tier <= res.tier then
            -- allowed for this provider but not possible here (instrument, place): say why
            menu[#menu + 1] = { header = m.label, txt = tostring(m.reason or 'Not possible here'), disabled = true }
        end
    end
    if res.tier >= 1 then menu[#menu + 1] = { header = 'Chart', txt = 'Findings, diagnoses and treatments', action = async(function() PFExam.Chart(target) end) } end
    for _, m in ipairs(res.modalities) do
        if m.id == 'ecg' and m.available then
            if monitorOn == target then
                menu[#menu + 1] = { header = 'Remove vitals monitor', action = async(PFExam.DetachMonitor) }
            else
                menu[#menu + 1] = { header = 'Attach vitals monitor', txt = 'Live readings every 5 s', action = async(PFExam.AttachMonitor, target) }
            end
        end
    end
    if res.tier >= 1 and mdtStarted() then
        menu[#menu + 1] = { header = 'Open patient page (MDT)', txt = 'Exam, treatment, chart and monitor', action = async(PFExam.OpenMdt, target) }
    end
    exports['pfm-menu']:openMenu(menu)
end

-- ── target option on players ───────────────────────────────────────────────────────────────────

local TARGET_LABEL = 'Examine'

local function serverIdOf(entity)
    local idx = NetworkGetPlayerIndexFromPed(entity)
    if not idx or idx == -1 then return nil end
    return GetPlayerServerId(idx)
end

if Config.UseTarget then
    CreateThread(function()
        exports['pfm-target']:AddGlobalPlayer({
            options = {
                {
                    icon = 'fas fa-stethoscope', label = TARGET_LABEL,
                    action = function(entity) local id = serverIdOf(entity) if id then CreateThread(function() PFExam.Open(id) end) end end,
                    -- medics on any patient; anyone else only on someone who is down (look, ask)
                    canInteract = function(entity)
                        local id = serverIdOf(entity)
                        if not id then return false end
                        if IsPlayerAEMSMember() then return true end
                        local down = Player(id).state['pf:down']
                        return down ~= nil and down ~= false
                    end,
                },
            },
            distance = 2.5,
        })
    end)
    AddEventHandler('onResourceStop', function(resource)
        if resource ~= GetCurrentResourceName() then return end
        pcall(function() exports['pfm-target']:RemoveGlobalPlayer(TARGET_LABEL) end)
    end)
end
