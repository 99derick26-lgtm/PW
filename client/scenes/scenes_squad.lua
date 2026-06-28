local composer   = require("composer")
local scene      = composer.newScene()
local saveUtil   = require("utils.save")
local squadUtil  = require("utils.squad")
local enemyGen   = require("utils.enemy_generator")
local statsUtil  = require("utils.stats")
local ui         = require("utils.ui")
local radialMenu = require("utils.radial_menu")

local SW = display.actualContentWidth
local SH = display.actualContentHeight
local CX = display.contentCenterX
local CY = display.contentCenterY

local RADIAL_INNER = {
    { icon="fight",      label="Fight",      scene="scenes.arena"      },
    { icon="home",       label="Home",       scene="scenes.home"       },
    { icon="bag",        label="Bag",        scene="scenes.bag"        },
    { icon="shop",       label="Shop",       scene="scenes.shop"       },
}
local RADIAL_OUTER = {
    { icon="squad",      label="Squad",      scene="scenes.squad"      },
    { icon="tournament", label="Tournament", scene="scenes.tournament" },
    { icon="pet",        label="Pets",       scene="scenes.pets"       },
    { icon="skills",     label="Skills",     scene="scenes.skills"     },
}

-------------------------------------------------
-- STATE
-------------------------------------------------
local sceneRoot   = nil
local contentGrp  = nil
local activeTab   = "squad"   -- "squad" | "conquer"
local pendingTaxRates = {}

-------------------------------------------------
-- HELPERS
-------------------------------------------------
local function rebuild() end  -- forward

local function showToast(msg, isError)
    local bg = display.newRoundedRect(sceneRoot, CX, SH-110, SW-40, 36, 8)
    bg:setFillColor(isError and 0.65 or 0.07,
                    isError and 0.08 or 0.38,
                    isError and 0.08 or 0.14, 0.96)
    bg.strokeWidth = 1.5
    bg:setStrokeColor(isError and 0.9 or 0.20,
                      isError and 0.3 or 0.85,
                      isError and 0.3 or 0.35)
    local t = display.newText({
        parent=sceneRoot, text=msg,
        x=CX, y=SH-110, font=ui.FONT_BOLD, fontSize=13, align="center"
    })
    t:setFillColor(1,1,1)
    local function fade(o)
        transition.to(o, { delay=1800, alpha=0, time=350,
            onComplete=function() if o and o.removeSelf then o:removeSelf() end end })
    end
    fade(bg); fade(t)
end

