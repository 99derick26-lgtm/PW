local composer = require("composer")
local scene = composer.newScene()

local api = require("utils.api")
local save = require("utils.save")
local ui = require("utils.ui")
local guildContext = require("utils.guild_context")
local battleContext = require("utils.battle_context")
local rewardPopup = require("utils.reward_popup")

local CX = display.contentCenterX
local CY = display.contentCenterY
local SW = display.contentWidth
local SH = display.contentHeight

local activeGuildId
local activeGuild
local activeMembers = {}
local activeMessages = {}
local activeJail = {}
local activePendingWar
local contentGroup
local bottomGroup
local chatField
local privateChat = false
local warTimer
local warCountdownText
local drawBottom
local declareWarErrorMessage
local FRAME_LARGE = "assets/sprites/ui/frames/border_large.png"

local FRAME_X = CX
local FRAME_TOP = 48
local FRAME_W = SW - 16
local FRAME_H = SH - 126
local FRAME_Y = FRAME_TOP + FRAME_H * 0.5
local CONTENT_TOP = FRAME_TOP + 28
local CONTENT_W = FRAME_W - 42
local CONTENT_BOT = FRAME_TOP + FRAME_H - 54
local TAB_Y = SH - 26

local function text(parent, value, x, y, size, color, width, align)
    local obj = display.newText({
        parent=parent, text=value or "",
        x=x, y=y, width=width,
        font=ui.FONT_BOLD, fontSize=size,
        align=align or "center",
    })
    obj:setFillColor(unpack(color))
    return obj
end

local function getJoinedGuild(player)
    return guildContext.getJoinedGuild(player)
end

local function getLeaderGuild(player)
    return guildContext.getHostedGuild(player)
end

local function canApplyToActiveGuild()
    local joinedGuild = getJoinedGuild(save.load())
    return not (joinedGuild and joinedGuild.guildId)
end

local function canDeclareWarOnActiveGuild()
    local leaderGuild = getLeaderGuild(save.load())
    return leaderGuild and leaderGuild.guildId and activeGuildId and leaderGuild.guildId ~= activeGuildId
end

local function secondsUntil(value)
    if type(value) == "number" then
        return math.max(0, math.floor((value / 1000) - os.time()))
    end
    local pattern = "^(%d+)%-(%d+)%-(%d+)T(%d+):(%d+):(%d+)"
    local y, mo, d, h, mi, s = tostring(value or ""):match(pattern)
    if not y then return 0 end
    local target = os.time({
        year=tonumber(y), month=tonumber(mo), day=tonumber(d),
        hour=tonumber(h), min=tonumber(mi), sec=tonumber(s),
        isdst=false,
    })
    return math.max(0, target - os.time(os.date("!*t")))
end

local function warTimerLabel()
    local left = secondsUntil(activePendingWar and (activePendingWar.readyAtMs or activePendingWar.readyAt))
    return string.format("%d:%02d", math.floor(left / 60), left % 60)
end

local function prepareLootOpponent(response)
    local data = response and response.data or {}
    local defenders = data.defenders or {}
    local primary = defenders[1]
    if not primary then return nil end

    primary.id = "enemy:leader"
    primary.guildLoot = true
    primary.guildLootGuildId = activeGuildId
    primary.guildLootGuild = data.guild or activeGuild
    primary.guildTeamHp = data.guildTeamHp
    primary.name = (data.guild and data.guild.name) or (activeGuild and activeGuild.name) or primary.name
    primary.pets = {}
    primary.equipped = primary.equipped or {}
    primary.equipped.pets = {}
    primary.defenders = {}
    for i = 2, #defenders do
        defenders[i].id = "enemy:leader:" .. tostring(i)
        defenders[i].pets = {}
        defenders[i].equipped = defenders[i].equipped or {}
        defenders[i].equipped.pets = {}
        table.insert(primary.defenders, defenders[i])
    end
    return primary
end

