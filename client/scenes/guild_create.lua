local composer = require("composer")
local scene     = composer.newScene()

local save = require("utils.save")
local ui   = require("utils.ui")
local api  = require("utils.api")
local guildContext = require("utils.guild_context")

local CX = display.contentCenterX
local CY = display.contentCenterY
local SW = display.actualContentWidth
local SH = display.actualContentHeight

local TIMERS = {}
local nameField = nil

local function cleanupNativeFields()
    native.setKeyboardFocus(nil)
    if nameField and nameField.removeSelf then
        nameField:removeSelf()
    end
    nameField = nil
end

local function hideNativeFields()
    native.setKeyboardFocus(nil)
    if nameField then
        nameField.isVisible = false
    end
end

local function flicker(obj, lo, hi, ms)
    local t = timer.performWithDelay(ms, function()
        if obj and obj.removeSelf then
            obj.alpha = lo + math.random() * (hi - lo)
        end
    end, 0)
    table.insert(TIMERS, t)
end

local function mkBtn(sceneGroup, x, y, w, h, label, r, g, b)
    local glow = display.newRoundedRect(sceneGroup, x, y, w + 6, h + 6, 10)
    glow:setFillColor(r, g, b, 0.18)
    glow.isHitTestable = false
    flicker(glow, 0.5, 1.0, 180)

    local bg = display.newRoundedRect(sceneGroup, x, y, w, h, 8)
    bg:setFillColor(r * 0.18, g * 0.18, b * 0.18)
    bg.strokeWidth = 1.5
    bg:setStrokeColor(r, g, b, 0.9)

    local txt = display.newText({
        parent=sceneGroup, text=label,
        x=x, y=y, font=ui.FONT_BOLD, fontSize=13, align="center"
    })
    txt:setFillColor(r, g, b)
    txt.isHitTestable = false

    return bg, txt
end

