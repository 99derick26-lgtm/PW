-- scenes/skills.lua
-- Pixel War Online - Skills Scene

local composer   = require("composer")
local scene      = composer.newScene()
local saveUtil   = require("utils.save")
local spellsDB   = require("utils.spells")
local ui         = require("utils.ui")
local radialMenu = require("utils.radial_menu")
local taskRewards = require("utils.task_rewards")

local SW = display.actualContentWidth
local SH = display.actualContentHeight
local CX = display.contentCenterX
local CY = display.contentCenterY

local RADIAL_INNER = {
    { icon="fight", label="Fight", scene="scenes.arena"  },
    { icon="home",  label="Home",  scene="scenes.home"   },
    { icon="bag",   label="Bag",   scene="scenes.bag"    },
    { icon="shop",  label="Shop",  scene="scenes.shop"   },
}
local RADIAL_OUTER = {
    { icon="squad",      label="Squad",      scene="scenes.squad"      },
    { icon="tournament", label="Tournament", scene="scenes.tournament" },
    { icon="pet",        label="Pets",       scene="scenes.pets"       },
    { icon="skills",     label="Skills",     scene="scenes.skills"     },
}

-------------------------------------------------
-- LAYOUT
-------------------------------------------------
local HEADER_H  = 50
local BORDER_B  = 96
local COLS      = 2
local ROWS_PER_PAGE = 3
local PAD       = 14
local GRID_TOP  = HEADER_H + 20
local FOOTER_H  = 30
local GRID_BOTTOM = SH - BORDER_B - FOOTER_H - 8
local CARD_INFO_H = 34
local CARD_GAP_Y = 10
local WIDTH_ICON_SIZE = math.floor((SW - PAD * (COLS + 1)) / COLS)
local HEIGHT_ICON_SIZE = math.floor((GRID_BOTTOM - GRID_TOP - (ROWS_PER_PAGE * CARD_INFO_H) - ((ROWS_PER_PAGE - 1) * CARD_GAP_Y)) / ROWS_PER_PAGE)
local ICON_SIZE = math.max(86, math.min(WIDTH_ICON_SIZE, HEIGHT_ICON_SIZE))
local ROW_H     = ICON_SIZE + CARD_INFO_H + CARD_GAP_Y

-------------------------------------------------
-- STATE
-------------------------------------------------
local sceneRoot = nil
local goldText  = nil
local player    = nil
local popup     = nil
local popupDim  = nil
local popupContent = nil
local currentPage = 1
local nextBtnBg = nil
local nextBtnText = nil
local pageText = nil

local buildGrid
local refreshSkillsView

-------------------------------------------------
-- VISUAL THEMES
-------------------------------------------------
local function getTierStyle(def)
    if def.unlockLevel >= 20 then
        return {
            label = "ULT",
            accent = { 1.00, 0.82, 0.20 },
            glow   = { 1.00, 0.58, 0.18 },
        }
    elseif def.unlockLevel >= 15 then
        return {
            label = "EPIC",
            accent = { 0.92, 0.36, 0.92 },
            glow   = { 0.46, 0.22, 0.90 },
        }
    elseif def.unlockLevel >= 10 then
        return {
            label = "RARE",
            accent = { 0.28, 0.82, 1.00 },
            glow   = { 0.10, 0.38, 0.92 },
        }
    end
    return {
        label = "CORE",
        accent = { 0.28, 1.00, 0.55 },
        glow   = { 0.06, 0.44, 0.18 },
    }
end

local function getCardState(def, pl, spellId)
    local owned  = spellsDB.owns(pl, spellId)
    local locked = pl.level < def.unlockLevel
    local canBuy = spellsDB.canBuy(pl, spellId)
    return owned, locked, canBuy
end

