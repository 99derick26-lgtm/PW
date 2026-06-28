-- scenes/home.lua
-- Pixel War Online — Home Screen (Redesign)

local composer  = require("composer")
local scene     = composer.newScene()
local save      = require("utils.save")
local sync      = require("utils.sync")
local api       = require("utils.api")
local ui        = require("utils.ui")
local pets      = require("utils.pets")
local petAssets = require("utils.pet_assets")
local stats     = require("utils.stats")
local xpUtil    = require("utils.xp")
local radialMenu = require("utils.radial_menu")
local tasksUtil = require("utils.tasks")
local levelUpPopup = require("utils.levelup_popup")
local notifications = require("utils.notifications")
local guildContext = require("utils.guild_context")
local battleContext = require("utils.battle_context")
local timeLabels = require("utils.time_labels")

-------------------------------------------------
-- CONSTANTS
-------------------------------------------------
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

local SW = display.actualContentWidth
local SH = display.actualContentHeight
local CX = display.contentCenterX
local CY = display.contentCenterY

local ENERGY_MAX      = 30
local ENERGY_INTERVAL = 16 * 60

-------------------------------------------------
-- DYNAMIC UI REFS
-------------------------------------------------
local xpBarFill
local levelXpText
local levelNumberText
local nameText
local statTexts    = {}
local matNumTexts  = {}
local energyText
local energyFill
local diamondText
local TIMERS       = {}
local activeSettingsPopup
local function trackTimer(t)
    if t then table.insert(TIMERS, t) end
    return t
end

local function setNavPressed(btn, pressed)
    if btn and btn.fill then
        btn.fill = {
            type = "image",
            filename = pressed and "assets/sprites/ui/btn_nav_pressed.png" or "assets/sprites/ui/btn_nav.png"
        }
    end
end

local function safeRemove(obj)
    if obj and obj.removeSelf then obj:removeSelf() end
end

local function closeSettingsPopup()
    safeRemove(activeSettingsPopup)
    activeSettingsPopup = nil
end

