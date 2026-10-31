-- The MDT inside the tablet and the computer (pf-devices).
--
-- The device app is this resource's own page (html/index.html?embed=1) in a device window: the
-- same code and UI as the full-screen MDT, 1:1. While it is open ("device mode"):
--   * every message for the MDT page goes to the device window instead of the full-screen frame
--     (the always-on overlays — dispatch pop-ups, custody timer, CCTV — still use the full screen);
--   * this resource does not take or drop NUI focus: the device has it;
--   * closing the MDT closes the app window, not the device.
-- Loaded first, so every other client file uses these wrappers.

PFMdtDevice = { active = false, appId = 'emsmdt' }

local rawSendNUIMessage = SendNUIMessage
local rawSetNuiFocus = SetNuiFocus

-- messages that keep going to the full-screen frame in device mode (things shown over the game)
local OVERLAY = {
    updateDispatchOverlay = true, setDispatchOverlayVisibility = true, playDispatchDing = true,
    custodyTimer = true, cctvViewer = true, cctvCaptureMask = true, cctvPreview = true,
}

local function devicesUp() return GetResourceState('pf-devices') == 'started' end

function SendNUIMessage(payload)
    if PFMdtDevice.active and type(payload) == 'table' and devicesUp() then
        pcall(function() exports['pf-devices']:AppEvent(PFMdtDevice.appId, 'nui', payload) end)
        if OVERLAY[payload.action] then rawSendNUIMessage(payload) end
        return
    end
    rawSendNUIMessage(payload)
end

function SetNuiFocus(hasFocus, hasCursor)
    if PFMdtDevice.active then return end
    rawSetNuiFocus(hasFocus, hasCursor)
end

local function leaveDeviceMode()
    if not PFMdtDevice.active then return end
    PFMdtDevice.active = false
    if type(PFMdtDeviceClosed) == 'function' then PFMdtDeviceClosed() end
end

--- Called by CloseMDT in device mode: the app window closes, the device stays open.
function PFMdtDeviceClose()
    if not PFMdtDevice.active then return false end
    leaveDeviceMode()
    if devicesUp() then pcall(function() exports['pf-devices']:CloseApp(PFMdtDevice.appId) end) end
    return true
end

-- the embedded page asks to open once it has loaded
RegisterNUICallback('pfDeviceOpen', function(_, cb)
    PFMdtDevice.active = true
    if type(PFMdtOpen) == 'function' then PFMdtOpen('device') end
    cb({ ok = true })
end)

-- the device window was closed or replaced
RegisterNUICallback('pfDeviceClosed', function(_, cb)
    leaveDeviceMode()
    cb({ ok = true })
end)

-- the tablet or computer was put away while the MDT app was open
AddEventHandler('pf-devices:client:shellState', function(_, isOpen)
    if isOpen == false then leaveDeviceMode() end
end)
