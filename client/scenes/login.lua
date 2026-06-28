local composer = require("composer")
local scene = composer.newScene()

local json = require("json")
local api = require("utils.api")
local save = require("utils.save")
local session = require("utils.session")
local ui = require("utils.ui")

local CX = display.contentCenterX
local CY = display.contentCenterY
local SW = display.actualContentWidth
local SH = display.actualContentHeight

local RAIN_COUNT = 60
local RAIN_COLOR = { 0.1, 0.6, 1.0, 0.35 }
local TIMERS = {}
local rainDrops = {}
local userField
local passField

local function safeKey(value)
    local key = tostring(value or ""):lower():gsub("[^%w_%-]", "_")
    return key ~= "" and key or nil
end

local function accountsPath()
    return system.pathForFile("local_accounts.json", system.DocumentsDirectory)
end

local function loadAccounts()
    local f = io.open(accountsPath(), "r")
    if not f then return { accounts = {} } end
    local raw = f:read("*a")
    io.close(f)
    return json.decode(raw) or { accounts = {} }
end

local function saveAccounts(data)
    local f = io.open(accountsPath(), "w")
    if not f then return false end
    f:write(json.encode(data))
    io.close(f)
    return true
end

local function spawnDrop(group, i)
    local x = math.random(0, SW)
    local len = math.random(14, 40)
    local spd = math.random(280, 520)
    local d = display.newLine(group, x, -len, x, 0)
    d:setStrokeColor(unpack(RAIN_COLOR))
    d.strokeWidth = math.random() > 0.7 and 2 or 1
    d.y = math.random(-SH, 0)
    rainDrops[i] = { obj = d, speed = spd, len = len }
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

local function flicker(obj, lo, hi, ms)
    local t = timer.performWithDelay(ms, function()
        if obj and obj.removeSelf then
            obj.alpha = lo + math.random() * (hi - lo)
        end
    end, 0)
    table.insert(TIMERS, t)
end