function scene:create(event)
    local sg = self.view

    -- bg
    local bg = display.newRect(sg, CX, CY, SW, SH)
    bg:setFillColor(0.02, 0.03, 0.08)

    -- scanlines
    for i = 1, 16 do
        local l = display.newRect(sg, CX, i * (SH/16), SW, 1)
        l:setFillColor(0.05, 0.15, 0.4, 0.06)
        l.isHitTestable = false
    end

    -- header
    local hdr = display.newRect(sg, CX, 32, SW, 56)
    hdr:setFillColor(0.02, 0.06, 0.18, 0.97)
    hdr.strokeWidth = 1
    hdr:setStrokeColor(0.2, 0.5, 1, 0.4)

    local title = display.newText({
        parent=sg, text="CREATE GUILD",
        x=CX, y=32, font=ui.FONT_BOLD, fontSize=18, align="center"
    })
    title:setFillColor(0.25, 0.75, 1.0)
    flicker(title, 0.85, 1.0, 140)

    -- back button
    local backBtn = display.newText({
        parent=sg, text="< BACK",
        x=52, y=32, font=ui.FONT_BOLD, fontSize=11, align="left"
    })
    backBtn:setFillColor(0.3, 0.7, 1)
    backBtn:addEventListener("tap", function()
        composer.gotoScene("scenes.home", { effect="slideRight", time=220 })
        return true
    end)

    -- panel
    local panelY = CY - 40
    local panel  = display.newRoundedRect(sg, CX, panelY, SW - 30, SH * 0.55, 14)
    panel:setFillColor(0.04, 0.10, 0.22, 0.97)
    panel.strokeWidth = 1.5
    panel:setStrokeColor(0.2, 0.5, 1.0, 0.6)

    -- guild name label
    display.newText({
        parent=sg, text="GUILD NAME",
        x=CX, y=panelY - 100,
        font=ui.FONT_BOLD, fontSize=11, align="center"
    }):setFillColor(0.4, 0.7, 1)

    -- name field bg
    local fieldBg = display.newRoundedRect(sg, CX, panelY - 68, SW - 80, 40, 8)
    fieldBg:setFillColor(0.06, 0.14, 0.30)
    fieldBg.strokeWidth = 1
    fieldBg:setStrokeColor(0.2, 0.6, 1, 0.7)

    nameField = native.newTextField(CX, panelY - 68, SW - 90, 36)
    nameField.placeholder = "Enter guild name..."
    nameField.font        = native.newFont(ui.FONT_BOLD, 14)
    nameField.hasBackground = false
    nameField:setTextColor(0.9, 0.95, 1)

    -- max members label
    display.newText({
        parent=sg, text="MAX MEMBERS",
        x=CX, y=panelY + 10,
        font=ui.FONT_BOLD, fontSize=11, align="center"
    }):setFillColor(0.4, 0.7, 1)

    -- member count selector
    local memberCount = 20
    local memberTxt = display.newText({
        parent=sg, text=tostring(memberCount),
        x=CX, y=panelY + 46,
        font=ui.FONT_BOLD, fontSize=22, align="center"
    })
    memberTxt:setFillColor(0.3, 0.9, 1)

    local minusBtn = display.newRoundedRect(sg, CX - 50, panelY + 46, 36, 36, 6)
    minusBtn:setFillColor(0.04, 0.12, 0.30)
    minusBtn.strokeWidth = 1
    minusBtn:setStrokeColor(0.2, 0.6, 1, 0.6)
    display.newText({ parent=sg, text="-", x=CX-50, y=panelY+44,
        font=ui.FONT_BOLD, fontSize=20 }):setFillColor(0.4, 0.8, 1)

    local plusBtn = display.newRoundedRect(sg, CX + 50, panelY + 46, 36, 36, 6)
    plusBtn:setFillColor(0.04, 0.12, 0.30)
    plusBtn.strokeWidth = 1
    plusBtn:setStrokeColor(0.2, 0.6, 1, 0.6)
    display.newText({ parent=sg, text="+", x=CX+50, y=panelY+44,
        font=ui.FONT_BOLD, fontSize=20 }):setFillColor(0.4, 0.8, 1)

    minusBtn:addEventListener("tap", function()
        if memberCount > 5 then
            memberCount = memberCount - 5
            memberTxt.text = tostring(memberCount)
        end
        return true
    end)
    plusBtn:addEventListener("tap", function()
        if memberCount < 50 then
            memberCount = memberCount + 5
            memberTxt.text = tostring(memberCount)
        end
        return true
    end)

    -- open toggle
    display.newText({
        parent=sg, text="OPEN TO PUBLIC",
        x=CX - 20, y=panelY + 100,
        font=ui.FONT_BOLD, fontSize=11, align="center"
    }):setFillColor(0.4, 0.7, 1)

    local isPublic  = true
    local toggleBg  = display.newRoundedRect(sg, CX + 54, panelY + 100, 42, 22, 11)
    toggleBg:setFillColor(0.1, 0.5, 0.2)
    toggleBg.strokeWidth = 1
    toggleBg:setStrokeColor(0.2, 0.9, 0.4, 0.7)
    local toggleDot = display.newCircle(sg, CX + 64, panelY + 100, 9)
    toggleDot:setFillColor(0.3, 1, 0.5)
    toggleDot.isHitTestable = false

    toggleBg:addEventListener("tap", function()
        isPublic = not isPublic
        if isPublic then
            toggleBg:setFillColor(0.1, 0.5, 0.2)
            toggleBg:setStrokeColor(0.2, 0.9, 0.4, 0.7)
            toggleDot:setFillColor(0.3, 1, 0.5)
            transition.to(toggleDot, { x=CX+64, time=120 })
        else
            toggleBg:setFillColor(0.3, 0.08, 0.08)
            toggleBg:setStrokeColor(1, 0.2, 0.2, 0.7)
            toggleDot:setFillColor(1, 0.3, 0.3)
            transition.to(toggleDot, { x=CX+44, time=120 })
        end
        return true
    end)

    -- CREATE button
    local createY  = panelY + SH * 0.27
    local createBg, createTxt = mkBtn(sg, CX, createY, SW - 60, 48, "CREATE GUILD", 0.2, 0.7, 1.0)

    local locked = false
    createBg:addEventListener("tap", function()
        if locked then return true end
        local name = nameField.text or ""
        name = name:match("^%s*(.-)%s*$")
        if #name == 0 then
            -- shake feedback
            transition.to(fieldBg, { x=CX+8, time=60, onComplete=function()
                transition.to(fieldBg, { x=CX-8, time=60, onComplete=function()
                    transition.to(fieldBg, { x=CX, time=60 })
                end})
            end})
            return true
        end

        locked = true
        createBg:setFillColor(0.1, 0.4, 0.9)
        createTxt:setFillColor(1, 1, 1)

        local player = save.load()

        -- block if already created a guild
        if guildContext.getHostedGuild(player) then
            locked = false
            createBg:setFillColor(0.3, 0.08, 0.08)
            display.newText({
                parent=sg, text="Disband your current guild first.",
                x=CX, y=createY - 36,
                font=ui.FONT_BOLD, fontSize=11, align="center"
            }):setFillColor(1, 0.3, 0.3)
            return true
        end

        api.guilds.create({
            name = name,
            maxMembers = memberCount,
            isPublic = isPublic,
        }, function(response)
            if response.ok and response.data and response.data.guild then
                local guild = response.data.guild
                local hostedGuild = {
                    guildId    = guild.guildId,
                    name       = guild.name,
                    leader     = guild.leader,
                    members    = guild.members,
                    maxMembers = guild.maxMembers,
                    isPublic   = guild.isPublic,
                    level      = guild.level or 1,
                    xp         = 0,
                    role       = "LEADER",
                }
                if response.data.player then
                    player = response.data.player
                end
                guildContext.applyGuild(player, hostedGuild, "LEADER")
                guildContext.setActiveGuild(hostedGuild.guildId, "hostedGuild")
                save.save(player)

                cleanupNativeFields()
                composer.gotoScene("scenes.guild_home", {
                    effect="slideLeft",
                    time=280,
                    params={ guildId=hostedGuild.guildId, guildKey="hostedGuild" },
                })
            else
                locked = false
                createBg:setFillColor(0.3, 0.08, 0.08)
                local message = "Could not create that guild on the server."
                if response.data and response.data.error == "already_created_guild" then
                    message = "Disband your current created guild first."
                end
                native.showAlert("Create Failed", message, { "OK" })
            end
        end)
        return true
    end)
end

function scene:show(event)
    if event.phase ~= "will" then return end
    if nameField then
        nameField.isVisible = true
    end
end

function scene:hide(event)
    if event.phase ~= "will" then return end
    hideNativeFields()
    for _, t in ipairs(TIMERS) do pcall(function() timer.cancel(t) end) end
    TIMERS = {}
end

function scene:destroy(event)
    cleanupNativeFields()
end

scene:addEventListener("create", scene)
scene:addEventListener("show",   scene)
scene:addEventListener("hide",   scene)
scene:addEventListener("destroy", scene)

return scene
