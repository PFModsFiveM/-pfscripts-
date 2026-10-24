Config = {}

-- Global elevator settings
Config.Elevators = {
    model = `pf_elevatormo`,        -- primary model name to scan for
    altModels = { },                -- additional model names to scan for (e.g. interior elevators)
    spawnPos = vector4(3772.080078, 7956.943359, 91.163055, 270.00),  -- spawn position and heading
    headingOffset = 0.0,
    speed = 1.0,                    -- meters per second

    -- Door configuration
    doors = {
        leftModel = `v_ilev_fib_doore_l`,
        rightModel = `v_ilev_fib_doore_r`,
        -- Positions relative to elevator center for closed doors
        elevatorDoorLeftClosedOffset = vector3(-0.5, 0.0, 0.0),   -- Left door closed position
        elevatorDoorRightClosedOffset = vector3(0.5, 0.0, 0.0),   -- Right door closed position
        -- How far doors slide when opening (X axis movement)
        doorSlideDistance = 0.6,  -- Meters to slide open
        doorAnimationSpeed = 1.0,  -- Animation speed multiplier (1.0 = 1 meter per second)
    },

    floors = {
        { label = "Floor 1", z = 91.163055, callButton = vector3(3772.5, 7954.7, 91.163055), doorOffset = vector3(0.0, -0.8, 0.0) },
        { label = "Floor 2", z = 95.880051, callButton = vector3(3772.5, 7954.7, 95.880051), doorOffset = vector3(0.0, -0.8, 0.0) },
        { label = "Floor 3", z = 100.602142, callButton = vector3(3772.5, 7954.7, 100.602142), doorOffset = vector3(0.0, -0.8, 0.0) },
        { label = "Floor 4", z = 105.323082, callButton = vector3(3772.5, 7954.7, 105.323082), doorOffset = vector3(0.0, -0.8, 0.0) },
        { label = "Floor 5", z = 110.044083, callButton = vector3(3772.5, 7954.7, 110.044083), doorOffset = vector3(0.0, -0.8, 0.0) },
        { label = "Floor 6", z = 114.765076, callButton = vector3(3772.5, 7954.7, 114.765076), doorOffset = vector3(0.0, -0.8, 0.0) },
        { label = "Floor 7", z = 119.483086, callButton = vector3(3772.5, 7954.7, 119.483086), doorOffset = vector3(0.0, -0.8, 0.0) },
        { label = "Floor 8", z = 124.205101, callButton = vector3(3772.5, 7954.7, 124.205101), doorOffset = vector3(0.0, -0.8, 0.0) },
        { label = "Floor 9", z = 128.926407, callButton = vector3(3772.5, 7954.7, 128.926407), doorOffset = vector3(0.0, -0.8, 0.0) }
    }
}
