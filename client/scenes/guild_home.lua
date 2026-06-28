-- scenes/guild_home.lua
-- Original layout: right-side tabs (Land/Jail/News/Chat/Crew + X exit)
-- Bottom 4 tabs navigate to separate scenes: guild_league, guild_war, guild_loot, scenes.home

local composer = require("composer")
local scene    = composer.newScene()
local widget   = require("widget")
local api      = require("utils.api")
local guildNav = require("utils.guild_nav")
local guildContext = require("utils.guild_context")
local saveUtil = require("utils.save")
local session  = require("utils.session")
local sync     = require("utils.sync")
local timeLabels = require("utils.time_labels")
local ui       = require("utils.ui")
local rewardPopup = require("utils.reward_popup")

local CX = display.contentCenterX
local CY = display.contentCenterY
local SW = display.contentWidth
local SH = display.contentHeight

-------------------------------------------------
-- ASSET PATHS
-------------------------------------------------
local FRAME_LARGE  = "assets/sprites/ui/frames/border_large.png"
local FRAME_SMALL  = "assets/sprites/ui/frames/border_small.png"
local FRAME_THIN_L = "assets/sprites/ui/frames/thin_large.png"
local FRAME_THIN_S = "assets/sprites/ui/frames/thin_small.png"

-------------------------------------------------
-- LAYOUT CONSTANTS
-------------------------------------------------
local BOTTOM_H = guildNav.HEIGHT
local BOTTOM_Y = guildNav.bottomY()
local HEADER_H = 72
local HEADER_Y = HEADER_H*0.5

local RIGHT_W     = 64
local RIGHT_TAB_H = 58
local RIGHT_X     = SW - RIGHT_W * 0.5 - 2

local CONTENT_X   = (SW - RIGHT_W - 6) * 0.5 + 2
local CONTENT_W   = SW - RIGHT_W - 10
local CONTENT_TOP = HEADER_H + 6
local CONTENT_BOT = guildNav.contentBottom()
local CONTENT_H   = CONTENT_BOT - CONTENT_TOP
local CONTENT_Y   = CONTENT_TOP + CONTENT_H * 0.5

local RIGHT_TABS  = {
    { label="LAND", icon="land" },
    { label="JAIL", icon="jail" },
    { label="NEWS", icon="news" },
    { label="CHAT", icon="chat" },
    { label="CREW", icon="crew" },
}
local BOTTOM_TABS = {
    { label="HOME",   icon="crew_home", action="stay"                  },
    { label="LEAGUE", icon="league",    action="scene", scene="scenes.guild_league" },
    { label="WAR",    icon="war",       action="scene", scene="scenes.guild_war"    },
    { label="LOOT",   icon="loot",      action="scene", scene="scenes.guild_loot"   },
}

-------------------------------------------------
-- STATE
-------------------------------------------------
local TIMERS        = {}
local sceneGroup    = nil
local contentGroup  = nil
local activeRightTab = 0
local rightTabBgs   = {}
local rightTabTxts  = {}
local rightTabIcons = {}
local lootPickPopup = nil
local activeGuild = nil
local chatField = nil
local settingsPopup = nil
local guildNameField = nil
local guildDescField = nil
local headerNameText = nil
local guildChatPrivate = false
local refreshActiveGuild
local buildCrew
local chatComposerRaised = false
local CHAT_KEYBOARD_LIFT = 280
local cleanupChatField
local trim

local function closeLootPick()
    if lootPickPopup and lootPickPopup.removeSelf then lootPickPopup:removeSelf() end
    lootPickPopup = nil
end

local function closeSettingsPopup()
    native.setKeyboardFocus(nil)
    if guildNameField and guildNameField.removeSelf then guildNameField:removeSelf() end
    if guildDescField and guildDescField.removeSelf then guildDescField:removeSelf() end
    guildNameField = nil
    guildDescField = nil
    if settingsPopup and settingsPopup.removeSelf then settingsPopup:removeSelf() end
    settingsPopup = nil
end

local function flicker(obj, lo, hi, ms)
    local t = timer.performWithDelay(ms, function()
        if obj and obj.removeSelf then obj.alpha = lo + math.random()*(hi-lo) end
    end, 0)
    table.insert(TIMERS, t)
end

local function blockModalTouch(target, onRelease)
    if not target or not target.addEventListener then return end
    target.isHitTestable = true
    target:addEventListener("touch", function(event)
        if event.phase == "began" then
            display.getCurrentStage():setFocus(target)
            target._modalFocus = true
        elseif target._modalFocus and (event.phase == "ended" or event.phase == "cancelled") then
            display.getCurrentStage():setFocus(nil)
            target._modalFocus = false
            if event.phase == "ended" and onRelease then
                return onRelease(event) ~= false
            end
        end
        return true
    end)
end

-------------------------------------------------
-- HELPERS
-------------------------------------------------
local function clearContent()
    closeLootPick()
    closeSettingsPopup()
    cleanupChatField(true)
    if contentGroup and contentGroup.removeSelf then
        contentGroup:removeSelf()
    end
    contentGroup = nil
    chatComposerRaised = false
end

local function drawFrame(parent, x, y, w, h, path)
    local r = display.newRoundedRect(parent, x, y, w, h, 8)
    r:setFillColor(0.025, 0.065, 0.16, 0.92)
    r.strokeWidth = 1.5
    r:setStrokeColor(0.18, 0.50, 0.92, 0.58)

    local accent = display.newRect(parent, x, y - h * 0.5 + 5, w - 18, 2)
    accent:setFillColor(0.24, 0.64, 1.0, 0.46)
    accent.isHitTestable = false
    return r
end

local ROLE_COLORS = {
    LEADER  = {1.0,0.78,0.10},
    GENERAL = {1.0,0.40,0.20},
    LIEUTENANT = {0.35,0.75,1.0},
    COLONEL = {0.35,0.75,1.0},
    CAPTAIN = {0.55,1.0,0.65},
    MEMBER  = {0.50,0.52,0.62},
}

local function roleBadge(parent, x, y, role)
    local rc = ROLE_COLORS[role] or ROLE_COLORS.MEMBER
    local bw = role == "LIEUTENANT" and 76 or 60
    local bg = display.newRoundedRect(parent, x, y, bw, 18, 4)
    bg:setFillColor(rc[1]*0.18, rc[2]*0.18, rc[3]*0.18, 0.97)
    bg.strokeWidth=1.5; bg:setStrokeColor(rc[1], rc[2], rc[3], 0.75)
    display.newText({ parent=parent, text=role,
        x=x, y=y, font=ui.FONT_BOLD, fontSize=7 }):setFillColor(unpack(rc))
end

local function divLine(parent, x, y, w)
    display.newRect(parent, x, y, w, 1):setFillColor(0.18, 0.48, 0.82, 0.26)
end

local function drawPortrait(parent, x, y, name, skinId, size)
    size = size or 44
    local ok, portrait = pcall(display.newImageRect, parent,
        "assets/sprites/characters/" .. tostring(skinId or "street_brawler") .. "/portrait.png", size, size)
    if ok and portrait then
        portrait.x = x
        portrait.y = y
        return portrait
    end

    local fallback = display.newCircle(parent, x, y, size * 0.45)
    fallback:setFillColor(0.05, 0.17, 0.38, 0.98)
    fallback.strokeWidth = 1.5
    fallback:setStrokeColor(0.24, 0.70, 1.0, 0.78)
    display.newText({
        parent=parent, text=string.sub(string.upper(name or "?"), 1, 1),
        x=x, y=y, font=ui.FONT_BOLD, fontSize=14
    }):setFillColor(0.70, 0.94, 1.0)
    return fallback
end

local function getGuildMembers(guild)
    return (guild and (guild._members or guild.memberList)) or {}
end

local function getGuildMessages(guild)
    return (guild and guild._messages) or {}
end

local function currentPlayerMember(guild)
    local player = saveUtil.load()
    return {
        playerId = player.playerId,
        name = player.name or player.displayName or "Player",
        level = player.level or 1,
        rank = (guild and guild.role) or "MEMBER",
        online = true,
        skinId = player.appearance and player.appearance.skinId or player.skinId,
    }
end

local function enrichLocalGuild(guild)
    guild = guild or {}
    guild._members = guild._members or { currentPlayerMember(guild) }
    guild._messages = guild._messages or {}
    return guild
end

local function loadGuildDetails(guild, callback)
    guild = enrichLocalGuild(guild)
    if not guild.guildId then
        callback(guild)
        return
    end

    api.guilds.get(guild.guildId, function(response)
        if response.ok and response.data then
            local remoteGuild = response.data.guild or guild
            for k, v in pairs(remoteGuild) do guild[k] = v end
            guild._members = response.data.members or guild._members or {}
            guild._messages = response.data.messages or guild._messages or {}
        end
        callback(guild)
    end)
end

local function applyGuildToLocalPlayer(guild)
    if not guild or not guild.guildId then return end
    local player = saveUtil.load()
    local role = guild.role
        or (guild.leaderPlayerId and player.playerId == guild.leaderPlayerId and "LEADER")
        or (guild.leader and (player.name == guild.leader or player.displayName == guild.leader) and "LEADER")
        or "MEMBER"
    guildContext.applyGuild(player, guild, role)
    saveUtil.save(player)
end

local function countOnlineMembers(guild)
    local online = 0
    for _, m in ipairs(getGuildMembers(guild)) do
        if m.online then online = online + 1 end
    end
    return online
end

local function findLeaderMember(guild)
    local leaderName = guild and guild.leader
    for _, m in ipairs(getGuildMembers(guild)) do
        if m.rank == "LEADER" or m.name == leaderName then
            return m
        end
    end
    return currentPlayerMember(guild)
end

local function isGuildLeader(guild, player)
    player = player or saveUtil.load()
    local role = string.upper(tostring((guild and guild.role) or ""))
    return role == "LEADER"
        or (guild and guild.leaderPlayerId and player.playerId == guild.leaderPlayerId)
        or (guild and guild.leader and player.name and player.name == guild.leader)
        or (guild and guild.leader and player.displayName and player.displayName == guild.leader)
end

local function resolveLeaderVisualId(player, guild, leader)
    if player and player.name and guild.leader == player.name then
        return (player.appearance and player.appearance.skinId) or "street_brawler"
    end
    return leader.skinId or "street_brawler"
end

