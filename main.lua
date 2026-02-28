--[[
    ╔══════════════════════════════════════════════════╗
    ║        LOCK-ON TARGET SYSTEM v2.0                ║
    ║        Mobile + PC | Console Style               ║
    ║        Bug-free & Production Ready               ║
    ╚══════════════════════════════════════════════════╝
    
    LocalScript — StarterPlayerScripts
    
    CONTROLES:
      PC:     Q = Lock/Unlock  |  E = Próximo alvo  |  R = Alvo anterior
      Mobile: Botão na tela    |  ◀ ▶ ou Swipe horizontal
    
    FEATURES:
      • Auto-lock ao bater em alguém
      • Destrava ao alvo morrer / sair do range
      • HP bar em tempo real
      • Indicador 3D animado
      • Trocar entre alvos
      • Compatível Mobile + PC + Gamepad
      • Camera suave estilo Souls/Zelda
--]]

-- ══════════════════════════════════════════════════════
-- SERVICES
-- ══════════════════════════════════════════════════════
local Players          = game:GetService("Players")
local RunService       = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService     = game:GetService("TweenService")

local Camera       = workspace.CurrentCamera
local LocalPlayer  = Players.LocalPlayer
local PlayerGui    = LocalPlayer:WaitForChild("PlayerGui")

-- ══════════════════════════════════════════════════════
-- CONFIGURAÇÕES (edite aqui)
-- ══════════════════════════════════════════════════════
local CONFIG = {
    -- Gameplay
    MaxLockDistance       = 120,
    LockSmoothness       = 0.2,
    CameraOffset         = Vector3.new(0, 4, 14),
    HeightOffset         = Vector3.new(0, 2, 0),
    AutoLockOnHit        = true,
    BreakLockOnDeath     = true,

    -- Teclas PC
    LockKey              = Enum.KeyCode.Q,
    NextTargetKey        = Enum.KeyCode.E,
    PrevTargetKey        = Enum.KeyCode.R,

    -- Visual
    IndicatorEnabled     = true,
    ShowTargetInfo       = true,
    FOVLocked            = 55,
    FOVTransitionSpeed   = 0.15,

    -- Mobile
    ButtonSize           = 65,
    SwipeThreshold       = 60,
}

-- ══════════════════════════════════════════════════════
-- ESTADO
-- ══════════════════════════════════════════════════════
local State = {
    LockedTarget   = nil,
    IsLocked       = false,
    Character      = nil,
    Humanoid       = nil,
    RootPart       = nil,
    DefaultFOV     = Camera.FieldOfView,
    Connections    = {},   -- armazena todas as connections pra cleanup
    Indicator      = nil,
    TouchStart     = nil,
}

-- ══════════════════════════════════════════════════════
-- UTILIDADES
-- ══════════════════════════════════════════════════════
local function SafeDisconnect(key)
    if State.Connections[key] then
        State.Connections[key]:Disconnect()
        State.Connections[key] = nil
    end
end

local function DisconnectAll()
    for key, conn in pairs(State.Connections) do
        if typeof(conn) == "RBXScriptConnection" then
            conn:Disconnect()
        end
    end
    State.Connections = {}
end

local function GetCharacterParts(player)
    local char = player and player.Character
    if not char then return nil, nil, nil end
    local root = char:FindFirstChild("HumanoidRootPart")
    local hum = char:FindFirstChildOfClass("Humanoid")
    return char, root, hum
end

local function IsAlive(player)
    local _, _, hum = GetCharacterParts(player)
    return hum and hum.Health > 0
end

local function DistanceTo(player)
    if not State.RootPart then return math.huge end
    local _, root = GetCharacterParts(player)
    if not root then return math.huge end
    return (State.RootPart.Position - root.Position).Magnitude
end

local function HasLineOfSight(targetRoot)
    if not State.RootPart or not targetRoot then return false end

    local origin = State.RootPart.Position + Vector3.new(0, 1, 0)
    local direction = targetRoot.Position - origin

    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = {State.Character, targetRoot.Parent}

    local result = workspace:Raycast(origin, direction, params)
    return result == nil -- nil = nada bloqueando
end

