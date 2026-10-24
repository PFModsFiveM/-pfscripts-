Config.Restaurants = {
    ['burgershot_vespucci'] = {
        businessId = 'burgershot_vespucci',
        label = 'Burger Shot - Vespucci',
        blip = {
            enabled = true,
            sprite = 106,
            color = 5,
            scale = 0.8,
            label = 'Burger Shot'
        },
        zones = {
            kitchen = {
                center = vector3(-1199.5, -885.3, 13.98),
                radius = 15.0
            },
            dining = {
                center = vector3(-1193.4, -894.1, 13.98),
                radius = 12.0
            },
            storage = {
                center = vector3(-1203.2, -897.8, 13.98),
                radius = 5.0
            },
            receiving = {
                center = vector3(-1206.7, -896.2, 13.98),
                radius = 4.0,
                deliverySpawn = vector3(-1206.7, -896.2, 13.48)
            }
        },
        storage = {
            dry = {
                coords = vector3(-1203.2, -897.8, 13.98),
                capacity = 500
            },
            fridge = {
                coords = vector3(-1202.1, -897.8, 13.98),
                capacity = 300
            },
            freezer = {
                coords = vector3(-1201.0, -897.8, 13.98),
                capacity = 300
            }
        },
        hygieneSpawns = {
            trash = {
                vector3(-1199.0, -892.0, 13.98),
                vector3(-1196.5, -888.5, 13.98),
                vector3(-1195.2, -895.0, 13.98),
            },
            roaches = {
                area = vector3(-1200.0, -890.0, 13.98),
                radius = 10.0
            }
        }
    },
    
    ['pizzathis'] = {
        businessId = 'pizzathis',
        label = 'Pizza This',
        blip = {
            enabled = true,
            sprite = 267,
            color = 1,
            scale = 0.8,
            label = 'Pizza This'
        },
        zones = {
            kitchen = {
                center = vector3(810.9, -750.8, 26.78),
                radius = 12.0
            },
            dining = {
                center = vector3(809.1, -762.4, 26.78),
                radius = 10.0
            },
            storage = {
                center = vector3(815.2, -745.6, 26.78),
                radius = 4.0
            },
            receiving = {
                center = vector3(817.5, -744.8, 26.78),
                radius = 3.0,
                deliverySpawn = vector3(817.5, -744.8, 26.28)
            }
        },
        storage = {
            dry = {
                coords = vector3(815.2, -745.6, 26.78),
                capacity = 400
            },
            fridge = {
                coords = vector3(814.5, -746.2, 26.78),
                capacity = 250
            },
            freezer = {
                coords = vector3(813.8, -746.8, 26.78),
                capacity = 250
            }
        },
        hygieneSpawns = {
            trash = {
                vector3(811.0, -751.0, 26.78),
                vector3(809.0, -748.0, 26.78),
            },
            roaches = {
                area = vector3(812.0, -749.0, 26.78),
                radius = 8.0
            }
        }
    }
}
