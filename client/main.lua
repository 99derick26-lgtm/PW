-- main.lua
display.setStatusBar(display.HiddenStatusBar)
display.setDefault("magTextureFilter", "nearest")
display.setDefault("minTextureFilter", "nearest")

local function hideSystemUi()
    if system.getInfo("platformName") == "Android" then
        native.setProperty("androidSystemUiVisibility", "immersiveSticky")
    elseif system.getInfo("platformName") == "iPhone OS" then
        native.setProperty("prefersHomeIndicatorAutoHidden", true)
    end
end

hideSystemUi()

Runtime:addEventListener("system", function(event)
    if event.type == "applicationResume" then
        hideSystemUi()
    end
end)

local composer = require("composer")

-- TEMP: go straight to home (or arena if you want)
composer.gotoScene("scenes.login")
