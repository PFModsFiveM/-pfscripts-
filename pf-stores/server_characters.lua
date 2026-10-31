-- A deleted character's stores go back on the market. pfm-core raises the server-only event
-- 'pfm-core:server:characterDeleted' after it removed the character; a call from a player is ignored.
--
-- Only the owner is cleared (as when the government makes a store unowned): the store's money stays
-- in its own bank account (store:<id> / its society account) and its stock and prices stay with it.
-- Running it twice changes nothing the second time.

PFStoresCharacters = PFStoresCharacters or {}
local C = PFStoresCharacters

local function validCitizenId(citizenid)
    return type(citizenid) == 'string' and citizenid ~= '' and #citizenid <= 50 and citizenid:match('^[%w]+$') ~= nil
end

--- Clears the owner of every store the character owned. Returns the store ids that were released.
function C.Release(citizenid)
    local released = {}
    local rows = MySQL.query.await('SELECT store_id FROM pf_stores WHERE owner_citizenid = ?', { citizenid }) or {}
    for _, row in ipairs(rows) do
        local storeId = row.store_id ~= nil and tostring(row.store_id) or nil
        if storeId then
            -- conditional on the owner, so a store sold meanwhile keeps its new owner
            local n = tonumber(MySQL.update.await('UPDATE pf_stores SET owner_citizenid = NULL, purchased_at = NULL WHERE store_id = ? AND owner_citizenid = ?',
                { storeId, citizenid })) or 0
            if n > 0 then
                released[#released + 1] = storeId
                TriggerClientEvent('pf-stores:client:onStorePurchased', -1, storeId)
            end
        end
    end
    return released
end

AddEventHandler('pfm-core:server:characterDeleted', function(citizenid)
    local src = tonumber(source)
    if src and src > 0 then return end
    if not validCitizenId(citizenid) then return end
    local ok, err = pcall(C.Release, citizenid)
    if not ok then print(('^1[pf-stores]^7 cleanup of deleted character %s failed: %s'):format(citizenid, tostring(err))) end
end)
