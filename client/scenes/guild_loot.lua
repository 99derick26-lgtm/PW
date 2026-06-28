-- scenes/guild_loot.lua
local composer  = require("composer")
local scene     = composer.newScene()
local saveUtil  = require("utils.save")
local api       = require("utils.api")
local sync      = require("utils.sync")
local ui        = require("utils.ui")
local itemDefs  = require("utils.items")
local guildNav  = require("utils.guild_nav")
local guildContext = require("utils.guild_context")

local SW = display.contentWidth
local SH = display.contentHeight
local CX = display.contentCenterX
local CY = display.contentCenterY
local BOTTOM_H   = guildNav.HEIGHT
local BOTTOM_Y   = guildNav.bottomY()
local HEADER_H   = 72
local HEADER_Y   = HEADER_H * 0.5
local CONTENT_TOP = HEADER_H + 2
local CONTENT_BOT = guildNav.contentBottom()
local CONTENT_H   = CONTENT_BOT - CONTENT_TOP

local FRAME_LARGE  = "assets/sprites/ui/frames/border_large.png"
local FRAME_SMALL  = "assets/sprites/ui/frames/border_small.png"
local FRAME_THIN_L = "assets/sprites/ui/frames/thin_large.png"
local FRAME_THIN_S = "assets/sprites/ui/frames/thin_small.png"

-------------------------------------------------
-- RANKS
-------------------------------------------------
local RANKS = { "LEADER", "GENERAL", "COLONEL", "CAPTAIN", "MEMBER" }
local RANK_LIMITS = { LEADER=1, GENERAL=4, COLONEL=10, CAPTAIN=15, MEMBER=999 }
local RANK_COLORS = {
    LEADER  = {1.0,0.78,0.10},
    GENERAL = {1.0,0.40,0.20},
    COLONEL = {0.35,0.75,1.0},
    CAPTAIN = {0.55,1.0,0.65},
    MEMBER  = {0.50,0.52,0.62},
}

local function rankValue(r)
    for i,v in ipairs(RANKS) do if v==r then return i end end
    return 99
end

local AUCTION_DEFAULT_PRICES = {
    gem = 1500,
    gems = 1500,
    crystal_green = 2000,
    crystal_blue = 2500,
    crystal_orange = 3000,
    crystal_purple = 3500,
}

local function getAuctionDefaultPrice(item)
    if not item then return 100 end
    if item.auctionPrice and item.auctionPrice > 0 then
        return item.auctionPrice
    end
    if item.price and item.price > 0 then
        return item.price
    end
    return AUCTION_DEFAULT_PRICES[item.key] or 100
end

local function isGuildLootableItem(def)
    return def and (tonumber(def.auctionPrice) or 0) > 1000
end

-- VAULT DEFS
-------------------------------------------------
local VAULT_DEFS = {
    { key="crystal_green",   name="Green Crystal",  sprite="assets/sprites/materials/crystal_green.png",   color={0.35,1.0,0.45},   type="Crystal", price=2000 },
    { key="crystal_blue",    name="Blue Crystal",   sprite="assets/sprites/materials/crystal_blue.png",    color={0.25,0.65,1.0},  type="Crystal", price=2500 },
    { key="crystal_orange",  name="Orange Crystal", sprite="assets/sprites/materials/crystal_orange.png",  color={1.0,0.55,0.18},  type="Crystal", price=3000 },
    { key="crystal_purple",  name="Purple Crystal", sprite="assets/sprites/materials/crystal_purple.png",  color={0.75,0.30,1.0},  type="Crystal", price=3500 },
    { key="augment_attack",  name="Atk Augment",    sprite="assets/sprites/materials/augment_attack.png",  color={1.0,0.30,0.25},  type="Augment" },
    { key="augment_defense", name="Def Augment",    sprite="assets/sprites/materials/augment_defense.png", color={0.25,0.65,1.0},  type="Augment" },
    { key="augment_speed",   name="Spd Augment",    sprite="assets/sprites/materials/augment_speed.png",   color={0.25,1.0,0.55},  type="Augment" },
    { key="augment_health",  name="HP Augment",     sprite="assets/sprites/materials/augment_health.png",  color={1.0,0.25,0.45},  type="Augment" },
    { key="scrap",           name="Amorphous",      sprite="assets/sprites/more/scrap.png",               color={0.80,0.70,0.50},  type="Material" },
    { key="coil",            name="Carbon Fiber",   sprite="assets/sprites/more/large_coil.png",          color={0.50,0.85,1.0},  type="Material" },
    { key="chip",            name="Micro-chips",    sprite="assets/sprites/more/chip.png",                color={0.40,1.0,0.60},  type="Material" },
}

-------------------------------------------------
-- BOTTOM TABS
-------------------------------------------------
local BOTTOM_TABS = {
    { label="HOME",   scene="scenes.guild_home"   },
    { label="LEAGUE", scene="scenes.guild_league" },
    { label="WAR",    scene="scenes.guild_war"    },
    { label="VAULT",  scene="scenes.guild_loot"   },
}

-------------------------------------------------
-- STATE
-------------------------------------------------
local activeTab     = 1
local gridGroup     = nil
local popup         = nil
local popupCleanup  = nil
local actionGroup   = nil
local sceneGroupRef = nil
local refreshingOnline = false
local serverEconomy = nil
local buildLootTabs = nil
local buildInventoryDonateDetail = nil

local function getCurrentGuild()
    local player = saveUtil.load()
    return guildContext.getActiveGuild(player)
end

local function getCurrentGuildId()
    local guild = getCurrentGuild()
    return guild and guild.guildId or nil
end

local function applyServerEconomy(economy)
    if not economy then return end
    serverEconomy = economy
end

local function pushPlayerSnapshot(player)
    api.player.update(player or saveUtil.load(), function() end)
end

local function refreshLootView()
    if not sceneGroupRef then return end
    activeTab = 1
    buildLootTabs(sceneGroupRef)
    buildGrid(sceneGroupRef, activeTab)
end

local function refreshServerState(sg, onDone)
    if refreshingOnline then
        if onDone then onDone(false) end
        return
    end
    refreshingOnline = true
    local guildId = getCurrentGuildId()
    api.player.me(function(response)
        if response.ok and response.data and response.data.player then
            sync.applyPlayerSnapshot(response.data.player, saveUtil.activeSlot)
        end
        if not guildId then
            refreshingOnline = false
            if sg then buildGrid(sg, activeTab) end
            if onDone then onDone(response.ok) end
            return
        end
        api.guilds.vault(guildId, function(vaultResponse)
            refreshingOnline = false
            if vaultResponse.ok and vaultResponse.data and vaultResponse.data.economy then
                applyServerEconomy(vaultResponse.data.economy)
            end
            if sg then buildGrid(sg, activeTab) end
            if onDone then onDone(vaultResponse.ok) end
        end)
    end)
end

-------------------------------------------------
-- HELPERS
-------------------------------------------------
local function closePopup()
    if popupCleanup then
        pcall(popupCleanup)
        popupCleanup = nil
    end
    if popup and popup.removeSelf then popup:removeSelf() end
    popup = nil
end

local function tryImg(parent, path, w, h)
    local ok, img = pcall(display.newImageRect, parent, path, w, h)
    return (ok and img) or nil
end

local function drawFrame(parent, x, y, w, h, path)
    local ok, img = pcall(display.newImageRect, parent, path, w, h)
    if ok and img then img.x=x; img.y=y; return img end
    local r = display.newRoundedRect(parent, x, y, w, h, 8)
    r:setFillColor(0.03,0.08,0.20,0.95)
    r.strokeWidth=1.5; r:setStrokeColor(0.18,0.65,0.42,0.70)
    return r
end

local function getPlayerRank()
    local p = saveUtil.load()
    local guild = getCurrentGuild()
    if guild and guild.role then return string.upper(guild.role) end
    return string.upper(p.guildRank or "MEMBER")
end

local function getPlayerName(p)
    return p.name or p.displayName or "Player"
end

local function isDonateResourceType(typeName)
    return typeName == "Material"
        or typeName == "Crystal"
        or typeName == "Augment"
        or typeName == "material"
end

local function isLeader()
    return getPlayerRank() == "LEADER"
end

local function recordContribution(p, item, amount)
    p.guildContributions = p.guildContributions or {}
    local name = getPlayerName(p)
    local row = p.guildContributions[name] or {
        name=name,
        rank=string.upper(p.guildRank or "MEMBER"),
        items={},
        itemCount=0,
        gold=0,
        total=0,
    }
    row.rank = string.upper(p.guildRank or row.rank or "MEMBER")
    row.items = row.items or {}
    row.items[item.key] = (row.items[item.key] or 0) + amount
    if item.key == "gold" then
        row.gold = (row.gold or 0) + amount
    else
        row.itemCount = (row.itemCount or 0) + amount
    end
    row.total = (row.itemCount or 0) + (row.gold or 0)
    row.lastAt = os.date("%m/%d/%Y %I:%M %p")
    p.guildContributions[name] = row
