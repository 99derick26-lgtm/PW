-- utils/weapons.lua
-- Pixel War Online — Weapon Rotation System
--
-- Weapons rotate only when knock pressure succeeds.
-- weapons.lua never touches items directly — just the index + use counter.

local items   = require("utils.items")
local weapons = {}

-------------------------------------------------
-- INTERNAL: ensure rotation state exists
-------------------------------------------------
local function ensureState(player)
    if not player then return end
    player.currentWeaponIndex = player.currentWeaponIndex or 1
    player.weaponPressure     = player.weaponPressure     or 0
end

local function clamp(value, minValue, maxValue)
    return math.max(minValue, math.min(maxValue, value))
end

-------------------------------------------------
-- getCurrentWeapon
-- Returns: itemDef, weaponId, pressure, totalWeapons
-------------------------------------------------
function weapons.getCurrentWeapon(player)
    if not player
        or not player.equipped
        or not player.equipped.weapons
        or #player.equipped.weapons == 0
    then
        return nil, nil, 0, 0
    end

    ensureState(player)

    local index    = player.currentWeaponIndex
    local weaponId = player.equipped.weapons[index]
    local def      = items[weaponId]
    local pressure = player.weaponPressure or 0

    return def, weaponId, pressure, #player.equipped.weapons
end

-------------------------------------------------
-- peekNextWeapon
-- Returns the weapon def + id that would come AFTER the current one.
-- Does NOT modify state. Used by the HUD to show upcoming weapon.
-------------------------------------------------
function weapons.peekNextWeapon(player)
    if not player
        or not player.equipped
        or not player.equipped.weapons
        or #player.equipped.weapons == 0
    then
        return nil, nil
    end

    ensureState(player)

    local count    = #player.equipped.weapons
    if count == 1 then
        -- only one weapon, it loops to itself
        return weapons.getCurrentWeapon(player)
    end

    local nextIndex = (player.currentWeaponIndex % count) + 1
    local weaponId  = player.equipped.weapons[nextIndex]
    return items[weaponId], weaponId
end

-------------------------------------------------
-- advanceWeapon
-- Compatibility shim: action-based rotation is disabled.
-- Returns: didRotate=false, currentWeaponDef, currentWeaponId
-------------------------------------------------
function weapons.advanceWeapon(player)
    if not player
        or not player.equipped
        or not player.equipped.weapons
        or #player.equipped.weapons == 0
    then
        return false, nil, nil
    end

    ensureState(player)

    local weaponId = player.equipped.weapons[player.currentWeaponIndex]
    return false, items[weaponId], weaponId
end

-------------------------------------------------
-- knockWeapon
-- Called when pressure knocks the weapon.
-- Weapon is treated as lost/broken — bypasses the action counter entirely
-- Returns: newWeaponDef, newWeaponId
-------------------------------------------------
function weapons.knockWeapon(player)
    if not player
        or not player.equipped
        or not player.equipped.weapons
        or #player.equipped.weapons == 0
    then
        return nil, nil
    end

    ensureState(player)

    -- force rotate immediately and reset pressure
    local count = #player.equipped.weapons
    player.currentWeaponIndex = (player.currentWeaponIndex % count) + 1
    player.weaponPressure     = 0

    local weaponId = player.equipped.weapons[player.currentWeaponIndex]
    return items[weaponId], weaponId
end

function weapons.addWeaponPressure(player, damageTaken, attackerAttack, defenderDefense, defenderMaxHp)
    if not player
        or not player.equipped
        or not player.equipped.weapons
        or #player.equipped.weapons == 0
    then
        return false, nil, nil, 0
    end

    ensureState(player)

    local threshold = math.max(1, (defenderMaxHp or 1) * 0.10)
    player.weaponPressure = (player.weaponPressure or 0) + math.max(0, damageTaken or 0)

    if player.weaponPressure < threshold then
        return false, nil, nil, 0
    end

    local pressureRatio = player.weaponPressure / threshold
    local extra = math.max(0, pressureRatio - 1) * 0.20
    local statRatio = math.max(attackerAttack or 1, 1) / math.max(defenderDefense or 1, 1)
    local knockChance = clamp((0.20 + extra) * statRatio, 0.20, 0.70)

    if math.random() < knockChance then
        local newDef, newId = weapons.knockWeapon(player)
        return true, newDef, newId, knockChance
    end

    return false, nil, nil, knockChance
end

-------------------------------------------------
-- resetRotation
-- Call at the start of each battle to reset state cleanly.
-------------------------------------------------
function weapons.resetRotation(player)
    if not player then return end
    player.currentWeaponIndex = 1
    player.weaponPressure     = 0
    player.weaponUsesLeft     = nil
end

-------------------------------------------------
-- getUsesPerWeapon (constant, for HUD)
-------------------------------------------------
function weapons.getUsesPerWeapon()
    return 0
end

return weapons
