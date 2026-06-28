local tasksUtil = require("utils.tasks")
local saveUtil = require("utils.save")
local xpUtil = require("utils.xp")
local ui = require("utils.ui")
local levelUpPopup = require("utils.levelup_popup")
local notifications = require("utils.notifications")

local M = {}

local function applyLevelUps(player)
    local summary = levelUpPopup.applyLevelUps(player, xpUtil)
    if summary then
        notifications.addLevelUp(player, summary)
    end
    return summary ~= nil
end

local function makeRewardCard(parent, centerX, y, entry, cardW)
    local cardH = 74
    local cardBg = display.newRoundedRect(parent, centerX, y, cardW, cardH, 10)
    cardBg:setFillColor(0.04, 0.12, 0.24, 0.97)
    cardBg.strokeWidth = 1.5
    cardBg:setStrokeColor(0.26, 0.74, 1.0, 0.65)

    local iconBox = display.newRoundedRect(parent, centerX - cardW * 0.5 + 30, y, 42, 42, 8)
    iconBox:setFillColor(0.05, 0.18, 0.30, 0.96)
    iconBox.strokeWidth = 1.5
    iconBox:setStrokeColor(0.28, 0.80, 1.0, 0.60)

    local okTaskIcon, taskIcon = pcall(
        display.newImageRect,
        parent,
        "assets/sprites/ui/icons/" .. (entry.def.icon or "fight") .. ".png",
        22, 22
    )
    if okTaskIcon and taskIcon then
        taskIcon.x = iconBox.x
        taskIcon.y = iconBox.y
        taskIcon.isHitTestable = false
    end

    local title = display.newText({
        parent = parent,
        text = string.upper(entry.def.title or "TASK COMPLETE"),
        x = centerX - cardW * 0.5 + 62,
        y = y - 16,
        width = cardW - 120,
        font = ui.FONT_BOLD,
        fontSize = 12,
        align = "left",
    })
    title.anchorX = 0
    title:setFillColor(0.84, 0.96, 1.0)

    local message = display.newText({
        parent = parent,
        text = entry.message or "Objective completed.",
        x = centerX - cardW * 0.5 + 62,
        y = y + 2,
        width = cardW - 120,
        font = ui.FONT,
        fontSize = 10,
        align = "left",
    })
    message.anchorX = 0
    message:setFillColor(0.70, 0.84, 0.96)

    local xpIcon = display.newImageRect(parent, "assets/sprites/ui/icons/lvelup.png", 16, 16)
    xpIcon.x = centerX - 34
    xpIcon.y = y + 22
    xpIcon.isHitTestable = false

    local xpText = display.newText({
        parent = parent,
        text = "+" .. tostring(entry.xpGain) .. " XP",
        x = centerX - 8,
        y = y + 22,
        font = ui.FONT_BOLD,
        fontSize = 10,
        align = "left",
    })
    xpText.anchorX = 0
    xpText:setFillColor(0.55, 0.92, 1.0)

    local goldIcon = display.newImageRect(parent, "assets/sprites/ui/icons/gold.png", 16, 16)
    goldIcon.x = centerX + 54
    goldIcon.y = y + 22
    goldIcon.isHitTestable = false

    local goldText = display.newText({
        parent = parent,
        text = "+" .. tostring(entry.goldGain) .. " GOLD",
        x = centerX + 80,
        y = y + 22,
        font = ui.FONT_BOLD,
        fontSize = 10,
        align = "left",
    })
    goldText.anchorX = 0
    goldText:setFillColor(1.0, 0.86, 0.28)
end

