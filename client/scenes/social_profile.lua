local composer = require("composer")
local scene = composer.newScene()

local api = require("utils.api")
local items = require("utils.items")
local radialMenu = require("utils.radial_menu")
local save = require("utils.save")
local spells = require("utils.spells")
local stats = require("utils.stats")
local ui = require("utils.ui")

local CX = display.contentCenterX
local CY = display.contentCenterY
local SW = display.actualContentWidth
local SH = display.actualContentHeight

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

local function text(parent, value, x, y, size, color, width, align)
    local obj = display.newText({
        parent = parent,
        text = value,
        x = x,
        y = y,
        width = width,
        font = ui.FONT_BOLD,
        fontSize = size,
        align = align or "center",
    })
    obj:setFillColor(unpack(color))
    return obj
end

local function playerName(player)
    return player.displayName or player.name or player.playerName or "Unknown"
end

local function playerSkin(player)
    return (player.appearance and player.appearance.skinId)
        or player.skinId
        or player.visualId
        or "street_brawler"
end

local STAT_BANNERS = {
    attack  = "assets/sprites/ui/icons/atk_banner.png",
    defense = "assets/sprites/ui/icons/def_banner.png",
    speed   = "assets/sprites/ui/icons/spd_banner.png",
    hp      = "assets/sprites/ui/icons/hp_banner.png",
}

local function equippedWeapons(player)
    local equipped = player and player.equipped
    local weapons = equipped and equipped.weapons or player and player.weapons
    return type(weapons) == "table" and weapons or {}
end

local function buildBattleOpponent(serverPlayer, mode)
    local localPlayer = save.load()
    local snap = serverPlayer.snapshot or serverPlayer
    local final = stats.calculate(snap)
    local opponent = {
        id         = serverPlayer.playerId or snap.playerId or snap.id or serverPlayer.displayName,
        name       = serverPlayer.displayName or snap.name or "Player",
        visualId   = playerSkin(snap),
        level      = snap.level or serverPlayer.level or localPlayer.level or 1,
        attack     = final.attack or snap.attack or 100,
        defense    = final.defense or snap.defense or 100,
        speed      = final.speed or snap.speed or 100,
        hp         = final.hp or snap.hp or 100,
        spells     = snap.spells or serverPlayer.spells or {},
        difficulty = "player",
        bias       = "server",
        pets       = spells.getEquippedPetsForBattle(snap),
        equipped   = snap.equipped or { weapons = equippedWeapons(serverPlayer), armor = {}, accessories = {}, pets = {} },
        currentWeaponIndex = snap.currentWeaponIndex or 1,
        weaponUsesLeft = snap.weaponUsesLeft,
    }

    if mode == "recruit" then
        opponent.isConquest = true
        opponent.conquestTarget = {
            playerId = serverPlayer.playerId,
            name     = opponent.name,
            level    = opponent.level,
            power    = (opponent.attack or 0) + (opponent.defense or 0) + (opponent.speed or 0),
            visualId = opponent.visualId,
            equipped = opponent.equipped,
            pets     = opponent.pets,
        }
    end

    return opponent
end

local function drawStat(parent, x, y, label, value, color)
    local card = display.newRoundedRect(parent, x, y, (SW - 48) * 0.5, 54, 8)
    card:setFillColor(0.035, 0.09, 0.22, 0.96)
    card.strokeWidth = 1.5
    card:setStrokeColor(0.18, 0.52, 1.0, 0.52)

    text(parent, label, x, y - 12, 9, color, card.width - 16)
    text(parent, tostring(value or 0), x, y + 10, 15, { 0.92, 0.97, 1.0 }, card.width - 16)
end