function scene:create(event)
    local sceneGroup = self.view

    local bg = display.newRect(sceneGroup, CX, CY, SW, SH)
    bg:setFillColor(0.02, 0.03, 0.08)

    for i = 1, 18 do
        local l = display.newRect(sceneGroup, CX, i * (SH / 18), SW, 1)
        l:setFillColor(0.05, 0.15, 0.4, 0.07)
        l.isHitTestable = false
    end

    local glow = display.newRect(sceneGroup, CX, SH - 40, SW, 120)
    glow:setFillColor(0.05, 0.2, 0.6, 0.18)
    glow.isHitTestable = false

    local rainGroup = display.newGroup()
    sceneGroup:insert(rainGroup)
    startRain(rainGroup)

    local titleY = CY - 132
    local titleGlow = display.newRect(sceneGroup, CX, titleY, 320, 70)
    titleGlow:setFillColor(0.05, 0.3, 0.9, 0.10)
    titleGlow.isHitTestable = false
    flicker(titleGlow, 0.7, 1.0, 80)

    display.newRect(sceneGroup, CX, titleY - 32, 260, 1):setFillColor(0.2, 0.6, 1, 0.5)

    local titleA = display.newText({
        parent = sceneGroup, text = "PIXEL WAR",
        x = CX, y = titleY - 8,
        font = ui.FONT_BOLD, fontSize = 38, align = "center"
    })
    titleA:setFillColor(0.25, 0.75, 1.0)
    flicker(titleA, 0.85, 1.0, 120)

    local titleB = display.newText({
        parent = sceneGroup, text = "ONLINE",
        x = CX, y = titleY + 28,
        font = ui.FONT_BOLD, fontSize = 22, align = "center"
    })
    titleB:setFillColor(0.0, 1.0, 0.7)
    flicker(titleB, 0.75, 1.0, 200)

    display.newRect(sceneGroup, CX, titleY + 44, 260, 1):setFillColor(0.0, 1.0, 0.7, 0.4)

    local formY = CY + 4

    local userBg = display.newRoundedRect(sceneGroup, CX, formY - 34, 238, 34, 8)
    userBg:setFillColor(0.03, 0.08, 0.20, 0.95)
    userBg.strokeWidth = 1.5
    userBg:setStrokeColor(0.18, 0.55, 1.0, 0.65)

    local passBg = display.newRoundedRect(sceneGroup, CX, formY + 12, 238, 34, 8)
    passBg:setFillColor(0.03, 0.08, 0.20, 0.95)
    passBg.strokeWidth = 1.5
    passBg:setStrokeColor(0.18, 0.55, 1.0, 0.65)

    display.newText({
        parent = sceneGroup, text = "USER ID",
        x = CX - 108, y = formY - 58,
        font = ui.FONT_BOLD, fontSize = 9, align = "left"
    }):setFillColor(0.35, 0.78, 1.0)

    display.newText({
        parent = sceneGroup, text = "PASSWORD",
        x = CX - 100, y = formY - 12,
        font = ui.FONT_BOLD, fontSize = 9, align = "left"
    }):setFillColor(0.35, 0.78, 1.0)

    userField = native.newTextField(CX, formY - 34, 224, 26)
    userField.placeholder = "user id"
    userField.font = native.newFont(ui.FONT, 12)
    userField.hasBackground = false
    userField:setTextColor(0.85, 0.95, 1)

    passField = native.newTextField(CX, formY + 12, 224, 26)
    passField.placeholder = "password"
    passField.isSecure = true
    passField.font = native.newFont(ui.FONT, 12)
    passField.hasBackground = false
    passField:setTextColor(0.85, 0.95, 1)

    local btnY = formY + 70
    local btnGlow = display.newRoundedRect(sceneGroup, CX, btnY, 210, 50, 10)
    btnGlow:setFillColor(0.05, 0.4, 1.0, 0.18)
    btnGlow.isHitTestable = false
    flicker(btnGlow, 0.5, 1.0, 160)

    local btnBg = display.newRoundedRect(sceneGroup, CX, btnY, 206, 46, 10)
    btnBg:setFillColor(0.04, 0.18, 0.55)
    btnBg.strokeWidth = 1.5
    btnBg:setStrokeColor(0.2, 0.7, 1, 0.9)

    local btnTxt = display.newText({
        parent = sceneGroup, text = "LOGIN / CREATE",
        x = CX, y = btnY,
        font = ui.FONT_BOLD, fontSize = 16, align = "center"
    })
    btnTxt:setFillColor(0.4, 0.9, 1)
    btnTxt.isHitTestable = false

    local errorText = display.newText({
        parent = sceneGroup, text = "",
        x = CX, y = btnY + 42,
        width = SW - 44,
        font = ui.FONT_BOLD, fontSize = 9,
        align = "center"
    })
    errorText:setFillColor(1.0, 0.35, 0.35)

    local debugText = display.newText({
        parent = sceneGroup,
        text = "URL: " .. tostring(session.get().baseUrl or "nil"),
        x = CX,
        y = btnY + 60,
        width = SW - 44,
        font = ui.FONT,
        fontSize = 8,
        align = "center"
    })
    debugText:setFillColor(0.55, 0.70, 0.92)

    local locked = false
    btnBg:addEventListener("tap", function()
        if locked then return true end

        local userId = userField and userField.text or ""
        local password = passField and passField.text or ""
        local accountKey = safeKey(userId)

        if not accountKey or password == "" then
            errorText:setFillColor(1.0, 0.35, 0.35)
            errorText.text = "ENTER USER ID AND PASSWORD"
            return true
        end

        locked = true
        btnBg:setFillColor(0.1, 0.4, 1.0)
        btnTxt:setFillColor(1, 1, 1)
        errorText:setFillColor(0.95, 0.82, 0.25)
        errorText.text = "CONNECTING..."
        debugText.text = "URL: " .. tostring(session.get().baseUrl or "nil")

        -- A stale auth token would make the server keep using the old account,
        -- even when the player typed a different username/password here.
        session.clear()

        api.auth.login({
            userId = userId,
            password = password,
            accountKey = accountKey,
        }, function(response)
            if response.ok and response.data then
                local data = loadAccounts()
                data.accounts = data.accounts or {}
                data.accounts[accountKey] = {
                    userId = userId,
                    createdAt = (data.accounts[accountKey] and data.accounts[accountKey].createdAt) or os.time(),
                    lastLoginAt = os.time(),
                }
                saveAccounts(data)

                save.setAccountKey(accountKey)
                session.setTokens(response.data.accessToken, response.data.refreshToken)
                session.setIdentity({
                    accountId = response.data.accountId,
                    accountKey = response.data.accountKey or accountKey,
                    userId = response.data.userId or userId,
                })

                errorText:setFillColor(0.0, 1.0, 0.55)
                errorText.text = "LOGIN OK"
                timer.performWithDelay(180, function()
                    composer.gotoScene("scenes.profile_select", { effect = "fade", time = 400 })
                end)
            else
                locked = false
                btnBg:setFillColor(0.04, 0.18, 0.55)
                btnTxt:setFillColor(0.4, 0.9, 1)
                errorText:setFillColor(1.0, 0.35, 0.35)
                if response.status == 401 then
                    errorText.text = "WRONG PASSWORD"
                elseif response.status == 404 then
                    errorText.text = "ACCOUNT NOT FOUND"
                elseif response.status == 409 then
                    errorText.text = "ACCOUNT EXISTS"
                else
                    errorText.text = "SERVER OFFLINE"
                end
                debugText.text = "URL: " .. tostring(session.get().baseUrl or "nil")
                    .. "  STATUS: " .. tostring(response.status or 0)
                    .. "  ERROR: " .. tostring(response.error or response.raw or "nil")
            end
        end)
        return true
    end)

    display.newText({
        parent = sceneGroup,
        text = "SERVER ACCOUNT  -  5 PROFILES PER LOGIN",
        x = CX, y = SH - 24,
        font = ui.FONT, fontSize = 8, align = "center"
    }):setFillColor(0.2, 0.3, 0.5, 0.6)
end

function scene:show(event)
    if event.phase ~= "did" then return end
    if userField then userField.isVisible = true end
    if passField then passField.isVisible = true end
end

function scene:hide(event)
    if event.phase ~= "will" then return end
    if userField then userField.isVisible = false end
    if passField then passField.isVisible = false end
    for _, t in ipairs(TIMERS) do
        pcall(function() timer.cancel(t) end)
    end
    TIMERS = {}
    for i, r in ipairs(rainDrops) do
        if r.obj and r.obj.removeSelf then r.obj:removeSelf() end
        rainDrops[i] = nil
    end
end

function scene:destroy(event)
    if userField and userField.removeSelf then
        userField:removeSelf()
        userField = nil
    end
    if passField and passField.removeSelf then
        passField:removeSelf()
        passField = nil
    end
end

scene:addEventListener("create", scene)
scene:addEventListener("show", scene)
scene:addEventListener("hide", scene)
scene:addEventListener("destroy", scene)

return scene
