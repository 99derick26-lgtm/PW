-- utils/enemies.lua
-- Pixel War Online — Arena Enemy Generator
--
-- Usage:
--   local enemies = require("utils.enemies")
--
--   -- Generate a fresh board of 8 enemies
--   local board = enemies.generateBoard(player, difficulty)
--   -- difficulty: "normal" | "hard" | "extreme"
--
--   -- Each enemy table looks like:
--   {
--     name       = "Street Brawler Zara",
--     class      = "Street Brawler",
--     level      = 5,
--     stats      = { hp=120, attack=18, defense=12, speed=14 },
--     maxHp      = 120,
--     weapons    = { "dagger_basic" },   -- same weapon IDs as player
--     skin       = "street_brawler",     -- sprite folder name
--     defeated   = false,
--   }
--
--   -- Energy helpers (call these from arena/arena_battle)
--   enemies.hasEnergy(player)            -- bool
--   enemies.spendEnergy(player)          -- deducts 1, returns true/false
--   enemies.calcEnergy(player)           -- returns current energy int (with tick)
--
--   -- Board persistence (stored in player.arenaBoard)
--   enemies.saveBoard(player, board)
--   enemies.loadBoard(player)            -- returns board or nil
--   enemies.isBoardCleared(board)        -- true when all 8 defeated
--   enemies.rerollIfCleared(player)      -- rerolls if cleared, returns board

local M = {}

-------------------------------------------------
-- ENERGY CONFIG (matches home.lua)
-------------------------------------------------
local ENERGY_MAX      = 30
local ENERGY_INTERVAL = 16 * 60   -- seconds per tick

-------------------------------------------------
-- DIFFICULTY LEVEL OFFSETS
-------------------------------------------------
-- normal  = player level
-- hard    = player level + 1  (unlocks at player level 10)
-- extreme = player level + 3  (unlocks at player level 20)
local DIFFICULTY_OFFSET = {
    normal  = 0,
    hard    = 1,
    extreme = 3,
}

-------------------------------------------------
-- CLASSES
-- Each class has: a display name, a skin ID, stat weights,
-- and weapon pools per tier (unlocked at certain levels)
-------------------------------------------------
local CLASSES = {
    {
        name    = "Street Brawler",
        skin    = "street_brawler",
        weights = { hp=1.4, attack=1.2, defense=0.8, speed=1.0 },
        weapons = {
            [1]  = { "dagger_basic" },
            [5]  = { "dagger_basic", "scrap_gun" },
            [10] = { "dagger_basic", "scrap_gun", "katana_speed" },
            [15] = { "katana_speed", "scrap_gun" },
            [20] = { "katana_speed", "scrap_gun", "plasma_blade" },
        },
    },
    {
        name    = "Cyber Sniper",
        skin    = "cyber_sniper",
        weights = { hp=0.9, attack=1.5, defense=0.7, speed=1.1 },
        weapons = {
            [1]  = { "scrap_gun" },
            [5]  = { "scrap_gun", "rail_pistol" },
            [10] = { "rail_pistol", "shock_rifle" },
            [15] = { "shock_rifle", "rail_pistol" },
            [20] = { "shock_rifle", "pulse_cannon" },
        },
    },
    {
        name    = "Iron Guard",
        skin    = "iron_guard",
        weights = { hp=1.6, attack=0.9, defense=1.5, speed=0.7 },
        weapons = {
            [1]  = { "dagger_basic" },
            [5]  = { "dagger_basic", "iron_club" },
            [10] = { "iron_club", "riot_shield_spike" },
            [15] = { "riot_shield_spike", "iron_club" },
            [20] = { "riot_shield_spike", "heavy_maul" },
        },
    },
    {
        name    = "Shadow Rogue",
        skin    = "shadow_rogue",
        weights = { hp=0.8, attack=1.3, defense=0.8, speed=1.6 },
        weapons = {
            [1]  = { "dagger_basic" },
            [5]  = { "dagger_basic", "shadow_blade" },
            [10] = { "shadow_blade", "twin_daggers" },
            [15] = { "twin_daggers", "shadow_blade" },
            [20] = { "twin_daggers", "void_knife" },
        },
    },
    {
        name    = "Tech Mauler",
        skin    = "tech_mauler",
        weights = { hp=1.2, attack=1.3, defense=1.0, speed=0.9 },
        weapons = {
            [1]  = { "scrap_gun" },
            [5]  = { "scrap_gun", "shock_fist" },
            [10] = { "shock_fist", "arc_hammer" },
            [15] = { "arc_hammer", "shock_fist" },
            [20] = { "arc_hammer", "gravity_crusher" },
        },
    },
    {
        name    = "Neon Witch",
        skin    = "neon_witch",
        weights = { hp=0.85, attack=1.4, defense=0.75, speed=1.2 },
        weapons = {
            [1]  = { "scrap_gun" },
            [5]  = { "scrap_gun", "hex_staff" },
            [10] = { "hex_staff", "void_wand" },
            [15] = { "void_wand", "hex_staff" },
            [20] = { "void_wand", "chaos_orb" },
        },
    },
}

