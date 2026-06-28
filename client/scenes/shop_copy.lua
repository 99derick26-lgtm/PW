local composer = require("composer")
local scene     = composer.newScene()

package.loaded["utils.items"] = nil  -- force reload for hot-testing

local items      = require("utils.items")
local saveUtil   = require("utils.save")
local ui         = require("utils.ui")
local petScaler  = require("utils.pet_scaler")
local stats      = require("utils.stats")
local xpUtil     = require("utils.xp")
local widget     = require("widget")
local radialMenu = require("utils.radial_menu")
local taskRewards = require("utils.task_rewards")
local chestRewards = require("utils.chest_rewards")

-------------------------------------------------
-- CONSTANTS
-------------------------------------------------
local COLS    = 1
local CARD_W  = 146
local CARD_H  = 74
local ROW_GAP = 8
local TAB_BTN_W = 40
local TAB_BTN_H = 40
local TAB_ICON_W = 30
local TAB_ICON_H = 30
local GRID_TOP_Y = 70
local GRID_BOTTOM_Y = display.contentHeight - 96

local STAT_ICONS = {
    attack  = "assets/sprites/ui/icons/atk.png",
    defense = "assets/sprites/ui/icons/def.png",
    speed   = "assets/sprites/ui/icons/spd.png",
    hp      = "assets/sprites/ui/icons/hp.png"
}

-- 7 tabs: icon = path to the tab icon sprite
local TABS = {
    -- row 1
    { icon="assets/sprites/ui/icons/tabs/home_I.png",   key="home",     row=1 },
    { icon="assets/sprites/ui/icons/tabs/pet_I.png",    key="pets",     row=1 },
    { icon="assets/sprites/ui/icons/tabs/weapons.png",  key="weapons",  row=1 },
    { icon="assets/sprites/ui/icons/tabs/armor.png",    key="armor",    row=1 },
    -- row 2
    { icon="assets/sprites/ui/icons/tabs/costumes.png", key="costumes", row=2 },
    { icon="assets/sprites/ui/icons/tabs/others.png",   key="more",     row=2 },
    { icon="assets/sprites/ui/icons/tabs/auction.png",  key="auction",  row=2 },
}

