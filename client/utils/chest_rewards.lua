local ui = require("utils.ui")

local M = {}
local notifications = require("utils.notifications")
local items = require("utils.items")

local CHESTS = {
    common = {
        id = "common",
        chance = 0.10,
        gold = 100,
        xp = 10,
        title = "COMMON CHEST",
        image = "assets/sprites/materials/common_chest.png",
        beamColor = { 1.0, 0.78, 0.18, 0.28 },
        accent = { 1.0, 0.84, 0.24, 0.90 },
    },
    rare = {
        id = "rare",
        chance = 0.05,
        gold = 500,
        xp = 50,
        title = "RARE CHEST",
        image = "assets/sprites/materials/rare_chest.png",
        beamColor = { 0.34, 0.88, 1.0, 0.30 },
        accent = { 0.50, 0.92, 1.0, 0.95 },
    },
}

local function getCommonItemPool()
    local pool = {}
    for id, def in pairs(items or {}) do
        if def and (def.price or 0) <= 500 then
            pool[#pool + 1] = id
        end
    end
    table.sort(pool, function(a, b)
        local pa = (items[a] and items[a].price) or 0
        local pb = (items[b] and items[b].price) or 0
        if pa ~= pb then return pa < pb end
        return a < b
    end)
    return pool
end

local function rollCommonReward()
    local pool = getCommonItemPool()
    if #pool == 0 or math.random() <= 0.55 then
        return { kind = "gold", amount = CHESTS.common.gold }
    end

    local itemId = pool[math.random(#pool)]
    return {
        kind = "item",
        itemId = itemId,
        item = items[itemId],
    }
end

local function rewardLabel(reward)
    if not reward then return "" end
    if reward.kind == "gold" then
        return "+" .. tostring(reward.amount or 0) .. " GOLD"
    end
    local def = reward.item or (reward.itemId and items[reward.itemId]) or {}
    local prefix = reward.amount and reward.amount > 1 and ("x" .. tostring(reward.amount) .. " ") or ""
    return prefix .. (def.name or tostring(reward.itemId or "Item"))
end

local function rewardIconPath(reward)
    if reward and reward.kind == "item" then
        local def = reward.item or (reward.itemId and items[reward.itemId]) or nil
        return def and def.icon or nil
    end
    return "assets/sprites/ui/icons/gold.png"
end

local function rewardQualityLabel(chestDef, reward)
    if reward and reward.kind == "item" then
        local def = reward.item or (reward.itemId and items[reward.itemId]) or nil
        return string.upper(tostring((def and (def.rarity or def.quality)) or chestDef.id or "ITEM"))
    end
    return string.upper(tostring(chestDef.id or "REWARD"))
end

local function grantChestReward(player, chestDef)
    if chestDef.id == "common" then
        local reward = rollCommonReward()
        if reward.kind == "gold" then
            player.gold = (player.gold or 0) + (reward.amount or 0)
        else
            local def = reward.item or (reward.itemId and items[reward.itemId]) or nil
            local materialKey = def and def.materialKey
            local amount = (materialKey == "scrap" or materialKey == "coil" or materialKey == "chip") and 10 or 1
            reward.amount = amount
            if materialKey then
                player.materials = player.materials or {}
                player.materials[materialKey] = (player.materials[materialKey] or 0) + amount
            else
                player.inventory = player.inventory or {}
                table.insert(player.inventory, reward.itemId)
            end
        end
        return reward
    end

    player.gold = (player.gold or 0) + chestDef.gold
    player.xp = (player.xp or 0) + (chestDef.xp or 0)
    return { kind = "gold", amount = chestDef.gold }
end

local function showRewardGridPopup(chestDef, rewards, onClose)
    local SW = display.actualContentWidth
    local SH = display.actualContentHeight
    local CX = display.contentCenterX
    local CY = display.contentCenterY

    local popup = display.newGroup()
    display.getCurrentStage():insert(popup)

    local dim = display.newRect(popup, CX, CY, SW, SH)
    dim:setFillColor(0, 0, 0, 0.78)
    dim.isHitTestable = true
    dim:addEventListener("touch", function() return true end)

    local panelW = math.min(SW - 30, 330)
    local panelH = 430
    local glow = display.newRoundedRect(popup, CX, CY, panelW + 8, panelH + 8, 16)
    glow:setFillColor(0, 0, 0, 0)
    glow.strokeWidth = 3
    glow:setStrokeColor(chestDef.accent[1], chestDef.accent[2], chestDef.accent[3], 0.36)

    local panel = display.newRoundedRect(popup, CX, CY, panelW, panelH, 14)
    panel:setFillColor(0.02, 0.06, 0.16, 0.98)
    panel.strokeWidth = 2
    panel:setStrokeColor(0.28, 0.76, 1.0, 0.82)

    local title = display.newText({
        parent = popup,
        text = chestDef.title,
        x = CX,
        y = CY - 184,
        width = panelW - 28,
        font = ui.FONT_BOLD,
        fontSize = 17,
        align = "center",
    })
    title:setFillColor(chestDef.accent[1], chestDef.accent[2], chestDef.accent[3])

    local gridGroup = display.newGroup()
    popup:insert(gridGroup)
    local cols = 2
    local slot = 68
    local gapX = 18
    local gapY = 8
    local startX = CX - ((cols * slot + (cols - 1) * gapX) * 0.5) + slot * 0.5
    local startY = CY - 136

    for i = 1, 10 do
        local col = (i - 1) % cols
        local row = math.floor((i - 1) / cols)
        local x = startX + col * (slot + gapX)
        local y = startY + row * (slot + gapY)
        local reward = rewards[i]

        local yay = display.newImageRect(gridGroup, "assets/sprites/ui/icons/yay.png", 90, 90)
        yay.x = x
        yay.y = y
        yay.alpha = reward and 0.82 or 0.16

        local frame = display.newRoundedRect(gridGroup, x, y, slot, slot, 7)
        frame:setFillColor(0.03, 0.08, 0.18, reward and 0.94 or 0.52)
        frame.strokeWidth = 1.5
        frame:setStrokeColor(chestDef.accent[1], chestDef.accent[2], chestDef.accent[3], reward and 0.85 or 0.22)

        if reward then
            local iconPath = rewardIconPath(reward)
            local icon
            if iconPath then
                icon = display.newImageRect(gridGroup, iconPath, 44, 44)
                icon.x = x
                icon.y = y - 3
            end
            local label = display.newText({
                parent = gridGroup,
                text = reward.amount and reward.amount > 1 and ("x" .. tostring(reward.amount))
                    or (reward.kind == "gold" and ("+" .. tostring(reward.amount or 0)) or rewardQualityLabel(chestDef, reward)),
                x = x,
                y = y + 25,
                width = slot - 4,
                font = ui.FONT_BOLD,
                fontSize = reward.kind == "gold" and 8 or 6,
                align = "center",
            })
            label:setFillColor(reward.kind == "gold" and 1.0 or 0.78, reward.kind == "gold" and 0.86 or 0.94, reward.kind == "gold" and 0.28 or 1.0)
        end
    end

    local collectGroup = display.newGroup()
    popup:insert(collectGroup)
    local collectButtonW = 90
    local collectButtonH = 75
    local btnY = CY + 188
    local okFrame, collectBtn = pcall(display.newImageRect, collectGroup, "assets/sprites/ui/btn_nav.png", collectButtonW, collectButtonH)
    if okFrame and collectBtn then
        collectBtn.x = CX
        collectBtn.y = btnY
    else
        collectBtn = display.newRoundedRect(collectGroup, CX, btnY, collectButtonW, collectButtonH, 8)
        collectBtn:setFillColor(0.06, 0.18, 0.45, 0.98)
        collectBtn.strokeWidth = 1.5
        collectBtn:setStrokeColor(0.30, 0.72, 1.0, 0.78)
    end
    local collectText = display.newText({
        parent = collectGroup,
        text = "COLLECT",
        x = CX,
        y = btnY,
        font = ui.FONT_BOLD,
        fontSize = 13,
    })
    collectText:setFillColor(0.86, 0.96, 1.0)

    local closing = false
    local function closePopup()
        if closing then return true end
        closing = true
        return ui.popupClose(popup, dim, { glow, panel, title, gridGroup, collectGroup }, onClose)
    end

    collectBtn:addEventListener("touch", function(event)
        if event.phase == "began" then
            local okPressed = pcall(function()
                collectBtn.fill = { type="image", filename="assets/sprites/ui/btn_nav_pressed.png" }
            end)
            if not okPressed then collectBtn.alpha = 0.75 end
            display.getCurrentStage():setFocus(collectBtn)
            collectBtn._hasFocus = true
        elseif collectBtn._hasFocus and (event.phase == "ended" or event.phase == "cancelled") then
            display.getCurrentStage():setFocus(nil)
            collectBtn._hasFocus = false
            pcall(function()
                collectBtn.fill = { type="image", filename="assets/sprites/ui/btn_nav.png" }
            end)
            collectBtn.alpha = 1
            if event.phase == "ended" then closePopup() end
        end
        return true
    end)

    ui.popupOpen(dim, { glow, panel, title, gridGroup, collectGroup }, { overlayAlpha = 0.78, startScale = 0.2, time = 170 })
end

local function spawnParticles(parent, cx, cy, color)
    for i = 1, 16 do
        local particle = display.newCircle(parent, cx, cy - 24, math.random(2, 4))
        particle:setFillColor(color[1], color[2], color[3], 0.95)
        particle.isHitTestable = false
        transition.to(particle, {
            x = cx + math.random(-90, 90),
            y = cy - 70 + math.random(-40, 40),
            alpha = 0,
            time = 700 + math.random(0, 360),
            transition = easing.outQuad,
            onComplete = function()
                if particle and particle.removeSelf then particle:removeSelf() end
            end
        })
    end
end

local function showChestPopup(chestDef, reward, onClose)
    local SW = display.actualContentWidth
    local SH = display.actualContentHeight
    local CX = display.contentCenterX
    local CY = display.contentCenterY

    local popup = display.newGroup()
    display.getCurrentStage():insert(popup)

    local dim = display.newRect(popup, CX, CY, SW, SH)
    dim:setFillColor(0, 0, 0, 0.78)
    dim.isHitTestable = true
    dim:addEventListener("touch", function() return true end)

    local panelW = math.min(SW - 54, 250)
    local panelH = 316

    local glow = display.newRoundedRect(popup, CX, CY, panelW + 8, panelH + 8, 16)
    glow:setFillColor(0, 0, 0, 0)
    glow.strokeWidth = 3
    glow:setStrokeColor(chestDef.accent[1], chestDef.accent[2], chestDef.accent[3], 0.34)

    local panel = display.newRoundedRect(popup, CX, CY, panelW, panelH, 14)
    panel:setFillColor(0.02, 0.06, 0.16, 0.98)
    panel.strokeWidth = 2
    panel:setStrokeColor(0.28, 0.76, 1.0, 0.82)

    local title = display.newText({
        parent = popup,
        text = chestDef.title,
        x = CX,
        y = CY - 126,
        width = panelW - 30,
        font = ui.FONT_BOLD,
        fontSize = 17,
        align = "center",
    })
    title:setFillColor(chestDef.accent[1], chestDef.accent[2], chestDef.accent[3])

    local yay = display.newImageRect(popup, "assets/sprites/ui/icons/yay.png", 174, 174)
    yay.x = CX
    yay.y = CY - 34
    yay.alpha = 0.95
    yay.isHitTestable = false

    local rewardSquare = display.newRoundedRect(popup, CX, CY - 34, 106, 106, 8)
    rewardSquare:setFillColor(0.03, 0.08, 0.18, 0.90)
    rewardSquare.strokeWidth = 2
    rewardSquare:setStrokeColor(chestDef.accent[1], chestDef.accent[2], chestDef.accent[3], 0.90)

    local rewardIcon
    local iconPath = rewardIconPath(reward)
    if iconPath then
        rewardIcon = display.newImageRect(popup, iconPath, 70, 70)
        rewardIcon.x = CX
        rewardIcon.y = CY - 34
    end

    spawnParticles(popup, CX, CY - 34, chestDef.accent)

    local quality = display.newText({
        parent = popup,
        text = rewardQualityLabel(chestDef, reward),
        x = CX,
        y = CY + 38,
        font = ui.FONT_BOLD,
        fontSize = 11,
    })
    quality:setFillColor(chestDef.accent[1], chestDef.accent[2], chestDef.accent[3])

    local rewardText = display.newText({
        parent = popup,
        text = rewardLabel(reward),
        x = CX,
        y = CY + 62,
        width = panelW - 32,
        font = ui.FONT_BOLD,
        fontSize = 12,
        align = "center",
    })
    rewardText:setFillColor(reward and reward.kind == "gold" and 1.0 or 0.84, reward and reward.kind == "gold" and 0.86 or 0.96, reward and reward.kind == "gold" and 0.28 or 1.0)

    local okBtn = display.newRoundedRect(popup, CX, CY + 120, 120, 36, 8)
    okBtn:setFillColor(0.08, 0.42, 0.16, 0.97)
    okBtn.strokeWidth = 1.5
    okBtn:setStrokeColor(0.22, 0.88, 0.32, 0.90)
    local okText = display.newText({
        parent = popup,
        text = "OPENED",
        x = CX,
        y = CY + 120,
        font = ui.FONT_BOLD,
        fontSize = 13,
    })
    okText:setFillColor(0.44, 1.0, 0.56)

    local function closePopup()
        return ui.popupClose(popup, dim, { glow, panel, title, yay, rewardSquare, rewardIcon, quality, rewardText, okBtn, okText }, onClose)
    end

    ui.popupOpen(dim, { glow, panel, title, yay, rewardSquare, rewardIcon, quality, rewardText, okBtn, okText }, { overlayAlpha = 0.78, startScale = 0.2, time = 170 })
    dim:addEventListener("tap", closePopup)
    okBtn:addEventListener("tap", closePopup)
end

local function showDropPopup(parent, chestDef, onClose)
    local host = parent or display.getCurrentStage()
    local SW = display.actualContentWidth
    local SH = display.actualContentHeight
    local CX = display.contentCenterX
    local CY = display.contentCenterY

    local popup = display.newGroup()
    host:insert(popup)

    local dim = display.newRect(popup, CX, CY, SW, SH)
    dim:setFillColor(0, 0, 0, 0.78)
    dim.isHitTestable = true
    dim:addEventListener("touch", function() return true end)

    local yay = display.newImageRect(popup, "assets/sprites/ui/icons/yay.png", 220, 220)
    yay.x = CX
    yay.y = CY - 6
    yay.alpha = 0.92
    yay.xScale, yay.yScale = 0.25, 0.25

    local chest = display.newImageRect(popup, chestDef.image, 138, 104)
    chest.x = CX
    chest.y = CY - 4
    chest.alpha = 0.0
    chest.xScale, chest.yScale = 0.25, 0.25

    local title = display.newText({
        parent = popup,
        text = chestDef.title,
        x = CX,
        y = CY + 92,
        width = 220,
        font = ui.FONT_BOLD,
        fontSize = 18,
        align = "center",
    })
    title:setFillColor(chestDef.accent[1], chestDef.accent[2], chestDef.accent[3])
    title.alpha = 0

    local sub = display.newText({
        parent = popup,
        text = "TAP TO COLLECT",
        x = CX,
        y = CY + 122,
        font = ui.FONT_BOLD,
        fontSize = 11,
        align = "center",
    })
    sub:setFillColor(0.82, 0.94, 1.0)
    sub.alpha = 0

    transition.to(yay, {
        xScale = 1.0, yScale = 1.0, alpha = 1.0,
        time = 180, transition = easing.outBack
    })
    timer.performWithDelay(40, function()
        if not chest or not chest.removeSelf then return end
        transition.to(chest, {
            xScale = 1.0, yScale = 1.0, alpha = 1.0,
            time = 220, transition = easing.outBack
        })
        transition.to(title, { alpha = 1.0, time = 150 })
        transition.to(sub, { alpha = 0.92, time = 150 })
    end)

    local closing = false
    local function collect()
        if closing then return true end
        closing = true
        transition.to(yay, { xScale = 0.05, yScale = 0.05, alpha = 0, time = 140, transition = easing.inBack })
        transition.to(chest, { xScale = 0.05, yScale = 0.05, alpha = 0, time = 140, transition = easing.inBack })
        transition.to(title, { alpha = 0, time = 100 })
        transition.to(sub, { alpha = 0, time = 100 })
        timer.performWithDelay(160, function()
            if popup and popup.removeSelf then popup:removeSelf() end
            if onClose then onClose() end
        end)
        return true
    end

    dim:addEventListener("tap", collect)
end

function M.rollForFight()
    local unlocked = {}
    if math.random() < CHESTS.common.chance then
        unlocked[#unlocked + 1] = CHESTS.common
    end
    if math.random() < CHESTS.rare.chance then
        unlocked[#unlocked + 1] = CHESTS.rare
    end
    return unlocked
end

function M.rollForFightAll(results)
    local unlocked = {}
    for _, result in ipairs(results or {}) do
        if result and result.won then
            local drops = M.rollForFight()
            for _, chest in ipairs(drops) do
                unlocked[#unlocked + 1] = chest
            end
        end
    end
    return unlocked
end

function M.ensureInventory(player)
    player.chests = player.chests or { common = 0, rare = 0 }
    player.chests.common = player.chests.common or 0
    player.chests.rare = player.chests.rare or 0
    return player.chests
end

function M.enqueueDrops(player, chests)
    local inventory = M.ensureInventory(player)
    local added = { common = 0, rare = 0 }

    for _, chest in ipairs(chests or {}) do
        if chest and chest.id and inventory[chest.id] ~= nil then
            inventory[chest.id] = inventory[chest.id] + 1
            added[chest.id] = (added[chest.id] or 0) + 1
        end
    end

    return added
end

function M.getDef(chestId)
    return CHESTS[chestId]
end

function M.openChest(player, chestId, xpUtil, levelUpPopup, onComplete)
    return M.openChests(player, chestId, 1, xpUtil, levelUpPopup, onComplete)
end

function M.openChests(player, chestId, count, xpUtil, levelUpPopup, onComplete)
    local inventory = M.ensureInventory(player)
    local chestDef = CHESTS[chestId]
    if not chestDef or (inventory[chestId] or 0) <= 0 then
        if onComplete then onComplete(false) end
        return false
    end

    count = math.max(1, math.min(10, math.floor(tonumber(count) or 1), inventory[chestId] or 0))
    local rewards = {}
    for _ = 1, count do
        inventory[chestId] = inventory[chestId] - 1
        rewards[#rewards + 1] = grantChestReward(player, chestDef)
    end

    local levelSummary = nil
    if chestId ~= "common" and count > 0 and levelUpPopup and xpUtil then
        levelSummary = levelUpPopup.applyLevelUps(player, xpUtil)
        if levelSummary then
            notifications.addLevelUp(player, levelSummary)
        end
    end

    local function afterRewardPopup()
        if levelSummary and levelUpPopup then
            levelUpPopup.show(levelSummary, function()
                if onComplete then onComplete(true, chestDef, levelSummary, rewards) end
            end)
        else
            if onComplete then onComplete(true, chestDef, levelSummary, rewards) end
        end
    end

    if count == 1 then
        showChestPopup(chestDef, rewards[1], afterRewardPopup)
    else
        showRewardGridPopup(chestDef, rewards, afterRewardPopup)
    end

    return true, chestDef, levelSummary
end

function M.describeAdded(added)
    local parts = {}
    if (added.common or 0) > 0 then
        parts[#parts + 1] = tostring(added.common) .. " Common"
    end
    if (added.rare or 0) > 0 then
        parts[#parts + 1] = tostring(added.rare) .. " Rare"
    end
    return table.concat(parts, ", ")
end

function M.showSequence(parent, chests, onClose)
    if type(parent) ~= "table" or not parent.removeSelf then
        onClose = chests
        chests = parent
        parent = nil
    end

    if not chests or #chests == 0 then
        if onClose then onClose() end
        return
    end

    local orderedChests = {}
    for _, chest in ipairs(chests) do
        if chest and chest.id == "common" then
            orderedChests[#orderedChests + 1] = chest
        end
    end
    for _, chest in ipairs(chests) do
        if chest and chest.id == "rare" then
            orderedChests[#orderedChests + 1] = chest
        end
    end
    for _, chest in ipairs(chests) do
        if chest and chest.id ~= "common" and chest.id ~= "rare" then
            orderedChests[#orderedChests + 1] = chest
        end
    end
    chests = orderedChests

    local index = 1
    local function step()
        local chestDef = chests[index]
        if not chestDef then
            if onClose then onClose() end
            return
        end

        showDropPopup(parent, chestDef, function()
            index = index + 1
            timer.performWithDelay(120, step)
        end)
    end

    step()
end

return M
