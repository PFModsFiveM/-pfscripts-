-- A deleted character's cars are gone (pfm-core deletes player_vehicles), so their service records
-- go too. pfm-core raises the server-only event 'pfm-core:server:characterDeleted' after the delete,
-- with the plates the character owned (deleted.plates); a call from a player is ignored.
-- vehicle_diagnostics rows are removed by those plates only. Not by the row's citizenid: that is
-- the owner at the row's last write and is not updated when a car is sold or transferred, so a
-- citizenid match can be a car that now belongs to another player. Running it twice changes
-- nothing the second time.

PFMechCharacters = PFMechCharacters or {}
local C = PFMechCharacters

local MAX_PLATES = 200

local function validCitizenId(citizenid)
    return type(citizenid) == 'string' and citizenid ~= '' and #citizenid <= 50 and citizenid:match('^[%w]+$') ~= nil
end

-- the plate as player_vehicles has it, and as garage_sync writes it (no spaces, upper case)
local function plateForms(plate)
    local trimmed = (plate:gsub('^%s+', ''):gsub('%s+$', ''))
    local clean = (plate:gsub('%s+', ''):upper())
    if trimmed == '' then return {} end
    if clean == trimmed then return { trimmed } end
    return { trimmed, clean }
end

--- Returns the number of diagnostics rows removed.
function C.Remove(citizenid, deleted)
    local removed = 0
    local plates = type(deleted) == 'table' and type(deleted.plates) == 'table' and deleted.plates or {}
    for i, plate in ipairs(plates) do
        if i > MAX_PLATES then break end
        if type(plate) == 'string' and #plate <= 16 then
            for _, form in ipairs(plateForms(plate)) do
                removed = removed + (tonumber(MySQL.update.await('DELETE FROM vehicle_diagnostics WHERE plate = ?', { form })) or 0)
            end
        end
    end
    return removed
end

AddEventHandler('pfm-core:server:characterDeleted', function(citizenid, deleted)
    local src = tonumber(source)
    if src and src > 0 then return end
    if not validCitizenId(citizenid) then return end
    local ok, err = pcall(C.Remove, citizenid, deleted)
    if not ok then print(('^1[pf-mechanicjob]^7 cleanup of deleted character %s failed: %s'):format(citizenid, tostring(err))) end
end)
