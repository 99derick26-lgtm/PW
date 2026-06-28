local composer  = require("composer")
local scene     = composer.newScene()

local saveUtil   = require("utils.save")
local items      = require("utils.items")
local petsDB     = require("utils.pets")
local petScaler  = require("utils.pet_scaler")
local petAssets  = require("utils.pet_assets")
local ui         = require("utils.ui")
local spells     = require("utils.spells")
local stats      = require("utils.stats")
local radialMenu = require("utils.radial_menu")
local taskRewards = require("utils.task_rewards")

local SW = display.actualContentWidth
local SH = display.actualContentHeight
local CX = display.contentCenterX
local CY = display.contentCenterY

local HEADER_H    = 35
local FOOTER_PAD  = 176
local STRIP_H     = 102
local STRIP_Y     = SH - FOOTER_PAD - STRIP_H * 0.5 - 4
local BTN_H       = 40
local BTN_W       = SW * 0.44
local BTN_Y       = STRIP_Y - STRIP_H * 0.5 - BTN_H * 0.5 - 6
local PANEL_TOP   = HEADER_H + 8
local PANEL_BOT   = BTN_Y - BTN_H * 0.5 - 8
local PANEL_H     = PANEL_BOT - PANEL_TOP
local PANEL_CY    = PANEL_TOP + PANEL_H * 0.5
local PANEL_W     = SW - 16
local ICON_SIZE   = 72
local ICON_PAD    = 8
local C_PANEL  = { 0.03, 0.08, 0.22, 0.97 }
local C_STROKE = { 0.20, 0.55, 1.00, 0.55 }
local C_SEL    = { 0.10, 0.45, 1.00, 0.75 }
local C_EQ     = { 0.08, 0.70, 0.25, 0.70 }
local C_IDLE   = { 0.05, 0.12, 0.28, 0.90 }
local C_STR_EQ = { 0.20, 1.00, 0.40, 0.90 }

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

local sceneGroupRef
local mainGroup
local stripScrollView
local selectedPetId = nil
local rowObjects    = {}
local activePopup   = nil
local loadImg
local buildMainPanel
local refreshStripColors

local STAT_META = {
    atk = {
        icon = "atk",
        color = { 1.00, 0.34, 0.30 },
        material = "augment_attack",
        sprite = "assets/sprites/materials/augment_attack.png",
        short = "ATK",
    },
    def = {
        icon = "def",
        color = { 0.36, 0.78, 1.00 },
        material = "augment_defense",
        sprite = "assets/sprites/materials/augment_defense.png",
        short = "DEF",
    },
    hp = {
        icon = "hp",
        color = { 0.38, 1.00, 0.48 },
        material = "augment_health",
        sprite = "assets/sprites/materials/augment_health.png",
        short = "HP",
    },
    spd = {
        icon = "spd",
        color = { 1.00, 0.85, 0.18 },
        material = "augment_speed",
        sprite = "assets/sprites/materials/augment_speed.png",
        short = "SPD",
    },
}

local STAT_BANNERS = {
    atk = "assets/sprites/ui/icons/atk_banner.png",
    def = "assets/sprites/ui/icons/def_banner.png",
    hp  = "assets/sprites/ui/icons/hp_banner.png",
    spd = "assets/sprites/ui/icons/spd_banner.png",
}

local function drawStatBanner(parent, statKey, x, y, value, valueColor)
    local bannerPath = STAT_BANNERS[statKey]
    local ok, banner = pcall(display.newImageRect, parent, bannerPath, 104, 40)
    if ok and banner then
        banner.x = x
        banner.y = y
    else
        local fallback = display.newRoundedRect(parent, x, y, 104, 28, 4)
        fallback:setFillColor(0.95, 0.60, 0.10, 0.96)
        display.newText({
            parent=parent, text=string.upper(statKey),
            x=x, y=y, font=ui.FONT_BOLD, fontSize=10
        }):setFillColor(0.02, 0.05, 0.14)
    end
    local valueText = display.newText({
        parent=parent,
        text=tostring(value or 0),
        x=x + 66, y=y,
        font=ui.FONT_BOLD, fontSize=21, align="left"
    })
    valueText.anchorX = 0
    valueText:setFillColor(0.94, 0.98, 1.0)
    return valueText
end

local function starString(filled)
    return string.rep("★", filled) .. string.rep("☆", 5 - filled)
end

local function closeActivePopup()
    if activePopup and activePopup.removeSelf then
        activePopup:removeSelf()
    end
    activePopup = nil
end

