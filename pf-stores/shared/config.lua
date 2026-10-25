Config = Config or {}

Config.Debug = false
-- Category to Upgrade Mapping
-- Links store supply categories to required Maze Bank Foreclosures upgrades
Config.CategoryUpgrades = {
	-- 24/7 and LTD stores
	['Drinks'] = 'grocery_license', -- Basic grocery items
	['Snacks'] = 'grocery_license',
	['Food'] = 'grocery_license',
	['Smoking'] = 'tobacco_license', -- Cigarettes require tobacco license
	['Automotive'] = 'grocery_license', -- Basic automotive at gas stations

	-- SmoKing
	['Disposable Vapes'] = 'vape_license',
	['Box Mods'] = 'vape_license',
	['Coil Tops'] = 'vape_license',
	['Juice'] = 'vape_license',

	-- DigiDen
	['Phones'] = 'electronics_license',
	['Wearables'] = 'electronics_license',
	['Electronics'] = 'electronics_license',
}


-- If true, any player can open/checkout Order Supplies for stores (dev only).
Config.DebugAllowAnyOrderSupplies = false

-- Store definitions
-- NOTE: Delivery coords are intentionally nil until you provide real vectors.
-- If coords are nil, the UI will still allow "Pickup" but will block "Outsource to trucking".
Config.Stores = {
	smoking = {
		id = 'smoking',
		label = 'SmoKing',
		type = 'purchasable',

		purchase = {
			-- qb-target will be attached to this prop.
			propModel = 'prop_forsale_lrg_04',
			coords = vector4(-503.46, 278.0, 83.32, 175.02),
			-- For testing you can set this to 0.
			price = 0,
			moneyType = 'bank',
		},

		npc = {
			coords = vector4(-502.77, 285.3, 83.32, 252.21),
			model = 'mp_m_shopkeep_01',
		},

		blip = {
			enabled = true,
			sprite = 59,
			scale = 0.8,
			color = 2,
			label = 'SmoKing',
		},

		-- Items shown inside pf-computer > Order Supplies
		-- Stock is tracked as "cases" in the DB.
		-- NOTE: Supplies now default to the storefront catalog (storefront.items).
		-- Only use supplyItems if you want a separate supply list AND you include an item mapping,
		-- e.g. { item = 'blue_stickevape', label = 'Blue Stick E-Vape', category = 'Disposable Vapes', cost = 90.0 }
		supplyItems = {},

		-- Public storefront (NUI store page)
		-- You will provide the real items list after the UI is finished.
		storefront = {
			enabled = true,
			-- Allowed payment methods at checkout (player chooses in the storefront UI)
			moneyTypes = { 'cash', 'bank' },
			defaultMoneyType = 'cash',
			-- Optional storefront branding
			-- color supports hex like '#f97316' (orange) or rgb/rgba strings.
			-- logo can be a file inside this resource UI folder (ex: 'assets/smoking_logo.png')
			-- or a full nui URL (ex: 'nui://pfm-inventory/html/images/smoking_logo.png').
			brand = {
				color = '#f97316', -- SmoKing orange
				logo = 'assets/smoking_logo.png',
				-- Many inventory PNGs have lots of transparent padding; this zoom helps them fill the card media box.
				productImageScale = 0.60,
				-- Nudge product images upward in the card (pixels; negative moves up).
				productImageOffsetY = -80,
			},
			categories = {
				'Disposable Vapes',
				'Box Mods',
				'Coil Tops',
				'Juice',
			},
			-- Items must use valid QBCore item names. Add entries later.
			-- { name = 'some_item', label = 'Display Name (optional)', category = 'Disposable Vapes', price = 100, maxQuantity = 10 }
			items = {
				-- Disposable Vapes
				{ name = 'blue_stickevape', label = 'Blue Stick E-Vape', category = 'Disposable Vapes', price = 125, cost = 63, maxQuantity = 10, image = 'blue_stickevape.png' },
				{ name = 'red_stickevape', label = 'Red Stick E-Vape', category = 'Disposable Vapes', price = 125, cost = 63, maxQuantity = 10, image = 'red_stickevape.png' },
				{ name = 'green_stickevape', label = 'Green Stick E-Vape', category = 'Disposable Vapes', price = 125, cost = 63, maxQuantity = 10, image = 'green_stickevape.png' },
				{ name = 'pink_stickevape', label = 'Pink Stick E-Vape', category = 'Disposable Vapes', price = 125, cost = 63, maxQuantity = 10, image = 'pink_stickevape.png' },
				{ name = 'lightgrey_stickevape', label = 'Light Grey Stick E-Vape', category = 'Disposable Vapes', price = 125, cost = 63, maxQuantity = 10, image = 'lightgrey_stickevape.png' },
				{ name = 'black_stickevape', label = 'Black Stick E-Vape', category = 'Disposable Vapes', price = 125, cost = 63, maxQuantity = 10, image = 'black_stickevape.png' },
				{ name = 'orange_stickevape', label = 'Orange Stick E-Vape', category = 'Disposable Vapes', price = 125, cost = 63, maxQuantity = 10, image = 'orange_stickevape.png' },
				{ name = 'yellow_stickevape', label = 'Yellow Stick E-Vape', category = 'Disposable Vapes', price = 125, cost = 63, maxQuantity = 10, image = 'yellow_stickevape.png' },

				{ name = 'blue_sumovape', label = 'Blue Sumo', category = 'Disposable Vapes', price = 150, cost = 75, maxQuantity = 10, image = 'blue_sumovape.png' },
				{ name = 'red_sumovape', label = 'Red Sumo', category = 'Disposable Vapes', price = 150, cost = 75, maxQuantity = 10, image = 'red_sumovape.png' },
				{ name = 'green_sumovape', label = 'Green Sumo', category = 'Disposable Vapes', price = 150, cost = 75, maxQuantity = 10, image = 'green_sumovape.png' },
				{ name = 'pink_sumovape', label = 'Pink Sumo', category = 'Disposable Vapes', price = 150, cost = 75, maxQuantity = 10, image = 'pink_sumovape.png' },
				{ name = 'lightgrey_sumovape', label = 'Light Grey Sumo', category = 'Disposable Vapes', price = 150, cost = 75, maxQuantity = 10, image = 'lightgrey_sumovape.png' },
				{ name = 'black_sumovape', label = 'Black Sumo', category = 'Disposable Vapes', price = 150, cost = 75, maxQuantity = 10, image = 'black_sumovape.png' },
				{ name = 'orange_sumovape', label = 'Orange Sumo', category = 'Disposable Vapes', price = 150, cost = 75, maxQuantity = 10, image = 'orange_sumovape.png' },
				{ name = 'yellow_sumovape', label = 'Yellow Sumo', category = 'Disposable Vapes', price = 150, cost = 75, maxQuantity = 10, image = 'yellow_sumovape.png' },

				{ name = 'blue_vaporglowvape', label = 'Blue VaporGlow', category = 'Disposable Vapes', price = 175, cost = 88, maxQuantity = 10, image = 'blue_vaporglowvape.png' },
				{ name = 'red_vaporglowvape', label = 'Red VaporGlow', category = 'Disposable Vapes', price = 175, cost = 88, maxQuantity = 10, image = 'red_vaporglowvape.png' },
				{ name = 'green_vaporglowvape', label = 'Green VaporGlow', category = 'Disposable Vapes', price = 175, cost = 88, maxQuantity = 10, image = 'green_vaporglowvape.png' },
				{ name = 'pink_vaporglowvape', label = 'Pink VaporGlow', category = 'Disposable Vapes', price = 175, cost = 88, maxQuantity = 10, image = 'pink_vaporglowvape.png' },
				{ name = 'lightgrey_vaporglowvape', label = 'Light Grey VaporGlow', category = 'Disposable Vapes', price = 175, cost = 88, maxQuantity = 10, image = 'lightgrey_vaporglowvape.png' },
				{ name = 'black_vaporglowvape', label = 'Black VaporGlow', category = 'Disposable Vapes', price = 175, cost = 88, maxQuantity = 10, image = 'black_vaporglowvape.png' },
				{ name = 'orange_vaporglowvape', label = 'Orange VaporGlow', category = 'Disposable Vapes', price = 175, cost = 88, maxQuantity = 10, image = 'orange_vaporglowvape.png' },
				{ name = 'yellow_vaporglowvape', label = 'Yellow VaporGlow', category = 'Disposable Vapes', price = 175, cost = 88, maxQuantity = 10, image = 'yellow_vaporglowvape.png' },

				-- Box Mods (devices)
				{ name = 'evape1', label = 'E-Vape + Atomizer', category = 'Box Mods', price = 650, cost = 325, maxQuantity = 5, image = 'evape1.png' },
				{ name = 'evape2', label = 'Smoke + Atomizer', category = 'Box Mods', price = 650, cost = 325, maxQuantity = 5, image = 'evape2.png' },

				{ name = 'sand_evapebox', label = 'Sand E-Vape Box', category = 'Box Mods', price = 550, cost = 275, maxQuantity = 5, image = 'sand_evapebox.png' },
				{ name = 'black_evapebox', label = 'Black E-Vape Box', category = 'Box Mods', price = 550, cost = 275, maxQuantity = 5, image = 'black_evapebox.png' },
				{ name = 'redblack_evapebox', label = 'Red & Black E-Vape Box', category = 'Box Mods', price = 550, cost = 275, maxQuantity = 5, image = 'redblack_evapebox.png' },
				{ name = 'cyan_evapebox', label = 'Cyan E-Vape Box', category = 'Box Mods', price = 550, cost = 275, maxQuantity = 5, image = 'cyan_evapebox.png' },
				{ name = 'redwhite_evapebox', label = 'Red & White E-Vape Box', category = 'Box Mods', price = 550, cost = 275, maxQuantity = 5, image = 'redwhite_evapebox.png' },
				{ name = 'grey_evapebox', label = 'Grey E-Vape Box', category = 'Box Mods', price = 550, cost = 275, maxQuantity = 5, image = 'grey_evapebox.png' },

				{ name = 'blue_smokebox', label = 'Blue Smoke Box', category = 'Box Mods', price = 550, cost = 275, maxQuantity = 5, image = 'blue_smokebox.png' },
				{ name = 'red_smokebox', label = 'Red Smoke Box', category = 'Box Mods', price = 550, cost = 275, maxQuantity = 5, image = 'red_smokebox.png' },
				{ name = 'green_smokebox', label = 'Green Smoke Box', category = 'Box Mods', price = 550, cost = 275, maxQuantity = 5, image = 'green_smokebox.png' },
				{ name = 'pink_smokebox', label = 'Pink Smoke Box', category = 'Box Mods', price = 550, cost = 275, maxQuantity = 5, image = 'pink_smokebox.png' },
				{ name = 'lightblue_smokebox', label = 'L. Blue Smoke Box', category = 'Box Mods', price = 550, cost = 275, maxQuantity = 5, image = 'lightblue_smokebox.png' },
				{ name = 'black_smokebox', label = 'Black Smoke Box', category = 'Box Mods', price = 550, cost = 275, maxQuantity = 5, image = 'black_smokebox.png' },
				{ name = 'orange_smokebox', label = 'Orange Smoke Box', category = 'Box Mods', price = 550, cost = 275, maxQuantity = 5, image = 'orange_smokebox.png' },
				{ name = 'yellow_smokebox', label = 'Yellow Smoke Box', category = 'Box Mods', price = 550, cost = 275, maxQuantity = 5, image = 'yellow_smokebox.png' },

				-- Coil Tops (atomizers)
				{ name = 'silver_longatomizer', label = 'Long Silver Atomizer', category = 'Coil Tops', price = 75, cost = 38, maxQuantity = 10, image = 'silver_longatomizer.png' },
				{ name = 'red_longatomizer', label = 'Long Red Atomizer', category = 'Coil Tops', price = 75, maxQuantity = 10, image = 'red_longatomizer.png' },
				{ name = 'blue_longatomizer', label = 'Long Blue Atomizer', category = 'Coil Tops', price = 75, maxQuantity = 10, image = 'blue_longatomizer.png' },
				{ name = 'green_longatomizer', label = 'Long Green Atomizer', category = 'Coil Tops', price = 75, maxQuantity = 10, image = 'green_longatomizer.png' },
				{ name = 'pink_longatomizer', label = 'Long Pink Atomizer', category = 'Coil Tops', price = 75, maxQuantity = 10, image = 'pink_longatomizer.png' },
				{ name = 'grey_longatomizer', label = 'Long Grey Atomizer', category = 'Coil Tops', price = 75, maxQuantity = 10, image = 'grey_longatomizer.png' },
				{ name = 'black_longatomizer', label = 'Long Black Atomizer', category = 'Coil Tops', price = 75, maxQuantity = 10, image = 'black_longatomizer.png' },
				{ name = 'orange_longatomizer', label = 'Long Orange Atomizer', category = 'Coil Tops', price = 75, maxQuantity = 10, image = 'orange_longatomizer.png' },
				{ name = 'yellow_longatomizer', label = 'Long Yellow Atomizer', category = 'Coil Tops', price = 75, maxQuantity = 10, image = 'yellow_longatomizer.png' },

				{ name = 'silver_shortatomizer', label = 'Short Silver Atomizer', category = 'Coil Tops', price = 65, maxQuantity = 10, image = 'silver_shortatomizer.png' },
				{ name = 'red_shortatomizer', label = 'Short Red Atomizer', category = 'Coil Tops', price = 65, maxQuantity = 10, image = 'red_shortatomizer.png' },
				{ name = 'blue_shortatomizer', label = 'Short Blue Atomizer', category = 'Coil Tops', price = 65, maxQuantity = 10, image = 'blue_shortatomizer.png' },
				{ name = 'green_shortatomizer', label = 'Short Green Atomizer', category = 'Coil Tops', price = 65, maxQuantity = 10, image = 'green_shortatomizer.png' },
				{ name = 'pink_shortatomizer', label = 'Short Pink Atomizer', category = 'Coil Tops', price = 65, maxQuantity = 10, image = 'pink_shortatomizer.png' },
				{ name = 'grey_shortatomizer', label = 'Short Grey Atomizer', category = 'Coil Tops', price = 65, maxQuantity = 10, image = 'grey_shortatomizer.png' },
				{ name = 'black_shortatomizer', label = 'Short Black Atomizer', category = 'Coil Tops', price = 65, maxQuantity = 10, image = 'black_shortatomizer.png' },
				{ name = 'orange_shortatomizer', label = 'Short Orange Atomizer', category = 'Coil Tops', price = 65, maxQuantity = 10, image = 'orange_shortatomizer.png' },
				{ name = 'yellow_shortatomizer', label = 'Short Yellow Atomizer', category = 'Coil Tops', price = 65, maxQuantity = 10, image = 'yellow_shortatomizer.png' },

				{ name = 'silver_notankatomizer', label = 'Silver NO-Tank Atomizer', category = 'Coil Tops', price = 60, maxQuantity = 10, image = 'silver_notankatomizer.png' },
				{ name = 'gold_notankatomizer', label = 'Gold NO-Tank Atomizer', category = 'Coil Tops', price = 60, maxQuantity = 10, image = 'gold_notankatomizer.png' },
				{ name = 'black_notankatomizer', label = 'Black NO-Tank Atomizer', category = 'Coil Tops', price = 60, maxQuantity = 10, image = 'black_notankatomizer.png' },
				{ name = 'red_notankatomizer', label = 'Red NO-Tank Atomizer', category = 'Coil Tops', price = 60, maxQuantity = 10, image = 'red_notankatomizer.png' },

				-- Juice (liquids)
				{ name = 'liquid_sweettemptation', label = 'Liquid: Sweet Temptation', category = 'Juice', price = 45, cost = 23, maxQuantity = 20, image = 'liquid_sweettemptation.png' },
				{ name = 'liquid_iceberg', label = 'Liquid: Iceberg', category = 'Juice', price = 45, maxQuantity = 20, image = 'liquid_iceberg.png' },
				{ name = 'liquid_snoopify', label = 'Liquid: Snoopify', category = 'Juice', price = 45, maxQuantity = 20, image = 'liquid_snoopify.png' },
				{ name = 'liquid_goldtobacco', label = 'Liquid: Goldtobacco', category = 'Juice', price = 45, maxQuantity = 20, image = 'liquid_goldtobacco.png' },
				{ name = 'liquid_fruitytrip', label = 'Liquid: FruityTrip', category = 'Juice', price = 45, maxQuantity = 20, image = 'liquid_fruitytrip.png' },
				{ name = 'liquid_candybomb', label = 'Liquid: CandyBomb', category = 'Juice', price = 45, maxQuantity = 20, image = 'liquid_candybomb.png' },
				{ name = 'liquid_sensei', label = 'Liquid: Sensei', category = 'Juice', price = 45, maxQuantity = 20, image = 'liquid_sensei.png' },
				{ name = 'liquid_blueberry', label = 'Liquid: Blue Berry', category = 'Juice', price = 45, maxQuantity = 20, image = 'liquid_blueberry.png' },

				-- Packaging (kept under Box Mods so it appears in the storefront)
				{ name = 'smokebox_cardboard', label = 'Smoke Box Cardboard', category = 'Box Mods', price = 15, cost = 8, maxQuantity = 25, image = 'smokebox_cardboard.png' },
				{ name = 'evape1_cardboard', label = 'E-Vape Stick Cardboard', category = 'Box Mods', price = 15, maxQuantity = 25, image = 'evape1_cardboard.png' },
				{ name = 'evape2_cardboard', label = 'E-Vape Box Cardboard', category = 'Box Mods', price = 15, maxQuantity = 25, image = 'evape2_cardboard.png' },
				{ name = 'sumo_cardboard', label = 'Sumo Vape Cardboard', category = 'Box Mods', price = 15, maxQuantity = 25, image = 'sumo_cardboard.png' },
				{ name = 'vaporglow_cardboard', label = 'VaporGlow Cardboard', category = 'Box Mods', price = 15, maxQuantity = 25, image = 'vaporglow_cardboard.png' },
			},
		},

		trucking = {
			enabled = true,
			title = 'SmoKing Supplies',
			cargoType = 'Store Supplies',
			cargoQuantityLabel = 'cases',
			requiredTrailer = nil,
			-- Payout for the driver (before any pf-trucking rental fee is deducted).
			-- If payoutRate is set, payout is computed from the order total.
			payoutRate = 0.12,
			payoutMin = 250,
			pickup = { label = 'Wholesale Distributor', coords = vector4(1012.4, -2520.7, 28.31, 92.0) },
			dropoff = { label = 'SmoKing', coords = vector3(-488.08, 303.04, 83.23) },
		},
	},

	digiden = {
		id = 'digiden',
		label = 'DigiDen',
		type = 'purchasable',

		purchase = {
				propModel = 'prop_forsale_lrg_04',
				coords = vector4(-21.51, -107.24, 57.01, 340.58),
				price = 0,
				moneyType = 'bank',
			},

			npc = {
				coords = vector4(-17.92, -94.24, 57.04, 156.07),
				model = 'mp_m_shopkeep_01',
			},

			blip = {
				enabled = true,
				sprite = 59,
				scale = 0.8,
				color = 3,
				label = 'DigiDen',
			},

			supplyItems = {},

			storefront = {
				enabled = true,
				moneyTypes = { 'cash', 'bank' },
				defaultMoneyType = 'bank',
				brand = {
					color = '#a855f7', -- purple
					logo = 'assets/digitalden_logo.png',
				},
				categories = {
					'Phones',
					'Wearables',
					'Electronics',
				},
				-- TODO: Prices are placeholders; adjust to your economy.
				items = {
					-- Phones
					{ name = 'yphone', label = 'Phone', category = 'Phones', price = 800, cost = 400, maxQuantity = 2, image = 'yphone_black.png' },
					{ name = 'yflipphone', label = 'Phone', category = 'Phones', price = 650, maxQuantity = 2, image = 'yflip_graphite.png' },
					{ name = 'yphone_natural', label = 'YPhone Natural', category = 'Phones', price = 800, maxQuantity = 2, image = 'yphone_natural.png' },
					{ name = 'yphone_black', label = 'YPhone Black', category = 'Phones', price = 800, maxQuantity = 2, image = 'yphone_black.png' },
					{ name = 'yphone_white', label = 'YPhone White', category = 'Phones', price = 800, maxQuantity = 2, image = 'yphone_white.png' },
					{ name = 'yphone_blue', label = 'YPhone Blue', category = 'Phones', price = 800, maxQuantity = 2, image = 'yphone_blue.png' },
					{ name = 'yflip_mint', label = 'YFlip Mint', category = 'Phones', price = 650, maxQuantity = 2, image = 'yflip_mint.png' },
					{ name = 'yflip_gold', label = 'YFlip Gold', category = 'Phones', price = 650, maxQuantity = 2, image = 'yflip_gold.png' },
					{ name = 'yflip_graphite', label = 'YFlip Graphite', category = 'Phones', price = 650, maxQuantity = 2, image = 'yflip_graphite.png' },
					{ name = 'yflip_lavender', label = 'YFlip Lavender', category = 'Phones', price = 650, maxQuantity = 2, image = 'yflip_lavender.png' },
					{ name = 'y24_black', label = 'Y24 Black', category = 'Phones', price = 950, maxQuantity = 2, image = 'y24_black.png' },
					{ name = 'y24_silver', label = 'Y24 Silver', category = 'Phones', price = 950, maxQuantity = 2, image = 'y24_silver.png' },
					{ name = 'y24_yellow', label = 'Y24 Yellow', category = 'Phones', price = 950, maxQuantity = 2, image = 'y24_yellow.png' },
					{ name = 'y24_violet', label = 'Y24 Violet', category = 'Phones', price = 950, maxQuantity = 2, image = 'y24_violet.png' },
					{ name = 'yphone_fold_black', label = 'YPhone Fold Black', category = 'Phones', price = 1350, maxQuantity = 1, image = 'yphone_fold_black.png' },
					{ name = 'yfold_black', label = 'YFold Black', category = 'Phones', price = 1350, maxQuantity = 1, image = 'yfold_black.png' },

					-- Wearables
					{ name = 'fitbit', label = 'Fitbit', category = 'Wearables', price = 350, cost = 175, maxQuantity = 3, image = 'fitbit.png' },

					-- Electronics / Tools
					{ name = 'radioscanner', label = 'Radio Scanner', category = 'Electronics', price = 1200, cost = 600, maxQuantity = 2, image = 'radioscanner.png' },
					{ name = 'pinger', label = 'Pinger', category = 'Electronics', price = 900, maxQuantity = 2, image = 'pinger.png' },
					{ name = 'cryptostick', label = 'Crypto Stick', category = 'Electronics', price = 2500, maxQuantity = 2, image = 'cryptostick.png' },
					{ name = 'radio', label = 'Radio', category = 'Electronics', price = 450, maxQuantity = 2, image = 'radio.png' },
					{ name = 'tablet', label = 'Tablet', category = 'Electronics', price = 1100, maxQuantity = 2, image = 'tablet.png' },
				},
			},

			trucking = {
				enabled = true,
				title = 'DigiDen Supplies',
				cargoType = 'Store Supplies',
				cargoQuantityLabel = 'cases',
				requiredTrailer = nil,
				payoutRate = 0.12,
				payoutMin = 250,
				pickup = { label = 'Wholesale Distributor', coords = vector4(1012.4, -2520.7, 28.31, 92.0) },
				dropoff = { label = 'DigiDen', coords = vector3(-28.55, -84.36, 57.25) },
			},
		},

	twentyfourseven_1 = {
		id = 'twentyfourseven_1',
		label = '24/7 Supermarket - Clinton Ave',
		type = 'chain',

		purchase = {
			propModel = 'prop_forsale_lrg_04',
			coords = vector4(362.31, 325.14, 103.57, 253.92),
			price = 0,
			moneyType = 'bank',
		},

	npc = {
		coords = vector4(372.88, 327.50, 103.57, 253.92),
		model = 'mp_m_shopkeep_01',
		},

	blip = {
		enabled = true,
		sprite = 52,
		scale = 0.8,
		color = 2,
		label = '24/7 Clinton Ave',
	},

	supplyItems = {},

	storefront = {
		enabled = true,
		moneyTypes = { 'cash', 'bank' },
		defaultMoneyType = 'cash',
		brand = {
			color = '#10b981', -- 24/7 green
			logo = 'assets/247_logo.png',
		},
		categories = {
			'Drinks',
			'Snacks',
			'Food',
			'Smoking',
		},
		items = {
				-- Drinks (wholesale: 40-60% of retail)
				{ name = 'water_bottle', label = 'Water', category = 'Drinks', price = 8, cost = 3, maxQuantity = 10, image = 'water_bottle.png' },
				{ name = 'kurkakola', label = 'Cola', category = 'Drinks', price = 12, cost = 5, maxQuantity = 10, image = 'cola.png' },
				{ name = 'coffee', label = 'Coffee', category = 'Drinks', price = 15, cost = 6, maxQuantity = 10, image = 'coffee.png' },
				{ name = 'milk', label = 'Milk', category = 'Drinks', price = 10, cost = 4, maxQuantity = 8, image = 'milk.png' },
				{ name = 'orange_juice', label = 'Orange Juice', category = 'Drinks', price = 14, cost = 6, maxQuantity = 8, image = 'orange_juice.png' },
				{ name = 'apple_juice', label = 'Apple Juice', category = 'Drinks', price = 14, cost = 6, maxQuantity = 8, image = 'apple_juice.png' },
				{ name = 'iced_tea', label = 'Iced Tea', category = 'Drinks', price = 12, cost = 5, maxQuantity = 10, image = 'iced_tea.png' },
				
				-- Alcohol (wholesale: 50% of retail)
				{ name = 'beer', label = 'Beer', category = 'Drinks', price = 18, cost = 9, maxQuantity = 12, image = 'beer.png' },
				{ name = 'whiskey', label = 'Whiskey', category = 'Drinks', price = 40, cost = 20, maxQuantity = 6, image = 'whiskey.png' },
				{ name = 'vodka', label = 'Vodka', category = 'Drinks', price = 35, cost = 18, maxQuantity = 6, image = 'vodka.png' },
				{ name = 'wine', label = 'Wine', category = 'Drinks', price = 30, cost = 15, maxQuantity = 6, image = 'wine.png' },

				-- Snacks (wholesale: 45% of retail)
				{ name = 'twerks_candy', label = 'Twerks Candy', category = 'Snacks', price = 8, cost = 3, maxQuantity = 20, image = 'twerks_candy.png' },
				{ name = 'snikkel_candy', label = 'Snikkel Candy', category = 'Snacks', price = 8, cost = 3, maxQuantity = 20, image = 'snikkel_candy.png' },
				{ name = 'chocolate_chips', label = 'Chocolate Chips', category = 'Snacks', price = 12, cost = 5, maxQuantity = 15, image = 'chocolate_chips.png' },

				-- Food (wholesale: 50% of retail)
				{ name = 'tosti', label = 'Grilled Cheese', category = 'Food', price = 10, cost = 5, maxQuantity = 10, image = 'tosti.png' },
				{ name = 'sandwich', label = 'Sandwich', category = 'Food', price = 12, cost = 6, maxQuantity = 10, image = 'sandwich.png' },

				-- Smoking (wholesale: 50% of retail)
				{ name = 'cigarette_pack', label = 'Cigarettes', category = 'Smoking', price = 22, cost = 11, maxQuantity = 10, image = 'cigarette_pack.png' },
				{ name = 'lighter', label = 'Lighter', category = 'Smoking', price = 6, cost = 3, maxQuantity = 15, image = 'lighter.png' },
			},
		},

		trucking = {
			enabled = true,
			title = '24/7 Clinton Ave Supplies',
			cargoType = 'Store Supplies',
			cargoQuantityLabel = 'cases',
			requiredTrailer = nil,
			payoutRate = 0.12,
			payoutMin = 250,
			pickup = { label = 'Wholesale Distributor', coords = vector4(1012.4, -2520.7, 28.31, 92.0) },
			dropoff = { label = '24/7 Clinton Ave', coords = vector3(373.18, 328.88, 103.57) },
		},
	},

	twentyfourseven_2 = {
		id = 'twentyfourseven_2',
		label = '24/7 Supermarket - Innocence Blvd',
		type = 'chain',

		purchase = {
			propModel = 'prop_forsale_lrg_04',
			coords = vector4(28.21, -1345.23, 29.5, 268.93),
			price = 0,
			moneyType = 'bank',
		},

		npc = {
			coords = vector4(24.50, -1347.28, 29.50, 268.93),
			model = 'mp_m_shopkeep_01',
		},

		blip = {
			enabled = true,
			sprite = 52,
			scale = 0.8,
			color = 2,
			label = '24/7 Innocence',
		},

		supplyItems = {},

		storefront = {
			enabled = true,
			moneyTypes = { 'cash', 'bank' },
			defaultMoneyType = 'cash',
			brand = {
				color = '#10b981',
				logo = nil,
			},
			categories = {
				'Drinks',
				'Snacks',
				'Food',
				'Smoking',
			},
			items = {
				{ name = 'water_bottle', label = 'Water', category = 'Drinks', price = 8, cost = 3, maxQuantity = 10, image = 'water_bottle.png' },
				{ name = 'kurkakola', label = 'Cola', category = 'Drinks', price = 12, cost = 5, maxQuantity = 10, image = 'cola.png' },
				{ name = 'coffee', label = 'Coffee', category = 'Drinks', price = 15, cost = 6, maxQuantity = 10, image = 'coffee.png' },
				{ name = 'milk', label = 'Milk', category = 'Drinks', price = 10, cost = 4, maxQuantity = 8, image = 'milk.png' },
				{ name = 'orange_juice', label = 'Orange Juice', category = 'Drinks', price = 14, cost = 6, maxQuantity = 8, image = 'orange_juice.png' },
				{ name = 'apple_juice', label = 'Apple Juice', category = 'Drinks', price = 14, cost = 6, maxQuantity = 8, image = 'apple_juice.png' },
				{ name = 'iced_tea', label = 'Iced Tea', category = 'Drinks', price = 12, cost = 5, maxQuantity = 10, image = 'iced_tea.png' },
				{ name = 'beer', label = 'Beer', category = 'Drinks', price = 18, cost = 9, maxQuantity = 12, image = 'beer.png' },
				{ name = 'whiskey', label = 'Whiskey', category = 'Drinks', price = 40, cost = 20, maxQuantity = 6, image = 'whiskey.png' },
				{ name = 'vodka', label = 'Vodka', category = 'Drinks', price = 35, cost = 18, maxQuantity = 6, image = 'vodka.png' },
				{ name = 'wine', label = 'Wine', category = 'Drinks', price = 30, cost = 15, maxQuantity = 6, image = 'wine.png' },
				{ name = 'twerks_candy', label = 'Twerks Candy', category = 'Snacks', price = 8, cost = 3, maxQuantity = 20, image = 'twerks_candy.png' },
				{ name = 'snikkel_candy', label = 'Snikkel Candy', category = 'Snacks', price = 8, cost = 3, maxQuantity = 20, image = 'snikkel_candy.png' },
				{ name = 'chocolate_chips', label = 'Chocolate Chips', category = 'Snacks', price = 12, cost = 5, maxQuantity = 15, image = 'chocolate_chips.png' },
				{ name = 'tosti', label = 'Grilled Cheese', category = 'Food', price = 10, cost = 5, maxQuantity = 10, image = 'tosti.png' },
				{ name = 'sandwich', label = 'Sandwich', category = 'Food', price = 12, cost = 6, maxQuantity = 10, image = 'sandwich.png' },
				{ name = 'cigarette_pack', label = 'Cigarettes', category = 'Smoking', price = 22, cost = 11, maxQuantity = 10, image = 'cigarette_pack.png' },
				{ name = 'lighter', label = 'Lighter', category = 'Smoking', price = 6, cost = 3, maxQuantity = 15, image = 'lighter.png' },
			},
		},

		trucking = {
			enabled = true,
			title = '24/7 Innocence Supplies',
			cargoType = 'Store Supplies',
			cargoQuantityLabel = 'cases',
			requiredTrailer = nil,
			payoutRate = 0.12,
			payoutMin = 250,
			pickup = { label = 'Wholesale Distributor', coords = vector4(1012.4, -2520.7, 28.31, 92.0) },
			dropoff = { label = '24/7 Innocence', coords = vector3(24.82, -1346.19, 29.50) },
		},
	},

	ltd = {
		id = 'ltd',
		label = 'LTD Gasoline - Great Ocean Hwy',
		type = 'chain',

		purchase = {
			propModel = 'prop_forsale_lrg_04',
			coords = vector4(1161.31, -322.70, 69.21, 99.67),
			price = 0,
			moneyType = 'bank',
		},

		npc = {
			coords = vector4(1164.81, -323.70, 69.21, 99.67),
			model = 'mp_m_shopkeep_01',
		},

		blip = {
			enabled = true,
			sprite = 52,
			scale = 0.8,
			color = 5,
			label = 'LTD Great Ocean',
		},

		supplyItems = {},

		storefront = {
			enabled = true,
			moneyTypes = { 'cash', 'bank' },
			defaultMoneyType = 'cash',
			brand = {
				color = '#eab308', -- yellow
				logo = nil,
			},
			categories = {
				'Drinks',
				'Snacks',
				'Food',
				'Automotive',
			},
			items = {
				{ name = 'water_bottle', label = 'Water', category = 'Drinks', price = 8, cost = 3, maxQuantity = 10, image = 'water_bottle.png' },
				{ name = 'kurkakola', label = 'Cola', category = 'Drinks', price = 12, cost = 5, maxQuantity = 10, image = 'cola.png' },
				{ name = 'coffee', label = 'Coffee', category = 'Drinks', price = 15, cost = 6, maxQuantity = 10, image = 'coffee.png' },
				{ name = 'iced_tea', label = 'Iced Tea', category = 'Drinks', price = 12, cost = 5, maxQuantity = 10, image = 'iced_tea.png' },
				{ name = 'beer', label = 'Beer', category = 'Drinks', price = 18, cost = 9, maxQuantity = 12, image = 'beer.png' },
				{ name = 'twerks_candy', label = 'Twerks Candy', category = 'Snacks', price = 8, cost = 3, maxQuantity = 20, image = 'twerks_candy.png' },
				{ name = 'snikkel_candy', label = 'Snikkel Candy', category = 'Snacks', price = 8, cost = 3, maxQuantity = 20, image = 'snikkel_candy.png' },
				{ name = 'tosti', label = 'Grilled Cheese', category = 'Food', price = 10, cost = 5, maxQuantity = 10, image = 'tosti.png' },
				{ name = 'sandwich', label = 'Sandwich', category = 'Food', price = 12, cost = 6, maxQuantity = 10, image = 'sandwich.png' },
				{ name = 'repairkit', label = 'Repair Kit', category = 'Automotive', price = 150, cost = 75, maxQuantity = 3, image = 'repairkit.png' },
				{ name = 'tirerepairkit', label = 'Tire Repair Kit', category = 'Automotive', price = 75, cost = 38, maxQuantity = 4, image = 'tirerepairkit.png' },
			},
		},

		trucking = {
			enabled = true,
			title = 'LTD Great Ocean Supplies',
			cargoType = 'Store Supplies',
			cargoQuantityLabel = 'cases',
			requiredTrailer = nil,
			payoutRate = 0.12,
			payoutMin = 250,
			pickup = { label = 'Wholesale Distributor', coords = vector4(1012.4, -2520.7, 28.31, 92.0) },
			dropoff = { label = 'LTD Great Ocean', coords = vector3(1163.33, -324.01, 69.21) },
		},
	},
}

-- Shared supply orders (server_orders.lua): suppliers, truckers and AI fallbacks
Config.SupplyChain = {
    PlayerSuppliers = true,             -- offer delivery orders to registered player suppliers first
    SupplierOfferSeconds = 120,         -- how long player suppliers have before the AI supplier fills it
    AIMarkup = 0.15,                    -- buyers pay this much extra for AI supply (held, refunded in part if a player supplies)
    PlayerSupplierShareOfMarkup = 0.5,  -- share of that markup a player supplier earns; the rest goes back to the buyer
    DriverPrioritySeconds = 300,        -- player truckers get the contract first for this long
    DriverMaxSeconds = 3600,            -- a claimed delivery not finished in this time goes back to the pool
    AIDeliverySeconds = 600,            -- travel time of an AI delivery
    PalletModel = 'prop_boxpile_06b',   -- the delivery pallet (pfm-worldobjects)
    CaseSize = {},                      -- items per case a supplier stocks, e.g. { sandwich = 10 } (default 1)
    StockFreshness = { fresh = true, good = true }, -- food a supplier may stock (stale/spoiled refused)
}