local function showPopup(sceneView, completedEntries, onClose)
    if not sceneView or not completedEntries or #completedEntries == 0 then
        if onClose then onClose(completedEntries or {}) end
        return
    end

    local SW = display.actualContentWidth
    local SH = display.actualContentHeight
    local CX = display.contentCenterX
    local CY = display.contentCenterY

    local popup = display.newGroup()
    display.getCurrentStage():insert(popup)

    local dim = display.newRect(popup, CX, CY, SW, SH)
    dim:setFillColor(0, 0, 0, 0.76)
    dim.isHitTestable = true

    local panelW = math.min(SW - 30, 320)
    local panelH = 180 + math.max(0, (#completedEntries - 1) * 82)
    local panelY = CY

    local glow = display.newRoundedRect(popup, CX, panelY, panelW + 8, panelH + 8, 16)
    glow:setFillColor(0, 0, 0, 0)
    glow.strokeWidth = 3
    glow:setStrokeColor(0.22, 0.86, 1.0, 0.28)

    local okBurst, burst = pcall(display.newImageRect, popup, "assets/sprites/ui/icons/yay.png", 140, 90)
    if okBurst and burst then
        burst.x = CX
        burst.y = panelY - panelH * 0.5 + 26
        burst.alpha = 0.95
        burst.isHitTestable = false
    end

    local panel = display.newRoundedRect(popup, CX, panelY, panelW, panelH, 14)
    panel:setFillColor(0.02, 0.06, 0.16, 0.98)
    panel.strokeWidth = 2
    panel:setStrokeColor(0.25, 0.75, 1.0, 0.80)

    local topBar = display.newRoundedRect(popup, CX, panelY - panelH * 0.5 + 3, panelW - 10, 4, 2)
    topBar:setFillColor(0.28, 0.90, 1.0, 0.78)

    local title = display.newText({
        parent = popup,
        text = (#completedEntries > 1) and "TASKS COMPLETE" or "TASK COMPLETE",
        x = CX,
        y = panelY - panelH * 0.5 + 26,
        width = panelW - 30,
        font = ui.FONT_BOLD,
        fontSize = 18,
        align = "center",
    })
    title:setFillColor(0.90, 0.98, 1.0)

    local firstCardY = panelY - panelH * 0.5 + 82
    for i, entry in ipairs(completedEntries) do
        makeRewardCard(popup, CX, firstCardY + (i - 1) * 82, entry, panelW - 26)
    end

    local okY = panelY + panelH * 0.5 - 28
    local okBtn = display.newRoundedRect(popup, CX, okY, 116, 34, 8)
    okBtn:setFillColor(0.08, 0.40, 0.16, 0.97)
    okBtn.strokeWidth = 1.5
    okBtn:setStrokeColor(0.22, 0.88, 0.32, 0.90)

    local okText = display.newText({
        parent = popup,
        text = "NICE",
        x = CX,
        y = okY,
        font = ui.FONT_BOLD,
        fontSize = 13,
    })
    okText:setFillColor(0.44, 1.0, 0.56)

    local function closePopup()
        return ui.popupClose(popup, dim, { glow, burst, panel, topBar, title, okBtn, okText }, function()
            if onClose then onClose(completedEntries) end
        end)
    end

    ui.popupOpen(dim, { glow, burst, panel, topBar, title, okBtn, okText }, { overlayAlpha = 0.76, startScale = 0.2, time = 170 })
    dim:addEventListener("tap", closePopup)
    okBtn:addEventListener("tap", closePopup)
end

function M.process(sceneView, player, updates, onClose)
    tasksUtil.init(player)

    local completedEntries = {}
    for _, update in ipairs(updates or {}) do
        if tasksUtil.advance(player, update.id, update.amount or 1) then
            local xpGain, goldGain = tasksUtil.claim(player, update.id)
            if xpGain then
                completedEntries[#completedEntries + 1] = {
                    def = tasksUtil.BY_ID[update.id],
                    xpGain = xpGain,
                    goldGain = goldGain,
                    message = update.message,
                }
            end
        end
    end

    if #completedEntries == 0 then
        return false, {}
    end

    applyLevelUps(player)
    saveUtil.save(player)
    showPopup(sceneView, completedEntries, onClose)
    return true, completedEntries
end

return M
