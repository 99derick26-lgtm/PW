local composer = require("composer")
local scene = composer.newScene()

local saveUtil = require("utils.save")
local sync = require("utils.sync")
local items = require("utils.items")
local ui = require("utils.ui")
local upgrades = require("utils.upgrades")

local sceneGroupRef
local contentGroup
local sourceId
local selectedTarget

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

local function formatStatSummary(item)
    if not item or not item.statPercent then return "" end

    local labels = {
        { key="attack", label="ATK" },
        { key="hp", label="HP" },
        { key="defense", label="DEF" },
        { key="speed", label="SPD" },
    }
    local parts = {}
    for _, entry in ipairs(labels) do
        local value = item.statPercent[entry.key]
        if value ~= nil then
            parts[#parts + 1] = entry.label .. " " .. (
                type(value) == "table"
                    and formatPercentRange(value.min, value.max)
                    or formatPercentValue(value)
            )
        end
    end
    return table.concat(parts, "  ")
end

local function drawButton(parent, x, y, label, enabled, onTap)
    local group = display.newGroup()
    parent:insert(group)

    local bg
    local ok, img = pcall(display.newImageRect, group, "assets/sprites/ui/btn_nav.png", 104, 116)
    if ok and img then
        bg = img
        bg.x = x
        bg.y = y
        bg.alpha = enabled and 1 or 0.42
    else
        bg = display.newRoundedRect(group, x, y, 112, 34, 7)
        bg:setFillColor(enabled and 0.04 or 0.05, enabled and 0.16 or 0.07, enabled and 0.34 or 0.12, 0.96)
        bg.strokeWidth = 1.5
        bg:setStrokeColor(0.30, 0.76, 1.0, enabled and 0.76 or 0.28)
    end

    local text = display.newText({
        parent=group, text=label,
        x=x, y=y,
        font=ui.FONT_BOLD, fontSize=11, align="center"
    })
    text:setFillColor(enabled and 0.84 or 0.46, enabled and 0.96 or 0.54, enabled and 1.0 or 0.64)
    text.isHitTestable = false

    group:addEventListener("tap", function()
        if enabled and onTap then onTap() end
        return true
    end)
    return group
end

local function drawItem(parent, item, x, y, label)
    local panel = display.newRoundedRect(parent, x, y, 132, 168, 8)
    panel:setFillColor(0.02, 0.06, 0.15, 0.94)
    panel.strokeWidth = 1.5
    panel:setStrokeColor(0.22, 0.62, 1.0, 0.58)

    if item and item.icon then
        local icon = display.newImageRect(parent, item.icon, 82, 82)
        icon.x = x
        icon.y = y - 34
    end

    display.newText({
        parent=parent, text=label,
        x=x, y=y - 78,
        width=112,
        font=ui.FONT_BOLD, fontSize=9, align="center"
    }):setFillColor(0.36, 0.78, 1.0)

    display.newText({
        parent=parent, text=(item and item.name) or "Unknown",
        x=x, y=y + 30,
        width=110,
        font=ui.FONT_BOLD, fontSize=11, align="center"
    }):setFillColor(0.88, 0.96, 1.0)

    local statLine = formatStatSummary(item)
    display.newText({
        parent=parent, text=statLine,
        x=x, y=y + 58,
        width=110,
        font=ui.FONT_BOLD, fontSize=12, align="center"
    }):setFillColor(0.74, 1.0, 0.84)
end

