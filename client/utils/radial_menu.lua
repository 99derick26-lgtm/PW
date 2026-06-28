local M = {}

local composer = require("composer")

-------------------------------------------------
-- CONFIG
-------------------------------------------------
local INNER_SLOT_COUNT = 4
local OUTER_SLOT_COUNT = 5
local INNER_WEDGE = 180 / INNER_SLOT_COUNT
local OUTER_WEDGE = 180 / OUTER_SLOT_COUNT

local ARC_INNER   = 48
local ARC_MID     = 108
local ARC_OUTER   = 168

local ICON_INNER  = (ARC_INNER + ARC_MID) * 0.5
local ICON_OUTER  = (ARC_MID  + ARC_OUTER) * 0.5

local ICON_SIZE     = 36
local ICON_SIZE_SEL = 46
local LABEL_SZ      = 9
local LABEL_SZ_SEL  = 11
local BTN_RADIUS    = 34
local ARC_SEGMENTS  = 40

-- colors
local C_ARC_FILL     = { 0.02, 0.06, 0.18, 0.97 }
local C_ARC_STROKE   = { 0.15, 0.5,  0.9,  0.7  }
local C_MID_RING     = { 0.2,  0.55, 1.0,  0.4  }
local C_DIV          = { 0.2,  0.55, 1.0,  0.45 }
local C_SEG_IDLE     = { 0.0,  0.0,  0.0,  0.0  }
local C_SEG_SEL      = { 0.1,  0.45, 1.0,  0.55 }
local C_SEG_ACTIVE   = { 0.05, 0.35, 0.9,  0.45 }
local C_LABEL_IDLE   = { 0.5,  0.8,  1.0        }
local C_LABEL_SEL    = { 1.0,  1.0,  1.0        }
local C_LABEL_ACTIVE = { 0.4,  1.0,  0.8        }
local C_BTN_IDLE     = { 0.04, 0.14, 0.38, 1.0  }
local C_BTN_OPEN     = { 0.1,  0.4,  1.0,  1.0  }
local C_BTN_STROKE   = { 0.3,  0.7,  1.0,  0.85 }

-------------------------------------------------
-- MODULE STATE
-------------------------------------------------
local menuGroup
local overlay
local touchBlock
local buttonGroup
local button
local buttonIcon
local buttonGlow
local buttonRing
local debugText
local pulseTimer
local navTimer
local innerSlots  = {}
local outerSlots  = {}
local isOpen      = false
local activeRing  = nil
local activeIndex = nil
local originX, originY
local currentActiveScene = nil
local DEBUG_ENABLED = false

-------------------------------------------------
-- UTIL
-------------------------------------------------
local function degToRad(d) return d * math.pi / 180 end

local function iconPath(iconName)
    if iconName == "squad" or iconName == "tournament" then
        return "assets/sprites/ui/icons/tabs/" .. iconName .. ".png"
    end
    return "assets/sprites/ui/icons/" .. iconName .. ".png"
end

local function updateDebug(message)
    if not DEBUG_ENABLED or not debugText then return end
    debugText.text = message or ""
end