local function getPageCount()
    return math.max(1, math.ceil(#spellsDB.ORDER / (COLS * ROWS_PER_PAGE)))
end

local function syncPager()
    local totalPages = getPageCount()
    if currentPage > totalPages then currentPage = totalPages end
    if currentPage < 1 then currentPage = 1 end

    if pageText then
        pageText.text = "PAGE " .. currentPage .. "/" .. totalPages
    end

    if nextBtnBg and nextBtnText then
        local active = totalPages > 1
        nextBtnBg:setFillColor(active and 0.08 or 0.05, active and 0.14 or 0.07, active and 0.30 or 0.12, 0.96)
        nextBtnBg.strokeWidth = 1.5
        nextBtnBg:setStrokeColor(active and 0.28 or 0.18, active and 0.66 or 0.22, active and 1.0 or 0.30, active and 0.82 or 0.45)
        nextBtnText:setFillColor(active and 0.70 or 0.38, active and 0.88 or 0.42, active and 1.0 or 0.48)
        nextBtnText.alpha = active and 1.0 or 0.65
    end
end

local function showRadial()
    radialMenu.show(sceneRoot, {
        activeScene = "skills",
        inner       = RADIAL_INNER,
        outer       = RADIAL_OUTER,
    })
end

refreshSkillsView = function(pl)
    local freshPlayer = pl or saveUtil.load()
    buildGrid(sceneRoot, freshPlayer)
    showRadial()
end

-------------------------------------------------
-- TOAST
-------------------------------------------------
local function showToast(msg, isError)
    local bg = display.newRoundedRect(sceneRoot, CX, SH - 110, SW - 40, 36, 8)
    bg:setFillColor(isError and 0.65 or 0.07,
                    isError and 0.08 or 0.42,
                    isError and 0.08 or 0.14, 0.96)
    bg.strokeWidth = 1.5
    bg:setStrokeColor(isError and 0.9 or 0.22,
                      isError and 0.3 or 0.88,
                      isError and 0.3 or 0.38)

    local t = display.newText({
        parent=sceneRoot, text=msg,
        x=CX, y=SH - 110, font=ui.FONT_BOLD, fontSize=13, align="center"
    })
    t:setFillColor(1, 1, 1)

    local function fade(o)
        transition.to(o, {
            delay = 1500,
            alpha = 0,
            time = 350,
            onComplete = function()
                if o and o.removeSelf then o:removeSelf() end
            end
        })
    end

    fade(bg)
    fade(t)
end

-------------------------------------------------
-- POPUP
-------------------------------------------------
local function closePopup()
    if popup and popup.removeSelf then
        return ui.popupClose(popup, popupDim, { popupContent }, function()
            popup = nil
            popupDim = nil
            popupContent = nil
        end)
    end
    popup = nil
    popupDim = nil
    popupContent = nil
    return true
end

local function showPopup(spellId)
    closePopup()
    player = saveUtil.load()

    local def           = spellsDB.DEFS[spellId]
    local owned, locked, canBuy = getCardState(def, player, spellId)
    local tier          = getTierStyle(def)

    popup = display.newGroup()
    sceneRoot:insert(popup)

    popupDim = display.newRect(popup, CX, CY, SW, SH)
    popupDim:setFillColor(0, 0, 0, 0.80)
    popupDim:addEventListener("tap", closePopup)

    popupContent = display.newGroup()
    popup:insert(popupContent)

    local panelW = SW - 28
    local panelH = 318
    local panel  = display.newRoundedRect(popupContent, CX, CY, panelW, panelH, 18)
    panel:setFillColor(0.03, 0.07, 0.20, 0.98)
    panel.strokeWidth = 2
    if owned then
        panel:setStrokeColor(0.18, 0.88, 0.35, 0.90)
    elseif locked then
        panel:setStrokeColor(0.28, 0.28, 0.42, 0.75)
    else
        panel:setStrokeColor(tier.accent[1], tier.accent[2], tier.accent[3], 0.88)
    end

    local accentBar = display.newRoundedRect(popupContent, CX, CY - panelH * 0.5 + 4, panelW - 10, 4, 2)
    if owned then
        accentBar:setFillColor(0.22, 1.0, 0.45, 0.84)
    elseif locked then
        accentBar:setFillColor(0.28, 0.28, 0.36, 0.72)
    else
        accentBar:setFillColor(tier.accent[1], tier.accent[2], tier.accent[3], 0.84)
    end

    local tierChip = display.newRoundedRect(popupContent, CX, CY - panelH * 0.5 + 28, 82, 18, 6)
    tierChip:setFillColor(0.06, 0.10, 0.20, 0.96)
    tierChip.strokeWidth = 1
    tierChip:setStrokeColor(tier.accent[1], tier.accent[2], tier.accent[3], 0.55)

    local tierText = display.newText({
        parent=popupContent,
        text=owned and "INSTALLED" or tier.label .. " SKILL",
        x=CX, y=tierChip.y, font=ui.FONT_BOLD, fontSize=8
    })
    if owned then
        tierText:setFillColor(0.36, 1.0, 0.50)
    else
        tierText:setFillColor(tier.accent[1], tier.accent[2], tier.accent[3])
    end

    local iconY  = CY - panelH * 0.5 + 94
    local halo   = display.newCircle(popupContent, CX, iconY, 54)
    if owned then
        halo:setFillColor(0.18, 0.88, 0.35, 0.08)
    elseif locked then
        halo:setFillColor(0.14, 0.14, 0.18, 0.06)
    else
        halo:setFillColor(tier.glow[1], tier.glow[2], tier.glow[3], 0.09)
    end

    local iconBg = display.newRoundedRect(popupContent, CX, iconY, 92, 92, 14)
    iconBg:setFillColor(0.06, 0.10, 0.26, 0.92)
    iconBg.strokeWidth = 2
    if owned then
        iconBg:setStrokeColor(0.18, 0.88, 0.35, 0.72)
    elseif locked then
        iconBg:setStrokeColor(0.28, 0.28, 0.42, 0.52)
    else
        iconBg:setStrokeColor(tier.accent[1], tier.accent[2], tier.accent[3], 0.65)
    end

    local okI, ico = pcall(display.newImageRect, popupContent, def.icon, 78, 78)
    if okI and ico then
        ico.x = CX
        ico.y = iconY
        if locked then ico:setFillColor(0.32, 0.32, 0.32) end
    else
        local fb = display.newText({
            parent=popupContent, text=string.upper(string.sub(def.name, 1, 1)),
            x=CX, y=iconY, font=ui.FONT_BOLD, fontSize=28
        })
        fb:setFillColor(locked and 0.50 or tier.accent[1],
                        locked and 0.50 or tier.accent[2],
                        locked and 0.58 or tier.accent[3])
    end

    local nameY = iconY + 58
    local nameT = display.newText({
        parent=popupContent, text=def.name,
        x=CX, y=nameY, font=ui.FONT_BOLD, fontSize=18, align="center"
    })
    if owned then
        nameT:setFillColor(0.40, 1.0, 0.55)
    elseif locked then
        nameT:setFillColor(0.55, 0.55, 0.62)
    else
        nameT:setFillColor(0.90, 0.96, 1.0)
    end

    local metaY = nameY + 18
    if def.maxUses then
        local mt = display.newText({
            parent=popupContent, text=tostring(def.maxUses) .. "x per battle",
            x=CX, y=metaY, font=ui.FONT_BOLD, fontSize=9, align="center"
        })
        mt:setFillColor(0.45, 0.72, 1.0)
    end

    local descY = (def.maxUses and metaY or nameY) + 24
    local desc = display.newText({
        parent=popupContent, text=def.description,
        x=CX, y=descY, width=panelW - 40,
        font=ui.FONT_BOLD, fontSize=11, align="center"
    })
    desc:setFillColor(0.78, 0.84, 0.95)

    local reqY = descY + 40
    local reqBg = display.newRoundedRect(popupContent, CX, reqY, 132, 20, 5)
    reqBg:setFillColor(0.06, 0.10, 0.28, 0.90)
    reqBg.strokeWidth = 1
    reqBg:setStrokeColor(0.22, 0.48, 0.88, 0.45)
    local reqText = display.newText({
        parent=popupContent, text="Requires Lv." .. def.unlockLevel,
        x=CX, y=reqY, font=ui.FONT_BOLD, fontSize=9
    })
    reqText:setFillColor(locked and 0.55 or 0.35, locked and 0.55 or 0.75, locked and 0.65 or 1.0)

    local actionY = CY + panelH * 0.5 - 36

    if owned then
        local ob = display.newRoundedRect(popupContent, CX, actionY, 152, 36, 9)
        ob:setFillColor(0.07, 0.35, 0.14, 0.97)
        ob.strokeWidth = 1.5
        ob:setStrokeColor(0.18, 0.85, 0.32, 0.80)
        local ot = display.newText({
            parent=popupContent, text="INSTALLED",
            x=CX, y=actionY, font=ui.FONT_BOLD, fontSize=14
        })
        ot:setFillColor(0.40, 1.00, 0.55)
    elseif locked then
        local lb = display.newRoundedRect(popupContent, CX, actionY, 182, 36, 9)
        lb:setFillColor(0.09, 0.09, 0.18, 0.97)
        lb.strokeWidth = 1.5
        lb:setStrokeColor(0.28, 0.28, 0.44, 0.70)
        local lt = display.newText({
            parent=popupContent, text="UNLOCK AT LV." .. def.unlockLevel,
            x=CX, y=actionY, font=ui.FONT_BOLD, fontSize=12
        })
        lt:setFillColor(0.50, 0.50, 0.65)
    else
        local btnW  = 204
        local btnH  = 38
        local btnBg = display.newRoundedRect(popupContent, CX, actionY, btnW, btnH, 9)
        btnBg:setFillColor(canBuy and 0.04 or 0.12,
                           canBuy and 0.16 or 0.12,
                           canBuy and 0.46 or 0.20, 0.97)
        btnBg.strokeWidth = 2
        if canBuy then
            btnBg:setStrokeColor(tier.accent[1], tier.accent[2], tier.accent[3], 0.85)
        else
            btnBg:setStrokeColor(0.30, 0.30, 0.42, 0.70)
        end

        local price = display.newText({
            parent=popupContent, text=def.cost .. "g",
            x=CX - 34, y=actionY, font=ui.FONT_BOLD, fontSize=14
        })
        price:setFillColor(canBuy and 1.0 or 0.50,
                           canBuy and 0.85 or 0.50,
                           canBuy and 0.20 or 0.50)

        local div = display.newRect(popupContent, CX + 10, actionY, 1, btnH - 12)
        div:setFillColor(0.30, 0.52, 0.90, 0.35)

        local buy = display.newText({
            parent=popupContent, text="BUY",
            x=CX + 52, y=actionY, font=ui.FONT_BOLD, fontSize=14
        })
        buy:setFillColor(canBuy and 1.0 or 0.45, 1.0, canBuy and 1.0 or 0.45)

        local capId = spellId
        if canBuy then
            btnBg:addEventListener("tap", function()
                local fresh = saveUtil.load()
                if spellsDB.buy(fresh, capId) then
                    saveUtil.save(fresh)
                    player = fresh
                    if goldText then goldText.text = tostring(fresh.gold or 0) end
                    closePopup()
                    local didReward = taskRewards.process(sceneRoot, fresh, {
                        {
                            id = "buy_a_skill",
                            amount = 1,
                            message = "You purchased your first skill.",
                        },
                    }, function()
                        refreshSkillsView(saveUtil.load())
                    end)
                    if not didReward then
                        refreshSkillsView(fresh)
                    end
                    showToast(spellsDB.DEFS[capId].name .. " purchased!", false)
                else
                    showToast("Cannot purchase right now.", true)
                end
                return true
            end)
        else
            btnBg:addEventListener("tap", function()
                showToast("Need " .. def.cost .. "g to buy this skill.", true)
                return true
            end)
        end
    end

    local closeX = CX + panelW * 0.5 - 22
    local closeY = CY - panelH * 0.5 + 22
    local closeBg = display.newCircle(popupContent, closeX, closeY, 14)
    closeBg:setFillColor(0.07, 0.11, 0.26, 0.96)
    closeBg.strokeWidth = 1.5
    closeBg:setStrokeColor(0.32, 0.58, 1.0, 0.55)

    local closeT = display.newText({
        parent=popupContent, text="X",
        x=closeX, y=closeY - 1, font=ui.FONT_BOLD, fontSize=13
    })
    closeT:setFillColor(0.70, 0.80, 1.0)
    closeBg:addEventListener("tap", closePopup)
    closeT:addEventListener("tap", closePopup)

    ui.popupOpen(popupDim, { popupContent })
end

-------------------------------------------------
-- GRID
-------------------------------------------------
buildGrid = function(sg, pl)
    if sg._gridGroup then sg._gridGroup:removeSelf(); sg._gridGroup = nil end

    local grid = display.newGroup()
    sg:insert(grid)
    sg._gridGroup = grid

    local contentBottom = GRID_BOTTOM
    local gridPanelY = (GRID_TOP + contentBottom) * 0.5
    local gridPanelH = contentBottom - GRID_TOP + 12

    local gridPanel = display.newRoundedRect(grid, CX, gridPanelY, SW - 12, gridPanelH, 14)
    gridPanel:setFillColor(0.01, 0.03, 0.10, 0.28)
    gridPanel.strokeWidth = 1.5
    gridPanel:setStrokeColor(0.16, 0.36, 0.78, 0.24)

    for i = 1, 8 do
        local y = GRID_TOP - 4 + i * math.floor(gridPanelH / 9)
        local scan = display.newRect(grid, CX, y, SW - 26, 1)
        scan:setFillColor(0.18, 0.42, 0.82, 0.05)
    end

    local visiblePerPage = COLS * ROWS_PER_PAGE
    local startIndex = ((currentPage - 1) * visiblePerPage) + 1
    local endIndex = math.min(startIndex + visiblePerPage - 1, #spellsDB.ORDER)

    for i = startIndex, endIndex do
        local spellId         = spellsDB.ORDER[i]
        local def            = spellsDB.DEFS[spellId]
        local localIndex     = i - startIndex
        local col            = localIndex % COLS
        local row            = math.floor(localIndex / COLS)
        local tier           = getTierStyle(def)
        local cardX          = PAD + col * (ICON_SIZE + PAD) + ICON_SIZE * 0.5
        local cardY          = GRID_TOP + row * ROW_H + ICON_SIZE * 0.5
        local owned, locked, canBuy = getCardState(def, pl, spellId)

        local card = display.newGroup()
        grid:insert(card)

        local plateGlow = display.newRoundedRect(card, cardX, cardY, ICON_SIZE + 8, ICON_SIZE + 8, 14)
        plateGlow:setFillColor(0, 0, 0, 0)
        plateGlow.strokeWidth = 2
        if owned then
            plateGlow:setStrokeColor(0.18, 0.92, 0.38, 0.40)
        elseif locked then
            plateGlow:setStrokeColor(0.16, 0.18, 0.28, 0.30)
        else
            plateGlow:setStrokeColor(tier.accent[1], tier.accent[2], tier.accent[3], 0.34)
        end

        local plate = display.newRoundedRect(card, cardX, cardY, ICON_SIZE + 2, ICON_SIZE + 2, 12)
        if owned then
            plate:setFillColor(0.04, 0.16, 0.08, 0.96)
            plate.strokeWidth = 2
            plate:setStrokeColor(0.24, 0.96, 0.42, 0.72)
        elseif locked then
            plate:setFillColor(0.03, 0.05, 0.10, 0.96)
            plate.strokeWidth = 1.5
            plate:setStrokeColor(0.18, 0.20, 0.28, 0.60)
        else
            plate:setFillColor(0.03, 0.08, 0.18, 0.96)
            plate.strokeWidth = 1.5
            plate:setStrokeColor(tier.accent[1], tier.accent[2], tier.accent[3], 0.58)
        end

        local topAccent = display.newRoundedRect(card, cardX, cardY - ICON_SIZE * 0.5 + 7, ICON_SIZE - 10, 3, 2)
        if owned then
            topAccent:setFillColor(0.22, 1.0, 0.45, 0.88)
        elseif locked then
            topAccent:setFillColor(0.22, 0.24, 0.30, 0.52)
        else
            topAccent:setFillColor(tier.accent[1], tier.accent[2], tier.accent[3], 0.82)
        end

        local tierChip = display.newRoundedRect(card, cardX - ICON_SIZE * 0.5 + 32, cardY - ICON_SIZE * 0.5 + 16, 44, 16, 5)
        if owned then
            tierChip:setFillColor(0.06, 0.22, 0.10, 0.94)
            tierChip.strokeWidth = 1
            tierChip:setStrokeColor(0.22, 1.0, 0.42, 0.55)
        elseif locked then
            tierChip:setFillColor(0.07, 0.08, 0.12, 0.94)
            tierChip.strokeWidth = 1
            tierChip:setStrokeColor(0.22, 0.24, 0.30, 0.48)
        else
            tierChip:setFillColor(0.06, 0.10, 0.20, 0.96)
            tierChip.strokeWidth = 1
            tierChip:setStrokeColor(tier.accent[1], tier.accent[2], tier.accent[3], 0.55)
        end

        local tierText = display.newText({
            parent=card,
            text=owned and "OWNED" or tier.label,
            x=tierChip.x, y=tierChip.y, font=ui.FONT_BOLD, fontSize=7
        })
        if owned then
            tierText:setFillColor(0.36, 1.0, 0.50)
        elseif locked then
            tierText:setFillColor(0.42, 0.45, 0.52)
        else
            tierText:setFillColor(tier.accent[1], tier.accent[2], tier.accent[3])
        end

        local okI, ico = pcall(display.newImageRect, card, def.icon, ICON_SIZE - 10, ICON_SIZE - 10)
        if okI and ico then
            ico.x = cardX
            ico.y = cardY
            if locked then
                ico:setFillColor(0.28, 0.28, 0.28)
            elseif not owned then
                ico:setFillColor(0.84, 0.84, 0.84)
            end
        else
            local fb = display.newRoundedRect(card, cardX, cardY, ICON_SIZE - 10, ICON_SIZE - 10, 10)
            if owned then
                fb:setFillColor(0.08, 0.24, 0.12, 1.0)
            elseif locked then
                fb:setFillColor(0.08, 0.08, 0.12, 1.0)
            else
                fb:setFillColor(tier.glow[1], tier.glow[2], tier.glow[3], 0.62)
            end

            local lt = display.newText({
                parent=card, text=string.upper(string.sub(def.name, 1, 1)),
                x=cardX, y=cardY, font=ui.FONT_BOLD, fontSize=22
            })
            if owned then
                lt:setFillColor(0.42, 1.0, 0.58)
            elseif locked then
                lt:setFillColor(0.32, 0.32, 0.36)
            else
                lt:setFillColor(tier.accent[1], tier.accent[2], tier.accent[3])
            end
        end

        if locked then
            local lockShade = display.newRoundedRect(card, cardX, cardY, ICON_SIZE - 12, ICON_SIZE - 12, 10)
            lockShade:setFillColor(0.00, 0.00, 0.00, 0.42)
            local lockText = display.newText({
                parent=card, text="LOCKED",
                x=cardX, y=cardY + 2, font=ui.FONT_BOLD, fontSize=11
            })
            lockText:setFillColor(0.48, 0.50, 0.58)
        end

        if def.maxUses then
            local useTag = display.newRoundedRect(card, cardX + ICON_SIZE * 0.5 - 20, cardY - ICON_SIZE * 0.5 + 16, 30, 16, 5)
            useTag:setFillColor(0.10, 0.08, 0.18, locked and 0.86 or 0.94)
            useTag.strokeWidth = 1
            useTag:setStrokeColor(0.42, 0.58, 1.0, locked and 0.18 or 0.40)
            local useText = display.newText({
                parent=card, text=tostring(def.maxUses) .. "x",
                x=useTag.x, y=useTag.y, font=ui.FONT_BOLD, fontSize=7
            })
            useText:setFillColor(locked and 0.45 or 0.55, locked and 0.48 or 0.78, locked and 0.55 or 1.0)
        end

        local nt = display.newText({
            parent=card, text=def.name,
            x=cardX, y=cardY + ICON_SIZE * 0.5 + 8,
            width=ICON_SIZE + 10, font=ui.FONT_BOLD, fontSize=9, align="center"
        })
        if owned then
            nt:setFillColor(0.42, 1.0, 0.58)
        elseif locked then
            nt:setFillColor(0.42, 0.45, 0.50)
        else
            nt:setFillColor(0.84, 0.92, 1.0)
        end

        local pillY = cardY + ICON_SIZE * 0.5 + 22
        local pillBg = display.newRoundedRect(card, cardX, pillY, ICON_SIZE - 30, 16, 5)
        if locked then
            pillBg:setFillColor(0.08, 0.09, 0.14, 0.94)
            pillBg.strokeWidth = 1
            pillBg:setStrokeColor(0.22, 0.24, 0.30, 0.45)
            local pt = display.newText({
                parent=card, text="REQ LV " .. def.unlockLevel,
                x=cardX, y=pillY, font=ui.FONT_BOLD, fontSize=7, align="center"
            })
            pt:setFillColor(0.50, 0.52, 0.62)
        elseif owned then
            pillBg:setFillColor(0.06, 0.20, 0.10, 0.94)
            pillBg.strokeWidth = 1
            pillBg:setStrokeColor(0.22, 1.0, 0.42, 0.42)
            local pt = display.newText({
                parent=card, text="INSTALLED",
                x=cardX, y=pillY, font=ui.FONT_BOLD, fontSize=7, align="center"
            })
            pt:setFillColor(0.36, 1.0, 0.50)
        else
            pillBg:setFillColor(0.08, 0.10, 0.18, 0.94)
            pillBg.strokeWidth = 1
            pillBg:setStrokeColor(1.0, 0.82, 0.20, 0.40)
            local pt = display.newText({
                parent=card, text="BUY " .. def.cost .. "g",
                x=cardX, y=pillY, font=ui.FONT_BOLD, fontSize=7, align="center"
            })
            pt:setFillColor(canBuy and 1.0 or 0.65,
                            canBuy and 0.84 or 0.52,
                            canBuy and 0.22 or 0.42)
        end

        local capId = spellId
        local hit = display.newRoundedRect(card, cardX, cardY + 12, ICON_SIZE + 8, ROW_H - 12, 12)
        hit:setFillColor(1, 1, 1, 0.01)
        hit:addEventListener("tap", function()
            player = saveUtil.load()
            showPopup(capId)
            return true
        end)
    end

    syncPager()
end

-------------------------------------------------
-- SCENE CREATE
-------------------------------------------------
function scene:create(event)
    local sg = self.view
    sceneRoot = sg

    local okB, bg = pcall(display.newImage, "assets/sprites/ui/bg_home_grid.png")
    if okB and bg then
        local s = math.max(SW / bg.width, SH / bg.height)
        bg:scale(s, s)
        bg.x = CX
        bg.y = CY
        sg:insert(bg)
    end

    local dim = display.newRect(sg, CX, CY, SW, SH)
    dim:setFillColor(0, 0, 0, 0.56)

    for i = 1, 18 do
        local line = display.newRect(sg, CX, i * (SH / 18), SW, 1)
        line:setFillColor(0.06, 0.18, 0.42, 0.04)
        line.isHitTestable = false
    end

    local borderInset = 0
    local borderH     = SH - BORDER_B
    local borderCY    = borderH * 0.5

    local outerBorder = display.newRoundedRect(sg, CX, borderCY, SW - borderInset * 2, borderH - borderInset * 2, 12)
    outerBorder:setFillColor(0, 0, 0, 0)
    outerBorder.strokeWidth = 3
    outerBorder:setStrokeColor(0.20, 0.55, 1.00, 0.75)

    local innerBorder = display.newRoundedRect(sg, CX, borderCY, SW - borderInset * 2 - 6, borderH - borderInset * 2 - 6, 10)
    innerBorder:setFillColor(0, 0, 0, 0)
    innerBorder.strokeWidth = 1
    innerBorder:setStrokeColor(0.35, 0.70, 1.00, 0.35)

    local corners = {
        { borderInset + 10, borderInset + 10 },
        { SW - borderInset - 10, borderInset + 10 },
        { borderInset + 10, borderH - borderInset - 10 },
        { SW - borderInset - 10, borderH - borderInset - 10 },
    }
    for _, c in ipairs(corners) do
        local dot = display.newCircle(sg, c[1], c[2], 4)
        dot:setFillColor(0.35, 0.75, 1.00, 0.90)
    end

    local hdrGlow = display.newRoundedRect(sg, CX, HEADER_H * 0.5, SW - 8, HEADER_H + 6, 12)
    hdrGlow:setFillColor(0, 0, 0, 0)
    hdrGlow.strokeWidth = 2
    hdrGlow:setStrokeColor(0.12, 0.48, 1.0, 0.38)

    local hdr = display.newRoundedRect(sg, CX, HEADER_H * 0.5, SW - 12, HEADER_H, 10)
    hdr:setFillColor(0.02, 0.06, 0.16, 0.96)
    hdr.strokeWidth = 1.5
    hdr:setStrokeColor(0.18, 0.38, 0.92, 0.48)

    local topLine = display.newRect(sg, CX, 6, SW - 24, 2)
    topLine:setFillColor(0.30, 0.66, 1.0, 0.62)

    local title = display.newText({
        parent=sg, text="SKILLS",
        x=18, y=HEADER_H * 0.5 - 6, font=ui.FONT_BOLD, fontSize=18, align="left"
    })
    title.anchorX = 0
    title:setFillColor(0.40, 0.84, 1.0)

    local subtitle = display.newText({
        parent=sg, text="COMBAT PROGRAMS",
        x=18, y=HEADER_H * 0.5 + 10, font=ui.FONT_BOLD, fontSize=8, align="left"
    })
    subtitle.anchorX = 0
    subtitle:setFillColor(0.42, 0.70, 1.0, 0.82)

    local goldChip = display.newRoundedRect(sg, SW - 66, HEADER_H * 0.5, 112, 28, 8)
    goldChip:setFillColor(0.08, 0.10, 0.22, 0.96)
    goldChip.strokeWidth = 1.5
    goldChip:setStrokeColor(1.0, 0.82, 0.20, 0.52)

    local goldLabel = display.newText({
        parent=sg, text="GOLD",
        x=SW - 102, y=HEADER_H * 0.5, font=ui.FONT_BOLD, fontSize=8, align="left"
    })
    goldLabel.anchorX = 0
    goldLabel:setFillColor(1.0, 0.82, 0.20, 0.82)

    goldText = display.newText({
        parent=sg, text="...",
        x=SW - 18, y=HEADER_H * 0.5, font=ui.FONT_BOLD, fontSize=13, align="right"
    })
    goldText.anchorX = 1.0
    goldText:setFillColor(1.0, 0.90, 0.28)

    local footerY = SH - BORDER_B - FOOTER_H * 0.5 - 2
    local footerLine = display.newRect(sg, CX, footerY - FOOTER_H * 0.5 - 4, SW - 20, 1)
    footerLine:setFillColor(0.20, 0.48, 0.88, 0.28)

    pageText = display.newText({
        parent=sg, text="PAGE 1/1",
        x=18, y=footerY, font=ui.FONT_BOLD, fontSize=8, align="left"
    })
    pageText.anchorX = 0
    pageText:setFillColor(0.42, 0.70, 1.0, 0.84)

    nextBtnBg = display.newRoundedRect(sg, SW - 44, footerY, 70, 22, 6)
    nextBtnBg.strokeWidth = 1.5
    nextBtnText = display.newText({
        parent=sg, text="NEXT",
        x=nextBtnBg.x, y=footerY, font=ui.FONT_BOLD, fontSize=9
    })

    nextBtnBg:addEventListener("tap", function()
        local totalPages = getPageCount()
        if totalPages <= 1 then
            showToast("More skills coming soon.", true)
            return true
        end
        currentPage = currentPage + 1
        if currentPage > totalPages then currentPage = 1 end
        player = saveUtil.load()
        refreshSkillsView(player)
        return true
    end)
end

-------------------------------------------------
-- SCENE SHOW
-------------------------------------------------
function scene:show(event)
    if event.phase ~= "did" then return end
    player = saveUtil.load()
    currentPage = 1
    if goldText then goldText.text = tostring(player.gold or 0) end
    refreshSkillsView(player)
end

-------------------------------------------------
-- SCENE HIDE
-------------------------------------------------
function scene:hide(event)
    if event.phase ~= "will" then return end
    closePopup()
    radialMenu.destroy()
end

scene:addEventListener("create", scene)
scene:addEventListener("show",   scene)
scene:addEventListener("hide",   scene)

return scene
