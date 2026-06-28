-- scenes/guild_league.lua
-- 8-member single-elimination bracket  |  tap a matchup to simulate the fight

local composer  = require("composer")
local scene     = composer.newScene()
local saveUtil  = require("utils.save")
local combat    = require("utils.combat")
local ui        = require("utils.ui")
local guildNav  = require("utils.guild_nav")

local SW = display.contentWidth
local SH = display.contentHeight
local CX = display.contentCenterX
local CY = display.contentCenterY
local BOTTOM_H   = guildNav.HEIGHT
local BOTTOM_Y   = guildNav.bottomY()
local HEADER_H   = 64
local HEADER_Y   = HEADER_H * 0.5
local CONTENT_TOP = HEADER_H + 2
local CONTENT_BOT = guildNav.contentBottom()
local CONTENT_H   = CONTENT_BOT - CONTENT_TOP

local FRAME_LARGE  = "assets/sprites/ui/frames/border_large.png"
local FRAME_SMALL  = "assets/sprites/ui/frames/border_small.png"
local FRAME_THIN_L = "assets/sprites/ui/frames/thin_large.png"
local FRAME_THIN_S = "assets/sprites/ui/frames/thin_small.png"

local function drawFrame(parent, x, y, w, h, path)
    local ok, img = pcall(display.newImageRect, parent, path, w, h)
    if ok and img then img.x=x; img.y=y; return img end
    local r = display.newRoundedRect(parent, x, y, w, h, 8)
    r:setFillColor(0.03,0.08,0.20,0.95)
    r.strokeWidth=1.5; r:setStrokeColor(0.18,0.65,0.42,0.70)
    return r
end

local BOTTOM_TABS = {
    { label="HOME",   scene="scenes.guild_home"   },
    { label="LEAGUE", scene="scenes.guild_league" },
    { label="WAR",    scene="scenes.guild_war"    },
    { label="LOOT",   scene="scenes.guild_loot"   },
}

-------------------------------------------------
-- BRACKET DATA
-- 8 participants — index 1 is always the player's guild member
-------------------------------------------------
local PARTICIPANTS = {
    { name="Chango",   level=14, atk=28, def=20, spd=18, hp=140, isPlayer=true  },
    { name="RavenX",   level=11, atk=22, def=16, spd=22, hp=110, isPlayer=false },
    { name="NullByte", level=9,  atk=18, def=14, spd=14, hp=90,  isPlayer=false },
    { name="Glitch77", level=7,  atk=14, def=12, spd=16, hp=70,  isPlayer=false },
    { name="IronClad", level=6,  atk=12, def=18, spd=10, hp=80,  isPlayer=false },
    { name="Vex",      level=8,  atk=16, def=10, spd=20, hp=80,  isPlayer=false },
    { name="Sable",    level=10, atk=20, def=12, spd=18, hp=100, isPlayer=false },
    { name="Bolt",     level=12, atk=24, def=14, spd=16, hp=120, isPlayer=false },
}

-- bracket state: rounds[round][matchIdx] = { p1=idx, p2=idx, winner=idx|nil }
-- round 1: 4 matches (QF), round 2: 2 matches (SF), round 3: 1 match (Final)
local bracketState = nil
local resultPopup  = nil

local function initBracket()
    -- shuffle participants for seeding
    local seeded = {}
    for i=1,#PARTICIPANTS do seeded[i]=i end
    -- keep player at seed 1
    bracketState = {
        [1] = {
            { p1=1, p2=8, winner=nil },
            { p1=2, p2=7, winner=nil },
            { p1=3, p2=6, winner=nil },
            { p1=4, p2=5, winner=nil },
        },
        [2] = {
            { p1=nil, p2=nil, winner=nil },
            { p1=nil, p2=nil, winner=nil },
        },
        [3] = {
            { p1=nil, p2=nil, winner=nil },
        },
    }
end

-------------------------------------------------
-- SIMULATE A FIGHT
-------------------------------------------------
local function simulateFight(pIdx, oIdx)
    local p = PARTICIPANTS[pIdx]
    local o = PARTICIPANTS[oIdx]

    local pEnt = { id="p1", level=p.level, attack=p.atk, defense=p.def, speed=p.spd, hp=p.hp, pets={}, petStats={} }
    local oEnt = { id="p2", level=o.level, attack=o.atk, defense=o.def, speed=o.spd, hp=o.hp, pets={}, petStats={} }

    -- simple simulation without combat.lua to avoid dependency issues
    math.randomseed(os.time())
    local pHp, oHp = p.hp, o.hp
    local turn = p.spd >= o.spd and "p" or "o"

    for _ = 1, 30 do
        if pHp <= 0 or oHp <= 0 then break end
        if turn == "p" then
            local dmg = math.max(1, math.floor(p.atk - o.def*0.5 + math.random(-3,3)))
            oHp = oHp - dmg; turn = "o"
        else
            local dmg = math.max(1, math.floor(o.atk - p.def*0.5 + math.random(-3,3)))
            pHp = pHp - dmg; turn = "p"
        end
    end

    return pHp > oHp and pIdx or oIdx, pHp, oHp
