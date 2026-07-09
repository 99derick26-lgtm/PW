local composer = require("composer")
local scene = composer.newScene()

local api = require("utils.api")
local guildNav = require("utils.guild_nav")
local shell = require("utils.guild_scene_shell")
local ui = require("utils.ui")

local activeGuild
local contentGroup
local chromeGroup

local function timeLeftLabel(releaseAt)
    local y, mo, d, h, mi, s = tostring(releaseAt or ""):match("^(%d+)%-(%d+)%-(%d+)T(%d+):(%d+):(%d+)")
    if not y then return "24H" end
    local release = os.time({
        year=tonumber(y), month=tonumber(mo), day=tonumber(d),
        hour=tonumber(h), min=tonumber(mi), sec=tonumber(s),
    })
    local diff = math.max(0, release - os.time())
    return tostring(math.floor(diff / 3600)) .. "H " .. tostring(math.floor((diff % 3600) / 60)) .. "M"
end

local function clearContent()
    if contentGroup and contentGroup.removeSelf then contentGroup:removeSelf() end
    contentGroup = nil
end

local function renderList(jail)
    clearContent()
    contentGroup = display.newGroup()
    scene.view:insert(contentGroup)
    if chromeGroup and chromeGroup.toFront then chromeGroup:toFront() end

    local m = shell.metrics()
    shell.drawFrame(contentGroup, m.CONTENT_X, m.CONTENT_Y, m.CONTENT_W, m.CONTENT_H)
    display.newText({
        parent=contentGroup, text="JAIL",
        x=m.CONTENT_X, y=m.CONTENT_TOP + 16,
        font=ui.FONT_BOLD, fontSize=15
    }):setFillColor(1.0,0.42,0.42)
    display.newText({
        parent=contentGroup, text="10% arena tax for 24 hours",
        x=m.CONTENT_X, y=m.CONTENT_TOP + 36,
        width=m.CONTENT_W - 30, font=ui.FONT_BOLD, fontSize=8, align="center"
    }):setFillColor(0.68,0.84,1.0)
    shell.divLine(contentGroup, m.CONTENT_X, m.CONTENT_TOP + 50, m.CONTENT_W - 24)

    jail = jail or {}
    if #jail == 0 then
        display.newText({
            parent=contentGroup, text="No prisoners.",
            x=m.CONTENT_X, y=m.CONTENT_Y + 8,
            width=m.CONTENT_W - 30, font=ui.FONT_BOLD, fontSize=12, align="center"
        }):setFillColor(0.55,0.75,0.96)
        return
    end

    local rowW = m.CONTENT_W - 24
    local rowH = 58
    local startY = m.CONTENT_TOP + 82
    for i, entry in ipairs(jail) do
        local y = startY + (i - 1) * (rowH + 8)
        if y + rowH * 0.5 < m.CONTENT_BOT - 10 then
            local row = display.newRoundedRect(contentGroup, m.CONTENT_X, y, rowW, rowH, 7)
            row:setFillColor(0.08,0.06,0.12,0.96)
            row.strokeWidth = 1.3
            row:setStrokeColor(0.90,0.20,0.22,0.66)

            local leftX = m.CONTENT_X - rowW * 0.5 + 32
            shell.drawPortrait(contentGroup, leftX, y, entry.name, entry.skinId, 42)

            local name = display.newText({
                parent=contentGroup, text=tostring(entry.name or "Player"),
                x=leftX + 30, y=y - 14,
                width=rowW - 112, font=ui.FONT_BOLD, fontSize=10, align="left"
            })
            name.anchorX = 0
            name:setFillColor(0.96,0.90,0.90)

            local taxGold = tonumber(entry.taxGold or entry.goldContributed or entry.contributionGold or 0) or 0
            local taxText = display.newText({
                parent=contentGroup, text="Tax paid: " .. tostring(taxGold) .. "g",
                x=leftX + 30, y=y + 4,
                width=rowW - 112, font=ui.FONT_BOLD, fontSize=8, align="left"
            })
            taxText.anchorX = 0
            taxText:setFillColor(1.0,0.82,0.20)

            display.newText({
                parent=contentGroup, text=timeLeftLabel(entry.releaseAt),
                x=m.CONTENT_X + rowW * 0.5 - 42, y=y - 4,
                width=74, font=ui.FONT_BOLD, fontSize=8, align="center"
            }):setFillColor(1.0,0.55,0.45)
        end
    end
end

local function refreshJail()
    if not activeGuild or not activeGuild.guildId then
        renderList({})
        return
    end
    api.guilds.jail(activeGuild.guildId, function(response)
        if response and response.ok and response.data then
            renderList(response.data.jail or {})
        else
            renderList({})
        end
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
        refreshJail()
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
