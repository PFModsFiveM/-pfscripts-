-- pf-justice client helpers shared by the client modules (community service today).
--
-- The client only shows things and sends intents: every check (position, timing, items, roles) is done
-- on the server. Prompts go through pfm-prompts (the shared in-world look); when it is not running a
-- small fallback shows the game's help text near a prompt point, so the flow still works.

PFJusticeClient = PFJusticeClient or {}
local C = PFJusticeClient

C.prompts = C.prompts or {}   -- [id] = def (kept for the fallback and for re-adding after a pfm-prompts restart)

function C.Notify(text, kind)
    TriggerEvent('QBCore:Notify', text, kind or 'primary')
end

local function promptsReady() return GetResourceState('pfm-prompts') == 'started' end

--- Adds (or replaces) an in-world prompt. def = { coords, label, options?, distance?, onPress? } as in
--- pfm-prompts' README.
function C.AddPrompt(id, def)
    C.prompts[id] = def
    if promptsReady() then
        pcall(function()
            if exports['pfm-prompts']:Exists(id) then exports['pfm-prompts']:Remove(id) end
            exports['pfm-prompts']:Add(id, def)
        end)
    end
end

function C.RemovePrompt(id)
    if not C.prompts[id] then return end
    C.prompts[id] = nil
    if promptsReady() then pcall(function() exports['pfm-prompts']:Remove(id) end) end
end

function C.RemovePromptsWithPrefix(prefix)
    for id in pairs(C.prompts) do
        if id:sub(1, #prefix) == prefix then C.RemovePrompt(id) end
    end
end

AddEventHandler('onClientResourceStart', function(res)
    if res ~= 'pfm-prompts' then return end
    for id, def in pairs(C.prompts) do pcall(function() exports['pfm-prompts']:Add(id, def) end) end
end)

-- Fallback without pfm-prompts: the game's help text with the first option when in reach. Checks
-- twice a second; draws every frame only while standing at a prompt.
local function firstOption(def)
    if type(def.options) == 'table' and def.options[1] then return def.options[1] end
    return def
end

CreateThread(function()
    while true do
        local wait = 500
        if not promptsReady() and next(C.prompts) ~= nil then
            local pos = GetEntityCoords(PlayerPedId())
            for _, def in pairs(C.prompts) do
                local c = def.coords
                if c and #(pos - vector3(c.x, c.y, c.z)) <= (def.distance or 2.0) then
                    local opt = firstOption(def)
                    wait = 0
                    BeginTextCommandDisplayHelp('STRING')
                    AddTextComponentSubstringPlayerName('~INPUT_PICKUP~ ' .. tostring(opt.label or def.label or ''))
                    EndTextCommandDisplayHelp(0, false, true, -1)
                    if IsControlJustPressed(0, 38) and opt.onPress then opt.onPress() end
                    break
                end
            end
        end
        Wait(wait)
    end
end)