local function removeLocalGuild(guildId)
    local player = saveUtil.load()
    guildContext.removeGuild(player, guildId)
    saveUtil.save(player)
end

local function saveCreatedGuildLocal(guild)
    if not guild or not guild.guildId then return end
    local player = saveUtil.load()
    guildContext.applyGuild(player, guild, "LEADER")
    saveUtil.save(player)
end

local function responseErrorText(response, fallback)
    if response and response.data and response.data.error then return tostring(response.data.error) end
    if response and response.error then return tostring(response.error) end
    if response and response.status then return fallback .. " (" .. tostring(response.status) .. ")" end
    return fallback
end

local function isStaleGuildMembership(response)
    if response and response.status == 404 then return true end
    if response and response.data and response.data.error == "not_guild_member" then return true end
    if response and response.error == "not_guild_member" then return true end
    if response and response.raw and string.find(tostring(response.raw), "not_guild_member", 1, true) then return true end
    return false
end

local function showGuildSettings(sg, guild)
    if not guild or not guild.guildId then return true end
    closeSettingsPopup()
    settingsPopup = display.newGroup()
    sg:insert(settingsPopup)

    local dim = display.newRect(settingsPopup, CX, CY, SW, SH)
    dim:setFillColor(0, 0, 0, 0.78)
    dim.isHitTestable = true

    local panelW, panelH = SW - 34, 260
    local panel = display.newRoundedRect(settingsPopup, CX, CY, panelW, panelH, 10)
    panel:setFillColor(0.03, 0.07, 0.18, 0.98)
    panel.strokeWidth = 2
    panel:setStrokeColor(0.20, 0.82, 0.52, 0.82)
    blockModalTouch(panel)

    display.newText({ parent=settingsPopup, text="GUILD SETTINGS",
        x=CX, y=CY - panelH * 0.5 + 26, font=ui.FONT_BOLD, fontSize=14
    }):setFillColor(0.32, 0.96, 0.58)

    display.newText({ parent=settingsPopup, text="NAME",
        x=CX - panelW * 0.5 + 26, y=CY - 72, font=ui.FONT_BOLD, fontSize=8, align="left"
    }):setFillColor(0.44, 0.62, 0.82)
    guildNameField = native.newTextField(CX, CY - 48, panelW - 46, 30)
    guildNameField.text = guild.name or ""
    guildNameField.font = native.newFont(ui.FONT_BOLD, 11)
    guildNameField:setTextColor(0.04, 0.08, 0.16)

    display.newText({ parent=settingsPopup, text="DESCRIPTION",
        x=CX - panelW * 0.5 + 26, y=CY - 12, font=ui.FONT_BOLD, fontSize=8, align="left"
    }):setFillColor(0.44, 0.62, 0.82)
    guildDescField = native.newTextField(CX, CY + 12, panelW - 46, 30)
    guildDescField.text = guild.desc or guild.description or ""
    guildDescField.font = native.newFont(ui.FONT_BOLD, 10)
    guildDescField:setTextColor(0.04, 0.08, 0.16)

    local cancel = display.newRoundedRect(settingsPopup, CX - 62, CY + panelH * 0.5 - 38, 96, 34, 7)
    cancel:setFillColor(0.08, 0.10, 0.18, 0.97)
    cancel.strokeWidth = 1.5
    cancel:setStrokeColor(0.45, 0.52, 0.68, 0.65)
    local cancelText = display.newText({ parent=settingsPopup, text="CANCEL", x=cancel.x, y=cancel.y, font=ui.FONT_BOLD, fontSize=10 })
    cancelText:setFillColor(0.70, 0.78, 0.92)
    cancelText.isHitTestable = false

    local save = display.newRoundedRect(settingsPopup, CX + 62, CY + panelH * 0.5 - 38, 96, 34, 7)
    save:setFillColor(0.04, 0.22, 0.10, 0.97)
    save.strokeWidth = 1.5
    save:setStrokeColor(0.28, 0.95, 0.48, 0.78)
    local saveText = display.newText({ parent=settingsPopup, text="SAVE", x=save.x, y=save.y, font=ui.FONT_BOLD, fontSize=10 })
    saveText:setFillColor(0.42, 1.0, 0.58)
    saveText.isHitTestable = false

    local statusText = display.newText({ parent=settingsPopup, text="",
        x=CX, y=CY + 54, width=panelW - 46, font=ui.FONT_BOLD, fontSize=8, align="center"
    })
    statusText:setFillColor(1.0, 0.45, 0.38)

    cancel:addEventListener("tap", function() closeSettingsPopup(); return true end)
    blockModalTouch(dim, function() closeSettingsPopup(); return true end)
    local function doSave()
        local payload = {
            name = trim(guildNameField and guildNameField.text or guild.name or ""),
            desc = trim(guildDescField and guildDescField.text or guild.desc or ""),
        }
        if payload.name == "" then
            statusText.text = "Guild name required."
            return true
        end
        statusText.text = "Saving..."
        print("Guild settings save tapped", guild.guildId, payload.name)
        api.guilds.update(guild.guildId, payload, function(response)
            if response.ok and response.data then
                if response.data.player then
                    sync.applyPlayerSnapshot(response.data.player, saveUtil.activeSlot)
                end
                closeSettingsPopup()
                refreshActiveGuild(sg, response.data.guild or guild)
            else
                local message = responseErrorText(response, "Save failed")
                print("Guild settings save failed:", message)
                if statusText and statusText.removeSelf then
                    statusText.text = message
                end
            end
        end)
        return true
    end
    save:addEventListener("tap", doSave)
    return true
end

local function showLeaveGuildConfirm(sg, guild)
    if not guild or not guild.guildId then return true end
    closeSettingsPopup()
    settingsPopup = display.newGroup()
    sg:insert(settingsPopup)

    local dim = display.newRect(settingsPopup, CX, CY, SW, SH)
    dim:setFillColor(0, 0, 0, 0.76)
    dim.isHitTestable = true
    local panel = display.newRoundedRect(settingsPopup, CX, CY, SW - 42, 210, 10)
    panel:setFillColor(0.03, 0.07, 0.18, 0.98)
    panel.strokeWidth = 2
    panel:setStrokeColor(0.90, 0.28, 0.24, 0.78)
    blockModalTouch(panel)
    display.newText({ parent=settingsPopup, text="LEAVE GUILD?",
        x=CX, y=CY - 74, font=ui.FONT_BOLD, fontSize=14
    }):setFillColor(1.0, 0.42, 0.38)
    display.newText({ parent=settingsPopup, text="Are you sure you want to leave?",
        x=CX, y=CY - 42, width=SW - 74, font=ui.FONT_BOLD, fontSize=11, align="center"
    }):setFillColor(0.82, 0.88, 1.0)
    display.newText({ parent=settingsPopup, text=tostring(guild.name or "this guild"),
        x=CX, y=CY - 17, width=SW - 86, font=ui.FONT_BOLD, fontSize=9, align="center"
    }):setFillColor(0.48, 0.94, 1.0)

    local selectedLeave = nil
    local yes = display.newRoundedRect(settingsPopup, CX - 62, CY + 25, 96, 34, 7)
    yes.strokeWidth = 1.5
    local yesText = display.newText({ parent=settingsPopup, text="YES", x=yes.x, y=yes.y, font=ui.FONT_BOLD, fontSize=10 })
    yesText.isHitTestable = false

    local no = display.newRoundedRect(settingsPopup, CX + 62, CY + 25, 96, 34, 7)
    no.strokeWidth = 1.5
    local noText = display.newText({ parent=settingsPopup, text="NO", x=no.x, y=no.y, font=ui.FONT_BOLD, fontSize=10 })
    noText.isHitTestable = false

    local confirm = display.newRoundedRect(settingsPopup, CX, CY + 72, 160, 34, 7)
    confirm:setFillColor(0.04, 0.22, 0.10, 0.97)
    confirm.strokeWidth = 1.5
    confirm:setStrokeColor(0.28, 0.95, 0.48, 0.78)
    local confirmText = display.newText({ parent=settingsPopup, text="CONFIRM", x=confirm.x, y=confirm.y, font=ui.FONT_BOLD, fontSize=10 })
    confirmText:setFillColor(0.42, 1.0, 0.58)
    confirmText.isHitTestable = false

    local statusText = display.newText({ parent=settingsPopup, text="",
        x=CX, y=CY + 50, width=SW - 74, font=ui.FONT_BOLD, fontSize=8, align="center"
    })
    statusText:setFillColor(1.0, 0.45, 0.38)

    blockModalTouch(dim, function() closeSettingsPopup(); return true end)

    local function updateChoice(wantsLeave)
        selectedLeave = wantsLeave
        yes:setFillColor(wantsLeave and 0.28 or 0.08, wantsLeave and 0.04 or 0.10, wantsLeave and 0.04 or 0.18, 0.97)
        yes:setStrokeColor(wantsLeave and 1.0 or 0.45, wantsLeave and 0.25 or 0.52, wantsLeave and 0.25 or 0.68, wantsLeave and 0.80 or 0.65)
        yesText:setFillColor(wantsLeave and 1.0 or 0.70, wantsLeave and 0.45 or 0.78, wantsLeave and 0.42 or 0.92)
        no:setFillColor((wantsLeave == false) and 0.04 or 0.08, (wantsLeave == false) and 0.22 or 0.10, (wantsLeave == false) and 0.10 or 0.18, 0.97)
        no:setStrokeColor((wantsLeave == false) and 0.28 or 0.45, (wantsLeave == false) and 0.95 or 0.52, (wantsLeave == false) and 0.48 or 0.68, (wantsLeave == false) and 0.78 or 0.65)
        noText:setFillColor((wantsLeave == false) and 0.42 or 0.70, (wantsLeave == false) and 1.0 or 0.78, (wantsLeave == false) and 0.58 or 0.92)
        statusText.text = ""
        return true
    end

    local function doLeave()
        statusText.text = "Leaving..."
        print("Guild leave tapped", guild.guildId)
        api.guilds.leave(guild.guildId, function(response)
            if response.ok then
                if response.data and response.data.player then
                    sync.applyPlayerSnapshot(response.data.player, saveUtil.activeSlot)
                end
                removeLocalGuild(guild.guildId)
                closeSettingsPopup()
                composer.gotoScene("scenes.guild_join", { effect="slideRight", time=220 })
            else
                local message = responseErrorText(response, "Leave failed")
                print("Guild leave failed:", message)
                if isStaleGuildMembership(response) then
                    removeLocalGuild(guild.guildId)
                    closeSettingsPopup()
                    composer.gotoScene("scenes.guild_join", { effect="slideRight", time=220 })
                elseif statusText and statusText.removeSelf then
                    statusText.text = message
                end
            end
        end)
        return true
    end

    yes:addEventListener("tap", function() return updateChoice(true) end)
    no:addEventListener("tap", function() return updateChoice(false) end)
    confirm:addEventListener("tap", function()
        if selectedLeave == nil then
            statusText.text = "Choose YES or NO."
            return true
        end
        if selectedLeave == false then
            closeSettingsPopup()
            return true
        end
        return doLeave()
    end)
    updateChoice(false)
    return true
