local composer = require("composer")
local scene = composer.newScene()

local api = require("utils.api")
local guildNav = require("utils.guild_nav")
local shell = require("utils.guild_scene_shell")
local sync = require("utils.sync")
local ui = require("utils.ui")

local activeGuild
local contentGroup
local chromeGroup
local popup
local buildCrew

local ROLE_COLORS = {
    LEADER={1.0,0.78,0.10}, GENERAL={1.0,0.40,0.20},
    LIEUTENANT={0.35,0.75,1.0}, COLONEL={0.35,0.75,1.0},
    CAPTAIN={0.55,1.0,0.65}, MEMBER={0.50,0.52,0.62},
}

local function isLeader(guild)
    return string.upper(tostring((guild and guild.role) or "")) == "LEADER"
end

local function roleBadge(parent, x, y, role)
    role = tostring(role or "MEMBER"):upper()
    local c = ROLE_COLORS[role] or ROLE_COLORS.MEMBER
    local w = role == "LIEUTENANT" and 82 or 64
    local bg = display.newRoundedRect(parent, x, y, w, 18, 4)
    bg:setFillColor(c[1] * 0.18, c[2] * 0.18, c[3] * 0.18, 0.97)
    bg.strokeWidth = 1.4
    bg:setStrokeColor(c[1], c[2], c[3], 0.75)
    display.newText({ parent=parent, text=role, x=x, y=y, font=ui.FONT_BOLD, fontSize=7 }):setFillColor(unpack(c))
end

local function closePopup()
    if popup and popup.removeSelf then popup:removeSelf() end
    popup = nil
end

local function clearContent()
    closePopup()
    if contentGroup and contentGroup.removeSelf then contentGroup:removeSelf() end
    contentGroup = nil
end

local function applyCrewResponse(response)
    if not response or not response.ok or not response.data then return false end
    if response.data.player then
        sync.applyPlayerSnapshot(response.data.player, require("utils.save").activeSlot)
    end
    if response.data.guild then
        for k, v in pairs(response.data.guild) do activeGuild[k] = v end
    end
    activeGuild._members = response.data.members or activeGuild._members or {}
    return true
end

local function showMemberSettings(member)
    if not activeGuild or not activeGuild.guildId then return true end
    closePopup()
    local m = shell.metrics()
    popup = display.newGroup()
    scene.view:insert(popup)

    local dim = display.newRect(popup, m.CX, m.CY, m.SW, m.SH)
    dim:setFillColor(0,0,0,0.72)
    dim.isHitTestable = true
    dim:addEventListener("tap", function() closePopup(); return true end)

    local panelW, panelH = m.SW - 54, 250
    local panel = display.newRoundedRect(popup, m.CX, m.CY, panelW, panelH, 10)
    panel:setFillColor(0.03,0.07,0.18,0.98)
    panel.strokeWidth = 2
    panel:setStrokeColor(0.25,0.75,1.0,0.72)
    panel:addEventListener("tap", function() return true end)

    display.newText({
        parent=popup, text=string.upper(member.name or "MEMBER"),
        x=m.CX, y=m.CY - panelH * 0.5 + 28,
        width=panelW - 36, font=ui.FONT_BOLD, fontSize=14, align="center"
    }):setFillColor(0.82,0.94,1.0)

    local status = display.newText({
        parent=popup, text="",
        x=m.CX, y=m.CY + panelH * 0.5 - 18,
        width=panelW - 24, font=ui.FONT_BOLD, fontSize=8, align="center"
    })
    status:setFillColor(1.0,0.45,0.45)

    local options = {
        { label="CAPTAIN", rank="CAPTAIN", color={0.55,1.0,0.65} },
        { label="LIEUTENANT", rank="LIEUTENANT", color={0.35,0.75,1.0} },
        { label="GENERAL", rank="GENERAL", color={1.0,0.40,0.20} },
        { label="KICK", kick=true, color={1.0,0.30,0.30} },
    }
    local startY = m.CY - 58
    for i, opt in ipairs(options) do
        local y = startY + (i - 1) * 38
        local btn = display.newRoundedRect(popup, m.CX, y, panelW - 42, 31, 7)
        btn:setFillColor(opt.kick and 0.24 or 0.04, opt.kick and 0.04 or 0.12, opt.kick and 0.04 or 0.24, 0.97)
        btn.strokeWidth = 1.5
        btn:setStrokeColor(opt.color[1], opt.color[2], opt.color[3], 0.75)
        display.newText({ parent=popup, text=opt.label, x=m.CX, y=y, font=ui.FONT_BOLD, fontSize=10 }):setFillColor(unpack(opt.color))
        btn:addEventListener("tap", function()
            if opt.kick then
                api.guilds.kickMember(activeGuild.guildId, member.playerId, function(response)
                    if applyCrewResponse(response) then closePopup(); buildCrew() else status.text = "Member update failed." end
                end)
            else
                api.guilds.setMemberRank(activeGuild.guildId, member.playerId, opt.rank, function(response)
                    if applyCrewResponse(response) then closePopup(); buildCrew() else status.text = "Member update failed." end
                end)
            end
            return true
        end)
    end
end