end

-------------------------------------------------
-- ADVANCE BRACKET
-------------------------------------------------
local function advanceBracket(round, matchIdx, winnerIdx)
    bracketState[round][matchIdx].winner = winnerIdx

    if round == 1 then
        local slot = math.ceil(matchIdx / 2)
        local pos  = matchIdx % 2 == 1 and "p1" or "p2"
        if not bracketState[2][slot] then bracketState[2][slot]={p1=nil,p2=nil,winner=nil} end
        bracketState[2][slot][pos] = winnerIdx
    elseif round == 2 then
        local pos = matchIdx == 1 and "p1" or "p2"
        bracketState[3][1][pos] = winnerIdx
    end
end

-------------------------------------------------
-- RESULT POPUP
-------------------------------------------------
local function closeResult()
    if resultPopup and resultPopup.removeSelf then resultPopup:removeSelf() end
    resultPopup = nil
end

local function showResult(sg, p1Idx, p2Idx, winnerIdx, p1Hp, p2Hp, onClose)
    closeResult()
    resultPopup = display.newGroup()
    sg:insert(resultPopup)

    local dim=display.newRect(resultPopup, CX, CY, SW, SH)
    dim:setFillColor(0,0,0,0.80); dim.isHitTestable=true

    local pw=SW-30; local ph=210
    local panel=display.newRoundedRect(resultPopup, CX, CY, pw, ph, 14)
    panel:setFillColor(0.03,0.08,0.20,0.98)
    panel.strokeWidth=2; panel:setStrokeColor(0.25,0.65,1.0,0.70)

    display.newText({ parent=resultPopup, text="FIGHT RESULT",
        x=CX, y=CY-ph*0.5+20, font=ui.FONT_BOLD, fontSize=14, align="center"
    }):setFillColor(0.35,0.85,1.0)

    local p1 = PARTICIPANTS[p1Idx]
    local p2 = PARTICIPANTS[p2Idx]
    local winner = PARTICIPANTS[winnerIdx]

    -- vs display
    local vsY=CY-20
    local p1Col = p1Idx==winnerIdx and {0.28,1.0,0.48} or {0.65,0.28,0.28}
    local p2Col = p2Idx==winnerIdx and {0.28,1.0,0.48} or {0.65,0.28,0.28}

    display.newText({ parent=resultPopup, text=p1.name,
        x=CX-70, y=vsY-16, font=ui.FONT_BOLD, fontSize=13, align="center"
    }):setFillColor(unpack(p1Col))
    display.newText({ parent=resultPopup, text="Lv."..p1.level,
        x=CX-70, y=vsY+2, font=ui.FONT_BOLD, fontSize=9, align="center"
    }):setFillColor(0.50,0.58,0.75)
    display.newText({ parent=resultPopup, text=math.max(0,math.floor(p1Hp)).." HP",
        x=CX-70, y=vsY+18, font=ui.FONT_BOLD, fontSize=9, align="center"
    }):setFillColor(unpack(p1Col))

    display.newText({ parent=resultPopup, text="VS",
        x=CX, y=vsY, font=ui.FONT_BOLD, fontSize=16, align="center"
    }):setFillColor(0.55,0.60,0.72)

    display.newText({ parent=resultPopup, text=p2.name,
        x=CX+70, y=vsY-16, font=ui.FONT_BOLD, fontSize=13, align="center"
    }):setFillColor(unpack(p2Col))
    display.newText({ parent=resultPopup, text="Lv."..p2.level,
        x=CX+70, y=vsY+2, font=ui.FONT_BOLD, fontSize=9, align="center"
    }):setFillColor(0.50,0.58,0.75)
    display.newText({ parent=resultPopup, text=math.max(0,math.floor(p2Hp)).." HP",
        x=CX+70, y=vsY+18, font=ui.FONT_BOLD, fontSize=9, align="center"
    }):setFillColor(unpack(p2Col))

    -- winner line
    display.newText({ parent=resultPopup,
        text="🏆  "..winner.name.." WINS",
        x=CX, y=CY+30, font=ui.FONT_BOLD, fontSize=15, align="center"
    }):setFillColor(1.0,0.82,0.20)

    -- OK button
    local okBtn=display.newRoundedRect(resultPopup, CX, CY+ph*0.5-28, 120, 34, 8)
    okBtn:setFillColor(0.04,0.18,0.42,0.97)
    okBtn.strokeWidth=1.5; okBtn:setStrokeColor(0.25,0.65,1.0,0.80)
    display.newText({ parent=resultPopup, text="CONTINUE",
        x=CX, y=CY+ph*0.5-28, font=ui.FONT_BOLD, fontSize=12
    }):setFillColor(0.75,0.90,1.0)
    okBtn:addEventListener("tap", function()
        closeResult(); if onClose then onClose() end; return true
    end)
