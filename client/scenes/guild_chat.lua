local composer = require("composer")
local scene = composer.newScene()

local api = require("utils.api")
local guildNav = require("utils.guild_nav")
local session = require("utils.session")
local shell = require("utils.guild_scene_shell")
local timeLabels = require("utils.time_labels")
local ui = require("utils.ui")

local ROLE_COLORS = {
    LEADER={1.0,0.78,0.10}, GENERAL={1.0,0.40,0.20},
    LIEUTENANT={0.35,0.75,1.0}, COLONEL={0.35,0.75,1.0},
    CAPTAIN={0.55,1.0,0.65}, MEMBER={0.50,0.52,0.62},
}

local activeGuild
local contentGroup
local chromeGroup
local chatField
local privateChat = false
local composerRaised = false
local KEYBOARD_LIFT = 280

local function trim(value)
    return tostring(value or ""):match("^%s*(.-)%s*$")
end

local function cleanupField()
    native.setKeyboardFocus(nil)
    if chatField and chatField.removeSelf then chatField:removeSelf() end
    chatField = nil
    composerRaised = false
end

local function clearContent()
    cleanupField()
    if contentGroup and contentGroup.removeSelf then contentGroup:removeSelf() end
    contentGroup = nil
end

local function findMember(members, msg, senderName)
    for _, member in ipairs(members or {}) do
        if member.playerId == msg.authorPlayerId or member.name == senderName then
            return member
        end
    end
    return nil
end

