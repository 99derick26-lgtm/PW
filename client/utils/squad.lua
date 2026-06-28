-- utils/squad.lua
-- Pixel War Online — Squad / Conquest System
--
-- Conquest rules:
--   - Player can conquer up to MAX_CONQUERED AI players
--   - Conquering costs 1 energy and triggers a fight
--   - Conquered players generate 20 gold every 6 hours (passive)
--   - Tax rate 0–20% (set per conquered player)
--   - Conquered player can be liberated if they "beat" you (simulated daily check)
--   - When server exists, AI players → real player snapshots

local M = {}

local MAX_CONQUERED   = 4          -- max 4 others (you + 4 = squad of 5)
local TAX_GOLD        = 20         -- base gold per tick per conquered player
local TAX_INTERVAL    = 6 * 3600   -- 6 hours in seconds
local LIBERATION_CHANCE = 0.08     -- 8% chance per tick a conquered player breaks free

-------------------------------------------------
-- AI PLAYER POOL
-- Used as conquest targets. Server will replace with real snapshots.
-------------------------------------------------
M.AI_POOL = {
    { name="Vex",       level=8,  power=220, visualId="street_brawler"   },
    { name="Kira",      level=10, power=280, visualId="street_fighter_f" },
    { name="Doza",      level=12, power=340, visualId="street_punk"      },
    { name="IronFist",  level=14, power=390, visualId="corp_enforcer"    },
    { name="Sable",     level=9,  power=250, visualId="street_fighter"   },
    { name="Reckoner",  level=11, power=310, visualId="street_punk_f"    },
    { name="Grindcore", level=13, power=370, visualId="corp_enforcer_f"  },
    { name="Nyxara",    level=15, power=430, visualId="street_brawler"   },
    { name="Bolt",      level=7,  power=190, visualId="street_fighter"   },
    { name="Cipher",    level=16, power=480, visualId="corp_enforcer"    },
}

-------------------------------------------------
-- ENSURE STATE
-------------------------------------------------
local function ensureSquad(player)
    player.squad = player.squad or {
        conquered  = {},   -- array of conquest entries
        lastTickTs = os.time(),
    }
    player.squad.conquered  = player.squad.conquered  or {}
    player.squad.lastTickTs = player.squad.lastTickTs or os.time()
end

-------------------------------------------------
-- GET AVAILABLE TARGETS
-- Returns AI players not already conquered by this player
-------------------------------------------------
function M.getTargets(player)
    ensureSquad(player)
    local conqueredNames = {}
    for _, c in ipairs(player.squad.conquered) do
        conqueredNames[c.name] = true
    end

    local targets = {}
    for _, ai in ipairs(M.AI_POOL) do
        if not conqueredNames[ai.name] then
            table.insert(targets, ai)
        end
    end
    return targets
end

-------------------------------------------------
-- CAN CONQUER
-------------------------------------------------
function M.canConquer(player)
    ensureSquad(player)
    return #player.squad.conquered < MAX_CONQUERED
end

-------------------------------------------------
-- ADD CONQUERED
-- Called after player wins a conquest fight
-------------------------------------------------
function M.addConquered(player, aiTarget)
    ensureSquad(player)
    if #player.squad.conquered >= MAX_CONQUERED then return false end
    for _, conquered in ipairs(player.squad.conquered) do
        if conquered.name == aiTarget.name then
            return false
        end
    end

    table.insert(player.squad.conquered, {
        name      = aiTarget.name,
        level     = aiTarget.level,
        power     = aiTarget.power,
        visualId  = aiTarget.visualId,
        taxRate   = 0.10,             -- default 10%
        conqueredAt = os.time(),
    })
    return true
end

-------------------------------------------------
-- REMOVE CONQUERED (liberation)
-------------------------------------------------
function M.removeConquered(player, name)
    ensureSquad(player)
    for i = #player.squad.conquered, 1, -1 do
        if player.squad.conquered[i].name == name then
            table.remove(player.squad.conquered, i)
            return true
        end
    end
    return false
end

-------------------------------------------------
-- SET TAX RATE
-------------------------------------------------
function M.setTaxRate(player, name, rate)
    ensureSquad(player)
    rate = math.max(0, math.min(0.20, rate))
    for _, c in ipairs(player.squad.conquered) do
        if c.name == name then
            c.taxRate = rate
            return true
        end
    end
    return false
end

-------------------------------------------------
-- TICK — collect passive gold + liberation checks
-- Call this when the squad scene opens or game resumes.
-- Returns: goldGained, liberated (array of names freed)
-------------------------------------------------
function M.tick(player)
    ensureSquad(player)

    local now      = os.time()
    local elapsed  = now - player.squad.lastTickTs
    local ticks    = math.floor(elapsed / TAX_INTERVAL)

    local goldGained = 0
    local liberated  = {}

    if ticks > 0 then
        player.squad.lastTickTs = player.squad.lastTickTs + ticks * TAX_INTERVAL

        for i = #player.squad.conquered, 1, -1 do
            local c = player.squad.conquered[i]

            -- gold from this conquered player
            goldGained = goldGained + math.floor(TAX_GOLD * c.taxRate * ticks)

            -- liberation chance per tick
            local freed = false
            for t = 1, ticks do
                if math.random() < LIBERATION_CHANCE then
                    freed = true; break
                end
            end

            if freed then
                table.insert(liberated, c.name)
                table.remove(player.squad.conquered, i)
            end
        end

        player.gold = (player.gold or 0) + goldGained
    end

    return goldGained, liberated
end

-------------------------------------------------
-- GET MAX
-------------------------------------------------
function M.maxConquered()
    return MAX_CONQUERED
end

-------------------------------------------------
-- BUILD OPPONENT TABLE for conquest fight
-- Wraps an AI pool entry into a combat-ready opponent table
-------------------------------------------------
function M.buildOpponent(aiTarget, playerLevel)
    local scaledLevel = math.max(1, aiTarget.level)
    local basePow     = aiTarget.power or 200
    local scale       = 1.0 + (scaledLevel - 1) * 0.06

    return {
        id       = aiTarget.name,
        name     = aiTarget.name,
        visualId = aiTarget.visualId or "street_brawler",
        level    = scaledLevel,
        attack   = math.floor(basePow * 0.28 * scale),
        defense  = math.floor(basePow * 0.24 * scale),
        speed    = math.floor(basePow * 0.22 * scale),
        hp       = math.floor(basePow * 1.20 * scale),
        pets     = {},
        difficulty = "normal",
        bias       = "balanced",
        isConquest = true,       -- flag so arena_battle can return here
    }
end

return M
