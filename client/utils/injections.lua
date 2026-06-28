local items = require("utils.items")

local M = {}

local DEFAULT_DURATION = 60 * 60
local DEFAULT_COOLDOWN = 6 * 60 * 60

local STAT_LABELS = {
    attack = "Attack",
    defense = "Defense",
    speed = "Speed",
    hp = "HP",
    all = "Overdrive",
}

local function now()
    return os.time()
end

local function statKeyFor(item)
    if type(item) == "string" then
        item = items[item]
    end
    if not item or item.type ~= "injection" then return nil end
    return item.injectionStat or item.id
end

function M.normalize(player)
    player.injections = player.injections or {}
    player.injections.active = player.injections.active or {}
    player.injections.cooldowns = player.injections.cooldowns or {}
    return player.injections
end

local function hasInventoryItem(player, itemId)
    for _, id in ipairs(player.inventory or {}) do
        if id == itemId then return true end
    end
    return false
end

local function removeInventoryItem(player, itemId)
    for i, id in ipairs(player.inventory or {}) do
        if id == itemId then
            table.remove(player.inventory, i)
            return true
        end
    end
    return false
end

function M.remaining(secondsUntil)
    local value = math.max(0, math.floor((tonumber(secondsUntil) or 0) - now()))
    return value
end

function M.formatRemaining(seconds)
    seconds = math.max(0, math.floor(tonumber(seconds) or 0))
    local hours = math.floor(seconds / 3600)
    local minutes = math.floor((seconds % 3600) / 60)
    if hours > 0 then
        return tostring(hours) .. "h " .. tostring(minutes) .. "m"
    end
    return tostring(math.max(1, minutes)) .. "m"
end

function M.getStatus(player, item)
    local injection = M.normalize(player)
    local statKey = statKeyFor(item)
    if not statKey then return { ok = false, reason = "Not an injection." } end

    local activeLeft = M.remaining(injection.active[statKey])
    if activeLeft > 0 then
        return {
            ok = false,
            activeLeft = activeLeft,
            reason = (STAT_LABELS[statKey] or "Injection") .. " is already active.",
        }
    end

    local cooldownLeft = M.remaining(injection.cooldowns[statKey])
    if cooldownLeft > 0 then
        return {
            ok = false,
            cooldownLeft = cooldownLeft,
            reason = (STAT_LABELS[statKey] or "Injection") .. " is cooling down.",
        }
    end

    return { ok = true }
end

function M.use(player, item)
    if type(item) == "string" then
        item = items[item]
    end
    if not item or item.type ~= "injection" then
        return false, "That item cannot be used."
    end

    player.inventory = player.inventory or {}
    if not hasInventoryItem(player, item.id) then
        return false, "You do not own this injection."
    end

    local status = M.getStatus(player, item)
    if not status.ok then
        local waitLeft = status.activeLeft or status.cooldownLeft
        if waitLeft then
            return false, status.reason .. " Try again in " .. M.formatRemaining(waitLeft) .. "."
        end
        return false, status.reason
    end

    local injection = M.normalize(player)
    local statKey = statKeyFor(item)
    local startedAt = now()
    injection.active[statKey] = startedAt + (item.durationSeconds or DEFAULT_DURATION)
    injection.cooldowns[statKey] = startedAt + (item.cooldownSeconds or DEFAULT_COOLDOWN)
    removeInventoryItem(player, item.id)
    return true, item.name .. " active."
end

function M.activeBonus(player)
    local bonus = { attack = 0, defense = 0, speed = 0, hp = 0 }
    local injection = M.normalize(player)
    local currentTime = now()

    for statKey, expiresAt in pairs(injection.active or {}) do
        expiresAt = tonumber(expiresAt) or 0
        if expiresAt <= currentTime then
            injection.active[statKey] = nil
        else
            local percent = statKey == "all" and 0.05 or 0.20
            if statKey == "all" then
                bonus.attack = bonus.attack + percent
                bonus.defense = bonus.defense + percent
                bonus.speed = bonus.speed + percent
                bonus.hp = bonus.hp + percent
            elseif bonus[statKey] ~= nil then
                bonus[statKey] = bonus[statKey] + percent
            end
        end
    end

    return bonus
end

return M
