local ui = require("utils.ui")

local M = {}
local activePopup = nil
local activeClose = nil

local DEFAULT_ICONS = {
    gold = "assets/sprites/ui/icons/gold.png",
    crystal_green = "assets/sprites/materials/crystal_green.png",
    crystal_blue = "assets/sprites/materials/crystal_blue.png",
    crystal_purple = "assets/sprites/materials/crystal_purple.png",
    crystal_orange = "assets/sprites/materials/crystal_orange.png",
    augment_attack = "assets/sprites/materials/augment_attack.png",
    augment_defense = "assets/sprites/materials/augment_defense.png",
    augment_speed = "assets/sprites/materials/augment_speed.png",
    augment_health = "assets/sprites/materials/augment_health.png",
    jail = "assets/sprites/ui/icons/jail.png",
}

local function iconFor(opts)
    if opts.icon then return opts.icon end
    if opts.key and DEFAULT_ICONS[opts.key] then return DEFAULT_ICONS[opts.key] end
    if opts.kind and DEFAULT_ICONS[opts.kind] then return DEFAULT_ICONS[opts.kind] end
    return DEFAULT_ICONS.gold
end

function M.show(parent, opts)
    opts = opts or {}
    M.closeActive(true)
    local host = display.getCurrentStage()
    local SW = display.actualContentWidth
    local SH = display.actualContentHeight
    local CX = display.contentCenterX
    local CY = display.contentCenterY
    local accent = opts.accent or {0.28, 0.76, 1.0}
    local titleText = tostring(opts.title or "OBTAINED")
    local messageText = tostring(opts.message or "")
    local detailText = opts.detail and tostring(opts.detail) or nil
    local buttonText = tostring(opts.button or "COLLECT")

    local popup = display.newGroup()
    host:insert(popup)
    activePopup = popup

    local dim = display.newRect(popup, CX, CY, SW, SH)
    dim:setFillColor(0, 0, 0, 0.78)
    dim.isHitTestable = true
    dim:addEventListener("tap", function() return true end)
    dim:addEventListener("touch", function() return true end)

    local panelW = math.min(SW - 42, 292)
    local panelH = detailText and 334 or 304
    local glow = display.newRoundedRect(popup, CX, CY, panelW + 8, panelH + 8, 16)
    glow:setFillColor(0, 0, 0, 0)
    glow.strokeWidth = 3
    glow:setStrokeColor(accent[1], accent[2], accent[3], 0.36)

    local panel = display.newRoundedRect(popup, CX, CY, panelW, panelH, 14)
    panel:setFillColor(0.02, 0.06, 0.16, 0.98)
    panel.strokeWidth = 2
    panel:setStrokeColor(0.28, 0.76, 1.0, 0.82)
    panel.isHitTestable = true
    panel:addEventListener("tap", function() return true end)
    panel:addEventListener("touch", function() return true end)

    local title = display.newText({
        parent=popup, text=titleText,
        x=CX, y=CY - panelH * 0.5 + 34,
        width=panelW - 30,
        font=ui.FONT_BOLD, fontSize=17, align="center",
    })
    title:setFillColor(accent[1], accent[2], accent[3])

    local yay = display.newImageRect(popup, "assets/sprites/ui/icons/yay.png", 176, 176)
    yay.x = CX
    yay.y = CY - 48
    yay.alpha = opts.noBurst and 0.18 or 0.92

    local iconPath = iconFor(opts)
    local icon
    if iconPath then
        icon = display.newImageRect(popup, iconPath, 72, 72)
        icon.x = CX
        icon.y = CY - 48
    end

    local message = display.newText({
        parent=popup, text=messageText,
        x=CX, y=CY + 34,
        width=panelW - 32,
        font=ui.FONT_BOLD, fontSize=12, align="center",
    })
    message:setFillColor(0.86, 0.96, 1.0)

    local detail
    if detailText then
        detail = display.newText({
            parent=popup, text=detailText,
            x=CX, y=CY + 68,
            width=panelW - 34,
            font=ui.FONT, fontSize=10, align="center",
        })
        detail:setFillColor(0.62, 0.78, 0.92)
    end

    local panelShield = ui.addPopupShield(popup, CX, CY, panelW, panelH)

    local btnY = CY + panelH * 0.5 - 38
    local okFrame, btn = pcall(display.newImageRect, popup, "assets/sprites/ui/btn_nav.png", 110, 80)
    if okFrame and btn then
        btn.x = CX
        btn.y = btnY
    else
        btn = display.newRoundedRect(popup, CX, btnY, 166, 42, 8)
        btn:setFillColor(0.06, 0.18, 0.45, 0.98)
        btn.strokeWidth = 1.5
        btn:setStrokeColor(0.30, 0.72, 1.0, 0.78)
    end
    local btnLabel = display.newText({
        parent=popup, text=buttonText,
        x=CX, y=btnY,
        font=ui.FONT_BOLD, fontSize=13,
    })
    btnLabel:setFillColor(0.86, 0.96, 1.0)

    local closing = false
    local function close()
        if closing then return true end
        closing = true
        activePopup = nil
        activeClose = nil
        ui.popupClose(popup, dim, { glow, panel, title, yay, icon, message, detail, panelShield, btn, btnLabel }, opts.onClose)
        return true
    end
    activeClose = close

    if btn.toFront then btn:toFront() end
    if btnLabel.toFront then btnLabel:toFront() end

    btn:addEventListener("touch", function(event)
        if event.phase == "began" then
            display.getCurrentStage():setFocus(btn)
            btn._hasFocus = true
            pcall(function() btn.fill = { type="image", filename="assets/sprites/ui/btn_nav_pressed.png" } end)
        elseif btn._hasFocus and (event.phase == "ended" or event.phase == "cancelled") then
            display.getCurrentStage():setFocus(nil)
            btn._hasFocus = false
            pcall(function() btn.fill = { type="image", filename="assets/sprites/ui/btn_nav.png" } end)
            if event.phase == "ended" then close() end
        end
        return true
    end)

    ui.popupOpen(dim, { glow, panel, title, yay, icon, message, detail, panelShield, btn, btnLabel }, { overlayAlpha=0.78, startScale=0.2, time=170 })
    return popup
end

function M.closeActive(immediate)
    if activeClose and not immediate then
        activeClose()
        return
    end
    if activePopup and activePopup.removeSelf then
        activePopup:removeSelf()
    end
    activePopup = nil
    activeClose = nil
end

return M
