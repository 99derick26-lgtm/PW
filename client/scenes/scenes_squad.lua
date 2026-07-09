local composer   = require("composer")
local scene      = composer.newScene()
local saveUtil   = require("utils.save")
local squadUtil  = require("utils.squad")
local ui         = require("utils.ui")
local radialMenu = require("utils.radial_menu")
local api        = require("utils.api")
local sync       = require("utils.sync")
local statsUtil  = require("utils.stats")
local spells     = require("utils.spells")
local energyUtil = require("utils.enemies")
local battleContext = require("utils.battle_context")

local SW = display.actualContentWidth
local SH = display.actualContentHeight
local CX = display.contentCenterX
local CY = display.contentCenterY

local RADIAL_INNER = {
    { icon="fight",      label="Fight",      scene="scenes.arena"      },
    { icon="home",       label="Home",       scene="scenes.home"       },
    { icon="bag",        label="Bag",        scene="scenes.bag"        },
    { icon="shop",       label="Shop",       scene="scenes.shop"       },
}
local RADIAL_OUTER = {
    { icon="squad",      label="Squad",      scene="scenes.squad"      },
    { icon="tournament", label="Tournament", scene="scenes.tournament" },
    { icon="pet",        label="Pets",       scene="scenes.pets"       },
    { icon="skills",     label="Skills",     scene="scenes.skills"     },
}

-------------------------------------------------
-- STATE
-------------------------------------------------
local sceneRoot   = nil
local contentGrp  = nil
local refreshingSquad = false

local HEADER_H = 50
local GOLD_ICON_PATH = "assets/sprites/ui/icons/gold.png"
local SETTINGS_ICON_PATH = "assets/sprites/ui/icons/settings.png"
local BTN_NAV_PATH = "assets/sprites/ui/btn_nav.png"
local TAX_STEPS = { 0, 0.05, 0.10, 0.15, 0.20 }

-------------------------------------------------
-- HELPERS
-------------------------------------------------
local function rebuild() end  -- forward

local function refreshSquadFromServer()
    if refreshingSquad then return end
    refreshingSquad = true
    api.squad.get(function(response)
        refreshingSquad = false
        if response and response.ok and response.data and response.data.player then
            local merged = sync.applyPlayerSnapshot(response.data.player, saveUtil.activeSlot)
            if type(response.data.player.rival) ~= "table" then
                merged.rival = nil
                saveUtil.save(merged, saveUtil.activeSlot)
            end
            rebuild()
        end
    end)
end

local function formatGold(value)
    value = tonumber(value) or 0
    if value >= 1000000 then
        return string.format("%.1fm", value / 1000000)
    elseif value >= 10000 then
        return string.format("%.1fk", value / 1000)
    end
    return tostring(math.floor(value))
end

local function drawGoldAmount(parent, x, y, amount, fontSize, anchorX)
    local iconX = x
    local textX = x + 12
    if anchorX == 1 then
        textX = x
        iconX = x - 48
    end

    local ok, icon = pcall(display.newImageRect, parent, GOLD_ICON_PATH, 16, 16)
    if ok and icon then
        icon.x, icon.y = iconX, y
    end

    local text = display.newText({
        parent=parent, text=formatGold(amount),
        x=textX, y=y, font=ui.FONT_BOLD, fontSize=fontSize or 12, align="left"
    })
    text.anchorX = anchorX or 0
    text:setFillColor(1.0, 0.86, 0.18)
    return text
end