local function drawStatStrip(parent, player, finalStats, y)
    local panelW = SW - 48
    local panel = display.newRoundedRect(parent, CX, y, panelW, 82, 8)
    panel:setFillColor(0.025, 0.07, 0.17, 0.94)
    panel.strokeWidth = 1.5
    panel:setStrokeColor(0.18, 0.52, 1.0, 0.42)

    local statsList = {
        { stat="attack", value=finalStats.attack or player.attack or 0 },
        { stat="defense", value=finalStats.defense or player.defense or 0 },
        { stat="speed", value=finalStats.speed or player.speed or 0 },
        { stat="hp",  value=finalStats.hp or player.hp or 0 },
    }
    local colW = panelW * 0.5
    local startX = CX - panelW * 0.25
    for i, item in ipairs(statsList) do
        local col = (i - 1) % 2
        local row = math.floor((i - 1) / 2)
        local x = startX + col * colW
        local sy = y - 20 + row * 40
        local ok, banner = pcall(display.newImageRect, parent, STAT_BANNERS[item.stat], 82, 24)
        if ok and banner then
            banner.x = x - 18
            banner.y = sy
        end
        local valueText = text(parent, tostring(item.value), x + 36, sy, 11, { 0.88, 0.96, 1.0 }, colW - 72, "left")
        valueText.anchorX = 0
    end
end

local function drawActionButton(parent, x, y, w, h, label, fill, stroke, onTap)
    local btn = display.newRoundedRect(parent, x, y, w, h, 8)
    btn:setFillColor(unpack(fill))
    btn.strokeWidth = 1.5
    btn:setStrokeColor(unpack(stroke))
    local labelText = text(parent, label, x, y, 12, { 0.84, 0.97, 1.0 }, w - 14)
    labelText.isHitTestable = false
    btn:addEventListener("tap", onTap)
    return btn
end

local function splitGuilds(player)
    local joined, created = nil, nil
    for _, guild in ipairs(player.guilds or {}) do
        local role = string.upper(tostring(guild.role or ""))
        if role == "LEADER" and not created then
            created = guild
        elseif role == "LEADER" then
            created = guild
        elseif role ~= "LEADER" and not joined then
            joined = guild
        end
    end
    if not joined and player.guild then joined = player.guild end
    if not created and player.createdGuild then created = player.createdGuild end
    return joined, created
end

local function drawGuildButtons(parent, player, y)
    local joined, created = splitGuilds(player)
    local btnW = (SW - 64) * 0.5
    local function openGuild(guild)
        if not guild or not guild.guildId then return true end
        composer.gotoScene("scenes.guild_view", {
            effect = "slideLeft",
            time = 220,
            params = { guildId = guild.guildId, returnScene = "scenes.social_profile" },
        })
        return true
    end

    drawActionButton(parent, CX - btnW * 0.5 - 6, y, btnW, 34,
        joined and string.upper(joined.name or "GUILD") or "NO GUILD",
        { 0.03, 0.12, 0.30, 0.96 }, { 0.18, 0.64, 1.0, joined and 0.76 or 0.32 },
        function() return openGuild(joined) end)
    drawActionButton(parent, CX + btnW * 0.5 + 6, y, btnW, 34,
        created and string.upper(created.name or "CREATED") or "NO CREATED",
        { 0.03, 0.12, 0.30, 0.96 }, { 0.18, 0.64, 1.0, created and 0.76 or 0.32 },
        function() return openGuild(created) end)
end

