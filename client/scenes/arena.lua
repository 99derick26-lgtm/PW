local composer = require("composer")
local scene     = composer.newScene()
local widget    = require("widget")

local petsDB     = require("utils.pets")
local saveUtil   = require("utils.save")
local stats      = require("utils.stats")
local xpUtil     = require("utils.xp")
local enemyGen   = require("utils.enemy_generator")
local combat     = require("utils.combat")
local spells     = require("utils.spells")
local api        = require("utils.api")
local sync       = require("utils.sync")
local ui         = require("utils.ui")
local petAssets  = require("utils.pet_assets")
local petScaler  = require("utils.pet_scaler")
local radialMenu = require("utils.radial_menu")
local levelUpPopup = require("utils.levelup_popup")
local chestRewards = require("utils.chest_rewards")
local notifications = require("utils.notifications")
local items = require("utils.items")
local battleContext = require("utils.battle_context")

-------------------------------------------------
-- CONSTANTS
-------------------------------------------------
local DIFFICULTY_LEVEL_OFFSET = {
    safe   = -2,
    bully  = -2,
    easy   = -1,
    casual =  0,
    normal =  0,
    hard   =  1,
    elite  =  2,
    extreme = 2,
}

local ARENA_DIFFICULTIES = {
    { key="extreme", label="EXTREME", offset= 2 },
    { key="hard",    label="HARD",    offset= 1 },
    { key="casual",  label="CASUAL",  offset= 0 },
    { key="easy",    label="EASY",    offset=-1 },
    { key="bully",   label="BULLY",   offset=-2 },
}

local ARENA_OPPONENT_COUNT = 8

local VISUAL_IDS = {
    "corp_enforcer", "corp_enforcer_f",
    "street_brawler", "street_fighter",
    "street_fighter_f", "street_punk", "street_punk_f"
}

local OPPONENT_POOL = {
    { name="enemy12345678", basePower=340, pets=2 },
    { name="FireMage",      basePower=280, pets=2 },
    { name="ShadowFox",     basePower=250, pets=3 },
    { name="StoneGiant",    basePower=410, pets=3 },
    { name="IceWitch",      basePower=300, pets=3 },
    { name="BladeWolf",     basePower=220, pets=1 },
    { name="NightCrow",     basePower=380, pets=3 },
    { name="IronClad",      basePower=190, pets=2 },
}

local RADIAL_INNER = {
    { icon="fight", label="Fight", scene="scenes.arena" },
    { icon="home",  label="Home",  scene="scenes.home"  },
    { icon="bag",   label="Bag",   scene="scenes.bag"   },
    { icon="shop",  label="Shop",  scene="scenes.shop"  },
}

local RADIAL_OUTER = {
    { icon="squad",      label="Squad",      scene="scenes.squad"      },
    { icon="tournament", label="Tournament", scene="scenes.tournament" },
    { icon="pet",        label="Pets",       scene="scenes.pets"       },
    { icon="skills",     label="Skills",     scene="scenes.skills"     },
}

-------------------------------------------------
-- SCENE STATE
-------------------------------------------------
local selectedOpponent
local previewGroup
local topInfoGroup
local rebuildArenaUI
local arenaDifficulty = composer.getVariable("arenaDifficulty") or "casual"
local difficultyPopup

local function clearGuildBattleModes()
    composer.setVariable("guildWarBattle", nil)
    composer.setVariable("guildLootChallenge", nil)
    composer.setVariable("battleMode", nil)
end

local function clearFightAllState()
    composer.setVariable("fightAllResults", nil)
    composer.setVariable("fightAllTotals", nil)
    composer.setVariable("fightAllChests", nil)
    composer.setVariable("fightAllLevelSummary", nil)
    composer.setVariable("fightAllReturnPending", nil)
end

local function setNavPressed(btn, pressed)
    if btn and btn.fill then
        btn.fill = {
            type = "image",
            filename = pressed and "assets/sprites/ui/btn_nav_pressed.png" or "assets/sprites/ui/btn_nav.png"
        }
    end
end

local function addNavTouch(target, btn, onRelease)
    target:addEventListener("touch", function(event)
        if event.phase == "began" then
            display.getCurrentStage():setFocus(target)
            target._hasFocus = true
            setNavPressed(btn, true)
        elseif target._hasFocus and (event.phase == "ended" or event.phase == "cancelled") then
            display.getCurrentStage():setFocus(nil)
            target._hasFocus = false
            setNavPressed(btn, false)
            if event.phase == "ended" and onRelease then
                onRelease()
            end
        end
        return true
    end)
end