local function showAugmentPopup(petId, statKey)
    closeActivePopup()

    local player = saveUtil.load()
    local starRating = petScaler.getStarRating(player, petId)
    local successRate = math.floor(petScaler.getUpgradeSuccessRate(starRating) * 100)
    local meta = STAT_META[statKey]
    local avatarStats = stats.calculate(player)
    local augments = petScaler.getAugments(player, petId)
    local nextAugments = {
        atk = augments.atk or 0,
        def = augments.def or 0,
        spd = augments.spd or 0,
        hp  = augments.hp  or 0,
    }
    nextAugments[statKey] = (nextAugments[statKey] or 0) + 1

    local currentStats = petScaler.scalePet(petId, avatarStats, augments) or {}
    local nextStats = petScaler.scalePet(petId, avatarStats, nextAugments) or {}
    local scaledGain = math.max(1, (nextStats[statKey] or 0) - (currentStats[statKey] or 0))

    activePopup = display.newGroup()
    sceneGroupRef:insert(activePopup)

    local dim = display.newRect(activePopup, CX, CY, SW, SH)
    dim:setFillColor(0, 0, 0, 0.72)
    dim.isHitTestable = true
    dim:addEventListener("touch", function() return true end)

    local content = display.newGroup()
    activePopup:insert(content)

    local panelW = SW - 26
    local panelH = 246
    local panelX = CX
    local panelY = PANEL_TOP + panelH * 0.5 + 8

    local panel = display.newRoundedRect(content, panelX, panelY, panelW, panelH, 14)
    panel:setFillColor(0.02, 0.06, 0.16, 0.97)
    panel.strokeWidth = 2
    panel:setStrokeColor(meta.color[1], meta.color[2], meta.color[3], 0.76)

    local starsBg = display.newRoundedRect(content, panelX, panelY - 84, 150, 24, 8)
    starsBg:setFillColor(0.04, 0.08, 0.20, 0.94)
    starsBg.strokeWidth = 1
    starsBg:setStrokeColor(0.25, 0.58, 1.0, 0.38)

    local starBase = display.newText({
        parent = content, text = "☆☆☆☆☆",
        x = panelX, y = starsBg.y, font = ui.FONT_BOLD, fontSize = 18
    })
    starBase:setFillColor(0.26, 0.34, 0.48)

    local starFill = display.newText({
        parent = content, text = starString(starRating),
        x = panelX, y = starsBg.y, font = ui.FONT_BOLD, fontSize = 18
    })
    starFill:setFillColor(1.0, 0.84, 0.24)

    local icon = loadImg(content, "assets/sprites/ui/icons/" .. meta.icon .. ".png", 34, 34)
    if icon then
        icon.x = panelX
        icon.y = panelY - 34
    end

    display.newText({
        parent = content,
        text = meta.short,
        x = panelX, y = panelY - 2,
        font = ui.FONT_BOLD, fontSize = 18
    }):setFillColor(unpack(meta.color))

    display.newText({
        parent = content,
        text = "+" .. tostring(scaledGain),
        x = panelX, y = panelY + 24,
        font = ui.FONT_BOLD, fontSize = 22
    }):setFillColor(0.35, 1.0, 0.45)

    display.newText({
        parent = content,
        text = "AT LV." .. tostring(level),
        x = panelX, y = panelY + 44,
        font = ui.FONT_BOLD, fontSize = 9
    }):setFillColor(0.58, 0.80, 1.0)

    display.newText({
        parent = content,
        text = "SUCCESS RATE",
        x = panelX, y = panelY + 68,
        font = ui.FONT_BOLD, fontSize = 18
    }):setFillColor(0.82, 0.92, 1.0)

    display.newText({
        parent = content,
        text = tostring(successRate) .. "%",
        x = panelX, y = panelY + 96,
        font = ui.FONT_BOLD, fontSize = 26
    }):setFillColor(unpack(meta.color))

    local upgradeBtn = display.newRoundedRect(content, panelX, panelY + 122, 148, 34, 8)
    upgradeBtn:setFillColor(0.06, 0.42, 0.16, 0.97)
    upgradeBtn.strokeWidth = 1.5
    upgradeBtn:setStrokeColor(0.22, 0.90, 0.32, 0.90)

    display.newText({
        parent = content,
        text = "UPGRADE",
        x = panelX, y = upgradeBtn.y,
        font = ui.FONT_BOLD, fontSize = 14
    }):setFillColor(0.50, 1.0, 0.60)

    local function closePopup()
        if activePopup ~= nil then
            ui.popupClose(activePopup, dim, { content }, function()
                activePopup = nil
            end)
        end
        return true
    end

    dim:addEventListener("tap", closePopup)

    upgradeBtn:addEventListener("tap", function()
        local p = saveUtil.load()
        local ok, reason = petScaler.attemptAugment(p, petId, statKey)
        if ok then
            saveUtil.save(p)
            closePopup()
            buildMainPanel(petId)
            refreshStripColors()
        else
            if reason == "missing" then
                upgradeBtn:setFillColor(0.30, 0.10, 0.10, 0.97)
            elseif reason == "failed" then
                upgradeBtn:setFillColor(0.40, 0.18, 0.04, 0.97)
            end
            timer.performWithDelay(220, function()
                if upgradeBtn and upgradeBtn.removeSelf then
                    upgradeBtn:setFillColor(0.06, 0.42, 0.16, 0.97)
                end
            end)
            if reason ~= "failed" then return true end
            saveUtil.save(p)
            closePopup()
            buildMainPanel(petId)
            refreshStripColors()
        end
        return true
    end)

    ui.popupOpen(dim, { content })
