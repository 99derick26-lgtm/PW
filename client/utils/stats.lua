local items = require("utils.items")
local weapons = require("utils.weapons")
local injections = require("utils.injections")

local stats = {}

function stats.calculate(player)
 local base = {
    atk = player.attack or 100,
    def = player.defense or 100,
    spd = player.speed or 100,
    hp  = player.hp or 100
}


    local bonus = {
    attack  = 0,
    defense = 0,
    speed   = 0,
    hp      = 0
}

    local function applyItemBonuses(itemId)
        local item = items[itemId]
        if not item or not item.statPercent then return end

        for stat, value in pairs(item.statPercent) do
            if type(value) == "table" then
                local avg = (value.min + value.max) * 0.5
                bonus[stat] = bonus[stat] + avg
            else
                bonus[stat] = bonus[stat] + value
            end
        end
    end

    if player.equipped and player.equipped.armor then
        for _, itemId in pairs(player.equipped.armor) do
            applyItemBonuses(itemId)
        end
    end

    if player.equipped and player.equipped.accessories then
        for _, itemId in pairs(player.equipped.accessories) do
            applyItemBonuses(itemId)
        end
    end

    -- Weapons rotate in combat, so only the current weapon's non-attack
    -- modifiers are included in visible/base combat stats.
    if player.equipped and player.equipped.weapons and #player.equipped.weapons > 0 then
        local index = math.max(1, math.min(player.currentWeaponIndex or 1, #player.equipped.weapons))
        local weapon = items[player.equipped.weapons[index]]
        if weapon and weapon.statPercent then
            for stat, value in pairs(weapon.statPercent) do
                if stat ~= "attack" then
                    if type(value) == "table" then
                        bonus[stat] = bonus[stat] + ((value.min + value.max) * 0.5)
                    else
                        bonus[stat] = bonus[stat] + value
                    end
                end
            end
        end
    end

    local injectionBonus = injections.activeBonus(player)
    for stat, value in pairs(injectionBonus) do
        bonus[stat] = (bonus[stat] or 0) + value
    end

 return {
    attack  = math.floor(base.atk * (1 + bonus.attack)),
    defense = math.floor(base.def * (1 + bonus.defense)),
    speed   = math.floor(base.spd * (1 + bonus.speed)),
    hp      = math.floor(base.hp  * (1 + bonus.hp))
}


end


return stats
