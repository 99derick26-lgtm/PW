-- utils/tasks.lua
-- Pixel War Online — Tutorial Task System
-- One-time tasks that guide the player through core systems.
-- Tasks unlock sequentially; progress tracked in player.tasks

local tasks = {}

--------------------------------------------------
-- TASK DEFINITIONS (in order)
--------------------------------------------------
tasks.DEFS = {
    {
        id          = "fight_a_battle",
        title       = "First Blood",
        description = "Fight your first battle in the Arena",
        icon        = "fight",
        scene       = "scenes.arena",
        minLevel    = 1,
        goal        = 1,
        xpReward    = 50,
        goldReward  = 100,
    },
    {
        id          = "buy_from_shop",
        title       = "Window Shopping",
        description = "Purchase any item from the Shop",
        icon        = "shop",
        scene       = "scenes.shop",
        minLevel    = 1,
        goal        = 1,
        xpReward    = 60,
        goldReward  = 120,
    },
    {
        id          = "set_username",
        title       = "Name Yourself",
        description = "Set your username in Settings",
        icon        = "settings",
        scene       = "scenes.profile",
        minLevel    = 1,
        goal        = 1,
        xpReward    = 60,
        goldReward  = 120,
    },
    {
        id          = "enroll_tournament",
        title       = "Enter The Bracket",
        description = "Enroll in a Tournament",
        icon        = "tournament",
        scene       = "scenes.tournament",
        minLevel    = 1,
        goal        = 1,
        xpReward    = 75,
        goldReward  = 150,
    },
    {
        id          = "equip_a_pet",
        title       = "New Companion",
        description = "Equip a pet before heading into battle",
        icon        = "pet",
        scene       = "scenes.pets",
        minLevel    = 3,
        goal        = 1,
        xpReward    = 75,
        goldReward  = 150,
    },
    {
        id          = "spend_gold",
        title       = "Big Spender",
        description = "Spend 500 gold total",
        icon        = "shop",
        scene       = "scenes.shop",
        minLevel    = 4,
        goal        = 500,
        xpReward    = 80,
        goldReward  = 200,
    },
    {
        id          = "buy_a_skill",
        title       = "Power Up",
        description = "Purchase your first skill",
        icon        = "skills",
        scene       = "scenes.skills",
        minLevel    = 5,
        goal        = 1,
        xpReward    = 100,
        goldReward  = 250,
    },
}

-- Quick lookup by id
tasks.BY_ID = {}
for _, def in ipairs(tasks.DEFS) do
    tasks.BY_ID[def.id] = def
end

--------------------------------------------------
-- INIT: ensure player.tasks exists
--------------------------------------------------
function tasks.init(player)
    player.tasks = player.tasks or {}
    for _, def in ipairs(tasks.DEFS) do
        if not player.tasks[def.id] then
            player.tasks[def.id] = { progress = 0, claimed = false }
        end
    end
end

--------------------------------------------------
-- GET STATE for a single task
--------------------------------------------------
function tasks.getState(player, taskId)
    tasks.init(player)
    return player.tasks[taskId]
end

--------------------------------------------------
-- CHECK: is this task unlocked?
-- Tasks unlock sequentially — task N unlocks when task N-1 is claimed
--------------------------------------------------
function tasks.isUnlocked(player, taskId)
    tasks.init(player)
    local idx = nil
    for i, def in ipairs(tasks.DEFS) do
        if def.id == taskId then idx = i break end
    end
    if not idx then return false end
    local def = tasks.DEFS[idx]
    return (player.level or 1) >= (def.minLevel or 1)
end

--------------------------------------------------
-- ADVANCE: increment progress on a task
-- Returns true if newly completed
--------------------------------------------------
function tasks.advance(player, taskId, amount)
    tasks.init(player)
    amount = amount or 1

    if not tasks.isUnlocked(player, taskId) then return false end

    local def   = tasks.BY_ID[taskId]
    local state = player.tasks[taskId]
    if not def or not state then return false end
    if state.claimed then return false end  -- already done

    local wasComplete = state.progress >= def.goal
    state.progress = math.min(state.progress + amount, def.goal)
    local nowComplete = state.progress >= def.goal

    return (not wasComplete) and nowComplete  -- true = just hit 100%
end

--------------------------------------------------
-- CLAIM: collect rewards
-- Returns xpReward, goldReward or nil if not claimable
--------------------------------------------------
function tasks.claim(player, taskId)
    tasks.init(player)
    local def   = tasks.BY_ID[taskId]
    local state = player.tasks[taskId]
    if not def or not state then return nil end
    if state.claimed then return nil end
    if state.progress < def.goal then return nil end

    state.claimed  = true
    player.xp      = (player.xp   or 0) + def.xpReward
    player.gold    = (player.gold  or 0) + def.goldReward

    return def.xpReward, def.goldReward
end

--------------------------------------------------
-- GET ALL VISIBLE TASKS
-- Shows all unlocked tasks plus the next locked task as a teaser
--------------------------------------------------
function tasks.getVisible(player)
    tasks.init(player)
    local visible = {}
    local shownLocked = false

    for _, def in ipairs(tasks.DEFS) do
        local unlocked = tasks.isUnlocked(player, def.id)
        local state    = player.tasks[def.id]

        if unlocked then
            table.insert(visible, {
                def      = def,
                state    = state,
                unlocked = true,
            })
        elseif not shownLocked then
            -- show next locked task as a teaser
            table.insert(visible, {
                def      = def,
                state    = state,
                unlocked = false,
            })
            shownLocked = true
        end
    end

    return visible
end

--------------------------------------------------
-- HAS UNCLAIMED COMPLETED TASKS (for notification dot)
--------------------------------------------------
function tasks.hasClaimable(player)
    tasks.init(player)
    for _, def in ipairs(tasks.DEFS) do
        local state = player.tasks[def.id]
        if state and state.progress >= def.goal and not state.claimed then
            return true
        end
    end
    return false
end

return tasks
