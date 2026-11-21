
loadstring([==[
-- AETHER VISUALS / MAIN
-- Toggle: F6 (or Fn + F6 on some laptops)

local Players = game:GetService("Players")
local UIS = game:GetService("UserInputService")
local TS = game:GetService("TweenService")
local Lighting = game:GetService("Lighting")

local player = Players.LocalPlayer
local env = (getgenv and getgenv()) or _G

if env.AetherVisuals and env.AetherVisuals.Destroy then
    pcall(env.AetherVisuals.Destroy)
end

local connections = {}
local function listen(signal, callback)
    local connection = signal:Connect(callback)
    table.insert(connections, connection)
    return connection
end

local function rgb(r,g,b)
    return Color3.fromRGB(r,g,b)
end

local accent = rgb(125,105,255)
local white = rgb(238,239,255)
local muted = rgb(136,141,168)
local surface = rgb(20,23,39)

local function new(class, parent, props)
    local item = Instance.new(class)
    for k,v in pairs(props or {}) do
        item[k] = v
    end
    item.Parent = parent
    return item
end

local function corner(parent, radius)
    return new("UICorner",parent,{
        CornerRadius = UDim.new(0,radius)
    })
end

local function outline(parent,color,trans)
    return new("UIStroke",parent,{
        Color=color or accent,
        Transparency=trans or 0.6,
        Thickness=1
    })
end

local function tween(obj,properties,time)
    TS:Create(obj,TweenInfo.new(
        time or 0.23,
        Enum.EasingStyle.Quint,
        Enum.EasingDirection.Out
    ),properties):Play()
end

local function text(parent,str,pos,size,fontSize,color,bold)
    return new("TextLabel",parent,{
        BackgroundTransparency=1,
        Position=pos,
        Size=size,
        Text=str,
        TextColor3=color or white,
        TextSize=fontSize or 13,
        Font=bold and Enum.Font.GothamBold or Enum.Font.Gotham,
        TextXAlignment=Enum.TextXAlignment.Left,
        TextYAlignment=Enum.TextYAlignment.Center
    })
end

-- ORIGINAL GAME VALUES
local original = {
    Ambient=Lighting.Ambient,
    OutdoorAmbient=Lighting.OutdoorAmbient,
    ClockTime=Lighting.ClockTime,
    Brightness=Lighting.Brightness,
    ExposureCompensation=Lighting.ExposureCompensation
}

local camera = workspace.CurrentCamera
local originalFov = camera and camera.FieldOfView or 70

local character = player.Character
local humanoid = character and character:FindFirstChildOfClass("Humanoid")
local originalSpeed = humanoid and humanoid.WalkSpeed or 16

local currentSpeed = originalSpeed
local currentFov = originalFov

-- POST PROCESSING
local CC = new("ColorCorrectionEffect",Lighting,{
    Name="AetherColor",
    Enabled=false
})

local Bloom = new("BloomEffect",Lighting,{
    Name="AetherBloom",
    Enabled=false,
    Intensity=0.6,
    Size=40,
    Threshold=1
})

local Rays = new("SunRaysEffect",Lighting,{
    Name="AetherRays",
    Enabled=false,
    Intensity=0.1,
    Spread=0.6
})

local function restoreLighting()
    for key,value in pairs(original) do
        Lighting[key]=value
    end
    CC.Enabled=false
    Bloom.Enabled=false
    Rays.Enabled=false
end

local presets = {
    {
        name="ORIGINAL",
        color=rgb(125,130,155)
    },
    {
        name="CINEMATIC",
        color=rgb(120,150,255),
        time=17.5,
        ambient=rgb(65,66,88),
        outdoor=rgb(105,105,125),
        brightness=2,
        exposure=0.05,
        tint=rgb(255,235,216),
        contrast=0.19,
        saturation=-0.07,
        bloom=0.4,
        rays=0.08
    },
    {
        name="NEON",
        color=rgb(77,223,255),
        time=20,
        ambient=rgb(55,48,105),
        outdoor=rgb(75,80,145),
        brightness=2.5,
        exposure=0.15,
        tint=rgb(190,218,255),
        contrast=0.24,
        saturation=0.22,
        bloom=1.2,
        rays=0
    },
    {
        name="SUNSET",
        color=rgb(255,155,98),
        time=17.7,
        ambient=rgb(110,75,75),
        outdoor=rgb(170,115,95),
        brightness=2.2,
        exposure=0.1,
        tint=rgb(255,211,173),
        contrast=0.13,
        saturation=0.18,
        bloom=0.65,
        rays=0.2
    },
    {
        name="NOIR",
        color=rgb(205,210,225),
        time=14,
        ambient=rgb(90,90,90),
        outdoor=rgb(115,115,115),
        brightness=2,
        exposure=0,
        tint=rgb(245,245,255),
        contrast=0.4,
        saturation=-1,
        bloom=0.15,
        rays=0
    },
    {
        name="DREAM",
        color=rgb(240,127,255),
        time=9.5,
        ambient=rgb(110,75,130),
        outdoor=rgb(145,125,180),
        brightness=2.5,
        exposure=0.2,
        tint=rgb(255,215,255),
        contrast=0.08,
        saturation=0.23,
        bloom=1.3,
        rays=0.07
    }
}

local buttons={}
local selected=1

local function applyPreset(index)
    selected=index
    restoreLighting()

    local p=presets[index]
    if index~=1 then
        Lighting.ClockTime=p.time
        Lighting.Ambient=p.ambient
        Lighting.OutdoorAmbient=p.outdoor
        Lighting.Brightness=p.brightness
        Lighting.ExposureCompensation=p.exposure

        CC.Enabled=true
        CC.TintColor=p.tint
        CC.Contrast=p.contrast
        CC.Saturation=p.saturation
        CC.Brightness=0

        Bloom.Enabled=p.bloom>0
        Bloom.Intensity=p.bloom
        Bloom.Size=40

        Rays.Enabled=p.rays>0
        Rays.Intensity=p.rays
    end

    for i,button in ipairs(buttons) do
        local active=i==index
        tween(button,{
            BackgroundColor3=active and presets[i].color or rgb(31,35,54),
            BackgroundTransparency=active and 0.12 or 0.15
        })
        tween(button.UIStroke,{
            Transparency=active and 0.05 or 0.85
        })
        tween(button,{
            TextColor3=active and rgb(12,15,25) or white
        })
    end
end

-- GUI
local parent=player:WaitForChild("PlayerGui")
if type(gethui)=="function" then
    local ok,result=pcall(gethui)
    if ok and result then parent=result end
end

local gui=new("ScreenGui",parent,{
    Name="AETHER_VISUALS",
    ResetOnSpawn=false,
    IgnoreGuiInset=true,
    ZIndexBehavior=Enum.ZIndexBehavior.Sibling
})

local shadow=new("Frame",gui,{
    AnchorPoint=Vector2.new(0.5,0.5),
    Position=UDim2.fromScale(0.5,0.5),
    Size=UDim2.new(0,540,0,576),
    BackgroundColor3=rgb(0,0,0),
    BackgroundTransparency=0.5,
    BorderSizePixel=0
})
corner(shadow,24)

local panel=new("Frame",gui,{
    AnchorPoint=Vector2.new(0.5,0.5),
    Position=UDim2.fromScale(0.5,0.5),
    Size=UDim2.new(0,512,0,548),
    BackgroundColor3=rgb(13,16,29),
    BackgroundTransparency=0.04,
    BorderSizePixel=0,
    ClipsDescendants=true
})
corner(panel,19)
outline(panel,rgb(130,125,210),0.35)

new("UIGradient",panel,{
    Color=ColorSequence.new({
        ColorSequenceKeypoint.new(0,rgb(30,33,57)),
        ColorSequenceKeypoint.new(0.5,rgb(16,19,35)),
        ColorSequenceKeypoint.new(1,rgb(10,13,25))
    }),
    Rotation=115
})

local scale=new("UIScale",panel,{Scale=1})

-- ACCENT STRIP
local strip=new("Frame",panel,{
    Position=UDim2.new(0,24,0,0),
    Size=UDim2.new(1,-48,0,2),
    BackgroundColor3=accent,
    BorderSizePixel=0
})
corner(strip,2)

new("UIGradient",strip,{
    Color=ColorSequence.new(
        rgb(58,180,255),
        rgb(198,105,255)
    )
})

-- HEADER
local logo=new("Frame",panel,{
    Position=UDim2.fromOffset(19,22),
    Size=UDim2.fromOffset(39,39),
    BackgroundColor3=accent,
    BackgroundTransparency=0.13
})
corner(logo,12)

local logoText=text(logo,"✦",
    UDim2.fromScale(0,0),
    UDim2.fromScale(1,1),
    27,rgb(255,255,255),true)
logoText.TextXAlignment=Enum.TextXAlignment.Center

text(panel,"AETHER",
    UDim2.fromOffset(72,19),
    UDim2.fromOffset(220,27),
    21,white,true)

text(panel,"VISUAL CONTROL  /  v1.0",
    UDim2.fromOffset(73,46),
    UDim2.fromOffset(240,17),
    10,muted,true)

local hide=new("TextButton",panel,{
    Position=UDim2.new(1,-54,0,26),
    Size=UDim2.fromOffset(31,30),
    BackgroundColor3=rgb(40,43,63),
    Text="—",
    TextSize=19,
    TextColor3=white,
    Font=Enum.Font.GothamBold,
    AutoButtonColor=false
})
corner(hide,9)
outline(hide,rgb(170,170,205),0.82)

local header=new("Frame",panel,{
    Position=UDim2.fromOffset(0,0),
    Size=UDim2.new(1,-65,0,76),
    BackgroundTransparency=1
})

-- ONLY ONE TAB: MAIN
local tab=new("Frame",panel,{
    Position=UDim2.fromOffset(17,82),
    Size=UDim2.new(1,-34,0,40),
    BackgroundColor3=rgb(26,29,50),
    BorderSizePixel=0
})
corner(tab,11)
outline(tab,accent,0.68)

local mark=new("Frame",tab,{
    Position=UDim2.fromOffset(14,10),
    Size=UDim2.fromOffset(3,20),
    BackgroundColor3=accent,
    BorderSizePixel=0
})
corner(mark,3)

text(tab,"MAIN",
    UDim2.fromOffset(28,0),
    UDim2.fromOffset(200,40),
    13,white,true)

text(tab,"01 / CONTROL",
    UDim2.new(1,-118,0,0),
    UDim2.fromOffset(110,40),
    10,muted,true)

local function card(y,h)
    local frame=new("Frame",panel,{
        Position=UDim2.fromOffset(17,y),
        Size=UDim2.new(1,-34,0,h),
        BackgroundColor3=surface,
        BackgroundTransparency=0.2,
        BorderSizePixel=0
    })
    corner(frame,13)
    outline(frame,rgb(115,119,165),0.85)
    return frame
end

local function slider(cardFrame,title,subtitle,min,max,initial,callback)
    text(cardFrame,title,
        UDim2.fromOffset(15,10),
        UDim2.fromOffset(285,21),
        14,white,true)

    text(cardFrame,subtitle,
        UDim2.fromOffset(15,33),
        UDim2.fromOffset(310,15),
        10,muted,false)

    local box=new("TextBox",cardFrame,{
        Position=UDim2.new(1,-77,0,14),
        Size=UDim2.fromOffset(62,30),
        BackgroundColor3=rgb(38,41,66),
        Text="",
        TextSize=14,
        TextColor3=white,
        Font=Enum.Font.GothamBold,
        ClearTextOnFocus=false,
        BorderSizePixel=0
    })
    corner(box,9)
    outline(box,accent,0.75)

    local track=new("Frame",cardFrame,{
        Position=UDim2.new(0,16,0,64),
        Size=UDim2.new(1,-32,0,5),
        BackgroundColor3=rgb(50,53,78),
        BorderSizePixel=0
    })
    corner(track,5)

    local fill=new("Frame",track,{
        Size=UDim2.fromScale(0,1),
        BackgroundColor3=accent,
        BorderSizePixel=0
    })
    corner(fill,5)

    new("UIGradient",fill,{
        Color=ColorSequence.new(
            rgb(85,175,255),
            rgb(189,100,255)
        )
    })

    local knob=new("Frame",track,{
        AnchorPoint=Vector2.new(0.5,0.5),
        Position=UDim2.fromScale(0,0.5),
        Size=UDim2.fromOffset(15,15),
        BackgroundColor3=white,
        BorderSizePixel=0
    })
    corner(knob,15)
    outline(knob,accent,0.15)

    local value=initial

    local function set(n)
        n=tonumber(n) or value
        value=math.floor(math.clamp(n,min,max)+0.5)
        box.Text=tostring(value)

        local alpha=(value-min)/(max-min)
        tween(fill,{Size=UDim2.fromScale(alpha,1)},0.12)
        tween(knob,{
            Position=UDim2.fromScale(alpha,0.5)
        },0.12)

        callback(value)
    end

    local dragging=false

    local function fromX(x)
        local alpha=math.clamp(
            (x-track.AbsolutePosition.X)/track.AbsoluteSize.X,
            0,1
        )
        set(min+(max-min)*alpha)
    end

    listen(track.InputBegan,function(input)
        if input.UserInputType==Enum.UserInputType.MouseButton1
        or input.UserInputType==Enum.UserInputType.Touch then
            dragging=true
            fromX(input.Position.X)
        end
    end)

    listen(UIS.InputChanged,function(input)
        if dragging and (
            input.UserInputType==Enum.UserInputType.MouseMovement
            or input.UserInputType==Enum.UserInputType.Touch
        ) then
            fromX(input.Position.X)
        end
    end)

    listen(UIS.InputEnded,function(input)
        if input.UserInputType==Enum.UserInputType.MouseButton1
        or input.UserInputType==Enum.UserInputType.Touch then
            dragging=false
        end
    end)

    listen(box.FocusLost,function()
        set(box.Text)
    end)

    set(initial)
    return set
end

local speedCard=card(133,87)
local setSpeed=slider(
    speedCard,
    "WalkSpeed",
    "CHARACTER MOVEMENT SPEED",
    8,200,originalSpeed,
    function(value)
        currentSpeed=value
        local char=player.Character
        local hum=char and char:FindFirstChildOfClass("Humanoid")
        if hum then hum.WalkSpeed=value end
    end
)

local fovCard=card(230,87)
local setFov=slider(
    fovCard,
    "Camera FOV",
    "FIELD OF VIEW",
    40,120,originalFov,
    function(value)
        currentFov=value
        local cam=workspace.CurrentCamera
        if cam then cam.FieldOfView=value end
    end
)

local visualCard=card(327,157)

text(visualCard,"Visual Presets",
    UDim2.fromOffset(15,9),
    UDim2.fromOffset(260,23),
    14,white,true)

text(visualCard,"POST PROCESSING / LIGHTING",
    UDim2.fromOffset(15,30),
    UDim2.fromOffset(300,14),
    10,muted,false)

for i,p in ipairs(presets) do
    local column=(i-1)%3
    local row=math.floor((i-1)/3)

    local button=new("TextButton",visualCard,{
        Position=UDim2.fromOffset(15+column*158,49+row*49),
        Size=UDim2.fromOffset(143,40),
        BackgroundColor3=rgb(31,35,54),
        Text=p.name,
        TextColor3=white,
        TextSize=11,
        Font=Enum.Font.GothamBold,
        AutoButtonColor=false,
        BorderSizePixel=0
    })
    corner(button,10)
    outline(button,p.color,0.85)

    buttons[i]=button

    listen(button.MouseEnter,function()
        if selected~=i then
            tween(button,{
                BackgroundColor3=rgb(48,51,80)
            },0.17)
        end
    end)

    listen(button.MouseLeave,function()
        if selected~=i then
            tween(button,{
                BackgroundColor3=rgb(31,35,54)
            },0.17)
        end
    end)

    listen(button.MouseButton1Click,function()
        applyPreset(i)
    end)
end

-- FOOTER
local statusDot=new("Frame",panel,{
    Position=UDim2.fromOffset(22,510),
    Size=UDim2.fromOffset(7,7),
    BackgroundColor3=rgb(90,240,165),
    BorderSizePixel=0
})
corner(statusDot,7)

text(panel,"CLIENT SIDE  •  ACTIVE",
    UDim2.fromOffset(36,501),
    UDim2.fromOffset(235,25),
    10,muted,true)

local reset=new("TextButton",panel,{
    Position=UDim2.new(1,-111,0,497),
    Size=UDim2.fromOffset(91,33),
    BackgroundColor3=rgb(40,43,63),
    Text="RESET",
    TextSize=11,
    TextColor3=white,
    Font=Enum.Font.GothamBold,
    BorderSizePixel=0,
    AutoButtonColor=false
})
corner(reset,9)
outline(reset,rgb(135,135,180),0.75)

listen(reset.MouseButton1Click,function()
    setSpeed(originalSpeed)
    setFov(originalFov)
    applyPreset(1)
end)

applyPreset(1)

-- WINDOW ANIMATION
local opened=true

local function toggle()
    opened=not opened

    if opened then
        gui.Enabled=true
        scale.Scale=0.93
        tween(scale,{Scale=1},0.32)
    else
        tween(scale,{Scale=0.93},0.16)
        task.delay(0.16,function()
            if not opened and gui.Parent then
                gui.Enabled=false
            end
        end)
    end
end

listen(hide.MouseButton1Click,toggle)

listen(UIS.InputBegan,function(input,processed)
    if processed then return end
    if input.KeyCode==Enum.KeyCode.F6 then
        toggle()
    end
end)

-- DRAGGING
local moving=false
local dragStart
local panelStart

listen(header.InputBegan,function(input)
    if input.UserInputType==Enum.UserInputType.MouseButton1
    or input.UserInputType==Enum.UserInputType.Touch then
        moving=true
        dragStart=input.Position
        panelStart=panel.Position
    end
end)

listen(UIS.InputChanged,function(input)
    if not moving then return end

    if input.UserInputType==Enum.UserInputType.MouseMovement
    or input.UserInputType==Enum.UserInputType.Touch then
        local delta=input.Position-dragStart
        local position=UDim2.new(
            panelStart.X.Scale,
            panelStart.X.Offset+delta.X,
            panelStart.Y.Scale,
            panelStart.Y.Offset+delta.Y
        )

        panel.Position=position
        shadow.Position=position
    end
end)

listen(UIS.InputEnded,function(input)
    if input.UserInputType==Enum.UserInputType.MouseButton1
    or input.UserInputType==Enum.UserInputType.Touch then
        moving=false
    end
end)

-- RESPAWN SUPPORT
listen(player.CharacterAdded,function(char)
    task.spawn(function()
        local hum=char:WaitForChild("Humanoid",10)
        if hum then
            hum.WalkSpeed=currentSpeed
        end
    end)
end)

-- RE-EXECUTION CLEANUP
env.AetherVisuals={
    Destroy=function()
        for _,connection in ipairs(connections) do
            connection:Disconnect()
        end

        restoreLighting()

        local cam=workspace.CurrentCamera
        if cam then cam.FieldOfView=originalFov end

        local char=player.Character
        local hum=char and char:FindFirstChildOfClass("Humanoid")
        if hum then hum.WalkSpeed=originalSpeed end

        CC:Destroy()
        Bloom:Destroy()
        Rays:Destroy()
        gui:Destroy()
    end
}

-- ENTRANCE
scale.Scale=0.84
tween(scale,{Scale=1},0.45)

print("[AETHER] Loaded. Press F6 to toggle.")
]==])()
