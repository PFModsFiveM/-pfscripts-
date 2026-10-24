Config = {}
Config.TabletItem = 'tablet' -- Changed from 'job_tablet' to 'tablet' -- Item name in your items.lua

Config.Apps = Config.Apps or {
    {name = 'Business Manager', icon = '📊', enabled = true},
    {name = 'Businesses', icon = '🏪', enabled = true},
}

Config.BusinessJobs = Config.BusinessJobs or {
    { label = 'Police',      role = 'police',     icon = '👮', description = 'Law enforcement and public safety' },
    { label = 'Ambulance',   role = 'ambulance',  icon = '🚑', description = 'Emergency medical services' },
    { label = 'Mechanic',    role = 'mechanic',   icon = '🔧', description = 'Vehicle repairs and maintenance' },
    { label = 'Beeker\'s',   role = 'beeker',     icon = '🏁', description = 'Custom garage and modifications' },
    { label = 'Benny\'s',    role = 'bennys',     icon = '🛠️', description = 'Premium auto customization' },
    { label = 'Real Estate', role = 'realestate', icon = '🏠', description = 'Property sales and management' },
    { label = 'Taxi',        role = 'taxi',       icon = '🚕', description = 'Passenger transportation services' },
    { label = 'Car Dealer',  role = 'cardealer',  icon = '🚗', description = 'New and used vehicle sales' },
    { label = 'Government',  role = 'government', icon = '🏛️', description = 'City administration and services' },
}

Config.RefreshInterval = 5 -- seconds

Config.UI = {
    AppGap = 6,          -- grid gap between app icons
    AppIconSize = 88,     -- px (width/height)
    DockIconSize = 50,    -- px
    WindowW = 760,        -- business & generic window width
    WindowH = 640         -- business & generic window height (increase to avoid cut off on 1080p)
}
