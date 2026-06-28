-- utils/enemy_generator.lua
-- Pixel War Online — Enemy Generator
--
-- Arena bots should feel like real players:
-- - legal level-appropriate gear only
-- - similar progression to the player
-- - small variance, not impossible loadouts

local M = {}
local items = require("utils.items")
local stats = require("utils.stats")
local spells = require("utils.spells")

local DIFFICULTY_LEVEL_OFFSET = {
    safe    = -2,
    easy    = -1,
    normal  =  0,
    hard    =  1,
    extreme =  2
}

--------------------------------------------------
-- DIFFICULTY BANDS (LOCKED)
--------------------------------------------------
local DIFFICULTY_BANDS = {
    easy   = 0.96,
    normal = 1.00,
    hard   = 1.06,
    elite  = 1.12
}

--------------------------------------------------
-- STAT BIAS TEMPLATES (LOCKED)
--------------------------------------------------
local STAT_BIASES = {
    balanced = {},
    attack   = { attack = 1.18, speed = 1.03 },
    defense  = { defense = 1.18, hp = 1.04 },
    speed    = { speed = 1.18, attack = 1.02 }
}

local SLOT_GROUPS = {
    weapon = "weapon",
    helmet = "armor",
    chest = "armor",
    gloves = "armor",
    boots = "armor",
    necklace = "accessories",
    ring = "accessories",
    charm = "accessories",
}

local ACCESSORY_UNLOCK_LEVEL = {
    necklace = 5,
    ring = 8,
    charm = 12,
}

local function avgStatValue(value)
    if type(value) == "table" then
        return ((value.min or 0) + (value.max or 0)) * 0.5
    end
    return value or 0
end

local function getItemScore(item, biasKey)
    local score = 0
    local itemStats = item.statPercent or {}
    local bias = STAT_BIASES[biasKey] or STAT_BIASES.balanced

    for stat, value in pairs(itemStats) do
        local avg = avgStatValue(value)
        local weight = bias[stat] or 1.0
        score = score + (avg * weight)
    end

    score = score + ((item.requiredLevel or 1) * 0.004)
    return score
end

