local composer = require("composer")
local scene = composer.newScene()

local api = require("utils.api")
local ui = require("utils.ui")
local widget = require("widget")

local CX = display.contentCenterX
local CY = display.contentCenterY
local SW = display.actualContentWidth
local SH = display.actualContentHeight

local activeTab = "xp"
local contentGroup
local sceneRef

local function clearGroup(group)
    if group and group.removeSelf then
        group:removeSelf()
    end
end

local function openPlayerProfile(player)
    if not player then return true end
    composer.gotoScene("scenes.social_profile", {
        effect = "slideLeft",
        time = 220,
        params = {
            playerId = player.playerId,
            player = player,
            returnScene = "scenes.leaderboard",
        },
    })
    return true
end

local function makeTopBar(parent, title)
    local header = display.newRect(parent, CX, 42, SW, 84)
    header:setFillColor(0.02, 0.05, 0.12, 0.96)
    header.strokeWidth = 1
    header:setStrokeColor(0.18, 0.48, 0.82, 0.40)

    display.newText({
        parent = parent,
        text = title,
        x = CX,
        y = 28,
        font = ui.FONT_BOLD,
        fontSize = 18,
        align = "center",
    }):setFillColor(0.4, 0.9, 1.0)

    local back = display.newText({
        parent = parent,
        text = "< BACK",
        x = 34,
        y = 28,
        font = ui.FONT_BOLD,
        fontSize = 11,
        align = "left",
    })
    back.anchorX = 0
    back:setFillColor(0.6, 0.9, 1.0)
    back:addEventListener("tap", function()
        composer.gotoScene("scenes.home", { effect = "slideRight", time = 220 })
        return true
    end)
end

local function tabButton(parent, x, y, w, h, label, isActive, onTap)
    local bg = display.newRoundedRect(parent, x, y, w, h, 8)
    bg:setFillColor(isActive and 0.10 or 0.03, isActive and 0.28 or 0.10, isActive and 0.56 or 0.24, 0.96)
    bg.strokeWidth = 1.5
    bg:setStrokeColor(isActive and 0.35 or 0.16, isActive and 0.82 or 0.48, isActive and 1.0 or 0.82, isActive and 0.92 or 0.52)

    display.newText({
        parent = parent,
        text = label,
        x = x,
        y = y,
        font = ui.FONT_BOLD,
        fontSize = 12,
        align = "center",
    }):setFillColor(isActive and 1.0 or 0.72, isActive and 1.0 or 0.86, isActive and 1.0 or 0.92)

    bg:addEventListener("tap", function()
        if onTap then onTap() end
        return true
    end)
end

local function renderComingSoon(group)
    display.newText({
        parent = group,
        text = "COMING SOON",
        x = CX,
        y = CY,
        font = ui.FONT_BOLD,
        fontSize = 18,
        align = "center",
    }):setFillColor(0.55, 0.75, 1.0)
end

