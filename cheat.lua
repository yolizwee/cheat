loadstring([==[
--[[
  AETHER / Nightfall V3.7 — DBD A/D Movement Edition
  Roblox client UI: Main, Visuals, ESP, Drift, Themes, Profiles, Settings
  Toggle: F6 default, configurable F7/Insert (Fn + F6 on certain laptops)
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
local HttpService = game:GetService("HttpService")
local PROFILE_FILE = "Aether_Nightfall_V3_profiles.json"
local SETTINGS_DEFAULTS = {
    speed = 16, fov = 70, jump = 50, zoom = 18, shoulder = 0,
    lockSpeed = true, lockJump = true, lockFov = true, preset = 1,
    glow = 100, contrast = 50, saturation = 50,
    espEnabled = false, espNames = true, espDistance = true, espRoles = true,
    espHighlights = false, espHealth = false, espTracers = false, espCorners = false, espSkeleton = false,
    espRange = 500, driftEnabled = false, driftStrength = 65,
    driftShiftOnly = false, driftTrails = true,
    dbdJukes = true, dbdFullSpin = true, dbdTurnSpeed = 60,
    theme = "OCEAN", hotkey = "F6",
}
local profileData = {active = "DEFAULT", slots = {DEFAULT = {}, PVP = {}, CINEMA = {}}}
if type(scope.AetherV3ProfileData) == "table" then
    profileData = scope.AetherV3ProfileData
elseif type(readfile) == "function" and type(isfile) == "function" then
    pcall(function()
        if isfile(PROFILE_FILE) then
            local decoded = HttpService:JSONDecode(readfile(PROFILE_FILE))
            if type(decoded) == "table" and type(decoded.slots) == "table" then
                profileData = decoded
            end
        end
    end)
end
if type(profileData.slots) ~= "table" then profileData.slots = {} end
if not ({DEFAULT = true, PVP = true, CINEMA = true})[profileData.active] then
    profileData.active = "DEFAULT"
end
local config = {}
local function loadSlot(name)
    local slot = profileData.slots[name]
    if type(slot) ~= "table" then slot = {} end
    for key, default in pairs(SETTINGS_DEFAULTS) do
        local value = slot[key]
        if type(value) ~= type(default) then value = default end
        config[key] = value
    end
end
loadSlot(profileData.active)
-- Compatibility with previous V2/V3's within-session saved WalkSpeed.
if not (profileData.slots[profileData.active] and profileData.slots[profileData.active].speed)
    and tonumber(scope.AetherNightfallSavedSpeed) then
    config.speed = tonumber(scope.AetherNightfallSavedSpeed)
end
local saveToken = 0
local function saveNow()
    profileData.slots[profileData.active] = table.clone(config)
    scope.AetherV3ProfileData = profileData
    if type(writefile) == "function" then
        pcall(function()
            writefile(PROFILE_FILE, HttpService:JSONEncode(profileData))
        end)
    end
end
local function scheduleSave()
    saveToken = saveToken + 1
    local token = saveToken
    task.delay(0.55, function()
        if token == saveToken then saveNow() end
    end)
end
local function setSetting(key, value)
    config[key] = value
    scheduleSave()
end
local storedSpeed = tonumber(config.speed) or tonumber(scope.AetherNightfallSavedSpeed)
-- Drift options are preserved if you run the script again in the same session.
local driftEnabled = config.driftEnabled == true
local driftStrength = math.clamp(tonumber(config.driftStrength) or 65, 0, 100)
local driftShiftOnly = config.driftShiftOnly == true
local driftTrails = config.driftTrails ~= false
local dbdJukes = config.dbdJukes ~= false
local dbdFullSpin = config.dbdFullSpin ~= false
local dbdTurnSpeed = math.clamp(tonumber(config.dbdTurnSpeed) or 60, 0, 100)
local shiftHeld = false
local trailRoot = nil
local trailObjects = {}
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
local speedLock = config.lockSpeed
local speedSyncing = false
local camera = workspace.CurrentCamera
local originalFov = camera and camera.FieldOfView or 70
local wantedFov = math.clamp(tonumber(config.fov) or originalFov, 40, 120)
local fovLock = config.lockFov
local originalJump = humanoid and humanoid.JumpPower or 50
local wantedJump = math.clamp(tonumber(config.jump) or originalJump, 20, 150)
local jumpLock = config.lockJump
local desiredZoom = math.clamp(tonumber(config.zoom) or 18, 4, 70)
local desiredShoulder = math.clamp(tonumber(config.shoulder) or 0, -8, 8)
local originalMaxZoom = localPlayer.CameraMaxZoomDistance
local originalMinZoom = localPlayer.CameraMinZoomDistance
local function applyCamera()
    pcall(function()
        localPlayer.CameraMaxZoomDistance = math.max(desiredZoom, localPlayer.CameraMinZoomDistance)
        localPlayer.CameraMinZoomDistance = math.min(0.5, desiredZoom)
    end)
end
local function keepJump()
    if not alive or not jumpLock then return end
    local ch = localPlayer.Character
    local h = ch and ch:FindFirstChildOfClass("Humanoid")
    if h and h.Health > 0 then
        pcall(function()
            h.UseJumpPower = true
            if math.abs(h.JumpPower - wantedJump) > 0.01 then h.JumpPower = wantedJump end
            h.CameraOffset = Vector3.new(desiredShoulder, 0, 0)
        end)
    end
end


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
    keepJump()
    -- Roblox/game spawn scripts can set WalkSpeed after Humanoid is created.
    -- Apply again once the character is fully initialized.
    task.delay(0.15, function() if alive and humanoid == h then keepSpeed() end end)
    task.delay(1.0, function() if alive and humanoid == h then keepSpeed(); keepJump(); applyCamera() end end)
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
    setSetting("preset", index)
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
        colorCorrection.Contrast = p.contrast + ((config.contrast or 50) - 50) / 200
        colorCorrection.Saturation = p.saturation + ((config.saturation or 50) - 50) / 100
        colorCorrection.Brightness = 0
        bloom.Enabled = p.glow > 0
        bloom.Intensity = p.glow * (config.glow or 100) / 100
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
    Size = UDim2.fromOffset(842, 512),
    BackgroundColor3 = theme.bg,
    BackgroundTransparency = 0.10,
    BorderSizePixel = 0,
    ClipsDescendants = true,
})
corners(panel, 10)
border(panel, Color3.fromRGB(53, 87, 104), 0.05)
local glassGlow = make("Frame", panel, {
    Name = "GlassLight", Position = UDim2.fromOffset(135, -120),
    Size = UDim2.fromOffset(610, 180), BackgroundColor3 = theme.primary,
    BackgroundTransparency = 0.965, BorderSizePixel = 0, ZIndex = 1,
})
corners(glassGlow, 45)
local topHairline = make("Frame", panel, {
    Position = UDim2.fromOffset(143, 0), Size = UDim2.fromOffset(684, 1),
    BackgroundColor3 = theme.primary, BackgroundTransparency = 0.56,
    BorderSizePixel = 0, ZIndex = 4,
})

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
    scale.Scale = math.min(1, (vp.X - 30) / 842, (vp.Y - 30) / 512)
end
rescale()

local sidebar = make("Frame", panel, {
    Position = UDim2.fromOffset(0, 0), Size = UDim2.fromOffset(137, 512),
    BackgroundColor3 = theme.side, BackgroundTransparency = 0.14,
    BorderSizePixel = 0,
})
make("Frame", panel, {
    Position = UDim2.fromOffset(137, 0), Size = UDim2.fromOffset(1, 512),
    BackgroundColor3 = theme.border, BackgroundTransparency = 0.35,
    BorderSizePixel = 0,
})

label(sidebar, "AETHER / V3", 12, 10, 120, 21, 12, theme.primary, true)
label(sidebar, "CONTROL CENTER", 12, 32, 123, 15, 9, theme.muted, true)
label(sidebar, "MODULES", 12, 77, 112, 15, 9, theme.muted, true)

local pageHost = make("Frame", panel, {
    Position = UDim2.fromOffset(156, 53), Size = UDim2.fromOffset(445, 447),
    BackgroundTransparency = 1,
})
local header = make("Frame", panel, {
    Position = UDim2.fromOffset(151, 0), Size = UDim2.fromOffset(675, 45),
    BackgroundTransparency = 1,
})
label(header, "AETHER  /  NIGHTFALL V3", 5, 8, 345, 20, 14, theme.text, true)
local status = label(header, "●  CLIENT SETTINGS ACTIVE", 369, 10, 215, 17, 10, theme.muted, true)

local close = button(header, "×", 630, 8, 28, 25)
close.TextSize = 20

local preview = make("Frame", panel, {
    Position = UDim2.fromOffset(620, 53), Size = UDim2.fromOffset(208, 447),
    BackgroundColor3 = theme.panel, BackgroundTransparency = 0.15,
    BorderSizePixel = 0,
})
corners(preview, 8)
border(preview, theme.border, 0.1)
label(preview, "AVATAR / LIVE PROFILE", 12, 10, 175, 18, 10, theme.primary, true)
local avatar = make("ImageLabel", preview, {
    Position = UDim2.fromOffset(8, 49), Size = UDim2.fromOffset(192, 291),
    BackgroundTransparency = 1,
    Image = "", ScaleType = Enum.ScaleType.Fit,
})
label(preview, "PLAYER", 12, 352, 170, 13, 9, theme.muted, true)
label(preview, localPlayer.DisplayName, 12, 369, 188, 20, 13, theme.text, true)
local hotkeyPreview = label(preview, "F6  /  TOGGLE MENU", 12, 401, 184, 20, 10, theme.muted, true)
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
    local f = make("ScrollingFrame", pageHost, {
        Name = name, Size = UDim2.fromScale(1, 1),
        BackgroundTransparency = 1, Visible = false,
        BorderSizePixel = 0,
        CanvasSize = UDim2.fromOffset(0, 900),
        ScrollingDirection = Enum.ScrollingDirection.Y,
        ScrollBarThickness = 2,
        ScrollBarImageColor3 = theme.primary,
    })
    pages[name] = f
    return f
end

local mainPage = page("Main")
local visualsPage = page("Visuals")
local espPage = page("ESP")
local driftPage = page("Drift")
local settingsPage = page("Settings")
local themesPage = page("Themes")
local profilesPage = page("Profiles")
local function pageLength(pageFrame, pixels)
    pageFrame.CanvasSize = UDim2.fromOffset(0, pixels)
end

local function showPage(name)
    currentPage = name
    for pageName, frame in pairs(pages) do
        frame.Visible = (pageName == name)
        if pageName == name then
            frame.Position = UDim2.fromOffset(9, 0)
            motion(frame, {Position = UDim2.fromOffset(0, 0)}, 0.24)
        end
    end
    for navName, b in pairs(navButtons) do
        local active = navName == name
        motion(b, {BackgroundColor3 = active and Color3.fromRGB(28, 44, 58) or theme.side}, 0.17)
        b.TextColor3 = active and theme.primary or theme.muted
    end
end

for i, name in ipairs({"Main", "Visuals", "ESP", "Drift", "Themes", "Profiles", "Settings"}) do
    local nav = button(sidebar, "   " .. name, 9, 94 + (i - 1) * 39, 119, 32)
    nav.TextXAlignment = Enum.TextXAlignment.Left
    nav.TextSize = 12
    nav.BackgroundColor3 = theme.side
    navButtons[name] = nav
    connect(nav.MouseButton1Click, function() showPage(name) end)
end
label(sidebar, "NIGHTFALL V3.6", 12, 468, 116, 15, 9, theme.muted, true)
label(sidebar, "LOCAL CLIENT", 12, 485, 116, 14, 9, theme.primary, true)

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
        setSetting("speed", n)
        keepSpeed()
        if not speedLock then
            local ch = localPlayer.Character
            local h = ch and ch:FindFirstChildOfClass("Humanoid")
            if h then h.WalkSpeed = n end
        end
    end)
local updateFov = slider(mainPage, 162, "Camera FOV", "FIELD OF VIEW  /  DEGREES",
    40, 120, wantedFov, function(n)
        wantedFov = n
        setSetting("fov", n)
        local cam = workspace.CurrentCamera
        if cam then cam.FieldOfView = n end
    end)
local updateJump = slider(mainPage, 278, "JumpPower", "JUMP STRENGTH / RESPAWN-SAFE",
    20, 150, wantedJump, function(n)
        wantedJump = n
        setSetting("jump", n)
        keepJump()
    end)
local updateZoom = slider(mainPage, 394, "Camera Zoom", "MAX CAMERA DISTANCE / STUDS",
    4, 70, desiredZoom, function(n)
        desiredZoom = n
        setSetting("zoom", n)
        applyCamera()
    end)
local updateShoulder = slider(mainPage, 510, "Camera Shoulder Offset", "0 CENTERED / NEGATIVE LEFT / POSITIVE RIGHT",
    -8, 8, desiredShoulder, function(n)
        desiredShoulder = n
        setSetting("shoulder", n)
        keepJump()
    end)
local setSpeedLock = switch(mainPage, 626, "Persistent WalkSpeed", "KEEP YOUR SPEED AFTER RESET / RESPAWN", config.lockSpeed, function(value)
    speedLock = value
    setSetting("lockSpeed", value)
    if value then keepSpeed() end
end)
local hint = card(mainPage, 707, 69)
label(hint, "CONTROL NOTES", 13, 8, 315, 17, 11, theme.primary, true)
label(hint, "F6 / Fn+F6: show or hide  •  drag the top bar", 13, 26, 418, 16, 11, theme.muted)
label(hint, "Server-enforced movement may override local speed.", 13, 44, 418, 14, 10, theme.muted)
pageLength(mainPage, 799)


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

local updateBloom = slider(visualsPage, 447, "Bloom Strength", "SOFT LIGHT / GLOW INTENSITY", 0, 200, config.glow, function(v)
    setSetting("glow", v)
    if selectedPreset ~= 1 then
        bloom.Intensity = (presets[selectedPreset].glow or 0) * v / 100
        bloom.Enabled = bloom.Intensity > 0
    end
end)
local updateContrast = slider(visualsPage, 563, "Contrast", "COLOR DEPTH / TONE CURVE", 0, 100, config.contrast, function(v)
    setSetting("contrast", v)
    if selectedPreset ~= 1 then
        colorCorrection.Contrast = (presets[selectedPreset].contrast or 0) + (v - 50) / 200
    end
end)
local updateSaturation = slider(visualsPage, 679, "Saturation", "LOW = MUTED / HIGH = VIBRANT", 0, 100, config.saturation, function(v)
    setSetting("saturation", v)
    if selectedPreset ~= 1 then
        colorCorrection.Saturation = (presets[selectedPreset].saturation or 0) + (v - 50) / 100
    end
end)
local effectsNote = card(visualsPage, 797, 57, "GRAPHICS ENGINE", "Effects operate on the local client only")
pageLength(visualsPage, 885)

-- ESP / boxes
local espEnabled = config.espEnabled
local espNames = config.espNames
local espDistance = config.espDistance
local espRoles = config.espRoles
local espHighlights = config.espHighlights
local espHealth = config.espHealth
local espTracers = config.espTracers
local espCorners = config.espCorners
local espSkeleton = config.espSkeleton
local espMaxDistance = config.espRange
local highlights = {}
local function clearHighlights()
    for plr, obj in pairs(highlights) do
        pcall(function() obj:Destroy() end)
        highlights[plr] = nil
    end
end
local function hideBoxes()
    for _, entry in pairs(boxes) do
        entry.frame.Visible = false
        if entry.tracer then entry.tracer.Visible = false end
        for _, line in ipairs(entry.skeletonLines or {}) do line.Visible = false end
    end
    clearHighlights()
end
pageTitle(espPage, "ESP", "PLAYER BOXES  /  ROLE COLORS WHEN AVAILABLE")
local setEspEnabled = switch(espPage, 46, "Player Boxes (ESP)", "SHOW PLAYERS THROUGH WORLD GEOMETRY", espEnabled, function(v)
    espEnabled = v
    setSetting("espEnabled", v)
    if not v then hideBoxes() end
end)
local setEspNames = switch(espPage, 120, "Display Names", "USERNAME ABOVE THE BOX", espNames, function(v)
    espNames = v
    setSetting("espNames", v)
end)
local setEspDistance = switch(espPage, 194, "Distance", "DISTANCE BELOW THE BOX", espDistance, function(v)
    espDistance = v
    setSetting("espDistance", v)
end)
local setEspRoles = switch(espPage, 268, "Role Colors", "RED / GREEN ONLY FOR DETECTED ROLES", espRoles, function(v)
    espRoles = v
    setSetting("espRoles", v)
end)
local espRange = slider(espPage, 341, "Max ESP Distance", "VISIBLE LIMIT  /  STUDS",
    50, 2000, espMaxDistance, function(v) espMaxDistance = v; setSetting("espRange", v) end)

local setHighlight = switch(espPage, 461, "Player Highlights", "CHAMS / VISIBLE THROUGH WALLS", espHighlights, function(v)
    espHighlights = v
    setSetting("espHighlights", v)
    if not v then clearHighlights() end
end)
local setHealth = switch(espPage, 535, "Health Bars", "DYNAMIC HEALTH INDICATORS", espHealth, function(v)
    espHealth = v
    setSetting("espHealth", v)
end)
local setTracers = switch(espPage, 609, "Tracers", "LINES FROM SCREEN BOTTOM", espTracers, function(v)
    espTracers = v
    setSetting("espTracers", v)
end)
local setCorners = switch(espPage, 683, "Corner ESP", "CORNER BOX STYLE", espCorners, function(v)
    espCorners = v
    setSetting("espCorners", v)
end)
local setSkeleton = switch(espPage, 757, "Skeleton ESP", "R6 / R15 BODY CONNECTIONS", espSkeleton, function(v)
    espSkeleton = v
    setSetting("espSkeleton", v)
end)
local espNote = card(espPage, 839, 53, "ROLE INTELLIGENCE", "Unknown roles remain gray if not replicated")
pageLength(espPage, 922)

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
    local healthBack = make("Frame", frame, {
        BackgroundColor3 = Color3.fromRGB(27, 31, 40),
        BorderSizePixel = 0, Size = UDim2.fromOffset(4, 100),
        Position = UDim2.fromOffset(-10, 0), Visible = false,
    })
    local healthFill = make("Frame", healthBack, {
        BackgroundColor3 = Color3.fromRGB(90, 235, 137),
        BorderSizePixel = 0, AnchorPoint = Vector2.new(0, 1),
        Position = UDim2.fromScale(0, 1), Size = UDim2.fromScale(1, 1),
    })
    local tracer = make("Frame", espGui, {
        Name = "Tracer_" .. tostring(plr.UserId), BackgroundColor3 = theme.gray,
        Size = UDim2.fromOffset(2, 10), BorderSizePixel = 0, Visible = false,
        AnchorPoint = Vector2.new(0.5, 0.5),
    })
    local segments = {}
    for i = 1, 8 do
        segments[i] = make("Frame", frame, {
            BorderSizePixel = 0, BackgroundColor3 = theme.gray, Visible = false,
        })
    end
    local skeletonLines = {}
    for i = 1, 16 do
        skeletonLines[i] = make("Frame", espGui, {
            BackgroundColor3 = theme.gray, BorderSizePixel = 0,
            AnchorPoint = Vector2.new(0.5, 0.5), Visible = false,
        })
    end
    local entry = {frame = frame, edge = edge, nametag = nametag,
        distance = rangeLabel, healthBack = healthBack, healthFill = healthFill,
        tracer = tracer, segments = segments, skeletonLines = skeletonLines}
    boxes[plr] = entry
    return entry
end

local rigR15 = {
    {"Head", "UpperTorso"}, {"UpperTorso", "LowerTorso"},
    {"UpperTorso", "LeftUpperArm"}, {"LeftUpperArm", "LeftLowerArm"},
    {"LeftLowerArm", "LeftHand"}, {"UpperTorso", "RightUpperArm"},
    {"RightUpperArm", "RightLowerArm"}, {"RightLowerArm", "RightHand"},
    {"LowerTorso", "LeftUpperLeg"}, {"LeftUpperLeg", "LeftLowerLeg"},
    {"LeftLowerLeg", "LeftFoot"}, {"LowerTorso", "RightUpperLeg"},
    {"RightUpperLeg", "RightLowerLeg"}, {"RightLowerLeg", "RightFoot"},
}
local rigR6 = {
    {"Head", "Torso"}, {"Torso", "Left Arm"},
    {"Torso", "Right Arm"}, {"Torso", "Left Leg"},
    {"Torso", "Right Leg"},
}
local function updateSkeleton(entry, ch, cam, color, visible)
    if not visible then
        for _, line in ipairs(entry.skeletonLines) do line.Visible = false end
        return
    end
    local rig = ch:FindFirstChild("UpperTorso") and rigR15 or rigR6
    for i, line in ipairs(entry.skeletonLines) do
        local bones = rig[i]
        local a = bones and ch:FindFirstChild(bones[1])
        local b = bones and ch:FindFirstChild(bones[2])
        if a and b and a:IsA("BasePart") and b:IsA("BasePart") then
            local u = cam:WorldToViewportPoint(a.Position)
            local v = cam:WorldToViewportPoint(b.Position)
            if u.Z > 0 and v.Z > 0 then
                local delta = Vector2.new(v.X - u.X, v.Y - u.Y)
                line.Visible = true
                line.BackgroundColor3 = color
                line.Position = UDim2.fromOffset((u.X + v.X)/2, (u.Y + v.Y)/2)
                line.Size = UDim2.fromOffset(delta.Magnitude, 1.5)
                line.Rotation = math.deg(math.atan2(delta.Y, delta.X))
            else
                line.Visible = false
            end
        else
            line.Visible = false
        end
    end
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
            local targetDistance = (myRoot and root) and (myRoot.Position - root.Position).Magnitude or math.huge
            if root and head and targetHumanoid and targetHumanoid.Health > 0 then
                local dist = targetDistance
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
                    entry.edge.Transparency = espCorners and 1 or 0
                    for k, segment in ipairs(entry.segments) do
                        segment.Visible = espCorners
                        segment.BackgroundColor3 = info.color
                        if espCorners then
                            local x = (k <= 4) and 0 or width - 2
                            local y = ((k-1) % 4 < 2) and 0 or height - 2
                            if k % 2 == 1 then
                                segment.Size = UDim2.fromOffset(math.min(13, width / 3), 2)
                                segment.Position = UDim2.fromOffset(k <= 4 and 0 or width - math.min(13, width / 3), y)
                            else
                                segment.Size = UDim2.fromOffset(2, math.min(13, height / 3))
                                segment.Position = UDim2.fromOffset(x, y == 0 and 0 or height - math.min(13, height / 3))
                            end
                        end
                    end
                    entry.healthBack.Visible = espHealth
                    entry.healthBack.Size = UDim2.fromOffset(4, height)
                    entry.healthBack.Position = UDim2.fromOffset(-9, 0)
                    local healthFrac = math.clamp(targetHumanoid.Health / math.max(1, targetHumanoid.MaxHealth), 0, 1)
                    entry.healthFill.Size = UDim2.fromScale(1, healthFrac)
                    entry.healthFill.BackgroundColor3 = Color3.fromRGB(255 * (1 - healthFrac), 225 * healthFrac, 95)
                    entry.tracer.Visible = espTracers
                    if espTracers then
                        local viewport = cam.ViewportSize
                        local from = Vector2.new(viewport.X / 2, viewport.Y - 12)
                        local to = Vector2.new(centerX, centerY)
                        local delta = to - from
                        entry.tracer.BackgroundColor3 = info.color
                        entry.tracer.Position = UDim2.fromOffset((from.X + to.X)/2, (from.Y + to.Y)/2)
                        entry.tracer.Size = UDim2.fromOffset(1.4, delta.Magnitude)
                        entry.tracer.Rotation = math.deg(math.atan2(delta.Y, delta.X)) - 90
                    end
                    entry.nametag.TextColor3 = info.color
                    entry.nametag.Text = plr.DisplayName .. (espRoles and ("  [" .. info.tag .. "]") or "")
                    entry.nametag.Visible = espNames
                    entry.nametag.Position = UDim2.fromOffset(-70, -25)
                    entry.nametag.Size = UDim2.fromOffset(width + 140, 21)
                    entry.distance.Text = string.format("%d studs", math.floor(dist))
                    entry.distance.Visible = espDistance
                    entry.distance.Position = UDim2.fromOffset(-35, height + 3)
                    entry.distance.Size = UDim2.fromOffset(width + 70, 17)
                    updateSkeleton(entry, ch, cam, info.color, espSkeleton)
                    entry.frame.Visible = true
                else
                    entry.frame.Visible = false
                    entry.tracer.Visible = false
                    updateSkeleton(entry, ch, cam, theme.gray, false)
                end
            else
                entry.frame.Visible = false
                entry.tracer.Visible = false
                updateSkeleton(entry, ch, cam, theme.gray, false)
            end
            if espHighlights and ch and targetHumanoid and targetHumanoid.Health > 0 then
                local old = highlights[plr]
                if old and old.Adornee ~= ch then old:Destroy(); old = nil end
                if not old then
                    old = make("Highlight", ch, {
                        Name = "AetherV3Highlight", Adornee = ch,
                        DepthMode = Enum.HighlightDepthMode.AlwaysOnTop,
                        FillTransparency = 0.72, OutlineTransparency = 0.06,
                    })
                    highlights[plr] = old
                end
                local info = roleInfo[espRoles and playerRole(plr) or "unknown"]
                old.FillColor = info.color
                old.OutlineColor = info.color
                old.Enabled = targetDistance <= espMaxDistance
            elseif highlights[plr] then
                highlights[plr]:Destroy()
                highlights[plr] = nil
            end
        end
    end
end
connect(Players.PlayerRemoving, function(plr)
    local e = boxes[plr]
    if e then
        e.frame:Destroy()
        e.tracer:Destroy()
        for _, line in ipairs(e.skeletonLines) do line:Destroy() end
        boxes[plr] = nil
    end
    if highlights[plr] then highlights[plr]:Destroy(); highlights[plr] = nil end
end)

-- DBD-inspired jukes: a small movement arc + rapid 180/360 turn.
-- This is not the physics of Dead by Daylight; it is a local approximation
-- using Roblox HumanoidRootPart orientation and horizontal velocity.
-- No teleports or movement-speed boost are used.
local function stopTrails()
    for _, obj in ipairs(trailObjects) do
        if obj and obj.Parent then pcall(function() obj:Destroy() end) end
    end
    table.clear(trailObjects)
    trailRoot = nil
end

local function getTrails(root)
    if trailRoot == root then return end
    stopTrails()
    trailRoot = root
    for _, side in ipairs({-1, 1}) do
        local a0 = make("Attachment", root, {
            Name = "AetherDriftA0", Position = Vector3.new(side * 0.8, -2.1, 0.2),
        })
        local a1 = make("Attachment", root, {
            Name = "AetherDriftA1", Position = Vector3.new(side * 0.8, -2.2, 0.2),
        })
        local line = make("Trail", root, {
            Name = "AetherDriftStreak", Attachment0 = a0, Attachment1 = a1,
            Color = ColorSequence.new(theme.primary),
            Transparency = NumberSequence.new({
                NumberSequenceKeypoint.new(0, 0.2),
                NumberSequenceKeypoint.new(1, 1),
            }),
            Lifetime = 0.35, MinLength = 0.05, FaceCamera = true, Enabled = false,
        })
        table.insert(trailObjects, a0)
        table.insert(trailObjects, a1)
        table.insert(trailObjects, line)
    end
end

local function setTrailsActive(on)
    for _, obj in ipairs(trailObjects) do
        if obj:IsA("Trail") then obj.Enabled = on end
    end
end

-- A = left spin / D = right spin when both Drift and DBD Jukes are on.
-- Save and restore AutoRotate; this matters after a Reset or script reload.
local activeJuke = nil
local nextJukeAt = 0
local function stopJuke()
    if activeJuke then
        local h = activeJuke.humanoid
        if h and h.Parent then
            pcall(function() h.AutoRotate = activeJuke.wasAutoRotate end)
        end
    end
    activeJuke = nil
    setTrailsActive(false)
end

local function beginJuke(sign)
    if not alive or not driftEnabled or not dbdJukes or activeJuke then return end
    if os.clock() < nextJukeAt then return end
    local ch = localPlayer.Character
    local hum = ch and ch:FindFirstChildOfClass("Humanoid")
    local root = ch and ch:FindFirstChild("HumanoidRootPart")
    if not hum or not root or hum.Health <= 0 or hum.Sit
        or hum.FloorMaterial == Enum.Material.Air then return end
    -- Follow the direction the character is running, not the camera's tilt.
    local startDirection = hum.MoveDirection
    if startDirection.Magnitude <= 0.15 then return end
    startDirection = Vector3.new(startDirection.X, 0, startDirection.Z).Unit
    local right = Vector3.new(-startDirection.Z, 0, startDirection.X)
    local duration = 0.48 - 0.28 * (dbdTurnSpeed / 100)
    local savedAutoRotate = hum.AutoRotate
    hum.AutoRotate = false
    activeJuke = {
        humanoid = hum, root = root, started = os.clock(), duration = duration,
        angle = (dbdFullSpin and (math.pi * 2) or math.pi) * sign,
        forward = startDirection, right = right,
        wasAutoRotate = savedAutoRotate,
    }
    nextJukeAt = os.clock() + duration + 0.15
end

local function updateJuke(dt)
    local j = activeJuke
    if not j then return false end
    local hum, root = j.humanoid, j.root
    if not alive or not driftEnabled or not dbdJukes or not hum.Parent or not root.Parent
        or hum.Health <= 0 or hum.Sit or hum.FloorMaterial == Enum.Material.Air
        or localPlayer.Character ~= hum.Parent then
        stopJuke()
        return false
    end

    local t = math.clamp((os.clock() - j.started) / j.duration, 0, 1)
    local eased = t * t * (3 - 2 * t)
    local theta = j.angle * eased
    local desired = j.forward * math.cos(theta) + j.right * math.sin(theta)
    if desired.Magnitude > 0.05 then
        desired = desired.Unit
        -- Rotate the avatar and curve the motion through a small loop.
        -- Physics remains collision-aware: no teleport / CFrame position jump.
        root.CFrame = CFrame.lookAt(root.Position, root.Position + desired)
        local current = root.AssemblyLinearVelocity
        local horizontal = Vector3.new(current.X, 0, current.Z)
        local speedLimit = math.max(8, hum.WalkSpeed)
        local target = desired * speedLimit
        local blended = horizontal:Lerp(target, math.clamp(dt * 15, 0, 1))
        if blended.Magnitude > speedLimit then blended = blended.Unit * speedLimit end
        root.AssemblyLinearVelocity = Vector3.new(blended.X, current.Y, blended.Z)
    end
    if driftTrails then
        getTrails(root)
        setTrailsActive(true)
    end
    if t >= 1 then stopJuke() end
    return true
end

local function applyDrift(dt)
    local ch = localPlayer.Character
    local hum = ch and ch:FindFirstChildOfClass("Humanoid")
    local root = ch and ch:FindFirstChild("HumanoidRootPart")
    local active = driftEnabled and (not driftShiftOnly or shiftHeld)
    if not active or not hum or not root or hum.Health <= 0
        or hum.FloorMaterial == Enum.Material.Air or hum.Sit then
        setTrailsActive(false)
        return
    end

    local velocity = root.AssemblyLinearVelocity
    local horizontal = Vector3.new(velocity.X, 0, velocity.Z)
    local direction = hum.MoveDirection
    -- No speed boost: constrain planar drift to the selected WalkSpeed.
    local speedLimit = math.max(hum.WalkSpeed, 8)
    if horizontal.Magnitude > speedLimit then
        horizontal = horizontal.Unit * speedLimit
    end
    local target = direction.Magnitude > 0.05 and (direction.Unit * speedLimit) or Vector3.zero
    -- A high strength means more inertia; 0 is almost immediate movement response.
    local response = 18 - 16.1 * (driftStrength / 100)
    local alpha = 1 - math.exp(-math.min(dt, 0.1) * response)
    local resulting = horizontal:Lerp(target, alpha)
    root.AssemblyLinearVelocity = Vector3.new(resulting.X, velocity.Y, resulting.Z)

    if driftTrails then
        getTrails(root)
        local isTurning = horizontal.Magnitude > 6 and
            (direction.Magnitude < 0.05 or
            horizontal.Unit:Dot(direction.Unit) < 0.88)
        setTrailsActive(isTurning)
    else
        setTrailsActive(false)
    end
end

pageTitle(driftPage, "DRIFT", "DBD-STYLE 180 / 360 JUKES  +  MOMENTUM")
local setDriftEnabled = switch(driftPage, 46, "Enable Drifts", "SMOOTH SKIDS WHEN YOU CHANGE DIRECTION",
    driftEnabled, function(v)
        driftEnabled = v
        scope.AetherNightfallDriftEnabled = v
        setSetting("driftEnabled", v)
        if not v then stopJuke(); setTrailsActive(false) end
    end)
local setDriftStrength = slider(driftPage, 123, "Drift Strength", "HIGHER = LONGER SLIDES ON TURNS", 0, 100,
    driftStrength, function(v)
        driftStrength = v
        scope.AetherNightfallDriftStrength = v
        setSetting("driftStrength", v)
    end)
local setDriftShift = switch(driftPage, 238, "Hold Shift to Drift", "IF OFF, DRIFT IS ALWAYS ACTIVE WHEN ENABLED",
    driftShiftOnly, function(v)
        driftShiftOnly = v
        scope.AetherNightfallDriftShiftOnly = v
        setSetting("driftShiftOnly", v)
    end)
local setDriftTrails = switch(driftPage, 312, "Drift Trails", "SOFT BLUE STREAKS ON SHARP TURNS",
    driftTrails, function(v)
        driftTrails = v
        scope.AetherNightfallDriftTrails = v
        setSetting("driftTrails", v)
        if not v then setTrailsActive(false) end
    end)
local setDbdJukes = switch(driftPage, 391, "DBD Jukes  /  A & D", "A = LEFT  /  D = RIGHT  /  ONLY WHILE RUNNING",
    dbdJukes, function(v)
        dbdJukes = v
        setSetting("dbdJukes", v)
        if not v then stopJuke() end
    end)
local setDbdSpin = switch(driftPage, 469, "Full 360 Spin", "ON = 360 DEGREES  /  OFF = QUICK 180",
    dbdFullSpin, function(v)
        dbdFullSpin = v
        setSetting("dbdFullSpin", v)
    end)
local setDbdTurnSpeed = slider(driftPage, 547, "Juke Turn Speed", "HIGHER = FASTER DBD-STYLE SPIN", 0, 100,
    dbdTurnSpeed, function(v)
        dbdTurnSpeed = v
        setSetting("dbdTurnSpeed", v)
    end)
local driftInfo = card(driftPage, 667, 53)
label(driftInfo, "No teleport or extra speed. A/D works while running on ground.",
    13, 8, 418, 18, 10, theme.muted)
label(driftInfo, "Movement is client-side and may be limited by the game.",
    13, 27, 418, 18, 10, theme.muted)
pageLength(driftPage, 750)


-- SETTINGS
pageTitle(settingsPage, "SETTINGS", "PERSISTENCE  /  RESET  /  SHORTCUTS")
local setFovLock = switch(settingsPage, 46, "Keep Camera FOV", "RESTORE FOV AFTER CAMERA CHANGES", config.lockFov, function(v)
    fovLock = v
    setSetting("lockFov", v)
end)
local setJumpLock = switch(settingsPage, 124, "Persistent JumpPower", "REAPPLY JUMP AFTER RESET / RESPAWN", config.lockJump, function(v)
    jumpLock = v
    setSetting("lockJump", v)
    if v then keepJump() end
end)
local controls = card(settingsPage, 208, 150, "HOTKEYS", "CHOOSE MENU TOGGLE KEY")
local activeHotkey = config.hotkey
local hotkeyInfo = label(controls, "Current key: " .. activeHotkey, 13, 43, 260, 17, 11, theme.primary, true)
local hotkeyButtons = {}
for i, key in ipairs({"F6", "F7", "Insert"}) do
    local b = button(controls, key:upper(), 13 + (i-1)*140, 83, 127, 37)
    hotkeyButtons[key] = b
    connect(b.MouseButton1Click, function()
        activeHotkey = key
        hotkeyInfo.Text = "Current key: " .. key
        hotkeyPreview.Text = key:upper() .. "  /  TOGGLE MENU"
        setSetting("hotkey", key)
    end)
end
local resetButton = button(settingsPage, "RESET MOVEMENT + GRAPHICS", 0, 380, 445, 36)
connect(resetButton.MouseButton1Click, function()
    updateSpeed(originalSpeed)
    updateFov(originalFov)
    updateJump(originalJump)
    updateZoom(18)
    updateShoulder(0)
    applyPreset(1)
end)
local settingsInfo = card(settingsPage, 434, 100, "ROLE DETECTION", "ESP COLOR LEGEND")
label(settingsInfo, "MURDERER", 13, 46, 95, 20, 10, theme.red, true)
label(settingsInfo, "INNOCENT", 116, 46, 94, 20, 10, theme.green, true)
label(settingsInfo, "SHERIFF", 220, 46, 90, 20, 10, theme.blue, true)
label(settingsInfo, "UNKNOWN", 321, 46, 100, 20, 10, theme.gray, true)
label(settingsPage, "Unknown stays gray if the game does not replicate roles.",
    5, 552, 440, 20, 10, theme.muted)
local storageHint = card(settingsPage, 590, 112, "STORAGE", "SESSION / OPTIONAL FILE PERSISTENCE")
label(storageHint, "Respawn: settings remain in this script session.", 13, 47, 413, 17, 10, theme.muted)
label(storageHint, "Between sessions: requires readfile / writefile support.", 13, 67, 420, 17, 10, theme.muted)
pageLength(settingsPage, 736)

-- COLOR THEMES
pageTitle(themesPage, "THEMES", "ACCENT COLORS  /  LIQUID GLASS")
local themeColors = {
    OCEAN = Color3.fromRGB(153,217,245),
    VIOLET = Color3.fromRGB(169,135,255),
    ROSE = Color3.fromRGB(255,126,174),
    MINT = Color3.fromRGB(101,237,188),
    AMBER = Color3.fromRGB(255,196,106),
    ICE = Color3.fromRGB(211,233,255),
}
local themeOrder = {"OCEAN","VIOLET","ROSE","MINT","AMBER","ICE"}
local themeButtons = {}
local themeSection = card(themesPage, 46, 303, "ACCENT PRESETS", "DYNAMIC HIGHLIGHTS + STROKES")
local function applyTheme(name)
    local replacement = themeColors[name]
    if not replacement then return end
    local previous = theme.primary
    theme.primary = replacement
    config.theme = name
    for _, obj in ipairs(gui:GetDescendants()) do
        if obj:IsA("UIStroke") and obj.Color == previous then
            obj.Color = replacement
        elseif (obj:IsA("TextLabel") or obj:IsA("TextButton"))
            and obj.TextColor3 == previous then
            obj.TextColor3 = replacement
        elseif obj:IsA("Frame") and obj.BackgroundColor3 == previous then
            obj.BackgroundColor3 = replacement
        end
    end
    for key, b in pairs(themeButtons) do
        b.TextColor3 = key == name and themeColors[key] or theme.text
        b.UIStroke.Color = themeColors[key]
        b.UIStroke.Transparency = key == name and 0 or 0.72
    end
    glassGlow.BackgroundColor3 = replacement
    topHairline.BackgroundColor3 = replacement
    scheduleSave()
end
for i, key in ipairs(themeOrder) do
    local x = (i-1)%2
    local y = math.floor((i-1)/2)
    local b = button(themeSection, "●  " .. key, 13 + x*212, 56 + y*74, 200, 58)
    b.TextColor3 = themeColors[key]
    themeButtons[key] = b
    connect(b.MouseButton1Click, function() applyTheme(key) end)
end
local themeNote = card(themesPage, 367, 82, "GLASS STYLE", "TRANSLUCENT LAYERS / SOFT GLOW")
label(themeNote, "Roblox GUI simulates glass; it cannot truly refract", 13, 46, 420, 16, 10, theme.muted)
label(themesPage, "the 3D scene behind individual panels.", 13, 462, 410, 18, 10, theme.muted)
pageLength(themesPage, 510)

-- THREE CONFIGURATION PROFILES
pageTitle(profilesPage, "PROFILES", "SAVE / LOAD YOUR PERSONAL SETUPS")
local profileButtons = {}
local profileStatus = label(profilesPage, "Current: " .. profileData.active, 0, 41, 433, 22, 12, theme.primary, true)
local applyProfile = nil
for i, slot in ipairs({"DEFAULT", "PVP", "CINEMA"}) do
    local block = card(profilesPage, 78 + (i-1)*111, 98, slot, "INDEPENDENT CONFIGURATION")
    local loadButton = button(block, "LOAD", 13, 49, 190, 32)
    local saveButton = button(block, "SAVE CURRENT", 217, 49, 214, 32)
    connect(loadButton.MouseButton1Click, function()
        saveNow()
        profileData.active = slot
        loadSlot(slot)
        if applyProfile then applyProfile() end
        profileStatus.Text = "Current: " .. slot
        scheduleSave()
    end)
    connect(saveButton.MouseButton1Click, function()
        profileData.slots[slot] = table.clone(config)
        profileStatus.Text = "Saved to: " .. slot
        saveNow()
    end)
end
local profileNote = card(profilesPage, 432, 66, "TIP", "SAVE BEFORE SWITCHING TO A DIFFERENT SETUP")
pageLength(profilesPage, 524)

applyProfile = function()
    updateSpeed(config.speed)
    updateFov(config.fov)
    updateJump(config.jump)
    updateZoom(config.zoom)
    updateShoulder(config.shoulder)
    setSpeedLock(config.lockSpeed)
    setJumpLock(config.lockJump)
    setFovLock(config.lockFov)
    activeHotkey = config.hotkey
    hotkeyInfo.Text = "Current key: " .. activeHotkey
    hotkeyPreview.Text = activeHotkey:upper() .. "  /  TOGGLE MENU"
    updateBloom(config.glow)
    updateContrast(config.contrast)
    updateSaturation(config.saturation)
    applyPreset(math.clamp(config.preset,1,#presets))
    espRange(config.espRange)
    setEspEnabled(config.espEnabled)
    setEspNames(config.espNames)
    setEspDistance(config.espDistance)
    setEspRoles(config.espRoles)
    setHighlight(config.espHighlights)
    setHealth(config.espHealth)
    setTracers(config.espTracers)
    setCorners(config.espCorners)
    setSkeleton(config.espSkeleton)
    setDriftEnabled(config.driftEnabled)
    setDriftStrength(config.driftStrength)
    setDriftShift(config.driftShiftOnly)
    setDriftTrails(config.driftTrails)
    setDbdJukes(config.dbdJukes)
    setDbdSpin(config.dbdFullSpin)
    setDbdTurnSpeed(config.dbdTurnSpeed)
    applyTheme(config.theme)
end


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
    if input.KeyCode == Enum.KeyCode.LeftShift or input.KeyCode == Enum.KeyCode.RightShift then
        shiftHeld = true
    end
    if processed then return end
    if input.KeyCode == Enum.KeyCode[activeHotkey] then
        toggleMenu()
    elseif UserInputService:GetFocusedTextBox() == nil then
        if input.KeyCode == Enum.KeyCode.A then
            beginJuke(-1)
        elseif input.KeyCode == Enum.KeyCode.D then
            beginJuke(1)
        end
    end
end)
connect(UserInputService.InputEnded, function(input)
    if input.KeyCode == Enum.KeyCode.LeftShift or input.KeyCode == Enum.KeyCode.RightShift then
        shiftHeld = UserInputService:IsKeyDown(Enum.KeyCode.LeftShift)
            or UserInputService:IsKeyDown(Enum.KeyCode.RightShift)
    end
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
    if not updateJuke(dt) then applyDrift(dt) end
    elapsed = elapsed + dt
    espElapsed = espElapsed + dt
    if elapsed >= 0.25 then
        elapsed = 0
        keepSpeed()
        keepJump()
        rescale()
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
    stopJuke()
    stopTrails()
    for _, entry in pairs(boxes) do
        pcall(function() entry.frame:Destroy() end)
        pcall(function() entry.tracer:Destroy() end)
        for _, line in ipairs(entry.skeletonLines) do
            pcall(function() line:Destroy() end)
        end
    end
    clearHighlights()
    saveNow()
    restoreLighting()
    local ch = localPlayer.Character
    local h = ch and ch:FindFirstChildOfClass("Humanoid")
    if h then
        h.WalkSpeed = originalSpeed
        h.JumpPower = originalJump
        h.CameraOffset = Vector3.zero
    end
    pcall(function()
        localPlayer.CameraMaxZoomDistance = originalMaxZoom
        localPlayer.CameraMinZoomDistance = originalMinZoom
    end)
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
scope.AetherNightfall = {Destroy = destroy, Version = "3.6-DBD", Profiles = profileData}
applyCamera()
keepSpeed()
keepJump()
applyTheme(config.theme)
applyPreset(math.clamp(tonumber(config.preset) or 1, 1, #presets))
showPage("Main")
saveNow()
print("[AETHER V3.7 DBD] A/D jukes + drift / ESP / visuals / profiles loaded.")
]==])()