local function buildChat()
    clearContent()
    contentGroup = display.newGroup()
    scene.view:insert(contentGroup)
    if chromeGroup and chromeGroup.toFront then chromeGroup:toFront() end

    local m = shell.metrics()
    shell.drawFrame(contentGroup, m.CONTENT_X, m.CONTENT_Y, m.CONTENT_W, m.CONTENT_H)
    display.newText({
        parent=contentGroup, text="GUILD CHAT",
        x=m.CONTENT_X, y=m.CONTENT_TOP + 16,
        font=ui.FONT_BOLD, fontSize=15
    }):setFillColor(0.62,0.88,1.0)
    shell.divLine(contentGroup, m.CONTENT_X, m.CONTENT_TOP + 34, m.CONTENT_W - 24)

    local inputH = 42
    local headerH = 42
    local scrollH = m.CONTENT_H - inputH - headerH - 14
    local bubbleW = m.CONTENT_W - 24
    local bubbleH = 66
    local bubblePad = 7
    local messages = (activeGuild and activeGuild._messages) or {}
    local members = (activeGuild and activeGuild._members) or {}

    local container = display.newContainer(contentGroup, m.CONTENT_W, scrollH)
    container.x = m.CONTENT_X
    container.y = m.CONTENT_TOP + headerH + scrollH * 0.5
    local inner = display.newGroup()
    container:insert(inner)

    local totalH = #messages * (bubbleH + bubblePad)
    local startY = -scrollH * 0.5 + bubbleH * 0.5 + bubblePad
    for i, msg in ipairs(messages) do
        local by = startY + (i - 1) * (bubbleH + bubblePad)
        local isPrivate = msg.private == true
        local bubble = display.newRoundedRect(inner, 0, by, bubbleW, bubbleH, 8)
        bubble:setFillColor(isPrivate and 0.035 or 0.04, isPrivate and 0.16 or 0.10, isPrivate and 0.10 or 0.22, 0.97)
        bubble.strokeWidth = 1.2
        bubble:setStrokeColor(isPrivate and 0.32 or 0.18, isPrivate and 0.95 or 0.55, isPrivate and 0.48 or 0.38, 0.52)

        local senderName = msg.author or msg.name or "Player"
        local member = findMember(members, msg, senderName)
        local role = member and member.rank or "MEMBER"
        local color = ROLE_COLORS[role] or ROLE_COLORS.MEMBER
        shell.drawPortrait(inner, -bubbleW * 0.5 + 30, by, senderName, member and member.skinId, 44)

        local nt = display.newText({
            parent=inner, text=(isPrivate and "PRIVATE  " or "") .. senderName,
            x=-bubbleW * 0.5 + 60, y=by - 19,
            width=bubbleW - 84, font=ui.FONT_BOLD, fontSize=10, align="left"
        })
        nt.anchorX = 0
        nt:setFillColor(unpack(color))

        local tt = display.newText({
            parent=inner, text=timeLabels.forMessage(msg),
            x=-bubbleW * 0.5 + 60, y=by - 4,
            font=ui.FONT_BOLD, fontSize=7, align="left"
        })
        tt.anchorX = 0
        tt:setFillColor(0.36,0.52,0.70)

        local body = display.newText({
            parent=inner, text=msg.body or msg.msg or "",
            x=-bubbleW * 0.5 + 60, y=by + 17,
            width=bubbleW - 84, font=ui.FONT_BOLD, fontSize=10, align="left"
        })
        body.anchorX = 0
        body:setFillColor(0.78,0.86,1.0)

        local currentPlayerId = session.get().playerId
        local canDelete = msg.id and (msg.authorPlayerId == currentPlayerId or (activeGuild and activeGuild.role == "LEADER"))
        if canDelete then
            local del = display.newRoundedRect(inner, bubbleW * 0.5 - 16, by - 22, 22, 18, 4)
            del:setFillColor(0.26,0.04,0.05,0.95)
            del.strokeWidth = 1
            del:setStrokeColor(1.0,0.24,0.24,0.70)
            local dx = display.newText({ parent=inner, text="X", x=del.x, y=del.y, font=ui.FONT_BOLD, fontSize=8 })
            dx:setFillColor(1.0,0.42,0.42)
            dx.isHitTestable = false
            del:addEventListener("tap", function()
                api.guilds.deleteChat(activeGuild.guildId, msg.id, function(response)
                    if response and response.ok and response.data and response.data.messages then
                        activeGuild._messages = response.data.messages
                        buildChat()
                    end
                end)
                return true
            end)
        end
    end

    local minY = math.min(0, scrollH - totalH - bubblePad * 2)
    local startTouchY, startGroupY = 0, 0
    container:addEventListener("touch", function(e)
        if e.phase == "began" then
            startTouchY = e.y
            startGroupY = inner.y
        elseif e.phase == "moved" then
            inner.y = math.max(minY, math.min(0, startGroupY + e.y - startTouchY))
        end
        return true
    end)

    local inputY = m.CONTENT_BOT - inputH * 0.5 - 5
    local inputW = m.CONTENT_W - 66
    local composeObjects = {}
    local function addBase(obj)
        obj._baseY = obj.y
        composeObjects[#composeObjects + 1] = obj
        return obj
    end
    local function moveComposer(raised)
        if composerRaised == raised then return end
        composerRaised = raised
        local offset = raised and -KEYBOARD_LIFT or 0
        for _, obj in ipairs(composeObjects) do
            if obj and obj.removeSelf then transition.to(obj, { y=obj._baseY + offset, time=140 }) end
        end
        if chatField and chatField.removeSelf then
            transition.to(chatField, { y=chatField._baseY + offset, time=140 })
        end
    end

    local frameColor = privateChat and {0.22,0.95,0.48} or {0.18,0.62,0.40}
    local inputBg = addBase(display.newRoundedRect(contentGroup, m.CONTENT_X - 18, inputY, inputW, inputH - 4, 7))
    inputBg:setFillColor(privateChat and 0.025 or 0.03, privateChat and 0.14 or 0.08, privateChat and 0.08 or 0.20, 0.98)
    inputBg.strokeWidth = 1.6
    inputBg:setStrokeColor(frameColor[1], frameColor[2], frameColor[3], 0.86)

    chatField = native.newTextField(m.CONTENT_X - 18, inputY, inputW - 8, inputH - 12)
    chatField.placeholder = privateChat and "Private guild message..." or "Message crew..."
    chatField.font = native.newFont(ui.FONT_BOLD, 10)
    chatField.hasBackground = false
    chatField:setTextColor(0.04, 0.08, 0.12)
    chatField._baseY = chatField.y

    local sendX = m.CONTENT_X + m.CONTENT_W * 0.5 - 22
    local sendBtn = addBase(display.newRoundedRect(contentGroup, sendX, inputY, 34, inputH - 8, 7))
    sendBtn:setFillColor(0.04,0.22,0.52,0.97)
    sendBtn.strokeWidth = 1.5
    sendBtn:setStrokeColor(0.18,0.62,0.40,0.80)
    local sendText = addBase(display.newText({ parent=contentGroup, text=">", x=sendX, y=inputY, font=ui.FONT_BOLD, fontSize=13 }))
    sendText:setFillColor(0.70,0.92,1.0)
    sendText.isHitTestable = false

    local privateBtn = addBase(display.newRoundedRect(contentGroup, m.CONTENT_X - m.CONTENT_W * 0.5 + 56, inputY - 32, 94, 22, 6))
    privateBtn:setFillColor(privateChat and 0.04 or 0.03, privateChat and 0.24 or 0.08, privateChat and 0.12 or 0.20, 0.96)
    privateBtn.strokeWidth = 1.2
    privateBtn:setStrokeColor(privateChat and 0.32 or 0.22, privateChat and 0.95 or 0.70, privateChat and 0.48 or 1.0, 0.64)
    local privateText = addBase(display.newText({
        parent=contentGroup, text=(privateChat and "[X] " or "[ ] ") .. "PRIVATE",
        x=privateBtn.x, y=privateBtn.y, font=ui.FONT_BOLD, fontSize=8
    }))
    privateText:setFillColor(privateChat and 0.56 or 0.78, privateChat and 1.0 or 0.92, privateChat and 0.64 or 1.0)
    privateText.isHitTestable = false
    privateBtn:addEventListener("tap", function()
        privateChat = not privateChat
        buildChat()
        return true
    end)

    local function sendChat()
        local body = trim(chatField and chatField.text or "")
        if body == "" or not activeGuild or not activeGuild.guildId then return true end
        chatField.text = ""
        native.setKeyboardFocus(nil)
        moveComposer(false)
        api.guilds.sendChat(activeGuild.guildId, { body=body, private=privateChat }, function(response)
            if response and response.ok and response.data and response.data.messages then
                activeGuild._messages = response.data.messages
                buildChat()
            end
        end)
        return true
    end

    chatField:addEventListener("userInput", function(event)
        if event.phase == "began" then
            moveComposer(true)
        elseif event.phase == "submitted" then
            sendChat()
        end
        return false
    end)
    sendBtn:addEventListener("tap", sendChat)
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
        buildChat()
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
