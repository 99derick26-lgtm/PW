local json = require("json")

local M = {}

local SESSION_FILENAME = "session.json"
local DEFAULT_BASE_URL = "http://192.168.1.250:3000"
local OLD_BASE_URLS = {
    ["http://192.168.1.77:3000"] = true,
}

local state = {
    baseUrl = DEFAULT_BASE_URL,
    accessToken = nil,
    refreshToken = nil,
    playerId = nil,
    accountId = nil,
    accountKey = nil,
    userId = nil,
    isOnlineEnabled = true,
}

local function sessionPath()
    return system.pathForFile(SESSION_FILENAME, system.DocumentsDirectory)
end

local function copyTable(src)
    local out = {}
    for k, v in pairs(src or {}) do
        out[k] = v
    end
    return out
end

local function isLoopbackUrl(url)
    if type(url) ~= "string" then return false end
    return string.find(url, "://localhost", 1, true) ~= nil
        or string.find(url, "://127.0.0.1", 1, true) ~= nil
end

local function isStaleDefaultUrl(url)
    return type(url) == "string" and OLD_BASE_URLS[url] == true
end

local function persist()
    local path = sessionPath()
    local file = io.open(path, "w")
    if not file then return false end
    file:write(json.encode(state))
    io.close(file)
    return true
end

local function makeAccountKey()
    local ok, deviceId = pcall(function()
        return system and system.getInfo and system.getInfo("deviceID")
    end)
    if ok and deviceId and deviceId ~= "" then
        return "device_" .. tostring(deviceId)
    end

    math.randomseed(os.time())
    return "acct_" .. tostring(os.time()) .. "_" .. tostring(math.random(100000, 999999))
end

function M.load()
    local path = sessionPath()
    local file = io.open(path, "r")
    if not file then
        return copyTable(state)
    end

    local raw = file:read("*a")
    io.close(file)

    local decoded = json.decode(raw)
    if type(decoded) == "table" then
        for k, v in pairs(decoded) do
            state[k] = v
        end
    end

    if not state.baseUrl or state.baseUrl == "" or isLoopbackUrl(state.baseUrl) or isStaleDefaultUrl(state.baseUrl) then
        state.baseUrl = DEFAULT_BASE_URL
    end

    if not state.accountKey or state.accountKey == "" then
        state.accountKey = makeAccountKey()
        persist()
    end

    state.isOnlineEnabled = (type(state.baseUrl) == "string" and state.baseUrl ~= "")

    return copyTable(state)
end

function M.get()
    return copyTable(state)
end

function M.setBaseUrl(baseUrl)
    if isLoopbackUrl(baseUrl) or isStaleDefaultUrl(baseUrl) then
        baseUrl = DEFAULT_BASE_URL
    end
    state.baseUrl = baseUrl
    state.isOnlineEnabled = (type(baseUrl) == "string" and baseUrl ~= "")
    persist()
    return M.get()
end

function M.setTokens(accessToken, refreshToken)
    state.accessToken = accessToken
    state.refreshToken = refreshToken or state.refreshToken
    persist()
    return M.get()
end

function M.setIdentity(identity)
    identity = identity or {}
    state.playerId = identity.playerId or state.playerId
    state.accountId = identity.accountId or state.accountId
    state.accountKey = identity.accountKey or state.accountKey
    state.userId = identity.userId or state.userId
    persist()
    return M.get()
end

function M.getAccountKey()
    if not state.accountKey or state.accountKey == "" then
        state.accountKey = makeAccountKey()
        persist()
    end
    return state.accountKey
end

function M.clear()
    state.accessToken = nil
    state.refreshToken = nil
    state.playerId = nil
    state.accountId = nil
    persist()
    return M.get()
end

function M.isConfigured()
    return state.isOnlineEnabled and type(state.baseUrl) == "string" and state.baseUrl ~= ""
end

function M.getAuthHeader()
    if not state.accessToken or state.accessToken == "" then
        return nil
    end
    return "Bearer " .. state.accessToken
end

M.load()

return M