local function renderHomePets(sceneObj, player)
    if sceneObj._homePetsGroup and sceneObj._homePetsGroup.removeSelf then
        for _, petSprite in ipairs(sceneObj._petSprites or {}) do
            transition.cancel(petSprite)
        end
        sceneObj._homePetsGroup:removeSelf()
    end

    sceneObj._petSprites = {}

    if not sceneObj._characterGroup or not sceneObj._characterGroup.removeSelf then return end
    if not sceneObj._spriteBaseY then return end

    player.equipped = player.equipped or {}
    player.equipped.pets = player.equipped.pets or {}

    local petGroup = display.newGroup()
    sceneObj._characterGroup:insert(petGroup)
    sceneObj._homePetsGroup = petGroup

    local spriteBaseY = sceneObj._spriteBaseY
    local petShadowPositions = {
        { x=-118, y=54 }, { x=70, y=42 }, { x=140, y=50 },
    }
    local petPositions = {
        { x=-118, y=24 }, { x=72, y=18 }, { x=142, y=26 },
    }

    for i = 1, math.min(3, #player.equipped.pets) do
        local sh = display.newRoundedRect(petGroup, CX + petShadowPositions[i].x, spriteBaseY + petShadowPositions[i].y, 34, 10, 5)
        sh:setFillColor(0, 0, 0, 0.18)
        sh.isHitTestable = false
    end

    for i = 1, math.min(3, #player.equipped.pets) do
        local petId = player.equipped.pets[i]
        local petDef = pets[petId]
        if petDef then
            local size = math.floor((petDef.homeSize or 72) * 0.92)
            local okPet, sprite = pcall(display.newImageRect, petGroup,
                petAssets.home(petId), size, size)
            if okPet and sprite then
                sprite.x = CX + petPositions[i].x
                sprite.y = spriteBaseY + petPositions[i].y
                sprite._baseX = sprite.x
                sprite._baseY = sprite.y
                sceneObj._petSprites[#sceneObj._petSprites + 1] = sprite
            end
        end
    end
end

local function refreshHomeCharacter(sceneObj, player)
    local sprite = sceneObj and sceneObj._playerSprite
    if not sprite or not sprite.removeSelf then return end
    local playerSkin = (player.appearance and player.appearance.skinId)
        or player.skinId
        or "street_brawler"
    sprite.fill = {
        type = "image",
        filename = "assets/sprites/characters/" .. playerSkin .. "/battle.png"
    }
end

local function animateHomePets(sceneObj)
    for i, petSprite in ipairs(sceneObj._petSprites or {}) do
        local baseX = petSprite._baseX or petSprite.x
        local baseY = petSprite._baseY or petSprite.y
        local function wagPet()
            if not petSprite or not petSprite.removeSelf then return end
            transition.to(petSprite, {
                x = baseX + ((i % 2 == 0) and 1 or -1),
                y = baseY - 1, rotation = ((i % 2 == 0) and 2 or -2),
                time = 520 + i * 80, transition = easing.inOutSine,
                onComplete = function()
                    transition.to(petSprite, {
                        x = baseX, y = baseY, rotation = 0,
                        time = 520 + i * 80, transition = easing.inOutSine,
                        onComplete = wagPet
                    })
                end
            })
        end
        wagPet()
    end
end

local function buildAmbientDots(sceneObj, parent, screenW, screenH)
    if sceneObj._ambientGroup and sceneObj._ambientGroup.removeSelf then
        safeRemove(sceneObj._ambientGroup)
    end

    sceneObj._ambientDots = {}

    local ambientGroup = display.newGroup()
    parent:insert(ambientGroup)
    sceneObj._ambientGroup = ambientGroup

    for i = 1, 18 do
        local size = (i % 4 == 0) and 4 or 2
        local dot = display.newRect(
            ambientGroup,
            math.random(18, math.floor(screenW - 18)),
            math.random(170, math.floor(screenH - 120)),
            size, size
        )
        dot:setFillColor(0.35, 0.65 + math.random() * 0.25, 1.0, 0.08 + math.random() * 0.14)
        dot.isHitTestable = false
        dot._baseAlpha = dot.alpha
        sceneObj._ambientDots[#sceneObj._ambientDots + 1] = dot
    end
end

local function buildFallingSparkles(sceneObj, parent, screenW, screenH)
    if sceneObj._sparkleGroup and sceneObj._sparkleGroup.removeSelf then
        safeRemove(sceneObj._sparkleGroup)
    end

    sceneObj._sparkleTrails = {}
    local sparkleGroup = display.newGroup()
    parent:insert(sparkleGroup)
    sceneObj._sparkleGroup = sparkleGroup

    for i = 1, 7 do
        local trail = display.newGroup()
        sparkleGroup:insert(trail)

        local head = display.newCircle(trail, 0, 0, 2)
        head:setFillColor(0.78, 0.96, 1.0, 0.95)

        for t = 1, 3 do
            local tail = display.newRoundedRect(trail, 0, t * 5, 2, 5, 1)
            tail:setFillColor(0.45, 0.78, 1.0, 0.18 - t * 0.03)
        end

        trail.x = math.random(20, math.floor(screenW - 20))
        trail.y = math.random(160, math.floor(screenH - 220))
        trail.alpha = 0.0
        trail.isHitTestable = false
        sceneObj._sparkleTrails[#sceneObj._sparkleTrails + 1] = trail
    end
end

-------------------------------------------------
-- HELPERS
-------------------------------------------------
local function flicker(obj, lo, hi, ms)
    local t = timer.performWithDelay(ms, function()
        if obj and obj.removeSelf then
            obj.alpha = lo + math.random() * (hi - lo)
        end
    end, 0)
    trackTimer(t)
end

local function makeSectionLabel(parent, text, x, y, align)
    local label = display.newText({
        parent = parent,
        text = string.upper(text or ""),
        x = x,
        y = y,
        font = ui.FONT_BOLD,
        fontSize = 9,
        align = align or "left",
    })
    if align == "left" then
        label.anchorX = 0
    elseif align == "right" then
        label.anchorX = 1
    end
    label:setFillColor(0.40, 0.68, 0.96, 0.82)
    return label
end

local function makeNavBtn(parent, x, y, w, h, label, action, iconName)
    if not iconName then
        local normalized = string.upper(label or "")
        if normalized == "FRIENDS" then
            iconName = "friends"
        elseif normalized == "MESSAGES" then
            iconName = "chat"
        end
    end

    local btnGroup = display.newGroup()
    parent:insert(btnGroup)

    local glow = display.newRoundedRect(btnGroup, 0, 0, w + 6, h + 4, 9)
    glow:setFillColor(0.1, 0.4, 1.0, 0.10)
    glow.isHitTestable = false
    flicker(glow, 0.3, 0.9, math.random(140, 260))

   local visualH = h + 19
local btnVisual = display.newImageRect(btnGroup, "assets/sprites/ui/btn_nav.png", w, visualH - 12)
btnVisual.x = 0
btnVisual.y = 0
btnVisual.isHitTestable = false

local btnBg = display.newRoundedRect(btnGroup, 0, 0, w, h, 8)
btnBg:setFillColor(1, 1, 1, 0.01)
btnBg.strokeWidth = 0


    local shimmer = display.newRect(btnGroup, 0, -h*0.5 + 4, w - 4, 3)
    shimmer:setFillColor(1, 1, 1, 0.06)
    shimmer.isHitTestable = false
    local function doShimmer()
        if not shimmer.removeSelf then return end
        shimmer.y = -h*0.5 + 4; shimmer.alpha = 0.06
        transition.to(shimmer, { y=h*0.5-4, alpha=0,
            time=1200+math.random(0,600), transition=easing.inQuad,
            onComplete=function()
                trackTimer(timer.performWithDelay(math.random(800,2400), doShimmer))
            end })
    end
    trackTimer(timer.performWithDelay(math.random(0,1200), doShimmer))

    local pressSweep = display.newRect(btnGroup, -w * 0.35, 0, math.max(18, math.floor(w * 0.12)), h - 6)
    pressSweep.rotation = -18
    pressSweep:setFillColor(0.8, 0.95, 1.0, 0.0)
    pressSweep.isHitTestable = false

    local btnTxt = display.newText({
        parent=btnGroup, text=label,
        x=iconName and 10 or 0, y=0, font=ui.FONT_BOLD, fontSize=10, align="center"
    })
    btnTxt.isHitTestable = false

    if iconName then
        local okIcon, btnIcon = pcall(display.newImageRect,
            btnGroup,
            "assets/sprites/ui/icons/" .. iconName .. ".png",
            16, 16
        )
        if okIcon and btnIcon then
            btnIcon.x = -w * 0.5 + 20
            btnIcon.y = 0
            btnIcon.isHitTestable = false
        end
    end

    btnGroup.x = x
    btnGroup.y = y

    local locked = false
    btnBg:addEventListener("touch", function(event)
        if locked and event.phase == "began" then return true end
        if event.phase == "began" then
            locked = true
            display.getCurrentStage():setFocus(btnBg)
            btnBg._hasFocus = true
            transition.cancel(btnGroup)
            transition.cancel(pressSweep)
            setNavPressed(btnVisual, true)
            btnTxt:setFillColor(0.8, 1.0, 1.0)
            glow:setFillColor(0.2, 0.6, 1.0, 0.35)
            btnGroup.yScale = 0.98
            transition.to(btnGroup, { y = y + 1, time = 70 })
            pressSweep.x = -w * 0.45
            pressSweep.alpha = 0.26
            transition.to(pressSweep, { x = w * 0.45, alpha = 0.02, time = 220 })
        elseif btnBg._hasFocus and (event.phase == "ended" or event.phase == "cancelled") then
            display.getCurrentStage():setFocus(nil)
            btnBg._hasFocus = false
            setNavPressed(btnVisual, false)
            btnTxt:setFillColor(1, 1, 1)
            glow:setFillColor(0.1, 0.4, 1.0, 0.10)
            btnGroup.yScale = 1
            transition.to(btnGroup, { y = y, time = 90 })
            locked = false
            if event.phase == "ended" and action then action() end
        end
        return true
    end)
    return btnBg, btnTxt, btnGroup
end

local function applyLevelUps(player)
    local summary = levelUpPopup.applyLevelUps(player, xpUtil)
    if summary then
        notifications.addLevelUp(player, summary)
    end
    return summary
end

local function setNotificationState(scene, notifications)
    scene._notifications = notifications or {}
    scene._notifMessages = {}
    for _, n in ipairs(scene._notifications) do
        scene._notifMessages[#scene._notifMessages + 1] = n.text or n.message or "Notification"
    end
    if #scene._notifMessages == 0 then
        scene._notifMessages = { "No notifications" }
    end
    scene._notifIndex = 1
    if scene._bellLabel and scene._bellLabel.removeSelf then
        scene._bellLabel.text = scene._notifMessages[1]
        scene._bellLabel.x = 58
        scene._bellLabel.alpha = 1
    end
end

local function guildFromList(player, wantLeader)
    local match = nil
    for _, guild in ipairs(player.guilds or {}) do
        local role = string.upper(tostring(guild.role or ""))
        if wantLeader and role == "LEADER" then
            match = guild
        elseif (not wantLeader) and role ~= "LEADER" then
            return guild
        end
    end
    return match
end

local function mergeNotifications(primary, secondary)
    local merged = {}
    local seen = {}

    local function notificationTime(n)
        return timeLabels.parse(n and (n.createdAt or n.sentAt or n.time)) or 0
    end

    local function notificationPriority(n)
        return (n and n.type == "level_up") and 0 or 1
    end

    local function addList(list)
        for _, n in ipairs(list or {}) do
            local id = n.id or n.createdAt or n.text
            if not id or not seen[id] then
                merged[#merged + 1] = n
                if id then seen[id] = true end
            end
        end
    end

    addList(primary)
    addList(secondary)
    table.sort(merged, function(a, b)
        local ap = notificationPriority(a)
        local bp = notificationPriority(b)
        if ap ~= bp then return ap > bp end
        return notificationTime(a) > notificationTime(b)
    end)
    return merged
end

local function keepModalOnTop(sceneView, popupGrp)
    if sceneView and sceneView.removeSelf and popupGrp and popupGrp.removeSelf then
        sceneView._activeHomePopup = popupGrp
        popupGrp:toFront()
    end
end

local function clearModalLayer(sceneView, popupGrp)
    if sceneView and sceneView._activeHomePopup == popupGrp then
        sceneView._activeHomePopup = nil
    end
end

local function blockBehindTouches(target, onRelease)
    if not target or not target.addEventListener then return end
    target.isHitTestable = true
    target:addEventListener("tap", function()
        return true
    end)
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

local function swallowTouches(target)
    if not target or not target.addEventListener then return end
    target.isHitTestable = true
    target:addEventListener("tap", function()
        return true
    end)
    target:addEventListener("touch", function(event)
        if event.phase == "began" then
            display.getCurrentStage():setFocus(target)
            target._swallowFocus = true
        elseif target._swallowFocus and (event.phase == "ended" or event.phase == "cancelled") then
            display.getCurrentStage():setFocus(nil)
            target._swallowFocus = false
        end
        return true
    end)
end

local function calcEnergy(player)
    player.energy    = player.energy    or ENERGY_MAX
    player.energyTs  = player.energyTs  or os.time()
    if player.energy < ENERGY_MAX then
        local elapsed  = os.time() - player.energyTs
        local gained   = math.floor(elapsed / ENERGY_INTERVAL)
        if gained > 0 then
            player.energy   = math.min(player.energy + gained, ENERGY_MAX)
            player.energyTs = player.energyTs + gained * ENERGY_INTERVAL
        end
    end
    return player.energy
end

-------------------------------------------------
-- TASKS POPUP
-------------------------------------------------
local function buildTasksPopup(sceneView, onClose)
    local freshPlayer = save.load()
    tasksUtil.init(freshPlayer)

    local popupGrp = display.newGroup()
    sceneView:insert(popupGrp)

    local dim = display.newRect(popupGrp, SW*0.5, SH*0.5, SW, SH)
    dim:setFillColor(0,0,0,0.72)
    dim.isHitTestable = true
    keepModalOnTop(sceneView, popupGrp)

    local content = display.newGroup()
    popupGrp:insert(content)

    local panelW = SW - 20
    local panelH = SH - 90
    local panelX = SW * 0.5
    local panelY = SH * 0.5

    local glow = display.newRoundedRect(content, panelX, panelY, panelW+6, panelH+6, 16)
    glow:setFillColor(0,0,0,0); glow.strokeWidth=3
    glow:setStrokeColor(0.2, 0.8, 1.0, 0.28)

    local panel = display.newRoundedRect(content, panelX, panelY, panelW, panelH, 14)
    panel:setFillColor(0.02, 0.06, 0.16, 0.97)
    panel.strokeWidth = 2
    panel:setStrokeColor(0.25, 0.75, 1.0, 0.80)
    blockBehindTouches(panel)

    for i = 0, 10 do
        local line = display.newRect(content, panelX,
            panelY - panelH*0.5 + i*(panelH/10), panelW-4, 1)
        line:setFillColor(0.2, 0.8, 1.0, 0.025)
    end

    local hLine = display.newRect(content, panelX, panelY-panelH*0.5+38, panelW-4, 1)
    hLine:setFillColor(0.25, 0.75, 1.0, 0.4)

    display.newText({
        parent=content, text="// TUTORIAL TASKS",
        x=panelX, y=panelY-panelH*0.5+20,
        font=ui.FONT_BOLD, fontSize=15
    }):setFillColor(0.3, 0.90, 1.0)

    local closeY  = panelY + panelH*0.5 - 24
    local closeBg = display.newRoundedRect(content, panelX, closeY, 110, 30, 6)
    closeBg:setFillColor(0.04, 0.12, 0.32, 0.97)
    closeBg.strokeWidth=1.5; closeBg:setStrokeColor(0.25,0.65,1.0,0.8)
    display.newText({
        parent=content, text="CLOSE",
        x=panelX, y=closeY, font=ui.FONT_BOLD, fontSize=13
    }):setFillColor(0.7, 0.90, 1.0)

    local function closePopup()
        clearModalLayer(sceneView, popupGrp)
        return ui.popupClose(popupGrp, dim, { content }, onClose)
    end

    swallowTouches(dim)
    blockBehindTouches(closeBg, closePopup)

    local visibleCards = tasksUtil.getVisible(freshPlayer)
    local cardH   = 84
    local cardPad = 8
    local cardW   = panelW - 24
    local listTop = panelY - panelH*0.5 + 50
    local cardX   = panelX

    for i, item in ipairs(visibleCards) do
        local def      = item.def
        local state    = item.state
        local unlocked = item.unlocked
        local cardY    = listTop + (i-1)*(cardH+cardPad) + cardH*0.5
        if cardY + cardH*0.5 > panelY + panelH*0.5 - 46 then break end

        local cardBg = display.newRoundedRect(content, cardX, cardY, cardW, cardH, 8)
        if not unlocked then
            cardBg:setFillColor(0.06,0.06,0.12,0.97)
            cardBg.strokeWidth=1; cardBg:setStrokeColor(0.18,0.18,0.28,0.6)
        elseif state.claimed then
            cardBg:setFillColor(0.04,0.18,0.08,0.97)
            cardBg.strokeWidth=1.5; cardBg:setStrokeColor(0.18,0.70,0.28,0.7)
        else
            cardBg:setFillColor(0.04,0.10,0.24,0.97)
            cardBg.strokeWidth=1.5; cardBg:setStrokeColor(0.25,0.55,1.0,0.8)
        end

        local iconBoxX = cardX - cardW*0.5 + 20
        local iconBox  = display.newRoundedRect(content, iconBoxX, cardY, 28, 28, 5)
        if not unlocked then
            iconBox:setFillColor(0.10,0.10,0.18); iconBox.strokeWidth=1
            iconBox:setStrokeColor(0.25,0.25,0.35)
        elseif state.claimed then
            iconBox:setFillColor(0.08,0.30,0.12); iconBox.strokeWidth=1.5
            iconBox:setStrokeColor(0.20,0.80,0.30)
        else
            iconBox:setFillColor(0.08,0.18,0.42); iconBox.strokeWidth=1.5
            iconBox:setStrokeColor(0.30,0.65,1.0)
        end

        local iconLbl = display.newText({
            parent=content,
            text = state and state.claimed and "✓" or "!",
            x=iconBoxX, y=cardY, font=ui.FONT_BOLD, fontSize=16
        })
        if not unlocked then iconLbl:setFillColor(0.35,0.35,0.45)
        elseif state.claimed then iconLbl:setFillColor(0.3,1.0,0.4)
        else iconLbl:setFillColor(1.0,0.85,0.2) end

        local textX = iconBoxX + 22
        local titleT = display.newText({
            parent=content, text=def.title,
            x=textX, y=cardY-22, font=ui.FONT_BOLD, fontSize=13, align="left"
        })
        titleT:setFillColor(not unlocked and 0.4 or 1.0,
                            not unlocked and 0.4 or 1.0,
                            not unlocked and 0.5 or 1.0)
        titleT.anchorX = 0

        local descT = display.newText({
            parent=content, text=def.description,
            x=textX, y=cardY-6, width=cardW-130, font=ui.FONT_BOLD, fontSize=9, align="left"
        })
        descT:setFillColor(0.60,0.68,0.82); descT.anchorX=0

        local rewardT = display.newText({
            parent=content,
            text="+"..def.xpReward.." XP  +"..def.goldReward.."g",
            x=cardX+cardW*0.5-8, y=cardY-22, font=ui.FONT_BOLD, fontSize=10, align="right"
        })
        rewardT:setFillColor(1.0,0.82,0.20); rewardT.anchorX=1

        local barW   = cardW - 18
        local barH   = 7
        local barBgY = cardY + 22
        local barBg  = display.newRoundedRect(content, cardX, barBgY, barW, barH, 3)
        barBg:setFillColor(0.08,0.08,0.18)

        local prog  = state and state.progress or 0
        local ratio = math.min(prog / def.goal, 1)
        if unlocked and ratio > 0 then
            local fillW = math.max(barW*ratio, 5)
            local fill  = display.newRoundedRect(content,
                cardX - barW*0.5 + fillW*0.5, barBgY, fillW, barH, 3)
            fill:setFillColor(state.claimed and 0.18 or 0.15,
                              state.claimed and 0.72 or 0.50,
                              state.claimed and 0.30 or 1.00)
        end

        if not unlocked then
            local lT = display.newText({ parent=content,
                text="LOCKED — complete previous task",
                x=cardX, y=barBgY+13, font=ui.FONT_BOLD, fontSize=8, align="center"})
            lT:setFillColor(0.38,0.38,0.48)
        elseif state.claimed then
            local dT = display.newText({ parent=content, text="COMPLETE",
                x=cardX, y=barBgY+13, font=ui.FONT_BOLD, fontSize=9, align="center"})
            dT:setFillColor(0.30,0.88,0.42)
        elseif prog >= def.goal then
            local claimW = 72
            local claimX = cardX + cardW*0.5 - claimW*0.5 - 6
            local claimBg = display.newRoundedRect(content, claimX, barBgY+2, claimW, 22, 5)
            claimBg:setFillColor(0.08,0.42,0.16,0.97)
            claimBg.strokeWidth=1.5; claimBg:setStrokeColor(0.22,0.88,0.32,0.9)
            display.newText({ parent=content, text="CLAIM",
                x=claimX, y=barBgY+2, font=ui.FONT_BOLD, fontSize=11
            }):setFillColor(0.4,1.0,0.55)

            local capId = def.id
            blockBehindTouches(claimBg, function()
                local p2 = save.load()
                local xpGain, goldGain = tasksUtil.claim(p2, capId)
                if xpGain then
                    save.save(p2)
                    local toast = display.newText({ parent=content,
                        text="+"..xpGain.." XP   +"..goldGain.."g",
                        x=panelX, y=panelY, font=ui.FONT_BOLD, fontSize=20 })
                    toast:setFillColor(1.0,0.88,0.18)
                    transition.to(toast, { y=toast.y-50, alpha=0, time=1100,
                        onComplete=function()
                            if toast.removeSelf then toast:removeSelf() end
                            clearModalLayer(sceneView, popupGrp)
                            popupGrp:removeSelf()
                            buildTasksPopup(sceneView, onClose)
                        end })
                end
                return true
            end)
        else
            local pT = display.newText({ parent=content,
                text=tostring(prog).." / "..tostring(def.goal),
                x=cardX, y=barBgY+13, font=ui.FONT_BOLD, fontSize=9, align="center"})
            pT:setFillColor(0.50,0.72,1.0)
        end
    end

    ui.popupOpen(dim, { content })

    return popupGrp
end

local function buildTaskQuickPopup(sceneView, taskItem)
    local def = taskItem.def
    local state = taskItem.state or {}
    local progress = state.progress or 0
    local isClaimed = state.claimed == true
    local isClaimable = (not isClaimed) and progress >= (def.goal or 1)
    local popupGrp = display.newGroup()
    sceneView:insert(popupGrp)

    local dim = display.newRect(popupGrp, SW * 0.5, SH * 0.5, SW, SH)
    dim:setFillColor(0, 0, 0, 0.74)
    dim.isHitTestable = true
    keepModalOnTop(sceneView, popupGrp)

    local content = display.newGroup()
    popupGrp:insert(content)

    local panelW = SW - 34
    local panelH = 286
    local panelX = SW * 0.5
    local panelY = SH * 0.5

    local glow = display.newRoundedRect(content, panelX, panelY, panelW + 6, panelH + 6, 16)
    glow:setFillColor(0, 0, 0, 0)
    glow.strokeWidth = 3
    glow:setStrokeColor(0.22, 0.82, 1.0, 0.30)

    local panel = display.newRoundedRect(content, panelX, panelY, panelW, panelH, 14)
    panel:setFillColor(0.02, 0.06, 0.16, 0.97)
    panel.strokeWidth = 2
    panel:setStrokeColor(0.25, 0.75, 1.0, 0.80)
    blockBehindTouches(panel)

    local topBar = display.newRoundedRect(content, panelX, panelY - panelH * 0.5 + 3, panelW - 10, 4, 2)
    topBar:setFillColor(0.28, 0.86, 1.0, 0.78)

    local title = display.newText({
        parent=content, text=string.upper(def.title),
        x=panelX, y=panelY - panelH * 0.5 + 24, width=panelW - 40,
        font=ui.FONT_BOLD, fontSize=15, align="center"
    })
    title:setFillColor(0.84, 0.96, 1.0)

    local iconBox = display.newRoundedRect(content, panelX, panelY - 46, 74, 74, 12)
    iconBox:setFillColor(0.05, 0.14, 0.30, 0.96)
    iconBox.strokeWidth = 1.5
    iconBox:setStrokeColor(0.28, 0.68, 1.0, 0.62)

    local okIcon, iconImg = pcall(display.newImageRect,
        content,
        "assets/sprites/ui/icons/" .. (def.icon or "fight") .. ".png",
        34, 34
    )
    if okIcon and iconImg then
        iconImg.x = panelX
        iconImg.y = iconBox.y
    end

    local desc = display.newText({
        parent=content, text=def.description,
        x=panelX, y=panelY + 18, width=panelW - 46,
        font=ui.FONT_BOLD, fontSize=11, align="center"
    })
    desc:setFillColor(0.72, 0.84, 0.98)

    local reward = display.newText({
        parent=content,
        text="+" .. def.xpReward .. " XP   +" .. def.goldReward .. " GOLD",
        x=panelX, y=panelY + 62, width=panelW - 60,
        font=ui.FONT_BOLD, fontSize=11, align="center"
    })
    reward:setFillColor(1.0, 0.84, 0.24)

    local goBtn = display.newRoundedRect(content, panelX - 64, panelY + 108, 96, 32, 8)
    if isClaimable then
        goBtn:setFillColor(0.08, 0.42, 0.16, 0.97)
        goBtn.strokeWidth = 1.5
        goBtn:setStrokeColor(0.22, 0.88, 0.32, 0.90)
    elseif isClaimed then
        goBtn:setFillColor(0.07, 0.12, 0.16, 0.92)
        goBtn.strokeWidth = 1.5
        goBtn:setStrokeColor(0.24, 0.34, 0.40, 0.65)
    else
        goBtn:setFillColor(0.05, 0.18, 0.42, 0.97)
        goBtn.strokeWidth = 1.5
        goBtn:setStrokeColor(0.28, 0.68, 1.0, 0.82)
    end
    local goLabel = display.newText({
        parent=content, text=isClaimable and "CLAIM REWARD" or (isClaimed and "CLAIMED" or "GO"),
        x=goBtn.x, y=goBtn.y, font=ui.FONT_BOLD, fontSize=12
    })
    if isClaimable then
        goLabel:setFillColor(0.4, 1.0, 0.55)
    elseif isClaimed then
        goLabel:setFillColor(0.62, 0.72, 0.78)
    else
        goLabel:setFillColor(0.78, 0.92, 1.0)
    end

    local closeBtn = display.newRoundedRect(content, panelX + 64, panelY + 108, 96, 32, 8)
    closeBtn:setFillColor(0.08, 0.10, 0.18, 0.97)
    closeBtn.strokeWidth = 1.5
    closeBtn:setStrokeColor(0.28, 0.32, 0.44, 0.72)
    display.newText({
        parent=content, text="EXIT",
        x=closeBtn.x, y=closeBtn.y, font=ui.FONT_BOLD, fontSize=12
    }):setFillColor(0.68, 0.78, 0.92)

    local function closePopup()
        clearModalLayer(sceneView, popupGrp)
        return ui.popupClose(popupGrp, dim, { content })
    end

    swallowTouches(dim)
    blockBehindTouches(closeBtn, closePopup)
    blockBehindTouches(goBtn, function()
        if isClaimed then
            return closePopup()
        end

        if isClaimable then
            local freshPlayer = save.load()
            local xpGain, goldGain = tasksUtil.claim(freshPlayer, def.id)
            if xpGain then
                applyLevelUps(freshPlayer)
                save.save(freshPlayer)
            end
            closePopup()
            composer.gotoScene("scenes.home", { effect="crossFade", time=0 })
            return true
        end

        closePopup()
        composer.gotoScene(def.scene or "scenes.home", { effect="slideLeft", time=220 })
        return true
    end)

    ui.popupOpen(dim, { content })

    return popupGrp
end

-------------------------------------------------
-- SCENE CREATE
-------------------------------------------------
function scene:create(event)
    local sg     = self.view
    local player = save.load()
    player.diamonds = player.diamonds or 0
    self._ambientDots = {}
    self._petSprites = {}
    self._statIcons = {}
    self._chatMessages = {
        "Arena reset in 2 hours",
        "Anyone recruiting for clans?",
        "Looking for active members",
        "Selling rare pets",
    }
    self._chatIndex = 1
    self._notifications = {}
    self._notifMessages = { "No notifications" }
    self._notifIndex = 1

    local screenW = SW
    local screenH = SH

    local bg = display.newImage("assets/sprites/ui/bg_home_grid.png")
    bg:scale(math.max(screenW/bg.width, screenH/bg.height),
             math.max(screenW/bg.width, screenH/bg.height))
    bg.x = CX; bg.y = SH*0.5
    bg.isHitTestable = false
    sg:insert(bg)

    buildAmbientDots(self, sg, screenW, screenH)
    buildFallingSparkles(self, sg, screenW, screenH)

    local frameTop  = display.screenOriginY + 30
    local frameH    = 158
    local framePad  = 10
    local frameW    = screenW - 12

    local frameGlow = display.newRoundedRect(sg, CX, frameTop + frameH*0.5, frameW+8, frameH+8, 16)
    frameGlow:setFillColor(0,0,0,0)
    frameGlow.strokeWidth = 3
    frameGlow:setStrokeColor(0.15, 0.55, 1.0, 0.22)
    frameGlow.isHitTestable = false
    flicker(frameGlow, 0.5, 1.0, 1800)

    local frameBg = display.newRoundedRect(sg, CX, frameTop + frameH*0.5, frameW, frameH, 13)
    frameBg:setFillColor(0.03, 0.07, 0.18, 0.93)
    frameBg.strokeWidth = 2
    frameBg:setStrokeColor(0.28, 0.65, 1.0, 0.80)
    frameBg.isHitTestable = false
    flicker(frameBg, 0.90, 1.0, 2600)

    local frameAccent = display.newRect(sg, CX, frameTop + 3, frameW - 4, 3)
    frameAccent:setFillColor(0.3, 0.7, 1.0, 0.7)
    frameAccent.isHitTestable = false

    local frameAccentB = display.newRect(sg, CX, frameTop + frameH - 3, frameW - 4, 3)
    frameAccentB:setFillColor(0.15, 0.45, 1.0, 0.35)
    frameAccentB.isHitTestable = false

    local corners = {
        { CX - frameW*0.5 + 6, frameTop + 6 },
        { CX + frameW*0.5 - 6, frameTop + 6 },
        { CX - frameW*0.5 + 6, frameTop + frameH - 6 },
        { CX + frameW*0.5 - 6, frameTop + frameH - 6 },
    }
    for _, c in ipairs(corners) do
        local dot = display.newCircle(sg, c[1], c[2], 3)
        dot:setFillColor(0.4, 0.8, 1.0, 0.9)
        dot.isHitTestable = false
        flicker(dot, 0.4, 1.0, math.random(600, 1400))
    end

    local scanLine = display.newRect(sg, CX, frameTop + 6, frameW - 4, 2)
    scanLine:setFillColor(0.4, 0.8, 1.0, 0.07)
    scanLine.isHitTestable = false
    local function doScan()
        scanLine.y = frameTop + 6; scanLine.alpha = 0.07
        transition.to(scanLine, { y=frameTop+frameH-6, alpha=0,
            time=2200, transition=easing.inOutQuad,
            onComplete=function()
                timer.performWithDelay(math.random(600,1800), doScan)
            end })
    end
    timer.performWithDelay(math.random(0, 1000), doScan)

    local identY = frameTop + 30

    local levelBadge
    local okLB, lb = pcall(display.newImageRect, sg, "assets/sprites/ui/level.png", 48, 48)
    if okLB and lb then
        levelBadge = lb; levelBadge.x = framePad + 30; levelBadge.y = identY
    else
        levelBadge = display.newRoundedRect(sg, framePad + 30, identY, 44, 44, 22)
        levelBadge:setFillColor(0.05, 0.15, 0.40, 0.9)
        levelBadge.strokeWidth = 2; levelBadge:setStrokeColor(0.3, 0.7, 1.0, 0.8)
    end

    levelNumberText = display.newText({
        parent=sg, text=tostring(player.level),
        x=framePad + 30, y=identY + 2, font=ui.FONT_BOLD, fontSize=20
    })
    levelNumberText:setFillColor(0.55, 0.85, 1.0)

    nameText = display.newText({
        parent=sg, text=player.name or "Player",
        x=framePad + 62, y=identY - 10,
        font=ui.FONT_BOLD, fontSize=22, align="left"
    })
    nameText.anchorX = 0; nameText:setFillColor(1, 1, 1)

    local xpBarX  = framePad + 62
    local xpBarW  = frameW - xpBarX - framePad - 4
    local xpBarY  = identY + 8

    local xpBarBg = display.newRoundedRect(sg, xpBarX + xpBarW*0.5, xpBarY, xpBarW, 7, 3)
    xpBarBg:setFillColor(0.05, 0.08, 0.18)

    xpBarFill = display.newRoundedRect(sg, xpBarX, xpBarY, xpBarW, 7, 3)
    xpBarFill.anchorX = 0; xpBarFill:setFillColor(0.28, 0.82, 1.0)
    xpBarFill._maxW = xpBarW; xpBarFill._baseX = xpBarX

    local xpShimmer = display.newRect(sg, xpBarX - 20, xpBarY, 18, 7)
    xpShimmer.anchorX = 0
    xpShimmer.rotation = -18
    xpShimmer:setFillColor(1, 1, 1, 0.0)
    xpShimmer.isHitTestable = false
    self._xpShimmer = xpShimmer
    self._xpBarY = xpBarY

    levelXpText = display.newText({
        parent=sg, text="XP 0 / 0",
        x=xpBarX, y=xpBarY + 10,
        font=ui.FONT_BOLD, fontSize=8, align="left"
    })
    levelXpText.anchorX = 0; levelXpText:setFillColor(0.5, 0.7, 0.9)

    local function goProfile()
        composer.gotoScene("scenes.profile", { effect="slideUp", time=260 })
    end

    local function goProfileSelect()
        composer.removeScene("scenes.profile")
        composer.gotoScene("scenes.profile_select", { effect="fade", time=280 })
    end

    local function showSettingsPopup()
        if activeSettingsPopup and activeSettingsPopup.removeSelf then
            activeSettingsPopup:toFront()
            return true
        end

        local overlay = display.newGroup()
        sg:insert(overlay)
        activeSettingsPopup = overlay

        local dim = display.newRect(overlay, CX, CY, SW, SH)
        dim:setFillColor(0, 0, 0, 0.72)

        local panel = display.newRoundedRect(overlay, CX, CY, SW * 0.78, 188, 12)
        panel:setFillColor(0.03, 0.08, 0.20, 0.98)
        panel.strokeWidth = 1.5
        panel:setStrokeColor(0.20, 0.70, 1.0, 0.82)
        swallowTouches(panel)

        display.newText({
            parent=overlay, text="SETTINGS",
            x=CX, y=CY-66, font=ui.FONT_BOLD, fontSize=15, align="center"
        }):setFillColor(0.42, 0.92, 1.0)

        local function popupBtn(label, y, color, onTap)
            local bg = display.newRoundedRect(overlay, CX, y, SW * 0.58, 34, 8)
            bg:setFillColor(color[1], color[2], color[3], 0.92)
            bg.strokeWidth = 1.2
            bg:setStrokeColor(0.24, 0.72, 1.0, 0.78)
            display.newText({
                parent=overlay, text=label,
                x=CX, y=y, font=ui.FONT_BOLD, fontSize=11, align="center"
            }):setFillColor(0.76, 0.96, 1.0)
            bg:addEventListener("tap", function()
                closeSettingsPopup()
                if onTap then onTap() end
                return true
            end)
            return bg
        end

        popupBtn("PROFILE", CY-22, {0.04, 0.18, 0.50}, goProfile)
        popupBtn("SWITCH PROFILE", CY+22, {0.04, 0.14, 0.38}, goProfileSelect)
        popupBtn("CLOSE", CY+66, {0.12, 0.05, 0.08}, nil)

        blockBehindTouches(dim, function()
            closeSettingsPopup()
            return true
        end)
        overlay:toFront()
        return true
    end

    local function makeCardIcon(iconName, x, y, onTap)
        local glow = display.newRoundedRect(sg, x, y, 32, 32, 9)
        glow:setFillColor(0.04, 0.24, 0.46, 0.34)
        glow.strokeWidth = 1
        glow:setStrokeColor(0.22, 0.82, 1.0, 0.32)

        local bg = display.newRoundedRect(sg, x, y, 28, 28, 8)
        bg:setFillColor(0.02, 0.08, 0.18, 0.92)
        bg.strokeWidth = 1
        bg:setStrokeColor(0.28, 0.76, 1.0, 0.72)

        local okIcon, icon = pcall(display.newImageRect, sg, "assets/sprites/ui/icons/" .. iconName .. ".png", 20, 20)
        if okIcon and icon then
            icon.x = x
            icon.y = y
            icon.isHitTestable = false
        else
            local fallback = display.newText({
                parent=sg, text=iconName == "logout" and ">" or "*",
                x=x, y=y, font=ui.FONT_BOLD, fontSize=13, align="center"
            })
            fallback:setFillColor(0.55, 0.92, 1.0)
            fallback.isHitTestable = false
        end

        bg:addEventListener("tap", function()
            if onTap then onTap() end
            return true
        end)
        return bg
    end

    local cardRight = CX + frameW * 0.5 - framePad - 3
    local cardIconY = frameTop + 22
    makeCardIcon("settings", cardRight - 38, cardIconY, showSettingsPopup)
    makeCardIcon("logout",   cardRight - 6,  cardIconY, goProfileSelect)

    local divY = frameTop + 56
    local div  = display.newRect(sg, CX, divY, frameW - 20, 1)
    div:setFillColor(0.25, 0.60, 1.0, 0.24)
    div.isHitTestable = false

    local row1Stats = {
        { key="ATK", icon="atk" },
        { key="DEF", icon="def" },
        { key="SPD", icon="spd" },
        { key="HP",  icon="hp"  },
    }
    local row2Stats = {
        { key="ENERGY",   icon="energy"   },
        { key="WIN",      icon="win"       },
        { key="GOLD",     icon="gold"      },
        { key="DIAMONDS", icon="diamonds"  },
    }

    local colW     = frameW / 4
    local row1Y    = divY + 24
    local row2Y    = divY + 68
    local iconSize = 22

    local function makeStatCol(row, y)
        for col, s in ipairs(row) do
            local cx2  = CX - frameW*0.5 + (col - 0.5) * colW
            local ix   = cx2 - 14
            local tx   = cx2 + 4

            local okI, ico = pcall(display.newImageRect, sg,
                "assets/sprites/ui/icons/"..s.icon..".png", iconSize, iconSize)
            if okI and ico then
                ico.x = ix; ico.y = y; ico.isHitTestable = false
                ico.alpha = 0.82
                self._statIcons[s.key] = ico
            else
                local ph = display.newRoundedRect(sg, ix, y, iconSize, iconSize, 4)
                ph:setFillColor(0.15, 0.25, 0.50, 0.7); ph.isHitTestable = false
                local fl = display.newText({ parent=sg, text=s.key:sub(1,1),
                    x=ix, y=y, font=ui.FONT_BOLD, fontSize=9 })
                fl:setFillColor(0.6, 0.8, 1.0); fl.isHitTestable = false
            end

            local color = { 1, 1, 1 }
            if s.key == "ENERGY"   then color = { 0.3, 1.0, 0.6 } end
            if s.key == "DIAMONDS" then color = { 0.7, 0.4, 1.0 } end

            local isEnergy = (s.key == "ENERGY")
            local txt = display.newText({
                parent=sg,
                text = isEnergy and "30/30" or "0",
                x=tx, y=y, font=ui.FONT_BOLD, fontSize=9
            })
            txt.anchorX = 0
            txt:setFillColor(color[1], color[2], color[3])
            statTexts[s.key] = txt
            if s.key == "ENERGY"   then energyText  = txt end
            if s.key == "DIAMONDS" then diamondText  = txt end
        end
    end

    makeStatCol(row1Stats, row1Y)
    makeStatCol(row2Stats, row2Y)

    local div2 = display.newRect(sg, CX, divY + 46, frameW - 20, 1)
    div2:setFillColor(0.2, 0.45, 0.85, 0.14); div2.isHitTestable = false

    local taskStripH = 74
    local taskStripY = SH - 118
    self._taskStripY = taskStripY
    self._taskStripH = taskStripH
    self._taskRowRef = nil

    local showcaseTop = frameTop + frameH + 28
    local showcaseBottom = showcaseTop + 184
    local showcaseY = showcaseTop + (showcaseBottom - showcaseTop) * 0.5
    local showcaseFloor = display.newRoundedRect(sg, CX, showcaseBottom - 18, screenW - 104, 16, 8)
    showcaseFloor:setFillColor(0, 0, 0, 0.22)
    showcaseFloor.isHitTestable = false

    local characterGroup = display.newGroup()
    sg:insert(characterGroup)
    self._characterGroup = characterGroup

    local spriteBaseY = showcaseBottom - 89

    local playerShadow = display.newRoundedRect(characterGroup, CX - 18, spriteBaseY + 78, 66, 14, 7)
    playerShadow:setFillColor(0, 0, 0, 0.30)
    playerShadow.isHitTestable = false
    self._playerShadow = playerShadow

    local heroGlow = display.newCircle(characterGroup, CX - 18, spriteBaseY - 12, 84)
    heroGlow:setFillColor(0.18, 0.56, 1.0, 0.08)
    heroGlow.isHitTestable = false
    flicker(heroGlow, 0.35, 0.95, 1700)

    local heroScan = display.newRect(characterGroup, CX, showcaseTop + 18, screenW - 74, 2)
    heroScan:setFillColor(0.52, 0.86, 1.0, 0.08)
    heroScan.isHitTestable = false
    local function doHeroScan()
        if not heroScan or not heroScan.removeSelf then return end
        heroScan.y = showcaseTop + 18
        heroScan.alpha = 0.09
        transition.to(heroScan, {
            y = showcaseBottom - 22,
            alpha = 0,
            time = 2400,
            transition = easing.inOutQuad,
            onComplete = function()
                trackTimer(timer.performWithDelay(math.random(1200, 2400), doHeroScan))
            end
        })
    end
    trackTimer(timer.performWithDelay(600, doHeroScan))

    local playerSkin = (player.appearance and player.appearance.skinId) or "street_brawler"
    local okSp, playerSprite = pcall(display.newImageRect, characterGroup,
        "assets/sprites/characters/"..playerSkin.."/battle.png", 108, 178)
    if okSp and playerSprite then
        playerSprite.x = CX - 20
        playerSprite.y = spriteBaseY
        self._playerSprite = playerSprite
        self._playerBaseY = spriteBaseY
    end

    self._spriteBaseY = spriteBaseY
    renderHomePets(self, player)

    -- Home button stack tuning:
    -- `btnH` controls the two social/guild rows.
    -- `btnGap` controls vertical spacing between those rows.
    -- `matH` keeps the materials bar the same visual height while retaining full width.
    -- Task icons are anchored around the radial home button near the bottom.
    local btnW   = (screenW - 52) * 0.5
    local btnH   = 32
    local btnGap = 6
    local chatY = showcaseBottom + 28
    local socialTop = chatY + 18
    local row1Y  = socialTop + 22
    local row2Y  = row1Y + btnH + btnGap
    local leftX  = CX - btnW*0.5 - btnGap*0.5
    local rightX = CX + btnW*0.5 + btnGap*0.5
    local socialPanelH = (row2Y + btnH * 0.5 + 12) - (socialTop + 8)

    local socialPanel = display.newRoundedRect(sg, CX, socialTop + socialPanelH * 0.5, screenW - 20, socialPanelH, 16)
    socialPanel:setFillColor(0.02, 0.05, 0.14, 0.86)
    socialPanel.strokeWidth = 1.5
    socialPanel:setStrokeColor(0.18, 0.50, 0.90, 0.44)
    socialPanel.isHitTestable = false

    local socialDividerH = display.newRect(sg, CX, row1Y + btnH * 0.5 + btnGap * 0.5, screenW - 44, 1)
    socialDividerH:setFillColor(0.18, 0.48, 0.82, 0.18)
    socialDividerH.isHitTestable = false

    local socialDividerV = display.newRect(sg, CX, socialTop + socialPanelH * 0.5 + 8, 1, socialPanelH - 26)
    socialDividerV:setFillColor(0.18, 0.48, 0.82, 0.16)
    socialDividerV.isHitTestable = false

    self._guildBtnLayout = { btnW=btnW, btnH=btnH, row1Y=row1Y, leftX=leftX, rightX=rightX }

    makeNavBtn(sg, leftX, row2Y, btnW, btnH, "FRIENDS", function()
        composer.gotoScene("scenes.friends", { effect="slideLeft", time=220 })
    end)
    makeNavBtn(sg, rightX, row2Y, btnW, btnH, "MESSAGES", function()
        composer.gotoScene("scenes.messages", { effect="slideLeft", time=220 })
    end)

    local chatHit = display.newRect(sg, CX, chatY, screenW - 20, 24)
    chatHit:setFillColor(0, 0, 0, 0.01)
    chatHit.isHitTestable = true
    self._chatBg = chatHit

    local chatLine = display.newRect(sg, CX, chatY + 13, screenW - 44, 1)
    chatLine:setFillColor(0.16, 0.52, 0.82, 0.22)
    chatLine.isHitTestable = false

    local chatAccent = display.newRect(sg, 26, chatY, 2, 16)
    chatAccent:setFillColor(0.25, 0.90, 0.55, 0.72)
    chatAccent.isHitTestable = false

    local okChatIcon, chatTag = pcall(display.newImageRect,
        sg,
        "assets/sprites/ui/icons/wchat.png",
        16, 16
    )
    if okChatIcon and chatTag then
        chatTag.x = 42
        chatTag.y = chatY
        chatTag.isHitTestable = false
        self._chatTag = chatTag
    end

    local chatText = display.newText({
        parent=sg, text=self._chatMessages[1],
        x=58, y=chatY, width=screenW-110, font=ui.FONT, fontSize=11, align="left"
    })
    chatText.anchorX = 0
    chatText:setFillColor(0.80, 0.96, 0.90)
    self._chatText = chatText

    chatHit:addEventListener("tap", function()
        composer.gotoScene("scenes.world_chat", { effect="slideUp", time=220 })
        return true
    end)

    local matBtnY = row2Y + btnH * 0.5 + 50
    local matBtnW = screenW - 20
    local matH    = 48
    local matGlow = display.newRoundedRect(sg, CX, matBtnY, matBtnW + 8, matH + 8, 14)
    matGlow:setFillColor(0.10, 0.45, 1.0, 0.08)
    matGlow.isHitTestable = false
    flicker(matGlow, 0.45, 0.95, 1600)

    local matBg = display.newRoundedRect(sg, CX, matBtnY, matBtnW, matH, 12)
    matBg:setFillColor(0.03, 0.08, 0.18, 0.94)
    matBg.strokeWidth = 1.5
    matBg:setStrokeColor(0.22, 0.58, 0.96, 0.52)

    local matTopAccent = display.newRect(sg, CX, matBtnY - matH * 0.5 + 4, matBtnW - 14, 2)
    matTopAccent:setFillColor(0.32, 0.76, 1.0, 0.52)
    matTopAccent.isHitTestable = false

    local matDefs = {
        { icon="scrap", key="scrap" },
        { icon="coil",  key="coil"  },
        { icon="chip",  key="chip"  },
    }
    local colWM   = matBtnW / 3
    local startX  = CX - matBtnW*0.5 + colWM*0.5

    for i, mat in ipairs(matDefs) do
        local mx = startX + (i-1)*colWM
        local iconPath = mat.icon == "coil"
            and "assets/sprites/more/large_coil.png"
            or ("assets/sprites/more/" .. mat.icon .. ".png")
        local ok, ic = pcall(display.newImageRect, sg,
            iconPath, 24, 24)
        if ok and ic then ic.x=mx-22; ic.y=matBtnY; ic.isHitTestable=false end
        local numTxt = display.newText({
            parent=sg, text="0",
            x=mx+2, y=matBtnY, font=ui.FONT_BOLD, fontSize=14, align="left"
        })
        numTxt:setFillColor(1,1,1); numTxt.isHitTestable=false
        matNumTexts[mat.key] = numTxt

        if i < #matDefs then
            local divider = display.newRect(sg, mx + colWM * 0.5, matBtnY, 1, matH - 16)
            divider:setFillColor(0.22, 0.50, 0.86, 0.22)
            divider.isHitTestable = false
        end
    end

    local matLocked = false
    matBg:addEventListener("touch", function(event)
        if matLocked and event.phase == "began" then return true end
        if event.phase == "began" then
            matLocked = true
            display.getCurrentStage():setFocus(matBg)
            matBg._hasFocus = true
            setNavPressed(matBg, true)
        elseif matBg._hasFocus and (event.phase == "ended" or event.phase == "cancelled") then
            display.getCurrentStage():setFocus(nil)
            matBg._hasFocus = false
            setNavPressed(matBg, false)
            matLocked = false
            if event.phase == "ended" then
                composer.gotoScene("scenes.materials", { effect="slideLeft", time=200 })
            end
        end
        return true
    end)

    local taskIconsY = SH - 100
    self._taskIconsY   = taskIconsY
    self._taskIconGroup = nil

    local notifY = matBtnY + matH * 0.5 + 34
    self._barY = notifY

    local bellBtnX = 42
    local bellCircle = display.newRoundedRect(sg, CX, notifY, screenW - 20, 28, 9)
    bellCircle:setFillColor(0, 0, 0, 0.01)
    bellCircle.strokeWidth = 0
    self._bellCircle = bellCircle

    local notifAccent = display.newRect(sg, 26, notifY, 2, 18)
    notifAccent:setFillColor(0.42, 0.78, 1.0, 0.72)
    notifAccent.isHitTestable = false

    local bellIcon = display.newText({
        parent=sg, text="🔔",
        x=bellBtnX, y=notifY - 1,
        font=ui.FONT_BOLD, fontSize=14
    })
    bellIcon.text = "!"
    bellIcon:setFillColor(0.84, 0.94, 1.0)

    local bellLabel = display.newText({
        parent=sg, text=self._notifMessages[self._notifIndex],
        x=58, y=notifY,
        width=screenW - 110,
        font=ui.FONT, fontSize=11, align="left"
    })
    bellLabel.anchorX = 0
    bellLabel:setFillColor(0.84, 0.94, 1.0)
    self._bellLabel = bellLabel

    local function openNotification(n)
        if not n or not n.replay or not n.replay.log then return false end
        local replayOpponent = n.replay.opponent or {}
        local final = stats.calculate(replayOpponent)
        local replayOpponentForBattle = {
            id = replayOpponent.playerId or replayOpponent.id or replayOpponent.displayName or replayOpponent.name,
            name = replayOpponent.displayName or replayOpponent.name or n.fromName or "Player",
            visualId = replayOpponent.visualId or replayOpponent.skinId
                or (replayOpponent.appearance and replayOpponent.appearance.skinId)
                or "street_brawler",
            level = replayOpponent.level or 1,
            attack = final.attack or replayOpponent.attack or 100,
            defense = final.defense or replayOpponent.defense or 100,
            speed = final.speed or replayOpponent.speed or 100,
            hp = final.hp or replayOpponent.hp or 100,
            pets = replayOpponent.pets or (replayOpponent.equipped and replayOpponent.equipped.pets) or {},
            equipped = replayOpponent.equipped or { weapons={}, armor={}, accessories={}, pets={} },
            currentWeaponIndex = replayOpponent.currentWeaponIndex or 1,
            weaponUsesLeft = replayOpponent.weaponUsesLeft,
        }
        battleContext.startArena(replayOpponentForBattle, {
            winner = n.replay.winner,
            log = n.replay.log,
        })
        composer.gotoScene("scenes.arena_battle", { effect="slideLeft", time=220 })
        return true
    end

    local function showNotifPopup()
        local popGrp = display.newGroup()
        self.view:insert(popGrp)

        local dim = display.newRect(popGrp, SW*0.5, SH*0.5, SW, SH)
        dim:setFillColor(0,0,0,0.70); dim.isHitTestable = true

        local content = display.newGroup()
        popGrp:insert(content)

        local pW = SW - 20; local pH = 600; local pX = SW*0.5; local pY = SH*0.45
        local pg = display.newRoundedRect(content, pX, pY, pW, pH, 14)
        pg:setFillColor(0.02, 0.06, 0.16, 0.97)
        pg.strokeWidth=2; pg:setStrokeColor(0.25, 0.65, 1.0, 0.80)
        swallowTouches(pg)

        for i=0,6 do
            local sl = display.newRect(content, pX, pY-pH*0.5+i*(pH/6), pW-4, 1)
            sl:setFillColor(0.2,0.8,1.0,0.022)
        end

        display.newText({ parent=content, text="// NOTIFICATIONS",
            x=pX, y=pY-pH*0.5+20, font=ui.FONT_BOLD, fontSize=14
        }):setFillColor(0.3, 0.90, 1.0)

        local hLine = display.newRect(content, pX, pY-pH*0.5+38, pW-4, 1)
        hLine:setFillColor(0.25,0.75,1.0,0.4)

        local notifs = self._notifications or {}
        if #notifs == 0 then
            notifs = { { text="No notifications", timeLabel="" } }
        end
        for i, n in ipairs(notifs) do
            if i > 4 then break end
            local notifText = n.text or n.message or "Notification"
            local notifTime = timeLabels.forMessage(n)
            local ny = pY - pH*0.5 + 55 + (i-1)*52
            local nBg = display.newRoundedRect(content, pX, ny, pW-20, 42, 7)
            nBg:setFillColor(0.04,0.10,0.24,0.97)
            nBg.strokeWidth=1; nBg:setStrokeColor(0.22,0.50,1.0,0.55)
            local dot = display.newCircle(content, pX-pW*0.5+22, ny, 4)
            dot:setFillColor(0.3, 0.75, 1.0)
            local nt = display.newText({ parent=content, text=notifText,
                x=pX+4, y=ny-6, width=pW-50, font=ui.FONT_BOLD, fontSize=10, align="left"})
            nt:setFillColor(0.85,0.95,1.0); nt.anchorX=0; nt.x=pX-pW*0.5+34
            local tt = display.newText({ parent=content, text=notifTime,
                x=pX+pW*0.5-14, y=ny-6, font=ui.FONT_BOLD, fontSize=8, align="right"})
            tt:setFillColor(0.4,0.6,0.9); tt.anchorX=1
            if n.replay then
                nBg:addEventListener("tap", function()
                    ui.popupClose(popGrp, dim, { content }, function()
                        openNotification(n)
                    end)
                    return true
                end)
            end
        end

        local closeY  = pY + pH*0.5 - 24
        local closeBg = display.newRoundedRect(content, pX, closeY, 110, 28, 6)
        closeBg:setFillColor(0.04,0.12,0.32,0.97)
        closeBg.strokeWidth=1.5; closeBg:setStrokeColor(0.25,0.65,1.0,0.8)
        display.newText({ parent=content, text="CLOSE",
            x=pX, y=closeY, font=ui.FONT_BOLD, fontSize=12
        }):setFillColor(0.7,0.90,1.0)
        local function closeNotif()
            return ui.popupClose(popGrp, dim, { content })
        end
        closeBg:addEventListener("tap", closeNotif)
        blockBehindTouches(dim, closeNotif)

        ui.popupOpen(dim, { content })
    end

    bellCircle:addEventListener("tap", function() showNotifPopup(); return true end)
    bellIcon:addEventListener("tap",   function() showNotifPopup(); return true end)
    bellLabel:addEventListener("tap",  function() showNotifPopup(); return true end)
end

-------------------------------------------------
-- SCENE SHOW
-------------------------------------------------
function scene:show(event)
    if event.phase ~= "did" then return end

    local player = save.load()
    player.diamonds = player.diamonds or 0

    if not self._ambientGroup or not self._ambientGroup.removeSelf then
        buildAmbientDots(self, self.view, SW, SH)
    end
    if not self._sparkleGroup or not self._sparkleGroup.removeSelf then
        buildFallingSparkles(self, self.view, SW, SH)
    end

    if applyLevelUps(player) then save.save(player) end

    local final    = stats.calculate(player)
    local xpNeeded = xpUtil.getXpToLevel(player.level)
    local energy   = calcEnergy(player)
    player.currentScene = "Home"
    save.save(player)
    sync.pushPlayerSnapshot(player)

    setNotificationState(self, player.notifications or {})

    api.pvp.history(function(response)
        if response and response.ok and response.data and response.data.history then
            local latestPlayer = save.load()
            local mergedNotifications = mergeNotifications(
                (latestPlayer and latestPlayer.notifications) or player.notifications,
                response.data.history
            )
            setNotificationState(self, mergedNotifications)
            if latestPlayer then
                latestPlayer.notifications = mergedNotifications
                save.save(latestPlayer)
            end
        end
    end)

    statTexts.ATK.text  = tostring(final.attack)
    statTexts.DEF.text  = tostring(final.defense)
    statTexts.SPD.text  = tostring(final.speed)
    statTexts.HP.text   = tostring(final.hp)
    statTexts.WIN.text  = save.getArenaWinRate(player, player.winRate)
    if statTexts.GOLD     then statTexts.GOLD.text     = tostring(player.gold or 0) end
    if statTexts.DIAMONDS then statTexts.DIAMONDS.text = tostring(player.diamonds)  end
    if energyText         then energyText.text         = energy.."/"..ENERGY_MAX    end

    local ratio = math.min(player.xp / xpNeeded, 1)
    xpBarFill.width   = math.max(xpBarFill._maxW * ratio, 2)
    xpBarFill.x       = xpBarFill._baseX
    xpBarFill.anchorX = 0
    levelXpText.text  = "XP "..player.xp.." / "..xpNeeded
    if levelNumberText then levelNumberText.text = tostring(player.level) end
    if nameText then nameText.text = player.name or "Player" end
    refreshHomeCharacter(self, player)
    renderHomePets(self, player)
    animateHomePets(self)

    local mats = player.materials or { scrap=0, coil=0, chip=0 }
    for key, txt in pairs(matNumTexts) do
        txt.text = tostring(mats[key] or 0)
    end

    if self._xpShimmer then
        local shimmer = self._xpShimmer
        local function sweepXpBar()
            if not shimmer or not shimmer.removeSelf or not xpBarFill or not xpBarFill.removeSelf then return end
            shimmer.x = xpBarFill._baseX - 22
            shimmer.y = self._xpBarY
            shimmer.alpha = ratio > 0 and 0.22 or 0
            transition.to(shimmer, {
                x = xpBarFill._baseX + math.max(xpBarFill.width, 24) + 10,
                alpha = 0,
                time = 1200,
                transition = easing.inOutQuad,
                onComplete = function()
                    trackTimer(timer.performWithDelay(1400 + math.random(0, 1200), sweepXpBar))
                end
            })
        end
        trackTimer(timer.performWithDelay(350, sweepXpBar))
    end

    if self._chatText and self._chatMessages then
        local function cycleChat()
            if not self._chatText or not self._chatText.removeSelf then return end
            self._chatIndex = (self._chatIndex % #self._chatMessages) + 1
            transition.to(self._chatText, {
                x = 46, alpha = 0, time = 220,
                onComplete = function()
                    if not self._chatText or not self._chatText.removeSelf then return end
                    self._chatText.text = self._chatMessages[self._chatIndex]
                    self._chatText.x = 74
                    transition.to(self._chatText, {
                        x = 58, alpha = 1, time = 220,
                        onComplete = function()
                            trackTimer(timer.performWithDelay(3000, cycleChat))
                        end
                    })
                end
            })
        end
        self._chatText.alpha = 1
        self._chatText.text = self._chatMessages[self._chatIndex]
        self._chatText.x = 58
        trackTimer(timer.performWithDelay(3000, cycleChat))
    end

    if self._bellLabel and self._notifMessages then
        local function cycleNotif()
            if not self._bellLabel or not self._bellLabel.removeSelf then return end
            self._notifIndex = (self._notifIndex % #self._notifMessages) + 1
            transition.to(self._bellLabel, {
                x = 46, alpha = 0, time = 220,
                onComplete = function()
                    if not self._bellLabel or not self._bellLabel.removeSelf then return end
                    self._bellLabel.text = self._notifMessages[self._notifIndex]
                    self._bellLabel.x = 74
                    transition.to(self._bellLabel, {
                        x = 58, alpha = 1, time = 220,
                        onComplete = function()
                            trackTimer(timer.performWithDelay(3600, cycleNotif))
                        end
                    })
                end
            })
        end
        self._bellLabel.alpha = 1
        self._bellLabel.text = self._notifMessages[self._notifIndex]
        self._bellLabel.x = 58
        trackTimer(timer.performWithDelay(3600, cycleNotif))
    end

    if self._playerSprite then
        local sprite = self._playerSprite
        local shadow = self._playerShadow
        local baseY = self._playerBaseY or sprite.y
        local function pulsePlayer()
            if not sprite or not sprite.removeSelf then return end
            transition.to(sprite, {
                y = baseY - 2, time = 900, transition = easing.inOutSine,
                onComplete = function()
                    if shadow and shadow.removeSelf then
                        transition.to(shadow, { xScale = 0.94, alpha = 0.20, time = 900, transition = easing.inOutSine })
                    end
                    transition.to(sprite, {
                        y = baseY, time = 900, transition = easing.inOutSine,
                        onComplete = function()
                            if shadow and shadow.removeSelf then
                                transition.to(shadow, { xScale = 1.0, alpha = 0.28, time = 900, transition = easing.inOutSine })
                            end
                            pulsePlayer()
                        end
                    })
                end
            })
        end
        pulsePlayer()
    end

    animateHomePets(self)

    for _, dot in ipairs(self._ambientDots or {}) do
        local startY = dot.y
        local startX = dot.x
        local driftX = startX + math.random(-8, 8)
        local driftY = startY + math.random(-18, 18)
        local function driftDot()
            if not dot or not dot.removeSelf then return end
            transition.to(dot, {
                x = driftX, y = driftY, alpha = math.min(dot._baseAlpha + 0.08, 0.32),
                time = 3200 + math.random(0, 2200), transition = easing.inOutSine,
                onComplete = function()
                    startX, driftX = driftX, startX
                    startY, driftY = driftY, startY
                    transition.to(dot, {
                        x = driftX, y = driftY, alpha = dot._baseAlpha,
                        time = 3200 + math.random(0, 2200), transition = easing.inOutSine,
                        onComplete = driftDot
                    })
                end
            })
        end
        driftDot()
    end

    for i, sparkle in ipairs(self._sparkleTrails or {}) do
        local function dropSparkle()
            if not sparkle or not sparkle.removeSelf then return end
            sparkle.x = math.random(18, math.floor(SW - 18))
            sparkle.y = math.random(140, 260)
            sparkle.alpha = 0
            sparkle.rotation = math.random(-12, 12)
            transition.to(sparkle, {
                alpha = 1.0,
                time = 220 + math.random(0, 120),
                onComplete = function()
                    if not sparkle or not sparkle.removeSelf then return end
                    transition.to(sparkle, {
                        x = sparkle.x + math.random(-24, 24),
                        y = SH - 180 + math.random(-18, 18),
                        alpha = 0.05,
                        time = 2400 + math.random(0, 900),
                        transition = easing.inQuad,
                        onComplete = function()
                            trackTimer(timer.performWithDelay(500 + math.random(0, 1600), dropSparkle))
                        end
                    })
                end
            })
        end
        trackTimer(timer.performWithDelay(300 + i * 180, dropSparkle))
    end

    local iconEffects = {
        HP = function(icon)
            transition.to(icon, { xScale = 1.08, yScale = 1.08, alpha = 1.0, time = 240, onComplete = function()
                if icon and icon.removeSelf then
                    transition.to(icon, { xScale = 1.0, yScale = 1.0, alpha = 0.92, time = 320 })
                end
            end })
        end,
        SPD = function(icon)
            transition.to(icon, { x = icon.x + 2, alpha = 1.0, time = 150, onComplete = function()
                if icon and icon.removeSelf then
                    transition.to(icon, { x = icon.x - 2, time = 150, onComplete = function()
                        if icon and icon.removeSelf then transition.to(icon, { x = icon.x, alpha = 0.92, time = 120 }) end
                    end })
                end
            end })
        end,
        ATK = function(icon)
            transition.to(icon, { alpha = 0.6, time = 120, onComplete = function()
                if icon and icon.removeSelf then transition.to(icon, { alpha = 1.0, time = 180 }) end
            end })
        end,
    }
    for key, fx in pairs(iconEffects) do
        local icon = self._statIcons[key]
        if icon then
            local function loopFx()
                if not icon or not icon.removeSelf then return end
                fx(icon)
                trackTimer(timer.performWithDelay(2600 + math.random(0, 2200), loopFx))
            end
            trackTimer(timer.performWithDelay(1000 + math.random(0, 1400), loopFx))
        end
    end

    if self._bellCircle and self._bellLabel then
        local function pulseBell()
            if not self._bellCircle or not self._bellCircle.removeSelf then return end
            transition.to(self._bellCircle, {
                xScale = 1.01, yScale = 1.01, alpha = 1.0, time = 300, transition = easing.outQuad,
                onComplete = function()
                    if self._bellLabel and self._bellLabel.removeSelf then
                        self._bellLabel.alpha = 1.0
                    end
                    transition.to(self._bellCircle, {
                        xScale = 1.0, yScale = 1.0, alpha = 0.92, time = 420, transition = easing.inQuad,
                        onComplete = function()
                            if self._bellLabel and self._bellLabel.removeSelf then
                                self._bellLabel.alpha = 0.90
                            end
                            trackTimer(timer.performWithDelay(2200 + math.random(0, 1600), pulseBell))
                        end
                    })
                end
            })
        end
        trackTimer(timer.performWithDelay(900, pulseBell))
    end

    if self._guildBtnGroup then
        self._guildBtnGroup:removeSelf(); self._guildBtnGroup=nil
    end
    local L = self._guildBtnLayout
    if L then
        local grp = display.newGroup()
        self.view:insert(grp)
        self._guildBtnGroup = grp
        local g = guildContext.getJoinedGuild(player) or guildFromList(player, false)
        local c = guildContext.getHostedGuild(player) or guildFromList(player, true)
        if g then
            makeNavBtn(grp,L.leftX,L.row1Y,L.btnW,L.btnH, string.upper(g.name), function()
                composer.gotoScene("scenes.guild_home",{effect="slideLeft",time=260,params={guildId=g.guildId, guildKey="joinedGuild"}})
            end, "crew")
        else
            makeNavBtn(grp,L.leftX,L.row1Y,L.btnW,L.btnH,"JOIN GUILD",function()
                composer.gotoScene("scenes.guild_join",{effect="slideLeft",time=260})
            end, "crew")
        end
        if c then
            makeNavBtn(grp,L.rightX,L.row1Y,L.btnW,L.btnH, string.upper(c.name), function()
                composer.gotoScene("scenes.guild_home",{effect="slideLeft",time=260,params={guildId=c.guildId, guildKey="hostedGuild"}})
            end, "crew")
        else
            makeNavBtn(grp,L.rightX,L.row1Y,L.btnW,L.btnH,"CREATE GUILD",function()
                composer.gotoScene("scenes.guild_create",{effect="slideLeft",time=260})
            end, "crew")
        end
    end

    if self._taskIconGroup then
        self._taskIconGroup:removeSelf(); self._taskIconGroup=nil
    end

    tasksUtil.init(player)
    local visible      = tasksUtil.getVisible(player)
    local activeTasks  = {}
    for _, item in ipairs(visible) do
        if item.unlocked and item.state and not item.state.claimed then
            table.insert(activeTasks, item)
        end
    end
    table.sort(activeTasks, function(a, b)
        local aReady = a.state and a.def and a.state.progress >= a.def.goal
        local bReady = b.state and b.def and b.state.progress >= b.def.goal
        if aReady ~= bReady then return aReady end
        return tostring(a.def and a.def.id or "") < tostring(b.def and b.def.id or "")
    end)

    local taskY   = self._taskIconsY or (SH - 190)
    local iconSz  = 34
    local grp     = display.newGroup()
    self.view:insert(grp)
    self._taskIconGroup = grp

    local taskOffsets = { -56, 56, -100, 100 }

    if false and #activeTasks == 0 then
        local doneBg = display.newRoundedRect(grp, CX, taskY, iconSz, iconSz, 10)
        doneBg:setFillColor(0.04, 0.22, 0.08, 0.95)
        doneBg.strokeWidth = 1.5; doneBg:setStrokeColor(0.22, 0.88, 0.32, 0.80)
        display.newText({ parent=grp, text="✓",
            x=CX, y=taskY, font=ui.FONT_BOLD, fontSize=20
        }):setFillColor(0.35, 1.0, 0.45)
    else
        for i = 1, math.min(4, #activeTasks) do
            local item = activeTasks[i]
            local ix = CX + taskOffsets[i]
            local claimable = item.state.progress >= item.def.goal

            local pulse = display.newRoundedRect(grp, ix, taskY, iconSz + 4, iconSz + 4, 12)
            pulse:setFillColor(0, 0, 0, 0)
            pulse.strokeWidth = 2
            pulse:setStrokeColor(claimable and 0.30 or 0.20, claimable and 1.0 or 0.62, claimable and 0.38 or 1.0, 0.90)
            transition.to(pulse, {
                alpha = 0.05,
                xScale = 1.18,
                yScale = 1.18,
                time = 900 + i * 60,
                iterations = 0,
                transition = easing.outQuad
            })

            local iconBg = display.newRoundedRect(grp, ix, taskY, iconSz, iconSz, 10)
            if claimable then
                iconBg:setFillColor(0.04, 0.26, 0.08, 0.97)
                iconBg.strokeWidth = 2; iconBg:setStrokeColor(0.25, 1.0, 0.30, 0.90)
            else
                iconBg:setFillColor(0.04, 0.10, 0.30, 0.95)
                iconBg.strokeWidth = 1.5; iconBg:setStrokeColor(0.25, 0.60, 1.0, 0.75)
            end

            local iconName = item.def.icon or "fight"
            local okIcon, iconImg = pcall(display.newImageRect,
                grp,
                "assets/sprites/ui/icons/" .. iconName .. ".png",
                18, 18
            )
            if okIcon and iconImg then
                iconImg.x = ix
                iconImg.y = taskY
                iconImg.alpha = claimable and 1.0 or 0.92
                iconImg.isHitTestable = false
            else
                local iconT = display.newText({ parent=grp, text="!",
                    x=ix, y=taskY-1, font=ui.FONT_BOLD, fontSize=16 })
                iconT:setFillColor(1.0, 0.85, 0.20)
                iconT.isHitTestable = false
            end

            if not claimable then
                flicker(iconBg, 0.72, 1.0, 1200+math.random(0,400))
            end

            local capView = self.view
            iconBg:addEventListener("tap", function()
                buildTaskQuickPopup(capView, item)
                return true
            end)
        end
    end

    radialMenu.show(self.view, {
        activeScene = "home",
        inner       = RADIAL_INNER,
        outer       = RADIAL_OUTER,
    })
    keepModalOnTop(self.view, self.view._activeHomePopup)
end

-------------------------------------------------
-- SCENE HIDE
-------------------------------------------------
function scene:hide(event)
    if event.phase ~= "will" then return end
    closeSettingsPopup()
    radialMenu.destroy()
    if self._guildBtnGroup  then self._guildBtnGroup:removeSelf();  self._guildBtnGroup=nil  end
    if self._taskRowRef     then self._taskRowRef:removeSelf();     self._taskRowRef=nil      end
    if self._taskIconGroup  then self._taskIconGroup:removeSelf();  self._taskIconGroup=nil  end
    self.view._activeHomePopup = nil
    if self._xpShimmer      then transition.cancel(self._xpShimmer) end
    if self._playerSprite   then transition.cancel(self._playerSprite) end
    if self._playerShadow   then transition.cancel(self._playerShadow) end
    if self._bellCircle     then transition.cancel(self._bellCircle) end
    if self._chatText       then transition.cancel(self._chatText) end
    for _, petSprite in ipairs(self._petSprites or {}) do transition.cancel(petSprite) end
    for _, dot in ipairs(self._ambientDots or {}) do transition.cancel(dot) end
    for _, sparkle in ipairs(self._sparkleTrails or {}) do transition.cancel(sparkle) end
    for _, icon in pairs(self._statIcons or {}) do transition.cancel(icon) end
    for _, t in ipairs(TIMERS) do pcall(function() timer.cancel(t) end) end
    TIMERS = {}
end

scene:addEventListener("create", scene)
scene:addEventListener("show",   scene)
scene:addEventListener("hide",   scene)

return scene
