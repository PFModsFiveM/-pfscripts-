# Removed (tablet-only mode)

This resource was converted to a tablet-only UI. The Garbage job/app is no longer included.

---

## Legacy documentation (not used)

## Database Setup
The XP system automatically creates the database table on resource start. You can also manually run:
```sql
-- Located in: sql/garbage.sql
CREATE TABLE IF NOT EXISTS `pf_garbage_xp` (
    `citizenid` VARCHAR(64) NOT NULL PRIMARY KEY,
    `xp` INT(11) NOT NULL DEFAULT 0,
    `level` INT(11) NOT NULL DEFAULT 1,
    `updated_at` TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
```

## Configuration Location
All garbage job settings are in `config.lua` under `Config.Garbage = {}`

## Key Features

### 🎯 XP & Progression System
- **XP per bag**: `Config.Garbage.XPPerBag` (default: 25)
- **Level thresholds**: Fully customizable in `Config.Garbage.LevelThresholds`
- **Persistent storage**: XP saves to database automatically
- **Database toggle**: `Config.Garbage.UseDatabase` (default: true)

### 👥 Group System (Party Mechanics)
- **Max party size**: `Config.Garbage.Groups.MaxMembers` (default: 4)
- **Auto-rebalancing**: Splits adjust automatically when members join/leave
- **Payout sharing**: `Config.Garbage.Groups.SharePayouts` (default: true)
- **Leader controls**: Invite, kick, adjust splits
- **Commands**: Same as Gruppe6 group system
  - Create party
  - Invite by player ID
  - Accept/decline invites
  - Leave party
  - Kick members
  - Adjust payout splits

### 💰 Payout System
- **Level-based payouts**: Higher levels earn more per bag
- **Customizable rates**: `Config.Garbage.PayoutPerBag`
  - Level 1: $20/bag
  - Level 2: $40/bag
  - Level 3+: $60/bag

### 🗑️ Interactable Props (Fully Customizable)
Add or remove props in `Config.Garbage.DumpsterProps` and `Config.Garbage.BinbagProps`:

**Dumpster Props** (2-6 bags each):
```lua
DumpsterProps = {
    'prop_dumpster_01a',
    'prop_dumpster_4a',
    'prop_dumpster_02a',
    'prop_dumpster_02b',
    'm23_2_prop_m32_dumpster_01a',
    'prop_dumpster_4b',
    -- Add more dumpster models here
}
```

**Binbag Props** (1 bag each):
```lua
BinbagProps = {
    'hei_prop_heist_binbag',
    'p_binbag_01_s',
    'prop_cs_street_binbag_01',
    'prop_rub_binbag_sd_01',
    'prop_cs_rub_binbag_01',
    'prop_rub_binbag_04',
    'prop_rub_binbag_sd_02',
    'ng_proc_binbag_01a',
    'prop_rub_binbag_05',
    'prop_rub_binbag_01',
    'prop_ld_rub_binbag_01',
    -- Add more binbag models here
}
```

### 🎬 Animations (Customizable)
All animations can be changed in config:
```lua
Animations = {
    Pickup = { dict = 'anim@heists@narcotics@trash', anim = 'pickup', duration = 900 },
    Carry = { dict = 'anim@heists@narcotics@trash', anim = 'walk', clipset = 'move_m@trash' },
    Deposit = { dict = 'anim@heists@narcotics@trash', anim = 'throw_bag', duration = 1200 },
}
```

### 🚛 Vehicle Settings
```lua
VehicleSpawn = vector4(-327.06, -1524.36, 27.54, 271.38),
VehicleModel = 'trash',  -- Change to any vehicle model
```

### 📍 Location Settings
```lua
DepotLocation = vector3(-325.53, -1523.77, 27.54),  -- Return location
DepotRadius = 7.5,  -- Interaction radius for return
```

### 🎨 Visual Settings
```lua
EnableHighlights = true,  -- Outline nearby props
HighlightRange = 6.0,  -- Range for highlighting
HighlightColor = {1, 255, 158, 255},  -- RGBA color
```

### 🗺️ Blip Settings
Customize truck and return blips:
```lua
TruckBlip = {
    sprite = 318,
    color = 2,
    scale = 0.9,
    label = 'Garbage Truck'
},

ReturnBlip = {
    sprite = 318,
    color = 5,
    scale = 1.0,
    label = 'Return Garbage Truck'
}
```