-------------------------------------------------
-- TAX SLIDER POPUP
-------------------------------------------------
local function showTaxPopup(conquered)
    local popup = display.newGroup()
    sceneRoot:insert(popup)

    local dim = display.newRect(popup, CX, CY, SW, SH)
    dim:setFillColor(0,0,0,0.75)

    local panelW = SW - 40
    local panelH = 220
    local panel  = display.newRoundedRect(popup, CX, CY, panelW, panelH, 16)
    panel:setFillColor(0.03, 0.07, 0.20, 0.98)
    panel.strokeWidth = 2
    panel:setStrokeColor(0.28, 0.62, 1.00, 0.85)

    display.newText({
        parent=popup, text="Tax Rate — "..conquered.name,
        x=CX, y=CY - panelH*0.5 + 28,
        font=ui.FONT_BOLD, fontSize=16
    }):setFillColor(0.35, 0.85, 1.0)

    -- current rate display
    local rate    = conquered.taxRate or 0.10
    local rateText = display.newText({
        parent=popup, text=math.floor(rate*100).."%",
        x=CX, y=CY - 20,
        font=ui.FONT_BOLD, fontSize=28
    })
    rateText:setFillColor(1.0, 0.85, 0.2)

    display.newText({
        parent=popup, text="Higher tax = more gold, but conquered players\nare more likely to fight back and break free.",
        x=CX, y=CY + 20, width=panelW-40,
        font=ui.FONT_BOLD, fontSize=9, align="center"
    }):setFillColor(0.55, 0.65, 0.85)

    -- – / + buttons
    local function adjustRate(delta)
        rate = math.max(0, math.min(0.20, rate + delta))
        rateText.text = math.floor(rate*100).."%"
    end

    local minusBtn = display.newRoundedRect(popup, CX - 70, CY - 20, 44, 44, 8)
    minusBtn:setFillColor(0.06, 0.12, 0.30, 0.97)
    minusBtn.strokeWidth = 1.5
    minusBtn:setStrokeColor(0.3, 0.6, 1.0, 0.6)
    display.newText({ parent=popup, text="−", x=CX-70, y=CY-22,
        font=ui.FONT_BOLD, fontSize=22 })
    minusBtn:addEventListener("tap", function() adjustRate(-0.05); return true end)

    local plusBtn = display.newRoundedRect(popup, CX + 70, CY - 20, 44, 44, 8)
    plusBtn:setFillColor(0.06, 0.12, 0.30, 0.97)
    plusBtn.strokeWidth = 1.5
    plusBtn:setStrokeColor(0.3, 0.6, 1.0, 0.6)
    display.newText({ parent=popup, text="+", x=CX+70, y=CY-22,
        font=ui.FONT_BOLD, fontSize=22 })
    plusBtn:addEventListener("tap", function() adjustRate(0.05); return true end)

    -- SAVE
    local saveY = CY + panelH*0.5 - 32
    local saveBtn = display.newRoundedRect(popup, CX - 50, saveY, 120, 36, 9)
    saveBtn:setFillColor(0.04, 0.18, 0.46, 0.97)
    saveBtn.strokeWidth = 1.5
    saveBtn:setStrokeColor(0.28, 0.65, 1.0, 0.80)
    display.newText({ parent=popup, text="SAVE",
        x=CX-50, y=saveY, font=ui.FONT_BOLD, fontSize=14 })
    saveBtn:addEventListener("tap", function()
        local p = saveUtil.load()
        squadUtil.setTaxRate(p, conquered.name, rate)
        saveUtil.save(p)
        return ui.popupClose(popup, nil, { popup }, rebuild)
    end)

    -- LIBERATE
    local libBtn = display.newRoundedRect(popup, CX + 60, saveY, 120, 36, 9)
    libBtn:setFillColor(0.30, 0.06, 0.06, 0.97)
    libBtn.strokeWidth = 1.5
    libBtn:setStrokeColor(1.0, 0.20, 0.20, 0.70)
    display.newText({ parent=popup, text="LIBERATE",
        x=CX+60, y=saveY, font=ui.FONT_BOLD, fontSize=13 })
    libBtn:addEventListener("tap", function()
        local p = saveUtil.load()
        squadUtil.removeConquered(p, conquered.name)
        saveUtil.save(p)
        return ui.popupClose(popup, nil, { popup }, function()
            rebuild()
            showToast(conquered.name.." has been liberated.", false)
        end)
    end)

    dim:addEventListener("tap", function()
        return ui.popupClose(popup, nil, { popup })
    end)

    ui.popupOpen(nil, { popup })
end

