-- Supplier app (pf-devices, tablet + computer): player suppliers — farmers, vineyard workers,
-- divers, anyone with goods — run their supply business from a device instead of chat commands.
-- Every action goes through the same PFOrders functions the /supplier commands use (offers capped
-- by the AI price at order time, stock taken from the real inventory and freshness-checked,
-- orders accepted atomically, goods and markup share paid on the ledger once the order is
-- delivered). Order lines are shown in the supplier's own stock units (O.SupplierLines).

local O = PFOrders

local function QB() return exports['pfm-core']:GetCoreObject() end

local function supplierRow(src)
    local Player = QB().Functions.GetPlayer(src)
    local cid = Player and Player.PlayerData.citizenid
    if not cid then return nil end
    return MySQL.single.await('SELECT id, name, active FROM pf_suppliers WHERE citizenid = ? LIMIT 1', { cid })
end

local function itemLabel(name)
    local def = QB().Shared.Items[name]
    return def and def.label or name
end

local function myOffers(sup)
    local rows = MySQL.query.await('SELECT item, unit_price, stock_qty FROM pf_supplier_offers WHERE supplier_id = ? ORDER BY item', { sup.id }) or {}
    local out = {}
    for _, r in ipairs(rows) do
        out[#out + 1] = { item = r.item, label = itemLabel(r.item), price = tonumber(r.unit_price) or 0, stock = tonumber(r.stock_qty) or 0 }
    end
    return out
end

-- What the supplier carries that matches their offers (so the app can offer "stock N cases").
-- (the case size is the one stocking uses, O.CaseSizeOf)
local function carried(src, offers)
    local inv = exports['pfm-inventory']
    local out = {}
    for _, o in ipairs(offers) do
        local ok, items = pcall(function() return inv:GetItemsByName(src, o.item) end)
        local n = 0
        for _, it in ipairs(ok and items or {}) do n = n + (tonumber(it.amount) or 0) end
        local size = O.CaseSizeOf(o.item)
        out[o.item] = { items = n, caseSize = size, cases = math.floor(n / size) }
    end
    return out
end

local function register()
    if GetResourceState('pf-devices') ~= 'started' then return end
    local devices = exports['pf-devices']
    devices:RegisterApp({
        id = 'supplier', name = 'Supplier', icon = '🚜',
        entry = 'html/apps/supplier.js', category = 'business', order = 40,
        access = { installable = true },
        store = { description = 'Sell your goods to the city\'s stores and restaurants: set prices, stock cases, fill orders.', publisher = 'PF Supply' },
        description = 'Sell goods to businesses',
    })
    devices:RegisterAppHandlers('supplier', {
        status = function(src)
            local sup = supplierRow(src)
            if not sup then return { ok = true, supplier = false } end
            local offers = myOffers(sup)
            local open = O.OpenOffersFor(src)
            local orders = {}
            for _, o in ipairs(open.ok and open.data or {}) do
                local lines = {}
                for _, l in ipairs(o.lines or {}) do
                    -- in the supplier's own stock units (what accepting reserves) and the price per unit
                    lines[#lines + 1] = { label = (l.label and l.label ~= l.name) and l.label or itemLabel(l.name), quantity = l.units, cost = l.cost }
                end
                -- paid at delivery: the goods (pays) and the supplier's share of the markup (bonus)
                orders[#orders + 1] = { orderId = o.orderId, lines = lines, subtotal = o.subtotal, pays = o.pays, bonus = o.bonus }
            end
            return { ok = true, supplier = true, name = sup.name, active = tonumber(sup.active) == 1, offers = offers, orders = orders, carried = carried(src, offers) }
        end,
        register = function(src, p) return O.RegisterSupplier(src, type(p.name) == 'string' and p.name or '') end,
        setOffer = function(src, p) return O.SetOffer(src, p.item, p.price) end,
        stock = function(src, p) return O.DepositStock(src, p.item, p.cases) end,
        accept = function(src, p) return O.AcceptSupply(src, tonumber(p.orderId)) end,
    })
end

AddEventHandler('onResourceStart', function(resource)
    if resource == GetCurrentResourceName() or resource == 'pf-devices' then register() end
end)
AddEventHandler('pf-devices:server:ready', register)