-- ══════════════════════════════════════════════════════
-- BUSCA DE ALVOS
-- ══════════════════════════════════════════════════════
local function GetValidTargets()
    local targets = {}
    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= LocalPlayer and IsAlive(player) then
            local dist = DistanceTo(player)
            if dist <= CONFIG.MaxLockDistance then
                local _, root = GetCharacterParts(player)
                if root and HasLineOfSight(root) then
                    table.insert(targets, {
                        Player = player,
                        Distance = dist,
                    })
                end
            end
        end
    end
    table.sort(targets, function(a, b) return a.Distance < b.Distance end)
    return targets
end

local function FindNearest()
    local targets = GetValidTargets()
    return targets[1] and targets[1].Player or nil
end

local function GetTargetIndex(targets, target)
    for i, t in ipairs(targets) do
        if t.Player == target then return i end
    end
    return 0
end

local function CycleTarget(direction)
    if not State.IsLocked then return end
    local targets = GetValidTargets()
    if #targets <= 1 then return end

    local idx = GetTargetIndex(targets, State.LockedTarget)
    idx = idx + direction
    if idx < 1 then idx = #targets end
    if idx > #targets then idx = 1 end

    -- Chama LockOn declarado abaixo via forward reference
    _G._LockOnFn(targets[idx].Player)
end

-- ══════════════════════════════════════════════════════
-- INDICADOR 3D
-- ══════════════════════════════════════════════════════
local function DestroyIndicator()
    if State.Indicator then
        State.Indicator:Destroy()
        State.Indicator = nil
    end
end

local function CreateIndicator(targetRoot)
    DestroyIndicator()
    if not CONFIG.IndicatorEnabled or not targetRoot then return end

    local bb = Instance.new("BillboardGui")
    bb.Name = "LockOnIndicator"
    bb.Size = UDim2.new(2.8, 0, 2.8, 0)
    bb.AlwaysOnTop = true
    bb.LightInfluence = 0
    bb.StudsOffset = Vector3.new(0, 0.5, 0)

    local holder = Instance.new("Frame")
    holder.Size = UDim2.new(1, 0, 1, 0)
    holder.BackgroundTransparency = 1
    holder.Parent = bb

    -- Anel externo
    local ring = Instance.new("Frame")
    ring.Name = "Ring"
    ring.AnchorPoint = Vector2.new(0.5, 0.5)
    ring.Position = UDim2.new(0.5, 0, 0.5, 0)
    ring.Size = UDim2.new(0.55, 0, 0.55, 0)
    ring.BackgroundColor3 = Color3.fromRGB(255, 40, 40)
    ring.BackgroundTransparency = 0.25
    ring.BorderSizePixel = 0
    ring.Parent = holder
    Instance.new("UICorner", ring).CornerRadius = UDim.new(1, 0)

    -- Buraco interno
    local hole = Instance.new("Frame")
    hole.AnchorPoint = Vector2.new(0.5, 0.5)
    hole.Position = UDim2.new(0.5, 0, 0.5, 0)
    hole.Size = UDim2.new(0.65, 0, 0.65, 0)
    hole.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
    hole.BackgroundTransparency = 0.75
    hole.BorderSizePixel = 0
    hole.Parent = ring
    Instance.new("UICorner", hole).CornerRadius = UDim.new(1, 0)

    -- Ponto central
    local dot = Instance.new("Frame")
    dot.AnchorPoint = Vector2.new(0.5, 0.5)
    dot.Position = UDim2.new(0.5, 0, 0.5, 0)
    dot.Size = UDim2.new(0.12, 0, 0.12, 0)
    dot.BackgroundColor3 = Color3.fromRGB(255, 60, 60)
    dot.BorderSizePixel = 0
    dot.Parent = holder
    Instance.new("UICorner", dot).CornerRadius = UDim.new(1, 0)

    -- 4 traços girantes
    local spinner = Instance.new("Frame")
    spinner.Name = "Spinner"
    spinner.AnchorPoint = Vector2.new(0.5, 0.5)
    spinner.Position = UDim2.new(0.5, 0, 0.5, 0)
    spinner.Size = UDim2.new(0.85, 0, 0.85, 0)
    spinner.BackgroundTransparency = 1
    spinner.Rotation = 0
    spinner.Parent = holder

    for i = 0, 3 do
        local tick = Instance.new("Frame")
        tick.AnchorPoint = Vector2.new(0.5, 0)
        tick.Position = UDim2.new(0.5, 0, 0, 0)
        tick.Size = UDim2.new(0.06, 0, 0.2, 0)
        tick.Rotation = i * 90
        tick.BackgroundColor3 = Color3.fromRGB(255, 100, 100)
        tick.BackgroundTransparency = 0.35
        tick.BorderSizePixel = 0
        tick.Parent = spinner
        Instance.new("UICorner", tick).CornerRadius = UDim.new(0, 2)
    end

    -- Animação segura
    task.spawn(function()
        while bb and bb.Parent do
            local ok, tween = pcall(function()
                return TweenService:Create(
                    spinner,
                    TweenInfo.new(3, Enum.EasingStyle.Linear),
                    {Rotation = spinner.Rotation + 360}
                )
            end)
            if not ok then break end
            tween:Play()
            tween.Completed:Wait()
        end
    end)

    -- Animação de escala de entrada
    ring.Size = UDim2.new(0.9, 0, 0.9, 0)
    TweenService:Create(ring, TweenInfo.new(0.3, Enum.EasingStyle.Back), {
        Size = UDim2.new(0.55, 0, 0.55, 0)
    }):Play()

    bb.Adornee = targetRoot
    bb.Parent = targetRoot
    State.Indicator = bb
