-- Management App - Client Side Handler (Tablet Only)
-- All management features are accessed through the tablet app (client/tablet.lua NUI callbacks).
-- This file holds the other side of hiring: a citizen's answer to a job offer.

local QBCore = exports['pfm-core']:GetCoreObject()

-- (Location placement was retired: the placed stash/locker/duty points were never used in game.)

-- ============================================================================
-- JOB OFFERS: the citizen accepts or declines (the server changes the job only on accept)
-- ============================================================================

local function offerMenu(offers)
    if type(offers) ~= 'table' or #offers == 0 then
        QBCore.Functions.Notify('You have no open job offers', 'primary')
        return
    end
    local menu = { { header = 'Job offers', isMenuHeader = true } }
    for _, o in ipairs(offers) do
        local id = tonumber(o.id)
        if id then
            local shop = tostring(o.shop or 'a mechanic shop')
            menu[#menu + 1] = {
                header = ('Job at %s'):format(shop),
                txt = ('Offered by %s · open for %s more hour(s)'):format(tostring(o.from or 'a manager'), tostring(o.hoursLeft or '?')),
                isMenuHeader = true,
            }
            menu[#menu + 1] = {
                header = 'Accept',
                txt = ('Leave your current job and join %s'):format(shop),
                params = { event = 'pf_mech:offers:answer', args = { id = id, accept = true } },
            }
            menu[#menu + 1] = {
                header = 'Decline',
                params = { event = 'pf_mech:offers:answer', args = { id = id, accept = false } },
            }
        end
    end
    menu[#menu + 1] = { header = 'Later', txt = 'Ask me again next time (or type /joboffers)', params = { event = 'qb-menu:client:closeMenu' } }
    exports['pfm-menu']:openMenu(menu)
end

-- the server sends the open offers when one is made and after each login
RegisterNetEvent('pf_mech:offers:show', function(offers)
    offerMenu(offers)
end)

RegisterNetEvent('pf_mech:offers:answer', function(args)
    if type(args) ~= 'table' or not tonumber(args.id) then return end
    TriggerServerEvent('pf_mech:management:respondOffer', tonumber(args.id), args.accept == true)
end)

RegisterCommand('joboffers', function()
    QBCore.Functions.TriggerCallback('pf_mech:management:myOffers', function(list)
        offerMenu(list)
    end)
end, false)
