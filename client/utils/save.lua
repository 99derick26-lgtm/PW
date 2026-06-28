local json = require("json")
local M    = {}
local guildContext = require("utils.guild_context")

-------------------------------------------------
-- ACTIVE PROFILE (set on profile select screen)
-------------------------------------------------
M.activeSlot = 1   -- 1..5, set before going to home
M.accountKey = "default"

local function safeKey(value)
    local key = tostring(value or "default"):lower():gsub("[^%w_%-]", "_")
    if key == "" then key = "default" end
    return key
end

function M.setAccountKey(value)
    M.accountKey = safeKey(value)
end

-------------------------------------------------
-- DEFAULT TEMPLATE
-------------------------------------------------
local function defaultPlayer(name)
    return {
        name    = tostring(name or "1"),
        level   = 1,
        xp      = 0,
        gold    = 6000,
        attack  = 100,
        defense = 100,
        intelligence = 5,
        speed   = 100,
        hp      = 100,
        inventory = {},
        equipped = {
            weapons = { "dagger_basic", "katana_speed", "scrap_gun" },
            armor   = { helmet=nil, chest=nil, gloves=nil, boots=nil },
            pets    = {},
        },
        currentWeaponIndex = 1,
        materials = {
            scrap=0, coil=0, chip=0,
            crystal_green=0, crystal_blue=0, crystal_purple=0, crystal_orange=0,
            augment_attack=0, augment_defense=0, augment_health=0, augment_speed=0,
        },
        winRate   = "0%",
        diamonds  = 0,
        energy    = 30,
        energyTs  = os.time(),
        spells    = {},
        tasks     = {},
        chests    = { common = 0, rare = 0 },
        petAugments = {},
        injections = { active = {}, cooldowns = {} },
        arenaFights = 0,
        arenaWins = 0,
    }
end

-------------------------------------------------
-- HELPERS
-------------------------------------------------
local function copyTable(t)
    local copy = {}
    for k, v in pairs(t) do
        copy[k] = type(v) == "table" and copyTable(v) or v
    end
    return copy
end

local function pathForSlot(slot)
    return system.pathForFile(
        "account_" .. M.accountKey .. "_profile_" .. slot .. ".json",
        system.DocumentsDirectory
    )
end

local function pathForAccountSlot(accountKey, slot)
    return system.pathForFile(
        "account_" .. safeKey(accountKey) .. "_profile_" .. slot .. ".json",
        system.DocumentsDirectory
    )
end

local function normalizeBaseStats(data)
    if data.statBaselineMigrated then return end

    -- Older saves started at 5/5/5/20. Lift that baseline to 100
    -- while preserving any level-up points already earned on top.
    if (data.attack or 0) < 100 then
        data.attack = (data.attack or 5) + 95
    end
    if (data.defense or 0) < 100 then
        data.defense = (data.defense or 5) + 95
    end
    if (data.speed or 0) < 100 then
        data.speed = (data.speed or 5) + 95
    end
    if (data.hp or 0) < 100 then
        data.hp = (data.hp or 20) + 80
    end

    data.statBaselineMigrated = true
end

local function maxBaseHpForLevel(level)
    local hp = 100
    level = math.max(1, tonumber(level) or 1)
    for currentLevel = 2, level do
        local totalPoints = currentLevel <= 10 and 20 or 30
        hp = hp + math.floor(totalPoints * 0.45)
    end
    return hp
end

local function repairInflatedHp(data)
    local maxHp = maxBaseHpForLevel(data.level)
    if (data.hp or 0) > maxHp * 2 then
        data.hp = maxHp
    end
end

-------------------------------------------------
-- PROFILES INDEX  (profiles.json)
-- Stores: { slots = { [1]=name|nil, ... } }
-------------------------------------------------
local function indexPath()
    return system.pathForFile("account_" .. M.accountKey .. "_profiles.json", system.DocumentsDirectory)
end

local function indexPathForAccount(accountKey)
    return system.pathForFile("account_" .. safeKey(accountKey) .. "_profiles.json", system.DocumentsDirectory)
end

local function loadIndex()
    local f = io.open(indexPath(), "r")
    if not f then return { slots = {} } end
    local raw = f:read("*a"); io.close(f)
    return json.decode(raw) or { slots = {} }
end