-------------------------------------------------
-- FIRST NAMES per class (6 per class, indexes match CLASSES)
-------------------------------------------------
local CLASS_NAMES = {
    -- Street Brawler
    { "Zara", "Knux", "Brix", "Doza", "Reck", "Thud" },
    -- Cyber Sniper
    { "Vex", "Lyra", "Pix", "Null", "Echo", "Dart" },
    -- Iron Guard
    { "Bron", "Grak", "Slab", "Weld", "Torq", "Helm" },
    -- Shadow Rogue
    { "Nyx", "Slip", "Fade", "Wraith", "Cinder", "Haze" },
    -- Tech Mauler
    { "Bolt", "Grind", "Fuse", "Amps", "Crank", "Volt" },
    -- Neon Witch
    { "Sable", "Rune", "Omen", "Flick", "Glitch", "Hex" },
}

-------------------------------------------------
-- STAT BASE FORMULA
-- Base stat at level 1, scaling per level
-------------------------------------------------
local BASE_HP      = 100
local BASE_ATK     = 100
local BASE_DEF     = 100
local BASE_SPD     = 100
local function calcBaseStats(level)
    local hp = BASE_HP
    local atk = BASE_ATK
    local def = BASE_DEF
    local spd = BASE_SPD

    for currentLevel = 2, level do
        local totalPoints = currentLevel <= 10 and 20 or 30
        local hpGain = math.floor(totalPoints * 0.40)
        local statGain = math.floor((totalPoints - hpGain) / 3)
        hp = hp + hpGain
        atk = atk + statGain
        def = def + statGain
        spd = spd + statGain
    end

    return hp, atk, def, spd
end

-- Small random variance ±10%
local function vary(val)
    return math.floor(val * (0.90 + math.random() * 0.20))
end

local function calcStats(level, weights)
    local baseHp, baseAtk, baseDef, baseSpd = calcBaseStats(level)
    local hp  = vary(baseHp * weights.hp)
    local atk = vary(baseAtk * weights.attack)
    local def = vary(baseDef * weights.defense)
    local spd = vary(baseSpd * weights.speed)
    -- floor minimums
    hp  = math.max(hp,  80)
    atk = math.max(atk,  80)
    def = math.max(def,  80)
    spd = math.max(spd,  80)
    return { hp=hp, attack=atk, defense=def, speed=spd }
end

