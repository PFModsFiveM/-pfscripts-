fx_version 'cerulean'
game 'gta5'

name 'pf-mechanicjob'
author 'PF Mods'
description 'Advanced Mechanic job'
version '1.0.0'

lua54 'yes'

ui_page 'tablet/index.html'

files {
    'html/img/*.png',
    'html/img/*.webp',
    'html/img/*.svg',
    'html/tablet_module.js',
    'html/apps.css',
    'html/apps/mechanic.js',
    'tablet/index.html',
    'tablet/style.css',
    'tablet/script.js'
}

shared_scripts {
  '@ox_lib/init.lua',             -- NEW: load ox_lib to get the `lib` global
  '@pfm-core/shared/locale.lua',
  'config.lua',
  'config/engineering.lua',       -- ENGINEERING: Advanced tuning config
  'shared/debug.lua',
  'shared/locale.lua',  -- NEW: Load locale system first
  'shared/engineering_items.lua', -- ENGINEERING: Item definitions
  'locales/en.lua',
  'locales/pl.lua',
  'locales/es.lua',
  'locales/fr.lua',
  'locales/de.lua'       -- NEW: Load all locale files
}

client_scripts {
  'client/devices_shell.lua',  -- send app messages to whichever device shell is open (tablet or computer)
  'client/tablet_apps.lua',
  'client/computer_programs.lua',  -- NEW: computer program exports
  'client/tools_menu.lua',
  'client/damage.lua',
  'client/preview.lua',
  'client/main.lua',
  'client/minigames.lua',
  'client/cosmetics.lua',
  'client/garage_sync.lua',
  'client/mileage_hud.lua',
  'client/rolling_coal.lua',
  'client/mechanictools.lua',
  'client/admin_customs.lua',
  -- 'client/register_pos.lua',  -- DISABLED: Replaced by tablet.lua for pf-tablet integration
  'client/receipt.lua',  -- NEW: receipt UI handler
  -- NEW: NOS
  'client/nos.lua',
  -- NEW: enhanced tire smoke
  'client/tire_smoke.lua',
  'client/service_book.lua',  -- NEW: service book UI/logic
  'client/tablet.lua',  -- NEW: tablet system (primary POS handler)
  'client/work_order_vehicles.lua',  -- NEW: work order vehicle management
  'client/management.lua',  -- NEW: management app handler
  'client/supplies.lua',  -- NEW: supplies pickup mission
  'client/advanced_systems.lua', -- NEW: advanced workshop systems (alignment, clutch workflow, diagnostics, roadside, chop)
  -- ENGINEERING: Advanced Vehicle Tuning System
  'client/engineering/cl_effects.lua',
  'client/engineering/cl_physics.lua',
  'client/engineering/cl_engineering.lua'
}

server_scripts {
  '@oxmysql/lib/MySQL.lua',
  '@pfm-banking/payouts.lua',          -- PFPayout: job payouts through the money ledger
  'server/sql_init.lua',              -- NEW: SQL auto-injection system
  'server/diagnostics.lua',            -- NEW: server-side diagnostics item/use
  'server/main.lua',
  'server/repair.lua',
  'server/useables.lua',
  'server/consumables.lua',
  'server/garage_sync.lua',  -- NEW (fixed comma)
  'server/preview.lua',
  'server/preview_receipt.lua',
  -- NEW: NOS
  'server/nos.lua',
  'server/register_pos.lua',  -- POS payment handler (chargeCustomer event)
  'server/tablet.lua',  -- NEW: tablet system (UI interface)
  'server/work_orders.lua',  -- NEW: work order level system
  'server/work_orders_debug.lua',  -- NEW: debug utilities
  'server/management.lua',  -- NEW: management app backend
  'server/business_data_provider.lua',  -- NEW: exports for pf-computer integration
  'server/supplies.lua',  -- NEW: supplies pickup mission
  'server/advanced_systems.lua', -- NEW: advanced workshop systems backend + integrations + skill tree
  'server/admin_customs.lua',
  'server/devices.lua',  -- registers the tablet/computer apps with pf-devices
  -- ENGINEERING: Advanced Vehicle Tuning System
  'server/engineering/sv_tuning_store.lua',
  'server/engineering/sv_calc.lua',
  'server/engineering/sv_engineering.lua',
  'server/engineering/sv_integration.lua',
  'server/engineering/sv_tablet.lua',
  'server/engineering/sv_useables.lua',
  'server/engineering/sv_events.lua'
}

escrow_ignore 'config.lua'
escrow_ignore 'config/engineering.lua'

exports {
    'GetTabletApps',
    'GetComputerPrograms',
    'GetBusinessTransactions',
    'GetBusinessAnalytics',
    'GetBusinessEmployees',
    'GetBusinessConfig',
    'GetBusinessInventory',
  'StartSuppliesPickup',
    -- ENGINEERING: Advanced Vehicle Tuning System
    'GetTuning',
    'GetOrCreateTuning',
    'GetBuildSummary',
    'ApplySimpleUpgrade',
    'InstallComponent',
    'GetRuntimeState',
    'SetECUMap',
    'SetBoost'
}

dependencies {
    'pfm-menu',
    'ox_lib'                      -- NEW: ensure ox_lib is present when enabled in config
}
