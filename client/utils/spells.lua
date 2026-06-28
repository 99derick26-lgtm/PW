-- utils/spells.lua
-- Pixel War Online — Spell System
-- Spells require level + gold purchase. Owned spells stored in player.spells = { "counter", ... }

local spells = {}

--------------------------------------------------
-- SPELL DEFINITIONS
--------------------------------------------------
spells.DEFS = {

    counter = {
        id            = "counter",
        name          = "Counter",
        description   = "Chance to counter melee attacks, reflecting 50% damage back",
        unlockLevel   = 2,
        cost          = 200,
        triggerChance = 0.15,
        maxUses       = nil,
        icon          = "assets/sprites/skills/counter.png",
    },

    two_piece_combo = {
        id            = "two_piece_combo",
        name          = "Two Piece Combo",
        description   = "Chance to land a second hit on your turn",
        unlockLevel   = 10,
        cost          = 500,
        triggerChance = 0.10,
        maxUses       = nil,
        icon          = "assets/sprites/skills/double_hit.png",
    },

    wrath = {
        id            = "wrath",
        name          = "Wrath",
        description   = "Chance to force a critical strike",
        unlockLevel   = 11,
        cost          = 600,
        triggerChance = 0.075,
        maxUses       = nil,
        icon          = "assets/sprites/skills/wrath.png",
    },

    last_stand = {
        id            = "last_stand",
        name          = "Last Stand",
        description   = "If a hit would kill you, survive with 1 HP instead",
        unlockLevel   = 13,
        cost          = 800,
        triggerChance = 1.0,
        maxUses       = 1,
        icon          = "assets/sprites/skills/last_stand.png",
    },

    stun_grenade = {
        id            = "stun_grenade",
        name          = "Stun Grenade",
        description   = "Once per battle: grenade hits all enemies",
        unlockLevel   = 15,
        cost          = 700,
        triggerChance = 0.60,
        maxUses       = 1,
        icon          = "assets/sprites/skills/stun_grenade.png",
    },

    call_a_friend = {
        id            = "call_a_friend",
        name          = "Call a Friend",
        description   = "Once per battle: summon a friend for 2 turns",
        unlockLevel   = 18,
        cost          = 900,
        triggerChance = 0.65,
        maxUses       = 1,
        icon          = "assets/sprites/skills/friend_call.png",
    },

    ultimate_trainer = {
        id            = "ultimate_trainer",
        name          = "Ultimate Trainer",
        description   = "Unlocks a 3rd pet slot in battle",
        unlockLevel   = 20,
        cost          = 1200,
        triggerChance = 1.0,
        maxUses       = nil,
        icon          = "assets/sprites/skills/ultimate_trainer.png",
    },
}

-- Ordered for UI display
spells.ORDER = {
    "counter",
    "two_piece_combo",
    "wrath",
    "last_stand",
    "stun_grenade",
    "call_a_friend",
    "ultimate_trainer",
}

--------------------------------------------------
-- OWNERSHIP
--------------------------------------------------
function spells.owns(player, spellId)
    if not player.spells then return false end
    for _, id in ipairs(player.spells) do
        if id == spellId then return true end
    end
    return false
end

function spells.canBuy(player, spellId)
    local def = spells.DEFS[spellId]
    if not def then return false end
    if spells.owns(player, spellId) then return false end
    if player.level < def.unlockLevel then return false end
    if (player.gold or 0) < def.cost then return false end
    return true
end

function spells.buy(player, spellId)
    if not spells.canBuy(player, spellId) then return false end
    local def = spells.DEFS[spellId]
    player.gold    = (player.gold or 0) - def.cost
    player.spells  = player.spells or {}
    table.insert(player.spells, spellId)
    return true
end

--------------------------------------------------
-- BUILD COMBAT STATE (only owned spells)
--------------------------------------------------
function spells.buildState(player)
    local state = {}
    for _, id in ipairs(player.spells or {}) do
        local def = spells.DEFS[id]
        if def then
            state[id] = {
                def      = def,
                usesLeft = def.maxUses,
                used     = false,
            }
        end
    end
    return state
end

