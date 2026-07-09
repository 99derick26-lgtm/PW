-- scenes/guild_war.lua
local composer = require("composer")
local scene    = composer.newScene()
local widget   = require("widget")
local api      = require("utils.api")
local combat   = require("utils.combat")
local saveUtil = require("utils.save")
local ui       = require("utils.ui")
local guildNav = require("utils.guild_nav")
local guildContext = require("utils.guild_context")
local battleContext = require("utils.battle_context")
local shell    = require("utils.guild_scene_shell")

local SW = display.contentWidth
local SH = display.contentHeight
local CX = display.contentCenterX
local CY = display.contentCenterY
local HEADER_H = 72
local HEADER_Y = HEADER_H * 0.5
local CONTENT_TOP = HEADER_H + 12
local CONTENT_BOT = guildNav.contentBottom()
local CONTENT_H = CONTENT_BOT - CONTENT_TOP

local TROPHY_ICON = "assets/sprites/ui/icons/win.png"
local WAR_CARD_H = 84
local WAR_CARD_GAP = 10

local contentGroup
local targetField
local activeGuild
local wars = {}
local refreshWars

local function getCurrentGuild()
    local player = saveUtil.load()
    return guildContext.getActiveGuild(player)
end

local function clearContent()
    if targetField and targetField.removeSelf then
        native.setKeyboardFocus(nil)
        targetField:removeSelf()
    end
    targetField = nil
    if contentGroup and contentGroup.removeSelf then
        contentGroup:removeSelf()
    end
    contentGroup = nil
end

local function text(parent, value, x, y, size, color, width, align)
    local obj = display.newText({
        parent=parent,
        text=value or "",
        x=x,
        y=y,
        width=width,
        font=ui.FONT_BOLD,
        fontSize=size,
        align=align or "center",
    })
    obj:setFillColor(unpack(color))
    return obj
end

