local saveUtil = require("utils.save")
local api = require("utils.api")

local M = {}

local function deepCopy(value)
    if type(value) ~= "table" then return value end
    local copy = {}
    for k, v in pairs(value) do
        copy[k] = deepCopy(v)
    end
    return copy
end

local function pruneGuildShortcuts(player)
    if type(player) ~= "table" or type(player.guilds) ~= "table" then return end
    local valid = {}
    for _, guild in ipairs(player.guilds) do
        if type(guild) == "table" and guild.guildId then
            valid[tostring(guild.guildId)] = true
        end
    end

    if type(player.guild) == "table"
        and player.guild.guildId
        and not valid[tostring(player.guild.guildId)] then
        player.guild = nil
    end
    if type(player.createdGuild) == "table"
        and player.createdGuild.guildId
        and not valid[tostring(player.createdGuild.guildId)] then
        player.createdGuild = nil
    end
end

function M.mergePlayerSnapshot(localPlayer, serverPlayer)
    serverPlayer = serverPlayer or {}
    local merged = deepCopy(serverPlayer)
    if merged.lastLoginAt == nil and localPlayer and localPlayer.lastLoginAt ~= nil then
        merged.lastLoginAt = localPlayer.lastLoginAt
    end
    if serverPlayer.displayName ~= nil then
        merged.name = tostring(serverPlayer.displayName)
    end
    if serverPlayer.guilds ~= nil then
        pruneGuildShortcuts(merged)
    end

    return merged
end

function M.applyPlayerSnapshot(serverPlayer, slot)
    local localPlayer = saveUtil.load(slot)
    local merged = M.mergePlayerSnapshot(localPlayer, serverPlayer)
    saveUtil.save(merged, slot)
    return merged
end

function M.pushPlayerSnapshot(player, callback)
    api.player.update(player, function(response)
        if response and response.ok and response.data and response.data.player then
            M.applyPlayerSnapshot(response.data.player, saveUtil.activeSlot)
        end
        if callback then callback(response) end
    end)
end

function M.buildShopPurchasePayload(itemId)
    return {
        itemId = itemId,
        profileSlot = saveUtil.activeSlot,
    }
end

function M.buildTaskClaimPayload(taskId)
    return {
        taskId = taskId,
        profileSlot = saveUtil.activeSlot,
    }
end

return M
