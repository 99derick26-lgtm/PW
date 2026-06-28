local pets = require("utils.pets")

local M = {}
local existsCache = {}
local rearBattleSprites = {
    alligator = true,
    elephant = true,
    guar = true,
    panda = true,
    polar_bear = true,
    rhino = true,
    tiger = true,
}

local function fileExists(path)
    if existsCache[path] ~= nil then return existsCache[path] end

    local fullPath = system.pathForFile(path, system.ResourceDirectory)
    local exists = false
    if fullPath then
        local f = io.open(fullPath, "r")
        if f then
            exists = true
            f:close()
        end
    end

    existsCache[path] = exists
    return exists
end

function M.folder(petId)
    local def = pets[petId]
    return (def and def.spriteFolder) or petId
end

function M.path(petId, preferredName, ...)
    local folder = M.folder(petId)
    local preferred = "assets/sprites/pets/" .. folder .. "/" .. preferredName .. ".png"
    if fileExists(preferred) then return preferred end

    for _, fallbackName in ipairs({ ... }) do
        local fallback = "assets/sprites/pets/" .. folder .. "/" .. fallbackName .. ".png"
        if fileExists(fallback) then return fallback end
    end

    return preferred
end

function M.portrait(petId)
    return M.path(petId, "portrait", "portraits")
end

function M.home(petId)
    return M.path(petId, "idle", "battle")
end

function M.battle(petId, team)
    if team == "player" then
        if rearBattleSprites[petId] then
            return "assets/sprites/pets/" .. M.folder(petId) .. "/rear_battle.png"
        end
        return "assets/sprites/pets/" .. M.folder(petId) .. "/rear.png"
    end
    return "assets/sprites/pets/" .. M.folder(petId) .. "/battle.png"
end

function M.hit(petId, team)
    if team == "player" then
        return "assets/sprites/pets/" .. M.folder(petId) .. "/rear_hit.png"
    end
    return "assets/sprites/pets/" .. M.folder(petId) .. "/hit.png"
end

function M.dead(petId, team)
    if team == "player" then
        if rearBattleSprites[petId] then
            return "assets/sprites/pets/" .. M.folder(petId) .. "/rear_dead.png"
        end
        return "assets/sprites/pets/" .. M.folder(petId) .. "/dead.png"
    end
    return "assets/sprites/pets/" .. M.folder(petId) .. "/dead.png"
end

function M.attack(petId, team)
    if team == "player" then
        if petId == "panda" then
            return "assets/sprites/pets/" .. M.folder(petId) .. "/attack_rear.png"
        end
        if rearBattleSprites[petId] then
            return "assets/sprites/pets/" .. M.folder(petId) .. "/rear_attack.png"
        end
        return "assets/sprites/pets/" .. M.folder(petId) .. "/battle.png"
    end
    return "assets/sprites/pets/" .. M.folder(petId) .. "/attack.png"
end

-- Kept for older callers that still want file-system fallback behavior.
function M.battleWithFallback(petId, team)
    if team == "player" then
        return M.path(petId, "rear_battle", "rear", "battle")
    end
    return M.path(petId, "battle")
end

function M.hitWithFallback(petId, team)
    if team == "player" then
        return M.path(petId, "rear_hit", "hit", "rear", "battle")
    end
    return M.path(petId, "hit", "battle")
end

function M.deadWithFallback(petId, team)
    if team == "player" then
        return M.path(petId, "rear_dead", "dead", "rear", "battle")
    end
    return M.path(petId, "dead", "battle")
end

function M.attackWithFallback(petId, team)
    if team == "player" then
        return M.path(petId, "rear_attack", "attack_rear", "rear_battle", "rear", "battle")
    end
    return M.path(petId, "attack", "battle")
end

return M
