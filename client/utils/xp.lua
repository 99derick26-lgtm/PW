-- utils/xp.lua
-- Pixel War Online — XP & Level Progression
local xp = {}

-------------------------------------------------
-- XP REQUIRED TO GO FROM `level` → `level + 1`
-------------------------------------------------
local XP_TABLE = {
    -- Early game (1–9)
    [1]=30,  [2]=40,  [3]=50,  [4]=60,  [5]=70,
    [6]=80,  [7]=90,  [8]=100, [9]=120,
    -- Early–Mid (10–19)
    [10]=150, [11]=180, [12]=220, [13]=270, [14]=330,
    [15]=400, [16]=480, [17]=560, [18]=650, [19]=750,
    -- Mid game (20–29)
    [20]=900,  [21]=1100, [22]=1300, [23]=1500, [24]=1700,
    [25]=1800, [26]=1900, [27]=2000, [28]=2100, [29]=2200,
    -- Bracket 1 — +500 per level (30–39)
    [30]=2500, [31]=3000, [32]=3500, [33]=4000, [34]=4500,
    [35]=5000, [36]=5500, [37]=6000, [38]=6500, [39]=7000,
    -- Bracket 2 — +1000 per level (40–49)
    [40]=8000,  [41]=9000,  [42]=10000, [43]=11000, [44]=12000,
    [45]=13000, [46]=14000, [47]=15000, [48]=16000, [49]=17000,
    -- Bracket 3 — +2000 per level (50–54)
    [50]=18000, [51]=20000, [52]=22000, [53]=24000, [54]=26000,
}

function xp.getXpToLevel(level)
    if XP_TABLE[level] then
        return XP_TABLE[level]
    end
    -- Beyond level 54: continue +2000 per level
    return 26000 + (level - 54) * 2000
end

local ARENA_REWARDS = {
    extreme = { gold = 24, xp = 14 },
    hard    = { gold = 22, xp = 12 },
    casual  = { gold = 20, xp = 10 },
    normal  = { gold = 20, xp = 10 },
    easy    = { gold = 18, xp = 8 },
    bully   = { gold = 16, xp = 6 },
}

local function normalizeDifficulty(difficulty)
    return string.lower(tostring(difficulty or "casual"))
end

-------------------------------------------------
-- ARENA REWARDS PER WINNING FIGHT
-------------------------------------------------
function xp.getArenaReward(difficulty)
    local reward = ARENA_REWARDS[normalizeDifficulty(difficulty)] or ARENA_REWARDS.casual
    return {
        gold = reward.gold,
        xp = reward.xp,
    }
end

function xp.getXpPerFight(difficulty)
    return xp.getArenaReward(difficulty).xp
end

function xp.getGoldPerFight(difficulty)
    return xp.getArenaReward(difficulty).gold
end

return xp