-------------------------------------------------
-- SQUAD TAB — list of conquered players
-------------------------------------------------
local function buildSquadTab(group)
    local player = saveUtil.load()
    local sq     = player.squad or { conquered={} }

    local titleY = 65
    display.newText({
        parent=group, text="YOUR SQUAD",
        x=CX, y=titleY, font=ui.FONT_BOLD, fontSize=16
    }):setFillColor(0.35, 0.85, 1.0)

    -- passive income info
    display.newText({
        parent=group,
        text="Conquered players earn you taxed gold every 6 hours.",
        x=CX, y=titleY+20, width=SW-40,
        font=ui.FONT_BOLD, fontSize=9, align="center"
    }):setFillColor(0.45, 0.60, 0.85)

    local slots = squadUtil.maxConquered()
    local cardH = 72
    local cardW = SW - 32
    local startY = titleY + 50

    for i = 1, slots do
        local c   = sq.conquered[i]
        local cardY = startY + (i-1) * (cardH + 10)

        local card = display.newRoundedRect(group, CX, cardY, cardW, cardH, 10)
        if c then
            card:setFillColor(0.05, 0.12, 0.28, 0.95)
            card.strokeWidth = 1.5
            card:setStrokeColor(0.22, 0.55, 1.0, 0.70)

            -- portrait placeholder
            local portrait = display.newRoundedRect(group,
                CX - cardW*0.5 + 36, cardY, 52, 52, 6)
            portrait:setFillColor(0.08, 0.16, 0.35)
            portrait.strokeWidth = 1
            portrait:setStrokeColor(0.3, 0.6, 1.0, 0.5)

            local okP, pSpr = pcall(display.newImageRect, group,
                "assets/sprites/characters/"..c.visualId.."/portrait.png", 46, 46)
            if okP and pSpr then
                pSpr.x = CX - cardW*0.5 + 36
                pSpr.y = cardY
            end

            -- name + level
            display.newText({
                parent=group, text=c.name,
                x=CX - cardW*0.5 + 76, y=cardY - 14,
                font=ui.FONT_BOLD, fontSize=14, align="left"
            }):setFillColor(1, 1, 1)

            display.newText({
                parent=group, text="Lv."..c.level,
                x=CX - cardW*0.5 + 76, y=cardY + 4,
                font=ui.FONT_BOLD, fontSize=10, align="left"
            }):setFillColor(0.55, 0.80, 1.0)

            -- tax rate
            local taxPct = math.floor((c.taxRate or 0)*100)
            display.newText({
                parent=group, text="Tax: "..taxPct.."%",
                x=CX - cardW*0.5 + 76, y=cardY + 20,
                font=ui.FONT_BOLD, fontSize=9, align="left"
            }):setFillColor(1.0, 0.85, 0.2)

            -- MANAGE button
            local manageX = CX + cardW*0.5 - 46
            local manageBtn = display.newRoundedRect(group,
                manageX, cardY, 72, 32, 7)
            manageBtn:setFillColor(0.04, 0.16, 0.42, 0.97)
            manageBtn.strokeWidth = 1.5
            manageBtn:setStrokeColor(0.28, 0.62, 1.0, 0.75)
            display.newText({
                parent=group, text="MANAGE",
                x=manageX, y=cardY,
                font=ui.FONT_BOLD, fontSize=11
            })
            local capC = c
            manageBtn:addEventListener("tap", function()
                showTaxPopup(capC); return true
            end)

        else
            -- empty slot
            card:setFillColor(0.04, 0.06, 0.14, 0.80)
            card.strokeWidth = 1
            card:setStrokeColor(0.18, 0.22, 0.38, 0.55)
            display.newText({
                parent=group, text="Empty slot — conquer a player to fill",
                x=CX, y=cardY,
                font=ui.FONT_BOLD, fontSize=11, align="center"
            }):setFillColor(0.30, 0.35, 0.55)
        end
    end

    -- CONQUER TAB prompt if slots available
    if #sq.conquered < slots then
        local promptY = startY + slots * (cardH + 10) + 10
        local promptBtn = display.newRoundedRect(group, CX, promptY, cardW, 44, 10)
        promptBtn:setFillColor(0.04, 0.18, 0.46, 0.95)
        promptBtn.strokeWidth = 2
        promptBtn:setStrokeColor(0.28, 0.65, 1.0, 0.85)
        display.newText({
            parent=group, text="⚔  FIND TARGETS  →",
            x=CX, y=promptY, font=ui.FONT_BOLD, fontSize=14
        }):setFillColor(0.35, 0.85, 1.0)
        promptBtn:addEventListener("tap", function()
            activeTab = "conquer"
            rebuild()
            return true
        end)
    end
end

