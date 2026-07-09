-- scenes/tournament.lua
-- Pixel War Online — Tournament Scene
-- Two modes:
--   Solo:  64-player bracket, you vs 63 AI opponents, instant sim
--   Team:  64-team bracket (teams of 5: you + up to 3 conquered + 1 random AI fill)

local composer   = require("composer")
local scene      = composer.newScene()
local saveUtil   = require("utils.save")
local squadUtil  = require("utils.squad")
local statsUtil  = require("utils.stats")
local combat     = require("utils.combat")
local petScaler  = require("utils.pet_scaler")
local spells     = require("utils.spells")
local api        = require("utils.api")
local sync       = require("utils.sync")
local ui         = require("utils.ui")
local radialMenu = require("utils.radial_menu")
local taskRewards = require("utils.task_rewards")

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
-- CONSTANTS
-------------------------------------------------
local ENTRY_COST  = 100    -- gold to enter a tournament
local SOLO_PRIZE  = { 1000, 500, 250, 100 }   -- 1st/2nd/3rd/4th gold prizes
local TEAM_PRIZE  = { 2500, 1200, 600, 250 }

-------------------------------------------------
-- STATE
-------------------------------------------------
local sceneRoot  = nil
local contentGrp = nil
local activeTab  = "single"
local tournamentStatus = nil
local function rebuild() end

local function ensureTournamentState(player)
    player.tournaments = player.tournaments or {}
    player.tournaments.single = player.tournaments.single or { joined=false, joinedAt=nil }
    player.tournaments.crew   = player.tournaments.crew   or { joined=false, joinedAt=nil }
end

-------------------------------------------------
-- AI NAME / VISUAL POOLS
-------------------------------------------------
local AI_NAMES = {
    "Vex","Kira","Doza","IronFist","Sable","Reckoner","Grindcore","Nyxara",
    "Bolt","Cipher","Raze","Flick","Torq","Null","Echo","Wraith",
    "Brix","Knux","Haze","Omen","Fade","Dart","Helm","Grak",
    "Lyra","Pix","Slip","Cinder","Volt","Amps","Fuse","Hex",
    "Zara","Slab","Weld","Rune","Sable2","Glitch","Thud","Crank",
    "Nyx","Dagger","Blaze","Specter","Ironwood","Runic","Arcane","Nova",
    "Pixel","Neon","Chrome","Virus","Static","Pulse","Axiom","Vector",
    "Phase","Quasar","Nexus","Zenith","Forge","Apex","Titan","Cipher2"
}
local AI_VISUALS = {
    "corp_enforcer","corp_enforcer_f","street_brawler","street_fighter",
    "street_fighter_f","street_punk","street_punk_f"
}

-------------------------------------------------
-- HELPERS
-------------------------------------------------
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
        transition.to(o, { delay=2000, alpha=0, time=350,
            onComplete=function() if o and o.removeSelf then o:removeSelf() end end })
    end
    fade(bg); fade(t)
end

local function processEnrollTask(player, message)
    return taskRewards.process(sceneRoot, player, {
        { id = "enroll_tournament", amount = 1, message = message or "You enrolled in a tournament." },
    }, function()
        rebuild()
    end)
end

local function applyTournamentResponse(response)
    if response and response.ok and response.data then
        tournamentStatus = response.data.tournaments or tournamentStatus
        if response.data.player then
            saveUtil.save(response.data.player)
        end
    end
end

local function applyTournamentStatusToPlayer(player, response)
    if response and response.ok and response.data then
        tournamentStatus = response.data.tournaments or tournamentStatus
        if response.data.player and response.data.player.tournaments then
            player.tournaments = response.data.player.tournaments
        end
    end
    saveUtil.save(player)
    sync.pushPlayerSnapshot(player)
end

local function getTournamentInfo(mode, localState)
    local info = tournamentStatus and tournamentStatus[mode]
    return {
        joined = info and info.joined or localState.joined,
        count = info and info.count or (localState.joined and 1 or 0),
        capacity = info and info.capacity or 64,
    }
end

local function levelBand(level)
    level = tonumber(level) or 1
    if level <= 10 then return "LV.1-10" end
    if level <= 20 then return "LV.10-20" end
    local startLevel = 21 + math.floor((level - 21) / 6) * 6
    return "LV." .. startLevel .. "-" .. (startLevel + 5)
end

local function drawHeaderBanner(parent, y, title, subtitle, levelText)
    local h = 50
    local glow = display.newRoundedRect(parent, CX, y, SW - 8, h + 6, 12)
    glow:setFillColor(0, 0, 0, 0)
    glow.strokeWidth = 2
    glow:setStrokeColor(0.12, 0.48, 1.0, 0.38)

    local hdr = display.newRoundedRect(parent, CX, y, SW - 12, h, 10)
    hdr:setFillColor(0.02, 0.06, 0.16, 0.96)
    hdr.strokeWidth = 1.5
    hdr:setStrokeColor(0.18, 0.38, 0.92, 0.48)

    local topLine = display.newRect(parent, CX, y - h * 0.5 + 6, SW - 24, 2)
    topLine:setFillColor(0.30, 0.66, 1.0, 0.62)

    local band = display.newRoundedRect(parent, 54, y, 76, 28, 7)
    band:setFillColor(0.06, 0.12, 0.28, 0.98)
    band.strokeWidth = 1.3
    band:setStrokeColor(0.28, 0.68, 1.0, 0.72)
    display.newText({ parent=parent, text=levelText, x=54, y=y, font=ui.FONT_BOLD, fontSize=9 })
        :setFillColor(0.78, 0.94, 1.0)

    local titleText = display.newText({
        parent=parent, text=title,
        x=104, y=y - 6, font=ui.FONT_BOLD, fontSize=18, align="left"
    })
    titleText.anchorX = 0
    titleText:setFillColor(0.40, 0.84, 1.0)

    local subText = display.newText({
        parent=parent, text=subtitle,
        x=104, y=y + 10, font=ui.FONT_BOLD, fontSize=8, align="left"
    })
    subText.anchorX = 0
    subText:setFillColor(0.42, 0.70, 1.0, 0.82)
