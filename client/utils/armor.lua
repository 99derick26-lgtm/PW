local items = require("utils.items")

local armor = {}

function armor.calculateBonuses(equippedArmor)
    local bonuses = {
        attack = 0,
        defense = 0,
        speed = 0,
        intelligence = 0,
        hp = 0
    }

    if not equippedArmor then
        return bonuses
    end

    for _, itemId in pairs(equippedArmor) do
        local item = items[itemId]
        if item and item.statPercentBonuses then
            for stat, value in pairs(item.statPercentBonuses) do
                bonuses[stat] = bonuses[stat] + value
            end
        end
    end

    return bonuses
end

return armor
