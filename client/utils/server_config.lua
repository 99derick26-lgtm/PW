local M = {}

-- Change this when you want a different backend for your build.
-- "local"   = your PC server, for UI/dev testing
-- "railway" = live Railway server
M.SERVER_MODE = "railway"

M.URLS = {
    localServer = "http://192.168.1.250:3000",
    railway = "https://upbeat-intuition-production.up.railway.app",
}

function M.getBaseUrl()
    if M.SERVER_MODE == "railway" then
        return M.URLS.railway
    end
    return M.URLS.localServer
end

function M.isKnownServerUrl(url)
    if type(url) ~= "string" then return false end
    return url == M.URLS.localServer
        or url == M.URLS.railway
        or url == "http://192.168.1.77:3000"
end

return M
