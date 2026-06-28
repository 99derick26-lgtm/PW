local composer = require("composer")
local scene     = composer.newScene()

local save = require("utils.save")
local api  = require("utils.api")
local sync = require("utils.sync")
local session = require("utils.session")
local ui   = require("utils.ui")

-------------------------------------------------
-- CONSTANTS
-------------------------------------------------
local CX = display.contentCenterX
local CY = display.contentCenterY
local SW = display.actualContentWidth
local SH = display.actualContentHeight

local CARD_W   = SW * 0.72
local CARD_H   = SH * 0.38
local CARD_GAP = SW * 0.82   -- spacing between card centers
local MAX_SLOTS = 5

local TIMERS   = {}
local RAIN_COUNT = 40
local RAIN_COLOR = { 0.1, 0.6, 1.0, 0.25 }

-------------------------------------------------
-- STATE
-------------------------------------------------
local profiles      = {}   -- save.listProfiles() result
local cards         = {}   -- display groups per slot index 1..5
local currentIndex  = 1    -- which card is centered
local cardContainer        -- group that holds all cards (we slide this)
local rainDrops     = {}

local selectedSlot  = nil  -- set when a card is tapped / centered
local startBtn      = nil
local startBtnTxt   = nil
local nameTxt       = nil  -- shows profile name under cards
local sceneActive   = false
local startLocked   = false
local activeNameField = nil
local activeNameOverlay = nil
local sceneGroupRef = nil
local dotsRef = {}
local refreshDotsRef = nil
local buildCard
local snapToIndex

local function hasOnlineSession()
    local auth = session.getAuthHeader()
    return auth ~= nil and auth ~= ""
end

local function normalizeServerProfiles(list)
    local mapped = {}
    for _, prof in ipairs(list or {}) do
        local slot = tonumber(prof.profileSlot or prof.slot)
        if not slot and prof.playerId then
            slot = tonumber(string.match(tostring(prof.playerId), "_slot_(%d+)$"))
        end
        if slot and slot >= 1 and slot <= MAX_SLOTS then
            mapped[slot] = {
                slot = slot,
                name = prof.displayName or prof.name or tostring(slot),
                playerId = prof.playerId,
                level = prof.level or 1,
                status = prof.status or "online",
                appearance = prof.appearance,
                skinId = prof.skinId,
                serverProfile = true,
            }
        end
    end
    return mapped
end

local function rebuildProfileCards()
    if not sceneGroupRef or not cardContainer or not cardContainer.removeSelf then return end
    for i, grp in pairs(cards) do
        if grp and grp.removeSelf then grp:removeSelf() end
        cards[i] = nil
    end

    for i = 1, MAX_SLOTS do
        local cardX = (i - 1) * CARD_GAP
        local grp = buildCard(cardContainer, i, profiles[i], cardX)
        grp.x = cardX
        grp.y = 0
        cards[i] = grp
    end

    snapToIndex(currentIndex or 1, false)
    if refreshDotsRef then refreshDotsRef(currentIndex or 1) end
end

local function loadProfilesFromServer()
    if not hasOnlineSession() then return end
    api.player.profiles(function(response)
        if response and response.ok and response.data and response.data.profiles then
            profiles = normalizeServerProfiles(response.data.profiles)
            rebuildProfileCards()
        end
    end)
end

local function closeActiveNameEntry()
    native.setKeyboardFocus(nil)
    if activeNameField and activeNameField.removeSelf then
        activeNameField:removeSelf()
    end
    activeNameField = nil

    if activeNameOverlay and activeNameOverlay.removeSelf then
        activeNameOverlay:removeSelf()
    end
    activeNameOverlay = nil
end

-------------------------------------------------
-- RAIN
-------------------------------------------------
local function spawnDrop(group, i)
    local x   = math.random(0, SW)
    local len = math.random(10, 30)
    local spd = math.random(240, 480)
    local d   = display.newLine(group, x, -len, x, 0)
    d:setStrokeColor(unpack(RAIN_COLOR))
    d.strokeWidth = 1
    d.y = math.random(-SH, 0)
    rainDrops[i] = { obj=d, speed=spd, len=len }
end

local function startRain(group)
    for i = 1, RAIN_COUNT do spawnDrop(group, i) end
    local t = timer.performWithDelay(16, function()
        for i = 1, RAIN_COUNT do
            local r = rainDrops[i]
            if r and r.obj and r.obj.removeSelf then
                r.obj.y = r.obj.y + r.speed * 0.016
                if r.obj.y > SH + r.len then
                    r.obj:removeSelf()
                    spawnDrop(group, i)
                end
            end
        end
    end, 0)
    table.insert(TIMERS, t)
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
    table.insert(TIMERS, t)
end

