local composer = require("composer")
local scene = composer.newScene()

local api = require("utils.api")
local guildContext = require("utils.guild_context")
local rewardPopup = require("utils.reward_popup")
local saveUtil = require("utils.save")
local shell = require("utils.guild_scene_shell")
local sync = require("utils.sync")
local ui = require("utils.ui")

local TIMERS = {}
local activeGuild
local contentGroup
local chromeGroup

local TWELVE_HOURS = 12 * 60 * 60
local AUGMENT_TYPES = { "augment_attack", "augment_defense", "augment_speed", "augment_health" }
local CRYSTAL_ROLLS = {
    { key="crystal_green", chance=0.32 },
    { key="crystal_blue", chance=0.28 },
    { key="crystal_purple", chance=0.23 },
    { key="crystal_orange", chance=0.17 },
}

local LAND_REWARD_META = {
    crystal_green   = { name="Green Crystal", sprite="assets/sprites/materials/crystal_green.png", color={0.35,1.0,0.45}, type="Crystal" },
    crystal_blue    = { name="Blue Crystal", sprite="assets/sprites/materials/crystal_blue.png", color={0.25,0.65,1.0}, type="Crystal" },
    crystal_purple  = { name="Purple Crystal", sprite="assets/sprites/materials/crystal_purple.png", color={0.75,0.30,1.0}, type="Crystal" },
    crystal_orange  = { name="Orange Crystal", sprite="assets/sprites/materials/crystal_orange.png", color={1.0,0.55,0.18}, type="Crystal" },
    augment_attack  = { name="Atk Augment", sprite="assets/sprites/materials/augment_attack.png", color={1.0,0.30,0.25}, type="Augment" },
    augment_defense = { name="Def Augment", sprite="assets/sprites/materials/augment_defense.png", color={0.25,0.65,1.0}, type="Augment" },
    augment_speed   = { name="Spd Augment", sprite="assets/sprites/materials/augment_speed.png", color={0.25,1.0,0.55}, type="Augment" },
    augment_health  = { name="HP Augment", sprite="assets/sprites/materials/augment_health.png", color={1.0,0.25,0.45}, type="Augment" },
}

local BUILDINGS = {
    crystal_mine = {
        id="crystal_mine", name="Crystal Mine",
        sprite="assets/sprites/materials/crystal_mine.png",
        reward="crystal_random", rewardAmt=3, color={0.25,0.72,1.0},
    },
    augment_drill = {
        id="augment_drill", name="Augment Drill",
        sprite="assets/sprites/materials/augment_drill.png",
        reward="augment_random", rewardAmt=1, color={0.55,1.0,0.30},
    },
}

local function cancelTimers()
    for _, t in ipairs(TIMERS) do pcall(function() timer.cancel(t) end) end
    TIMERS = {}
end

local function isLeader(guild)
    return string.upper(tostring((guild and guild.role) or "")) == "LEADER"
end

local function fmtTime(seconds)
    if seconds <= 0 then return "READY" end
    local h = math.floor(seconds / 3600)
    local m = math.floor((seconds % 3600) / 60)
    if h > 0 then return tostring(h) .. "h " .. string.format("%02d", m) .. "m" end
    return tostring(m) .. "m " .. string.format("%02d", seconds % 60) .. "s"
end

