local M = {}

local SECONDS_PER_DAY = 86400

local function daysFromCivil(year, month, day)
    year = year - (month <= 2 and 1 or 0)
    local era = math.floor(year / 400)
    local yoe = year - era * 400
    local mp = month + (month > 2 and -3 or 9)
    local doy = math.floor((153 * mp + 2) / 5) + day - 1
    local doe = yoe * 365 + math.floor(yoe / 4) - math.floor(yoe / 100) + doy
    return era * 146097 + doe - 719468
end

local function utcEpoch(year, month, day, hour, min, sec)
    return daysFromCivil(year, month, day) * SECONDS_PER_DAY
        + (hour or 0) * 3600
        + (min or 0) * 60
        + (sec or 0)
end

function M.parse(value)
    if type(value) == "number" then
        return value
    end
    if type(value) ~= "string" then
        return nil
    end

    local numeric = tonumber(value)
    if numeric then
        return numeric
    end

    local y, mo, d, h, mi, s = value:match("^(%d+)%-(%d+)%-(%d+)T(%d+):(%d+):(%d+)")
    if y then
        return utcEpoch(
            tonumber(y), tonumber(mo), tonumber(d),
            tonumber(h), tonumber(mi), tonumber(s)
        )
    end

    return nil
end

function M.fromTimestamp(value, fallback)
    local epoch = M.parse(value)
    if not epoch then
        return fallback or ""
    end

    local elapsed = math.max(0, os.time() - epoch)
    if elapsed < 60 then
        return "NOW"
    end
    if elapsed < 3600 then
        return tostring(math.floor(elapsed / 60)) .. "m"
    end
    if elapsed < SECONDS_PER_DAY then
        return tostring(math.floor(elapsed / 3600)) .. "h"
    end

    return os.date("%m/%d/%Y", epoch)
end

function M.forMessage(message)
    if not message then return "" end
    return M.fromTimestamp(
        message.sentAt or message.createdAt or message.time,
        message.timeLabel or ""
    )
end

return M