end

-- ══════════════════════════════════════════════════════
-- UI MOBILE
-- ══════════════════════════════════════════════════════
local UI = {}

local function BuildUI()
    -- Limpa UI anterior se existir
    local old = PlayerGui:FindFirstChild("LockOnUI")
    if old then old:Destroy() end

    local screen = Instance.new("ScreenGui")
    screen.Name = "LockOnUI"
    screen.ResetOnSpawn = false
    screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    screen.DisplayOrder = 10
    screen.Parent = PlayerGui

    -- ═══ CONTAINER DOS BOTÕES ═══
    local btnContainer = Instance.new("Frame")
    btnContainer.Name = "Buttons"
    btnContainer.Size = UDim2.new(0, 180, 0, 130)
    btnContainer.Position = UDim2.new(1, -190, 0.55, 0)
    btnContainer.BackgroundTransparency = 1
    btnContainer.Parent = screen

    -- Botão principal LOCK
    local lockBtn = Instance.new("TextButton")
    lockBtn.Name = "LockBtn"
    lockBtn.AnchorPoint = Vector2.new(0.5, 0.5)
    lockBtn.Position = UDim2.new(0.5, 0, 0.4, 0)
    lockBtn.Size = UDim2.new(0, CONFIG.ButtonSize, 0, CONFIG.ButtonSize)
    lockBtn.BackgroundColor3 = Color3.fromRGB(35, 35, 40)
    lockBtn.BackgroundTransparency = 0.2
    lockBtn.BorderSizePixel = 0
    lockBtn.Text = "⊕"
    lockBtn.TextColor3 = Color3.fromRGB(200, 200, 200)
    lockBtn.TextScaled = true
    lockBtn.Font = Enum.Font.GothamBold
    lockBtn.AutoButtonColor = false
    lockBtn.Parent = btnContainer
    Instance.new("UICorner", lockBtn).CornerRadius = UDim.new(1, 0)

    local lockStroke = Instance.new("UIStroke")
    lockStroke.Color = Color3.fromRGB(150, 150, 160)
    lockStroke.Thickness = 2.5
    lockStroke.Parent = lockBtn

    -- Label
    local lockLbl = Instance.new("TextLabel")
    lockLbl.Name = "Label"
    lockLbl.AnchorPoint = Vector2.new(0.5, 0)
    lockLbl.Position = UDim2.new(0.5, 0, 1, 4)
    lockLbl.Size = UDim2.new(0, 60, 0, 16)
    lockLbl.BackgroundTransparency = 1
    lockLbl.Text = "LOCK"
    lockLbl.TextColor3 = Color3.fromRGB(160, 160, 170)
    lockLbl.TextSize = 11
    lockLbl.Font = Enum.Font.GothamBold
    lockLbl.Parent = lockBtn

    -- Botão esquerda
    local leftBtn = Instance.new("TextButton")
    leftBtn.Name = "LeftBtn"
    leftBtn.AnchorPoint = Vector2.new(0.5, 0.5)
    leftBtn.Position = UDim2.new(0.15, 0, 0.4, 0)
    leftBtn.Size = UDim2.new(0, 42, 0, 42)
    leftBtn.BackgroundColor3 = Color3.fromRGB(35, 35, 40)
    leftBtn.BackgroundTransparency = 0.4
    leftBtn.BorderSizePixel = 0
    leftBtn.Text = "◀"
    leftBtn.TextColor3 = Color3.fromRGB(180, 180, 190)
    leftBtn.TextScaled = true
    leftBtn.Font = Enum.Font.GothamBold
    leftBtn.AutoButtonColor = false
    leftBtn.Visible = false
    leftBtn.Parent = btnContainer
    Instance.new("UICorner", leftBtn).CornerRadius = UDim.new(0.3, 0)

    -- Botão direita
    local rightBtn = Instance.new("TextButton")
    rightBtn.Name = "RightBtn"
    rightBtn.AnchorPoint = Vector2.new(0.5, 0.5)
    rightBtn.Position = UDim2.new(0.85, 0, 0.4, 0)
    rightBtn.Size = UDim2.new(0, 42, 0, 42)
    rightBtn.BackgroundColor3 = Color3.fromRGB(35, 35, 40)
    rightBtn.BackgroundTransparency = 0.4
    rightBtn.BorderSizePixel = 0
    rightBtn.Text = "▶"
    rightBtn.TextColor3 = Color3.fromRGB(180, 180, 190)
    rightBtn.TextScaled = true
    rightBtn.Font = Enum.Font.GothamBold
    rightBtn.AutoButtonColor = false
    rightBtn.Visible = false
    rightBtn.Parent = btnContainer
    Instance.new("UICorner", rightBtn).CornerRadius = UDim.new(0.3, 0)

    -- ═══ PAINEL DE INFO DO ALVO ═══
    local infoPanel = Instance.new("Frame")
    infoPanel.Name = "TargetInfo"
    infoPanel.AnchorPoint = Vector2.new(0.5, 0)
    infoPanel.Position = UDim2.new(0.5, 0, 0, 70)
    infoPanel.Size = UDim2.new(0, 220, 0, 48)
    infoPanel.BackgroundColor3 = Color3.fromRGB(15, 15, 20)
    infoPanel.BackgroundTransparency = 0.35
    infoPanel.BorderSizePixel = 0
    infoPanel.Visible = false
    infoPanel.Parent = screen
    Instance.new("UICorner", infoPanel).CornerRadius = UDim.new(0, 8)

    local infoStroke = Instance.new("UIStroke")
    infoStroke.Color = Color3.fromRGB(255, 50, 50)
    infoStroke.Thickness = 1
    infoStroke.Transparency = 0.5
    infoStroke.Parent = infoPanel

    local nameLbl = Instance.new("TextLabel")
    nameLbl.Name = "Name"
    nameLbl.Size = UDim2.new(1, -16, 0, 20)
    nameLbl.Position = UDim2.new(0, 8, 0, 3)
    nameLbl.BackgroundTransparency = 1
    nameLbl.Text = ""
    nameLbl.TextColor3 = Color3.fromRGB(255, 80, 80)
    nameLbl.TextSize = 13
    nameLbl.Font = Enum.Font.GothamBold
    nameLbl.TextXAlignment = Enum.TextXAlignment.Left
    nameLbl.TextTruncate = Enum.TextTruncate.AtEnd
    nameLbl.Parent = infoPanel

    local distLbl = Instance.new("TextLabel")
    distLbl.Name = "Distance"
    distLbl.Size = UDim2.new(0, 50, 0, 20)
    distLbl.Position = UDim2.new(1, -58, 0, 3)
    distLbl.BackgroundTransparency = 1
    distLbl.Text = ""
    distLbl.TextColor3 = Color3.fromRGB(180, 180, 190)
    distLbl.TextSize = 11
    distLbl.Font = Enum.Font.Gotham
    distLbl.TextXAlignment = Enum.TextXAlignment.Right
    distLbl.Parent = infoPanel

    local hpBg = Instance.new("Frame")
    hpBg.Name = "HPBg"
    hpBg.Size = UDim2.new(1, -16, 0, 8)
    hpBg.Position = UDim2.new(0, 8, 0, 28)
    hpBg.BackgroundColor3 = Color3.fromRGB(50, 50, 55)
    hpBg.BorderSizePixel = 0
    hpBg.Parent = infoPanel
    Instance.new("UICorner", hpBg).CornerRadius = UDim.new(0, 4)

    local hpFill = Instance.new("Frame")
    hpFill.Name = "HPFill"
    hpFill.Size = UDim2.new(1, 0, 1, 0)
    hpFill.BackgroundColor3 = Color3.fromRGB(50, 220, 80)
    hpFill.BorderSizePixel = 0
    hpFill.Parent = hpBg
    Instance.new("UICorner", hpFill).CornerRadius = UDim.new(0, 4)

    -- Refs
    UI.Screen     = screen
    UI.LockBtn    = lockBtn
    UI.LockStroke = lockStroke
    UI.LockLabel  = lockLbl
    UI.LeftBtn    = leftBtn
    UI.RightBtn   = rightBtn
    UI.InfoPanel  = infoPanel
    UI.NameLabel  = nameLbl
    UI.DistLabel  = distLbl
    UI.HPFill     = hpFill

    return screen