end

local function showResetPopup(petId)
    closeActivePopup()

    local player = saveUtil.load()
    local augments = petScaler.getAugments(player, petId)
    local entries = {
        { key = "atk", count = augments.atk or 0 },
        { key = "def", count = augments.def or 0 },
        { key = "spd", count = augments.spd or 0 },
        { key = "hp",  count = augments.hp  or 0 },
    }

    activePopup = display.newGroup()
    sceneGroupRef:insert(activePopup)

    local dim = display.newRect(activePopup, CX, CY, SW, SH)
    dim:setFillColor(0, 0, 0, 0.72)
    dim.isHitTestable = true
    dim:addEventListener("touch", function() return true end)

    local content = display.newGroup()
    activePopup:insert(content)

    local panelW = SW - 26
    local panelH = 282
    local panelX = CX
    local panelY = PANEL_TOP + panelH * 0.5 + 12

    local panel = display.newRoundedRect(content, panelX, panelY, panelW, panelH, 14)
    panel:setFillColor(0.02, 0.06, 0.16, 0.97)
    panel.strokeWidth = 2
    panel:setStrokeColor(0.35, 0.62, 1.0, 0.72)

    local rowStartY = panelY - 78
    for i, entry in ipairs(entries) do
        local meta = STAT_META[entry.key]
        local rowY = rowStartY + (i - 1) * 34

        local icon = loadImg(content, meta.sprite, 34, 22)
        if icon then
            icon.x = panelX - 36
            icon.y = rowY
        end

        display.newText({
            parent = content,
            text = "x" .. tostring(entry.count),
            x = panelX + 10, y = rowY,
            font = ui.FONT_BOLD, fontSize = 16, align = "left"
        }):setFillColor(unpack(meta.color))
    end

    display.newText({
        parent = content,
        text = "ARE YOU SURE YOU WANT TO RESTART?",
        x = panelX, y = panelY + 56, width = panelW - 36,
        font = ui.FONT_BOLD, fontSize = 13, align = "center"
    }):setFillColor(0.82, 0.92, 1.0)

    local cancelBtn = display.newRoundedRect(content, panelX - 74, panelY + 106, 124, 34, 8)
    cancelBtn:setFillColor(0.08, 0.10, 0.18, 0.97)
    cancelBtn.strokeWidth = 1.5
    cancelBtn:setStrokeColor(0.30, 0.42, 0.62, 0.70)
    display.newText({
        parent = content, text = "CANCEL",
        x = cancelBtn.x, y = cancelBtn.y, font = ui.FONT_BOLD, fontSize = 12
    }):setFillColor(0.72, 0.82, 0.95)

    local sureBtn = display.newRoundedRect(content, panelX + 74, panelY + 106, 124, 34, 8)
    sureBtn:setFillColor(0.42, 0.12, 0.12, 0.97)
    sureBtn.strokeWidth = 1.5
    sureBtn:setStrokeColor(1.0, 0.28, 0.28, 0.84)
    display.newText({
        parent = content, text = "I'M SURE",
        x = sureBtn.x, y = sureBtn.y, font = ui.FONT_BOLD, fontSize = 12
    }):setFillColor(1.0, 0.84, 0.84)

    local function closePopup()
        if activePopup ~= nil then
            ui.popupClose(activePopup, dim, { content }, function()
                activePopup = nil
            end)
        end
        return true
    end

    dim:addEventListener("tap", closePopup)
    cancelBtn:addEventListener("tap", closePopup)
    sureBtn:addEventListener("tap", function()
        local p = saveUtil.load()
        if petScaler.resetAugments(p, petId) then
            saveUtil.save(p)
        end
        closePopup()
        buildMainPanel(petId)
        refreshStripColors()
        return true
    end)

    ui.popupOpen(dim, { content })
end

