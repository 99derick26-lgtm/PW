local composer = require("composer")
local scene = composer.newScene()

local api = require("utils.api")
local save = require("utils.save")
local ui = require("utils.ui")
local widget = require("widget")

local SW = display.actualContentWidth
local SH = display.actualContentHeight
local CX = display.contentCenterX
local CY = display.contentCenterY

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

local SEARCH_TOP = 52
local SEARCH_H = 70
local LIST_TOP = 132

local searchField

local function openProfile(player)
    local params = {
        playerId = player.playerId,
        playerName = player.displayName,
        returnScene = "scenes.friends",
    }
    if player.localProfile then
        params.player = player
    end

    composer.gotoScene("scenes.social_profile", {
        effect = "slideLeft",
        time = 220,
        params = params,
    })
end

local function buildCard(parent, y, player)
    local card = display.newRoundedRect(parent, CX, y, SW - 26, 66, 8)
    card:setFillColor(0.025, 0.07, 0.17, 0.96)
    card.strokeWidth = 1.5
    card:setStrokeColor(0.16, 0.46, 0.95, 0.62)

    local avatar = display.newCircle(parent, 38, y, 17)
    avatar:setFillColor(0.05, 0.17, 0.38, 0.98)
    avatar.strokeWidth = 1.5
    avatar:setStrokeColor(0.24, 0.70, 1.0, 0.78)

    local initial = string.sub(tostring(player.displayName or "?"), 1, 1)
    display.newText({
        parent = parent,
        text = string.upper(initial),
        x = avatar.x,
        y = avatar.y,
        font = ui.FONT_BOLD,
        fontSize = 14,
    }):setFillColor(0.70, 0.94, 1.0)

    local statusDot = display.newCircle(parent, 51, y + 13, 4)
    local status = string.lower(player.status or "offline")
    if status == "online" then
        statusDot:setFillColor(0.24, 1.0, 0.42)
    elseif status == "away" then
        statusDot:setFillColor(1.0, 0.82, 0.20)
    else
        statusDot:setFillColor(0.42, 0.46, 0.56)
    end

    local nameText = display.newText({
        parent = parent,
        text = player.displayName or "Unknown",
        x = 66,
        y = y - 14,
        width = SW - 168,
        font = ui.FONT_BOLD,
        fontSize = 14,
        align = "left",
    })
    nameText.anchorX = 0
    nameText:setFillColor(0.88, 0.96, 1.0)

    local guildName = player.primaryGuild and player.primaryGuild.name or "No Guild"
    local accountLabel = player.accountName and ("  |  @" .. tostring(player.accountName)) or ""
    local infoText = display.newText({
        parent = parent,
        text = "Lv." .. tostring(player.level or 1) .. "  |  " .. tostring(player.currentScene or "Unknown") .. "  |  " .. guildName .. accountLabel,
        x = 66,
        y = y + 9,
        width = SW - 170,
        font = ui.FONT_BOLD,
        fontSize = 9,
        align = "left",
    })
    infoText.anchorX = 0
    infoText:setFillColor(0.46, 0.74, 1.0)

    local viewBtn = display.newRoundedRect(parent, SW - 56, y, 72, 26, 7)
    viewBtn:setFillColor(0.05, 0.18, 0.42, 0.97)
    viewBtn.strokeWidth = 1.5
    viewBtn:setStrokeColor(0.28, 0.68, 1.0, 0.82)
    local viewText = display.newText({
        parent = parent,
        text = "VIEW",
        x = viewBtn.x,
        y = viewBtn.y,
        font = ui.FONT_BOLD,
        fontSize = 8,
    })
    viewText:setFillColor(0.78, 0.92, 1.0)
    viewText.isHitTestable = false

    local function onTap()
        openProfile(player)
        return true
    end

    card:addEventListener("tap", onTap)
    viewBtn:addEventListener("tap", onTap)
end

local function renderRows(sceneObject, list, title)
    if sceneObject.scrollView then
        sceneObject.scrollView:removeSelf()
        sceneObject.scrollView = nil
    end

    if sceneObject.sectionLabel then
        sceneObject.sectionLabel.text = title
    end

    local listBottom = SH - 104
    local listH = listBottom - LIST_TOP
    local scrollView = widget.newScrollView({
        x = CX,
        y = LIST_TOP + listH * 0.5,
        width = SW - 8,
        height = listH,
        hideBackground = true,
        horizontalScrollDisabled = true,
    })
    sceneObject.view:insert(scrollView)
    sceneObject.scrollView = scrollView

    local content = display.newGroup()
    scrollView:insert(content)

    if not list or #list == 0 then
        local emptyText = display.newText({
            parent = content,
            text = "No players found.",
            x = CX,
            y = 70,
            width = SW - 40,
            font = ui.FONT_BOLD,
            fontSize = 12,
            align = "center",
        })
        emptyText:setFillColor(0.68, 0.82, 1.0)
        return
    end

    for i, player in ipairs(list) do
        buildCard(content, 38 + (i - 1) * 76, player)
    end
end

local function loadFriends(sceneObject)
    sceneObject.sectionLabel.text = "Loading network..."
    api.friends.list(function(response)
        local friends = {}
        if response.ok and response.data and response.data.friends then
            friends = response.data.friends
        end
        renderRows(sceneObject, friends, "Your active network")
    end)
end

