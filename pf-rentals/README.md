# PF-Rentals - Vehicle Rental System

A comprehensive vehicle rental system for QBCore FiveM servers with a modern UI.

## Features

- 🚗 **Interactive Rental Peds** - Multiple rental locations with NPC interaction using qb-target
- 💰 **Flexible Payments** - Supports both cash and bank payments
- ⏱️ **Timed Rentals** - Players select rental duration (1-30 days)
- 🔑 **Automatic Keys** - Integration with qb-vehiclekeys for automatic key distribution
- 📸 **Vehicle Previews** - Uses screenshot-basic for vehicle image generation
- 🗺️ **Map Blips** - Configurable rental location blips
- 📊 **Database Tracking** - Stores rental history in MySQL database
- ⏰ **Auto Expiration** - Vehicles are automatically returned when rental expires
- 🎨 **Modern UI** - Clean, responsive interface with category filtering

## Dependencies

Required:
- qb-core
- qb-target
- oxmysql

Optional:
- screenshot-basic (for vehicle images)
- qb-vehiclekeys (for vehicle keys)
- LegacyFuel or qb-fuel (for fuel setting)

## Installation

1. Extract `pf-rentals` to your `resources/[pfscripts]` folder
2. Add `ensure pf-rentals` to your server.cfg
3. Restart your server
4. The database table will be created automatically

## Configuration

Edit `config.lua` to customize:

### Rental Locations

```lua
Config.RentalLocations = {
    {
        name = "Airport Rentals",
        coords = vector3(-1034.19, -2733.60, 13.76),
        heading = 328.90,
        blip = {
            enabled = true,
            sprite = 56,
            color = 3,
            scale = 0.8,
            label = "Vehicle Rentals"
        },
        ped = {
            model = "a_m_y_business_01",
            scenario = "WORLD_HUMAN_CLIPBOARD"
        },
        spawnPoint = vector4(-1028.22, -2725.72, 13.76, 240.0)
    },
    -- Add more locations...
}
```

### Available Vehicles

```lua
Config.RentalVehicles = {
    {
        id = 1,
        brand = 'Grotti',
        model = 'turismor',
        displayName = 'Grotti Turismo R',
        category = 'sports',
        price = 500,
        image = 'screenshot'
    },
    -- Add more vehicles...
}
```

### Payment Settings

```lua
Config.PaymentMethods = {
    cash = true,
    bank = true
}

Config.MaxRentalDuration = 30  -- Maximum days
Config.MinRentalDuration = 1   -- Minimum days
```

### Features Toggles

```lua
Config.UseQBNotifications = true   -- Use QB-Core notifications
Config.UseQBVehicleKeys = true     -- Give keys automatically
Config.UseScreenshotBasic = true   -- Use screenshot-basic for images
Config.CheckInterval = 60000       -- Check rental expiration every 60 seconds
```

## Usage

### For Players

1. Go to any rental location (marked with a blip on the map)
2. Interact with the rental ped using qb-target (Third Eye)
3. Browse available vehicles by category
4. Select a vehicle and choose rental duration
5. Confirm the rental and pay
6. The vehicle will spawn at the designated spawn point
7. You'll receive the keys automatically

### For Admins

**Commands:**
- `/expirerentals` - Expire all active rentals immediately (Admin only)

**Debug Mode:**
```lua
Config.Debug = true  -- Enable debug prints in console
```

## Vehicle Categories

- Sports
- Muscle
- Sedan
- Trucks
- Vans
- Compacts
- Offroad
- Motorcycles

Add custom categories by including them in your vehicle configurations.

## Database

The script automatically creates a `player_rentals` table with the following structure:

```sql
CREATE TABLE `player_rentals` (
    `id` INT(11) NOT NULL AUTO_INCREMENT,
    `citizenid` VARCHAR(50) NOT NULL,
    `rental_id` VARCHAR(100) NOT NULL,
    `vehicle_model` VARCHAR(50) NOT NULL,
    `brand` VARCHAR(50),
    `duration` INT(11),
    `daily_rate` INT(11),
    `total_price` INT(11),
    `payment_method` VARCHAR(20) DEFAULT 'cash',
    `start_time` INT(11),
    `expiration_time` INT(11),
    `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`)
);
```

## Rental Expiration

- Rentals are checked every 60 seconds by default (configurable)
- When a rental expires:
  - Player receives a notification
  - The vehicle is automatically deleted
  - The rental record is removed from active rentals

## Customization

### Adding New Rental Locations

1. Open `config.lua`
2. Add a new entry to `Config.RentalLocations`
3. Set coordinates, ped model, blip settings, and spawn point
4. Restart the resource

### Adding New Vehicles

1. Open `config.lua`
2. Add a new entry to `Config.RentalVehicles`
3. Set vehicle details including spawn name, display name, category, and price
4. Restart the resource

### Changing UI Appearance

Edit files in the `html` folder:
- `index.html` - Structure
- `style.css` - Styling
- `script.js` - Functionality

## Troubleshooting

**Rental ped not spawning:**
- Check that qb-target is running
- Verify the ped model exists
- Enable debug mode to see console messages

**Vehicle keys not working:**
- Ensure qb-vehiclekeys is installed and running
- Check that `Config.UseQBVehicleKeys = true`
- Verify qb-core's vehiclekeys system is working

**Images not showing:**
- Install screenshot-basic resource
- Ensure screenshot-basic is started before pf-rentals
- Check that `Config.UseScreenshotBasic = true`

**Payment not working:**
- Verify player has sufficient funds
- Check that payment methods are enabled in config
- Review server console for errors

## Support

For issues or questions, contact the server development team.

## Credits

- Author: ProjectFusion
- Version: 1.0.0
- Framework: QBCore

## License

This resource is proprietary to ProjectFusion servers.
