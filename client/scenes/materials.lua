local composer  = require("composer")
local scene     = composer.newScene()

local saveUtil   = require("utils.save")
local ui         = require("utils.ui")
local radialMenu = require("utils.radial_menu")

-------------------------------------------------
-- CONFIG
-------------------------------------------------
local PRODUCE_INTERVAL = 5 * 60        -- 5 min testing  (change to 8*3600 for production)
local PRODUCE_AMOUNT   = 10
local BUILD_COST       = 300

-------------------------------------------------
-- MINE DEFINITIONS
-------------------------------------------------
local MINES = {
    { level=5,  name="Amorphous Mine",    material="scrap", icon="scrap", mine_icon="scrap_mine" },
    { level=10, name="Carbon Fiber Mine", material="coil",  icon="coil",  mine_icon="coil_mine"  },
    { level=15, name="Micro-chip Mine",   material="chip",  icon="chip",  mine_icon="chip_mine"  },
    { level=20, name="Amorphous Rig",     material="scrap", icon="scrap", mine_icon="scrap_mine" },
    { level=25, name="Carbon Fiber Rig",  material="coil",  icon="coil",  mine_icon="coil_mine"  },
    { level=30, name="Micro-chip Rig",    material="chip",  icon="chip",  mine_icon="chip_mine"  },
}

local MAT_DISPLAY = {
    { key="scrap", icon="scrap" },
    { key="coil",  icon="coil"  },
    { key="chip",  icon="chip"  },
}

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

-------------------------------------------------
-- LAYOUT
-------------------------------------------------
local SW       = display.actualContentWidth
local SH       = display.actualContentHeight
local CX       = display.contentCenterX
local CY       = display.contentCenterY
local HEADER_H    = 44
local MATBAR_H    = 52
local COLS        = 2
local ROWS        = 3
local PAD         = 8
local SAFE_BOTTOM = SH * 0.15 + 100    -- bottom 15% + 100px buffer for radial button
local GRID_AVAIL  = SH - HEADER_H - MATBAR_H - SAFE_BOTTOM
local SLOT_W      = (SW - PAD * (COLS + 1)) / COLS
local SLOT_H      = (GRID_AVAIL - PAD * (ROWS + 1)) / ROWS
local GRID_TOP    = HEADER_H + MATBAR_H + PAD

local C_BUILT   = { 0.05, 0.12, 0.26, 0.97 }
local C_EMPTY   = { 0.06, 0.07, 0.10, 0.97 }
local C_LOCKED  = { 0.04, 0.04, 0.06, 0.97 }
local C_STR_B   = { 0.20, 0.60, 1.00, 0.70 }
local C_STR_E   = { 0.20, 0.60, 1.00, 0.40 }
local C_STR_L   = { 0.22, 0.22, 0.30, 0.50 }
local C_GOLD    = { 1.00, 0.80, 0.20 }

-------------------------------------------------
-- STATE
-------------------------------------------------
local sceneGroupRef
local gridGroup
local matBarGroup
local tickTimer
local buildMatBar
local buildGrid

local function showRadial()
    radialMenu.show(sceneGroupRef, {
        activeScene = nil,
        inner       = RADIAL_INNER,
        outer       = RADIAL_OUTER,
    })
end

local function refreshScene()
    buildMatBar(sceneGroupRef)
    buildGrid(sceneGroupRef)
    showRadial()
end

-------------------------------------------------
-- HELPERS
-------------------------------------------------
local function tryImg(parent, path, w, h)
    local ok, img = pcall(display.newImageRect, parent, path, w, h)
    return (ok and img) or nil
end

local function ip(name)   -- icon path shorthand
    if name == "coil" then
        return "assets/sprites/more/large_coil.png"
    end
    return "assets/sprites/more/" .. name .. ".png"
end

local function ensureSave(p)
    p.materials         = p.materials or {}
    p.materials.scrap   = p.materials.scrap or 0
    p.materials.coil    = p.materials.coil  or 0
    p.materials.chip    = p.materials.chip  or 0
    p.mines             = p.mines or {}
    p.lastMineTime      = p.lastMineTime or 0
    -- track which mines have been collected this cycle
    p.mineCollected     = p.mineCollected or {}
    return p
end

local function cycleReady(p)
    return (os.time() - p.lastMineTime) >= PRODUCE_INTERVAL
end

