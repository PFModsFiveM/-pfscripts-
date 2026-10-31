-- PF Services client: waypoints and blips for dispatch requests.

local requestBlips = {}

RegisterNetEvent('pf-services:client:waypoint', function(x, y)
    x, y = tonumber(x), tonumber(y)
    if x and y then SetNewWaypoint(x + 0.0, y + 0.0) end
end)

-- A short-lived blip on the map for a new request for this player's job.
RegisterNetEvent('pf-services:client:newRequest', function(req)
    if type(req) ~= 'table' or type(req.coords) ~= 'table' then return end
    local id = tonumber(req.id)
    if not id then return end
    if requestBlips[id] and DoesBlipExist(requestBlips[id]) then RemoveBlip(requestBlips[id]) end
    local blip = AddBlipForCoord(req.coords.x + 0.0, req.coords.y + 0.0, (req.coords.z or 0.0) + 0.0)
    SetBlipSprite(blip, 161)
    SetBlipScale(blip, 1.0)
    SetBlipColour(blip, 1)
    SetBlipAsShortRange(blip, false)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentString(('#%d %s'):format(id, tostring(req.label or 'Request')))
    EndTextCommandSetBlipName(blip)
    requestBlips[id] = blip
    SetTimeout(120000, function()
        if requestBlips[id] and DoesBlipExist(requestBlips[id]) then RemoveBlip(requestBlips[id]) end
        requestBlips[id] = nil
    end)
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    for _, blip in pairs(requestBlips) do if DoesBlipExist(blip) then RemoveBlip(blip) end end
end)