local function drawSkillsHeader(parent, y, title, subtitle)
    local group = display.newGroup()
    parent:insert(group)

    local glow = display.newRoundedRect(group, CX, y, SW - 8, HEADER_H + 6, 12)
    glow:setFillColor(0, 0, 0, 0)
    glow.strokeWidth = 2
    glow:setStrokeColor(0.12, 0.48, 1.0, 0.38)

    local hdr = display.newRoundedRect(group, CX, y, SW - 12, HEADER_H, 10)
    hdr:setFillColor(0.02, 0.06, 0.16, 0.96)
    hdr.strokeWidth = 1.5
    hdr:setStrokeColor(0.18, 0.38, 0.92, 0.48)

    local topLine = display.newRect(group, CX, y - HEADER_H * 0.5 + 6, SW - 24, 2)
    topLine:setFillColor(0.30, 0.66, 1.0, 0.62)

    local titleText = display.newText({
        parent=group, text=title,
        x=18, y=y - 6, font=ui.FONT_BOLD, fontSize=18, align="left"
    })
    titleText.anchorX = 0
    titleText:setFillColor(0.40, 0.84, 1.0)

    local subText = display.newText({
        parent=group, text=subtitle or "",
        x=18, y=y + 10, font=ui.FONT_BOLD, fontSize=8, align="left"
    })
    subText.anchorX = 0
    subText:setFillColor(0.42, 0.70, 1.0, 0.82)

    return group
end

local function getRivalInfo(player)
    local rival = player and player.rival
    if type(rival) == "table" and rival.playerId then return rival end
    return nil
end

local function playerSkin(player)
    return (player and player.appearance and player.appearance.skinId)
        or (player and player.skinId)
        or (player and player.visualId)
        or "street_brawler"
end

local function equippedWeapons(player)
    local equipped = player and player.equipped
    local weapons = equipped and equipped.weapons or player and player.weapons
    return type(weapons) == "table" and weapons or {}
end

local function buildPlayerOpponent(serverPlayer)
    local localPlayer = saveUtil.load()
    local snap = serverPlayer.snapshot or serverPlayer
    local final = statsUtil.calculate(snap)
    local equipped = snap.equipped or serverPlayer.equipped or {
        weapons = equippedWeapons(serverPlayer),
        armor = {},
        accessories = {},
        pets = {},
    }
    return {
        id         = serverPlayer.playerId or snap.playerId or serverPlayer.displayName,
        name       = serverPlayer.displayName or snap.name or serverPlayer.name or "Rival",
        serverPlayerId = serverPlayer.playerId or snap.playerId,
        visualId   = playerSkin(snap),
        level      = snap.level or serverPlayer.level or localPlayer.level or 1,
        attack     = final.attack or snap.attack or 100,
        defense    = final.defense or snap.defense or 100,
        speed      = final.speed or snap.speed or 100,
        hp         = final.hp or snap.hp or 100,
        spells     = snap.spells or serverPlayer.spells or {},
        difficulty = "player",
        bias       = "server",
        pets       = spells.getEquippedPetsForBattle(snap),
        equipped   = equipped,
        currentWeaponIndex = snap.currentWeaponIndex or 1,
        weaponUsesLeft = snap.weaponUsesLeft,
    }
end

local function showToast(msg, isError)
    local bg = display.newRoundedRect(sceneRoot, CX, SH-110, SW-40, 36, 8)
    bg:setFillColor(isError and 0.65 or 0.07,
                    isError and 0.08 or 0.38,
                    isError and 0.08 or 0.14, 0.96)
    bg.strokeWidth = 1.5
    bg:setStrokeColor(isError and 0.9 or 0.20,
                      isError and 0.3 or 0.85,
                      isError and 0.3 or 0.35)
    local t = display.newText({
        parent=sceneRoot, text=msg,
        x=CX, y=SH-110, font=ui.FONT_BOLD, fontSize=13, align="center"
    })
    t:setFillColor(1,1,1)
    local function fade(o)
        transition.to(o, { delay=1800, alpha=0, time=350,
            onComplete=function() if o and o.removeSelf then o:removeSelf() end end })
    end
    fade(bg); fade(t)
end