-------------------------------------------------
-- FIGHT ALL OVERLAY
-------------------------------------------------
local function showFightAllOverlay(sg, results, totalXp, totalGold, levelSummary, unlockedChests)
    local SW = display.actualContentWidth
    local SH = display.actualContentHeight
    local CX = display.contentCenterX
    local CY = display.contentCenterY

    local overlay = display.newGroup()
    sg:insert(overlay)

    local dim = display.newRect(overlay, CX, CY, SW, SH)
    dim:setFillColor(0, 0, 0, 0.82)
    dim.isHitTestable = true

    local panelW = SW - 20
    local panelH = SH - 80
    local panelX = CX
    local panelY = CY

    local glow = display.newRoundedRect(overlay, panelX, panelY, panelW + 6, panelH + 6, 16)
    glow:setFillColor(0, 0, 0, 0)
    glow.strokeWidth = 3
    glow:setStrokeColor(0.18, 0.62, 1.0, 0.22)

    local panel = display.newRoundedRect(overlay, panelX, panelY, panelW, panelH, 14)
    panel:setFillColor(0.03, 0.07, 0.18, 0.98)
    panel.strokeWidth = 2
    panel:setStrokeColor(0.25, 0.60, 1.0, 0.70)

    for i = 0, 10 do
        local line = display.newRect(overlay, panelX, panelY - panelH * 0.5 + i * (panelH / 10), panelW - 6, 1)
        line:setFillColor(0.20, 0.80, 1.0, 0.020)
    end

    display.newText({
        parent=overlay, text="FIGHT ALL RESULTS",
        x=CX, y=panelY - panelH*0.5 + 22,
        font=ui.FONT_BOLD, fontSize=15
    }):setFillColor(0.3, 0.85, 1)

    local topDividerY = panelY - panelH * 0.5 + 40
    local topDivider = display.newRect(overlay, panelX, topDividerY, panelW - 8, 1)
    topDivider:setFillColor(0.25, 0.70, 1.0, 0.38)

    local rewardY = topDividerY + 22
    local rewardBg = display.newRoundedRect(overlay, CX, rewardY, panelW - 18, 34, 8)
    rewardBg:setFillColor(0.10, 0.10, 0.18, 0.96)
    rewardBg.strokeWidth = 1.5
    rewardBg:setStrokeColor(1.0, 0.82, 0.22, 0.65)

    display.newText({
        parent=overlay,
        text="+" .. totalXp .. " XP   +" .. totalGold .. "g",
        x=CX, y=rewardY,
        font=ui.FONT_BOLD, fontSize=12
    }):setFillColor(1, 0.85, 0.2)

    local cardH    = 64
    local cardPad  = 8
    local scrollW  = panelW - 24
    local cardW    = scrollW - 8
    local listTop  = rewardY + 28
    local listBottom = panelY + panelH * 0.5 - 58
    local listH    = listBottom - listTop
    local listY    = listTop
    local contentH = math.max(listH, #results * (cardH + cardPad) + cardPad + 4)

    local scrollView = widget.newScrollView({
        x                        = CX,
        y                        = listY + listH * 0.5,
        width                    = scrollW,
        height                   = listH,
        scrollWidth              = scrollW,
        scrollHeight             = contentH,
        hideBackground           = true,
        horizontalScrollDisabled = true,
        verticalScrollDisabled   = false,
    })
    overlay:insert(scrollView)

    local cardX = 0
    local firstCardY = -contentH * 0.5 + cardPad + cardH * 0.5

    for idx, r in ipairs(results) do
        local cardY = firstCardY + (idx - 1) * (cardH + cardPad)

        local cardBg = display.newRoundedRect(scrollView, cardX, cardY, cardW, cardH, 8)
        cardBg:setFillColor(unpack(r.won
            and {0.05, 0.30, 0.10, 0.97}
            or  {0.28, 0.05, 0.05, 0.97}))
        cardBg.strokeWidth = 1.5
        cardBg:setStrokeColor(unpack(r.won
            and {0.15, 0.85, 0.25, 0.9}
            or  {0.85, 0.15, 0.15, 0.9}))

        local badgeX = cardX - cardW * 0.5 + 34
        local badge  = display.newRoundedRect(scrollView, badgeX, cardY, 44, 28, 5)
        badge:setFillColor(unpack(r.won
            and {0.10, 0.60, 0.18, 1.0}
            or  {0.60, 0.10, 0.10, 1.0}))
        display.newText({
            parent   = scrollView,
            text     = r.won and "WIN" or "LOSS",
            x        = badgeX, y = cardY,
            font     = ui.FONT_BOLD, fontSize = 11
        }):setFillColor(1, 1, 1)

        local accent = display.newRect(scrollView, cardX - cardW * 0.5 + 3, cardY, 6, cardH - 6)
        accent:setFillColor(unpack(r.won
            and {0.18, 1.0, 0.28, 0.95}
            or  {1.0, 0.22, 0.22, 0.95}))

        local infoCenterX = cardX + 24
        local nameText = display.newText({
            parent   = scrollView,
            text     = r.oppName,
            x        = infoCenterX, y = cardY - 10,
            font     = ui.FONT_BOLD, fontSize = 13,
            align    = "center"
        })
        nameText:setFillColor(1, 1, 1)

        local subline = "Tap to replay"
        if r.opponent and r.opponent.level then
            subline = "Lv." .. tostring(r.opponent.level) .. "  •  Tap to replay"
        end
        local subText = display.newText({
            parent   = scrollView,
            text     = subline,
            x        = infoCenterX, y = cardY + 11,
            font     = ui.FONT_BOLD, fontSize = 8,
            align    = "center"
        })
        subText:setFillColor(0.62, 0.74, 0.90)

        local capR = r
        cardBg:addEventListener("tap", function()
            overlay:removeSelf()
            composer.setVariable("fightAllResults", results)
            composer.setVariable("fightAllTotals", { xp = totalXp, gold = totalGold })
            composer.setVariable("fightAllChests", unlockedChests or {})
            composer.setVariable("fightAllLevelSummary", levelSummary)
            composer.setVariable("fightAllReturnPending", true)
            battleContext.startArena(capR.opponent, capR.log or {
                winner = capR.won and "player" or "enemy",
                log = {},
            })
            composer.gotoScene("scenes.arena_battle", { effect="slideLeft", time=200 })
            return true
        end)
        badge:addEventListener("tap", function()
            overlay:removeSelf()
            composer.setVariable("fightAllResults", results)
            composer.setVariable("fightAllTotals", { xp = totalXp, gold = totalGold })
            composer.setVariable("fightAllChests", unlockedChests or {})
            composer.setVariable("fightAllLevelSummary", levelSummary)
            composer.setVariable("fightAllReturnPending", true)
            battleContext.startArena(capR.opponent, capR.log or {
                winner = capR.won and "player" or "enemy",
                log = {},
            })
            composer.gotoScene("scenes.arena_battle", { effect="slideLeft", time=200 })
            return true
        end)
    end

    local closeY = panelY + panelH*0.5 - 26
    local closeBtn = display.newRoundedRect(overlay, CX, closeY, 170, 38, 8)
    closeBtn:setFillColor(0.08, 0.18, 0.45)
    closeBtn.strokeWidth = 1.5
    closeBtn:setStrokeColor(0.3, 0.6, 1, 0.8)

    display.newText({
        parent=overlay, text="CLAIM REWARDS",
        x=CX, y=closeY, font=ui.FONT_BOLD, fontSize=13
    }):setFillColor(1, 1, 1)

    overlay.alpha = 0
    panel.y = panel.y + 12
    glow.y = glow.y + 12
    transition.to(overlay, { alpha = 1, time = 160 })
    transition.to(panel, { y = panelY, time = 180, transition = easing.outQuad })
    transition.to(glow, { y = panelY, time = 180, transition = easing.outQuad })

    closeBtn:addEventListener("tap", function()
        overlay:removeSelf()
        local function finishClaim()
            if levelSummary then
                levelUpPopup.show(levelSummary)
            end
        end

        if unlockedChests and #unlockedChests > 0 then
            chestRewards.showSequence(sg, unlockedChests, finishClaim)
        else
            finishClaim()
        end
        return true
    end)
end

-------------------------------------------------
-- HELPERS
-------------------------------------------------
local function opponentKey(opp)
    if not opp then return nil end
    return tostring(opp.id or opp.serverPlayerId or opp.name or "")
end

local function buildArenaSession(player, difficultyKey)
    player = player or saveUtil.load()
    difficultyKey = difficultyKey or arenaDifficulty or "casual"
    local targetLevel = math.max(1, (player.level or 1) + (DIFFICULTY_LEVEL_OFFSET[difficultyKey] or 0))
    local pool = {}
    for _, opp in ipairs(OPPONENT_POOL) do
        table.insert(pool, {
            name      = opp.name,
            basePower = opp.basePower,
            pets      = opp.pets
        })
    end

    local session = {
        opponents = {},
        defeated = {},
        difficulty = difficultyKey,
        targetLevel = targetLevel,
        playerLevel = player.level or 1,
    }

    for i = 1, ARENA_OPPONENT_COUNT do
        local idx = math.random(#pool)
        local opp = table.remove(pool, idx)
        opp.id             = "local:" .. tostring(targetLevel) .. ":" .. tostring(i) .. ":" .. tostring(opp.name)
        opp.visualId       = VISUAL_IDS[math.random(#VISUAL_IDS)]
        opp.generatedPets  = nil
        opp.generatedBuild = nil
        opp.targetLevel     = targetLevel
        table.insert(session.opponents, opp)
    end

    return session
end

local function topUpArenaOpponents(session, player)
    session = session or {}
    session.opponents = session.opponents or {}
    player = player or saveUtil.load()
    local targetLevel = math.max(1, session.targetLevel or ((player.level or 1) + (DIFFICULTY_LEVEL_OFFSET[session.difficulty or arenaDifficulty] or 0)))
    local used = {}
    for _, opp in ipairs(session.opponents) do
        local key = opponentKey(opp)
        if key and key ~= "" then used[key] = true end
    end

    while #session.opponents < ARENA_OPPONENT_COUNT do
        local base = OPPONENT_POOL[((#session.opponents) % #OPPONENT_POOL) + 1]
        local idx = #session.opponents + 1
        local opp = {
            id = "bot:" .. tostring(targetLevel) .. ":" .. tostring(idx) .. ":" .. tostring(base.name),
            name = base.name .. " " .. tostring(targetLevel),
            basePower = base.basePower,
            pets = base.pets,
            visualId = VISUAL_IDS[((idx - 1) % #VISUAL_IDS) + 1],
            generatedPets = nil,
            generatedBuild = nil,
            targetLevel = targetLevel,
            isBot = true,
        }
        while used[opponentKey(opp)] do
            idx = idx + 1
            opp.id = "bot:" .. tostring(targetLevel) .. ":" .. tostring(idx) .. ":" .. tostring(base.name)
        end
        used[opponentKey(opp)] = true
        table.insert(session.opponents, opp)
    end

    while #session.opponents > ARENA_OPPONENT_COUNT do
        table.remove(session.opponents)
    end
    return session
end

local function selectEnemyProfile()
    local diffRoll = math.random()
    local difficulty = "normal"
    if diffRoll < 0.15 then
        difficulty = "easy"
    elseif diffRoll > 0.88 then
        difficulty = "hard"
    end

    local biasPool = { "balanced", "attack", "defense", "speed" }
    return difficulty, biasPool[math.random(#biasPool)]
end

local function ensureGeneratedBuild(player, opp)
    if opp.generatedBuild then
        return opp.generatedBuild
    end

    local diff = opp.difficulty or arenaDifficulty or "casual"
    if diff == "casual" then diff = "normal" end
    local _, bias = selectEnemyProfile()
    local enemyLevel = math.max(1, opp.level or opp.targetLevel or ((player.level or 1) + (DIFFICULTY_LEVEL_OFFSET[arenaDifficulty] or 0)))
    opp.generatedBuild = enemyGen.buildArenaOpponent(player, {
        id = opp.name,
        name = opp.name,
        visualId = opp.visualId,
        level = enemyLevel,
        difficulty = diff,
        bias = bias,
    })
    return opp.generatedBuild
end

local function hasAnyLoadoutData(opp)
    if not opp then return false end
    local weapons = opp.equipped and opp.equipped.weapons or {}
    local pets = opp.pets or {}
    local skills = opp.spells or {}
    return (#weapons > 0) or (#pets > 0) or (#skills > 0)
end

local function buildServerOpponent(serverPlayer, localPlayer)
    local snap = serverPlayer.snapshot or serverPlayer
    local final = stats.calculate(snap)
    local equipped = snap.equipped or serverPlayer.equipped or { weapons = {}, armor = {}, accessories = {}, pets = {} }
    local petList = (type(snap.pets) == "table" and #snap.pets > 0 and snap.pets)
        or (type(serverPlayer.pets) == "table" and #serverPlayer.pets > 0 and serverPlayer.pets)
        or spells.getEquippedPetsForBattle({ equipped = equipped, spells = snap.spells or serverPlayer.spells or {} })
    local opp = {
        id         = serverPlayer.playerId or snap.id or serverPlayer.displayName,
        name       = serverPlayer.displayName or snap.name or "Player",
        serverPlayerId = serverPlayer.playerId,
        visualId   = snap.visualId or serverPlayer.visualId or snap.skinId or serverPlayer.skinId or "street_brawler",
        level      = snap.level or serverPlayer.level or localPlayer.level or 1,
        attack     = final.attack or snap.attack or 100,
        defense    = final.defense or snap.defense or 100,
        speed      = final.speed or snap.speed or 100,
        hp         = final.hp or snap.hp or 100,
        spells     = snap.spells or serverPlayer.spells or {},
        difficulty = "player",
        bias       = "server",
        pets       = petList or {},
        equipped   = equipped,
        currentWeaponIndex = snap.currentWeaponIndex or 1,
        weaponUsesLeft = snap.weaponUsesLeft,
    }
    if serverPlayer.bot and not hasAnyLoadoutData(opp) then
        local generated = enemyGen.buildArenaOpponent(localPlayer, {
            id = opp.id,
            name = opp.name,
            visualId = opp.visualId,
            level = opp.level,
            difficulty = serverPlayer.difficulty or arenaDifficulty or "casual",
            bias = serverPlayer.bias or "balanced",
        })
        opp.attack = generated.attack or opp.attack
        opp.defense = generated.defense or opp.defense
        opp.speed = generated.speed or opp.speed
        opp.hp = generated.hp or opp.hp
        opp.pets = generated.pets or {}
        opp.spells = generated.spells or {}
        opp.equipped = generated.equipped or opp.equipped
        opp.currentWeaponIndex = generated.currentWeaponIndex or opp.currentWeaponIndex
        opp.weaponUsesLeft = generated.weaponUsesLeft
    end
    return opp
end

local function serverPlayerToArenaEntry(serverPlayer, localPlayer)
    local opp = buildServerOpponent(serverPlayer, localPlayer)
    if serverPlayer.bot and not hasAnyLoadoutData(opp) then
        local generated = enemyGen.buildArenaOpponent(localPlayer, {
            id = serverPlayer.playerId or opp.id,
            name = serverPlayer.displayName or opp.name or "Bot",
            visualId = opp.visualId or serverPlayer.skinId or "street_brawler",
            level = opp.level or localPlayer.level or 1,
            difficulty = arenaDifficulty or "casual",
            bias = "balanced",
        })
        opp.attack = generated.attack or opp.attack
        opp.defense = generated.defense or opp.defense
        opp.speed = generated.speed or opp.speed
        opp.hp = generated.hp or opp.hp
        opp.pets = generated.pets or {}
        opp.spells = generated.spells or {}
        opp.equipped = generated.equipped or opp.equipped
        opp.currentWeaponIndex = generated.currentWeaponIndex or opp.currentWeaponIndex
        opp.weaponUsesLeft = generated.weaponUsesLeft
    end
    opp.basePower = (opp.attack or 0) + (opp.defense or 0) + (opp.speed or 0)
    opp.generatedBuild = opp
    opp.generatedPets = opp.pets
    opp.serverPlayerId = serverPlayer.playerId
    opp.isBot = serverPlayer.bot == true
    return opp
end

local function getPetTier(def)
    local size = def.spriteSize or 24
    if size <= 16 then return 1 end
    if size <= 24 then return 2 end
    return 3
end

local function normalizePetId(petRef)
    if type(petRef) == "table" then
        return petRef.id or petRef.petId or petRef.baseId
    end
    return petRef
end

local function fakeBotWinRate(opp)
    local seed = tostring((opp and (opp.id or opp.serverPlayerId or opp.name)) or "bot")
    local hash = 0
    for i = 1, #seed do
        hash = (hash * 31 + seed:byte(i)) % 100000
    end
    return tostring(35 + (hash % 41)) .. "%"
end

local function showDifficultyPopup(sg)
    if difficultyPopup and difficultyPopup.removeSelf then
        difficultyPopup:toFront()
        return
    end

    local overlay = display.newGroup()
    sg:insert(overlay)
    difficultyPopup = overlay

    local dim = display.newRect(overlay, display.contentCenterX, display.contentCenterY, display.actualContentWidth, display.actualContentHeight)
    dim:setFillColor(0, 0, 0, 0.78)
    dim.isHitTestable = true

    local panelW, panelH = display.actualContentWidth - 34, 270
    local panel = display.newRoundedRect(overlay, display.contentCenterX, display.contentCenterY, panelW, panelH, 12)
    panel:setFillColor(0.03, 0.07, 0.18, 0.98)
    panel.strokeWidth = 2
    panel:setStrokeColor(0.25, 0.75, 1.0, 0.70)

    display.newText({
        parent=overlay, text="ARENA SETTINGS",
        x=display.contentCenterX, y=display.contentCenterY - panelH*0.5 + 24,
        font=ui.FONT_BOLD, fontSize=15, align="center"
    }):setFillColor(0.45, 0.90, 1.0)

    local player = saveUtil.load()
    local startY = display.contentCenterY - 76
    for i, def in ipairs(ARENA_DIFFICULTIES) do
        local y = startY + (i - 1) * 42
        local active = def.key == arenaDifficulty
        local row = display.newRoundedRect(overlay, display.contentCenterX, y, panelW - 34, 34, 7)
        row:setFillColor(active and 0.05 or 0.025, active and 0.18 or 0.08, active and 0.28 or 0.18, 0.97)
        row.strokeWidth = 1.5
        row:setStrokeColor(active and 0.35 or 0.16, active and 0.85 or 0.45, active and 1.0 or 0.70, active and 0.85 or 0.45)

        local targetLevel = math.max(1, (player.level or 1) + def.offset)
        display.newText({
            parent=overlay, text=def.label,
            x=display.contentCenterX - 70, y=y,
            font=ui.FONT_BOLD, fontSize=12, align="left"
        }):setFillColor(0.82, 0.94, 1.0)
        display.newText({
            parent=overlay, text=(def.offset >= 0 and "+" or "") .. tostring(def.offset) .. " LV  ->  Lv." .. targetLevel,
            x=display.contentCenterX + 58, y=y,
            font=ui.FONT_BOLD, fontSize=10, align="center"
        }):setFillColor(0.54, 0.72, 0.92)

        local function chooseDifficulty()
            arenaDifficulty = def.key
            composer.setVariable("arenaDifficulty", arenaDifficulty)
            local newSession = buildArenaSession(saveUtil.load(), arenaDifficulty)
            composer.setVariable("arenaSession", newSession)
            selectedOpponent = newSession.opponents[1]
            difficultyPopup = nil
            overlay:removeSelf()
            if rebuildArenaUI then rebuildArenaUI(sg, saveUtil.load(), newSession) end
            return true
        end

        local hit = display.newRect(overlay, display.contentCenterX, y, panelW - 34, 36)
        hit:setFillColor(0, 0, 0, 0.01)
        hit.isHitTestable = true
        hit:addEventListener("tap", chooseDifficulty)
        row:addEventListener("tap", chooseDifficulty)
    end

    dim:addEventListener("tap", function()
        difficultyPopup = nil
        overlay:removeSelf()
        return true
    end)

    overlay:toFront()
end

-------------------------------------------------
-- PREVIEW
-------------------------------------------------
local function updatePreview(sceneGroup, player)
    if previewGroup then previewGroup:removeSelf(); previewGroup = nil end
    if topInfoGroup then topInfoGroup:removeSelf(); topInfoGroup = nil end
    if not selectedOpponent then return end

    previewGroup = display.newGroup()
    sceneGroup:insert(previewGroup)

    local enemyBuild      = ensureGeneratedBuild(player, selectedOpponent)
    local enemyPetIds     = enemyBuild.pets or {}
    local previewEntities = {}

    table.insert(previewEntities, {
        type = "character", tier = 2, slot = 1,
        path = "assets/sprites/characters/" .. selectedOpponent.visualId .. "/battle.png",
        w = 96, h = 160
    })

    for i, petRef in ipairs(enemyPetIds) do
        local petId = normalizePetId(petRef)
        local def = petsDB[petId]
        if def then
            table.insert(previewEntities, {
                type = "pet",
                tier = getPetTier(def),
                slot = i + 1,
                path = petAssets.home(petId),
                w    = def.spriteSize,
                h    = def.spriteSize
            })
        end
    end

    table.sort(previewEntities, function(a, b)
        if a.tier ~= b.tier then return a.tier > b.tier end
        if a.type ~= b.type then return a.type == "pet" end
        return a.slot < b.slot
    end)

    local characterX = display.contentCenterX + 120
    local baseY      = 135
    local spacing    = 40

    for i, e in ipairs(previewEntities) do
        local sprite = display.newImageRect(previewGroup, e.path, e.w, e.h)
        if not sprite then
            sprite = display.newRoundedRect(previewGroup, 0, 0, e.w, e.h, 6)
            sprite:setFillColor(0.06, 0.14, 0.28, 0.94)
            sprite.strokeWidth = 1
            sprite:setStrokeColor(0.20, 0.64, 1.0, 0.8)
        end
        sprite.x = characterX - ((#previewEntities - i) * spacing)
        sprite.y = baseY + (e.tier * 6)
    end

    local function compactList(values, fallback)
        if type(values) ~= "table" or #values == 0 then return fallback end
        local out = {}
        for i = 1, math.min(3, #values) do
            out[#out + 1] = tostring(values[i])
        end
        if #values > 3 then
            out[#out + 1] = "+" .. tostring(#values - 3)
        end
        return table.concat(out, ", ")
    end

    topInfoGroup = display.newGroup()
    sceneGroup:insert(topInfoGroup)

    display.newText({
        parent = topInfoGroup, text = "Lv." .. (enemyBuild.level or 1),
        x = display.contentCenterX - 150, y = -10,
        font = ui.FONT_BOLD, fontSize = 16, align = "left"
    })

    display.newText({
        parent = topInfoGroup, text = selectedOpponent.name,
        x = display.contentCenterX, y = -10,
        font = ui.FONT_BOLD, fontSize = 16, align = "left"
    })

    local statDefs = {
        { key="attack",  icon="atk" },
        { key="defense", icon="def" },
        { key="speed",   icon="spd" },
        { key="hp",      icon="hp"  },
        { key="WIN",     icon="win" },
    }
    local winText = selectedOpponent.isBot
        and fakeBotWinRate(selectedOpponent)
        or saveUtil.getArenaWinRate(selectedOpponent, selectedOpponent.winRate)

    local statStartX = display.contentCenterX - 160
    local statSpacing = 65

    for i, def in ipairs(statDefs) do
        local x = statStartX + (i - 1) * statSpacing

        local icon = display.newImageRect(
            topInfoGroup,
            "assets/sprites/ui/icons/" .. def.icon .. ".png",
            32, 32
        )
        icon.x = x + 6
        icon.y = 20

        display.newText({
            parent   = topInfoGroup,
            text     = def.key == "WIN" and winText or tostring(enemyBuild[def.key] or 0),
            x        = x + 32,
            y        = 20,
            font     = ui.FONT_BOLD,
            fontSize = 8
        })
    end
end

-------------------------------------------------
-- SCENE CREATE
-------------------------------------------------
local function updatePreviewEnhanced(sceneGroup, player)
    updatePreview(sceneGroup, player)
    if not topInfoGroup or not topInfoGroup.removeSelf or not selectedOpponent then return end
    local enemyBuild = ensureGeneratedBuild(player, selectedOpponent)

    local function compactList(values, fallback)
        if type(values) ~= "table" or #values == 0 then return fallback end
        local out = {}
        for i = 1, math.min(3, #values) do
            out[#out + 1] = tostring(values[i])
        end
        if #values > 3 then out[#out + 1] = "+" .. tostring(#values - 3) end
        return table.concat(out, ", ")
    end

    local loadoutStartY = 44
    local loadoutX = display.contentCenterX - 154
    local lines = {
        "PETS: " .. compactList(enemyBuild.pets, "none"),
        "SKILLS: " .. compactList(enemyBuild.spells, "none"),
    }
    for i, textValue in ipairs(lines) do
        local line = display.newText({
            parent = topInfoGroup,
            text = textValue,
            x = loadoutX,
            y = loadoutStartY + (i - 1) * 14,
            width = 200,
            font = ui.FONT_BOLD,
            fontSize = 8,
            align = "left"
        })
        line.anchorX = 0
        line:setFillColor(0.64, 0.84, 1.0)
    end

    local weaponIds = (enemyBuild.equipped and enemyBuild.equipped.weapons) or {}
    local weaponY = loadoutStartY + (#lines * 14) + 6
    local iconX = loadoutX + 8
    local weaponLabel = display.newText({
        parent = topInfoGroup,
        text = "WEAPONS:",
        x = loadoutX,
        y = weaponY,
        font = ui.FONT_BOLD,
        fontSize = 8,
        align = "left"
    })
    weaponLabel.anchorX = 0
    weaponLabel:setFillColor(0.64, 0.84, 1.0)

    if #weaponIds == 0 then
        local none = display.newText({
            parent = topInfoGroup,
            text = "none",
            x = loadoutX + 52,
            y = weaponY,
            font = ui.FONT_BOLD,
            fontSize = 8,
            align = "left"
        })
        none.anchorX = 0
        none:setFillColor(0.64, 0.84, 1.0)
        return
    end

    for i = 1, math.min(4, #weaponIds) do
        local wid = weaponIds[i]
        local def = items[wid]
        if def and def.icon then
            local icon = display.newImageRect(topInfoGroup, def.icon, 16, 16)
            if icon then
                icon.x = iconX + 60 + ((i - 1) * 18)
                icon.y = weaponY
            end
        end
    end
end

function scene:create(event)
    local sceneGroup = self.view
    local player     = saveUtil.load()

    local arenaSession = composer.getVariable("arenaSession")
    if not arenaSession then
        arenaSession = buildArenaSession(player, arenaDifficulty)
        composer.setVariable("arenaSession", arenaSession)
    else
        topUpArenaOpponents(arenaSession, player)
        composer.setVariable("arenaSession", arenaSession)
    end

    selectedOpponent = arenaSession.opponents[1]

    local bg = display.newImage("assets/sprites/ui/bg_home_grid.png")
    local scaleX = display.actualContentWidth  / bg.width
    local scaleY = display.actualContentHeight / bg.height
    bg:scale(math.max(scaleX, scaleY), math.max(scaleX, scaleY))
    bg.x = display.contentCenterX
    bg.y = display.contentCenterY
    sceneGroup:insert(bg)

    local focusPanel = display.newRect(
        sceneGroup,
        display.contentCenterX, 100,
        display.actualContentWidth * 1.9, 260
    )
    focusPanel:setFillColor(0, 0, 0, 0.65)
    focusPanel.isHitTestable = false

    updatePreview(sceneGroup, player)

    rebuildArenaUI = function(sg, pl, session)
        updatePreviewEnhanced(sg, pl)

        if sg._arenaGridGroup then
            sg._arenaGridGroup:removeSelf()
            sg._arenaGridGroup = nil
        end

        local wallGroup = display.newGroup()
        sg:insert(wallGroup)
        sg._arenaGridGroup = wallGroup

        local wallFrame = display.newImageRect(
            wallGroup,
            "assets/sprites/ui/hologram_frame.png",
            display.actualContentWidth + 10, 230
        )
        wallFrame.x = display.contentCenterX
        wallFrame.y = 420

        local wallSurface = display.newRect(
            wallGroup,
            display.contentCenterX, 420,
            display.actualContentWidth - 25, 190
        )
        wallSurface:setFillColor(0, 0, 0, 0.55)
        wallSurface.isHitTestable = false

        local controlY      = 320
        local controlBtnW   = 110
        local controlBtnH   = 34
        local controlSpacing = 20
        local controlButtons = {}

        for i, def in ipairs({ {id="REFRESH",label="REFRESH"}, {id="SETTINGS",label="SETTINGS"} }) do
            local x = display.contentCenterX +
                (i == 1 and -controlBtnW/2 - controlSpacing/2
                         or  controlBtnW/2 + controlSpacing/2)

            local btnGroup = display.newGroup()
            wallGroup:insert(btnGroup)

            local btn = display.newImageRect(
                btnGroup, "assets/sprites/ui/btn_nav.png",
                controlBtnW, controlBtnH
            )
            btn.x = x; btn.y = controlY
            btnGroup._navBtn = btn

            display.newText({
                parent = btnGroup, text = def.label,
                x = x, y = controlY, fontSize = 13
            })

            local hit = display.newRect(btnGroup, x, controlY, controlBtnW, controlBtnH)
            hit:setFillColor(0, 0, 0, 0.01)
            hit.isHitTestable = true
            btnGroup._hit = hit

            controlButtons[def.id] = btnGroup
        end

        local function refreshArena()
            local newSession = buildArenaSession(saveUtil.load(), arenaDifficulty)
            composer.setVariable("arenaSession", newSession)
            selectedOpponent = newSession.opponents[1]
            rebuildArenaUI(sg, saveUtil.load(), newSession)
        end

        local function openSettings()
            timer.performWithDelay(1, function()
                if sg and sg.removeSelf then
                    showDifficultyPopup(sg)
                end
            end)
        end

        addNavTouch(controlButtons["REFRESH"], controlButtons["REFRESH"]._navBtn, refreshArena)
        addNavTouch(controlButtons["SETTINGS"], controlButtons["SETTINGS"]._navBtn, openSettings)
        controlButtons["REFRESH"]._hit:addEventListener("tap", function()
            refreshArena()
            return true
        end)
        controlButtons["SETTINGS"]._hit:addEventListener("tap", function()
            openSettings()
            return true
        end)

        local gridGroup = display.newGroup()
        wallGroup:insert(gridGroup)

        local startY = 380

        if not session.serverRequested then
            session.serverRequested = true
            api.pvp.find({ difficulty=arenaDifficulty, targetLevel=session.targetLevel, count=8 }, function(response)
                if next(session.defeated or {}) ~= nil then return end
                if response and response.ok and response.data and response.data.opponents then
                    local serverOpponents = {}
                    for _, serverPlayer in ipairs(response.data.opponents) do
                        table.insert(serverOpponents, serverPlayerToArenaEntry(serverPlayer, saveUtil.load()))
                    end
                    if #serverOpponents > 0 then
                        session.opponents = serverOpponents
                        session.targetLevel = response.data.targetLevel or session.targetLevel
                        topUpArenaOpponents(session, saveUtil.load())
                        composer.setVariable("arenaSession", session)
                        selectedOpponent = session.opponents[1]
                        rebuildArenaUI(sg, saveUtil.load(), session)
                        if difficultyPopup and difficultyPopup.removeSelf then
                            difficultyPopup:toFront()
                        end
                    end
                end
            end)
        end

        for row = 1, 2 do
            for col = 1, 4 do
                local index = (row - 1) * 4 + col
                local opp   = session.opponents[index]
                if not opp then break end

                local defeated = session.defeated[opponentKey(opp)] or session.defeated[opp.name]

                local cellX = 62 + (col - 1) * 80
                local cellY = startY + (row - 1) * 80

                local portrait = display.newImageRect(
                    gridGroup,
                    "assets/sprites/enemies/" .. opp.visualId .. "/portrait.png",
                    72, 72
                )
                if not portrait then
                    portrait = display.newImageRect(
                        gridGroup,
                        "assets/sprites/characters/" .. (opp.visualId or "street_brawler") .. "/portrait.png",
                        72, 72
                    )
                end
                if not portrait then
                    portrait = display.newRoundedRect(gridGroup, cellX, cellY, 72, 72, 8)
                    portrait:setFillColor(0.04, 0.12, 0.26, 0.97)
                end
                portrait.x = cellX
                portrait.y = cellY

                if defeated then
                    portrait:setFillColor(0.20, 0.20, 0.20)
                    portrait.alpha = 0.55

                    local dimRect = display.newRect(gridGroup, cellX, cellY, 72, 72)
                    dimRect:setFillColor(0, 0, 0, 0.45)

                    local xGroup = display.newGroup()
                    gridGroup:insert(xGroup)
                    xGroup.x = cellX
                    xGroup.y = cellY

                    local xSize = 26
                    local xThick = 5

                    local line1 = display.newRoundedRect(xGroup, 0, 0, xSize * 1.41, xThick, 2)
                    line1:setFillColor(0.95, 0.15, 0.15)
                    line1.rotation = 45

                    local line2 = display.newRoundedRect(xGroup, 0, 0, xSize * 1.41, xThick, 2)
                    line2:setFillColor(0.95, 0.15, 0.15)
                    line2.rotation = -45

                    local dLabel = display.newText({
                        parent   = gridGroup,
                        text     = "DEFEATED",
                        x        = cellX,
                        y        = cellY + 42,
                        font     = ui.FONT_BOLD,
                        fontSize = 7,
                        align    = "center",
                    })
                    dLabel:setFillColor(0.85, 0.2, 0.2)
                end

                portrait:addEventListener("tap", function()
                    if defeated then return true end
                    selectedOpponent = opp
                    updatePreviewEnhanced(sg, saveUtil.load())
                    return true
                end)
            end
        end

        local barY       = display.contentHeight - 80
        local buttonWidth = 105
        local buttonHeight = 45
        local spacing    = 10
        local labels     = { "CONQUER", "FIGHT", "FIGHT ALL" }
        local buttons    = {}

        for i, label in ipairs(labels) do
            local btnGroup = display.newGroup()
            sg:insert(btnGroup)

            local x = display.contentCenterX + (i - 2) * (buttonWidth + spacing)

            local btn = display.newImageRect(
                btnGroup, "assets/sprites/ui/btn_nav.png",
                buttonWidth, buttonHeight
            )
            btn.x = x; btn.y = barY
            btnGroup._navBtn = btn

            display.newText({
                parent = btnGroup, text = label,
                x = x, y = barY,
                font = ui.FONT_BOLD, fontSize = 14
            })

            buttons[label] = btnGroup
        end

        addNavTouch(buttons["FIGHT"], buttons["FIGHT"]._navBtn, function()
            if not selectedOpponent then return end

            local p = saveUtil.load()

            local function goLocalFight()
                local enemyBuild = ensureGeneratedBuild(p, selectedOpponent)

                battleContext.startArena({
                    id         = enemyBuild.id,
                    name       = enemyBuild.name,
                    visualId   = enemyBuild.visualId,
                    level      = enemyBuild.level,
                    attack     = enemyBuild.attack,
                    defense    = enemyBuild.defense,
                    speed      = enemyBuild.speed,
                    hp         = enemyBuild.hp,
                    difficulty = enemyBuild.difficulty,
                    bias       = enemyBuild.bias,
                    pets       = enemyBuild.pets or {},
                    equipped   = enemyBuild.equipped,
                    currentWeaponIndex = enemyBuild.currentWeaponIndex,
                    weaponUsesLeft = enemyBuild.weaponUsesLeft,
                })

                composer.gotoScene("scenes.arena_battle")
            end

            if selectedOpponent.generatedBuild or selectedOpponent.serverPlayerId or selectedOpponent.isBot then
                local enemyBuild = ensureGeneratedBuild(p, selectedOpponent)
                battleContext.startArena(enemyBuild)
                composer.gotoScene("scenes.arena_battle")
                return
            end

            api.pvp.find({ difficulty=arenaDifficulty, targetLevel=(p.level or 1) + (DIFFICULTY_LEVEL_OFFSET[arenaDifficulty] or 0) }, function(response)
                if response and response.ok and response.data and response.data.opponent then
                    battleContext.startArena(buildServerOpponent(response.data.opponent, p))
                    composer.gotoScene("scenes.arena_battle")
                else
                    goLocalFight()
                end
            end)
        end)

        addNavTouch(buttons["CONQUER"], buttons["CONQUER"]._navBtn, function()
            if not selectedOpponent then return end

            local p = saveUtil.load()
            local enemyBuild = ensureGeneratedBuild(p, selectedOpponent)

            battleContext.startArena({
                id         = enemyBuild.id,
                name       = enemyBuild.name,
                visualId   = enemyBuild.visualId,
                level      = enemyBuild.level,
                attack     = enemyBuild.attack,
                defense    = enemyBuild.defense,
                speed      = enemyBuild.speed,
                hp         = enemyBuild.hp,
                difficulty = enemyBuild.difficulty,
                bias       = enemyBuild.bias,
                pets       = enemyBuild.pets or {},
                equipped   = enemyBuild.equipped,
                currentWeaponIndex = enemyBuild.currentWeaponIndex,
                weaponUsesLeft = enemyBuild.weaponUsesLeft,
                isConquest = true,
                conquestTarget = {
                    name      = enemyBuild.name or selectedOpponent.name,
                    level     = enemyBuild.level,
                    power     = selectedOpponent.basePower or (enemyBuild.attack + enemyBuild.defense + enemyBuild.speed),
                    visualId  = selectedOpponent.visualId,
                    playerId   = selectedOpponent.serverPlayerId,
                }
            })

            composer.gotoScene("scenes.arena_battle", { effect="slideLeft", time=220 })
        end)

        addNavTouch(buttons["FIGHT ALL"], buttons["FIGHT ALL"]._navBtn, function()
            local p = saveUtil.load()
            local session = composer.getVariable("arenaSession")
            if not session then return end

            local results = {}
            local totalXp   = 0
            local totalGold = 0
            local playerStats = stats.calculate(p)

            topUpArenaOpponents(session, p)
            for i = 1, ARENA_OPPONENT_COUNT do
                local opp = session.opponents[i]
                if not opp then break end
                local enemyBuild = ensureGeneratedBuild(p, opp)

                local playerEntity = {
                    id      = "player",
                    name    = p.name or "Player",
                    level   = p.level or session.playerLevel or 1,
                    attack  = playerStats.attack,
                    defense = playerStats.defense,
                    speed   = playerStats.speed,
                    hp      = playerStats.hp,
                    spells  = p.spells,
                    pets    = spells.getEquippedPetsForBattle(p),
                    petStats = (function()
                        local out = {}
                        for _, petId in ipairs(spells.getEquippedPetsForBattle(p)) do
                            out[petId] = petScaler.scalePet(petId, playerStats, petScaler.getAugments(p, petId))
                        end
                        return out
                    end)(),
                    equipped = p.equipped,
                    currentWeaponIndex = p.currentWeaponIndex,
                    weaponUsesLeft = p.weaponUsesLeft,
                }
                local enemyEntity = {
                    id      = opp.name,
                    name    = opp.name,
                    attack  = enemyBuild.attack,
                    defense = enemyBuild.defense,
                    speed   = enemyBuild.speed,
                    hp      = enemyBuild.hp,
                    pets    = enemyBuild.pets or {},
                    equipped = enemyBuild.equipped,
                    currentWeaponIndex = enemyBuild.currentWeaponIndex,
                    weaponUsesLeft = enemyBuild.weaponUsesLeft,
                }

                local log    = combat.runBattle(playerEntity, enemyEntity)
                local won    = (log and log.winner == "player")
                local reward = xpUtil.getArenaReward(enemyBuild.difficulty or opp.difficulty or session.difficulty or arenaDifficulty)
                local xpGain = won and reward.xp or 0
                local gGain  = won and reward.gold or 0

                totalXp   = totalXp   + xpGain
                totalGold = totalGold + gGain

                table.insert(results, {
                    index    = i,
                    oppName  = opp.name,
                    won      = won,
                    xp       = xpGain,
                    gold     = gGain,
                    log      = log,
                    opponent = {
                        id         = enemyBuild.id,
                        name       = enemyBuild.name,
                        visualId   = enemyBuild.visualId,
                        level      = enemyBuild.level,
                        attack     = enemyBuild.attack,
                        defense    = enemyBuild.defense,
                        speed      = enemyBuild.speed,
                        hp         = enemyBuild.hp,
                        difficulty = enemyBuild.difficulty,
                        bias       = enemyBuild.bias,
                        pets       = enemyBuild.pets or {},
                        equipped   = enemyBuild.equipped,
                        currentWeaponIndex = enemyBuild.currentWeaponIndex,
                        weaponUsesLeft = enemyBuild.weaponUsesLeft,
                    }
                })
                if won then
                    session.defeated[opponentKey(opp)] = true
                    session.defeated[opp.name] = true
                end
            end

            p.xp   = (p.xp   or 0) + totalXp
            p.gold = (p.gold or 0) + totalGold
            local levelSummary = levelUpPopup.applyLevelUps(p, xpUtil)
            if levelSummary then
                notifications.addLevelUp(p, levelSummary)
            end
            local unlockedChests = chestRewards.rollForFightAll(results)
            chestRewards.enqueueDrops(p, unlockedChests)
            saveUtil.save(p)
            local function reportArenaEarnings(callback)
                if totalGold <= 0 then
                    if callback then callback() end
                    return
                end
                api.squad.reportFightReward({ goldGained = totalGold }, function(response)
                    if response and response.ok and response.data and response.data.jailTax then
                        local taxAmount = tonumber(response.data.jailTax.amount) or 0
                        totalGold = math.max(0, totalGold - taxAmount)
                    end
                    if response and response.ok and response.data and response.data.player then
                        p = sync.applyPlayerSnapshot(response.data.player, saveUtil.activeSlot)
                    end
                    if callback then callback(response) end
                end)
            end
            session.playerLevel = p.level or session.playerLevel
            composer.setVariable("arenaSession", session)
            rebuildArenaUI(sceneGroup, p, session)

            local function showResults()
                showFightAllOverlay(sg, results, totalXp, totalGold, levelSummary, unlockedChests)
            end

            sync.pushPlayerSnapshot(p, function()
                reportArenaEarnings(showResults)
            end)
        end)
    end

    rebuildArenaUI(sceneGroup, player, arenaSession)
end

-------------------------------------------------
-- SCENE SHOW
-------------------------------------------------
function scene:show(event)
    if event.phase ~= "did" then return end

    local sceneGroup   = self.view
    local player       = saveUtil.load()
    local arenaSession = composer.getVariable("arenaSession")

    if not arenaSession then return end

    arenaSession.playerLevel = player.level or arenaSession.playerLevel
    topUpArenaOpponents(arenaSession, player)

    local defeatedId = composer.getVariable("arenaDefeated")
    if defeatedId then
        arenaSession.defeated[defeatedId] = true
        composer.setVariable("arenaDefeated", nil)
    end

    if not selectedOpponent then
        selectedOpponent = arenaSession.opponents[1]
    end

    rebuildArenaUI(sceneGroup, player, arenaSession)

    local fightAllResults = composer.getVariable("fightAllResults")
    local fightAllTotals = composer.getVariable("fightAllTotals")
    local fightAllChests = composer.getVariable("fightAllChests")
    local fightAllLevelSummary = composer.getVariable("fightAllLevelSummary")
    local fightAllReturnPending = composer.getVariable("fightAllReturnPending")
    if fightAllReturnPending and fightAllResults and fightAllTotals then
        clearFightAllState()
        timer.performWithDelay(10, function()
            if sceneGroup and sceneGroup.removeSelf then
                showFightAllOverlay(sceneGroup, fightAllResults, fightAllTotals.xp or 0, fightAllTotals.gold or 0, fightAllLevelSummary, fightAllChests)
            end
        end)
    else
        clearFightAllState()
    end

    radialMenu.show(sceneGroup, {
        activeScene = "arena",
        inner       = RADIAL_INNER,
        outer       = RADIAL_OUTER,
    })
end

-------------------------------------------------
-- SCENE HIDE
-------------------------------------------------
function scene:hide(event)
    if event.phase ~= "will" then return end
    if difficultyPopup and difficultyPopup.removeSelf then
        difficultyPopup:removeSelf()
    end
    difficultyPopup = nil
    radialMenu.destroy()
end

scene:addEventListener("create", scene)
scene:addEventListener("show",   scene)
scene:addEventListener("hide",   scene)

return scene
