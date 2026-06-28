-- utils/pet_scaler.lua
-- Pixel War Online — Pet Stat Authority (2005–2012 MMO Style)

local petsDB = require("utils.pets")
local statsUtil = require("utils.stats")

local petScaler = {}

petScaler.PET_STAT_CAP = petsDB.BASE_STAT_CEILING or 800
petScaler.GEM_VALUE = petsDB.AUGMENT_STEP or 10
petScaler.AUGMENT_STEP = petScaler.GEM_VALUE

local AUGMENT_KEYS = {
    atk = "augment_attack",
    def = "augment_defense",
    hp  = "augment_health",
    spd = "augment_speed",
}

function petScaler.getAugments(player, petInstanceId)
    local all = (player and player.petAugments) or {}
    local aug = all[petInstanceId] or {}
    return {
        atk = aug.atk or 0,
        def = aug.def or 0,
        hp  = aug.hp or 0,
        spd = aug.spd or 0,
    }
end

function petScaler.getTotalAugments(player, petInstanceId)
    local aug = petScaler.getAugments(player, petInstanceId)
    return aug.atk + aug.def + aug.hp + aug.spd
end

function petScaler.getBaseTotal(petInstanceId)
    local def = petsDB[petInstanceId]
    local base = def and def.base
    if not base then return 0 end
    return (base.hp or 0) + (base.atk or 0) + (base.def or 0) + (base.spd or 0)
end

function petScaler.getAugmentLimit(petInstanceId)
    local remaining = petScaler.PET_STAT_CAP - petScaler.getBaseTotal(petInstanceId)
    return math.max(0, math.floor(remaining / petScaler.GEM_VALUE))
end

function petScaler.getStarRating(player, petInstanceId)
    local limit = math.max(1, petScaler.getAugmentLimit(petInstanceId))
    local total = petScaler.getTotalAugments(player, petInstanceId)
    return math.max(0, math.min(5, math.floor((total / limit) * 5)))
end

function petScaler.getUpgradeSuccessRate(starRating)
    local rates = {
        [0] = 1.00,
        [1] = 0.80,
        [2] = 0.60,
        [3] = 0.40,
        [4] = 0.20,
    }
    return rates[math.max(0, math.min(4, starRating or 0))] or 0.20
end

function petScaler.applyAugment(player, petInstanceId, statKey)
    if not player or not petInstanceId or not AUGMENT_KEYS[statKey] then
        return false, "invalid"
    end

    player.materials = player.materials or {}
    player.petAugments = player.petAugments or {}

    if petScaler.getTotalAugments(player, petInstanceId) >= petScaler.getAugmentLimit(petInstanceId) then
        return false, "maxed"
    end

    local materialKey = AUGMENT_KEYS[statKey]
    if (player.materials[materialKey] or 0) <= 0 then
        return false, "missing"
    end

    local aug = player.petAugments[petInstanceId] or { atk = 0, def = 0, hp = 0, spd = 0 }
    aug[statKey] = (aug[statKey] or 0) + 1
    player.petAugments[petInstanceId] = aug
    player.materials[materialKey] = (player.materials[materialKey] or 0) - 1
    return true, materialKey
end

function petScaler.attemptAugment(player, petInstanceId, statKey)
    local total = petScaler.getTotalAugments(player, petInstanceId)
    if total >= petScaler.getAugmentLimit(petInstanceId) then
        return false, "maxed"
    end

    local materialKey = AUGMENT_KEYS[statKey]
    if not player or not materialKey then
        return false, "invalid"
    end

    player.materials = player.materials or {}
    if (player.materials[materialKey] or 0) <= 0 then
        return false, "missing"
    end

    player.materials[materialKey] = (player.materials[materialKey] or 0) - 1
    local successRate = petScaler.getUpgradeSuccessRate(petScaler.getStarRating(player, petInstanceId))
    if math.random() <= successRate then
        local aug = player.petAugments[petInstanceId] or { atk = 0, def = 0, hp = 0, spd = 0 }
        aug[statKey] = (aug[statKey] or 0) + 1
        player.petAugments[petInstanceId] = aug
        return true, materialKey
    end
    return false, "failed"
end

function petScaler.resetAugments(player, petInstanceId)
    if not player or not petInstanceId then return false end
    local aug = petScaler.getAugments(player, petInstanceId)
    local total = aug.atk + aug.def + aug.hp + aug.spd
    if total <= 0 then return false end

    player.materials = player.materials or {}
    player.materials.augment_attack  = (player.materials.augment_attack or 0) + aug.atk
    player.materials.augment_defense = (player.materials.augment_defense or 0) + aug.def
    player.materials.augment_health  = (player.materials.augment_health or 0) + aug.hp
    player.materials.augment_speed   = (player.materials.augment_speed or 0) + aug.spd
    player.petAugments = player.petAugments or {}
    player.petAugments[petInstanceId] = nil
    return true
end

--------------------------------------------------
-- SCALE PET (SINGLE SOURCE OF TRUTH)
--------------------------------------------------
local function normalizeAvatarStats(avatarStats)
    if type(avatarStats) == "table" then
        if avatarStats.attack or avatarStats.defense or avatarStats.speed or avatarStats.hp
            or avatarStats.atk or avatarStats.def or avatarStats.spd
        then
            return {
                attack = avatarStats.attack or avatarStats.atk or 100,
                defense = avatarStats.defense or avatarStats.def or 100,
                speed = avatarStats.speed or avatarStats.spd or 100,
                hp = avatarStats.hp or 100,
            }
        end
        return statsUtil.calculate(avatarStats)
    end
    return { attack = 100, defense = 100, speed = 100, hp = 100 }
end

local function scalePetStat(playerStat, baseStat, gemCount)
    return math.floor((playerStat or 0) * ((baseStat or 0) + (gemCount or 0) * petScaler.GEM_VALUE) / 100)
end

function petScaler.scalePet(petId, avatarStats, augments)
    local def = petsDB[petId]
    if not def or not def.base then
        return nil
    end

    augments = augments or {}
    local avatar = normalizeAvatarStats(avatarStats)

    local stats = {
        atk = scalePetStat(avatar.attack, def.base.atk, augments.atk),
        def = scalePetStat(avatar.defense, def.base.def, augments.def),
        spd = scalePetStat(avatar.speed, def.base.spd, augments.spd),
        hp  = scalePetStat(avatar.hp, def.base.hp, augments.hp),
    }

    return stats
end


return petScaler

