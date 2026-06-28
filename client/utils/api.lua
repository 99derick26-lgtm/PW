local json = require("json")
local session = require("utils.session")

local M = {}

local function joinUrl(baseUrl, path)
    if not baseUrl or baseUrl == "" then return nil end
    if not path or path == "" then return baseUrl end
    local normalizedBase = string.gsub(baseUrl, "/+$", "")
    local normalizedPath = string.gsub(path, "^/+", "")
    return normalizedBase .. "/" .. normalizedPath
end

local function buildHeaders(extraHeaders)
    local headers = {
        ["Content-Type"] = "application/json",
        ["Accept"] = "application/json",
    }

    local authHeader = session.getAuthHeader()
    if authHeader then
        headers.Authorization = authHeader
    end

    for k, v in pairs(extraHeaders or {}) do
        headers[k] = v
    end

    return headers
end

local function offlineResponse(path, method, body)
    return {
        ok = false,
        status = 0,
        offline = true,
        error = "backend_not_configured",
        path = path,
        method = method,
        requestBody = body,
    }
end

function M.health(callback)
    return M.get("/health", callback)
end

function M.dbTest(callback)
    return M.get("/db-test", callback)
end

function M.request(path, options, callback)
    options = options or {}
    local currentSession = session.get()
    local method = string.upper(options.method or "GET")
    local body = options.body
    local headers = buildHeaders(options.headers)
    local baseUrl = currentSession.baseUrl

    if not currentSession.isOnlineEnabled or not baseUrl or baseUrl == "" then
        if callback then
            timer.performWithDelay(1, function()
                callback(offlineResponse(path, method, body))
            end)
        end
        return nil
    end

    local url = joinUrl(baseUrl, path)
    local params = {
        headers = headers,
    }

    if body ~= nil then
        params.body = json.encode(body)
    end

    return network.request(url, method, function(event)
        local response = {
            ok = false,
            status = event.status or 0,
            raw = event.response,
            headers = event.responseHeaders,
            isError = event.isError or false,
            error = event.isError and (event.response or "network_error") or nil,
            data = nil,
        }

        if type(event.response) == "string" and event.response ~= "" then
            local decoded = json.decode(event.response)
            if decoded ~= nil then
                response.data = decoded
            end
        end

        response.ok = (not event.isError) and response.status >= 200 and response.status < 300

        if callback then
            callback(response)
        end
    end, params)
end

function M.get(path, callback, headers)
    return M.request(path, {
        method = "GET",
        headers = headers,
    }, callback)
end

function M.post(path, body, callback, headers)
    return M.request(path, {
        method = "POST",
        body = body,
        headers = headers,
    }, callback)
end

function M.patch(path, body, callback, headers)
    return M.request(path, {
        method = "PATCH",
        body = body,
        headers = headers,
    }, callback)
end

function M.delete(path, callback, headers)
    return M.request(path, {
        method = "DELETE",
        headers = headers,
    }, callback)
end

M.auth = {}
function M.auth.login(payload, callback)
    return M.post("/v1/auth/login", payload, callback)
end

function M.auth.register(payload, callback)
    return M.post("/v1/auth/register", payload, callback)
end

function M.auth.refresh(payload, callback)
    return M.post("/v1/auth/refresh", payload, callback)
end

M.player = {}
function M.player.me(callback)
    return M.get("/v1/player/me", callback)
end

function M.player.profiles(callback)
    return M.get("/v1/account/profiles", callback)
end

function M.player.createProfile(slot, callback)
    return M.post("/v1/account/profiles", {
        profileSlot = slot,
    }, callback)
end

function M.player.selectProfile(slot, callback)
    return M.post("/v1/account/profiles/select", {
        profileSlot = slot,
    }, callback)
end

function M.player.deleteProfile(slot, callback)
    return M.delete("/v1/account/profiles/" .. tostring(slot), callback)
end

function M.player.update(payload, callback)
    return M.patch("/v1/player/me", payload, callback)
end

function M.player.search(query, callback)
    return M.get("/v1/players/search?q=" .. tostring(query or ""), callback)
end

function M.player.get(playerId, callback)
    return M.get("/v1/players/" .. tostring(playerId), callback)
end

M.shop = {}
function M.shop.catalog(callback)
    return M.get("/v1/shop/catalog", callback)
end

function M.shop.purchase(payload, callback)
    return M.post("/v1/shop/purchase", payload, callback)
end

M.tasks = {}
function M.tasks.list(callback)
    return M.get("/v1/tasks", callback)
end

function M.tasks.claim(payload, callback)
    return M.post("/v1/tasks/claim", payload, callback)
end

M.friends = {}
function M.friends.list(callback)
    return M.get("/v1/friends", callback)
end

function M.friends.requests(callback)
    return M.get("/v1/friends/requests", callback)
end

function M.friends.sendRequest(payload, callback)
    return M.post("/v1/friends/request", payload, callback)
end

M.messages = {}
function M.messages.threads(callback)
    return M.get("/v1/messages/threads", callback)
end

function M.messages.thread(threadId, callback)
    return M.get("/v1/messages/thread/" .. tostring(threadId), callback)
end

function M.messages.withPlayer(playerName, callback)
    return M.get("/v1/messages/with/" .. tostring(playerName or ""), callback)
end

function M.messages.send(payload, callback)
    return M.post("/v1/messages/send", payload, callback)
end

M.walls = {}
function M.walls.list(playerName, callback)
    return M.get("/v1/walls/" .. tostring(playerName or ""), callback)
end

function M.walls.post(playerName, payload, callback)
    return M.post("/v1/walls/" .. tostring(playerName or ""), payload, callback)