-------------------------------------------------
-- CONQUER TAB — list of AI targets to fight
-------------------------------------------------
local function buildSquadGridTab(group)
    local player = saveUtil.load()
    local sq     = player.squad or { conquered={} }

    local titleY = 65
    display.newText({
        parent=group, text="YOUR SQUAD",
        x=CX, y=titleY, font=ui.FONT_BOLD, fontSize=16
    }):setFillColor(0.35, 0.85, 1.0)

    display.newText({
        parent=group,
        text="Conquer 4 fighters in Arena. Set their tax here, then save when you are ready.",
        x=CX, y=titleY + 22, width=SW - 44,
        font=ui.FONT_BOLD, fontSize=9, align="center"
    }):setFillColor(0.45, 0.60, 0.85)

    local slots   = squadUtil.maxConquered()
    local cols    = 2
    local cardGap = 10
    local cardW   = (SW - 34 - cardGap) * 0.5
    local cardH   = 162
    local startX  = 17 + cardW * 0.5
    local startY  = titleY + 96

    for i = 1, slots do
        local conquered = sq.conquered[i]
        local row = math.floor((i - 1) / cols)
        local col = (i - 1) % cols
        local cardX = startX + col * (cardW + cardGap)
        local cardY = startY + row * (cardH + cardGap)

        local card = display.newRoundedRect(group, cardX, cardY, cardW, cardH, 12)
        card.strokeWidth = 1.5

        if conquered then
            card:setFillColor(0.05, 0.12, 0.28, 0.95)
            card:setStrokeColor(0.22, 0.55, 1.0, 0.70)

            local portrait = display.newRoundedRect(group, cardX, cardY - 34, 82, 82, 10)
            portrait:setFillColor(0.08, 0.16, 0.35)
            portrait.strokeWidth = 1
            portrait:setStrokeColor(0.3, 0.6, 1.0, 0.5)

            local okP, pSpr = pcall(display.newImageRect, group,
                "assets/sprites/characters/"..conquered.visualId.."/portrait.png", 72, 72)
            if okP and pSpr then
                pSpr.x = cardX
                pSpr.y = cardY - 34
            end

            display.newText({
                parent=group, text=conquered.name,
                x=cardX, y=cardY + 18,
                font=ui.FONT_BOLD, fontSize=13, align="center"
            }):setFillColor(1, 1, 1)

            display.newText({
                parent=group, text="LV."..conquered.level,
                x=cardX, y=cardY + 34,
                font=ui.FONT_BOLD, fontSize=9, align="center"
            }):setFillColor(0.55, 0.80, 1.0)

            local rate = pendingTaxRates[conquered.name] or conquered.taxRate or 0.10
            local taxText = display.newText({
                parent=group, text="TAX "..math.floor(rate * 100).."%",
                x=cardX, y=cardY + 54,
                font=ui.FONT_BOLD, fontSize=11, align="center"
            })
            taxText:setFillColor(1.0, 0.85, 0.2)

            local function adjustRate(delta)
                rate = math.max(0, math.min(0.20, rate + delta))
                pendingTaxRates[conquered.name] = rate
                taxText.text = "TAX "..math.floor(rate * 100).."%"
            end

            local minusX = cardX - 34
            local plusX  = cardX + 34
            local taxBtnY = cardY + 82

            local minusBtn = display.newRoundedRect(group, minusX, taxBtnY, 34, 26, 7)
            minusBtn:setFillColor(0.06, 0.12, 0.30, 0.97)
            minusBtn.strokeWidth = 1.5
            minusBtn:setStrokeColor(0.3, 0.6, 1.0, 0.6)
            display.newText({
                parent=group, text="-", x=minusX, y=taxBtnY - 1,
                font=ui.FONT_BOLD, fontSize=17
            }):setFillColor(1, 1, 1)
            minusBtn:addEventListener("tap", function()
                adjustRate(-0.05)
                return true
            end)

            local plusBtn = display.newRoundedRect(group, plusX, taxBtnY, 34, 26, 7)
            plusBtn:setFillColor(0.06, 0.12, 0.30, 0.97)
            plusBtn.strokeWidth = 1.5
            plusBtn:setStrokeColor(0.3, 0.6, 1.0, 0.6)
            display.newText({
                parent=group, text="+", x=plusX, y=taxBtnY - 1,
                font=ui.FONT_BOLD, fontSize=17
            }):setFillColor(1, 1, 1)
            plusBtn:addEventListener("tap", function()
                adjustRate(0.05)
                return true
            end)

            local freeBtnY = cardY + 112
            local freeBtn = display.newRoundedRect(group, cardX, freeBtnY, cardW - 26, 28, 8)
            freeBtn:setFillColor(0.30, 0.06, 0.06, 0.97)
            freeBtn.strokeWidth = 1.5
            freeBtn:setStrokeColor(1.0, 0.20, 0.20, 0.70)
            display.newText({
                parent=group, text="LIBERATE", x=cardX, y=freeBtnY,
                font=ui.FONT_BOLD, fontSize=11
            }):setFillColor(1, 1, 1)
            freeBtn:addEventListener("tap", function()
                local p = saveUtil.load()
                squadUtil.removeConquered(p, conquered.name)
                pendingTaxRates[conquered.name] = nil
                saveUtil.save(p)
                rebuild()
                showToast(conquered.name.." has been liberated.", false)
                return true
            end)
        else
            card:setFillColor(0.04, 0.06, 0.14, 0.80)
            card:setStrokeColor(0.18, 0.22, 0.38, 0.55)

            display.newText({
                parent=group, text="+",
                x=cardX, y=cardY - 16,
                font=ui.FONT_BOLD, fontSize=30
            }):setFillColor(0.22, 0.55, 1.0, 0.55)

            display.newText({
                parent=group, text="EMPTY SLOT",
                x=cardX, y=cardY + 18,
                font=ui.FONT_BOLD, fontSize=12, align="center"
            }):setFillColor(0.55, 0.68, 0.95)

            display.newText({
                parent=group,
                text="Conquer a player in Arena to fill this slot.",
                x=cardX, y=cardY + 48, width=cardW - 20,
                font=ui.FONT_BOLD, fontSize=8, align="center"
            }):setFillColor(0.30, 0.35, 0.55)
        end
    end

    local controlsY = startY + math.ceil(slots / cols) * (cardH + cardGap) + 8
    local saveBtn = display.newRoundedRect(group, CX, controlsY, SW - 34, 42, 10)
    saveBtn:setFillColor(0.04, 0.18, 0.46, 0.95)
    saveBtn.strokeWidth = 2
    saveBtn:setStrokeColor(0.28, 0.65, 1.0, 0.85)
    display.newText({
        parent=group, text="SAVE TAX RATES",
        x=CX, y=controlsY, font=ui.FONT_BOLD, fontSize=14
    }):setFillColor(0.35, 0.85, 1.0)
    saveBtn:addEventListener("tap", function()
        local p = saveUtil.load()
        local savedCount = 0
        for name, rate in pairs(pendingTaxRates) do
            if squadUtil.setTaxRate(p, name, rate) then
                savedCount = savedCount + 1
            end
        end
        saveUtil.save(p)
        pendingTaxRates = {}
        rebuild()
        showToast(savedCount > 0 and "Tax rates saved." or "No tax changes to save.", false)
        return true
    end)

