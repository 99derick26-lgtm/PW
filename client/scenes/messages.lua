local composer = require("composer")
local scene = composer.newScene()

local api = require("utils.api")
local json = require("json")
local save = require("utils.save")
local timeLabels = require("utils.time_labels")
local ui = require("utils.ui")
local widget = require("widget")

local SW = display.actualContentWidth
local SH = display.actualContentHeight
local CX = display.contentCenterX
local CY = display.contentCenterY

local COMPOSE_H = 62
local COMPOSE_BOTTOM_PAD = 104
local KEYBOARD_LIFT = 330

local function trim(value)
    return tostring(value or ""):match("^%s*(.-)%s*$")
end

local function makeText(parent, value, x, y, size, color, width, align)
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

local function targetName(sceneObject)
    return sceneObject.targetName or ""
end

local function isThreadMode(sceneObject)
    return sceneObject.mode == "thread"
end

local function wallKey(sceneObject)
    return tostring(targetName(sceneObject) or "unknown"):lower():gsub("[^%w_%-]", "_")
end

local function wallPath(sceneObject)
    return system.pathForFile("wall_" .. wallKey(sceneObject) .. ".json", system.DocumentsDirectory)
end

local function loadWallPosts(sceneObject)
    local f = io.open(wallPath(sceneObject), "r")
    if not f then return {} end
    local raw = f:read("*a")
    io.close(f)
    local data = json.decode(raw)
    return (data and data.posts) or {}
end

local function saveWallPosts(sceneObject, posts)
    local f = io.open(wallPath(sceneObject), "w")
    if not f then return false end
    f:write(json.encode({ posts = posts or {} }))
    io.close(f)
    return true
end

local function senderName()
    local player = save.load()
    return player.name or player.displayName or "Player"
end

local function senderSkin()
    local player = save.load()
    return (player.appearance and player.appearance.skinId) or player.skinId or "street_brawler"
end

local function drawPortrait(parent, x, y, name, skin)
    local ok, portrait = pcall(display.newImageRect, parent, "assets/sprites/characters/" .. tostring(skin or "street_brawler") .. "/portrait.png", 44, 44)
    if ok and portrait then
        portrait.x = x
        portrait.y = y
        return portrait
    end

    local fallback = display.newCircle(parent, x, y, 20)
    fallback:setFillColor(0.05, 0.17, 0.38, 0.98)
    fallback.strokeWidth = 1.5
    fallback:setStrokeColor(0.24, 0.70, 1.0, 0.78)
    makeText(parent, string.sub(string.upper(name or "?"), 1, 1), x, y, 15, { 0.70, 0.94, 1.0 })
    return fallback
end

local function moveComposer(sceneObject, raised)
    local yOffset = raised and -KEYBOARD_LIFT or 0
    if sceneObject.composerRaised == raised then return end
    sceneObject.composerRaised = raised

    for _, obj in ipairs(sceneObject.composeDisplayObjects or {}) do
        if obj and obj.removeSelf then
            transition.to(obj, { y = obj._baseY + yOffset, time = 140 })
        end
    end

    for _, field in ipairs(sceneObject.composeFields or {}) do
        if field and field.removeSelf then
            transition.to(field, { y = field._baseY + yOffset, time = 140 })
        end
    end
end

local function openThreadTarget(thread)
    if thread.kind == "player" and thread.playerId then
        composer.gotoScene("scenes.social_profile", {
            effect = "slideLeft",
            time = 220,
            params = {
                playerId = thread.playerId,
                playerName = thread.from,
                returnScene = "scenes.messages",
            },
        })
    end
end

local function openPlayerThread(sceneObject, playerName)
    composer.gotoScene("scenes.messages", {
        effect = "slideLeft",
        time = 180,
        params = {
            mode = "thread",
            toPlayerName = playerName or targetName(sceneObject),
        },
    })
end

local function openPlayerProfile(sceneObject, post)
    composer.gotoScene("scenes.social_profile", {
        effect = "slideLeft",
        time = 180,
        params = {
            playerId = post and post.fromPlayerId,
            playerName = post and post.from or targetName(sceneObject),
            returnScene = "scenes.messages",
        },
    })
end