local function showSellPopup(petId, petName, sellPrice)
    closeActivePopup()

    activePopup = display.newGroup()
    sceneGroupRef:insert(activePopup)

    local dim = display.newRect(activePopup, CX, CY, SW, SH)
    dim:setFillColor(0, 0, 0, 0.72)
    dim.isHitTestable = true
    dim:addEventListener("touch", function() return true end)

    local content = display.newGroup()
    activePopup:insert(content)

    local panelW = SW - 34
    local panelH = 170
    local panel = display.newRoundedRect(content, CX, CY, panelW, panelH, 12)
    panel:setFillColor(0.02, 0.06, 0.16, 0.98)
    panel.strokeWidth = 2
    panel:setStrokeColor(0.25, 0.70, 1.0, 0.82)

    display.newText({
        parent = content, text = "SELL PET",
        x = CX, y = CY - 52,
        font = ui.FONT_BOLD, fontSize = 14
    }):setFillColor(0.84, 0.96, 1.0)

    display.newText({
        parent = content,
        text = "Are you sure to sell " .. tostring(petName or petId) .. " for " .. tostring(sellPrice or 0) .. "g?",
        x = CX, y = CY - 14,
        width = panelW - 34,
        font = ui.FONT_BOLD, fontSize = 11,
        align = "center"
    }):setFillColor(0.70, 0.84, 1.0)

    local function closePopup()
        if activePopup ~= nil then
            ui.popupClose(activePopup, dim, { content }, function()
                activePopup = nil
            end)
        end
        return true
    end

    local cancelBtn = display.newRoundedRect(content, CX - 62, CY + 46, 102, 34, 8)
    cancelBtn:setFillColor(0.08, 0.10, 0.18, 0.97)
    cancelBtn.strokeWidth = 1.5
    cancelBtn:setStrokeColor(0.30, 0.42, 0.62, 0.70)
    display.newText({
        parent = content, text = "CANCEL",
        x = cancelBtn.x, y = cancelBtn.y,
        font = ui.FONT_BOLD, fontSize = 11
    }):setFillColor(0.72, 0.82, 0.95)

    local sellBtn = display.newRoundedRect(content, CX + 62, CY + 46, 102, 34, 8)
    sellBtn:setFillColor(0.45, 0.28, 0.04, 0.97)
    sellBtn.strokeWidth = 1.5
    sellBtn:setStrokeColor(1.0, 0.70, 0.20, 0.90)
    display.newText({
        parent = content, text = "SELL",
        x = sellBtn.x, y = sellBtn.y,
        font = ui.FONT_BOLD, fontSize = 11
    }):setFillColor(1.0, 0.85, 0.30)

    dim:addEventListener("tap", closePopup)
    cancelBtn:addEventListener("tap", closePopup)
    sellBtn:addEventListener("tap", function()
        local p = saveUtil.load()
        p.gold = (p.gold or 0) + (sellPrice or 0)
        for i = #p.inventory, 1, -1 do
            if p.inventory[i] == petId then
                table.remove(p.inventory, i)
                break
            end
        end
        saveUtil.save(p)
        selectedPetId = nil
        closePopup()
        buildMainPanel(nil)
        buildStripScroll(sceneGroupRef)
        return true
    end)

    ui.popupOpen(dim, { content }, { overlayAlpha = 0.72, startScale = 0.2, time = 170 })
end

local function isEquipped(player, petId)
    for _, id in ipairs(player.equipped.pets or {}) do
        if id == petId then return true end
    end
    return false
end

loadImg = function(parent, path, w, h)
    local ok, img = pcall(display.newImageRect, parent, path, w, h)
    return ok and img or nil
end

refreshStripColors = function()
    local player = saveUtil.load()
    for _, r in ipairs(rowObjects) do
        local eq  = isEquipped(player, r.petId)
        local sel = (r.petId == selectedPetId)
        if r.bg then
            r.bg:setFillColor(unpack(eq and C_EQ or sel and C_SEL or C_IDLE))
            r.bg.strokeWidth = (eq or sel) and 2 or 1
            r.bg:setStrokeColor(unpack(eq and C_STR_EQ or C_STROKE))
        end
    end
end