end

local function buildConquerTab(group)
    local player  = saveUtil.load()
    local targets = squadUtil.getTargets(player)
    local energy  = player.energy or 0

    local titleY = 65
    display.newText({
        parent=group, text="CONQUEST TARGETS",
        x=CX, y=titleY, font=ui.FONT_BOLD, fontSize=16
    }):setFillColor(0.35, 0.85, 1.0)

    -- energy display
    display.newText({
        parent=group, text="⚡ Energy: "..energy,
        x=CX, y=titleY + 20,
        font=ui.FONT_BOLD, fontSize=11
    }):setFillColor(0.45, 0.90, 0.55)

    display.newText({
        parent=group,
        text="Win the fight to add them to your squad. Costs 1 energy.",
        x=CX, y=titleY + 36, width=SW-40,
        font=ui.FONT_BOLD, fontSize=9, align="center"
    }):setFillColor(0.45, 0.60, 0.85)

    if not squadUtil.canConquer(player) then
        display.newText({
            parent=group, text="Squad full! Liberate a member to conquer more.",
            x=CX, y=CY, width=SW-60,
            font=ui.FONT_BOLD, fontSize=13, align="center"
        }):setFillColor(1.0, 0.5, 0.2)
        return
    end

    local cardH  = 68
    local cardW  = SW - 32
    local startY = titleY + 60

    for i, target in ipairs(targets) do
        if i > 6 then break end  -- show max 6 targets
        local cardY = startY + (i-1) * (cardH + 8)

        local card = display.newRoundedRect(group, CX, cardY, cardW, cardH, 10)
        card:setFillColor(0.05, 0.10, 0.24, 0.95)
        card.strokeWidth = 1.5
        card:setStrokeColor(0.22, 0.50, 1.0, 0.60)

        -- portrait
        local okP, pSpr = pcall(display.newImageRect, group,
            "assets/sprites/characters/"..target.visualId.."/portrait.png", 44, 44)
        if okP and pSpr then
            pSpr.x = CX - cardW*0.5 + 30
            pSpr.y = cardY
        end

        -- name + level
        display.newText({
            parent=group, text=target.name,
            x=CX - cardW*0.5 + 66, y=cardY - 12,
            font=ui.FONT_BOLD, fontSize=14, align="left"
        }):setFillColor(1, 1, 1)

        display.newText({
            parent=group, text="Lv."..target.level.."  Power ~"..target.power,
            x=CX - cardW*0.5 + 66, y=cardY + 6,
            font=ui.FONT_BOLD, fontSize=9, align="left"
        }):setFillColor(0.55, 0.75, 1.0)

        -- CONQUER button
        local hasEnergy = energy > 0
        local btnX = CX + cardW*0.5 - 46
        local btn  = display.newRoundedRect(group, btnX, cardY, 72, 34, 8)
        btn:setFillColor(hasEnergy and 0.04 or 0.10,
                         hasEnergy and 0.18 or 0.10,
                         hasEnergy and 0.46 or 0.16, 0.97)
        btn.strokeWidth = 1.5
        btn:setStrokeColor(hasEnergy and 0.28 or 0.28,
                           hasEnergy and 0.68 or 0.28,
                           hasEnergy and 1.00 or 0.40, 0.85)
        display.newText({
            parent=group, text="CONQUER",
            x=btnX, y=cardY, font=ui.FONT_BOLD, fontSize=10
        }):setFillColor(hasEnergy and 1.0 or 0.45, 1.0, hasEnergy and 1.0 or 0.45)

        local capT = target
        btn:addEventListener("tap", function()
            if not hasEnergy then
                showToast("Not enough energy!", true); return true
            end
            -- deduct energy
            local p = saveUtil.load()
            p.energy = math.max(0, (p.energy or 1) - 1)
            saveUtil.save(p)

            -- send to arena_battle as a conquest fight
            local opponent = squadUtil.buildOpponent(capT, p.level)
            opponent.isConquest    = true
            opponent.conquestTarget = capT
            composer.setVariable("opponent", opponent)
            composer.gotoScene("scenes.arena_battle",
                { effect="slideLeft", time=220 })
            return true
        end)
    end
