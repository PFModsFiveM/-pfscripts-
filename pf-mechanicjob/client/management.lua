-- Management App - Client Side Handler (Tablet Only)
-- All management features are accessed through the tablet app
-- No standalone F6 keybind - integrated into tablet window system

local QBCore = exports['pfm-core']:GetCoreObject()

-- Placement handlers for location setup
function PlacementFromProp(placementType, cb)
    local playerPed = PlayerPedId()
    local camCoords = GetGameplayCamCoord()
    local camForward = GetGameplayCamForwardVector()
    local raycastTarget = vector3(
        camCoords.x + camForward.x * 100,
        camCoords.y + camForward.y * 100,
        camCoords.z + camForward.z * 100
    )

    -- Perform raycast
    local hit, hitCoords, hitEntity = GetShapeTestResult(StartShapeTestRay(camCoords.x, camCoords.y, camCoords.z, raycastTarget.x, raycastTarget.y, raycastTarget.z, 10, playerPed, 7))

    if hit and hitEntity then
        local entity = NetworkGetEntityFromNetworkId(hitEntity)
        if DoesEntityExist(entity) then
            local entityCoords = GetEntityCoords(entity)
            local entityHeading = GetEntityHeading(entity)
            local modelHash = GetEntityModel(entity)

            TriggerServerEvent('pf_mechanic:setLocation', {
                type = placementType,
                x = entityCoords.x,
                y = entityCoords.y,
                z = entityCoords.z,
                heading = entityHeading,
                is_prop = 1,
                prop_model = tostring(modelHash)
            })

            if cb then cb(json.encode({success = true})) end
            return
        end
    end

    if cb then cb(json.encode({success = false, message = "No prop looked at"})) end
end

function PlacementFromCoord(placementType, cb)
    local playerPed = PlayerPedId()
    local playerCoords = GetEntityCoords(playerPed)
    local playerHeading = GetEntityHeading(playerPed)

    TriggerServerEvent('pf_mechanic:setLocation', {
        type = placementType,
        x = playerCoords.x,
        y = playerCoords.y,
        z = playerCoords.z,
        heading = playerHeading,
        is_prop = 0
    })

    if cb then cb(json.encode({success = true})) end
end

-- ============================================================================
-- NUI CALLBACKS FOR TABLET MANAGEMENT APP
-- ============================================================================

-- These callbacks are automatically called from tablet's JavaScript
-- They route data between the tablet frontend and the server