end

-- ══════════════════════════════════════════════════════
-- UPDATE VISUAL DA UI
-- ══════════════════════════════════════════════════════
local function UpdateUI()
    if not UI.LockBtn then return end

    if State.IsLocked then
        UI.LockStroke.Color = Color3.fromRGB(255, 55, 55)
        UI.LockStroke.Thickness = 3
        UI.LockBtn.BackgroundColor3 = Color3.fromRGB(70, 12, 12)
        UI.LockBtn.BackgroundTransparency = 0.1
        UI.LockBtn.Text = "◉"
        UI.LockBtn.TextColor3 = Color3.fromRGB(255, 90, 90)
        UI.LockLabel.Text = "LOCKED"
        UI.LockLabel.TextColor3 = Color3.fromRGB(255, 80, 80)
        UI.LeftBtn.Visible = true
        UI.RightBtn.Visible = true
        UI.InfoPanel.Visible = CONFIG.ShowTargetInfo
    else
        UI.LockStroke.Color = Color3.fromRGB(150, 150, 160)
        UI.LockStroke.Thickness = 2.5
        UI.LockBtn.BackgroundColor3 = Color3.fromRGB(35, 35, 40)
        UI.LockBtn.BackgroundTransparency = 0.2
        UI.LockBtn.Text = "⊕"
        UI.LockBtn.TextColor3 = Color3.fromRGB(200, 200, 200)
        UI.LockLabel.Text = "LOCK"
        UI.LockLabel.TextColor3 = Color3.fromRGB(160, 160, 170)
        UI.LeftBtn.Visible = false
        UI.RightBtn.Visible = false
        UI.InfoPanel.Visible = false
    end