end

local function applyCrewResponse(sg, guild, response)
    if not response or not response.ok or not response.data then return false end
    if response.data.player then
        sync.applyPlayerSnapshot(response.data.player, saveUtil.activeSlot)
    end
    guild._members = response.data.members or guild._members or {}
    if response.data.guild then
        for k, v in pairs(response.data.guild) do guild[k] = v end
    end
    activeGuild = guild
    buildCrew(sg, guild)
    return true
end

local function showCrewMemberSettings(sg, guild, member)
    closeSettingsPopup()
    settingsPopup = display.newGroup()
    sg:insert(settingsPopup)

    local dim = display.newRect(settingsPopup, CX, CY, SW, SH)
    dim:setFillColor(0,0,0,0.72)
    dim.isHitTestable = true
    blockModalTouch(dim, function() closeSettingsPopup(); return true end)

    local panelW, panelH = SW - 54, 268
    local panel = display.newRoundedRect(settingsPopup, CX, CY, panelW, panelH, 12)
    panel:setFillColor(0.03,0.07,0.18,0.98)
    panel.strokeWidth = 2
    panel:setStrokeColor(0.25,0.75,1.0,0.72)
    blockModalTouch(panel)

    display.newText({
        parent=settingsPopup, text=string.upper(member.name or "MEMBER"),
        x=CX, y=CY - panelH*0.5 + 28,
        font=ui.FONT_BOLD, fontSize=14, align="center"
    }):setFillColor(0.82,0.94,1.0)

    local statusText = display.newText({
        parent=settingsPopup, text="",
        x=CX, y=CY + panelH*0.5 - 18,
        width=panelW - 24, font=ui.FONT_BOLD, fontSize=9, align="center"
    })
    statusText:setFillColor(1.0,0.45,0.45)

    local function fail(response)
        statusText.text = responseErrorText(response, "Member update failed")
    end

    local options = {
        { label="CAPTAIN", rank="CAPTAIN", color={0.55,1.0,0.65} },
        { label="LIEUTENANT", rank="LIEUTENANT", color={0.35,0.75,1.0} },
        { label="GENERAL", rank="GENERAL", color={1.0,0.40,0.20} },
        { label="KICK", kick=true, color={1.0,0.30,0.30} },
    }

    local startY = CY - 62
    for i, opt in ipairs(options) do
        local y = startY + (i - 1) * 42
        local btn = display.newRoundedRect(settingsPopup, CX, y, panelW - 42, 34, 7)
        btn:setFillColor(opt.kick and 0.24 or 0.04, opt.kick and 0.04 or 0.12, opt.kick and 0.04 or 0.24, 0.97)
        btn.strokeWidth = 1.5
        btn:setStrokeColor(opt.color[1], opt.color[2], opt.color[3], 0.75)
        display.newText({ parent=settingsPopup, text=opt.label,
            x=CX, y=y, font=ui.FONT_BOLD, fontSize=11 }):setFillColor(unpack(opt.color))

        btn:addEventListener("tap", function()
            if not guild.guildId or not member.playerId then return true end
            if opt.kick then
                native.showAlert("Kick Member", "Remove " .. tostring(member.name or "this member") .. " from the guild?", { "CANCEL", "KICK" }, function(event)
                    if event.action == "clicked" and event.index == 2 then
                        api.guilds.kickMember(guild.guildId, member.playerId, function(response)
                            if applyCrewResponse(sg, guild, response) then closeSettingsPopup() else fail(response) end
                        end)
                    end
                end)
            else
                api.guilds.setMemberRank(guild.guildId, member.playerId, opt.rank, function(response)
                    if applyCrewResponse(sg, guild, response) then closeSettingsPopup() else fail(response) end
                end)
            end
            return true
        end)
    end

    local close = display.newCircle(settingsPopup, CX + panelW*0.5 - 16, CY - panelH*0.5 + 16, 12)
    close:setFillColor(0.24,0.04,0.04,0.97)
    close.strokeWidth = 1.5
    close:setStrokeColor(0.85,0.18,0.18,0.80)
    display.newText({ parent=settingsPopup, text="X", x=close.x, y=close.y, font=ui.FONT_BOLD, fontSize=10 }):setFillColor(1.0,0.30,0.30)
    close:addEventListener("tap", function() closeSettingsPopup(); return true end)
end

-------------------------------------------------
-- CONTENT: HOME
-------------------------------------------------
local function buildHome(sg, guild)
    return
end

