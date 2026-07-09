local composer = require("composer")
local api = require("utils.api")
local guildContext = require("utils.guild_context")
local guildNav = require("utils.guild_nav")
local saveUtil = require("utils.save")
local sync = require("utils.sync")
local ui = require("utils.ui")

local M = {}

function M.metrics()
    local sw = display.contentWidth
    local sh = display.contentHeight
    local cx = display.contentCenterX
    local cy = display.contentCenterY
    local headerH = 66
    local headerY = headerH * 0.5
    local contentTop = headerH + 4
    local contentBot = guildNav.contentBottom()
    local contentH = contentBot - contentTop
    return {
        SW=sw, SH=sh, CX=cx, CY=cy,
        HEADER_H=headerH, HEADER_Y=headerY,
        CONTENT_X=cx,
        CONTENT_W=sw - 14,
        CONTENT_TOP=contentTop,
        CONTENT_BOT=contentBot,
        CONTENT_H=contentH,
        CONTENT_Y=contentTop + contentH * 0.5,
    }
end

function M.drawFrame(parent, x, y, w, h)
    local r = display.newRoundedRect(parent, x, y, w, h, 8)
    r:setFillColor(0.025, 0.065, 0.16, 0.92)
    r.strokeWidth = 1.5
    r:setStrokeColor(0.18, 0.50, 0.92, 0.58)

    local accent = display.newRect(parent, x, y - h * 0.5 + 5, w - 18, 2)
    accent:setFillColor(0.24, 0.64, 1.0, 0.46)
    accent.isHitTestable = false
    return r
end

function M.divLine(parent, x, y, w)
    local line = display.newRect(parent, x, y, w, 1)
    line:setFillColor(0.18, 0.48, 0.82, 0.26)
    return line
end

function M.drawBackground(parent)
    local m = M.metrics()
    local bg = display.newImage("assets/sprites/ui/bg_home_grid.png")
    if bg then
        bg:scale(math.max(m.SW / bg.width, m.SH / bg.height), math.max(m.SW / bg.width, m.SH / bg.height))
        bg.x = m.CX
        bg.y = m.CY
        parent:insert(bg)
    else
        bg = display.newRect(parent, m.CX, m.CY, m.SW, m.SH)
        bg:setFillColor(0.02, 0.03, 0.08)
    end
    local dim = display.newRect(parent, m.CX, m.CY, m.SW, m.SH)
    dim:setFillColor(0, 0, 0, 0.20)
    dim.isHitTestable = false
end

function M.loadGuild(params, callback)
    local player = saveUtil.load()
    local guild = guildContext.getActiveGuild(player, params) or {
        name="Unknown Guild", guildId=params and params.guildId,
        rep=320, gold=0, role="MEMBER", members=0, maxMembers=20,
    }
    if not guild.guildId then
        callback(guild)
        return
    end
    api.guilds.get(guild.guildId, function(response)
        if response and response.ok and response.data then
            if response.data.player then
                sync.applyPlayerSnapshot(response.data.player, saveUtil.activeSlot)
                player = saveUtil.load()
            end
            local remote = response.data.guild or guild
            for k, v in pairs(remote) do guild[k] = v end
            guild._members = response.data.members or guild._members or {}
            guild._messages = response.data.messages or guild._messages or {}
            guild._jail = response.data.jail or guild._jail or {}
            guild._pendingWar = response.data.pendingWar
            guildContext.applyGuild(player, guild, guild.role or "MEMBER")
            saveUtil.save(player)
        end
        callback(guild)
    end)
end

function M.guildParams(guild)
    return {
        guildId = guild and guild.guildId or guildContext.getActiveGuildId(),
        guildKey = composer.getVariable("guildContextKind"),
    }
end

