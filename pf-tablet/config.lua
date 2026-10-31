Config = {}
Config.TabletItem = 'tablet' -- Changed from 'job_tablet' to 'tablet' -- Item name in your items.lua

-- The tablet's own apps (Settings is always there). Everything else is a platform app from pf-devices
-- and runs on the computer too: jobs, government, news, directory, dispatch, and the Business Manager,
-- Order Supplies and Job Board (pf-computer). The old 'Businesses' list moved to the Directory app
-- (pf-services); the tablet's own Business Manager became the shared Business Manager, whose City
-- registry section has the registry, compliance, bills, audit log and ownership transfers.
Config.Apps = Config.Apps or {}

Config.RefreshInterval = 5 -- seconds

Config.UI = {
    AppGap = 6,          -- grid gap between app icons
    AppIconSize = 88,     -- px (width/height)
    DockIconSize = 50,    -- px
    WindowW = 760,        -- business & generic window width
    WindowH = 640         -- business & generic window height (increase to avoid cut off on 1080p)
}