local function buildLegacyMockHomeUnused(sg, guild)
    clearContent()
    contentGroup = display.newGroup(); sg:insert(contentGroup)

    drawFrame(contentGroup, CONTENT_X, CONTENT_Y, CONTENT_W, CONTENT_H, FRAME_LARGE)

    local leader = MOCK_MEMBERS[1]
    local avR = 34
    local avY = CONTENT_TOP + avR + 16

    local glow = display.newCircle(contentGroup, CONTENT_X, avY, avR+8)
    glow:setFillColor(0.18, 0.82, 0.48, 0.07)

    local avBg = display.newCircle(contentGroup, CONTENT_X, avY, avR)
    avBg:setFillColor(0.05, 0.14, 0.34, 0.95)
    avBg.strokeWidth = 2.5
    avBg:setStrokeColor(0.18, 0.82, 0.48, 0.85)
    flicker(avBg, 0.65, 1.0, 900)

    display.newText({
        parent=contentGroup,
        text=string.upper(string.sub(leader.name, 1, 1)),
        x=CONTENT_X, y=avY-2, font=ui.FONT_BOLD, fontSize=28
    }):setFillColor(0.35, 0.90, 0.55)

    display.newText({
        parent=contentGroup, text="⭐",
        x=CONTENT_X+avR, y=avY-avR+2, font=ui.FONT_BOLD, fontSize=11
    })

    display.newText({
        parent=contentGroup, text=leader.name,
        x=CONTENT_X, y=avY+avR+12, font=ui.FONT_BOLD, fontSize=14, align="center"
    }):setFillColor(0.28, 0.95, 0.55)

    display.newText({
        parent=contentGroup, text="LV "..leader.level,
        x=CONTENT_X, y=avY+avR+26, font=ui.FONT_BOLD, fontSize=10, align="center"
    }):setFillColor(0.38, 0.70, 1.0)

    local d1Y = avY + avR + 40
    divLine(contentGroup, CONTENT_X, d1Y, CONTENT_W - 20)

    local total = 0
    for _, m in ipairs(MOCK_MEMBERS) do total = total + m.level end
    local avgLv = math.floor(total / #MOCK_MEMBERS)

    display.newText({
        parent=contentGroup, text="AVG. LEVEL",
        x=CONTENT_X, y=d1Y+12, font=ui.FONT_BOLD, fontSize=8, align="center"
    }):setFillColor(0.42, 0.58, 0.78)

    display.newText({
        parent=contentGroup, text=tostring(avgLv),
        x=CONTENT_X, y=d1Y+28, font=ui.FONT_BOLD, fontSize=22, align="center"
    }):setFillColor(0.85, 0.92, 1.0)

    local d2Y = d1Y + 44
    divLine(contentGroup, CONTENT_X, d2Y, CONTENT_W - 20)

    local summary = guild.description or "Just a Family\nDo your best!"
    if #summary > 200 then summary = string.sub(summary, 1, 197).."..." end

    display.newText({
        parent=contentGroup, text=summary,
        x=CONTENT_X, y=d2Y+22, width=CONTENT_W - 18,
        font=ui.FONT_BOLD, fontSize=10, align="center"
    }):setFillColor(0.70, 0.78, 0.92)
end

local function buildHomePixelWar(sg, guild)
    clearContent()
    contentGroup = display.newGroup(); sg:insert(contentGroup)

    local player = saveUtil.load()
    local isLeader = isGuildLeader(guild, player)
    drawFrame(contentGroup, CONTENT_X, CONTENT_Y, CONTENT_W, CONTENT_H, FRAME_LARGE)

    local leader = findLeaderMember(guild)
    local leaderSkin = resolveLeaderVisualId(player, guild, leader)
    local members = getGuildMembers(guild)
    local onlineCount = countOnlineMembers(guild)
    local avR = 30
    local avY = CONTENT_TOP + avR + 16

    for i = 1, 6 do
        local dot = display.newRect(contentGroup,
            CONTENT_X - CONTENT_W * 0.5 + 18 + math.random() * (CONTENT_W - 36),
            CONTENT_TOP + 16 + math.random() * (CONTENT_H - 34),
            math.random(2, 4), math.random(2, 4))
        dot:setFillColor(0.42, 0.78, 1.0, 0.05 + math.random() * 0.08)
        flicker(dot, 0.04, 0.20, 600 + i * 120)
    end

    for i = 1, 5 do
        local lineY = CONTENT_TOP + 46 + i * 54
        local scan = display.newRect(contentGroup, CONTENT_X, lineY, CONTENT_W - 18, 1)
        scan:setFillColor(0.20, 0.58, 1.0, 0.06)
        flicker(scan, 0.02, 0.16, 900 + i * 180)
    end

    local glow = display.newCircle(contentGroup, CONTENT_X, avY, avR + 8)
    glow:setFillColor(0.20, 0.58, 1.0, 0.10)

    local avBg = display.newCircle(contentGroup, CONTENT_X, avY, avR)
    avBg:setFillColor(0.05, 0.14, 0.34, 0.95)
    avBg.strokeWidth = 2
    avBg:setStrokeColor(0.24, 0.70, 1.0, 0.86)
    flicker(avBg, 0.65, 1.0, 900)

    local okPortrait, portrait = pcall(display.newImageRect, contentGroup,
        "assets/sprites/characters/" .. leaderSkin .. "/portrait.png", avR * 1.65, avR * 1.65)
    if okPortrait and portrait then
        portrait.x = CONTENT_X
        portrait.y = avY
    else
        display.newText({
            parent=contentGroup,
            text=string.upper(string.sub(leader.name, 1, 1)),
            x=CONTENT_X, y=avY - 2, font=ui.FONT_BOLD, fontSize=24
        }):setFillColor(0.35, 0.90, 0.55)
    end

    display.newText({
        parent=contentGroup, text="*",
        x=CONTENT_X + avR, y=avY - avR + 2, font=ui.FONT_BOLD, fontSize=11
    }):setFillColor(1.0, 0.82, 0.20)

    display.newText({
        parent=contentGroup, text=leader.name,
        x=CONTENT_X, y=avY + avR + 12, font=ui.FONT_BOLD, fontSize=14, align="center"
    }):setFillColor(0.84, 0.96, 1.0)

    display.newText({
        parent=contentGroup, text="LV " .. leader.level .. "  •  " .. leader.rank,
        x=CONTENT_X, y=avY + avR + 26, font=ui.FONT_BOLD, fontSize=10, align="center"
    }):setFillColor(0.42, 0.78, 1.0)

    local d1Y = avY + avR + 40
    divLine(contentGroup, CONTENT_X, d1Y, CONTENT_W - 20)

    local total = 0
    for _, m in ipairs(members) do total = total + (m.level or 1) end
    local avgLv = #members > 0 and math.floor(total / #members) or 0

    local statY = d1Y + 20
    local statW = (CONTENT_W - 32) / 3
    local statsBar = {
        { label="ONLINE", value=tostring(onlineCount).."/"..tostring(guild.maxMembers or 20), color={0.42, 0.92, 1.0} },
        { label="AVG LV", value=tostring(avgLv), color={0.72, 0.88, 1.0} },
        { label="FUNDS",  value=tostring(guild.gold or 0).."g", color={1.0, 0.82, 0.20} },
    }

    for i, item in ipairs(statsBar) do
        local sx = CONTENT_X - statW + (i - 1) * statW
        local bg = display.newRoundedRect(contentGroup, sx, statY, statW - 6, 34, 6)
        bg:setFillColor(0.03, 0.08, 0.18, 0.94)
        bg.strokeWidth = 1.5
        bg:setStrokeColor(0.20, 0.55, 0.95, 0.45)
        display.newText({
            parent=contentGroup, text=item.label,
            x=sx, y=statY - 8, font=ui.FONT_BOLD, fontSize=6
        }):setFillColor(0.42, 0.58, 0.78)
        display.newText({
            parent=contentGroup, text=item.value,
            x=sx, y=statY + 7, font=ui.FONT_BOLD, fontSize=10
        }):setFillColor(unpack(item.color))
    end

    local actionText = isLeader and "SET" or "LEAVE"
    local actionBtn = display.newRoundedRect(contentGroup, CONTENT_X + CONTENT_W * 0.5 - 35, CONTENT_TOP + 18, 48, 24, 6)
    actionBtn:setFillColor(isLeader and 0.035 or 0.20, isLeader and 0.12 or 0.04, isLeader and 0.28 or 0.05, 0.96)
    actionBtn.strokeWidth = 1.5
    actionBtn:setStrokeColor(isLeader and 0.24 or 0.95, isLeader and 0.70 or 0.22, isLeader and 1.0 or 0.22, 0.78)
    local actionLabel = display.newText({
        parent=contentGroup, text=actionText,
        x=actionBtn.x, y=actionBtn.y, font=ui.FONT_BOLD, fontSize=8
    })
    actionLabel:setFillColor(isLeader and 0.72 or 1.0, isLeader and 0.92 or 0.38, isLeader and 1.0 or 0.35)
    local function onGuildAction()
        if isLeader then
            return showGuildSettings(sg, guild)
        end
        return showLeaveGuildConfirm(sg, guild)
    end
    actionBtn:addEventListener("tap", onGuildAction)
    actionLabel:addEventListener("tap", onGuildAction)

    display.newText({
        parent=contentGroup, text="LEADER STATUS",
        x=CONTENT_X, y=statY + 36, font=ui.FONT_BOLD, fontSize=8, align="center"
    }):setFillColor(0.42, 0.58, 0.78)

    local statusBg = display.newRoundedRect(contentGroup, CONTENT_X, statY + 54, CONTENT_W - 22, 28, 7)
    statusBg:setFillColor(0.04, 0.12, 0.26, 0.94)
    statusBg.strokeWidth = 1.5
    statusBg:setStrokeColor(0.18, 0.50, 0.92, 0.45)
    display.newText({
        parent=contentGroup,
        text=tostring(onlineCount) .. " ONLINE",
        x=CONTENT_X, y=statY + 54, width=CONTENT_W - 34,
        font=ui.FONT_BOLD, fontSize=8, align="center"
    }):setFillColor(0.72, 0.90, 1.0)

    local d2Y = statY + 76
    divLine(contentGroup, CONTENT_X, d2Y, CONTENT_W - 20)

    local summary = guild.description or guild.desc or ""
    if #summary > 200 then summary = string.sub(summary, 1, 197).."..." end
    if summary == "" then summary = "No guild description yet." end

    display.newText({
        parent=contentGroup, text=summary,
        x=CONTENT_X, y=d2Y + 28, width=CONTENT_W - 28,
        font=ui.FONT_BOLD, fontSize=10, align="center"
    }):setFillColor(0.78, 0.86, 0.98)

    local feedY = d2Y + 92
    local feed = {
        "RECENT ACTIVITY",
    }
    for i, line in ipairs(feed) do
        display.newText({
            parent=contentGroup, text=line,
            x=CONTENT_X, y=feedY + (i - 1) * 14, width=CONTENT_W - 28,
            font=ui.FONT_BOLD, fontSize=(i == 1) and 8 or 7, align="center"
        }):setFillColor(i == 1 and 0.42 or 0.62,
                         i == 1 and 0.58 or 0.82,
                         i == 1 and 0.78 or 0.98)
    end
end

-------------------------------------------------
-- CONTENT: CREW
-------------------------------------------------
buildCrew = function(sg, guild)
    clearContent()
    contentGroup = display.newGroup(); sg:insert(contentGroup)
    drawFrame(contentGroup, CONTENT_X, CONTENT_Y, CONTENT_W, CONTENT_H, FRAME_LARGE)

    display.newText({ parent=contentGroup, text="CREW",
        x=CONTENT_X, y=CONTENT_TOP+14, font=ui.FONT_BOLD, fontSize=12
    }):setFillColor(0.62,0.88,1.0)
    divLine(contentGroup, CONTENT_X, CONTENT_TOP+24, CONTENT_W-20)

    local player   = saveUtil.load()
    local isLeader = isGuildLeader(guild, player)
    local members  = getGuildMembers(guild)

    local CARD_H   = 54
    local CARD_PAD = 6
    local cardW    = CONTENT_W - 16
    local headerH  = 30
    local scrollH  = CONTENT_H - headerH - 20
    local totalH   = #members * (CARD_H + CARD_PAD)

    local scrollY   = CONTENT_TOP + headerH + scrollH*0.5
    local container = display.newContainer(contentGroup, CONTENT_W, scrollH)
    container.x     = CONTENT_X
    container.y     = scrollY

    local innerGroup = display.newGroup()
    container:insert(innerGroup)

    local startY = -(scrollH*0.5) + CARD_H*0.5 + CARD_PAD

    if #members == 0 then
        display.newText({ parent=contentGroup,
            text="No members found.",
            x=CONTENT_X, y=CONTENT_Y, width=CONTENT_W-26,
            font=ui.FONT_BOLD, fontSize=11, align="center"
        }):setFillColor(0.62,0.78,0.96)
    end

    for i, m in ipairs(members) do
        local cardY = startY + (i-1)*(CARD_H+CARD_PAD)

        -- card bg
        local card = display.newRoundedRect(innerGroup, 0, cardY, cardW, CARD_H, 8)
        card:setFillColor(0.04, 0.10, 0.22, 0.97)
        card.strokeWidth = 1.5
        card:setStrokeColor(0.18, 0.55, 0.38, 0.55)

        local function openMemberProfile()
            composer.gotoScene("scenes.social_profile", {
                effect = "slideLeft",
                time = 220,
                params = {
                    playerId = m.playerId,
                    playerName = m.name,
                    returnScene = "scenes.guild_home",
                },
            })
            return true
        end

        -- online dot
        local dot = display.newCircle(innerGroup, -cardW*0.5+10, cardY, 4)
        dot:setFillColor(
            m.online and 0.12 or 0.22,
            m.online and 0.92 or 0.22,
            m.online and 0.38 or 0.28)
        if m.online then flicker(dot, 0.5, 1.0, 600) end

        -- avatar circle
        local avX = -cardW*0.5 + 30
        local avC = display.newCircle(innerGroup, avX, cardY, 18)
        avC:setFillColor(0.06, 0.14, 0.36, 0.90)
        avC.strokeWidth = 1.5
        avC:setStrokeColor(0.2, 0.55, 0.9, 0.6)
        display.newText({ parent=innerGroup,
            text=string.upper(string.sub(m.name,1,1)),
            x=avX, y=cardY-1, font=ui.FONT_BOLD, fontSize=13
        }):setFillColor(0.55, 0.85, 1.0)

        -- name + level
        local textX = avX + 26
        local nt = display.newText({ parent=innerGroup, text=m.name,
            x=textX, y=cardY-9, font=ui.FONT_BOLD, fontSize=12, align="left" })
        nt:setFillColor(0.90, 0.95, 1.0); nt.anchorX=0

        local lt = display.newText({ parent=innerGroup, text="LV "..m.level,
            x=textX, y=cardY+8, font=ui.FONT_BOLD, fontSize=8, align="left" })
        lt:setFillColor(0.35, 0.70, 1.0); lt.anchorX=0

        card:addEventListener("tap", openMemberProfile)
        nt:addEventListener("tap", openMemberProfile)
        lt:addEventListener("tap", openMemberProfile)

        -- role badge
        local badgeX = isLeader and (cardW*0.5 - 74) or (cardW*0.5 - 38)
        roleBadge(innerGroup, badgeX, cardY, m.rank)

        if isLeader and m.rank ~= "LEADER" then
            local gearX = cardW*0.5 - 24
            local hit = display.newCircle(innerGroup, gearX, cardY, 14)
            hit:setFillColor(0.03,0.10,0.18,0.96)
            hit.strokeWidth = 1.5
            hit:setStrokeColor(0.28,0.82,1.0,0.72)

            local okGear, gear = pcall(display.newImageRect, innerGroup, "assets/sprites/ui/icons/settings.png", 18, 18)
            if okGear and gear then
                gear.x = gearX
                gear.y = cardY
                gear.isHitTestable = false
            else
                local fallback = display.newText({
                    parent=innerGroup, text="*",
                    x=gearX, y=cardY, font=ui.FONT_BOLD, fontSize=13
                })
                fallback:setFillColor(0.55,0.90,1.0)
                fallback.isHitTestable = false
            end

            hit:addEventListener("tap", function()
                showCrewMemberSettings(sg, guild, m)
                return true
            end)

            if false then
                local pb = display.newRoundedRect(innerGroup, cardW*0.5-80, cardY, 42, 20, 4)
                pb:setFillColor(0.04,0.18,0.36,0.97)
                pb.strokeWidth=1.5; pb:setStrokeColor(0.30,0.65,1.0,0.75)
                local capName = m.name
                display.newText({ parent=innerGroup, text="▲ PROMO",
                    x=cardW*0.5-80, y=cardY, font=ui.FONT_BOLD, fontSize=6
                }):setFillColor(0.45,0.80,1.0)
                pb:addEventListener("tap", function() print("Promote: "..capName); return true end)
            end
            if false then
                local kb = display.newRoundedRect(innerGroup, cardW*0.5-28, cardY, 42, 20, 4)
            kb:setFillColor(0.30,0.04,0.04,0.97)
            kb.strokeWidth=1.5; kb:setStrokeColor(0.90,0.18,0.18,0.75)
            local capName = m.name
            display.newText({ parent=innerGroup, text="KICK",
                x=cardW*0.5-28, y=cardY, font=ui.FONT_BOLD, fontSize=7
            }):setFillColor(1.0,0.35,0.35)
                kb:addEventListener("tap", function() print("Kick: "..capName); return true end)
            end
        end
    end

    -- touch scroll
    local minY = math.min(0, scrollH - totalH - CARD_PAD*2)
    local startTouchY, startGroupY = 0, 0
    container:addEventListener("touch", function(e)
        if e.phase == "began" then
            startTouchY = e.y; startGroupY = innerGroup.y
        elseif e.phase == "moved" then
            local dy = e.y - startTouchY
            innerGroup.y = math.max(minY, math.min(0, startGroupY + dy))
        end
        return true
    end)

    -- member count footer
    display.newText({ parent=contentGroup,
        text=#members.." / "..(guild.maxMembers or 20).." members",
        x=CONTENT_X, y=CONTENT_BOT-10, font=ui.FONT_BOLD, fontSize=8
    }):setFillColor(0.35,0.65,1.0)
end

-------------------------------------------------
-- CONTENT: CHAT
-------------------------------------------------
local function buildChat(sg, guild)
    clearContent()
    contentGroup = display.newGroup(); sg:insert(contentGroup)
    drawFrame(contentGroup, CONTENT_X, CONTENT_Y, CONTENT_W, CONTENT_H, FRAME_LARGE)

    local inputH  = 40
    local headerH = 28
    local scrollH = CONTENT_H - inputH - headerH - 10
    local bw      = CONTENT_W - 16
    local BUBBLE_H = 72
    local BUBBLE_P = 8
    local messages = getGuildMessages(guild)
    local members = getGuildMembers(guild)

    display.newText({ parent=contentGroup, text="GUILD CHAT",
        x=CONTENT_X, y=CONTENT_TOP+14, font=ui.FONT_BOLD, fontSize=12
    }):setFillColor(0.62,0.88,1.0)
    divLine(contentGroup, CONTENT_X, CONTENT_TOP+24, CONTENT_W-20)

    -- container clips content, uses screen coordinates
    local scrollY   = CONTENT_TOP + headerH + scrollH*0.5
    local container = display.newContainer(contentGroup, CONTENT_W, scrollH)
    container.x     = CONTENT_X
    container.y     = scrollY

    local innerGroup = display.newGroup()
    container:insert(innerGroup)

    local totalH  = #messages * (BUBBLE_H + BUBBLE_P)
    local startY  = -(scrollH*0.5) + BUBBLE_H*0.5 + BUBBLE_P

    for i, msg in ipairs(messages) do
        local by = startY + (i-1)*(BUBBLE_H+BUBBLE_P)

        local bubble = display.newRoundedRect(innerGroup, 0, by, bw, BUBBLE_H, 8)
        bubble:setFillColor(0.04, 0.10, 0.22, 0.97)
        bubble.strokeWidth = 1
        bubble:setStrokeColor(0.18, 0.55, 0.38, 0.45)

        local senderName = msg.author or msg.name or "Player"
        local senderRole = "MEMBER"
        local senderSkin = "street_brawler"
        for _, m in ipairs(members) do
            if m.playerId == msg.authorPlayerId or m.name == senderName then
                senderRole = m.rank
                senderSkin = m.skinId or senderSkin
            end
        end
        local rc = ROLE_COLORS[senderRole] or ROLE_COLORS.MEMBER

        drawPortrait(innerGroup, -bw*0.5+28, by, senderName, senderSkin, 44)

        local nt = display.newText({ parent=innerGroup, text=(msg.private and "PRIVATE  " or "") .. senderName,
            x=-bw*0.5+58, y=by-20, font=ui.FONT_BOLD, fontSize=10, align="left" })
        nt:setFillColor(unpack(rc)); nt.anchorX=0

        local tt = display.newText({ parent=innerGroup, text=timeLabels.forMessage(msg),
            x=-bw*0.5+58, y=by-5, font=ui.FONT_BOLD, fontSize=7, align="left" })
        tt:setFillColor(0.36,0.52,0.70); tt.anchorX=0

        local mt = display.newText({ parent=innerGroup, text=msg.body or msg.msg or "",
            x=-bw*0.5+58, y=by+17, width=bw-74,
            font=ui.FONT_BOLD, fontSize=10, align="left" })
        mt:setFillColor(0.78,0.86,1.0); mt.anchorX=0

        local currentPlayerId = session.get().playerId
        local canDelete = msg.id and (msg.authorPlayerId == currentPlayerId or guild.role == "LEADER")
        if canDelete then
            local del = display.newRoundedRect(innerGroup, bw*0.5-14, by-23, 20, 18, 4)
            del:setFillColor(0.26,0.04,0.05,0.95)
            del.strokeWidth = 1
            del:setStrokeColor(1.0,0.24,0.24,0.70)
            local dx = display.newText({ parent=innerGroup, text="X",
                x=del.x, y=del.y, font=ui.FONT_BOLD, fontSize=8 })
            dx:setFillColor(1.0,0.42,0.42)
            dx.isHitTestable = false
            del:addEventListener("tap", function()
                api.guilds.deleteChat(guild.guildId, msg.id, function(response)
                    if response.ok and response.data and response.data.messages then
                        guild._messages = response.data.messages
                        activeGuild = guild
                        buildChat(sg, guild)
                    end
                end)
                return true
            end)
        end
    end

    -- touch scroll
    local minY   = math.min(0, scrollH - totalH - BUBBLE_P*2)
    local startTouchY, startGroupY = 0, 0
    container:addEventListener("touch", function(e)
        if e.phase == "began" then
            startTouchY = e.y; startGroupY = innerGroup.y
        elseif e.phase == "moved" then
            local dy = e.y - startTouchY
            innerGroup.y = math.max(minY, math.min(0, startGroupY + dy))
        end
        return true
    end)

    -- input bar
    local inputY = CONTENT_BOT - inputH*0.5 - 2
    local inputW = CONTENT_W - 46
    local composeObjects = {}
    local function addBase(obj)
        obj._baseY = obj.y
        table.insert(composeObjects, obj)
        return obj
    end
    local function moveChatComposer(raised)
        if chatComposerRaised == raised then return end
        chatComposerRaised = raised
        local yOffset = raised and -CHAT_KEYBOARD_LIFT or 0
        for _, obj in ipairs(composeObjects) do
            if obj and obj.removeSelf then
                transition.to(obj, { y = obj._baseY + yOffset, time = 140 })
            end
        end
        if chatField and chatField.removeSelf then
            transition.to(chatField, { y = chatField._baseY + yOffset, time = 140 })
        end
    end

    addBase(drawFrame(contentGroup, CONTENT_X-20, inputY, inputW, inputH-4, FRAME_THIN_S))

    chatField = native.newTextField(CONTENT_X-20, inputY, inputW-8, inputH-10)
    chatField.placeholder = "Message crew..."
    chatField.font = native.newFont(ui.FONT_BOLD, 10)
    chatField.hasBackground = false
    chatField:setTextColor(0.85, 0.92, 1)
    chatField._baseY = chatField.y

    local sendX   = CONTENT_X + CONTENT_W*0.5 - 18
    local sendBtn = addBase(display.newRoundedRect(contentGroup, sendX, inputY, 32, inputH-8, 6))
    sendBtn:setFillColor(0.04,0.22,0.52,0.97)
    sendBtn.strokeWidth=1.5; sendBtn:setStrokeColor(0.18,0.62,0.40,0.80)
    display.newText({ parent=contentGroup, text="▶",
        x=sendX, y=inputY, font=ui.FONT_BOLD, fontSize=13
    }):setFillColor(0.70,0.92,1.0)
    local privateBtn = addBase(display.newRoundedRect(contentGroup, CONTENT_X - CONTENT_W * 0.5 + 52, inputY - 30, 92, 22, 6))
    privateBtn:setFillColor(guildChatPrivate and 0.04 or 0.03, guildChatPrivate and 0.22 or 0.08, guildChatPrivate and 0.14 or 0.20, 0.96)
    privateBtn.strokeWidth = 1.2
    privateBtn:setStrokeColor(0.22, 0.70, 1.0, 0.58)
    local privateText = display.newText({
        parent=contentGroup,
        text=(guildChatPrivate and "[X] " or "[ ] ") .. "PRIVATE",
        x=privateBtn.x, y=privateBtn.y, font=ui.FONT_BOLD, fontSize=8
    })
    privateText:setFillColor(0.78, 0.92, 1.0)
    privateText.isHitTestable = false
    privateBtn:addEventListener("tap", function()
        guildChatPrivate = not guildChatPrivate
        buildChat(sg, guild)
        return true
    end)
    local function sendChat()
        local body = trim(chatField and chatField.text or "")
        if body == "" then return true end
        if not guild.guildId then return true end
        if chatField then chatField.text = "" end
        native.setKeyboardFocus(nil)
        moveChatComposer(false)
        api.guilds.sendChat(guild.guildId, { body = body, private = guildChatPrivate }, function(response)
            if response.ok and response.data and response.data.messages then
                guild._messages = response.data.messages
                activeGuild = guild
                buildChat(sg, guild)
            end
        end)
        return true
    end

    chatField:addEventListener("userInput", function(event)
        if event.phase == "began" then
            moveChatComposer(true)
        elseif event.phase == "submitted" then
            sendChat()
        end
        return false
    end)
    sendBtn:addEventListener("tap", sendChat)
end
-------------------------------------------------
-- CONTENT: LAND  (6-slot mine grid)
-------------------------------------------------
local TWELVE_HOURS = 12 * 60 * 60
local AUGMENT_TYPES = { "augment_attack","augment_defense","augment_speed","augment_health" }
local CRYSTAL_ROLLS = {
    { key = "crystal_green",  chance = 0.32 },
    { key = "crystal_blue",   chance = 0.28 },
    { key = "crystal_purple", chance = 0.23 },
    { key = "crystal_orange", chance = 0.17 },
}

local LAND_REWARD_META = {
    crystal_green   = { name="Green Crystal",  sprite="assets/sprites/materials/crystal_green.png",  color={0.35,1.0,0.45}, type="Crystal" },
    crystal_blue    = { name="Blue Crystal",   sprite="assets/sprites/materials/crystal_blue.png",   color={0.25,0.65,1.0}, type="Crystal" },
    crystal_purple  = { name="Purple Crystal", sprite="assets/sprites/materials/crystal_purple.png", color={0.75,0.30,1.0}, type="Crystal" },
    crystal_orange  = { name="Orange Crystal", sprite="assets/sprites/materials/crystal_orange.png", color={1.0,0.55,0.18}, type="Crystal" },
    augment_attack  = { name="Atk Augment",    sprite="assets/sprites/materials/augment_attack.png", color={1.0,0.30,0.25}, type="Augment" },
    augment_defense = { name="Def Augment",    sprite="assets/sprites/materials/augment_defense.png", color={0.25,0.65,1.0}, type="Augment" },
    augment_speed   = { name="Spd Augment",    sprite="assets/sprites/materials/augment_speed.png",  color={0.25,1.0,0.55}, type="Augment" },
    augment_health  = { name="HP Augment",     sprite="assets/sprites/materials/augment_health.png", color={1.0,0.25,0.45}, type="Augment" },
}

local function rollCrystalReward()
    local roll = math.random()
    local acc = 0
    for _, entry in ipairs(CRYSTAL_ROLLS) do
        acc = acc + entry.chance
        if roll <= acc then
            return entry.key
        end
    end
    return CRYSTAL_ROLLS[#CRYSTAL_ROLLS].key
end

function trim(value)
    return tostring(value or ""):match("^%s*(.-)%s*$")
end

function cleanupChatField(remove)
    native.setKeyboardFocus(nil)
    if chatField then
        chatField.isVisible = false
        if remove and chatField.removeSelf then
            chatField:removeSelf()
            chatField = nil
        end
    end
end

local function fmtTime(s)
    if s<=0 then return "READY" end
    local h=math.floor(s/3600); local m=math.floor((s%3600)/60)
    if h>0 then return h.."h "..string.format("%02d",m).."m" end
    return m.."m "..string.format("%02d",s%60).."s"
end

local function buildLand(sg, guild)
    clearContent()
    contentGroup = display.newGroup(); sg:insert(contentGroup)
    drawFrame(contentGroup, CONTENT_X, CONTENT_Y, CONTENT_W, CONTENT_H, FRAME_LARGE)

    display.newText({ parent=contentGroup, text="GUILD MINES",
        x=CONTENT_X, y=CONTENT_TOP+14, font=ui.FONT_BOLD, fontSize=13
    }):setFillColor(0.62,0.88,1.0)
    display.newText({ parent=contentGroup, text="Tap a slot to place a mine  ·  12 hr cycles",
        x=CONTENT_X, y=CONTENT_TOP+27, font=ui.FONT_BOLD, fontSize=7
    }):setFillColor(0.38,0.52,0.65)
    divLine(contentGroup, CONTENT_X, CONTENT_TOP+36, CONTENT_W-18)

    local player   = saveUtil.load()
    local isLeader = isGuildLeader(guild, player)
    player.guildSlots = player.guildSlots or {}

    local COLS=2; local ROWS=3; local PAD=7
    local gridTop=CONTENT_TOP+40; local gridH=CONTENT_H-40-6
    local cellW=(CONTENT_W-PAD*(COLS+1))/COLS
    local cellH=(gridH-PAD*(ROWS+1))/ROWS

    local BUILDINGS = {
        crystal_mine  = { id="crystal_mine",  name="Crystal Mine",  sprite="assets/sprites/materials/crystal_mine.png",  reward="crystal_random", rewardAmt=3, color={0.25,0.72,1.0} },
        augment_drill = { id="augment_drill", name="Augment Drill", sprite="assets/sprites/materials/augment_drill.png", reward="augment_random", rewardAmt=1, color={0.55,1.0,0.30} },
    }

    local splitSlot=nil; local splitGroup=nil
    local function closeSplit()
        if splitGroup and splitGroup.removeSelf then splitGroup:removeSelf() end
        splitGroup=nil; splitSlot=nil
    end
    local function refreshLand() buildLand(sg, guild) end

    for idx=1,6 do
        local col=((idx-1)%COLS); local row=math.floor((idx-1)/COLS)
        local cx=CONTENT_X-CONTENT_W*0.5+PAD+col*(cellW+PAD)+cellW*0.5
        local cy=gridTop+PAD+row*(cellH+PAD)+cellH*0.5
        local slot=player.guildSlots[idx]
        local bdef=slot and BUILDINGS[slot.building]
        local sl=slot and math.max(0, TWELVE_HOURS-(os.time()-slot.startTime)) or 0
        local running=slot~=nil; local ready=running and sl<=0

        local cellBg=display.newRoundedRect(contentGroup, cx, cy, cellW, cellH, 12)
        if ready then
            cellBg:setFillColor(0.05,0.22,0.10,0.97)
            cellBg.strokeWidth=2; cellBg:setStrokeColor(0.24,0.72,1.0,0.82)
        elseif running and bdef then
            cellBg:setFillColor(0.04,0.10,0.24,0.97)
            cellBg.strokeWidth=1.5
            cellBg:setStrokeColor(bdef.color[1]*0.5,bdef.color[2]*0.5,bdef.color[3]*0.5,0.65)
        else
            cellBg:setFillColor(0.03,0.06,0.14,0.95)
            cellBg.strokeWidth=1.5; cellBg:setStrokeColor(0.14,0.32,0.24,0.50)
        end

        if slot and bdef then
            local sprSz=math.min(cellW-10,cellH*0.50)
            local sprY=cy-cellH*0.5+sprSz*0.5+8
            local okS,spr=pcall(display.newImageRect, contentGroup, bdef.sprite, sprSz, sprSz)
            if okS and spr then spr.x=cx; spr.y=sprY end

            display.newText({ parent=contentGroup, text=bdef.name,
                x=cx, y=cy+cellH*0.5-40, font=ui.FONT_BOLD, fontSize=8, align="center", width=cellW-6
            }):setFillColor(ready and 0.28 or 0.72, ready and 1.0 or 0.88, ready and 0.45 or 1.0)

            local barW=cellW-14; local barH2=10; local barY=cy+cellH*0.5-26
            local barBg=display.newRoundedRect(contentGroup, cx, barY, barW, barH2, 4)
            barBg:setFillColor(0.04,0.05,0.12)
            barBg.strokeWidth=1; barBg:setStrokeColor(0.12,0.28,0.22,0.55)

            local fillR=math.min(1,1-(sl/TWELVE_HOURS))
            if fillR>0 then
                local fw=math.max((barW-4)*fillR,3)
                local bf=display.newRoundedRect(contentGroup, cx-(barW-4)*0.5+fw*0.5, barY, fw, barH2-4, 3)
                bf:setFillColor(ready and 0.18 or bdef.color[1]*0.6+0.2,
                                ready and 0.92 or bdef.color[2]*0.6+0.2,
                                ready and 0.38 or bdef.color[3]*0.6+0.2)
                if ready then flicker(bf,0.7,1.0,500) end
            end

            local timerLbl=ready and "READY" or fmtTime(sl)
            local tt=display.newText({ parent=contentGroup, text=timerLbl,
                x=cx, y=barY, font=ui.FONT_BOLD, fontSize=6, align="center" })
            tt:setFillColor(ready and 0.28 or 0.45, ready and 1.0 or 0.70, ready and 0.45 or 0.45)

            if running and not ready then
                local capTT=tt; local capSlot=slot
                local tk=timer.performWithDelay(1000, function()
                    if capTT and capTT.removeSelf then
                        local sl2=math.max(0,TWELVE_HOURS-(os.time()-capSlot.startTime))
                        capTT.text=sl2<=0 and "READY" or fmtTime(sl2)
                        if sl2<=0 then capTT:setFillColor(0.28,1.0,0.45) end
                    end
                end, 0)
                table.insert(TIMERS, tk)
            end

            local actLbl=ready and (isLeader and "TAP TO COLLECT" or "READY") or "RUNNING"
            local al=display.newText({ parent=contentGroup, text=actLbl,
                x=cx, y=cy+cellH*0.5-13, font=ui.FONT_BOLD, fontSize=6, align="center" })
            al:setFillColor(ready and 0.28 or 0.35, ready and 1.0 or 0.55, ready and 0.45 or 0.38)
            if ready and isLeader then flicker(al,0.6,1.0,700) end

            if isLeader then
                local rx=cx+cellW*0.5-11; local ry=cy-cellH*0.5+11
                local rb=display.newCircle(contentGroup, rx, ry, 10)
                rb:setFillColor(0.32,0.04,0.04,0.95)
                rb.strokeWidth=1.5; rb:setStrokeColor(0.88,0.18,0.18,0.80)
                display.newText({ parent=contentGroup, text="×",
                    x=rx, y=ry-1, font=ui.FONT_BOLD, fontSize=12
                }):setFillColor(1.0,0.30,0.30)
                local capIdx=idx
                rb:addEventListener("tap", function()
                    local p=saveUtil.load(); p.guildSlots=p.guildSlots or {}
                    p.guildSlots[capIdx]=nil; saveUtil.save(p); sync.pushPlayerSnapshot(p); refreshLand()
                    return true
                end)
            end

            local capIdx=idx; local capBdef=bdef
            cellBg:addEventListener("tap", function()
                if ready and isLeader then
                    local rk=capBdef.reward
                    if rk=="augment_random" then rk=AUGMENT_TYPES[math.random(#AUGMENT_TYPES)] end
                    if rk=="crystal_random" then rk=rollCrystalReward() end
                    local meta=LAND_REWARD_META[rk] or { name=rk, type="Material" }
                    api.guilds.collectLand(guild.guildId, {
                        key=rk, name=meta.name, sprite=meta.sprite,
                        color=meta.color, type=meta.type, qty=capBdef.rewardAmt,
                    }, function(response)
                        if response and response.ok then
                            if response.data and response.data.player then
                                sync.applyPlayerSnapshot(response.data.player, saveUtil.activeSlot)
                            end
                            local p=saveUtil.load(); p.guildSlots=p.guildSlots or {}
                            p.guildSlots[capIdx]={ building=capBdef.id, startTime=os.time() }
                            saveUtil.save(p); sync.pushPlayerSnapshot(p); refreshLand()
                            rewardPopup.show(sg, {
                                title="OBTAINED",
                                key=rk,
                                icon=meta.sprite,
                                accent=meta.color or capBdef.color,
                                message="OBTAINED " .. tostring(capBdef.rewardAmt) .. " " .. string.upper(tostring(meta.name or rk)),
                                detail="SENT TO GUILD VAULT",
                                button="COLLECT",
                            })
                        else
                            rewardPopup.show(sg, {
                                title="COLLECT FAILED",
                                key="jail",
                                accent={1.0, 0.32, 0.28},
                                message="COULD NOT SEND REWARD",
                                detail="Try again after the guild sync catches up.",
                                button="OK",
                                noBurst=true,
                            })
                        end
                    end)
                end
                return true
            end)

        else
            if not isLeader then
                local lt=display.newText({ parent=contentGroup, text="🔒",
                    x=cx, y=cy, font=ui.FONT_BOLD, fontSize=22 })
                lt.isHitTestable=false
            else
                local pt=display.newText({ parent=contentGroup, text="+",
                    x=cx, y=cy, font=ui.FONT_BOLD, fontSize=32 })
                pt:setFillColor(0.22,0.55,0.35); pt.isHitTestable=false

                local capIdx=idx; local capCx=cx; local capCy=cy
                cellBg:addEventListener("tap", function()
                    closeSplit(); splitSlot=capIdx
                    splitGroup=display.newGroup(); contentGroup:insert(splitGroup)
                    local halfH=cellH*0.5-2

                    local topBg=display.newRoundedRect(splitGroup, capCx, capCy-halfH*0.5-1, cellW, halfH, 10)
                    topBg:setFillColor(0.04,0.14,0.32,0.98)
                    topBg.strokeWidth=2; topBg:setStrokeColor(0.25,0.72,1.0,0.85)
                    local okT,tSpr=pcall(display.newImageRect, splitGroup, "assets/sprites/materials/crystal_mine.png", halfH-14, halfH-14)
                    if okT and tSpr then tSpr.x=capCx-20; tSpr.y=capCy-halfH*0.5-1 end
                    local tn=display.newText({ parent=splitGroup, text="Crystal Mine",
                        x=capCx+16, y=capCy-halfH*0.5-1, font=ui.FONT_BOLD, fontSize=8, align="center", width=cellW*0.5 })
                    tn:setFillColor(0.55,0.88,1.0)
                    topBg:addEventListener("tap", function()
                        local p=saveUtil.load(); p.guildSlots=p.guildSlots or {}
                        p.guildSlots[capIdx]={ building="crystal_mine", startTime=os.time() }
                        saveUtil.save(p); sync.pushPlayerSnapshot(p); closeSplit(); refreshLand(); return true
                    end)

                    local botBg=display.newRoundedRect(splitGroup, capCx, capCy+halfH*0.5+1, cellW, halfH, 10)
                    botBg:setFillColor(0.04,0.18,0.10,0.98)
                    botBg.strokeWidth=2; botBg:setStrokeColor(0.55,1.0,0.30,0.85)
                    local okB,bSpr=pcall(display.newImageRect, splitGroup, "assets/sprites/materials/augment_drill.png", halfH-14, halfH-14)
                    if okB and bSpr then bSpr.x=capCx-20; bSpr.y=capCy+halfH*0.5+1 end
                    local bn=display.newText({ parent=splitGroup, text="Augment Drill",
                        x=capCx+16, y=capCy+halfH*0.5+1, font=ui.FONT_BOLD, fontSize=8, align="center", width=cellW*0.5 })
                    bn:setFillColor(0.55,1.0,0.35)
                    botBg:addEventListener("tap", function()
                        local p=saveUtil.load(); p.guildSlots=p.guildSlots or {}
                        p.guildSlots[capIdx]={ building="augment_drill", startTime=os.time() }
                        saveUtil.save(p); sync.pushPlayerSnapshot(p); closeSplit(); refreshLand(); return true
                    end)

                    local xb=display.newCircle(splitGroup, capCx+cellW*0.5-11, capCy-cellH*0.5+11, 10)
                    xb:setFillColor(0.28,0.04,0.04,0.97)
                    xb.strokeWidth=1.5; xb:setStrokeColor(0.88,0.18,0.18,0.80)
                    display.newText({ parent=splitGroup, text="×",
                        x=xb.x, y=xb.y-1, font=ui.FONT_BOLD, fontSize=12
                    }):setFillColor(1.0,0.30,0.30)
                    xb:addEventListener("tap", function() closeSplit(); return true end)
                    return true
                end)
            end
        end
    end
end

-------------------------------------------------
-- CONTENT: PLACEHOLDER
-------------------------------------------------
local function buildJail(sg, guild)
    clearContent()
    contentGroup=display.newGroup(); sg:insert(contentGroup)
    drawFrame(contentGroup, CONTENT_X, CONTENT_Y, CONTENT_W, CONTENT_H, FRAME_LARGE)

    display.newText({ parent=contentGroup, text="JAIL",
        x=CONTENT_X, y=CONTENT_TOP+14, font=ui.FONT_BOLD, fontSize=12
    }):setFillColor(1.0,0.42,0.42)
    divLine(contentGroup, CONTENT_X, CONTENT_TOP+24, CONTENT_W-20)

    display.newText({ parent=contentGroup,
        text="10% arena tax for 24 hours",
        x=CONTENT_X, y=CONTENT_TOP+44, width=CONTENT_W-24,
        font=ui.FONT_BOLD, fontSize=8, align="center"
    }):setFillColor(0.68,0.84,1.0)

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

    local function renderList(list)
        if not contentGroup or not contentGroup.removeSelf then return end
        if not list or #list == 0 then
            display.newText({ parent=contentGroup,
                text="No prisoners.",
                x=CONTENT_X, y=CONTENT_Y+8, width=CONTENT_W-30,
                font=ui.FONT_BOLD, fontSize=11, align="center"
            }):setFillColor(0.55,0.75,0.96)
            return
        end
        local startY = CONTENT_TOP + 76
        for i, entry in ipairs(list) do
            local y = startY + (i - 1) * 36
            local row = display.newRoundedRect(contentGroup, CONTENT_X, y, CONTENT_W - 18, 30, 6)
            row:setFillColor(0.08,0.06,0.12,0.96)
            row.strokeWidth = 1.2
            row:setStrokeColor(0.90,0.20,0.22,0.62)
            local name = display.newText({
                parent=contentGroup, text=tostring(entry.name or "Player"),
                x=CONTENT_X - CONTENT_W*0.5 + 20, y=y-1,
                width=CONTENT_W*0.52, font=ui.FONT_BOLD, fontSize=9, align="left"
            })
            name.anchorX=0
            name:setFillColor(0.96,0.90,0.90)
            display.newText({
                parent=contentGroup, text=timeLeftLabel(entry.releaseAt),
                x=CONTENT_X + CONTENT_W*0.28, y=y-1,
                width=CONTENT_W*0.34, font=ui.FONT_BOLD, fontSize=8, align="center"
            }):setFillColor(1.0,0.55,0.45)
        end
    end

    local loadingText = display.newText({ parent=contentGroup,
        text="LOADING...",
        x=CONTENT_X, y=CONTENT_Y+8, width=CONTENT_W-30,
        font=ui.FONT_BOLD, fontSize=10, align="center"
    })
    loadingText:setFillColor(0.55,0.75,0.96)

    api.guilds.jail(guild.guildId, function(response)
        if loadingText and loadingText.removeSelf then loadingText:removeSelf() end
        if response and response.ok and response.data then
            renderList(response.data.jail or {})
        else
            display.newText({ parent=contentGroup,
                text="Could not load jail.",
                x=CONTENT_X, y=CONTENT_Y+8, width=CONTENT_W-30,
                font=ui.FONT_BOLD, fontSize=10, align="center"
            }):setFillColor(1.0,0.45,0.45)
        end
    end)
end

local function buildPlaceholder(sg, label, icon)
    clearContent()
    contentGroup=display.newGroup(); sg:insert(contentGroup)
    drawFrame(contentGroup, CONTENT_X, CONTENT_Y, CONTENT_W, CONTENT_H, FRAME_LARGE)
    display.newText({ parent=contentGroup, text=icon,
        x=CONTENT_X, y=CONTENT_Y-22, font=ui.FONT_BOLD, fontSize=34 })
    display.newText({ parent=contentGroup, text=label,
        x=CONTENT_X, y=CONTENT_Y+16, font=ui.FONT_BOLD, fontSize=15
    }):setFillColor(0.35,0.80,1.0)
    display.newText({ parent=contentGroup, text="Coming soon",
        x=CONTENT_X, y=CONTENT_Y+36, font=ui.FONT_BOLD, fontSize=10
    }):setFillColor(0.38,0.48,0.62)
end

local function renderCurrentTab(sg, guild)
    if headerNameText and guild and guild.name then
        headerNameText.text = string.upper(guild.name)
    end
    local label = activeRightTab > 0 and RIGHT_TABS[activeRightTab].label or "HOME"
    if     label=="CREW" then buildCrew(sg, guild)
    elseif label=="CHAT" then buildChat(sg, guild)
    elseif label=="LAND" then buildLand(sg, guild)
    elseif label=="JAIL" then buildJail(sg, guild)
    elseif label=="NEWS" then buildPlaceholder(sg, "NEWS", "NEWS")
    else                      buildHomePixelWar(sg, guild)
    end
end

refreshActiveGuild = function(sg, guild, callback)
    loadGuildDetails(guild or activeGuild or {}, function(loadedGuild)
        activeGuild = loadedGuild
        if loadedGuild and loadedGuild.guildId then
            guildContext.setActiveGuild(loadedGuild.guildId, (loadedGuild.role == "LEADER") and "hostedGuild" or "joinedGuild")
        end
        applyGuildToLocalPlayer(loadedGuild)
        if sg then renderCurrentTab(sg, activeGuild) end
        if callback then callback(activeGuild) end
    end)
end

local function guildFromParams(player, params)
    return guildContext.getActiveGuild(player, params)
end

-------------------------------------------------
-- SET RIGHT TAB
-------------------------------------------------
local function setRightTab(idx, sg, guild)
    if idx==activeRightTab then return end
    activeRightTab=idx
    for i, bg in ipairs(rightTabBgs) do
        local active=(i==idx)
        bg:setFillColor(active and 0.04 or 0.02, active and 0.14 or 0.055, active and 0.30 or 0.13, 0.97)
        bg.strokeWidth=active and 2 or 1
        bg:setStrokeColor(active and 0.24 or 0.12, active and 0.72 or 0.38, active and 1.0 or 0.76, active and 0.90 or 0.44)
        rightTabTxts[i]:setFillColor(active and 0.84 or 0.62, active and 0.96 or 0.82, active and 1.0 or 0.96)
        if rightTabIcons[i] then
            rightTabIcons[i].alpha = active and 1.0 or 0.72
            rightTabIcons[i].xScale = active and 1.0 or 0.92
            rightTabIcons[i].yScale = active and 1.0 or 0.92
        end
    end
    local label=RIGHT_TABS[idx].label
    if label=="CREW" or label=="CHAT" then
        refreshActiveGuild(sg, guild)
    elseif label=="LAND" then buildLand(sg, guild)
    elseif label=="JAIL" then buildJail(sg, guild)
    elseif label=="NEWS" then buildPlaceholder(sg, "NEWS", "📰")
    else                      refreshActiveGuild(sg, guild)
    end
end

-------------------------------------------------
-- SCENE CREATE
-------------------------------------------------
function scene:create(event)
    local sg     = self.view
    sceneGroup   = sg

    local player = saveUtil.load()
    local guild  = enrichLocalGuild(guildFromParams(player, event and event.params) or {
        name="Unknown Guild", level=1, xp=0, xpMax=1000,
        rep=320, gold=0, role="MEMBER",
        members=0, maxMembers=20, description="",
    })
    activeGuild = guild

    -- background
    local bg = display.newImage("assets/sprites/ui/bg_home_grid.png")
    if bg then
        bg:scale(math.max(SW / bg.width, SH / bg.height), math.max(SW / bg.width, SH / bg.height))
        bg.x = CX
        bg.y = CY
        sg:insert(bg)
    else
        bg = display.newRect(sg, CX, CY, SW, SH)
        bg:setFillColor(0.02, 0.03, 0.08)
    end

    local dim = display.newRect(sg, CX, CY, SW, SH)
    dim:setFillColor(0, 0, 0, 0.18)
    dim.isHitTestable = false

    for i=1,24 do
        local dot = display.newRect(sg,
            8 + math.random() * (SW - 16),
            18 + math.random() * (SH - 68),
            math.random(2, 4), math.random(2, 4))
        dot:setFillColor(0.32, 0.72, 1.0, 0.08 + math.random() * 0.14)
        dot.isHitTestable = false
    end

    -- header
    drawFrame(sg, CX, HEADER_Y, SW-6, HEADER_H, FRAME_SMALL)
    local nameT=display.newText({ parent=sg, text=string.upper(guild.name),
        x=CX, y=HEADER_Y-16, font=ui.FONT_BOLD, fontSize=16, align="center" })
    headerNameText = nameT
    nameT:setFillColor(0.82, 0.96, 1.0)

    local iconY=HEADER_Y+14; local repX=CX-50; local goldX=CX+50
    display.newText({ parent=sg, text="🔷", x=repX-14, y=iconY, font=ui.FONT_BOLD, fontSize=16 })
    display.newText({ parent=sg, text=tostring(guild.rep or 320),
        x=repX+10, y=iconY, font=ui.FONT_BOLD, fontSize=12, align="left"
    }):setFillColor(0.72,0.92,1.0)
    display.newText({ parent=sg, text="🪙", x=goldX-14, y=iconY, font=ui.FONT_BOLD, fontSize=16 })
    display.newText({ parent=sg, text=tostring(guild.gold or 0),
        x=goldX+10, y=iconY, font=ui.FONT_BOLD, fontSize=12, align="left"
    }):setFillColor(1.0,0.82,0.20)

    local repMask = display.newRect(sg, repX - 14, iconY, 22, 20)
    repMask:setFillColor(0.025, 0.065, 0.16, 0.98)
    display.newText({ parent=sg, text="◇", x=repX-14, y=iconY, font=ui.FONT_BOLD, fontSize=16 }):setFillColor(0.72, 0.92, 1.0)
    local goldMask = display.newRect(sg, goldX - 14, iconY, 22, 20)
    goldMask:setFillColor(0.025, 0.065, 0.16, 0.98)
    display.newText({ parent=sg, text="◎", x=goldX-14, y=iconY, font=ui.FONT_BOLD, fontSize=16 }):setFillColor(1.0, 0.82, 0.20)

    -- right tab strip
    local totalTabsH=#RIGHT_TABS*RIGHT_TAB_H+(#RIGHT_TABS-1)*4
    local tabsStartY=CONTENT_TOP+(CONTENT_H-totalTabsH)*0.5

    for i, tab in ipairs(RIGHT_TABS) do
        local ty=tabsStartY+(i-1)*(RIGHT_TAB_H+4)+RIGHT_TAB_H*0.5
        local tabBg=display.newRoundedRect(sg, RIGHT_X, ty, RIGHT_W - 6, RIGHT_TAB_H - 4, 7)
        tabBg:setFillColor(0.02, 0.055, 0.13, 0.96)
        tabBg.strokeWidth=1.25
        tabBg:setStrokeColor(0.12, 0.38, 0.76, 0.46)
        rightTabBgs[i]=tabBg
        local okIcon, icon = pcall(display.newImageRect, sg, "assets/sprites/ui/icons/" .. tab.icon .. ".png", 30, 30)
        if okIcon and icon then
            icon.x = RIGHT_X
            icon.y = ty - 10
            icon.alpha = 0.72
            rightTabIcons[i] = icon
        end
        local tt=display.newText({ parent=sg, text=tab.label,
            x=RIGHT_X, y=ty + RIGHT_TAB_H * 0.5 - 8, font=ui.FONT_BOLD, fontSize=7, align="center", width=RIGHT_W-8 })
        tt:setFillColor(0.62, 0.82, 0.96); rightTabTxts[i]=tt
        local ci=i
        tabBg:addEventListener("tap", function() setRightTab(ci,sg,activeGuild or guild); return true end)
        tt:addEventListener("tap",    function() setRightTab(ci,sg,activeGuild or guild); return true end)
        if icon then icon:addEventListener("tap", function() setRightTab(ci,sg,activeGuild or guild); return true end) end
    end

    -- close button under the guild banner
    local closeY=HEADER_Y+HEADER_H*0.5+22
    local closeBg=display.newRoundedRect(sg, RIGHT_X, closeY, 38, 34, 8)
    closeBg:setFillColor(0.03,0.10,0.24,0.96)
    closeBg.strokeWidth=1.5; closeBg:setStrokeColor(0.24,0.70,1.0,0.70)
    local closeLabel=display.newText({ parent=sg, text="X",
        x=RIGHT_X, y=closeY, font=ui.FONT_BOLD, fontSize=13
    })
    closeLabel:setFillColor(0.72,0.92,1.0)
    closeBg:addEventListener("tap", function()
        composer.gotoScene("scenes.home",{effect="slideRight",time=220}); return true
    end)
    closeLabel:addEventListener("tap", function()
        composer.gotoScene("scenes.home",{effect="slideRight",time=220}); return true
    end)

    guildNav.build(sg, "HOME")

    -- default: show HOME content
    activeRightTab = 0
    buildHomePixelWar(sg, activeGuild)
end

-------------------------------------------------
-- SCENE SHOW / HIDE
-------------------------------------------------
function scene:show(event)
    if event.phase ~= "did" then return end

    local player = saveUtil.load()
    local guild  = guildFromParams(player, event and event.params) or {
        name="Unknown Guild", level=1, xp=0, xpMax=1000,
        rep=320, gold=0, role="MEMBER",
        members=0, maxMembers=20, description="",
    }

    for i, bg in ipairs(rightTabBgs) do
        if bg and bg.setFillColor then
            bg:setFillColor(0.02, 0.055, 0.13, 0.97)
            bg.strokeWidth = 1
            bg:setStrokeColor(0.12, 0.38, 0.76, 0.46)
        end
        if rightTabTxts[i] then
            rightTabTxts[i]:setFillColor(0.62, 0.82, 0.96)
        end
        if rightTabIcons[i] then
            rightTabIcons[i].alpha = 0.72
            rightTabIcons[i].xScale = 0.92
            rightTabIcons[i].yScale = 0.92
        end
    end

    activeRightTab = 0
    refreshActiveGuild(sceneGroup, guild)
end

function scene:hide(event)
    if event.phase ~= "will" then return end
    rewardPopup.closeActive(true)
    for _,t in ipairs(TIMERS) do pcall(function() timer.cancel(t) end) end
    TIMERS={}
    clearContent()
    rightTabBgs={}; rightTabTxts={}
    activeRightTab=0
end

scene:addEventListener("create", scene)
scene:addEventListener("show",   scene)
scene:addEventListener("hide",   scene)
return scene
