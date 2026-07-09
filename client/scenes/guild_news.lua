local composer = require("composer")
local scene = composer.newScene()

local api = require("utils.api")
local guildNav = require("utils.guild_nav")
local shell = require("utils.guild_scene_shell")
local ui = require("utils.ui")

local activeGuild
local contentGroup
local chromeGroup

local function clearContent()
    if contentGroup and contentGroup.removeSelf then contentGroup:removeSelf() end
    contentGroup = nil
end

local function row(parent, x, y, w, h, title, body, color)
    color = color or {0.42,0.92,1.0}
    local bg = display.newRoundedRect(parent, x, y, w, h, 7)
    bg:setFillColor(0.035, 0.085, 0.19, 0.96)
    bg.strokeWidth = 1.3
    bg:setStrokeColor(color[1], color[2], color[3], 0.48)
    local t = display.newText({
        parent=parent, text=title,
        x=x - w * 0.5 + 12, y=y - h * 0.5 + 15,
        width=w - 24, font=ui.FONT_BOLD, fontSize=8, align="left"
    })
    t.anchorX = 0
    t:setFillColor(color[1], color[2], color[3])
    body = tostring(body or "")
    if #body > 110 then body = string.sub(body, 1, 107) .. "..." end
    local b = display.newText({
        parent=parent, text=body,
        x=x - w * 0.5 + 12, y=y + 8,
        width=w - 24, font=ui.FONT_BOLD, fontSize=8, align="left"
    })
    b.anchorX = 0
    b:setFillColor(0.78,0.88,1.0)
end

local function buildRows(wars)
    clearContent()
    contentGroup = display.newGroup()
    scene.view:insert(contentGroup)
    if chromeGroup and chromeGroup.toFront then chromeGroup:toFront() end

    local m = shell.metrics()
    shell.drawFrame(contentGroup, m.CONTENT_X, m.CONTENT_Y, m.CONTENT_W, m.CONTENT_H)
    display.newText({
        parent=contentGroup, text="GUILD NEWS",
        x=m.CONTENT_X, y=m.CONTENT_TOP + 16,
        font=ui.FONT_BOLD, fontSize=15
    }):setFillColor(0.62,0.88,1.0)
    shell.divLine(contentGroup, m.CONTENT_X, m.CONTENT_TOP + 34, m.CONTENT_W - 24)

    local messages = (activeGuild and activeGuild._messages) or {}
    local members = (activeGuild and activeGuild._members) or {}
    local jail = (activeGuild and activeGuild._jail) or {}
    local leagueHistory = (activeGuild and activeGuild.leagueHistory) or {}
    local rows = {}

    if messages[1] then
        rows[#rows + 1] = {
            "LATEST CHAT",
            tostring(messages[1].author or messages[1].name or "Player") .. ": " .. tostring(messages[1].body or messages[1].msg or ""),
            {0.54,1.0,0.68},
        }
    end
    if jail[1] then
        rows[#rows + 1] = {
            "CAPTURED",
            tostring(jail[1].name or "Player") .. " is paying 10% arena tax to the guild.",
            {1.0,0.42,0.36},
        }
    end
    for i = 1, math.min(3, #leagueHistory) do
        local item = leagueHistory[i]
        rows[#rows + 1] = {
            tostring(item.title or "LEAGUE"),
            tostring(item.body or "League activity updated."),
            {0.42,1.0,0.70},
        }
    end
    for _, war in ipairs(wars or {}) do
        if war.winnerGuildId then
            rows[#rows + 1] = {
                "WAR RESULT",
                tostring(war.attackerGuildName or "Guild") .. " vs " .. tostring(war.defenderGuildName or "Guild") .. " finished.",
                {1.0,0.58,0.35},
            }
        end
    end
    rows[#rows + 1] = {
        "CREW STATUS",
        tostring(#members) .. "/" .. tostring((activeGuild and activeGuild.maxMembers) or 20) .. " members online and ready.",
        {0.42,0.92,1.0},
    }
    rows[#rows + 1] = {
        "VAULT",
        "Funds: " .. tostring((activeGuild and activeGuild.gold) or 0) .. "g  -  Rep: " .. tostring((activeGuild and activeGuild.rep) or 0),
        {1.0,0.82,0.20},
    }
    rows[#rows + 1] = {
        "WAR ROOM",
        "Loots, captures, and war results will post here as guild activity rolls in.",
        {1.0,0.45,0.36},
    }

    local rowW = m.CONTENT_W - 24
    local rowH = 58
    local startY = m.CONTENT_TOP + 72
    for i, item in ipairs(rows) do
        local y = startY + (i - 1) * (rowH + 8)
        if y + rowH * 0.5 < m.CONTENT_BOT - 10 then
            row(contentGroup, m.CONTENT_X, y, rowW, rowH, item[1], item[2], item[3])
        end
    end
end

local function refreshNews()
    if not activeGuild or not activeGuild.guildId then
        buildRows({})
        return
    end
    api.guilds.wars(activeGuild.guildId, function(response)
        buildRows((response and response.ok and response.data and response.data.wars) or {})
    end)
end

function scene:create()
    shell.drawBackground(self.view)
end

function scene:show(event)
    if event.phase ~= "did" then return end
    shell.loadGuild(event.params or {}, function(guild)
        activeGuild = guild
        if chromeGroup and chromeGroup.removeSelf then chromeGroup:removeSelf() end
        chromeGroup = display.newGroup()
        scene.view:insert(chromeGroup)
        shell.drawHeader(chromeGroup, activeGuild)
        shell.drawCloseToHome(chromeGroup, activeGuild)
        guildNav.build(chromeGroup, "HOME")
        refreshNews()
    end)
end

function scene:hide(event)
    if event.phase ~= "will" then return end
    clearContent()
    if chromeGroup and chromeGroup.removeSelf then chromeGroup:removeSelf() end
    chromeGroup = nil
end

scene:addEventListener("create", scene)
scene:addEventListener("show", scene)
scene:addEventListener("hide", scene)

return scene
