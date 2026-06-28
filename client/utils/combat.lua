-- utils/combat.lua
-- Pixel War Online — Deterministic Combat Engine
-- Supports Leaders + Pets + Weapons + Spells

local combat = {}

local petsDB    = require("utils.pets")
local weapons   = require("utils.weapons")
local items     = require("utils.items")
local petScaler = require("utils.pet_scaler")
local spells    = require("utils.spells")

local ACCESSORY_SLOTS = {
    necklace = true,
    ring = true,
    charm = true,
}

local function clamp(value, minValue, maxValue)
    return math.max(minValue, math.min(maxValue, value))
end

local function countAccessoryStat(player, stat)
    local count = 0
    local equipped = player and player.equipped and player.equipped.accessories
    if not equipped then return count end

    for _, itemId in pairs(equipped) do
        local item = items[itemId]
        if item
            and ACCESSORY_SLOTS[item.slot]
            and item.statPercent
            and item.statPercent[stat]
        then
            count = count + 1
        end
    end

    return count
end

local function buildHiddenEffects(raw)
    return {
        critChance = clamp(0.06 + countAccessoryStat(raw, "attack") * 0.03, 0.06, 0.15),
        dodgeChance = clamp(0.08 + countAccessoryStat(raw, "speed") * 0.04, 0.08, 0.20),
    }
end

--------------------------------------------------
-- HELPERS
--------------------------------------------------
local function copyStats(src)
    return {
        atk = src.attack or src.atk or 0,
        def = src.defense or src.def or 0,
        spd = src.speed  or src.spd or 0,
        hp  = src.hp or 1
    }
end

--------------------------------------------------
-- BUILD COMBAT UNITS
--------------------------------------------------
local function buildLeader(raw)
    return {
        type  = "leader",
        id    = raw.id or "leader",
        name  = raw.name or "Leader",
        raw   = raw,
        stats = {
            atk = raw.attack  or raw.atk  or 0,
            def = raw.defense or raw.def  or 0,
            spd = raw.speed   or raw.spd  or 0,
            hp  = raw.hp or 1,
        },
        hp    = raw.hp or 1,
        alive = true,
        hidden = buildHiddenEffects(raw),
    }
end

local function petRefIds(petRef)
    if type(petRef) == "table" then
        local baseId = petRef.id or petRef.petId or petRef.baseId
        return baseId, petRef.instanceId or petRef.combatId
    end
    return petRef, nil
end

local function buildPet(petRef, avatarStats, side, scaledStats)
    local petId, instanceId = petRefIds(petRef)
    local def = petsDB[petId]
    if not def then return nil end
    local scaled = scaledStats or petScaler.scalePet(petId, avatarStats)
    return {
        type   = "pet",
        id     = instanceId or (side .. ":pet:" .. petId),
        baseId = petId,
        side   = side,
        name   = def.name,
        stats  = { atk=scaled.atk, def=scaled.def, spd=scaled.spd, hp=scaled.hp },
        hp     = scaled.hp,
        alive  = true,
    }
end

