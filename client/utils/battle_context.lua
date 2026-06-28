local composer = require("composer")

local M = {}

local BATTLE_KEYS = {
    "battleMode",
    "opponent",
    "fightAllReplay",
    "guildLootChallenge",
    "guildWarBattle",
}

function M.clear()
    for _, key in ipairs(BATTLE_KEYS) do
        composer.setVariable(key, nil)
    end
end

function M.startArena(opponent, replay)
    M.clear()
    composer.setVariable("battleMode", replay and "arena_replay" or "arena")
    composer.setVariable("opponent", opponent)
    if replay then
        composer.setVariable("fightAllReplay", replay)
    end
end

function M.startGuildLoot(opponent, challenge)
    M.clear()
    composer.setVariable("battleMode", "guild_loot")
    composer.setVariable("opponent", opponent)
    composer.setVariable("guildLootChallenge", challenge)
end

function M.startGuildWar(opponent, war)
    M.clear()
    composer.setVariable("battleMode", "guild_war")
    composer.setVariable("opponent", opponent)
    composer.setVariable("guildWarBattle", war)
end

function M.mode()
    return composer.getVariable("battleMode")
end

return M
