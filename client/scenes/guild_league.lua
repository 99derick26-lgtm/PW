local composer = require("composer")
local scene = composer.newScene()

local api = require("utils.api")
local battleContext = require("utils.battle_context")
local guildContext = require("utils.guild_context")
local guildNav = require("utils.guild_nav")
local saveUtil = require("utils.save")
local shell = require("utils.guild_scene_shell")
local sync = require("utils.sync")
local ui = require("utils.ui")

local SW = display.contentWidth
local SH = display.contentHeight
local CX = display.contentCenterX
local CY = display.contentCenterY
local CONTENT_TOP = 78
local CONTENT_BOT = guildNav.contentBottom()
local CONTENT_H = CONTENT_BOT - CONTENT_TOP

local contentGroup
local chromeGroup
local popup
local activeGuild

local STAT_ICONS = {
    attack = "assets/sprites/ui/icons/atk.png",
    defense = "assets/sprites/ui/icons/def.png",
    speed = "assets/sprites/ui/icons/spd.png",
    hp = "assets/sprites/ui/icons/hp.png",
}

local SLOT_POSITIONS = {
    [1] = { x=-76, y=38, w=60, h=60 },
    [2] = { x=76, y=38, w=60, h=60 },
    [3] = { x=0, y=130, w=60, h=60, leader=true },
    [4] = { x=-76, y=220, w=60, h=60 },
    [5] = { x=76, y=220, w=60, h=60 },
}

local GUILD_NAMES = {
    "Pinche Perros", "Neon Riot", "Grid Saints", "Iron Circuit",
    "Ghost Syndicate", "Street Wolves", "Cyber Saints", "Null Crew",
    "Rooftop Kings", "Market Crash", "Blue Phones", "Chrome Dogs",
    "Scrap Lords", "Toxic Angels", "Night Ops", "Jailbreak",
    "Pixel Punx", "Gold Teeth", "Coil Runners", "Void Union",
    "Hard Reset", "Redline", "Metro Saints", "Signal Zero",
    "Low Battery", "Arena Rats", "Vault Boys", "Static Bloom",
    "Byte Club", "Crash Cart", "Chrome Mercy", "Final Packet",
}

local function closePopup()
    if popup and popup.removeSelf then popup:removeSelf() end
    popup = nil
end

local function clearContent()
    closePopup()
    if contentGroup and contentGroup.removeSelf then contentGroup:removeSelf() end
    contentGroup = nil
end

local function playerId()
    local player = saveUtil.load()
    return player and player.playerId
end

local function applyGuildResponse(response)
    if not response or not response.ok or not response.data then return false end
    if response.data.player then
        sync.applyPlayerSnapshot(response.data.player, saveUtil.activeSlot)
    end
    if response.data.guild then
        activeGuild = response.data.guild
    end
    return true
end

local function statValue(holder, key)
    return tonumber(holder and holder[key]) or 100
end

local function drawStat(parent, x, y, key, value)
    local ok, icon = pcall(display.newImageRect, parent, STAT_ICONS[key], 18, 18)
    if ok and icon then
        icon.x = x
        icon.y = y
    end
    display.newText({
        parent=parent, text=tostring(value),
        x=x + 24, y=y, width=42,
        font=ui.FONT_BOLD, fontSize=9, align="left",
    }):setFillColor(0.78,0.90,1.0)
end

local function makeNavButton(parent, x, y, w, h, label, onTap)
    local ok, img = pcall(display.newImageRect, parent, "assets/sprites/ui/btn_nav.png", w, h)
    local btn = ok and img or display.newRoundedRect(parent, x, y, w, h, 8)
    btn.x = x
    btn.y = y
    if not ok then
        btn:setFillColor(0.04,0.14,0.32,0.96)
        btn.strokeWidth = 1.5
        btn:setStrokeColor(0.26,0.70,1.0,0.78)
    end
    local t = display.newText({
        parent=parent, text=label,
        x=x, y=y, width=w - 14,
        font=ui.FONT_BOLD, fontSize=10, align="center",
    })
    t:setFillColor(0.84,0.96,1.0)
    btn:addEventListener("tap", onTap)
    t:addEventListener("tap", onTap)
    return btn
end