local function startRebelFight(rival)
    if not (rival and rival.playerId) then
        showToast("No rival found.", true)
        return
    end

    local p = saveUtil.load()
    if not energyUtil.spendEnergy(p) then
        saveUtil.save(p)
        showToast("Not enough energy.", true)
        return
    end
    saveUtil.save(p)

    api.pvp.prepare(rival.playerId, { mode = "fight" }, function(response)
        if response and response.ok and response.data and response.data.opponent then
            local opponent = buildPlayerOpponent(response.data.opponent)
            opponent.isRebel = true
            opponent.rebelRivalPlayerId = rival.playerId
            battleContext.startArena(opponent)
            composer.gotoScene("scenes.arena_battle", { effect="slideLeft", time=220 })
        else
            p.energy = math.min(30, (p.energy or 0) + 1)
            saveUtil.save(p)
            showToast("Could not reach rival.", true)
        end
    end)
end

-------------------------------------------------
-- TAX SLIDER POPUP
-------------------------------------------------
local function showTaxPopup()
    local popup = display.newGroup()
    sceneRoot:insert(popup)

    local dim = display.newRect(popup, CX, CY, SW, SH)
    dim:setFillColor(0, 0, 0, 0.75)

    local panelW = SW - 40
    local panelH = 190
    local panel = display.newRoundedRect(popup, CX, CY, panelW, panelH, 16)
    panel:setFillColor(0.03, 0.07, 0.20, 0.98)
    panel.strokeWidth = 2
    panel:setStrokeColor(0.28, 0.62, 1.00, 0.85)

    display.newText({
        parent=popup, text="TAX RATE",
        x=CX, y=CY - panelH * 0.5 + 28,
        font=ui.FONT_BOLD, fontSize=16
    }):setFillColor(0.35, 0.85, 1.0)

    local player = saveUtil.load()
    local current = 0.10
    if player.squad and player.squad.conquered and player.squad.conquered[1] then
        current = player.squad.conquered[1].taxRate or current
    end

    local stepIndex = 3
    for i, step in ipairs(TAX_STEPS) do
        if math.abs(step - current) < 0.001 then
            stepIndex = i
            break
        end
    end

    local rate = TAX_STEPS[stepIndex]
    local rateText = display.newText({
        parent=popup, text=math.floor(rate * 100).."%",
        x=CX, y=CY - 20,
        font=ui.FONT_BOLD, fontSize=28
    })
    rateText:setFillColor(1.0, 0.85, 0.2)

    display.newText({
        parent=popup, text="Applies to every fighter in your squad.",
        x=CX, y=CY + 18, width=panelW - 40,
        font=ui.FONT_BOLD, fontSize=9, align="center"
    }):setFillColor(0.55, 0.65, 0.85)

    local function adjustRate(delta)
        stepIndex = math.max(1, math.min(#TAX_STEPS, stepIndex + delta))
        rate = TAX_STEPS[stepIndex]
        rateText.text = math.floor(rate * 100).."%"
    end

    local minusBtn = display.newRoundedRect(popup, CX - 70, CY - 20, 44, 44, 8)
    minusBtn:setFillColor(0.06, 0.12, 0.30, 0.97)
    minusBtn.strokeWidth = 1.5
    minusBtn:setStrokeColor(0.3, 0.6, 1.0, 0.6)
    display.newText({
        parent=popup, text="-", x=CX - 70, y=CY - 22,
        font=ui.FONT_BOLD, fontSize=22
    }):setFillColor(1, 1, 1)
    minusBtn:addEventListener("tap", function() adjustRate(-1); return true end)

    local plusBtn = display.newRoundedRect(popup, CX + 70, CY - 20, 44, 44, 8)
    plusBtn:setFillColor(0.06, 0.12, 0.30, 0.97)
    plusBtn.strokeWidth = 1.5
    plusBtn:setStrokeColor(0.3, 0.6, 1.0, 0.6)
    display.newText({
        parent=popup, text="+", x=CX + 70, y=CY - 22,
        font=ui.FONT_BOLD, fontSize=22
    }):setFillColor(1, 1, 1)
    plusBtn:addEventListener("tap", function() adjustRate(1); return true end)

    local saveY = CY + panelH * 0.5 - 32
    local saveBtn
    local okBtn, imgBtn = pcall(display.newImageRect, popup, BTN_NAV_PATH, 126, 33)
    if okBtn and imgBtn then
        saveBtn = imgBtn
        saveBtn.x, saveBtn.y = CX, saveY
    else
        saveBtn = display.newRoundedRect(popup, CX, saveY, 126, 33, 7)
        saveBtn:setFillColor(0.04, 0.18, 0.46, 0.97)
        saveBtn.strokeWidth = 1.5
        saveBtn:setStrokeColor(0.28, 0.65, 1.0, 0.80)
    end
    display.newText({
        parent=popup, text="SAVE", x=CX, y=saveY,
        font=ui.FONT_BOLD, fontSize=14
    }):setFillColor(1, 1, 1)
    saveBtn:addEventListener("tap", function()
        local p = saveUtil.load()
        if p.squad and p.squad.conquered then
            for _, member in ipairs(p.squad.conquered) do
                if member.name then
                    squadUtil.setTaxRate(p, member.name, rate)
                end
            end
        end
        saveUtil.save(p)
        return ui.popupClose(popup, nil, { popup }, function()
            rebuild()
            showToast("Tax rate saved.", false)
        end)
    end)

    dim:addEventListener("tap", function()
        return ui.popupClose(popup, nil, { popup })
    end)

    ui.popupOpen(nil, { popup })
end

local function buildSquadGridTab(group)
    local player = saveUtil.load()
    local sq     = player.squad or { conquered={} }

    drawSkillsHeader(group, 32, "RIVAL", "CONQUEROR")

    local rival = getRivalInfo(player)
    local rivalPanelY = 99
    local rivalPanel = display.newRoundedRect(group, CX, rivalPanelY, SW - 30, 72, 10)
    rivalPanel:setFillColor(0.03, 0.07, 0.18, 0.82)
    rivalPanel.strokeWidth = 1.5
    rivalPanel:setStrokeColor(0.18, 0.46, 0.90, 0.60)

    if rival then
        local portraitX = CX - 104
        local portrait = display.newRoundedRect(group, portraitX, rivalPanelY, 66, 66, 8)
        portrait:setFillColor(0.08, 0.16, 0.35)
        portrait.strokeWidth = 1
        portrait:setStrokeColor(0.35, 0.72, 1.0, 0.62)

        local visualId = rival.visualId or rival.skin or rival.avatar
        if visualId then
            local okP, pSpr = pcall(display.newImageRect, group,
                "assets/sprites/characters/"..visualId.."/portrait.png", 60, 60)
            if okP and pSpr then
                pSpr.x, pSpr.y = portraitX, rivalPanelY
            end
        end

        local nameText = display.newText({
            parent=group, text=rival.name or rival.playerName or "Rival",
            x=CX - 58, y=rivalPanelY - 14,
            width=130,
            font=ui.FONT_BOLD, fontSize=15, align="left"
        })
        nameText.anchorX = 0
        nameText:setFillColor(1, 1, 1)
        drawGoldAmount(group, CX - 58, rivalPanelY + 12,
            rival.goldGiven or rival.contributionGold or rival.taxPaid or 0, 14, 0)

        local rebelBtn = display.newRoundedRect(group, CX + 106, rivalPanelY, 82, 34, 8)
        rebelBtn:setFillColor(0.32, 0.05, 0.07, 0.96)
        rebelBtn.strokeWidth = 1.5
        rebelBtn:setStrokeColor(1.0, 0.24, 0.26, 0.78)
        display.newText({
            parent=group, text="REBEL",
            x=CX + 104, y=rivalPanelY,
            font=ui.FONT_BOLD, fontSize=12
        }):setFillColor(1, 1, 1)
        rebelBtn:addEventListener("tap", function()
            startRebelFight(rival)
            return true
        end)
    else
        display.newText({
            parent=group, text="NO RIVAL",
            x=CX, y=rivalPanelY - 7, font=ui.FONT_BOLD, fontSize=13, align="center"
        }):setFillColor(0.55, 0.75, 1.0)
        display.newText({
            parent=group, text="Nobody is taxing your arena wins.",
            x=CX, y=rivalPanelY + 13, font=ui.FONT_BOLD, fontSize=8, align="center"
        }):setFillColor(0.42, 0.58, 0.84)
    end

    local squadHeaderY = 172
    local squadHeader = drawSkillsHeader(group, squadHeaderY, "YOUR SQUAD", "TAXED FIGHTERS")
    local settingsHit = display.newRoundedRect(squadHeader, SW - 34, squadHeaderY, 38, 34, 8)
    settingsHit:setFillColor(0.04, 0.11, 0.24, 0.88)
    settingsHit.strokeWidth = 1.5
    settingsHit:setStrokeColor(0.23, 0.60, 1.0, 0.70)
    local okSet, settingsIcon = pcall(display.newImageRect, squadHeader, SETTINGS_ICON_PATH, 24, 24)
    if okSet and settingsIcon then
        settingsIcon.x, settingsIcon.y = SW - 34, squadHeaderY
    end
    settingsHit:addEventListener("tap", function()
        showTaxPopup()
        return true
    end)

    local slots   = squadUtil.maxConquered()
    local cols    = 2
    local colGap  = 12
    local rowGap  = 48
    local cardW   = (SW - 34 - colGap) * 0.5
    local cardH   = 134
    local startX  = 17 + cardW * 0.5
    local startY  = 286

    for i = 1, slots do
        local conquered = sq.conquered[i]
        local row = math.floor((i - 1) / cols)
        local col = (i - 1) % cols
        local cardX = startX + col * (cardW + colGap)
        local cardY = startY + row * (cardH + rowGap)

        local card = display.newRoundedRect(group, cardX, cardY, cardW, cardH, 12)
        card.strokeWidth = 1.5

        if conquered then
            card:setFillColor(0.05, 0.12, 0.28, 0.95)
            card:setStrokeColor(0.22, 0.55, 1.0, 0.70)

            local portrait = display.newRoundedRect(group, cardX, cardY - 34, 66, 66, 8)
            portrait:setFillColor(0.08, 0.16, 0.35)
            portrait.strokeWidth = 1
            portrait:setStrokeColor(0.3, 0.6, 1.0, 0.5)

            local okP, pSpr = pcall(display.newImageRect, group,
                "assets/sprites/characters/"..conquered.visualId.."/portrait.png", 60, 60)
            if okP and pSpr then
                pSpr.x = cardX
                pSpr.y = cardY - 34
            end

            display.newText({
                parent=group, text=conquered.name,
                x=cardX, y=cardY + 18,
                width=cardW - 14,
                font=ui.FONT_BOLD, fontSize=12, align="center"
            }):setFillColor(1, 1, 1)

            display.newText({
                parent=group, text="LV."..conquered.level,
                x=cardX, y=cardY + 35,
                font=ui.FONT_BOLD, fontSize=9, align="center"
            }):setFillColor(0.55, 0.80, 1.0)

            drawGoldAmount(group, cardX - 18, cardY + 57,
                conquered.contributionGold or conquered.goldGiven or 0, 11, 0)

            local freeBtnY = cardY + 92
            local freeBtn = display.newRoundedRect(group, cardX, freeBtnY, cardW - 18, 26, 7)
            freeBtn:setFillColor(0.30, 0.06, 0.06, 0.97)
            freeBtn.strokeWidth = 1.5
            freeBtn:setStrokeColor(1.0, 0.20, 0.20, 0.70)
            display.newText({
                parent=group, text="LIBERATE", x=cardX, y=freeBtnY,
                font=ui.FONT_BOLD, fontSize=11
            }):setFillColor(1, 1, 1)
            freeBtn:addEventListener("tap", function()
                local p = saveUtil.load()
                squadUtil.removeConquered(p, conquered.name)
                saveUtil.save(p)
                rebuild()
                showToast(conquered.name.." has been liberated.", false)
                return true
            end)
        else
            card:setFillColor(0.04, 0.06, 0.14, 0.80)
            card:setStrokeColor(0.18, 0.22, 0.38, 0.55)

            display.newText({
                parent=group, text="EMPTY SLOT",
                x=cardX, y=cardY - 4,
                font=ui.FONT_BOLD, fontSize=12, align="center"
            }):setFillColor(0.55, 0.68, 0.95)

            display.newText({
                parent=group,
                text="Conquer in Arena",
                x=cardX, y=cardY + 18, width=cardW - 20,
                font=ui.FONT_BOLD, fontSize=8, align="center"
            }):setFillColor(0.30, 0.35, 0.55)
        end
    end
end

-------------------------------------------------
-- REBUILD
-------------------------------------------------
rebuild = function()
    if contentGrp then contentGrp:removeSelf(); contentGrp=nil end
    contentGrp = display.newGroup()
    sceneRoot:insert(contentGrp)

    local inner = display.newGroup()
    contentGrp:insert(inner)
    buildSquadGridTab(inner)
end

-------------------------------------------------
-- SCENE CREATE
-------------------------------------------------
function scene:create(event)
    local sg  = self.view
    sceneRoot = sg

    local okB, bg = pcall(display.newImage, "assets/sprites/ui/bg_home_grid.png")
    if okB and bg then
        local s = math.max(SW/bg.width, SH/bg.height)
        bg:scale(s,s); bg.x=CX; bg.y=CY; sg:insert(bg)
    end

    local dim = display.newRect(sg, CX, CY, SW, SH)
    dim:setFillColor(0,0,0,0.50)

    -- border
    local borderH = SH - 90
    local borderBorder = display.newRoundedRect(sg, CX, borderH*0.5, SW-8, borderH-8, 12)
    borderBorder:setFillColor(0,0,0,0)
    borderBorder.strokeWidth = 3
    borderBorder:setStrokeColor(0.20, 0.55, 1.00, 0.75)
    local inner2 = display.newRoundedRect(sg, CX, borderH*0.5, SW-14, borderH-14, 10)
    inner2:setFillColor(0,0,0,0)
    inner2.strokeWidth = 1
    inner2:setStrokeColor(0.35, 0.70, 1.00, 0.30)
end

-------------------------------------------------
-- SCENE SHOW
-------------------------------------------------
function scene:show(event)
    if event.phase ~= "did" then return end

    local player = saveUtil.load()

    -- check if returning from a conquest fight
    local conquestResult = composer.getVariable("conquestResult")
    if conquestResult then
        composer.setVariable("conquestResult", nil)
        if conquestResult.won and conquestResult.target then
            local p = saveUtil.load()
            local added = squadUtil.addConquered(p, conquestResult.target)
            if added then
                saveUtil.save(p)
                showToast(conquestResult.target.name.." has been conquered!", false)
            else
                showToast("Squad is full!", true)
            end
        elseif not conquestResult.won then
            showToast("You lost the conquest fight.", true)
        end
    end

    -- tick passive gold
    local gained, liberated = squadUtil.tick(player)
    if gained > 0 then
        saveUtil.save(player)
        showToast("+"..gained.."g from your squad!", false)
    end
    for _, name in ipairs(liberated) do
        showToast(name.." broke free from your squad!", true)
    end

    rebuild()
    refreshSquadFromServer()

    radialMenu.show(self.view, {
        activeScene = "squad",
        inner       = RADIAL_INNER,
        outer       = RADIAL_OUTER,
    })
end

-------------------------------------------------
-- SCENE HIDE
-------------------------------------------------
function scene:hide(event)
    if event.phase ~= "will" then return end
    radialMenu.destroy()
end

scene:addEventListener("create", scene)
scene:addEventListener("show",   scene)
scene:addEventListener("hide",   scene)

return scene