function M.drawHeader(parent, guild)
    local m = M.metrics()
    M.drawFrame(parent, m.CX, m.HEADER_Y, m.SW - 6, m.HEADER_H)
    display.newText({
        parent=parent, text=string.upper((guild and guild.name) or "GUILD"),
        x=m.CX, y=m.HEADER_Y - 13, width=m.SW - 24,
        font=ui.FONT_BOLD, fontSize=16, align="center"
    }):setFillColor(0.82, 0.96, 1.0)
    display.newText({
        parent=parent, text="<> " .. tostring((guild and guild.rep) or 320),
        x=m.CX - 52, y=m.HEADER_Y + 14,
        font=ui.FONT_BOLD, fontSize=11
    }):setFillColor(0.72, 0.92, 1.0)
    display.newText({
        parent=parent, text="() " .. tostring((guild and guild.gold) or 0),
        x=m.CX + 52, y=m.HEADER_Y + 14,
        font=ui.FONT_BOLD, fontSize=11
    }):setFillColor(1.0, 0.82, 0.20)
end

function M.drawTitleBanner(parent, title, opts)
    opts = opts or {}
    local m = M.metrics()
    local h = opts.height or 56
    local y = opts.y or (h * 0.5 + 8)
    local w = opts.width or (m.SW - 12)
    local glow = display.newRoundedRect(parent, m.CX, y, w + 4, h + 4, 10)
    glow:setFillColor(0, 0, 0, 0)
    glow.strokeWidth = 2
    glow:setStrokeColor(0.12, 0.48, 1.0, 0.38)

    local bg = display.newRoundedRect(parent, m.CX, y, w, h, 9)
    bg:setFillColor(0.02, 0.06, 0.16, 0.96)
    bg.strokeWidth = 1.5
    bg:setStrokeColor(0.18, 0.38, 0.92, 0.48)

    local topLine = display.newRect(parent, m.CX, y - h * 0.5 + 6, w - 22, 2)
    topLine:setFillColor(0.30, 0.66, 1.0, 0.62)

    local titleText = display.newText({
        parent=parent,
        text=string.upper(tostring(title or "")),
        x=m.CX,
        y=y,
        width=w - 30,
        font=ui.FONT_BOLD,
        fontSize=opts.fontSize or 20,
        align="center",
    })
    titleText:setFillColor(unpack(opts.color or {0.40, 0.84, 1.0}))
    return bg
end

function M.drawCloseToHome(parent, guild)
    local m = M.metrics()
    local size = 38
    local x = m.SW - size * 0.5 - 10
    local y = guildNav.contentBottom() - size * 0.5 - 8
    local bg = display.newRoundedRect(parent, x, y, size, size, 8)
    bg:setFillColor(0.03, 0.10, 0.24, 0.96)
    bg.strokeWidth = 1.5
    bg:setStrokeColor(0.24, 0.70, 1.0, 0.78)
    local label = display.newText({
        parent=parent, text="X", x=x, y=y,
        font=ui.FONT_BOLD, fontSize=13
    })
    label:setFillColor(0.72, 0.92, 1.0)
    local function goHome()
        composer.gotoScene("scenes.guild_home", {
            effect="slideRight", time=180, params=M.guildParams(guild),
        })
        return true
    end
    bg:addEventListener("tap", goHome)
    label:addEventListener("tap", goHome)
end

function M.drawShell(parent, guild, activeBottom)
    M.drawBackground(parent)
    M.drawHeader(parent, guild)
    guildNav.build(parent, activeBottom or "HOME")
    M.drawCloseToHome(parent, guild)
end

function M.drawPortrait(parent, x, y, name, skinId, size)
    size = size or 44
    local paths = {}
    if skinId then
        paths[#paths + 1] = "assets/sprites/characters/" .. tostring(skinId) .. "/portrait.png"
    end
    paths[#paths + 1] = "assets/sprites/characters/street_brawler/portrait.png"
    paths[#paths + 1] = "assets/sprites/characters/street_fighter/portrait.png"
    for _, path in ipairs(paths) do
        local ok, img = pcall(display.newImageRect, parent, path, size, size)
        if ok and img then
            img.x = x
            img.y = y
            return img
        end
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

return M