end

local function donateItemToVault(item, amount, onDone)
    local guildId = getCurrentGuildId()
    if guildId then
        local payload = {
            key=item.key, name=item.name, sprite=item.sprite,
            color=item.color, type=item.type, qty=amount or 1,
        }

        local function runDonate()
            api.guilds.donate(guildId, payload, function(response)
                if response.ok and response.data then
                    applyServerEconomy(response.data.economy)
                    if response.data.player then
                        sync.applyPlayerSnapshot(response.data.player, saveUtil.activeSlot)
                    end
                    closePopup()
                    refreshLootView()
                end
                if onDone then onDone(response.ok, response) end
            end)
        end

        api.player.update(saveUtil.load(), function(syncResponse)
            if syncResponse and syncResponse.ok and syncResponse.data and syncResponse.data.player then
                sync.applyPlayerSnapshot(syncResponse.data.player, saveUtil.activeSlot)
            end
            runDonate()
        end)
        return true
    end

    local pp = saveUtil.load()
    amount = amount or 1
    pp.guildVault = pp.guildVault or {}
    pp.materials  = pp.materials  or {}
    pp.inventory  = pp.inventory  or {}

    if isDonateResourceType(item.type) then
        if (pp.materials[item.key] or 0) < amount then return false end
        pp.materials[item.key] = pp.materials[item.key] - amount
        pp.guildVault[item.key] = (pp.guildVault[item.key] or 0) + amount
    elseif item.type == "gold" then
        if (pp.gold or 0) < amount then return false end
        pp.gold = pp.gold - amount
        pp.guildVault.gold = (pp.guildVault.gold or 0) + amount
    else
        local removed = 0
        for idx = #pp.inventory, 1, -1 do
            if pp.inventory[idx] == item.key then
                table.remove(pp.inventory, idx)
                removed = removed + 1
                if removed >= amount then break end
            end
        end
        if removed < amount then return false end
        pp.guildVault[item.key] = (pp.guildVault[item.key] or 0) + amount
    end

    recordContribution(pp, item, amount)
    saveUtil.save(pp)
    pushPlayerSnapshot(pp)
    closePopup()
    refreshLootView()
    if onDone then onDone(true, { ok=true, localOnly=true }) end
    return true
end

-------------------------------------------------
-- BOTTOM BAR
-------------------------------------------------
local function buildBottomBar(sg, activeIdx)
    guildNav.build(sg, "VAULT")
end

