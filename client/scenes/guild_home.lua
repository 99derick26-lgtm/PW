local composer = require("composer")
local scene = composer.newScene()

local api = require("utils.api")
local guildContext = require("utils.guild_context")
local guildNav = require("utils.guild_nav")
local saveUtil = require("utils.save")
local shell = require("utils.guild_scene_shell")
local sync = require("utils.sync")
local ui = require("utils.ui")

local activeGuild
local contentGroup
local chromeGroup
local popup
local nameField
local descField
local buildHome

local RIGHT_W = 64
local RIGHT_TAB_H = 58
local RIGHT_TABS = {
    { label="LAND", icon="land", scene="scenes.guild_land" },
    { label="JAIL", icon="jail", scene="scenes.guild_jail" },
    { label="NEWS", icon="news", scene="scenes.guild_news" },
    { label="CHAT", icon="chat", scene="scenes.guild_chat" },
    { label="CREW", icon="crew", scene="scenes.guild_crew" },
}

local function trim(value)
    return tostring(value or ""):match("^%s*(.-)%s*$")
end

local function clearPopup()
    native.setKeyboardFocus(nil)
    if nameField and nameField.removeSelf then nameField:removeSelf() end
    if descField and descField.removeSelf then descField:removeSelf() end
    nameField = nil
    descField = nil
    if popup and popup.removeSelf then popup:removeSelf() end
    popup = nil
end

local function clearContent()
    clearPopup()
    if contentGroup and contentGroup.removeSelf then contentGroup:removeSelf() end
    contentGroup = nil
end

local function roleOf(guild)
    return string.upper(tostring((guild and guild.role) or ""))
end

local function isLeader(guild)
    local player = saveUtil.load()
    return roleOf(guild) == "LEADER"
        or (guild and guild.leaderPlayerId and guild.leaderPlayerId == player.playerId)
        or (guild and guild.leader and (guild.leader == player.name or guild.leader == player.displayName))
end

local function membersOf(guild)
    return (guild and (guild._members or guild.memberList)) or {}
end

local function leaderMember(guild)
    local leaderName = guild and guild.leader
    for _, member in ipairs(membersOf(guild)) do
        if member.rank == "LEADER" or member.role == "LEADER" or member.name == leaderName then
            return member
        end
    end
    local player = saveUtil.load()
    return {
        name=player.name or player.displayName or leaderName or "Player",
        level=player.level or 1,
        rank=roleOf(guild) ~= "" and roleOf(guild) or "LEADER",
        skinId=player.appearance and player.appearance.skinId or player.skinId,
        online=true,
    }
end

local function countOnline(guild)
    local count = 0
    for _, member in ipairs(membersOf(guild)) do
        if member.online then count = count + 1 end
    end
    return count
end

local function saveGuildToPlayer(guild)
    if not guild or not guild.guildId then return end
    local player = saveUtil.load()
    guildContext.applyGuild(player, guild, guild.role or "MEMBER")
    saveUtil.save(player)
end

local function reloadGuild(callback)
    shell.loadGuild({ guildId=activeGuild and activeGuild.guildId }, function(guild)
        activeGuild = guild
        saveGuildToPlayer(guild)
        if callback then callback(guild) end
    end)
end

local function responseErrorText(response, fallback)
    if response and response.data and response.data.error then return tostring(response.data.error) end
    if response and response.error then return tostring(response.error) end
    if response and response.status then return fallback .. " (" .. tostring(response.status) .. ")" end
    return fallback
end

local function button(parent, x, y, w, h, label, color)
    local bg = display.newRoundedRect(parent, x, y, w, h, 7)
    bg:setFillColor(color[1] * 0.12, color[2] * 0.12, color[3] * 0.12, 0.97)
    bg.strokeWidth = 1.5
    bg:setStrokeColor(color[1], color[2], color[3], 0.76)
    local text = display.newText({ parent=parent, text=label, x=x, y=y, font=ui.FONT_BOLD, fontSize=10 })
    text:setFillColor(color[1], color[2], color[3])
    text.isHitTestable = false
    return bg
end