local function renderThreads(sceneObject, threads)
    if sceneObject.scrollView then
        sceneObject.scrollView:removeSelf()
        sceneObject.scrollView = nil
    end

    local hasTarget = targetName(sceneObject) ~= ""
    local listTop = 62
    local listBottom = hasTarget and (SH - COMPOSE_H - COMPOSE_BOTTOM_PAD - 10) or (SH - 88)
    local listH = listBottom - listTop

    local scrollView = widget.newScrollView({
        x = CX,
        y = listTop + listH * 0.5,
        width = SW - 8,
        height = listH,
        hideBackground = true,
        horizontalScrollDisabled = true,
    })
    sceneObject.view:insert(scrollView)
    sceneObject.scrollView = scrollView

    local content = display.newGroup()
    scrollView:insert(content)

    if hasTarget and isThreadMode(sceneObject) then
        local messages = sceneObject.threadMessages or {}
        if #messages == 0 then
            local emptyText = display.newText({
                parent = content,
                text = "No private messages with " .. targetName(sceneObject) .. " yet.",
                x = CX,
                y = 80,
                width = SW - 40,
                font = ui.FONT_BOLD,
                fontSize = 12,
                align = "center",
            })
            emptyText:setFillColor(0.68, 0.82, 1.0)
            return
        end

        for i, msg in ipairs(messages) do
            local y = 46 + (i - 1) * 82
            drawPortrait(content, 36, y, msg.author, msg.authorSkin)

            local bubble = display.newRoundedRect(content, CX + 24, y, SW - 86, 68, 8)
            bubble:setFillColor(0.04, 0.10, 0.24, 0.98)
            bubble.strokeWidth = 1.5
            bubble:setStrokeColor(0.20, 0.55, 1.0, 0.52)

            local nameLine = display.newText({
                parent = content,
                text = string.upper(msg.author or "PLAYER") .. "  [" .. timeLabels.forMessage(msg) .. "]",
                x = 66,
                y = y - 18,
                width = SW - 120,
                font = ui.FONT_BOLD,
                fontSize = 9,
                align = "left",
            })
            nameLine.anchorX = 0
            nameLine:setFillColor(1.0, 0.90, 0.20)

            local bodyText = display.newText({
                parent = content,
                text = msg.body or "",
                x = 66,
                y = y + 8,
                width = SW - 120,
                font = ui.FONT_BOLD,
                fontSize = 10,
                align = "left",
            })
            bodyText.anchorX = 0
            bodyText:setFillColor(0.92, 0.96, 1.0)
        end
        return
    end

    if hasTarget then
        local posts = sceneObject.serverWallPosts or loadWallPosts(sceneObject)
        if #posts == 0 then
            local emptyText = display.newText({
                parent = content,
                text = "No messages with " .. targetName(sceneObject) .. " yet.",
                x = CX,
                y = 80,
                width = SW - 40,
                font = ui.FONT_BOLD,
                fontSize = 12,
                align = "center",
            })
            emptyText:setFillColor(0.68, 0.82, 1.0)
            return
        end

        for i, post in ipairs(posts) do
            local y = 46 + (i - 1) * 92
            local portrait = drawPortrait(content, 36, y, post.from, post.fromSkin)

            local bubble = display.newRoundedRect(content, CX + 24, y, SW - 86, 78, 8)
            bubble:setFillColor(0.04, 0.10, 0.24, 0.98)
            bubble.strokeWidth = 1.5
            bubble:setStrokeColor(0.20, 0.55, 1.0, 0.52)

            local nameLine = display.newText({
                parent = content,
                text = string.upper(post.from or "PLAYER") .. "  [" .. timeLabels.forMessage(post) .. "]",
                x = 66,
                y = y - 22,
                width = SW - 120,
                font = ui.FONT_BOLD,
                fontSize = 9,
                align = "left",
            })
            nameLine.anchorX = 0
            nameLine:setFillColor(1.0, 0.90, 0.20)

            local bodyText = display.newText({
                parent = content,
                text = post.body or "",
                x = 66,
                y = y + 8,
                width = SW - 120,
                font = ui.FONT_BOLD,
                fontSize = 10,
                align = "left",
            })
            bodyText.anchorX = 0
            bodyText:setFillColor(0.92, 0.96, 1.0)

            bubble:addEventListener("tap", function()
                openPlayerThread(sceneObject, post.from)
                return true
            end)
            bodyText:addEventListener("tap", function()
                openPlayerThread(sceneObject, post.from)
                return true
            end)
            nameLine:addEventListener("tap", function()
                openPlayerThread(sceneObject, post.from)
                return true
            end)
            if portrait then
                portrait:addEventListener("tap", function()
                    openPlayerProfile(sceneObject, post)
                    return true
                end)
            end
        end
        return
    end

    if not threads or #threads == 0 then
        local emptyText = display.newText({
            parent = content,
            text = "No threads yet.",
            x = CX,
            y = 80,
            width = SW - 40,
            font = ui.FONT_BOLD,
            fontSize = 12,
            align = "center",
        })
        emptyText:setFillColor(0.68, 0.82, 1.0)
        return
    end

    for i, thread in ipairs(threads) do
        local y = 44 + (i - 1) * 78
        local card = display.newRoundedRect(content, CX, y, SW - 24, 68, 8)
        card:setFillColor(0.03, 0.08, 0.20, 0.95)
        card.strokeWidth = 1.5
        card:setStrokeColor(0.20, 0.50, 1.0, 0.50)

        local portrait = display.newCircle(content, 38, y, 18)
        portrait:setFillColor(0.05, 0.17, 0.38, 0.98)
        portrait.strokeWidth = 1.5
        portrait:setStrokeColor(0.24, 0.70, 1.0, 0.78)
        makeText(content, string.sub(string.upper(thread.from or "?"), 1, 1), 38, y, 14, { 0.70, 0.94, 1.0 })

        local fromText = display.newText({
            parent = content,
            text = string.upper(thread.from or "UNKNOWN"),
            x = 66,
            y = y - 14,
            width = SW - 126,
            font = ui.FONT_BOLD,
            fontSize = 12,
            align = "left",
        })
        fromText.anchorX = 0
        fromText:setFillColor(0.88, 0.96, 1.0)

        local messageText = display.newText({
            parent = content,
            text = thread.lastMessage or "",
            x = 66,
            y = y + 10,
            width = SW - 126,
            font = ui.FONT_BOLD,
            fontSize = 9,
            align = "left",
        })
        messageText.anchorX = 0
        messageText:setFillColor(0.68, 0.82, 1.0)

        card:addEventListener("tap", function()
            openThreadTarget(thread)
            return true
        end)
    end