end

M.guilds = {}
function M.guilds.search(query, callback)
    return M.get("/v1/guilds/search?q=" .. string.gsub(tostring(query or ""), "([^%w%-_%.~])", function(c)
        return string.format("%%%02X", string.byte(c))
    end), callback)
end

function M.guilds.create(payload, callback)
    return M.post("/v1/guilds", payload, callback)
end

function M.guilds.join(guildId, callback)
    return M.post("/v1/guilds/" .. tostring(guildId) .. "/join", {}, callback)
end

function M.guilds.update(guildId, payload, callback)
    return M.post("/v1/guilds/" .. tostring(guildId) .. "/update", payload or {}, callback)
end

function M.guilds.leave(guildId, callback)
    return M.post("/v1/guilds/" .. tostring(guildId) .. "/leave", {}, callback)
end

function M.guilds.setMemberRank(guildId, playerId, rank, callback)
    return M.post("/v1/guilds/" .. tostring(guildId) .. "/members/" .. tostring(playerId) .. "/rank", {
        rank = rank,
    }, callback)
end

function M.guilds.kickMember(guildId, playerId, callback)
    return M.post("/v1/guilds/" .. tostring(guildId) .. "/members/" .. tostring(playerId) .. "/kick", {}, callback)
end

function M.guilds.get(guildId, callback)
    return M.get("/v1/guilds/" .. tostring(guildId), callback)
end

function M.guilds.prepareLoot(guildId, callback)
    return M.post("/v1/guilds/" .. tostring(guildId) .. "/loot/prepare", {}, callback)
end

function M.guilds.reportLoot(guildId, payload, callback)
    return M.post("/v1/guilds/" .. tostring(guildId) .. "/loot/report", payload or {}, callback)
end

function M.guilds.wars(guildId, callback)
    return M.get("/v1/guilds/" .. tostring(guildId) .. "/wars", callback)
end

function M.guilds.declareWar(guildId, payload, callback)
    return M.post("/v1/guilds/" .. tostring(guildId) .. "/wars", payload or {}, callback)
end

function M.guilds.jail(guildId, callback)
    return M.get("/v1/guilds/" .. tostring(guildId) .. "/jail", callback)
end

function M.guilds.chat(guildId, callback)
    return M.get("/v1/guilds/" .. tostring(guildId) .. "/chat", callback)
end

function M.guilds.sendChat(guildId, payload, callback)
    return M.post("/v1/guilds/" .. tostring(guildId) .. "/chat", payload, callback)
end

function M.guilds.deleteChat(guildId, messageId, callback)
    return M.delete("/v1/guilds/" .. tostring(guildId) .. "/chat/" .. tostring(messageId), callback)
end

function M.guilds.vault(guildId, callback)
    return M.get("/v1/guilds/" .. tostring(guildId) .. "/vault", callback)
end

function M.guilds.donate(guildId, payload, callback)
    return M.post("/v1/guilds/" .. tostring(guildId) .. "/vault/donate", payload or {}, callback)
end

function M.guilds.collectLand(guildId, payload, callback)
    return M.post("/v1/guilds/" .. tostring(guildId) .. "/land/collect", payload or {}, callback)
end

function M.guilds.takeVault(guildId, payload, callback)
    return M.post("/v1/guilds/" .. tostring(guildId) .. "/vault/take", payload or {}, callback)
end

function M.guilds.contributions(guildId, callback)
    return M.get("/v1/guilds/" .. tostring(guildId) .. "/contributions", callback)
end

function M.guilds.auctions(guildId, callback)
    return M.get("/v1/guilds/" .. tostring(guildId) .. "/auctions", callback)
end

function M.guilds.postAuction(guildId, payload, callback)
    return M.post("/v1/guilds/" .. tostring(guildId) .. "/auctions", payload or {}, callback)
end

function M.guilds.bidAuction(guildId, auctionId, payload, callback)
    return M.post("/v1/guilds/" .. tostring(guildId) .. "/auctions/" .. tostring(auctionId) .. "/bid", payload or {}, callback)
end

M.chat = {}
function M.chat.world(callback)
    return M.get("/v1/chat/world", callback)
end

function M.chat.sendWorld(payload, callback)
    return M.post("/v1/chat/world", payload, callback)
end

M.pvp = {}
function M.pvp.find(payload, callback)
    return M.post("/v1/pvp/find", payload, callback)
end

function M.pvp.prepare(playerId, payload, callback)
    return M.post("/v1/pvp/prepare/" .. tostring(playerId), payload or {}, callback)
end

function M.pvp.history(callback)
    return M.get("/v1/pvp/history", callback)
end

function M.pvp.report(payload, callback)
    return M.post("/v1/pvp/report", payload or {}, callback)
end

M.tournaments = {}
function M.tournaments.status(callback)
    return M.get("/v1/tournaments/status", callback)
end

function M.tournaments.setJoined(mode, joined, callback)
    return M.post("/v1/tournaments/" .. tostring(mode) .. "/join", {
        joined = joined == true,
    }, callback)
end

M.squad = {}
function M.squad.get(callback)
    return M.get("/v1/squad", callback)
end

function M.squad.recruit(payload, callback)
    return M.post("/v1/squad/recruit", payload or {}, callback)
end

function M.squad.setTax(payload, callback)
    return M.post("/v1/squad/tax", payload or {}, callback)
end

function M.squad.liberate(payload, callback)
    return M.post("/v1/squad/liberate", payload or {}, callback)
end

function M.squad.reportFightReward(payload, callback)
    return M.post("/v1/squad/fight-reward", payload or {}, callback)
end

return M
