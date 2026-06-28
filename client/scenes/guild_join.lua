local composer   = require("composer")
local scene      = composer.newScene()
local ui         = require("utils.ui")
local radialMenu = require("utils.radial_menu")
local api        = require("utils.api")
local save       = require("utils.save")

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

local MOCK_GUILDS = {
    { name="Ghost Syndicate", leader="RavenX", members=17, maxMembers=20, level=9, desc="Night ops, clean runs, active players." },
    { name="Grid Dogs", leader="Chango", members=12, maxMembers=20, level=7, desc="Daily logins, arena help, casual but active." },
    { name="Neon Riot", leader="Vex", members=19, maxMembers=20, level=11, desc="High activity, guild war focused." },
    { name="Iron Circuit", leader="NullByte", members=8, maxMembers=20, level=6, desc="Growing guild for grinders and builders." },
    { name="Cyber Saints", leader="Lira", members=15, maxMembers=20, level=8, desc="Friendly crew with steady progression." },
    { name="Street Wolves", leader="Bolt", members=11, maxMembers=20, level=5, desc="Arena-first team with open slots." },
}

local resultGroup
local searchField
local lastQuery = ""
local searchDisplayObjects = {}
local searchRaised = false
local SEARCH_KEYBOARD_LIFT = 220

local function addSearchBase(obj)
    obj._baseY = obj.y
    table.insert(searchDisplayObjects, obj)
    return obj
end

local function moveSearchComposer(raised)
    searchRaised = raised == true
    for _, obj in ipairs(searchDisplayObjects) do
        if obj and obj.removeSelf then obj.y = obj._baseY end
    end
    if searchField and searchField.removeSelf then
        searchField.y = searchField._baseY
    end
end

local function clearResults()
    if resultGroup and resultGroup.removeSelf then
        resultGroup:removeSelf()
    end
    resultGroup = nil
end

