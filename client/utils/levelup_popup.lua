local ui = require("utils.ui")

local M = {}

local function getLevelStatPoints(level)
    if level <= 10 then
        return 20
    end
    return 30
end

local function rollLevelGain(level)
    local totalPoints = getLevelStatPoints(level)
    local hpPoints = math.floor(totalPoints * (math.random(40, 45) / 100))
    local remaining = totalPoints - hpPoints

    local attack = 0
    local defense = 0
    local speed = 0

    for i = 1, remaining do
        local pick = math.random(3)
        if pick == 1 then
            attack = attack + 1
        elseif pick == 2 then
            defense = defense + 1
        else
            speed = speed + 1
        end
    end

    return {
        attack = attack,
        defense = defense,
        speed = speed,
        hp = hpPoints,
    }
end

function M.applyLevelUps(player, xpUtil)
    local summary = {
        levelsGained = 0,
        attack = 0,
        defense = 0,
        speed = 0,
        hp = 0,
        startingLevel = player.level or 1,
    }

    while true do
        local needed = xpUtil.getXpToLevel(player.level)
        if (player.xp or 0) < needed then break end

        player.xp = player.xp - needed
        player.level = player.level + 1
        local gain = rollLevelGain(player.level)
        player.attack = (player.attack or 0) + gain.attack
        player.defense = (player.defense or 0) + gain.defense
        player.speed = (player.speed or 0) + gain.speed
        player.hp = (player.hp or 0) + gain.hp

        summary.levelsGained = summary.levelsGained + 1
        summary.attack = summary.attack + gain.attack
        summary.defense = summary.defense + gain.defense
        summary.speed = summary.speed + gain.speed
        summary.hp = summary.hp + gain.hp
    end

    if summary.levelsGained <= 0 then
        return nil
    end

    summary.finalLevel = player.level
    return summary
end

