local M = {}

local function add(player, text, payload)
    if not player or not text then return nil end

    player.notifications = player.notifications or {}
    local entry = {
        id = "local_" .. tostring(os.time()) .. "_" .. tostring(math.random(1000, 9999)),
        type = (payload and payload.type) or "info",
        text = text,
        timeLabel = "NOW",
        createdAt = os.time(),
        replay = payload and payload.replay or nil,
    }
    table.insert(player.notifications, 1, entry)
    while #player.notifications > 50 do
        table.remove(player.notifications)
    end
    return entry
end

local function buildLevelUpText(summary)
    if not summary then return nil end

    local lines = {}
    if (summary.hp or 0) > 0 then lines[#lines + 1] = "HP +" .. tostring(summary.hp) end
    if (summary.attack or 0) > 0 then lines[#lines + 1] = "ATK +" .. tostring(summary.attack) end
    if (summary.defense or 0) > 0 then lines[#lines + 1] = "DEF +" .. tostring(summary.defense) end
    if (summary.speed or 0) > 0 then lines[#lines + 1] = "SPD +" .. tostring(summary.speed) end

    local text = "Level up! Lv. " .. tostring(summary.finalLevel or "?")
    if #lines > 0 then
        text = text .. " - " .. table.concat(lines, ", ")
    end
    return text
end

function M.add(player, text, payload)
    return add(player, text, payload)
end

function M.addLevelUp(player, summary)
    local text = buildLevelUpText(summary)
    if not text then return nil end
    return add(player, text, { type="level_up" })
end

return M