local function showSettings()
    if not activeGuild or not activeGuild.guildId then return true end
    clearPopup()
    local m = shell.metrics()
    popup = display.newGroup()
    scene.view:insert(popup)
    local dim = display.newRect(popup, m.CX, m.CY, m.SW, m.SH)
    dim:setFillColor(0,0,0,0.76)
    dim.isHitTestable = true
    dim:addEventListener("tap", function() clearPopup(); return true end)

    local panelW, panelH = m.SW - 34, 246
    local panel = display.newRoundedRect(popup, m.CX, m.CY, panelW, panelH, 10)
    panel:setFillColor(0.03,0.07,0.18,0.98)
    panel.strokeWidth = 2
    panel:setStrokeColor(0.20,0.82,0.52,0.82)
    panel:addEventListener("tap", function() return true end)
    display.newText({ parent=popup, text="GUILD SETTINGS", x=m.CX, y=m.CY - 92, font=ui.FONT_BOLD, fontSize=14 }):setFillColor(0.32,0.96,0.58)

    display.newText({ parent=popup, text="NAME", x=m.CX - panelW * 0.5 + 24, y=m.CY - 58, font=ui.FONT_BOLD, fontSize=8 }).anchorX = 0
    nameField = native.newTextField(m.CX, m.CY - 34, panelW - 46, 30)
    nameField.text = activeGuild.name or ""
    nameField.font = native.newFont(ui.FONT_BOLD, 11)
    nameField:setTextColor(0.04,0.08,0.16)

    display.newText({ parent=popup, text="DESCRIPTION", x=m.CX - panelW * 0.5 + 24, y=m.CY + 2, font=ui.FONT_BOLD, fontSize=8 }).anchorX = 0
    descField = native.newTextField(m.CX, m.CY + 26, panelW - 46, 30)
    descField.text = activeGuild.desc or activeGuild.description or ""
    descField.font = native.newFont(ui.FONT_BOLD, 10)
    descField:setTextColor(0.04,0.08,0.16)

    local status = display.newText({ parent=popup, text="", x=m.CX, y=m.CY + 63, width=panelW - 42, font=ui.FONT_BOLD, fontSize=8, align="center" })
    status:setFillColor(1.0,0.45,0.38)
    local cancel = button(popup, m.CX - 62, m.CY + 92, 96, 34, "CANCEL", {0.70,0.78,0.92})
    local save = button(popup, m.CX + 62, m.CY + 92, 96, 34, "SAVE", {0.42,1.0,0.58})
    cancel:addEventListener("tap", function() clearPopup(); return true end)
    save:addEventListener("tap", function()
        local payload = { name=trim(nameField and nameField.text or ""), desc=trim(descField and descField.text or "") }
        if payload.name == "" then status.text = "Guild name required."; return true end
        status.text = "Saving..."
        api.guilds.update(activeGuild.guildId, payload, function(response)
            if response and response.ok and response.data then
                if response.data.player then sync.applyPlayerSnapshot(response.data.player, saveUtil.activeSlot) end
                if response.data.guild then activeGuild = response.data.guild end
                clearPopup()
                buildHome()
            else
                status.text = responseErrorText(response, "Save failed")
            end
        end)
        return true
    end)
    return true
end

local function showLeaveConfirm()
    if not activeGuild or not activeGuild.guildId then return true end
    clearPopup()
    local m = shell.metrics()
    popup = display.newGroup()
    scene.view:insert(popup)
    local dim = display.newRect(popup, m.CX, m.CY, m.SW, m.SH)
    dim:setFillColor(0,0,0,0.76)
    dim.isHitTestable = true
    dim:addEventListener("tap", function() clearPopup(); return true end)
    local panel = display.newRoundedRect(popup, m.CX, m.CY, m.SW - 42, 192, 10)
    panel:setFillColor(0.03,0.07,0.18,0.98)
    panel.strokeWidth = 2
    panel:setStrokeColor(0.90,0.28,0.24,0.78)
    panel:addEventListener("tap", function() return true end)
    display.newText({ parent=popup, text="LEAVE GUILD?", x=m.CX, y=m.CY - 60, font=ui.FONT_BOLD, fontSize=14 }):setFillColor(1.0,0.42,0.38)
    display.newText({ parent=popup, text=tostring(activeGuild.name or "this guild"), x=m.CX, y=m.CY - 28, width=m.SW - 74, font=ui.FONT_BOLD, fontSize=10, align="center" }):setFillColor(0.82,0.88,1.0)
    local no = button(popup, m.CX - 58, m.CY + 34, 92, 34, "NO", {0.70,0.78,0.92})
    local yes = button(popup, m.CX + 58, m.CY + 34, 92, 34, "YES", {1.0,0.42,0.38})
    no:addEventListener("tap", function() clearPopup(); return true end)
    yes:addEventListener("tap", function()
        api.guilds.leave(activeGuild.guildId, function(response)
            if response and response.ok then
                if response.data and response.data.player then sync.applyPlayerSnapshot(response.data.player, saveUtil.activeSlot) end
                local player = saveUtil.load()
                guildContext.removeGuild(player, activeGuild.guildId)
                saveUtil.save(player)
                clearPopup()
                composer.gotoScene("scenes.guild_join", { effect="slideRight", time=220 })
            end
        end)
        return true
    end)
    return true