end

local function loadThreads(sceneObject)
    if targetName(sceneObject) ~= "" and isThreadMode(sceneObject) then
        api.messages.withPlayer(targetName(sceneObject), function(response)
            if response.ok and response.data and response.data.thread then
                sceneObject.threadMessages = response.data.thread.messages or {}
            else
                sceneObject.threadMessages = {}
            end
            renderThreads(sceneObject, {})
        end)
        return
    end

    if targetName(sceneObject) ~= "" then
        api.walls.list(targetName(sceneObject), function(response)
            if response.ok and response.data and response.data.posts then
                sceneObject.serverWallPosts = response.data.posts
                saveWallPosts(sceneObject, response.data.posts)
            else
                sceneObject.serverWallPosts = nil
            end
            renderThreads(sceneObject, {})
        end)
        return
    end

    api.messages.threads(function(response)
        local threads = {}
        if response.ok and response.data and response.data.threads then
            threads = response.data.threads
        end
        renderThreads(sceneObject, threads)
    end)
end

local function sendMessage(sceneObject)
    local toName = trim(targetName(sceneObject))
    local body = trim(sceneObject.messageField and sceneObject.messageField.text or "")
    if toName == "" or body == "" then return true end

    local posts = sceneObject.serverWallPosts or loadWallPosts(sceneObject)
    table.insert(posts, {
        from = senderName(),
        fromSkin = senderSkin(),
        to = toName,
        body = body,
        private = sceneObject.privateMessage == true,
        sentAt = os.time(),
    })
    saveWallPosts(sceneObject, posts)
    sceneObject.serverWallPosts = posts

    if sceneObject.messageField then sceneObject.messageField.text = "" end
    native.setKeyboardFocus(nil)
    moveComposer(sceneObject, false)

    if isThreadMode(sceneObject) then
        table.insert(sceneObject.threadMessages, {
            author = senderName(),
            authorSkin = senderSkin(),
            body = body,
            sentAt = os.time(),
        })
        renderThreads(sceneObject, {})
        api.messages.send({ to = toName, body = body, private = sceneObject.privateMessage == true }, function(response)
            if response.ok and response.data and response.data.thread then
                sceneObject.threadMessages = response.data.thread.messages or sceneObject.threadMessages
                renderThreads(sceneObject, {})
            end
        end)
        return true
    end

    renderThreads(sceneObject, {})

    api.walls.post(toName, { body = body, private = sceneObject.privateMessage == true }, function(response)
        if response.ok and response.data and response.data.posts then
            sceneObject.serverWallPosts = response.data.posts
            saveWallPosts(sceneObject, response.data.posts)
            renderThreads(sceneObject, {})
        end
    end)
    api.messages.send({ to = toName, body = body, private = true }, function() end)
    return true