local function normalizeWarSide(list, side)
    local out = {}
    for i, fighter in ipairs(list or {}) do
        local copy = {}
        for k, v in pairs(fighter) do copy[k] = v end
        copy.id = side .. ":leader:" .. tostring(i)
        if i == 1 then copy.id = side == "player" and "player" or "enemy:leader" end
        copy.pets = {}
        copy.equipped = copy.equipped or {}
        copy.equipped.pets = {}
        out[#out + 1] = copy
    end
    return out
end

local function playWar(war, round)
    round = round or {}
    local attackers = normalizeWarSide(round.attackers or war.attackers or {}, "player")
    local defenders = normalizeWarSide(round.defenders or war.defenders or {}, "enemy")
    if not attackers[1] or not defenders[1] then
        native.showAlert("War", "That war slot is missing fighters.", { "OK" })
        return
    end

    local opponent = defenders[1]
    opponent.name = war.defenderGuildName or opponent.name or "Enemy Guild"
    opponent.guildWar = true
    opponent.defenders = {}
    for i = 2, #defenders do
        opponent.defenders[#opponent.defenders + 1] = defenders[i]
    end

    battleContext.startGuildWar(opponent, {
        warId = war.warId,
        round = round.round,
        attackerGuildId = war.attackerGuildId,
        attackerGuildName = war.attackerGuildName,
        defenderGuildId = war.defenderGuildId,
        defenderGuildName = war.defenderGuildName,
        attackers = attackers,
        defenders = defenders,
    })
    composer.gotoScene("scenes.arena_battle", { effect="slideLeft", time=220 })
end

local function warWinnerGuildId(war, round)
    if war.winnerGuildId then return war.winnerGuildId end

    round = round or {}
    local attackers = normalizeWarSide(round.attackers or war.attackers or {}, "player")
    local defenders = normalizeWarSide(round.defenders or war.defenders or {}, "enemy")
    if not attackers[1] or not defenders[1] then return nil end

    local player = attackers[1]
    player.defenders = {}
    for i = 2, #attackers do
        player.defenders[#player.defenders + 1] = attackers[i]
    end

    local enemy = defenders[1]
    enemy.defenders = {}
    for i = 2, #defenders do
        enemy.defenders[#enemy.defenders + 1] = defenders[i]
    end

    player.pets = {}
    enemy.pets = {}
    local ok, result = pcall(combat.runBattle, player, enemy)
    if not ok or not result then return nil end
    return result.winner == "player" and war.attackerGuildId or war.defenderGuildId
end

local function displayMatchup(war)
    local activeId = activeGuild and activeGuild.guildId
    local firstId = war.attackerGuildId
    local firstName = war.attackerGuildName or "Guild"
    local secondId = war.defenderGuildId
    local secondName = war.defenderGuildName or "Guild"

    if activeId and activeId == war.defenderGuildId then
        firstId = war.defenderGuildId
        firstName = war.defenderGuildName or "Guild"
        secondId = war.attackerGuildId
        secondName = war.attackerGuildName or "Guild"
    end

    return {
        firstId = firstId,
        firstName = tostring(firstName),
        secondId = secondId,
        secondName = tostring(secondName),
    }
end

local function buildWarCard(parent, war, round, index, startY)
    local cardW = SW - 26
    local cardH = WAR_CARD_H
    local x = 0
    local y = startY + (index - 1) * (cardH + WAR_CARD_GAP)
    local bg = display.newRoundedRect(parent, x, y, cardW, cardH, 8)
    bg:setFillColor(0.03, 0.08, 0.18, 0.96)
    bg.strokeWidth = 1.8

    local winnerId = warWinnerGuildId(war, round)
    local matchup = displayMatchup(war)
    local activeId = activeGuild and activeGuild.guildId
    local titleColor = {0.78, 0.92, 1.0}
    if winnerId and activeId == winnerId then
        titleColor = {0.34, 1.0, 0.48}
        bg:setStrokeColor(0.22, 0.90, 0.42, 0.72)
    elseif winnerId and (activeId == war.attackerGuildId or activeId == war.defenderGuildId) then
        titleColor = {1.0, 0.32, 0.28}
        bg:setStrokeColor(1.0, 0.30, 0.28, 0.72)
    else
        bg:setStrokeColor(0.22, 0.66, 1.0, 0.64)
    end

    local titleY = y + 4
    local leftX = x - cardW * 0.19
    local rightX = x + cardW * 0.19
    text(parent, "ROUND " .. tostring((round and round.round) or index), x, y - 24, 8, {0.44, 0.86, 1.0}, cardW - 40)
    text(parent, matchup.firstName, leftX, titleY, 12, titleColor, cardW * 0.36)
    text(parent, "VS", x, titleY, 11, titleColor, 38)
    text(parent, matchup.secondName, rightX, titleY, 12, titleColor, cardW * 0.36)

    local trophyX
    if winnerId == matchup.firstId then
        trophyX = leftX - cardW * 0.18
    elseif winnerId == matchup.secondId then
        trophyX = rightX - cardW * 0.18
    end
    if trophyX then
        local okTrophy, trophy = pcall(display.newImageRect, parent, TROPHY_ICON, 18, 18)
        if okTrophy and trophy then
            trophy.x = trophyX
            trophy.y = titleY
        end
    end

    local function onTap()
        playWar(war, round)
        return true
    end

    bg:addEventListener("tap", onTap)

    local hit = display.newRect(parent, x, y, cardW, cardH)
    hit:setFillColor(1, 1, 1, 0)
    hit.isHitTestable = true
    hit:addEventListener("tap", onTap)
end

local function buildContent()
    clearContent()
    local cardCount = 0
    for _, war in ipairs(wars) do
        cardCount = cardCount + math.max(1, #(war.rounds or {}))
    end
    local scrollH = math.max(CONTENT_H, 104 + math.max(1, cardCount) * (WAR_CARD_H + WAR_CARD_GAP))
    local topY = -scrollH * 0.5
    local titleY = topY + 30
    local firstCardY = topY + 84

    contentGroup = widget.newScrollView({
        x = CX,
        y = CONTENT_TOP + CONTENT_H * 0.5,
        width = SW,
        height = CONTENT_H,
        scrollWidth = SW,
        scrollHeight = scrollH,
        hideBackground = true,
        horizontalScrollDisabled = true,
        hideScrollBar = false,
    })
    scene.view:insert(contentGroup)
    if contentGroup.scrollToPosition then
        contentGroup:scrollToPosition({ y=0, time=0 })
    end

    activeGuild = getCurrentGuild()
    if not activeGuild or not activeGuild.guildId then
        text(contentGroup, "JOIN OR CREATE A GUILD FIRST", 0, topY + CONTENT_H * 0.35, 14, {1.0, 0.42, 0.32}, SW - 40)
        return
    end

    text(contentGroup, "WAR SLOTS", 0, titleY, 12, {0.44, 0.86, 1.0}, SW - 40)

    if #wars == 0 then
        text(contentGroup, "NO ACTIVE WARS", 0, topY + CONTENT_H * 0.35, 18, {1.0, 0.42, 0.28}, SW - 40)
        text(contentGroup, "Declared wars appear here after their timer finishes.", 0, topY + CONTENT_H * 0.35 + 26, 10, {0.40, 0.48, 0.62}, SW - 60)
        return
    end

    local cardIndex = 1
    for i = 1, #wars do
        local rounds = wars[i].rounds or {}
        if #rounds == 0 then
            buildWarCard(contentGroup, wars[i], nil, cardIndex, firstCardY)
            cardIndex = cardIndex + 1
        else
            for _, round in ipairs(rounds) do
                buildWarCard(contentGroup, wars[i], round, cardIndex, firstCardY)
                cardIndex = cardIndex + 1
            end
        end
    end
    local spacer = display.newRect(contentGroup, 0, firstCardY + cardIndex * (WAR_CARD_H + WAR_CARD_GAP), 1, 1)
    spacer:setFillColor(0, 0, 0, 0.01)
end

refreshWars = function()
    activeGuild = getCurrentGuild()
    if not activeGuild or not activeGuild.guildId then
        wars = {}
        buildContent()
        return
    end
    api.guilds.wars(activeGuild.guildId, function(response)
        if response and response.ok then
            wars = response.data and response.data.wars or {}
        else
            wars = {}
        end
        buildContent()
    end)
end

function scene:create(event)
    local sg = self.view
    local bg = display.newRect(sg, CX, CY, SW, SH)
    bg:setFillColor(0.02, 0.03, 0.08)
    for i = 1, 20 do
        local ln = display.newRect(sg, CX, i * (SH / 20), SW, 1)
        ln:setFillColor(0.05, 0.18, 0.42, 0.04)
        ln.isHitTestable = false
    end

    shell.drawTitleBanner(sg, "WAR", { y=36, height=54, color={1.0, 0.35, 0.30} })

    guildNav.build(sg, "WAR")
    shell.drawCloseToHome(sg, activeGuild)
end

function scene:show(event)
    if event.phase ~= "did" then return end
    if event.params and event.params.guildId then
        guildContext.setActiveGuild(event.params.guildId, event.params.guildKey)
    end
    refreshWars()
end

function scene:hide(event)
    if event.phase ~= "will" then return end
    clearContent()
end

scene:addEventListener("create", scene)
scene:addEventListener("show", scene)
scene:addEventListener("hide", scene)
return scene
