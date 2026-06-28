local items = require("utils.items")

local upgrades = {}

local RESOURCE_DEFS = {
    scrap = {
        name = "Amorphous",
        icon = "assets/sprites/more/scrap.png",
        storage = "materials",
        key = "scrap",
    },
    coil = {
        name = "Carbon Fiber",
        icon = "assets/sprites/more/large_coil.png",
        storage = "materials",
        key = "coil",
    },
    chip = {
        name = "Micro-chips",
        icon = "assets/sprites/more/chip.png",
        storage = "materials",
        key = "chip",
    },
    crystal_green = {
        name = "Green Crystal",
        icon = "assets/sprites/materials/crystal_green.png",
        storage = "materials",
        key = "crystal_green",
    },
    crystal_blue = {
        name = "Blue Crystal",
        icon = "assets/sprites/materials/crystal_blue.png",
        storage = "materials",
        key = "crystal_blue",
    },
    crystal_orange = {
        name = "Orange Crystal",
        icon = "assets/sprites/materials/crystal_orange.png",
        storage = "materials",
        key = "crystal_orange",
    },
    crystal_purple = {
        name = "Purple Crystal",
        icon = "assets/sprites/materials/crystal_purple.png",
        storage = "materials",
        key = "crystal_purple",
    },
    diamonds = {
        name = "Diamonds",
        icon = "assets/sprites/materials/rare_chest.png",
        storage = "diamonds",
        key = "diamonds",
    },
}

local TOKEN_ALIASES = {
    a = "scrap",
    amorphous = "scrap",
    scrap = "scrap",
    i = "scrap",

    c = "coil",
    coil = "coil",
    coils = "coil",
    carbon = "coil",
    carbonfiber = "coil",
    carbon_fiber = "coil",
    w = "coil",

    m = "chip",
    chip = "chip",
    chips = "chip",
    microchip = "chip",
    microchips = "chip",
    micro_chips = "chip",
    s = "chip",

    gc = "crystal_green",
    greencrystal = "crystal_green",
    green_crystal = "crystal_green",

    bc = "crystal_blue",
    bluecrystal = "crystal_blue",
    blue_crystal = "crystal_blue",

    oc = "crystal_orange",
    orangecrystal = "crystal_orange",
    orange_crystal = "crystal_orange",

    pc = "crystal_purple",
    purplecrystal = "crystal_purple",
    purple_crystal = "crystal_purple",

    d = "diamonds",
    dm = "diamonds",
    dmd = "diamonds",
    dmnd = "diamonds",
    dmnds = "diamonds",
    diamond = "diamonds",
    diamonds = "diamonds",
}

local function normalizeToken(token)
    token = tostring(token or ""):lower()
    token = token:gsub("%s+", "")
    token = token:gsub("%-", "_")
    token = token:gsub("_+$", "")
    return TOKEN_ALIASES[token], token
end

local function addRequirement(list, key, amount, rawToken)
    if not key then return end
    for _, req in ipairs(list) do
        if req.key == key then
            req.amount = req.amount + amount
            return
        end
    end

    local def = RESOURCE_DEFS[key]
    if def then
        list[#list + 1] = {
            key = key,
            amount = amount,
            name = def.name,
            icon = def.icon,
            storage = def.storage,
        }
    else
        list[#list + 1] = {
            key = key,
            amount = amount,
            name = (items[key] and items[key].name) or tostring(rawToken or key):upper(),
            icon = items[key] and items[key].icon,
            storage = "inventory",
        }
    end
end

