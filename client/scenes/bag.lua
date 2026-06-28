local composer = require("composer")
local scene     = composer.newScene()

local saveUtil   = require("utils.save")
local sync       = require("utils.sync")
local items      = require("utils.items")
local pets       = require("utils.pets")
local ui         = require("utils.ui")
local petScaler  = require("utils.pet_scaler")
local petAssets  = require("utils.pet_assets")
local stats      = require("utils.stats")
local injections = require("utils.injections")
local spells     = require("utils.spells")
local upgrades   = require("utils.upgrades")
local xpUtil     = require("utils.xp")
local radialMenu = require("utils.radial_menu")
local chestRewards = require("utils.chest_rewards")
local levelUpPopup = require("utils.levelup_popup")

-------------------------------------------------
-- CONSTANTS
-------------------------------------------------
local ARMOR_SLOTS     = { "helmet", "chest", "gloves", "boots" }
local ACCESSORY_SLOTS = { "necklace", "ring", "charm" }
local WEAPON_SLOTS    = 9
local PET_INV_COLS    = 4
local PET_INV_ROWS    = 2
local PET_SLOT_SIZE   = 56
local PET_SLOT_PAD    = 10
local ARMOR_SLOT_SET  = { helmet=true, chest=true, gloves=true, boots=true }
local ACCESSORY_SLOT_SET = { necklace=true, ring=true, charm=true }

local BAG_GRID_COLS      = 6
local BAG_GRID_ROWS      = 4
local BAG_GRID_SLOT_SIZE = 56
local BAG_GRID_PAD       = 2
local BAG_GRID_FRAME_W   = 356
local BAG_GRID_FRAME_H   = 240
local BAG_GRID_Y         = display.contentHeight - 150
local BAG_GRID_CENTER_X  = display.contentCenterX
local BAG_TOP_CENTER_Y   = 176

local COLORS = {
    emptyFill       = { 0.015, 0.04, 0.11, 0.88 },
    filledFill      = { 0.03, 0.07, 0.18, 0.96 },
    emptyStroke     = { 0.13, 0.48, 0.88, 0.24 },
    emptyNeonStroke = { 0.35, 0.72, 1.00, 0.62 },
    panelFill       = { 0.015, 0.04, 0.11, 0.82 },
    panelStroke     = { 0.13, 0.48, 0.88, 0.28 },
    equippedStroke  = { 0.35, 0.92, 1.0, 0.95 },
    blockedStroke   = { 0.65, 0.22, 0.22, 0.82 },
}

local STAT_ICONS = {
    attack  = "assets/sprites/ui/icons/atk.png",
    defense = "assets/sprites/ui/icons/def.png",
    speed   = "assets/sprites/ui/icons/spd.png",
    hp      = "assets/sprites/ui/icons/hp.png"
}

-- Tab definitions — icon paths + keys
local STAT_BANNERS = {
    attack  = "assets/sprites/ui/icons/atk_banner.png",
    defense = "assets/sprites/ui/icons/def_banner.png",
    speed   = "assets/sprites/ui/icons/spd_banner.png",
    hp      = "assets/sprites/ui/icons/hp_banner.png",
}

local function drawStatBanner(parent, statKey, x, y, value)
    local ok, banner = pcall(display.newImageRect, parent, STAT_BANNERS[statKey], 72, 32)
    if ok and banner then
        banner.x = x
        banner.y = y
    end
    local st = display.newText({
        parent=parent, text=tostring(value or ""),
        x=x + 52, y=y, width=70,
        font=ui.FONT_BOLD, fontSize=14, align="left"
    })
    st.anchorX = 0
    st:setFillColor(0.86, 0.96, 1.0)
    return st
end

