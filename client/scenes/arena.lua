local composer = require("composer")
local scene     = composer.newScene()
local widget    = require("widget")

local petsDB     = require("utils.pets")
local saveUtil   = require("utils.save")
local stats      = require("utils.stats")
local xpUtil     = require("utils.xp")
local enemyGen   = require("utils.enemy_generator")
local energyUtil = require("utils.enemies")
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
local BOT_VISUAL_ID = "street_brawler"

-- Anchor the complete arena header to the visible top of letterboxed screens.
-- Search, opponent name, and stats all derive from this one panel position.
local ARENA_TOP_PANEL_TOP = display.screenOriginY + 42
local ARENA_TOP_PANEL_H = 136
local ARENA_SEARCH_LABEL_Y = ARENA_TOP_PANEL_TOP + 14
local ARENA_SEARCH_INPUT_Y = ARENA_TOP_PANEL_TOP + 40
local ARENA_OPPONENT_NAME_Y = ARENA_TOP_PANEL_TOP + 74
local ARENA_STATS_Y = ARENA_TOP_PANEL_TOP + 108

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
local showConqueredTargetPopup
local arenaSearchField
local arenaSearchButtonLabel
local runArenaPlayerSearch

local function formatArenaStat(value)
    local number = math.floor(tonumber(value) or 0)
    local sign = number < 0 and "-" or ""
    local digits = tostring(math.abs(number))
    local formatted = digits:reverse():gsub("(%d%d%d)", "%1,"):reverse()
    formatted = formatted:gsub("^,", "")
    return sign .. formatted
end

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

local function showArenaToast(msg, isError)
    local sg = composer.getScene(composer.getSceneName("current"))
    local parent = sg and sg.view or display.getCurrentStage()
    local bg = display.newRoundedRect(parent, display.contentCenterX, display.actualContentHeight - 106, display.actualContentWidth - 40, 34, 8)
    bg:setFillColor(isError and 0.58 or 0.05, isError and 0.08 or 0.28, isError and 0.08 or 0.12, 0.96)
    bg.strokeWidth = 1.5
    bg:setStrokeColor(isError and 0.95 or 0.20, isError and 0.25 or 0.85, isError and 0.25 or 0.45, 0.85)
    local txt = display.newText({
        parent=parent, text=msg,
        x=display.contentCenterX, y=display.actualContentHeight - 106,
        font=ui.FONT_BOLD, fontSize=12, align="center",
    })
    txt:setFillColor(1, 1, 1)
    transition.to(bg, { delay=1500, time=250, alpha=0, onComplete=function() if bg.removeSelf then bg:removeSelf() end end })
    transition.to(txt, { delay=1500, time=250, alpha=0, onComplete=function() if txt.removeSelf then txt:removeSelf() end end })
end

local function spendArenaEnergy()
    local p = saveUtil.load()
    if not energyUtil.spendEnergy(p) then
        saveUtil.save(p)
        showArenaToast("Not enough energy.", true)
        return nil
    end
    saveUtil.save(p)
    return p
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