function upgrades.parseCost(cost)
    local requirements = {}
    if type(cost) == "table" then
        for key, amount in pairs(cost) do
            local mapped, raw = normalizeToken(key)
            addRequirement(requirements, mapped or raw, tonumber(amount) or 0, key)
        end
        return requirements
    end

    if type(cost) ~= "string" then return requirements end
    for part in cost:gmatch("[^,]+") do
        local text = part:gsub("^%s+", ""):gsub("%s+$", "")
        local amount, token = text:match("^(%d+)%s*([%a_%-]+)$")
        if not amount then
            token, amount = text:match("^([%a_%-]+)%s*%-?%s*(%d+)$")
        end
        if not amount then
            token, amount = text:match("^([%a_%-]+)$"), 1
        end

        local mapped, raw = normalizeToken(token)
        addRequirement(requirements, mapped or raw, tonumber(amount) or 1, token)
    end
    return requirements
end

function upgrades.formatCost(cost)
    local parts = {}
    for _, req in ipairs(upgrades.parseCost(cost)) do
        parts[#parts + 1] = tostring(req.amount) .. " " .. req.name
    end
    return table.concat(parts, ", ")
end

function upgrades.getDef(key)
    return RESOURCE_DEFS[key]
end

function upgrades.getAvailable(player, req)
    if not player or not req then return 0 end
    if req.storage == "diamonds" then
        return player.diamonds or 0
    elseif req.storage == "inventory" then
        local total = 0
        for _, id in ipairs(player.inventory or {}) do
            if id == req.key then total = total + 1 end
        end
        return total
    end

    player.materials = player.materials or {}
    return player.materials[req.key] or 0
end

function upgrades.canAfford(player, requirements)
    for _, req in ipairs(requirements or {}) do
        if upgrades.getAvailable(player, req) < (req.amount or 0) then
            return false, req
        end
    end
    return true
end

local function removeInventoryItems(player, itemId, amount)
    local removed = 0
    for i = #(player.inventory or {}), 1, -1 do
        if player.inventory[i] == itemId then
            table.remove(player.inventory, i)
            removed = removed + 1
            if removed >= amount then return true end
        end
    end
    return removed >= amount
end

function upgrades.spend(player, requirements)
    local ok, missing = upgrades.canAfford(player, requirements)
    if not ok then return false, missing end

    player.materials = player.materials or {}
    for _, req in ipairs(requirements or {}) do
        local amount = req.amount or 0
        if req.storage == "diamonds" then
            player.diamonds = (player.diamonds or 0) - amount
        elseif req.storage == "inventory" then
            removeInventoryItems(player, req.key, amount)
        else
            player.materials[req.key] = (player.materials[req.key] or 0) - amount
        end
    end

    return true
end

function upgrades.getTargets(sourceId)
    local targets = {}
    for id, item in pairs(items) do
        if item and item.upgradeFrom == sourceId and not item.aliasOf then
            targets[#targets + 1] = item
        end
    end
    table.sort(targets, function(a, b)
        return (a.requiredLevel or 0) < (b.requiredLevel or 0)
    end)
    return targets
end

function upgrades.hasTarget(sourceId)
    return #upgrades.getTargets(sourceId) > 0
end

function upgrades.replaceItem(player, sourceId, targetId)
    local replaced = false
    for i, id in ipairs(player.inventory or {}) do
        if id == sourceId then
            player.inventory[i] = targetId
            replaced = true
            break
        end
    end

    player.equipped = player.equipped or {}
    player.equipped.weapons = player.equipped.weapons or {}
    player.equipped.armor = player.equipped.armor or {}
    player.equipped.accessories = player.equipped.accessories or {}
    for i, id in ipairs(player.equipped.weapons) do
        if id == sourceId then
            player.equipped.weapons[i] = targetId
            replaced = true
            break
        end
    end

    for slot, id in pairs(player.equipped.armor) do
        if id == sourceId then
            player.equipped.armor[slot] = targetId
            replaced = true
            break
        end
    end

    for slot, id in pairs(player.equipped.accessories) do
        if id == sourceId then
            player.equipped.accessories[slot] = targetId
            replaced = true
            break
        end
    end

    if not replaced then
        player.inventory = player.inventory or {}
        player.inventory[#player.inventory + 1] = targetId
    end

    return true
end

upgrades.replaceWeapon = upgrades.replaceItem

return upgrades
