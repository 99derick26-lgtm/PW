print("ITEMS.LUA LOADED")

local items = {

-- =========================
-- WEAPONS
-- =========================
dagger_basic = {
    id = "dagger_basic", name = "Dagger", slot = "weapon",
    icon = "assets/sprites/weapons/dagger_basic.png",
    statPercent = { attack = { min = 0.05, max = 0.10 } },
    requiredLevel = 1, description = "A simple blade. Light, quick, and reliable.",
    price = 300, auctionPrice = 150, sellPercent = 0.2,
},

short_sword = {
    id = "short_sword", name = "Short Sword", slot = "weapon",
    icon = "assets/sprites/weapons/short_sword.png",
    statPercent = { attack = { min = 0.10, max = 0.15 } },
    requiredLevel = 4, description = "A compact sword for quick close-range fights.",
    price = 400, auctionPrice = 200, sellPercent = 0.2,
},

heavy_stick = {
    id = "heavy_stick", name = "Heavy Stick", slot = "weapon",
    icon = "assets/sprites/weapons/crowbar.png",
    statPercent = { attack = { min = 0.10, max = 0.30 }, speed = -0.10 },
    requiredLevel = 5, description = "Simple, heavy, and unpleasant to get hit by.",
    price = 500, auctionPrice = 250, sellPercent = 0.2,
},


spear = {
    id = "spear", name = "Spear", slot = "weapon",
    icon = "assets/sprites/weapons/extending_spear.png",
    statPercent = { attack = { min = 0.20, max = 0.30 } },
    requiredLevel = 6, description = "Reach and control in one clean line.",
    price = 600, auctionPrice = 300, sellPercent = 0.2,
},

machette_basic = {
    id = "machette_basic", name = "Machete", slot = "weapon",
    icon = "assets/sprites/weapons/machette.png",
    statPercent = { attack = { min = 0.20, max = 0.30 }, speed = -0.10 },
    requiredLevel = 6, description = "A rough blade with real bite.",
    price = 550, auctionPrice = 275, sellPercent = 0.2,
},

katana_speed = {
    id = "katana_speed", name = "Katana", slot = "weapon",
    icon = "assets/sprites/weapons/katana_speed.png",
    statPercent = { attack = { min = 0.15, max = 0.30 }, defense = 0.10 },
    requiredLevel = 7, description = "A razor-sharp blade built for swift strikes.",
    price = 700, auctionPrice = 350, sellPercent = 0.2,
},

scrap_trident = {
    id = "scrap_trident", name = "Trident", slot = "weapon",
    icon = "assets/sprites/weapons/scrap_trident.png.png",
    statPercent = { attack = { min = 0.30, max = 0.40 }, speed = -0.10 },
    requiredLevel = 10, description = "A three-pronged weapon with nasty reach.",
    price = 800, auctionPrice = 400, sellPercent = 0.2,
},

scrap_gun = {
    id = "scrap_gun", name = "Pistol", slot = "weapon", ranged = true,
    icon = "assets/sprites/weapons/scrap_gun.png",
    statPercent = { attack = { min = 0.20, max = 0.30 } },
    requiredLevel = 10, description = "A compact ranged sidearm.",
    price = 600, auctionPrice = 300, sellPercent = 0.2,
},

energy_pistol = {
    id = "energy_pistol", name = "Energy Pistol", slot = "weapon", ranged = true,
    icon = "assets/sprites/weapons/energy pistol.png",
    statPercent = { attack = { min = 0.50, max = 0.60 } },
    requiredLevel = 10, description = "An upgraded pistol with clean energy output.",
    hiddenFromShop = true, price = 3000, auctionPrice = 3000, sellPercent = 0.2,
    upgradeFrom = "scrap_gun",
    upgradeCost = "C-60, M-10, A-20, GC-1",
},

plasma_gun = {
    id = "plasma_gun", name = "Plasma Pistol", slot = "weapon", ranged = true,
    icon = "assets/sprites/weapons/plasma_gun.png",
    statPercent = { attack = { min = 0.80, max = 1.00 } },
    requiredLevel = 18, description = "A bright plasma pistol with heavy punch.",
   hiddenFromShop = true, price = 4500, auctionPrice = 4500, sellPercent = 0.4,
    upgradeFrom = "energy_pistol",
    upgradeCost = "C-100, M-20, A-50, BC-1",
},

power_plasma_pistol = {
    id = "power_plasma_pistol", name = "Power Plasma Pistol", slot = "weapon", ranged = true, hits = 2,
    icon = "assets/sprites/weapons/tachyon pistol.png",
    statPercent = { attack = { min = 0.60, max = 0.70 } },
    requiredLevel = 24, description = "A tuned plasma pistol that can strike twice.",
    hiddenFromShop = true, price = 7500, auctionPrice = 7500, sellPercent = 0.4,
    upgradeFrom = "plasma_gun",
    upgradeCost = "C-150, A-100, M-50, PC-2, D-30",
},

helium_blaster = {
    id = "helium_blaster", name = "Helium Blaster", slot = "weapon", ranged = true,
    icon = "assets/sprites/weapons/helium blaster.png",
    statPercent = { attack = { min = 1.30, max = 1.50 } },
    requiredLevel = 30, description = "A high-pressure blaster with brutal force.",
    hiddenFromShop = true, price = 8500, auctionPrice = 8500, sellPercent = 0.4,
    upgradeFrom = "power_plasma_pistol",
    upgradeCost = "C-200, A-150, M-80, BC-4, D-60",
},

heavy_axe = {
    id = "heavy_axe", name = "Axe", slot = "weapon",
    icon = "assets/sprites/weapons/heavy_axe.png",
    statPercent = { attack = { min = 0.10, max = 0.60 }, defense = -0.10, speed = -0.20 },
    requiredLevel = 12, description = "Brutal and unforgiving. Every swing counts.",
    auctionPrice = 450, price = 900, sellPercent = 0.2,
},

tech_hammer = {
    id = "tech_hammer", name = "Titanium Hammer", slot = "weapon",
    icon = "assets/sprites/weapons/stone_hammer.png",
    statPercent = { attack = { min = 0.10, max = 0.80 }, defense = -0.10, speed = -0.30 },
    requiredLevel = 1, description = "A heavy hammer that trades speed for impact.",
    auctionPrice = 500, price = 1000, sellPercent = 0.2,
},

sickle = {
    id = "sickle", name = "Carbon Sickle", slot = "weapon",
    icon = "assets/sprites/weapons/sickle.png",
    statPercent = { attack = { min = 0.20, max = 0.70 } },
    requiredLevel = 13, description = "A curved carbon blade made for clean cuts.",
    auctionPrice = 2000, price = 2000, sellPercent = 0.2,
},

energy_sickle = {
    id = "energy_sickle", name = "Energy Sickle", slot = "weapon",
    icon = "assets/sprites/weapons/energy_sickle.png",
    statPercent = { attack = { min = 0.40, max = 0.90 }, defense = 0.10 },
    requiredLevel = 15, description = "A carbon sickle charged with energy.",
    hiddenFromShop = true, price = 2500, auctionPrice = 2500, sellPercent = 0.2,
    upgradeFrom = "sickle",
    upgradeCost = "C-50, A-80, M-50, GC-3, D-15",
},

radiation_sickle = {
    id = "radiation_sickle", name = "Radiation Sickle", slot = "weapon",
    icon = "assets/sprites/weapons/radiation_sickle.png",
    statPercent = { attack = { min = 0.60, max = 1.20 }, defense = 0.10 },
    requiredLevel = 22, description = "A sickle pulsing with unstable radiation.",
    hiddenFromShop = true, price = 5000, auctionPrice = 5000, sellPercent = 0.2,
    upgradeFrom = "energy_sickle",
    upgradeCost = "C-100, A-150, M-100, OC-4, D-40",
},

annihilation_sickle = {
    id = "annihilation_sickle", name = "Annihilation Sickle", slot = "weapon",
    icon = "assets/sprites/weapons/annihilation_sickle.png",
    statPercent = { attack = { min = 0.80, max = 2.60 }, defense = 0.20 },
    requiredLevel = 30, description = "A violent endgame sickle built for deletion.",
    hiddenFromShop = true, price = 7500, auctionPrice = 7500, sellPercent = 0.2,
    upgradeFrom = "radiation_sickle",
    upgradeCost = "C-300, A-500, M-300, PC-6, D-80",
},

pipe_crusher = {
    id = "pipe_crusher", name = "Pipe Crusher", slot = "weapon",
    icon = "assets/sprites/weapons/pipecrusher.png",
    statPercent = { attack = { min = 0.10, max = 0.90 }, speed = -0.30 },
    requiredLevel = 14, description = "Slow, ugly, and built to flatten armor.",
    price = 1500, auctionPrice = 750, sellPercent = 0.2,
},

heavy_sword = {
    id = "heavy_sword", name = "Heavy Sword", slot = "weapon",
    icon = "assets/sprites/weapons/heavy_sword.png",
    statPercent = { attack = { min = 0.40, max = 0.50 }, defense = 0.10, speed = -0.10 },
    requiredLevel = 15, description = "A massive sword that trades speed for raw power.",
    auctionPrice = 600, price = 1200, sellPercent = 0.2,
},

plasma_sword = {
    id = "plasma_sword", name = "Golden Sword", slot = "weapon",
    icon = "assets/sprites/weapons/golden_sword.png",
    statPercent = { attack = { min = 0.60, max = 0.70 }, defense = 0.15 },
    requiredLevel = 18, description = "A gold-framed blade with plasma heat.",
    hiddenFromShop = true, price = 4000, auctionPrice = 4000, sellPercent = 0.2,
    upgradeFrom = "heavy_sword",
    upgradeCost = "C-10, A-30, M-20, OC-1",
},

helium_blade = {
    id = "helium_blade", name = "Helium Blade", slot = "weapon", freeze = true,
    icon = "assets/sprites/weapons/helium_blade.png",
    statPercent = { attack = { min = 0.80, max = 0.90 }, defense = 0.20 },
    requiredLevel = 22, description = "A freezing blade powered by helium flow.",
    hiddenFromShop = true, price = 4500, auctionPrice = 4500, sellPercent = 0.2,
    upgradeFrom = "plasma_sword",
    upgradeCost = "C-60, A-80, M-100, BC-2",
},

green_axe = {
    id = "green_axe", name = "Energy Axe", slot = "weapon",
    icon = "assets/sprites/weapons/green_axe-export.png",
    statPercent = { attack = { min = 0.40, max = 1.10 } },
    requiredLevel = 15, description = "A green energy axe with a clean bite.",
    hiddenFromShop = true, price = 2500, auctionPrice = 2500, sellPercent = 0.2,
    upgradeFrom = "heavy_axe",
    upgradeCost = "C-100, A-100, M-50, GC-2",
},

plasma_axe = {
    id = "plasma_axe", name = "Plasma Axe", slot = "weapon",
    icon = "assets/sprites/weapons/blue_axe.png",
    statPercent = { attack = { min = 0.60, max = 1.80 } },
    requiredLevel = 20, description = "An axe head burning with plasma force.",
    hiddenFromShop = true, price = 4000, auctionPrice = 4000, sellPercent = 0.2,
    upgradeFrom = "green_axe",
    upgradeCost = "C-200, A-200, M-100, BC-3, D-20",
},

dirac_axe = {
    id = "dirac_axe", name = "Dirac Axe", slot = "weapon",
    icon = "assets/sprites/weapons/purple_axe-export.png",
    statPercent = { attack = { min = 0.80, max = 2.40 } },
    requiredLevel = 28, description = "A purple axe tuned past normal matter.",
    hiddenFromShop = true, price = 7500, auctionPrice = 7500, sellPercent = 0.2,
    upgradeFrom = "plasma_axe",
    upgradeCost = "C-400, A-400, M-200, PC-6, D-60",
},

ice_burst_blade = {
    id = "ice_burst_blade", name = "Ice Burst Blade", slot = "weapon",
    icon = "assets/sprites/weapons/blue_plasma_blade.png",
    statPercent = { attack = { min = 0.60, max = 0.70 }, defense = 0.10 },
    requiredLevel = 16, description = "A blue blade that bursts with icy force.",
    hiddenFromShop = true, price = 3000, auctionPrice = 3000, sellPercent = 0.2,
},

scrap_flamethrower = {
    id = "scrap_flamethrower", name = "Scrap Flamethrower", slot = "weapon", ranged = true, attacksAll = true,
    icon = "assets/sprites/weapons/scrap_flamethrower.png",
    statPercent = { attack = { min = 0.30, max = 0.50 }, defense = -0.10 },
    requiredLevel = 25, description = "A homemade flamethrower that can pressure all enemies.",
     price = 3500, auctionPrice = 3500, sellPercent = 0.2,
},

executioner = {
    id = "executioner", name = "Executioner", slot = "weapon",
    icon = "assets/sprites/weapons/executioner.png",
    statPercent = { attack = { min = 0.80, max = 1.20 }, defense = 0.10 },
    requiredLevel = 19, description = "A vicious blade made for ending fights.",
    hiddenFromShop = true, price = 6000, auctionPrice = 6000, sellPercent = 0.4,
    upgradeFrom = "pipe_crusher",
    upgradeCost = "C-20, A-50, M-3, BC-1",
},

holy_executioner = {
    id = "holy_executioner", name = "Holy Executioner", slot = "weapon",
    icon = "assets/sprites/weapons/holy_exuctioner.png",
    statPercent = { attack = { min = 1.00, max = 1.40 }, defense = 0.20 },
    requiredLevel = 26, description = "An executioner blade reforged with holy light.",
    hiddenFromShop = true, price = 11000, auctionPrice = 11000, sellPercent = 0.4,
    upgradeFrom = "executioner",
    upgradeCost = "C-100, A-200, M-100, OC-2",
},

mammoth_executioner = {
    id = "mammoth_executioner", name = "Mammoth Executioner", slot = "weapon",
    icon = "assets/sprites/weapons/mammoth executioner.png",
    statPercent = { attack = { min = 1.20, max = 1.60 }, defense = 0.25 },
    requiredLevel = 32, description = "A colossal executioner blade for heavy finishers.",
    hiddenFromShop = true, price = 15000, auctionPrice = 15000, sellPercent = 0.4,
    upgradeFrom = "holy_executioner",
    upgradeCost = "C-150, A-400, M-150, PC-3",
},

rocket_launcher = {
    id = "rocket_launcher", name = "Rocket Launcher", slot = "weapon", ranged = true,
    icon = "assets/sprites/weapons/rocket.png",
    statPercent = { attack = { min = 0.40, max = 0.70 } },
    requiredLevel = 32, description = "A launcher held together by nerve and bolts.",
    price = 5000, auctionPrice = 5000, sellPercent = 0.2,
},

green_energy_blade = {
    id = "green_energy_blade", name = "Green Energy Blade", slot = "weapon",
    icon = "assets/sprites/weapons/green_plasma_blade.png",
    statPercent = { attack = { min = 0.70, max = 0.80 }, speed = 0.20 },
    requiredLevel = 20, description = "A clean energy edge that hums before it cuts.",
     price = 4000, auctionPrice = 4000, sellPercent = 0.2,
},

blue_plasma_blade = {
    id = "blue_plasma_blade", name = "Blue Plasma Blade", slot = "weapon",
    icon = "assets/sprites/weapons/blue_plasma_blade.png",
    statPercent = { attack = { min = 0.80, max = 0.90 }, speed = 0.25 },
    requiredLevel = 24, description = "A hotter blue blade with improved speed.",
    hiddenFromShop = true, price = 6000, auctionPrice = 6000, sellPercent = 0.4,
    upgradeFrom = "green_energy_blade",
    upgradeCost = "C-40, A-70, M-90, BC-1",
},

orange_particle_sword = {
    id = "orange_particle_sword", name = "Orange Particle Sword", slot = "weapon",
    icon = "assets/sprites/weapons/orange_plasma_blade.png",
    statPercent = { attack = { min = 0.90, max = 1.00 }, speed = 0.30 },
    requiredLevel = 28, description = "An orange blade stabilized with particle flow.",
    hiddenFromShop = true, price = 9000, auctionPrice = 9000, sellPercent = 0.2,
    upgradeFrom = "blue_plasma_blade",
    upgradeCost = "C-60, A-80, M-100, OC-1",
},

purple_cosmic_sword = {
    id = "purple_cosmic_sword", name = "Purple Cosmic Sword", slot = "weapon",
    icon = "assets/sprites/weapons/purple_plasma_blade.png",
    statPercent = { attack = { min = 1.00, max = 1.20 }, speed = 0.40 },
    requiredLevel = 34, description = "A cosmic plasma blade with extreme speed scaling.",
    hiddenFromShop = true, price = 9500, auctionPrice = 9500, sellPercent = 0.2,
    upgradeFrom = "orange_particle_sword",
    upgradeCost = "C-200, A-400, M-600, PC-2",
},
-- =========================
-- ARMOR
-- =========================
leather_helmet = {
    id = "leather_helmet",
    name = "Leather Helmet",
    slot = "helmet",
    icon = "assets/sprites/armor/leather_helmet.png",
    statPercent = {
        defense = 0.05,
        hp      = 0.05
    },
    requiredLevel = 2,
    description = "Basic head protection made from reinforced leather.",
    price = 400,
    sellPercent = 0.2
},

leather_chest = {
    id = "leather_chest",
    name = "Leather Jacket",
    slot = "chest",
    icon = "assets/sprites/armor/leather_chest.png",
    statPercent = {
        defense = 0.10,
        hp      = 0.10
    },
    requiredLevel = 5,
    description = "A lightweight jacket offering modest protection.",
    price = 600,
    sellPercent = 0.2
},

leather_gloves = {
    id = "leather_gloves",
    name = "Leather Gloves",
    slot = "gloves",
    icon = "assets/sprites/armor/leather_gloves.png",
    statPercent = {
        defense = 0.03,
        hp      = 0.04
    },
    requiredLevel = 4,
    description = "Simple gloves that provide minimal defense.",
    price = 300,
    sellPercent = 0.2
},

leather_boots = {
    id = "leather_boots",
    name = "Leather Boots",
    slot = "boots",
    icon = "assets/sprites/armor/leather_boots.png",
    statPercent = {
        defense = 0.03,
        hp      = 0.03,
        speed   = 0.15
    },
    requiredLevel = 5,
    description = "Sturdy boots that slightly improve movement speed.",
    price = 500,
    sellPercent = 0.2
},

combat_helmet = {
    id = "combat_helmet",
    name = "Combat Helmet",
    slot = "helmet",
    icon = "assets/sprites/armor/combat_helmet.png",
    statPercent = {
        defense = 0.10,
        hp      = 0.10
    },
    requiredLevel = 12,
    price = 400,
    auctionPrice = 400,
    sellPercent = 0.4
},

combat_chest = {
    id = "combat_chest",
    name = "Combat Armor",
    slot = "chest",
    icon = "assets/sprites/armor/combat_chest.png",
    statPercent = {
        defense = 0.20,
        hp      = 0.20
    },
    requiredLevel = 15,
    price = 650,
    auctionPrice = 650,
    sellPercent = 0.4
},

combat_gloves = {
    id = "combat_gloves",
    name = "Combat Gloves",
    slot = "gloves",
    icon = "assets/sprites/armor/combat_gloves.png",
    statPercent = {
        defense = 0.07,
        hp      = 0.10
    },
    requiredLevel = 10,
    price = 250,
    auctionPrice = 250,
    sellPercent = 0.4
},

combat_boots = {
    id = "combat_boots",
    name = "Combat Boots",
    slot = "boots",
    icon = "assets/sprites/armor/combat_boots.png",
    statPercent = {
        defense = 0.05,
        hp      = 0.05,
        speed   = 0.30
    },
    requiredLevel = 13,
    price = 600,
    auctionPrice = 600,
    sellPercent = 0.4
},

battle_helmet = {
    id = "battle_helmet",
    name = "Battle Helmet",
    slot = "helmet",
    icon = "assets/sprites/armor/battle_helmet.png",
    statPercent = { hp = 0.20, defense = 0.15 },
    requiredLevel = 16,
    hiddenFromShop = true,
    price = 2000,
    auctionPrice = 2000,
    sellPercent = 0.4,
    upgradeFrom = "combat_helmet",
    upgradeCost = "C-10, A-30, M-10, BC-1",
},

battle_chest = {
    id = "battle_chest",
    name = "Battle Armor",
    slot = "chest",
    icon = "assets/sprites/armor/battle_chest.png",
    statPercent = { hp = 0.60, defense = 0.30 },
    requiredLevel = 19,
    hiddenFromShop = true,
    price = 3500,
    auctionPrice = 3500,
    sellPercent = 0.4,
    upgradeFrom = "combat_chest",
    upgradeCost = "C-40, A-70, M-30, BC-1",
},

battle_gloves = {
    id = "battle_gloves",
    name = "Battle Gloves",
    slot = "gloves",
    icon = "assets/sprites/armor/battle_gloves.png",
    statPercent = { hp = 0.15, defense = 0.10 },
    requiredLevel = 14,
    hiddenFromShop = true,
    price = 1000,
    auctionPrice = 1000,
    sellPercent = 0.4,
    upgradeFrom = "combat_gloves",
    upgradeCost = "C-10, A-30, M-10, BC-1",
},

battle_boots = {
    id = "battle_boots",
    name = "Battle Boots",
    slot = "boots",
    icon = "assets/sprites/armor/battle_boots.png",
    statPercent = { hp = 0.15, defense = 0.10, speed = 0.35 },
    requiredLevel = 17,
    hiddenFromShop = true,
    price = 2500,
    auctionPrice = 2500,
    sellPercent = 0.4,
    upgradeFrom = "combat_boots",
    upgradeCost = "C-20, A-30, M-10, BC-1",
},

golden_helmet = {
    id = "golden_helmet",
    name = "Golden Helmet",
    slot = "helmet",
    icon = "assets/sprites/armor/golden_helmet.png",
    statPercent = { hp = 0.30, defense = 0.20 },
    requiredLevel = 20,
    hiddenFromShop = true,
    price = 3500,
    auctionPrice = 3500,
    sellPercent = 0.4,
    upgradeFrom = "battle_helmet",
    upgradeCost = "C-10, A-30, M-30, OC-1",
},

golden_armor = {
    id = "golden_armor",
    name = "Golden Armor",
    slot = "chest",
    icon = "assets/sprites/armor/golden_armor.png",
    statPercent = { hp = 0.70, defense = 0.40 },
    requiredLevel = 23,
    hiddenFromShop = true,
    price = 5500,
    auctionPrice = 5500,
    sellPercent = 0.4,
    upgradeFrom = "battle_chest",
    upgradeCost = "C-40, A-100, M-40, OC-1",
},

golden_gloves = {
    id = "golden_gloves",
    name = "Golden Gloves",
    slot = "gloves",
    icon = "assets/sprites/armor/golden_gloves.png",
    statPercent = { hp = 0.20, defense = 0.15 },
    requiredLevel = 18,
    hiddenFromShop = true,
    price = 2500,
    auctionPrice = 2500,
    sellPercent = 0.4,
    upgradeFrom = "battle_gloves",
    upgradeCost = "C-10, A-30, M-20, OC-1",
},

golden_boots = {
    id = "golden_boots",
    name = "Golden Boots",
    slot = "boots",
    icon = "assets/sprites/armor/golden_boots.png",
    statPercent = { hp = 0.20, defense = 0.15, speed = 0.45 },
    requiredLevel = 21,
    hiddenFromShop = true,
    price = 4500,
    auctionPrice = 4500,
    sellPercent = 0.4,
    upgradeFrom = "battle_boots",
    upgradeCost = "C-20, A-30, M-10, OC-1",
},

warrior_helmet = {
    id = "warrior_helmet",
    name = "Warrior Helmet",
    slot = "helmet",
    icon = "assets/sprites/armor/warrior_helmet.png",
    statPercent = { hp = 0.40, defense = 0.30 },
    requiredLevel = 24,
    hiddenFromShop = true,
    price = 7500,
    auctionPrice = 7500,
    sellPercent = 0.4,
    upgradeFrom = "golden_helmet",
    upgradeCost = "C-600, A-300, D-200, PC-2",
},

warrior_armor = {
    id = "warrior_armor",
    name = "Warrior Armor",
    slot = "chest",
    icon = "assets/sprites/armor/warrior_armor.png",
    statPercent = { hp = 0.80, defense = 0.50 },
    requiredLevel = 27,
    hiddenFromShop = true,
    price = 15000,
    auctionPrice = 15000,
    sellPercent = 0.4,
    upgradeFrom = "golden_armor",
    upgradeCost = "C-500, A-1000, M-600, PC-4",
},

warrior_gloves = {
    id = "warrior_gloves",
    name = "Warrior Gloves",
    slot = "gloves",
    icon = "assets/sprites/armor/Warrior_gloves.png",
    statPercent = { hp = 0.30, defense = 0.25 },
    requiredLevel = 22,
    hiddenFromShop = true,
    price = 5000,
    auctionPrice = 5000,
    sellPercent = 0.4,
    upgradeFrom = "golden_gloves",
    upgradeCost = "C-300, A-400, M-300, PC-1",
},

warrior_boots = {
    id = "warrior_boots",
    name = "Warrior Boots",
    slot = "boots",
    icon = "assets/sprites/armor/warrior_boots.png",
    statPercent = { hp = 0.20, defense = 0.20, speed = 0.50 },
    requiredLevel = 25,
    hiddenFromShop = true,
    price = 11000,
    auctionPrice = 11000,
    sellPercent = 0.4,
    upgradeFrom = "golden_boots",
    upgradeCost = "C-600, A-700, D-300, PC-3",
},

riot_helmet = {
    id = "riot_helmet",
    name = "Riot Helmet",
    slot = "helmet",
    icon = "assets/sprites/armor/riot_helmet.png",
    statPercent = {
        defense = 0.15,
        hp      = 0.15
    },
    requiredLevel = 16,
    price = 1000,
    sellPercent = 0.2
},

riot_chest = {
    id = "riot_chest",
    name = "Riot Chest",
    slot = "chest",
    icon = "assets/sprites/armor/riot_chest.png",
    statPercent = {
        defense = 0.26,
        hp      = 0.20,
        speed   = -0.05
    },
    requiredLevel = 20,
    price = 2000,
    sellPercent = 0.2
},

riot_gloves = {
    id = "riot_gloves",
    name = "Riot Gloves",
    slot = "gloves",
    icon = "assets/sprites/armor/riot_gloves.png",
    statPercent = {
        defense = 0.15,
        hp      = 0.12
    },
    requiredLevel = 14,
    price = 850,
    sellPercent = 0.2
},

riot_boots = {
    id = "riot_boots",
    name = "Riot Boots",
    slot = "boots",
    icon = "assets/sprites/armor/riot_boots.png",
    statPercent = {
        defense = 0.10,
        hp      = 0.10,
        speed   = 0.45
    },
    requiredLevel = 18,
    price = 1500,
    sellPercent = 0.2
},

-- =========================
-- NECKLACES
-- =========================
attack_necklace = {
    id           = "attack_necklace",
    name         = "Warrior's Pendant",
    slot         = "necklace",
    icon         = "assets/sprites/armor/attack_necklace.png",
    statPercent  = { attack = 0.15 },
    requiredLevel = 20,
    description  = "A fierce pendant that sharpens your blade instincts.",
    price        = 600,
    sellPercent  = 0.2
},

defense_necklace = {
    id           = "defense_necklace",
    name         = "Guardian's Pendant",
    slot         = "necklace",
    icon         = "assets/sprites/armor/defense_necklace.png",
    statPercent  = { defense = 0.15 },
    requiredLevel = 21,
    description  = "A reinforced pendant that toughens your resolve.",
    price        = 600,
    sellPercent  = 0.2
},

health_necklace = {
    id           = "health_necklace",
    name         = "Vitality Pendant",
    slot         = "necklace",
    icon         = "assets/sprites/armor/health_necklace.png",
    statPercent  = { hp = 0.15 },
    requiredLevel = 23,
    description  = "A glowing pendant that pulses with life energy.",
    price        = 600,
    sellPercent  = 0.2
},

speed_necklace = {
    id           = "speed_necklace",
    name         = "Swift Pendant",
    slot         = "necklace",
    icon         = "assets/sprites/armor/speed_necklace.png",
    statPercent  = { speed = 0.15 },
    requiredLevel = 22,
    description  = "A lightweight pendant that quickens your reflexes.",
    price        = 600,
    sellPercent  = 0.2
},

-- =========================
-- RINGS
-- =========================
attack_ring = {
    id           = "attack_ring",
    name         = "Berserker's Ring",
    slot         = "ring",
    icon         = "assets/sprites/armor/attack_ring.png",
    statPercent  = { attack = 0.15 },
    requiredLevel = 23,
    description  = "A crimson ring forged for those who live to fight.",
    price        = 750,
    sellPercent  = 0.2
},

defense_ring = {
    id           = "defense_ring",
    name         = "Bulwark Ring",
    slot         = "ring",
    icon         = "assets/sprites/armor/defense_ring.png",
    statPercent  = { defense = 0.15 },
    requiredLevel = 24,
    description  = "A heavy ring inscribed with protective runes.",
    price        = 750,
    sellPercent  = 0.2
},

health_ring = {
    id           = "health_ring",
    name         = "Life Ring",
    slot         = "ring",
    icon         = "assets/sprites/armor/health_ring.png",
    statPercent  = { hp = 0.15 },
    requiredLevel = 26,
    description  = "A green-stoned ring that pulses with healing energy.",
    price        = 750,
    sellPercent  = 0.2
},

speed_ring = {
    id           = "speed_ring",
    name         = "Quickstep Ring",
    slot         = "ring",
    icon         = "assets/sprites/armor/speed_ring.png",
    statPercent  = { speed = 0.15 },
    requiredLevel = 25,
    description  = "A gold ring that makes every step feel lighter.",
    price        = 750,
    sellPercent  = 0.2
},

-- =========================
-- CHARMS
-- =========================
attack_charm = {
    id           = "attack_charm",
    name         = "Fang Charm",
    slot         = "charm",
    icon         = "assets/sprites/armor/attack_charm.png",
    statPercent  = { attack = 0.15 },
    requiredLevel = 9,
    description  = "A jagged charm carved from a warrior's trophy.",
    price        = 900,
    sellPercent  = 0.2
},

defense_charm = {
    id           = "defense_charm",
    name         = "Shield Charm",
    slot         = "charm",
    icon         = "assets/sprites/armor/defense_charm.png",
    statPercent  = { defense = 0.15 },
    requiredLevel = 9,
    description  = "A charm shaped like a shield, worn for protection.",
    price        = 900,
    sellPercent  = 0.2
},

health_charm = {
    id           = "health_charm",
    name         = "Heart Charm",
    slot         = "charm",
    icon         = "assets/sprites/armor/health_charm.png",
    statPercent  = { hp = 0.15 },
    requiredLevel = 9,
    description  = "A heart-shaped charm that reinforces your life force.",
    price        = 900,
    sellPercent  = 0.2
},

speed_charm = {
    id           = "speed_charm",
    name         = "Wing Charm",
    slot         = "charm",
    icon         = "assets/sprites/armor/speed_charm.png",
    statPercent  = { speed = 0.15 },
    requiredLevel = 9,
    description  = "A golden wing charm that feels almost weightless.",
    price        = 900,
    sellPercent  = 0.2
},

-- =========================
-- MISC
-- =========================
digital_key = {
    id           = "digital_key",
    name         = "Digital Key",
    slot         = "misc",
    icon         = "assets/sprites/materials/digital_key.png",
    description  = "A one-use access key that opens Rare Chests.",
    price        = 50,
    requiredLevel = 1,
    sellPercent  = 0.2,
    stackable    = true
},

scrap = {
    id           = "scrap",
    name         = "Amorphous",
    slot         = "misc",
    type         = "material",
    materialKey  = "scrap",
    icon         = "assets/sprites/more/scrap.png",
    description  = "Unstable crafting material gathered from the materials flow.",
    price        = 10,
    requiredLevel = 2,
    sellPercent  = 0.2,
    stackable    = true
},

coil = {
    id           = "coil",
    name         = "Carbon Fiber",
    slot         = "misc",
    type         = "material",
    materialKey  = "coil",
    icon         = "assets/sprites/more/large_coil.png",
    description  = "Flexible crafting material used for stronger upgrades.",
    price        = 10,
    requiredLevel = 3,
    sellPercent  = 0.2,
    stackable    = true
},

chip = {
    id           = "chip",
    name         = "Micro-chips",
    slot         = "misc",
    type         = "material",
    materialKey  = "chip",
    icon         = "assets/sprites/more/chip.png",
    description  = "High-tech material for advanced progression systems.",
    price        = 10,
    requiredLevel = 4,
    sellPercent  = 0.2,
    stackable    = true
},

attk_injection = {
    id           = "attk_injection",
    name         = "Attack Injection",
    slot         = "misc",
    type         = "injection",
    injectionStat = "attack",
    boostPercent = 0.20,
    durationSeconds = 3600,
    cooldownSeconds = 21600,
    icon         = "assets/sprites/more/attk_injection.png",
    description  = "Boosts attack by 20% for 1 hour. Same injection cooldown: 6 hours.",
    price        = 300,
    requiredLevel = 10,
    sellPercent  = 0.2,
    stackable    = true
},

defense_injection = {
    id           = "defense_injection",
    name         = "Defense Injection",
    slot         = "misc",
    type         = "injection",
    injectionStat = "defense",
    boostPercent = 0.20,
    durationSeconds = 3600,
    cooldownSeconds = 21600,
    icon         = "assets/sprites/more/defense_injection.png",
    description  = "Boosts defense by 20% for 1 hour. Same injection cooldown: 6 hours.",
    price        = 300,
    requiredLevel = 10,
    sellPercent  = 0.2,
    stackable    = true
},

speed_injection = {
    id           = "speed_injection",
    name         = "Speed Injection",
    slot         = "misc",
    type         = "injection",
    injectionStat = "speed",
    boostPercent = 0.20,
    durationSeconds = 3600,
    cooldownSeconds = 21600,
    icon         = "assets/sprites/more/speed_injection.png",
    description  = "Boosts speed by 20% for 1 hour. Same injection cooldown: 6 hours.",
    price        = 300,
    requiredLevel = 10,
    sellPercent  = 0.2,
    stackable    = true
},

hp_injection = {
    id           = "hp_injection",
    name         = "HP Injection",
    slot         = "misc",
    type         = "injection",
    injectionStat = "hp",
    boostPercent = 0.20,
    durationSeconds = 3600,
    cooldownSeconds = 21600,
    icon         = "assets/sprites/more/hp_injection.png",
    description  = "Boosts HP by 20% for 1 hour. Same injection cooldown: 6 hours.",
    price        = 300,
    requiredLevel = 10,
    sellPercent  = 0.2,
    stackable    = true
},

all_injection = {
    id           = "all_injection",
    name         = "Overdrive",
    slot         = "misc",
    type         = "injection",
    injectionStat = "all",
    boostPercent = 0.05,
    durationSeconds = 3600,
    cooldownSeconds = 21600,
    icon         = "assets/sprites/more/all_injection.png",
    description  = "Boosts all stats by 5% for 1 hour. Overdrive cooldown: 6 hours.",
    price        = 500,
    requiredLevel = 15,
    sellPercent  = 0.2,
    stackable    = true
},

-- =========================
-- COSTUMES
-- =========================
corp_enforcer_costume = {
    id           = "corp_enforcer_costume",
    name         = "Corp Enforcer",
    slot         = "costume",
    skinId       = "corp_enforcer",
    icon         = "assets/sprites/characters/corp_enforcer/portrait.png",
    description  = "A polished corporate combat uniform.",
    price        = 1000,
    requiredLevel = 1,
    sellPercent  = 0.2
},

corp_enforcer_f_costume = {
    id           = "corp_enforcer_f_costume",
    name         = "Corp Enforcer F",
    slot         = "costume",
    skinId       = "corp_enforcer_f",
    icon         = "assets/sprites/characters/corp_enforcer_f/portrait.png",
    description  = "A sharp corporate field uniform.",
    price        = 1000,
    requiredLevel = 1,
    sellPercent  = 0.2
},

street_brawler_costume = {
    id           = "street_brawler_costume",
    name         = "Street Brawler",
    slot         = "costume",
    skinId       = "street_brawler",
    icon         = "assets/sprites/characters/street_brawler/portrait.png",
    description  = "Street-ready gear for close-up trouble.",
    price        = 1000,
    requiredLevel = 1,
    sellPercent  = 0.2
},

street_fighter_costume = {
    id           = "street_fighter_costume",
    name         = "Street Fighter",
    slot         = "costume",
    skinId       = "street_fighter",
    icon         = "assets/sprites/characters/street_fighter/portrait.png",
    description  = "A scrappy fighter look built for city fights.",
    price        = 1000,
    requiredLevel = 1,
    sellPercent  = 0.2
},

street_fighter_f_costume = {
    id           = "street_fighter_f_costume",
    name         = "Street Fighter F",
    slot         = "costume",
    skinId       = "street_fighter_f",
    icon         = "assets/sprites/characters/street_fighter_f/portrait.png",
    description  = "A nimble street fighter outfit.",
    price        = 1000,
    requiredLevel = 1,
    sellPercent  = 0.2
},

-- =========================
-- PETS (NO STAT PERCENT)
-- =========================
dog = {
    id = "dog",
    name = "Dog",
    slot = "pet",
    petId = "dog",
    description = "A loyal companion with balanced stats.",
    price = 1500,
    requiredLevel = 8,
    sellPercent = 0.2
},

cat = {
    id = "cat",
    name = "Cat",
    slot = "pet",
    petId = "cat",
    description = "Fast and agile, but not very tough.",
    price = 1000,
    requiredLevel = 3,
    sellPercent = 0.2
},

snake = {
    id = "snake",
    name = "Snake",
    slot = "pet",
    petId = "snake",
    description = "A sneaky pet with surprising speed.",
    price = 4500,
    requiredLevel = 14,
    sellPercent = 0.2
},

parrot = {
    id = "parrot",
    name = "Parrot",
    slot = "pet",
    petId = "parrot",
    description = "A clever companion that boosts awareness.",
    price = 3000,
    requiredLevel = 9,
    sellPercent = 0.2
},

horse = {
    id = "horse",
    name = "Horse",
    slot = "pet",
    petId = "horse",
    description = "A powerful mount that excels in endurance.",
    price = 2500,
    requiredLevel = 12,
    sellPercent = 0.2
},

capybara = {
    id = "capybara",
    name = "Capybara",
    slot = "pet",
    petId = "capybara",
    description = "Calm, tanky, and surprisingly resilient.",
    price = 2000,
    requiredLevel = 7,
    sellPercent = 0.2
},

cheetah = {
    id = "cheetah",
    name = "Cheetah",
    slot = "pet",
    petId = "cheetah",
    description = "Extremely fast, but fragile.",
    price = 2000,
    requiredLevel = 10,
    sellPercent = 0.2
},

panda = {
    id = "panda",
    name = "Panda",
    slot = "pet",
    petId = "panda",
    description = "Sturdy and calm with a defensive build.",
    price = 2000,
    requiredLevel = 10,
    sellPercent = 0.2
},

hippo = {
    id = "hippo",
    name = "Hippo",
    slot = "pet",
    petId = "hippo",
    description = "A massive pet with incredible durability.",
    price = 10000,
    requiredLevel = 18,
    sellPercent = 0.2
},

raccoon = {
    id = "raccoon",
    name = "Raccoon",
    slot = "pet",
    petId = "raccoon",
    description = "Tricky and adaptable, excels in utility.",
    price = 4000,
    requiredLevel = 14,
    sellPercent = 0.2
},

turtle = {
    id = "turtle",
    name = "Turtle",
    slot = "pet",
    petId = "turtle",
    description = "Slow but extremely tough.",
    price = 5000,
    requiredLevel = 14,
    sellPercent = 0.2
},

rhino = {
    id = "rhino",
    name = "Rhino",
    slot = "pet",
    petId = "rhino",
    description = "A heavy charger with strong all-around stats.",
    price = 7000,
    requiredLevel = 15,
    sellPercent = 0.2
},

guar = {
    id = "guar",
    name = "Guar",
    slot = "pet",
    petId = "guar",
    description = "Ancient, steady, and built for endurance.",
    price = 10000,
    requiredLevel = 16,
    sellPercent = 0.2
},

alligator = {
    id = "alligator",
    name = "Alligator",
    slot = "pet",
    petId = "alligator",
    description = "A brutal striker with huge raw power.",
    price = 20000,
    requiredLevel = 26,
    sellPercent = 0.2
},

polar_bear = {
    id = "polar_bear",
    name = "Polar Bear",
    slot = "pet",
    petId = "polar_bear",
    description = "Fast for its size and terrifying up close.",
    price = 17000,
    requiredLevel = 26,
    sellPercent = 0.2
},

elephant = {
    id = "elephant",
    name = "Elephant",
    slot = "pet",
    petId = "elephant",
    description = "Massive, durable, and powerful.",
    price = 20000,
    requiredLevel = 28,
    sellPercent = 0.2
},

tiger = {
    id = "tiger",
    name = "Tiger",
    slot = "pet",
    petId = "tiger",
    description = "A fierce hunter with high speed and attack.",
    price = 15000,
    requiredLevel = 24,
    sellPercent = 0.2
},

wasp = {
    id = "wasp",
    name = "Wasp",
    slot = "pet",
    petId = "wasp",
    description = "Fast and aggressive, but fragile.",
    price = 7000,
    requiredLevel = 13,
    sellPercent = 0.2
}

}

local function aliasItem(aliasId, targetId)
    local target = items[targetId]
    if not target then return end
    local copy = {}
    for k, v in pairs(target) do copy[k] = v end
    copy.id = aliasId
    copy.aliasOf = targetId
    copy.hiddenFromShop = true
    items[aliasId] = copy
end

aliasItem("crow_bar", "heavy_stick")
aliasItem("extended_spear", "spear")
aliasItem("stone_hammer", "tech_hammer")
aliasItem("monosickle", "sickle")
aliasItem("scrap_sniper", "energy_pistol")
aliasItem("green_plasma_blade", "green_energy_blade")
aliasItem("multi_use_torch", "scrap_flamethrower")
aliasItem("scrap_launcher", "rocket_launcher")
aliasItem("shield_bash", "pipe_crusher")

return items