local function rebuild()
    if contentGroup then
        contentGroup:removeSelf()
        contentGroup = nil
    end

    contentGroup = display.newGroup()
    sceneGroupRef:insert(contentGroup)

    local player = saveUtil.load()
    local source = items[sourceId]
    local targets = upgrades.getTargets(sourceId)
    selectedTarget = selectedTarget or targets[1]

    local cx = display.contentCenterX
    local sw = display.actualContentWidth
    local sh = display.actualContentHeight

    local title = display.newText({
        parent=contentGroup, text="ITEM UPGRADE",
        x=cx, y=44,
        width=sw - 44,
        font=ui.FONT_BOLD, fontSize=18, align="center"
    })
    title:setFillColor(0.82, 0.96, 1.0)

    if not source or not selectedTarget then
        display.newText({
            parent=contentGroup,
            text="No upgrade path found.",
            x=cx, y=display.contentCenterY,
            width=sw - 56,
            font=ui.FONT_BOLD, fontSize=14, align="center"
        }):setFillColor(0.84, 0.94, 1.0)
        drawButton(contentGroup, cx, sh - 54, "BACK", true, function()
            composer.gotoScene("scenes.bag", { effect="slideRight", time=200 })
        end)
        return
    end

    drawItem(contentGroup, source, cx - 76, 158, "CURRENT")
    drawItem(contentGroup, selectedTarget, cx + 76, 158, "UPGRADE")

    local reqs = upgrades.parseCost(selectedTarget.upgradeCost)
    local canAfford = upgrades.canAfford(player, reqs)
    local listTop = 278
    local rowH = 48

    local reqPanelH = math.min(250, 26 + math.max(1, #reqs) * rowH)
    local reqPanel = display.newRoundedRect(contentGroup, cx, listTop + reqPanelH * 0.5 - 12, sw - 32, reqPanelH, 8)
    reqPanel:setFillColor(0.015, 0.04, 0.11, 0.94)
    reqPanel.strokeWidth = 1.5
    reqPanel:setStrokeColor(0.18, 0.58, 1.0, 0.52)

    display.newText({
        parent=contentGroup, text="MATERIALS NEEDED",
        x=cx, y=listTop - 2,
        font=ui.FONT_BOLD, fontSize=12, align="center"
    }):setFillColor(0.36, 0.78, 1.0)

    for i, req in ipairs(reqs) do
        local y = listTop + 24 + (i - 1) * rowH
        local have = upgrades.getAvailable(player, req)
        local enough = have >= (req.amount or 0)

        if req.icon then
            local icon = display.newImageRect(contentGroup, req.icon, 34, 34)
            icon.x = cx - 128
            icon.y = y
        end

        local nameText = display.newText({
            parent=contentGroup, text=req.name,
            x=cx - 98, y=y - 7,
            width=140,
            font=ui.FONT_BOLD, fontSize=10, align="left"
        })
        nameText.anchorX = 0
        nameText:setFillColor(0.86, 0.96, 1.0)

        local countText = display.newText({
            parent=contentGroup,
            text=tostring(have) .. "/" .. tostring(req.amount or 0),
            x=cx + 126, y=y,
            width=74,
            font=ui.FONT_BOLD, fontSize=12, align="right"
        })
        countText.anchorX = 1
        countText:setFillColor(enough and 0.56 or 1.0, enough and 1.0 or 0.36, enough and 0.66 or 0.34)
    end

    local statusText = canAfford and "READY" or "MISSING MATERIALS"
    display.newText({
        parent=contentGroup, text=statusText,
        x=cx, y=sh - 102,
        width=sw - 60,
        font=ui.FONT_BOLD, fontSize=12, align="center"
    }):setFillColor(canAfford and 0.50 or 1.0, canAfford and 1.0 or 0.42, canAfford and 0.64 or 0.36)

    drawButton(contentGroup, cx - 68, sh - 184, "BACK", true, function()
        composer.gotoScene("scenes.bag", { effect="slideRight", time=200 })
    end)

    drawButton(contentGroup, cx + 68, sh - 184, "UPGRADE", canAfford, function()
        local fresh = saveUtil.load()
        local freshReqs = upgrades.parseCost(selectedTarget.upgradeCost)
        local ok, missing = upgrades.spend(fresh, freshReqs)
        if not ok then
            native.showAlert("Upgrade", "Not enough " .. ((missing and missing.name) or "materials") .. ".", { "OK" })
            rebuild()
            return true
        end

        upgrades.replaceItem(fresh, sourceId, selectedTarget.id)
        saveUtil.save(fresh)
        sync.pushPlayerSnapshot(fresh)
        composer.setVariable("bagTab", (source and source.slot == "weapon") and "weapons" or "armor")
        composer.gotoScene("scenes.bag", { effect="slideRight", time=220 })
        return true
    end)
end

function scene:create(event)
    sceneGroupRef = self.view

    local bg = display.newImage("assets/sprites/ui/bg_home_grid.png")
    local scaleX = display.actualContentWidth / bg.width
    local scaleY = display.actualContentHeight / bg.height
    bg:scale(math.max(scaleX, scaleY), math.max(scaleX, scaleY))
    bg.x = display.contentCenterX
    bg.y = display.contentCenterY
    bg.isHitTestable = false
    sceneGroupRef:insert(bg)
end

function scene:show(event)
    if event.phase ~= "did" then return end
    sourceId = event.params and event.params.sourceId or sourceId
    selectedTarget = nil
    rebuild()
end

function scene:hide(event)
    if event.phase ~= "will" then return end
    if contentGroup then
        contentGroup:removeSelf()
        contentGroup = nil
    end
end

scene:addEventListener("create", scene)
scene:addEventListener("show", scene)
scene:addEventListener("hide", scene)

return scene