-- position cardContainer so slot `idx` is centred
snapToIndex = function(idx, animate)
    if not sceneActive or not cardContainer or not cardContainer.removeSelf then
        return
    end
    currentIndex = idx
    local targetX = CX - (idx - 1) * CARD_GAP
    if animate then
        transition.cancel(cardContainer)
        transition.to(cardContainer, { x=targetX, time=220, transition=easing.outQuad })
    else
        cardContainer.x = targetX
    end

    -- update name label & highlight
    local prof = profiles[idx]
    if nameTxt then
        if prof then
            nameTxt.text = prof.name
            nameTxt:setFillColor(0.4, 0.9, 1)
        else
            nameTxt.text = "EMPTY SLOT"
            nameTxt:setFillColor(0.3, 0.4, 0.5)
        end
    end

    -- dim all cards, brighten active
    for i, grp in pairs(cards) do
        if grp then grp.alpha = (i == idx) and 1.0 or 0.45 end
    end

    selectedSlot = prof and prof.slot or nil
    -- show/hide start button
    if startBtn then
        startBtn.isVisible    = (selectedSlot ~= nil)
        startBtnTxt.isVisible = (selectedSlot ~= nil)
    end
end

-------------------------------------------------
-- BUILD ONE CARD
-------------------------------------------------
buildCard = function(sceneGroup, slotIndex, prof, cardX)
    local grp = display.newGroup()
    sceneGroup:insert(grp)

    -- card background
    local bg = display.newRoundedRect(grp, 0, 0, CARD_W, CARD_H, 14)
    bg:setFillColor(0.04, 0.10, 0.22)
    bg.strokeWidth = 1.5
    bg:setStrokeColor(0.2, 0.5, 1.0, 0.7)

    if prof then
        -- filled slot
        -- avatar placeholder box
        local avatarBox = display.newRoundedRect(grp, 0, -CARD_H * 0.18, CARD_W * 0.38, CARD_W * 0.38, 8)
        avatarBox:setFillColor(0.08, 0.18, 0.38)
        avatarBox.strokeWidth = 1
        avatarBox:setStrokeColor(0.2, 0.6, 1, 0.5)

        -- avatar label (replace with sprite if you have one)
        local avatarLbl = display.newText({
            parent=grp, text="[?]",
            x=0, y=-CARD_H * 0.18,
            font=ui.FONT_BOLD, fontSize=18, align="center"
        })
        avatarLbl:setFillColor(0.3, 0.6, 1)

        -- name
        display.newText({
            parent=grp, text=prof.name,
            x=0, y=CARD_H * 0.14,
            font=ui.FONT_BOLD, fontSize=16, align="center"
        }):setFillColor(0.9, 0.95, 1)

        -- slot badge
        local badge = display.newText({
            parent=grp, text="SLOT " .. slotIndex,
            x=0, y=CARD_H * 0.30,
            font=ui.FONT, fontSize=9, align="center"
        })
        badge:setFillColor(0.2, 0.5, 0.8)

        -- DELETE button (small, bottom-right of card)
        local delBtn = display.newRoundedRect(grp, CARD_W * 0.28, CARD_H * 0.38, 48, 22, 5)
        delBtn:setFillColor(0.4, 0.05, 0.05)
        delBtn.strokeWidth = 1
        delBtn:setStrokeColor(1, 0.2, 0.2, 0.6)

        local delTxt = display.newText({
            parent=grp, text="DEL",
            x=CARD_W * 0.28, y=CARD_H * 0.38,
            font=ui.FONT_BOLD, fontSize=9, align="center"
        })
        delTxt:setFillColor(1, 0.3, 0.3)
        delTxt.isHitTestable = false

        delBtn:addEventListener("tap", function()
            api.player.deleteProfile(prof.slot, function() end)
            save.deleteProfile(prof.slot)
            -- reload scene
            composer.removeScene("scenes.profile_select")
            composer.gotoScene("scenes.profile_select", { effect="fade", time=200 })
            return true
        end)

    else
        -- empty slot — show + button
        local plusCircle = display.newCircle(grp, 0, -10, 28)
        plusCircle:setFillColor(0.06, 0.18, 0.4)
        plusCircle.strokeWidth = 1.5
        plusCircle:setStrokeColor(0.2, 0.7, 1, 0.7)

        local plusTxt = display.newText({
            parent=grp, text="+",
            x=0, y=-14,
            font=ui.FONT_BOLD, fontSize=32, align="center"
        })
        plusTxt:setFillColor(0.3, 0.8, 1)
        plusTxt.isHitTestable = false

        local newTxt = display.newText({
            parent=grp, text="NEW PROFILE",
            x=0, y=CARD_H * 0.28,
            font=ui.FONT_BOLD, fontSize=11, align="center"
        })
        newTxt:setFillColor(0.3, 0.6, 0.9)
        newTxt.isHitTestable = false

        local function triggerCreate()
            if currentIndex ~= slotIndex then
                snapToIndex(slotIndex, true)
                return true
            end
            closeActiveNameEntry()
            if hasOnlineSession() then
                api.player.createProfile(slotIndex, function(response)
                    if response and response.ok and response.data then
                        session.setTokens(response.data.accessToken, response.data.refreshToken)
                        session.setIdentity({
                            accountId = response.data.accountId,
                            playerId = response.data.playerId,
                            accountKey = response.data.accountKey,
                            userId = response.data.userId,
                        })
                        if response.data.player then
                            sync.applyPlayerSnapshot(response.data.player, slotIndex)
                        end
                        loadProfilesFromServer()
                    elseif nameTxt then
                        nameTxt.text = "CREATE FAILED"
                        nameTxt:setFillColor(1.0, 0.35, 0.35)
                    end
                end)
            else
                save.createProfile(tostring(slotIndex))
                composer.removeScene("scenes.profile_select")
                composer.gotoScene("scenes.profile_select", { effect="fade", time=200 })
            end
            return true
        end

        local function addCreateTouch(target)
            target:addEventListener("touch", function(event)
                if event.phase == "began" then
                    display.getCurrentStage():setFocus(target)
                    target._hasFocus = true
                    return true
                elseif target._hasFocus and event.phase == "ended" then
                    display.getCurrentStage():setFocus(nil)
                    target._hasFocus = false
                    return triggerCreate()
                elseif target._hasFocus and event.phase == "cancelled" then
                    display.getCurrentStage():setFocus(nil)
                    target._hasFocus = false
                    return true
                end
                return false
            end)
        end

        addCreateTouch(bg)
        addCreateTouch(plusCircle)
        bg:addEventListener("tap", function()
            return triggerCreate()
        end)
    end

    return grp