end

-------------------------------------------------
-- REBUILD
-------------------------------------------------
rebuild = function()
    if contentGrp then contentGrp:removeSelf(); contentGrp=nil end
    contentGrp = display.newGroup()
    sceneRoot:insert(contentGrp)

    local inner = display.newGroup()
    contentGrp:insert(inner)
    buildSquadGridTab(inner)
end

-------------------------------------------------
-- SCENE CREATE
-------------------------------------------------
function scene:create(event)
    local sg  = self.view
    sceneRoot = sg

    local okB, bg = pcall(display.newImage, "assets/sprites/ui/bg_home_grid.png")
    if okB and bg then
        local s = math.max(SW/bg.width, SH/bg.height)
        bg:scale(s,s); bg.x=CX; bg.y=CY; sg:insert(bg)
    end

    local dim = display.newRect(sg, CX, CY, SW, SH)
    dim:setFillColor(0,0,0,0.50)

    -- border
    local borderH = SH - 90
    local borderBorder = display.newRoundedRect(sg, CX, borderH*0.5, SW-8, borderH-8, 12)
    borderBorder:setFillColor(0,0,0,0)
    borderBorder.strokeWidth = 3
    borderBorder:setStrokeColor(0.20, 0.55, 1.00, 0.75)
    local inner2 = display.newRoundedRect(sg, CX, borderH*0.5, SW-14, borderH-14, 10)
    inner2:setFillColor(0,0,0,0)
    inner2.strokeWidth = 1
    inner2:setStrokeColor(0.35, 0.70, 1.00, 0.30)
end

-------------------------------------------------
-- SCENE SHOW
-------------------------------------------------
function scene:show(event)
    if event.phase ~= "did" then return end

    local player = saveUtil.load()

    -- check if returning from a conquest fight
    local conquestResult = composer.getVariable("conquestResult")
    if conquestResult then
        composer.setVariable("conquestResult", nil)
        if conquestResult.won and conquestResult.target then
            local p = saveUtil.load()
            local added = squadUtil.addConquered(p, conquestResult.target)
            if added then
                saveUtil.save(p)
                showToast(conquestResult.target.name.." has been conquered!", false)
            else
                showToast("Squad is full!", true)
            end
        elseif not conquestResult.won then
            showToast("You lost the conquest fight.", true)
        end
    end

    -- tick passive gold
    local gained, liberated = squadUtil.tick(player)
    if gained > 0 then
        saveUtil.save(player)
        showToast("+"..gained.."g from your squad!", false)
    end
    for _, name in ipairs(liberated) do
        showToast(name.." broke free from your squad!", true)
    end

    activeTab = "squad"
    pendingTaxRates = {}
    rebuild()

    radialMenu.show(self.view, {
        activeScene = "squad",
        inner       = RADIAL_INNER,
        outer       = RADIAL_OUTER,
    })
end

-------------------------------------------------
-- SCENE HIDE
-------------------------------------------------
function scene:hide(event)
    if event.phase ~= "will" then return end
    radialMenu.destroy()
end

scene:addEventListener("create", scene)
scene:addEventListener("show",   scene)
scene:addEventListener("hide",   scene)

return scene