local function isBotOpponent(opp)
    if not opp then return false end
    if opp.isBot == true or opp.bot == true then return true end
    local id = tostring(opp.id or opp.serverPlayerId or "")
    return id:match("^local:") ~= nil
        or id:match("^bot:") ~= nil
        or id:match("^bot_") ~= nil
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
        opp.visualId       = BOT_VISUAL_ID
        opp.isBot          = true
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
        if isBotOpponent(opp) then
            opp.isBot = true
            opp.visualId = BOT_VISUAL_ID
            if opp.generatedBuild then
                opp.generatedBuild.visualId = BOT_VISUAL_ID
                opp.generatedBuild.isBot = true
            end
        end
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
            visualId = BOT_VISUAL_ID,
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
        if isBotOpponent(opp) then
            opp.visualId = BOT_VISUAL_ID
            opp.generatedBuild.visualId = BOT_VISUAL_ID
            opp.generatedBuild.isBot = true
        end
        return opp.generatedBuild
    end

    local diff = opp.difficulty or arenaDifficulty or "casual"
    if diff == "casual" then diff = "normal" end
    local _, bias = selectEnemyProfile()
    local enemyLevel = math.max(1, opp.level or opp.targetLevel or ((player.level or 1) + (DIFFICULTY_LEVEL_OFFSET[arenaDifficulty] or 0)))
    opp.generatedBuild = enemyGen.buildArenaOpponent(player, {
        id = opp.name,
        name = opp.name,
        visualId = isBotOpponent(opp) and BOT_VISUAL_ID or opp.visualId,
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
    if serverPlayer.bot == true then
        opp.visualId = BOT_VISUAL_ID
        opp.isBot = true
    end
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

local function makeConquestTarget(targetPlayer, fallback)
    targetPlayer = targetPlayer or {}
    fallback = fallback or targetPlayer
    return {
        playerId = targetPlayer.playerId or targetPlayer.serverPlayerId or fallback.serverPlayerId,
        name     = targetPlayer.displayName or targetPlayer.name or fallback.name,
        level    = targetPlayer.level or fallback.level,
        power    = targetPlayer.basePower or fallback.basePower or ((fallback.attack or 0) + (fallback.defense or 0) + (fallback.speed or 0)),
        visualId = targetPlayer.visualId or targetPlayer.skinId or fallback.visualId,
        equipped = targetPlayer.equipped or fallback.equipped,
        pets     = targetPlayer.pets or fallback.pets,
    }
end

local function startConquestBattle(enemyBuild, targetPlayer, defeatedRivalPlayerId)
    local p = spendArenaEnergy()
    if not p then return end

    battleContext.startArena({
        id         = enemyBuild.id,
        name       = enemyBuild.name,
        serverPlayerId = enemyBuild.serverPlayerId,
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
        conquestTarget = makeConquestTarget(targetPlayer, enemyBuild),
        conquestRivalPlayerId = defeatedRivalPlayerId,
    })

    composer.gotoScene("scenes.arena_battle", { effect="slideLeft", time=220 })
end

showConqueredTargetPopup = function(sg, targetPlayer, rival)
    if not (sg and sg.insert and rival and rival.playerId) then return end
    local overlay = display.newGroup()
    sg:insert(overlay)

    local dim = display.newRect(overlay, display.contentCenterX, display.contentCenterY, display.actualContentWidth, display.actualContentHeight)
    dim:setFillColor(0, 0, 0, 0.78)
    dim.isHitTestable = true

    local panelW, panelH = display.actualContentWidth - 34, 250
    local panel = display.newRoundedRect(overlay, display.contentCenterX, display.contentCenterY, panelW, panelH, 12)
    panel:setFillColor(0.03, 0.07, 0.18, 0.98)
    panel.strokeWidth = 2
    panel:setStrokeColor(0.25, 0.75, 1.0, 0.75)

    local portrait = display.newRoundedRect(overlay, display.contentCenterX, display.contentCenterY - 72, 58, 58, 8)
    portrait:setFillColor(0.07, 0.14, 0.30, 0.95)
    portrait.strokeWidth = 1.5
    portrait:setStrokeColor(0.35, 0.75, 1.0, 0.72)
    local skin = rival.visualId or rival.skinId or "street_brawler"
    local okP, img = pcall(display.newImageRect, overlay, "assets/sprites/characters/"..skin.."/portrait.png", 54, 54)
    if okP and img then
        img.x, img.y = portrait.x, portrait.y
    end

    local rivalName = rival.displayName or rival.name or "Rival"
    display.newText({
        parent=overlay, text=rivalName,
        x=display.contentCenterX, y=display.contentCenterY - 30,
        font=ui.FONT_BOLD, fontSize=16, align="center",
    }):setFillColor(1, 1, 1)
    display.newText({
        parent=overlay, text="LV."..tostring(rival.level or 1),
        x=display.contentCenterX, y=display.contentCenterY - 12,
        font=ui.FONT_BOLD, fontSize=10, align="center",
    }):setFillColor(0.55, 0.80, 1.0)

    display.newText({
        parent=overlay,
        text="This player is in "..rivalName.."'s squad.\nWould you like to fight them?",
        x=display.contentCenterX, y=display.contentCenterY + 26,
        width=panelW - 42,
        font=ui.FONT_BOLD, fontSize=11, align="center",
    }):setFillColor(0.78, 0.88, 1.0)

    local function makeBtn(label, x, onTap)
        local btn
        local ok, imgBtn = pcall(display.newImageRect, overlay, "assets/sprites/ui/btn_nav.png", 126, 33)
        if ok and imgBtn then
            btn = imgBtn
            btn.x, btn.y = x, display.contentCenterY + 88
        else
            btn = display.newRoundedRect(overlay, x, display.contentCenterY + 88, 126, 33, 7)
            btn:setFillColor(0.04, 0.16, 0.40, 0.96)
            btn.strokeWidth = 1.5
            btn:setStrokeColor(0.25, 0.70, 1.0, 0.80)
        end
        display.newText({ parent=overlay, text=label, x=x, y=display.contentCenterY + 88, font=ui.FONT_BOLD, fontSize=13 }):setFillColor(1, 1, 1)
        btn:addEventListener("tap", function()
            if overlay.removeSelf then overlay:removeSelf() end
            onTap()
            return true
        end)
    end

    makeBtn("NO", display.contentCenterX - 70, function() end)
    makeBtn("YES", display.contentCenterX + 70, function()
        api.pvp.prepare(rival.playerId, { mode="fight" }, function(response)
            if response and response.ok and response.data and response.data.opponent then
                local rivalBuild = buildServerOpponent(response.data.opponent, saveUtil.load())
                startConquestBattle(rivalBuild, targetPlayer, rival.playerId)
            else
                showArenaToast("Could not reach rival.", true)
            end
        end)
    end)
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
    if opp.isBot then
        opp.visualId = BOT_VISUAL_ID
    end
    return opp
end

runArenaPlayerSearch = function(sceneGroup)
    local query = arenaSearchField and arenaSearchField.text or ""
    query = query:gsub("^%s+", ""):gsub("%s+$", "")
    if query == "" then
        showArenaToast("Enter a username.", true)
        return
    end

    native.setKeyboardFocus(nil)
    if arenaSearchButtonLabel then
        arenaSearchButtonLabel.text = "..."
    end

    api.player.search(query, function(response)
        if arenaSearchButtonLabel and arenaSearchButtonLabel.removeSelf then
            arenaSearchButtonLabel.text = "SEARCH"
        end

        local results = response and response.ok and response.data
            and (response.data.results or response.data.players) or nil
        if not results or #results == 0 then
            results = saveUtil.searchProfiles(query)
        end
        if not results or #results == 0 then
            showArenaToast("Player not found.", true)
            return
        end

        local normalizedQuery = string.lower(query)
        local selected = results[1]
        for _, result in ipairs(results) do
            local candidateName = result.displayName or result.name
                or result.username or result.accountName or ""
            if string.lower(tostring(candidateName)) == normalizedQuery then
                selected = result
                break
            end
        end

        local player = saveUtil.load()
        if selected.playerId and player.playerId
            and tostring(selected.playerId) == tostring(player.playerId)
        then
            showArenaToast("You cannot fight yourself.", true)
            return
        end

        local opponent = serverPlayerToArenaEntry(selected, player)
        local session = composer.getVariable("arenaSession")
        if not session then
            session = buildArenaSession(player, arenaDifficulty)
        end
        session.opponents = session.opponents or {}
        session.opponents[1] = opponent
        session.defeated = session.defeated or {}
        session.defeated[opponentKey(opponent)] = nil
        composer.setVariable("arenaSession", session)
        selectedOpponent = opponent

        if rebuildArenaUI and sceneGroup and sceneGroup.removeSelf then
            rebuildArenaUI(sceneGroup, player, session)
        end
        showArenaToast("Selected " .. tostring(opponent.name or query) .. ".")
    end)
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
local function previewPetSize(def)
    local base = tonumber(def and def.spriteSize) or 42
    local tier = def and def.size or "medium"
    local boost = 1.22
    if tier == "small" then
        boost = 0.96
    elseif tier == "medium" then
        boost = 1.34
    elseif tier == "large" then
        boost = 1.08
    elseif tier == "massive" then
        boost = 0.92
    end
    return math.max(30, math.floor(base * boost))
end

local function previewPetTierRank(def)
    local tier = def and def.size or "medium"
    if tier == "small" then return 1 end
    if tier == "medium" then return 2 end
    if tier == "large" then return 3 end
    if tier == "massive" then return 4 end
    return 2
end

local function previewPetGap(leftEntry, rightEntry)
    local rank = math.max(previewPetTierRank(leftEntry.def), previewPetTierRank(rightEntry.def))
    local largest = math.max(leftEntry.size, rightEntry.size)
    return math.floor(math.max(8, math.min(34, 6 + rank * 7 + math.max(0, largest - 48) * 0.14)))
end

local function buildPreviewPetLayout(petRefs, baseY, heroX)
    local entries = {}
    for _, petRef in ipairs(petRefs or {}) do
        if #entries >= 3 then break end
        local petId = normalizePetId(petRef)
        local def = petsDB[petId]
        if def then
            entries[#entries + 1] = {
                petId = petId,
                def = def,
                size = previewPetSize(def),
            }
        end
    end

    if #entries == 0 then return entries end

    local gaps = {}
    local totalW = 0
    for i, entry in ipairs(entries) do
        totalW = totalW + entry.size
        if i > 1 then
            gaps[i - 1] = previewPetGap(entries[i - 1], entry)
            totalW = totalW + gaps[i - 1]
        end
    end

    local leftBound = display.screenOriginX + 34
    local rightBound = math.min(heroX - 58, display.contentCenterX + 18)
    local usableW = math.max(90, rightBound - leftBound)
    if totalW > usableW then
        local scale = usableW / totalW
        totalW = 0
        for i, entry in ipairs(entries) do
            entry.size = math.max(28, math.floor(entry.size * scale))
            totalW = totalW + entry.size
            if i > 1 then
                gaps[i - 1] = math.max(7, math.floor((gaps[i - 1] or 10) * scale))
                totalW = totalW + gaps[i - 1]
            end
        end
    end

    local x = leftBound + (usableW - totalW) * 0.5
    local groundY = baseY + 82
    for i, entry in ipairs(entries) do
        x = x + entry.size * 0.5
        entry.x = math.floor(x + 0.5)
        entry.y = math.floor(groundY - entry.size * 0.5 + 0.5)
        entry.groundY = groundY
        x = x + entry.size * 0.5 + (gaps[i] or 0)
    end

    return entries
end

local function updatePreview(sceneGroup, player)
    if previewGroup then previewGroup:removeSelf(); previewGroup = nil end
    if topInfoGroup then topInfoGroup:removeSelf(); topInfoGroup = nil end
    if not selectedOpponent then return end

    previewGroup = display.newGroup()
    sceneGroup:insert(previewGroup)

    local enemyBuild      = ensureGeneratedBuild(player, selectedOpponent)
    local enemyPetIds     = enemyBuild.pets or selectedOpponent.pets or {}

    topInfoGroup = display.newGroup()
    sceneGroup:insert(topInfoGroup)

    local winText = selectedOpponent.isBot
        and fakeBotWinRate(selectedOpponent)
        or saveUtil.getArenaWinRate(selectedOpponent, selectedOpponent.winRate)

    local nameText = display.newText({
        parent = topInfoGroup, text = selectedOpponent.name,
        x = display.contentCenterX - 155, y = ARENA_OPPONENT_NAME_Y,
        width = 230,
        font = ui.FONT_BOLD, fontSize = 18, align = "left"
    })
    nameText.anchorX = 0
    nameText:setFillColor(1, 1, 1)

    local winIcon = display.newImageRect(
        topInfoGroup,
        "assets/sprites/ui/icons/win.png",
        22, 22
    )
    if winIcon then
        winIcon.x = display.contentCenterX + 102
        winIcon.y = ARENA_OPPONENT_NAME_Y
    end
    local winLabel = display.newText({
        parent = topInfoGroup,
        text = tostring(winText),
        x = display.contentCenterX + 120, y = ARENA_OPPONENT_NAME_Y,
        font = ui.FONT_BOLD, fontSize = 11,
        align = "left"
    })
    winLabel.anchorX = 0
    winLabel:setFillColor(0.74, 0.96, 1.0)

    local statDefs = {
        { key="attack",  icon="atk" },
        { key="defense", icon="def" },
        { key="speed",   icon="spd" },
        { key="hp",      icon="hp"  },
    }
    local statStripY = ARENA_STATS_Y
    local statStripW = display.actualContentWidth - 24
    local statDivider = display.newRect(
        topInfoGroup,
        display.contentCenterX,
        statStripY - 18,
        statStripW - 12,
        1)
    statDivider:setFillColor(0.18, 0.52, 1.0, 0.34)

    local statLeft = display.contentCenterX - statStripW * 0.5
    local statCellW = statStripW / #statDefs

    for i, def in ipairs(statDefs) do
        local cellCenterX = statLeft + (i - 0.5) * statCellW
        local iconX = cellCenterX - 22
        local icon = display.newImageRect(
            topInfoGroup,
            "assets/sprites/ui/icons/" .. def.icon .. ".png",
            22, 22
        )
        if icon then
            icon.x = iconX
            icon.y = statStripY
            icon.alpha = 0.88
        end

        local valueText = display.newText({
            parent   = topInfoGroup,
            text     = formatArenaStat(enemyBuild[def.key]),
            x        = cellCenterX - 7,
            y        = statStripY,
            width    = 49,
            font     = ui.FONT_BOLD,
            fontSize = 9,
            align    = "left"
        })
        valueText.anchorX = 0
        valueText:setFillColor(0.92, 0.98, 1.0)

        if i < #statDefs then
            local dividerX = statLeft + i * statCellW
            local divider = display.newRect(
                topInfoGroup, dividerX, statStripY, 1, 20)
            divider:setFillColor(0.18, 0.48, 0.88, 0.30)
        end
    end

    local baseY = 226
    local heroX = display.contentCenterX + 92
    local enemyShadow = display.newRoundedRect(previewGroup, heroX, baseY + 74, 70, 13, 7)
    enemyShadow:setFillColor(0, 0, 0, 0.32)
    enemyShadow.isHitTestable = false

    local sprite = display.newImageRect(
        previewGroup,
        "assets/sprites/characters/" .. (selectedOpponent.visualId or "street_brawler") .. "/battle.png",
        108, 178
    )
    if sprite then
        sprite.x = heroX
        sprite.y = baseY
    end

    for _, slot in ipairs(buildPreviewPetLayout(enemyPetIds, baseY, heroX)) do
        local petSize = slot.size
        local shadow = display.newRoundedRect(previewGroup, slot.x, slot.groundY + 4, petSize * 0.76, 10, 5)
        if shadow then
            shadow:setFillColor(0, 0, 0, 0.28)
            shadow.isHitTestable = false
        end
        local pet = display.newImageRect(previewGroup, petAssets.home(slot.petId), petSize, petSize)
        if pet then
            pet.x = slot.x
            pet.y = slot.y
        end
    end
end

-------------------------------------------------
-- SCENE CREATE
-------------------------------------------------

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

    local searchPanel = display.newRoundedRect(
        sceneGroup,
        display.contentCenterX,
        ARENA_TOP_PANEL_TOP + ARENA_TOP_PANEL_H * 0.5,
        display.actualContentWidth - 16,
        ARENA_TOP_PANEL_H,
        8)
    searchPanel:setFillColor(0.015, 0.05, 0.13, 0.97)
    searchPanel.strokeWidth = 1.5
    searchPanel:setStrokeColor(0.18, 0.50, 1.0, 0.58)

    local searchLabel = display.newText({
        parent = sceneGroup,
        text = "SEARCH PLAYER",
        x = display.screenOriginX + 18,
        y = ARENA_SEARCH_LABEL_Y,
        font = ui.FONT_BOLD,
        fontSize = 9,
        align = "left",
    })
    searchLabel.anchorX = 0
    searchLabel:setFillColor(0.38, 0.86, 1.0)

    local searchInputY = ARENA_SEARCH_INPUT_Y
    local searchBg = display.newRoundedRect(
        sceneGroup,
        display.contentCenterX - 34,
        searchInputY,
        display.actualContentWidth - 138,
        30,
        7)
    searchBg:setFillColor(0.04, 0.10, 0.24, 0.98)
    searchBg.strokeWidth = 1.5
    searchBg:setStrokeColor(0.20, 0.55, 1.00, 0.62)

    arenaSearchField = native.newTextField(
        display.contentCenterX - 30,
        searchInputY,
        display.actualContentWidth - 158,
        22)
    arenaSearchField.placeholder = "Enter player name"
    arenaSearchField.inputType = "default"
    arenaSearchField.returnKey = "search"
    arenaSearchField.hasBackground = false
    arenaSearchField:setTextColor(0.85, 0.95, 1.0)

    local searchBtn = display.newRoundedRect(
        sceneGroup,
        display.screenOriginX + display.actualContentWidth - 55,
        searchInputY,
        66,
        30,
        7)
    searchBtn:setFillColor(0.05, 0.18, 0.42, 0.97)
    searchBtn.strokeWidth = 1.5
    searchBtn:setStrokeColor(0.28, 0.68, 1.0, 0.82)
    arenaSearchButtonLabel = display.newText({
        parent = sceneGroup,
        text = "SEARCH",
        x = searchBtn.x,
        y = searchBtn.y,
        font = ui.FONT_BOLD,
        fontSize = 8,
    })
    arenaSearchButtonLabel:setFillColor(0.78, 0.92, 1.0)
    arenaSearchButtonLabel.isHitTestable = false

    local function submitArenaSearch()
        runArenaPlayerSearch(sceneGroup)
        return true
    end
    searchBtn:addEventListener("tap", submitArenaSearch)
    arenaSearchField:addEventListener("userInput", function(searchEvent)
        if searchEvent.phase == "submitted" then
            submitArenaSearch()
        end
    end)

    updatePreview(sceneGroup, player)

    rebuildArenaUI = function(sg, pl, session)
        updatePreview(sg, pl)

        if sg._arenaGridGroup then
            sg._arenaGridGroup:removeSelf()
            sg._arenaGridGroup = nil
        end

        local wallGroup = display.newGroup()
        sg:insert(wallGroup)
        sg._arenaGridGroup = wallGroup

        local wallSurface = display.newRect(
            wallGroup,
            display.contentCenterX, 440,
            display.actualContentWidth - 25, 205
        )
        wallSurface:setFillColor(0, 0, 0, 0.76)
        wallSurface.isHitTestable = false

        local controlY      = 346
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

        local startY = 406

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
                    updatePreview(sg, saveUtil.load())
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
                if not spendArenaEnergy() then return end
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
                if not spendArenaEnergy() then return end
                local enemyBuild = ensureGeneratedBuild(p, selectedOpponent)
                battleContext.startArena(enemyBuild)
                composer.gotoScene("scenes.arena_battle")
                return
            end

            api.pvp.find({ difficulty=arenaDifficulty, targetLevel=(p.level or 1) + (DIFFICULTY_LEVEL_OFFSET[arenaDifficulty] or 0) }, function(response)
                if response and response.ok and response.data and response.data.opponent then
                    if not spendArenaEnergy() then return end
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

            if selectedOpponent.serverPlayerId and not selectedOpponent.isBot then
                api.pvp.prepare(selectedOpponent.serverPlayerId, { mode="recruit" }, function(response)
                    if response and response.ok and response.data and response.data.opponent then
                        local targetPlayer = response.data.opponent
                        local rival = targetPlayer.rival
                        if rival and rival.playerId and rival.playerId ~= p.playerId then
                            showConqueredTargetPopup(sg, targetPlayer, rival)
                            return
                        end
                        local enemyBuild = buildServerOpponent(targetPlayer, p)
                        startConquestBattle(enemyBuild, targetPlayer, nil)
                    else
                        showArenaToast("Could not prepare conquest.", true)
                    end
                end)
                return
            end

            local enemyBuild = ensureGeneratedBuild(p, selectedOpponent)
            startConquestBattle(enemyBuild, {
                name      = enemyBuild.name or selectedOpponent.name,
                level     = enemyBuild.level,
                power     = selectedOpponent.basePower or (enemyBuild.attack + enemyBuild.defense + enemyBuild.speed),
                visualId  = selectedOpponent.visualId,
                playerId   = selectedOpponent.serverPlayerId,
            }, nil)
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
            local neededEnergy = 0
            for i = 1, ARENA_OPPONENT_COUNT do
                if session.opponents[i] then neededEnergy = neededEnergy + 1 end
            end
            energyUtil.calcEnergy(p)
            if (p.energy or 0) < neededEnergy then
                saveUtil.save(p)
                showArenaToast("Need "..neededEnergy.." energy.", true)
                return
            end
            for _ = 1, neededEnergy do
                energyUtil.spendEnergy(p)
            end
            saveUtil.save(p)
            playerStats = stats.calculate(p)

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

    if arenaSearchField then
        arenaSearchField.isVisible = true
    end

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
    native.setKeyboardFocus(nil)
    if arenaSearchField then
        arenaSearchField.isVisible = false
    end
    if difficultyPopup and difficultyPopup.removeSelf then
        difficultyPopup:removeSelf()
    end
    difficultyPopup = nil
    radialMenu.destroy()
end

function scene:destroy(event)
    if arenaSearchField and arenaSearchField.removeSelf then
        arenaSearchField:removeSelf()
    end
    arenaSearchField = nil
    arenaSearchButtonLabel = nil
end

scene:addEventListener("create", scene)
scene:addEventListener("show",   scene)
scene:addEventListener("hide",   scene)
scene:addEventListener("destroy", scene)

return scene