end

local function goGuildScene(tab)
    composer.gotoScene(tab.scene, {
        effect="slideLeft", time=180,
        params={
            guildId=activeGuild and activeGuild.guildId,
            guildKey=composer.getVariable("guildContextKind"),
        },
    })
    return true
end

local function drawRightTabs(parent, m)
    local rightX = m.SW - RIGHT_W * 0.5 - 2
    local totalTabsH = #RIGHT_TABS * RIGHT_TAB_H + (#RIGHT_TABS - 1) * 4
    local startY = m.CONTENT_TOP + (m.CONTENT_H - totalTabsH) * 0.5
    for i, tab in ipairs(RIGHT_TABS) do
        local y = startY + (i - 1) * (RIGHT_TAB_H + 4) + RIGHT_TAB_H * 0.5
        local bg = display.newRoundedRect(parent, rightX, y, RIGHT_W - 6, RIGHT_TAB_H - 4, 7)
        bg:setFillColor(0.02,0.055,0.13,0.96)
        bg.strokeWidth = 1.25
        bg:setStrokeColor(0.12,0.38,0.76,0.46)
        local ok, icon = pcall(display.newImageRect, parent, "assets/sprites/ui/icons/" .. tab.icon .. ".png", 30, 30)
        if ok and icon then
            icon.x = rightX
            icon.y = y - 10
            icon.alpha = 0.82
            icon:addEventListener("tap", function() return goGuildScene(tab) end)
        end
        local label = display.newText({
            parent=parent, text=tab.label,
            x=rightX, y=y + RIGHT_TAB_H * 0.5 - 8,
            width=RIGHT_W - 8, font=ui.FONT_BOLD, fontSize=7, align="center"
        })
        label:setFillColor(0.62,0.82,0.96)
        bg:addEventListener("tap", function() return goGuildScene(tab) end)
        label:addEventListener("tap", function() return goGuildScene(tab) end)
    end
end

local function drawExitButton(parent, m)
    local size = 38
    local x = m.SW - size * 0.5 - 10
    local y = guildNav.contentBottom() - size * 0.5 - 8
    local bg = display.newRoundedRect(parent, x, y, size, size, 8)
    bg:setFillColor(0.03,0.10,0.24,0.96)
    bg.strokeWidth = 1.5
    bg:setStrokeColor(0.24,0.70,1.0,0.78)
    local label = display.newText({ parent=parent, text="X", x=x, y=y, font=ui.FONT_BOLD, fontSize=13 })
    label:setFillColor(0.72,0.92,1.0)
    local function exit()
        composer.gotoScene("scenes.home", { effect="slideRight", time=220 })
        return true
    end
    bg:addEventListener("tap", exit)
    label:addEventListener("tap", exit)
end

