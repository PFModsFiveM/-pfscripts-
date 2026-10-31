-- Start-up of the field apps: tables, the apps on pf-devices and the request handlers on
-- pf-services. Either platform may start before or after this resource, or restart on its own.

local A = GovApps

local function startUp()
    GovSchema.Ensure()
    A.RegisterAll()
    if GovRequests and GovRequests.RegisterHandlers then GovRequests.RegisterHandlers() end
end

AddEventHandler('onResourceStart', function(resource)
    if resource == GetCurrentResourceName() then
        CreateThread(startUp)
    elseif resource == 'pf-devices' then
        -- pf-devices raises pf-devices:server:ready as well; registering twice is harmless
        CreateThread(function() A.RegisterAll() end)
    elseif resource == 'pf-services' then
        CreateThread(function() if GovRequests then GovRequests.RegisterHandlers() end end)
    end
end)

AddEventHandler('pf-devices:server:ready', function()
    A.RegisterAll()
end)

-- pf-devices access check for City Hall Requests and other resources: may this player ask City Hall
-- on behalf of a business?
exports('ManagesBusiness', function(src, businessId)
    if businessId then return GovRequests.ManagedBusiness(src, businessId) ~= nil end
    return #GovRequests.ManagedBusinesses(src) > 0
end)
