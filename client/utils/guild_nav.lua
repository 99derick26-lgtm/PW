local composer = require("composer")
local ui = require("utils.ui")
local guildContext = require("utils.guild_context")

local M = {}

M.HEIGHT = 50
M.BOTTOM_PAD = 1

local TABS = {
    { label="HOME",   scene="scenes.guild_home"   },
    { label="LEAGUE", scene="scenes.guild_league" },
    { label="WAR",    scene="scenes.guild_war"    },
    { label="VAULT",  scene="scenes.guild_loot"   },
}

function M.bottomY()
    return display.contentHeight - M.BOTTOM_PAD
end

function M.contentBottom()
    return M.bottomY() - M.HEIGHT * 0.5 - 4
end

function M.build(parent, activeLabel)
    local sw = display.contentWidth
    local cx = display.contentCenterX
    local y = M.bottomY()
    local btnW = sw / #TABS

    local barBg = display.newRect(parent, cx, y, sw, M.HEIGHT + 6)
    barBg:setFillColor(0.015, 0.035, 0.09, 0.99)
    barBg.strokeWidth = 1
    barBg:setStrokeColor(0.14, 0.42, 0.82, 0.42)

    local barAcc = display.newRect(parent, cx, y - (M.HEIGHT + 6) * 0.5, sw, 2)
    barAcc:setFillColor(0.22, 0.58, 0.96, 0.62)

    for i, tab in ipairs(TABS) do
        local x = (i - 0.5) * btnW
        local active = tab.label == activeLabel
        local hit = display.newRoundedRect(parent, x, y, btnW - 7, M.HEIGHT - 10, 7)
        hit:setFillColor(active and 0.045 or 0.025, active and 0.16 or 0.07, active and 0.34 or 0.17, 0.96)
        hit.strokeWidth = active and 2 or 1.25
        hit:setStrokeColor(active and 0.24 or 0.12, active and 0.72 or 0.38, active and 1.0 or 0.76, active and 0.92 or 0.48)

        local topLine = display.newRect(parent, x, y - (M.HEIGHT - 10) * 0.5 + 4, btnW - 20, 2)
        topLine:setFillColor(active and 0.35 or 0.18, active and 0.84 or 0.52, active and 1.0 or 0.90, active and 0.78 or 0.32)
        topLine.isHitTestable = false

        local label = display.newText({
            parent=parent, text=tab.label,
            x=x, y=y, font=ui.FONT_BOLD, fontSize=11, align="center"
        })
        label:setFillColor(active and 0.82 or 0.62, active and 0.96 or 0.82, active and 1.0 or 0.96)
        label.isHitTestable = false

        if not active then
            hit:addEventListener("tap", function()
                composer.gotoScene(tab.scene, {
                    effect="crossFade",
                    time=180,
                    params={
                        guildId= guildContext.getActiveGuildId(),
                        guildKey= composer.getVariable("guildContextKind"),
                    },
                })
                return true
            end)
        end
    end
end

return M
