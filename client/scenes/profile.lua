local composer = require("composer")
local scene     = composer.newScene()

local save = require("utils.save")
local api  = require("utils.api")
local ui   = require("utils.ui")
local tasksUtil = require("utils.tasks")

local CX = display.contentCenterX
local CY = display.contentCenterY
local SW = display.actualContentWidth
local SH = display.actualContentHeight

local TIMERS = {}
local activeNameField = nil
local activeNameOverlay = nil

local function closeActiveNameEdit()
    native.setKeyboardFocus(nil)
    if activeNameField and activeNameField.removeSelf then
        activeNameField:removeSelf()
    end
    activeNameField = nil

    if activeNameOverlay and activeNameOverlay.removeSelf then
        activeNameOverlay:removeSelf()
    end
    activeNameOverlay = nil
end

-------------------------------------------------
-- HELPERS
-------------------------------------------------
local function flicker(obj, lo, hi, ms)
    local t = timer.performWithDelay(ms, function()
        if obj and obj.removeSelf then
            obj.alpha = lo + math.random() * (hi - lo)
        end
    end, 0)
    table.insert(TIMERS, t)
end

local function mkBtn(sg, x, y, w, h, label, r, g, b, action)
    local glow = display.newRoundedRect(sg, x, y, w+6, h+4, 10)
    glow:setFillColor(r, g, b, 0.15)
    glow.isHitTestable = false
    flicker(glow, 0.4, 1.0, 180)

    local bg = display.newRoundedRect(sg, x, y, w, h, 8)
    bg:setFillColor(r*0.12, g*0.12, b*0.12)
    bg.strokeWidth = 1.5
    bg:setStrokeColor(r, g, b, 0.85)

    local txt = display.newText({
        parent=sg, text=label,
        x=x, y=y, font=ui.FONT_BOLD, fontSize=12, align="center"
    })
    txt:setFillColor(r, g, b)
    txt.isHitTestable = false

    local locked = false
    bg:addEventListener("tap", function()
        if locked then return true end
        locked = true
        bg:setFillColor(r*0.3, g*0.3, b*0.3)
        txt:setFillColor(1,1,1)
        timer.performWithDelay(150, function()
            bg:setFillColor(r*0.12, g*0.12, b*0.12)
            txt:setFillColor(r, g, b)
            locked = false
            if action then action() end
        end)
        return true
    end)
    return bg, txt
end

local function showNameEditOverlay(sg, currentName, onConfirm)
    closeActiveNameEdit()

    local overlay = display.newGroup()
    sg:insert(overlay)
    activeNameOverlay = overlay

    local dimmer = display.newRect(overlay, CX, CY, SW, SH)
    dimmer:setFillColor(0,0,0,0.75)

    local panel = display.newRoundedRect(overlay, CX, CY, SW*0.82, 180, 14)
    panel:setFillColor(0.04, 0.10, 0.22)
    panel.strokeWidth = 1.5
    panel:setStrokeColor(0.2, 0.6, 1, 0.8)

    display.newText({
        parent=overlay, text="RENAME PROFILE",
        x=CX, y=CY-62, font=ui.FONT_BOLD, fontSize=13, align="center"
    }):setFillColor(0.4, 0.9, 1)

    local fieldBg = display.newRoundedRect(overlay, CX, CY-18, SW*0.68, 38, 8)
    fieldBg:setFillColor(0.06, 0.14, 0.30)
    fieldBg.strokeWidth = 1
    fieldBg:setStrokeColor(0.2, 0.6, 1, 0.6)

    local nameField = native.newTextField(CX, CY-18, SW*0.64, 34)
    nameField.text        = currentName or ""
    nameField.font        = native.newFont(ui.FONT_BOLD, 13)
    nameField.hasBackground = false
    nameField:setTextColor(0.9, 0.95, 1)
    activeNameField = nameField
    nameField._baseY = nameField.y
    overlay._baseY = overlay.y

    local function moveEditor(raised)
        local yOffset = raised and -220 or 0
        if overlay and overlay.removeSelf then
            transition.to(overlay, { y = overlay._baseY + yOffset, time = 140 })
        end
        if nameField and nameField.removeSelf then
            transition.to(nameField, { y = nameField._baseY + yOffset, time = 140 })
        end
    end

    nameField:addEventListener("userInput", function(event)
        if event.phase == "began" then
            moveEditor(true)
        elseif event.phase == "submitted" then
            moveEditor(false)
        end
        return false
    end)

    local function close()
        moveEditor(false)
        closeActiveNameEdit()
    end

    -- CONFIRM
    local confirmBg = display.newRoundedRect(overlay, CX+46, CY+42, 110, 34, 8)
    confirmBg:setFillColor(0.04, 0.22, 0.60)
    confirmBg.strokeWidth = 1
    confirmBg:setStrokeColor(0.2, 0.7, 1, 0.8)
    display.newText({
        parent=overlay, text="SAVE",
        x=CX+46, y=CY+42, font=ui.FONT_BOLD, fontSize=11
    }):setFillColor(0.4, 0.9, 1)

    confirmBg:addEventListener("tap", function()
        local name = (nameField.text or ""):match("^%s*(.-)%s*$")
        if #name == 0 then name = currentName end
        close()
        if onConfirm then onConfirm(name) end
        return true
    end)

    -- CANCEL
    local cancelBg = display.newRoundedRect(overlay, CX-46, CY+42, 110, 34, 8)
    cancelBg:setFillColor(0.14, 0.05, 0.05)
    cancelBg.strokeWidth = 1
    cancelBg:setStrokeColor(1, 0.3, 0.3, 0.5)
    display.newText({
        parent=overlay, text="CANCEL",
        x=CX-46, y=CY+42, font=ui.FONT_BOLD, fontSize=11
    }):setFillColor(1, 0.4, 0.4)

    cancelBg:addEventListener("tap", function()
        close(); return true
    end)
