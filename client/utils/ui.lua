local ui = {}

ui.FONT = "assets/fonts/pixel.ttf"
ui.FONT_BOLD = "assets/fonts/pixelBold.ttf"

function ui.popupOpen(overlay, targets, opts)
    opts = opts or {}
    local overlayAlpha = opts.overlayAlpha or (overlay and overlay.alpha) or 0.78
    local startScale = opts.startScale or 0.3
    local time = opts.time or 180

    if overlay and overlay.removeSelf then
        overlay.alpha = 0
        transition.to(overlay, { alpha = overlayAlpha, time = time })
    end

    for _, obj in ipairs(targets or {}) do
        if obj and obj.removeSelf then
            obj._popupTargetAlpha = obj.alpha
            obj.alpha = 0
            obj.xScale = startScale
            obj.yScale = startScale
            transition.to(obj, {
                alpha = obj._popupTargetAlpha,
                xScale = 1.0,
                yScale = 1.0,
                time = time + (opts.scaleExtraTime or 40),
                transition = opts.transition or easing.outBack,
            })
        end
    end
end

function ui.popupClose(group, overlay, targets, onClose, opts)
    opts = opts or {}
    local time = opts.time or 140
    local endScale = opts.endScale or 0.05
    local closed = false

    local function finish()
        if closed then return end
        closed = true
        if group and group.removeSelf then group:removeSelf() end
        if onClose then onClose() end
    end

    if overlay and overlay.removeSelf then
        transition.to(overlay, { alpha = 0, time = math.max(80, time - 20) })
    end

    for _, obj in ipairs(targets or {}) do
        if obj and obj.removeSelf then
            transition.to(obj, {
                alpha = 0,
                xScale = endScale,
                yScale = endScale,
                time = time,
                transition = opts.transition or easing.inBack,
            })
        end
    end

    timer.performWithDelay(time + 20, finish)
    return true
end

function ui.addPopupShield(parent, x, y, width, height)
    local shield = display.newRect(parent, x, y, width, height)
    shield:setFillColor(1, 1, 1, 0.01)
    shield.isHitTestable = true
    shield:addEventListener("tap", function()
        return true
    end)
    shield:addEventListener("touch", function()
        return true
    end)
    return shield
end

return ui
