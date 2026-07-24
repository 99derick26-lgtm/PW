-- scenes/arena_battle.lua
local composer  = require("composer")
local scene     = composer.newScene()
local petsDB    = require("utils.pets")
local saveUtil  = require("utils.save")
local api       = require("utils.api")
local sync      = require("utils.sync")
local statsUtil = require("utils.stats")
local combat    = require("utils.combat")
local weapons   = require("utils.weapons")
local petScaler = require("utils.pet_scaler")
local spells    = require("utils.spells")
local ui        = require("utils.ui")
local petAssets = require("utils.pet_assets")
local tasksUtil = require("utils.tasks")
local xpUtil    = require("utils.xp")
local levelUpPopup = require("utils.levelup_popup")
local chestRewards = require("utils.chest_rewards")
local notifications = require("utils.notifications")

-------------------------------------------------
-- MODULE-LEVEL STATE
-------------------------------------------------
local battleRoot      = nil
local activeTimers    = {}
local player          = nil
local opponent        = nil
local maxPlayerHp     = 1
local maxEnemyHp      = 1
local currentPlayerHp = 1
local currentEnemyHp  = 1
local actorSprites    = {}
local battleSpeed     = 1
local battleFinished  = false
local skipRequested   = false
local activeResult    = nil
local battleBorder    = nil
local endTapShield    = nil
local pendingBattleResult = nil
local hpBars = {
    enemyBg = nil,
    enemyFill = nil,
    enemyLabel = nil,
    playerBg = nil,
    playerFill = nil,
    playerLabel = nil,
}

local hpFrameSheet = nil
local streetBrawlerSheets = {}
local ATTACK_PACE_SCALE = 1.40
local HP_FRAME_FRAMES = {
    player = { x = 398, y = 376, width = 230, height = 660 },
    enemy  = { x = 398, y = 541, width = 230, height = 660 },
}

-- Weapon HUD state
local weaponHUD = {
    -- floatingIcon: follows the attacker sprite during attacks
    floatingIcon  = nil,
    -- pips: small dots showing uses remaining (anchored bottom-center)
    pipGroup      = nil,
    pips          = {},          -- array of rect display objects
    usesLeft      = 0,
    totalUses     = 3,
    -- next weapon preview (small icon, bottom-right of HUD)
    nextIcon      = nil,
    nextLabel     = nil,
}
local enemyWeaponHUD = {
    group = nil,
    currentIcon = nil,
    nameLabel = nil,
}

-- forward declarations
local playCombatLog
local applyRewards
local updateHpBars
local performAttack
local updateWeaponHUD
local finishBattle
local getWeaponDefForAttacker
local setStreetBrawlerIdleVisible

local function scaledTime(ms)
    return math.max(1, math.floor((ms or 1) / math.max(1, battleSpeed)))
end

local function attackPacedTime(ms)
    return math.max(1, math.floor((ms or 1) * ATTACK_PACE_SCALE))
end

local function trackDelay(delay, fn)
    local t = timer.performWithDelay(scaledTime(delay), fn)
    table.insert(activeTimers, t)
    return t
end

-------------------------------------------------
-- HELPERS
-------------------------------------------------
local function normalizeActorId(id)
    if actorSprites and actorSprites[id] then return id end
    if id=="enemy" or id=="enemy:leader" then return "enemy" end
    if id=="player" or id=="player:leader" then return "player" end
    return id
end

local function canonicalPetId(id)
    if not id then return nil end
    if type(id) == "table" then
        return id.id or id.petId or id.baseId
    end
    return id:match("^.-:pet:%d+:(.+)$")
        or id:match("^.-:pet:.-:(.+)$")
        or id:match("^.-:pet:(.+)$")
        or id
end

local function enemyPetRefsFor(owner, ownerIndex)
    local refs = {}
    if not owner then return refs end
    for _, petRef in ipairs(owner.pets or {}) do
        local petId = canonicalPetId(petRef)
        if petId then
            refs[#refs + 1] = {
                id = petId,
                petId = petId,
                baseId = petId,
                instanceId = "enemy:pet:" .. tostring(ownerIndex or 1) .. ":" .. tostring(petId),
            }
        end
    end
    return refs
end

local function playerPetRefsFor(pets)
    local refs = {}
    for i, petRef in ipairs(pets or {}) do
        local petId = canonicalPetId(petRef)
        if petId then
            refs[#refs + 1] = {
                id = petId,
                petId = petId,
                baseId = petId,
                instanceId = "player:pet:" .. tostring(i) .. ":" .. tostring(petId),
            }
        end
    end
    return refs
end

