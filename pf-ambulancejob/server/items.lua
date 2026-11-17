-- Usable medical items (moved out of server/main.lua, batch 17B).
-- Self-care items (bandage, IFAK, painkillers, and the field items a person can use on themselves)
-- never do anything on the client's word: the server first checks the action could start (nothing
-- is used up), the client plays the progress bar, then asks the treatment engine, which uses the
-- item up on the server before any effect (server/medical/treatment.lua). A first-aid kit starts the
-- server-timed civilian first aid on the closest down person (hospital:client:UseFirstAid).

local Core = PFAmbulance.GetCore()

local function notify(src, text)
    TriggerClientEvent('QBCore:Notify', src, text, 'error')
end

local function holds(src, name)
    local Player = exports['pfm-core']:GetPlayer(src)
    if not Player then return false end
    local f = Player.Functions and Player.Functions.GetItemByName or Player.GetItemByName
    if f then return f(name) ~= nil end
    local ok, has = pcall(function() return Core.Functions.HasItem(src, name, 1) end)
    return ok and has == true
end

PFMedItems = PFMedItems or {}

--- A self-care item was used: if the action can start, the client runs the progress bar and then
--- calls the treat callback on itself with this item as the hint. Returns the precheck result.
function PFMedItems.UseSelf(src, itemName)
    local def = PFMed.Treatments.SelfUse[itemName]
    if not def or not holds(src, itemName) then return { ok = false, error = 'missing_item' } end
    local action = PFMed.Treatments.Actions[def.action]
    local res = PFMed.Treat.Precheck(src, def.action, src, { item = itemName })
    if not res.ok then
        notify(src, res.message or 'You cannot use that now')
        return res
    end
    TriggerClientEvent('pf-ambulancejob:client:SelfTreat', src, def.action, itemName, action.duration or 4000)
    return res
end

for itemName in pairs(PFMed.Treatments.SelfUse) do
    Core.Functions.CreateUseableItem(itemName, function(source)
        local src = tonumber(source)
        if src and src > 0 then PFMedItems.UseSelf(src, itemName) end
    end)
end

-- Civilian first aid on someone else: the server starts it (distance, state, timing) when the
-- client names the closest person (hospital:server:UseFirstAid -> PFMed.Down.StartFirstAid).
Core.Functions.CreateUseableItem('firstaid', function(source, item)
    local src = tonumber(source)
    if not src or src <= 0 then return end
    if holds(src, (type(item) == 'table' and item.name) or 'firstaid') then
        TriggerClientEvent('hospital:client:UseFirstAid', src)
    end
end)

-- Legacy item events (architecture 9): the old clients removed their own item after a local heal.
-- Items are used up by the treatment engine now, so these do nothing.
RegisterNetEvent('hospital:server:removeBandage', function() end)
RegisterNetEvent('hospital:server:removeIfaks', function() end)
RegisterNetEvent('hospital:server:removePainkillers', function() end)
