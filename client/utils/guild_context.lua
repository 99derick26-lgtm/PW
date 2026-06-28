local composer = require("composer")

local M = {}

local function roleOf(guild)
    return string.upper(tostring((guild and guild.role) or ""))
end

local function isLeader(guild)
    return roleOf(guild) == "LEADER"
end

local function guildCopy(guild)
    if not guild then return nil end
    local out = {}
    for k, v in pairs(guild) do out[k] = v end
    return out
end

local function compactGuild(guild, forcedRole)
    if not guild or not guild.guildId then return nil end
    return {
        guildId = guild.guildId,
        name = guild.name,
        leader = guild.leader,
        leaderPlayerId = guild.leaderPlayerId,
        members = guild.members,
        maxMembers = guild.maxMembers,
        gold = guild.gold or 0,
        rep = guild.rep,
        averageLevel = guild.averageLevel or guild.avgLevel or guild.level,
        isPublic = guild.isPublic,
        level = guild.level or guild.avgLevel or 1,
        avgLevel = guild.avgLevel or guild.level,
        jailCount = guild.jailCount,
        role = forcedRole or guild.role or "MEMBER",
        desc = guild.desc or guild.description,
        description = guild.description or guild.desc,
    }
end

local function upsertGuildList(player, guild, role)
    if not player or not guild or not guild.guildId then return end
    player.guilds = player.guilds or {}
    for _, entry in ipairs(player.guilds) do
        if entry.guildId == guild.guildId then
            entry.name = guild.name or entry.name
            entry.role = role or guild.role or entry.role
            entry.members = guild.members or entry.members
            entry.maxMembers = guild.maxMembers or entry.maxMembers
            entry.gold = guild.gold or entry.gold or 0
            entry.rep = guild.rep or entry.rep
            entry.averageLevel = guild.averageLevel or guild.avgLevel or guild.level or entry.averageLevel
            entry.level = guild.level or guild.avgLevel or entry.level
            entry.avgLevel = guild.avgLevel or entry.avgLevel
            entry.jailCount = guild.jailCount or entry.jailCount
            entry.desc = guild.desc or guild.description or entry.desc
            entry.description = guild.description or guild.desc or entry.description
            return
        end
    end
    player.guilds[#player.guilds + 1] = compactGuild(guild, role or guild.role)
end

function M.normalizePlayer(player)
    if not player then return player end
    player.guilds = player.guilds or {}

    if player.joinedGuild and player.joinedGuild.guildId then
        player.guild = player.joinedGuild
        upsertGuildList(player, player.joinedGuild, player.joinedGuild.role or "MEMBER")
    elseif player.guild and player.guild.guildId and not isLeader(player.guild) then
        player.joinedGuild = player.guild
        upsertGuildList(player, player.guild, player.guild.role or "MEMBER")
    else
        for _, entry in ipairs(player.guilds) do
            if entry and entry.guildId and not isLeader(entry) then
                player.joinedGuild = entry
                player.guild = entry
                break
            end
        end
    end

    if player.hostedGuild and player.hostedGuild.guildId then
        player.createdGuild = player.hostedGuild
        upsertGuildList(player, player.hostedGuild, "LEADER")
    elseif player.createdGuild and player.createdGuild.guildId then
        player.hostedGuild = player.createdGuild
        upsertGuildList(player, player.createdGuild, "LEADER")
    else
        for _, entry in ipairs(player.guilds) do
            if entry and entry.guildId and isLeader(entry) then
                player.hostedGuild = entry
                player.createdGuild = entry
                break
            end
        end
    end

    return player
end

function M.getJoinedGuild(player)
    player = M.normalizePlayer(player)
    return player and player.joinedGuild or nil
end

function M.getHostedGuild(player)
    player = M.normalizePlayer(player)
    return player and player.hostedGuild or nil
end

function M.findGuild(player, guildId)
    if not guildId then return nil end
    player = M.normalizePlayer(player)
    if not player then return nil end
    if player.joinedGuild and player.joinedGuild.guildId == guildId then return player.joinedGuild end
    if player.hostedGuild and player.hostedGuild.guildId == guildId then return player.hostedGuild end
    for _, entry in ipairs(player.guilds or {}) do
        if entry and entry.guildId == guildId then return entry end
    end
    return nil
end

function M.setActiveGuild(guildId, kind)
    composer.setVariable("guildContextId", guildId)
    composer.setVariable("guildContextKind", kind)
end

function M.getActiveGuildId()
    return composer.getVariable("guildContextId")
end

function M.getActiveGuild(player, params)
    player = M.normalizePlayer(player)
    params = params or {}

    if params.guildId then
        local guild = M.findGuild(player, params.guildId) or { guildId = params.guildId }
        M.setActiveGuild(params.guildId, params.guildKey)
        return guild
    end

    if params.guildKey == "hostedGuild" or params.guildKey == "createdGuild" then
        local guild = M.getHostedGuild(player)
        if guild then M.setActiveGuild(guild.guildId, "hostedGuild") end
        return guild
    end

    if params.guildKey == "joinedGuild" or params.guildKey == "guild" then
        local guild = M.getJoinedGuild(player)
        if guild then M.setActiveGuild(guild.guildId, "joinedGuild") end
        return guild
    end

    local contextId = M.getActiveGuildId()
    if contextId then
        local guild = M.findGuild(player, contextId)
        if guild then return guild end
    end

    local joined = M.getJoinedGuild(player)
    if joined then
        M.setActiveGuild(joined.guildId, "joinedGuild")
        return joined
    end

    local hosted = M.getHostedGuild(player)
    if hosted then
        M.setActiveGuild(hosted.guildId, "hostedGuild")
        return hosted
    end

    return nil
end

function M.applyGuild(player, guild, role)
    if not player or not guild or not guild.guildId then return player end
    role = role or guild.role or "MEMBER"
    local compact = compactGuild(guild, role)
    upsertGuildList(player, compact, role)

    if string.upper(tostring(role)) == "LEADER" then
        player.hostedGuild = compact
        player.createdGuild = compact
    else
        player.joinedGuild = compact
        player.guild = compact
    end
    return player
end

function M.removeGuild(player, guildId)
    if not player or not guildId then return player end
    player.guilds = player.guilds or {}
    for i = #player.guilds, 1, -1 do
        if player.guilds[i].guildId == guildId then table.remove(player.guilds, i) end
    end
    if player.guild and player.guild.guildId == guildId then player.guild = nil end
    if player.joinedGuild and player.joinedGuild.guildId == guildId then player.joinedGuild = nil end
    if player.createdGuild and player.createdGuild.guildId == guildId then player.createdGuild = nil end
    if player.hostedGuild and player.hostedGuild.guildId == guildId then player.hostedGuild = nil end
    if M.getActiveGuildId() == guildId then
        M.setActiveGuild(nil, nil)
    end
    return player
end

return M