buildMainPanel = function(petId)
    if mainGroup then mainGroup:removeSelf(); mainGroup = nil end

    mainGroup = display.newGroup()
    sceneGroupRef:insert(mainGroup)

    if not petId then
        display.newText({
            parent=mainGroup, text="Select a pet below",
            x=CX, y=PANEL_CY, font=ui.FONT_BOLD, fontSize=13
        }):setFillColor(0.35, 0.55, 0.85)

        local eb = display.newRoundedRect(mainGroup, CX - SW*0.25, BTN_Y, BTN_W, BTN_H, 8)
        eb:setFillColor(0.1, 0.1, 0.15)
        eb.strokeWidth = 1; eb:setStrokeColor(0.25, 0.35, 0.5, 0.5)
        display.newText({ parent=mainGroup, text="EQUIP", x=CX - SW*0.25, y=BTN_Y,
            font=ui.FONT_BOLD, fontSize=14 }):setFillColor(0.3, 0.35, 0.45)

        local sb = display.newRoundedRect(mainGroup, CX + SW*0.25, BTN_Y, BTN_W, BTN_H, 8)
        sb:setFillColor(0.1, 0.1, 0.15)
        sb.strokeWidth = 1; sb:setStrokeColor(0.25, 0.35, 0.5, 0.5)
        display.newText({ parent=mainGroup, text="SELL", x=CX + SW*0.25, y=BTN_Y,
            font=ui.FONT_BOLD, fontSize=14 }):setFillColor(0.3, 0.35, 0.45)
        return
    end

    local item    = items[petId]
    local pId     = (item and item.petId) or petId
    local def     = petsDB[pId]
    local player  = saveUtil.load()
    local augments = petScaler.getAugments(player, petId)
    local totalAugments = petScaler.getTotalAugments(player, petId)
    local augmentLimit = petScaler.getAugmentLimit(petId)
    local starRating = petScaler.getStarRating(player, petId)
    local pstats  = petScaler.scalePet(pId, stats.calculate(player), augments)
    local eq      = isEquipped(player, petId)
    local petName = (item and item.name) or (def and def.name) or petId

    local cardTop = PANEL_TOP
    local nameY = cardTop + 4
    display.newText({
        parent=mainGroup, text=petName,
        x=CX, y=nameY, font=ui.FONT_BOLD, fontSize=36
    }):setFillColor(0.22, 0.58, 1.0)

    local starTabY = nameY + 42
    local starTab = display.newRoundedRect(mainGroup, CX, starTabY, 150, 28, 4)
    starTab:setFillColor(0.03, 0.08, 0.20, 0.82)
    starTab.strokeWidth = 1
    starTab:setStrokeColor(0.24, 0.58, 1.0, 0.48)

    local emptyStars = display.newText({
        parent = mainGroup,
        text = "☆☆☆☆☆",
        x = CX, y = starTabY - 1,
        font = ui.FONT_BOLD, fontSize = 22
    })
    emptyStars:setFillColor(0.28, 0.36, 0.52)
    emptyStars.alpha = 1

    local filledStars = display.newText({
        parent = mainGroup,
        text = starString(starRating),
        x = CX, y = starTabY - 1,
        font = ui.FONT_BOLD, fontSize = 22
    })
    filledStars:setFillColor(1.0, 0.84, 0.24)
    filledStars.alpha = 1

    local spriteSize  = math.min(136, PANEL_H * 0.34)
    local spriteY = starTabY + spriteSize * 0.5 + 26

    local glow = display.newCircle(mainGroup, CX, spriteY, spriteSize * 0.52)
    glow:setFillColor(0.05, 0.2, 0.7, 0.12)
    glow.strokeWidth = 0

    local sprite = loadImg(mainGroup,
        petAssets.home(pId), spriteSize, spriteSize)
    if sprite then
        sprite.x = CX; sprite.y = spriteY
    else
        local ph = display.newRect(mainGroup, CX, spriteY, 70, 70)
        ph:setFillColor(0.1, 0.12, 0.18)
    end

    local divY = spriteY + spriteSize * 0.5 + 8
    local div  = display.newRect(mainGroup, CX, divY, PANEL_W - 24, 1)
    div:setFillColor(0.2, 0.45, 0.9, 0.35)
    div.alpha = 0

    local starTabY = divY + 28
    local starTab = display.newRoundedRect(mainGroup, CX, starTabY, 172, 34, 10)
    starTab:setFillColor(0.03, 0.08, 0.20, 0.94)
    starTab.strokeWidth = 1
    starTab:setStrokeColor(0.24, 0.58, 1.0, 0.40)
    starTab.alpha = 0

    local emptyStars = display.newText({
        parent = mainGroup,
        text = "☆☆☆☆☆",
        x = CX, y = starTabY - 7,
        font = ui.FONT_BOLD, fontSize = 45
    })
    emptyStars:setFillColor(0.28, 0.36, 0.52)
    emptyStars.alpha = 0

    local filledStars = display.newText({
        parent = mainGroup,
        text = starString(starRating),
        x = CX, y = starTabY - 7,
        font = ui.FONT_BOLD, fontSize = 45
    })
    filledStars:setFillColor(1.0, 0.84, 0.24)
    filledStars.alpha = 0

    local statDefs = {
        { "atk", pstats and pstats.atk or 0, augments.atk or 0 },
        { "def", pstats and pstats.def or 0, augments.def or 0 },
        { "spd", pstats and pstats.spd or 0, augments.spd or 0 },
        { "hp",  pstats and pstats.hp  or 0, augments.hp  or 0 },
    }

    local statX = CX - 104
    local statStartY = spriteY + spriteSize * 0.5 + 32
    local statRowH = 34

    for i, s in ipairs(statDefs) do
        local sy  = statStartY + (i - 1) * statRowH
        local meta = STAT_META[s[1]]
        drawStatBanner(mainGroup, s[1], statX, sy, s[2], meta.color)
    end

    local hintText = display.newText({
        parent = mainGroup,
        text = "",
        x = CX, y = PANEL_CY + PANEL_H * 0.5 - 38,
        width = PANEL_W - 30,
        font = ui.FONT_BOLD, fontSize = 8, align = "center"
    })
    hintText:setFillColor(0.58, 0.80, 1.0)

    local augOrder = { "atk", "def", "spd", "hp" }
    for i, statKey in ipairs(augOrder) do
        local meta = STAT_META[statKey]
        local sy  = statStartY + (i - 1) * statRowH

        local plusBtn = display.newRoundedRect(mainGroup, statX + 158, sy, 22, 22, 6)
        plusBtn:setFillColor(0.05, 0.14, 0.28, 0.96)
        plusBtn.strokeWidth = 1
        plusBtn:setStrokeColor(meta.color[1], meta.color[2], meta.color[3], 0.75)

        local plusText = display.newText({
            parent = mainGroup,
            text = "+",
            x = plusBtn.x, y = plusBtn.y - 1,
            font = ui.FONT_BOLD, fontSize = 16
        })
        plusText:setFillColor(unpack(meta.color))

        local function openAugmentPopup()
            if totalAugments >= augmentLimit then
                hintText.text = "MAX AUGMENTS REACHED"
                hintText:setFillColor(1.0, 0.84, 0.24)
                timer.performWithDelay(900, function()
                    if hintText and hintText.removeSelf then hintText.text = "" end
                end)
                return true
            end
            showAugmentPopup(petId, statKey)
            return true
        end

        plusBtn:addEventListener("tap", openAugmentPopup)
        plusText:addEventListener("tap", openAugmentPopup)
    end

    local function doReset()
        local p = saveUtil.load()
        if petScaler.getTotalAugments(p, petId) <= 0 then
            hintText.text = "NO AUGMENTS TO RESET"
            hintText:setFillColor(0.70, 0.82, 1.0)
            timer.performWithDelay(900, function()
                if hintText and hintText.removeSelf then hintText.text = "" end
            end)
        else
            showResetPopup(petId)
        end
        return true
    end

    local actionX = statX + 214
    local equipY = statStartY + 4
    local sellY = equipY + 50
    local resetY = sellY + 46

    local equipRowHit = display.newRect(mainGroup, actionX + 4, equipY, 82, 32)
    equipRowHit:setFillColor(0, 0, 0, 0.01)
    equipRowHit.isHitTestable = true

    local equipBox = display.newRoundedRect(mainGroup, actionX - 28, equipY, 20, 20, 5)
    equipBox:setFillColor(0.02, 0.08, 0.18, 0.96)
    equipBox.strokeWidth = 1.5
    equipBox:setStrokeColor(eq and 0.26 or 0.28, eq and 0.95 or 0.70, eq and 0.48 or 1.0, 0.86)
    if eq then
        local check = display.newText({
            parent = mainGroup,
            text = "✓",
            x = equipBox.x,
            y = equipBox.y - 1,
            font = ui.FONT_BOLD,
            fontSize = 16
        })
        check:setFillColor(0.36, 1.0, 0.56)
        check.isHitTestable = false
    end

    local equipLabel = display.newText({
        parent = mainGroup,
        text = "EQUIP",
        x = actionX - 12,
        y = equipY,
        font = ui.FONT_BOLD,
        fontSize = 11,
        align = "left"
    })
    equipLabel.anchorX = 0
    equipLabel:setFillColor(0.74, 0.92, 1.0)
    equipLabel.isHitTestable = false

    local function toggleEquip()
        local p = saveUtil.load()
        p.equipped.pets = p.equipped.pets or {}
        local justEquipped = false
        if eq then
            for i = #p.equipped.pets, 1, -1 do
                if p.equipped.pets[i] == petId then
                    table.remove(p.equipped.pets, i); break
                end
            end
        else
            local maxEquipped = spells.getMaxPetSlots(p)
            if #p.equipped.pets >= maxEquipped then
                hintText.text = "FULL (" .. maxEquipped .. " MAX)"
                hintText:setFillColor(1.0, 0.84, 0.24)
                timer.performWithDelay(1400, function()
                    if hintText and hintText.removeSelf then hintText.text = "" end
                end)
                return true
            end
            table.insert(p.equipped.pets, petId)
            justEquipped = true
        end
        saveUtil.save(p)
        if justEquipped then
            taskRewards.process(sceneGroupRef, p, {
                {
                    id = "equip_a_pet",
                    amount = 1,
                    message = "You equipped a pet for battle.",
                },
            }, function()
                buildMainPanel(petId)
                buildStripScroll(sceneGroupRef)
            end)
        end
        buildMainPanel(petId)
        buildStripScroll(sceneGroupRef)
        return true
    end

    equipRowHit:addEventListener("tap", toggleEquip)
    equipBox:addEventListener("tap", toggleEquip)

    local sellPrice = item and math.floor((item.price or 0) * (item.sellPercent or 0.2)) or 0

    local sellHit = display.newCircle(mainGroup, actionX, sellY, 22)
    sellHit:setFillColor(0.03, 0.10, 0.22, 0.70)
    sellHit.strokeWidth = 1.5
    sellHit:setStrokeColor(1.0, 0.70, 0.20, eq and 0.32 or 0.82)
    sellHit.alpha = eq and 0.38 or 1.0
    local sellIcon = loadImg(mainGroup, "assets/sprites/ui/icons/sell.png", 34, 34)
    if sellIcon then
        sellIcon.x = actionX
        sellIcon.y = sellY
        sellIcon.alpha = sellHit.alpha
        sellIcon.isHitTestable = false
    end

    sellHit:addEventListener("tap", function()
        if eq then return true end
        showSellPopup(petId, petName, sellPrice)
        return true
    end)

    local resetHit = display.newCircle(mainGroup, actionX, resetY, 22)
    resetHit:setFillColor(0.03, 0.10, 0.22, 0.70)
    resetHit.strokeWidth = 1.5
    resetHit:setStrokeColor(0.36, 0.58, 0.90, 0.72)
    local resetIcon = loadImg(mainGroup, "assets/sprites/ui/icons/reset.png", 34, 34)
    if resetIcon then
        resetIcon.x = actionX
        resetIcon.y = resetY
        resetIcon.isHitTestable = false
    end
    resetHit:addEventListener("tap", doReset)