--------------------------------------------------
-- TARGET SELECTION
--------------------------------------------------
local function chooseTarget(attacker, enemy)
    local livingPets = {}
    for _, pet in ipairs(enemy.pets) do
        if pet.alive then table.insert(livingPets, pet) end
    end
    if #livingPets > 0 and math.random() < 0.65 then
        return livingPets[math.random(#livingPets)]
    end
    local livingLeaders = {}
    if enemy.leader and enemy.leader.alive then table.insert(livingLeaders, enemy.leader) end
    for _, leader in ipairs(enemy.leaders or {}) do
        if leader.alive then table.insert(livingLeaders, leader) end
    end
    if #livingLeaders == 0 then return nil end
    return livingLeaders[math.random(#livingLeaders)]
end

local function teamLeaderAlive(team)
    if team.leader and team.leader.alive then return true end
    for _, leader in ipairs(team.leaders or {}) do
        if leader.alive then return true end
    end
    return false
end

local function leaderTeamHp(team)
    local total = 0
    if team.leader and team.leader.alive then total = total + math.max(team.leader.hp or 0, 0) end
    for _, leader in ipairs(team.leaders or {}) do
        if leader.alive then total = total + math.max(leader.hp or 0, 0) end
    end
    return total
end

--------------------------------------------------
-- DODGE
--------------------------------------------------
local BASE_DODGE_CHANCE = 0.08

local function checkDodge(attacker, defender)
    local chance = (defender.hidden and defender.hidden.dodgeChance) or BASE_DODGE_CHANCE
    return math.random() < chance
end

--------------------------------------------------
-- CRIT
--------------------------------------------------
local BASE_CRIT_CHANCE = 0.06

local function checkCrit(attacker)
    if not attacker or attacker.type ~= "leader" then return false end
    local chance = (attacker.hidden and attacker.hidden.critChance) or BASE_CRIT_CHANCE
    return math.random() < chance
end

--------------------------------------------------
-- DAMAGE
--------------------------------------------------
local DEFENSE_MITIGATION_MIN = 0.30
local DEFENSE_MITIGATION_MAX = 0.35
local MIN_DAMAGE = 7

local function dealDamage(attacker, defender, dmgMultiplier, forceCrit)
    dmgMultiplier = dmgMultiplier or 1.0
    local atk = math.max(attacker.stats.atk or 0, 1)
    local def = math.max(defender.stats.def or 0, 0)
    local mitigationRoll = DEFENSE_MITIGATION_MIN + math.random() * (DEFENSE_MITIGATION_MAX - DEFENSE_MITIGATION_MIN)
    local mitigation = def * mitigationRoll
    local raw = (atk - mitigation) * dmgMultiplier
    local dmg = math.max(MIN_DAMAGE, math.floor(raw))
    local isCrit = forceCrit or checkCrit(attacker)
    if isCrit then dmg = math.floor(dmg * 1.5) end
    defender.hp = defender.hp - dmg
    if defender.hp <= 0 then
        defender.hp    = 0
        defender.alive = false
    end
    return dmg, isCrit
end

--------------------------------------------------
-- TURN ORDER
--------------------------------------------------
local DOUBLE_TURN_RATIO = 1.4

local function buildTurnQueue(teamA, teamB)
    local base     = {}
    local maxSpeed = 1

    local function add(unit, side)
        if unit.alive then
            local spd = unit.stats.spd or 1
            maxSpeed  = math.max(maxSpeed, spd)
            table.insert(base, { unit=unit, side=side, speed=spd })
        end
    end

    add(teamA.leader, "player")
    add(teamB.leader, "enemy")
    for _, leader in ipairs(teamA.leaders or {}) do add(leader, "player") end
    for _, leader in ipairs(teamB.leaders or {}) do add(leader, "enemy") end
    for _, p in ipairs(teamA.pets) do add(p, "player") end
    for _, p in ipairs(teamB.pets) do add(p, "enemy")  end
    if teamA.friend and teamA.friend.alive then
        add(teamA.friend, "player")
    end

    table.sort(base, function(a, b)
        if a.speed ~= b.speed then return a.speed > b.speed end
        return a.unit.id < b.unit.id
    end)

    local queue = {}
    for _, entry in ipairs(base) do
        table.insert(queue, entry)
        if entry.speed >= maxSpeed * DOUBLE_TURN_RATIO then
            table.insert(queue, entry)
        end
    end
    return queue
end

--------------------------------------------------
-- LOG HELPER
--------------------------------------------------
local function logSpell(log, entry)
    if entry then log[#log+1] = entry end
end


--------------------------------------------------
-- MAIN COMBAT
--------------------------------------------------
function combat.runBattle(playerRaw, enemyRaw)
    local log = {}

    local player = { leader=buildLeader(playerRaw), pets={}, leaders={}, friend=nil }
    local enemy  = { leader=buildLeader(enemyRaw),  pets={}, leaders={}            }
    player.leader.side = "player"
    enemy.leader.side = "enemy"

    local basePlayerAtk = player.leader.stats.atk

    local function logPlayerWeaponSwitch(newDef, newId)
        if newDef then
            log[#log+1] = {
                type      = "weapon_switch",
                unit      = "player:leader",
                weapon    = { id=newId, name=newDef.name, icon=newDef.icon },
                usesLeft  = 0,
                didRotate = true,
                nextWeapon = nil,
            }
        end
    end

    local function logEnemyWeaponSwitch(newDef, newId)
        if newDef then
            log[#log+1] = {
                type      = "weapon_switch",
                unit      = "enemy:leader",
                weapon    = { id=newId, name=newDef.name, icon=newDef.icon },
                usesLeft  = 0,
                didRotate = true,
                nextWeapon = nil,
            }
        end
    end

    local function applyWeaponPressure(attacker, target, damage)
        if not target or target.type ~= "leader" then return end

        local targetRaw = target.raw or ((target.id == player.leader.id) and playerRaw or enemyRaw)
        local didKnock, newDef, newId = weapons.addWeaponPressure(
            targetRaw,
            damage,
            attacker.stats and attacker.stats.atk,
            target.stats and target.stats.def,
            target.stats and target.stats.hp
        )

        if didKnock then
            log[#log+1] = { type="weapon_knock", unit=target.id }
            if target.id == player.leader.id then
                logPlayerWeaponSwitch(newDef, newId)
            elseif target.id == enemy.leader.id then
                logEnemyWeaponSwitch(newDef, newId)
            end
        end
    end

    local playerSpellState = spells.buildState(playerRaw)
    local enemySpellState  = spells.buildState(enemyRaw)
    local maxPetSlots = spells.hasUltimateTrainer(playerSpellState) and 3 or 2

    local function spellStateForSide(side)
        return side == "player" and playerSpellState or enemySpellState
    end

    local function getSpellEntry(state, id)
        if not state then return nil end
        local entry = state[id]
        if not entry then return nil end
        if entry.usesLeft ~= nil and entry.usesLeft <= 0 then return nil end
        return entry
    end

    local function consumeSpell(state, id)
        if not state then return end
        local entry = state[id]
        if not entry then return end
        if entry.usesLeft ~= nil then
            entry.usesLeft = entry.usesLeft - 1
        end
        entry.used = true
    end

    local function trySpellRoll(state, id)
        local entry = getSpellEntry(state, id)
        if not entry then return false end
        local chance = math.max(0, math.min(1, tonumber(entry.def and entry.def.triggerChance) or 0))
        if math.random() >= chance then return false end
        consumeSpell(state, id)
        return true
    end

    for i, id in ipairs(playerRaw.pets or {}) do
        if i > maxPetSlots then break end
        local baseId = petRefIds(id)
        local pet = buildPet(id, player.leader.stats, "player", playerRaw.petStats and playerRaw.petStats[baseId])
        if pet then table.insert(player.pets, pet) end
    end

    for i, defenderRaw in ipairs(playerRaw.defenders or {}) do
        defenderRaw.id = defenderRaw.id or ("player:leader:" .. tostring(i + 1))
        local leader = buildLeader(defenderRaw)
        leader.side = "player"
        table.insert(player.leaders, leader)
        for _, id in ipairs(defenderRaw.pets or {}) do
            local baseId = petRefIds(id)
            local pet = buildPet(id, leader.stats, "player", defenderRaw.petStats and defenderRaw.petStats[baseId])
            if pet then table.insert(player.pets, pet) end
        end
    end

    if spells.hasUltimateTrainer(playerSpellState) then
        log[#log+1] = { type="spell", spell="ultimate_trainer", caster="player" }
    end

    for _, id in ipairs(enemyRaw.pets or {}) do
        local baseId = petRefIds(id)
        local pet = buildPet(id, enemy.leader.stats, "enemy", enemyRaw.petStats and enemyRaw.petStats[baseId])
        if pet then table.insert(enemy.pets, pet) end
    end

    for i, defenderRaw in ipairs(enemyRaw.defenders or {}) do
        defenderRaw.id = defenderRaw.id or ("enemy:leader:" .. tostring(i + 1))
        local leader = buildLeader(defenderRaw)
        leader.side = "enemy"
        table.insert(enemy.leaders, leader)
        for _, id in ipairs(defenderRaw.pets or {}) do
            local baseId = petRefIds(id)
            local pet = buildPet(id, leader.stats, "enemy", defenderRaw.petStats and defenderRaw.petStats[baseId])
            if pet then table.insert(enemy.pets, pet) end
        end
    end

    log[#log+1] = { type="start", playerPets=#player.pets, enemyPets=#enemy.pets, playerTeamHp=leaderTeamHp(player), enemyTeamHp=leaderTeamHp(enemy) }

    local totalRoundsEst   = 8
    local stunGrenadeRound = math.random(1, totalRoundsEst)
    local callAFriendRound = math.random(1, totalRoundsEst)

    local round = 0

    while teamLeaderAlive(player) and teamLeaderAlive(enemy) do
        round = round + 1
        log[#log+1] = { type="round", round=round }

        if round == stunGrenadeRound then
            local entry = spells.tryStunGrenade(playerSpellState, enemy)
            if entry then
                logSpell(log, entry)
                for _, hit in ipairs(entry.hits or {}) do
                if hit.died then
                        log[#log+1] = { type="death", unit=hit.target, unitType="unknown" }
                    end
                end
                if not teamLeaderAlive(enemy) then break end
            end
        end

        if round == callAFriendRound then
            local entry = spells.tryCallAFriend(playerSpellState, tonumber(playerRaw.level) or 1)
            if entry then
                logSpell(log, entry)
                player.friend           = entry.friend
                player.friend.turnsLeft = 2
            end
        end

        local queue = buildTurnQueue(player, enemy)
        assert(#queue > 0, "Turn queue built with no units")

        for _, entry in ipairs(queue) do
            local attacker = entry.unit
            local skipTurn = not attacker.alive

            if not skipTurn and attacker.id == "player:friend" then
                if attacker.turnsLeft <= 0 then
                    attacker.alive = false
                    log[#log+1]    = { type="spell", spell="call_a_friend_leave", caster="player" }
                    skipTurn       = true
                else
                    attacker.turnsLeft = attacker.turnsLeft - 1
                end
            end

            if not skipTurn then

                -- ── WEAPON STAT BONUS (player leader attacking only) ──────
                -- Bonus applied before damage roll; advanceWeapon fires AFTER
                -- the hit resolves (covers both player hitting and being hit).
                if attacker.type == "leader" then
                    attacker.stats.atkBase = attacker.stats.atkBase or attacker.stats.atk
                    attacker.stats.atk = attacker.stats.atkBase
                    local attackerRaw = attacker.raw or (entry.side == "player" and playerRaw or enemyRaw)
                    local weapon, weaponId = weapons.getCurrentWeapon(attackerRaw)
                    if weapon and weapon.statPercent and weapon.statPercent.attack then
                        local bonus = weapon.statPercent.attack
                        if type(bonus) == "table" then
                            bonus = bonus.min + math.random() * (bonus.max - bonus.min)
                        end
                        attacker.stats.atk = math.floor(attacker.stats.atkBase * (1 + bonus))
                    end
                    attacker._currentWeaponId = weaponId
                end
                -- ──────────────────────────────────────────────────────────

                -- two piece combo check
                local bonusHit = false
                local wrathCrit = false
                if attacker.type == "leader" then
                    local attackerSpellState = spellStateForSide(entry.side)
                    if trySpellRoll(attackerSpellState, "two_piece_combo") then
                        bonusHit = true
                        log[#log+1] = { type="spell", spell="two_piece_combo", caster=entry.side, attacker=attacker.id }
                    end
                    if trySpellRoll(attackerSpellState, "wrath") then
                        wrathCrit = true
                        log[#log+1] = { type="spell", spell="wrath", caster=entry.side, attacker=attacker.id }
                    end
                end

                -- pick target
                local enemyTeam = (entry.side == "player") and enemy or player
                local target    = chooseTarget(attacker, enemyTeam)

                if target and target.alive then
                    if checkDodge(attacker, target) then
                        log[#log+1] = { type="dodge", attacker=attacker.id, target=target.id }
                    else
                        local dmg, isCrit = dealDamage(attacker, target, 1.0, wrathCrit)

                        -- last stand
                        if not target.alive and target.type == "leader" then
                            local targetSide = target.side or ((target.id == player.leader.id) and "player" or "enemy")
                            local targetSpellState = spellStateForSide(targetSide)
                            if getSpellEntry(targetSpellState, "last_stand") then
                                consumeSpell(targetSpellState, "last_stand")
                                target.hp = 1
                                target.alive = true
                                log[#log+1] = { type="spell", spell="last_stand", caster=targetSide, target=target.id }
                            end
                        end

                        -- counter check (leaders only, non-ranged attacks)
                        if target.type == "leader" and attacker.type == "leader" then
                            local attackerSide = attacker.side or ((attacker.id == player.leader.id) and "player" or "enemy")
                            local counterSide = target.side or ((target.id == player.leader.id) and "player" or "enemy")
                            local attackerRaw = attacker.raw or (attackerSide == "player" and playerRaw or enemyRaw)
                            local weapon = weapons.getCurrentWeapon(attackerRaw)
                            local isRanged = weapon and weapon.ranged or false
                            local counterState = spellStateForSide(counterSide)
                            if (not isRanged) and trySpellRoll(counterState, "counter") then
                                local counterDmg = math.max(math.floor(dmg * 0.5), 1)
                                attacker.hp = math.max(attacker.hp - counterDmg, 0)
                                if attacker.hp <= 0 then attacker.alive = false end
                                log[#log+1] = {
                                    type = "spell",
                                    spell = "counter",
                                    caster = counterSide,
                                    target = attacker.id,
                                    damage = counterDmg,
                                    targetHp = attacker.hp,
                                    targetDied = not attacker.alive,
                                }
                            end
                        end

                        log[#log+1] = {
                            type     = "hit",
                            attacker = attacker.id,
                            target   = target.id,
                            damage   = dmg,
                            crit     = isCrit,
                            targetHp = target.hp,
                            targetTeamHp = entry.side == "player" and leaderTeamHp(enemy) or leaderTeamHp(player),
                            weaponId = attacker._currentWeaponId,   -- ← HUD uses this
                        }

                        -- ── ACTION ADVANCE: player leader landed a hit ─────
                        applyWeaponPressure(attacker, target, dmg)
                        -- ──────────────────────────────────────────────────

                        if not target.alive then
                            local targetSide = target.side or ((target.id == player.leader.id) and "player" or "enemy")
                            local defeated = target.type == "leader"
                                and ((targetSide == "player" and not teamLeaderAlive(player))
                                    or (targetSide == "enemy" and not teamLeaderAlive(enemy)))
                            log[#log+1] = {
                                type="death",
                                unit=target.id,
                                unitType=target.type,
                                side=targetSide,
                                teamDefeated=defeated,
                            }
                            if target.type == "leader"
                                and ((targetSide == "player" and not teamLeaderAlive(player))
                                    or (targetSide == "enemy" and not teamLeaderAlive(enemy))) then
                                break
                            end
                        end

                        -- ── CRIT WEAPON KNOCK (leaders only) ──────────────
                        -- ──────────────────────────────────────────────────

                        if attacker.type == "leader" and not attacker.alive then
                            local attackerSide = attacker.side or ((attacker.id == player.leader.id) and "player" or "enemy")
                            log[#log+1] = {
                                type="death",
                                unit=attacker.id,
                                unitType=attacker.type,
                                side=attackerSide,
                                teamDefeated=(attackerSide == "player" and not teamLeaderAlive(player)) or (attackerSide == "enemy" and not teamLeaderAlive(enemy)),
                            }
                            if attacker.type == "leader" and ((entry.side == "player" and not teamLeaderAlive(player)) or (entry.side == "enemy" and not teamLeaderAlive(enemy))) then break end
                        end

                        -- bonus hit (two piece combo)
                        if bonusHit and target.alive then
                            local dmg2, crit2 = dealDamage(attacker, target, 1.0, false)
                            local targetSide = target.side or ((target.id == player.leader.id) and "player" or "enemy")
                            if not target.alive and target.type == "leader" then
                                local targetSpellState = spellStateForSide(targetSide)
                                if getSpellEntry(targetSpellState, "last_stand") then
                                    consumeSpell(targetSpellState, "last_stand")
                                    target.hp = 1
                                    target.alive = true
                                    log[#log+1] = { type="spell", spell="last_stand", caster=targetSide, target=target.id }
                                end
                            end
                            log[#log+1] = {
                                type     = "hit",
                                attacker = attacker.id,
                                target   = target.id,
                                damage   = dmg2,
                                crit     = crit2,
                                targetHp = target.hp,
                                targetTeamHp = entry.side == "player" and leaderTeamHp(enemy) or leaderTeamHp(player),
                                isCombo  = true,
                                weaponId = attacker._currentWeaponId,
                            }
                            applyWeaponPressure(attacker, target, dmg2)
                            if not target.alive then
                                local defeated = target.type == "leader"
                                    and ((targetSide == "player" and not teamLeaderAlive(player))
                                        or (targetSide == "enemy" and not teamLeaderAlive(enemy)))
                                log[#log+1] = {
                                    type="death",
                                    unit=target.id,
                                    unitType=target.type,
                                    side=targetSide,
                                    teamDefeated=defeated,
                                }
                                if target.type == "leader"
                                    and ((targetSide == "player" and not teamLeaderAlive(player))
                                        or (targetSide == "enemy" and not teamLeaderAlive(enemy))) then
                                    break
                                end
                            end
                        end
                    end
                end  -- end if target
            end  -- end if not skipTurn
        end  -- end for queue
    end  -- end while

    local winner = teamLeaderAlive(player) and "player" or "enemy"
    log[#log+1]  = { type="end", winner=winner }

    return { winner=winner, log=log }
end

return combat
