loadstring([==[
--[[
  AETHER / Nightfall V2
  Roblox client UI: Main, Visuals, ESP, Settings
  Toggle: F6 (Fn + F6 on keyboards using media keys)
  ESP labels roles only when a game exposes that information to the client.
  Unknown roles are gray, not silently identified as innocent.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local Lighting = game:GetService("Lighting")

local localPlayer = Players.LocalPlayer
assert(localPlayer, "AETHER requires a Roblox client")
local scope = (type(getgenv) == "function" and getgenv()) or _G
-- Preserve the last chosen speed within this Roblox client session.
local storedSpeed = tonumber(scope.AetherNightfallSavedSpeed)
if scope.AetherNightfall and type(scope.AetherNightfall.Destroy) == "function" then
    pcall(scope.AetherNightfall.Destroy)
end
if scope.AetherVisuals and type(scope.AetherVisuals.Destroy) == "function" then
    pcall(scope.AetherVisuals.Destroy)
end

local alive = true
local listeners = {}
local boxes = {}
local humanoidListener
local selectedPreset = 1
local navButtons = {}
local pages = {}
local currentPage = "Main"
local menuOpen = true

local theme = {
    bg = Color3.fromRGB(6, 11, 20),
    side = Color3.fromRGB(7, 13, 24),
    panel = Color3.fromRGB(11, 19, 32),
    card = Color3.fromRGB(15, 26, 41),
    cardHover = Color3.fromRGB(22, 36, 56),
    border = Color3.fromRGB(37, 61, 80),
    primary = Color3.fromRGB(153, 217, 245),
    text = Color3.fromRGB(223, 235, 247),
    muted = Color3.fromRGB(116, 142, 159),
    red = Color3.fromRGB(255, 89, 103),
    green = Color3.fromRGB(91, 224, 160),
    blue = Color3.fromRGB(104, 194, 255),
    gray = Color3.fromRGB(161, 169, 186),
}

local function connect(signal, callback)
    local conn = signal:Connect(callback)
    table.insert(listeners, conn)
    return conn
end

local function make(class, parent, props)
    local object = Instance.new(class)
    for name, value in pairs(props or {}) do object[name] = value end
    object.Parent = parent
    return object
end

local function corners(parent, pixels)
    return make("UICorner", parent, {CornerRadius = UDim.new(0, pixels)})
end

local function border(parent, color, opacity, width)
    return make("UIStroke", parent, {
        Color = color or theme.border,
        Transparency = opacity or 0,
        Thickness = width or 1,
        ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
    })
end

local function motion(object, changes, seconds)
    if not object or not object.Parent then return end
    TweenService:Create(object, TweenInfo.new(
        seconds or 0.22, Enum.EasingStyle.Quart, Enum.EasingDirection.Out
    ), changes):Play()
end

local function label(parent, value, x, y, w, h, size, color, bold)
    return make("TextLabel", parent, {
        BackgroundTransparency = 1,
        Position = UDim2.fromOffset(x, y),
        Size = UDim2.fromOffset(w, h),
        Text = value,
        TextSize = size or 12,
        TextColor3 = color or theme.text,
        Font = bold and Enum.Font.GothamBold or Enum.Font.Gotham,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextYAlignment = Enum.TextYAlignment.Center,
        TextTruncate = Enum.TextTruncate.AtEnd,
    })
end

local function button(parent, value, x, y, w, h)
    local b = make("TextButton", parent, {
        Position = UDim2.fromOffset(x, y),
        Size = UDim2.fromOffset(w, h),
        BackgroundColor3 = theme.card,
        BackgroundTransparency = 0.08,
        BorderSizePixel = 0,
        Text = value,
        TextColor3 = theme.text,
        TextSize = 11,
        Font = Enum.Font.GothamBold,
        AutoButtonColor = false,
    })
    corners(b, 7)
    border(b, theme.border, 0.2)
    connect(b.MouseEnter, function()
        motion(b, {BackgroundColor3 = theme.cardHover}, 0.14)
    end)
    connect(b.MouseLeave, function()
        motion(b, {BackgroundColor3 = theme.card}, 0.14)
    end)
    return b
end

local function card(parent, y, h, title, subtitle)
    local frame = make("Frame", parent, {
        Position = UDim2.fromOffset(0, y),
        Size = UDim2.fromOffset(445, h),
        BackgroundColor3 = theme.card,
        BackgroundTransparency = 0.14,
        BorderSizePixel = 0,
    })
    corners(frame, 9)
    border(frame, theme.border, 0.27)
    if title then label(frame, title, 13, 9, 280, 18, 12, theme.text, true) end
    if subtitle then label(frame, subtitle, 13, 27, 390, 15, 10, theme.muted) end
    return frame
end

-- The server may reset movement. This re-applies the local setting while enabled.
-- Server-controlled games can still override movement; no bypass is guaranteed.
local originalSpeed = 16
local character = localPlayer.Character
local humanoid = character and character:FindFirstChildOfClass("Humanoid")
if humanoid then originalSpeed = humanoid.WalkSpeed end
local wantedSpeed = math.clamp(storedSpeed or originalSpeed, 8, 200)
scope.AetherNightfallSavedSpeed = wantedSpeed
local speedLock = true
local speedSyncing = false
local camera = workspace.CurrentCamera
local originalFov = camera and camera.FieldOfView or 70
local wantedFov = originalFov
local fovLock = true

local function keepSpeed()
    if not alive or not speedLock then return end
    local characterNow = localPlayer.Character
    local h = characterNow and characterNow:FindFirstChildOfClass("Humanoid")
    if h and h.Health > 0 and math.abs(h.WalkSpeed - wantedSpeed) > 0.01 then
        h.WalkSpeed = wantedSpeed
    end
end

local function bindHumanoid(h)
    if humanoidListener then humanoidListener:Disconnect() end
    humanoid = h
    if not h then return end
    if speedLock then keepSpeed() end
    -- Roblox/game spawn scripts can set WalkSpeed after Humanoid is created.
    -- Apply again once the character is fully initialized.
    task.delay(0.15, function() if alive and humanoid == h then keepSpeed() end end)
    task.delay(1.0, function() if alive and humanoid == h then keepSpeed() end end)
    humanoidListener = h:GetPropertyChangedSignal("WalkSpeed"):Connect(function()
        if not speedLock or speedSyncing or not alive then return end
        speedSyncing = true
        task.defer(function()
            if alive then keepSpeed() end
            speedSyncing = false
        end)
    end)
end

if humanoid then bindHumanoid(humanoid) end
connect(localPlayer.CharacterAdded, function(newCharacter)
    task.spawn(function()
        local h = newCharacter:WaitForChild("Humanoid", 15)
        if alive and h then bindHumanoid(h) end
    end)
end)

local originalLighting = {
    Ambient = Lighting.Ambient,
    OutdoorAmbient = Lighting.OutdoorAmbient,
    Brightness = Lighting.Brightness,
    ClockTime = Lighting.ClockTime,
    ExposureCompensation = Lighting.ExposureCompensation,
}

local colorCorrection = make("ColorCorrectionEffect", Lighting, {
    Name = "AetherNightfallColor", Enabled = false,
})
local bloom = make("BloomEffect", Lighting, {
    Name = "AetherNightfallBloom", Enabled = false, Threshold = 1.1, Size = 40,
})
local sunrays = make("SunRaysEffect", Lighting, {
    Name = "AetherNightfallRays", Enabled = false,
})

local presets = {
    {name = "ORIGINAL", color = theme.gray},
    {name = "CINEMATIC", color = theme.blue, time = 17.6, ambient = Color3.fromRGB(59, 68, 88),
        tint = Color3.fromRGB(246, 233, 221), contrast = 0.19, saturation = -0.08, glow = 0.35, rays = 0.08},
    {name = "NEON", color = Color3.fromRGB(102, 229, 255), time = 21, ambient = Color3.fromRGB(58, 45, 111),
        tint = Color3.fromRGB(178, 209, 255), contrast = 0.26, saturation = 0.19, glow = 1.0, rays = 0},
    {name = "SUNSET", color = Color3.fromRGB(255, 175, 115), time = 17.8, ambient = Color3.fromRGB(125, 76, 76),
        tint = Color3.fromRGB(255, 207, 170), contrast = 0.12, saturation = 0.16, glow = 0.65, rays = 0.16},
    {name = "NOIR", color = Color3.fromRGB(211, 222, 233), time = 14, ambient = Color3.fromRGB(89, 89, 89),
        tint = Color3.fromRGB(245, 245, 255), contrast = 0.35, saturation = -1, glow = 0.1, rays = 0},
    {name = "DREAM", color = Color3.fromRGB(231, 137, 250), time = 10, ambient = Color3.fromRGB(126, 81, 139),
        tint = Color3.fromRGB(255, 211, 250), contrast = 0.08, saturation = 0.2, glow = 1.15, rays = 0.06},
}

local presetButtons = {}
local function restoreLighting()
    for key, value in pairs(originalLighting) do Lighting[key] = value end
    colorCorrection.Enabled = false
    bloom.Enabled = false
    sunrays.Enabled = false
end

local function applyPreset(index)
    selectedPreset = index
    local p = presets[index]
    if not p then return end
    restoreLighting()
    if index > 1 then
        Lighting.ClockTime = p.time
        Lighting.Ambient = p.ambient
        Lighting.OutdoorAmbient = p.ambient
        Lighting.Brightness = 2
        Lighting.ExposureCompensation = 0.08
        colorCorrection.Enabled = true
        colorCorrection.TintColor = p.tint
        colorCorrection.Contrast = p.contrast
        colorCorrection.Saturation = p.saturation
        colorCorrection.Brightness = 0
        bloom.Enabled = p.glow > 0
        bloom.Intensity = p.glow
        sunrays.Enabled = p.rays > 0
        sunrays.Intensity = p.rays
        sunrays.Spread = 0.7
    end
    for i, b in ipairs(presetButtons) do
        local on = i == index
        motion(b, {BackgroundColor3 = on and Color3.fromRGB(33, 60, 78) or theme.card}, 0.17)
        motion(b.UIStroke, {Color = on and presets[i].color or theme.border}, 0.17)
        b.TextColor3 = on and theme.primary or theme.text
    end
end

local parent = localPlayer:WaitForChild("PlayerGui")
if type(gethui) == "function" then
    local ok, result = pcall(gethui)
    if ok and result then parent = result end
end

local espGui = make("ScreenGui", parent, {
    Name = "AetherNightfallESP", ResetOnSpawn = false,
    IgnoreGuiInset = true, DisplayOrder = 8080,
    ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
})
local gui = make("ScreenGui", parent, {
    Name = "AetherNightfallUI", ResetOnSpawn = false,
    IgnoreGuiInset = true, DisplayOrder = 8090,
    ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
})

local panel = make("Frame", gui, {
    Position = UDim2.fromScale(0.5, 0.5),
    AnchorPoint = Vector2.new(0.5, 0.5),
    Size = UDim2.fromOffset(842, 502),
    BackgroundColor3 = theme.bg,
    BackgroundTransparency = 0.03,
    BorderSizePixel = 0,
    ClipsDescendants = true,
})
corners(panel, 10)
border(panel, Color3.fromRGB(53, 87, 104), 0.05)
make("UIGradient", panel, {
    Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, Color3.fromRGB(10, 21, 35)),
        ColorSequenceKeypoint.new(0.6, Color3.fromRGB(7, 14, 26)),
        ColorSequenceKeypoint.new(1, Color3.fromRGB(4, 10, 19)),
    }), Rotation = 28,
})

local scale = make("UIScale", panel, {Scale = 0.9})
local function rescale()
    local c = workspace.CurrentCamera
    if not c then return end
    local vp = c.ViewportSize
    scale.Scale = math.min(1, (vp.X - 30) / 842, (vp.Y - 30) / 502)
end
rescale()

local sidebar = make("Frame", panel, {
    Position = UDim2.fromOffset(0, 0), Size = UDim2.fromOffset(137, 502),
    BackgroundColor3 = theme.side, BackgroundTransparency = 0.14,
    BorderSizePixel = 0,
})
make("Frame", panel, {
    Position = UDim2.fromOffset(137, 0), Size = UDim2.fromOffset(1, 502),
    BackgroundColor3 = theme.border, BackgroundTransparency = 0.35,
    BorderSizePixel = 0,
})

label(sidebar, "@nightfall", 12, 10, 120, 21, 12, theme.primary, true)
label(sidebar, "CONTROL CENTER", 12, 32, 123, 15, 9, theme.muted, true)
label(sidebar, "MODULES", 12, 77, 112, 15, 9, theme.muted, true)

local pageHost = make("Frame", panel, {
    Position = UDim2.fromOffset(156, 53), Size = UDim2.fromOffset(445, 436),
    BackgroundTransparency = 1,
})
local header = make("Frame", panel, {
    Position = UDim2.fromOffset(151, 0), Size = UDim2.fromOffset(675, 45),
    BackgroundTransparency = 1,
})
label(header, "AETHER  /  NIGHTFALL", 5, 8, 345, 20, 14, theme.text, true)
local status = label(header, "●  GAME DATA READY", 387, 10, 190, 17, 10, theme.muted, true)

local close = button(header, "×", 630, 8, 28, 25)
close.TextSize = 20

local preview = make("Frame", panel, {
    Position = UDim2.fromOffset(620, 53), Size = UDim2.fromOffset(208, 436),
    BackgroundColor3 = theme.panel, BackgroundTransparency = 0.15,
    BorderSizePixel = 0,
})
corners(preview, 8)
border(preview, theme.border, 0.1)
label(preview, "LIVE PREVIEW", 12, 10, 150, 18, 10, theme.primary, true)
local avatar = make("ImageLabel", preview, {
    Position = UDim2.fromOffset(8, 49), Size = UDim2.fromOffset(192, 291),
    BackgroundTransparency = 1,
    Image = "", ScaleType = Enum.ScaleType.Fit,
})
label(preview, "PLAYER", 12, 352, 170, 13, 9, theme.muted, true)
label(preview, localPlayer.DisplayName, 12, 369, 188, 20, 13, theme.text, true)
label(preview, "F6  •  TOGGLE MENU", 12, 401, 184, 20, 10, theme.muted, true)
task.spawn(function()
    local ok, url = pcall(function()
        return Players:GetUserThumbnailAsync(
            localPlayer.UserId, Enum.ThumbnailType.AvatarThumbnail,
            Enum.ThumbnailSize.Size420x420
        )
    end)
    if alive and ok and avatar.Parent then avatar.Image = url end
end)

local function page(name)
    local f = make("Frame", pageHost, {
        Name = name, Size = UDim2.fromScale(1, 1),
        BackgroundTransparency = 1, Visible = false,
    })
    pages[name] = f
    return f
end

local mainPage = page("Main")
local visualsPage = page("Visuals")
local espPage = page("ESP")
local settingsPage = page("Settings")

local function showPage(name)
    currentPage = name
    for pageName, frame in pairs(pages) do frame.Visible = (pageName == name) end
    for navName, b in pairs(navButtons) do
        local active = navName == name
        motion(b, {BackgroundColor3 = active and Color3.fromRGB(28, 44, 58) or theme.side}, 0.17)
        b.TextColor3 = active and theme.primary or theme.muted
    end
end

for i, name in ipairs({"Main", "Visuals", "ESP", "Settings"}) do
    local nav = button(sidebar, "   " .. name, 9, 102 + (i - 1) * 39, 119, 32)
    nav.TextXAlignment = Enum.TextXAlignment.Left
    nav.TextSize = 12
    nav.BackgroundColor3 = theme.side
    navButtons[name] = nav
    connect(nav.MouseButton1Click, function() showPage(name) end)
end
label(sidebar, "NIGHTFALL V2.0", 12, 457, 116, 15, 9, theme.muted, true)
label(sidebar, "LOCAL CLIENT", 12, 474, 116, 14, 9, theme.primary, true)

local function pageTitle(p, name, subtitle)
    label(p, name, 0, 0, 330, 22, 15, theme.text, true)
    label(p, subtitle, 0, 21, 435, 15, 10, theme.muted)
end

local function slider(target, y, title, subtitle, lowest, highest, initial, callback)
    local frame = card(target, y, 105, title, subtitle)
    local bar = make("Frame", frame, {
        Position = UDim2.fromOffset(15, 76), Size = UDim2.fromOffset(320, 5),
        BackgroundColor3 = Color3.fromRGB(45, 64, 81), BorderSizePixel = 0,
    })
    corners(bar, 4)
    local fill = make("Frame", bar, {
        BackgroundColor3 = theme.primary, Size = UDim2.fromScale(0, 1),
        BorderSizePixel = 0,
    })
    corners(fill, 4)
    local knob = make("Frame", bar, {
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromScale(0, 0.5), Size = UDim2.fromOffset(12, 12),
        BackgroundColor3 = theme.text, BorderSizePixel = 0,
    })
    corners(knob, 12)
    border(knob, theme.primary, 0, 1.3)
    local field = make("TextBox", frame, {
        Position = UDim2.fromOffset(355, 61), Size = UDim2.fromOffset(74, 32),
        BackgroundColor3 = Color3.fromRGB(27, 43, 59), TextColor3 = theme.text,
        TextSize = 12, Font = Enum.Font.GothamBold, ClearTextOnFocus = false,
        Text = "", BorderSizePixel = 0,
    })
    corners(field, 6)
    border(field, theme.border, 0.1)
    local value = initial
    local function update(num)
        num = tonumber(num)
        if not num then num = value end
        value = math.floor(math.clamp(num, lowest, highest) + 0.5)
        field.Text = tostring(value)
        local alpha = (value - lowest) / (highest - lowest)
        motion(fill, {Size = UDim2.fromScale(alpha, 1)}, 0.08)
        motion(knob, {Position = UDim2.fromScale(alpha, 0.5)}, 0.08)
        callback(value)
    end
    local dragging = false
    local function setX(x)
        if bar.AbsoluteSize.X <= 0 then return end
        local a = math.clamp((x - bar.AbsolutePosition.X) / bar.AbsoluteSize.X, 0, 1)
        update(lowest + a * (highest - lowest))
    end
    connect(bar.InputBegan, function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            setX(input.Position.X)
        end
    end)
    connect(UserInputService.InputChanged, function(input)
        if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement
            or input.UserInputType == Enum.UserInputType.Touch) then
            setX(input.Position.X)
        end
    end)
    connect(UserInputService.InputEnded, function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
            dragging = false
        end
    end)
    connect(field.FocusLost, function() update(field.Text) end)
    update(initial)
    return update
end

local function switch(target, y, title, subtitle, initial, callback)
    local frame = card(target, y, 66)
    label(frame, title, 13, 9, 330, 18, 12, theme.text, true)
    label(frame, subtitle, 13, 29, 343, 16, 10, theme.muted)
    local rail = button(frame, "", 379, 18, 49, 25)
    local dot = make("Frame", rail, {
        Size = UDim2.fromOffset(18, 18),
        Position = UDim2.fromOffset(3, 3),
        BackgroundColor3 = theme.text, BorderSizePixel = 0,
    })
    corners(rail, 20)
    corners(dot, 20)
    local on = initial
    local function set(nextValue)
        on = not not nextValue
        motion(rail, {BackgroundColor3 = on and Color3.fromRGB(49, 100, 121)
            or Color3.fromRGB(42, 58, 71)}, 0.18)
        motion(dot, {Position = UDim2.fromOffset(on and 27 or 3, 3)}, 0.18)
        callback(on)
    end
    connect(rail.MouseButton1Click, function() set(not on) end)
    set(initial)
    return set
end

-- MAIN
pageTitle(mainPage, "MAIN", "CHARACTER MOVEMENT  /  CAMERA")
local updateSpeed = slider(mainPage, 46, "WalkSpeed", "SPEED IS REAPPLIED WHILE LOCK IS ENABLED",
    8, 200, wantedSpeed, function(n)
        wantedSpeed = n
        scope.AetherNightfallSavedSpeed = n
        keepSpeed()
        if not speedLock then
            local ch = localPlayer.Character
            local h = ch and ch:FindFirstChildOfClass("Humanoid")
            if h then h.WalkSpeed = n end
        end
    end)
local updateFov = slider(mainPage, 162, "Camera FOV", "FIELD OF VIEW  /  DEGREES",
    40, 120, originalFov, function(n)
        wantedFov = n
        local cam = workspace.CurrentCamera
        if cam then cam.FieldOfView = n end
    end)
switch(mainPage, 279, "Persistent WalkSpeed", "ON RESPAWN AND AFTER LOCAL RESETS", true, function(value)
    speedLock = value
    if value then keepSpeed() end
end)
local hint = card(mainPage, 355, 69)
label(hint, "CONTROL NOTES", 13, 8, 315, 17, 11, theme.primary, true)
label(hint, "F6 / Fn+F6: show or hide  •  drag the top bar", 13, 26, 418, 16, 11, theme.muted)
label(hint, "Server-enforced movement may override local speed.", 13, 44, 418, 14, 10, theme.muted)

-- VISUALS
pageTitle(visualsPage, "VISUALS", "COLOR GRADING  /  LIGHTING PRESETS")
local presetsPanel = card(visualsPage, 46, 246, "POST-PROCESSING", "SIX STYLE PRESETS")
for i, p in ipairs(presets) do
    local col = (i - 1) % 2
    local row = math.floor((i - 1) / 2)
    local b = button(presetsPanel, p.name, 15 + col * 211, 57 + row * 58, 198, 45)
    b.BackgroundColor3 = theme.card
    b.TextColor3 = p.color
    presetButtons[i] = b
    connect(b.MouseButton1Click, function() applyPreset(i) end)
end
local visInfo = card(visualsPage, 302, 80)
label(visInfo, "RENDER STYLE", 14, 10, 365, 20, 12, theme.text, true)
label(visInfo, "Effects are applied only to your local client.", 14, 34, 415, 18, 11, theme.muted)
local clearVisuals = button(visualsPage, "RESTORE ORIGINAL LIGHTING", 0, 394, 445, 32)
connect(clearVisuals.MouseButton1Click, function() applyPreset(1) end)

-- ESP / boxes
local espEnabled = false
local espNames = true
local espDistance = true
local espRoles = true
local espMaxDistance = 500
local function hideBoxes()
    for _, entry in pairs(boxes) do entry.frame.Visible = false end
end
pageTitle(espPage, "ESP", "PLAYER BOXES  /  ROLE COLORS WHEN AVAILABLE")
switch(espPage, 46, "Player Boxes (ESP)", "SHOW PLAYERS THROUGH WORLD GEOMETRY", false, function(v)
    espEnabled = v
    if not v then hideBoxes() end
end)
switch(espPage, 120, "Display Names", "USERNAME ABOVE THE BOX", true, function(v)
    espNames = v
end)
switch(espPage, 194, "Distance", "DISTANCE BELOW THE BOX", true, function(v)
    espDistance = v
end)
switch(espPage, 268, "Role Colors", "RED / GREEN ONLY FOR DETECTED ROLES", true, function(v)
    espRoles = v
end)
local espRange = slider(espPage, 341, "Max ESP Distance", "VISIBLE LIMIT  /  STUDS",
    50, 2000, 500, function(v) espMaxDistance = v end)

local roleInfo = {
    murderer = {color = theme.red, tag = "MURDERER"},
    innocent = {color = theme.green, tag = "INNOCENT"},
    sheriff = {color = theme.blue, tag = "SHERIFF"},
    unknown = {color = theme.gray, tag = "UNKNOWN"},
}
local roleKeys = {"Role", "CurrentRole", "RoundRole", "PlayerRole", "MM2Role"}
local function normalizeRole(value)
    if value == nil then return nil end
    local s = string.lower(tostring(value))
    if s:find("murder") or s:find("killer") or s:find("assassin") or s:find("убий") then
        return "murderer"
    end
    if s:find("innocent") or s:find("civilian") or s:find("невинов") then
        return "innocent"
    end
    if s:find("sheriff") or s:find("detective") or s:find("hero") then
        return "sheriff"
    end
    return nil
end
local function playerRole(plr)
    -- Only inspect replicated attributes / values; do not claim to know secret roles.
    for _, source in ipairs({plr, plr.Character}) do
        if source then
            for _, key in ipairs(roleKeys) do
                local role = normalizeRole(source:GetAttribute(key))
                if role then return role end
                local valueObj = source:FindFirstChild(key)
                if valueObj and valueObj:IsA("ValueBase") then
                    role = normalizeRole(valueObj.Value)
                    if role then return role end
                end
            end
        end
    end
    return "unknown"
end
local function getBox(plr)
    local existing = boxes[plr]
    if existing then return existing end
    local frame = make("Frame", espGui, {
        Name = "ESP_" .. tostring(plr.UserId),
        BackgroundTransparency = 1, BorderSizePixel = 0, Visible = false,
    })
    corners(frame, 1)
    local edge = border(frame, theme.gray, 0, 1.4)
    local nametag = label(frame, "", 0, -24, 160, 20, 12, theme.text, true)
    nametag.TextXAlignment = Enum.TextXAlignment.Center
    nametag.TextStrokeTransparency = 0.25
    local rangeLabel = label(frame, "", 0, 0, 160, 18, 10, theme.text)
    rangeLabel.TextXAlignment = Enum.TextXAlignment.Center
    rangeLabel.TextStrokeTransparency = 0.3
    local entry = {frame = frame, edge = edge, nametag = nametag, distance = rangeLabel}
    boxes[plr] = entry
    return entry
end

local function renderEsp()
    if not espEnabled then return end
    local cam = workspace.CurrentCamera
    local selfChar = localPlayer.Character
    local myRoot = selfChar and selfChar:FindFirstChild("HumanoidRootPart")
    if not cam then return end
    for _, plr in ipairs(Players:GetPlayers()) do
        if plr ~= localPlayer then
            local entry = getBox(plr)
            local ch = plr.Character
            local root = ch and ch:FindFirstChild("HumanoidRootPart")
            local head = ch and ch:FindFirstChild("Head")
            local targetHumanoid = ch and ch:FindFirstChildOfClass("Humanoid")
            if root and head and targetHumanoid and targetHumanoid.Health > 0 then
                local dist = myRoot and (myRoot.Position - root.Position).Magnitude or 0
                local top, topOnScreen = cam:WorldToViewportPoint(head.Position + Vector3.new(0, 0.65, 0))
                local bottom, bottomOnScreen = cam:WorldToViewportPoint(root.Position - Vector3.new(0, 2.9, 0))
                local visible = top.Z > 0 and bottom.Z > 0 and topOnScreen and bottomOnScreen
                    and dist <= espMaxDistance
                if visible then
                    local height = math.clamp(math.abs(bottom.Y - top.Y), 14, 1500)
                    local width = math.clamp(height * 0.52, 10, 700)
                    local centerX = (top.X + bottom.X) * 0.5
                    local centerY = (top.Y + bottom.Y) * 0.5
                    entry.frame.Position = UDim2.fromOffset(centerX - width * 0.5, centerY - height * 0.5)
                    entry.frame.Size = UDim2.fromOffset(width, height)
                    local info = roleInfo[espRoles and playerRole(plr) or "unknown"]
                    entry.edge.Color = info.color
                    entry.nametag.TextColor3 = info.color
                    entry.nametag.Text = plr.DisplayName .. (espRoles and ("  [" .. info.tag .. "]") or "")
                    entry.nametag.Visible = espNames
                    entry.nametag.Position = UDim2.fromOffset(-70, -25)
                    entry.nametag.Size = UDim2.fromOffset(width + 140, 21)
                    entry.distance.Text = string.format("%d studs", math.floor(dist))
                    entry.distance.Visible = espDistance
                    entry.distance.Position = UDim2.fromOffset(-35, height + 3)
                    entry.distance.Size = UDim2.fromOffset(width + 70, 17)
                    entry.frame.Visible = true
                else
                    entry.frame.Visible = false
                end
            else
                entry.frame.Visible = false
            end
        end
    end
end
connect(Players.PlayerRemoving, function(plr)
    local e = boxes[plr]
    if e then e.frame:Destroy(); boxes[plr] = nil end
end)

-- SETTINGS
pageTitle(settingsPage, "SETTINGS", "PERSISTENCE  /  RESET  /  SHORTCUTS")
switch(settingsPage, 46, "Keep Camera FOV", "RESTORE YOUR FOV IF THE GAME CHANGES IT", true, function(v)
    fovLock = v
end)
local controls = card(settingsPage, 124, 102, "KEYBINDS", "WINDOW CONTROLS")
label(controls, "Toggle menu", 13, 50, 190, 18, 11, theme.text)
label(controls, "F6 / Fn + F6", 279, 50, 150, 18, 11, theme.primary, true)
local resetButton = button(settingsPage, "RESET SPEED, FOV AND LIGHTING", 0, 245, 445, 36)
connect(resetButton.MouseButton1Click, function()
    updateSpeed(originalSpeed)
    updateFov(originalFov)
    applyPreset(1)
end)
local settingsInfo = card(settingsPage, 298, 100, "ROLE DETECTION", "ESP COLOR LEGEND")
label(settingsInfo, "MURDERER", 13, 46, 95, 20, 10, theme.red, true)
label(settingsInfo, "INNOCENT", 116, 46, 94, 20, 10, theme.green, true)
label(settingsInfo, "SHERIFF", 220, 46, 90, 20, 10, theme.blue, true)
label(settingsInfo, "UNKNOWN", 321, 46, 100, 20, 10, theme.gray, true)
label(settingsPage, "Unknown stays gray if the game does not replicate roles.",
    5, 410, 440, 20, 10, theme.muted)

-- Window controls
local minButton = make("TextButton", gui, {
    Name = "QuickToggle",
    AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -16, 0, 55),
    Size = UDim2.fromOffset(42, 42),
    BackgroundColor3 = theme.side, Text = "A", Font = Enum.Font.GothamBold,
    TextColor3 = theme.primary, TextSize = 17, AutoButtonColor = false,
    BorderSizePixel = 0,
})
corners(minButton, 12)
border(minButton, theme.primary, 0.25)