local function rollCrystalReward()
    local roll = math.random()
    local acc = 0
    for _, entry in ipairs(CRYSTAL_ROLLS) do
        acc = acc + entry.chance
        if roll <= acc then return entry.key end
    end
    return CRYSTAL_ROLLS[#CRYSTAL_ROLLS].key
end

local function tryImg(parent, path, w, h)
    local ok, img = pcall(display.newImageRect, parent, path, w, h)
    return ok and img or nil
end

local function showRewardFailure()
    rewardPopup.show(scene.view, {
        title="COLLECT FAILED",
        key="jail",
        accent={1.0, 0.32, 0.28},
        message="COULD NOT SEND REWARD",
        detail="Try again after the guild sync catches up.",
        button="OK",
        noBurst=true,
    })
end

local function buildContent()
    cancelTimers()
    if contentGroup and contentGroup.removeSelf then contentGroup:removeSelf() end
    contentGroup = display.newGroup()
    scene.view:insert(contentGroup)
    if chromeGroup and chromeGroup.toFront then chromeGroup:toFront() end

    local m = shell.metrics()
    shell.drawFrame(contentGroup, m.CONTENT_X, m.CONTENT_Y, m.CONTENT_W, m.CONTENT_H)
    display.newText({
        parent=contentGroup, text="GUILD MINES",
        x=m.CONTENT_X, y=m.CONTENT_TOP + 15,
        font=ui.FONT_BOLD, fontSize=14
    }):setFillColor(0.62,0.88,1.0)
    display.newText({
        parent=contentGroup, text="Tap a slot to place a mine  -  12 hr cycles",
        x=m.CONTENT_X, y=m.CONTENT_TOP + 30,
        font=ui.FONT_BOLD, fontSize=7
    }):setFillColor(0.38,0.52,0.65)
    shell.divLine(contentGroup, m.CONTENT_X, m.CONTENT_TOP + 40, m.CONTENT_W - 24)

    local player = saveUtil.load()
    player.guildSlots = player.guildSlots or {}
    local leader = isLeader(activeGuild)
    local cols, rows, pad = 2, 3, 8
    local gridTop = m.CONTENT_TOP + 46
    local gridH = m.CONTENT_H - 58
    local cellW = (m.CONTENT_W - pad * (cols + 1)) / cols
    local cellH = (gridH - pad * (rows + 1)) / rows
    local splitGroup

    local function closeSplit()
        if splitGroup and splitGroup.removeSelf then splitGroup:removeSelf() end
        splitGroup = nil
    end

    local function refresh()
        closeSplit()
        buildContent()
    end

    for idx = 1, 6 do
        local col = (idx - 1) % cols
        local row = math.floor((idx - 1) / cols)
        local cx = m.CONTENT_X - m.CONTENT_W * 0.5 + pad + col * (cellW + pad) + cellW * 0.5
        local cy = gridTop + pad + row * (cellH + pad) + cellH * 0.5
        local slot = player.guildSlots[idx]
        local building = slot and BUILDINGS[slot.building]
        local left = slot and math.max(0, TWELVE_HOURS - (os.time() - (slot.startTime or os.time()))) or 0
        local ready = slot ~= nil and left <= 0

        local cell = display.newRoundedRect(contentGroup, cx, cy, cellW, cellH, 12)
        if ready then
            cell:setFillColor(0.04,0.22,0.10,0.97)
            cell.strokeWidth = 2
            cell:setStrokeColor(0.24,0.92,0.46,0.84)
        elseif building then
            cell:setFillColor(0.04,0.10,0.24,0.97)
            cell.strokeWidth = 1.6
            cell:setStrokeColor(building.color[1], building.color[2], building.color[3], 0.58)
        else
            cell:setFillColor(0.025,0.06,0.14,0.95)
            cell.strokeWidth = 1.5
            cell:setStrokeColor(0.14,0.32,0.24,0.50)
        end

        if slot and building then
            local sprSize = math.min(cellW - 18, cellH * 0.50)
            local spr = tryImg(contentGroup, building.sprite, sprSize, sprSize)
            if spr then
                spr.x = cx
                spr.y = cy - cellH * 0.16
            end

            display.newText({
                parent=contentGroup, text=building.name,
                x=cx, y=cy + cellH * 0.25,
                width=cellW - 10, font=ui.FONT_BOLD, fontSize=8, align="center"
            }):setFillColor(ready and 0.28 or 0.72, ready and 1.0 or 0.88, ready and 0.45 or 1.0)

            local barW = cellW - 18
            local barY = cy + cellH * 0.36
            local barBg = display.newRoundedRect(contentGroup, cx, barY, barW, 10, 4)
            barBg:setFillColor(0.04,0.05,0.12)
            barBg.strokeWidth = 1
            barBg:setStrokeColor(0.12,0.28,0.22,0.55)
            local fillRatio = math.min(1, 1 - (left / TWELVE_HOURS))
            if fillRatio > 0 then
                local fw = math.max((barW - 4) * fillRatio, 3)
                local fill = display.newRoundedRect(contentGroup, cx - (barW - 4) * 0.5 + fw * 0.5, barY, fw, 6, 3)
                fill:setFillColor(ready and 0.18 or 0.20, ready and 0.92 or 0.70, ready and 0.38 or 0.75)
            end
            local timerText = display.newText({
                parent=contentGroup, text=ready and "READY" or fmtTime(left),
                x=cx, y=barY, font=ui.FONT_BOLD, fontSize=6
            })
            timerText:setFillColor(ready and 0.28 or 0.45, ready and 1.0 or 0.70, ready and 0.45 or 0.45)
            if not ready then
                local capSlot = slot
                TIMERS[#TIMERS + 1] = timer.performWithDelay(1000, function()
                    if not timerText or not timerText.removeSelf then return end
                    local nextLeft = math.max(0, TWELVE_HOURS - (os.time() - (capSlot.startTime or os.time())))
                    timerText.text = nextLeft <= 0 and "READY" or fmtTime(nextLeft)
                    if nextLeft <= 0 then timerText:setFillColor(0.28,1.0,0.45) end
                end, 0)
            end

            display.newText({
                parent=contentGroup,
                text=ready and (leader and "TAP TO COLLECT" or "READY") or "RUNNING",
                x=cx, y=cy + cellH * 0.48 - 8,
                font=ui.FONT_BOLD, fontSize=6
            }):setFillColor(ready and 0.28 or 0.35, ready and 1.0 or 0.55, ready and 0.45 or 0.38)

            if leader then
                local remove = display.newCircle(contentGroup, cx + cellW * 0.5 - 12, cy - cellH * 0.5 + 12, 10)
                remove:setFillColor(0.32,0.04,0.04,0.95)
                remove.strokeWidth = 1.5
                remove:setStrokeColor(0.88,0.18,0.18,0.80)
                display.newText({ parent=contentGroup, text="X", x=remove.x, y=remove.y - 1, font=ui.FONT_BOLD, fontSize=9 }):setFillColor(1.0,0.30,0.30)
                remove:addEventListener("tap", function()
                    local p = saveUtil.load()
                    p.guildSlots = p.guildSlots or {}
                    p.guildSlots[idx] = nil
                    saveUtil.save(p)
                    sync.pushPlayerSnapshot(p)
                    refresh()
                    return true
                end)
            end

            cell:addEventListener("tap", function()
                if ready and leader and activeGuild and activeGuild.guildId then
                    local key = building.reward
                    if key == "augment_random" then key = AUGMENT_TYPES[math.random(#AUGMENT_TYPES)] end
                    if key == "crystal_random" then key = rollCrystalReward() end
                    local meta = LAND_REWARD_META[key] or { name=key, type="Material" }
                    api.guilds.collectLand(activeGuild.guildId, {
                        key=key, name=meta.name, sprite=meta.sprite,
                        color=meta.color, type=meta.type, qty=building.rewardAmt,
                    }, function(response)
                        if response and response.ok then
                            if response.data and response.data.player then
                                sync.applyPlayerSnapshot(response.data.player, saveUtil.activeSlot)
                            end
                            local p = saveUtil.load()
                            p.guildSlots = p.guildSlots or {}
                            p.guildSlots[idx] = { building=building.id, startTime=os.time() }
                            saveUtil.save(p)
                            sync.pushPlayerSnapshot(p)
                            refresh()
                            rewardPopup.show(scene.view, {
                                title="OBTAINED",
                                key=key,
                                icon=meta.sprite,
                                accent=meta.color or building.color,
                                message="OBTAINED " .. tostring(building.rewardAmt) .. " " .. string.upper(tostring(meta.name or key)),
                                detail="SENT TO GUILD VAULT",
                                button="COLLECT",
                            })
                        else
                            showRewardFailure()
                        end
                    end)
                end
                return true
            end)
        else
            if not leader then
                display.newText({
                    parent=contentGroup, text="LOCK",
                    x=cx, y=cy, font=ui.FONT_BOLD, fontSize=10
                }):setFillColor(0.40,0.48,0.60)
            else
                display.newText({
                    parent=contentGroup, text="+",
                    x=cx, y=cy, font=ui.FONT_BOLD, fontSize=30
                }):setFillColor(0.22,0.70,0.42)
                cell:addEventListener("tap", function()
                    closeSplit()
                    splitGroup = display.newGroup()
                    contentGroup:insert(splitGroup)
                    local halfH = cellH * 0.5 - 3
                    local choices = {
                        { y=cy - halfH * 0.5 - 2, building=BUILDINGS.crystal_mine },
                        { y=cy + halfH * 0.5 + 2, building=BUILDINGS.augment_drill },
                    }
                    for _, choice in ipairs(choices) do
                        local bg = display.newRoundedRect(splitGroup, cx, choice.y, cellW, halfH, 10)
                        bg:setFillColor(0.04,0.12,0.26,0.98)
                        bg.strokeWidth = 2
                        bg:setStrokeColor(choice.building.color[1], choice.building.color[2], choice.building.color[3], 0.82)
                        local spr = tryImg(splitGroup, choice.building.sprite, halfH - 12, halfH - 12)
                        if spr then
                            spr.x = cx - cellW * 0.22
                            spr.y = choice.y
                        end
                        display.newText({
                            parent=splitGroup, text=choice.building.name,
                            x=cx + cellW * 0.18, y=choice.y,
                            width=cellW * 0.50, font=ui.FONT_BOLD, fontSize=8, align="center"
                        }):setFillColor(choice.building.color[1], choice.building.color[2], choice.building.color[3])
                        bg:addEventListener("tap", function()
                            local p = saveUtil.load()
                            p.guildSlots = p.guildSlots or {}
                            p.guildSlots[idx] = { building=choice.building.id, startTime=os.time() }
                            saveUtil.save(p)
                            sync.pushPlayerSnapshot(p)
                            refresh()
                            return true
                        end)
                    end
                    return true
                end)
            end
        end
    end
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
        require("utils.guild_nav").build(chromeGroup, "HOME")
        buildContent()
    end)
end

function scene:hide(event)
    if event.phase ~= "will" then return end
    rewardPopup.closeActive(true)
    cancelTimers()
    if contentGroup and contentGroup.removeSelf then contentGroup:removeSelf() end
    contentGroup = nil
    if chromeGroup and chromeGroup.removeSelf then chromeGroup:removeSelf() end
    chromeGroup = nil
end

scene:addEventListener("create", scene)
scene:addEventListener("show", scene)
scene:addEventListener("hide", scene)

return scene