end

-------------------------------------------------
-- SCENE CREATE
-------------------------------------------------
function scene:create(event)
    local sceneGroup = self.view
    sceneGroupRef = sceneGroup
    sceneActive = true
    selectedSlot = nil
    currentIndex = 1
    cards = {}
    rainDrops = {}
    profiles = save.listProfiles()

    -- bg
    local bg = display.newRect(sceneGroup, CX, CY, SW, SH)
    bg:setFillColor(0.02, 0.03, 0.08)

    -- scanlines
    for i = 1, 16 do
        local l = display.newRect(sceneGroup, CX, i * (SH / 16), SW, 1)
        l:setFillColor(0.05, 0.15, 0.4, 0.06)
        l.isHitTestable = false
    end

    -- city glow
    local glow = display.newRect(sceneGroup, CX, SH - 40, SW, 120)
    glow:setFillColor(0.05, 0.2, 0.6, 0.14)
    glow.isHitTestable = false

    -- rain
    local rainGroup = display.newGroup()
    sceneGroup:insert(rainGroup)
    startRain(rainGroup)

    -- title
    local titleY = SH * 0.10
    local tA = display.newText({
        parent=sceneGroup, text="SELECT PROFILE",
        x=CX, y=titleY,
        font=ui.FONT_BOLD, fontSize=22, align="center"
    })
    tA:setFillColor(0.25, 0.75, 1.0)
    flicker(tA, 0.85, 1.0, 140)

    display.newRect(sceneGroup, CX, titleY + 16, 240, 1):setFillColor(0.2, 0.6, 1, 0.4)

    -- dot indicators
    local dotsY  = SH * 0.80
    local dotGap = 14
    local dots   = {}
    for i = 1, MAX_SLOTS do
        local d = display.newCircle(sceneGroup, CX + (i - 3) * dotGap, dotsY, 3)
        d:setFillColor(0.2, 0.4, 0.7)
        dots[i] = d
    end
    -- highlight active dot
    local function refreshDots(idx)
        for i, d in ipairs(dots) do
            d:setFillColor(i == idx and 0.3 or 0.2,
                           i == idx and 0.8 or 0.4,
                           i == idx and 1.0 or 0.7)
            d.xScale = i == idx and 1.4 or 1.0
            d.yScale = i == idx and 1.4 or 1.0
        end
    end
    dotsRef = dots
    refreshDotsRef = refreshDots

    -- name label
    local nameY = SH * 0.74
    nameTxt = display.newText({
        parent=sceneGroup, text="",
        x=CX, y=nameY,
        font=ui.FONT_BOLD, fontSize=14, align="center"
    })

    -- card container (we translate this to swipe)
    cardContainer = display.newGroup()
    sceneGroup:insert(cardContainer)
    cardContainer.y = CY - 10

    for i = 1, MAX_SLOTS do
        local cardX = (i - 1) * CARD_GAP
        local grp   = buildCard(cardContainer, i, profiles[i], cardX)
        grp.x       = cardX
        grp.y       = 0
        cards[i]    = grp
    end

    -- START button (hidden until profile selected)
    local btnY = SH * 0.88
    local btnGlow = display.newRoundedRect(sceneGroup, CX, btnY, 210, 48, 10)
    btnGlow:setFillColor(0.05, 0.4, 1.0, 0.15)
    btnGlow.isHitTestable = false
    flicker(btnGlow, 0.5, 1.0, 160)

    startBtn = display.newRoundedRect(sceneGroup, CX, btnY, 206, 44, 10)
    startBtn:setFillColor(0.04, 0.18, 0.55)
    startBtn.strokeWidth = 1.5
    startBtn:setStrokeColor(0.2, 0.7, 1, 0.9)
    startBtn.isVisible = false

    startBtnTxt = display.newText({
        parent=sceneGroup, text="PLAY",
        x=CX, y=btnY,
        font=ui.FONT_BOLD, fontSize=20, align="center"
    })
    startBtnTxt:setFillColor(0.4, 0.9, 1)
    startBtnTxt.isHitTestable = false
    startBtnTxt.isVisible = false

    startBtn:addEventListener("tap", function()
        if startLocked or not selectedSlot then return true end
        startLocked = true
        startBtn:setFillColor(0.1, 0.4, 1.0)
        save.activeSlot = selectedSlot

        local function goHome()
            if not sceneActive then return end
            composer.gotoScene("scenes.home", { effect="fade", time=400 })
        end

        local player = save.load(selectedSlot)
        player.lastLoginAt = os.time()
        save.save(player, selectedSlot)
        if hasOnlineSession() then
            api.player.selectProfile(selectedSlot, function(response)
                if response and response.ok and response.data then
                    session.setTokens(response.data.accessToken, response.data.refreshToken)
                    session.setIdentity({
                        accountId = response.data.accountId,
                        playerId = response.data.playerId,
                        accountKey = response.data.accountKey,
                        userId = response.data.userId,
                    })
                    local onlinePlayer = sync.applyPlayerSnapshot(response.data.player, selectedSlot)
                    api.player.update(onlinePlayer, function()
                        goHome()
                    end)
                else
                    goHome()
                end
            end)
        else
            goHome()
        end
        return true
    end)

    -- SWIPE
    local swipeStartX = nil
    local SWIPE_THRESHOLD = 40

    local function onSceneTouch(event)
        if not sceneActive or not cardContainer or not cardContainer.removeSelf then
            return true
        end

        if event.phase == "began" then
            swipeStartX = event.x

        elseif event.phase == "moved" and swipeStartX then
            -- live drag
            local dx = event.x - swipeStartX
            cardContainer.x = (CX - (currentIndex - 1) * CARD_GAP) + dx

        elseif event.phase == "ended" or event.phase == "cancelled" then
            if swipeStartX then
                local dx = event.x - swipeStartX
                local newIdx = currentIndex
                if dx < -SWIPE_THRESHOLD and currentIndex < MAX_SLOTS then
                    newIdx = currentIndex + 1
                elseif dx > SWIPE_THRESHOLD and currentIndex > 1 then
                    newIdx = currentIndex - 1
                end
                snapToIndex(newIdx, true)
                refreshDots(newIdx)
                swipeStartX = nil
            end
        end
        return true
    end
    self._touchListener = onSceneTouch
    sceneGroup:addEventListener("touch", onSceneTouch)

    -- initial position
    snapToIndex(1, false)
    refreshDots(1)
end

-------------------------------------------------
-- SCENE SHOW
-------------------------------------------------
function scene:show(event)
    if event.phase ~= "will" then return end
    sceneActive = true
    startLocked = false
    if startBtn and startBtn.removeSelf then
        startBtn:setFillColor(0.04, 0.18, 0.55)
    end
    loadProfilesFromServer()
end

-------------------------------------------------
-- SCENE HIDE
-------------------------------------------------
function scene:hide(event)
    if event.phase ~= "will" then return end
    sceneActive = false
    closeActiveNameEntry()
    if cardContainer and cardContainer.removeSelf then
        transition.cancel(cardContainer)
    end
    for _, t in ipairs(TIMERS) do pcall(function() timer.cancel(t) end) end
    TIMERS = {}
    for i, r in ipairs(rainDrops) do
        if r.obj and r.obj.removeSelf then r.obj:removeSelf() end
        rainDrops[i] = nil
    end
end

function scene:destroy(event)
    closeActiveNameEntry()
end

scene:addEventListener("create", scene)
scene:addEventListener("show",   scene)
scene:addEventListener("hide",   scene)
scene:addEventListener("destroy", scene)

return scene