local function toggleMenu()
    menuOpen = not menuOpen
    if menuOpen then
        panel.Visible = true
        motion(panel, {BackgroundTransparency = 0.03}, 0.24)
    else
        panel.Visible = false
    end
end
connect(close.MouseButton1Click, toggleMenu)
connect(minButton.MouseButton1Click, toggleMenu)
connect(UserInputService.InputBegan, function(input, processed)
    if input.KeyCode == Enum.KeyCode.F6 and not processed then toggleMenu() end
end)

local moving = false
local dragOrigin
local windowOrigin
connect(header.InputBegan, function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch then
        moving = true
        dragOrigin = input.Position
        windowOrigin = panel.Position
    end
end)
connect(UserInputService.InputChanged, function(input)
    if moving and (input.UserInputType == Enum.UserInputType.MouseMovement
        or input.UserInputType == Enum.UserInputType.Touch) then
        local delta = input.Position - dragOrigin
        panel.Position = UDim2.new(
            windowOrigin.X.Scale, windowOrigin.X.Offset + delta.X / scale.Scale,
            windowOrigin.Y.Scale, windowOrigin.Y.Offset + delta.Y / scale.Scale
        )
    end
end)
connect(UserInputService.InputEnded, function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch then moving = false end
end)

local elapsed = 0
local espElapsed = 0
connect(RunService.Heartbeat, function(dt)
    elapsed = elapsed + dt
    espElapsed = espElapsed + dt
    if elapsed >= 0.25 then
        elapsed = 0
        keepSpeed()
        local cam = workspace.CurrentCamera
        if cam and fovLock and math.abs(cam.FieldOfView - wantedFov) > 0.01 then
            cam.FieldOfView = wantedFov
        end
    end
    if espElapsed >= 0.05 then
        espElapsed = 0
        renderEsp()
    end
end)

local function destroy()
    if not alive then return end
    alive = false
    for _, connection in ipairs(listeners) do
        pcall(function() connection:Disconnect() end)
    end
    if humanoidListener then humanoidListener:Disconnect() end
    for _, entry in pairs(boxes) do pcall(function() entry.frame:Destroy() end) end
    restoreLighting()
    local ch = localPlayer.Character
    local h = ch and ch:FindFirstChildOfClass("Humanoid")
    if h then h.WalkSpeed = originalSpeed end
    local cam = workspace.CurrentCamera
    if cam then cam.FieldOfView = originalFov end
    colorCorrection:Destroy()
    bloom:Destroy()
    sunrays:Destroy()
    espGui:Destroy()
    gui:Destroy()
    if scope.AetherNightfall and scope.AetherNightfall.Destroy == destroy then
        scope.AetherNightfall = nil
    end
end
scope.AetherNightfall = {Destroy = destroy, Version = "2.1"}
applyPreset(1)
showPage("Main")
print("[AETHER NIGHTFALL V2.1] Ready. WalkSpeed persists after Reset/respawn. F6 toggles the menu.")
]==])()