end

-------------------------------------------------
-- BUILD BRACKET UI
-------------------------------------------------
local bracketGroup = nil

local function buildBracket(sg)
    if bracketGroup then bracketGroup:removeSelf(); bracketGroup=nil end
    bracketGroup = display.newGroup()
    sg:insert(bracketGroup)

    -- Layout: 3 rounds side by side
    -- QF (col 0), SF (col 1), Final (col 2)
    local ROUND_LABELS = { "QUARTER\nFINALS", "SEMI\nFINALS", "FINAL" }
    local COL_W    = (SW-20) / 3
    local SLOT_H   = 42
    local SLOT_PAD = 8
    local startY   = CONTENT_TOP + 22

    for r = 1, 3 do
        local matches = bracketState[r]
        local cx2 = 10 + (r-1)*COL_W + COL_W*0.5
        local nMatches = #matches

        -- round label
        display.newText({ parent=bracketGroup, text=ROUND_LABELS[r],
            x=cx2, y=startY-12, font=ui.FONT_BOLD, fontSize=7, align="center", width=COL_W-4
        }):setFillColor(0.35,0.65,0.85)

        -- vertical spacing for centering
        local totalH = nMatches*(SLOT_H*2+SLOT_PAD*2) + (nMatches-1)*12
        local blockStart = startY + (CONTENT_H - totalH)*0.5

        for m = 1, nMatches do
            local match = matches[m]
            local blockY = blockStart + (m-1)*(SLOT_H*2+SLOT_PAD*2+12)

            -- connector line between rounds
            if r < 3 then
                local lineX = cx2 + COL_W*0.5 - 2
                local lineY = blockY + SLOT_H + SLOT_PAD*0.5
                local ln=display.newRect(bracketGroup, lineX, lineY, 2, SLOT_H*2+SLOT_PAD*2)
                ln:setFillColor(0.18,0.45,0.32,0.40)
            end

            for slot = 1, 2 do
                local pIdx = slot==1 and match.p1 or match.p2
                local sy2  = blockY + (slot-1)*(SLOT_H+SLOT_PAD)
                local isWinner = match.winner and (match.winner == pIdx)
                local isLoser  = match.winner and (match.winner ~= pIdx) and pIdx

                -- slot bg
                local slotBg=display.newRoundedRect(bracketGroup, cx2, sy2+SLOT_H*0.5, COL_W-6, SLOT_H, 6)
                if isWinner then
                    slotBg:setFillColor(0.04,0.20,0.10,0.97)
                    slotBg.strokeWidth=1.5; slotBg:setStrokeColor(0.18,0.85,0.35,0.80)
                elseif isLoser then
                    slotBg:setFillColor(0.12,0.04,0.04,0.90)
                    slotBg.strokeWidth=1; slotBg:setStrokeColor(0.55,0.18,0.18,0.55)
                elseif pIdx then
                    slotBg:setFillColor(0.04,0.10,0.24,0.97)
                    slotBg.strokeWidth=1; slotBg:setStrokeColor(0.20,0.45,0.70,0.45)
                else
                    slotBg:setFillColor(0.02,0.04,0.10,0.80)
                    slotBg.strokeWidth=1; slotBg:setStrokeColor(0.10,0.18,0.18,0.30)
                end

                if pIdx then
                    local p = PARTICIPANTS[pIdx]
                    local nameC = isWinner and {0.28,1.0,0.48} or (isLoser and {0.65,0.28,0.28} or {0.80,0.88,1.0})
                    local nt=display.newText({ parent=bracketGroup, text=p.name,
                        x=cx2-4, y=sy2+SLOT_H*0.5-8,
                        font=ui.FONT_BOLD, fontSize=8, align="left", width=COL_W-16 })
                    nt:setFillColor(unpack(nameC)); nt.anchorX=0; nt.x=cx2-COL_W*0.5+6
                    local lvt=display.newText({ parent=bracketGroup, text="Lv."..p.level,
                        x=cx2-COL_W*0.5+6, y=sy2+SLOT_H*0.5+6,
                        font=ui.FONT_BOLD, fontSize=7, align="left" })
                    lvt:setFillColor(0.40,0.58,0.80); lvt.anchorX=0
                    if p.isPlayer then
                        display.newText({ parent=bracketGroup, text="⭐",
                            x=cx2+COL_W*0.5-10, y=sy2+SLOT_H*0.5,
                            font=ui.FONT_BOLD, fontSize=10 })
                    end
                    if isWinner then
                        display.newText({ parent=bracketGroup, text="W",
                            x=cx2+COL_W*0.5-8, y=sy2+SLOT_H*0.5,
                            font=ui.FONT_BOLD, fontSize=9 }):setFillColor(0.28,1.0,0.48)
                    end
                else
                    display.newText({ parent=bracketGroup, text="TBD",
                        x=cx2, y=sy2+SLOT_H*0.5,
                        font=ui.FONT_BOLD, fontSize=8, align="center"
                    }):setFillColor(0.25,0.30,0.38)
                end
            end

            -- FIGHT button (only if both participants set and no winner yet)
            if match.p1 and match.p2 and not match.winner then
                local fightY = blockY + SLOT_H + SLOT_PAD*0.5
                local capR=r; local capM=m; local capSg=sg

                local fb=display.newRoundedRect(bracketGroup, cx2, fightY, COL_W-10, 18, 4)
                fb:setFillColor(0.06,0.18,0.48,0.97)
                fb.strokeWidth=1.5; fb:setStrokeColor(0.28,0.65,1.0,0.85)
                local ft=display.newText({ parent=bracketGroup, text="FIGHT",
                    x=cx2, y=fightY, font=ui.FONT_BOLD, fontSize=7 })
                ft:setFillColor(0.55,0.85,1.0); ft.isHitTestable=false

                fb:addEventListener("tap", function()
                    local pm = bracketState[capR][capM]
                    local winnerIdx, p1Hp, p2Hp = simulateFight(pm.p1, pm.p2)
                    showResult(capSg, pm.p1, pm.p2, winnerIdx, p1Hp, p2Hp, function()
                        advanceBracket(capR, capM, winnerIdx)
                        buildBracket(capSg)
                    end)
                    return true
                end)
            end

            -- champion label for final winner
            if r==3 and matches[1].winner then
                local champ=PARTICIPANTS[matches[1].winner]
                local champY=blockY+SLOT_H*2+SLOT_PAD+14
                display.newText({ parent=bracketGroup,
                    text="🏆  CHAMPION",
                    x=cx2, y=champY, font=ui.FONT_BOLD, fontSize=9, align="center"
                }):setFillColor(1.0,0.82,0.20)
                display.newText({ parent=bracketGroup,
                    text=champ.name,
                    x=cx2, y=champY+14, font=ui.FONT_BOLD, fontSize=8, align="center"
                }):setFillColor(1.0,0.92,0.55)
            end
        end
    end

    -- RESET button
    local resetBtn=display.newRoundedRect(bracketGroup, CX, CONTENT_BOT-14, 110, 22, 6)
    resetBtn:setFillColor(0.04,0.12,0.28,0.97)
    resetBtn.strokeWidth=1.5; resetBtn:setStrokeColor(0.20,0.50,0.85,0.65)
    display.newText({ parent=bracketGroup, text="RESET BRACKET",
        x=CX, y=CONTENT_BOT-14, font=ui.FONT_BOLD, fontSize=7
    }):setFillColor(0.45,0.68,1.0)
    resetBtn:addEventListener("tap", function()
        initBracket(); buildBracket(sg); return true
    end)
