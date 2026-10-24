-- Deprecated: moved to client/diagnostic/diagnostics.lua
local QBCore = exports['pfm-core']:GetCoreObject()
print('[DIAGNOSTICS] Deprecated file loaded (no logic).')
-- All functionality now in client/diagnostic/diagnostics.lua

RegisterNetEvent('pf_mech:nos:help', function()
  TriggerEvent('chat:addMessage', { args = { '^3NOS', 'Hold Left Shift to boost • Left Ctrl to purge • Up/Down = level • PgUp/PgDn = purge style' } })
end)