local function getEligibleItemsForSlot(slot, level)
    local list = {}
    for itemId, item in pairs(items) do
        if item.slot == slot and (item.requiredLevel or 1) <= level then
            list[#list + 1] = itemId
        end
    end
    return list
end

local function sortCandidates(candidateIds, biasKey)
    table.sort(candidateIds, function(a, b)
        local itemA = items[a]
        local itemB = items[b]
        local scoreA = getItemScore(itemA, biasKey)
        local scoreB = getItemScore(itemB, biasKey)
        if scoreA ~= scoreB then return scoreA > scoreB end
        if (itemA.requiredLevel or 1) ~= (itemB.requiredLevel or 1) then
            return (itemA.requiredLevel or 1) > (itemB.requiredLevel or 1)
        end
        return a < b
    end)
end

local function pickFromTop(candidateIds, topN)
    if #candidateIds == 0 then return nil end
    local count = math.min(#candidateIds, topN or 3)
    if #candidateIds > count and math.random() < 0.08 then
        return candidateIds[math.random(count + 1, #candidateIds)]
    end
    return candidateIds[math.random(count)]
end

local function cloneList(src)
    local out = {}
    for i, v in ipairs(src or {}) do out[i] = v end
    return out
end

local function getLegalPetEntries(level)
    local entries = {}
    for itemId, item in pairs(items) do
        if item.slot == "pet" and item.petId and (item.requiredLevel or 1) <= level then
            entries[#entries + 1] = {
                petId = item.petId,
                requiredLevel = item.requiredLevel or 1,
            }
        end
    end
    table.sort(entries, function(a, b)
        if a.requiredLevel ~= b.requiredLevel then return a.requiredLevel > b.requiredLevel end
        return a.petId < b.petId
    end)
    return entries
end

local function pickUnique(source, count)
    local pool = cloneList(source)
    local chosen = {}
    for _ = 1, math.min(count, #pool) do
        local idx = math.random(#pool)
        chosen[#chosen + 1] = table.remove(pool, idx)
    end
    return chosen
end

local function weightedPickByLevel(entries, enemyLevel)
    if #entries == 0 then return nil end
    local total = 0
    local weights = {}
    for i, entry in ipairs(entries) do
        local req = entry.requiredLevel or 1
        local gap = math.max(0, enemyLevel - req)
        local weight = math.max(0.02, 1.8 - gap * 0.10)
        if req >= enemyLevel - 2 then
            weight = weight + 0.85
        elseif req >= enemyLevel - 5 then
            weight = weight + 0.30
        end
        weights[i] = weight
        total = total + weight
    end

    if total <= 0 then return entries[math.random(#entries)] end
    local roll = math.random() * total
    local running = 0
    for i, entry in ipairs(entries) do
        running = running + weights[i]
        if roll <= running then return entry end
    end
    return entries[#entries]
end

local function pickWeightedUniquePets(entries, count, enemyLevel)
    local pool = cloneList(entries)
    local chosen = {}
    for _ = 1, math.min(count, #pool) do
        local entry = weightedPickByLevel(pool, enemyLevel)
        if not entry then break end
        chosen[#chosen + 1] = entry.petId
        for i = #pool, 1, -1 do
            if pool[i].petId == entry.petId then
                table.remove(pool, i)
                break
            end
        end
    end
    return chosen
end

local function buildSkillLoadout(enemyLevel)
    local unlocked = {}
    for _, spellId in ipairs(spells.ORDER or {}) do
        local def = spells.DEFS and spells.DEFS[spellId]
        if def and enemyLevel >= (def.unlockLevel or 99) then
            unlocked[#unlocked + 1] = { id = spellId, unlockLevel = def.unlockLevel or 1 }
        end
    end

    local owned = {}
    for _, entry in ipairs(unlocked) do
        local gap = math.max(0, enemyLevel - entry.unlockLevel)
        local chance = math.min(0.95, 0.35 + gap * 0.045)
        if math.random() < chance then
            owned[#owned + 1] = entry.id
        end
    end

    if enemyLevel >= 10 and #owned == 0 and #unlocked > 0 then
        owned[#owned + 1] = unlocked[math.random(#unlocked)].id
    end
    return owned
end

local function buildBotBaseStats(playerLevel, enemyLevel)
    local attack = 100
    local defense = 100
    local speed = 100
    local hp = 100

    for level = 2, enemyLevel do
        local totalPoints = level <= 10 and 20 or 30
        local hpGain = math.floor(totalPoints * 0.40)
        local statGain = math.floor((totalPoints - hpGain) / 3)
        attack = attack + statGain
        defense = defense + statGain
        speed = speed + statGain
        hp = hp + hpGain
    end

    return {
        level = enemyLevel,
        attack = attack,
        defense = defense,
        intelligence = 5,
        speed = speed,
        hp = hp,
    }
end

local function applyDifficulty(finalStats, diffKey)
    local diff = DIFFICULTY_BANDS[diffKey] or 1.0
    local botStatScale = 0.90
    return {
        attack = math.max(1, math.floor(finalStats.attack * diff * botStatScale)),
        defense = math.max(1, math.floor(finalStats.defense * diff * botStatScale)),
        speed = math.max(1, math.floor(finalStats.speed * diff * botStatScale)),
        hp = math.max(1, math.floor(finalStats.hp * diff * botStatScale)),
    }
end

function M.buildLoadout(player, opts)
    opts = opts or {}

    local diffKey = opts.difficulty or "normal"
    local biasKey = opts.bias or "balanced"
    local enemyLevel = math.max(1, opts.level or player.level or 1)

    local base = buildBotBaseStats(player.level or enemyLevel, enemyLevel)
    local bot = {
        name = opts.name or "Opponent",
        level = enemyLevel,
        attack = base.attack,
        defense = base.defense,
        intelligence = base.intelligence,
        speed = base.speed,
        hp = base.hp,
        equipped = {
            weapons = {},
            armor = {},
            accessories = {},
            pets = {},
        },
        spells = {},
        currentWeaponIndex = 1,
    }

    local playerWeaponCount = math.max(1, math.min(3, #(player.equipped and player.equipped.weapons or {})))
    local weaponCount = math.max(1, math.min(3, playerWeaponCount + math.random(-1, 0)))

    local legalWeapons = getEligibleItemsForSlot("weapon", enemyLevel)
    sortCandidates(legalWeapons, biasKey)
    local weaponPool = cloneList(legalWeapons)
    for _ = 1, math.min(weaponCount, #weaponPool) do
        local topN = math.min(#weaponPool, 4)
        local pickIndex = math.random(topN)
        bot.equipped.weapons[#bot.equipped.weapons + 1] = table.remove(weaponPool, pickIndex)
    end

    for _, slot in ipairs({ "helmet", "chest", "gloves", "boots" }) do
        local candidates = getEligibleItemsForSlot(slot, enemyLevel)
        sortCandidates(candidates, biasKey)
        if #candidates > 0 then
            bot.equipped.armor[slot] = pickFromTop(candidates, 3)
        end
    end

    for _, slot in ipairs({ "necklace", "ring", "charm" }) do
        if enemyLevel >= (ACCESSORY_UNLOCK_LEVEL[slot] or 99) then
            local candidates = getEligibleItemsForSlot(slot, enemyLevel)
            sortCandidates(candidates, biasKey)
            if #candidates > 0 and math.random() < 0.9 then
                bot.equipped.accessories[slot] = pickFromTop(candidates, 3)
            end
        end
    end

    local legalPets = getLegalPetEntries(enemyLevel)
    local playerPetCount = #spells.getEquippedPetsForBattle(player)
    local playerMaxPets = spells.getMaxPetSlots(player)
    local maxPets = math.min(#legalPets, math.max(0, math.min(playerMaxPets, playerPetCount + math.random(-1, 1))))
    bot.equipped.pets = pickWeightedUniquePets(legalPets, maxPets, enemyLevel)
    bot.spells = buildSkillLoadout(enemyLevel)

    local finalStats = stats.calculate(bot)
    local tunedStats = applyDifficulty(finalStats, diffKey)
    bot.attack = tunedStats.attack
    bot.defense = tunedStats.defense
    bot.speed = tunedStats.speed
    bot.hp = tunedStats.hp

    return bot
end

--------------------------------------------------
-- GENERATE ENEMY LEADER (FROM FINAL PLAYER STATS)
--------------------------------------------------
function M.generate(playerStats, opts)
    opts = opts or {}

    local diffKey = opts.difficulty or "normal"
    local biasKey = opts.bias or "balanced"

    local diff = DIFFICULTY_BANDS[diffKey] or 1.0
    local bias = STAT_BIASES[biasKey] or {}
    local botStatScale = 0.90

    local enemy = {
        attack = math.floor(playerStats.attack * diff * (bias.attack or 1) * botStatScale),
        defense = math.floor(playerStats.defense * diff * (bias.defense or 1) * botStatScale),
        speed = math.floor(playerStats.speed * diff * (bias.speed or 1) * botStatScale),

        -- HP intentionally scales slower than player
        hp = math.floor(playerStats.hp * diff * 0.85 * botStatScale),

        difficulty = diffKey,
        bias = biasKey
    }

    return enemy
end

--------------------------------------------------
-- GENERATE ENEMY PET (DERIVED FROM ENEMY LEADER)
--------------------------------------------------
function M.generatePet(enemyStats, opts)
    opts = opts or {}

    local petScale = opts.petScale or 0.65

    return {
        attack = math.floor(enemyStats.attack * petScale),
        defense = math.floor(enemyStats.defense * petScale),
        speed = math.floor(enemyStats.speed * petScale),
        hp = math.floor(enemyStats.hp * petScale)
    }
end

function M.buildArenaOpponent(player, opts)
    opts = opts or {}
    local bot = M.buildLoadout(player, opts)
    return {
        id = opts.id or bot.name,
        name = opts.name or bot.name,
        visualId = opts.visualId,
        level = bot.level,
        attack = bot.attack,
        defense = bot.defense,
        speed = bot.speed,
        hp = bot.hp,
        pets = cloneList(bot.equipped.pets),
        equipped = {
            weapons = cloneList(bot.equipped.weapons),
            armor = bot.equipped.armor,
            accessories = bot.equipped.accessories,
            pets = cloneList(bot.equipped.pets),
        },
        spells = cloneList(bot.spells),
        currentWeaponIndex = 1,
        weaponUsesLeft = nil,
        difficulty = opts.difficulty or "normal",
        bias = opts.bias or "balanced",
    }
end

return M