local LOOT_REWARD_META = {
    gold = { icon="assets/sprites/ui/icons/gold.png", accent={1.0,0.84,0.24}, name="Gold" },
    crystal_green = { icon="assets/sprites/materials/crystal_green.png", accent={0.35,1.0,0.45}, name="Green Crystal" },
    crystal_blue = { icon="assets/sprites/materials/crystal_blue.png", accent={0.25,0.65,1.0}, name="Blue Crystal" },
    crystal_purple = { icon="assets/sprites/materials/crystal_purple.png", accent={0.75,0.30,1.0}, name="Purple Crystal" },
    crystal_orange = { icon="assets/sprites/materials/crystal_orange.png", accent={1.0,0.55,0.18}, name="Orange Crystal" },
    augment_attack = { icon="assets/sprites/materials/augment_attack.png", accent={1.0,0.30,0.25}, name="Atk Augment" },
    augment_defense = { icon="assets/sprites/materials/augment_defense.png", accent={0.25,0.65,1.0}, name="Def Augment" },
    augment_speed = { icon="assets/sprites/materials/augment_speed.png", accent={0.25,1.0,0.55}, name="Spd Augment" },
    augment_health = { icon="assets/sprites/materials/augment_health.png", accent={1.0,0.25,0.45}, name="HP Augment" },
}

local function showLootResultPopup(result)
    local report = result.report or {}
    if result.won then
        local reward = report.reward or {}
        local key = reward.key or reward.type or "gold"
        local meta = LOOT_REWARD_META[key] or { icon=reward.sprite, accent={0.28,0.76,1.0}, name=reward.name or "Loot" }
        local amount = tonumber(reward.amount) or 1
        rewardPopup.show(scene.view, {
            title="LOOT SECURED",
            key=key,
            icon=meta.icon or reward.sprite,
            accent=meta.accent,
            message="YOU OBTAINED " .. tostring(amount) .. " " .. string.upper(tostring(reward.name or meta.name or "LOOT")),
            detail="TAKEN FROM GUILD VAULT",
            button="COLLECT",
        })
    else
        rewardPopup.show(scene.view, {
            title="CAPTURED",
            key="jail",
            icon="assets/sprites/ui/icons/jail.png",
            accent={1.0,0.32,0.28},
            message="YOU WERE THROWN IN JAIL",
            detail="For 24 hours, 10% of your arena earnings are taxed and you cannot loot other guilds.",
            button="OK",
            noBurst=true,
        })
    end
end

local function startGuildLoot()
    if not activeGuildId then return true end
    local requestedGuildId = activeGuildId
    api.guilds.prepareLoot(requestedGuildId, function(response)
        if requestedGuildId ~= activeGuildId then
            return
        end
        local responseGuildId = response and response.data and response.data.guild and response.data.guild.guildId
        if responseGuildId and responseGuildId ~= requestedGuildId then
            native.showAlert("Loot Failed", "The guild loot response did not match the guild you selected. Try again.", { "OK" })
            return
        end
        if response.ok then
            local opponent = prepareLootOpponent(response)
            if opponent then
                battleContext.startGuildLoot(opponent, {
                    guildId = activeGuildId,
                    guild = (response.data and response.data.guild) or activeGuild,
                    defenders = response.data and response.data.defenders or {},
                })
                composer.gotoScene("scenes.arena_battle", { effect="slideLeft", time=220 })
                return
            end
        end

        local errorId = response.data and response.data.error
        local message = "Could not start guild loot combat yet."
        if response.offline then
            message = "Online guild loot needs the server connection enabled."
        elseif response.status == 404 then
            message = "The server does not have guild loot combat enabled yet. Restart the server and try again."
        elseif response.status == 401 then
            message = "Your online session expired. Log in again and try guild loot."
        elseif response.status and response.status >= 500 then
            message = "The server hit an error preparing that guild fight."
        end
        if errorId == "guild_level_out_of_range" then
            local guildLevel = response.data.guildLevel or "?"
            local playerLevel = response.data.playerLevel or "?"
            message = "Guild average level must be within 3 levels of you. You are Lv." .. tostring(playerLevel) .. "; guild is Lv." .. tostring(guildLevel) .. "."
        elseif errorId == "guild_jail_active" then
            message = "You are in " .. tostring(response.data.guildName or "a guild") .. " jail. You cannot loot guilds until your 24 hour sentence ends."
        elseif errorId == "cannot_loot_own_guild" then
            message = "You cannot loot your own guild."
        elseif errorId == "guild_not_found" then
            message = "That guild could not be found anymore."
        elseif errorId then
            message = "Could not start guild loot combat: " .. tostring(errorId)
        end
        native.showAlert("Loot Failed", message, { "OK" })
    end)
    return true
