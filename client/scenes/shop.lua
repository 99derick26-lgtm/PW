local composer = require("composer")
local scene     = composer.newScene()

package.loaded["utils.items"] = nil  -- force reload for hot-testing

local items      = require("utils.items")
local api        = require("utils.api")
local saveUtil   = require("utils.save")
local sync       = require("utils.sync")
local ui         = require("utils.ui")
local petScaler  = require("utils.pet_scaler")
local petAssets  = require("utils.pet_assets")
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
local TAB_BTN_W = 58
local TAB_BTN_H = 42
local TAB_ICON_W = 30
local TAB_ICON_H = 30
local GRID_TOP_Y = 50
local GRID_BOTTOM_Y = display.contentHeight - 58

local STAT_ICONS = {
    attack  = "assets/sprites/ui/icons/atk.png",
    defense = "assets/sprites/ui/icons/def.png",
    speed   = "assets/sprites/ui/icons/spd.png",
    hp      = "assets/sprites/ui/icons/hp.png"
}

-- 7 tabs: icon = path to the tab icon sprite
local STAT_BANNERS = {
    attack  = "assets/sprites/ui/icons/atk_banner.png",
    defense = "assets/sprites/ui/icons/def_banner.png",
    speed   = "assets/sprites/ui/icons/spd_banner.png",
    hp      = "assets/sprites/ui/icons/hp_banner.png",
}

local STAT_BANNER_WIDTH = 72
local STAT_BANNER_HEIGHT = 32
local STAT_VALUE_OFFSET_X = 44
local STAT_COLUMN_GAP = 128

local WEAPON_STAT_ORDER = { attack=1, defense=2, speed=3, hp=4 }
local ARMOR_STAT_ORDER = { hp=1, defense=2, speed=3, attack=4 }

local function orderGearStats(item, entries)
    local slot = item and item.slot
    local order
    if slot == "weapon" then
        order = WEAPON_STAT_ORDER
    elseif slot == "helmet" or slot == "chest" or slot == "gloves"
        or slot == "boots" or slot == "necklace" or slot == "ring"
        or slot == "charm" then
        order = ARMOR_STAT_ORDER
    else
        return false
    end

    table.sort(entries, function(a, b)
        local aRank = order[a.stat] or 99
        local bRank = order[b.stat] or 99
        if aRank == bRank then
            return tostring(a.stat) < tostring(b.stat)
        end
        return aRank < bRank
    end)
    return true
end

local function drawStatBanner(parent, statKey, x, y, value)
    local ok, banner = pcall(
        display.newImageRect,
        parent,
        STAT_BANNERS[statKey],
        STAT_BANNER_WIDTH,
        STAT_BANNER_HEIGHT
    )
    if ok and banner then
        banner.x = x
        banner.y = y
    end
    local st = display.newText({
        parent=parent, text=tostring(value or ""),
        x=x + STAT_VALUE_OFFSET_X, y=y, width=70,
        font=ui.FONT_BOLD, fontSize=14, align="left"
    })
    st.anchorX = 0
    st:setFillColor(0.86, 0.96, 1.0)
    return st
end