local function renderXpLeaderboard(group)
    local scroll = widget.newScrollView({
        x = CX,
        y = (SH + 116) * 0.5,
        width = SW,
        height = SH - 116,
        horizontalScrollDisabled = true,
        verticalScrollDisabled = false,
        hideBackground = true,
        hideScrollBar = false,
        topPadding = 0,
        bottomPadding = 24,
        friction = 0.92,
    })
    group:insert(scroll)

    local rows = display.newGroup()
    scroll:insert(rows)

    api.request("/v1/leaderboard/xp?limit=50", { method = "GET" }, function(response)
        if not group or not group.removeSelf then return end
        if rows and rows.removeSelf then rows:removeSelf() end
        rows = display.newGroup()
        if scroll and scroll.insert then
            scroll:insert(rows)
        end

        if not response or not response.ok or not response.data or not response.data.players then
            local failureText = "NO LEADERBOARD DATA"
            if response and response.data and response.data.error then
                failureText = string.upper(tostring(response.data.error))
            elseif response and response.status and response.status > 0 then
                failureText = "ERROR " .. tostring(response.status)
            elseif response and response.offline then
                failureText = "SERVER OFFLINE"
            end
            display.newText({
                parent = rows,
                text = failureText,
                x = CX,
                y = CY,
                font = ui.FONT_BOLD,
                fontSize = 14,
                align = "center",
            }):setFillColor(0.8, 0.9, 1.0)
            return
        end

        local players = response.data.players
        local startY = 132
        local rowH = 42
        local panelW = SW - 24

        local header = display.newRoundedRect(rows, CX, 108, panelW, 28, 8)
        header:setFillColor(0.02, 0.06, 0.14, 0.96)
        header.strokeWidth = 1
        header:setStrokeColor(0.18, 0.48, 0.82, 0.32)

        local levelHeader = display.newText({
            parent = rows,
            text = "LV.",
            x = 34,
            y = 108,
            font = ui.FONT_BOLD,
            fontSize = 10,
            align = "left",
        })
        levelHeader.anchorX = 0
        levelHeader:setFillColor(0.55, 0.82, 1.0)

        local nameHeader = display.newText({
            parent = rows,
            text = "NAME",
            x = 84,
            y = 108,
            font = ui.FONT_BOLD,
            fontSize = 10,
            align = "left",
        })
        nameHeader.anchorX = 0
        nameHeader:setFillColor(0.55, 0.82, 1.0)

        local xpHeader = display.newText({
            parent = rows,
            text = "XP ACQUIRED",
            x = SW - 34,
            y = 108,
            font = ui.FONT_BOLD,
            fontSize = 10,
            align = "right",
        })
        xpHeader.anchorX = 1
        xpHeader:setFillColor(0.55, 0.82, 1.0)

        for i, player in ipairs(players) do
            local y = startY + (i - 1) * rowH
            local row = display.newRoundedRect(rows, CX, y, panelW, 32, 8)
            row:setFillColor(0.03, 0.08, 0.18, 0.95)
            row.strokeWidth = 1
            row:setStrokeColor(0.18, 0.48, 0.82, 0.42)

            local levelText = display.newText({
                parent = rows,
                text = "LV. " .. tostring(player.level or 1),
                x = 34,
                y = y,
                font = ui.FONT_BOLD,
                fontSize = 10,
                align = "left",
            })
            levelText.anchorX = 0
            levelText:setFillColor(0.45, 0.85, 1.0)
            levelText.isHitTestable = false

            local nameText = display.newText({
                parent = rows,
                text = player.displayName or "Player",
                x = 84,
                y = y,
                font = ui.FONT_BOLD,
                fontSize = 12,
                align = "left",
            })
            nameText.anchorX = 0
            nameText:setFillColor(0.95, 0.98, 1.0)
            nameText.isHitTestable = false

            local xpText = display.newText({
                parent = rows,
                text = tostring(player.xp or 0),
                x = SW - 34,
                y = y,
                font = ui.FONT_BOLD,
                fontSize = 11,
                align = "right",
            })
            xpText.anchorX = 1
            xpText:setFillColor(0.7, 0.95, 1.0)
            xpText.isHitTestable = false

            row:addEventListener("tap", function()
                return openPlayerProfile(player)
            end)
        end

        local contentHeight = startY + (#players * rowH) + 24
        rows.y = 0
        scroll:setScrollHeight(math.max(scroll.height, contentHeight))
    end)
end

local function rebuild(sceneObject)
    sceneObject = sceneObject or sceneRef
    if not sceneObject or not sceneObject.view then return end

    if contentGroup then
        clearGroup(contentGroup)
        contentGroup = nil
    end

    contentGroup = display.newGroup()
    sceneObject.view:insert(contentGroup)

    local bg = display.newImage("assets/backgrounds/rooftop.png")
    if bg then
        bg:scale(math.max(SW / bg.width, SH / bg.height), math.max(SW / bg.width, SH / bg.height))
        bg.x = CX
        bg.y = CY
        contentGroup:insert(bg)
    else
        local fallback = display.newRect(contentGroup, CX, CY, SW, SH)
        fallback:setFillColor(0.02, 0.03, 0.08)
    end

    makeTopBar(contentGroup, "LEADERBOARD")

    local tabY = 86
    local tabW = (SW - 26) * 0.5
    tabButton(contentGroup, CX - tabW * 0.5 - 3, tabY, tabW, 30, "XP", activeTab == "xp", function()
        activeTab = "xp"
        rebuild()
    end)
    tabButton(contentGroup, CX + tabW * 0.5 + 3, tabY, tabW, 30, "GUILDS", activeTab == "guilds", function()
        activeTab = "guilds"
        rebuild()
    end)

    if activeTab == "xp" then
        renderXpLeaderboard(contentGroup)
    else
        renderComingSoon(contentGroup)
    end
end

function scene:create(event)
    sceneRef = self
end

function scene:show(event)
    if event.phase ~= "did" then return end
    sceneRef = self
    rebuild(self)
end

function scene:hide(event)
    if event.phase ~= "will" then return end
    clearGroup(contentGroup)
    contentGroup = nil
end

scene:addEventListener("create", scene)
scene:addEventListener("show", scene)
scene:addEventListener("hide", scene)

return scene