local function runSearch(sceneObject)
    local query = searchField and searchField.text or ""
    query = query:gsub("^%s+", ""):gsub("%s+$", "")

    if query == "" then
        loadFriends(sceneObject)
        return
    end

    api.player.search(query, function(response)
        local results = {}
        if response.ok and response.data and response.data.results then
            results = response.data.results
        else
            results = save.searchProfiles(query)
        end
        renderRows(sceneObject, results, "Results for " .. query)
    end)
end

function scene:create(event)
    local sg = self.view

    local bg = display.newImage("assets/sprites/ui/bg_home_grid.png")
    bg:scale(math.max(SW / bg.width, SH / bg.height), math.max(SW / bg.width, SH / bg.height))
    bg.x = CX
    bg.y = CY
    sg:insert(bg)

    local dim = display.newRect(sg, CX, CY, SW, SH)
    dim:setFillColor(0, 0, 0, 0.56)

    local borderH = SH - 96
    local border = display.newRoundedRect(sg, CX, borderH * 0.5, SW - 8, borderH - 8, 12)
    border:setFillColor(0, 0, 0, 0)
    border.strokeWidth = 3
    border:setStrokeColor(0.20, 0.55, 1.00, 0.75)

    local header = display.newRoundedRect(sg, CX, 30, SW - 16, 48, 8)
    header:setFillColor(0.02, 0.06, 0.16, 0.96)
    header.strokeWidth = 1.5
    header:setStrokeColor(0.18, 0.38, 0.92, 0.46)

    local title = display.newText({
        parent = sg,
        text = "FRIENDS",
        x = 18,
        y = 24,
        font = ui.FONT_BOLD,
        fontSize = 18,
        align = "left",
    })
    title.anchorX = 0
    title:setFillColor(0.38, 0.86, 1.0)

    self.sectionLabel = display.newText({
        parent = sg,
        text = "Your active network",
        x = 18,
        y = 40,
        font = ui.FONT_BOLD,
        fontSize = 8,
        align = "left",
    })
    self.sectionLabel.anchorX = 0
    self.sectionLabel:setFillColor(0.50, 0.74, 1.0, 0.82)

    local closeBtn = display.newRoundedRect(sg, SW - 30, 30, 34, 34, 8)
    closeBtn:setFillColor(0.05, 0.18, 0.42, 0.98)
    closeBtn.strokeWidth = 1.5
    closeBtn:setStrokeColor(0.28, 0.68, 1.0, 0.82)
    display.newText({
        parent = sg,
        text = "X",
        x = closeBtn.x,
        y = closeBtn.y,
        font = ui.FONT_BOLD,
        fontSize = 14,
    }):setFillColor(0.78, 0.96, 1.0)
    closeBtn:addEventListener("tap", function()
        native.setKeyboardFocus(nil)
        composer.gotoScene("scenes.home", { effect = "slideRight", time = 220 })
        return true
    end)

    local searchPanel = display.newRoundedRect(sg, CX, SEARCH_TOP + SEARCH_H * 0.5, SW - 16, SEARCH_H, 8)
    searchPanel:setFillColor(0.015, 0.05, 0.13, 0.97)
    searchPanel.strokeWidth = 1.5
    searchPanel:setStrokeColor(0.18, 0.50, 1.0, 0.58)

    display.newText({
        parent = sg,
        text = "SEARCH PLAYER",
        x = 18,
        y = SEARCH_TOP + 14,
        font = ui.FONT_BOLD,
        fontSize = 9,
        align = "left",
    }):setFillColor(0.38, 0.86, 1.0)

    local searchBg = display.newRoundedRect(sg, CX - 34, SEARCH_TOP + 42, SW - 138, 32, 7)
    searchBg:setFillColor(0.04, 0.10, 0.24, 0.98)
    searchBg.strokeWidth = 1.5
    searchBg:setStrokeColor(0.20, 0.55, 1.00, 0.62)

    searchField = native.newTextField(CX - 34, SEARCH_TOP + 42, SW - 150, 24)
    searchField.placeholder = "Enter player name"
    searchField.inputType = "default"
    searchField.returnKey = "search"
    searchField.hasBackground = false
    searchField:setTextColor(0.85, 0.95, 1)

    local searchBtn = display.newRoundedRect(sg, SW - 44, SEARCH_TOP + 42, 66, 32, 7)
    searchBtn:setFillColor(0.05, 0.18, 0.42, 0.97)
    searchBtn.strokeWidth = 1.5
    searchBtn:setStrokeColor(0.28, 0.68, 1.0, 0.82)
    local searchText = display.newText({
        parent = sg,
        text = "SEARCH",
        x = searchBtn.x,
        y = searchBtn.y,
        font = ui.FONT_BOLD,
        fontSize = 8,
    })
    searchText:setFillColor(0.78, 0.92, 1.0)
    searchText.isHitTestable = false

    searchBtn:addEventListener("tap", function()
        native.setKeyboardFocus(nil)
        runSearch(self)
        return true
    end)

    searchField:addEventListener("userInput", function(event)
        if event.phase == "submitted" then
            native.setKeyboardFocus(nil)
            runSearch(self)
        end
    end)
end

function scene:show(event)
    if event.phase ~= "did" then return end
    if searchField then
        searchField.isVisible = true
        searchField.text = ""
    end

    loadFriends(self)

end

function scene:hide(event)
    if event.phase ~= "will" then return end
    if searchField then
        searchField.isVisible = false
    end
end

function scene:destroy(event)
    if searchField and searchField.removeSelf then
        searchField:removeSelf()
        searchField = nil
    end
end

scene:addEventListener("create", scene)
scene:addEventListener("show", scene)
scene:addEventListener("hide", scene)
scene:addEventListener("destroy", scene)

return scene