local function drawWeapons(parent, player, y)
    local panelW = SW - 48
    local panel = display.newRoundedRect(parent, CX, y, panelW, 72, 8)
    panel:setFillColor(0.025, 0.07, 0.17, 0.94)
    panel.strokeWidth = 1.5
    panel:setStrokeColor(0.18, 0.52, 1.0, 0.42)

    text(parent, "WEAPONS", CX, y - 25, 9, { 0.42, 0.78, 1.0 }, panelW - 16)

    local weapons = equippedWeapons(player)
    if #weapons == 0 then
        text(parent, "UNARMED", CX, y + 8, 11, { 0.58, 0.70, 0.86 }, panelW - 16)
        return
    end

    local count = math.min(#weapons, 4)
    local gap = math.min(64, panelW / math.max(count, 1))
    local startX = CX - (count - 1) * gap * 0.5
    for i = 1, count do
        local weaponId = weapons[i]
        local def = items[weaponId]
        local x = startX + (i - 1) * gap
        local iconPath = (def and def.icon) or "assets/sprites/weapons/unarmed.png"
        local ok, icon = pcall(display.newImageRect, parent, iconPath, 28, 28)
        if ok and icon then
            icon.x = x
            icon.y = y + 2
        end
        text(parent, def and def.name or "Unknown", x, y + 26, 7, { 0.80, 0.90, 1.0 }, gap - 4)
    end
end

local function launchPvp(player, mode)
    if not player then return true end
    local launched = false

    local function openBattle(sourcePlayer)
        if launched then return end
        launched = true
        composer.setVariable("opponent", buildBattleOpponent(sourcePlayer or player, mode))
        composer.gotoScene("scenes.arena_battle", { effect = "slideLeft", time = 220 })
    end

    if not player.playerId then
        openBattle(player)
        return true
    end

    timer.performWithDelay(700, function()
        openBattle(player)
    end)

    api.pvp.prepare(player.playerId, { mode = mode }, function(response)
        local serverPlayer = response and response.ok and response.data and response.data.opponent
        if serverPlayer then
            openBattle(serverPlayer)
        else
            openBattle(player)
        end
    end)
    return true
end

local function renderProfile(sceneObject, player)
    if sceneObject.contentGroup then
        sceneObject.contentGroup:removeSelf()
    end

    local group = display.newGroup()
    sceneObject.view:insert(group)
    sceneObject.contentGroup = group

    local finalStats = stats.calculate(player)
    local name = playerName(player)
    local level = player.level or 1

    text(group, string.upper(name), CX, 82, 22, { 0.88, 0.96, 1.0 }, SW - 32)
    text(group, "LV " .. tostring(level), CX - 14, 108, 11, { 0.42, 0.78, 1.0 }, 64, "right")
    local winIcon = display.newImageRect(group, "assets/sprites/ui/icons/win.png", 16, 16)
    if winIcon then
        winIcon.x = CX + 8
        winIcon.y = 108
    end
    text(group, save.getArenaWinRate(player, player.winRate), CX + 46, 108, 11, { 0.92, 0.97, 1.0 }, 60, "left")

    local glow = display.newCircle(group, CX, 210, 82)
    glow:setFillColor(0.04, 0.20, 0.55, 0.24)

    local platform = display.newRoundedRect(group, CX, 292, 126, 16, 8)
    platform:setFillColor(0.05, 0.18, 0.36, 0.72)

    local skin = playerSkin(player)
    local ok, sprite = pcall(display.newImageRect, group, "assets/sprites/characters/" .. skin .. "/battle.png", 108, 178)
    if ok and sprite then
        sprite.x = CX
        sprite.y = 218
    else
        local avatar = display.newCircle(group, CX, 210, 54)
        avatar:setFillColor(0.05, 0.17, 0.38, 0.98)
        avatar.strokeWidth = 2
        avatar:setStrokeColor(0.24, 0.70, 1.0, 0.78)
        text(group, string.sub(string.upper(name), 1, 1), CX, 210, 28, { 0.70, 0.94, 1.0 })
    end

    local statTop = 340
    drawStatStrip(group, player, finalStats, statTop)
    drawGuildButtons(group, player, statTop + 88)

    drawWeapons(group, player, statTop + 162)

    local btnW = (SW - 64) * 0.5
    local fightY = statTop + 232
    drawActionButton(group, CX - btnW * 0.5 - 6, fightY, btnW, 38, "FIGHT",
        { 0.05, 0.22, 0.52, 0.98 }, { 0.28, 0.75, 1.0, 0.88 },
        function() return launchPvp(player, "fight") end)
    drawActionButton(group, CX + btnW * 0.5 + 6, fightY, btnW, 38, "RECRUIT",
        { 0.04, 0.28, 0.18, 0.98 }, { 0.24, 0.95, 0.58, 0.86 },
        function() return launchPvp(player, "recruit") end)

    local row2Y = statTop + 280
    drawActionButton(group, CX - btnW * 0.5 - 6, row2Y, btnW, 38, "MESSAGE",
        { 0.05, 0.22, 0.52, 0.98 }, { 0.28, 0.75, 1.0, 0.88 },
        function()
            composer.gotoScene("scenes.messages", {
                effect = "slideLeft",
                time = 220,
                params = {
                    toPlayerId = player.playerId,
                    toPlayerName = name,
                },
            })
            return true
        end)

    local friendStatus = text(group, "", CX, row2Y + 30, 8, { 0.72, 0.86, 1.0 }, SW - 70)
    drawActionButton(group, CX + btnW * 0.5 + 6, row2Y, btnW, 38, "FRIEND",
        { 0.14, 0.10, 0.28, 0.98 }, { 0.58, 0.48, 1.0, 0.86 },
        function()
            if not player.playerId then
                friendStatus.text = "Player id missing."
                return true
            end
            friendStatus.text = "Adding..."
            api.friends.sendRequest({ playerId = player.playerId }, function(response)
                if response.ok then
                    friendStatus.text = "Added to friends."
                else
                    friendStatus.text = "Could not add friend."
                end
            end)
            return true
        end)
end

local function showError(sceneObject, message)
    if sceneObject.contentGroup then
        sceneObject.contentGroup:removeSelf()
    end
    local group = display.newGroup()
    sceneObject.view:insert(group)
    sceneObject.contentGroup = group
    text(group, message, CX, CY, 13, { 1.0, 0.35, 0.35 }, SW - 40)
end

local function loadProfile(sceneObject)
    local params = sceneObject.params or {}

    if params.player then
        renderProfile(sceneObject, params.player)
        return
    end

    if params.playerId then
        api.player.get(params.playerId, function(response)
            if response.ok and response.data and response.data.player then
                renderProfile(sceneObject, response.data.player)
            else
                showError(sceneObject, "Could not load player.")
            end
        end)
        return
    end

    if params.playerName and params.playerName ~= "" then
        renderProfile(sceneObject, {
            displayName = params.playerName,
            level = params.level or 1,
            attack = params.attack or 100,
            defense = params.defense or 100,
            speed = params.speed or 100,
            hp = params.hp or 100,
            appearance = params.appearance,
            skinId = params.skinId,
            visualId = params.visualId,
        })
        return
    end

    showError(sceneObject, "No player selected.")
end

function scene:create(event)
    local sg = self.view

    local bg = display.newImage("assets/sprites/ui/bg_home_grid.png")
    if bg then
        bg:scale(math.max(SW / bg.width, SH / bg.height), math.max(SW / bg.width, SH / bg.height))
        bg.x = CX
        bg.y = CY
        sg:insert(bg)
    else
        local fallback = display.newRect(sg, CX, CY, SW, SH)
        fallback:setFillColor(0.02, 0.03, 0.08)
    end

    local dim = display.newRect(sg, CX, CY, SW, SH)
    dim:setFillColor(0, 0, 0, 0.56)

    local header = display.newRoundedRect(sg, CX, 30, SW - 16, 48, 8)
    header:setFillColor(0.02, 0.06, 0.16, 0.96)
    header.strokeWidth = 1.5
    header:setStrokeColor(0.18, 0.38, 0.92, 0.46)

    local backBtn = text(sg, "< BACK", 54, 30, 11, { 0.3, 0.7, 1.0 })
    backBtn:addEventListener("tap", function()
        local returnScene = (self.params and self.params.returnScene) or "scenes.friends"
        composer.gotoScene(returnScene, { effect = "slideRight", time = 220 })
        return true
    end)

    text(sg, "PLAYER", CX, 30, 16, { 0.38, 0.86, 1.0 })

    self.contentGroup = display.newGroup()
    sg:insert(self.contentGroup)
end

function scene:show(event)
    if event.phase ~= "did" then return end
    self.params = event.params or {}
    loadProfile(self)
    radialMenu.show(self.view, {
        activeScene = nil,
        inner = RADIAL_INNER,
        outer = RADIAL_OUTER,
    })
end

function scene:hide(event)
    if event.phase ~= "will" then return end
    radialMenu.destroy()
end

scene:addEventListener("create", scene)
scene:addEventListener("show", scene)
scene:addEventListener("hide", scene)

return scene