local function bracketPopup()
    closePopup()
    popup = display.newGroup()
    scene.view:insert(popup)

    local dim = display.newRect(popup, CX, CY, SW, SH)
    dim:setFillColor(0,0,0,0.78)
    dim.isHitTestable = true
    dim:addEventListener("tap", function() closePopup(); return true end)

    local panelW, panelH = SW - 18, CONTENT_H - 18
    local panel = display.newRoundedRect(popup, CX, CONTENT_TOP + panelH * 0.5, panelW, panelH, 10)
    panel:setFillColor(0.02,0.04,0.11,0.98)
    panel.strokeWidth = 1.5
    panel:setStrokeColor(0.22,0.58,1.0,0.62)
    panel:addEventListener("tap", function() return true end)

    display.newText({
        parent=popup, text="GUILD LEAGUE",
        x=CX, y=CONTENT_TOP + 18,
        font=ui.FONT_BOLD, fontSize=14,
    }):setFillColor(0.42,1.0,0.70)

    local labels = { "32", "16", "8", "4", "FINAL" }
    local colW = (panelW - 16) / 5
    local top = CONTENT_TOP + 48
    for r = 1, 5 do
        local x = CX - panelW * 0.5 + 8 + (r - 0.5) * colW
        display.newText({
            parent=popup, text=labels[r],
            x=x, y=top - 14, width=colW - 4,
            font=ui.FONT_BOLD, fontSize=7, align="center",
        }):setFillColor(0.46,0.74,1.0)

        local rows = r == 1 and 16 or math.max(1, math.floor(16 / (2 ^ (r - 1))))
        local rowH = math.min(30, (panelH - 80) / rows)
        for i = 1, rows do
            local y = top + (i - 1) * rowH + rowH * 0.5
            local bg = display.newRoundedRect(popup, x, y, colW - 5, rowH - 4, 5)
            bg:setFillColor(0.025,0.07,0.16,0.94)
            bg.strokeWidth = 1
            bg:setStrokeColor(0.12,0.42,0.82,0.50)
            local name = r == 1 and (i == 1 and ((activeGuild and activeGuild.name) or "Your Guild") or GUILD_NAMES[i]) or "TBD"
            display.newText({
                parent=popup, text=name,
                x=x, y=y, width=colW - 10,
                font=ui.FONT_BOLD, fontSize=6, align="center",
            }):setFillColor(i == 1 and r == 1 and 0.46 or 0.72, i == 1 and r == 1 and 1.0 or 0.82, 1.0)
        end
    end
end

local function startChallenge(slot)
    local holder = slot and slot.holder
    if not holder or not activeGuild or not activeGuild.guildId then return true end
    local opponent = {
        id="enemy:leader",
        name=holder.name or "League Holder",
        displayName=holder.name,
        level=holder.level or 1,
        attack=holder.attack or 100,
        defense=holder.defense or 100,
        speed=holder.speed or 100,
        hp=holder.hp or 100,
        visualId=holder.skinId,
        pets={},
        spells={},
        equipped={},
    }
    battleContext.startGuildLeagueChallenge(opponent, {
        guildId=activeGuild.guildId,
        guildKey=composer.getVariable("guildContextKind"),
        slot=slot.slot,
    })
    composer.gotoScene("scenes.arena_battle", { effect="slideLeft", time=220 })
    return true
end

local function showSlotPopup(slot)
    local holder = slot and slot.holder
    if not holder then return true end
    closePopup()
    popup = display.newGroup()
    scene.view:insert(popup)

    local dim = display.newRect(popup, CX, CY, SW, SH)
    dim:setFillColor(0,0,0,0.74)
    dim.isHitTestable = true
    dim:addEventListener("tap", function() closePopup(); return true end)

    local panelW, panelH = SW - 54, 304
    local panel = display.newRoundedRect(popup, CX, CY, panelW, panelH, 10)
    panel:setFillColor(0.025,0.065,0.16,0.98)
    panel.strokeWidth = 2
    panel:setStrokeColor(slot.locked and 1.0 or 0.25, slot.locked and 0.78 or 0.75, slot.locked and 0.18 or 1.0, 0.78)
    panel:addEventListener("tap", function() return true end)

    shell.drawPortrait(popup, CX, CY - 94, holder.name, holder.skinId, 70)
    display.newText({
        parent=popup,
        text="LV " .. tostring(holder.level or 1) .. "  " .. tostring(holder.name or "Player"),
        x=CX, y=CY - 42, width=panelW - 26,
        font=ui.FONT_BOLD, fontSize=12, align="center",
    }):setFillColor(0.84,0.94,1.0)

    local statY = CY + 4
    drawStat(popup, CX - 86, statY - 16, "attack", statValue(holder, "attack"))
    drawStat(popup, CX + 20, statY - 16, "defense", statValue(holder, "defense"))
    drawStat(popup, CX - 86, statY + 20, "speed", statValue(holder, "speed"))
    drawStat(popup, CX + 20, statY + 20, "hp", statValue(holder, "hp"))

    local myId = playerId()
    local label = "CHALLENGE"
    local enabled = true
    if slot.locked then
        label = "LEADER LOCKED"
        enabled = false
    elseif holder.playerId == myId then
        label = "HOLDING SLOT"
        enabled = false
    end
    makeNavButton(popup, CX, CY + 104, 158, 40, label, function()
        if enabled then return startChallenge(slot) end
        return true
    end)
