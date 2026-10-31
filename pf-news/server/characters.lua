-- A deleted character's reporter bonuses and ads (articles, leads and views are cleaned in main.lua).
-- pfm-core raises the server-only event 'pfm-core:server:characterDeleted' after the delete; a call
-- from a player is ignored.
--
--   * pf_news_payouts: bonuses still pending are cancelled (there is nobody to pay); paid rows stay,
--     they belong to the money trail (their ledger keys pf-news:bonus:<article id>);
--   * pf_news_ads: an ad belongs to the business that paid for it, so the row stays (its money moved
--     through the business account and any refund goes back there) but loses the buyer's citizenid
--     and name.
-- Each step runs on its own, and running it twice changes nothing the second time.

PFNews = PFNews or {}
PFNews.CharacterCleanupSteps = {
    { name = 'payouts', sql = "UPDATE pf_news_payouts SET state = 'cancelled', error = 'character_deleted' WHERE citizenid = ? AND state = 'pending'" },
    { name = 'ads', sql = "UPDATE pf_news_ads SET buyer_cid = '', buyer_name = NULL WHERE buyer_cid = ?" },
}

local function validCitizenId(citizenid)
    return type(citizenid) == 'string' and citizenid ~= '' and #citizenid <= 50 and citizenid:match('^[%w]+$') ~= nil
end

--- Returns { [step name] = rows changed or false when that step failed }.
function PFNews.RemoveCharacterMoneyRows(citizenid)
    local out = {}
    for _, step in ipairs(PFNews.CharacterCleanupSteps) do
        local ok, n = pcall(MySQL.update.await, step.sql, { citizenid })
        if ok then
            out[step.name] = tonumber(n) or 0
        else
            out[step.name] = false
            print(('^1[pf-news]^7 cleanup (%s) of deleted character %s failed: %s'):format(step.name, citizenid, tostring(n)))
        end
    end
    return out
end

AddEventHandler('pfm-core:server:characterDeleted', function(citizenid)
    local src = tonumber(source)
    if src and src > 0 then return end
    if not validCitizenId(citizenid) then return end
    PFNews.RemoveCharacterMoneyRows(citizenid)
end)
