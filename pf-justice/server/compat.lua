-- pf-justice compatibility mirrors (PF_ARCHITECTURE 1 "read rule for metadata", 9).
--
-- 20+ existing call sites read player metadata `injail` (minutes) and `criminalrecord`
-- ({ hasRecord, date }). pf-justice keeps them as mirrors of its own rows, refreshed on every order
-- and record event, at load and once a minute for online inmates:
--   * injail = the minutes left on the citizen's incarceration chain (GetJailMinutes);
--   * criminalrecord = the latest conviction (or imported legacy flag), with an expiry
--     (Config.Compat.RecordExpiryDays, 0 = never), written only when it changes.
--
-- Batch 15: the old jails still write these themselves. While Config.Compat.LegacyRuntimes.prison
-- is not false, injail is left to pfm-prison (its client enters its own jail when injail > 0, so a
-- second writer would jail a player twice). A chain that holds a shadow of a live MDT jail is never
-- mirrored either. While LegacyRuntimes.policejob is not false, PJ's /jail still sets
-- hasRecord = true and the mirror never turns that back to false. 16C/16D flip the flags; from then
-- on pf-justice is the only writer.

PFJustice = PFJustice or {}
PFJustice.Compat = PFJustice.Compat or {}
local Compat = PFJustice.Compat
PFJustice.CustodyKit = PFJustice.CustodyKit or {} -- filled by custody.lua; looked up when called
local K = PFJustice.CustodyKit

local CONVICTION_KINDS = { conviction = true, legacy_flag = true }

local function openRows(cid)
    local O = PFJustice.Orders
    if O and K.callable(O.IncarcerationRows) then return O.IncarcerationRows(cid) or {} end
    local res = K.callApi('GetOrders', cid, { kinds = { 'jail', 'prison', 'remand' }, states = { 'active', 'pending', 'suspended' }, limit = 100 })
    return type(res) == 'table' and res.list or {}
end

--- Whether pf-justice may write injail for this citizen now.
function Compat.MirrorsInjail(cid)
    if K.legacyLive('prison') then return false end
    if K.legacyLive('mdt') then
        for _, r in ipairs(openRows(cid)) do
            local ref = r.legacy_ref or r.legacyRef
            if type(ref) == 'string' and ref:sub(1, 9) == 'mdt_jail:' then return false end
        end
    end
    return true
end

--- The criminalrecord value pf-justice's records give (nil when the records cannot be read).
function Compat.RecordValue(cid, now)
    local res = K.callApi('GetRecord', cid, { limit = 100 })
    if type(res) ~= 'table' or not res.ok then return nil end
    local latest
    for _, e in ipairs(res.entries or {}) do
        if CONVICTION_KINDS[e.kind] and not e.expungedAt and tonumber(e.at) and (not latest or tonumber(e.at) > latest) then
            latest = tonumber(e.at)
        end
    end
    local days = tonumber(K.cfg('Compat', 'RecordExpiryDays', 30)) or 30
    local has = latest ~= nil and (days <= 0 or (now or K.now()) - latest < days * 86400)
    return { hasRecord = has == true, date = has and os.date('*t', latest) or nil }
end

local function sameRecord(a, b)
    if type(a) ~= 'table' or type(b) ~= 'table' then return false end
    if (a.hasRecord == true) ~= (b.hasRecord == true) then return false end
    local da, db = type(a.date) == 'table' and a.date or {}, type(b.date) == 'table' and b.date or {}
    return da.year == db.year and da.month == db.month and da.day == db.day
end

--- Refreshes the mirrors of an online citizen. what = { injail = true, record = true } (both by default).
function Compat.Refresh(cid, what, now)
    if not K.validCid(cid) or not K.ready() then return false end
    what = what or { injail = true, record = true }
    local P = K.playerByCid(cid)
    if not P then return false end
    local meta = P.PlayerData.metadata or {}
    local wrote = false
    if what.injail and Compat.MirrorsInjail(cid) then
        local minutes = tonumber(K.callApi('GetJailMinutes', cid)) or 0
        if (tonumber(meta.injail) or 0) ~= minutes then
            K.setMeta(P, 'injail', minutes)
            wrote = true
        end
    end
    if what.record then
        local value = Compat.RecordValue(cid, now)
        if value then
            local current = type(meta.criminalrecord) == 'table' and meta.criminalrecord or { hasRecord = false }
            -- PJ /jail still sets the flag in batch 15: never undo a flag another writer set
            if K.legacyLive('policejob') and current.hasRecord == true and not value.hasRecord then value = nil end
            if value and not sameRecord(current, value) then
                P = K.playerByCid(cid) or P
                K.setMeta(P, 'criminalrecord', value)
                wrote = true
            end
        end
    end
    return wrote
end

--- Once a minute: injail of every online inmate (memory reads only).
function Compat.Tick()
    local clock = PFJustice.Clock
    local list = clock and type(clock.srcOf) == 'table' and clock.srcOf or {}
    local n = 0
    for cid in pairs(list) do
        if Compat.Refresh(cid, { injail = true }) then n = n + 1 end
    end
    return n
end

local function safe(fn, ...)
    local ok, err = pcall(fn, ...)
    if not ok then print(('^1[pf-justice]^7 compat: %s'):format(tostring(err))) end
end

local function orderCid(order) return type(order) == 'table' and (order.cid or order.citizenid) or nil end

AddEventHandler('pf-justice:server:orderCreated', function(order) safe(Compat.Refresh, orderCid(order), { injail = true }) end)
AddEventHandler('pf-justice:server:orderChanged', function(order) safe(Compat.Refresh, orderCid(order), { injail = true, record = true }) end)
AddEventHandler('pf-justice:server:releaseOrdered', function(cid) safe(Compat.Refresh, cid) end)
AddEventHandler('pf-justice:server:recordChanged', function(cid) safe(Compat.Refresh, cid, { record = true }) end)

AddEventHandler('QBCore:Server:PlayerLoaded', function(player)
    local data = type(player) == 'table' and player.PlayerData
    local cid = data and data.citizenid
    if K.validCid(cid) then
        CreateThread(function()
            Wait(3000) -- after the legacy import and the clock load of this player
            safe(Compat.Refresh, cid)
        end)
    end
end)

CreateThread(function()
    while true do
        Wait(60000)
        safe(Compat.Tick)
    end
end)