-------------------------------------------------
-- MAT BAR
-------------------------------------------------
buildMatBar = function(sg)
    if matBarGroup then matBarGroup:removeSelf(); matBarGroup = nil end
    matBarGroup = display.newGroup()
    sg:insert(matBarGroup)

    local p    = ensureSave(saveUtil.load())
    local barY = HEADER_H + MATBAR_H * 0.5

    local barBg = display.newRect(matBarGroup, CX, barY, SW, MATBAR_H)
    barBg:setFillColor(0.03, 0.06, 0.16, 0.97)
    barBg.strokeWidth = 1
    barBg:setStrokeColor(0.15, 0.40, 0.85, 0.35)

    local colW = SW / #MAT_DISPLAY
    for i, mat in ipairs(MAT_DISPLAY) do
        local mx = (i - 0.5) * colW
        local ic = tryImg(matBarGroup, ip(mat.icon), 28, 28)
        if ic then ic.x = mx - 26; ic.y = barY end
        display.newText({
            parent=matBarGroup,
            text=tostring(p.materials[mat.key] or 0),
            x=mx + 4, y=barY,
            font=ui.FONT_BOLD, fontSize=15, align="left"
        }):setFillColor(1, 1, 1)
    end
end

-------------------------------------------------
-- GRID
-------------------------------------------------
buildGrid = function(sg)
    if gridGroup then gridGroup:removeSelf(); gridGroup = nil end
    gridGroup = display.newGroup()
    sg:insert(gridGroup)

    local p     = ensureSave(saveUtil.load())
    local ready = cycleReady(p)

    for i, mine in ipairs(MINES) do
        local col    = (i - 1) % COLS
        local row    = math.floor((i - 1) / COLS)
        local slotX  = PAD + col * (SLOT_W + PAD) + SLOT_W * 0.5
        local slotY  = GRID_TOP + row * (SLOT_H + PAD) + SLOT_H * 0.5
        local plevel = p.level or 1
        local locked = plevel < mine.level
        local built  = p.mines[i] == true
        -- already collected this cycle?
        local collected = p.mineCollected[i] == true

        local fill   = built and C_BUILT or (not locked and C_EMPTY or C_LOCKED)
        local stroke = built and C_STR_B or (not locked and C_STR_E  or C_STR_L )

        local bg = display.newRoundedRect(gridGroup, slotX, slotY, SLOT_W, SLOT_H, 10)
        bg:setFillColor(unpack(fill))
        bg.strokeWidth = 2
        bg:setStrokeColor(unpack(stroke))

        local iconSize = math.min(SLOT_W, SLOT_H) - 16

        -- ── LOCKED ──
        if locked then
            -- lock icon centered
            local lk = tryImg(gridGroup, ip("lock"), 32, 32)
            if lk then lk.x = slotX; lk.y = slotY - 10
            else
                local b = display.newRoundedRect(gridGroup, slotX, slotY-8, 24, 20, 4)
                b:setFillColor(0.28,0.28,0.36,0.9)
            end
            -- level number only
            display.newText({ parent=gridGroup, text="LVL "..mine.level,
                x=slotX, y=slotY+16, font=ui.FONT_BOLD, fontSize=13, align="center"
            }):setFillColor(unpack(C_GOLD))

        -- ── UNLOCKED, NOT BUILT ──
        elseif not built then
            -- ghost mine icon + gold cost, no name
            local ghost = tryImg(gridGroup, ip(mine.mine_icon), iconSize, iconSize)
            if ghost then ghost.x=slotX; ghost.y=slotY-8; ghost.alpha=0.22 end

            -- cost badge at bottom of slot
            local gIc = tryImg(gridGroup, ip("gold"), 14, 14)
            if gIc then gIc.x=slotX-22; gIc.y=slotY+SLOT_H*0.5-14 end
            display.newText({ parent=gridGroup, text=BUILD_COST.."g",
                x=slotX+6, y=slotY+SLOT_H*0.5-14,
                font=ui.FONT_BOLD, fontSize=12, align="left"
            }):setFillColor(unpack(C_GOLD))

            -- whole slot is the build button
            bg:addEventListener("tap", function()
                local pp = ensureSave(saveUtil.load())
                if (pp.gold or 0) < BUILD_COST then
                    bg:setFillColor(0.35,0.05,0.05,0.97)
                    timer.performWithDelay(600, function() bg:setFillColor(unpack(C_EMPTY)) end)
                    return true
                end
                pp.gold = pp.gold - BUILD_COST
                pp.mines[i] = true
                saveUtil.save(pp)
                refreshScene()
                return true
            end)

        -- ── BUILT ──
        else
            -- mine icon fills slot
            local mIc = tryImg(gridGroup, ip(mine.mine_icon), iconSize, iconSize)
            if mIc then mIc.x=slotX; mIc.y=slotY end

            if ready and not collected then
                -- blue tint when ready
                bg:setFillColor(0.05, 0.20, 0.55, 0.97)
                bg.strokeWidth=2; bg:setStrokeColor(0.3, 0.7, 1.0, 0.9)

                -- floating badge: sits above the mine image, bobs up and down
                local badgeSize = 66
                local badgeY    = slotY - SLOT_H * 0.28   -- above center, over the mine

                local badge = display.newRoundedRect(gridGroup, slotX, badgeY, badgeSize, badgeSize, 6)
                badge:setFillColor(1, 1, 1, 0.50)
                badge.strokeWidth = 0

                local badgeIc = tryImg(gridGroup, ip(mine.icon), 22, 22)
                if badgeIc then badgeIc.x = slotX; badgeIc.y = badgeY - 8 end

                local badgeTxt = display.newText({
                    parent=gridGroup, text="+"..PRODUCE_AMOUNT,
                    x=slotX, y=badgeY + 10,
                    font=ui.FONT_BOLD, fontSize=11, align="center"
                })
                badgeTxt:setFillColor(0.15, 0.95, 0.35)

                -- bob animation — no box, just icon + white text
                local bobGroup = display.newGroup()
                gridGroup:insert(bobGroup)
                badge:removeSelf()
                if badgeIc then badgeIc:removeSelf() end
                badgeTxt:removeSelf()

                -- material icon
                local bIc2 = tryImg(bobGroup, ip(mine.icon), 56, 56)
                if bIc2 then bIc2.x = 0; bIc2.y = -10 end

                -- shadow (slightly offset dark copy for readability)
                local shadow = display.newText({ parent=bobGroup, text="+"..PRODUCE_AMOUNT,
                    x=1, y=23, font=ui.FONT_BOLD, fontSize=15, align="center" })
                shadow:setFillColor(0, 0, 0, 0.6)

                -- white text on top
                local bTxt2 = display.newText({ parent=bobGroup, text="+"..PRODUCE_AMOUNT,
                    x=0, y=22, font=ui.FONT_BOLD, fontSize=15, align="center" })
                bTxt2:setFillColor(1, 1, 1)

                bobGroup.x = slotX
                bobGroup.y = badgeY

                local bobOffset = 6
                local bobTime   = 600
                local function doBob()
                    if not bobGroup.isVisible then return end
                    transition.to(bobGroup, { y=badgeY + bobOffset, time=bobTime,
                        transition=easing.inOutSine, onComplete=function()
                            if not bobGroup.isVisible then return end
                            transition.to(bobGroup, { y=badgeY, time=bobTime,
                                transition=easing.inOutSine, onComplete=doBob })
                        end })
                end
                doBob()

                -- whole slot tappable to collect
                local capI=i; local capMine=mine
                bg:addEventListener("tap", function()
                    local pp = ensureSave(saveUtil.load())
                    pp.materials[capMine.material] = (pp.materials[capMine.material] or 0) + PRODUCE_AMOUNT
                    pp.mineCollected[capI] = true
                    local allDone = true
                    for j, m in ipairs(MINES) do
                        if pp.mines[j] == true and not pp.mineCollected[j] then
                            allDone = false; break
                        end
                    end
                    if allDone then
                        pp.lastMineTime  = os.time()
                        pp.mineCollected = {}
                    end
                    saveUtil.save(pp)
                    refreshScene()
                    return true
                end)

            elseif collected then
                -- grey tint — collected, waiting for next cycle
                bg:setFillColor(0.15, 0.15, 0.18, 0.97)
                bg.strokeWidth=1; bg:setStrokeColor(0.30, 0.30, 0.35, 0.50)
            end
            -- no text — icon does all the work
        end
    end