local ARMOR_SLOTS = {
    helmet=true, chest=true, gloves=true, boots=true,
    necklace=true, ring=true, charm=true
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
local activeTab    = "home"
local sceneGroupRef
local activePopup
local goldText
local shopScroll
local tabButtons   = {}   -- track tab button groups for active highlight
local categoryText

-- forward declare so popup can call it
local buildGrid
local showRadial

local TAB_LABELS = {
    home = "All Stock",
    pets = "Pets",
    weapons = "Weapons",
    armor = "Armor",
    costumes = "Costumes",
    more = "Misc",
    auction = "Auction",
}

local function oneLineName(name, maxLen)
    name = tostring(name or "")
    if #name <= maxLen then return name end
    return string.sub(name, 1, maxLen - 3) .. "..."
end

local function isCostumeItem(item)
    if not item then return false end
    local slot = item.slot
    return slot == "costume" or slot == "skin"
end

local function isMiscItem(item)
    if not item then return false end
    local slot = item.slot
    if slot == "weapon" or slot == "pet" then return false end
    if ARMOR_SLOTS[slot] then return false end
    if isCostumeItem(item) then return false end
    return true
end

local function buildMiscPlaceholder()
    local ph = display.newGroup()
    sceneGroupRef:insert(ph)
    shopScroll = ph

    local player = saveUtil.load()
    local mats = player.materials or { scrap = 0, coil = 0, chip = 0 }
    local chests = chestRewards.ensureInventory(player)
    local CX = display.contentCenterX

    display.newText({
        parent = ph,
        text = "MISC STOCK",
        x = CX,
        y = 96,
        font = ui.FONT_BOLD,
        fontSize = 18,
        align = "center"
    }):setFillColor(0.4, 0.8, 1)

    display.newText({
        parent = ph,
        text = "Potions, materials, chests, and other non-gear items will appear here.",
        x = CX,
        y = 126,
        width = display.actualContentWidth - 48,
        font = ui.FONT,
        fontSize = 12,
        align = "center"
    }):setFillColor(0.56, 0.72, 0.90)

    local function summaryCard(x, y, w, h, title, lines, accent, iconPath, iconW, iconH)
        local card = display.newRoundedRect(ph, x, y, w, h, 12)
        card:setFillColor(0.03, 0.07, 0.18, 0.96)
        card.strokeWidth = 1.5
        card:setStrokeColor(accent[1], accent[2], accent[3], 0.58)

        if iconPath then
            local okIcon, icon = pcall(display.newImageRect, ph, iconPath, iconW or 22, iconH or 22)
            if okIcon and icon then
                icon.x = x - w * 0.5 + 22
                icon.y = y - h * 0.5 + 22
            end
        end

        local titleText = display.newText({
            parent = ph,
            text = title,
            x = x,
            y = y - h * 0.5 + 22,
            width = w - 46,
            font = ui.FONT_BOLD,
            fontSize = 11,
            align = "center"
        })
        titleText:setFillColor(accent[1], accent[2], accent[3])

        for i, line in ipairs(lines) do
            local text = display.newText({
                parent = ph,
                text = line,
                x = x,
                y = y - 8 + (i - 1) * 18,
                width = w - 24,
                font = ui.FONT_BOLD,
                fontSize = 10,
                align = "center"
            })
            text:setFillColor(0.88, 0.95, 1.0)
        end
    end

    summaryCard(CX - 78, 220, 138, 104, "RESOURCES", {
        "Gold: " .. tostring(player.gold or 0),
        "Energy: " .. tostring(player.energy or 0),
        "Diamonds: " .. tostring(player.diamonds or 0),
    }, { 1.0, 0.84, 0.24 }, "assets/sprites/ui/icons/gold.png", 18, 18)

    summaryCard(CX + 78, 220, 138, 104, "CHESTS", {
        "Common: " .. tostring(chests.common or 0),
        "Rare: " .. tostring(chests.rare or 0),
        "Battle drops",
    }, { 0.50, 0.92, 1.0 }, "assets/sprites/materials/rare_chest.png", 28, 22)

    summaryCard(CX, 346, 292, 98, "MATERIALS", {
        "Amorphous: " .. tostring(mats.scrap or 0),
        "Carbon Fiber: " .. tostring(mats.coil or 0) .. "    Micro-chips: " .. tostring(mats.chip or 0),
        "Managed from the Materials screen",
    }, { 0.42, 1.0, 0.62 }, "assets/sprites/more/chip.png", 18, 18)
end

local function buildDockPositions(cx, sh)
    local row1Y = sh - 41
    local row2Y = sh - 1
    return {
        { x = cx - 140, y = row1Y },
        { x = cx - 93, y = row1Y },
        { x = cx - 46, y = row1Y },
        { x = cx + 1, y = row1Y },
        { x = cx + 48, y = row1Y },
        { x = cx + 95,  y = row1Y },
        { x = cx + 140, y = row1Y },
    }
end

-------------------------------------------------
-- BUILD SHOP LIST  (sorted by requiredLevel asc)
-------------------------------------------------
local function buildShopList(tab)
    local player = saveUtil.load()
    local owned  = {}
    for _, id in ipairs(player.inventory or {}) do owned[id] = true end

    local list = {}
    for id, item in pairs(items) do
        if (not owned[id]) or item.stackable then
            local include = false
            if tab == "home" then
                include = true
            elseif tab == "weapons" then
                include = item.slot == "weapon"
            elseif tab == "armor" then
                include = ARMOR_SLOTS[item.slot] == true
            elseif tab == "pets" then
                include = item.slot == "pet"
            elseif tab == "costumes" then
                include = isCostumeItem(item)
            elseif tab == "more" then
                include = isMiscItem(item)
            end
            if include then
                table.insert(list, id)
            end
        end
    end

    table.sort(list, function(a, b)
        local lvA = items[a].requiredLevel or 999
        local lvB = items[b].requiredLevel or 999
        if lvA == lvB then return a < b end
        return lvA < lvB
    end)

    return list
end

-------------------------------------------------
-- ITEM POPUP
-------------------------------------------------
local function showItemPopup(item)
    if activePopup then activePopup:removeSelf(); activePopup = nil end

    local player = saveUtil.load()
    local locked = item.requiredLevel and player.level < item.requiredLevel
    local canAfford = (player.gold or 0) >= (item.price or 0)

    local popupGroup = display.newGroup()
    sceneGroupRef:insert(popupGroup)
    activePopup = popupGroup

    local overlay = display.newRect(
        popupGroup,
        display.contentCenterX, display.contentCenterY,
        display.actualContentWidth, display.actualContentHeight
    )
    overlay:setFillColor(0, 0, 0, 0.72)

    local content = display.newGroup()
    popupGroup:insert(content)

    local cx = display.contentCenterX
    local cy = display.contentCenterY
    local panelW = math.min(display.actualContentWidth - 30, 326)
    local panelH = 292
    local buyable = (not locked) and canAfford

    local box = display.newRoundedRect(content, cx, cy, panelW, panelH, 8)
    box:setFillColor(0.015, 0.04, 0.11, 0.98)
    box.strokeWidth = 2
    if buyable then
        box:setStrokeColor(0.35, 0.72, 1.0, 0.82)
    else
        box:setStrokeColor(0.65, 0.22, 0.22, 0.82)
    end
    ui.addPopupShield(content, cx, cy, panelW, panelH)

    local title = display.newText({
        parent=content, text=item.name,
        x=cx, y=cy - panelH * 0.5 + 34,
        width=panelW - 54, font=ui.FONT_BOLD, fontSize=15, align="center"
    })
    title:setFillColor(0.86, 0.96, 1.0)

    local icon
    if item.slot == "pet" and item.petId then
        icon = display.newImageRect(
            content,
            "assets/sprites/pets/" .. item.petId .. "/portrait.png",
            106, 106
        )
    elseif item.icon then
        icon = display.newImageRect(content, item.icon, 106, 106)
    end
    if icon then
        icon.x = cx - panelW * 0.5 + 74
        icon.y = cy - 48
        if locked then icon.alpha = 0.45 end
    end

    if item.description then
        local desc = display.newText({
            parent=content, text=item.description,
            x=cx - 32, y=cy - 70,
            width=panelW - 166, font=ui.FONT, fontSize=11, align="left"
        })
        desc.anchorX = 0
        desc:setFillColor(0.68, 0.82, 0.96)
    end

    local statEntries = {}

    if item.slot == "pet" and item.petId then
        local pstats = petScaler.scalePet(item.petId, stats.calculate(player))
        if pstats then
            statEntries = {
                { stat="attack",  text=tostring(pstats.atk) },
                { stat="defense", text=tostring(pstats.def) },
                { stat="speed",   text=tostring(pstats.spd) },
                { stat="hp",      text=tostring(pstats.hp)  },
            }
        end
    elseif item.statPercent then
        for stat, bonus in pairs(item.statPercent) do
            local text
            if type(bonus) == "table" then
                local lo = math.floor(bonus.min * 100)
                local hi = math.floor(bonus.max * 100)
                text = lo==hi and ("+"..lo.."%") or ("+"..lo.."–"..hi.."%")
            else
                local pct  = math.floor(math.abs(bonus) * 100)
                local sign = bonus >= 0 and "+" or "-"
                text = sign..pct.."%"
            end
            statEntries[#statEntries + 1] = { stat=stat, text=text }
        end
    end

    local statsStartX = cx - 132
    local statsStartY = cy + 30
    local statColGap = panelW - 146
    local statCellH = 34
    for i = 1, math.min(4, #statEntries) do
        local entry = statEntries[i]
        local col = (i - 1) % 2
        local row = math.floor((i - 1) / 2)
        local sx = statsStartX + col * statColGap
        local sy = statsStartY + row * statCellH
        local iconPath = STAT_ICONS[entry.stat]
        if iconPath then
            local si = display.newImageRect(content, iconPath, 32, 32)
            si.x = sx
            si.y = sy
        end
        local st = display.newText({
            parent=content, text=entry.text,
            x=sx + 17, y=sy, width=96,
            font=ui.FONT_BOLD, fontSize=15, align="left"
        })
        st.anchorX = 0
        st:setFillColor(0.86, 0.96, 1.0)
    end

    local priceY = cy + panelH * 0.5 - 42
    local priceIcon = display.newImageRect(content, "assets/sprites/ui/icons/gold.png", 45, 45)
    priceIcon.x = cx - panelW * 0.5 + 32
    priceIcon.y = priceY
    local priceText = display.newText({
        parent=content, text=tostring(item.price or 0),
        x=priceIcon.x + 17, y=priceY,
        width=88, font=ui.FONT_BOLD, fontSize=12, align="left"
    })
    priceText.anchorX = 0
    priceText:setFillColor(0.72, 1.0, 0.80)

    if locked then
        local lockText = display.newText({
            parent=content,
            text="LV " .. tostring(item.requiredLevel),
            x=cx + panelW * 0.5 - 72, y=priceY,
            font=ui.FONT_BOLD, fontSize=11, align="center"
        })
        lockText:setFillColor(1.0, 0.28, 0.28)
    end

    local buyGroup = display.newGroup()
    content:insert(buyGroup)
    local buyX = cx + panelW * 0.5 - 68
    local buyY = cy + panelH * 0.5 - 42
    local buyBtn
    local okBtn, btnObj = pcall(display.newImageRect, buyGroup, "assets/sprites/ui/btn_nav.png", 100, 120)
    if okBtn and btnObj then
        buyBtn = btnObj
        buyBtn.x = buyX
        buyBtn.y = buyY
    else
        buyBtn = display.newRoundedRect(buyGroup, buyX, buyY, 104, 34, 7)
        buyBtn:setFillColor(0.05, 0.18, 0.42, 0.98)
        buyBtn.strokeWidth = 1
        buyBtn:setStrokeColor(0.26, 0.78, 1.0, 0.82)
    end
    if not buyable then buyBtn.alpha = 0.55 end

    local buyLabel = display.newText({
        parent=buyGroup,
        text = locked and "LOCKED" or (canAfford and "BUY" or "NO GOLD"),
        x=buyX, y=buyY,
        font=ui.FONT_BOLD, fontSize=12, align="center"
    })
    buyLabel:setFillColor(0.82, 0.96, 1.0)
    buyLabel.isHitTestable = false

    if buyable then
        buyGroup:addEventListener("tap", function()
            local p = saveUtil.load()
            p.inventory = p.inventory or {}
            if not item.stackable then
                for _, id in ipairs(p.inventory) do
                    if id == item.id then return true end
                end
            end
            if p.gold < item.price then return true end
            p.gold = p.gold - item.price
            table.insert(p.inventory, item.id)
            saveUtil.save(p)
            if goldText then goldText.text = tostring(p.gold) end
            ui.popupClose(popupGroup, overlay, { content }, function()
                activePopup = nil
            end)
            local didReward = taskRewards.process(sceneGroupRef, p, {
                {
                    id = "buy_from_shop",
                    amount = 1,
                    message = "You bought an item from the Shop.",
                },
                {
                    id = "spend_gold",
                    amount = item.price or 0,
                    message = "You spent gold on your build.",
                },
            }, function()
                if goldText then goldText.text = tostring(saveUtil.load().gold or 0) end
                buildGrid()
            end)
            if not didReward then
                buildGrid()
            end
            return true
        end)
    end

    local function closePopup()
        return ui.popupClose(popupGroup, overlay, { content }, function()
            activePopup = nil
        end)
    end

    overlay:addEventListener("tap", closePopup)

    ui.popupOpen(overlay, { content }, { overlayAlpha = 0.72, startScale = 0.2, time = 170 })
end

-------------------------------------------------
-- BUILD GRID
-------------------------------------------------
buildGrid = function()
    if shopScroll then
        if shopScroll._fadeTop and shopScroll._fadeTop.removeSelf then shopScroll._fadeTop:removeSelf() end
        if shopScroll._fadeBottom and shopScroll._fadeBottom.removeSelf then shopScroll._fadeBottom:removeSelf() end
        shopScroll:removeSelf()
        shopScroll = nil
    end

    -- update tab highlight
    for _, tb in ipairs(tabButtons) do
        if tb.key == activeTab then
            tb.bg.alpha     = 1.0
            tb.iconImg.alpha = 1.0
            tb.glow.isVisible = true
            tb.bg:setFillColor(0.08, 0.18, 0.40, 0.98)
            tb.bg.strokeWidth = 2
            tb.bg:setStrokeColor(0.35, 0.92, 1.0, 0.95)
        else
            tb.bg.alpha     = 0.35
            tb.iconImg.alpha = 0.6
            tb.glow.isVisible = false
            tb.bg:setFillColor(0.05, 0.10, 0.25, 0.90)
            tb.bg.strokeWidth = 1.5
            tb.bg:setStrokeColor(0.3, 0.6, 1.0, 0.5)
        end
    end
    if categoryText then
        categoryText.text = string.upper(TAB_LABELS[activeTab] or "SHOP")
    end

    if activeTab == "costumes" or activeTab == "auction" then
        local ph = display.newGroup()
        sceneGroupRef:insert(ph)
        shopScroll = ph

        local labels = {
            costumes = "Costume shop\ncoming soon",
            auction  = "Guild Auction\ncoming soon",
        }
        display.newText({
            parent=ph, text=labels[activeTab],
            x=display.contentCenterX, y=display.contentCenterY - 40,
            font=ui.FONT_BOLD, fontSize=18, align="center"
        }):setFillColor(0.4, 0.8, 1)
        return
    end

    local shopItems = buildShopList(activeTab)
    if activeTab == "more" and #shopItems == 0 then
        buildMiscPlaceholder()
        return
    end

    local contentLeft = 16
    local contentRight = display.actualContentWidth - 16
    local contentWidth = contentRight - contentLeft
    local scrollTop = GRID_TOP_Y + 8
    local scrollBottom = GRID_BOTTOM_Y - 8

    shopScroll = widget.newScrollView({
        x                        = contentLeft + contentWidth * 0.5,
        y                        = (scrollTop + scrollBottom) * 0.5,
        width                    = contentWidth,
        height                   = scrollBottom - scrollTop,
        hideBackground           = true,
        horizontalScrollDisabled = true,
    })
    sceneGroupRef:insert(shopScroll)

    local gridGroup = display.newGroup()
    shopScroll:insert(gridGroup)

    local player    = saveUtil.load()
    local contentW  = contentWidth
    local rowCardW  = contentW - 10
    local rowCardH  = CARD_H
    local startY    = rowCardH * 0.5 + 10
    local x         = contentW * 0.5

    for i, itemId in ipairs(shopItems) do
        local item = items[itemId]
        if item then
            local y        = startY + (i - 1) * (rowCardH + ROW_GAP)
            local locked   = item.requiredLevel and player.level < item.requiredLevel

            local row = display.newGroup()
            gridGroup:insert(row)

            local glow = display.newRoundedRect(row, x, y, rowCardW + 4, rowCardH + 4, 8)
            glow:setFillColor(0, 0, 0, 0)
            glow.strokeWidth = 2
            glow:setStrokeColor(locked and 0.65 or 0.22, locked and 0.25 or 0.62, locked and 0.25 or 1.0, locked and 0.40 or 0.26)

            local border = display.newRoundedRect(row, x, y, rowCardW, rowCardH, 8)
            border:setFillColor(0.03, 0.07, 0.18, 0.96)
            border.strokeWidth = 1.5
            if locked then
                border:setStrokeColor(0.65, 0.22, 0.22, 0.65)
            else
                border:setStrokeColor(0.35, 0.72, 1.0, 0.62)
            end

            local iconPath
            if item.slot == "pet" and item.petId then
                iconPath = "assets/sprites/pets/" .. item.petId .. "/portrait.png"
            elseif item.icon then
                iconPath = item.icon
            end
            if iconPath then
                local ic = display.newImageRect(row, iconPath, 68, 62)
                ic.x = x - rowCardW * 0.5 + 44
                ic.y = y
                if locked then ic.alpha = 0.45 end
            end

            local textLeft = x - rowCardW * 0.5 + 92
            local textW = rowCardW - 112
            local nameText = display.newText({
                parent=row,
                text=oneLineName(item.name, 28),
                x=textLeft, y=y - 16,
                width=textW, font=ui.FONT_BOLD, fontSize=11, align="left"
            })
            nameText.anchorX = 0
            nameText.height = 10
            if locked then
                nameText:setFillColor(0.72, 0.60, 0.60)
            else
                nameText:setFillColor(0.88, 0.95, 1.0)
            end

            if locked then
                local priceBar = display.newRoundedRect(row, textLeft + 34, y + 18, 70, 18, 5)
                priceBar:setFillColor(0.12, 0.08, 0.10, 0.96)
                priceBar.strokeWidth = 0
                display.newText({
                    parent=row, text="Lv "..item.requiredLevel,
                    x=textLeft + 34, y=y+18, font=ui.FONT_BOLD, fontSize=9, align="center"
                }):setFillColor(1, 0.25, 0.25)
            else
                local gi = display.newImageRect(
                    row, "assets/sprites/ui/icons/gold.png", 13, 13
                )
                gi.x = textLeft + 7; gi.y = y + 18
                local priceText = display.newText({
                    parent=row, text=tostring(item.price),
                    x=textLeft + 20, y=y+18, width=textW - 20, font=ui.FONT_BOLD, fontSize=10, align="left"
                })
                priceText.anchorX = 0
                priceText:setFillColor(0.72, 1.0, 0.80)
            end

            border:addEventListener("tap", function()
                showItemPopup(item)
                return true
            end)
            glow:addEventListener("tap", function()
                showItemPopup(item)
                return true
            end)
        end
    end

    gridGroup.height = startY + (#shopItems - 1) * (rowCardH + ROW_GAP) + rowCardH * 0.5 + 10

    local fadeTop = display.newRect(sceneGroupRef, contentLeft + contentWidth * 0.5, scrollTop - 7, contentWidth, 14)
    fadeTop:setFillColor(0.015, 0.04, 0.11, 0.96)
    fadeTop.isHitTestable = false
    local fadeBottom = display.newRect(sceneGroupRef, contentLeft + contentWidth * 0.5, scrollBottom + 7, contentWidth, 14)
    fadeBottom:setFillColor(0.015, 0.04, 0.11, 0.96)
    fadeBottom.isHitTestable = false
    shopScroll._fadeTop = fadeTop
    shopScroll._fadeBottom = fadeBottom

    if showRadial then
        showRadial()
    end
end

-------------------------------------------------
-- SCENE CREATE
-------------------------------------------------
function scene:create(event)
    local sceneGroup = self.view
    sceneGroupRef    = sceneGroup

    -- background
    local bg = display.newImage("assets/sprites/ui/bg_home_grid.png")
    local sx = display.actualContentWidth  / bg.width
    local sy = display.actualContentHeight / bg.height
    bg:scale(math.max(sx,sy), math.max(sx,sy))
    bg.x = display.contentCenterX
    bg.y = display.contentCenterY
    sceneGroup:insert(bg)

    local edgeLineL = display.newRect(sceneGroup, 5, display.contentCenterY, 2, display.actualContentHeight - 36)
    edgeLineL:setFillColor(0.13, 0.54, 1.0, 0.58)
    edgeLineL.isHitTestable = false
    local edgeLineR = display.newRect(sceneGroup, display.actualContentWidth - 5, display.contentCenterY, 2, display.actualContentHeight - 36)
    edgeLineR:setFillColor(0.13, 0.54, 1.0, 0.58)
    edgeLineR.isHitTestable = false

    local headerPanel = display.newRoundedRect(sceneGroup, display.contentCenterX, 20, display.actualContentWidth - 24, 38, 8)
    headerPanel:setFillColor(0.02, 0.06, 0.16, 0.96)
    headerPanel.strokeWidth = 1
    headerPanel:setStrokeColor(0.22, 0.52, 1.0, 0.36)

    local headerLine = display.newRect(sceneGroup, display.contentCenterX, 39, display.actualContentWidth - 48, 1)
    headerLine:setFillColor(0.30, 0.70, 1.0, 0.28)

    local shopTitle = display.newText({
        parent=sceneGroup, text="SHOP",
        x=22, y=14, font=ui.FONT_BOLD, fontSize=18, align="left"
    })
    shopTitle.anchorX = 0
    shopTitle:setFillColor(0.38, 0.86, 1.0)

    categoryText = display.newText({
        parent=sceneGroup, text="ALL STOCK",
        x=22, y=29, font=ui.FONT_BOLD, fontSize=8, align="left"
    })
    categoryText.anchorX = 0
    categoryText:setFillColor(0.50, 0.74, 1.0, 0.82)

    -- gold display
    local goldGroup = display.newGroup()
    sceneGroup:insert(goldGroup)

    local goldChip = display.newRoundedRect(goldGroup, display.actualContentWidth - 80, 20, 96, 24, 8)
    goldChip:setFillColor(0.08, 0.10, 0.22, 0.96)
    goldChip.strokeWidth = 1.5
    goldChip:setStrokeColor(1.0, 0.82, 0.20, 0.50)

    local goldIcon = display.newImageRect(
        goldGroup, "assets/sprites/ui/icons/gold.png", 16, 16
    )
    goldIcon.x = display.actualContentWidth - 118
    goldIcon.y = 20

    goldText = display.newText({
        parent=goldGroup, text=tostring(saveUtil.load().gold or 0),
        x=display.actualContentWidth - 56, y=20,
        font=ui.FONT_BOLD, fontSize=15, align="right"
    })
    goldText.anchorX = 1

    local reelPanelY = (GRID_TOP_Y + GRID_BOTTOM_Y) * 0.5
    local reelPanelH = GRID_BOTTOM_Y - GRID_TOP_Y
    local reelPanel = display.newRoundedRect(sceneGroup, display.contentCenterX, reelPanelY, display.actualContentWidth - 24, reelPanelH, 8)
    reelPanel:setFillColor(0.015, 0.04, 0.11, 0.82)
    reelPanel.strokeWidth = 1
    reelPanel:setStrokeColor(0.13, 0.48, 0.88, 0.28)
    reelPanel.isHitTestable = false

    -------------------------------------------------
    -- TAB DOCK - compact bottom rows above the radial
    -------------------------------------------------
    local tabBar  = display.newGroup()
    sceneGroup:insert(tabBar)
    tabButtons = {}

    local dockLine = display.newRoundedRect(tabBar, display.contentCenterX, display.contentHeight - 12, 72, 1, 1)
    dockLine:setFillColor(0.22, 0.62, 1.0, 0.10)

    local function makeTabBtn(t, x, y)
        local grp = display.newGroup()
        tabBar:insert(grp)

        local bg = display.newRoundedRect(grp, x, y, TAB_BTN_W, TAB_BTN_H, 8)
        bg:setFillColor(0.05, 0.10, 0.25, 0.90)
        bg.strokeWidth = 1.5
        bg:setStrokeColor(0.3, 0.6, 1.0, 0.5)

        local glow = display.newRoundedRect(grp, x, y, TAB_BTN_W + 6, TAB_BTN_H + 6, 10)
        glow:setFillColor(0, 0, 0, 0)
        glow.strokeWidth = 2.5
        glow:setStrokeColor(0.3, 0.9, 1.0, 0.9)
        glow.isVisible = false

        local iconImg = display.newImageRect(grp, t.icon, TAB_ICON_W, TAB_ICON_H)
        iconImg.x = x
        iconImg.y = y

        bg:addEventListener("tap", function()
            activeTab = t.key
            composer.setVariable("shopTab", t.key)
            buildGrid()
            return true
        end)
        iconImg:addEventListener("tap", function()
            activeTab = t.key
            composer.setVariable("shopTab", t.key)
            buildGrid()
            return true
        end)

        table.insert(tabButtons, {
            key     = t.key,
            bg      = bg,
            glow    = glow,
            iconImg = iconImg,
        })
    end

    local dockPositions = buildDockPositions(display.contentCenterX, display.contentHeight)
    for i, t in ipairs(TABS) do
        local pos = dockPositions[i]
        makeTabBtn(t, pos.x, pos.y)
    end

    local dockLineLower = display.newRoundedRect(tabBar, display.contentCenterX, display.contentHeight - 120, 220, 1, 1)
    dockLineLower:setFillColor(0.22, 0.62, 1.0, 0.10)

    showRadial = function()
        radialMenu.show(sceneGroup, {
            activeScene = "shop",
            inner       = RADIAL_INNER,
            outer       = RADIAL_OUTER,
        })
    end
end

-------------------------------------------------
-- SCENE SHOW
-------------------------------------------------
function scene:show(event)
    if event.phase ~= "did" then return end

    activeTab = composer.getVariable("shopTab") or activeTab or "home"
    if goldText then goldText.text = tostring(saveUtil.load().gold or 0) end

    buildGrid()
end

-------------------------------------------------
-- SCENE HIDE
-------------------------------------------------
function scene:hide(event)
    if event.phase ~= "will" then return end
    radialMenu.destroy()
    if activePopup then activePopup:removeSelf(); activePopup = nil end
end

scene:addEventListener("create", scene)
scene:addEventListener("show",   scene)
scene:addEventListener("hide",   scene)

return scene