end

local function showConfirmOverlay(sg, message, onConfirm)
    local overlay = display.newGroup()
    sg:insert(overlay)

    local dimmer = display.newRect(overlay, CX, CY, SW, SH)
    dimmer:setFillColor(0,0,0,0.78)

    local panel = display.newRoundedRect(overlay, CX, CY, SW*0.80, 160, 14)
    panel:setFillColor(0.08, 0.04, 0.04)
    panel.strokeWidth = 1.5
    panel:setStrokeColor(1, 0.2, 0.2, 0.7)

    display.newText({
        parent=overlay, text=message,
        x=CX, y=CY-38, width=SW*0.70,
        font=ui.FONT_BOLD, fontSize=12, align="center"
    }):setFillColor(1, 0.5, 0.5)

    local confirmBg = display.newRoundedRect(overlay, CX+46, CY+30, 110, 34, 8)
    confirmBg:setFillColor(0.35, 0.04, 0.04)
    confirmBg.strokeWidth = 1
    confirmBg:setStrokeColor(1, 0.2, 0.2, 0.8)
    display.newText({
        parent=overlay, text="DELETE",
        x=CX+46, y=CY+30, font=ui.FONT_BOLD, fontSize=11
    }):setFillColor(1, 0.3, 0.3)

    local function close()
        if overlay and overlay.removeSelf then overlay:removeSelf() end
    end

    confirmBg:addEventListener("tap", function()
        close(); if onConfirm then onConfirm() end; return true
    end)

    local cancelBg = display.newRoundedRect(overlay, CX-46, CY+30, 110, 34, 8)
    cancelBg:setFillColor(0.04, 0.10, 0.22)
    cancelBg.strokeWidth = 1
    cancelBg:setStrokeColor(0.2, 0.5, 1, 0.5)
    display.newText({
        parent=overlay, text="CANCEL",
        x=CX-46, y=CY+30, font=ui.FONT_BOLD, fontSize=11
    }):setFillColor(0.5, 0.7, 1)

    cancelBg:addEventListener("tap", function()
        close(); return true
    end)
end

