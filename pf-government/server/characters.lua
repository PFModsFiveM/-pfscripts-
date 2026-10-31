-- A deleted character in the government records. pfm-core raises the server-only event
-- 'pfm-core:server:characterDeleted' after it removed the character; a call from a player is ignored.
--
--   * pf_gov_staff: the character's staff role row is removed (no government access left behind);
--   * pf_gov_businesses: a business the character owned becomes 'unowned' (as TransferBusinessOwnership
--     does with no new owner), so it can be bought or transferred again; its account and history stay;
--   * pf_gov_utilities: the property (and business) utility records lose their owner.
-- Each step runs on its own, so one failing table does not stop the others, and running it twice
-- changes nothing the second time.

PFGovCharacters = PFGovCharacters or {}
local C = PFGovCharacters

C.Steps = {
    { name = 'staff', sql = 'DELETE FROM pf_gov_staff WHERE citizenid = ?' },
    { name = 'businesses', sql = "UPDATE pf_gov_businesses SET owner_id = 'unowned', owner_name = 'Unassigned', updated_at = NOW() WHERE owner_id = ?" },
    { name = 'utilities', sql = 'UPDATE pf_gov_utilities SET owner_id = NULL, owner_name = NULL WHERE owner_id = ?' },
}

local function validCitizenId(citizenid)
    return type(citizenid) == 'string' and citizenid ~= '' and #citizenid <= 50 and citizenid:match('^[%w]+$') ~= nil
end

--- Returns { [step name] = rows changed or false when that step failed }.
function C.Remove(citizenid)
    local out = {}
    for _, step in ipairs(C.Steps) do
        local ok, n = pcall(MySQL.update.await, step.sql, { citizenid })
        if ok then
            out[step.name] = tonumber(n) or 0
        else
            out[step.name] = false
            print(('^1[pf-government]^7 cleanup (%s) of deleted character %s failed: %s'):format(step.name, citizenid, tostring(n)))
        end
    end
    return out
end

AddEventHandler('pfm-core:server:characterDeleted', function(citizenid)
    local src = tonumber(source)
    if src and src > 0 then return end
    if not validCitizenId(citizenid) then return end
    C.Remove(citizenid)
end)
