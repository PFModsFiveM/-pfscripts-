# Elevator Door System Configuration

## Overview
This elevator system includes automated door control that:
- **Closes doors** before the elevator moves
- **Waits for doors to fully close** before movement starts (1.2 second delay)
- **Opens doors** when the elevator arrives at a floor
- **Locks/Unlocks doors** automatically via qb-doorlock without showing UI popups
- **Syncs elevator car doors** with the elevator movement (moves up/down with elevator)
- **Spawns separate floor doors** at each level entrance

## Configuration

### Door Positions in config.lua

Each floor in the `Config.Elevators.floors` table has:

```lua
{
    label = "Floor 1",
    z = 91.163055,                          -- Floor height (Z coordinate)
    callButton = vector3(3772.5, 7954.7, 91.163055),  -- Call button position
    doorLeftPos = vector3(-0.5, -0.8, 0.0), -- Left door offset
    doorRightPos = vector3(0.5, -0.8, 0.0), -- Right door offset
    doorOffset = vector3(0.0, -0.8, 0.0)   -- Used for floor door positioning
}
```

### Door Models

Located in `Config.Elevators.doors`:

```lua
doors = {
    leftModel = `v_ilev_fib_doore_l`,    -- Left door model
    rightModel = `v_ilev_fib_doore_r`,   -- Right door model
    
    -- Positions relative to elevator center when closed
    elevatorDoorLeftClosedOffset = vector3(-0.5, 0.0, 0.0),
    elevatorDoorRightClosedOffset = vector3(0.5, 0.0, 0.0),
    
    -- Door sliding animation settings
    doorSlideDistance = 0.6,    -- How far doors slide open (meters)
    doorAnimationSpeed = 1.0,   -- Speed of animation (meter/second)
}
```

## Door Behavior

### Opening Sequence
1. Elevator arrives at floor
2. Doors begin sliding open (X-axis movement)
3. Both elevator car doors and floor entrance doors open simultaneously
4. Doors automatically unlock via qb-doorlock (silent, no popup)

### Closing Sequence
1. Floor button pressed or elevator queued
2. Doors begin sliding closed
3. System locks doors via qb-doorlock
4. Elevator waits 1.2 seconds for doors to fully close
5. Elevator moves to next floor

## Fine-Tuning Door Positions

If doors don't align properly with your apartment layout:

### 1. Get Door Coordinates from Codewalker
- Open your map in Codewalker
- Find the elevator door entities in your apartment's MLO
- Note the exact X, Y, Z coordinates

### 2. Update Floor Configurations
Convert world coordinates to relative offsets:

```lua
-- If your door is at world position (3771.5, 7954.5, 91.0)
-- And elevator center is at (3772.0, 7954.7, 91.0)
-- The offset is: (-0.5, -0.2, 0.0)

doorLeftPos = vector3(-0.5, -0.2, 0.0),
doorRightPos = vector3(0.5, -0.2, 0.0),
```

### 3. Adjust Animation Settings
- **doorSlideDistance**: Increase if doors don't open fully, decrease if they overlap
- **doorAnimationSpeed**: Increase for faster animation, decrease for slower (should match real door movement)

## Door Lock States

The system uses qb-doorlock's door state system:

- **State 0**: Unlocked (opened when doors are open)
- **State 1**: Locked (doors close before elevator moves)

Door hashes used:
- `pf_elevator_left_car` - Left elevator car door
- `pf_elevator_right_car` - Right elevator car door
- `pf_elevatorfloor_N_left` - Left door on floor N
- `pf_elevatorfloor_N_right` - Right door on floor N

## Troubleshooting

### Doors not opening/closing
- Check console for error messages mentioning door models
- Verify `v_ilev_fib_doore_l` and `v_ilev_fib_doore_r` models are available in your game files
- Ensure door positions are set correctly in config

### Doors getting stuck
- Check that `doorSlideDistance` matches the actual door model size
- Verify doors aren't overlapping with other geometry
- Increase `doorCloseDelay` in server.lua if doors need more time to close

### Elevator not waiting for doors
- Default door close delay is 1200ms in server.lua
- Adjust if your door animation speed is different:
  ```lua
  local doorCloseDelay = 1500  -- Increase to 1.5 seconds
  ```

### qb-doorlock not locking doors
- Ensure qb-doorlock is running and loaded
- Check that door registration is successful (console will show messages)
- Verify door entities actually exist

## Script Integration Points

### Client-Side (client.lua)

- `CloseDoors()` - Called before elevator movement
- `OpenDoors(floorIndex)` - Called when elevator arrives
- `LockElevatorDoors()` - Registers and locks all doors via qb-doorlock
- `UnlockElevatorDoors(floorIndex)` - Unlocks doors at destination floor
- `RegisterDoorWithQBDoorlock(doorEnt, doorHash)` - Manually register a door

### Server-Side (server.lua)

- `doorCloseDelay` constant - Time to wait for doors before moving (1200ms)
- Adjust in `MoveToFloor()` function if needed

## Door Position References

Your provided door coordinates (MLO-relative):
```
Ground Floor Right: (-1.52758789, 8.911621, -20.9038086)
Ground Floor Left: (-1.52758789, 10.4130859, -20.9038086)
```

These are interior-relative coordinates. The system converts them based on the elevator's world position in the config.