-------------------------------------------------
-- DONATE POPUP
-------------------------------------------------
local function buildDonatePopup(sg)
    closePopup()
    popup = display.newGroup(); sg:insert(popup)

    local dim = display.newRect(popup, CX, CY, SW, SH)
    dim:setFillColor(0,0,0,0.80); dim.isHitTestable=true
    dim:addEventListener("touch", function(e)
        if e.phase == "began" then
            closePopup()
        end
        return true
    end)

    local pw = SW-20; local ph = SH*0.75
    local panel = display.newRoundedRect(popup, CX, CY, pw, ph, 14)
    panel:setFillColor(0.03,0.07,0.18,0.98)
    panel.strokeWidth=2; panel:setStrokeColor(0.25,0.75,1.0,0.70)
    panel:addEventListener("touch", function() return true end)

    display.newText({ parent=popup, text="// DONATE TO GUILD",
        x=CX, y=CY-ph*0.5+18, font=ui.FONT_BOLD, fontSize=14
    }):setFillColor(0.30,0.90,1.0)

    local hline = display.newRect(popup, CX, CY-ph*0.5+32, pw-10, 1)
    hline:setFillColor(0.25,0.75,1.0,0.35)

    local xb = display.newCircle(popup, CX+pw*0.5-16, CY-ph*0.5+16, 12)
    xb:setFillColor(0.28,0.04,0.04,0.97); xb.strokeWidth=1.5
    xb:setStrokeColor(0.85,0.18,0.18,0.80)
    display.newText({ parent=popup, text="✕", x=xb.x, y=xb.y-1,
        font=ui.FONT_BOLD, fontSize=11 }):setFillColor(1.0,0.30,0.30)
    xb:addEventListener("tap", function() closePopup(); return true end)

    -- build donate items list
    local p = saveUtil.load()
    local donateItems = {}

    -- materials
    local mats = p.materials or {}
    for _, def in ipairs(VAULT_DEFS) do
        if isDonateResourceType(def.type) then
            local qty = mats[def.key] or 0
            if qty > 0 then
                table.insert(donateItems, { key=def.key, name=def.name,
                    sprite=def.sprite, color=def.color, qty=qty, type=def.type })
            end
        end
    end
    -- gold
    if (p.gold or 0) > 0 then
        table.insert(donateItems, { key="gold", name="Gold",
            sprite="assets/sprites/ui/icons/gold.png",
            color={1.0,0.82,0.20}, qty=p.gold, type="gold" })
    end

    local groupedInventory = {}
    for _, id in ipairs(p.inventory or {}) do
        local def = itemDefs[id]
        if isGuildLootableItem(def) then
            local row = groupedInventory[id]
            if not row then
                row = {
                    key=id,
                    name=def.name or id,
                    sprite=def.icon,
                    color={0.75,0.80,1.0},
                    qty=0,
                    type=def.slot or "item",
                    description=def.description,
                    price=def.price,
                    auctionPrice=def.auctionPrice,
                }
                groupedInventory[id] = row
                table.insert(donateItems, row)
            end
            row.qty = row.qty + 1
        end
    end

    local scrollH  = ph - 50
    local ITEM_H   = 56
    local ITEM_PAD = 6
    local totalH   = math.max(scrollH, #donateItems*(ITEM_H+ITEM_PAD)+ITEM_PAD)
    local scrollY  = CY - ph*0.5 + 38 + scrollH*0.5

    local container = display.newContainer(popup, pw-8, scrollH)
    container.x = CX; container.y = scrollY

    local inner = display.newGroup(); container:insert(inner)
    local startY = -(scrollH*0.5) + ITEM_H*0.5 + ITEM_PAD

    if #donateItems == 0 then
        display.newText({ parent=inner, text="Nothing to donate",
            x=0, y=0, font=ui.FONT_BOLD, fontSize=13, align="center"
        }):setFillColor(0.40,0.48,0.60)
    end

    for i, item in ipairs(donateItems) do
        local iy = startY + (i-1)*(ITEM_H+ITEM_PAD)
        local iw = pw - 24

        local card = display.newRoundedRect(inner, 0, iy, iw, ITEM_H, 8)
        card:setFillColor(0.04,0.10,0.22,0.97)
        card.strokeWidth=1.5
        card:setStrokeColor(item.color[1]*0.6, item.color[2]*0.6, item.color[3]*0.6, 0.55)

        local spr = tryImg(inner, item.sprite, 38, 38)
        if spr then spr.x=-iw*0.5+28; spr.y=iy end

        local nt = display.newText({ parent=inner, text=item.name,
            x=-iw*0.5+58, y=iy-8, width=iw-134, font=ui.FONT_BOLD, fontSize=12, align="left" })
        nt:setFillColor(unpack(item.color)); nt.anchorX=0
        nt.isHitTestable = false

        local qt = display.newText({ parent=inner,
            text="Have: "..tostring(item.qty),
            x=-iw*0.5+58, y=iy+8, width=iw-134, font=ui.FONT_BOLD, fontSize=9, align="left" })
        qt:setFillColor(0.55,0.65,0.80); qt.anchorX=0
        qt.isHitTestable = false

        local db = display.newRoundedRect(inner, iw*0.5-36, iy, 58, 28, 6)
        db:setFillColor(0.04,0.20,0.10,0.97)
        db.strokeWidth=1.5; db:setStrokeColor(0.20,0.88,0.35,0.80)
        local donateLabel = item.type=="gold" and "DONATE" or "DONATE"
        display.newText({ parent=inner, text=donateLabel,
            x=iw*0.5-36, y=iy, font=ui.FONT_BOLD, fontSize=8
        }):setFillColor(0.35,1.0,0.50)

        local capItem = item
        db:addEventListener("tap", function()
            closePopup()
            buildInventoryDonateDetail(sg, capItem)
            return true
        end)
    end

    local minY = math.min(0, scrollH - totalH - ITEM_PAD*2)
    local sy0, gy0 = 0, 0
    container:addEventListener("touch", function(e)
        if e.phase=="began" then sy0=e.y; gy0=inner.y
        elseif e.phase=="moved" then
            inner.y = math.max(minY, math.min(0, gy0+(e.y-sy0)))
        end
        return true
    end)
end

buildInventoryDonateDetail = function(sg, item)
    closePopup()
    popup = display.newGroup(); sg:insert(popup)

    local dim=display.newRect(popup, CX, CY, SW, SH)
    dim:setFillColor(0,0,0,0.78); dim.isHitTestable=true
    dim:addEventListener("touch", function(e)
        if e.phase == "began" then
            closePopup()
        end
        return true
    end)

    local pw=SW-34; local ph=300
    local panel=display.newRoundedRect(popup, CX, CY, pw, ph, 14)
    panel:setFillColor(0.03,0.08,0.20,0.98)
    panel.strokeWidth=2; panel:setStrokeColor(item.color[1],item.color[2],item.color[3],0.72)
    panel:addEventListener("touch", function() return true end)

    local spr=tryImg(popup, item.sprite, 72, 72)
    if spr then spr.x=CX-pw*0.5+58; spr.y=CY-ph*0.5+70 end

    local nt=display.newText({ parent=popup, text=item.name,
        x=CX-pw*0.5+104, y=CY-ph*0.5+48, width=pw-128,
        font=ui.FONT_BOLD, fontSize=15, align="left" })
    nt.anchorX=0; nt:setFillColor(unpack(item.color))
    nt.isHitTestable = false

    local detail = (item.type or "Item").."   -   Have: "..tostring(item.qty or 1)
    local dt=display.newText({ parent=popup, text=detail,
        x=CX-pw*0.5+104, y=CY-ph*0.5+70, width=pw-128,
        font=ui.FONT_BOLD, fontSize=9, align="left" })
    dt.anchorX=0; dt:setFillColor(0.58,0.70,0.88)
    dt.isHitTestable = false

    local desc = item.description or "Donate this item to add it to the guild vault."
    local body=display.newText({ parent=popup, text=desc,
        x=CX, y=CY-ph*0.5+128, width=pw-34,
        font=ui.FONT_BOLD, fontSize=10, align="center" })
    body:setFillColor(0.70,0.80,0.94)
    body.isHitTestable = false

    local maxQty = math.min(990, tonumber(item.qty or 1) or 1)
    local selectedQty = math.min(1, maxQty)
    local qtyText
    local donateText
    local repeatTimer = nil
    local repeatBtn = nil

    local function stopRepeat()
        if repeatTimer then
            timer.cancel(repeatTimer)
            repeatTimer = nil
        end
        repeatBtn = nil
    end

    local function setQty(nextQty)
        selectedQty = math.max(1, math.min(maxQty, nextQty))
        if qtyText then
            qtyText.text = tostring(selectedQty)
        end
        if donateText then
            donateText.text = "DONATE "..tostring(selectedQty)
        end
    end

    local function holdQtyStep(qty, direction)
        qty = math.max(1, tonumber(qty) or 1)
        if direction < 0 then
            if qty <= 10 then return 1 end
            if qty <= 100 then return 10 end
            if qty <= 1000 then return 100 end
            return 1000
        end
        if qty < 10 then return 1 end
        if qty < 100 then return 10 end
        if qty < 1000 then return 100 end
        return 1000
    end

    local function nudgeQty(delta, held)
        if maxQty <= 0 then return end
        local step = held and holdQtyStep(selectedQty, delta) or 1
        setQty(selectedQty + step * delta)
    end

    local function bindHold(btn, delta)
        btn:addEventListener("touch", function(e)
            if e.phase == "began" then
                display.getCurrentStage():setFocus(btn, e.id)
                btn.isFocus = true
                btn.didHoldStep = false
                stopRepeat()
                repeatBtn = btn
                repeatTimer = timer.performWithDelay(360, function()
                    if repeatBtn == btn and btn.isFocus then
                        btn.didHoldStep = true
                        nudgeQty(delta, true)
                    end
                end, 0)
                return true
            elseif btn.isFocus and (e.phase == "ended" or e.phase == "cancelled") then
                display.getCurrentStage():setFocus(nil)
                btn.isFocus = false
                stopRepeat()
                if e.phase == "ended" and not btn.didHoldStep then
                    nudgeQty(delta, false)
                end
                btn.didHoldStep = false
                return true
            end
            return false
        end)
    end

    local actionY=CY+ph*0.5-52
    local qtyY=CY+ph*0.5-106

    local minus=display.newRoundedRect(popup, CX-82, qtyY, 34, 34, 6)
    minus:setFillColor(0.04,0.10,0.24,0.97)
    minus.strokeWidth=1.5; minus:setStrokeColor(0.25,0.70,1.0,0.65)
    local minusText = display.newText({ parent=popup, text="-", x=minus.x, y=qtyY-1, font=ui.FONT_BOLD, fontSize=16 })
    minusText:setFillColor(0.60,0.82,1.0)
    minusText.isHitTestable = false

    local qtyBg=display.newRoundedRect(popup, CX, qtyY, 78, 34, 6)
    qtyBg:setFillColor(0.03,0.08,0.20,0.97)
    qtyBg.strokeWidth=1.5; qtyBg:setStrokeColor(item.color[1],item.color[2],item.color[3],0.60)
    qtyText=display.newText({ parent=popup, text="1", x=CX, y=qtyY-1, font=ui.FONT_BOLD, fontSize=14 })
    qtyText:setFillColor(unpack(item.color))
    qtyText.isHitTestable = false
    local maxText = display.newText({
        parent=popup, text="MAX "..tostring(maxQty),
        x=CX, y=qtyY+20, font=ui.FONT_BOLD, fontSize=7
    })
    maxText:setFillColor(0.45,0.58,0.78)
    maxText.isHitTestable = false

    local plus=display.newRoundedRect(popup, CX+82, qtyY, 34, 34, 6)
    plus:setFillColor(0.04,0.10,0.24,0.97)
    plus.strokeWidth=1.5; plus:setStrokeColor(0.25,0.70,1.0,0.65)
    local plusText = display.newText({ parent=popup, text="+", x=plus.x, y=qtyY-1, font=ui.FONT_BOLD, fontSize=16 })
    plusText:setFillColor(0.60,0.82,1.0)
    plusText.isHitTestable = false

    bindHold(minus, -1)
    bindHold(plus, 1)

    local donate=display.newRoundedRect(popup, CX+pw*0.5-76, actionY, 118, 36, 8)
    donate:setFillColor(0.04,0.20,0.10,0.97)
    donate.strokeWidth=2; donate:setStrokeColor(0.20,0.88,0.35,0.85)
    donateText = display.newText({ parent=popup, text="DONATE "..tostring(selectedQty),
        x=donate.x, y=actionY, font=ui.FONT_BOLD, fontSize=12
    })
    donateText:setFillColor(0.35,1.0,0.50)
    donateText.isHitTestable = false
    donate:addEventListener("touch", function(e)
        if e.phase == "began" then
            display.getCurrentStage():setFocus(donate, e.id)
            donate.isFocus = true
            donate.alpha = 0.85
            return true
        elseif donate.isFocus and e.phase == "ended" then
            display.getCurrentStage():setFocus(nil)
            donate.isFocus = false
            donate.alpha = 1
            stopRepeat()
            donateText.text = "DONATING..."
            donateItemToVault(item, selectedQty, function(ok)
                if popup and donateText and donateText.removeSelf and not ok then
                    donateText.text = "FAILED"
                    timer.performWithDelay(700, function()
                        if donateText and donateText.removeSelf then
                            donateText.text = "DONATE "..tostring(selectedQty)
                        end
                    end)
                end
            end)
            return true
        elseif donate.isFocus and e.phase == "cancelled" then
            display.getCurrentStage():setFocus(nil)
            donate.isFocus = false
            donate.alpha = 1
            return true
        end
        return false
    end)

    local keep=display.newRoundedRect(popup, CX-pw*0.5+76, actionY, 118, 36, 8)
    keep:setFillColor(0.04,0.10,0.24,0.97)
    keep.strokeWidth=1.5; keep:setStrokeColor(0.25,0.70,1.0,0.65)
    display.newText({ parent=popup, text="KEEP",
        x=keep.x, y=actionY, font=ui.FONT_BOLD, fontSize=12
    }):setFillColor(0.62,0.86,1.0)
    keep:addEventListener("tap", function() closePopup(); return true end)

    local xb=display.newCircle(popup, CX+pw*0.5-18, CY-ph*0.5+18, 13)
    xb:setFillColor(0.25,0.04,0.04,0.97); xb.strokeWidth=1.5
    xb:setStrokeColor(0.85,0.18,0.18,0.80)
    display.newText({ parent=popup, text="X", x=xb.x, y=xb.y,
        font=ui.FONT_BOLD, fontSize=10 }):setFillColor(1.0,0.30,0.30)
    xb:addEventListener("tap", function() stopRepeat(); closePopup(); return true end)

    popupCleanup = stopRepeat
end

-------------------------------------------------
-- TOP CONTRIBUTORS POPUP
-------------------------------------------------
local function buildContributorsPopup(sg)
    closePopup()
    popup = display.newGroup(); sg:insert(popup)

    local dim = display.newRect(popup, CX, CY, SW, SH)
    dim:setFillColor(0,0,0,0.80); dim.isHitTestable=true
    dim:addEventListener("touch", function(e)
        if e.phase == "began" then
            closePopup()
        end
        return true
    end)

    local pw = SW-20; local ph = SH*0.78
    local panel = display.newRoundedRect(popup, CX, CY, pw, ph, 14)
    panel:setFillColor(0.03,0.07,0.18,0.98)
    panel.strokeWidth=2; panel:setStrokeColor(0.25,0.75,1.0,0.70)
    panel:addEventListener("touch", function() return true end)

    display.newText({ parent=popup, text="// TOP CONTRIBUTORS",
        x=CX, y=CY-ph*0.5+18, font=ui.FONT_BOLD, fontSize=14
    }):setFillColor(0.30,0.90,1.0)

    local hline = display.newRect(popup, CX, CY-ph*0.5+32, pw-10, 1)
    hline:setFillColor(0.25,0.75,1.0,0.35)

    local xb = display.newCircle(popup, CX+pw*0.5-16, CY-ph*0.5+16, 12)
    xb:setFillColor(0.28,0.04,0.04,0.97); xb.strokeWidth=1.5
    xb:setStrokeColor(0.85,0.18,0.18,0.80)
    display.newText({ parent=popup, text="✕", x=xb.x, y=xb.y-1,
        font=ui.FONT_BOLD, fontSize=11 }):setFillColor(1.0,0.30,0.30)
    xb:addEventListener("tap", function() closePopup(); return true end)

    local p = saveUtil.load()
    local contributions = serverEconomy and serverEconomy.contributions or p.guildContributions or {}
    local sorted = {}
    for _, row in pairs(contributions) do
        row.itemCount = row.itemCount or 0
        row.gold = row.gold or 0
        row.total = row.total or (row.itemCount + row.gold)
        table.insert(sorted, row)
    end
    table.sort(sorted, function(a,b) return (a.total or 0) > (b.total or 0) end)

    -- column headers
    local headerY = CY - ph*0.5 + 46
    local iw = pw - 16
    display.newText({ parent=popup, text="MEMBER",
        x=CX-iw*0.5+10, y=headerY, font=ui.FONT_BOLD, fontSize=8, align="left"
    }):setFillColor(0.40,0.58,0.78)
    local cols = {
        { label="ITEMS", x=CX+iw*0.5-140 },
        { label="GOLD",  x=CX+iw*0.5-82  },
        { label="TOTAL", x=CX+iw*0.5-26  },
    }
    for _, col in ipairs(cols) do
        display.newText({ parent=popup, text=col.label,
            x=col.x, y=headerY, font=ui.FONT_BOLD, fontSize=7, align="center"
        }):setFillColor(0.40,0.58,0.78)
    end

    local scrollH  = ph - 68
    local CARD_H   = 44
    local CARD_PAD = 5
    local totalH   = math.max(scrollH, #sorted*(CARD_H+CARD_PAD)+CARD_PAD)
    local scrollY  = CY - ph*0.5 + 54 + scrollH*0.5

    local container = display.newContainer(popup, pw-8, scrollH)
    container.x = CX; container.y = scrollY

    local inner = display.newGroup(); container:insert(inner)
    local startY = -(scrollH*0.5) + CARD_H*0.5 + CARD_PAD

    if #sorted == 0 then
        display.newText({ parent=inner, text="No contributions yet",
            x=0, y=0, font=ui.FONT_BOLD, fontSize=13, align="center"
        }):setFillColor(0.40,0.48,0.60)
    end

    for i, m in ipairs(sorted) do
        local cy2 = startY + (i-1)*(CARD_H+CARD_PAD)

        local card = display.newRoundedRect(inner, 0, cy2, iw, CARD_H, 7)
        card:setFillColor(0.04,0.10,0.22,0.97)
        card.strokeWidth=1
        local rc = RANK_COLORS[m.rank] or RANK_COLORS.MEMBER
        card:setStrokeColor(rc[1]*0.5, rc[2]*0.5, rc[3]*0.5, 0.55)

        -- rank badge dot
        local dot = display.newCircle(inner, -iw*0.5+8, cy2, 4)
        dot:setFillColor(unpack(rc))

        -- name
        local nt = display.newText({ parent=inner, text=m.name,
            x=-iw*0.5+18, y=cy2-6, font=ui.FONT_BOLD, fontSize=11, align="left" })
        nt:setFillColor(0.90,0.95,1.0); nt.anchorX=0

        -- rank label
        local rl = display.newText({ parent=inner, text=m.rank,
            x=-iw*0.5+18, y=cy2+8, font=ui.FONT_BOLD, fontSize=7, align="left" })
        rl:setFillColor(unpack(rc)); rl.anchorX=0

        local donCols = {
            { val=m.itemCount or 0, x=iw*0.5-140 },
            { val=m.gold or 0,      x=iw*0.5-82  },
            { val=m.total or 0,     x=iw*0.5-26  },
        }
        for _, dc in ipairs(donCols) do
            local vt = display.newText({ parent=inner, text=tostring(dc.val),
                x=dc.x, y=cy2, font=ui.FONT_BOLD, fontSize=9, align="center" })
            vt:setFillColor(0.75,0.85,1.0)
        end
    end

    -- scroll
    local minY = math.min(0, scrollH - totalH - CARD_PAD*2)
    local sy0, gy0 = 0, 0
    container:addEventListener("touch", function(e)
        if e.phase=="began" then sy0=e.y; gy0=inner.y
        elseif e.phase=="moved" then
            inner.y = math.max(minY, math.min(0, gy0+(e.y-sy0)))
        end
        return true
    end)
end

-------------------------------------------------
-- AUCTION POPUP — POST ITEM (leader/general/colonel)
-------------------------------------------------
local function buildAuctionPostPopup(sg, onPosted, preselectedItem)
    closePopup()
    popup = display.newGroup(); sg:insert(popup)

    local dim = display.newRect(popup, CX, CY, SW, SH)
    dim:setFillColor(0,0,0,0.82); dim.isHitTestable=true

    local pw = SW-20; local ph = SH*0.72
    local panel = display.newRoundedRect(popup, CX, CY, pw, ph, 14)
    panel:setFillColor(0.03,0.07,0.18,0.98)
    panel.strokeWidth=2; panel:setStrokeColor(1.0,0.70,0.20,0.65)

    display.newText({ parent=popup, text="// POST AUCTION",
        x=CX, y=CY-ph*0.5+18, font=ui.FONT_BOLD, fontSize=14
    }):setFillColor(1.0,0.80,0.25)

    local hline = display.newRect(popup, CX, CY-ph*0.5+32, pw-10, 1)
    hline:setFillColor(1.0,0.70,0.20,0.35)

    local xb = display.newCircle(popup, CX+pw*0.5-16, CY-ph*0.5+16, 12)
    xb:setFillColor(0.28,0.04,0.04,0.97); xb.strokeWidth=1.5
    xb:setStrokeColor(0.85,0.18,0.18,0.80)
    display.newText({ parent=popup, text="✕", x=xb.x, y=xb.y-1,
        font=ui.FONT_BOLD, fontSize=11 }):setFillColor(1.0,0.30,0.30)
    xb:addEventListener("tap", function() closePopup(); return true end)

    -- collect postable items from vault
    local p = saveUtil.load()
    local vault = serverEconomy and serverEconomy.vault or p.guildVault or {}
    local vaultItems = serverEconomy and serverEconomy.vaultItems or {}
    local postItems = {}
    if preselectedItem then
        if not preselectedItem.price then
            preselectedItem.price = getAuctionDefaultPrice(preselectedItem)
        end
        table.insert(postItems, preselectedItem)
    else
        for _, def in ipairs(VAULT_DEFS) do
            if (vault[def.key] or 0) > 0 then
                    table.insert(postItems, { key=def.key, name=def.name,
                    sprite=def.sprite, color=def.color, qty=vault[def.key], type=def.type, price=def.price, auctionPrice=def.auctionPrice })
            end
        end
        for key, qty in pairs(vault) do
            local known = false
            for _, def in ipairs(VAULT_DEFS) do
                if def.key == key then known = true; break end
            end
            if not known and qty > 0 then
                local meta = vaultItems[key]
                local def = itemDefs[key]
                if def then
                    table.insert(postItems, { key=key, name=def.name,
                        sprite=def.icon, color={0.75,0.80,1.0}, qty=qty, type=def.slot, price=def.price, auctionPrice=def.auctionPrice })
                elseif meta then
                    table.insert(postItems, { key=key, name=meta.name or key,
                        sprite=meta.sprite, color=meta.color or {0.75,0.80,1.0}, qty=qty, type=meta.type, price=meta.price, auctionPrice=meta.auctionPrice })
                end
            end
        end
    end

    local selectedItem = preselectedItem
    local selectedPrice = getAuctionDefaultPrice(preselectedItem)
    local selectedFloor = selectedPrice
    local selectedMinRank = "MEMBER"
    local selBg = nil

    -- item scroll
    local scrollH  = ph * 0.42
    local ITEM_H   = 48; local ITEM_PAD = 5
    local totalH   = math.max(scrollH, #postItems*(ITEM_H+ITEM_PAD)+ITEM_PAD)
    local scrollY  = CY - ph*0.5 + 42 + scrollH*0.5
    local iw       = pw - 20

    local container = display.newContainer(popup, pw-8, scrollH)
    container.x = CX; container.y = scrollY
    local inner = display.newGroup(); container:insert(inner)
    local startY2 = -(scrollH*0.5) + ITEM_H*0.5 + ITEM_PAD

    local itemBgs = {}
    for i, item in ipairs(postItems) do
        local iy = startY2 + (i-1)*(ITEM_H+ITEM_PAD)
        local card = display.newRoundedRect(inner, 0, iy, iw, ITEM_H, 7)
        local selected = selectedItem and selectedItem.key == item.key
        card:setFillColor(selected and 0.05 or 0.04, selected and 0.22 or 0.10, selected and 0.10 or 0.22, 0.97)
        card.strokeWidth=selected and 2 or 1.5
        card:setStrokeColor(selected and 0.22 or item.color[1]*0.5,
                            selected and 0.88 or item.color[2]*0.5,
                            selected and 0.35 or item.color[3]*0.5,
                            selected and 0.90 or 0.55)
        itemBgs[i] = card

        local spr = tryImg(inner, item.sprite, 34, 34)
        if spr then spr.x=-iw*0.5+22; spr.y=iy end
        local nt = display.newText({ parent=inner, text=item.name,
            x=-iw*0.5+46, y=iy-6, font=ui.FONT_BOLD, fontSize=11, align="left" })
        nt:setFillColor(unpack(item.color)); nt.anchorX=0
        local qt = display.newText({ parent=inner, text="x"..item.qty,
            x=-iw*0.5+46, y=iy+7, font=ui.FONT_BOLD, fontSize=8, align="left" })
        qt:setFillColor(0.50,0.60,0.78); qt.anchorX=0

        local capItem=item; local capI=i
        card:addEventListener("tap", function()
            selectedItem = capItem
            selectedPrice = getAuctionDefaultPrice(capItem)
            selectedFloor = selectedPrice
            priceTxt.text = tostring(selectedPrice)
            for j, bg in ipairs(itemBgs) do
                if j==capI then
                    bg:setFillColor(0.05,0.22,0.10,0.97)
                    bg.strokeWidth=2; bg:setStrokeColor(0.22,0.88,0.35,0.90)
                else
                    bg:setFillColor(0.04,0.10,0.22,0.97)
                    bg.strokeWidth=1.5
                    local c=postItems[j].color
                    bg:setStrokeColor(c[1]*0.5,c[2]*0.5,c[3]*0.5,0.55)
                end
            end
            return true
        end)
    end

    local minScroll = math.min(0, scrollH - totalH - ITEM_PAD*2)
    local sy0, gy0 = 0, 0
    container:addEventListener("touch", function(e)
        if e.phase=="began" then sy0=e.y; gy0=inner.y
        elseif e.phase=="moved" then
            inner.y = math.max(minScroll, math.min(0, gy0+(e.y-sy0)))
        end
        return true
    end)

    -- price input
    local priceY = CY + ph*0.5 - 130
    display.newText({ parent=popup, text="STARTING PRICE (gold)",
        x=CX, y=priceY-20, font=ui.FONT_BOLD, fontSize=9, align="center"
    }):setFillColor(0.50,0.65,0.85)

    local priceBg = display.newRoundedRect(popup, CX, priceY, 160, 32, 6)
    priceBg:setFillColor(0.04,0.10,0.24,0.97)
    priceBg.strokeWidth=1.5; priceBg:setStrokeColor(1.0,0.70,0.20,0.60)

    local priceTxt = display.newText({ parent=popup, text=tostring(selectedPrice),
        x=CX, y=priceY, font=ui.FONT_BOLD, fontSize=14, align="center"
    })
    priceTxt:setFillColor(1.0,0.82,0.20)

    local minusB = display.newRoundedRect(popup, CX-100, priceY, 32, 32, 6)
    minusB:setFillColor(0.04,0.10,0.24,0.97); minusB.strokeWidth=1
    minusB:setStrokeColor(1.0,0.70,0.20,0.50)
    display.newText({ parent=popup, text="-", x=CX-100, y=priceY-1,
        font=ui.FONT_BOLD, fontSize=18 }):setFillColor(1.0,0.82,0.20)
    minusB:addEventListener("tap", function()
        selectedPrice = math.max(selectedFloor or 10, selectedPrice-50)
        priceTxt.text = tostring(selectedPrice); return true
    end)

    local plusB = display.newRoundedRect(popup, CX+100, priceY, 32, 32, 6)
    plusB:setFillColor(0.04,0.10,0.24,0.97); plusB.strokeWidth=1
    plusB:setStrokeColor(1.0,0.70,0.20,0.50)
    display.newText({ parent=popup, text="+", x=CX+100, y=priceY-1,
        font=ui.FONT_BOLD, fontSize=18 }):setFillColor(1.0,0.82,0.20)
    plusB:addEventListener("tap", function()
        selectedPrice = selectedPrice+50
        priceTxt.text = tostring(selectedPrice); return true
    end)

    -- min rank selector
    local rankY = CY + ph*0.5 - 86
    display.newText({ parent=popup, text="MIN RANK TO BID",
        x=CX, y=rankY-18, font=ui.FONT_BOLD, fontSize=9, align="center"
    }):setFillColor(0.50,0.65,0.85)

    local rankBtns = {}
    local rankList = {"MEMBER","CAPTAIN","COLONEL","GENERAL","LEADER"}
    local rankBtnW = (pw-20) / #rankList
    for i, rk in ipairs(rankList) do
        local rx = CX - pw*0.5+10 + (i-0.5)*rankBtnW
        local rc = RANK_COLORS[rk] or RANK_COLORS.MEMBER
        local isActive = (rk == selectedMinRank)
        local rbg = display.newRoundedRect(popup, rx, rankY, rankBtnW-4, 22, 4)
        rbg:setFillColor(isActive and rc[1]*0.25 or 0.03,
                         isActive and rc[2]*0.25 or 0.06,
                         isActive and rc[3]*0.25 or 0.14, 0.97)
        rbg.strokeWidth=1.5
        rbg:setStrokeColor(rc[1], rc[2], rc[3], isActive and 0.90 or 0.35)
        local rt = display.newText({ parent=popup, text=rk:sub(1,3),
            x=rx, y=rankY, font=ui.FONT_BOLD, fontSize=7, align="center" })
        rt:setFillColor(unpack(rc))
        rankBtns[i] = { bg=rbg, txt=rt, rank=rk, color=rc }
        rbg:addEventListener("tap", function()
            selectedMinRank = rk
            for j, btn in ipairs(rankBtns) do
                local act = (btn.rank==selectedMinRank)
                local c = btn.color
                btn.bg:setFillColor(act and c[1]*0.25 or 0.03,
                                    act and c[2]*0.25 or 0.06,
                                    act and c[3]*0.25 or 0.14, 0.97)
                btn.bg:setStrokeColor(c[1],c[2],c[3], act and 0.90 or 0.35)
            end
            return true
        end)
    end

    -- POST button
    local postY = CY + ph*0.5 - 26
    local postBg = display.newRoundedRect(popup, CX, postY, 180, 36, 8)
    postBg:setFillColor(0.05,0.22,0.08,0.97)
    postBg.strokeWidth=2; postBg:setStrokeColor(0.22,0.88,0.35,0.85)
    display.newText({ parent=popup, text="POST TO AUCTION",
        x=CX, y=postY, font=ui.FONT_BOLD, fontSize=12
    }):setFillColor(0.35,1.0,0.50)

    postBg:addEventListener("tap", function()
        if not selectedItem then return true end
        local guildId = getCurrentGuildId()
        if guildId then
            api.guilds.postAuction(guildId, {
                key=selectedItem.key, name=selectedItem.name,
                sprite=selectedItem.sprite, color=selectedItem.color,
                type=selectedItem.type, qty=1,
                price=selectedPrice, auctionPrice=selectedFloor, minRank=selectedMinRank,
            }, function(response)
                if response.ok and response.data then
                    applyServerEconomy(response.data.economy)
                    closePopup()
                    if onPosted then onPosted() end
                end
            end)
            return true
        end

        local pp = saveUtil.load()
        pp.guildAuction = pp.guildAuction or {}
        table.insert(pp.guildAuction, {
            key=selectedItem.key, name=selectedItem.name,
            sprite=selectedItem.sprite, color=selectedItem.color,
            price=selectedPrice, auctionPrice=selectedFloor, minRank=selectedMinRank,
            seller=pp.name or "Unknown", bids={},
        })
        pp.guildVault = pp.guildVault or {}
        if (pp.guildVault[selectedItem.key] or 0) > 0 then pp.guildVault[selectedItem.key] = pp.guildVault[selectedItem.key] - 1 end
        saveUtil.save(pp)
        closePopup()
        if onPosted then onPosted() end
        return true
    end)
end

-------------------------------------------------
-- AUCTION VIEW POPUP — BID ON ITEM
-------------------------------------------------
local function buildAuctionBidPopup(sg, auctionItem, auctionIdx, onBid)
    closePopup()
    popup = display.newGroup(); sg:insert(popup)

    local dim = display.newRect(popup, CX, CY, SW, SH)
    dim:setFillColor(0,0,0,0.80); dim.isHitTestable=true
    dim:addEventListener("tap", function() closePopup(); return true end)

    local pw=SW-30; local ph=280
    local panel = display.newRoundedRect(popup, CX, CY, pw, ph, 14)
    panel:setFillColor(0.03,0.07,0.18,0.98)
    panel.strokeWidth=2; panel:setStrokeColor(1.0,0.70,0.20,0.65)

    local spr = tryImg(popup, auctionItem.sprite, 64, 64)
    if spr then spr.x=CX; spr.y=CY-ph*0.5+52 end

    display.newText({ parent=popup, text=auctionItem.name,
        x=CX, y=CY-ph*0.5+98, font=ui.FONT_BOLD, fontSize=15, align="center"
    }):setFillColor(unpack(auctionItem.color or {0.9,0.9,1.0}))

    display.newText({ parent=popup,
        text="Seller: "..auctionItem.seller.."   ·   Min rank: "..auctionItem.minRank,
        x=CX, y=CY-ph*0.5+116, font=ui.FONT_BOLD, fontSize=8, align="center"
    }):setFillColor(0.45,0.55,0.75)

    -- current top bid
    local topBid = auctionItem.price
    local topBidder = "None"
    for _, bid in ipairs(auctionItem.bids or {}) do
        if bid.amount > topBid then topBid=bid.amount; topBidder=bid.name end
    end

    local bidInfoTxt = display.newText({ parent=popup,
        text="Top bid: "..topBid.."g  ·  "..topBidder,
        x=CX, y=CY-ph*0.5+134, font=ui.FONT_BOLD, fontSize=10, align="center"
    })
    bidInfoTxt:setFillColor(1.0,0.82,0.20)

    -- bid amount
    local bidAmount = topBid + 50
    local bidTxt = display.newText({ parent=popup, text=tostring(bidAmount).."g",
        x=CX, y=CY, font=ui.FONT_BOLD, fontSize=16, align="center"
    })
    bidTxt:setFillColor(1.0,0.90,0.30)

    local mb = display.newRoundedRect(popup, CX-80, CY, 32, 32, 6)
    mb:setFillColor(0.04,0.10,0.24,0.97); mb.strokeWidth=1
    mb:setStrokeColor(1.0,0.70,0.20,0.50)
    display.newText({ parent=popup, text="-", x=CX-80, y=CY-1,
        font=ui.FONT_BOLD, fontSize=18 }):setFillColor(1.0,0.82,0.20)
    mb:addEventListener("tap", function()
        bidAmount = math.max(topBid+50, bidAmount-50)
        bidTxt.text = tostring(bidAmount).."g"; return true
    end)

    local pb2 = display.newRoundedRect(popup, CX+80, CY, 32, 32, 6)
    pb2:setFillColor(0.04,0.10,0.24,0.97); pb2.strokeWidth=1
    pb2:setStrokeColor(1.0,0.70,0.20,0.50)
    display.newText({ parent=popup, text="+", x=CX+80, y=CY-1,
        font=ui.FONT_BOLD, fontSize=18 }):setFillColor(1.0,0.82,0.20)
    pb2:addEventListener("tap", function()
        bidAmount = bidAmount+50; bidTxt.text = tostring(bidAmount).."g"; return true
    end)

    -- check rank
    local playerRank = getPlayerRank()
    local canBid = rankValue(playerRank) <= rankValue(auctionItem.minRank)

    local bidBg = display.newRoundedRect(popup, CX, CY+ph*0.5-36, 180, 36, 8)
    if canBid then
        bidBg:setFillColor(0.05,0.22,0.08,0.97)
        bidBg.strokeWidth=2; bidBg:setStrokeColor(0.22,0.88,0.35,0.85)
        display.newText({ parent=popup, text="PLACE BID",
            x=CX, y=CY+ph*0.5-36, font=ui.FONT_BOLD, fontSize=13
        }):setFillColor(0.35,1.0,0.50)
        bidBg:addEventListener("tap", function()
            local pp = saveUtil.load()
            if (pp.gold or 0) < bidAmount then
                bidBg:setFillColor(0.30,0.04,0.04,0.97)
                timer.performWithDelay(500, function()
                    bidBg:setFillColor(0.05,0.22,0.08,0.97)
                end)
                return true
            end
            local guildId = getCurrentGuildId()
            if guildId and auctionItem.auctionId then
                api.guilds.bidAuction(guildId, auctionItem.auctionId, { amount=bidAmount }, function(response)
                    if response.ok and response.data then
                        if response.data.economy then
                            applyServerEconomy(response.data.economy)
                        else
                            serverEconomy = serverEconomy or {}
                            serverEconomy.auctions = response.data.auctions or serverEconomy.auctions
                        end
                        if response.data.player then
                            sync.applyPlayerSnapshot(response.data.player, saveUtil.activeSlot)
                        end
                        closePopup()
                        if onBid then onBid() end
                    end
                end)
                return true
            end

            pp.guildAuction = pp.guildAuction or {}
            if pp.guildAuction[auctionIdx] then
                table.insert(pp.guildAuction[auctionIdx].bids, { name=pp.name or "Player", amount=bidAmount })
                if bidAmount > pp.guildAuction[auctionIdx].price then pp.guildAuction[auctionIdx].price = bidAmount end
            end
            saveUtil.save(pp)
            closePopup()
            if onBid then onBid() end
            return true
        end)
    else
        bidBg:setFillColor(0.10,0.10,0.14,0.97)
        bidBg.strokeWidth=1; bidBg:setStrokeColor(0.30,0.30,0.35,0.40)
        display.newText({ parent=popup, text="RANK TOO LOW",
            x=CX, y=CY+ph*0.5-36, font=ui.FONT_BOLD, fontSize=11
        }):setFillColor(0.40,0.40,0.48)
    end

    local xb = display.newCircle(popup, CX+pw*0.5-16, CY-ph*0.5+16, 12)
    xb:setFillColor(0.28,0.04,0.04,0.97); xb.strokeWidth=1.5
    xb:setStrokeColor(0.85,0.18,0.18,0.80)
    display.newText({ parent=popup, text="✕", x=xb.x, y=xb.y-1,
        font=ui.FONT_BOLD, fontSize=11 }):setFillColor(1.0,0.30,0.30)
    xb:addEventListener("tap", function() closePopup(); return true end)
end

-------------------------------------------------
-- ACTION BUTTONS (Contributors / Auction)
-------------------------------------------------
local ACTION_BTN_H  = 38
local ACTION_BTN_Y  = CONTENT_BOT - ACTION_BTN_H*0.5 - 4
local ACTION_AREA_H = ACTION_BTN_H + 10

local function buildActionButtons(sg)
    if actionGroup then actionGroup:removeSelf(); actionGroup=nil end
    actionGroup = display.newGroup(); sg:insert(actionGroup)

    local btnW = (SW-18) / 3
    local btnDefs = {
        { label="DONATE",       color={0.35,1.0,0.50},  action=function() buildDonatePopup(sg) end },
        { label="CONTRIBUTORS", color={0.35,0.75,1.0},  action=function() buildContributorsPopup(sg) end },
        { label="AUCTION",      color={1.0,0.78,0.20},  action=function() buildAuctionView(sg) end },
    }

    for i, btn in ipairs(btnDefs) do
        local bx = 9 + (i-0.5)*btnW
        drawFrame(actionGroup, bx, ACTION_BTN_Y, btnW-6, ACTION_BTN_H, FRAME_THIN_S)
        local bt = display.newText({ parent=actionGroup, text=btn.label,
            x=bx, y=ACTION_BTN_Y, width=btnW-10, font=ui.FONT_BOLD, fontSize=8, align="center" })
        bt:setFillColor(unpack(btn.color))
        local capAction = btn.action
        local hitBg = display.newRect(actionGroup, bx, ACTION_BTN_Y, btnW-6, ACTION_BTN_H)
        hitBg:setFillColor(0,0,0,0)
        hitBg:addEventListener("tap", function() capAction(); return true end)
        bt:addEventListener("tap", function() capAction(); return true end)
    end
end

-------------------------------------------------
-- AUCTION VIEW (grid of posted items)
-------------------------------------------------
buildAuctionView = function(sg)
    if gridGroup then gridGroup:removeSelf(); gridGroup=nil end
    gridGroup = display.newGroup(); sg:insert(gridGroup)

    local p = saveUtil.load()
    local auctions = serverEconomy and serverEconomy.auctions or p.guildAuction or {}

    local COLS2  = 5
    local PAD2   = 6
    local gridTop = CONTENT_TOP + 40
    local gridBot = ACTION_BTN_Y - ACTION_BTN_H*0.5 - 6
    local gridH   = gridBot - gridTop
    local ROWS2   = 6
    local slotW   = (SW - PAD2*(COLS2+1)) / COLS2
    local slotH   = (gridH - PAD2*(ROWS2+1)) / ROWS2
    local totalSlots = COLS2 * ROWS2

    if #auctions == 0 then
        display.newText({ parent=gridGroup, text="No auctions yet",
            x=CX, y=gridTop + gridH*0.5 - 10,
            font=ui.FONT_BOLD, fontSize=13, align="center"
        }):setFillColor(0.40,0.48,0.60)
        if isLeader() then
            display.newText({ parent=gridGroup, text="Tap an item in Guild Vault to post it.",
                x=CX, y=gridTop + gridH*0.5 + 12,
                font=ui.FONT_BOLD, fontSize=9, align="center"
            }):setFillColor(0.55,0.66,0.82)
        end
    end

    for i = 1, totalSlots do
        local col = (i-1) % COLS2
        local row = math.floor((i-1) / COLS2)
        local sx  = PAD2 + col*(slotW+PAD2) + slotW*0.5
        local sy  = gridTop + PAD2 + row*(slotH+PAD2) + slotH*0.5

        local item = auctions[i]

        local slotBg = display.newRoundedRect(gridGroup, sx, sy, slotW, slotH, 6)
        if item then
            local c = item.color or {0.75,0.80,1.0}
            slotBg:setFillColor(0.04,0.12,0.26,0.97)
            slotBg.strokeWidth=1.5
            slotBg:setStrokeColor(c[1]*0.7,c[2]*0.7,c[3]*0.7,0.65)

            local spr = tryImg(gridGroup, item.sprite, slotW-8, slotH-14)
            if spr then spr.x=sx; spr.y=sy-4 end

            -- price badge bottom right
            local pBg = display.newRoundedRect(gridGroup,
                sx+slotW*0.5-14, sy+slotH*0.5-8, 28, 13, 3)
            pBg:setFillColor(0.02,0.06,0.18,0.95)
            pBg.strokeWidth=1; pBg:setStrokeColor(1.0,0.78,0.20,0.55)
            local pt = display.newText({ parent=gridGroup,
                text=tostring(item.price).."g",
                x=sx+slotW*0.5-14, y=sy+slotH*0.5-8,
                font=ui.FONT_BOLD, fontSize=6, align="center" })
            pt:setFillColor(1.0,0.82,0.20); pt.isHitTestable=false

            local capItem=item; local capIdx=i; local capSg=sg
            slotBg:addEventListener("tap", function()
                buildAuctionBidPopup(capSg, capItem, capIdx, function()
                    buildAuctionView(capSg)
                end)
                return true
            end)
        else
            slotBg:setFillColor(0.02,0.04,0.10,0.70)
            slotBg.strokeWidth=1; slotBg:setStrokeColor(0.10,0.14,0.14,0.25)
        end
    end
end

-------------------------------------------------
-- BUILD GRID (vault or inventory tabs)
-------------------------------------------------
local COLS   = 5
local PAD    = 6

buildGrid = function(sg, tabIdx)
    if gridGroup then gridGroup:removeSelf(); gridGroup=nil end
    gridGroup = display.newGroup(); sg:insert(gridGroup)

    local player = saveUtil.load()
    local vault  = serverEconomy and serverEconomy.vault or player.guildVault or {}
    local vaultItems = serverEconomy and serverEconomy.vaultItems or {}

    local gridTop  = CONTENT_TOP + 34
    local gridBot  = ACTION_BTN_Y - ACTION_BTN_H*0.5 - 6
    local gridH    = gridBot - gridTop
    local ROWS     = 6
    local slotW    = (SW - PAD*(COLS+1)) / COLS
    local slotH    = (gridH - PAD*(ROWS+1)) / ROWS
    local totalSlots = COLS * ROWS

    local items2 = {}

    if tabIdx == 1 then
        local shown = {}
        for _, def in ipairs(VAULT_DEFS) do
            shown[def.key] = true
            table.insert(items2, {
                key=def.key, name=def.name, color=def.color,
                type=def.type, qty=vault[def.key] or 0,
                sprite=def.sprite,
            })
        end
        for key, qty in pairs(vault) do
            if not shown[key] and qty > 0 then
                local meta = vaultItems[key]
                local def = itemDefs[key]
                if def then
                    table.insert(items2, {
                        key=key, name=def.name, color={0.75,0.80,1.0},
                        type=def.slot, qty=qty, sprite=def.icon,
                        description=def.description,
                    })
                elseif meta then
                    table.insert(items2, {
                        key=key, name=meta.name or key, color=meta.color or {0.75,0.80,1.0},
                        type=meta.type, qty=qty, sprite=meta.sprite,
                    })
                end
            end
        end
    else
        -- personal inventory: only guild donation materials
        local mats = player.materials or {}
        for _, def in ipairs(VAULT_DEFS) do
            if isDonateResourceType(def.type) then
                if (mats[def.key] or 0) > 0 then
                    table.insert(items2, {
                        key=def.key, name=def.name, color=def.color,
                        type=def.type, qty=mats[def.key],
                        sprite=def.sprite,
                    })
                end
            end
        end
        if (player.gold or 0) > 0 then
            table.insert(items2, {
                key="gold", name="Gold", color={1.0,0.82,0.20},
                type="gold", qty=player.gold, sprite="assets/sprites/ui/icons/gold.png",
            })
        end
        local groupedInventory = {}
        for _, id in ipairs(player.inventory or {}) do
            local def = itemDefs[id]
            if isGuildLootableItem(def) then
                local row = groupedInventory[id]
                if not row then
                    row = {
                        key=id,
                        name=def.name or id,
                        color={0.75,0.80,1.0},
                        type=def.slot or "item",
                        qty=0,
                        sprite=def.icon,
                        description=def.description,
                        price=def.price,
                        auctionPrice=def.auctionPrice,
                    }
                    groupedInventory[id] = row
                    table.insert(items2, row)
                end
                row.qty = row.qty + 1
            end
        end
    end

    for i = 1, totalSlots do
        local col = (i-1) % COLS
        local row = math.floor((i-1) / COLS)
        local sx  = PAD + col*(slotW+PAD) + slotW*0.5
        local sy  = gridTop + PAD + row*(slotH+PAD) + slotH*0.5

        local item    = items2[i]
        local hasItem = item ~= nil
        local qty     = hasItem and item.qty or 0

        local slotBg = display.newRoundedRect(gridGroup, sx, sy, slotW, slotH, 6)
        if hasItem and qty > 0 then
            slotBg:setFillColor(0.04,0.12,0.26,0.97)
            slotBg.strokeWidth=1.5
            slotBg:setStrokeColor(item.color[1]*0.7,item.color[2]*0.7,item.color[3]*0.7,0.65)
        elseif hasItem then
            slotBg:setFillColor(0.03,0.06,0.14,0.90)
            slotBg.strokeWidth=1; slotBg:setStrokeColor(0.14,0.22,0.18,0.40)
        else
            slotBg:setFillColor(0.02,0.04,0.10,0.70)
            slotBg.strokeWidth=1; slotBg:setStrokeColor(0.10,0.14,0.14,0.25)
        end

        if hasItem then
            if item.sprite then
                local spr = tryImg(gridGroup, item.sprite, slotW-8, slotH-10)
                if spr then
                    spr.x=sx; spr.y=sy
                    if qty==0 then spr:setFillColor(0.28,0.28,0.28) end
                end
            end

            -- qty badge bottom right only
            local qBg = display.newRoundedRect(gridGroup,
                sx+slotW*0.5-10, sy+slotH*0.5-8, 20, 12, 3)
            qBg:setFillColor(0.02,0.06,0.18,0.95)
            qBg.strokeWidth=1; qBg:setStrokeColor(
                item.color[1],item.color[2],item.color[3],0.45)
            local qt = display.newText({ parent=gridGroup, text=tostring(qty),
                x=sx+slotW*0.5-10, y=sy+slotH*0.5-8,
                font=ui.FONT_BOLD, fontSize=6, align="center" })
            qt:setFillColor(qty>0 and item.color[1] or 0.30,
                            qty>0 and item.color[2] or 0.30,
                            qty>0 and item.color[3] or 0.32)
            qt.isHitTestable=false; qBg.isHitTestable=false

            local capItem=item; local capSg=sg
            slotBg:addEventListener("tap", function()
                -- simple vault detail popup reused
                if activeTab==1 then
                    local fullDef=capItem
                    for _,d in ipairs(VAULT_DEFS) do
                        if d.key==capItem.key then fullDef=d; break end
                    end
                    buildVaultDetail(capSg, fullDef, (serverEconomy and serverEconomy.vault or saveUtil.load().guildVault or {})[fullDef.key] or 0)
                else
                    buildInventoryDonateDetail(capSg, capItem)
                end
                return true
            end)
        end
    end
end

-------------------------------------------------
-- VAULT DETAIL POPUP (tap item in vault)
-------------------------------------------------
buildVaultDetail = function(sg, item, qty)
    closePopup()
    popup = display.newGroup(); sg:insert(popup)

    local dim=display.newRect(popup, CX, CY, SW, SH)
    dim:setFillColor(0,0,0,0.78); dim.isHitTestable=true
    dim:addEventListener("touch", function(e)
        if e.phase == "began" then
            closePopup()
        end
        return true
    end)

    local pw=SW-36; local ph=230
    local panel=display.newRoundedRect(popup, CX, CY, pw, ph, 14)
    panel:setFillColor(0.03,0.08,0.20,0.98)
    panel.strokeWidth=2; panel:setStrokeColor(item.color[1],item.color[2],item.color[3],0.72)
    panel:addEventListener("touch", function() return true end)

    local iconY=CY-ph*0.5+58
    local spr=tryImg(popup, item.sprite, 68, 68)
    if spr then spr.x=CX; spr.y=iconY end

    display.newText({ parent=popup, text=item.name,
        x=CX, y=CY-ph*0.5+106, font=ui.FONT_BOLD, fontSize=16, align="center"
    }):setFillColor(unpack(item.color))

    display.newText({ parent=popup,
        text=(item.type or "").."   ·   Guild Vault: "..qty,
        x=CX, y=CY-ph*0.5+124, font=ui.FONT_BOLD, fontSize=10, align="center"
    }):setFillColor(0.60,0.68,0.85)

    local actionY=CY+ph*0.5-38
    if qty > 0 then
        local leaderCanAuction = isLeader()
        local takeX = leaderCanAuction and (CX - 70) or CX
        local tb=display.newRoundedRect(popup, takeX, actionY, leaderCanAuction and 118 or 150, 36, 8)
        tb:setFillColor(0.04,0.18,0.10,0.97)
        tb.strokeWidth=2; tb:setStrokeColor(item.color[1],item.color[2],item.color[3],0.82)
        display.newText({ parent=popup, text="TAKE  1",
            x=takeX, y=actionY, font=ui.FONT_BOLD, fontSize=12
        }):setFillColor(unpack(item.color))
        tb:addEventListener("tap", function()
            local guildId = getCurrentGuildId()
            if guildId then
                api.guilds.takeVault(guildId, { key=item.key, qty=1 }, function(response)
                    if response.ok and response.data then
                        applyServerEconomy(response.data.economy)
                        if response.data.player then
                            sync.applyPlayerSnapshot(response.data.player, saveUtil.activeSlot)
                        end
                        closePopup()
                        buildGrid(sg, activeTab)
                    end
                end)
                return true
            end

            local p=saveUtil.load()
            p.guildVault=p.guildVault or {}
            if (p.guildVault[item.key] or 0) > 0 then
                p.guildVault[item.key]=p.guildVault[item.key]-1
                if item.type == "Crystal" or item.type == "Augment" or item.type == "Material" then
                    p.materials=p.materials or {}
                    p.materials[item.key]=(p.materials[item.key] or 0)+1
                else
                    p.inventory=p.inventory or {}
                    table.insert(p.inventory, item.key)
                end
                saveUtil.save(p)
                pushPlayerSnapshot(p)
                closePopup()
                buildGrid(sg, activeTab)
            end
            return true
        end)
        if leaderCanAuction then
            local ab=display.newRoundedRect(popup, CX+70, actionY, 118, 36, 8)
            ab:setFillColor(0.18,0.11,0.03,0.97)
            ab.strokeWidth=2; ab:setStrokeColor(1.0,0.78,0.20,0.82)
            display.newText({ parent=popup, text="AUCTION",
                x=CX+70, y=actionY, font=ui.FONT_BOLD, fontSize=12
            }):setFillColor(1.0,0.82,0.24)
            ab:addEventListener("tap", function()
                closePopup()
                buildAuctionPostPopup(sg, function() buildGrid(sg, activeTab) end, {
                    key=item.key, name=item.name, sprite=item.sprite,
                    color=item.color, qty=qty, type=item.type
                })
                return true
            end)
        end
    else
        display.newText({ parent=popup, text="None in vault",
            x=CX, y=actionY, font=ui.FONT_BOLD, fontSize=12, align="center"
        }):setFillColor(0.35,0.38,0.45)
    end

    local xb=display.newCircle(popup, CX+pw*0.5-18, CY-ph*0.5+18, 13)
    xb:setFillColor(0.25,0.04,0.04,0.97); xb.strokeWidth=1.5
    xb:setStrokeColor(0.85,0.18,0.18,0.80)
    display.newText({ parent=popup, text="✕", x=xb.x, y=xb.y-1,
        font=ui.FONT_BOLD, fontSize=12 }):setFillColor(1.0,0.30,0.30)
    xb:addEventListener("tap", function() closePopup(); return true end)
end

-------------------------------------------------
-- LOOT STRIP
-------------------------------------------------
local tabBgs  = {}
local tabTxts = {}

buildLootTabs = function(sg)
    for _, obj in ipairs(tabBgs) do
        if obj and obj.removeSelf then obj:removeSelf() end
    end
    for _, obj in ipairs(tabTxts) do
        if obj and obj.removeSelf then obj:removeSelf() end
    end
    tabBgs = {}
    tabTxts = {}

    activeTab = 1

    local LTAB_W = SW - 20
    local LTAB_H = 24
    local LTAB_Y = CONTENT_TOP + 16

    local bg=display.newRoundedRect(sg, CX, LTAB_Y, LTAB_W, LTAB_H, 4)
    bg:setFillColor(0.04, 0.18, 0.10, 0.97)
    bg.strokeWidth=1.5
    bg:setStrokeColor(0.18, 0.82, 0.42, 0.90)
    tabBgs[1]=bg
    local bt=display.newText({ parent=sg, text="GUILD VAULT",
        x=CX, y=LTAB_Y, font=ui.FONT_BOLD, fontSize=10, align="center" })
    bt:setFillColor(0.28, 1.0, 0.48)
    tabTxts[1]=bt
end

-------------------------------------------------
-- SCENE CREATE
-------------------------------------------------
function scene:create(event)
    local sg = self.view
    sceneGroupRef = sg

    local bg=display.newRect(sg, CX, CY, SW, SH); bg:setFillColor(0.02,0.03,0.08)
    for i=1,20 do
        local ln=display.newRect(sg, CX, i*(SH/20), SW, 1)
        ln:setFillColor(0.05,0.18,0.42,0.04); ln.isHitTestable=false
    end

    drawFrame(sg, CX, HEADER_Y, SW-6, HEADER_H, FRAME_SMALL)
    display.newRect(sg, CX, HEADER_H, SW, 2):setFillColor(0.15,0.55,0.35,0.55)
    display.newText({ parent=sg, text="GUILD VAULT",
        x=CX, y=HEADER_Y-14, font=ui.FONT_BOLD, fontSize=18, align="center"
    }):setFillColor(0.25,0.95,0.58)
    display.newText({ parent=sg, text="Vault  -  Donate  -  Auction",
        x=CX, y=HEADER_Y+14, font=ui.FONT_BOLD, fontSize=9, align="center"
    }):setFillColor(0.38,0.52,0.65)

    buildBottomBar(sg, 4)
    buildLootTabs(sg)
    buildActionButtons(sg)
    buildGrid(sg, activeTab)
end

-------------------------------------------------
-- SCENE SHOW
-------------------------------------------------
function scene:show(event)
    if event.phase ~= "did" then return end
    if event.params and event.params.guildId then
        guildContext.setActiveGuild(event.params.guildId, event.params.guildKey)
    end
    activeTab = 1
    if sceneGroupRef then
        buildLootTabs(sceneGroupRef)
        buildActionButtons(sceneGroupRef)
        buildGrid(sceneGroupRef, 1)
        refreshServerState(sceneGroupRef)
    end
end

-------------------------------------------------
-- SCENE HIDE
-------------------------------------------------
function scene:hide(event)
    if event.phase ~= "will" then return end
    closePopup()
    tabBgs  = {}
    tabTxts = {}
    if actionGroup then actionGroup:removeSelf(); actionGroup=nil end
end

scene:addEventListener("create", scene)
scene:addEventListener("show",   scene)
scene:addEventListener("hide",   scene)
return scene