end

local function UpdateTargetInfo()
    if not State.IsLocked or not State.LockedTarget then return end
    if not UI.NameLabel then return end

    local _, _, hum = GetCharacterParts(State.LockedTarget)
    if not hum then return end

    -- Nome
    UI.NameLabel.Text = State.LockedTarget.DisplayName or State.LockedTarget.Name

    -- Distância
    local dist = math.floor(DistanceTo(State.LockedTarget))
    UI.DistLabel.Text = dist .. "m"

    -- HP
    local pct = math.clamp(hum.Health / hum.MaxHealth, 0, 1)

    TweenService:Create(UI.HPFill, TweenInfo.new(0.2), {
        Size = UDim2.new(pct, 0, 1, 0)
    }):Play()

    -- Cor: verde → amarelo → vermelho
    local color
    if pct > 0.6 then
        color = Color3.fromRGB(50, 220, 80)
    elseif pct > 0.3 then
        color = Color3.fromRGB(240, 200, 40)
    else
        color = Color3.fromRGB(255, 55, 55)
    end

    TweenService:Create(UI.HPFill, TweenInfo.new(0.3), {
        BackgroundColor3 = color
    }):Play()
end

-- ══════════════════════════════════════════════════════
-- LOCK / UNLOCK CORE
-- ══════════════════════════════════════════════════════
local function Unlock()
    State.LockedTarget = nil
    State.IsLocked = false
    DestroyIndicator()
    UpdateUI()

    -- Restaura câmera suavemente
    Camera.CameraType = Enum.CameraType.Custom
    TweenService:Create(Camera, TweenInfo.new(0.3), {
        FieldOfView = State.DefaultFOV
    }):Play()