end

buildStripScroll = function(sg)
    if stripScrollView then
        stripScrollView:removeSelf()
        stripScrollView = nil
    end
    rowObjects = {}

    local player = saveUtil.load()

    local inventoryPets, seen = {}, {}
    for _, id in ipairs(player.inventory or {}) do
        local it = items[id]
        if it and it.slot == "pet" and not seen[id] then
            seen[id] = true
            table.insert(inventoryPets, id)
        end
    end

    local ownedPets, ordered = {}, {}
    for _, id in ipairs(player.equipped and player.equipped.pets or {}) do
        if seen[id] and not ordered[id] then
            ordered[id] = true
            table.insert(ownedPets, id)
        end
    end
    for _, id in ipairs(inventoryPets) do
        if not ordered[id] then
            ordered[id] = true
            table.insert(ownedPets, id)
        end
    end

    local container = display.newGroup()
    sg:insert(container)
    stripScrollView = container

    local stripBg = display.newRoundedRect(container, CX, STRIP_Y, SW - 16, STRIP_H, 10)
    stripBg:setFillColor(0.03, 0.08, 0.22, 0.95)
    stripBg.strokeWidth = 2
    stripBg:setStrokeColor(unpack(C_STROKE))

    if #ownedPets == 0 then
        display.newText({
            parent=container, text="No pets owned",
            x=CX, y=STRIP_Y, font=ui.FONT, fontSize=12
        }):setFillColor(0.4, 0.5, 0.65)
        return
    end

    local clipW    = SW - 20
    local clipH    = STRIP_H - 6
    local perItem  = ICON_SIZE + ICON_PAD
    local totalW   = ICON_PAD + #ownedPets * perItem + ICON_PAD
    local maxScroll = math.max(0, totalW - clipW)

    local clip = display.newContainer(clipW, clipH)
    clip.x = CX
    clip.y = STRIP_Y
    container:insert(clip)

    local scrollGroup = display.newGroup()
    clip:insert(scrollGroup)

    local leftEdge = -clipW * 0.5

    for idx, petId in ipairs(ownedPets) do
        local iconX = leftEdge + ICON_PAD + (idx - 1) * perItem + ICON_SIZE * 0.5
        local iconY = -10

        local it  = items[petId]
        local pId = (it and it.petId) or petId
        local eq  = isEquipped(player, petId)
        local sel = (petId == selectedPetId)
        local stars = petScaler.getStarRating(player, petId)

        local bg = display.newRoundedRect(scrollGroup,
            iconX, iconY, ICON_SIZE, ICON_SIZE - 4, 6)
        bg:setFillColor(unpack(eq and C_EQ or sel and C_SEL or C_IDLE))
        bg.strokeWidth = (eq or sel) and 2 or 1
        bg:setStrokeColor(unpack(eq and C_STR_EQ or C_STROKE))

        local port = loadImg(scrollGroup,
            petAssets.portrait(pId),
            ICON_SIZE - 10, ICON_SIZE - 10)
        if port then port.x = iconX; port.y = iconY end

        local starBg = display.newRoundedRect(scrollGroup, iconX, iconY + 45, ICON_SIZE - 4, 20, 6)
        starBg:setFillColor(0.03, 0.08, 0.20, 0.92)
        starBg.strokeWidth = 1
        starBg:setStrokeColor(0.22, 0.46, 0.84, 0.40)

        local starEmpty = display.newText({
            parent = scrollGroup,
            text = "☆☆☆☆☆",
            x = iconX, y = iconY + 45,
            font = ui.FONT_BOLD, fontSize = 18
        })
        starEmpty:setFillColor(0.25, 0.32, 0.48)

        local starFill = display.newText({
            parent = scrollGroup,
            text = starString(stars),
            x = iconX, y = iconY + 45,
            font = ui.FONT_BOLD, fontSize = 18
        })
        starFill:setFillColor(1.0, 0.84, 0.24)

        local capId = petId
        local function onTap()
            selectedPetId = capId
            buildMainPanel(capId)
            refreshStripColors()
            return true
        end
        bg:addEventListener("tap", onTap)
        if port then port:addEventListener("tap", onTap) end

        table.insert(rowObjects, { petId=petId, bg=bg })
    end

    local dragStartX, scrollStartX
    local isDragging = false
    local THRESH = 6

    clip:addEventListener("touch", function(e)
        if e.phase == "began" then
            display.getCurrentStage():setFocus(clip)
            dragStartX   = e.x
            scrollStartX = scrollGroup.x
            isDragging   = false
            return true
        elseif e.phase == "moved" then
            local dx = e.x - dragStartX
            if math.abs(dx) > THRESH then isDragging = true end
            if isDragging then
                local nx = scrollStartX + dx
                nx = math.max(-maxScroll, math.min(0, nx))
                scrollGroup.x = nx
            end
            return true
        elseif e.phase == "ended" or e.phase == "cancelled" then
            display.getCurrentStage():setFocus(nil)
            isDragging = false
            return true
        end
    end)