-------------------------------------------------
-- BUILD WEDGE VERTS (donut slice, relative to 0,0)
-------------------------------------------------
local function buildWedgeVerts(startDeg, endDeg, innerR, outerR, segs)
    local op, ip = {}, {}
    for i = 0, segs do
        local a = degToRad(startDeg + i * (endDeg - startDeg) / segs)
        op[#op+1] =  outerR * math.cos(a)
        op[#op+1] = -outerR * math.sin(a)
    end
    for i = segs, 0, -1 do
        local a = degToRad(startDeg + i * (endDeg - startDeg) / segs)
        ip[#ip+1] =  innerR * math.cos(a)
        ip[#ip+1] = -innerR * math.sin(a)
    end
    local v = {}
    for j = 1, #op do v[#v+1] = op[j] end
    for j = 1, #ip do v[#v+1] = ip[j] end
    return v
end

-------------------------------------------------
-- DRAW ARC BAND (donut ring, relative coords)
-------------------------------------------------
local function drawBand(group, cx, cy, innerR, outerR, color, strokeColor)
    local v = buildWedgeVerts(0, 180, innerR, outerR, ARC_SEGMENTS)
    local p = display.newPolygon(group, cx, cy, v)
    p:setFillColor(unpack(color))
    p.strokeWidth = 1
    p:setStrokeColor(unpack(strokeColor or C_ARC_STROKE))
    return p
end

-------------------------------------------------
-- DRAW SPOKE
-------------------------------------------------
local function drawSpoke(group, cx, cy, angleDeg, innerR, outerR)
    local rad = degToRad(angleDeg)
    local x1  = cx + innerR * math.cos(rad)
    local y1  = cy - innerR * math.sin(rad)
    local x2  = cx + outerR * math.cos(rad)
    local y2  = cy - outerR * math.sin(rad)
    local l   = display.newLine(group, x1, y1, x2, y2)
    l:setStrokeColor(unpack(C_DIV))
    l.strokeWidth = 1
end

-------------------------------------------------
-- DRAW MID RING
-------------------------------------------------
local function drawMidRing(group, cx, cy)
    local pts = {}
    for i = 0, ARC_SEGMENTS do
        local a = degToRad(180 - i * (180 / ARC_SEGMENTS))
        pts[#pts+1] = cx + ARC_MID * math.cos(a)
        pts[#pts+1] = cy - ARC_MID * math.sin(a)
    end
    for i = 1, #pts - 2, 2 do
        local l = display.newLine(group, pts[i], pts[i+1], pts[i+2], pts[i+3])
        l:setStrokeColor(unpack(C_MID_RING))
        l.strokeWidth = 1
    end
end

-------------------------------------------------
-- DRAW OUTER ARC LINE (semicircle border, no bottom)
-------------------------------------------------
local function drawArcLine(group, cx, cy, r, strokeColor, strokeW)
    local pts = {}
    for i = 0, ARC_SEGMENTS do
        local a = degToRad(i * (180 / ARC_SEGMENTS))
        pts[#pts+1] = cx + r * math.cos(a)
        pts[#pts+1] = cy - r * math.sin(a)
    end
    for i = 1, #pts - 2, 2 do
        local l = display.newLine(group, pts[i], pts[i+1], pts[i+2], pts[i+3])
        l:setStrokeColor(unpack(strokeColor))
        l.strokeWidth = strokeW
    end
end

-------------------------------------------------
-- HIGHLIGHT HELPERS
-------------------------------------------------
local function clearSlot(s)
    if not s or s.isSoon then return end
    if s.wedge then
        s.wedge:setFillColor(unpack(s.isActive and C_SEG_ACTIVE or C_SEG_IDLE))
    end
    if s.icon  then s.icon.xScale = 1; s.icon.yScale = 1 end
    if s.label then
        s.label.isVisible = s.isActive
        s.label:setFillColor(unpack(s.isActive and C_LABEL_ACTIVE or C_LABEL_IDLE))
        s.label.size = s.isActive and (LABEL_SZ + 1) or LABEL_SZ
    end
end

local function highlightSlotObj(s)
    if not s or s.isSoon then return end
    if s.wedge then s.wedge:setFillColor(unpack(C_SEG_SEL)) end
    if s.icon  then
        local sc = ICON_SIZE_SEL / ICON_SIZE
        s.icon.xScale = sc; s.icon.yScale = sc
    end
    if s.label then
        s.label.isVisible = true
        s.label:setFillColor(unpack(C_LABEL_SEL))
        s.label.size = LABEL_SZ_SEL
    end
end

local function clearHighlight()
    for i = 1, #innerSlots do
        clearSlot(innerSlots[i])
    end
    for i = 1, #outerSlots do
        clearSlot(outerSlots[i])
    end
end

-------------------------------------------------
-- PULSE ANIMATION (button ring only)
-------------------------------------------------
local function startPulse()
    if pulseTimer then timer.cancel(pulseTimer); pulseTimer = nil end
    if not buttonRing then return end
    local function doPulse()
        if not buttonRing or not buttonRing.removeSelf then return end
        transition.to(buttonRing, {
            alpha = 0.15, xScale = 1.18, yScale = 1.18,
            time  = 900, transition = easing.outQuad,
            onComplete = function()
                if not buttonRing or not buttonRing.removeSelf then return end
                transition.to(buttonRing, {
                    alpha = 0.7, xScale = 1.0, yScale = 1.0,
                    time  = 700, transition = easing.inQuad,
                    onComplete = doPulse
                })
            end
        })
    end
    doPulse()
end

local function stopPulse()
    if pulseTimer then timer.cancel(pulseTimer); pulseTimer = nil end
    if buttonRing then
        transition.cancel(buttonRing)
        buttonRing.alpha  = 0.8
        buttonRing.xScale = 1.0
        buttonRing.yScale = 1.0
    end
end

-------------------------------------------------
-- OPEN / CLOSE
-------------------------------------------------
local function closeMenu(keepInputBlock)
    if not isOpen then return end
    clearHighlight()
    activeRing  = nil
    activeIndex = nil
    updateDebug("closed")
    transition.to(menuGroup, { alpha=0, time=130 })
    if not keepInputBlock then
        overlay.isVisible        = false
        overlay.isHitTestable    = false
        touchBlock.isVisible     = false
        touchBlock.isHitTestable = false
    end
    isOpen = false
    button:setFillColor(unpack(C_BTN_IDLE))
    if buttonIcon then buttonIcon.isVisible = true  end
    if buttonGlow then buttonGlow.alpha      = 0.6   end
    if buttonRing then startPulse() end
end

local function bringMenuToFront()
    if overlay and overlay.toFront then overlay:toFront() end
    if touchBlock and touchBlock.toFront then touchBlock:toFront() end
    if menuGroup and menuGroup.toFront then menuGroup:toFront() end
    if buttonGroup and buttonGroup.toFront then buttonGroup:toFront() end
end

local function openMenu()
    if isOpen then return end
    bringMenuToFront()
    button:setFillColor(unpack(C_BTN_OPEN))
    if buttonIcon then buttonIcon.isVisible = false end
    if buttonGlow then buttonGlow.alpha      = 1.0   end
    if buttonRing then stopPulse() end
    menuGroup.alpha = 0
    transition.to(menuGroup, { alpha=1, time=150 })
    overlay.isVisible        = true
    overlay.isHitTestable    = true
    touchBlock.isVisible     = true
    touchBlock.isHitTestable = true
    isOpen = true
    updateDebug("open: hold and drag")
end

-------------------------------------------------
-- ANGLE → SLOT INDEX
-------------------------------------------------
local function angleToIndex(angleDeg, slotCount)
    local wedge = 180 / slotCount
    local idx = math.floor((180 - angleDeg) / wedge) + 1
    if idx < 1 then idx = 1 end
    if idx > slotCount then idx = slotCount end
    return idx
end

local function updateSelection(touchX, touchY)
    if not isOpen then return end
    local dx = touchX - originX
    local dy = touchY - originY
    if dy >= 0 then
        clearHighlight(); activeRing = nil; activeIndex = nil
        updateDebug("below menu")
        return
    end
    local dist     = math.sqrt(dx*dx + dy*dy)
    local angleDeg = math.deg(math.atan2(-dy, dx))
    if angleDeg < 0   then angleDeg = 0   end
    if angleDeg > 180 then angleDeg = 180 end

    local newRing  = dist < ARC_MID and "inner" or "outer"
    local newIndex = newRing == "inner"
        and angleToIndex(angleDeg, INNER_SLOT_COUNT)
        or angleToIndex(angleDeg, OUTER_SLOT_COUNT)

    if newRing == activeRing and newIndex == activeIndex then return end
    clearHighlight()
    activeRing  = newRing
    activeIndex = newIndex

    local slot
    if newRing == "inner" then
        slot = innerSlots[newIndex]
        highlightSlotObj(slot)
    else
        slot = outerSlots[newIndex]
        if slot and not slot.isSoon then highlightSlotObj(slot) end
    end

    local label = "-"
    local scene = "-"
    if slot then
        if slot.label and slot.label.text and slot.label.text ~= "" then
            label = slot.label.text
        end
        if slot.scene then
            scene = slot.scene
        elseif slot.isSoon then
            scene = "soon"
        end
    end
    updateDebug(string.format(
        "ring=%s idx=%d label=%s scene=%s angle=%.1f dist=%.0f",
        newRing, newIndex, label, scene, angleDeg, dist
    ))
end

-------------------------------------------------
-- BUILD SLOT
-------------------------------------------------
local function buildSlot(group, cx, cy, slotIndex, slotCount, iconR, innerR, outerR, data, isOuter)
    local wedge = 180 / slotCount
    local startDeg = (slotCount - slotIndex) * wedge
    local endDeg   = startDeg + wedge
    local midDeg   = (startDeg + endDeg) * 0.5
    local rad      = degToRad(midDeg)
    local ix       = cx + iconR * math.cos(rad)
    local iy       = cy - iconR * math.sin(rad)

    local isSoon   = (not data) or (data.icon == "soon") or
                     (not data.scene and not data.icon)
    local isActive = data and data.scene and
                     (data.scene == ("scenes." .. (currentActiveScene or "")))

    -- outer soon slots: just show "..." marker, no wedge/label/nav
    if isOuter and isSoon then
        local dot = display.newText({
            parent=group, text="...",
            x=ix, y=iy,
            font=native.systemFontBold, fontSize=14
        })
        dot:setFillColor(0.3, 0.4, 0.55, 0.6)
        return { isSoon=true, wedge=nil, icon=nil, label=nil, scene=nil }
    end

    -- wedge highlight background
    local wv    = buildWedgeVerts(startDeg, endDeg, innerR + 1, outerR - 1, 10)
    local wedge = display.newPolygon(group, cx, cy, wv)
    wedge:setFillColor(unpack(isActive and C_SEG_ACTIVE or C_SEG_IDLE))
    wedge.strokeWidth = 0

    -- icon
    local icon
    if data and data.icon then
        local ok, img = pcall(function()
            return display.newImageRect(
                group,
                iconPath(data.icon),
                ICON_SIZE, ICON_SIZE
            )
        end)
        if ok and img then
            icon = img
            icon.x = ix; icon.y = iy
        else
            icon = display.newCircle(group, ix, iy, 6)
            icon:setFillColor(0.3, 0.6, 1.0, 0.7)
        end
    end

    -- active scene: small green dot below icon
    if isActive and icon then
        local dot = display.newCircle(group, ix, iy + ICON_SIZE * 0.65, 3)
        dot:setFillColor(0.4, 1.0, 0.7)
    end

    -- label (hidden until hover; active scene label always visible)
    local labelR = ARC_OUTER + 14
    local lx = cx + labelR * math.cos(rad)
    local ly = cy - labelR * math.sin(rad)
    local labelTxt = (data and data.label) and string.upper(data.label) or ""
    local label = display.newText({
        parent=group, text=labelTxt,
        x=lx, y=ly,
        font=native.systemFontBold,
        fontSize = isActive and (LABEL_SZ + 1) or LABEL_SZ,
        align="center"
    })
    label:setFillColor(unpack(isActive and C_LABEL_ACTIVE or C_LABEL_IDLE))
    label.isVisible = isActive

    return {
        wedge    = wedge,
        icon     = icon,
        label    = label,
        labelTxt = data and data.label or nil,
        scene    = data and data.scene or nil,
        isSoon   = isSoon,
        isActive = isActive,
    }
end

-------------------------------------------------
-- BUILD MENU
-------------------------------------------------
local function buildMenu(sceneGroup, innerData, outerData, activeScene)
    currentActiveScene = activeScene

    local screenW = display.actualContentWidth
    local screenH = display.actualContentHeight
    local centerX = display.contentCenterX

    originX = centerX
    originY = screenH - 100

    -- 1) TOUCH BLOCKER
    touchBlock = display.newRect(
        sceneGroup, display.contentCenterX, display.contentCenterY, screenW, screenH
    )
    touchBlock:setFillColor(0, 0, 0, 0)
    touchBlock.isVisible     = false
    touchBlock.isHitTestable = false
    touchBlock:addEventListener("tap",   function() closeMenu(); return true end)
    touchBlock:addEventListener("touch", function() return true end)

    -- 2) DIM OVERLAY
    overlay = display.newRect(
        sceneGroup, display.contentCenterX, display.contentCenterY, screenW, screenH
    )
    overlay:setFillColor(0, 0, 0, 0.75)
    overlay.isVisible     = false
    overlay.isHitTestable = false
    overlay:addEventListener("tap", function() closeMenu(); return true end)
    overlay:addEventListener("touch", function() return true end)

    -- 3) MENU GROUP
    menuGroup = display.newGroup()
    sceneGroup:insert(menuGroup)
    menuGroup.alpha = 0

    -- solid semicircle background: vertices are relative to polygon center (cx,cy)
    -- so we pass originX,originY as center and use relative coords (offset from that)
    local bgVerts = {}
    for i = 0, ARC_SEGMENTS do
        local a = degToRad(i * 180 / ARC_SEGMENTS)
        bgVerts[#bgVerts+1] =  (ARC_OUTER + 4) * math.cos(a)
        bgVerts[#bgVerts+1] = -(ARC_OUTER + 4) * math.sin(a)
    end
    -- close fan back to center (relative 0,0)
    bgVerts[#bgVerts+1] = 0
    bgVerts[#bgVerts+1] = 0
    local bgPoly = display.newPolygon(menuGroup, originX, originY, bgVerts)
    bgPoly.y = bgPoly.y + (ARC_OUTER - 250)    -- polygon is auto-centered on bounding box; shift down half-height to realign
    bgPoly:setFillColor(unpack(C_ARC_FILL))
    bgPoly.strokeWidth = 0

    -- rings and dividers drawn on top of background
  drawMidRing(menuGroup, originX, originY)
    drawArcLine(menuGroup, originX, originY, ARC_OUTER + 3, {0.2, 0.6, 1.0, 0.85}, 2)
    drawArcLine(menuGroup, originX, originY, ARC_INNER - 3, {0.2, 0.6, 1.0, 0.5},  1.5)
    for i = 0, OUTER_SLOT_COUNT do
        drawSpoke(menuGroup, originX, originY, i * OUTER_WEDGE, ARC_INNER, ARC_OUTER)
    end

    local normalizedOuterData = {}
    if outerData and #outerData == 4 then
        normalizedOuterData = {
            outerData[1],
            outerData[2],
            { label = "Leaderboard", icon = "leaderboard", scene = "scenes.leaderboard" },
            outerData[3],
            outerData[4],
        }
    else
        normalizedOuterData = outerData or {}
    end

    innerSlots = {}
    for i = 1, INNER_SLOT_COUNT do
        innerSlots[i] = buildSlot(
            menuGroup, originX, originY,
            i, INNER_SLOT_COUNT, ICON_INNER, ARC_INNER, ARC_MID,
            innerData[i], false
        )
    end

    outerSlots = {}
    for i = 1, OUTER_SLOT_COUNT do
        outerSlots[i] = buildSlot(
            menuGroup, originX, originY,
            i, OUTER_SLOT_COUNT, ICON_OUTER, ARC_MID, ARC_OUTER,
            normalizedOuterData[i], true
        )
    end

    -- 4) BUTTON GROUP (always on top)
    buttonGroup = display.newGroup()
    sceneGroup:insert(buttonGroup)

    if DEBUG_ENABLED then
        debugText = display.newText({
            parent = buttonGroup,
            text = "radial debug",
            x = originX,
            y = originY - (ARC_OUTER + 26),
            width = screenW - 24,
            font = native.systemFontBold,
            fontSize = 12,
            align = "center"
        })
        debugText:setFillColor(1.0, 0.95, 0.55)
        updateDebug("ready")
    end

    -- pulsing ring around button only (small, BTN_RADIUS based)
    buttonRing = display.newCircle(buttonGroup, originX, originY, BTN_RADIUS + 4)
    buttonRing:setFillColor(0, 0, 0, 0)
    buttonRing.strokeWidth = 1.5
    buttonRing:setStrokeColor(0.2, 0.6, 1.0, 0.7)
    buttonRing.alpha = 0.7

    buttonGlow = display.newCircle(buttonGroup, originX, originY, BTN_RADIUS + 6)
    buttonGlow:setFillColor(0.05, 0.25, 0.8, 0.30)
    buttonGlow.strokeWidth = 0
    buttonGlow.alpha = 0.6

    button = display.newCircle(buttonGroup, originX, originY, BTN_RADIUS)
    button:setFillColor(unpack(C_BTN_IDLE))
    button.strokeWidth = 2
    button:setStrokeColor(unpack(C_BTN_STROKE))

    buttonIcon = nil
    if activeScene then
        local ok, img = pcall(function()
            return display.newImageRect(
                buttonGroup,
                iconPath(activeScene),
                BTN_RADIUS * 1.2, BTN_RADIUS * 1.2
            )
        end)
        if ok and img then
            img.x = originX; img.y = originY
            img.isHitTestable = false
            buttonIcon = img
        end
    end

    startPulse()

    sceneGroup:insert(touchBlock)
    sceneGroup:insert(overlay)
    sceneGroup:insert(menuGroup)
    sceneGroup:insert(buttonGroup)

    -- TOUCH HANDLER (hold+drag only — no tap toggle)
    button:addEventListener("touch", function(e)
        if e.phase == "began" then
            display.getCurrentStage():setFocus(button)
            openMenu()

        elseif e.phase == "moved" then
            updateSelection(e.x, e.y)

        elseif e.phase == "ended" or e.phase == "cancelled" then
            display.getCurrentStage():setFocus(nil)
            local dest = nil
            local pickedLabel = "-"
            if activeRing == "inner" and activeIndex then
                local s = innerSlots[activeIndex]
                if s and s.scene then dest = s.scene end
                if s and s.labelTxt then pickedLabel = s.labelTxt end
            elseif activeRing == "outer" and activeIndex then
                local s = outerSlots[activeIndex]
                if s and s.scene and not s.isSoon then dest = s.scene end
                if s and s.labelTxt then pickedLabel = s.labelTxt end
            end
            updateDebug("release: " .. pickedLabel .. " -> " .. (dest or "nil"))
            if dest then
                closeMenu(true)
                navTimer = timer.performWithDelay(1, function()
                    navTimer = nil
                    composer.gotoScene(dest, { effect="crossFade", time=180 })
                end)
            else
                closeMenu(false)
            end
        end
        return true
    end)
end

-------------------------------------------------
-- DESTROY
-------------------------------------------------
function M.destroy()
    isOpen      = false
    activeRing  = nil
    activeIndex = nil

    if pulseTimer then timer.cancel(pulseTimer); pulseTimer = nil end
    if navTimer then timer.cancel(navTimer); navTimer = nil end
    if buttonRing then transition.cancel(buttonRing) end

    local function rm(o) if o and o.removeSelf then o:removeSelf() end end
    rm(touchBlock); rm(overlay); rm(menuGroup); rm(buttonGroup)

    touchBlock  = nil; overlay     = nil
    menuGroup   = nil; buttonGroup = nil
    button      = nil; buttonIcon  = nil
    buttonGlow  = nil; buttonRing  = nil
    debugText   = nil
    navTimer    = nil
    innerSlots  = {}; outerSlots   = {}
    currentActiveScene = nil
end

-------------------------------------------------
-- M.show()
-------------------------------------------------
function M.show(sceneGroup, options)
    M.destroy()
    options = options or {}
    buildMenu(
        sceneGroup,
        options.inner or {},
        options.outer or {},
        options.activeScene or nil
    )
end

M.new = M.show

return M