function M.show(summary, onClose)
    if not summary or (summary.levelsGained or 0) <= 0 then
        if onClose then onClose() end
        return
    end

    local SW = display.actualContentWidth
    local SH = display.actualContentHeight
    local CX = display.contentCenterX
    local CY = display.contentCenterY

    local popup = display.newGroup()
    display.getCurrentStage():insert(popup)

    local dim = display.newRect(popup, CX, CY, SW, SH)
    dim:setFillColor(0, 0, 0, 0.78)
    dim.isHitTestable = true

    local panelW = math.min(SW - 72, 248)
    local panelH = 340
    local panelY = CY

    local okBurst, burst = pcall(display.newImageRect, popup, "assets/sprites/ui/icons/yay.png", 150, 96)
    if okBurst and burst then
        burst.x = CX
        burst.y = panelY - 108
        burst.alpha = 0.95
        burst.isHitTestable = false
    end

    local beamLeft = display.newRect(popup, CX - 46, panelY - 18, 24, 250)
    beamLeft:setFillColor(0.36, 1.0, 0.30, 0.22)
    beamLeft.rotation = -8
    local beamRight = display.newRect(popup, CX + 46, panelY - 18, 24, 250)
    beamRight:setFillColor(0.36, 0.92, 1.0, 0.20)
    beamRight.rotation = 8

    for i = 1, 18 do
        local particle = display.newCircle(popup, CX, panelY - 96, math.random(2, 4))
        local tint = (i % 2 == 0) and { 0.38, 1.0, 0.34 } or { 0.38, 0.90, 1.0 }
        particle:setFillColor(tint[1], tint[2], tint[3], 0.92)
        particle.isHitTestable = false
        transition.to(particle, {
            x = CX + math.random(-90, 90),
            y = panelY - 138 + math.random(-34, 34),
            alpha = 0,
            time = 700 + math.random(0, 360),
            transition = easing.outQuad,
            onComplete = function()
                if particle and particle.removeSelf then particle:removeSelf() end
            end
        })
    end

    local glow = display.newRoundedRect(popup, CX, panelY, panelW + 8, panelH + 8, 16)
    glow:setFillColor(0, 0, 0, 0)
    glow.strokeWidth = 3
    glow:setStrokeColor(0.32, 1.0, 0.36, 0.28)

    local panel = display.newRoundedRect(popup, CX, panelY, panelW, panelH, 14)
    panel:setFillColor(0.02, 0.06, 0.16, 0.98)
    panel.strokeWidth = 2
    panel:setStrokeColor(0.30, 0.82, 1.0, 0.82)

    local title
    local okBanner, banner = pcall(display.newImageRect, popup, "assets/sprites/ui/icons/lvelup.png", 176, 58)
    if okBanner and banner then
        banner.x = CX
        banner.y = panelY - panelH * 0.5 + 42
        banner.isHitTestable = false
    else
        title = display.newText({
            parent = popup,
            text = "LEVEL UP",
            x = CX,
            y = panelY - panelH * 0.5 + 34,
            font = ui.FONT_BOLD,
            fontSize = 24,
        })
        title:setFillColor(0.55, 1.0, 0.40)
    end

    local levelText = display.newText({
        parent = popup,
        text = "Lv. " .. tostring(summary.startingLevel) .. "  ->  Lv. " .. tostring(summary.finalLevel),
        x = CX,
        y = panelY - panelH * 0.5 + 88,
        font = ui.FONT_BOLD,
        fontSize = 13,
    })
    levelText:setFillColor(0.88, 0.98, 1.0)

    local statCards = {
        { icon = "atk", label = "ATK", gain = summary.attack or 0, x = CX - 52, y = panelY - 4 },
        { icon = "def", label = "DEF", gain = summary.defense or 0, x = CX + 52, y = panelY - 4 },
        { icon = "spd", label = "SPD", gain = summary.speed or 0, x = CX - 52, y = panelY + 78 },
        { icon = "hp", label = "HP", gain = summary.hp or 0, x = CX + 52, y = panelY + 78 },
    }

    for _, stat in ipairs(statCards) do
        local icon = display.newImageRect(popup, "assets/sprites/ui/icons/" .. stat.icon .. ".png", 24, 24)
        icon.x = stat.x
        icon.y = stat.y - 12
        icon.isHitTestable = false

        local label = display.newText({
            parent = popup,
            text = stat.label,
            x = stat.x,
            y = stat.y + 10,
            font = ui.FONT_BOLD,
            fontSize = 10,
        })
        label:setFillColor(0.72, 0.86, 0.98)

        local gainText = display.newText({
            parent = popup,
            text = "+" .. tostring(stat.gain),
            x = stat.x,
            y = stat.y + 34,
            font = ui.FONT_BOLD,
            fontSize = 17,
        })
        gainText:setFillColor(0.56, 1.0, 0.42)
    end

    local closeY = panelY + panelH * 0.5 - 30
    local closeBtn = display.newRoundedRect(popup, CX, closeY, 124, 36, 8)
    closeBtn:setFillColor(0.08, 0.42, 0.16, 0.97)
    closeBtn.strokeWidth = 1.5
    closeBtn:setStrokeColor(0.22, 0.88, 0.32, 0.90)

    local closeText = display.newText({
        parent = popup,
        text = "AWESOME",
        x = CX,
        y = closeY,
        font = ui.FONT_BOLD,
        fontSize = 13,
    })
    closeText:setFillColor(0.44, 1.0, 0.56)

    local function closePopup()
        return ui.popupClose(popup, dim, {
            beamLeft, beamRight, glow, panel, burst, banner or title, levelText,
            closeBtn, closeText
        }, onClose)
    end

    ui.popupOpen(dim, {
        beamLeft, beamRight, glow, panel, burst, banner or title, levelText,
        closeBtn, closeText
    }, { overlayAlpha = 0.78, startScale = 0.2, time = 170 })
    dim:addEventListener("tap", closePopup)
    closeBtn:addEventListener("tap", closePopup)
end

return M
