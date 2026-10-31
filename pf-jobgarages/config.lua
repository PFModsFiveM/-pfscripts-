Config = Config or {}

-- Garage provider: 'cd', 'qb', or 'none'
Config.GarageProvider = 'qb'

-- Player vehicles owner column: 'citizenid', 'owner', 'license', 'identifier'
Config.PlayerVehiclesOwnerColumn = 'license'

-- Taking a fleet vehicle out needs the player to be on duty for the garage's job (checked on the
-- server). A garage can override it with requireOnDuty = false. Storing a car back is always allowed.
Config.RequireOnDuty = true

-- Fleet management (adding/removing cars, force returns, assignments, permissions) needs this job
-- grade unless the garage's saved "minimum grade to manage" says otherwise. A garage can set its
-- own manageGrade. Job bosses can always manage.
Config.DefaultManageGrade = 4

-- Job garage locations
Config.JobGarages = {
    ['mechanic_main'] = {
        label = 'East Customs Fleet',
        job = 'mechanic',
        minGrade = 0,

        targetProp = 'prop_parkingpay',
        targetCoords = vector4(869.03, -2127.16, 30.6, 262.22),

        spawnCoords = vector4(859.77, -2127.05, 30.54, 350.35),
        themeColor = '#ffd54f',
    },

    ['police_main'] = {
        label = 'MRPD Fleet',
        job = 'police',
        minGrade = 0,

        targetProp = 'prop_parkingpay',
        targetCoords = vector4(458.61, -1023.36, 28.33, 268.63),

        spawnCoords = vector4(410.12, -971.35, 25.45, 180.0),
        themeColor = '#53a2ff',
    },

    ['ambulance_main'] = {
        label = 'Pillbox Fleet',
        job = 'ambulance',
        minGrade = 0,

        targetProp = 'prop_parkingpay',
        targetCoords = vector4(309.39, -586.56, 43.29, 340.0),

        spawnCoords = vector4(299.84, -577.28, 43.26, 160.0),
        themeColor = '#ff5252',
    },
}