end

local function claimSlot(slot)
    if not activeGuild or not activeGuild.guildId then return true end
    api.guilds.claimLeagueSlot(activeGuild.guildId, slot.slot, function(response)
        if applyGuildResponse(response) then
            scene:buildContent()
        end
    end)
    return true
end

local function drawLeagueSlot(parent, slot, baseX, baseY)
    local pos = SLOT_POSITIONS[slot.slot] or SLOT_POSITIONS[1]
    local x = baseX + pos.x
    local y = baseY + pos.y
    local holder = slot.holder
    local bg = display.newRoundedRect(parent, x, y, pos.w, pos.h, 4)
    if pos.leader then
        bg:setFillColor(0.95,0.72,0.16,0.98)
        bg.strokeWidth = 2
        bg:setStrokeColor(1.0,0.92,0.32,0.95)
    else
        bg:setFillColor(holder and 0.04 or 0.02, holder and 0.13 or 0.08, holder and 0.26 or 0.17, 0.96)
        bg.strokeWidth = 1.5
        bg:setStrokeColor(holder and 0.28 or 0.12, holder and 0.72 or 0.34, holder and 1.0 or 0.58, holder and 0.78 or 0.52)
    end

    local function onTap()
        if holder then
            return showSlotPopup(slot)
        end
        return claimSlot(slot)
    end

    if holder then
        shell.drawPortrait(parent, x, y - 3, holder.name, holder.skinId, math.min(pos.w, pos.h) - 10)
        display.newText({
            parent=parent, text=holder.name or "Player",
            x=x, y=y + pos.h * 0.5 + 12, width=86,
            font=ui.FONT_BOLD, fontSize=8, align="center",
        }):setFillColor(pos.leader and 1.0 or 0.82, pos.leader and 0.84 or 0.94, pos.leader and 0.24 or 1.0)
        display.newText({
            parent=parent, text="LV " .. tostring(holder.level or 1),
            x=x, y=y + pos.h * 0.5 + 25,
            font=ui.FONT_BOLD, fontSize=7,
        }):setFillColor(0.50,0.72,0.96)
    else
        display.newText({
            parent=parent, text="+",
            x=x, y=y - 3, font=ui.FONT_BOLD, fontSize=20,
        }):setFillColor(0.34,0.86,1.0)
        display.newText({
            parent=parent, text="EMPTY",
            x=x, y=y + pos.h * 0.5 + 15,
            font=ui.FONT_BOLD, fontSize=7,
        }):setFillColor(0.46,0.62,0.82)
    end
    bg:addEventListener("tap", onTap)
    local hit = display.newRect(parent, x, y + 14, math.max(pos.w, 82), pos.h + 48)
    hit:setFillColor(1,1,1,0)
    hit.isHitTestable = true
    hit:addEventListener("tap", onTap)
end