-------------------------------------------------
-- SCENE CREATE
-------------------------------------------------
function scene:create(event)
    local sg     = self.view
    local player = save.load()

    local playerSkin = (player.appearance and player.appearance.skinId)
        or "street_brawler"

    --------------------------------------------------
    -- BACKGROUND — full dark + grid tint
    --------------------------------------------------
    local bg = display.newRect(sg, CX, CY, SW, SH)
    bg:setFillColor(0.02, 0.03, 0.08)

    -- try to show bg_home_grid behind everything
    local ok, bgImg = pcall(display.newImage, "assets/sprites/ui/bg_home_grid.png")
    if ok and bgImg then
        local sx = SW / bgImg.width
        local sy = SH / bgImg.height
        bgImg:scale(math.max(sx,sy)*1.1, math.max(sx,sy)*1.1)
        bgImg.x = CX; bgImg.y = CY
        bgImg.alpha = 0.4
        bgImg.isHitTestable = false
        sg:insert(bgImg)
    end

    -- scanlines
    for i = 1, 20 do
        local l = display.newRect(sg, CX, i*(SH/20), SW, 1)
        l:setFillColor(0.05, 0.15, 0.4, 0.05)
        l.isHitTestable = false
    end

    --------------------------------------------------
    -- CHARACTER ART — large, bottom-anchored
    --------------------------------------------------
    local charOk, charSprite = pcall(display.newImageRect,
        sg,
        "assets/sprites/characters/" .. playerSkin .. "/battle.png",
        180, 300)
    if charOk and charSprite then
        charSprite.x = CX + 60
        charSprite.y = SH * 0.62
        charSprite.alpha = 0.92
    end

    -- character glow behind sprite
    local charGlow = display.newCircle(sg, CX + 60, SH * 0.68, 110)
    charGlow:setFillColor(0.05, 0.2, 0.7, 0.18)
    charGlow.strokeWidth = 0
    flicker(charGlow, 0.6, 1.0, 800)

    -- re-insert sprite on top of glow
    if charOk and charSprite then sg:insert(charSprite) end

    -- ground line
    local ground = display.newRect(sg, CX, SH*0.76, SW, 1)
    ground:setFillColor(0.2, 0.5, 1, 0.2)

    --------------------------------------------------
    -- HEADER
    --------------------------------------------------
    local hdr = display.newRect(sg, CX, 32, SW, 56)
    hdr:setFillColor(0.02, 0.05, 0.16, 0.97)
    hdr.strokeWidth = 1
    hdr:setStrokeColor(0.2, 0.5, 1, 0.35)

    local backBtn = display.newText({
        parent=sg, text="< BACK",
        x=52, y=32, font=ui.FONT_BOLD, fontSize=11
    })
    backBtn:setFillColor(0.3, 0.7, 1)
    backBtn:addEventListener("tap", function()
        composer.gotoScene("scenes.home", { effect="slideRight", time=220 })
        return true
    end)

    display.newText({
        parent=sg, text="PROFILE",
        x=CX, y=32, font=ui.FONT_BOLD, fontSize=18, align="center"
    }):setFillColor(0.25, 0.75, 1.0)

    --------------------------------------------------
    -- PROFILE CARD — top left area
    --------------------------------------------------
    local cardX = CX - SW*0.08
    local cardY = SH * 0.20

    -- card glow
    local cardGlow = display.newRoundedRect(sg, cardX, cardY, SW*0.78, 110, 14)
    cardGlow:setFillColor(0.04, 0.15, 0.45, 0.20)
    cardGlow.strokeWidth = 0
    cardGlow.isHitTestable = false
    flicker(cardGlow, 0.7, 1.0, 200)

    -- card panel
    local card = display.newRoundedRect(sg, cardX, cardY, SW*0.76, 108, 12)
    card:setFillColor(0.04, 0.10, 0.24, 0.95)
    card.strokeWidth = 1.5
    card:setStrokeColor(0.2, 0.55, 1.0, 0.75)

    -- decorative top bar on card
    local cardBar = display.newRoundedRect(sg, cardX, cardY - 54 + 4, SW*0.76, 4, 2)
    cardBar:setFillColor(0.2, 0.6, 1, 0.8)

    -- slot badge
    local slotBadge = display.newRoundedRect(sg, cardX - SW*0.30, cardY - 30, 54, 18, 4)
    slotBadge:setFillColor(0.05, 0.15, 0.38)
    slotBadge.strokeWidth = 1
    slotBadge:setStrokeColor(0.2, 0.5, 0.9, 0.6)
    display.newText({
        parent=sg, text="SLOT " .. save.activeSlot,
        x=cardX - SW*0.30, y=cardY - 30,
        font=ui.FONT, fontSize=8, align="center"
    }):setFillColor(0.3, 0.6, 1)

    -- player name (tappable to rename)
    local nameLabel = display.newText({
        parent=sg, text=player.name or "Player",
        x=cardX - SW*0.14, y=cardY - 12,
        font=ui.FONT_BOLD, fontSize=20, align="left"
    })
    nameLabel:setFillColor(0.9, 0.95, 1)
    nameLabel.anchorX = 0

    -- edit icon hint
    local editHint = display.newText({
        parent=sg, text="[EDIT]",
        x=cardX + SW*0.28, y=cardY - 12,
        font=ui.FONT, fontSize=8, align="right"
    })
    editHint:setFillColor(0.3, 0.6, 1, 0.7)
    flicker(editHint, 0.4, 1.0, 600)

    -- level + xp line
    local xpNeeded = player.level * 100
    display.newText({
        parent=sg, text="LEVEL " .. (player.level or 1),
        x=cardX - SW*0.14, y=cardY + 12,
        font=ui.FONT_BOLD, fontSize=13, align="left"
    }):setFillColor(0.25, 0.75, 1.0)

    display.newText({
        parent=sg, text="XP " .. (player.xp or 0) .. " / " .. xpNeeded,
        x=cardX - SW*0.14, y=cardY + 30,
        font=ui.FONT, fontSize=10, align="left"
    }):setFillColor(0.4, 0.65, 0.9)

    -- xp bar
    local barW  = SW * 0.60
    local barX  = cardX - SW*0.14
    local barBg = display.newRect(sg, barX + barW*0.5, cardY + 46, barW, 5)
    barBg.anchorX = 0.5
    barBg:setFillColor(0.1, 0.12, 0.18)

    local xpPct  = math.min((player.xp or 0) / xpNeeded, 1)
    local barFill = display.newRect(sg, barX, cardY + 46, barW * xpPct, 5)
    barFill.anchorX = 0
    barFill:setFillColor(0.2, 0.7, 1)

    -- tap card or name to rename
    local function doRename()
        showNameEditOverlay(sg, player.name, function(newName)
            local oldName = player.name
            player.name = newName
            if newName and #newName > 0 and newName ~= oldName then
                tasksUtil.advance(player, "set_username", 1)
            end
            save.renameProfile(save.activeSlot, newName)
            save.save(player)
            local renamePayload = {}
            for k, v in pairs(player) do renamePayload[k] = v end
            renamePayload.renameProfile = true
            api.player.update(renamePayload, function() end)
            nameLabel.text = newName
            -- re-navigate to refresh
            composer.removeScene("scenes.profile")
            composer.gotoScene("scenes.profile", { effect="fade", time=200 })
        end)
    end

    card:addEventListener("tap", doRename)
    nameLabel:addEventListener("tap", doRename)
    editHint:addEventListener("tap", doRename)

    --------------------------------------------------
    -- ACTION BUTTONS
    --------------------------------------------------
    local btnW  = SW * 0.82
    local btnH  = 46
    local btn1Y = SH * 0.84
    local btn2Y = btn1Y + btnH + 10
    local btn3Y = btn2Y + btnH + 10

    -- SWITCH PROFILE
    mkBtn(sg, CX, btn1Y, btnW, btnH, "SWITCH PROFILE", 0.2, 0.6, 1.0, function()
        composer.removeScene("scenes.home")
        composer.removeScene("scenes.profile")
        composer.gotoScene("scenes.profile_select", { effect="fade", time=300 })
    end)

    -- DELETE PROFILE
    mkBtn(sg, CX, btn2Y, btnW, btnH, "DELETE PROFILE", 1.0, 0.2, 0.2, function()
        showConfirmOverlay(sg,
            "DELETE " .. string.upper(player.name or "PROFILE") .. "?\nThis cannot be undone.",
            function()
                api.player.deleteProfile(save.activeSlot, function() end)
                save.deleteProfile(save.activeSlot)
                composer.removeScene("scenes.home")
                composer.removeScene("scenes.profile")
                composer.gotoScene("scenes.profile_select", { effect="fade", time=300 })
            end
        )
    end)
end

-------------------------------------------------
-- SCENE HIDE
-------------------------------------------------
function scene:hide(event)
    if event.phase ~= "will" then return end
    closeActiveNameEdit()
    for _, t in ipairs(TIMERS) do pcall(function() timer.cancel(t) end) end
    TIMERS = {}
end

function scene:destroy(event)
    closeActiveNameEdit()
end

scene:addEventListener("create", scene)
scene:addEventListener("hide",   scene)
scene:addEventListener("destroy", scene)

return scene
