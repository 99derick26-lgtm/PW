local composer = require("composer")
local scene = composer.newScene()

-- Easy function to create slot boxes
local function createSlot(group, x, y, size, color)
    local box = display.newRect(group, x, y, size, size)
    box:setFillColor(unpack(color or {0.3, 0.3, 0.3}))
    box.strokeWidth = 2
    box:setStrokeColor(1, 1, 1)
    return box
end

function scene:create(event)
    local sceneGroup = self.view

    local W = display.contentWidth
    local H = display.contentHeight

    ---------------------------------------------------------
    --  TOP (60%) green background
    ---------------------------------------------------------
    local topH = H * 0.60
    local topBG = display.newRect(sceneGroup, W * 0.5, topH * 0.5, W, topH)
    topBG:setFillColor(0.1, 0.6, 0.1)  -- GREEN

    ---------------------------------------------------------
    --  BOTTOM (40%) white background
    ---------------------------------------------------------
    local bottomBG = display.newRect(sceneGroup, W * 0.5, topH + (H * 0.40 * 0.5), W, H * 0.40)
    bottomBG:setFillColor(1, 1, 1)  -- WHITE

    ---------------------------------------------------------
    -- CHARACTER & EQUIPMENT LAYOUT (TOP SECTION)
    ---------------------------------------------------------

    local slotSize = 45  -- smaller box size
    local margin = 10

    ---------------------------------------------------------
    -- HELMET (CENTER ABOVE AVATAR)
    ---------------------------------------------------------
    local helmet = createSlot(sceneGroup, W * 0.5, 20 + slotSize * 0.5, slotSize)

    ---------------------------------------------------------
    -- AVATAR BOX (CENTER)
    ---------------------------------------------------------
    local avatar = display.newRect(sceneGroup, W * 0.5, topH * 0.5, 120, 120)
    avatar:setFillColor(0.2, 0.4, 0.8)

    ---------------------------------------------------------
    -- RIGHT SIDE EQUIPMENT LIST
    ---------------------------------------------------------
    local rightX = W * 0.77
    local startY = 80

    local necklace = createSlot(sceneGroup, rightX, startY, slotSize)
    local chest    = createSlot(sceneGroup, rightX, startY + (slotSize + margin) * 1, slotSize)
    local gloves   = createSlot(sceneGroup, rightX, startY + (slotSize + margin) * 2, slotSize)
    local pants    = createSlot(sceneGroup, rightX, startY + (slotSize + margin) * 3, slotSize)
    local boots    = createSlot(sceneGroup, rightX, startY + (slotSize + margin) * 4, slotSize)

    ---------------------------------------------------------
    -- LEFT SIDE WEAPONS LIST
    ---------------------------------------------------------
    local leftX = W * 0.23
    local wStartY = 80

    local w1 = createSlot(sceneGroup, leftX, wStartY, slotSize)
    local w2 = createSlot(sceneGroup, leftX, wStartY + (slotSize + margin) * 1, slotSize)
    local w3 = createSlot(sceneGroup, leftX, wStartY + (slotSize + margin) * 2, slotSize)
    local w4 = createSlot(sceneGroup, leftX, wStartY + (slotSize + margin) * 3, slotSize)
    local w5 = createSlot(sceneGroup, leftX, wStartY + (slotSize + margin) * 4, slotSize)

    ---------------------------------------------------------
    -- TITLE
    ---------------------------------------------------------
    display.newText({
        parent = sceneGroup,
        text = "CHARACTER",
        x = W * 0.5,
        y = topH - 15,
        fontSize = 22
    })

    ---------------------------------------------------------
    -- BACK BUTTON
    ---------------------------------------------------------
    local back = display.newText({
        parent = sceneGroup,
        text = "BACK",
        x = W * 0.5,
        y = H - 30,
        fontSize = 20
    })

    back:addEventListener("tap", function()
        composer.gotoScene("scenes.home")
    end)
end

scene:addEventListener("create", scene)
return scene