end

local function addBaseY(obj)
    obj._baseY = obj.y
    return obj
end

local function createComposer(sceneObject)
    local sg = sceneObject.view
    sceneObject.composeDisplayObjects = {}
    sceneObject.composeFields = {}

    local composeY = SH - COMPOSE_BOTTOM_PAD - COMPOSE_H * 0.5
    local bg = addBaseY(display.newRoundedRect(sg, CX, composeY, SW - 18, COMPOSE_H, 10))
    bg:setFillColor(0.03, 0.08, 0.20, 0.98)
    bg.strokeWidth = 1.5
    bg:setStrokeColor(0.20, 0.50, 1.0, 0.55)
    table.insert(sceneObject.composeDisplayObjects, bg)

    local fieldBg = addBaseY(display.newRoundedRect(sg, CX - 34, composeY, SW - 110, 38, 9))
    fieldBg:setFillColor(0.05, 0.12, 0.27, 0.98)
    fieldBg.strokeWidth = 1.2
    fieldBg:setStrokeColor(0.18, 0.55, 1.0, 0.58)
    table.insert(sceneObject.composeDisplayObjects, fieldBg)

    local sendBtn = addBaseY(display.newRoundedRect(sg, SW - 44, composeY, 68, 38, 9))
    sendBtn:setFillColor(0.05, 0.22, 0.52, 0.98)
    sendBtn.strokeWidth = 1.5
    sendBtn:setStrokeColor(0.28, 0.75, 1.0, 0.88)
    table.insert(sceneObject.composeDisplayObjects, sendBtn)

    local sendText = addBaseY(makeText(sg, "SEND", sendBtn.x, sendBtn.y, 9, { 0.78, 0.96, 1.0 }))
    table.insert(sceneObject.composeDisplayObjects, sendText)

    sceneObject.privateMessage = sceneObject.privateMessage == true
    local privateBtn = addBaseY(display.newRoundedRect(sg, 62, composeY - 34, 104, 24, 6))
    privateBtn:setFillColor(sceneObject.privateMessage and 0.04 or 0.03, sceneObject.privateMessage and 0.22 or 0.08, sceneObject.privateMessage and 0.14 or 0.20, 0.96)
    privateBtn.strokeWidth = 1.2
    privateBtn:setStrokeColor(0.22, 0.70, 1.0, 0.58)
    table.insert(sceneObject.composeDisplayObjects, privateBtn)
    local privateText = addBaseY(makeText(sg, (sceneObject.privateMessage and "[X] " or "[ ] ") .. "PRIVATE", privateBtn.x, privateBtn.y, 8, { 0.78, 0.92, 1.0 }, 98))
    table.insert(sceneObject.composeDisplayObjects, privateText)
    privateBtn:addEventListener("tap", function()
        sceneObject.privateMessage = not sceneObject.privateMessage
        if sceneObject.messageField then sceneObject.messageField.isVisible = false; sceneObject.messageField:removeSelf(); sceneObject.messageField = nil end
        for _, obj in ipairs(sceneObject.composeDisplayObjects or {}) do
            if obj and obj.removeSelf then obj:removeSelf() end
        end
        createComposer(sceneObject)
        return true
    end)

    sceneObject.messageField = native.newTextField(CX - 34, composeY, SW - 122, 30)
    sceneObject.messageField.placeholder = "Message " .. targetName(sceneObject)
    sceneObject.messageField.hasBackground = false
    sceneObject.messageField:setTextColor(0.85, 0.95, 1)
    sceneObject.messageField._baseY = sceneObject.messageField.y
    table.insert(sceneObject.composeFields, sceneObject.messageField)

    sceneObject.messageField:addEventListener("userInput", function(event)
        if event.phase == "began" then
            moveComposer(sceneObject, true)
        elseif event.phase == "submitted" then
            sendMessage(sceneObject)
        end
    end)

    sendBtn:addEventListener("tap", function()
        return sendMessage(sceneObject)
    end)