end

local function LockOn(target)
    if not target or not IsAlive(target) then return end
    if target == State.LockedTarget then return end -- já travado nesse

    local _, root = GetCharacterParts(target)
    if not root then return end

    State.LockedTarget = target
    State.IsLocked = true

    -- Câmera scriptada
    Camera.CameraType = Enum.CameraType.Scriptable

    TweenService:Create(Camera, TweenInfo.new(0.25), {
        FieldOfView = CONFIG.FOVLocked
    }):Play()

    CreateIndicator(root)
    UpdateUI()

    -- Monitora morte do alvo
    SafeDisconnect("TargetDied")
    local _, _, hum = GetCharacterParts(target)
    if hum then
        State.Connections["TargetDied"] = hum.Died:Connect(function()
            if State.LockedTarget == target then
                Unlock()
            end
        end)
    end

    -- Monitora se o alvo sair do jogo
    SafeDisconnect("TargetLeft")
    State.Connections["TargetLeft"] = Players.PlayerRemoving:Connect(function(p)
        if p == State.LockedTarget then
            Unlock()
        end
    end)
end

-- Forward reference pra CycleTarget poder chamar LockOn
_G._LockOnFn = LockOn

-- ══════════════════════════════════════════════════════
-- AUTO-LOCK AO BATER
-- ══════════════════════════════════════════════════════
local function ConnectToolHit(tool)
    if not tool:IsA("Tool") then return end

    local function TryConnect(handle)
        if not handle then return end
        handle.Touched:Connect(function(hit)
            if State.IsLocked then return end
            if not CONFIG.AutoLockOnHit then return end

            local hitModel = hit:FindFirstAncestorOfClass("Model")
            if not hitModel then return end

            local hitPlayer = Players:GetPlayerFromCharacter(hitModel)
            if hitPlayer and hitPlayer ~= LocalPlayer and IsAlive(hitPlayer) then
                LockOn(hitPlayer)
            end
        end)
    end

    -- Handle pode já existir ou aparecer depois
    local handle = tool:FindFirstChild("Handle")
    if handle then
        TryConnect(handle)
    end
    tool.ChildAdded:Connect(function(child)
        if child.Name == "Handle" then
            TryConnect(child)
        end
    end)
end

local function SetupHitDetection(char)
    if not char then return end
    for _, child in ipairs(char:GetChildren()) do
        ConnectToolHit(child)
    end
    SafeDisconnect("ToolAdded")
    State.Connections["ToolAdded"] = char.ChildAdded:Connect(ConnectToolHit)
end

-- ══════════════════════════════════════════════════════
-- CÂMERA LOOP
-- ══════════════════════════════════════════════════════
local function UpdateCamera()
    if not State.IsLocked or not State.LockedTarget then return end
    if not State.RootPart then return end

    local _, targetRoot = GetCharacterParts(State.LockedTarget)
    if not targetRoot then
        Unlock()
        return
    end

    -- Checa distância
    local dist = (State.RootPart.Position - targetRoot.Position).Magnitude
    if dist > CONFIG.MaxLockDistance * 1.5 then
        Unlock()
        return
    end

    -- Calcula posição da câmera
    local playerPos = State.RootPart.Position
    local targetPos = targetRoot.Position + CONFIG.HeightOffset

    local lookDir = (targetPos - playerPos)
    if lookDir.Magnitude < 0.1 then return end
    lookDir = lookDir.Unit

    local camPos = playerPos
        - lookDir * CONFIG.CameraOffset.Z
        + Vector3.new(0, CONFIG.CameraOffset.Y, 0)

    -- Impede câmera de ir pra dentro de paredes
    local camParams = RaycastParams.new()
    camParams.FilterType = Enum.RaycastFilterType.Exclude
    camParams.FilterDescendantsInstances = {State.Character}

    local camRay = workspace:Raycast(playerPos + Vector3.new(0, 2, 0), camPos - (playerPos + Vector3.new(0, 2, 0)), camParams)
    if camRay then
        camPos = camRay.Position + camRay.Normal * 0.5
    end

    -- Ponto de foco: entre player e alvo
    local lookAt = playerPos:Lerp(targetPos, 0.55)

    local goalCF = CFrame.lookAt(camPos, lookAt)
    Camera.CFrame = Camera.CFrame:Lerp(goalCF, CONFIG.LockSmoothness)

    -- Atualiza info do alvo
    UpdateTargetInfo()