end

-------------------------------------------------
-- SCENE CREATE
-------------------------------------------------
function scene:create(event)
    sceneGroupRef = self.view
    local sg = sceneGroupRef

    local bg = display.newRect(sg, CX, CY, SW, SH)
    bg:setFillColor(0.05, 0.06, 0.09)
    local bgImg = tryImg(sg, "assets/sprites/ui/bg_home_grid.png", SW, SH)
    if bgImg then bgImg.x=CX; bgImg.y=CY end

    local hdr = display.newRect(sg, CX, HEADER_H*0.5, SW, HEADER_H)
    hdr:setFillColor(0.02,0.05,0.14,0.97)
    hdr.strokeWidth=1; hdr:setStrokeColor(0.2,0.5,1,0.4)

    display.newText({ parent=sg, text="MATERIALS",
        x=CX, y=HEADER_H*0.5, font=ui.FONT_BOLD, fontSize=16
    }):setFillColor(0.3, 0.85, 1)
end

-------------------------------------------------
-- SCENE SHOW
-------------------------------------------------
function scene:show(event)
    if event.phase ~= "did" then return end

    refreshScene()

    -- refresh grid every 30s so READY appears without needing to re-enter
    tickTimer = timer.performWithDelay(30000, function()
        refreshScene()
    end, 0)
end

-------------------------------------------------
-- SCENE HIDE
-------------------------------------------------
function scene:hide(event)
    if event.phase ~= "will" then return end
    radialMenu.destroy()
    if tickTimer then timer.cancel(tickTimer); tickTimer = nil end
end

scene:addEventListener("create", scene)
scene:addEventListener("show",   scene)
scene:addEventListener("hide",   scene)

return scene