local function collectEnemyPetRefs()
    local refs = {}
    local function append(list)
        for _, ref in ipairs(list) do refs[#refs + 1] = ref end
    end
    append(enemyPetRefsFor(opponent, 1))
    for i, defender in ipairs(opponent and opponent.defenders or {}) do
        append(enemyPetRefsFor(defender, i + 1))
    end
    return refs
end

local function estimateEnemyTeamHp()
    if not opponent then return 1 end
    local total = math.max(1, tonumber(opponent.hp) or 1)
    for _, defender in ipairs(opponent.defenders or {}) do
        total = total + math.max(1, tonumber(defender.hp) or opponent.hp or 1)
    end
    return total
end

local function estimatePlayerTeamHp()
    if not player then return 1 end
    local baseHp = player.hp
    if not (opponent and opponent.guildWar == true and composer.getVariable("guildWarBattle")) then
        baseHp = statsUtil.calculate(player).hp
    end
    local total = math.max(1, tonumber(baseHp) or 1)
    for _, defender in ipairs(player.defenders or {}) do
        total = total + math.max(1, tonumber(defender.hp) or baseHp or 1)
    end
    return total
end

local function setSprite(sprite, path)
    if not sprite or not sprite.removeSelf then return end
    sprite.fill = { type="image", filename=path }
end

local function resourceExists(path)
    if not path or not system or not system.pathForFile then return false end
    local ok, resolved = pcall(system.pathForFile, path, system.ResourceDirectory)
    if not ok or not resolved then return false end
    local file = io.open(resolved, "rb")
    if file then
        io.close(file)
        return true
    end
    return false
end

local function trySetSprite(sprite, path)
    if resourceExists(path) then
        setSprite(sprite, path)
        return true
    end
    print("[arena_battle] missing sprite: " .. tostring(path))
    return false
end

local function setPetPoseOrIdle(sprite, petId, team, pose)
    if not sprite or not petId then return false end
    local path
    if pose == "attack" then
        path = petAssets.attackWithFallback(petId, team)
    elseif pose == "hit" then
        path = petAssets.hitWithFallback(petId, team)
    elseif pose == "dead" then
        path = petAssets.deadWithFallback(petId, team)
    else
        path = petAssets.battleWithFallback(petId, team)
    end
    if trySetSprite(sprite, path) then return true end
    return trySetSprite(sprite, petAssets.battleWithFallback(petId, team))
end

local function spawnPetFallback(root, size, team)
    local fallback = display.newRoundedRect(root, 0, 0, size, size, math.max(6, math.floor(size * 0.16)))
    if team == "enemy" then
        fallback:setFillColor(0.28, 0.08, 0.10, 0.95)
        fallback:setStrokeColor(1.0, 0.40, 0.45, 0.85)
    else
        fallback:setFillColor(0.08, 0.16, 0.30, 0.95)
        fallback:setStrokeColor(0.40, 0.82, 1.0, 0.85)
    end
    fallback.strokeWidth = 2
    return fallback
end

local FORMATION_REF_W = 390
local FORMATION_REF_H = 3200
local FORMATION = {
    enemy = {
        leaderY = 850,
        backPetsY = 850,
        frontPetsY = 980,
        rearScale = 4,
        frontScale = 4.33,
        petOffsets = {
            { x = -130, row = "front" },
            { x = 130, row = "front" },
            { x = -72, row = "back" },
            { x = 72, row = "back" },
            { x = -178, row = "front" },
            { x = 178, row = "front" },
        },
    },
    player = {
        leaderY = 2350,
        backPetsY = 2350,
        frontPetsY = 2500,
        rearScale = 4.66,
        frontScale = 5,
        petOffsets = {
            { x = -180, row = "front" },
            { x = 180, row = "front" },
            { x = -108, row = "back" },
            { x = 108, row = "back" },
            { x = -245, row = "front" },
            { x = 245, row = "front" },
        },
    },
}

local function formationY(refY)
    local top = display.screenOriginY
    return top + (refY / FORMATION_REF_H) * display.actualContentHeight
end

local function formationX(refOffset)
    return display.contentCenterX + (refOffset / FORMATION_REF_W) * display.actualContentWidth
end

local function clampFormationX(x, spriteWidth)
    local left = display.screenOriginX + math.max(18, (spriteWidth or 0) * 0.38)
    local right = display.screenOriginX + display.actualContentWidth - math.max(18, (spriteWidth or 0) * 0.38)
    return math.max(left, math.min(right, x))
end

local function petBaseDimensions(def)
    local tier = def and def.size or "medium"
    if tier == "small" then return 16, 16 end
    if tier == "medium" then return 24, 24 end
    if tier == "large" then return 32, 32 end
    if tier == "massive" then return 48, 48 end
    return 24, 24
end

local function petDisplayDimensions(def, formationScale)
    local w, h = petBaseDimensions(def)
    return w * formationScale, h * formationScale
end

local function placeUnit(sprite, x, y, team)
    if not sprite then return end
    sprite.x = x
    sprite.y = y
    sprite.homeX = x
    sprite.homeY = y
    sprite.team = team
end

local function updateUnitHpBar(sprite)
    if not sprite or not sprite.hpFill or not sprite.hpBg then return end
    local maxHp = math.max(1, tonumber(sprite.maxHp) or 1)
    local hp = math.max(0, tonumber(sprite.currentHp) or maxHp)
    local ratio = math.max(0, math.min(hp / maxHp, 1))
    local maxW = sprite.hpBarW or sprite.hpBg.width or 42
    local width = math.max(2, maxW * ratio)
    sprite.hpFill.width = width
    sprite.hpFill.x = sprite.hpBg.x - maxW * 0.5
end

local function attachUnitHpBar(sprite, maxHp, team)
    return
end

local function attachUnitHpBar_DISABLED(sprite, maxHp, team)
    if not sprite or not battleRoot then return end
    sprite.maxHp = math.max(1, tonumber(maxHp) or 1)
    sprite.currentHp = sprite.maxHp

    local group = display.newGroup()
    battleRoot:insert(group)
    local barW = math.max(38, math.min(72, (sprite.width or 48) * 0.58))
    local barH = 5
    local yOffset = -((sprite.height or 64) * 0.54) - 7
    local bg = display.newRoundedRect(group, sprite.x, sprite.y + yOffset, barW, barH, 2)
    bg:setFillColor(0.02, 0.03, 0.06, 0.86)
    bg.strokeWidth = 1
    bg:setStrokeColor(team == "enemy" and 1.0 or 0.30, team == "enemy" and 0.35 or 0.75, team == "enemy" and 0.35 or 1.0, 0.62)
    local fill = display.newRoundedRect(group, bg.x - barW * 0.5, bg.y, barW, barH - 2, 2)
    fill.anchorX = 0
    fill:setFillColor(team == "enemy" and 1.0 or 0.25, team == "enemy" and 0.28 or 0.75, team == "enemy" and 0.30 or 1.0, 0.92)
    sprite.hpGroup = group
    sprite.hpBg = bg
    sprite.hpFill = fill
    sprite.hpBarW = barW
    updateUnitHpBar(sprite)
end

local function sendLowerUnitsToFront()
    local units = {}
    for _, sprite in pairs(actorSprites or {}) do
        if sprite and sprite.removeSelf and not sprite._depthQueued then
            sprite._depthQueued = true
            units[#units + 1] = sprite
        end
    end
    table.sort(units, function(a, b)
        return (a.homeY or a.y or 0) < (b.homeY or b.y or 0)
    end)
    for _, sprite in ipairs(units) do
        sprite._depthQueued = nil
        sprite:toFront()
    end
    for _, sprite in pairs(actorSprites or {}) do
        if sprite and sprite.hpGroup and sprite.hpGroup.toFront then
            sprite.hpGroup:toFront()
        end
    end
end

local function playerSkinId()
    return (player and player.appearance and player.appearance.skinId)
        or (player and player.skinId)
        or "street_brawler"
end

local function opponentSkinId()
    return (opponent and opponent.visualId) or "street_brawler"
end

local function isGuildLootBattle()
    if opponent and opponent.guildLoot == true and composer.getVariable("battleMode") == "guild_loot" then
        return true
    end
    if opponent and opponent.guildLoot == true and composer.getVariable("guildLootChallenge") then
        return true
    end
    if composer.getVariable("guildLootChallenge") and not (opponent and opponent.guildLoot == true) then
        composer.setVariable("guildLootChallenge", nil)
    end
    return false
end

local function activeGuildWarBattle()
    local war = composer.getVariable("guildWarBattle")
    if not war then return nil end
    if (opponent and opponent.guildWar ~= true) or composer.getVariable("battleMode") ~= "guild_war" then
        composer.setVariable("guildWarBattle", nil)
        return nil
    end
    return war
end

local function isGuildWarBattle()
    return activeGuildWarBattle() ~= nil
end

local function activeGuildLeagueChallenge()
    local challenge = composer.getVariable("guildLeagueChallenge")
    if not challenge then return nil end
    if composer.getVariable("battleMode") ~= "guild_league_challenge" then
        composer.setVariable("guildLeagueChallenge", nil)
        return nil
    end
    return challenge
end

local function isGuildLeagueChallenge()
    return activeGuildLeagueChallenge() ~= nil
end

local function withoutCallFriend(list)
    local out = {}
    for _, id in ipairs(list or {}) do
        if id ~= "call_a_friend" then out[#out + 1] = id end
    end
    return out
end

local function reportRemoteFight(result)
    if not result or composer.getVariable("battleMode") == "arena_replay" then return end
    if not opponent then return end

    local targetPlayerId = opponent.serverPlayerId
    local mode = "fight"
    if opponent.isConquest and opponent.conquestTarget and opponent.conquestTarget.playerId then
        targetPlayerId = opponent.conquestTarget.playerId
        mode = "recruit"
    end
    if not targetPlayerId or tostring(targetPlayerId):match("^bot_") then return end

    api.pvp.report({
        targetPlayerId = targetPlayerId,
        mode = mode,
        result = {
            winner = result.winner,
            log = result.log,
        },
        challenger = {
            name = player.name or player.displayName or "Player",
            displayName = player.name or player.displayName or "Player",
            visualId = playerSkinId(),
            skinId = playerSkinId(),
            level = player.level,
            attack = player.attack,
            defense = player.defense,
            speed = player.speed,
            hp = statsUtil.calculate(player).hp,
            equipped = player.equipped,
            pets = spells.getEquippedPetsForBattle(player),
            currentWeaponIndex = player.currentWeaponIndex,
            weaponUsesLeft = player.weaponUsesLeft,
        },
    }, function() end)
end

local function setCharacterPose(unit, pose, fallbackPose)
    local normalized = normalizeActorId(unit)
    local sprite = actorSprites[normalized]
    if not sprite then return false end

    local skin = sprite.skinId or (normalized == "player" and playerSkinId() or opponentSkinId())
    local base = "assets/sprites/characters/" .. skin .. "/"
    local extensions = { ".png", ".jpg", ".jpeg" }
    if setStreetBrawlerIdleVisible then
        setStreetBrawlerIdleVisible(sprite, false)
    end
    sprite.alpha = 1

    for _, ext in ipairs(extensions) do
        if trySetSprite(sprite, base .. pose .. ext) then return true end
    end
    if fallbackPose then
        for _, ext in ipairs(extensions) do
            if trySetSprite(sprite, base .. fallbackPose .. ext) then return true end
        end
    end
    return false
end

local function getHpFrameSheet()
    if hpFrameSheet then return hpFrameSheet end
    hpFrameSheet = graphics.newImageSheet("assets/sprites/ui/Hpp.png", {
        frames = {
            HP_FRAME_FRAMES.player,
            HP_FRAME_FRAMES.enemy,
        }
    })
    return hpFrameSheet
end

-------------------------------------------------
-- WEAPON HUD
-- Shows only: current weapon icon + weapon name. Nothing else.
-------------------------------------------------
local WEAPON_HUD_X = display.contentCenterX
local WEAPON_HUD_Y = display.contentHeight - 60

local function buildWeaponHUD(root, player)
    local hudGroup = display.newGroup()
    root:insert(hudGroup)
    weaponHUD.pipGroup = hudGroup

    -- background panel
    local panelW = 140
    local panelH = 32
    local panel  = display.newRoundedRect(hudGroup, WEAPON_HUD_X, WEAPON_HUD_Y, panelW, panelH, 7)
    panel:setFillColor(0.03, 0.07, 0.18, 0.85)
    panel.strokeWidth = 1.5
    panel:setStrokeColor(0.25, 0.55, 1.0, 0.6)

    -- weapon icon (left of panel)
    local iconX = WEAPON_HUD_X - 52
    local ok, icon = pcall(display.newImageRect, hudGroup,
        "assets/sprites/weapons/unarmed.png", 26, 26)
    if ok and icon then
        icon.x = iconX
        icon.y = WEAPON_HUD_Y
        weaponHUD.currentIcon = icon
    end

    -- weapon name
    local nameLabel = display.newText({
        parent   = hudGroup,
        text     = "Unarmed",
        x        = WEAPON_HUD_X + 8,
        y        = WEAPON_HUD_Y,
        font     = ui.FONT_BOLD,
        fontSize = 11,
        align    = "center",
    })
    nameLabel:setFillColor(0.8, 0.9, 1.0)
    weaponHUD.nameLabel = nameLabel

    updateWeaponHUD(player)
end

-- Sync icon and name only
updateWeaponHUD = function(p)
    if not p then return end
    local def, weaponId = weapons.getCurrentWeapon(p)

    if weaponHUD.currentIcon then
        local iconPath = (def and def.icon) or "assets/sprites/weapons/unarmed.png"
        weaponHUD.currentIcon.fill = { type="image", filename=iconPath }
    end
    if weaponHUD.nameLabel then
        weaponHUD.nameLabel.text = (def and def.name) or "Unarmed"
    end
end


-------------------------------------------------
-- FLOATING WEAPON (attaches to attacker sprite)
-- Spawns during performAttack, removed when attacker returns home.
-------------------------------------------------
local function isMeleeWeapon(weaponDef)
    return weaponDef and weaponDef.icon and weaponDef.ranged ~= true
end

local function meleeWeaponDisplaySize(weaponDef)
    local token = string.lower(table.concat({
        tostring(weaponDef and weaponDef.id or ""),
        tostring(weaponDef and weaponDef.name or ""),
        tostring(weaponDef and weaponDef.icon or ""),
    }, " "))

    if token:find("dagger", 1, true) then return 44 end
    if token:find("spear", 1, true) or token:find("trident", 1, true) then return 78 end
    if token:find("hammer", 1, true)
        or token:find("axe", 1, true)
        or token:find("executioner", 1, true)
        or token:find("mammoth", 1, true)
    then
        return 66
    end
    if token:find("sickle", 1, true)
        or token:find("sword", 1, true)
        or token:find("blade", 1, true)
        or token:find("katana", 1, true)
        or token:find("machete", 1, true)
        or token:find("crowbar", 1, true)
        or token:find("stick", 1, true)
        or token:find("pipe", 1, true)
    then
        return 58
    end
    return 54
end

local function attachWeaponToSprite(attackerSprite, weaponDef)
    -- clean up previous floating icon if any
    if weaponHUD.floatingIcon and weaponHUD.floatingIcon.removeSelf then
        weaponHUD.floatingIcon:removeSelf()
        weaponHUD.floatingIcon = nil
    end

    if not attackerSprite or not weaponDef or not weaponDef.icon then return end

    local melee = isMeleeWeapon(weaponDef)
    local iconSize = melee and meleeWeaponDisplaySize(weaponDef) or 36
    local ok, icon = pcall(display.newImageRect, battleRoot,
        weaponDef.icon, iconSize, iconSize)
    if not (ok and icon) then return end
    icon._battleTransient = true

    if melee then
        -- Weapon art is consistently drawn from handle (lower-left) to tip
        -- (upper-right). Anchor near the handle so rotation stays in the fist.
        icon.anchorX = 0.18
        icon.anchorY = 0.82
        icon._melee = true
    end
    local offsetX = (attackerSprite.team == "player") and 24 or -24
    icon.x = attackerSprite.x + offsetX
    icon.y = attackerSprite.y - 10
    icon.alpha = 0.92

    weaponHUD.floatingIcon = icon
    return icon
end

local function positionMeleeWeapon(icon, attackVisual, team, frame)
    if not icon or not icon.removeSelf or not icon._melee then return false end
    if not attackVisual or not attackVisual.removeSelf then return false end

    local grip
    if team == "player" then
        grip = {
            { x = 0.46, y = 0.08, rotation = -45 },
            { x = 0.13, y = 0.60, rotation = 82 },
            { x = 0.13, y = 0.66, rotation = 125 },
        }
    else
        grip = {
            { x = 0.42, y = 0.12, rotation = -45 },
            { x = 0.64, y = 0.66, rotation = 82 },
            { x = 0.68, y = 0.69, rotation = 125 },
        }
    end

    local pose = grip[math.max(1, math.min(3, frame or 1))]
    local visualWidth = attackVisual._displayWidth
        or attackVisual.contentWidth or attackVisual.width
    local visualHeight = attackVisual._displayHeight
        or attackVisual.contentHeight or attackVisual.height
    icon.x = attackVisual.x + (pose.x - 0.5) * visualWidth
    icon.y = attackVisual.y + (pose.y - 0.5) * visualHeight
    icon.rotation = pose.rotation
    icon:toFront()
    return true
end

local function detachWeaponFromSprite()
    if weaponHUD.floatingIcon and weaponHUD.floatingIcon.removeSelf then
        local icon = weaponHUD.floatingIcon
        weaponHUD.floatingIcon = nil
        transition.to(icon, {
            alpha = 0, time = 120,
            onComplete = function()
                if icon and icon.removeSelf then icon:removeSelf() end
            end
        })
    end
end

-------------------------------------------------
-- VISUAL HELPERS
-------------------------------------------------
local function slideTo(sprite, x, y, time, onComplete)
    if not sprite then return end
    transition.to(sprite, { x=x, y=y, time=scaledTime(time),
        transition=easing.inOutQuad, onComplete=onComplete })
end

local STREET_BRAWLER_ANIM = {
    run_front = {
        path = "assets/sprites/characters/street_brawler/run_front_sheet.png",
        columns = 4,
        rows = 2,
        frameCount = 8,
    },
    run_rear = {
        path = "assets/sprites/characters/street_brawler/run_rear_sheet.png",
        columns = 4,
        rows = 2,
        frameCount = 8,
    },
    attack = {
        path = "assets/sprites/characters/street_brawler/attack_sheet.png",
        columns = 3,
        rows = 2,
        frameCount = 6,
    },
    melee_attack = {
        path = "assets/sprites/characters/street_brawler/melee_attack_sheet.png",
        columns = 3,
        rows = 2,
        frameCount = 6,
    },
    weapon_idle = {
        path = "assets/sprites/characters/street_brawler/weapon_idle_sheet.png",
        columns = 2,
        rows = 1,
        frameCount = 2,
    },
}

-- Opaque-pixel measurements from the idle art and normalized animation cells.
-- Scaling by visible height (instead of PNG canvas size) keeps the animated
-- character at the same body scale as the original idle pose.
local STREET_BRAWLER_METRICS = {
    front = {
        idleHeight = 0.9300,
        idleBottom = 0.96498,
        run = { height = 0.8945, bottom = 0.9650 },
        attack = { height = 0.8920, bottom = 0.96354 },
        melee_attack = { height = 0.8246, bottom = 0.96962 },
        weapon_idle = { height = 0.90365, bottom = 0.96875 },
    },
    rear = {
        idleHeight = 0.9270,
        idleBottom = 0.97967,
        run = { height = 0.8968, bottom = 0.9650 },
        attack = { height = 0.8920, bottom = 0.96354 },
        melee_attack = { height = 0.8247, bottom = 0.96962 },
        weapon_idle = { height = 0.90625, bottom = 0.97135 },
    },
}

local function getStreetBrawlerSheet(name)
    if streetBrawlerSheets[name] then return streetBrawlerSheets[name] end
    local def = STREET_BRAWLER_ANIM[name]
    if not def or not resourceExists(def.path) then return nil end
    local sheet = graphics.newImageSheet(def.path, {
        width = 256,
        height = 384,
        numFrames = def.frameCount,
        sheetContentWidth = 256 * def.columns,
        sheetContentHeight = 384 * def.rows,
    })
    streetBrawlerSheets[name] = sheet
    return sheet
end

local function sizeStreetBrawlerVisual(visual, sprite, animationName, facingOverride)
    local idleFacing = sprite.team == "player" and "rear" or "front"
    local animationFacing = facingOverride or idleFacing
    local idleMetrics = STREET_BRAWLER_METRICS[idleFacing]
    local animation = STREET_BRAWLER_METRICS[animationFacing][animationName]
    if not animation then return end

    local frameHeight = 384
    local scale = ((sprite.height or 64) * idleMetrics.idleHeight)
        / (frameHeight * animation.height)
    visual.xScale = scale
    visual.yScale = scale
    visual._displayWidth = 256 * scale
    visual._displayHeight = frameHeight * scale

    -- Align the lowest opaque pixel with the idle pose's lowest opaque pixel.
    local idleBottomOffset = (sprite.height or 64)
        * (idleMetrics.idleBottom - 0.5)
    local animationBottomOffset = frameHeight * scale
        * (animation.bottom - 0.5)
    visual._logicalYOffset = idleBottomOffset - animationBottomOffset
end

local function isAnimatedStreetBrawler(sprite)
    return sprite
        and not sprite.petId
        and (sprite.skinId or "street_brawler") == "street_brawler"
end

setStreetBrawlerIdleVisible = function(sprite, visible)
    if not sprite then return end
    local idleVisual = sprite._weaponIdleVisual
    local heldWeapon = sprite._weaponIdleIcon
    if idleVisual and idleVisual.removeSelf then
        idleVisual.alpha = visible and 1 or 0
    end
    if heldWeapon and heldWeapon.removeSelf then
        heldWeapon.alpha = visible and 1 or 0
    end
    if visible then
        sprite.alpha = idleVisual and idleVisual.removeSelf and 0 or 1
    else
        sprite.alpha = 0
    end
end

local function clearStreetBrawlerWeaponIdle(sprite)
    if not sprite then return end
    if sprite._weaponIdleVisual and sprite._weaponIdleVisual.removeSelf then
        sprite._weaponIdleVisual:removeSelf()
    end
    if sprite._weaponIdleIcon and sprite._weaponIdleIcon.removeSelf then
        sprite._weaponIdleIcon:removeSelf()
    end
    sprite._weaponIdleVisual = nil
    sprite._weaponIdleIcon = nil
    sprite.alpha = 1
end

local function refreshStreetBrawlerWeaponIdle(sprite, weaponDef)
    clearStreetBrawlerWeaponIdle(sprite)
    if not isAnimatedStreetBrawler(sprite) or not isMeleeWeapon(weaponDef) then
        return
    end

    local sheet = getStreetBrawlerSheet("weapon_idle")
    if not sheet then return end
    local facing = sprite.team == "player" and "rear" or "front"
    local sourceFrame = facing == "rear" and 2 or 1
    local visual = display.newSprite(battleRoot, sheet, {
        {
            name = "armed_idle",
            frames = { sourceFrame },
            time = 1,
            loopCount = 1,
        },
    })
    sizeStreetBrawlerVisual(visual, sprite, "weapon_idle", facing)
    visual.x = sprite.x
    visual.y = sprite.y + (visual._logicalYOffset or 0)
    visual:setFrame(1)
    visual:toFront()

    local iconSize = meleeWeaponDisplaySize(weaponDef)
    local ok, icon = pcall(display.newImageRect, battleRoot,
        weaponDef.icon, iconSize, iconSize)
    if ok and icon then
        icon.anchorX = 0.18
        icon.anchorY = 0.82
        local grip = facing == "rear"
            and { x = 0.85, y = 0.64 }
            or { x = 0.18, y = 0.64 }
        icon.x = visual.x + (grip.x - 0.5) * visual._displayWidth
        icon.y = visual.y + (grip.y - 0.5) * visual._displayHeight
        -- Enemy/front points up-left; player/rear points up-right.
        icon.rotation = facing == "rear" and 0 or -90
        icon:toFront()
    end

    sprite._weaponIdleVisual = visual
    sprite._weaponIdleIcon = ok and icon or nil
    setStreetBrawlerIdleVisible(sprite, true)
end

local function makeStreetBrawlerRunVisual(sprite, returningHome)
    if not isAnimatedStreetBrawler(sprite) then return nil end
    local facing
    if returningHome then
        facing = sprite.team == "player" and "front" or "rear"
    else
        facing = sprite.team == "player" and "rear" or "front"
    end
    local name = "run_" .. facing
    local sheet = getStreetBrawlerSheet(name)
    if not sheet then return nil end

    local visual = display.newSprite(battleRoot, sheet, {
        {
            name = "run",
            start = 1,
            count = 8,
            time = scaledTime(attackPacedTime(440)),
            loopCount = 0,
        },
    })
    sizeStreetBrawlerVisual(visual, sprite, "run", facing)
    visual.x = sprite.x
    visual.y = sprite.y + visual._logicalYOffset
    visual._battleTransient = true
    visual:play()
    visual:toFront()
    setStreetBrawlerIdleVisible(sprite, false)
    return visual
end

local function makeStreetBrawlerAttackVisual(sprite, x, y, attackStyle)
    if not isAnimatedStreetBrawler(sprite) then return nil end
    local sheetName
    if attackStyle == "melee" then
        sheetName = "melee_attack"
    elseif attackStyle == "unarmed" then
        sheetName = "attack"
    else
        -- Ranged poses intentionally remain separate from punch/melee.
        return nil
    end
    local sheet = getStreetBrawlerSheet(sheetName)
    if not sheet then return nil end

    local firstFrame = sprite.team == "player" and 4 or 1
    local visual = display.newSprite(battleRoot, sheet, {
        {
            name = "attack",
            frames = { firstFrame, firstFrame + 1, firstFrame + 2 },
            time = scaledTime(attackPacedTime(360)),
            loopCount = 1,
        },
    })
    sizeStreetBrawlerVisual(visual, sprite, sheetName)
    visual.x = x or sprite.x
    visual.y = (y or sprite.y) + visual._logicalYOffset
    visual._battleTransient = true
    visual:setFrame(1)
    visual:toFront()
    setStreetBrawlerIdleVisible(sprite, false)
    return visual
end

local function removeAttackVisual(visual)
    if visual and visual.removeSelf then visual:removeSelf() end
end

local function clearBattleTransientVisuals(group)
    if not group or not group.numChildren then return end
    for i = group.numChildren, 1, -1 do
        local child = group[i]
        if child then
            if child._battleTransient then
                if child.removeSelf then child:removeSelf() end
            elseif child.numChildren then
                clearBattleTransientVisuals(child)
            end
        end
    end
    weaponHUD.floatingIcon = nil
end

local function moveAttackSprite(sprite, visual, x, y, time, onComplete)
    if visual and visual.removeSelf then
        slideTo(sprite, x, y, time)
        slideTo(visual, x, y + (visual._logicalYOffset or 0), time, onComplete)
    else
        slideTo(sprite, x, y, time, onComplete)
    end
end

local function buildEnemyWeaponHUD(root, enemy)
    local hudGroup = display.newGroup()
    root:insert(hudGroup)
    enemyWeaponHUD.group = hudGroup

    local panelW = 140
    local panelH = 30
    local panelX = display.contentCenterX
    local panelY = 94
    local panel = display.newRoundedRect(hudGroup, panelX, panelY, panelW, panelH, 7)
    panel:setFillColor(0.16, 0.04, 0.08, 0.84)
    panel.strokeWidth = 1.5
    panel:setStrokeColor(1.0, 0.34, 0.34, 0.55)

    local ok, icon = pcall(display.newImageRect, hudGroup,
        "assets/sprites/weapons/unarmed.png", 24, 24)
    if ok and icon then
        icon.x = panelX - 52
        icon.y = panelY
        enemyWeaponHUD.currentIcon = icon
    end

    local nameLabel = display.newText({
        parent = hudGroup,
        text = "Unarmed",
        x = panelX + 8,
        y = panelY,
        width = 92,
        font = ui.FONT_BOLD,
        fontSize = 10,
        align = "center",
    })
    nameLabel:setFillColor(1.0, 0.86, 0.86)
    enemyWeaponHUD.nameLabel = nameLabel

    local def = weapons.getCurrentWeapon(enemy)
    if enemyWeaponHUD.currentIcon then
        enemyWeaponHUD.currentIcon.fill = {
            type = "image",
            filename = (def and def.icon) or "assets/sprites/weapons/unarmed.png"
        }
    end
    if enemyWeaponHUD.nameLabel then
        enemyWeaponHUD.nameLabel.text = (def and def.name) or "Unarmed"
    end
end

local function flash(target)
    if not target or not target.removeSelf then return end
    target.alpha = 0.4
    trackDelay(60, function()
        if target and target.removeSelf then target.alpha=1 end
    end)
    transition.to(target, { x=target.x+4, time=scaledTime(40),
        onComplete=function()
            if target and target.removeSelf then
                transition.to(target, { x=target.x-4, time=scaledTime(40) })
            end
        end })
end

local function flashBattleBorder()
    if not battleBorder or not battleBorder.removeSelf then return end
    transition.cancel(battleBorder)
    battleBorder:toFront()
    battleBorder.alpha = 0
    transition.to(battleBorder, {
        alpha = 0.95,
        time = scaledTime(35),
        transition = easing.outQuad,
        onComplete = function()
            if battleBorder and battleBorder.removeSelf then
                transition.to(battleBorder, {
                    alpha = 0,
                    time = scaledTime(200),
                    transition = easing.outQuad,
                })
            end
        end
    })
end

local function dodgeMove(sprite)
    if not sprite or not sprite.removeSelf then return end

    -- Enemy-side units occupy the top half and retreat upward.
    -- Player-side units occupy the bottom half and retreat downward.
    local dodgeDistance = sprite.team == "enemy" and -28 or 28

    local function animatePart(part)
        if not part or not part.removeSelf then return end
        local startY = part.y
        transition.to(part, {
            y = startY + dodgeDistance,
            time = scaledTime(100),
            transition = easing.outQuad,
            onComplete = function()
                if part and part.removeSelf then
                    transition.to(part, {
                        y = startY,
                        time = scaledTime(150),
                        transition = easing.inOutQuad,
                    })
                end
            end,
        })
    end

    animatePart(sprite)
    animatePart(sprite._weaponIdleVisual)
    animatePart(sprite._weaponIdleIcon)
end

local function spawnDamageText(targetSprite, text, color)
    if not targetSprite or not targetSprite.removeSelf then return end
    local d = display.newText({
        parent=battleRoot, text=text,
        x=targetSprite.x, y=targetSprite.y-120,
        font=ui.FONT_BOLD, fontSize=24, align="center"
    })
    d._battleTransient = true
    d:setFillColor(unpack(color))
    transition.to(d, { y=d.y-12, alpha=0, time=scaledTime(950),
        onComplete=function() if d and d.removeSelf then d:removeSelf() end end })
end

-------------------------------------------------
-- ATTACK ANIMATION
-- Street Brawler uses run, anticipation, impact, and recovery frames.
-- Other characters and pets retain the safe static-sprite fallback.
-------------------------------------------------
performAttack = function(attackerSprite, targetSprite, weaponDef, onImpact, returnDelay)
    if not attackerSprite or not targetSprite then return end

    local centerX   = display.contentCenterX
    local centerY   = display.contentCenterY
    local approachY = attackerSprite.team=="player" and (centerY-60) or (centerY+60)
    local attackerPetId = attackerSprite.petId
    local runVisual = makeStreetBrawlerRunVisual(attackerSprite)
    if attackerPetId then
        setPetPoseOrIdle(
            attackerSprite, attackerPetId, attackerSprite.team, "attack")
    end

    moveAttackSprite(attackerSprite, runVisual, centerX, approachY,
        attackPacedTime(220), function()
        local attackX = attackerSprite.team=="enemy"
            and (targetSprite.x + math.random(-12,12))
            or targetSprite.x
        local stopGap = math.max(
            22,
            ((attackerSprite.height or 64) + (targetSprite.height or 64)) * 0.22)
        local attackY = targetSprite.y
            + (attackerSprite.team == "player" and stopGap or -stopGap)

        moveAttackSprite(attackerSprite, runVisual, attackX, attackY,
            attackPacedTime(170), function()
            removeAttackVisual(runVisual)
            runVisual = nil

            -- The first attack frame is the raised-hand anticipation pose.
            local meleeAttack = isMeleeWeapon(weaponDef)
            local attackStyle = meleeAttack and "melee"
                or ((not weaponDef or not weaponDef.icon) and "unarmed" or "ranged")
            local attackVisual = makeStreetBrawlerAttackVisual(
                attackerSprite, attackX, attackY, attackStyle)
            if not attackVisual then attackerSprite.alpha = 1 end
            local floatIcon = attachWeaponToSprite(attackerSprite, weaponDef)
            if not positionMeleeWeapon(
                floatIcon, attackVisual, attackerSprite.team, 1)
                and floatIcon and floatIcon.removeSelf
            then
                floatIcon.x = attackX + ((attackerSprite.team=="player") and 24 or -24)
                floatIcon.y = attackY - 10
                floatIcon:toFront()
            end

            trackDelay(attackPacedTime(180), function()
                if attackVisual and attackVisual.removeSelf then
                    attackVisual:setFrame(2)
                end
                positionMeleeWeapon(
                    floatIcon, attackVisual, attackerSprite.team, 2)
                if onImpact then onImpact() end

                trackDelay(attackPacedTime(110), function()
                    if attackVisual and attackVisual.removeSelf then
                        attackVisual:setFrame(3)
                    end
                    positionMeleeWeapon(
                        floatIcon, attackVisual, attackerSprite.team, 3)

                    trackDelay(attackPacedTime(90), function()
                        local function returnHome()
                        removeAttackVisual(attackVisual)
                        -- Release the composited weapon with the follow-through
                        -- instead of leaving it behind while the unit runs home.
                        detachWeaponFromSprite()
                        local returnVisual = makeStreetBrawlerRunVisual(
                            attackerSprite, true)
                        moveAttackSprite(
                            attackerSprite,
                            returnVisual,
                            centerX,
                            approachY,
                            attackPacedTime(210),
                            function()
                                moveAttackSprite(
                                    attackerSprite,
                                    returnVisual,
                                    attackerSprite.homeX,
                                    attackerSprite.homeY,
                                    attackPacedTime(230),
                                    function()
                                        removeAttackVisual(returnVisual)
                                        setStreetBrawlerIdleVisible(
                                            attackerSprite, true)
                                        if attackerPetId then
                                            setPetPoseOrIdle(
                                                attackerSprite,
                                                attackerPetId,
                                                attackerSprite.team,
                                                "battle")
                                        end
                                            end)
                                    end)
                        end
                        if returnDelay and returnDelay > 0 then
                            trackDelay(returnDelay, returnHome)
                        else
                            returnHome()
                        end
                    end)
            end)
        end)
    end)
end)
end

-------------------------------------------------
-- SPELL BANNER
-------------------------------------------------
local SPELL_BANNERS = {
    counter             = { name="Counter",          sub="Reflected the attack!" },
    two_piece_combo     = { name="Two Piece Combo",  sub="Double hit!" },
    wrath               = { name="Wrath",            sub="Critical strike primed!" },
    last_stand          = { name="Last Stand",       sub="Survived with 1 HP!" },
    stun_grenade        = { name="Stun Grenade",     sub="All enemies hit!" },
    call_a_friend       = { name="Call a Friend",    sub="An ally joins the fight!" },
    call_a_friend_leave = { name="Friend Left",      sub="Your ally has departed." },
    ultimate_trainer    = { name="Ultimate Trainer", sub="3rd pet slot unlocked!" },
}

local function recoilForCounter(sprite, onComplete)
    if not sprite or not sprite.removeSelf then
        if onComplete then onComplete() end
        return
    end

    local recoilDistance = sprite.team == "enemy" and -30 or 30
    local idleVisual = sprite._weaponIdleVisual
    local heldWeapon = sprite._weaponIdleIcon
    local idleVisualY = idleVisual and idleVisual.y
    local heldWeaponY = heldWeapon and heldWeapon.y

    local function moveVisiblePart(part)
        if part and part.removeSelf then
            transition.to(part, {
                y = part.y + recoilDistance,
                time = scaledTime(140),
                transition = easing.outQuad,
            })
        end
    end

    moveVisiblePart(idleVisual)
    moveVisiblePart(heldWeapon)
    transition.to(sprite, {
        y = sprite.y + recoilDistance,
        time = scaledTime(140),
        transition = easing.outQuad,
        onComplete = function()
            -- The run visual starts from the recoiled base sprite. Reset the
            -- hidden idle composition so it is aligned when the unit gets home.
            if isAnimatedStreetBrawler(sprite) then
                setStreetBrawlerIdleVisible(sprite, false)
            else
                sprite.alpha = 1
            end
            if idleVisual and idleVisual.removeSelf and idleVisualY then
                idleVisual.y = idleVisualY
            end
            if heldWeapon and heldWeapon.removeSelf and heldWeaponY then
                heldWeapon.y = heldWeaponY
            end
            if onComplete then onComplete() end
        end,
    })
end

local function playCounterSequence(entry, incomingAttacker, counterer)
    if not incomingAttacker or not counterer then return end

    local info = SPELL_BANNERS.counter
    spawnSpellBanner(info.name, info.sub)
    recoilForCounter(counterer, function()
        local counterWeapon = getWeaponDefForAttacker({
            attacker = entry.casterUnit,
            weaponId = entry.weaponId,
        })
        performAttack(counterer, incomingAttacker, counterWeapon, function()
            flash(incomingAttacker)
            spawnDamageText(
                incomingAttacker,
                tostring(entry.damage or 0),
                {0.45, 0.9, 1.0})
            if incomingAttacker.team == "player" then
                currentPlayerHp = math.max(
                    entry.targetTeamHp or entry.targetHp or 0, 0)
            else
                currentEnemyHp = math.max(
                    entry.targetTeamHp or entry.targetHp or 0, 0)
            end
            updateHpBars()
        end)
    end)
end

local function spawnCriticalCue(casterSide)
    local key = (casterSide == "enemy") and "enemy" or "player"
    local sprite = actorSprites[key]
    if not sprite or not sprite.removeSelf then return end

    local ok, fx = pcall(display.newImageRect, battleRoot, "assets/sprites/skills/critical.png", 120, 56)
    if not (ok and fx) then return end
    fx._battleTransient = true
    fx.x = sprite.x
    fx.y = sprite.y + ((key == "player") and 44 or -44)
    fx.alpha = 0
    transition.to(fx, { alpha = 1, time = scaledTime(120) })
    trackDelay(280, function()
        transition.to(fx, {
            alpha = 0,
            time = scaledTime(180),
            onComplete = function()
                if fx and fx.removeSelf then fx:removeSelf() end
            end
        })
    end)
end

local function playLastStandSequence(casterSide)
    local key = (casterSide == "enemy") and "enemy" or "player"
    local sprite = actorSprites[key]
    if not sprite or not sprite.removeSelf then return end

    if key == "player" then
        setCharacterPose("player", "rear_defeated", "defeated")
    else
        setCharacterPose("enemy", "defeated", nil)
    end

    trackDelay(200, function()
        local ok, reviveFx = pcall(display.newImageRect, battleRoot, "assets/sprites/skills/revive.png", 110, 110)
        if ok and reviveFx then
            reviveFx._battleTransient = true
            reviveFx.x = sprite.x
            reviveFx.y = sprite.y
            reviveFx.alpha = 0
            transition.to(reviveFx, { alpha = 1, time = scaledTime(120) })
            transition.to(reviveFx, {
                y = sprite.y + ((key == "player") and -14 or 14),
                alpha = 0,
                time = scaledTime(320),
                transition = easing.outQuad,
                onComplete = function()
                    if reviveFx and reviveFx.removeSelf then reviveFx:removeSelf() end
                end
            })
        end

        if key == "player" then
            setCharacterPose("player", "rear_victory", "victory")
        else
            setCharacterPose("enemy", "victory", nil)
        end

        trackDelay(260, function()
            if key == "player" then
                setCharacterPose("player", "rear", "battle")
            else
                setCharacterPose("enemy", "battle", nil)
            end
        end)
    end)
end

local function spawnSpellBanner(spellName, subtitle)
    local bg = display.newRoundedRect(battleRoot,
        display.contentCenterX, display.contentCenterY-40, 220, 54, 10)
    bg._battleTransient = true
    bg:setFillColor(0.05,0.08,0.22,0.92); bg.strokeWidth=2
    bg:setStrokeColor(0.3,0.7,1.0,0.9); bg.alpha=0

    local nt = display.newText({ parent=battleRoot,
        text=string.upper(spellName),
        x=display.contentCenterX, y=display.contentCenterY-46,
        font=ui.FONT_BOLD, fontSize=18, align="center" })
    nt._battleTransient = true
    nt:setFillColor(0.4,0.9,1.0); nt.alpha=0

    local st = nil
    if subtitle then
        st = display.newText({ parent=battleRoot, text=subtitle,
            x=display.contentCenterX, y=display.contentCenterY-28,
            font=ui.FONT, fontSize=11, align="center" })
        st._battleTransient = true
        st:setFillColor(0.8,0.9,1.0); st.alpha=0
    end

    transition.to(bg, { alpha=1, time=scaledTime(180) })
    transition.to(nt, { alpha=1, time=scaledTime(180) })
    if st then transition.to(st, { alpha=1, time=scaledTime(180) }) end

    trackDelay(900, function()
        transition.to(bg, { alpha=0, time=scaledTime(300),
            onComplete=function() if bg.removeSelf then bg:removeSelf() end end })
        transition.to(nt, { alpha=0, time=scaledTime(300),
            onComplete=function() if nt.removeSelf then nt:removeSelf() end end })
        if st then transition.to(st, { alpha=0, time=scaledTime(300),
            onComplete=function() if st.removeSelf then st:removeSelf() end end }) end
    end)
end

-------------------------------------------------
-- COMBAT LOG HANDLERS
-------------------------------------------------
local function handleSpell(entry)
    local info = SPELL_BANNERS[entry.spell]
    if not info then return end
    local sub = info.sub
    if entry.spell=="call_a_friend" and entry.friend then
        sub = entry.friend.name.." joins for 2 turns!"
    end
    spawnSpellBanner(info.name, sub)

    if entry.spell=="wrath" then
        spawnCriticalCue(entry.caster)
    elseif entry.spell=="last_stand" then
        playLastStandSequence(entry.caster)
    end

        if entry.spell=="stun_grenade" and entry.hits then
        for _, hit in ipairs(entry.hits) do
            local spr = actorSprites[normalizeActorId(hit.target)]
            if spr then flash(spr); spawnDamageText(spr, tostring(hit.damage), {1,0.7,0.2}) end
            if hit.target=="enemy" or hit.target=="enemy:leader" then
                currentEnemyHp = math.max(hit.targetHp, 0)
            end
        end
        updateHpBars()
    end

    if entry.spell=="last_stand" then
        local targetId = normalizeActorId(entry.target or entry.caster)
        local targetSprite = actorSprites[targetId] or actorSprites["player"]
        local spr = targetSprite
        if spr then spawnDamageText(spr, "LAST STAND!", {0.3,1.0,0.5}) end
        if targetSprite and targetSprite.team == "enemy" then
            currentEnemyHp = 1
        else
            currentPlayerHp = 1
        end
        updateHpBars()
    end

    if entry.spell=="call_a_friend" and entry.friend then
        local pSpr = actorSprites["player"]
        if pSpr then
            local friend = display.newImageRect(battleRoot,
                "assets/sprites/characters/street_brawler/rear.png", 72, 120)
            friend.x=pSpr.x+80; friend.y=pSpr.y
            friend.homeX=friend.x; friend.homeY=friend.y; friend.team="player"
            actorSprites["player:friend"] = friend
        end
    end
end

local function handleHit(entry, counterEntry)
    local attackerSprite = actorSprites[normalizeActorId(entry.attacker)]
    local targetSprite   = actorSprites[normalizeActorId(entry.target)]
    local targetId       = normalizeActorId(entry.target)
    if not attackerSprite or not targetSprite then return end

    local dmgText = tostring(entry.damage)
    local color   = {1,0.3,0.3}
    if entry.crit then dmgText="CRIT "..dmgText; color={1,0.6,0.2} end

    local weaponDefForAnim = getWeaponDefForAttacker(entry)

    performAttack(attackerSprite, targetSprite, weaponDefForAnim, function()
        setStreetBrawlerIdleVisible(targetSprite, false)
        if targetSprite.type == "leader" and targetSprite.team == "enemy" then
            setSprite(targetSprite, "assets/sprites/characters/"..(targetSprite.skinId or opponent.visualId or "street_brawler").."/battle_hit.png")
        elseif targetSprite.type == "leader" and targetSprite.team == "player" then
            local skin = targetSprite.skinId
                      or (player.appearance and player.appearance.skinId)
                      or player.skinId
                      or "street_brawler"
            setSprite(targetSprite, "assets/sprites/characters/"..skin.."/rear_hit.png")
        elseif targetId=="player:friend" then
            setSprite(targetSprite, "assets/sprites/characters/street_brawler/rear_hit.png")
        else
            local petId = canonicalPetId(entry.target)
            setPetPoseOrIdle(
                targetSprite, petId, targetSprite.team, "hit")
        end
        targetSprite.alpha = 1

        flash(targetSprite)
        spawnDamageText(targetSprite, dmgText, color)
        if targetSprite.type ~= "leader" then
            -- Main arena bars track leaders only; pet HP never contributes.
        elseif targetSprite.team == "player" then
            if type(entry.targetTeamHp) == "number" then
                currentPlayerHp = math.max(entry.targetTeamHp, 0)
            elseif targetId=="player" and type(entry.targetHp)=="number" then
                currentPlayerHp = math.max(entry.targetHp, 0)
            end
        elseif targetSprite.team == "enemy" then
            if type(entry.targetTeamHp) == "number" then
                currentEnemyHp = math.max(entry.targetTeamHp, 0)
            elseif type(entry.targetHp)=="number" then
                currentEnemyHp = math.max(entry.targetHp, 0)
            end
        end
        updateHpBars()
        if counterEntry then
            playCounterSequence(
                counterEntry,
                attackerSprite,
                targetSprite)
        end

        trackDelay(220, function()
            if targetSprite.type == "leader" and targetSprite.team == "enemy" then
                setSprite(targetSprite, "assets/sprites/characters/"..(targetSprite.skinId or opponent.visualId or "street_brawler").."/battle.png")
            elseif targetSprite.type == "leader" and targetSprite.team == "player" then
                local skin = targetSprite.skinId
                          or (player.appearance and player.appearance.skinId)
                          or player.skinId
                          or "street_brawler"
                setSprite(targetSprite, "assets/sprites/characters/"..skin.."/rear.png")
            elseif targetId=="player:friend" then
                setSprite(targetSprite, "assets/sprites/characters/street_brawler/rear.png")
            else
                local petId = canonicalPetId(entry.target)
                setPetPoseOrIdle(
                    targetSprite, petId, targetSprite.team, "battle")
            end
            if not counterEntry then
                setStreetBrawlerIdleVisible(targetSprite, true)
            end
        end)
    end, counterEntry and attackPacedTime(900) or nil)
end

local function handleDeath(entry)
    local sprite = actorSprites[normalizeActorId(entry.unit)]
    if not sprite then return end
    if entry.teamDefeated then
        local side = entry.side or sprite.team
        if side == "enemy" then
            currentEnemyHp = 0
        elseif side == "player" then
            currentPlayerHp = 0
        end
        updateHpBars()
    end
    local petId = canonicalPetId(entry.unit)
    if petId and petId ~= entry.unit then
        sprite.alpha = 0.3
        setPetPoseOrIdle(sprite, petId, sprite.team, "dead")
        sprite.alpha = 1
        return
    end

    if normalizeActorId(entry.unit) == "player" then
        if not setCharacterPose("player", "rear_defeated", "defeated") then
            sprite.alpha = 0.3
        end
    elseif sprite.type == "leader" and sprite.team == "enemy" then
        if not setCharacterPose(entry.unit, "defeated", nil) then
            sprite.alpha = 0.3
        end
    else
        sprite.alpha = 0.3
    end
end

local function applyEndBattleSprites(result)
    if not result then return end

    if result.winner == "player" then
        setCharacterPose("player", "rear_victory", "victory")
        for key, enemySprite in pairs(actorSprites or {}) do
            if enemySprite and enemySprite.type == "leader" and enemySprite.team == "enemy" then
                if not setCharacterPose(key, "defeated", nil) then
                    enemySprite.alpha = 0.3
                end
            end
        end
    else
        if not setCharacterPose("player", "rear_defeated", "defeated") then
            local playerSprite = actorSprites["player"]
            if playerSprite then playerSprite.alpha = 0.3 end
        end
        for key, enemySprite in pairs(actorSprites or {}) do
            if enemySprite and enemySprite.type == "leader" and enemySprite.team == "enemy" then
                setCharacterPose(key, "victory", nil)
            end
        end
    end
end

getWeaponDefForAttacker = function(entry)
    local normalized = normalizeActorId(entry.attacker)
    local attackerSprite = actorSprites[normalized]
    local attackerIsPlayer = (normalized == "player")
    local attackerIsEnemy = (normalized == "enemy")
        or (attackerSprite and attackerSprite.team == "enemy" and attackerSprite.type == "leader")
    local weaponId = entry.weaponId

    if not weaponId and attackerIsEnemy then
        local raw = opponent
        if entry.attacker and entry.attacker ~= "enemy" and entry.attacker ~= "enemy:leader" then
            for _, defender in ipairs(opponent.defenders or {}) do
                if defender.id == entry.attacker then
                    raw = defender
                    break
                end
            end
        end
        local _, currentId = weapons.getCurrentWeapon(raw)
        weaponId = currentId
    end

    if (attackerIsPlayer or attackerIsEnemy) and weaponId then
        local items = require("utils.items")
        return items[weaponId]
    end

    return nil
end

local function handleDodge(entry)
    local attackerSprite = actorSprites[normalizeActorId(entry.attacker)]
    local targetSprite = actorSprites[normalizeActorId(entry.target)]
    if not targetSprite then return end
    if not attackerSprite then
        spawnDamageText(targetSprite, "DODGED", {0.6,0.9,1})
        dodgeMove(targetSprite)
        return
    end

    performAttack(attackerSprite, targetSprite, getWeaponDefForAttacker(entry), function()
        spawnDamageText(targetSprite, "DODGED", {0.6,0.9,1})
        dodgeMove(targetSprite)
    end)
end

-- weapon_switch: refresh the weapon held by the idle character.
local function handleWeaponSwitch(entry)
    if not entry.weapon then return end

    if (entry.unit=="player" or entry.unit=="player:leader") and weaponHUD.currentIcon and entry.weapon.icon then
        weaponHUD.currentIcon.fill = { type="image", filename=entry.weapon.icon }
    end
    if (entry.unit=="player" or entry.unit=="player:leader") and weaponHUD.nameLabel and entry.weapon.name then
        weaponHUD.nameLabel.text = entry.weapon.name
    end
    if (entry.unit=="enemy" or entry.unit=="enemy:leader") and enemyWeaponHUD.currentIcon and entry.weapon.icon then
        enemyWeaponHUD.currentIcon.fill = { type="image", filename=entry.weapon.icon }
    end
    if (entry.unit=="enemy" or entry.unit=="enemy:leader") and enemyWeaponHUD.nameLabel and entry.weapon.name then
        enemyWeaponHUD.nameLabel.text = entry.weapon.name
    end

    local sprite = actorSprites[normalizeActorId(entry.unit)]
    if sprite and entry.weapon.id then
        local items = require("utils.items")
        refreshStreetBrawlerWeaponIdle(sprite, items[entry.weapon.id])
    end

end

local function buildPlaybackControls(root)
    local twoX = display.newRoundedRect(root, display.actualContentWidth - 42, display.contentHeight - 38, 58, 30, 7)
    twoX:setFillColor(0.03, 0.07, 0.18, 0.86)
    twoX.strokeWidth = 1.5
    twoX:setStrokeColor(0.25, 0.65, 1.0, 0.72)

    local twoXText = display.newText({
        parent=root, text="2X",
        x=twoX.x, y=twoX.y,
        font=ui.FONT_BOLD, fontSize=12, align="center"
    })
    twoXText:setFillColor(0.82, 0.94, 1.0)
    twoXText.isHitTestable = false

    local function toggleSpeed()
        battleSpeed = (battleSpeed == 1) and 2 or 1
        twoXText.text = (battleSpeed == 2) and "1X" or "2X"
        twoX:setFillColor(battleSpeed == 2 and 0.05 or 0.03, battleSpeed == 2 and 0.22 or 0.07, battleSpeed == 2 and 0.42 or 0.18, 0.90)
        return true
    end
    twoX:addEventListener("tap", toggleSpeed)

    local skip = display.newRoundedRect(root, display.actualContentWidth - 15, display.contentCenterY, 26, 92, 7)
    skip:setFillColor(0.03, 0.07, 0.18, 0.74)
    skip.strokeWidth = 1.5
    skip:setStrokeColor(0.25, 0.65, 1.0, 0.58)

    local skipText = display.newText({
        parent=root, text="S\nK\nI\nP",
        x=skip.x, y=skip.y,
        font=ui.FONT_BOLD, fontSize=10, align="center"
    })
    skipText:setFillColor(0.82, 0.94, 1.0)
    skipText.isHitTestable = false

    skip:addEventListener("tap", function()
        skipRequested = true
        if activeResult then finishBattle(activeResult) end
        return true
    end)
end

finishBattle = function(result)
    if battleFinished then return end
    battleFinished = true
    for _, t in ipairs(activeTimers) do pcall(function() timer.cancel(t) end) end
    activeTimers = {}
    transition.cancel()
    clearBattleTransientVisuals(battleRoot)

    local resetSprites = {}
    for _, sprite in pairs(actorSprites or {}) do
        if sprite and sprite.removeSelf and not resetSprites[sprite] then
            resetSprites[sprite] = true
            sprite.x = sprite.homeX or sprite.x
            sprite.y = sprite.homeY or sprite.y
        end
    end

    applyEndBattleSprites(result)
    flashBattleBorder()
    pendingBattleResult = result

    if endTapShield and endTapShield.removeSelf then
        endTapShield:removeSelf()
    end
    endTapShield = display.newGroup()
    battleRoot:insert(endTapShield)

    local dim = display.newRect(endTapShield, display.contentCenterX, display.contentCenterY,
        display.actualContentWidth, display.actualContentHeight)
    dim:setFillColor(0, 0, 0, 0.15)
    dim.isHitTestable = true

    local hint = display.newText({
        parent = endTapShield,
        text = "TAP TO CONTINUE",
        x = display.contentCenterX,
        y = display.contentCenterY + 120,
        font = ui.FONT_BOLD,
        fontSize = 14,
        align = "center",
    })
    hint:setFillColor(1, 1, 1)
    hint.isHitTestable = true

    local function advance()
        if not pendingBattleResult then return true end
        local resultToShow = pendingBattleResult
        pendingBattleResult = nil
        if endTapShield and endTapShield.removeSelf then
            endTapShield:removeSelf()
            endTapShield = nil
        end
        applyRewards(resultToShow)
        return true
    end

    dim:addEventListener("tap", advance)
    hint:addEventListener("tap", advance)
end

-------------------------------------------------
-- HP BARS
-- Enemy:  TOP anchor fixed. Full HP = fill reaches VS center.
--         Takes damage = bottom edge rises toward top.
-- Player: BOTTOM anchor fixed. Full HP = fill reaches VS center.
--         Takes damage = top edge drops toward bottom.
-------------------------------------------------
updateHpBars = function()
    local enemyRatio = math.max(0, math.min(currentEnemyHp / maxEnemyHp, 1))
    local playerRatio = math.max(0, math.min(currentPlayerHp / maxPlayerHp, 1))

    if hpBars.enemyFill and hpBars.enemyBg then
        local maxWidth = hpBars.enemyBg.maxWidth or hpBars.enemyBg.bg.width
        local width = enemyRatio <= 0 and 0 or math.max(4, math.floor(maxWidth * enemyRatio))
        transition.cancel(hpBars.enemyFill)
        hpBars.enemyFill.width = width
        hpBars.enemyFill.x = hpBars.enemyBg.bg.x - (maxWidth * 0.5) + 3
    end

    if hpBars.playerFill and hpBars.playerBg then
        local maxWidth = hpBars.playerBg.maxWidth or hpBars.playerBg.bg.width
        local width = playerRatio <= 0 and 0 or math.max(4, math.floor(maxWidth * playerRatio))
        transition.cancel(hpBars.playerFill)
        hpBars.playerFill.width = width
        hpBars.playerFill.x = hpBars.playerBg.bg.x + (maxWidth * 0.5) + 3 - width
    end
end

-------------------------------------------------
-- PLAY COMBAT LOG
-------------------------------------------------
playCombatLog = function(result)
    activeResult = result
    local log   = result.log or {}
    local index = 1

    local start = log[1]
    if start and start.type == "start" then
        if type(start.playerTeamHp) == "number" and start.playerTeamHp > 0 then
            maxPlayerHp = start.playerTeamHp
            currentPlayerHp = start.playerTeamHp
        end
        if type(start.enemyTeamHp) == "number" and start.enemyTeamHp > 0 then
            maxEnemyHp = start.enemyTeamHp
            currentEnemyHp = start.enemyTeamHp
        end
        updateHpBars()
    end

    local function step()
        if battleFinished then return end
        if skipRequested then finishBattle(result); return end
        local entry = log[index]
        if not entry then finishBattle(result); return end

        local pairedCounter
        if entry.type == "hit" then
            local nextEntry = log[index + 1]
            if nextEntry
                and nextEntry.type == "spell"
                and nextEntry.spell == "counter"
                and nextEntry.target == entry.attacker
                and nextEntry.casterUnit == entry.target
            then
                pairedCounter = nextEntry
                index = index + 1
            end
            handleHit(entry, pairedCounter)
        elseif entry.type=="death"         then
            handleDeath(entry)
            if entry.teamDefeated then
                -- The lethal attack has already finished returning home.
                -- Declare the result now so winner and loser poses appear
                -- together, with no weapon-rotation or end-log pause.
                finishBattle(result)
                return
            end
        elseif entry.type=="dodge"         then handleDodge(entry)
        elseif entry.type=="spell"         then handleSpell(entry)
        elseif entry.type=="weapon_switch" then handleWeaponSwitch(entry)
        end

        index = index + 1
        local isMovementAction = entry.type == "hit" or entry.type == "dodge"
        local delay = isMovementAction and attackPacedTime(1280) or 700
        if pairedCounter then
            delay = attackPacedTime(2500)
        elseif entry.type=="spell" then
            if entry.spell=="wrath" then
                delay = 260
            elseif entry.spell=="counter" or entry.spell=="last_stand" then
                delay = 520
            else
                delay = 900
            end
        end
        trackDelay(delay, step)
    end

    step()
end

-------------------------------------------------
-- APPLY REWARDS
-------------------------------------------------
applyRewards = function(result)
    local replayFight = (composer.getVariable("battleMode") == "arena_replay") and composer.getVariable("fightAllReplay") or nil
    local isConquest  = opponent and opponent.isConquest
    local isRebel     = opponent and opponent.isRebel
    local guildLootChallenge = isGuildLootBattle() and composer.getVariable("guildLootChallenge") or nil
    local guildWarBattle = activeGuildWarBattle()
    local guildLeagueChallenge = activeGuildLeagueChallenge()
    local gainedGold = 0
    local gainedXp   = 2
    local conquestServerHandled = false

    if guildWarBattle then
        local rg = display.newGroup()
        battleRoot:insert(rg)
        local won = result.winner == "player"
        local dim = display.newRect(rg, display.contentCenterX, display.contentCenterY, display.actualContentWidth, display.actualContentHeight)
        dim:setFillColor(0, 0, 0, 0.58)
        dim.isHitTestable = true
        local panel = display.newRoundedRect(rg, display.contentCenterX, display.contentCenterY, display.actualContentWidth - 42, 188, 10)
        panel:setFillColor(0.02, 0.06, 0.14, 0.98)
        panel.strokeWidth = 2
        panel:setStrokeColor(won and 0.22 or 1.0, won and 0.90 or 0.30, won and 0.42 or 0.28, 0.80)
        display.newText({
            parent=rg,
            text=won and "WAR VICTORY" or "WAR DEFEAT",
            x=display.contentCenterX,
            y=display.contentCenterY - 48,
            font=ui.FONT_BOLD,
            fontSize=20,
            align="center",
        }):setFillColor(won and 0.36 or 1.0, won and 1.0 or 0.38, won and 0.48 or 0.34)
        display.newText({
            parent=rg,
            text=tostring(guildWarBattle.attackerGuildName or "Your Guild") .. " vs " .. tostring(guildWarBattle.defenderGuildName or "Enemy Guild"),
            x=display.contentCenterX,
            y=display.contentCenterY - 16,
            width=display.actualContentWidth - 70,
            font=ui.FONT_BOLD,
            fontSize=11,
            align="center",
        }):setFillColor(0.70, 0.84, 1.0)
        local contBtn = display.newRoundedRect(rg, display.contentCenterX, display.contentCenterY + 48, 150, 38, 8)
        contBtn:setFillColor(0.06, 0.18, 0.45, 0.97)
        contBtn.strokeWidth = 1.5
        contBtn:setStrokeColor(0.3, 0.65, 1.0, 0.8)
        display.newText({ parent=rg, text="CONTINUE", x=contBtn.x, y=contBtn.y, font=ui.FONT_BOLD, fontSize=14 }):setFillColor(1,1,1)
        contBtn:addEventListener("tap", function()
            composer.setVariable("opponent", nil)
            composer.setVariable("guildWarBattle", nil)
            composer.setVariable("battleMode", nil)
            composer.gotoScene("scenes.guild_war", { effect="slideRight", time=260 })
            return true
        end)
        return
    end

    if guildLeagueChallenge then
        local rg = display.newGroup()
        battleRoot:insert(rg)
        local won = result.winner == "player"
        local dim = display.newRect(rg, display.contentCenterX, display.contentCenterY, display.actualContentWidth, display.actualContentHeight)
        dim:setFillColor(0, 0, 0, 0.58)
        dim.isHitTestable = true
        local panel = display.newRoundedRect(rg, display.contentCenterX, display.contentCenterY, display.actualContentWidth - 42, 188, 10)
        panel:setFillColor(0.02, 0.06, 0.14, 0.98)
        panel.strokeWidth = 2
        panel:setStrokeColor(won and 0.22 or 1.0, won and 0.90 or 0.30, won and 0.42 or 0.28, 0.80)
        display.newText({
            parent=rg,
            text=won and "SLOT CLAIMED" or "CHALLENGE LOST",
            x=display.contentCenterX,
            y=display.contentCenterY - 48,
            font=ui.FONT_BOLD,
            fontSize=20,
            align="center",
        }):setFillColor(won and 0.36 or 1.0, won and 1.0 or 0.38, won and 0.48 or 0.34)
        display.newText({
            parent=rg,
            text=won and "You replaced the league slot holder." or "The slot holder keeps their spot.",
            x=display.contentCenterX,
            y=display.contentCenterY - 14,
            width=display.actualContentWidth - 70,
            font=ui.FONT_BOLD,
            fontSize=11,
            align="center",
        }):setFillColor(0.70, 0.84, 1.0)
        local contBtn = display.newRoundedRect(rg, display.contentCenterX, display.contentCenterY + 48, 150, 38, 8)
        contBtn:setFillColor(0.06, 0.18, 0.45, 0.97)
        contBtn.strokeWidth = 1.5
        contBtn:setStrokeColor(0.3, 0.65, 1.0, 0.8)
        display.newText({ parent=rg, text="CONTINUE", x=contBtn.x, y=contBtn.y, font=ui.FONT_BOLD, fontSize=14 }):setFillColor(1,1,1)
        contBtn:addEventListener("tap", function()
            api.guilds.reportLeagueChallenge(guildLeagueChallenge.guildId, guildLeagueChallenge.slot, { won=won }, function(response)
                if response and response.ok and response.data and response.data.player then
                    sync.applyPlayerSnapshot(response.data.player, saveUtil.activeSlot)
                end
                composer.setVariable("opponent", nil)
                composer.setVariable("guildLeagueChallenge", nil)
                composer.setVariable("battleMode", nil)
                composer.gotoScene("scenes.guild_league", {
                    effect="slideRight", time=260,
                    params={ guildId=guildLeagueChallenge.guildId, guildKey=guildLeagueChallenge.guildKey },
                })
            end)
            return true
        end)
        return
    end

    if result.winner=="player" and not replayFight and not guildLootChallenge and not isRebel then
        local reward = xpUtil.getArenaReward(opponent and opponent.difficulty or composer.getVariable("arenaDifficulty") or "casual")
        gainedGold = reward.gold
        gainedXp   = reward.xp
        player.gold = (player.gold or 0) + gainedGold
        player.xp   = (player.xp   or 0) + gainedXp
        composer.setVariable("arenaDefeated", opponent.name)
    end

    if not isConquest and not isRebel and not guildLootChallenge then
        saveUtil.recordArenaFight(player, result.winner == "player")
    end

    tasksUtil.advance(player, "fight_a_battle", 1)
    local levelSummary = levelUpPopup.applyLevelUps(player, xpUtil)
    if levelSummary then
        notifications.addLevelUp(player, levelSummary)
    end
    local unlockedChests = (replayFight or guildLootChallenge or result.winner ~= "player") and {} or chestRewards.rollForFight()
    chestRewards.enqueueDrops(player, unlockedChests)
    saveUtil.save(player)
    local taxReported = false
    local function reportArenaEarnings(callback)
        if taxReported or gainedGold <= 0 then
            if callback then callback() end
            return
        end
        taxReported = true
        api.squad.reportFightReward({ goldGained = gainedGold }, function(response)
            if response and response.ok and response.data and response.data.jailTax then
                local taxAmount = tonumber(response.data.jailTax.amount) or 0
                gainedGold = math.max(0, gainedGold - taxAmount)
            end
            if response and response.ok and response.data and response.data.player then
                player = sync.applyPlayerSnapshot(response.data.player, saveUtil.activeSlot)
            end
            if callback then callback(response) end
        end)
    end
    local earningsReady = false
    local showPanelAfterEarnings
    sync.pushPlayerSnapshot(player, function()
        reportArenaEarnings(function()
            earningsReady = true
            if showPanelAfterEarnings then showPanelAfterEarnings() end
        end)
    end)
    reportRemoteFight(result)

    local guildLootReport = nil
    local guildLootReporting = false
    local specialReporting = false
    local function submitGuildLootResult(callback)
        if not guildLootChallenge or replayFight then
            if callback then callback() end
            return
        end
        if guildLootReport or guildLootReporting then
            if callback then callback() end
            return
        end
        guildLootReporting = true
        api.guilds.reportLoot(guildLootChallenge.guildId, {
            won = (result.winner == "player"),
        }, function(response)
            guildLootReporting = false
            guildLootReport = response
            if response and response.ok and response.data and response.data.player then
                player = sync.applyPlayerSnapshot(response.data.player, saveUtil.activeSlot)
            end
            if callback then callback() end
        end)
    end

    local function submitSpecialResult(callback)
        if replayFight or specialReporting then
            if callback then callback() end
            return
        end
        specialReporting = true

        if isRebel then
            api.squad.rebel({ won = result.winner == "player" }, function(response)
                if response and response.ok and response.data and response.data.player then
                    player = sync.applyPlayerSnapshot(response.data.player, saveUtil.activeSlot)
                    if result.winner == "player" then
                        player.rival = nil
                        saveUtil.save(player, saveUtil.activeSlot)
                    end
                end
                if callback then callback(response) end
            end)
            return
        end

        if isConquest and result.winner == "player" and opponent and opponent.conquestTarget and opponent.conquestTarget.playerId then
            api.squad.recruit({
                target = opponent.conquestTarget,
                targetPlayerId = opponent.conquestTarget.playerId,
                defeatedRivalPlayerId = opponent.conquestRivalPlayerId,
            }, function(response)
                if response and response.ok and response.data and response.data.player then
                    conquestServerHandled = true
                    player = sync.applyPlayerSnapshot(response.data.player, saveUtil.activeSlot)
                end
                if callback then callback(response) end
            end)
            return
        end

        if callback then callback() end
    end

    local function showResultPanel()
        local rg  = display.newGroup()
        battleRoot:insert(rg)

        local won = result.winner=="player"
        local CX  = display.contentCenterX
        local CY  = display.contentCenterY

        local dim = display.newRect(rg, CX, CY, display.actualContentWidth, display.actualContentHeight)
        dim:setFillColor(0,0,0,0.55); dim.isHitTestable=true

        local panel = display.newRoundedRect(rg, CX, CY, 270, 220, 14)
        panel:setFillColor(0.03,0.07,0.18,0.97); panel.strokeWidth=2
        panel:setStrokeColor(won and 0.2 or 0.8, won and 0.85 or 0.2, won and 0.3 or 0.2, 0.9)

        local rt = display.newText({ parent=rg,
            text=isRebel and (won and "FREED" or "STILL CONQUERED") or (won and "VICTORY" or "DEFEAT"),
            x=CX, y=CY-75, font=ui.FONT_BOLD, fontSize=30 })
        rt:setFillColor(won and 0.3 or 1.0, won and 1.0 or 0.3, won and 0.5 or 0.3)

        display.newText({ parent=rg, text=opponent.name or "Enemy",
            x=CX, y=CY-48, font=ui.FONT_BOLD, fontSize=13
        }):setFillColor(0.7,0.8,1.0)

        if won and not isRebel then
            display.newText({ parent=rg,
                text="+"..gainedGold.."g   +"..gainedXp.." XP",
                x=CX, y=CY-22, font=ui.FONT_BOLD, fontSize=16
            }):setFillColor(1,0.85,0.2)
        end

        local xpNeeded = xpUtil.getXpToLevel(player.level)
        local xpRatio  = math.min((player.xp or 0)/xpNeeded, 1)
        local barW     = 210
        local barBg    = display.newRoundedRect(rg, CX, CY+8, barW, 10, 4)
        barBg:setFillColor(0.08,0.08,0.18)
        if xpRatio > 0 then
            local xpFill = display.newRoundedRect(rg,
                CX - barW*0.5 + barW*xpRatio*0.5, CY+8, barW*xpRatio, 10, 4)
            xpFill:setFillColor(0.2,0.75,1.0)
        end
        display.newText({ parent=rg,
            text="Lv."..player.level.."  "..player.xp.." / "..xpNeeded.." XP",
            x=CX, y=CY+22, font=ui.FONT_BOLD, fontSize=9
        }):setFillColor(0.5,0.7,0.9)

        local contY   = CY+68
        local contBtn = display.newRoundedRect(rg, CX, contY, 150, 38, 8)
        contBtn:setFillColor(0.06,0.18,0.45,0.97)
        contBtn.strokeWidth=1.5; contBtn:setStrokeColor(0.3,0.65,1.0,0.8)
        display.newText({ parent=rg, text="CONTINUE",
            x=CX, y=contY, font=ui.FONT_BOLD, fontSize=14
        }):setFillColor(1,1,1)
        contBtn:addEventListener("tap", function()
            local function leaveBattle()
                if isConquest and not replayFight and not conquestServerHandled then
                    composer.setVariable("conquestResult", {
                        won    = (result.winner == "player"),
                        target = opponent and opponent.conquestTarget or nil,
                    })
                end
                if guildLootChallenge and not replayFight then
                    composer.setVariable("guildLootResult", {
                        won = (result.winner == "player"),
                        guild = guildLootChallenge.guild,
                        guildId = guildLootChallenge.guildId,
                        report = guildLootReport and guildLootReport.data or nil,
                    })
                end
                composer.setVariable("opponent", nil)
                composer.setVariable("fightAllReplay", nil)
                composer.setVariable("guildLootChallenge", nil)
                composer.setVariable("battleMode", nil)
                local returnScene = "scenes.arena"
                if guildLootChallenge and not replayFight then
                    returnScene = "scenes.guild_view"
                elseif (isConquest or isRebel) and not replayFight then
                    returnScene = "scenes.squad"
                end
                local params = nil
                if guildLootChallenge and not replayFight then
                    params = {
                        guildId = guildLootChallenge.guildId,
                        returnScene = "scenes.guild_join",
                    }
                end
                composer.gotoScene(returnScene, { effect="slideRight", time=260, params=params })
            end

            local function continueAfterChests()
                submitGuildLootResult(function()
                    submitSpecialResult(function()
                        if levelSummary then
                            levelUpPopup.show(levelSummary, leaveBattle)
                        else
                            leaveBattle()
                        end
                    end)
                end)
            end

            if unlockedChests and #unlockedChests > 0 then
                chestRewards.showSequence(battleRoot, unlockedChests, continueAfterChests)
            else
                continueAfterChests()
            end
            return true
        end)
    end
    showPanelAfterEarnings = showResultPanel
    if earningsReady or gainedGold <= 0 then
        showPanelAfterEarnings()
    end
end

-------------------------------------------------
-- BUILD BATTLE UI
-------------------------------------------------
local function buildBattle(sceneGroup)
    battleRoot = display.newGroup()
    sceneGroup:insert(battleRoot)

    opponent = composer.getVariable("opponent")
    assert(opponent, "arena_battle: no opponent set via composer variable")

    local guildWarBattle = activeGuildWarBattle()
    if guildWarBattle and guildWarBattle.attackers and guildWarBattle.attackers[1] then
        player = guildWarBattle.attackers[1]
        player.defenders = {}
        for i = 2, #guildWarBattle.attackers do
            player.defenders[#player.defenders + 1] = guildWarBattle.attackers[i]
        end
    else
        player = saveUtil.load()
    end

    -- reset weapon rotation at battle start
    weapons.resetRotation(player)

    opponent.hp = opponent.hp or 25
    actorSprites = {}

    maxPlayerHp     = estimatePlayerTeamHp()
    maxEnemyHp      = estimateEnemyTeamHp()
    currentPlayerHp = maxPlayerHp
    currentEnemyHp  = maxEnemyHp

    -- BACKGROUND
    local bgs = {
        "assets/backgrounds/market.png",
        "assets/backgrounds/office.png",
        "assets/backgrounds/rooftop.png",
    }
    local okB, bg = pcall(display.newImageRect, battleRoot,
        bgs[math.random(#bgs)],
        display.actualContentWidth, display.actualContentHeight+200)
    if okB and bg then
        bg.x=display.contentCenterX; bg.y=display.contentCenterY-100; bg:toBack()
    end

    local enemyLeaderY = formationY(FORMATION.enemy.leaderY)
    local playerLeaderY = formationY(FORMATION.player.leaderY)
    local enemyLeaderW = 24 * FORMATION.enemy.rearScale
    local enemyLeaderH = 40 * FORMATION.enemy.rearScale
    local playerLeaderW = 24 * FORMATION.player.rearScale
    local playerLeaderH = 40 * FORMATION.player.rearScale
    local guildLeaderSlots = {
        { x = -160, row = "back" },
        { x = -80,  row = "front" },
        { x = 0,    row = "back" },
        { x = 80,   row = "front" },
        { x = 160,  row = "back" },
    }

    local function teamLeaderSlot(team, index)
        local isPlayerTeam = team == "player"
        local useTeamSlots = isGuildLootBattle() or isGuildWarBattle()
        if not useTeamSlots then
            local y = isPlayerTeam and playerLeaderY or enemyLeaderY
            local scale = isPlayerTeam and FORMATION.player.rearScale or FORMATION.enemy.rearScale
            return display.contentCenterX, y, scale
        end
        local slot = guildLeaderSlots[((index - 1) % #guildLeaderSlots) + 1]
        local row = slot.row == "front" and "front" or "back"
        local formation = FORMATION[team]
        local scale = row == "front" and formation.frontScale or formation.rearScale
        local w = 24 * scale
        local yRef = row == "front" and formation.frontPetsY or formation.leaderY
        return clampFormationX(formationX(slot.x), w), formationY(yRef), scale
    end

    -- PLAYER SPRITE
    local skin = (player.appearance and player.appearance.skinId)
              or player.skinId or "street_brawler"
    local playerX, playerY, playerScale = teamLeaderSlot("player", 1)
    local okP, pSpr = pcall(display.newImageRect, battleRoot,
        "assets/sprites/characters/"..skin.."/rear.png", 24 * playerScale, 40 * playerScale)
    if okP and pSpr then
        placeUnit(pSpr, playerX, playerY, "player")
        pSpr.type = "leader"
        pSpr.skinId = skin
        pSpr.weaponOwner = player
        attachUnitHpBar(pSpr, player.hp or maxPlayerHp, "player")
        actorSprites["player"]        = pSpr
        actorSprites["player:leader"] = pSpr
    end

    for i, defender in ipairs(player.defenders or {}) do
        local x, y, scale = teamLeaderSlot("player", i + 1)
        local skinId = defender.visualId or defender.skinId or "street_brawler"
        local okD, dSpr = pcall(display.newImageRect, battleRoot,
            "assets/sprites/characters/"..skinId.."/rear.png", 24 * scale, 40 * scale)
        if okD and dSpr then
            placeUnit(dSpr, x, y, "player")
            dSpr.type = "leader"
            dSpr.skinId = skinId
            dSpr.weaponOwner = defender
            attachUnitHpBar(dSpr, defender.hp or player.hp, "player")
            actorSprites[defender.id or ("player:leader:" .. tostring(i + 1))] = dSpr
        end
    end

    -- ENEMY SPRITE
    local eSkin = opponent.isBot and "street_brawler"
        or opponent.visualId or "street_brawler"
    local enemyX, enemyY, enemyScale = teamLeaderSlot("enemy", 1)
    local okE, eSpr = pcall(display.newImageRect, battleRoot,
        "assets/sprites/characters/"..eSkin.."/battle.png", 24 * enemyScale, 40 * enemyScale)
    if okE and eSpr then
        placeUnit(eSpr, enemyX, enemyY, "enemy")
        eSpr.type = "leader"
        eSpr.skinId = eSkin
        eSpr.weaponOwner = opponent
        attachUnitHpBar(eSpr, opponent.hp, "enemy")
        actorSprites["enemy"]        = eSpr
        actorSprites["enemy:leader"] = eSpr
    end

    for i, defender in ipairs(opponent.defenders or {}) do
        local x, y, scale = teamLeaderSlot("enemy", i + 1)
        local w = 24 * scale
        local h = 40 * scale
        local skinId = opponent.isBot and "street_brawler"
            or defender.visualId or defender.skinId or "street_brawler"
        local okD, dSpr = pcall(display.newImageRect, battleRoot,
            "assets/sprites/characters/"..skinId.."/battle.png", w, h)
        if okD and dSpr then
            placeUnit(dSpr, x, y, "enemy")
            dSpr.type = "leader"
            dSpr.skinId = skinId
            dSpr.weaponOwner = defender
            attachUnitHpBar(dSpr, defender.hp or opponent.hp, "enemy")
            actorSprites[defender.id or ("enemy:leader:" .. tostring(i + 1))] = dSpr
        end
    end


    -- ── HP BARS ──────────────────────────────────────────────────────────
    -- Enemy bar:  frame top = y:0 (screen top), frame bottom = vsCenterY
    --             fill TOP anchor fixed at y:0, shrinks downward on damage
    -- Player bar: frame top = vsCenterY, frame bottom = screenH
    --             fill BOTTOM anchor fixed at screenH, shrinks upward on damage

    local screenTop    = display.screenOriginY
    local screenBottom = display.contentHeight - display.screenOriginY
    local vsCenterY    = display.contentCenterY
    local frameW       = 22
    local frameX       = frameW * 0.5 + 4
    local fillW        = math.max(6, math.floor(frameW * 0.46))
    local hpSheet      = getHpFrameSheet()

    -- ── ENEMY bar ────────────────────────────────────────────────────────
    local eFrameH = vsCenterY - screenTop
    local eFrameY = screenTop + eFrameH * 0.5

    hpBars.enemyZoneH = eFrameH
    hpBars.enemyTopY  = screenTop

    local eFill = display.newRect(battleRoot,
        frameX, hpBars.enemyTopY + hpBars.enemyZoneH * 0.5,
        fillW, hpBars.enemyZoneH)
    eFill.fill = { type="image", filename="assets/sprites/ui/health.png" }
    hpBars.enemyFill = eFill

    local okEF, eFrame = pcall(display.newImageRect, battleRoot,
        hpSheet, 2, frameW, eFrameH)
    if okEF and eFrame then
        eFrame.x = frameX; eFrame.y = eFrameY
        hpBars.enemyFrame = eFrame
    end

    -- ── PLAYER bar ───────────────────────────────────────────────────────
    local pFrameH = screenBottom - vsCenterY
    local pFrameY = vsCenterY + pFrameH * 0.5

    hpBars.playerZoneH   = pFrameH
    hpBars.playerBottomY = screenBottom

    local pFill = display.newRect(battleRoot,
        frameX, hpBars.playerBottomY - hpBars.playerZoneH * 0.5,
        fillW, hpBars.playerZoneH)
    pFill.fill = { type="image", filename="assets/sprites/ui/health.png" }
    hpBars.playerFill = pFill

    local okPF, pFrame = pcall(display.newImageRect, battleRoot,
        hpSheet, 1, frameW, pFrameH)
    if okPF and pFrame then
        pFrame.x = frameX; pFrame.y = pFrameY
        hpBars.playerFrame = pFrame
    end

    -- VS badge at the seam
    local okVS, vsBadge = pcall(display.newImageRect, battleRoot,
        "assets/sprites/ui/vs.png", 64, 54)
    if okVS and vsBadge then
        vsBadge.x = frameX; vsBadge.y = vsCenterY
        vsBadge.alpha = 0
    end

    if battleBorder and (not battleBorder.removeSelf) then
        battleBorder = nil
    end
    if battleBorder then battleBorder.alpha = 0 end
    if hpBars.enemyFrame then hpBars.enemyFrame.alpha = 0 end
    if hpBars.enemyFill then hpBars.enemyFill.alpha = 0 end
    if hpBars.playerFrame then hpBars.playerFrame.alpha = 0 end
    if hpBars.playerFill then hpBars.playerFill.alpha = 0 end
    if not battleBorder then
        battleBorder = display.newRoundedRect(battleRoot,
            display.contentCenterX, display.contentCenterY,
            display.actualContentWidth - 10, display.actualContentHeight - 10, 16)
        battleBorder:setFillColor(0, 0, 0, 0)
        battleBorder.strokeWidth = 4
        battleBorder:setStrokeColor(1, 1, 1, 0)
        battleBorder.alpha = 0
    end
    -- ─────────────────────────────────────────────────────────────────────

    local barW = display.actualContentWidth - 34
    local barH = 18
    local topY = display.screenOriginY + 18
    local bottomY = display.contentHeight - display.screenOriginY - 18

    local function buildHorizontalBar(y, isEnemy)
        local group = display.newGroup()
        battleRoot:insert(group)

        local bg = display.newRoundedRect(group, display.contentCenterX, y, barW, barH, 7)
        bg:setFillColor(isEnemy and 0.14 or 0.08, isEnemy and 0.04 or 0.10, isEnemy and 0.08 or 0.18, 0.92)
        bg.strokeWidth = 1.5
        bg:setStrokeColor(isEnemy and 1.0 or 0.30, isEnemy and 0.38 or 0.72, isEnemy and 0.38 or 1.0, 0.72)

        local fill = display.newRoundedRect(group, bg.x - (barW * 0.5) + 3, y, barW - 6, barH - 4, 5)
        fill.anchorX = 0
        fill:setFillColor(isEnemy and 1.0 or 0.28, isEnemy and 0.28 or 0.74, isEnemy and 0.30 or 1.0, 0.92)

        local label = display.newText({
            parent = group,
            text = isEnemy and tostring(opponent.name or opponent.displayName or "ENEMY")
                or tostring(player.name or player.displayName or "PLAYER"),
            x = bg.x,
            y = y - 1,
            font = ui.FONT_BOLD,
            fontSize = 9,
            align = "center",
        })
        label:setFillColor(0.88, 0.94, 1.0)

        return { group = group, bg = bg, fill = fill, label = label, maxWidth = barW - 6 }
    end

    hpBars.enemyBg = buildHorizontalBar(topY, true)
    hpBars.playerBg = buildHorizontalBar(bottomY, false)
    hpBars.enemyFill = hpBars.enemyBg.fill
    hpBars.playerFill = hpBars.playerBg.fill
    hpBars.enemyLabel = hpBars.enemyBg.label
    hpBars.playerLabel = hpBars.playerBg.label
    if hpBars.enemyBg.group then hpBars.enemyBg.group:toFront() end
    if hpBars.playerBg.group then hpBars.playerBg.group:toFront() end
    if battleBorder and battleBorder.toFront then battleBorder:toFront() end
    updateHpBars()

    local function petSpreadMultiplier(def)
        local tier = def and def.size or "medium"
        if tier == "small" then return 0.78 end
        if tier == "medium" then return 1.0 end
        if tier == "large" then return 1.22 end
        if tier == "massive" then return 1.38 end
        return 1.0
    end

    local function petSlot(team, index, def)
        local formation = FORMATION[team]
        local slots = formation.petOffsets
        local slot = slots[((index - 1) % #slots) + 1]
        local wave = math.floor((index - 1) / #slots)
        local row = slot.row == "back" and "back" or "front"
        local yRef = row == "back" and formation.backPetsY or formation.frontPetsY
        local scale = row == "back" and formation.rearScale or formation.frontScale
        local petW = select(1, petDisplayDimensions(def, scale))
        local distance = petSpreadMultiplier(def)
        local xRef = slot.x
        if xRef ~= 0 then
            local side = xRef < 0 and -1 or 1
            xRef = side * (math.abs(xRef) * distance + math.max(0, petW - 92) * 0.34)
        end
        local spread = (team == "enemy" and 48 or 72) * distance
        if wave > 0 then
            spread = spread * wave * (index % 2 == 0 and 1 or -1)
        else
            spread = 0
        end
        return {
            x = formationX(xRef + spread),
            y = formationY(yRef),
            scale = scale,
        }
    end

    -- PLAYER PETS
    player.equipped = player.equipped or {}
    player.equipped.pets = player.equipped.pets or {}
    local activePlayerPets = playerPetRefsFor((isGuildWarBattle() or isGuildLeagueChallenge()) and {} or spells.getEquippedPetsForBattle(player))
    for i, petRef in ipairs(activePlayerPets) do
        local petId = canonicalPetId(petRef)
        local def = petsDB[petId]
        if def then
            local slot = petSlot("player", i, def)
            local petW, petH = petDisplayDimensions(def, slot.scale)
            slot.x = clampFormationX(slot.x, petW)
            local path = petAssets.battleWithFallback(petId, "player")
            local okPet, pet = pcall(display.newImageRect, battleRoot,
                path, petW, petH)
            if okPet and pet then
                placeUnit(pet, slot.x, slot.y, "player")
                pet.petId = petId
                actorSprites[petRef.instanceId or ("player:pet:"..petId)] = pet
                if i == 1 then actorSprites["player:pet:"..petId] = pet end
            else
                print("[arena_battle] MISSING player pet sprite: "..path)
                pet = spawnPetFallback(battleRoot, math.max(petW, petH), "player")
                placeUnit(pet, slot.x, slot.y, "player")
                pet.petId = petId
                actorSprites[petRef.instanceId or ("player:pet:"..petId)] = pet
                if i == 1 then actorSprites["player:pet:"..petId] = pet end
            end
        end
    end

    -- ENEMY PETS
    -- opponent.pets is an array of petId strings e.g. {"cheetah","dog"}
    -- Sprites loaded from: assets/sprites/pets/{petId}/battle.png
    local enemyPetRefs = collectEnemyPetRefs()
    for i, petRef in ipairs((isGuildLootBattle() or isGuildWarBattle() or isGuildLeagueChallenge()) and {} or enemyPetRefs) do
        local petId = canonicalPetId(petRef)
        local def = petsDB[petId]
        if def then
            local slot = petSlot("enemy", i, def)
            local petW, petH = petDisplayDimensions(def, slot.scale)
            slot.x = clampFormationX(slot.x, petW)
            local path = petAssets.battleWithFallback(petId, "enemy")
            local okPet, pet = pcall(display.newImageRect, battleRoot, path, petW, petH)
            if okPet and pet then
                placeUnit(pet, slot.x, slot.y, "enemy")
                pet.petId = petId
                actorSprites[petRef.instanceId or ("enemy:pet:"..petId)] = pet
                if i == 1 then actorSprites["enemy:pet:"..petId] = pet end
                print("[arena_battle] loaded enemy pet: "..path.." size="..math.floor(petW).."x"..math.floor(petH))
            else
                print("[arena_battle] MISSING enemy pet sprite: "..path)
                pet = spawnPetFallback(battleRoot, math.max(petW, petH), "enemy")
                placeUnit(pet, slot.x, slot.y, "enemy")
                pet.petId = petId
                actorSprites[petRef.instanceId or ("enemy:pet:"..petId)] = pet
                if i == 1 then actorSprites["enemy:pet:"..petId] = pet end
            end
        else
            print("[arena_battle] enemy petId not in petsDB: "..(petId or "nil"))
        end
    end

    sendLowerUnitsToFront()
    local preparedIdle = {}
    for _, sprite in pairs(actorSprites or {}) do
        if sprite and sprite.type == "leader" and not preparedIdle[sprite] then
            preparedIdle[sprite] = true
            local weaponDef = weapons.getCurrentWeapon(sprite.weaponOwner)
            refreshStreetBrawlerWeaponIdle(sprite, weaponDef)
        end
    end
    if hpBars.enemyBg.group then hpBars.enemyBg.group:toFront() end
    if hpBars.playerBg.group then hpBars.playerBg.group:toFront() end
    if battleBorder and battleBorder.toFront then battleBorder:toFront() end

    -- WEAPON HUD (bottom-center, above action area)
    weaponHUD = {
        floatingIcon = nil,
        pipGroup     = nil,
        pips         = {},
        usesLeft     = weapons.getUsesPerWeapon(),
        totalUses    = weapons.getUsesPerWeapon(),
        nextIcon     = nil,
        nextLabel    = nil,
        currentIcon  = nil,
        nameLabel    = nil,
    }
    buildPlaybackControls(battleRoot)
end

-------------------------------------------------
-- RESOLVE BATTLE
-------------------------------------------------
local function resolveBattle()
    local guildWarBattle = activeGuildWarBattle()
    local guildLeagueChallenge = activeGuildLeagueChallenge()
    local leagueChallenge = guildLeagueChallenge ~= nil
    local finalStats = guildWarBattle and {
        attack = player.attack or 100,
        defense = player.defense or 100,
        speed = player.speed or 100,
        hp = player.hp or 100,
    } or statsUtil.calculate(player)

    local playerPetStats = {}
    local activePlayerPets = playerPetRefsFor((guildWarBattle or leagueChallenge) and {} or spells.getEquippedPetsForBattle(player))
    for _, petRef in ipairs(activePlayerPets) do
        local petId = canonicalPetId(petRef)
        playerPetStats[petId] = petScaler.scalePet(petId, finalStats, petScaler.getAugments(player, petId))
    end

    local combatPlayer = {
        id                 = "player",
        level              = player.level,
        attack             = finalStats.attack,
        defense            = finalStats.defense,
        speed              = finalStats.speed,
        hp                 = finalStats.hp,
        spells             = leagueChallenge and withoutCallFriend(player.spells) or player.spells,
        pets               = activePlayerPets,
        petStats           = playerPetStats,
        equipped           = player.equipped,
        currentWeaponIndex = player.currentWeaponIndex,
        weaponUsesLeft     = player.weaponUsesLeft,    -- pass uses state to combat
    }

    local playerDefenders = {}
    for i, defender in ipairs(player.defenders or {}) do
        playerDefenders[#playerDefenders + 1] = {
            id       = defender.id or ("player:leader:" .. tostring(i + 1)),
            name     = defender.name or defender.displayName or "Guildmate",
            level    = defender.level or player.level,
            attack   = defender.attack,
            defense  = defender.defense,
            speed    = defender.speed,
            hp       = defender.hp,
            spells   = defender.spells or {},
            pets     = guildWarBattle and {} or (defender.pets or {}),
            petStats = {},
            equipped = defender.equipped,
            currentWeaponIndex = defender.currentWeaponIndex,
            weaponUsesLeft     = defender.weaponUsesLeft,
        }
    end
    combatPlayer.defenders = playerDefenders

    local enemyPetStats = {}
    local primaryEnemyPets = enemyPetRefsFor(opponent, 1)
    if isGuildLootBattle() or guildWarBattle or leagueChallenge then primaryEnemyPets = {} end
    for _, petRef in ipairs(primaryEnemyPets) do
        local petId = canonicalPetId(petRef)
        enemyPetStats[petId] = petScaler.scalePet(petId, opponent)
    end

    local defenderEnemies = {}
    for i, defender in ipairs(opponent.defenders or {}) do
        local defenderPets = enemyPetRefsFor(defender, i + 1)
        if isGuildLootBattle() or guildWarBattle or leagueChallenge then defenderPets = {} end
        local defenderPetStats = {}
        for _, petRef in ipairs(defenderPets) do
            local petId = canonicalPetId(petRef)
            defenderPetStats[petId] = petScaler.scalePet(petId, defender)
        end
        defenderEnemies[#defenderEnemies + 1] = {
            id       = defender.id or ("enemy:leader:" .. tostring(i + 1)),
            name     = defender.name or defender.displayName or "Defender",
            level    = defender.level or opponent.level or player.level,
            attack   = defender.attack,
            defense  = defender.defense,
            speed    = defender.speed,
            hp       = defender.hp,
            spells   = defender.spells or {},
            pets     = defenderPets,
            petStats = defenderPetStats,
            equipped = defender.equipped,
            currentWeaponIndex = defender.currentWeaponIndex,
            weaponUsesLeft     = defender.weaponUsesLeft,
        }
    end

    local combatEnemy = {
        id       = "enemy:leader",
        name     = opponent.name or "Enemy",
        level    = opponent.level or player.level,
        attack   = opponent.attack,
        defense  = opponent.defense,
        speed    = opponent.speed,
        hp       = opponent.hp,
        spells   = leagueChallenge and withoutCallFriend(opponent.spells) or (opponent.spells or {}),
        pets     = primaryEnemyPets,
        petStats = enemyPetStats,
        equipped = opponent.equipped,
        currentWeaponIndex = opponent.currentWeaponIndex,
        weaponUsesLeft     = opponent.weaponUsesLeft,
        defenders          = defenderEnemies,
    }

    local replay = (composer.getVariable("battleMode") == "arena_replay") and composer.getVariable("fightAllReplay") or nil
    if replay and replay.log and replay.log.log then
        replay = replay.log
    end
    local result = replay or combat.runBattle(combatPlayer, combatEnemy)
    playCombatLog(result)
end

-------------------------------------------------
-- SCENE CREATE  (intentionally empty for battle)
-------------------------------------------------
function scene:create(event)
end

-------------------------------------------------
-- SCENE SHOW
-------------------------------------------------
function scene:show(event)
    if event.phase ~= "did" then return end

    if battleRoot then battleRoot:removeSelf(); battleRoot=nil end
    battleSpeed = 1
    battleFinished = false
    skipRequested = false
    activeResult = nil
    pendingBattleResult = nil
    if endTapShield and endTapShield.removeSelf then
        endTapShield:removeSelf()
    end
    endTapShield = nil
    activeTimers = {}

    buildBattle(self.view)
    resolveBattle()
end

-------------------------------------------------
-- SCENE HIDE
-------------------------------------------------
function scene:hide(event)
    if event.phase ~= "will" then return end
    for _, t in ipairs(activeTimers) do pcall(function() timer.cancel(t) end) end
    activeTimers = {}
    transition.cancel()
    if battleRoot then battleRoot:removeSelf(); battleRoot=nil end
end

scene:addEventListener("create", scene)
scene:addEventListener("show",   scene)
scene:addEventListener("hide",   scene)

return scene