end

local function clearContent()
    if chatField and chatField.removeSelf then chatField:removeSelf() end
    chatField = nil
    if contentGroup and contentGroup.removeSelf then contentGroup:removeSelf() end
    contentGroup = nil
end

local function stopWarTimer()
    if warTimer then
        timer.cancel(warTimer)
        warTimer = nil
    end
    warCountdownText = nil
end

local function drawFrame(parent)
    local ok, frame = pcall(display.newImageRect, parent, FRAME_LARGE, FRAME_W, FRAME_H)
    if ok and frame then
        frame.x = FRAME_X
        frame.y = FRAME_Y
        return frame
    end
    local fallback = display.newRoundedRect(parent, FRAME_X, FRAME_Y, FRAME_W, FRAME_H, 8)
    fallback:setFillColor(0.02, 0.08, 0.12, 0.96)
    fallback.strokeWidth = 2
    fallback:setStrokeColor(0.18, 0.90, 0.55, 0.72)
    return fallback
end

local function drawShell()
    clearContent()
    contentGroup = display.newGroup()
    scene.view:insert(contentGroup)

    local guild = activeGuild or {}
    drawFrame(contentGroup)

    local portraitY = CONTENT_TOP + 48
    local ok, portrait = pcall(display.newImageRect, contentGroup, "assets/sprites/characters/street_punk/portrait.png", 64, 64)
    if ok and portrait then
        portrait.x = CX
        portrait.y = portraitY
    else
        local avatar = display.newCircle(contentGroup, CX, portraitY, 32)
        avatar:setFillColor(0.05, 0.17, 0.38, 0.98)
        avatar.strokeWidth = 1.5
        avatar:setStrokeColor(0.24, 0.70, 1.0, 0.78)
    end

    text(contentGroup, string.upper(guild.name or "GUILD"), CX, CONTENT_TOP + 104, 17, { 0.36, 1.0, 0.68 }, CONTENT_W)
    local avgLevel = guild.averageLevel or guild.avgLevel or guild.level or 1
    text(contentGroup, "AVG LV " .. tostring(avgLevel) .. "  -  LEADER", CX, CONTENT_TOP + 124, 10, { 0.64, 0.88, 1.0 }, CONTENT_W)

    local statY = CONTENT_TOP + 160
    local statW = (CONTENT_W - 12) / 3
    local statX0 = CX - CONTENT_W * 0.5 + statW * 0.5
    local statDefs = {
        { "ONLINE", tostring(guild.members or #activeMembers) .. "/" .. tostring(guild.maxMembers or 20), { 0.36, 1.0, 0.68 } },
        { "AVG LV", tostring(avgLevel), { 0.72, 0.82, 1.0 } },
        { "FUNDS", tostring(guild.gold or 0) .. "g", { 1.0, 0.80, 0.22 } },
    }
    for i, def in ipairs(statDefs) do
        local x = statX0 + (i - 1) * (statW + 6)
        local box = display.newRoundedRect(contentGroup, x, statY, statW, 34, 5)
        box:setFillColor(0.03, 0.10, 0.18, 0.94)
        box.strokeWidth = 1.2
        box:setStrokeColor(def[3][1], def[3][2], def[3][3], 0.62)
        text(contentGroup, def[1], x, statY - 9, 7, { 0.54, 0.74, 0.94 }, statW - 6)
        text(contentGroup, def[2], x, statY + 6, 10, def[3], statW - 6)
    end

    local status = display.newRoundedRect(contentGroup, CX, statY + 46, CONTENT_W, 28, 6)
    status:setFillColor(0.03, 0.15, 0.22, 0.96)
    status.strokeWidth = 1.2
    status:setStrokeColor(0.10, 0.80, 0.48, 0.52)
    text(contentGroup, "LEADER STATUS", CX, statY + 37, 7, { 0.58, 0.72, 0.92 }, CONTENT_W)
    text(contentGroup, tostring(guild.members or #activeMembers) .. " ONLINE", CX, statY + 49, 9, { 0.64, 1.0, 0.76 }, CONTENT_W)

    text(contentGroup, tostring(guild.desc or guild.description or "No guild description yet."), CX, statY + 94, 11, { 0.88, 0.96, 1.0 }, CONTENT_W - 20)
    text(contentGroup, "RECENT ACTIVITY", CX, CONTENT_BOT - 128, 8, { 0.58, 0.72, 0.92 }, CONTENT_W)
    if bottomGroup and bottomGroup.toFront then
        bottomGroup:toFront()
    end
end

local function drawMembers()
    drawShell()
    text(contentGroup, "MEMBERS", CX, CONTENT_BOT - 178, 13, { 0.36, 1.0, 0.68 }, CONTENT_W)
    for i, member in ipairs(activeMembers or {}) do
        if i > 8 then break end
        local y = CONTENT_BOT - 146 + (i - 1) * 32
        local row = display.newRoundedRect(contentGroup, CX, y, CONTENT_W, 27, 7)
        row:setFillColor(0.03, 0.08, 0.18, 0.94)
        row.strokeWidth = 1
        row:setStrokeColor(0.18, 0.52, 1.0, 0.34)
        local name = member.name or member.displayName or "Player"
        text(contentGroup, name, CX - CONTENT_W * 0.5 + 10, y, 10, { 0.88, 0.96, 1.0 }, CONTENT_W - 120, "left").anchorX = 0
        text(contentGroup, tostring(member.rank or member.role or "MEMBER"), CX + CONTENT_W * 0.5 - 46, y, 8, { 0.50, 0.82, 1.0 }, 86)
    end
end

local function timeLeftLabel(releaseAt)
    local y, mo, d, h, mi, s = tostring(releaseAt or ""):match("^(%d+)%-(%d+)%-(%d+)T(%d+):(%d+):(%d+)")
    if not y then return "24H" end
    local release = os.time({
        year = tonumber(y), month = tonumber(mo), day = tonumber(d),
        hour = tonumber(h), min = tonumber(mi), sec = tonumber(s),
    })
    local diff = math.max(0, release - os.time())
    local hours = math.floor(diff / 3600)
    local mins = math.floor((diff % 3600) / 60)
    return tostring(hours) .. "H " .. tostring(mins) .. "M"
end

local function drawJail()
    drawShell()
    text(contentGroup, "JAIL", CX, CONTENT_BOT - 178, 13, { 1.0, 0.42, 0.42 }, CONTENT_W)
    text(contentGroup, "Prisoners pay 10% arena tax for 24 hours.", CX, CONTENT_BOT - 158, 8, { 0.72, 0.86, 1.0 }, CONTENT_W - 18)

    local list = activeJail or {}
    if #list == 0 then
        text(contentGroup, "No prisoners.", CX, CONTENT_BOT - 112, 11, { 0.58, 0.76, 0.96 }, CONTENT_W)
        return
    end

    local startY = CONTENT_BOT - 128
    for i, entry in ipairs(list) do
        local y = startY + (i - 1) * 34
        local row = display.newRoundedRect(contentGroup, CX, y, CONTENT_W - 8, 28, 6)
        row:setFillColor(0.08, 0.06, 0.12, 0.96)
        row.strokeWidth = 1.2
        row:setStrokeColor(0.90, 0.20, 0.22, 0.62)
        local name = tostring(entry.name or "Player")
        text(contentGroup, name, CX - CONTENT_W * 0.5 + 16, y - 1, 9, { 0.96, 0.90, 0.90 }, CONTENT_W * 0.5, "left").anchorX = 0
        text(contentGroup, timeLeftLabel(entry.releaseAt), CX + CONTENT_W * 0.24, y - 1, 8, { 1.0, 0.55, 0.45 }, CONTENT_W * 0.35)
    end
end

local function drawChat()
    drawShell()
    text(contentGroup, "GUILD CHAT", CX, CONTENT_BOT - 190, 13, { 0.36, 1.0, 0.68 }, CONTENT_W)
    local listTop = CONTENT_BOT - 154
    for i, msg in ipairs(activeMessages or {}) do
        if i > 5 then break end
        local y = listTop + (i - 1) * 52
        local bubble = display.newRoundedRect(contentGroup, CX, y, CONTENT_W, 44, 7)
        bubble:setFillColor(msg.private and 0.08 or 0.03, msg.private and 0.06 or 0.08, msg.private and 0.16 or 0.18, 0.94)
        bubble.strokeWidth = 1
        bubble:setStrokeColor(0.18, 0.52, 1.0, msg.private and 0.20 or 0.34)
        local prefix = msg.private and "PRIVATE  " or ""
        text(contentGroup, prefix .. tostring(msg.author or "Player"), CX - CONTENT_W * 0.5 + 10, y - 12, 8, { 0.50, 0.82, 1.0 }, CONTENT_W - 20, "left").anchorX = 0
        text(contentGroup, tostring(msg.body or ""), CX - CONTENT_W * 0.5 + 10, y + 7, 9, { 0.86, 0.94, 1.0 }, CONTENT_W - 20, "left").anchorX = 0
    end

    local inputY = TAB_Y - 70
    local inputBg = display.newRoundedRect(contentGroup, CX - 22, inputY, SW - 82, 32, 7)
    inputBg:setFillColor(0.03, 0.08, 0.20, 0.96)
    inputBg.strokeWidth = 1.5
    inputBg:setStrokeColor(0.20, 0.58, 1.0, 0.54)
    chatField = native.newTextField(CX - 22, inputY, SW - 92, 24)
    chatField.placeholder = "Message guild..."
    chatField.hasBackground = false
    chatField:setTextColor(0.85, 0.95, 1.0)

    local priv = display.newRoundedRect(contentGroup, 54, inputY + 34, 88, 24, 6)
    priv:setFillColor(privateChat and 0.04 or 0.03, privateChat and 0.24 or 0.08, privateChat and 0.15 or 0.20, 0.96)
    priv.strokeWidth = 1.2
    priv:setStrokeColor(0.25, 0.72, 1.0, 0.55)
    text(contentGroup, (privateChat and "[X] " or "[ ] ") .. "PRIVATE", priv.x, priv.y, 8, { 0.78, 0.92, 1.0 }, 82)
    priv:addEventListener("tap", function()
        privateChat = not privateChat
        drawChat()
        return true
    end)

    local send = display.newRoundedRect(contentGroup, SW - 34, inputY, 42, 32, 7)
    send:setFillColor(0.04, 0.22, 0.52, 0.96)
    send.strokeWidth = 1.5
    send:setStrokeColor(0.20, 0.78, 0.48, 0.74)
    text(contentGroup, "SEND", send.x, send.y, 8, { 0.62, 1.0, 0.74 }, 38)
    send:addEventListener("tap", function()
        local body = chatField and chatField.text or ""
        body = body:gsub("^%s+", ""):gsub("%s+$", "")
        if body == "" or not activeGuildId then return true end
        api.guilds.sendChat(activeGuildId, { body=body, private=privateChat }, function(response)
            if response.ok and response.data and response.data.messages then
                activeMessages = response.data.messages
                drawChat()
            end
        end)
        return true
    end)
end

local function applyToGuild()
    if not activeGuildId then return true end
    if not canApplyToActiveGuild() then
        native.showAlert("Leave Guild First", "Leave your joined guild before applying to another one.", { "OK" })
        return true
    end
    api.guilds.join(activeGuildId, function(response)
        if response.ok and response.data then
            if response.data.player then save.save(response.data.player) end
            native.showAlert("Guild Joined", "You joined " .. tostring((response.data.guild or activeGuild).name or "the guild") .. ".", { "OK" })
        else
            local message = "Could not join that guild yet."
            if response.data and response.data.error == "leave_joined_guild_first" then
                message = "Leave your joined guild before applying to another one."
            end
            native.showAlert("Join Failed", message, { "OK" })
        end
    end)
    return true
end

local function showDeclareConfirm()
    local leaderGuild = getLeaderGuild(save.load())
    if not leaderGuild or not leaderGuild.guildId or not activeGuildId then return true end
    if activePendingWar and secondsUntil(activePendingWar.readyAtMs or activePendingWar.readyAt) > 0 then return true end

    local popup = display.newGroup()
    scene.view:insert(popup)
    local overlay = display.newRect(popup, CX, CY, SW, SH)
    overlay:setFillColor(0, 0, 0, 0.70)

    local panelW = math.min(SW - 36, 318)
    local panelH = 190
    local panel = display.newRoundedRect(popup, CX, CY, panelW, panelH, 10)
    panel:setFillColor(0.02, 0.06, 0.16, 0.98)
    panel.strokeWidth = 2
    panel:setStrokeColor(0.28, 0.72, 1.0, 0.82)
    ui.addPopupShield(popup, CX, CY, panelW, panelH)

    text(popup, "DECLARE WAR", CX, CY - 62, 16, { 0.42, 0.86, 1.0 }, panelW - 34)
    text(popup,
        "Are you sure you want to declare war on " .. tostring((activeGuild and activeGuild.name) or "this guild") .. "?",
        CX, CY - 18, 11, { 0.82, 0.94, 1.0 }, panelW - 42)

    local function close()
        return ui.popupClose(popup, overlay, { panel }, function() end)
    end

    local noBtn = display.newRoundedRect(popup, CX - 58, CY + 54, 92, 34, 7)
    noBtn:setFillColor(0.05, 0.10, 0.20, 0.97)
    noBtn.strokeWidth = 1.5
    noBtn:setStrokeColor(0.32, 0.62, 1.0, 0.58)
    text(popup, "NO", noBtn.x, noBtn.y, 12, { 0.82, 0.94, 1.0 }, 80)
    noBtn:addEventListener("tap", close)

    local yesBtn = display.newRoundedRect(popup, CX + 58, CY + 54, 92, 34, 7)
    yesBtn:setFillColor(0.10, 0.05, 0.10, 0.97)
    yesBtn.strokeWidth = 1.5
    yesBtn:setStrokeColor(1.0, 0.34, 0.30, 0.72)
    text(popup, "YES", yesBtn.x, yesBtn.y, 12, { 1.0, 0.52, 0.42 }, 80)
    yesBtn:addEventListener("tap", function()
        api.guilds.declareWar(leaderGuild.guildId, { targetGuildId = activeGuildId }, function(response)
            if response and response.ok then
                activePendingWar = response.data and response.data.war or nil
                drawBottom()
            else
                if response and response.data and response.data.error == "war_pending" and response.data.war then
                    activePendingWar = response.data.war
                    drawBottom()
                    return
                end
                native.showAlert("Declare Failed", declareWarErrorMessage(response), { "OK" })
            end
        end)
        close()
        return true
    end)

    overlay:addEventListener("tap", close)
    ui.popupOpen(overlay, { panel }, { overlayAlpha = 0.70, startScale = 0.2, time = 170 })
    return true
end

declareWarErrorMessage = function(response)
    if not response then
        return "No response from the server."
    end
    if response.offline then
        return "Online guild war needs the server connection enabled."
    end
    local errorId = (response.data and response.data.error) or response.error
    if errorId == "leader_required" then
        return "Only the leader of your created guild can declare war."
    elseif errorId == "not_guild_member" then
        return "You are not currently a member of the attacking guild on the server."
    elseif errorId == "guild_not_found" then
        return "Your attacking guild could not be found on the server."
    elseif errorId == "target_guild_not_found" then
        return "That target guild could not be found on the server."
    elseif errorId == "cannot_war_self" then
        return "You cannot declare war on your own guild."
    elseif errorId == "war_pending" then
        return "War has already been declared. The timer is still running."
    end
    if response.status == 404 then
        return "The server does not have guild war routes enabled yet. Restart the server and try again."
    elseif response.status == 401 then
        return "Your online session expired. Log in again and try declaring war."
    elseif response.status == 403 then
        return "The server rejected this declare request. You may not be the guild leader on the server."
    elseif response.status and response.status >= 500 then
        return "The server hit an error while declaring war."
    end
    if errorId then
        return "Could not declare war: " .. tostring(errorId)
    end
    return "Could not declare war. Status: " .. tostring(response.status or "?")
end

drawBottom = function()
    stopWarTimer()
    if bottomGroup and bottomGroup.removeSelf then bottomGroup:removeSelf() end
    bottomGroup = display.newGroup()
    scene.view:insert(bottomGroup)
    local labels = {
        { "LOOT", startGuildLoot },
        { "JAIL", function()
            if not activeGuildId then return true end
            api.guilds.jail(activeGuildId, function(response)
                if response.ok and response.data then
                    activeJail = response.data.jail or {}
                end
                drawJail()
            end)
            return true
        end },
        { "GUILDS CHAT", function() drawChat(); return true end },
        { "MEMBERS", function() drawMembers(); return true end },
    }
    if canDeclareWarOnActiveGuild() then
        local label = activePendingWar and secondsUntil(activePendingWar.readyAtMs or activePendingWar.readyAt) > 0 and warTimerLabel() or "DECLARE"
        table.insert(labels, 2, { label, showDeclareConfirm, isWar = true })
    end
    if canApplyToActiveGuild() then
        table.insert(labels, 2, { "APPLY TO GUILD", applyToGuild })
    end
    local y = TAB_Y
    local w = (SW - 20) / #labels
    for i, item in ipairs(labels) do
        local x = 10 + (i - 1) * w + w * 0.5
        local btn = display.newRoundedRect(bottomGroup, x, y, w - 6, 38, 7)
        btn:setFillColor(0.03, 0.10, 0.18, 0.96)
        btn.strokeWidth = 1.5
        btn:setStrokeColor(0.15, 0.74, 0.48, 0.62)
        local labelObj = text(bottomGroup, item[1], x, y, 7, item.isWar and { 1.0, 0.58, 0.46 } or { 0.72, 1.0, 0.82 }, w - 12)
        if item.isWar then warCountdownText = labelObj end
        btn:addEventListener("tap", item[2])
    end
    if activePendingWar and secondsUntil(activePendingWar.readyAtMs or activePendingWar.readyAt) > 0 and warCountdownText then
        warTimer = timer.performWithDelay(1000, function()
            local left = secondsUntil(activePendingWar and (activePendingWar.readyAtMs or activePendingWar.readyAt))
            if left <= 0 then
                activePendingWar = nil
                drawBottom()
                return
            end
            if warCountdownText then warCountdownText.text = warTimerLabel() end
        end, 0)
    end
end

function scene:create(event)
    local sg = self.view
    local bg = display.newImage("assets/sprites/ui/bg_home_grid.png")
    if bg then
        bg:scale(math.max(SW / bg.width, SH / bg.height), math.max(SW / bg.width, SH / bg.height))
        bg.x = CX
        bg.y = CY
        sg:insert(bg)
    end
    local dim = display.newRect(sg, CX, CY, SW, SH)
    dim:setFillColor(0, 0, 0, 0.58)
    local back = text(sg, "< BACK", 42, 28, 10, { 0.42, 0.82, 1.0 }, 80)
    back:addEventListener("tap", function()
        composer.gotoScene((self.params and self.params.returnScene) or "scenes.guild_join", { effect="slideRight", time=220 })
        return true
    end)
end

function scene:show(event)
    if event.phase ~= "did" then return end
    self.params = event.params or {}
    activeGuildId = self.params.guildId
    activeGuild = nil
    activeMembers = {}
    activeMessages = {}
    activeJail = {}
    activePendingWar = nil
    drawBottom()
    drawShell()

    local lootResult = composer.getVariable("guildLootResult")
    if lootResult and lootResult.guildId == activeGuildId then
        composer.setVariable("guildLootResult", nil)
        timer.performWithDelay(120, function()
            showLootResultPopup(lootResult)
        end)
    end

    if activeGuildId then
        api.guilds.get(activeGuildId, function(response)
            if response.ok and response.data then
                activeGuild = response.data.guild
                activeMembers = response.data.members or {}
                activeMessages = response.data.messages or {}
                activeJail = response.data.jail or {}
                activePendingWar = response.data.pendingWar
            end
            drawShell()
            drawBottom()
        end)
    end
end

function scene:hide(event)
    if event.phase ~= "will" then return end
    rewardPopup.closeActive(true)
    stopWarTimer()
    clearContent()
end

scene:addEventListener("create", scene)
scene:addEventListener("show", scene)
scene:addEventListener("hide", scene)

return scene