end

function scene:create(event)
    local sg = self.view

    local bg = display.newImage("assets/sprites/ui/bg_home_grid.png")
    bg:scale(math.max(SW / bg.width, SH / bg.height), math.max(SW / bg.width, SH / bg.height))
    bg.x = CX
    bg.y = CY
    sg:insert(bg)

    local dim = display.newRect(sg, CX, CY, SW, SH)
    dim:setFillColor(0, 0, 0, 0.56)

    local borderH = SH - 16
    local border = display.newRoundedRect(sg, CX, CY, SW - 8, borderH, 12)
    border:setFillColor(0, 0, 0, 0)
    border.strokeWidth = 3
    border:setStrokeColor(0.20, 0.55, 1.00, 0.75)

    local header = display.newRoundedRect(sg, CX, 30, SW - 16, 48, 8)
    header:setFillColor(0.02, 0.06, 0.16, 0.96)
    header.strokeWidth = 1.5
    header:setStrokeColor(0.18, 0.38, 0.92, 0.46)

    self.title = display.newText({
        parent = sg,
        text = "MESSAGES",
        x = 18,
        y = 24,
        font = ui.FONT_BOLD,
        fontSize = 18,
        align = "left",
    })
    self.title.anchorX = 0
    self.title:setFillColor(0.38, 0.86, 1.0)

    self.subtitle = display.newText({
        parent = sg,
        text = "Tap a thread to open it",
        x = 18,
        y = 40,
        font = ui.FONT_BOLD,
        fontSize = 8,
        align = "left",
    })
    self.subtitle.anchorX = 0
    self.subtitle:setFillColor(0.50, 0.74, 1.0, 0.82)

    local closeBtn = display.newRoundedRect(sg, SW - 30, 30, 34, 34, 8)
    closeBtn:setFillColor(0.05, 0.18, 0.42, 0.98)
    closeBtn.strokeWidth = 1.5
    closeBtn:setStrokeColor(0.28, 0.68, 1.0, 0.82)
    makeText(sg, "X", closeBtn.x, closeBtn.y, 14, { 0.78, 0.96, 1.0 })
    closeBtn:addEventListener("tap", function()
        native.setKeyboardFocus(nil)
        composer.gotoScene("scenes.home", { effect = "slideRight", time = 220 })
        return true
    end)
end

function scene:show(event)
    if event.phase ~= "did" then return end

    local params = event.params or {}
    self.mode = params.mode or "wall"
    self.targetName = params.toPlayerName or params.playerName or nil
    if not self.targetName or self.targetName == "" then
        self.targetName = senderName()
    end
    self.targetId = params.toPlayerId or params.playerId or self.targetName

    if self.title then
        if isThreadMode(self) then
            self.title.text = string.upper(targetName(self))
        else
            self.title.text = self.targetName and string.upper(self.targetName .. "'S WALL") or "MESSAGES"
        end
    end
    if self.subtitle then
        self.subtitle.text = isThreadMode(self) and "Private thread" or (self.targetName and "Private message or post on their wall" or "Tap a thread to open it")
    end

    if self.messageField then
        self.messageField.isVisible = false
        self.messageField:removeSelf()
        self.messageField = nil
    end
    self.composeDisplayObjects = nil
    self.composeFields = nil
    self.composerRaised = false

    if self.targetName then
        createComposer(self)
    end

    loadThreads(self)
end

function scene:hide(event)
    if event.phase ~= "will" then return end
    native.setKeyboardFocus(nil)
    if self.messageField then self.messageField.isVisible = false end
end

function scene:destroy(event)
    if self.messageField then self.messageField:removeSelf(); self.messageField = nil end
end

scene:addEventListener("create", scene)
scene:addEventListener("show", scene)
scene:addEventListener("hide", scene)
scene:addEventListener("destroy", scene)

return scene