buildCrew = function()
    clearContent()
    contentGroup = display.newGroup()
    scene.view:insert(contentGroup)
    if chromeGroup and chromeGroup.toFront then chromeGroup:toFront() end

    local m = shell.metrics()
    shell.drawFrame(contentGroup, m.CONTENT_X, m.CONTENT_Y, m.CONTENT_W, m.CONTENT_H)
    display.newText({
        parent=contentGroup, text="CREW",
        x=m.CONTENT_X, y=m.CONTENT_TOP + 16,
        font=ui.FONT_BOLD, fontSize=15
    }):setFillColor(0.62,0.88,1.0)
    shell.divLine(contentGroup, m.CONTENT_X, m.CONTENT_TOP + 34, m.CONTENT_W - 24)

    local members = (activeGuild and activeGuild._members) or {}
    local leader = isLeader(activeGuild)
    local rowW = m.CONTENT_W - 24
    local rowH = 58
    local pad = 7
    local scrollH = m.CONTENT_H - 70
    local container = display.newContainer(contentGroup, m.CONTENT_W, scrollH)
    container.x = m.CONTENT_X
    container.y = m.CONTENT_TOP + 48 + scrollH * 0.5
    local inner = display.newGroup()
    container:insert(inner)

    if #members == 0 then
        display.newText({
            parent=contentGroup, text="No members found.",
            x=m.CONTENT_X, y=m.CONTENT_Y, width=m.CONTENT_W - 30,
            font=ui.FONT_BOLD, fontSize=12, align="center"
        }):setFillColor(0.62,0.78,0.96)
    end

    local startY = -scrollH * 0.5 + rowH * 0.5 + pad
    for i, member in ipairs(members) do
        local y = startY + (i - 1) * (rowH + pad)
        local bg = display.newRoundedRect(inner, 0, y, rowW, rowH, 8)
        bg:setFillColor(0.04,0.10,0.22,0.97)
        bg.strokeWidth = 1.5
        bg:setStrokeColor(0.18,0.55,0.38,0.55)

        local dot = display.newCircle(inner, -rowW * 0.5 + 10, y, 4)
        dot:setFillColor(member.online and 0.12 or 0.22, member.online and 0.92 or 0.22, member.online and 0.38 or 0.28)

        shell.drawPortrait(inner, -rowW * 0.5 + 36, y, member.name, member.skinId, 44)
        local textX = -rowW * 0.5 + 66
        local name = display.newText({
            parent=inner, text=member.name or "Player",
            x=textX, y=y - 10, width=rowW - 160,
            font=ui.FONT_BOLD, fontSize=12, align="left"
        })
        name.anchorX = 0
        name:setFillColor(0.90,0.95,1.0)
        local level = display.newText({
            parent=inner, text="LV " .. tostring(member.level or 1),
            x=textX, y=y + 9, font=ui.FONT_BOLD, fontSize=8, align="left"
        })
        level.anchorX = 0
        level:setFillColor(0.35,0.70,1.0)

        local badgeX = leader and (rowW * 0.5 - 76) or (rowW * 0.5 - 42)
        roleBadge(inner, badgeX, y, member.rank or member.role or "MEMBER")

        local function openProfile()
            composer.gotoScene("scenes.social_profile", {
                effect="slideLeft", time=220,
                params={
                    playerId=member.playerId,
                    playerName=member.name,
                    returnScene="scenes.guild_crew",
                    guildId=activeGuild and activeGuild.guildId,
                    guildKey=require("composer").getVariable("guildContextKind"),
                },
            })
            return true
        end
        bg:addEventListener("tap", openProfile)
        name:addEventListener("tap", openProfile)

        if leader and (member.rank or member.role) ~= "LEADER" then
            local gearX = rowW * 0.5 - 26
            local hit = display.newCircle(inner, gearX, y, 14)
            hit:setFillColor(0.03,0.10,0.18,0.96)
            hit.strokeWidth = 1.5
            hit:setStrokeColor(0.28,0.82,1.0,0.72)
            local ok, gear = pcall(display.newImageRect, inner, "assets/sprites/ui/icons/settings.png", 18, 18)
            if ok and gear then
                gear.x = gearX
                gear.y = y
                gear.isHitTestable = false
            else
                display.newText({ parent=inner, text="*", x=gearX, y=y, font=ui.FONT_BOLD, fontSize=13 }):setFillColor(0.55,0.90,1.0)
            end
            hit:addEventListener("tap", function()
                showMemberSettings(member)
                return true
            end)
        end
    end

    local minY = math.min(0, scrollH - (#members * (rowH + pad)) - pad * 2)
    local sy, gy = 0, 0
    container:addEventListener("touch", function(e)
        if e.phase == "began" then
            sy = e.y
            gy = inner.y
        elseif e.phase == "moved" then
            inner.y = math.max(minY, math.min(0, gy + e.y - sy))
        end
        return true
    end)

    display.newText({
        parent=contentGroup,
        text=tostring(#members) .. " / " .. tostring((activeGuild and activeGuild.maxMembers) or 20) .. " members",
        x=m.CONTENT_X, y=m.CONTENT_BOT - 14,
        font=ui.FONT_BOLD, fontSize=8
    }):setFillColor(0.35,0.65,1.0)
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
        buildCrew()
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