## How to Add Custom Props

### Adding Dumpsters
1. Find the prop name in-game (use resource like `ps-props` or developer tools)
2. Add to `Config.Garbage.DumpsterProps`:
```lua
DumpsterProps = {
    'prop_dumpster_01a',
    'your_custom_dumpster_here',  -- Add your model
}
```

### Adding Binbags
1. Find the prop name
2. Add to `Config.Garbage.BinbagProps`:
```lua
BinbagProps = {
    'hei_prop_heist_binbag',
    'your_custom_binbag_here',  -- Add your model
}
```

## Gameplay Mechanics

### Level System
- Level 1 (0 XP): $20/bag, 20 bag cap
- Level 2 (1,000 XP): $40/bag, unlimited
- Level 3+ (3,000+ XP): $60/bag, unlimited

### Job Flow (Solo)
1. Start job from tablet → Truck spawns
2. Collect bags from dumpsters (2-6 bags) or loose bags (1 bag)
3. Deposit bags at truck rear (press E or use qb-target)
4. Collect 10 bags total (configurable)
5. Return truck to depot for payout

### Job Flow (Party)
1. Leader creates party and invites members (by server ID)
2. Members accept invites to join
3. Leader starts job → Truck spawns
4. All party members can collect and deposit bags
5. Leader adjusts payout splits (optional)
6. Return truck → Payout automatically split among party
7. Example: $600 total with 4 members = $150 each (25% split)

### Party System Features
- **Auto-rebalancing**: When a member joins, splits adjust evenly
  - 2 members: 50%/50%
  - 3 members: 33%/33%/34% (leader gets leftover)
  - 4 members: 25%/25%/25%/25%
- **Manual adjustment**: Leader can change any member's percentage
- **Leader controls**: Only leader can invite, kick, or adjust splits
- **Persistent**: Party stays together across multiple jobs
- **Leave anytime**: Members can leave, leader can kick

### XP Progression
- Earn XP for each bag deposited (personal, not shared)
- XP saves automatically to database
- Level up unlocks better payouts (applies to your split)
- Progress persists between sessions
- Groups don't affect XP gain

## Group System Usage

### Creating a Party
1. Open the job tablet
2. Navigate to Garbage Job
3. Click "Create Party" button
4. You become the party leader

### Inviting Members
1. Ask players for their server ID (shown in top-right of screen or via /id command)
2. Enter their ID in the invite field
3. Click "Invite"
4. They receive a notification to accept/decline

### Joining a Party
1. When invited, you'll see a notification
2. Press the accept button in the notification
3. You'll join the party and see all members

### Managing Party
**As Leader:**
- Invite members by ID
- Kick members from party
- Adjust payout splits (percentage)
- Start the job (spawns truck for everyone)

**As Member:**
- View current party and splits
- Leave party anytime
- Work together with party on same truck

### Payout Example
Total payout: $600 (10 bags × $60/bag at level 3)

**Default split (4 members):**
- Leader: $150 (25%)
- Member 1: $150 (25%)
- Member 2: $150 (25%)
- Member 3: $150 (25%)

**Custom split:**
- Leader adjusts splits to: 40%, 20%, 20%, 20%
- Leader: $240 (40%)
- Member 1: $120 (20%)
- Member 2: $120 (20%)
- Member 3: $120 (20%)

### Party Tips
- Splits must total 100%
- Only leader can start the job
- All members can collect/deposit bags
- XP is earned individually (not split)
- Party persists across jobs
- If leader disconnects, party disbands

## Debug Mode
Toggle debug mode in-game:
```lua
/garbdebug
```
Shows markers and additional logging.

## Troubleshooting

### XP Not Saving
- Check `Config.Garbage.UseDatabase = true`
- Verify database table exists (auto-created on start)
- Check server console for MySQL errors

### Props Not Highlighting
- Check `Config.Garbage.EnableHighlights = true`
- Verify prop models exist in your server
- Adjust `Config.Garbage.HighlightRange` if too far/close

### Vehicle Not Spawning
- Check spawn location isn't blocked
- Verify vehicle model exists: `Config.Garbage.VehicleModel`
- Check server console for errors

## Support
For issues or questions, check:
1. Server console for errors
2. Client F8 console for warnings
3. Verify all config values are valid