local TABS = {
    { key="weapons",  icon="assets/sprites/ui/icons/tabs/weapons.png"  },
    { key="armor",    icon="assets/sprites/ui/icons/tabs/armor.png"    },
    { key="costumes", icon="assets/sprites/ui/icons/tabs/costumes.png" },
    { key="other",    icon="assets/sprites/ui/icons/tabs/others.png"   },
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
-- SCENE-LEVEL STATE
-------------------------------------------------
local sceneGroupRef
local contentGroup
local activePopup
local activeTab  = "weapons"
local tabButtons = {}   -- for highlight tracking
local showRadial
local createSlot
local rebuildBag
local bagTimers   = {}
local bagAmbientDots = {}
local bagSparkles = {}

local function trackBagTimer(t)
    if t then bagTimers[#bagTimers + 1] = t end
    return t
end

-------------------------------------------------
-- HELPERS
-------------------------------------------------
local function formatPercentValue(value)
    local pct = math.floor(math.abs(value or 0) * 100)
    return ((value or 0) >= 0 and "+" or "-") .. tostring(pct) .. "%"
end

local function formatPercentRange(minValue, maxValue)
    local lo = math.floor((minValue or 0) * 100)
    local hi = math.floor((maxValue or 0) * 100)
    if lo == hi then return formatPercentValue(minValue or 0) end
    if lo >= 0 and hi >= 0 then return "+" .. lo .. "-" .. hi .. "%" end
    if lo <= 0 and hi <= 0 then return "-" .. math.abs(lo) .. "-" .. math.abs(hi) .. "%" end
    return tostring(lo) .. "-+" .. tostring(hi) .. "%"
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

local isCostumeItem

local function pushPlayerUpdate(player)
    sync.pushPlayerSnapshot(player)
end

local function isEquipped(player, itemId)
    local item = items[itemId]
    if isCostumeItem(item) then
        local activeSkin = (player.appearance and player.appearance.skinId) or player.skinId
        return activeSkin ~= nil and activeSkin == item.skinId
    end
    for _, id in ipairs(player.equipped.weapons or {}) do
        if id == itemId then return true end
    end
    for _, id in ipairs(player.equipped.pets or {}) do
        if id == itemId then return true end
    end
    for _, id in pairs(player.equipped.armor or {}) do
        if id == itemId then return true end
    end
    for _, id in pairs(player.equipped.accessories or {}) do
        if id == itemId then return true end
    end
    return false
end

local function countInventory(player)
    local counts = {}
    for _, id in ipairs(player.inventory or {}) do
        counts[id] = (counts[id] or 0) + 1
    end
    return counts
end

local function countEquippedCopies(player, itemId)
    local total = 0
    local equipped = player and player.equipped or {}
    for _, id in pairs(equipped.weapons or {}) do
        if id == itemId then total = total + 1 end
    end
    for _, id in pairs(equipped.pets or {}) do
        if id == itemId then total = total + 1 end
    end
    for _, id in pairs(equipped.armor or {}) do
        if id == itemId then total = total + 1 end
    end
    for _, id in pairs(equipped.accessories or {}) do
        if id == itemId then total = total + 1 end
    end
    return total
end

local function isArmorOrAccessorySlot(slot)
    return ARMOR_SLOT_SET[slot] or ACCESSORY_SLOT_SET[slot]
end

isCostumeItem = function(item)
    if not item then return false end
    local slot = item.slot
    return slot == "costume" or slot == "skin"
end

local function isOtherItem(item)
    if not item then return false end
    local slot = item.slot
    if slot == "weapon" or slot == "pet" then return false end
    if isArmorOrAccessorySlot(slot) then return false end
    if isCostumeItem(item) then return false end
    return true
end

local function collectInventoryByFilter(player, predicate)
    local list = {}
    for _, id in ipairs(player.inventory or {}) do
        local item = items[id]
        if item and predicate(item) then
            list[#list + 1] = id
        end
    end
    return list
end

local function cloneItemWithCount(itemId, count)
    local base = items[itemId]
    if not base then return nil end

    local copy = {}
    for k, v in pairs(base) do
        copy[k] = v
    end
    copy.id = base.id or itemId
    copy.count = count
    copy.quantityLabel = "x" .. tostring(count)
    return copy
end

local function createBagInventoryGrid(group, inventoryIds)
    local player = saveUtil.load()
    local entries = {}
    local rawStacks = {}
    local rawOrder = {}

    for _, entry in ipairs(inventoryIds or {}) do
        if type(entry) == "table" then
            if (entry.count or 0) > 0 then
                entries[#entries + 1] = entry
            end
        elseif entry then
            local stack = rawStacks[entry]
            if not stack then
                stack = { id = entry, count = 0 }
                rawStacks[entry] = stack
                rawOrder[#rawOrder + 1] = stack
            end
            stack.count = stack.count + 1
        end
    end

    for _, stack in ipairs(rawOrder) do
        local equippedCount = countEquippedCopies(player, stack.id)
        local visibleCount = (stack.count or 0) - equippedCount
        if visibleCount > 0 then
            local cloned = cloneItemWithCount(stack.id, visibleCount)
            if cloned then
                cloned.showCountBadge = equippedCount > 0
                entries[#entries + 1] = cloned
            end
        end
    end

    local frameGroup = display.newGroup()
    group:insert(frameGroup)
    frameGroup.x = BAG_GRID_CENTER_X
    frameGroup.y = BAG_GRID_Y

    local gridPanel = display.newRoundedRect(frameGroup, 0, 4, BAG_GRID_FRAME_W, BAG_GRID_FRAME_H, 8)
    gridPanel:setFillColor(unpack(COLORS.panelFill))
    gridPanel.strokeWidth = 9
    gridPanel:setStrokeColor(unpack(COLORS.panelStroke))

    local topLine = display.newRect(frameGroup, 0, -BAG_GRID_FRAME_H * 0.5 + 13, BAG_GRID_FRAME_W - 34, 1)
    topLine:setFillColor(0.30, 0.70, 1.0, 0.22)
    topLine.isHitTestable = false

    local bottomLine = display.newRect(frameGroup, 0, BAG_GRID_FRAME_H * 0.5 - 13, BAG_GRID_FRAME_W - 34, 1)
    bottomLine:setFillColor(0.30, 0.70, 1.0, 0.16)
    bottomLine.isHitTestable = false

    local gridW = BAG_GRID_COLS * BAG_GRID_SLOT_SIZE + (BAG_GRID_COLS - 1) * BAG_GRID_PAD
    local gridH = BAG_GRID_ROWS * BAG_GRID_SLOT_SIZE + (BAG_GRID_ROWS - 1) * BAG_GRID_PAD
    local startX = -gridW * 0.5 + BAG_GRID_SLOT_SIZE * 0.5
    local startY = -gridH * 0.5 + BAG_GRID_SLOT_SIZE * 0.5 + 4

    for i = 1, BAG_GRID_COLS * BAG_GRID_ROWS do
        local col = (i - 1) % BAG_GRID_COLS
        local row = math.floor((i - 1) / BAG_GRID_COLS)
        local x = startX + col * (BAG_GRID_SLOT_SIZE + BAG_GRID_PAD)
        local y = startY + row * (BAG_GRID_SLOT_SIZE + BAG_GRID_PAD)
        createSlot(frameGroup, x, y, BAG_GRID_SLOT_SIZE, entries[i])
    end
end

local function buildOtherGridEntries(player)
    local mats = player.materials or { scrap = 0, coil = 0, chip = 0 }
    local chests = chestRewards.ensureInventory(player)
    local function countItem(id)
        local total = 0
        for _, invId in ipairs(player.inventory or {}) do
            if invId == id then total = total + 1 end
        end
        return total
    end

    local function showChestOpenPopup(chestId)
        local fresh = saveUtil.load()
        local freshChests = chestRewards.ensureInventory(fresh)
        local chestDef = chestRewards.getDef(chestId)
        if not chestDef or (freshChests[chestId] or 0) <= 0 then return true end

        if activePopup then
            activePopup:removeSelf()
            activePopup = nil
        end

        local popupGroup = display.newGroup()
        sceneGroupRef:insert(popupGroup)
        activePopup = popupGroup

        local function countKeys(source)
            local total = 0
            for _, invId in ipairs(source.inventory or {}) do
                if invId == "digital_key" then total = total + 1 end
            end
            return total
        end
        local hasKey = countKeys(fresh)
        local isRare = chestId == "rare"
        local canOpen = (not isRare) or hasKey > 0
        local canOpen10 = (freshChests[chestId] or 0) >= 10 and ((not isRare) or hasKey >= 10)

        local overlay = display.newRect(
            popupGroup,
            display.contentCenterX, display.contentCenterY,
            display.actualContentWidth, display.actualContentHeight
        )
        overlay:setFillColor(0, 0, 0, 0.72)
        overlay.isHitTestable = true
        overlay:addEventListener("touch", function() return true end)

        local box = display.newRoundedRect(
            popupGroup,
            display.contentCenterX, display.contentCenterY,
            302, 246, 14
        )
        box:setFillColor(0.03, 0.08, 0.18, 0.96)
        box.strokeWidth = 2
        box:setStrokeColor(chestDef.accent[1], chestDef.accent[2], chestDef.accent[3], 0.72)
        local panelShield = ui.addPopupShield(popupGroup, display.contentCenterX, display.contentCenterY, 302, 246)

        local title = display.newText({
            parent = popupGroup,
            text = chestDef.title,
            x = display.contentCenterX,
            y = display.contentCenterY - 94,
            width = 220,
            font = ui.FONT_BOLD,
            fontSize = 18,
            align = "center",
        }):setFillColor(chestDef.accent[1], chestDef.accent[2], chestDef.accent[3])

        local chestIcon = display.newImageRect(popupGroup, chestDef.image, 118, 90)
        chestIcon.x = display.contentCenterX
        chestIcon.y = display.contentCenterY - 26

        local bodyText = isRare
            and ("Requires 1 Digital Key to open.\nYou have " .. tostring(hasKey) .. " key" .. ((hasKey == 1) and "" or "s") .. ".")
            or "Open this chest for free and claim the rewards inside."

        local bodyLabel = display.newText({
            parent = popupGroup,
            text = bodyText,
            x = display.contentCenterX,
            y = display.contentCenterY + 46,
            width = 230,
            font = ui.FONT,
            fontSize = 13,
            align = "center",
        })
        bodyLabel:setFillColor(0.82, 0.92, 1.0)

        local openBtn
        local openLabel
        local open10Btn
        local open10Label
        local openButtonW = 63
        local openButtonH = 60
        local openButtonY = display.contentCenterY + 94
        local openButtonGap = 15

        local function closePopup()
            return ui.popupClose(popupGroup, overlay, { box, panelShield, title, chestIcon, bodyLabel, openBtn, openLabel, open10Btn, open10Label }, function()
                activePopup = nil
            end)
        end

        local function removeKeys(source, qty)
            local removed = 0
            for idx = #(source.inventory or {}), 1, -1 do
                if source.inventory[idx] == "digital_key" then
                    table.remove(source.inventory, idx)
                    removed = removed + 1
                    if removed >= qty then break end
                end
            end
            return removed >= qty
        end

        local function makeOpenButton(x, label, enabled, onTap)
            local okBtn, btn = pcall(display.newImageRect, popupGroup, "assets/sprites/ui/btn_nav.png", openButtonW, openButtonH)
            if okBtn and btn then
                btn.x = x
                btn.y = openButtonY
                btn.alpha = enabled and 1 or 0.42
            else
                btn = display.newRoundedRect(popupGroup, x, openButtonY, openButtonW, openButtonH, 8)
                btn:setFillColor(enabled and 0.06 or 0.05, enabled and 0.18 or 0.06, enabled and 0.45 or 0.10, 0.96)
                btn.strokeWidth = 1.5
                btn:setStrokeColor(0.28, 0.62, 1.0, enabled and 0.76 or 0.30)
            end
            local txt = display.newText({
                parent = popupGroup,
                text = label,
                x = x,
                y = openButtonY,
                font = ui.FONT_BOLD,
                fontSize = 11,
            })
            txt:setFillColor(enabled and 0.86 or 0.46, enabled and 0.96 or 0.54, enabled and 1.0 or 0.64)
            btn:addEventListener("touch", function(event)
                if not enabled then return true end
                if event.phase == "began" then
                    display.getCurrentStage():setFocus(btn)
                    btn._hasFocus = true
                    pcall(function() btn.fill = { type="image", filename="assets/sprites/ui/btn_nav_pressed.png" } end)
                elseif btn._hasFocus and (event.phase == "ended" or event.phase == "cancelled") then
                    display.getCurrentStage():setFocus(nil)
                    btn._hasFocus = false
                    pcall(function() btn.fill = { type="image", filename="assets/sprites/ui/btn_nav.png" } end)
                    if event.phase == "ended" then onTap() end
                end
                return true
            end)
            return btn, txt
        end

        local function openCount(count)
            local openPlayer = saveUtil.load()
            chestRewards.ensureInventory(openPlayer)
            if isRare and not removeKeys(openPlayer, count) then return true end

            ui.popupClose(popupGroup, overlay, { box, panelShield, title, chestIcon, bodyLabel, openBtn, openLabel, open10Btn, open10Label }, function()
                activePopup = nil
                local opened = chestRewards.openChests(openPlayer, chestId, count, xpUtil, levelUpPopup, function()
                    openPlayer.hp = stats.calculate(openPlayer).hp
                    saveUtil.save(openPlayer)
                    pushPlayerUpdate(openPlayer)
                    rebuildBag()
                end)
                if opened then
                    saveUtil.save(openPlayer)
                    pushPlayerUpdate(openPlayer)
                end
            end)
            return true
        end

        openBtn, openLabel = makeOpenButton(display.contentCenterX - (openButtonW * 0.5 + openButtonGap * 0.5), canOpen and "OPEN" or "NEED KEY", canOpen, function()
            return openCount(1)
        end)
        open10Btn, open10Label = makeOpenButton(display.contentCenterX + (openButtonW * 0.5 + openButtonGap * 0.5), "*10", canOpen10, function()
            return openCount(10)
        end)

        overlay:addEventListener("tap", closePopup)
        ui.popupOpen(overlay, { box, panelShield, title, chestIcon, bodyLabel, openBtn, openLabel, open10Btn, open10Label }, { overlayAlpha = 0.72, startScale = 0.2, time = 170 })

        return true
    end

    local entries = {
        {
            id = "resource_gold",
            name = "Gold",
            slot = "resource",
            icon = "assets/sprites/ui/icons/gold.png",
            description = "Main currency used across shops and upgrades.",
            count = player.gold or 0,
            quantityLabel = tostring(player.gold or 0),
        },
        {
            id = "resource_scrap",
            name = "Amorphous",
            slot = "resource",
            icon = "assets/sprites/more/scrap.png",
            description = "Unstable crafting material gathered from the materials flow.",
            count = mats.scrap or 0,
            quantityLabel = tostring(mats.scrap or 0),
        },
        {
            id = "resource_coil",
            name = "Carbon Fiber",
            slot = "resource",
            icon = "assets/sprites/more/large_coil.png",
            description = "Flexible crafting material used for stronger upgrades.",
            count = mats.coil or 0,
            quantityLabel = tostring(mats.coil or 0),
        },
        {
            id = "resource_chip",
            name = "Micro-chips",
            slot = "resource",
            icon = "assets/sprites/more/chip.png",
            description = "High-tech material for advanced progression systems.",
            count = mats.chip or 0,
            quantityLabel = tostring(mats.chip or 0),
        },
        {
            id = "resource_crystal_green",
            name = "Green Crystal",
            slot = "resource",
            icon = "assets/sprites/materials/crystal_green.png",
            description = "Crystal used for guild and upgrade systems.",
            count = mats.crystal_green or 0,
            quantityLabel = tostring(mats.crystal_green or 0),
        },
        {
            id = "resource_crystal_blue",
            name = "Blue Crystal",
            slot = "resource",
            icon = "assets/sprites/materials/crystal_blue.png",
            description = "Crystal used for guild and upgrade systems.",
            count = mats.crystal_blue or 0,
            quantityLabel = tostring(mats.crystal_blue or 0),
        },
        {
            id = "resource_crystal_purple",
            name = "Purple Crystal",
            slot = "resource",
            icon = "assets/sprites/materials/crystal_purple.png",
            description = "Crystal used for guild and upgrade systems.",
            count = mats.crystal_purple or 0,
            quantityLabel = tostring(mats.crystal_purple or 0),
        },
        {
            id = "resource_crystal_orange",
            name = "Orange Crystal",
            slot = "resource",
            icon = "assets/sprites/materials/crystal_orange.png",
            description = "Crystal used for guild and upgrade systems.",
            count = mats.crystal_orange or 0,
            quantityLabel = tostring(mats.crystal_orange or 0),
        },
        {
            id = "resource_augment_attack",
            name = "Atk Augment",
            slot = "resource",
            icon = "assets/sprites/materials/augment_attack.png",
            description = "Pet upgrade material for attack.",
            count = mats.augment_attack or 0,
            quantityLabel = tostring(mats.augment_attack or 0),
        },
        {
            id = "resource_augment_defense",
            name = "Def Augment",
            slot = "resource",
            icon = "assets/sprites/materials/augment_defense.png",
            description = "Pet upgrade material for defense.",
            count = mats.augment_defense or 0,
            quantityLabel = tostring(mats.augment_defense or 0),
        },
        {
            id = "resource_augment_health",
            name = "HP Augment",
            slot = "resource",
            icon = "assets/sprites/materials/augment_health.png",
            description = "Pet upgrade material for health.",
            count = mats.augment_health or 0,
            quantityLabel = tostring(mats.augment_health or 0),
        },
        {
            id = "resource_augment_speed",
            name = "Spd Augment",
            slot = "resource",
            icon = "assets/sprites/materials/augment_speed.png",
            description = "Pet upgrade material for speed.",
            count = mats.augment_speed or 0,
            quantityLabel = tostring(mats.augment_speed or 0),
        },
        {
            id = "resource_common_chest",
            name = "Common Chest",
            slot = "resource",
            icon = "assets/sprites/materials/common_chest.png",
            description = "Open from the bag to gain gold and XP rewards.",
            count = chests.common or 0,
            quantityLabel = "x" .. tostring(chests.common or 0),
            onTap = function() return showChestOpenPopup("common") end,
        },
        {
            id = "resource_rare_chest",
            name = "Rare Chest",
            slot = "resource",
            icon = "assets/sprites/materials/rare_chest.png",
            description = "Requires 1 Digital Key to open. Rare chests pay out bigger rewards.",
            count = chests.rare or 0,
            quantityLabel = "x" .. tostring(chests.rare or 0),
            onTap = function() return showChestOpenPopup("rare") end,
        },
    }

    if (chests.rare or 0) <= 0 then
        entries[6] = nil
    end
    if (chests.common or 0) <= 0 then
        table.remove(entries, 5)
    end

    for i = #entries, 1, -1 do
        local entry = entries[i]
        if entry and entry.id and (entry.id:find("resource_crystal_") == 1 or entry.id:find("resource_augment_") == 1) and (entry.count or 0) <= 0 then
            table.remove(entries, i)
        end
    end

    local miscInventory = collectInventoryByFilter(player, function(item)
        return isOtherItem(item)
    end)
    for _, id in ipairs(miscInventory) do
        entries[#entries + 1] = id
    end

    return entries
end

local function flicker(obj, lo, hi, ms)
    local t = timer.performWithDelay(ms, function()
        if obj and obj.removeSelf then
            obj.alpha = lo + math.random() * (hi - lo)
        end
    end, 0)
    trackBagTimer(t)
end

local function buildAmbientDots(parent, screenW, screenH)
    local ambientGroup = display.newGroup()
    parent:insert(ambientGroup)
    bagAmbientDots = {}

    for i = 1, 18 do
        local size = (i % 4 == 0) and 4 or 2
        local dot = display.newRect(
            ambientGroup,
            math.random(18, math.floor(screenW - 18)),
            math.random(120, math.floor(screenH - 120)),
            size, size
        )
        dot:setFillColor(0.35, 0.65 + math.random() * 0.25, 1.0, 0.08 + math.random() * 0.14)
        dot.isHitTestable = false
        dot._baseAlpha = dot.alpha
        bagAmbientDots[#bagAmbientDots + 1] = dot
        flicker(dot, 0.05, 0.22, math.random(700, 1500))
    end

    for _, dot in ipairs(bagAmbientDots) do
        local startY = dot.y
        local startX = dot.x
        local driftX = startX + math.random(-8, 8)
        local driftY = startY + math.random(-18, 18)
        local function driftDot()
            if not dot or not dot.removeSelf then return end
            transition.to(dot, {
                x = driftX, y = driftY, alpha = math.min(dot._baseAlpha + 0.08, 0.32),
                time = 3200 + math.random(0, 2200), transition = easing.inOutSine,
                onComplete = function()
                    startX, driftX = driftX, startX
                    startY, driftY = driftY, startY
                    transition.to(dot, {
                        x = driftX, y = driftY, alpha = dot._baseAlpha,
                        time = 3200 + math.random(0, 2200), transition = easing.inOutSine,
                        onComplete = driftDot
                    })
                end
            })
        end
        driftDot()
    end
end

local function buildFallingSparkles(parent, screenW, screenH)
    local sparkleGroup = display.newGroup()
    parent:insert(sparkleGroup)
    bagSparkles = {}

    for i = 1, 7 do
        local trail = display.newGroup()
        sparkleGroup:insert(trail)

        local head = display.newCircle(trail, 0, 0, 2)
        head:setFillColor(0.78, 0.96, 1.0, 0.95)

        for t = 1, 3 do
            local tail = display.newRoundedRect(trail, 0, t * 5, 2, 5, 1)
            tail:setFillColor(0.45, 0.78, 1.0, 0.18 - t * 0.03)
        end

        trail.x = math.random(20, math.floor(screenW - 20))
        trail.y = math.random(120, math.floor(screenH - 220))
        trail.alpha = 0.0
        trail.isHitTestable = false
        bagSparkles[#bagSparkles + 1] = trail
    end

    for i, sparkle in ipairs(bagSparkles) do
        local function dropSparkle()
            if not sparkle or not sparkle.removeSelf then return end
            sparkle.x = math.random(18, math.floor(screenW - 18))
            sparkle.y = math.random(120, 250)
            sparkle.alpha = 0
            sparkle.rotation = math.random(-12, 12)
            transition.to(sparkle, {
                alpha = 1.0,
                time = 220 + math.random(0, 120),
                onComplete = function()
                    if not sparkle or not sparkle.removeSelf then return end
                    transition.to(sparkle, {
                        x = sparkle.x + math.random(-24, 24),
                        y = screenH - 180 + math.random(-18, 18),
                        alpha = 0.05,
                        time = 2400 + math.random(0, 900),
                        transition = easing.inQuad,
                        onComplete = function()
                            trackBagTimer(timer.performWithDelay(500 + math.random(0, 1600), dropSparkle))
                        end
                    })
                end
            })
        end
        trackBagTimer(timer.performWithDelay(300 + i * 180, dropSparkle))
    end
end

-------------------------------------------------
-- FORWARD DECLARATIONS
-------------------------------------------------
local buildWeaponsTab
local buildArmorTab
local buildAvatarTab
local buildOtherTab

-------------------------------------------------
-- REBUILD BAG
-------------------------------------------------
rebuildBag = function()
    if contentGroup then
        contentGroup:removeSelf()
        contentGroup = nil
    end

    contentGroup = display.newGroup()
    sceneGroupRef:insert(contentGroup)

    -- update tab highlights
    for _, tb in ipairs(tabButtons) do
        local isActive = (tb.key == activeTab)
        tb.bg.alpha      = isActive and 1.0  or 0.35
        tb.iconImg.alpha = isActive and 1.0  or 0.55
        tb.glow.isVisible = isActive
    end

    if activeTab == "weapons" then
        buildWeaponsTab(contentGroup)
    elseif activeTab == "armor" then
        buildArmorTab(contentGroup)
    elseif activeTab == "costumes" then
        buildAvatarTab(contentGroup)
    elseif activeTab == "other" then
        buildOtherTab(contentGroup)
    end

    if showRadial then
        showRadial()
    end
end

-------------------------------------------------
-- SLOT
-------------------------------------------------
createSlot = function(group, x, y, size, itemId, isActive, hideCount)
    local r = display.newRoundedRect(group, x, y, size, size, 5)
    r.strokeWidth = isActive and 2 or 1

    if itemId then
        r:setFillColor(unpack(COLORS.filledFill))
        r:setStrokeColor(unpack(isActive and COLORS.equippedStroke or COLORS.emptyNeonStroke))

        local item = (type(itemId) == "table") and itemId or items[itemId]
        if item then
            local icon
            if item.slot == "pet" then
                icon = display.newImageRect(
                    group,
                    petAssets.portrait(item.id),
                    size - 8, size - 8
                )
            else
                icon = display.newImageRect(group, item.icon, size - 8, size - 8)
            end

            if icon then icon.x = x; icon.y = y end

            local player = saveUtil.load()
            local count
            local countText
            if hideCount then
                count = nil
            elseif type(itemId) == "table" then
                count = item.count
                countText = item.quantityLabel or tostring(item.count or 0)
            else
                local counts = countInventory(player)
                count = counts[itemId]
                countText = "x" .. tostring(count or 0)
            end
            if count and (count > 1 or (type(itemId) == "table" and item.showCountBadge)) then
                local label = display.newText({
                    parent   = group,
                    text     = countText,
                    x        = x + size * 0.28,
                    y        = y + size * 0.28,
                    font     = ui.FONT_BOLD,
                    fontSize = (type(itemId) == "table" and #countText >= 4) and 10 or 12
                })
                label:setFillColor(0.6, 1.0, 1.0)
            end

            r:addEventListener("tap", function()
                if item.onTap then
                    return item.onTap() or true
                end
                showItemPopup(item)
                return true
            end)
        end
    else
        r:setFillColor(unpack(COLORS.emptyFill))
        r:setStrokeColor(unpack(COLORS.emptyStroke))
    end

    return r
end

-------------------------------------------------
-- ITEM POPUP
-------------------------------------------------
showItemPopup = function(item)
    if activePopup then
        activePopup:removeSelf()
        activePopup = nil
    end

    local player   = saveUtil.load()
    local equipped = isEquipped(player, item.id)

    local popupGroup = display.newGroup()
    sceneGroupRef:insert(popupGroup)
    activePopup = popupGroup

    local overlay = display.newRect(
        popupGroup,
        display.contentCenterX, display.contentCenterY,
        display.actualContentWidth, display.actualContentHeight
    )
    overlay:setFillColor(0, 0, 0, 0.72)
    overlay.isHitTestable = true
    overlay:addEventListener("touch", function() return true end)

    local content = display.newGroup()
    popupGroup:insert(content)

    local cx = display.contentCenterX
    local cy = display.contentCenterY
    local panelW = math.min(display.actualContentWidth - 30, 326)
    local panelH = 324

    local box = display.newRoundedRect(
        content,
        cx, cy,
        panelW, panelH, 8
    )
    box:setFillColor(0.015, 0.04, 0.11, 0.98)
    box.strokeWidth = 2
    box:setStrokeColor(unpack(equipped and COLORS.equippedStroke or COLORS.emptyNeonStroke))
    ui.addPopupShield(content, cx, cy, panelW, panelH)

    local title = display.newText({
        parent   = content,
        text     = item.name,
        x        = cx,
        y        = cy - panelH * 0.5 + 34,
        width    = panelW - 54,
        font     = ui.FONT_BOLD,
        fontSize = 15,
        align    = "center"
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
    end

    if item.description then
        local desc = display.newText({
            parent   = content,
            text     = item.description,
            x        = cx - 32,
            y        = cy - 70,
            width    = panelW - 166,
            font     = ui.FONT,
            fontSize = 11,
            align    = "left"
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
    local statColGap = 138
    local statCellH = 34
    for i = 1, math.min(4, #statEntries) do
        local entry = statEntries[i]
        local col = (i - 1) % 2
        local row = math.floor((i - 1) / 2)
        local sx = statsStartX + col * statColGap
        local sy = statsStartY + row * statCellH
        drawStatBanner(content, entry.stat, sx, sy, entry.text)
    end

    local actionY = cy + panelH * 0.5 - 34
    local sellPrice = math.floor((item.price or 0) * (item.sellPercent or 0.5))
    local isInjection = item.type == "injection"
    local canUpgrade = upgrades.hasTarget(item.id)

    local equipGroup = display.newGroup()
    content:insert(equipGroup)
    local equipX = cx + panelW * 0.5 - 68
    local equipBtn
    local okBtn, btnObj = pcall(display.newImageRect, equipGroup, "assets/sprites/ui/btn_nav.png", 60, 30)
    if okBtn and btnObj then
        equipBtn = btnObj
        equipBtn.x = equipX
        equipBtn.y = actionY
    else
        equipBtn = display.newRoundedRect(equipGroup, equipX, actionY, 60, 30, 7)
        equipBtn:setFillColor(0.05, 0.18, 0.42, 0.98)
        equipBtn.strokeWidth = 1
        equipBtn:setStrokeColor(0.26, 0.78, 1.0, 0.82)
    end

    local equipLabel = display.newText({
        parent   = equipGroup,
        text     = isInjection and "USE" or (equipped and "UNEQUIP" or "EQUIP"),
        x        = equipX,
        y        = actionY,
        font     = ui.FONT_BOLD,
        fontSize = 14
    })
    equipLabel:setFillColor(0.82, 0.96, 1.0)
    equipLabel.isHitTestable = false

    local sellGroup
    local putFirstChecked = false

    if item.slot == "weapon" and not equipped then
        local putFirstGroup = display.newGroup()
        content:insert(putFirstGroup)

        local boxX = cx - panelW * 0.5 + 32
        local boxY = actionY - 34
        local checkBox = display.newRoundedRect(putFirstGroup, boxX, boxY, 18, 18, 4)
        checkBox:setFillColor(0.02, 0.08, 0.18, 0.98)
        checkBox.strokeWidth = 1.5
        checkBox:setStrokeColor(0.28, 0.76, 1.0, 0.72)

        local checkMark = display.newText({
            parent=putFirstGroup, text="X",
            x=boxX, y=boxY,
            font=ui.FONT_BOLD, fontSize=12, align="center"
        })
        checkMark:setFillColor(0.72, 1.0, 0.80)
        checkMark.isVisible = false
        checkMark.isHitTestable = false

        local putFirstText = display.newText({
            parent=putFirstGroup, text="PUT FIRST",
            x=boxX + 16, y=boxY,
            width=110,
            font=ui.FONT_BOLD, fontSize=10, align="left"
        })
        putFirstText.anchorX = 0
        putFirstText:setFillColor(0.68, 0.86, 1.0)
        putFirstText.isHitTestable = false

        local function togglePutFirst()
            putFirstChecked = not putFirstChecked
            checkMark.isVisible = putFirstChecked
            checkBox:setFillColor(putFirstChecked and 0.05 or 0.02, putFirstChecked and 0.18 or 0.08, putFirstChecked and 0.24 or 0.18, 0.98)
            return true
        end

        checkBox:addEventListener("tap", togglePutFirst)
        putFirstGroup:addEventListener("tap", togglePutFirst)
    end

    if canUpgrade then
        local upgradeGroup = display.newGroup()
        content:insert(upgradeGroup)
        local upgradeX = cx + panelW * 0.5 - 66
        local upgradeY = cy - 72
        local upgradeBg
        local okUpgradeBtn, upgradeBtnObj = pcall(display.newImageRect, upgradeGroup, "assets/sprites/ui/btn_nav.png", 60, 30)
        if okUpgradeBtn and upgradeBtnObj then
            upgradeBg = upgradeBtnObj
            upgradeBg.x = upgradeX
            upgradeBg.y = upgradeY
        else
            upgradeBg = display.newRoundedRect(upgradeGroup, upgradeX, upgradeY, 60, 30, 6)
            upgradeBg:setFillColor(0.04, 0.15, 0.28, 0.92)
            upgradeBg.strokeWidth = 1
            upgradeBg:setStrokeColor(0.35, 0.90, 1.0, 0.70)
        end
        local upgradeText = display.newText({
            parent=upgradeGroup, text="UPGRADE",
            x=upgradeX, y=upgradeY,
            font=ui.FONT_BOLD, fontSize=9, align="center"
        })
        upgradeText:setFillColor(0.82, 0.96, 1.0)
        upgradeText.isHitTestable = false

        addNavTouch(upgradeGroup, upgradeBg, function()
            ui.popupClose(popupGroup, overlay, { content }, function()
                activePopup = nil
                composer.gotoScene("scenes.upgrades", {
                    effect="slideLeft",
                    time=200,
                    params={ sourceId=item.id }
                })
            end)
            return true
        end)
    end

    addNavTouch(equipGroup, equipBtn, function()
        local p    = saveUtil.load()
        local slot = item.slot
        if isInjection then
            local ok, message = injections.use(p, item)
            if not ok then
                native.showAlert("Injection", message or "This injection cannot be used yet.", { "OK" })
                return true
            end

            saveUtil.save(p)
            pushPlayerUpdate(p)
            ui.popupClose(popupGroup, overlay, { content }, function()
                activePopup = nil
                rebuildBag()
            end)
            return true
        end

        p.equipped = p.equipped or {}
        p.equipped.weapons = p.equipped.weapons or {}
        p.equipped.pets = p.equipped.pets or {}
        p.equipped.armor = p.equipped.armor or {}

        if equipped then
            if isCostumeItem(item) then
                p.appearance = p.appearance or {}
                if p.appearance.skinId == item.skinId then
                    p.appearance.skinId = nil
                end
                if p.skinId == item.skinId then
                    p.skinId = nil
                end
            elseif slot == "weapon" then
                for i = #p.equipped.weapons, 1, -1 do
                    if p.equipped.weapons[i] == item.id then
                        table.remove(p.equipped.weapons, i)
                    end
                end
            elseif slot == "pet" then
                for i = #p.equipped.pets, 1, -1 do
                    if p.equipped.pets[i] == item.id then
                        table.remove(p.equipped.pets, i)
                    end
                end
            elseif slot == "necklace" or slot == "ring" or slot == "charm" then
                p.equipped.accessories = p.equipped.accessories or {}
                if p.equipped.accessories[slot] == item.id then
                    p.equipped.accessories[slot] = nil
                end
            else
                if p.equipped.armor[slot] == item.id then
                    p.equipped.armor[slot] = nil
                end
            end
        else
            local owned = false
            for _, id in ipairs(p.inventory) do
                if id == item.id then owned = true; break end
            end
            if not owned then return true end

            if slot == "weapon" then
                if #p.equipped.weapons < WEAPON_SLOTS then
                    if putFirstChecked then
                        table.insert(p.equipped.weapons, 1, item.id)
                        p.currentWeaponIndex = 1
                    else
                        table.insert(p.equipped.weapons, item.id)
                        p.currentWeaponIndex = p.currentWeaponIndex or 1
                    end
                end
            elseif slot == "pet" then
                if #p.equipped.pets < spells.getMaxPetSlots(p) then
                    table.insert(p.equipped.pets, item.id)
                end
            elseif slot == "necklace" or slot == "ring" or slot == "charm" then
                p.equipped.accessories = p.equipped.accessories or {}
                p.equipped.accessories[slot] = item.id
            elseif isCostumeItem(item) then
                p.appearance = p.appearance or {}
                p.appearance.skinId = item.skinId
                p.skinId = item.skinId
            elseif slot == "helmet" or slot == "chest"
                or slot == "gloves" or slot == "boots" then
                p.equipped.armor[slot] = item.id
            end
        end

        saveUtil.save(p)
        pushPlayerUpdate(p)
        ui.popupClose(popupGroup, overlay, { content }, function()
            activePopup = nil
            rebuildBag()
        end)
    end)

    if not equipped then
        sellGroup = display.newGroup()
        content:insert(sellGroup)
        local sellX = cx - panelW * 0.5 + 145
        local sellY = actionY
        local sellBg
        local okSellBtn, sellBtnObj = pcall(display.newImageRect, sellGroup, "assets/sprites/ui/btn_nav.png", 60, 30)
        if okSellBtn and sellBtnObj then
            sellBg = sellBtnObj
            sellBg.x = sellX
            sellBg.y = sellY
        else
            sellBg = display.newRoundedRect(sellGroup, sellX, sellY, 60, 30, 6)
            sellBg:setFillColor(0.04, 0.11, 0.22, 0.92)
            sellBg.strokeWidth = 1
            sellBg:setStrokeColor(0.35, 0.72, 1.0, 0.60)
        end
        local sellText = display.newText({
            parent=sellGroup, text="SELL",
            x=sellX, y=sellY,
            font=ui.FONT_BOLD, fontSize=11, align="center"
        })
        sellText:setFillColor(0.82, 0.96, 1.0)
        sellText.isHitTestable = false

        local function confirmSell()
            local confirmGroup = display.newGroup()
            popupGroup:insert(confirmGroup)
            confirmGroup:toFront()

            local dim = display.newRect(
                confirmGroup,
                display.contentCenterX, display.contentCenterY,
                display.actualContentWidth, display.actualContentHeight
            )
            dim:setFillColor(0, 0, 0, 0.68)
            dim.isHitTestable = true
            dim:addEventListener("touch", function() return true end)
            dim:addEventListener("tap", function() return true end)

            local confirmContent = display.newGroup()
            confirmGroup:insert(confirmContent)

            local confirmW = math.min(display.actualContentWidth - 44, 286)
            local confirmH = 164
            local confirmPanel = display.newRoundedRect(confirmContent, cx, cy, confirmW, confirmH, 10)
            confirmPanel:setFillColor(0.015, 0.04, 0.11, 0.98)
            confirmPanel.strokeWidth = 2
            confirmPanel:setStrokeColor(0.25, 0.70, 1.0, 0.82)
            ui.addPopupShield(confirmContent, cx, cy, confirmW, confirmH)

            local titleText = display.newText({
                parent=confirmContent, text="SELL ITEM",
                x=cx, y=cy - 54,
                font=ui.FONT_BOLD, fontSize=14, align="center"
            })
            titleText:setFillColor(0.84, 0.96, 1.0)

            local bodyText = display.newText({
                parent=confirmContent,
                text="Are you sure to sell " .. tostring(item.name or item.id) .. " for " .. tostring(sellPrice) .. "?",
                x=cx, y=cy - 12,
                width=confirmW - 34,
                font=ui.FONT_BOLD, fontSize=11, align="center"
            })
            bodyText:setFillColor(0.70, 0.84, 1.0)

            local function makeConfirmButton(x, label, danger, onRelease)
                local group = display.newGroup()
                confirmContent:insert(group)
                local bg = display.newRoundedRect(group, x, cy + 48, 88, 32, 7)
                if danger then
                    bg:setFillColor(0.20, 0.06, 0.08, 0.96)
                    bg:setStrokeColor(1.0, 0.30, 0.30, 0.78)
                else
                    bg:setFillColor(0.04, 0.12, 0.30, 0.96)
                    bg:setStrokeColor(0.28, 0.72, 1.0, 0.72)
                end
                bg.strokeWidth = 1.5
                local txt = display.newText({
                    parent=group, text=label,
                    x=x, y=cy + 48,
                    font=ui.FONT_BOLD, fontSize=11, align="center"
                })
                txt:setFillColor(danger and 1.0 or 0.76, danger and 0.52 or 0.92, danger and 0.52 or 1.0)
                txt.isHitTestable = false
                addNavTouch(group, bg, onRelease)
            end

            makeConfirmButton(cx - 54, "CANCEL", false, function()
                ui.popupClose(confirmGroup, dim, { confirmContent })
            end)

            makeConfirmButton(cx + 54, "SELL", true, function()
                local p = saveUtil.load()
                p.gold = (p.gold or 0) + sellPrice

                for i = #p.inventory, 1, -1 do
                    if p.inventory[i] == item.id then
                        table.remove(p.inventory, i)
                        break
                    end
                end

                saveUtil.save(p)
                pushPlayerUpdate(p)
                ui.popupClose(popupGroup, overlay, { content }, function()
                    activePopup = nil
                    rebuildBag()
                end)
            end)

            ui.popupOpen(dim, { confirmContent }, { overlayAlpha = 0.68, startScale = 0.25, time = 150 })
        end

        addNavTouch(sellGroup, sellBg, function()
            confirmSell()
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
-- WEAPONS TAB
-------------------------------------------------
buildWeaponsTab = function(group)
    local player = saveUtil.load()
    player.equipped = player.equipped or {}
    player.equipped.weapons = player.equipped.weapons or {}
    local GRID   = 3
    local SIZE   = 72
    local PAD    = 6

    local equippedGroup = display.newGroup()
    group:insert(equippedGroup)
    equippedGroup.y = 14

    local startX = display.contentCenterX
        - ((GRID * SIZE + (GRID - 1) * PAD) * 0.5)
        + SIZE * 0.5

    for row = 1, GRID do
        for col = 1, GRID do
            local index    = (row - 1) * GRID + col
            local weaponId = player.equipped.weapons[index]
            local isActive = (index == player.currentWeaponIndex)
            local x = startX + (col - 1) * (SIZE + PAD)
            local y = 20 + (row - 1) * (SIZE + PAD)
            createSlot(equippedGroup, x, y, SIZE, weaponId, isActive, true)
        end
    end

    local inventory = collectInventoryByFilter(player, function(item)
        return item.slot == "weapon"
    end)
    createBagInventoryGrid(group, inventory)
end

-------------------------------------------------
-- ARMOR TAB
-------------------------------------------------
buildArmorTab = function(group)
    local player = saveUtil.load()
    local W = display.contentWidth
    local H = display.contentHeight

    player.equipped.accessories = player.equipped.accessories or {}

    local topGroup = display.newGroup()
    group:insert(topGroup)
    topGroup.y = -50

    local charX    = W * 0.5
    local slotSize = 56
    local offset   = 112
    local rowGap   = 102
    local helmetY  = H * 0.06
    local row1Y    = helmetY + 72
    local row2Y    = row1Y + rowGap
    local row3Y    = row2Y + rowGap

    local playerSkin = (player.appearance and player.appearance.skinId)
        or "street_brawler"

    local charGlow = display.newCircle(topGroup, charX, row2Y, 66)
    charGlow:setFillColor(0.05, 0.2, 0.7, 0.14)
    charGlow.strokeWidth = 0

    local spriteOk, charSprite = pcall(display.newImageRect,
        topGroup,
        "assets/sprites/characters/" .. playerSkin .. "/battle.png",
        128, 224)
    if spriteOk and charSprite then
        charSprite.x = charX
        charSprite.y = row2Y
    else
        local ph = display.newRect(topGroup, charX, row2Y, 100, 165)
        ph:setFillColor(0.2, 0.2, 0.25)
    end
    if spriteOk and charSprite then topGroup:insert(charSprite) end

    local function drawSlot(slotName, x, y, equippedId, fromRight)
        local lineX1 = fromRight and (x - slotSize*0.5 - 2) or (x + slotSize*0.5 + 2)
        local lineX2 = fromRight and (charX + 52) or (charX - 52)
        local conn = display.newLine(topGroup, lineX1, y, lineX2, y)
        conn:setStrokeColor(0.2, 0.5, 1, 0.22)
        conn.strokeWidth = 1

        createSlot(topGroup, x, y, slotSize, equippedId, false, true)

        display.newText({
            parent = topGroup, text = slotName:upper(),
            x = x, y = y + slotSize * 0.65,
            font = ui.FONT, fontSize = 9
        }):setFillColor(0.4, 0.7, 1)
    end

    local helmetId = player.equipped.armor["helmet"]
    createSlot(topGroup, charX, helmetY, slotSize, helmetId, false, true)
    display.newText({
        parent = topGroup, text = "HELMET",
        x = charX, y = helmetY + slotSize * 0.65,
        font = ui.FONT, fontSize = 9
    }):setFillColor(0.4, 0.7, 1)
    local vConn = display.newLine(topGroup, charX, helmetY + slotSize*0.5 + 2, charX, row1Y - 58)
    vConn:setStrokeColor(0.2, 0.5, 1, 0.22)
    vConn.strokeWidth = 1

    drawSlot("necklace", charX - offset, row1Y, player.equipped.accessories["necklace"], false)
    drawSlot("chest",    charX + offset, row1Y, player.equipped.armor["chest"],          true)
    drawSlot("ring",     charX - offset, row2Y, player.equipped.accessories["ring"],     false)
    drawSlot("gloves",   charX + offset, row2Y, player.equipped.armor["gloves"],         true)
    drawSlot("charm",    charX - offset, row3Y, player.equipped.accessories["charm"],    false)
    drawSlot("boots",    charX + offset, row3Y, player.equipped.armor["boots"],          true)

    local armorInventory = collectInventoryByFilter(player, function(item)
        return isArmorOrAccessorySlot(item.slot)
    end)
    createBagInventoryGrid(group, armorInventory)
end

-------------------------------------------------
-- COSTUMES TAB (coming soon)
-------------------------------------------------
buildAvatarTab = function(group)
    local player = saveUtil.load()
    local CX = display.contentCenterX

    local panel = display.newRoundedRect(group, CX, BAG_TOP_CENTER_Y + 10, 250, 112, 12)
    panel:setFillColor(0.03, 0.08, 0.22, 0.92)
    panel.strokeWidth = 1.5
    panel:setStrokeColor(0.30, 0.72, 1.0, 0.46)

    display.newText({
        parent = group, text = "COSTUMES",
        x = CX, y = BAG_TOP_CENTER_Y - 22,
        font = ui.FONT_BOLD, fontSize = 18, align = "center"
    }):setFillColor(0.3, 0.8, 1)

    local playerSkin = (player.appearance and player.appearance.skinId) or "street_brawler"
    local spriteOk, preview = pcall(display.newImageRect,
        group,
        "assets/sprites/characters/" .. playerSkin .. "/battle.png",
        80, 130
    )
    if spriteOk and preview then
        preview.x = CX - 62
        preview.y = BAG_TOP_CENTER_Y + 16
    end

    display.newText({
        parent = group,
        text = "Current skin:\n" .. string.upper(playerSkin:gsub("_", " ")),
        x = CX + 52,
        y = BAG_TOP_CENTER_Y - 2,
        width = 110,
        font = ui.FONT_BOLD,
        fontSize = 11,
        align = "center"
    }):setFillColor(0.84, 0.94, 1.0)

    display.newText({
        parent = group,
        text = (#collectInventoryByFilter(player, isCostumeItem) > 0)
            and "Owned costume items are shown below."
            or "No costume items yet.\nGrid stays ready.",
        x = CX + 52,
        y = BAG_TOP_CENTER_Y + 34,
        width = 120,
        font = ui.FONT,
        fontSize = 10,
        align = "center"
    }):setFillColor(0.52, 0.68, 0.84)

    local costumeInventory = collectInventoryByFilter(player, function(item)
        return isCostumeItem(item)
    end)
    createBagInventoryGrid(group, costumeInventory)
end

-------------------------------------------------
-- OTHER TAB 
-------------------------------------------------
buildOtherTab = function(group)
    local player = saveUtil.load()
    local otherEntries = buildOtherGridEntries(player)
    createBagInventoryGrid(group, otherEntries)
end

-------------------------------------------------
-- SCENE CREATE
-------------------------------------------------
function scene:create(event)
    local sceneGroup = self.view
    sceneGroupRef    = sceneGroup

    local bg = display.newImage("assets/sprites/ui/bg_home_grid.png")
    local scaleX = display.actualContentWidth  / bg.width
    local scaleY = display.actualContentHeight / bg.height
    bg:scale(math.max(scaleX, scaleY), math.max(scaleX, scaleY))
    bg.x = display.contentCenterX
    bg.y = display.contentCenterY
    bg.isHitTestable = false
    sceneGroup:insert(bg)

    buildAmbientDots(sceneGroup, display.actualContentWidth, display.actualContentHeight)
    buildFallingSparkles(sceneGroup, display.actualContentWidth, display.actualContentHeight)

    local player = saveUtil.load()
    player.inventory        = player.inventory or {}
    player.equipped         = player.equipped  or {}
    player.equipped.weapons = player.equipped.weapons or {}
    player.equipped.armor   = player.equipped.armor   or {}
    player.equipped.pets    = player.equipped.pets    or {}
    player.equipped.accessories = player.equipped.accessories or {}

    local cleaned = {}
    for _, id in ipairs(player.equipped.weapons) do
        if id and items[id] then table.insert(cleaned, id) end
    end
    player.equipped.weapons = cleaned
    player.currentWeaponIndex = #player.equipped.weapons == 0
        and nil
        or math.min(player.currentWeaponIndex or 1, #player.equipped.weapons)
    saveUtil.save(player)
    pushPlayerUpdate(player)

    -------------------------------------------------
    -- TAB BAR — 4 icon buttons, single row at bottom
    -------------------------------------------------
    local tabBar  = display.newGroup()
    sceneGroup:insert(tabBar)
    tabButtons = {}

    local H      = display.contentHeight
    local btnW   = 48
    local btnH   = 48
    local iconSz = 34
    local tabY   = H + 18
    local centerX = display.contentCenterX
    local radialSpacing = 76
    local sideGap = 64
    local tabXs = {
        centerX + radialSpacing,
        centerX + radialSpacing + sideGap,
        centerX - radialSpacing - sideGap,
        centerX - radialSpacing,
    }

    for i, t in ipairs(TABS) do
        local x   = tabXs[i]
        local grp = display.newGroup()
        tabBar:insert(grp)

        -- dark pill background
        local bg2 = display.newRoundedRect(grp, x, tabY, btnW, btnH, 12)
        bg2:setFillColor(0.05, 0.10, 0.25, 0.90)
        bg2.strokeWidth = 1.5
        bg2:setStrokeColor(0.3, 0.6, 1.0, 0.5)

        -- active glow ring
        local glow = display.newRoundedRect(grp, x, tabY, btnW + 6, btnH + 6, 12)
        glow:setFillColor(0, 0, 0, 0)
        glow.strokeWidth = 2
        glow:setStrokeColor(0.3, 0.9, 1.0, 0.9)
        glow.isVisible = false
        flicker(glow, 0.18, 0.72, math.random(180, 340))

        -- icon
        local iconImg = display.newImageRect(grp, t.icon, iconSz, iconSz)
        iconImg.x = x
        iconImg.y = tabY

        local function onTap()
            activeTab = t.key
            composer.setVariable("bagTab", t.key)
            rebuildBag()
            return true
        end
        bg2:addEventListener("tap", onTap)
        iconImg:addEventListener("tap", onTap)

        table.insert(tabButtons, {
            key     = t.key,
            bg      = bg2,
            glow    = glow,
            iconImg = iconImg,
        })
    end

    local dockLineLeft = display.newRoundedRect(tabBar, centerX - 64, tabY, 38, 2, 2)
    dockLineLeft:setFillColor(0.22, 0.62, 1.0, 0.16)
    local dockLineRight = display.newRoundedRect(tabBar, centerX + 64, tabY, 38, 2, 2)
    dockLineRight:setFillColor(0.22, 0.62, 1.0, 0.16)

    showRadial = function()
        radialMenu.show(sceneGroup, {
            activeScene = "bag",
            inner       = RADIAL_INNER,
            outer       = RADIAL_OUTER,
        })
    end

    rebuildBag()
end

-------------------------------------------------
-- SCENE SHOW
-------------------------------------------------
function scene:show(event)
    if event.phase ~= "did" then return end

    activeTab = composer.getVariable("bagTab") or activeTab or "weapons"
    rebuildBag()
end

-------------------------------------------------
-- SCENE HIDE
-------------------------------------------------
function scene:hide(event)
    if event.phase ~= "will" then return end
    radialMenu.destroy()
    if activePopup then
        activePopup:removeSelf()
        activePopup = nil
    end
end

scene:addEventListener("create", scene)
scene:addEventListener("show",   scene)
scene:addEventListener("hide",   scene)

return scene