function scene:buildContent()
    clearContent()
    contentGroup = display.newGroup()
    scene.view:insert(contentGroup)
    if chromeGroup and chromeGroup.toFront then chromeGroup:toFront() end

    local teamTop = CONTENT_TOP + 6
    local teamH = math.floor(CONTENT_H * 0.50)
    local teamFrame = display.newRoundedRect(contentGroup, CX, teamTop + teamH * 0.5, SW - 16, teamH, 8)
    teamFrame:setFillColor(0.015,0.035,0.08,0.92)
    teamFrame.strokeWidth = 1.5
    teamFrame:setStrokeColor(0.16,0.48,0.92,0.42)

    display.newText({
        parent=contentGroup, text="LEAGUE TEAM",
        x=CX, y=teamTop + 17,
        font=ui.FONT_BOLD, fontSize=11,
    }):setFillColor(0.42,1.0,0.70)

    local slots = (activeGuild and activeGuild.leagueSlots) or {}
    local bySlot = {}
    for _, slot in ipairs(slots) do bySlot[slot.slot] = slot end
    for i = 1, 5 do
        local slot = bySlot[i] or { slot=i, locked=i == 3, holder=nil }
        drawLeagueSlot(contentGroup, slot, CX, teamTop + 36)
    end

    local histTop = teamTop + teamH + 8
    local histH = CONTENT_BOT - histTop - 10
    local histFrame = display.newRoundedRect(contentGroup, CX, histTop + histH * 0.5, SW - 16, histH, 8)
    histFrame:setFillColor(0.02,0.055,0.13,0.94)
    histFrame.strokeWidth = 1.5
    histFrame:setStrokeColor(0.16,0.48,0.92,0.44)
    display.newText({
        parent=contentGroup, text="PREVIOUS LEAGUE FIGHTS",
        x=CX, y=histTop + 17,
        font=ui.FONT_BOLD, fontSize=10,
    }):setFillColor(0.62,0.88,1.0)

    local tournament = activeGuild and activeGuild.leagueTournament
    local timerBody = "All guilds enter automatically every 24 hours."
    if tournament and tournament.active then
        timerBody = "Round " .. tostring(tournament.round or 1)
            .. " - " .. tostring(tournament.guildsRemaining or 0) .. " guilds remaining."
    end
    local history = {
        { title="LEAGUE STATUS", body=timerBody, kind="info" },
        { title="LEAGUE BRACKET", body="Tap to view the current guild league tournament.", kind="bracket" },
    }
    for _, item in ipairs((activeGuild and activeGuild.leagueHistory) or {}) do
        history[#history + 1] = item
    end

    local rowW = SW - 38
    local rowH = 45
    for i = 1, math.min(4, #history) do
        local item = history[i]
        local y = histTop + 48 + (i - 1) * (rowH + 7)
        local row = display.newRoundedRect(contentGroup, CX, y, rowW, rowH, 7)
        row:setFillColor(0.035,0.085,0.19,0.96)
        row.strokeWidth = 1.3
        row:setStrokeColor(0.22,0.64,1.0,0.48)
        local title = display.newText({
            parent=contentGroup, text=item.title or "LEAGUE",
            x=CX - rowW * 0.5 + 11, y=y - 11,
            width=rowW - 22, font=ui.FONT_BOLD, fontSize=8, align="left",
        })
        title.anchorX = 0
        title:setFillColor(0.42,1.0,0.70)
        local body = display.newText({
            parent=contentGroup, text=item.body or "",
            x=CX - rowW * 0.5 + 11, y=y + 9,
            width=rowW - 22, font=ui.FONT_BOLD, fontSize=7, align="left",
        })
        body.anchorX = 0
        body:setFillColor(0.76,0.86,1.0)
        row:addEventListener("tap", function() bracketPopup(); return true end)
    end
end

function scene:create()
    local sg = self.view
    local bg = display.newRect(sg, CX, CY, SW, SH)
    bg:setFillColor(0.02,0.03,0.08)
    for i = 1, 18 do
        local line = display.newRect(sg, CX, i * (SH / 18), SW, 1)
        line:setFillColor(0.06,0.18,0.42,0.04)
    end
    shell.drawTitleBanner(sg, "LEAGUE", { y=36, height=54, color={0.35,1.0,0.68} })
end

function scene:show(event)
    if event.phase ~= "did" then return end
    local params = (event and event.params) or {}
    if params.guildId then
        guildContext.setActiveGuild(params.guildId, params.guildKey)
    end
    shell.loadGuild(params, function(guild)
        activeGuild = guild
        if chromeGroup and chromeGroup.removeSelf then chromeGroup:removeSelf() end
        chromeGroup = display.newGroup()
        scene.view:insert(chromeGroup)
        guildNav.build(chromeGroup, "LEAGUE")
        shell.drawCloseToHome(chromeGroup, activeGuild)
        scene:buildContent()
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