-------------------------------------------------
-- WEAPON SELECTION
-- Pick the highest-tier weapon pool the enemy qualifies for
-------------------------------------------------
local function pickWeapons(classDef, level)
    local bestTier = 1
    for tier, _ in pairs(classDef.weapons) do
        if level >= tier and tier > bestTier then
            bestTier = tier
        end
    end
    local pool = classDef.weapons[bestTier]
    -- pick 1–2 weapons from pool
    local count = math.min(#pool, level >= 10 and 2 or 1)
    local chosen = {}
    local used   = {}
    for _ = 1, count do
        local tries = 0
        repeat
            local idx = math.random(1, #pool)
            if not used[idx] then
                chosen[#chosen+1] = pool[idx]
                used[idx] = true
                break
            end
            tries = tries + 1
        until tries > 10
    end
    if #chosen == 0 then chosen = { pool[1] } end
    return chosen
end

-------------------------------------------------
-- GENERATE ONE ENEMY
-------------------------------------------------
local function generateEnemy(level, slotIndex)
    -- pick class — slot 8 always picks a "heavy" class for end boss feel
    local classIdx
    if slotIndex == 8 then
        -- bias toward tanky/strong classes (Iron Guard, Tech Mauler)
        local heavies = { 3, 5 }
        classIdx = heavies[math.random(1, #heavies)]
    else
        classIdx = math.random(1, #CLASSES)
    end

    local classDef  = CLASSES[classIdx]
    local namePool  = CLASS_NAMES[classIdx]
    local firstName = namePool[math.random(1, #namePool)]
    local fullName  = classDef.name .. " " .. firstName

    local stats   = calcStats(level, classDef.weights)
    local weapons = pickWeapons(classDef, level)

    return {
        name     = fullName,
        class    = classDef.name,
        level    = level,
        stats    = stats,
        maxHp    = stats.hp,
        weapons  = weapons,
        skin     = classDef.skin,
        defeated = false,
    }
end

-------------------------------------------------
-- GENERATE BOARD (8 enemies)
-------------------------------------------------
function M.generateBoard(player, difficulty)
    difficulty = difficulty or "normal"
    local offset  = DIFFICULTY_OFFSET[difficulty] or 0
    local baseLevel = (player.level or 1) + offset

    local board = {}
    for i = 1, 8 do
        local enemyLevel = math.max(1, baseLevel)
        board[i] = generateEnemy(enemyLevel, i)
    end
    return board
end

-------------------------------------------------
-- BOARD PERSISTENCE
-------------------------------------------------
function M.saveBoard(player, board)
    player.arenaBoard = board
end

function M.loadBoard(player)
    return player.arenaBoard
end

function M.isBoardCleared(board)
    if not board or #board == 0 then return true end
    for _, e in ipairs(board) do
        if not e.defeated then return false end
    end
    return true
end

-- Call at arena open: rerolls if cleared (or no board yet), returns current board
function M.rerollIfCleared(player, difficulty)
    local board = M.loadBoard(player)
    if not board or M.isBoardCleared(board) then
        board = M.generateBoard(player, difficulty)
        M.saveBoard(player, board)
    end
    return board
end

-------------------------------------------------
-- ENERGY HELPERS
-------------------------------------------------
function M.calcEnergy(player)
    player.energy   = player.energy   or ENERGY_MAX
    player.energyTs = player.energyTs or os.time()

    if player.energy < ENERGY_MAX then
        local elapsed = os.time() - player.energyTs
        local gained  = math.floor(elapsed / ENERGY_INTERVAL)
        if gained > 0 then
            player.energy   = math.min(player.energy + gained, ENERGY_MAX)
            player.energyTs = player.energyTs + gained * ENERGY_INTERVAL
        end
    end
    return player.energy
end

function M.hasEnergy(player)
    return M.calcEnergy(player) > 0
end

-- Deduct 1 energy. Returns true if successful, false if out of energy.
function M.spendEnergy(player)
    M.calcEnergy(player)   -- tick first
    if player.energy <= 0 then return false end
    player.energy = player.energy - 1
    -- if full before deduction we need to start the refill clock
    if player.energy == ENERGY_MAX - 1 then
        player.energyTs = os.time()
    end
    return true
end

function M.energyMax()
    return ENERGY_MAX
end

function M.energyInterval()
    return ENERGY_INTERVAL
end

-------------------------------------------------
-- DIFFICULTY UNLOCK LEVELS
-------------------------------------------------
function M.difficultyUnlocked(player, difficulty)
    local level = player.level or 1
    if difficulty == "normal"  then return true end
    if difficulty == "hard"    then return level >= 10 end
    if difficulty == "extreme" then return level >= 20 end
    return false
end

return M