end

local function portraitPath(visualId)
    return "assets/sprites/characters/" .. tostring(visualId or "street_brawler") .. "/portrait.png"
end

local function drawPortraitNode(parent, x, y, item, imageSize, textWidth)
    imageSize = imageSize or 46
    textWidth = textWidth or 74

    local okP, pic = pcall(display.newImageRect, parent, portraitPath(item.visualId), imageSize, imageSize)
    if okP and pic then
        pic.x = x
        pic.y = y
    end

    local name = display.newText({
        parent=parent, text=item.name or "Fighter",
        x=x, y=y + imageSize * 0.5 + 11, width=textWidth,
        font=ui.FONT_BOLD, fontSize=8, align="center"
    })
    name:setFillColor(0.92, 0.98, 1.0)
    return pic
end

local function sampleEntrants(player, mode)
    local visuals = AI_VISUALS
    local names = { player.name or "You", "NullVex", "GridShade", "ByteRift", "IronPulse", "ChromeHex", "Sable", "Kira" }
    local entrants = {}
    for i = 1, 7 do
        entrants[i] = {
            name = names[i + 1] or ("Fighter" .. i),
            visualId = visuals[((i - 1) % #visuals) + 1],
        }
    end
    entrants[8] = {
        name = mode == "crew" and "Your Squad" or (player.name or "You"),
        visualId = (player.appearance and player.appearance.skinId) or player.skinId or "street_brawler",
        isPlayer = true,
    }
    return entrants
end

local function buildBracketSample(player, mode)
    local entrants = sampleEntrants(player, mode)
    return {
        winner = entrants[8],
        finalists = { entrants[8], entrants[4] },
        semis = { entrants[8], entrants[7], entrants[4], entrants[3] },
    }
end

local function drawBracket(parent, player, mode, yTop)
    local data = buildBracketSample(player, mode)
    local lineColor = { 0.94, 0.97, 1.0, 0.88 }
    local lineW = 3

    local winnerY = yTop
    local finalsY = yTop + 92
    local semisY = yTop + 184

    local function snap(v)
        return math.floor(v + 0.5)
    end

    local winnerX = snap(CX)
    local finalsX = { snap(CX - 66), snap(CX + 66) }
    local semisX = { snap(CX - 126), snap(CX - 42), snap(CX + 42), snap(CX + 126) }

    local lineGroup = display.newGroup()
    parent:insert(lineGroup)

    local function segment(x1, y1, x2, y2)
        x1, y1, x2, y2 = snap(x1), snap(y1), snap(x2), snap(y2)
        if x1 == x2 then
            local top = math.min(y1, y2)
            local h = math.max(lineW, math.abs(y2 - y1) + lineW)
            local r = display.newRect(lineGroup, x1, top + h * 0.5, lineW, h)
            r:setFillColor(unpack(lineColor))
            return r
        end
        local left = math.min(x1, x2)
        local w = math.max(lineW, math.abs(x2 - x1) + lineW)
        local r = display.newRect(lineGroup, left + w * 0.5, y1, w, lineW)
        r:setFillColor(unpack(lineColor))
        return r
    end

    local function nodeTop(y, imageSize)
        return snap(y - imageSize * 0.5 - 7)
    end

    local function nodeBottom(y, imageSize)
        return snap(y + imageSize * 0.5 + 22)
    end

    local winnerBottom = nodeBottom(winnerY, 52)
    local finalsTop = nodeTop(finalsY, 48)
    local finalsBottom = nodeBottom(finalsY, 48)
    local semisTop = nodeTop(semisY, 46)

    local finalJunctionY = snap((winnerBottom + finalsTop) * 0.5)
    local semiJunctionY = snap((finalsBottom + semisTop) * 0.5)

    segment(winnerX, winnerBottom, winnerX, finalJunctionY)
    segment(finalsX[1], finalJunctionY, finalsX[2], finalJunctionY)
    for i = 1, 2 do
        segment(finalsX[i], finalJunctionY, finalsX[i], finalsTop)
    end

    for i = 1, 2 do
        local lx = finalsX[i]
        local left = semisX[(i - 1) * 2 + 1]
        local right = semisX[(i - 1) * 2 + 2]
        segment(lx, finalsBottom, lx, semiJunctionY)
        segment(left, semiJunctionY, right, semiJunctionY)
        segment(left, semiJunctionY, left, semisTop)
        segment(right, semiJunctionY, right, semisTop)
    end

    drawPortraitNode(parent, winnerX, winnerY, data.winner, 52, 90)

    for i = 1, 2 do
        drawPortraitNode(parent, finalsX[i], finalsY, data.finalists[i], 48, 78)
    end

    for i = 1, 4 do
        drawPortraitNode(parent, semisX[i], semisY, data.semis[i], 46, 68)
    end
end

local function getLastTournamentResult(player, mode)
    local t = player.tournaments or {}
    return t.lastResults and t.lastResults[mode]
end

local function recordTournamentResult(player, mode, result)
    player.tournaments = player.tournaments or {}
    player.tournaments.lastResults = player.tournaments.lastResults or {}
    player.tournaments.lastResults[mode] = result
    player.tournaments.champions = player.tournaments.champions or {}
    table.insert(player.tournaments.champions, 1, {
        name = result.winner or "Champion",
        visualId = result.winner == (player.name or "You")
            and ((player.appearance and player.appearance.skinId) or player.skinId or "street_brawler")
            or AI_VISUALS[math.random(#AI_VISUALS)],
        band = levelBand(player.level or 1),
        mode = mode,
    })
    while #player.tournaments.champions > 12 do
        table.remove(player.tournaments.champions)
    end
end

-- Generate a random AI combatant table for combat.runBattle
local function makeAICombatant(name, level, id)
    local base = 100 + level * 12
    return {
        id      = id or name,
        name    = name,
        level   = level,
        attack  = math.floor(base * 0.28),
        defense = math.floor(base * 0.22),
        speed   = math.floor(base * 0.20),
        hp      = math.floor(base * 1.30),
        pets    = {},
    }
end

-- Build player combatant from save
local function makePlayerCombatant(player)
    local s = statsUtil.calculate(player)
    return {
        id      = "player",
        name    = player.name or "You",
        level   = player.level or 1,
        attack  = s.attack,
        defense = s.defense,
        speed   = s.speed,
        hp      = s.hp,
        spells  = player.spells,
        pets    = spells.getEquippedPetsForBattle(player),
        petStats = (function()
            local out = {}
            for _, petId in ipairs(spells.getEquippedPetsForBattle(player)) do
                out[petId] = petScaler.scalePet(petId, s, petScaler.getAugments(player, petId))
            end
            return out
        end)(),
        equipped = player.equipped,
        currentWeaponIndex = player.currentWeaponIndex,
        weaponUsesLeft     = player.weaponUsesLeft,
    }
end

-- Simulate one fight: returns "a" or "b" as winner id
local function simFight(a, b)
    local result = combat.runBattle(a, b)
    return result.winner == "player" and a.id or b.id
end

-- Shuffle array in-place (Fisher-Yates)
local function shuffle(t)
    for i = #t, 2, -1 do
        local j = math.random(i)
        t[i], t[j] = t[j], t[i]
    end
end

-------------------------------------------------
-- RUN SOLO BRACKET
-- 64 players, single elimination, 6 rounds
-- Player is seeded in; rest are AI
-- Returns: { place=N, rounds={{winner,loser},...}, gold=X }
-------------------------------------------------
local function runSoloBracket(player)
    local level = player.level or 1

    -- build 64 combatants
    local combatants = {}
    local namePool = {}
    for _, n in ipairs(AI_NAMES) do table.insert(namePool, n) end
    shuffle(namePool)

    for i = 1, 63 do
        local aiLevel = math.max(1, level + math.random(-3, 4))
        local name    = namePool[i] or ("Bot"..i)
        table.insert(combatants, makeAICombatant(name, aiLevel, "ai_"..i))
    end

    -- inject player at a random seed position
    local playerCombatant = makePlayerCombatant(player)
    local playerSlot = math.random(64)
    table.insert(combatants, playerSlot, playerCombatant)
    -- trim to 64
    while #combatants > 64 do table.remove(combatants) end

    local rounds = {}
    local current = combatants
    local playerEliminated = false
    local playerPlace = 64

    while #current > 1 do
        local nextRound    = {}
        local roundResults = {}
        local i = 1
        while i <= #current do
            local a = current[i]
            local b = current[i+1] or current[1]  -- bye if odd
            local winnerId = simFight(a, b)
            local winner   = (winnerId == a.id) and a or b
            local loser    = (winnerId == a.id) and b or a

            table.insert(roundResults, { winner=winner.name, loser=loser.name })
            table.insert(nextRound, winner)

            -- track player
            if loser.id == "player" then
                playerEliminated = true
                playerPlace = #current  -- rough placement
            end

            i = i + 2
        end
        table.insert(rounds, roundResults)
        current = nextRound
        if playerEliminated then break end
    end

    -- if player survived to the end
    if not playerEliminated then
        playerPlace = 1
    end

    -- prize
    local gold = 0
    if     playerPlace == 1 then gold = SOLO_PRIZE[1]
    elseif playerPlace <= 2  then gold = SOLO_PRIZE[2]
    elseif playerPlace <= 4  then gold = SOLO_PRIZE[3]
    elseif playerPlace <= 8  then gold = SOLO_PRIZE[4]
    end

    return { place=playerPlace, rounds=rounds, gold=gold,
             winner=current[1] and current[1].name or "Unknown" }
end

-------------------------------------------------
-- RUN TEAM BRACKET
-- 64 teams of 5. Player's team = player + squad + AI fill.
-- Each team fight: sum of individual sim fights (3-of-5)
-------------------------------------------------
local function runTeamBracket(player)
    local level = player.level or 1

    -- build player's team
    local playerTeam = { makePlayerCombatant(player) }
    local sq = player.squad or { conquered={} }
    for _, c in ipairs(sq.conquered) do
        table.insert(playerTeam, makeAICombatant(c.name, c.level, "squad_"..c.name))
    end
    -- fill to 5 with random AI
    local fillIdx = 1
    while #playerTeam < 5 do
        table.insert(playerTeam, makeAICombatant("Ally"..fillIdx,
            math.max(1, level + math.random(-2,2)), "fill_"..fillIdx))
        fillIdx = fillIdx + 1
    end

    -- build 63 enemy teams
    local allTeams = { { name="YOUR SQUAD", members=playerTeam, isPlayer=true } }
    local namePool = {}
    for _, n in ipairs(AI_NAMES) do table.insert(namePool, n) end
    shuffle(namePool)

    for t = 1, 63 do
        local teamName = (namePool[t] or "Team"..t).."'s Squad"
        local members  = {}
        for m = 1, 5 do
            local aiLevel = math.max(1, level + math.random(-3, 4))
            table.insert(members, makeAICombatant(
                teamName.."_"..m, aiLevel, "team"..t.."_"..m))
        end
        table.insert(allTeams, { name=teamName, members=members, isPlayer=false })
    end

    shuffle(allTeams)

    -- team vs team: 3 of 5 fights
    local function simTeamFight(teamA, teamB)
        local winsA, winsB = 0, 0
        for m = 1, 5 do
            local a = teamA.members[m] or teamA.members[1]
            local b = teamB.members[m] or teamB.members[1]
            local wid = simFight(a, b)
            if wid == a.id then winsA=winsA+1 else winsB=winsB+1 end
        end
        return (winsA >= 3) and teamA or teamB
    end

    local current = allTeams
    local playerEliminated = false
    local playerPlace = 64
    local rounds = {}

    while #current > 1 do
        local nextRound    = {}
        local roundResults = {}
        local i = 1
        while i <= #current do
            local a = current[i]
            local b = current[i+1] or current[1]
            local winner = simTeamFight(a, b)
            local loser  = (winner == a) and b or a
            table.insert(roundResults, { winner=winner.name, loser=loser.name })
            table.insert(nextRound, winner)
            if loser.isPlayer then
                playerEliminated = true
                playerPlace = #current
            end
            i = i + 2
        end
        table.insert(rounds, roundResults)
        current = nextRound
        if playerEliminated then break end
    end

    if not playerEliminated then playerPlace = 1 end

    local gold = 0
    if     playerPlace == 1 then gold = TEAM_PRIZE[1]
    elseif playerPlace <= 2  then gold = TEAM_PRIZE[2]
    elseif playerPlace <= 4  then gold = TEAM_PRIZE[3]
    elseif playerPlace <= 8  then gold = TEAM_PRIZE[4]
    end

    return { place=playerPlace, rounds=rounds, gold=gold,
             winner=current[1] and current[1].name or "Unknown" }
end

-------------------------------------------------
-- RESULTS OVERLAY
-------------------------------------------------
local function showResults(result, mode)
    local popup = display.newGroup()
    sceneRoot:insert(popup)

    local dim = display.newRect(popup, CX, CY, SW, SH)
    dim:setFillColor(0,0,0,0.82)

    local panelW = SW - 24
    local panelH = SH - 120
    local panel  = display.newRoundedRect(popup, CX, CY, panelW, panelH, 16)
    panel:setFillColor(0.03, 0.07, 0.20, 0.98)
    panel.strokeWidth = 2
    panel:setStrokeColor(0.28, 0.65, 1.00, 0.85)

    -- place badge
    local placeColor = result.place == 1 and {1.0,0.85,0.2}
        or result.place <= 2 and {0.75,0.75,0.85}
        or result.place <= 4 and {0.85,0.55,0.25}
        or {0.5,0.6,0.7}

    local placeText = result.place == 1 and "🥇 CHAMPION"
        or result.place <= 2 and "🥈 2nd Place"
        or result.place <= 4 and "🥉 Top 4"
        or result.place <= 8 and "Top 8"
        or "Eliminated"

    local topY = CY - panelH*0.5 + 36
    display.newText({
        parent=popup, text=placeText,
        x=CX, y=topY, font=ui.FONT_BOLD, fontSize=22, align="center"
    }):setFillColor(unpack(placeColor))

    display.newText({
        parent=popup, text=(mode=="solo" and "64-Player Solo" or "64-Team Conquest"),
        x=CX, y=topY+28, font=ui.FONT_BOLD, fontSize=11, align="center"
    }):setFillColor(0.45, 0.65, 0.95)

    -- winner
    display.newText({
        parent=popup, text="🏆 Tournament Winner: "..result.winner,
        x=CX, y=topY+52, font=ui.FONT_BOLD, fontSize=11, align="center"
    }):setFillColor(1.0, 0.85, 0.2)

    -- gold prize
    if result.gold > 0 then
        display.newText({
            parent=popup, text="+"..result.gold.."g Prize!",
            x=CX, y=topY+76, font=ui.FONT_BOLD, fontSize=18, align="center"
        }):setFillColor(1.0, 0.88, 0.2)
    else
        display.newText({
            parent=popup, text="No prize — better luck next time.",
            x=CX, y=topY+76, font=ui.FONT_BOLD, fontSize=13, align="center"
        }):setFillColor(0.55, 0.60, 0.75)
    end

    -- round summary (last 4 rounds)
    local summaryY = topY + 108
    local showFrom = math.max(1, #result.rounds - 3)
    for r = showFrom, #result.rounds do
        local rnd = result.rounds[r]
        local roundLabel = "Round "..(r)
        if r == #result.rounds then roundLabel = "Final" end
        display.newText({
            parent=popup, text=roundLabel,
            x=CX, y=summaryY, font=ui.FONT_BOLD, fontSize=9
        }):setFillColor(0.40, 0.60, 1.0)
        summaryY = summaryY + 14
        local shown = 0
        for _, match in ipairs(rnd) do
            if shown < 3 then
                local isPlayerMatch = (match.winner == (saveUtil.load().name or "You"))
                    or (match.loser == (saveUtil.load().name or "You"))
                display.newText({
                    parent=popup,
                    text=match.winner.." def. "..match.loser,
                    x=CX, y=summaryY, font=ui.FONT_BOLD, fontSize=8, align="center"
                }):setFillColor(isPlayerMatch and 0.4 or 0.35,
                                isPlayerMatch and 1.0 or 0.50,
                                isPlayerMatch and 0.6 or 0.55)
                summaryY = summaryY + 12
                shown = shown + 1
            end
        end
        if #rnd > 3 then
            display.newText({
                parent=popup, text="...and "..(#rnd-3).." more matches",
                x=CX, y=summaryY, font=ui.FONT_BOLD, fontSize=7
            }):setFillColor(0.35, 0.40, 0.60)
            summaryY = summaryY + 12
        end
        summaryY = summaryY + 4
    end

    -- CLOSE button
    local closeY = CY + panelH*0.5 - 32
    local closeBtn = display.newRoundedRect(popup, CX, closeY, 160, 38, 9)
    closeBtn:setFillColor(0.04, 0.16, 0.42, 0.97)
    closeBtn.strokeWidth = 1.5
    closeBtn:setStrokeColor(0.28, 0.65, 1.0, 0.80)
    display.newText({ parent=popup, text="CLOSE",
        x=CX, y=closeY, font=ui.FONT_BOLD, fontSize=14 })
    closeBtn:addEventListener("tap", function()
        return ui.popupClose(popup, nil, { popup })
    end)

    dim:addEventListener("tap", function()
        return ui.popupClose(popup, nil, { popup })
    end)

    ui.popupOpen(nil, { popup })
end

-------------------------------------------------
-- SOLO TAB
-------------------------------------------------
local function buildSoloTab(group)
    local player = saveUtil.load()

    display.newText({
        parent=group, text="64-PLAYER SOLO BRACKET",
        x=CX, y=80, font=ui.FONT_BOLD, fontSize=16
    }):setFillColor(0.35, 0.85, 1.0)

    display.newText({
        parent=group,
        text="You vs 63 opponents.\nSingle elimination. Instant results.",
        x=CX, y=112, width=SW-50, font=ui.FONT_BOLD, fontSize=11, align="center"
    }):setFillColor(0.50, 0.65, 0.90)

    -- prize table
    local prizeY = 150
    display.newText({ parent=group, text="PRIZES",
        x=CX, y=prizeY, font=ui.FONT_BOLD, fontSize=11
    }):setFillColor(1.0, 0.85, 0.2)
    local prizes = {
        {"🥇 1st",  SOLO_PRIZE[1].."g"},
        {"🥈 2nd",  SOLO_PRIZE[2].."g"},
        {"🥉 3rd–4th", SOLO_PRIZE[3].."g"},
        {"Top 8",   SOLO_PRIZE[4].."g"},
    }
    for i, p in ipairs(prizes) do
        local py = prizeY + i * 18
        display.newText({ parent=group, text=p[1],
            x=CX-50, y=py, font=ui.FONT_BOLD, fontSize=10, align="right"
        }):setFillColor(0.75, 0.80, 1.0)
        display.newText({ parent=group, text=p[2],
            x=CX+50, y=py, font=ui.FONT_BOLD, fontSize=10, align="left"
        }):setFillColor(1.0, 0.85, 0.2)
    end

    -- entry cost
    local canAfford = (player.gold or 0) >= ENTRY_COST
    local enterY    = prizeY + 5 * 18 + 28
    display.newText({
        parent=group, text="Entry: "..ENTRY_COST.."g   Your gold: "..(player.gold or 0).."g",
        x=CX, y=enterY, font=ui.FONT_BOLD, fontSize=10
    }):setFillColor(canAfford and 1.0 or 0.80,
                    canAfford and 0.85 or 0.35,
                    canAfford and 0.2  or 0.25)

    local btnY  = enterY + 40
    local btn   = display.newRoundedRect(group, CX, btnY, 200, 46, 12)
    btn:setFillColor(canAfford and 0.04 or 0.10,
                     canAfford and 0.18 or 0.10,
                     canAfford and 0.46 or 0.20, 0.97)
    btn.strokeWidth = 2
    btn:setStrokeColor(canAfford and 0.28 or 0.28,
                       canAfford and 0.68 or 0.28,
                       canAfford and 1.00 or 0.40, 0.88)
    display.newText({ parent=group, text="ENTER TOURNAMENT",
        x=CX, y=btnY, font=ui.FONT_BOLD, fontSize=14
    }):setFillColor(canAfford and 1.0 or 0.45,
                    canAfford and 1.0 or 0.45,
                    canAfford and 1.0 or 0.45)

    btn:addEventListener("tap", function()
        if not canAfford then
            showToast("Need "..ENTRY_COST.."g to enter!", true); return true
        end
        local p = saveUtil.load()
        p.gold  = (p.gold or 0) - ENTRY_COST
        saveUtil.save(p)
        local result = runSoloBracket(p)
        if result.gold > 0 then
            p.gold = (p.gold or 0) + result.gold
            saveUtil.save(p)
        end
        showResults(result, "solo")
        return true
    end)
end

-------------------------------------------------
-- TEAM TAB
-------------------------------------------------
local function buildTeamTab(group)
    local player = saveUtil.load()
    local sq     = player.squad or { conquered={} }
    local squadSize = 1 + #sq.conquered  -- player + conquered

    display.newText({
        parent=group, text="64-TEAM CONQUEST",
        x=CX, y=80, font=ui.FONT_BOLD, fontSize=16
    }):setFillColor(0.35, 0.85, 1.0)

    display.newText({
        parent=group,
        text="Teams of 5. Your squad fights as one unit.\nAI fills empty slots automatically.",
        x=CX, y=112, width=SW-50, font=ui.FONT_BOLD, fontSize=11, align="center"
    }):setFillColor(0.50, 0.65, 0.90)

    -- squad preview
    local sqY = 145
    display.newText({ parent=group, text="YOUR TEAM  ("..squadSize.."/5)",
        x=CX, y=sqY, font=ui.FONT_BOLD, fontSize=11
    }):setFillColor(1.0, 0.85, 0.2)

    local members = { player.name or "You" }
    for _, c in ipairs(sq.conquered) do table.insert(members, c.name) end
    while #members < 5 do table.insert(members, "AI Ally") end

    for i, name in ipairs(members) do
        local isReal = i <= squadSize
        display.newText({
            parent=group, text=(i<=squadSize and "👤 " or "🤖 ")..name,
            x=CX, y=sqY + i*16, font=ui.FONT_BOLD, fontSize=10, align="center"
        }):setFillColor(isReal and 0.4 or 0.35,
                        isReal and 1.0 or 0.55,
                        isReal and 0.6 or 0.60)
    end

    -- prizes
    local prizeY = sqY + 5*16 + 14
    display.newText({ parent=group, text="PRIZES",
        x=CX, y=prizeY, font=ui.FONT_BOLD, fontSize=11
    }):setFillColor(1.0, 0.85, 0.2)
    local prizes = {
        {"🥇 1st",    TEAM_PRIZE[1].."g"},
        {"🥈 2nd",    TEAM_PRIZE[2].."g"},
        {"🥉 3rd–4th",TEAM_PRIZE[3].."g"},
        {"Top 8",     TEAM_PRIZE[4].."g"},
    }
    for i, p in ipairs(prizes) do
        local py = prizeY + i*18
        display.newText({ parent=group, text=p[1],
            x=CX-50, y=py, font=ui.FONT_BOLD, fontSize=10, align="right"
        }):setFillColor(0.75, 0.80, 1.0)
        display.newText({ parent=group, text=p[2],
            x=CX+50, y=py, font=ui.FONT_BOLD, fontSize=10, align="left"
        }):setFillColor(1.0, 0.85, 0.2)
    end

    local canAfford = (player.gold or 0) >= ENTRY_COST
    local enterY    = prizeY + 5*18 + 20
    display.newText({
        parent=group, text="Entry: "..ENTRY_COST.."g",
        x=CX, y=enterY, font=ui.FONT_BOLD, fontSize=10
    }):setFillColor(canAfford and 1.0 or 0.80,
                    canAfford and 0.85 or 0.35,
                    canAfford and 0.2  or 0.25)

    local btnY = enterY + 38
    local btn  = display.newRoundedRect(group, CX, btnY, 200, 46, 12)
    btn:setFillColor(canAfford and 0.04 or 0.10,
                     canAfford and 0.18 or 0.10,
                     canAfford and 0.46 or 0.20, 0.97)
    btn.strokeWidth = 2
    btn:setStrokeColor(canAfford and 0.28 or 0.28,
                       canAfford and 0.68 or 0.28,
                       canAfford and 1.00 or 0.40, 0.88)
    display.newText({ parent=group, text="ENTER TOURNAMENT",
        x=CX, y=btnY, font=ui.FONT_BOLD, fontSize=14
    }):setFillColor(canAfford and 1.0 or 0.45,
                    canAfford and 1.0 or 0.45,
                    canAfford and 1.0 or 0.45)

    btn:addEventListener("tap", function()
        if not canAfford then
            showToast("Need "..ENTRY_COST.."g to enter!", true); return true
        end
        local p = saveUtil.load()
        p.gold  = (p.gold or 0) - ENTRY_COST
        saveUtil.save(p)
        local result = runTeamBracket(p)
        if result.gold > 0 then
            p.gold = (p.gold or 0) + result.gold
            saveUtil.save(p)
        end
        showResults(result, "team")
        return true
    end)
end

local function makeNavButton(parent, x, y, label, onTap)
    local btnW, btnH = 126, 33
    local ok, btn = pcall(display.newImageRect, parent, "assets/sprites/ui/btn_nav.png", btnW, btnH)
    if ok and btn then
        btn.x, btn.y = x, y
    else
        btn = display.newRoundedRect(parent, x, y, btnW, btnH, 7)
        btn:setFillColor(0.04, 0.11, 0.26, 0.96)
        btn.strokeWidth = 1.4
        btn:setStrokeColor(0.24, 0.68, 1.0, 0.82)
    end
    local txt = display.newText({
        parent=parent, text=label,
        x=x, y=y, font=ui.FONT_BOLD, fontSize=12, align="center"
    })
    txt:setFillColor(0.88, 0.98, 1.0)
    btn:addEventListener("tap", function()
        if onTap then onTap() end
        return true
    end)
    return btn
end

local function showResultsList(mode)
    local player = saveUtil.load()
    local result = getLastTournamentResult(player, mode)

    local popup = display.newGroup()
    sceneRoot:insert(popup)

    local dim = display.newRect(popup, CX, CY, SW, SH)
    dim:setFillColor(0, 0, 0, 0.80)

    local panelW, panelH = SW - 28, SH - 130
    local panel = display.newRoundedRect(popup, CX, CY, panelW, panelH, 12)
    panel:setFillColor(0.02, 0.06, 0.16, 0.98)
    panel.strokeWidth = 2
    panel:setStrokeColor(0.20, 0.62, 1.0, 0.86)

    local topY = CY - panelH * 0.5 + 34
    display.newText({
        parent=popup, text="RESULTS",
        x=CX, y=topY, font=ui.FONT_BOLD, fontSize=20
    }):setFillColor(0.38, 0.86, 1.0)

    local y = topY + 36
    if not result then
        display.newText({
            parent=popup, text="No tournament battles recorded yet.",
            x=CX, y=y + 40, width=panelW - 34,
            font=ui.FONT_BOLD, fontSize=12, align="center"
        }):setFillColor(0.62, 0.74, 0.98)
    else
        local playerName = mode == "crew" and "YOUR SQUAD" or (player.name or "You")
        display.newText({
            parent=popup,
            text="PLACE " .. tostring(result.place or "?") .. "  |  WINNER " .. tostring(result.winner or "Unknown"),
            x=CX, y=y, width=panelW - 28,
            font=ui.FONT_BOLD, fontSize=10, align="center"
        }):setFillColor(1.0, 0.86, 0.22)
        y = y + 26

        local shown = 0
        for r, round in ipairs(result.rounds or {}) do
            for _, match in ipairs(round) do
                if match.winner == playerName or match.loser == playerName then
                    shown = shown + 1
                    local won = match.winner == playerName
                    local row = display.newRoundedRect(popup, CX, y, panelW - 28, 34, 6)
                    row:setFillColor(0.04, 0.10, 0.25, 0.96)
                    row.strokeWidth = 1
                    row:setStrokeColor(0.18, 0.48, 0.86, 0.62)
                    display.newText({
                        parent=popup,
                        text="ROUND " .. r .. "  " .. (won and "WIN" or "LOSS"),
                        x=CX - 110, y=y, font=ui.FONT_BOLD, fontSize=9
                    }):setFillColor(won and 0.42 or 1.0, won and 1.0 or 0.34, won and 0.62 or 0.34)
                    display.newText({
                        parent=popup,
                        text=tostring(match.winner) .. " def. " .. tostring(match.loser),
                        x=CX + 36, y=y, width=panelW - 160,
                        font=ui.FONT_BOLD, fontSize=8, align="left"
                    }):setFillColor(0.88, 0.94, 1.0)
                    y = y + 40
                end
            end
        end

        if shown == 0 then
            display.newText({
                parent=popup, text="No personal fights were found in this result.",
                x=CX, y=y + 24, width=panelW - 34,
                font=ui.FONT_BOLD, fontSize=11, align="center"
            }):setFillColor(0.62, 0.74, 0.98)
        end
    end

    makeNavButton(popup, CX, CY + panelH * 0.5 - 30, "CLOSE", function()
        ui.popupClose(popup, nil, { popup })
    end)

    dim:addEventListener("tap", function()
        ui.popupClose(popup, nil, { popup })
        return true
    end)
    ui.popupOpen(nil, { popup })
end

local function showChampionsList()
    local player = saveUtil.load()
    local champions = (player.tournaments and player.tournaments.champions) or {}

    local popup = display.newGroup()
    sceneRoot:insert(popup)

    local dim = display.newRect(popup, CX, CY, SW, SH)
    dim:setFillColor(0, 0, 0, 0.80)

    local panelW, panelH = SW - 28, SH - 130
    local panel = display.newRoundedRect(popup, CX, CY, panelW, panelH, 12)
    panel:setFillColor(0.02, 0.06, 0.16, 0.98)
    panel.strokeWidth = 2
    panel:setStrokeColor(0.20, 0.62, 1.0, 0.86)

    local topY = CY - panelH * 0.5 + 34
    display.newText({
        parent=popup, text="CHAMPIONS",
        x=CX, y=topY, font=ui.FONT_BOLD, fontSize=20
    }):setFillColor(0.38, 0.86, 1.0)

    if #champions == 0 then
        display.newText({
            parent=popup, text="No champions recorded yet.",
            x=CX, y=topY + 80, width=panelW - 34,
            font=ui.FONT_BOLD, fontSize=12, align="center"
        }):setFillColor(0.62, 0.74, 0.98)
    else
        local cardW, cardH = (panelW - 44) * 0.5, 58
        local startY = topY + 50
        for i = 1, math.min(12, #champions) do
            local c = champions[i]
            local col = ((i - 1) % 2)
            local row = math.floor((i - 1) / 2)
            local x = CX - cardW * 0.5 - 6 + col * (cardW + 12)
            local y = startY + row * 62

            local card = display.newRoundedRect(popup, x, y, cardW, cardH, 7)
            card:setFillColor(0.04, 0.10, 0.25, 0.96)
            card.strokeWidth = 1
            card:setStrokeColor(0.18, 0.48, 0.86, 0.62)

            local okP, pic = pcall(display.newImageRect, popup, portraitPath(c.visualId), 34, 34)
            if okP and pic then
                pic.x, pic.y = x - cardW * 0.5 + 24, y
            end

            local name = display.newText({
                parent=popup, text=tostring(c.name or "Champion"),
                x=x - cardW * 0.5 + 48, y=y - 8, width=cardW - 56,
                font=ui.FONT_BOLD, fontSize=8, align="left"
            })
            name.anchorX = 0
            name:setFillColor(0.94, 0.98, 1.0)

            local band = display.newText({
                parent=popup, text=tostring(c.band or ""),
                x=x - cardW * 0.5 + 48, y=y + 10, width=cardW - 56,
                font=ui.FONT_BOLD, fontSize=8, align="left"
            })
            band.anchorX = 0
            band:setFillColor(1.0, 0.86, 0.22)
        end
    end

    makeNavButton(popup, CX, CY + panelH * 0.5 - 30, "CLOSE", function()
        ui.popupClose(popup, nil, { popup })
    end)

    dim:addEventListener("tap", function()
        ui.popupClose(popup, nil, { popup })
        return true
    end)
    ui.popupOpen(nil, { popup })
end

local function toggleQueue(mode, live)
    local player = saveUtil.load()
    ensureTournamentState(player)
    local localState = player.tournaments[mode] or { joined=false }
    local nextJoined = not live.joined

    localState.joined = nextJoined
    localState.joinedAt = nextJoined and os.time() or nil
    player.tournaments[mode] = localState

    if nextJoined then
        processEnrollTask(player, "You enrolled in a tournament.")
    end

    api.tournaments.setJoined(mode, nextJoined, function(response)
        if response and response.ok then
            applyTournamentStatusToPlayer(player, response)
        else
            saveUtil.save(player)
            sync.pushPlayerSnapshot(player)
        end
        rebuild()
    end)
end

local function buildTournamentTab(group, mode)
    local player = saveUtil.load()
    ensureTournamentState(player)

    local modeName = mode == "crew" and "SQUADS" or "SINGLE"
    local countLabel = mode == "crew" and "SQUADS" or "PLAYERS"
    local localState = player.tournaments[mode] or { joined=false }
    local live = getTournamentInfo(mode, localState)

    drawHeaderBanner(group, 92, "TOURNAMENTS", modeName .. " BRACKET", levelBand(player.level or 1))

    local status = (live.joined and "QUEUED" or "NOT JOINED") ..
        "  " .. countLabel .. " " .. tostring(live.count or 0) .. "/" .. tostring(live.capacity or 64)
    display.newText({
        parent=group, text=status,
        x=CX, y=136, width=SW - 30,
        font=ui.FONT_BOLD, fontSize=10, align="center"
    }):setFillColor(live.joined and 0.36 or 0.66, live.joined and 1.0 or 0.72, live.joined and 0.58 or 0.92)

    makeNavButton(group, CX, 166, live.joined and "LEAVE QUEUE" or "JOIN QUEUE", function()
        toggleQueue(mode, live)
    end)

    drawBracket(group, player, mode, 258)

    local bottomY = SH - 178
    makeNavButton(group, CX - 74, bottomY, "RESULTS", function()
        showResultsList(mode)
    end)
    makeNavButton(group, CX + 74, bottomY, "CHAMPIONS", function()
        showChampionsList()
    end)
end

-------------------------------------------------
-- REBUILD
-------------------------------------------------

rebuild = function()
    if contentGrp then contentGrp:removeSelf(); contentGrp=nil end
    contentGrp = display.newGroup()
    sceneRoot:insert(contentGrp)

    -- tab bar
    local tabY = 32
    local tabs = { {key="single",label="SINGLE"}, {key="crew",label="SQUADS"} }
    local tabW = (SW - 30) / #tabs

    for i, t in ipairs(tabs) do
        local x        = 12 + (i-1)*tabW + tabW*0.5
        local isActive = (t.key == activeTab)
        local bg = display.newRoundedRect(contentGrp, x, tabY, tabW-6, 36, 8)
        bg:setFillColor(isActive and 0.05 or 0.03,
                        isActive and 0.14 or 0.06,
                        isActive and 0.38 or 0.15, 0.97)
        bg.strokeWidth = isActive and 2 or 1
        bg:setStrokeColor(isActive and 0.28 or 0.20,
                          isActive and 0.68 or 0.28,
                          isActive and 1.00 or 0.45,
                          isActive and 0.90 or 0.45)
        display.newText({
            parent=contentGrp, text=t.label,
            x=x, y=tabY, font=ui.FONT_BOLD, fontSize=13
        }):setFillColor(isActive and 0.35 or 0.45,
                        isActive and 0.85 or 0.55,
                        isActive and 1.00 or 0.70)
        local capKey = t.key
        bg:addEventListener("tap", function()
            activeTab = capKey; rebuild(); return true
        end)
    end

    local inner = display.newGroup()
    contentGrp:insert(inner)

    buildTournamentTab(inner, activeTab)
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
    dim:setFillColor(0,0,0,0.52)

    -- border
    local borderH = SH - 90
    local border  = display.newRoundedRect(sg, CX, borderH*0.5, SW-8, borderH-8, 12)
    border:setFillColor(0,0,0,0)
    border.strokeWidth = 3
    border:setStrokeColor(0.20, 0.55, 1.00, 0.75)
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
    rebuild()
    api.tournaments.status(function(response)
        applyTournamentResponse(response)
        rebuild()
    end)
    radialMenu.show(self.view, {
        activeScene = "tournament",
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