--------------------------------------------------
-- INTERNAL HELPERS
--------------------------------------------------
local function canFire(state, id)
    local s = state[id]
    if not s then return false end
    if s.usesLeft ~= nil and s.usesLeft <= 0 then return false end
    return math.random() < s.def.triggerChance
end

local function consume(state, id)
    local s = state[id]
    if not s then return end
    if s.usesLeft ~= nil then
        s.usesLeft = s.usesLeft - 1
    end
    s.used = true
end

--------------------------------------------------
-- TRIGGER FUNCTIONS
--------------------------------------------------

function spells.onPlayerHit(state, attacker, player, weaponIsRanged, damage)
    if weaponIsRanged then return nil end
    if not canFire(state, "counter") then return nil end
    consume(state, "counter")
    local counterDmg = math.max(math.floor(damage * 0.5), 1)
    attacker.hp = math.max(attacker.hp - counterDmg, 0)
    if attacker.hp <= 0 then attacker.alive = false end
    return {
        type       = "spell",
        spell      = "counter",
        caster     = "player",
        target     = attacker.id,
        damage     = counterDmg,
        targetHp   = attacker.hp,
        targetDied = not attacker.alive,
    }
end

function spells.onPlayerTurnStart(state)
    if not canFire(state, "two_piece_combo") then return nil end
    consume(state, "two_piece_combo")
    return { type="spell", spell="two_piece_combo", caster="player" }
end

function spells.onPlayerHpLow(state, playerUnit, ratio)
    if ratio > 0.40 then return nil end
    if not canFire(state, "wrath") then return nil end
    consume(state, "wrath")
    return { type="spell", spell="wrath", caster="player" }
end

function spells.onFatalHit(state, playerUnit)
    if not canFire(state, "last_stand") then return false end
    consume(state, "last_stand")
    playerUnit.hp    = 1
    playerUnit.alive = true
    return true
end

function spells.tryStunGrenade(state, enemyTeam)
    if not canFire(state, "stun_grenade") then return nil end
    consume(state, "stun_grenade")
    local hits    = {}
    local targets = {}
    if enemyTeam.leader and enemyTeam.leader.alive then
        table.insert(targets, enemyTeam.leader)
    end
    for _, pet in ipairs(enemyTeam.pets or {}) do
        if pet.alive then table.insert(targets, pet) end
    end
    for _, t in ipairs(targets) do
        local dmg = math.max(math.random(8, 18), 1)
        t.hp = math.max(t.hp - dmg, 0)
        if t.hp <= 0 then t.alive = false end
        table.insert(hits, { target=t.id, damage=dmg, targetHp=t.hp, died=not t.alive })
    end
    return { type="spell", spell="stun_grenade", caster="player", hits=hits }
end

function spells.tryCallAFriend(state, playerLevel)
    if not canFire(state, "call_a_friend") then return nil end
    consume(state, "call_a_friend")
    playerLevel = math.max(1, math.floor(tonumber(playerLevel) or 1))
    local friendLevel = math.max(1, playerLevel + math.random(-3, 3))
    local friend = {
        type      = "friend",
        id        = "player:friend",
        name      = "Friend (Lv." .. friendLevel .. ")",
        level     = friendLevel,
        stats     = {
            atk = math.floor(friendLevel * 2.2),
            def = math.floor(friendLevel * 1.6),
            spd = math.floor(friendLevel * 1.4),
            hp  = math.floor(friendLevel * 8),
        },
        hp        = math.floor(friendLevel * 8),
        alive     = true,
        turnsLeft = 2,
        side      = "player",
    }
    return { type="spell", spell="call_a_friend", caster="player", friend=friend }
end

function spells.hasUltimateTrainer(state)
    return state["ultimate_trainer"] ~= nil
end

function spells.getMaxPetSlots(player)
    if spells.owns(player or {}, "ultimate_trainer") then
        return 3
    end
    return 2
end

function spells.getEquippedPetsForBattle(player)
    player = player or {}
    local equipped = player.equipped or {}
    local pets = equipped.pets or {}
    local maxPets = spells.getMaxPetSlots(player)
    local active = {}
    for i = 1, math.min(#pets, maxPets) do
        active[#active + 1] = pets[i]
    end
    return active
end

return spells