local function loadIndexForAccount(accountKey)
    local f = io.open(indexPathForAccount(accountKey), "r")
    if not f then return { slots = {} } end
    local raw = f:read("*a"); io.close(f)
    return json.decode(raw) or { slots = {} }
end

local function loadAccounts()
    local path = system.pathForFile("local_accounts.json", system.DocumentsDirectory)
    local f = io.open(path, "r")
    if not f then return { accounts = {} } end
    local raw = f:read("*a"); io.close(f)
    return json.decode(raw) or { accounts = {} }
end

local function normalizeLoadedProfile(data)
    normalizeBaseStats(data)
    repairInflatedHp(data)
    data.inventory  = data.inventory  or {}
    data.equipped   = data.equipped   or {}
    data.equipped.weapons = data.equipped.weapons or {}
    data.equipped.armor   = data.equipped.armor   or {}
    data.equipped.pets    = data.equipped.pets    or {}
    data.equipped.accessories = data.equipped.accessories or {}
    if #data.equipped.weapons == 0 then
        data.currentWeaponIndex = nil
    else
        data.currentWeaponIndex = math.min(math.max(1, tonumber(data.currentWeaponIndex or 1) or 1), #data.equipped.weapons)
    end
    data.materials  = data.materials  or { scrap=0, coil=0, chip=0 }
    data.materials.scrap           = data.materials.scrap           or 0
    data.materials.coil            = data.materials.coil            or 0
    data.materials.chip            = data.materials.chip            or 0
    data.materials.crystal_green   = data.materials.crystal_green   or 0
    data.materials.crystal_blue    = data.materials.crystal_blue    or 0
    data.materials.crystal_purple  = data.materials.crystal_purple  or 0
    data.materials.crystal_orange  = data.materials.crystal_orange  or 0
    data.materials.augment_attack  = data.materials.augment_attack  or 0
    data.materials.augment_defense = data.materials.augment_defense or 0
    data.materials.augment_health  = data.materials.augment_health  or 0
    data.materials.augment_speed   = data.materials.augment_speed   or 0
    data.winRate    = data.winRate    or "0%"
    data.diamonds   = data.diamonds   or 0
    data.energy     = data.energy     or 30
    data.energyTs   = data.energyTs   or os.time()
    data.spells     = data.spells     or {}
    data.tasks      = data.tasks      or {}
    data.chests     = data.chests     or { common = 0, rare = 0 }
    data.petAugments = data.petAugments or {}
    data.injections = data.injections or {}
    data.injections.active = data.injections.active or {}
    data.injections.cooldowns = data.injections.cooldowns or {}
    data.arenaFights = math.max(0, tonumber(data.arenaFights or 0) or 0)
    data.arenaWins   = math.max(0, tonumber(data.arenaWins or 0) or 0)
    if data.arenaWins > data.arenaFights then
        data.arenaWins = data.arenaFights
    end
    if data.arenaFights > 0 then
        local rate = (data.arenaWins / data.arenaFights) * 100
        data.winRate = tostring(math.floor(rate + 0.5)) .. "%"
    else
        data.winRate = data.winRate or "0%"
    end
    guildContext.normalizePlayer(data)
    return data
end

local function loadProfileForAccount(accountKey, slot)
    local f = io.open(pathForAccountSlot(accountKey, slot), "r")
    if not f then return nil end
    local raw = f:read("*a"); io.close(f)
    local data = json.decode(raw)
    if not data then return nil end
    return normalizeLoadedProfile(data)
end

local function saveIndex(idx)
    local f = io.open(indexPath(), "w")
    if not f then return end
    f:write(json.encode(idx)); io.close(f)
end

-------------------------------------------------
-- PUBLIC: list all profile slots
-- Returns table[1..5]:  { slot, name } or nil
-------------------------------------------------
function M.listProfiles()
    local idx  = loadIndex()
    local list = {}
    for i = 1, 5 do
        local name = idx.slots[i]   -- nil = empty slot
        list[i] = name and { slot=i, name=name } or nil
    end
    return list
end

-------------------------------------------------
-- PUBLIC: create a new profile in the next open slot
-- Returns slot number, or nil if full
-------------------------------------------------
function M.createProfile(name)
    local idx = loadIndex()
    for i = 1, 5 do
        if not idx.slots[i] then
            name = tostring(name or i)
            idx.slots[i] = name
            saveIndex(idx)
            -- write default save file for that slot
            local p = defaultPlayer(name)
            local f = io.open(pathForSlot(i), "w")
            if f then f:write(json.encode(p)); io.close(f) end
            return i
        end
    end
    return nil  -- all 5 slots taken
end

function M.renameProfile(slot, name)
    slot = tonumber(slot or M.activeSlot) or M.activeSlot
    name = tostring(name or ""):match("^%s*(.-)%s*$")
    if name == "" then return false end

    local idx = loadIndex()
    if not idx.slots[slot] then return false end
    idx.slots[slot] = name
    saveIndex(idx)

    local player = M.load(slot)
    player.name = name
    M.save(player, slot)
    return true
end

-------------------------------------------------
-- PUBLIC: delete a profile slot
-------------------------------------------------
function M.deleteProfile(slot)
    local idx = loadIndex()
    idx.slots[slot] = nil
    saveIndex(idx)
    -- remove save file
    local path = pathForSlot(slot)
    local f = io.open(path, "r")
    if f then io.close(f); os.remove(path) end
end

-------------------------------------------------
-- PUBLIC: load active profile (or slot override)
-------------------------------------------------
function M.load(slot)
    slot = slot or M.activeSlot
    local path = pathForSlot(slot)
    local f    = io.open(path, "r")
    if not f then return defaultPlayer("Player") end
    local raw  = f:read("*a"); io.close(f)
    local data = json.decode(raw)
    if not data then return defaultPlayer("Player") end
    return normalizeLoadedProfile(data)
end

-------------------------------------------------
-- PUBLIC: save active profile (or slot override)
-------------------------------------------------
function M.save(playerData, slot)
    slot = slot or M.activeSlot
    playerData = normalizeLoadedProfile(playerData or defaultPlayer("Player"))
    local f = io.open(pathForSlot(slot), "w")
    if not f then return end
    f:write(json.encode(playerData)); io.close(f)
end

function M.recordArenaFight(playerData, won)
    if not playerData then return nil end
    playerData.arenaFights = math.max(0, tonumber(playerData.arenaFights or 0) or 0) + 1
    if won then
        playerData.arenaWins = math.max(0, tonumber(playerData.arenaWins or 0) or 0) + 1
    end
    if playerData.arenaWins > playerData.arenaFights then
        playerData.arenaWins = playerData.arenaFights
    end
    if playerData.arenaFights > 0 then
        local rate = (playerData.arenaWins / playerData.arenaFights) * 100
        playerData.winRate = tostring(math.floor(rate + 0.5)) .. "%"
    else
        playerData.winRate = "0%"
    end
    return playerData
end

function M.getArenaWinRate(playerData, fallback)
    local fights = math.max(0, tonumber(playerData and playerData.arenaFights or 0) or 0)
    local wins   = math.max(0, tonumber(playerData and playerData.arenaWins or 0) or 0)
    if wins > fights then
        wins = fights
    end
    if fights > 0 then
        return tostring(math.floor((wins / fights) * 100 + 0.5)) .. "%"
    end
    if type(fallback) == "string" and fallback ~= "" then
        return fallback
    end
    return "0%"
end

function M.searchProfiles(query)
    query = tostring(query or ""):lower()
    local out = {}
    if query == "" then return out end

    local accounts = loadAccounts().accounts or {}
    for accountKey, account in pairs(accounts) do
        local idx = loadIndexForAccount(accountKey)
        local userId = tostring((account and account.userId) or accountKey)
        for slot = 1, 5 do
            local profileName = idx.slots[slot]
            if profileName then
                local haystack = (userId .. " " .. tostring(profileName)):lower()
                if string.find(haystack, query, 1, true) then
                    local player = loadProfileForAccount(accountKey, slot) or defaultPlayer(profileName)
                    player.displayName = player.name or profileName
                    player.playerId = "local_" .. safeKey(accountKey) .. "_" .. tostring(slot)
                    player.accountKey = accountKey
                    player.accountName = userId
                    player.profileSlot = slot
                    player.status = (accountKey == M.accountKey) and "online" or "offline"
                    player.currentScene = player.currentScene or "Home"
                    player.primaryGuild = player.guild or player.createdGuild
                    player.localProfile = true
                    table.insert(out, player)
                end
            end
        end
    end

    table.sort(out, function(a, b)
        return tostring(a.displayName or a.name) < tostring(b.displayName or b.name)
    end)
    return out
end

return M