end

-------------------------------------------------
-- BOTTOM BAR
-------------------------------------------------
local function buildBottomBar(sg, activeIdx)
    guildNav.build(sg, "LEAGUE")
end

-------------------------------------------------
-- SCENE CREATE
-------------------------------------------------
function scene:create(event)
    local sg = self.view

    local bg=display.newRect(sg, CX, CY, SW, SH); bg:setFillColor(0.02,0.03,0.08)
    for i=1,20 do
        local ln=display.newRect(sg, CX, i*(SH/20), SW, 1)
        ln:setFillColor(0.05,0.18,0.42,0.04); ln.isHitTestable=false
    end

    -- header
    drawFrame(sg, CX, HEADER_Y, SW-6, HEADER_H, FRAME_SMALL)
    display.newRect(sg, CX, HEADER_H, SW, 2):setFillColor(0.15,0.55,0.35,0.55)
    display.newText({ parent=sg, text="LEAGUE",
        x=CX-30, y=HEADER_Y, font=ui.FONT_BOLD, fontSize=20, align="center"
    }):setFillColor(0.25,0.95,0.58)
    display.newText({ parent=sg, text="1v1 Tournament  ·  Tap FIGHT to simulate",
        x=CX, y=HEADER_Y+18, font=ui.FONT_BOLD, fontSize=8, align="center"
    }):setFillColor(0.38,0.52,0.65)

    buildBottomBar(sg, 2)

    if not bracketState then initBracket() end
    buildBracket(sg)
end

-------------------------------------------------
-- SCENE HIDE
-------------------------------------------------
function scene:hide(event)
    if event.phase ~= "will" then return end
    closeResult()
end

scene:addEventListener("create", scene)
scene:addEventListener("hide",   scene)
return scene