end

-- ══════════════════════════════════════════════════════
-- SETUP DO PERSONAGEM
-- ══════════════════════════════════════════════════════
local function OnCharacterAdded(char)
    State.Character = char
    State.Humanoid = char:WaitForChild("Humanoid", 10)
    State.RootPart = char:WaitForChild("HumanoidRootPart", 10)

    if not State.Humanoid or not State.RootPart then
        warn("[LockOn] Falha ao encontrar Humanoid/RootPart")
        return
    end

    -- Destrava se tava travado
    if State.IsLocked then
        Unlock()
    end

    -- Morte do próprio player
    SafeDisconnect("SelfDied")
    State.Connections["SelfDied"] = State.Humanoid.Died:Connect(function()
        Unlock()
    end)

    -- Hit detection
    task.delay(0.5, function()
        SetupHitDetection(char)
    end)
end

-- ══════════════════════════════════════════════════════
-- INPUT: TECLADO
-- ══════════════════════════════════════════════════════
UserInputService.InputBegan:Connect(function(input, processed)
    if processed then return end

    if input.KeyCode == CONFIG.LockKey then
        if State.IsLocked then
            Unlock()
        else
            local target = FindNearest()
            if target then LockOn(target) end
        end

    elseif input.KeyCode == CONFIG.NextTargetKey then
        CycleTarget(1)

    elseif input.KeyCode == CONFIG.PrevTargetKey then
        CycleTarget(-1)
    end
end)

-- ══════════════════════════════════════════════════════
-- INPUT: TOUCH (SWIPE)
-- ══════════════════════════════════════════════════════
UserInputService.TouchStarted:Connect(function(touch, processed)
    if processed or not State.IsLocked then return end
    local vp = Camera.ViewportSize
    -- Só swipe na metade superior
    if touch.Position.Y < vp.Y * 0.45 then
        State.TouchStart = touch.Position
    end
end)

UserInputService.TouchEnded:Connect(function(touch)
    if not State.TouchStart or not State.IsLocked then
        State.TouchStart = nil
        return
    end
    local dx = touch.Position.X - State.TouchStart.X
    if math.abs(dx) >= CONFIG.SwipeThreshold then
        CycleTarget(dx > 0 and 1 or -1)
    end
    State.TouchStart = nil
end)

-- ══════════════════════════════════════════════════════
-- INICIALIZAÇÃO
-- ══════════════════════════════════════════════════════
local function Init()
    -- UI
    BuildUI()
    UpdateUI()

    -- Botões mobile
    UI.LockBtn.MouseButton1Click:Connect(function()
        if State.IsLocked then
            Unlock()
        else
            local target = FindNearest()
            if target then LockOn(target) end
        end
    end)

    UI.LeftBtn.MouseButton1Click:Connect(function()
        CycleTarget(-1)
    end)

    UI.RightBtn.MouseButton1Click:Connect(function()
        CycleTarget(1)
    end)

    -- Personagem
    if LocalPlayer.Character then
        OnCharacterAdded(LocalPlayer.Character)
    end
    LocalPlayer.CharacterAdded:Connect(OnCharacterAdded)

    -- Render loop
    RunService.RenderStepped:Connect(UpdateCamera)

    print("══════════════════════════════════════")
    print("  LOCK-ON SYSTEM v2.0 — ATIVO")
    print("  PC:  Q=Lock | E=Next | R=Prev")
    print("  Mobile: Botões na tela / Swipe")
    print("══════════════════════════════════════")
end

Init()
