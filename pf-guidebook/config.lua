Config = {}

-- auto | qbcore | esx | standalone
Config.Framework = 'auto'

Config.ItemName = 'guidebook'
Config.EnableUseableItem = true
Config.DataFile = 'guidebook_data.json'
Config.CallbackTimeoutMs = 12000

-- QBCore permission groups
Config.AdminPermissions = {
    'god',
    'admin'
}

-- ESX groups
Config.AdminGroups = {
    'admin',
    'superadmin'
}

-- Generic/standalone ace permissions checked via IsPlayerAceAllowed
Config.AdminAcePermissions = {
    'guidebook.admin'
}

-- Optional identifier allowlist for admin access (license:, steam:, discord:, etc.)
Config.AdminIdentifiers = {}

Config.Commands = {
    Guidebook = 'guidebook',
    GuidebookAdmin = 'guidebookadmin',
    Help = 'help',
    HelpAdmin = 'helpadmin',
    SendHelp = 'sendhelp',
    PointGps = 'pointgps'
}

Config.DefaultData = {
    categories = {
        {
            key = 'welcome',
            label = 'Welcome',
            order = 1,
            enabled = true,
            expanded = true,
            permissionsEnabled = false,
            allowedJobs = {}
        },
        {
            key = 'tutorials',
            label = 'Tutorials',
            order = 2,
            enabled = true,
            expanded = true,
            permissionsEnabled = false,
            allowedJobs = {}
        },
        {
            key = 'rules',
            label = 'Rules',
            order = 3,
            enabled = true,
            expanded = false,
            permissionsEnabled = false,
            allowedJobs = {}
        },
        {
            key = 'city_laws',
            label = 'City laws',
            order = 4,
            enabled = true,
            expanded = false,
            permissionsEnabled = false,
            allowedJobs = {}
        },
        {
            key = 'jobs',
            label = 'Department of Employment',
            order = 5,
            enabled = true,
            expanded = true,
            permissionsEnabled = false,
            allowedJobs = {}
        }
    },
    pages = {
        {
            categoryKey = 'welcome',
            key = 'our_city',
            label = 'Our city',
            order = 0,
            enabled = true,
            permissionsEnabled = false,
            allowedJobs = {},
            content = [[
                <h2>Welcome to the city</h2>
                <p>This guidebook can be opened with <strong>/guidebook</strong> or <strong>/help</strong>.</p>
                <p>Admins can manage this content in-game without restarting the server.</p>
            ]]
        },
        {
            categoryKey = 'tutorials',
            key = 'cars_and_bikes',
            label = 'Cars & Bikes',
            order = 0,
            enabled = true,
            permissionsEnabled = false,
            allowedJobs = {},
            content = [[
                <h2>Cars & Bikes</h2>
                <p>Use rental or dealership systems to get your first vehicle.</p>
                <ul>
                    <li>Start with rentals if your budget is limited.</li>
                    <li>Buy from dealerships when ready.</li>
                    <li>Always store vehicles in a garage.</li>
                </ul>
            ]]
        },
        {
            categoryKey = 'jobs',
            key = 'police',
            label = 'Police',
            order = 0,
            enabled = true,
            permissionsEnabled = false,
            allowedJobs = {},
            content = [[
                <h2>Police</h2>
                <p>Visit your city job center to apply for open positions.</p>
                <p>Department-specific SOPs can be added here by admins.</p>
            ]]
        }
    }
}