end

function scene:create(event)
    sceneGroupRef = self.view
    local sg = sceneGroupRef

    local bg = display.newImage("assets/sprites/ui/bg_home_grid.png")
    local sx = SW / bg.width; local sy = SH / bg.height
    bg:scale(math.max(sx,sy), math.max(sx,sy))
    bg.x = CX; bg.y = CY; bg.isHitTestable = false
    sg:insert(bg)

end

function scene:show(event)
    if event.phase ~= "did" then return end

    local player = saveUtil.load()
    local ownsSelected = false
    if selectedPetId then
        for _, id in ipairs(player.inventory or {}) do
            if id == selectedPetId then
                ownsSelected = true
                break
            end
        end
    end

    if not ownsSelected then
        selectedPetId = nil
        if player.equipped.pets and #player.equipped.pets > 0 then
            selectedPetId = player.equipped.pets[1]
        else
            for _, id in ipairs(player.inventory or {}) do
                local it = items[id]
                if it and it.slot == "pet" then selectedPetId = id; break end
            end
        end
    end

    buildStripScroll(sceneGroupRef)
    buildMainPanel(selectedPetId)

    radialMenu.show(sceneGroupRef, {
        activeScene = "pet",
        inner       = RADIAL_INNER,
        outer       = RADIAL_OUTER,
    })
end

function scene:hide(event)
    if event.phase ~= "will" then return end
    radialMenu.destroy()
    if stripScrollView then stripScrollView:removeSelf(); stripScrollView = nil end
    if mainGroup       then mainGroup:removeSelf();       mainGroup = nil end
    rowObjects    = {}
    selectedPetId = nil
end

scene:addEventListener("create", scene)
scene:addEventListener("show",   scene)
scene:addEventListener("hide",   scene)

return scene