buildHome = function()
    clearContent()
    if chromeGroup and chromeGroup.removeSelf then chromeGroup:removeSelf() end
    chromeGroup = display.newGroup()
    scene.view:insert(chromeGroup)

    local m = shell.metrics()
    shell.drawHeader(chromeGroup, activeGuild)
    guildNav.build(chromeGroup, "HOME")
    drawRightTabs(chromeGroup, m)
    drawExitButton(chromeGroup, m)

    contentGroup = display.newGroup()
    scene.view:insert(contentGroup)
    local rightSpace = RIGHT_W + 8
    local contentW = m.SW - rightSpace - 10
    local contentX = contentW * 0.5 + 4
    shell.drawFrame(contentGroup, contentX, m.CONTENT_Y, contentW, m.CONTENT_H)

    local leader = leaderMember(activeGuild)
    local members = membersOf(activeGuild)
    local avR = 30
    local avY = m.CONTENT_TOP + avR + 16
    local glow = display.newCircle(contentGroup, contentX, avY, avR + 8)
    glow:setFillColor(0.20,0.58,1.0,0.10)
    local avBg = display.newCircle(contentGroup, contentX, avY, avR)
    avBg:setFillColor(0.05,0.14,0.34,0.95)
    avBg.strokeWidth = 2
    avBg:setStrokeColor(0.24,0.70,1.0,0.86)
    shell.drawPortrait(contentGroup, contentX, avY, leader.name, leader.skinId, avR * 1.65)
    display.newText({ parent=contentGroup, text="*", x=contentX + avR, y=avY - avR + 2, font=ui.FONT_BOLD, fontSize=11 }):setFillColor(1.0,0.82,0.20)
    display.newText({ parent=contentGroup, text=leader.name or "Player", x=contentX, y=avY + avR + 12, font=ui.FONT_BOLD, fontSize=14 }):setFillColor(0.84,0.96,1.0)
    display.newText({
        parent=contentGroup,
        text="LV " .. tostring(leader.level or 1) .. "  -  " .. tostring(leader.rank or leader.role or "LEADER"),
        x=contentX, y=avY + avR + 26, font=ui.FONT_BOLD, fontSize=10
    }):setFillColor(0.42,0.78,1.0)

    local actionLabel = isLeader(activeGuild) and "SET" or "LEAVE"
    local action = button(contentGroup, contentX + contentW * 0.5 - 36, m.CONTENT_TOP + 19, 50, 24, actionLabel, isLeader(activeGuild) and {0.72,0.92,1.0} or {1.0,0.38,0.35})
    action:addEventListener("tap", function() return isLeader(activeGuild) and showSettings() or showLeaveConfirm() end)

    local lineY = avY + avR + 42
    shell.divLine(contentGroup, contentX, lineY, contentW - 22)
    local total = 0
    for _, member in ipairs(members) do total = total + (member.level or 1) end
    local avgLv = #members > 0 and math.floor(total / #members) or (activeGuild and (activeGuild.avgLevel or activeGuild.level) or 1)
    local stats = {
        { "ONLINE", tostring(countOnline(activeGuild)) .. "/" .. tostring((activeGuild and activeGuild.maxMembers) or 20), {0.42,0.92,1.0} },
        { "AVG LV", tostring(avgLv), {0.72,0.88,1.0} },
        { "FUNDS", tostring((activeGuild and activeGuild.gold) or 0) .. "g", {1.0,0.82,0.20} },
    }
    local statW = (contentW - 32) / 3
    local statY = lineY + 20
    for i, stat in ipairs(stats) do
        local x = contentX - statW + (i - 1) * statW
        local bg = display.newRoundedRect(contentGroup, x, statY, statW - 6, 34, 6)
        bg:setFillColor(0.03,0.08,0.18,0.94)
        bg.strokeWidth = 1.5
        bg:setStrokeColor(0.20,0.55,0.95,0.45)
        display.newText({ parent=contentGroup, text=stat[1], x=x, y=statY - 8, font=ui.FONT_BOLD, fontSize=6 }):setFillColor(0.42,0.58,0.78)
        display.newText({ parent=contentGroup, text=stat[2], x=x, y=statY + 7, font=ui.FONT_BOLD, fontSize=10 }):setFillColor(unpack(stat[3]))
    end

    display.newText({ parent=contentGroup, text="LEADER STATUS", x=contentX, y=statY + 36, font=ui.FONT_BOLD, fontSize=8 }):setFillColor(0.42,0.58,0.78)
    local statusBg = display.newRoundedRect(contentGroup, contentX, statY + 54, contentW - 22, 28, 7)
    statusBg:setFillColor(0.04,0.12,0.26,0.94)
    statusBg.strokeWidth = 1.5
    statusBg:setStrokeColor(0.18,0.50,0.92,0.45)
    display.newText({ parent=contentGroup, text=tostring(countOnline(activeGuild)) .. " ONLINE", x=contentX, y=statY + 54, width=contentW - 34, font=ui.FONT_BOLD, fontSize=8, align="center" }):setFillColor(0.72,0.90,1.0)

    local summary = (activeGuild and (activeGuild.description or activeGuild.desc)) or "No guild description yet."
    if summary == "" then summary = "No guild description yet." end
    if #summary > 200 then summary = string.sub(summary, 1, 197) .. "..." end
    display.newText({
        parent=contentGroup, text=summary,
        x=contentX, y=statY + 108, width=contentW - 32,
        font=ui.FONT_BOLD, fontSize=10, align="center"
    }):setFillColor(0.78,0.86,0.98)
    display.newText({ parent=contentGroup, text="RECENT ACTIVITY", x=contentX, y=m.CONTENT_BOT - 74, font=ui.FONT_BOLD, fontSize=8 }):setFillColor(0.42,0.58,0.78)
end

function scene:create()
    shell.drawBackground(self.view)
end

function scene:show(event)
    if event.phase ~= "did" then return end
    shell.loadGuild(event.params or {}, function(guild)
        activeGuild = guild
        buildHome()
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