local function searchGuilds(query)
    local q = string.lower((query or ""):gsub("^%s+", ""):gsub("%s+$", ""))
    if q == "" then return {} end

    local results = {}
    for _, guild in ipairs(MOCK_GUILDS) do
        local name = string.lower(guild.name)
        if name:find(q, 1, true) then
            results[#results + 1] = guild
        end
    end

    if #results == 0 then
        for _, guild in ipairs(MOCK_GUILDS) do
            local name = string.lower(guild.name)
            local letters = 0
            for token in q:gmatch(".") do
                if name:find(token, 1, true) then letters = letters + 1 end
            end
            if letters >= math.max(2, math.floor(#q * 0.5)) then
                results[#results + 1] = guild
            end
        end
    end

    return results
end

local function buildResults(sceneView, query, serverResults)
    clearResults()

    query = (query or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if query == "" then return end

    resultGroup = display.newGroup()
    sceneView:insert(resultGroup)

    local listTop = 160
    local panelW = SW - 20
    local results = serverResults or searchGuilds(query)

    if #results == 0 then
        local emptyPanel = display.newRoundedRect(resultGroup, CX, listTop + 34, panelW, 72, 10)
        emptyPanel:setFillColor(0.03, 0.08, 0.20, 0.95)
        emptyPanel.strokeWidth = 1.5
        emptyPanel:setStrokeColor(0.20, 0.50, 1.0, 0.45)
        display.newText({
            parent=resultGroup, text="No guilds matched that search.",
            x=CX, y=listTop + 26, font=ui.FONT_BOLD, fontSize=13
        }):setFillColor(0.82, 0.90, 1.0)
        display.newText({
            parent=resultGroup, text="Try a shorter or similar guild name.",
            x=CX, y=listTop + 46, font=ui.FONT_BOLD, fontSize=9
        }):setFillColor(0.48, 0.72, 1.0)
        return
    end

    for i, guild in ipairs(results) do
        local y = listTop + (i - 1) * 82

        local glow = display.newRoundedRect(resultGroup, CX, y, panelW + 4, 74, 10)
        glow:setFillColor(0, 0, 0, 0)
        glow.strokeWidth = 2
        glow:setStrokeColor(0.18, 0.62, 1.0, 0.22)

        local card = display.newRoundedRect(resultGroup, CX, y, panelW, 70, 10)
        card:setFillColor(0.03, 0.08, 0.20, 0.95)
        card.strokeWidth = 1.5
        card:setStrokeColor(0.20, 0.50, 1.0, 0.55)

        local accent = display.newRoundedRect(resultGroup, CX, y - 33, panelW - 10, 3, 2)
        accent:setFillColor(0.24, 0.78, 1.0, 0.72)

        local nameT = display.newText({
            parent=resultGroup, text=string.upper(guild.name),
            x=24, y=y - 18, width=panelW - 120, font=ui.FONT_BOLD, fontSize=13, align="left"
        })
        nameT.anchorX = 0
        nameT:setFillColor(0.88, 0.96, 1.0)

        local infoT = display.newText({
            parent=resultGroup,
            text="Leader " .. guild.leader .. "  •  Lv." .. guild.level .. "  •  " .. guild.members .. "/" .. guild.maxMembers,
            x=24, y=y + 2, width=panelW - 120, font=ui.FONT_BOLD, fontSize=9, align="left"
        })
        infoT.anchorX = 0
        infoT:setFillColor(0.46, 0.74, 1.0)

        local descT = display.newText({
            parent=resultGroup, text=guild.desc,
            x=24, y=y + 18, width=panelW - 120, font=ui.FONT_BOLD, fontSize=8, align="left"
        })
        descT.anchorX = 0
        descT:setFillColor(0.74, 0.84, 0.98)

        local joinBtn = display.newRoundedRect(resultGroup, CX + panelW * 0.5 - 42, y, 70, 28, 7)
        joinBtn:setFillColor(0.05, 0.18, 0.42, 0.97)
        joinBtn.strokeWidth = 1.5
        joinBtn:setStrokeColor(0.28, 0.68, 1.0, 0.82)
        local joinText = display.newText({
            parent=resultGroup, text="VIEW",
            x=joinBtn.x, y=joinBtn.y, font=ui.FONT_BOLD, fontSize=10
        })
        joinText:setFillColor(0.78, 0.92, 1.0)
        joinText.isHitTestable = false

        local function viewGuild()
            if guild.guildId then
                composer.gotoScene("scenes.guild_view", {
                    effect="slideLeft",
                    time=260,
                    params={ guildId=guild.guildId, returnScene="scenes.guild_join" },
                })
                return true
            end

            native.showAlert(
                guild.name,
                "Leader: " .. guild.leader .. "\nMembers: " .. guild.members .. "/" .. guild.maxMembers .. "\n\n" .. guild.desc,
                { "OK" }
            )
            return true
        end

        card:addEventListener("tap", viewGuild)
        joinBtn:addEventListener("tap", viewGuild)
    end
end

function scene:create(event)
    local sg = self.view

    local bg = display.newImage("assets/sprites/ui/bg_home_grid.png")
    bg:scale(math.max(SW / bg.width, SH / bg.height), math.max(SW / bg.width, SH / bg.height))
    bg.x = CX
    bg.y = CY
    sg:insert(bg)

    local dim = display.newRect(sg, CX, CY, SW, SH)
    dim:setFillColor(0, 0, 0, 0.54)

    local borderH = SH - 96
    local border = display.newRoundedRect(sg, CX, borderH * 0.5, SW - 8, borderH - 8, 12)
    border:setFillColor(0, 0, 0, 0)
    border.strokeWidth = 3
    border:setStrokeColor(0.20, 0.55, 1.00, 0.75)

    local header = display.newRoundedRect(sg, CX, 30, SW - 16, 48, 10)
    header:setFillColor(0.02, 0.06, 0.16, 0.96)
    header.strokeWidth = 1.5
    header:setStrokeColor(0.18, 0.38, 0.92, 0.46)

    local title = display.newText({
        parent=sg, text="JOIN GUILD",
        x=18, y=24, font=ui.FONT_BOLD, fontSize=18, align="left"
    })
    title.anchorX = 0
    title:setFillColor(0.38, 0.86, 1.0)

    local subtitle = display.newText({
        parent=sg, text="Search by guild name",
        x=18, y=40, font=ui.FONT_BOLD, fontSize=8, align="left"
    })
    subtitle.anchorX = 0
    subtitle:setFillColor(0.50, 0.74, 1.0, 0.82)

    local searchPanel = addSearchBase(display.newRoundedRect(sg, CX, 106, SW - 20, 50, 10))
    searchPanel:setFillColor(0.03, 0.08, 0.20, 0.95)
    searchPanel.strokeWidth = 1.5
    searchPanel:setStrokeColor(0.20, 0.50, 1.0, 0.45)

    local searchGlow = addSearchBase(display.newRoundedRect(sg, CX, 106, SW - 16, 54, 10))
    searchGlow:setFillColor(0, 0, 0, 0)
    searchGlow.strokeWidth = 2
    searchGlow:setStrokeColor(0.18, 0.62, 1.0, 0.20)

    local inputBox = addSearchBase(display.newRoundedRect(sg, CX - 34, 106, SW - 104, 28, 7))
    inputBox:setFillColor(0.04, 0.10, 0.24, 0.98)
    inputBox.strokeWidth = 1.2
    inputBox:setStrokeColor(0.20, 0.55, 1.0, 0.58)

    local searchHint = addSearchBase(display.newText({
        parent=sg, text="Type a guild name and press Enter",
        x=24, y=82, width=SW - 48, font=ui.FONT_BOLD, fontSize=9, align="left"
    }))
    searchHint.anchorX = 0
    searchHint:setFillColor(0.44, 0.70, 1.0)

    local fieldMirror = addSearchBase(display.newText({
        parent=sg, text="Ghost, Grid, Neon...",
        x=24, y=106, width=SW - 132, font=ui.FONT_BOLD, fontSize=10, align="left"
    }))
    fieldMirror.anchorX = 0
    fieldMirror:setFillColor(0.52, 0.66, 0.84)

    local searchBtn = addSearchBase(display.newRoundedRect(sg, SW - 52, 106, 62, 28, 7))
    searchBtn:setFillColor(0.05, 0.18, 0.42, 0.97)
    searchBtn.strokeWidth = 1.5
    searchBtn:setStrokeColor(0.28, 0.68, 1.0, 0.82)
    local searchBtnText = addSearchBase(display.newText({
        parent=sg, text="ENTER",
        x=searchBtn.x, y=searchBtn.y, font=ui.FONT_BOLD, fontSize=9
    }))
    searchBtnText:setFillColor(0.78, 0.92, 1.0)
    searchBtnText.isHitTestable = false

    local field = native.newTextField(CX - 30, 106, SW - 110, 28)
    field.placeholder = "Ghost, Grid, Neon..."
    field.hasBackground = false
    field.alpha = 0.01
    field._baseY = field.y
    searchField = field

    local function updateMirror()
        local value = field.text or ""
        if value == "" then
            fieldMirror.text = "Ghost, Grid, Neon..."
            fieldMirror:setFillColor(0.52, 0.66, 0.84)
        else
            fieldMirror.text = value
            fieldMirror:setFillColor(0.86, 0.95, 1.0)
        end
    end

    local function doSearch()
        local query = field.text or ""
        query = query:gsub("^%s+", ""):gsub("%s+$", "")
        lastQuery = query
        if query == "" then
            updateMirror()
            clearResults()
            native.setKeyboardFocus(nil)
            moveSearchComposer(false)
            return true
        end
        api.guilds.search(query, function(response)
            if response.ok and response.data and response.data.guilds then
                buildResults(sg, query, response.data.guilds)
            else
                buildResults(sg, query, {})
            end
        end)
        native.setKeyboardFocus(nil)
        moveSearchComposer(false)
        return true
    end

    field:addEventListener("userInput", function(e)
        updateMirror()
        if e.phase == "began" then
            moveSearchComposer(true)
        elseif e.phase == "submitted" then
            return doSearch()
        end
        return false
    end)
    inputBox:addEventListener("tap", function()
        native.setKeyboardFocus(field)
        moveSearchComposer(true)
        return true
    end)
    fieldMirror:addEventListener("tap", function()
        native.setKeyboardFocus(field)
        moveSearchComposer(true)
        return true
    end)
    searchBtn:addEventListener("tap", doSearch)
    self.doGuildSearch = doSearch
end

function scene:show(event)
    if event.phase ~= "did" then return end

    if searchField then
        searchField.isVisible = true
        searchField.text = searchField.text or ""
    end

    clearResults()

    radialMenu.show(self.view, {
        activeScene = nil,
        inner       = RADIAL_INNER,
        outer       = RADIAL_OUTER,
    })
end

function scene:hide(event)
    if event.phase ~= "will" then return end
    radialMenu.destroy()
    clearResults()
    if searchField then
        searchField.isVisible = false
        native.setKeyboardFocus(nil)
    end
    moveSearchComposer(false)
end

function scene:destroy(event)
    if searchField then
        searchField:removeSelf()
        searchField = nil
    end
end

scene:addEventListener("create", scene)
scene:addEventListener("show", scene)
scene:addEventListener("hide", scene)
scene:addEventListener("destroy", scene)

return scene