local TABS = {
    -- row 1
    { icon="assets/sprites/ui/icons/tabs/home_I.png",   key="home",     label="HOME",     row=1 },
    { icon="assets/sprites/ui/icons/tabs/pet_I.png",    key="pets",     label="PETS",     row=1 },
    { icon="assets/sprites/ui/icons/tabs/weapons.png",  key="weapons",  label="WEAPONS",  row=1 },
    { icon="assets/sprites/ui/icons/tabs/armor.png",    key="armor",    label="ARMOR",    row=1 },
    -- row 2
    { icon="assets/sprites/ui/icons/tabs/costumes.png", key="costumes", label="COSTUME",  row=2 },
    { icon="assets/sprites/ui/icons/tabs/others.png",   key="more",     label="OTHER",    row=2 },
    { icon="assets/sprites/ui/icons/tabs/auction.png",  key="auction",  label="AUCTION",  row=2 },
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
local shopInputLocked = false
local auctionPage = 1
local publicAuctionData = { auctions={}, page=1, totalPages=1 }

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

local SHOP_SALE_MULTIPLIER = 0.10

local function getShopPrice(item)
    return math.max(1, math.floor((item.price or 0) * SHOP_SALE_MULTIPLIER))
end

local function usesQuantityPurchase(item)
    return item and item.slot == "misc" and item.stackable == true
end

local function grantPurchasedItem(player, item, amount)
    amount = math.max(1, math.floor(tonumber(amount) or 1))
    if item.type == "material" and item.materialKey then
        player.materials = player.materials or {}
        player.materials[item.materialKey] = (player.materials[item.materialKey] or 0) + amount
        return
    end

    player.inventory = player.inventory or {}
    for _ = 1, amount do
        table.insert(player.inventory, item.id)
    end
end

local function unlockShopInputSoon()
    timer.performWithDelay(180, function()
        shopInputLocked = false
    end)
end

local function setNavPressed(btn, pressed)
    if btn and btn.fill then
        btn.fill = {
            type = "image",
            filename = pressed and "assets/sprites/ui/btn_nav_pressed.png" or "assets/sprites/ui/btn_nav.png"
        }
    end
end

local function addNavTouch(target, btn, onRelease)
    target:addEventListener("tap", function()
        return true
    end)
    target:addEventListener("touch", function(event)
        if event.phase == "began" then
            display.getCurrentStage():setFocus(target)
            target._hasFocus = true
            setNavPressed(btn, true)
        elseif target._hasFocus and (event.phase == "ended" or event.phase == "cancelled") then
            display.getCurrentStage():setFocus(nil)
            target._hasFocus = false
            setNavPressed(btn, false)
            if event.phase == "ended" and onRelease then
                onRelease()
            end
        end
        return true
    end)
end

local function oneLineName(name, maxLen)
    name = tostring(name or "")
    if #name <= maxLen then return name end
    return string.sub(name, 1, maxLen - 3) .. "..."
end

local function safeImageRect(parent, path, width, height)
    if not path or path == "" then return nil end
    local ok, image = pcall(display.newImageRect, parent, path, width, height)
    if ok then
        return image
    end
    print("Shop image missing: " .. tostring(path))
    return nil
end

local function formatPercentValue(value)
    local pct = math.floor(math.abs(value) * 100)
    return (value >= 0 and "+" or "-") .. tostring(pct) .. "%"
end

local function formatPercentRange(minValue, maxValue)
    local lo = math.floor((minValue or 0) * 100)
    local hi = math.floor((maxValue or 0) * 100)
    if lo == hi then
        return formatPercentValue(minValue or 0)
    end
    if lo >= 0 and hi >= 0 then
        return "+" .. tostring(lo) .. "-" .. tostring(hi) .. "%"
    end
    if lo <= 0 and hi <= 0 then
        return "-" .. tostring(math.abs(lo)) .. "-" .. tostring(math.abs(hi)) .. "%"
    end
    return tostring(lo) .. "-+" .. tostring(hi) .. "%"
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
    }, { 1.0, 0.84, 0.24 }, "assets/sprites/ui/icons/gold.png", 16, 16)

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
    local row1Y = sh - 8
    local row2Y = sh + 40
    local leftX1 = cx - 139
    local leftX2 = cx - 77
    local rightX1 = cx + 77
    local rightX2 = cx + 139
    return {
        { x = leftX1,  y = row1Y },
        { x = leftX2,  y = row1Y },
        { x = leftX1,  y = row2Y },
        { x = leftX2,  y = row2Y },
        { x = rightX1, y = row1Y },
        { x = rightX2, y = row1Y },
        { x = rightX1, y = row2Y },
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
        if ((not owned[id]) or item.stackable) and not item.hiddenFromShop then
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
    if shopInputLocked then return end
    if activePopup then activePopup:removeSelf(); activePopup = nil end

    local player = saveUtil.load()
    local locked = item.requiredLevel and player.level < item.requiredLevel
    local shopPrice = getShopPrice(item)
    local quantityPurchase = usesQuantityPurchase(item)
    local selectedQty = 1
    local maxQty = math.max(1, math.floor((player.gold or 0) / math.max(1, shopPrice)))
    local canAfford = (player.gold or 0) >= shopPrice

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
    local panelH = 324
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
            petAssets.portrait(item.petId),
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
                text = formatPercentRange(bonus.min, bonus.max)
            else
                text = formatPercentValue(bonus)
            end
            statEntries[#statEntries + 1] = { stat=stat, text=text }
        end
    elseif item.type == "injection" then
        local pct = math.floor((item.boostPercent or 0) * 100)
        if item.injectionStat == "all" then
            statEntries = {
                { stat="attack", text="+" .. tostring(pct) .. "%" },
                { stat="defense", text="+" .. tostring(pct) .. "%" },
                { stat="speed", text="+" .. tostring(pct) .. "%" },
                { stat="hp", text="+" .. tostring(pct) .. "%" },
            }
        elseif item.injectionStat then
            statEntries[#statEntries + 1] = {
                stat=item.injectionStat,
                text="+" .. tostring(pct) .. "%"
            }
        end
    end

    local statsStartX = cx - 102
    local statsStartY = cy + 22
    local statCellH = 34
    local verticalGearStats = orderGearStats(item, statEntries)
    for i = 1, math.min(4, #statEntries) do
        local entry = statEntries[i]
        local col = verticalGearStats and 0 or ((i - 1) % 2)
        local row = verticalGearStats and (i - 1) or math.floor((i - 1) / 2)
        local sx = statsStartX + col * STAT_COLUMN_GAP
        local sy = statsStartY + row * statCellH
        drawStatBanner(content, entry.stat, sx, sy, entry.text)
    end

    local priceY = cy + panelH * 0.5 - 42
    local priceText
    local buyLabel
    local qtyText
    local function clampPurchaseQty(qty)
        return math.max(1, math.min(maxQty, math.floor(qty or 1)))
    end
    local function refreshPurchaseQty()
        if qtyText then qtyText.text = tostring(selectedQty) end
        if priceText then
            priceText.text = tostring(shopPrice * (quantityPurchase and selectedQty or 1))
        end
        if buyLabel then
            buyLabel.text = locked and "LOCKED"
                or (canAfford and (quantityPurchase and ("BUY x" .. tostring(selectedQty)) or "BUY") or "NO GOLD")
        end
    end
    local function purchaseHoldStep(qty, direction)
        qty = math.max(1, tonumber(qty) or 1)
        if direction < 0 then
            if qty <= 10 then return 1 end
            if qty <= 100 then return 10 end
            if qty <= 1000 then return 100 end
            return 1000
        end
        if qty < 10 then return 1 end
        if qty < 100 then return 10 end
        if qty < 1000 then return 100 end
        return 1000
    end
    local function setPurchaseQty(qty)
        selectedQty = clampPurchaseQty(qty)
        refreshPurchaseQty()
    end
    local function nudgePurchaseQty(direction, held)
        local step = held and purchaseHoldStep(selectedQty, direction) or 1
        setPurchaseQty(selectedQty + step * direction)
    end
    if quantityPurchase then
        local qtyY = cy + 58
        local qtyLabel = display.newText({
            parent=content,
            text="QTY",
            x=cx - 52, y=qtyY,
            font=ui.FONT_BOLD, fontSize=11, align="center"
        })
        qtyLabel:setFillColor(0.50, 0.86, 1.0)

        qtyText = display.newText({
            parent=content,
            text="1",
            x=cx, y=qtyY,
            width=54,
            font=ui.FONT_BOLD, fontSize=18, align="center"
        })
        qtyText:setFillColor(0.88, 0.96, 1.0)

        local function makeQtyButton(x, label, direction)
            local group = display.newGroup()
            content:insert(group)
            local bg = display.newRoundedRect(group, x, qtyY, 34, 28, 6)
            bg:setFillColor(0.04, 0.13, 0.26, 0.96)
            bg.strokeWidth = 1.5
            bg:setStrokeColor(0.30, 0.76, 1.0, 0.72)
            local text = display.newText({
                parent=group,
                text=label,
                x=x, y=qtyY - 1,
                font=ui.FONT_BOLD, fontSize=18, align="center"
            })
            text:setFillColor(0.82, 0.96, 1.0)
            text.isHitTestable = false
            local holdTimer
            local didHoldStep = false
            local function cancelHoldTimer()
                if holdTimer then
                    timer.cancel(holdTimer)
                    holdTimer = nil
                end
            end
            local function stepQty()
                nudgePurchaseQty(direction, true)
            end
            group:addEventListener("touch", function(event)
                if event.phase == "began" then
                    display.getCurrentStage():setFocus(group)
                    group._hasFocus = true
                    didHoldStep = false
                    cancelHoldTimer()
                    holdTimer = timer.performWithDelay(360, function()
                        didHoldStep = true
                        stepQty()
                    end, 0)
                elseif group._hasFocus and (event.phase == "ended" or event.phase == "cancelled") then
                    cancelHoldTimer()
                    display.getCurrentStage():setFocus(nil)
                    group._hasFocus = false
                    if event.phase == "ended" and not didHoldStep then
                        nudgePurchaseQty(direction, false)
                    end
                end
                return true
            end)
            group:addEventListener("tap", function()
                return true
            end)
        end

        makeQtyButton(cx - 104, "-", -1)
        makeQtyButton(cx + 52, "+", 1)
    end
    local priceIcon = display.newImageRect(content, "assets/sprites/ui/icons/gold.png", 16, 16)
    priceIcon.x = cx - panelW * 0.5 + 32
    priceIcon.y = priceY
    priceText = display.newText({
        parent=content, text=tostring(shopPrice),
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
    local okBtn, btnObj = pcall(display.newImageRect, buyGroup, "assets/sprites/ui/btn_nav.png", 60, 30)
    if okBtn and btnObj then
        buyBtn = btnObj
        buyBtn.x = buyX
        buyBtn.y = buyY
    else
        buyBtn = display.newRoundedRect(buyGroup, buyX, buyY, 60, 30, 7)
        buyBtn:setFillColor(0.05, 0.18, 0.42, 0.98)
        buyBtn.strokeWidth = 1
        buyBtn:setStrokeColor(0.26, 0.78, 1.0, 0.82)
    end
    if not buyable then buyBtn.alpha = 0.55 end

    buyLabel = display.newText({
        parent=buyGroup,
        text = locked and "LOCKED" or (canAfford and (quantityPurchase and "BUY x1" or "BUY") or "NO GOLD"),
        x=buyX, y=buyY,
        font=ui.FONT_BOLD, fontSize=12, align="center"
    })
    buyLabel:setFillColor(0.82, 0.96, 1.0)
    buyLabel.isHitTestable = false
    refreshPurchaseQty()

    if buyable then
        local buyHit = display.newRect(buyGroup, buyX, buyY, 96, 34)
        buyHit:setFillColor(1, 1, 1, 0.01)
        buyHit.isHitTestable = true

        addNavTouch(buyHit, buyBtn, function()
            if shopInputLocked then return end
            shopInputLocked = true

            local p = saveUtil.load()
            p.inventory = p.inventory or {}
            if not item.stackable then
                for _, id in ipairs(p.inventory) do
                    if id == item.id then
                        unlockShopInputSoon()
                        return
                    end
                end
            end
            local buyQty = quantityPurchase and selectedQty or 1
            local totalPrice = shopPrice * buyQty
            if p.gold < totalPrice then
                unlockShopInputSoon()
                return
            end

            p.gold = p.gold - totalPrice
            grantPurchasedItem(p, item, buyQty)
            saveUtil.save(p)
            sync.pushPlayerSnapshot(p)
            if goldText then goldText.text = tostring(p.gold) end

            ui.popupClose(popupGroup, overlay, { content }, function()
                activePopup = nil

                local didReward = taskRewards.process(sceneGroupRef, p, {
                    {
                        id = "buy_from_shop",
                        amount = buyQty,
                        message = "You bought an item from the Shop.",
                    },
                    {
                        id = "spend_gold",
                        amount = totalPrice,
                        message = "You spent gold on your build.",
                    },
                }, function()
                    local updatedPlayer = saveUtil.load()
                    sync.pushPlayerSnapshot(updatedPlayer)
                    if goldText then goldText.text = tostring(updatedPlayer.gold or 0) end
                    buildGrid()
                    unlockShopInputSoon()
                end)

                if not didReward then
                    buildGrid()
                    unlockShopInputSoon()
                end
            end)
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

local function secondsLeftText(endsAt)
    local y, mo, d, h, mi, s = tostring(endsAt or ""):match("^(%d+)%-(%d+)%-(%d+)T(%d+):(%d+):(%d+)")
    if not y then return "" end
    local target = os.time({ year=tonumber(y), month=tonumber(mo), day=tonumber(d), hour=tonumber(h), min=tonumber(mi), sec=tonumber(s) })
    local left = math.max(0, target - os.time())
    local hours = math.floor(left / 3600)
    local mins = math.floor((left % 3600) / 60)
    if hours > 0 then return tostring(hours) .. "h " .. tostring(mins) .. "m" end
    return tostring(math.floor(left / 60)) .. "m"
end

local function showAuctionBidPopup(auction)
    if activePopup then activePopup:removeSelf(); activePopup = nil end
    local popupGroup = display.newGroup()
    sceneGroupRef:insert(popupGroup)
    activePopup = popupGroup

    local overlay = display.newRect(popupGroup, display.contentCenterX, display.contentCenterY, display.actualContentWidth, display.actualContentHeight)
    overlay:setFillColor(0,0,0,0.72)
    local cx, cy = display.contentCenterX, display.contentCenterY
    local panelW, panelH = math.min(display.actualContentWidth - 34, 320), 292
    local panel = display.newRoundedRect(popupGroup, cx, cy, panelW, panelH, 9)
    panel:setFillColor(0.02,0.06,0.16,0.98)
    panel.strokeWidth = 2
    panel:setStrokeColor(0.24,0.70,1.0,0.76)

    local icon = safeImageRect(popupGroup, auction.sprite, 92, 92)
    if icon then
        icon.x = cx
        icon.y = cy - 80
    end
    display.newText({
        parent=popupGroup, text=auction.name or "Auction Item",
        x=cx, y=cy - 22, width=panelW - 40,
        font=ui.FONT_BOLD, fontSize=14, align="center",
    }):setFillColor(0.88,0.96,1.0)
    display.newText({
        parent=popupGroup,
        text="Top bid: " .. tostring(auction.price or 0) .. "g  -  " .. tostring(auction.topBidder or "None"),
        x=cx, y=cy + 8, width=panelW - 36,
        font=ui.FONT_BOLD, fontSize=10, align="center",
    }):setFillColor(1.0,0.82,0.20)
    display.newText({
        parent=popupGroup,
        text="Max: " .. tostring(auction.maxPrice or 0) .. "g    Ends: " .. secondsLeftText(auction.endsAt),
        x=cx, y=cy + 28, width=panelW - 36,
        font=ui.FONT_BOLD, fontSize=8, align="center",
    }):setFillColor(0.54,0.72,0.96)

    local nextBid = auction.nextBid or ((auction.price or 0) + 250)
    local bidBtn = display.newRoundedRect(popupGroup, cx, cy + 82, 172, 38, 8)
    bidBtn:setFillColor(0.04,0.18,0.42,0.98)
    bidBtn.strokeWidth = 1.6
    bidBtn:setStrokeColor(0.30,0.78,1.0,0.82)
    display.newText({
        parent=popupGroup, text="BID " .. tostring(nextBid) .. "g",
        x=cx, y=cy + 82, font=ui.FONT_BOLD, fontSize=12,
    }):setFillColor(0.84,0.96,1.0)
    bidBtn:addEventListener("tap", function()
        api.auctions.bidPublic(auction.auctionId, {}, function(response)
            if response and response.ok and response.data then
                if response.data.player then
                    sync.applyPlayerSnapshot(response.data.player, saveUtil.activeSlot)
                    if goldText then goldText.text = tostring((saveUtil.load() or {}).gold or 0) end
                end
                if activePopup then activePopup:removeSelf(); activePopup = nil end
                buildGrid()
            end
        end)
        return true
    end)

    local function closePopup()
        if activePopup then activePopup:removeSelf(); activePopup = nil end
        return true
    end
    overlay:addEventListener("tap", closePopup)
end

local function buildAuctionGrid()
    local ph = display.newGroup()
    sceneGroupRef:insert(ph)
    shopScroll = ph

    local contentLeft = 16
    local contentRight = display.actualContentWidth - 16
    local contentWidth = contentRight - contentLeft
    local scrollTop = GRID_TOP_Y + 8
    local controlsY = GRID_BOTTOM_Y - 24
    local scrollBottom = controlsY - 30

    local auctions = publicAuctionData.auctions or {}
    local cols = 2
    local cardW = (contentWidth - 18) / 2
    local cardH = 56
    local gapX, gapY = 8, 7
    local startX = contentLeft + cardW * 0.5 + 4
    local startY = scrollTop + cardH * 0.5 + 4

    local frame = display.newRoundedRect(ph, contentLeft + contentWidth * 0.5, (scrollTop + scrollBottom) * 0.5, contentWidth + 4, scrollBottom - scrollTop + 8, 8)
    frame:setFillColor(0,0,0,0)
    frame.strokeWidth = 2
    frame:setStrokeColor(0.22,0.62,1.0,0.58)
    frame.isHitTestable = false

    if #auctions == 0 then
        display.newText({
            parent=ph, text="No public auctions",
            x=display.contentCenterX, y=(scrollTop + scrollBottom) * 0.5,
            font=ui.FONT_BOLD, fontSize=16, align="center",
        }):setFillColor(0.4,0.8,1)
    end

    for i, auction in ipairs(auctions) do
        local col = (i - 1) % cols
        local row = math.floor((i - 1) / cols)
        local x = startX + col * (cardW + gapX)
        local y = startY + row * (cardH + gapY)
        local card = display.newRoundedRect(ph, x, y, cardW, cardH, 7)
        card:setFillColor(0.03,0.07,0.18,0.96)
        card.strokeWidth = 1.3
        card:setStrokeColor(0.30,0.72,1.0,0.58)
        local icon = safeImageRect(ph, auction.sprite, 38, 38)
        if icon then
            icon.x = x - cardW * 0.5 + 27
            icon.y = y
        end
        local name = display.newText({
            parent=ph, text=oneLineName(auction.name, 15),
            x=x - cardW * 0.5 + 52, y=y - 11,
            width=cardW - 58, font=ui.FONT_BOLD, fontSize=8, align="left",
        })
        name.anchorX = 0
        name:setFillColor(0.88,0.95,1.0)
        local price = display.newText({
            parent=ph, text=tostring(auction.price or 0) .. "g",
            x=x - cardW * 0.5 + 52, y=y + 8,
            width=cardW - 58, font=ui.FONT_BOLD, fontSize=10, align="left",
        })
        price.anchorX = 0
        price:setFillColor(0.72,1.0,0.80)
        card:addEventListener("tap", function()
            showAuctionBidPopup(auction)
            return true
        end)
    end

    local totalPages = publicAuctionData.totalPages or 1
    local prev = display.newRoundedRect(ph, display.contentCenterX - 96, controlsY, 76, 28, 7)
    prev:setFillColor(0.04,0.10,0.24, auctionPage <= 1 and 0.36 or 0.96)
    prev.strokeWidth = 1.3
    prev:setStrokeColor(0.24,0.62,1.0, auctionPage <= 1 and 0.30 or 0.72)
    display.newText({ parent=ph, text="PREV", x=prev.x, y=prev.y, font=ui.FONT_BOLD, fontSize=9 }):setFillColor(0.78,0.92,1.0)
    local next = display.newRoundedRect(ph, display.contentCenterX + 96, controlsY, 76, 28, 7)
    next:setFillColor(0.04,0.10,0.24, auctionPage >= totalPages and 0.36 or 0.96)
    next.strokeWidth = 1.3
    next:setStrokeColor(0.24,0.62,1.0, auctionPage >= totalPages and 0.30 or 0.72)
    display.newText({ parent=ph, text="NEXT", x=next.x, y=next.y, font=ui.FONT_BOLD, fontSize=9 }):setFillColor(0.78,0.92,1.0)
    display.newText({
        parent=ph, text="PAGE " .. tostring(auctionPage) .. "/" .. tostring(totalPages),
        x=display.contentCenterX, y=controlsY, font=ui.FONT_BOLD, fontSize=9,
    }):setFillColor(0.60,0.82,1.0)

    prev:addEventListener("tap", function()
        if auctionPage > 1 then
            auctionPage = auctionPage - 1
            buildGrid()
        end
        return true
    end)
    next:addEventListener("tap", function()
        if auctionPage < totalPages then
            auctionPage = auctionPage + 1
            buildGrid()
        end
        return true
    end)
end

-------------------------------------------------
-- BUILD GRID
-------------------------------------------------
buildGrid = function()
    if shopScroll then
        if shopScroll._fadeTop and shopScroll._fadeTop.removeSelf then shopScroll._fadeTop:removeSelf() end
        if shopScroll._fadeBottom and shopScroll._fadeBottom.removeSelf then shopScroll._fadeBottom:removeSelf() end
        if shopScroll._scrollFrame and shopScroll._scrollFrame.removeSelf then shopScroll._scrollFrame:removeSelf() end
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

    if activeTab == "auction" then
        api.auctions.public(auctionPage, 12, function(response)
            if activeTab ~= "auction" then return end
            publicAuctionData = (response and response.ok and response.data) or { auctions={}, page=auctionPage, totalPages=1 }
            auctionPage = publicAuctionData.page or auctionPage
            buildAuctionGrid()
            if showRadial then showRadial() end
        end)
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
                iconPath = petAssets.portrait(item.petId)
            elseif item.icon then
                iconPath = item.icon
            end
        if iconPath then
            local ic = safeImageRect(row, iconPath, 68, 62)
            if ic then
                ic.x = x - rowCardW * 0.5 + 44
                ic.y = y
                if locked then ic.alpha = 0.45 end
            end
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
                    row, "assets/sprites/ui/icons/gold.png", 16, 16
                )
                gi.x = textLeft + 148; gi.y = y + 18
                local priceText = display.newText({
                    parent=row, text=tostring(getShopPrice(item)),
                    x=textLeft + 160, y=y+18, width=textW - 20, font=ui.FONT_BOLD, fontSize=16, align="left"
                })
                priceText.anchorX = 0
                priceText:setFillColor(0.72, 1.0, 0.80)
            end

            border:addEventListener("tap", function()
                if activePopup or shopInputLocked then return true end
                showItemPopup(item)
                return true
            end)
            glow:addEventListener("tap", function()
                if activePopup or shopInputLocked then return true end
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
    local scrollFrame = display.newRoundedRect(
        sceneGroupRef,
        contentLeft + contentWidth * 0.5,
        (scrollTop + scrollBottom) * 0.5,
        contentWidth + 4,
        (scrollBottom - scrollTop) + 8,
        8
    )
    scrollFrame:setFillColor(0, 0, 0, 0)
    scrollFrame.strokeWidth = 2
    scrollFrame:setStrokeColor(0.22, 0.62, 1.0, 0.58)
    scrollFrame.isHitTestable = false
    shopScroll._fadeTop = fadeTop
    shopScroll._fadeBottom = fadeBottom
    shopScroll._scrollFrame = scrollFrame

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

    local headerPanel = display.newRoundedRect(sceneGroup, display.contentCenterX, 15, display.actualContentWidth - 24, 34, 8)
    headerPanel:setFillColor(0.02, 0.06, 0.16, 0.96)
    headerPanel.strokeWidth = 1
    headerPanel:setStrokeColor(0.22, 0.52, 1.0, 0.36)

    local headerLine = display.newRect(sceneGroup, display.contentCenterX, 32, display.actualContentWidth - 48, 1)
    headerLine:setFillColor(0.30, 0.70, 1.0, 0.28)

    local shopTitle = display.newText({
        parent=sceneGroup, text="SHOP",
        x=22, y=10, font=ui.FONT_BOLD, fontSize=18, align="left"
    })
    shopTitle.anchorX = 0
    shopTitle:setFillColor(0.38, 0.86, 1.0)

    categoryText = display.newText({
        parent=sceneGroup, text="ALL STOCK",
        x=22, y=24, font=ui.FONT_BOLD, fontSize=8, align="left"
    })
    categoryText.anchorX = 0
    categoryText:setFillColor(0.50, 0.74, 1.0, 0.82)

    -- gold display
    local goldGroup = display.newGroup()
    sceneGroup:insert(goldGroup)

    local goldChip = display.newRoundedRect(goldGroup, display.actualContentWidth - 80, 15, 96, 24, 8)
    goldChip:setFillColor(0.08, 0.10, 0.22, 0.96)
    goldChip.strokeWidth = 1.5
    goldChip:setStrokeColor(1.0, 0.82, 0.20, 0.50)

    local goldIcon = display.newImageRect(
        goldGroup, "assets/sprites/ui/icons/gold.png", 16, 16
    )
    goldIcon.x = display.actualContentWidth - 118
    goldIcon.y = 15

    goldText = display.newText({
        parent=goldGroup, text=tostring(saveUtil.load().gold or 0),
        x=display.actualContentWidth - 56, y=15,
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
    -- TAB DOCK - compact bottom rows
    -------------------------------------------------
    local tabBar  = display.newGroup()
    sceneGroup:insert(tabBar)
    tabButtons = {}

    local dockBg = display.newRoundedRect(tabBar, display.contentCenterX, display.contentHeight + 24, display.actualContentWidth - 16, 116, 10)
    dockBg:setFillColor(0.015, 0.04, 0.11, 0.90)
    dockBg.strokeWidth = 1
    dockBg:setStrokeColor(0.13, 0.48, 0.88, 0.30)
    dockBg.isHitTestable = false


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

        local function onTap()
            activeTab = t.key
            composer.setVariable("shopTab", t.key)
            buildGrid()
            return true
        end
        bg:addEventListener("tap", onTap)
        iconImg:addEventListener("tap", onTap)

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

    shopInputLocked = false
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
    shopInputLocked = false
    if activePopup then activePopup:removeSelf(); activePopup = nil end
end

scene:addEventListener("create", scene)
scene:addEventListener("show",   scene)
scene:addEventListener("hide",   scene)

return scene

