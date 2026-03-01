--[[
    ╔══════════════════════════════════════════════════════════╗
    ║        LOCK-ON TARGET SYSTEM v4.0 — CONSOLE GRADE        ║
    ║        Predictive • Aim Friction • Orbital • Threat AI   ║
    ║        Mobile + PC + Gamepad | Framerate Independent      ║
    ╚══════════════════════════════════════════════════════════════╝
    
    LocalScript → StarterPlayerScripts
    
    CONTROLES:
      PC:      Q = Lock/Unlock  |  E = Próximo  |  R = Anterior
               Mouse move = orbital adjust (quando locked)
      Mobile:  Botão arrastável |  ◀ ▶ Trocar alvo  |  Swipe
      Gamepad: RB = Lock  |  Right Stick = Orbital  |  RS Click = Cycle
    
    v4 CHANGELOG:
      ✦ FIX: Lerp framerate-independent (exponential decay)
      ✦ FIX: Prediction alpha clamped corretamente
      ✦ FIX: TargetCharRemoved memory leak
      ✦ FIX: ClearSight filtra TODOS characters
      ✦ NEW: Target validation timer (2.5s behind wall before unlock)
      ✦ NEW: Aim friction / sticky aim (sem lock)
      ✦ NEW: FOV dinâmico por distância
      ✦ NEW: Sphere cast (4 raycasts offset) anti-wall
      ✦ NEW: Câmera orbital real com mouse/stick
      ✦ NEW: Feedback visual de troca (fade + pulse)
      ✦ NEW: Threat scoring (attacking > low hp > approaching)
      ✦ NEW: Swipe timeout (300ms max)
      ✦ NEW: Cached target parts (1 lookup per frame)
--]]

-- ══════════════════════════════════════════════════════
-- SERVICES
-- ══════════════════════════════════════════════════════
local Players            = game:GetService("Players")
local RunService         = game:GetService("RunService")
local UserInputService   = game:GetService("UserInputService")
local TweenService       = game:GetService("TweenService")

local Camera       = workspace.CurrentCamera
local LocalPlayer  = Players.LocalPlayer
local PlayerGui    = LocalPlayer:WaitForChild("PlayerGui")

-- ══════════════════════════════════════════════════════
-- CONFIG
-- ══════════════════════════════════════════════════════
local CONFIG = {
    -- ▸ Targeting
    MaxLockDistance       = 150,
    AutoLockOnHit        = true,
    AutoSwitchOnKill     = true,

    -- ▸ Target scoring weights
    PreferFrontTargets   = true,
    FrontWeight          = 0.5,         -- bonus pra quem tá na frente
    ThreatWeight         = 0.3,         -- bonus pra quem tá te atacando/vindo
    LowHPWeight          = 0.15,        -- bonus pra quem tá com pouca vida
    ApproachWeight       = 0.25,        -- bonus pra quem tá vindo na sua direção

    -- ▸ Wall validation
    WallLossTimeout      = 2.5,         -- segundos atrás de parede antes de unlock
    WallCheckInterval    = 0.15,        -- intervalo entre checks de parede

    -- ▸ Câmera (framerate independent)
    CamSmoothRate        = 12,          -- taxa de suavização (units/sec, exponential)
    PredictionRate       = 8,           -- taxa de suavização da predição
    VelocitySmoothRate   = 5,           -- taxa de suavização da velocidade
    PredictionStrength   = 0.4,         -- quanto antecipar o movimento
    AimLeadFactor        = 0.22,        -- mira à frente do alvo

    -- ▸ Câmera orbital
    CameraDistance       = 14,
    CameraHeight         = 4.5,
    LookAtBias           = 0.6,         -- 0=player, 1=alvo
    OrbitalEnabled       = true,
    OrbitalSpeed         = 0.003,       -- sensibilidade mouse/stick
    OrbitalMaxAngle      = math.rad(50),-- máximo desvio lateral
    OrbitalDecayRate     = 3,           -- volta pro centro (units/sec)

    -- ▸ FOV dinâmico
    FOVClose             = 62,          -- FOV quando alvo perto
    FOVFar               = 48,          -- FOV quando alvo longe
    FOVCloseDistance      = 15,         -- distância "perto"
    FOVFarDistance        = 80,         -- distância "longe"
    FOVSmoothRate        = 6,
    FOVTransitionTime    = 0.35,        -- tempo de transição ao lock/unlock

    -- ▸ Aim friction (sem lock ativo)
    AimFrictionEnabled   = true,
    AimFrictionRadius    = 60,          -- pixels do centro da tela
    AimFrictionStrength  = 0.45,        -- 0=sem efeito, 1=para totalmente
    AimFrictionRange     = 80,          -- studs máximo pro friction funcionar

    -- ▸ Visual
    IndicatorEnabled     = true,
    ShowTargetInfo       = true,
    SwitchFeedback       = true,        -- flash ao trocar alvo
    TargetInfoOffset     = UDim2.new(0.5, 0, 0, 55),

    -- ▸ Teclas
    LockKey              = Enum.KeyCode.Q,
    NextTargetKey        = Enum.KeyCode.E,
    PrevTargetKey        = Enum.KeyCode.R,
    GamepadLock          = Enum.KeyCode.ButtonR1,
    GamepadNext          = Enum.KeyCode.ButtonR3,

    -- ▸ Mobile
    ButtonSize           = 62,
    DefaultButtonPos     = UDim2.new(1, -85, 0.35, 0),
    SwipeThreshold       = 55,
    SwipeTimeout         = 0.3,         -- segundos máximo pra swipe contar
    DragThreshold        = 8,
}

-- ══════════════════════════════════════════════════════
-- STATE
-- ══════════════════════════════════════════════════════
local State = {
    Target          = nil,           -- Player ou Model
    IsLocked        = false,
    Char            = nil,
    Hum             = nil,
    Root            = nil,
    DefaultFOV      = Camera.FieldOfView,
    CurrentFOV      = Camera.FieldOfView,
    Conns           = {},
    Indicator       = nil,

    -- Cache (atualizado 1x por frame)
    CachedTargetRoot = nil,
    CachedTargetHum  = nil,
    CachedTargetChar = nil,

    -- Predição (framerate independent)
    TargetVelocity      = Vector3.zero,
    SmoothedPrediction  = Vector3.zero,
    LastTargetPos       = nil,
    LastPredictionTime  = 0,

    -- Wall validation
    WallLossTimer       = 0,
    HasLineOfSight      = true,
    LastWallCheck       = 0,

    -- Câmera orbital
    OrbitalOffset       = 0,           -- ângulo lateral em radianos

    -- Mobile
    TouchStart      = nil,
    TouchStartTime  = 0,
    ButtonDragging  = false,
    SavedButtonPos  = nil,

    -- Aim friction
    LastCameraInput = Vector2.zero,

    -- Threat tracking: quem bateu no player recentemente
    RecentAttackers = {},   -- {[Player/Model] = timestamp}
}

-- ══════════════════════════════════════════════════════
-- MATH HELPERS
-- ══════════════════════════════════════════════════════

-- Exponential decay lerp: framerate independent
-- Retorna alpha pra usar em :Lerp()
-- rate = velocidade (maior = mais rápido), dt = delta time
local function ExpDecay(rate, dt)
    return 1 - math.exp(-rate * dt)
end

-- Clamp lerp alpha pra segurança
local function SafeLerp(a, b, alpha)
    alpha = math.clamp(alpha, 0, 1)
    if typeof(a) == "Vector3" then
        return a:Lerp(b, alpha)
    elseif typeof(a) == "CFrame" then
        return a:Lerp(b, alpha)
    elseif typeof(a) == "number" then
        return a + (b - a) * alpha
    end
    return b
end

-- ══════════════════════════════════════════════════════
-- CONNECTION MANAGER (zero leaks)
-- ══════════════════════════════════════════════════════
local function Conn(key, connection)
    if State.Conns[key] and typeof(State.Conns[key]) == "RBXScriptConnection" then
        State.Conns[key]:Disconnect()
    end
    State.Conns[key] = connection
end

local function Disconn(key)
    if State.Conns[key] then
        if typeof(State.Conns[key]) == "RBXScriptConnection" then
            State.Conns[key]:Disconnect()
        end
        State.Conns[key] = nil
    end
end

local function DisconnGroup(prefix)
    local toRemove = {}
    for k, v in pairs(State.Conns) do
        if type(k) == "string" and k:sub(1, #prefix) == prefix then
            if typeof(v) == "RBXScriptConnection" then
                v:Disconnect()
            end
            table.insert(toRemove, k)
        end
    end
    for _, k in ipairs(toRemove) do
        State.Conns[k] = nil
    end
end

-- ══════════════════════════════════════════════════════
-- TARGET PARTS — cached per frame
-- ══════════════════════════════════════════════════════

-- Pega parts de um Player
local function GetParts(target)
    if not target then return nil, nil, nil end
    if typeof(target) == "Instance" and target:IsA("Player") then
        local c = target.Character
        if not c then return nil, nil, nil end
        return c, c:FindFirstChild("HumanoidRootPart"), c:FindFirstChildOfClass("Humanoid")
    end
    return nil, nil, nil
end

-- Atualiza cache 1x por frame
local function RefreshTargetCache()
    if not State.Target then
        State.CachedTargetChar = nil
        State.CachedTargetRoot = nil
        State.CachedTargetHum = nil
        return
    end
    State.CachedTargetChar, State.CachedTargetRoot, State.CachedTargetHum = GetParts(State.Target)
end

local function Alive(target)
    local _, _, h = GetParts(target)
    return h ~= nil and h.Health > 0
end

local function Dist(target)
    if not State.Root then return math.huge end
    local _, r = GetParts(target)
    if not r then return math.huge end
    return (State.Root.Position - r.Position).Magnitude
end

-- ══════════════════════════════════════════════════════
-- RAYCAST — filtra TODOS characters do workspace
-- ══════════════════════════════════════════════════════
local FrameCache = {
    Characters = nil,
    FrameCount = -1,
}
local _frameCounter = 0

local function GetAllCharactersCached()
    if FrameCache.FrameCount == _frameCounter then
        return FrameCache.Characters
    end
    local chars = {}
    for _, p in ipairs(Players:GetPlayers()) do
        if p.Character then
            chars[#chars + 1] = p.Character
        end
    end
    FrameCache.Characters = chars
    FrameCache.FrameCount = _frameCounter
    return chars
end

local function ClearSight(fromPos, toPos, extraIgnore)
    local dir = toPos - fromPos
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.RespectCanCollide = true

    local filter = GetAllCharactersCached()
    if extraIgnore then
        -- Copia pra não poluir o cache
        local merged = table.clone(filter)
        for _, v in ipairs(extraIgnore) do
            merged[#merged + 1] = v
        end
        params.FilterDescendantsInstances = merged
    else
        params.FilterDescendantsInstances = filter
    end

    local hit = workspace:Raycast(fromPos, dir, params)
    return hit == nil
end

-- Sphere cast simulado: 4 raycasts com offset
local function SphereCast(origin, target, radius, ignoreList)
    local dir = target - origin
    if dir.Magnitude < 0.1 then return true end

    local forward = dir.Unit
    local right = forward:Cross(Vector3.new(0, 1, 0))
    if right.Magnitude < 0.01 then
        right = forward:Cross(Vector3.new(1, 0, 0))
    end
    right = right.Unit
    local up = right:Cross(forward).Unit

    local offsets = {
        Vector3.zero,               -- centro
        right * radius,             -- direita
        -right * radius,            -- esquerda
        up * radius,                -- cima
    }

    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = ignoreList or {}
    params.RespectCanCollide = true

    local bestHit = nil
    local bestDist = math.huge

    for _, offset in ipairs(offsets) do
        local from = origin + offset
        local to = target + offset
        local result = workspace:Raycast(from, to - from, params)
        if result then
            local d = (result.Position - from).Magnitude
            if d < bestDist then
                bestDist = d
                bestHit = result
            end
        end
    end

    return bestHit -- nil = clear, hit = blocked
end

-- ══════════════════════════════════════════════════════
-- THREAT SCORING — prioriza alvos inteligentemente
-- ══════════════════════════════════════════════════════

-- Registra quem atacou o player (chamado pelo hit detection)
local function RegisterAttacker(attacker)
    State.RecentAttackers[attacker] = tick()
end

-- Limpa atacantes antigos (>5s)
local function CleanAttackers()
    local now = tick()
    local toRemove = {}
    for k, t in pairs(State.RecentAttackers) do
        if now - t > 5 then
            table.insert(toRemove, k)
        end
    end
    for _, k in ipairs(toRemove) do
        State.RecentAttackers[k] = nil
    end
end

local function ScoreTarget(target)
    local _, root, hum = GetParts(target)
    if not root or not hum or not State.Root then return math.huge end
    if hum.Health <= 0 then return math.huge end

    local dist = (State.Root.Position - root.Position).Magnitude
    if dist > CONFIG.MaxLockDistance then return math.huge end

    -- PRÉ-FILTRO: Skip raycast se alvo está muito atrás da câmera
    local camLook = Camera.CFrame.LookVector
    local toTarget = (root.Position - State.Root.Position)
    local dot = 0
    if toTarget.Magnitude > 0.1 then
        dot = camLook:Dot(toTarget.Unit)
        if dot < -0.3 then return math.huge end  -- Atrás demais, nem testa LOS
    end

    -- SÓ ENTÃO faz o raycast (caro)
    local origin = State.Root.Position + Vector3.new(0, 1.5, 0)
    local targetPos = root.Position + Vector3.new(0, 1.5, 0)

    if not ClearSight(origin, targetPos) then
        return math.huge
    end

    -- Score base = distância normalizada (0-1)
    local normDist = dist / CONFIG.MaxLockDistance
    local score = normDist

    -- FRONT BONUS: alvos na frente da câmera (reutiliza dot já calculado)
    if CONFIG.PreferFrontTargets and toTarget.Magnitude > 0.1 then
        local frontPenalty = (1 - dot) * 0.5 * CONFIG.FrontWeight
        score = score + frontPenalty
    end

    -- THREAT BONUS: quem atacou recentemente
    local attackTime = State.RecentAttackers[target]
    if attackTime then
        local recency = math.clamp(1 - (tick() - attackTime) / 5, 0, 1)
        score = score - recency * CONFIG.ThreatWeight
    end

    -- LOW HP BONUS: prioriza quem tá quase morrendo
    local hpPct = hum.Health / hum.MaxHealth
    if hpPct < 0.4 then
        score = score - (1 - hpPct) * CONFIG.LowHPWeight
    end

    -- APPROACH BONUS: quem tá vindo na sua direção
    local rootVel = root.AssemblyLinearVelocity
    if rootVel and rootVel.Magnitude > 1 then
        local toPlayer = (State.Root.Position - root.Position)
        if toPlayer.Magnitude > 0.1 then
            local approachDot = rootVel.Unit:Dot(toPlayer.Unit)
            if approachDot > 0.3 then
                score = score - approachDot * CONFIG.ApproachWeight
            end
        end
    end

    return score
end

local function GetScoredTargets()
    CleanAttackers()

    local targets = {}

    -- Players
    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= LocalPlayer and Alive(player) then
            local s = ScoreTarget(player)
            if s < math.huge then
                table.insert(targets, {Target = player, Score = s, Distance = Dist(player)})
            end
        end
    end

    table.sort(targets, function(a, b) return a.Score < b.Score end)
    return targets
end

local function FindBestTarget()
    local t = GetScoredTargets()
    return t[1] and t[1].Target or nil
end

-- ══════════════════════════════════════════════════════
-- VELOCITY PREDICTION — framerate independent
-- ══════════════════════════════════════════════════════
local function UpdatePrediction(dt)
    if not State.CachedTargetRoot then
        State.TargetVelocity = Vector3.zero
        State.SmoothedPrediction = Vector3.zero
        State.LastTargetPos = nil
        return
    end

    local currentPos = State.CachedTargetRoot.Position
    local now = tick()

    if State.LastTargetPos then
        local timeDelta = now - State.LastPredictionTime
        if timeDelta > 0.001 then
            -- Velocidade instantânea
            local instantVel = (currentPos - State.LastTargetPos) / timeDelta

            -- Suaviza velocidade com exponential decay
            local velAlpha = ExpDecay(CONFIG.VelocitySmoothRate, dt)
            State.TargetVelocity = SafeLerp(State.TargetVelocity, instantVel, velAlpha)

            -- Posição predita
            local predicted = currentPos + State.TargetVelocity * CONFIG.PredictionStrength

            -- Suaviza predição com exponential decay
            local predAlpha = ExpDecay(CONFIG.PredictionRate, dt)
            State.SmoothedPrediction = SafeLerp(State.SmoothedPrediction, predicted, predAlpha)
        end
    else
        State.SmoothedPrediction = currentPos
    end

    State.LastTargetPos = currentPos
    State.LastPredictionTime = now
end

local function GetPredictedTargetPos()
    if not State.CachedTargetRoot then return Vector3.zero end

    local basePos = State.CachedTargetRoot.Position + Vector3.new(0, 2, 0)

    if State.SmoothedPrediction.Magnitude > 0 then
        local predicted = State.SmoothedPrediction + Vector3.new(0, 2, 0)
        return basePos:Lerp(predicted, CONFIG.AimLeadFactor)
    end

    return basePos
end

-- ══════════════════════════════════════════════════════
-- WALL VALIDATION — timer antes de unlock
-- ══════════════════════════════════════════════════════
local function UpdateWallValidation(dt)
    if not State.IsLocked or not State.CachedTargetRoot or not State.Root then
        State.WallLossTimer = 0
        State.HasLineOfSight = true
        return
    end

    local now = tick()
    if now - State.LastWallCheck < CONFIG.WallCheckInterval then return end
    local elapsed = now - State.LastWallCheck  -- tempo REAL desde último check
    State.LastWallCheck = now

    local origin = State.Root.Position + Vector3.new(0, 1.5, 0)
    local target = State.CachedTargetRoot.Position + Vector3.new(0, 1.5, 0)

    local hasLOS = ClearSight(origin, target)

    if hasLOS then
        State.WallLossTimer = 0
        State.HasLineOfSight = true
    else
        State.HasLineOfSight = false
        State.WallLossTimer = State.WallLossTimer + elapsed

        if State.WallLossTimer >= CONFIG.WallLossTimeout then
            if CONFIG.AutoSwitchOnKill then
                local next = FindBestTarget()
                if next and next ~= State.Target then
                    LockOn(next)
                else
                    Unlock()
                end
            else
                Unlock()
            end
        end
    end
end

-- ══════════════════════════════════════════════════════
-- 3D INDICATOR
-- ══════════════════════════════════════════════════════
local function DestroyIndicator()
    if State.Indicator then
        pcall(function() State.Indicator:Destroy() end)
        State.Indicator = nil
    end
end

local function CreateIndicator(targetRoot, fadeIn)
    DestroyIndicator()
    if not CONFIG.IndicatorEnabled or not targetRoot then return end

    local bb = Instance.new("BillboardGui")
    bb.Name = "LockIndicator"
    bb.Size = UDim2.new(3, 0, 3, 0)
    bb.AlwaysOnTop = true
    bb.LightInfluence = 0
    bb.StudsOffset = Vector3.new(0, 0.5, 0)
    bb.MaxDistance = CONFIG.MaxLockDistance * 2

    local holder = Instance.new("Frame")
    holder.Size = UDim2.new(1, 0, 1, 0)
    holder.BackgroundTransparency = 1
    holder.Parent = bb

    -- Ring
    local ring = Instance.new("Frame")
    ring.Name = "Ring"
    ring.AnchorPoint = Vector2.new(0.5, 0.5)
    ring.Position = UDim2.new(0.5, 0, 0.5, 0)
    ring.Size = UDim2.new(0.5, 0, 0.5, 0)
    ring.BackgroundColor3 = Color3.fromRGB(255, 35, 35)
    ring.BackgroundTransparency = 0.15
    ring.BorderSizePixel = 0
    ring.Parent = holder
    Instance.new("UICorner", ring).CornerRadius = UDim.new(1, 0)

    local hole = Instance.new("Frame")
    hole.AnchorPoint = Vector2.new(0.5, 0.5)
    hole.Position = UDim2.new(0.5, 0, 0.5, 0)
    hole.Size = UDim2.new(0.6, 0, 0.6, 0)
    hole.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
    hole.BackgroundTransparency = 0.82
    hole.BorderSizePixel = 0
    hole.Parent = ring
    Instance.new("UICorner", hole).CornerRadius = UDim.new(1, 0)

    -- Dot
    local dot = Instance.new("Frame")
    dot.Name = "Dot"
    dot.AnchorPoint = Vector2.new(0.5, 0.5)
    dot.Position = UDim2.new(0.5, 0, 0.5, 0)
    dot.Size = UDim2.new(0.08, 0, 0.08, 0)
    dot.BackgroundColor3 = Color3.fromRGB(255, 80, 80)
    dot.BorderSizePixel = 0
    dot.Parent = holder
    Instance.new("UICorner", dot).CornerRadius = UDim.new(1, 0)

    -- 4 setas
    local arrowHolder = Instance.new("Frame")
    arrowHolder.Name = "Arrows"
    arrowHolder.AnchorPoint = Vector2.new(0.5, 0.5)
    arrowHolder.Position = UDim2.new(0.5, 0, 0.5, 0)
    arrowHolder.Size = UDim2.new(0.85, 0, 0.85, 0)
    arrowHolder.BackgroundTransparency = 1
    arrowHolder.Parent = holder

    local arrowData = {
        {pos = UDim2.new(0.5, 0, 0, 0),  rot = 0},
        {pos = UDim2.new(1, 0, 0.5, 0),  rot = 90},
        {pos = UDim2.new(0.5, 0, 1, 0),  rot = 180},
        {pos = UDim2.new(0, 0, 0.5, 0),  rot = 270},
    }

    for _, d in ipairs(arrowData) do
        local arrow = Instance.new("Frame")
        arrow.AnchorPoint = Vector2.new(0.5, 0)
        arrow.Position = d.pos
        arrow.Size = UDim2.new(0.04, 0, 0.15, 0)
        arrow.Rotation = d.rot
        arrow.BackgroundColor3 = Color3.fromRGB(255, 100, 100)
        arrow.BackgroundTransparency = 0.2
        arrow.BorderSizePixel = 0
        arrow.Parent = arrowHolder
        Instance.new("UICorner", arrow).CornerRadius = UDim.new(0, 2)
    end

    -- Dead flag: para os loops quando indicator é destruído
    bb:GetPropertyChangedSignal("Parent"):Connect(function()
        if not bb.Parent then
            bb:SetAttribute("_dead", true)
        end
    end)

    -- Pulse animation
    task.spawn(function()
        local expanding = false
        while not bb:GetAttribute("_dead") do
            local sizeA = expanding and UDim2.new(0.95, 0, 0.95, 0) or UDim2.new(0.72, 0, 0.72, 0)
            local sizeD = expanding and UDim2.new(0.1, 0, 0.1, 0) or UDim2.new(0.06, 0, 0.06, 0)
            local ok = pcall(function()
                TweenService:Create(arrowHolder, TweenInfo.new(0.65, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), {Size = sizeA}):Play()
                TweenService:Create(dot, TweenInfo.new(0.65, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), {Size = sizeD}):Play()
            end)
            if not ok then break end
            expanding = not expanding
            task.wait(0.65)
        end
    end)

    -- LOS indicator: escurece quando atrás de parede
    task.spawn(function()
        while not bb:GetAttribute("_dead") do
            local transparency = State.HasLineOfSight and 0.15 or 0.55
            pcall(function()
                TweenService:Create(ring, TweenInfo.new(0.3), {BackgroundTransparency = transparency}):Play()
            end)
            task.wait(0.2)
        end
    end)

    -- Fade-in na troca
    if fadeIn then
        ring.Size = UDim2.new(0.9, 0, 0.9, 0)
        ring.BackgroundTransparency = 0.9
        pcall(function()
            TweenService:Create(ring, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
                Size = UDim2.new(0.5, 0, 0.5, 0),
                BackgroundTransparency = 0.15,
            }):Play()
        end)
    end

    bb.Adornee = targetRoot
    bb.Parent = targetRoot
    State.Indicator = bb
end

-- Flash feedback ao trocar alvo
local function FlashSwitchFeedback()
    if not CONFIG.SwitchFeedback or not State.Indicator then return end

    for _, child in ipairs(State.Indicator:GetDescendants()) do
        if child.Name == "Ring" and child:IsA("Frame") then
            pcall(function()
                child.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
                TweenService:Create(child, TweenInfo.new(0.3), {
                    BackgroundColor3 = Color3.fromRGB(255, 35, 35)
                }):Play()
            end)
            break
        end
    end
end

-- ══════════════════════════════════════════════════════
-- UI MOBILE
-- ══════════════════════════════════════════════════════
local UI = {}

local function BuildUI()
    local old = PlayerGui:FindFirstChild("LockOnUI_v4")
    if old then old:Destroy() end

    local screen = Instance.new("ScreenGui")
    screen.Name = "LockOnUI_v4"
    screen.ResetOnSpawn = false
    screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    screen.DisplayOrder = 10
    screen.Parent = PlayerGui

    -- ═══ DRAGGABLE BUTTON CONTAINER ═══
    local btnFrame = Instance.new("Frame")
    btnFrame.Name = "DragContainer"
    btnFrame.Size = UDim2.new(0, CONFIG.ButtonSize + 10, 0, CONFIG.ButtonSize + 70)
    btnFrame.Position = State.SavedButtonPos or CONFIG.DefaultButtonPos
    btnFrame.BackgroundTransparency = 1
    btnFrame.Active = true
    btnFrame.Parent = screen

    local lockBtn = Instance.new("TextButton")
    lockBtn.Name = "LockBtn"
    lockBtn.AnchorPoint = Vector2.new(0.5, 0)
    lockBtn.Position = UDim2.new(0.5, 0, 0, 0)
    lockBtn.Size = UDim2.new(0, CONFIG.ButtonSize, 0, CONFIG.ButtonSize)
    lockBtn.BackgroundColor3 = Color3.fromRGB(30, 30, 35)
    lockBtn.BackgroundTransparency = 0.15
    lockBtn.BorderSizePixel = 0
    lockBtn.Text = "⊕"
    lockBtn.TextColor3 = Color3.fromRGB(190, 190, 200)
    lockBtn.TextScaled = true
    lockBtn.Font = Enum.Font.GothamBold
    lockBtn.AutoButtonColor = false
    lockBtn.Parent = btnFrame
    Instance.new("UICorner", lockBtn).CornerRadius = UDim.new(1, 0)

    local btnStroke = Instance.new("UIStroke")
    btnStroke.Color = Color3.fromRGB(130, 130, 145)
    btnStroke.Thickness = 2
    btnStroke.Parent = lockBtn

    local btnGlow = Instance.new("UIStroke")
    btnGlow.Name = "Glow"
    btnGlow.Color = Color3.fromRGB(255, 50, 50)
    btnGlow.Thickness = 0
    btnGlow.Transparency = 0.6
    btnGlow.Parent = lockBtn

    local lockLbl = Instance.new("TextLabel")
    lockLbl.Name = "Label"
    lockLbl.AnchorPoint = Vector2.new(0.5, 0)
    lockLbl.Position = UDim2.new(0.5, 0, 1, 3)
    lockLbl.Size = UDim2.new(0, 70, 0, 14)
    lockLbl.BackgroundTransparency = 1
    lockLbl.Text = "LOCK"
    lockLbl.TextColor3 = Color3.fromRGB(140, 140, 150)
    lockLbl.TextSize = 10
    lockLbl.Font = Enum.Font.GothamBold
    lockLbl.Parent = lockBtn

    -- ═══ DRAG LOGIC ═══
    local dragging = false
    local dragStart = nil
    local startPos = nil
    local totalDist = 0

    -- Usamos InputBegan/Changed/Ended no próprio frame
    lockBtn.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.Touch
            or input.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging = true
            dragStart = input.Position
            startPos = btnFrame.Position
            totalDist = 0
            State.ButtonDragging = false
        end
    end)

    UserInputService.InputChanged:Connect(function(input)
        if not dragging then return end
        if input.UserInputType ~= Enum.UserInputType.Touch
            and input.UserInputType ~= Enum.UserInputType.MouseMovement then return end

        local delta = input.Position - dragStart
        totalDist = math.max(totalDist, delta.Magnitude)

        if totalDist > CONFIG.DragThreshold then
            State.ButtonDragging = true
            btnFrame.Position = UDim2.new(
                startPos.X.Scale,
                startPos.X.Offset + (input.Position.X - dragStart.X),
                startPos.Y.Scale,
                startPos.Y.Offset + (input.Position.Y - dragStart.Y)
            )
        end
    end)

    UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.Touch
            or input.UserInputType == Enum.UserInputType.MouseButton1 then
            if dragging then
                dragging = false
                if State.ButtonDragging then
                    State.SavedButtonPos = btnFrame.Position
                end
                -- Delay pra não triggar click junto
                task.delay(0.05, function()
                    State.ButtonDragging = false
                end)
            end
        end
    end)

    -- ═══ SWITCH BUTTONS ═══
    local switchCont = Instance.new("Frame")
    switchCont.Name = "Switch"
    switchCont.AnchorPoint = Vector2.new(0.5, 0)
    switchCont.Position = UDim2.new(0.5, 0, 1, 22)
    switchCont.Size = UDim2.new(0, 120, 0, 36)
    switchCont.BackgroundTransparency = 1
    switchCont.Visible = false
    switchCont.Parent = btnFrame

    local function MakeSwitchBtn(name, text, posX)
        local btn = Instance.new("TextButton")
        btn.Name = name
        btn.Size = UDim2.new(0, 48, 0, 36)
        btn.Position = UDim2.new(posX, 0, 0, 0)
        btn.BackgroundColor3 = Color3.fromRGB(30, 30, 35)
        btn.BackgroundTransparency = 0.3
        btn.BorderSizePixel = 0
        btn.Text = text
        btn.TextColor3 = Color3.fromRGB(180, 180, 190)
        btn.TextSize = 16
        btn.Font = Enum.Font.GothamBold
        btn.AutoButtonColor = false
        btn.Parent = switchCont
        Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 8)
        return btn
    end

    local leftBtn = MakeSwitchBtn("Left", "◀", 0)
    local rightBtn = MakeSwitchBtn("Right", "▶", UDim.new(1, -48))
    rightBtn.Position = UDim2.new(1, -48, 0, 0)

    -- ═══ TARGET INFO ═══
    local infoPanel = Instance.new("Frame")
    infoPanel.Name = "TargetInfo"
    infoPanel.AnchorPoint = Vector2.new(0.5, 0)
    infoPanel.Position = CONFIG.TargetInfoOffset
    infoPanel.Size = UDim2.new(0, 240, 0, 52)
    infoPanel.BackgroundColor3 = Color3.fromRGB(10, 10, 15)
    infoPanel.BackgroundTransparency = 0.3
    infoPanel.BorderSizePixel = 0
    infoPanel.Visible = false
    infoPanel.Parent = screen
    Instance.new("UICorner", infoPanel).CornerRadius = UDim.new(0, 10)

    local infoBorder = Instance.new("UIStroke")
    infoBorder.Color = Color3.fromRGB(255, 40, 40)
    infoBorder.Thickness = 1.5
    infoBorder.Transparency = 0.4
    infoBorder.Parent = infoPanel

    local miniIcon = Instance.new("TextLabel")
    miniIcon.Size = UDim2.new(0, 18, 0, 18)
    miniIcon.Position = UDim2.new(0, 8, 0, 5)
    miniIcon.BackgroundTransparency = 1
    miniIcon.Text = "◉"
    miniIcon.TextColor3 = Color3.fromRGB(255, 60, 60)
    miniIcon.TextSize = 14
    miniIcon.Font = Enum.Font.GothamBold
    miniIcon.Parent = infoPanel

    -- LOS indicator dot (verde=visível, amarelo=parede)
    local losDot = Instance.new("Frame")
    losDot.Name = "LOSDot"
    losDot.Size = UDim2.new(0, 6, 0, 6)
    losDot.Position = UDim2.new(0, 10, 0, 23)
    losDot.BackgroundColor3 = Color3.fromRGB(40, 220, 80)
    losDot.BorderSizePixel = 0
    losDot.Parent = infoPanel
    Instance.new("UICorner", losDot).CornerRadius = UDim.new(1, 0)

    local nameLbl = Instance.new("TextLabel")
    nameLbl.Name = "Name"
    nameLbl.Size = UDim2.new(1, -80, 0, 20)
    nameLbl.Position = UDim2.new(0, 28, 0, 4)
    nameLbl.BackgroundTransparency = 1
    nameLbl.Text = ""
    nameLbl.TextColor3 = Color3.fromRGB(255, 255, 255)
    nameLbl.TextSize = 13
    nameLbl.Font = Enum.Font.GothamBold
    nameLbl.TextXAlignment = Enum.TextXAlignment.Left
    nameLbl.TextTruncate = Enum.TextTruncate.AtEnd
    nameLbl.Parent = infoPanel

    local distLbl = Instance.new("TextLabel")
    distLbl.Name = "Dist"
    distLbl.Size = UDim2.new(0, 55, 0, 20)
    distLbl.Position = UDim2.new(1, -60, 0, 4)
    distLbl.BackgroundTransparency = 1
    distLbl.Text = ""
    distLbl.TextColor3 = Color3.fromRGB(170, 170, 180)
    distLbl.TextSize = 11
    distLbl.Font = Enum.Font.Gotham
    distLbl.TextXAlignment = Enum.TextXAlignment.Right
    distLbl.Parent = infoPanel

    local hpBg = Instance.new("Frame")
    hpBg.Size = UDim2.new(1, -20, 0, 8)
    hpBg.Position = UDim2.new(0, 10, 1, -16)
    hpBg.BackgroundColor3 = Color3.fromRGB(45, 45, 50)
    hpBg.BorderSizePixel = 0
    hpBg.Parent = infoPanel
    Instance.new("UICorner", hpBg).CornerRadius = UDim.new(0, 4)

    local hpGhost = Instance.new("Frame")
    hpGhost.Name = "Ghost"
    hpGhost.Size = UDim2.new(1, 0, 1, 0)
    hpGhost.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
    hpGhost.BackgroundTransparency = 0.5
    hpGhost.BorderSizePixel = 0
    hpGhost.ZIndex = 1
    hpGhost.Parent = hpBg
    Instance.new("UICorner", hpGhost).CornerRadius = UDim.new(0, 4)

    local hpFill = Instance.new("Frame")
    hpFill.Name = "Fill"
    hpFill.Size = UDim2.new(1, 0, 1, 0)
    hpFill.BackgroundColor3 = Color3.fromRGB(40, 220, 80)
    hpFill.BorderSizePixel = 0
    hpFill.ZIndex = 2
    hpFill.Parent = hpBg
    Instance.new("UICorner", hpFill).CornerRadius = UDim.new(0, 4)

    -- Save refs
    UI.Screen     = screen
    UI.BtnFrame   = btnFrame
    UI.LockBtn    = lockBtn
    UI.BtnStroke  = btnStroke
    UI.BtnGlow    = btnGlow
    UI.LockLabel  = lockLbl
    UI.SwitchCont = switchCont
    UI.LeftBtn    = leftBtn
    UI.RightBtn   = rightBtn
    UI.InfoPanel  = infoPanel
    UI.NameLabel  = nameLbl
    UI.DistLabel  = distLbl
    UI.HPFill     = hpFill
    UI.HPGhost    = hpGhost
    UI.LOSDot     = losDot
end

-- ══════════════════════════════════════════════════════
-- UI UPDATES
-- ══════════════════════════════════════════════════════
local function UpdateButtonVisual()
    if not UI.LockBtn then return end

    if State.IsLocked then
        pcall(function()
            TweenService:Create(UI.BtnStroke, TweenInfo.new(0.2), {Color = Color3.fromRGB(255, 45, 45), Thickness = 3}):Play()
            TweenService:Create(UI.BtnGlow, TweenInfo.new(0.2), {Thickness = 4, Transparency = 0.5}):Play()
            TweenService:Create(UI.LockBtn, TweenInfo.new(0.2), {BackgroundColor3 = Color3.fromRGB(65, 10, 10), BackgroundTransparency = 0.05}):Play()
        end)
        UI.LockBtn.Text = "◉"
        UI.LockBtn.TextColor3 = Color3.fromRGB(255, 85, 85)
        UI.LockLabel.Text = "LOCKED"
        UI.LockLabel.TextColor3 = Color3.fromRGB(255, 70, 70)
        UI.SwitchCont.Visible = true
        UI.InfoPanel.Visible = CONFIG.ShowTargetInfo
    else
        pcall(function()
            TweenService:Create(UI.BtnStroke, TweenInfo.new(0.2), {Color = Color3.fromRGB(130, 130, 145), Thickness = 2}):Play()
            TweenService:Create(UI.BtnGlow, TweenInfo.new(0.2), {Thickness = 0, Transparency = 1}):Play()
            TweenService:Create(UI.LockBtn, TweenInfo.new(0.2), {BackgroundColor3 = Color3.fromRGB(30, 30, 35), BackgroundTransparency = 0.15}):Play()
        end)
        UI.LockBtn.Text = "⊕"
        UI.LockBtn.TextColor3 = Color3.fromRGB(190, 190, 200)
        UI.LockLabel.Text = "LOCK"
        UI.LockLabel.TextColor3 = Color3.fromRGB(140, 140, 150)
        UI.SwitchCont.Visible = false
        UI.InfoPanel.Visible = false
    end
end

local lastHP = 1
local function UpdateTargetInfo()
    if not State.IsLocked or not State.CachedTargetHum then return end
    if not UI.NameLabel then return end

    -- Nome
    local displayName = State.Target.DisplayName or State.Target.Name
    UI.NameLabel.Text = displayName

    -- Distância
    local d = math.floor(Dist(State.Target))
    UI.DistLabel.Text = d .. "m"

    -- LOS dot
    local losColor = State.HasLineOfSight
        and Color3.fromRGB(40, 220, 80)
        or Color3.fromRGB(255, 180, 30)
    pcall(function()
        TweenService:Create(UI.LOSDot, TweenInfo.new(0.2), {BackgroundColor3 = losColor}):Play()
    end)

    -- HP
    local pct = math.clamp(State.CachedTargetHum.Health / State.CachedTargetHum.MaxHealth, 0, 1)

    pcall(function()
        TweenService:Create(UI.HPFill, TweenInfo.new(0.15), {Size = UDim2.new(pct, 0, 1, 0)}):Play()
    end)

    -- Ghost (damage flash com delay)
    if pct < lastHP - 0.01 then
        task.delay(0.4, function()
            pcall(function()
                TweenService:Create(UI.HPGhost, TweenInfo.new(0.5), {Size = UDim2.new(pct, 0, 1, 0)}):Play()
            end)
        end)
    elseif pct > lastHP then
        -- Heal: ghost acompanha
        pcall(function()
            TweenService:Create(UI.HPGhost, TweenInfo.new(0.2), {Size = UDim2.new(pct, 0, 1, 0)}):Play()
        end)
    end
    lastHP = pct

    -- Cor HP
    local color
    if pct > 0.6 then     color = Color3.fromRGB(40, 220, 80)
    elseif pct > 0.3 then color = Color3.fromRGB(245, 200, 30)
    elseif pct > 0.1 then color = Color3.fromRGB(255, 80, 30)
    else                   color = Color3.fromRGB(255, 40, 40)
    end

    pcall(function()
        TweenService:Create(UI.HPFill, TweenInfo.new(0.25), {BackgroundColor3 = color}):Play()
    end)
end

-- ══════════════════════════════════════════════════════
-- LOCK / UNLOCK / CYCLE
-- ══════════════════════════════════════════════════════

-- Forward declarations
local LockOn, Unlock, CycleTarget

Unlock = function()
    local hadTarget = State.Target ~= nil

    State.Target = nil
    State.IsLocked = false
    State.TargetVelocity = Vector3.zero
    State.SmoothedPrediction = Vector3.zero
    State.LastTargetPos = nil
    State.WallLossTimer = 0
    State.HasLineOfSight = true
    State.OrbitalOffset = 0
    State.CachedTargetRoot = nil
    State.CachedTargetHum = nil
    State.CachedTargetChar = nil
    lastHP = 1

    DestroyIndicator()
    Disconn("TargetDied")
    Disconn("TargetLeft")
    Disconn("TargetCharRemoved")  -- FIX: agora desconecta corretamente

    Camera.CameraType = Enum.CameraType.Custom

    if hadTarget then
        pcall(function()
            TweenService:Create(Camera, TweenInfo.new(CONFIG.FOVTransitionTime, Enum.EasingStyle.Quad), {
                FieldOfView = State.DefaultFOV
            }):Play()
        end)
    end

    UpdateButtonVisual()
end

LockOn = function(target)
    if not target or not Alive(target) then return end

    local _, root, hum = GetParts(target)
    if not root or not hum then return end

    local isSwitching = State.IsLocked and State.Target ~= nil and State.Target ~= target

    -- Limpa anterior
    DestroyIndicator()
    Disconn("TargetDied")
    Disconn("TargetLeft")
    Disconn("TargetCharRemoved")

    -- Seta novo alvo
    State.Target = target
    State.IsLocked = true
    State.LastTargetPos = root.Position
    State.SmoothedPrediction = root.Position
    State.TargetVelocity = Vector3.zero
    State.WallLossTimer = 0
    State.HasLineOfSight = true
    State.OrbitalOffset = 0

    -- Refresh cache
    RefreshTargetCache()

    lastHP = math.clamp(hum.Health / hum.MaxHealth, 0, 1)
    if UI.HPGhost then
        UI.HPGhost.Size = UDim2.new(lastHP, 0, 1, 0)
    end

    Camera.CameraType = Enum.CameraType.Scriptable

    -- FOV dinâmico inicial
    local dist = (State.Root.Position - root.Position).Magnitude
    local fovT = math.clamp((dist - CONFIG.FOVCloseDistance) / (CONFIG.FOVFarDistance - CONFIG.FOVCloseDistance), 0, 1)
    local targetFOV = CONFIG.FOVClose + (CONFIG.FOVFar - CONFIG.FOVClose) * fovT

    pcall(function()
        TweenService:Create(Camera, TweenInfo.new(0.3, Enum.EasingStyle.Quad), {FieldOfView = targetFOV}):Play()
    end)

    State.CurrentFOV = targetFOV

    -- Indicator com fade se trocando
    CreateIndicator(root, isSwitching)
    if isSwitching then
        FlashSwitchFeedback()
    end

    UpdateButtonVisual()

    -- Monitor morte
    Conn("TargetDied", hum.Died:Connect(function()
        if State.Target ~= target then return end
        if CONFIG.AutoSwitchOnKill then
            task.defer(function()
                local next = FindBestTarget()
                if next then LockOn(next) else Unlock() end
            end)
        else
            Unlock()
        end
    end))

    -- Monitor saída
    Conn("TargetLeft", Players.PlayerRemoving:Connect(function(p)
        if p == target then
            task.defer(function()
                if CONFIG.AutoSwitchOnKill then
                    local next = FindBestTarget()
                    if next then LockOn(next) else Unlock() end
                else
                    Unlock()
                end
            end)
        end
    end))

    -- Monitor respawn do alvo
    Conn("TargetCharRemoved", target.CharacterRemoving:Connect(function()
        if State.Target ~= target then return end
        task.delay(0.3, function()
            if State.Target == target and not Alive(target) then
                if CONFIG.AutoSwitchOnKill then
                    local next = FindBestTarget()
                    if next then LockOn(next) else Unlock() end
                else
                    Unlock()
                end
            end
        end)
    end))
end

CycleTarget = function(direction)
    if not State.IsLocked then return end
    local targets = GetScoredTargets()
    if #targets <= 1 then return end

    local idx = 0
    for i, t in ipairs(targets) do
        if t.Target == State.Target then idx = i; break end
    end

    idx = idx + direction
    if idx < 1 then idx = #targets end
    if idx > #targets then idx = 1 end

    LockOn(targets[idx].Target)
end

-- ══════════════════════════════════════════════════════
-- AIM FRICTION (sem lock) — sticky aim estilo console
-- ══════════════════════════════════════════════════════
local function ResetAimFriction()
    pcall(function()
        UserInputService.MouseDeltaSensitivity = 1
    end)
end

local function ApplyAimFriction(dt)
    if not CONFIG.AimFrictionEnabled or State.IsLocked or not State.Root then
        ResetAimFriction()
        return
    end

    local vpSize = Camera.ViewportSize
    local screenCenter = Vector2.new(vpSize.X / 2, vpSize.Y / 2)

    local closestScreenDist = math.huge
    local frictionActive = false

    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= LocalPlayer and Alive(player) then
            local _, root = GetParts(player)
            if root then
                local worldDist = (State.Root.Position - root.Position).Magnitude
                if worldDist <= CONFIG.AimFrictionRange then
                    local screenPos, onScreen = Camera:WorldToScreenPoint(root.Position + Vector3.new(0, 1.5, 0))
                    if onScreen then
                        local screenDist = (Vector2.new(screenPos.X, screenPos.Y) - screenCenter).Magnitude
                        if screenDist < CONFIG.AimFrictionRadius then
                            closestScreenDist = math.min(closestScreenDist, screenDist)
                            frictionActive = true
                        end
                    end
                end
            end
        end
    end

    -- Aplica sensibilidade diretamente aqui (sem hook separado)
    if frictionActive then
        local proximity = 1 - (closestScreenDist / CONFIG.AimFrictionRadius)
        local mult = 1 - (proximity * CONFIG.AimFrictionStrength)
        pcall(function()
            UserInputService.MouseDeltaSensitivity = mult
        end)
    else
        ResetAimFriction()
    end
end

-- Safety net: garante reset se o script crashar
game:BindToClose(ResetAimFriction)

-- ══════════════════════════════════════════════════════
-- AUTO-LOCK HIT DETECTION
-- ══════════════════════════════════════════════════════
local function TryAutoLock(hitPart)
    if State.IsLocked then return end
    if not CONFIG.AutoLockOnHit then return end

    local model = hitPart:FindFirstAncestorOfClass("Model")
    if not model then return end

    local player = Players:GetPlayerFromCharacter(model)
    if player and player ~= LocalPlayer and Alive(player) then
        LockOn(player)
    end
end

-- Detecta dano recebido (pra threat scoring)
local function SetupDamageDetection()
    if not State.Hum then return end

    local lastHealth = State.Hum.Health
    Conn("DamageTaken", State.Hum.HealthChanged:Connect(function(newHealth)
        if newHealth < lastHealth then
            -- Alguém nos atacou, tenta descobrir quem
            -- Heurística: o player mais perto provavelmente atacou
            local nearest = nil
            local nearestDist = 25 -- range máximo de ataque

            for _, player in ipairs(Players:GetPlayers()) do
                if player ~= LocalPlayer and Alive(player) then
                    local d = Dist(player)
                    if d < nearestDist then
                        nearestDist = d
                        nearest = player
                    end
                end
            end

            if nearest then
                RegisterAttacker(nearest)
            end
        end
        lastHealth = newHealth
    end))
end

local function ConnectToolHit(tool)
    if not tool:IsA("Tool") then return end

    local function HookPart(part)
        if not part or not part:IsA("BasePart") then return end
        local key = "tool_" .. tool.Name .. "_" .. part.Name .. "_" .. math.random(1000, 9999)
        Conn(key, part.Touched:Connect(function(hit)
            TryAutoLock(hit)
        end))
    end

    for _, child in ipairs(tool:GetChildren()) do
        if child:IsA("BasePart") then HookPart(child) end
    end
    tool.ChildAdded:Connect(function(child)
        if child:IsA("BasePart") then HookPart(child) end
    end)
end

local function SetupHitDetection(char)
    if not char then return end
    DisconnGroup("tool_")

    for _, child in ipairs(char:GetChildren()) do
        ConnectToolHit(child)
    end
    Conn("CharToolAdded", char.ChildAdded:Connect(ConnectToolHit))
end

-- ══════════════════════════════════════════════════════
-- ORBITAL CAMERA — mouse/stick ajusta ângulo lateral
-- ══════════════════════════════════════════════════════
local function UpdateOrbital(dt)
    if not CONFIG.OrbitalEnabled then return end
    if not State.IsLocked then
        State.OrbitalOffset = 0
        return
    end

    -- Gamepad right stick
    local gamepadInput = UserInputService:GetGamepadState(Enum.UserInputType.Gamepad1)
    if gamepadInput then
        for _, obj in ipairs(gamepadInput) do
            if obj.KeyCode == Enum.KeyCode.Thumbstick2 then
                local x = obj.Position.X
                if math.abs(x) > 0.15 then -- deadzone
                    State.OrbitalOffset = State.OrbitalOffset + x * CONFIG.OrbitalSpeed * 60 * dt
                end
            end
        end
    end

    -- Clamp
    State.OrbitalOffset = math.clamp(State.OrbitalOffset, -CONFIG.OrbitalMaxAngle, CONFIG.OrbitalMaxAngle)

    -- Decay pro centro (quando não tá movendo)
    local decayAlpha = ExpDecay(CONFIG.OrbitalDecayRate, dt)
    State.OrbitalOffset = SafeLerp(State.OrbitalOffset, 0, decayAlpha * 0.3)
end

-- Mouse orbital: shift + mouse move
Conn("MouseOrbital", UserInputService.InputChanged:Connect(function(input)
    if not State.IsLocked or not CONFIG.OrbitalEnabled then return end

    if input.UserInputType == Enum.UserInputType.MouseMovement then
        if UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) then
            local delta = input.Delta.X
            State.OrbitalOffset = State.OrbitalOffset + delta * CONFIG.OrbitalSpeed
            State.OrbitalOffset = math.clamp(State.OrbitalOffset, -CONFIG.OrbitalMaxAngle, CONFIG.OrbitalMaxAngle)
        end
    end
end))

-- ══════════════════════════════════════════════════════
-- MAIN CAMERA LOOP — framerate independent
-- ══════════════════════════════════════════════════════
local function UpdateCamera(dt)
    _frameCounter = _frameCounter + 1

    -- Aim friction (roda sempre, mesmo sem lock)
    ApplyAimFriction(dt)

    if not State.IsLocked or not State.Target then
        return
    end
    if not State.Root then return end

    -- Refresh cache
    RefreshTargetCache()

    if not State.CachedTargetRoot then
        Unlock()
        return
    end

    -- Wall validation
    UpdateWallValidation(dt)

    -- Distance check
    local dist = (State.Root.Position - State.CachedTargetRoot.Position).Magnitude
    if dist > CONFIG.MaxLockDistance * 1.6 then
        Unlock()
        return
    end

    -- Update prediction
    UpdatePrediction(dt)

    -- Update orbital
    UpdateOrbital(dt)

    -- Posições
    local playerPos = State.Root.Position
    local predictedTarget = GetPredictedTargetPos()
    local actualTarget = State.CachedTargetRoot.Position + Vector3.new(0, 2, 0)

    -- Direção base pro alvo (no plano XZ)
    local toTarget = actualTarget - playerPos
    local flatDir = Vector3.new(toTarget.X, 0, toTarget.Z)
    if flatDir.Magnitude < 0.5 then return end
    flatDir = flatDir.Unit

    -- Aplica orbital offset (rotação lateral)
    local orbitalCF = CFrame.Angles(0, State.OrbitalOffset, 0)
    local adjustedDir = (orbitalCF * CFrame.new(Vector3.zero, flatDir)).LookVector

    -- Posição da câmera
    local camGoal = playerPos
        - adjustedDir * CONFIG.CameraDistance
        + Vector3.new(0, CONFIG.CameraHeight, 0)

    -- SPHERE CAST anti-wall (4 raycasts)
    local wallCheckOrigin = playerPos + Vector3.new(0, 2, 0)
    local ignoreChars = GetAllCharactersCached()

    local wallHit = SphereCast(wallCheckOrigin, camGoal, 0.5, ignoreChars)
    if wallHit then
        camGoal = wallHit.Position + wallHit.Normal * 0.9
        if camGoal.Y < playerPos.Y + 1.5 then
            camGoal = Vector3.new(camGoal.X, playerPos.Y + 1.5, camGoal.Z)
        end
    end

    -- Ponto de foco com predição
    local focusPoint = playerPos:Lerp(predictedTarget, CONFIG.LookAtBias)

    -- Goal CFrame
    local goalCF = CFrame.lookAt(camGoal, focusPoint)

    -- FRAMERATE INDEPENDENT lerp
    local camAlpha = ExpDecay(CONFIG.CamSmoothRate, dt)
    Camera.CFrame = SafeLerp(Camera.CFrame, goalCF, camAlpha)

    -- FOV DINÂMICO por distância
    local fovT = math.clamp(
        (dist - CONFIG.FOVCloseDistance) / (CONFIG.FOVFarDistance - CONFIG.FOVCloseDistance),
        0, 1
    )
    local targetFOV = CONFIG.FOVClose + (CONFIG.FOVFar - CONFIG.FOVClose) * fovT
    local fovAlpha = ExpDecay(CONFIG.FOVSmoothRate, dt)
    State.CurrentFOV = SafeLerp(State.CurrentFOV, targetFOV, fovAlpha)
    Camera.FieldOfView = State.CurrentFOV

    -- Update UI info
    UpdateTargetInfo()
end

-- ══════════════════════════════════════════════════════
-- CHARACTER SETUP
-- ══════════════════════════════════════════════════════
local function OnCharacter(char)
    ResetAimFriction()  -- SEMPRE reseta ao respawn

    State.Char = char
    State.Hum = char:WaitForChild("Humanoid", 10)
    State.Root = char:WaitForChild("HumanoidRootPart", 10)

    if not State.Hum or not State.Root then
        warn("[LockOn v4] Humanoid/RootPart não encontrado")
        return
    end

    if State.IsLocked then Unlock() end

    Conn("SelfDied", State.Hum.Died:Connect(function()
        Unlock()
    end))

    task.delay(0.5, function()
        if State.Char == char then
            SetupHitDetection(char)
            SetupDamageDetection()
        end
    end)
end

-- ══════════════════════════════════════════════════════
-- INPUT
-- ══════════════════════════════════════════════════════

-- Teclado + Gamepad
UserInputService.InputBegan:Connect(function(input, processed)
    if processed then return end
    local key = input.KeyCode

    if key == CONFIG.LockKey or key == CONFIG.GamepadLock then
        if State.IsLocked then Unlock()
        else
            local t = FindBestTarget()
            if t then LockOn(t) end
        end
    elseif key == CONFIG.NextTargetKey or key == CONFIG.GamepadNext then
        CycleTarget(1)
    elseif key == CONFIG.PrevTargetKey then
        CycleTarget(-1)
    end
end)

-- Touch swipe com timeout
UserInputService.TouchStarted:Connect(function(touch, processed)
    if processed or not State.IsLocked then return end
    local vp = Camera.ViewportSize
    if touch.Position.Y < vp.Y * 0.4 then
        State.TouchStart = touch.Position
        State.TouchStartTime = tick()
    end
end)

UserInputService.TouchEnded:Connect(function(touch)
    if not State.TouchStart or not State.IsLocked then
        State.TouchStart = nil
        return
    end

    local elapsed = tick() - State.TouchStartTime
    if elapsed > CONFIG.SwipeTimeout then
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
-- INIT
-- ══════════════════════════════════════════════════════
local function Init()
    BuildUI()
    UpdateButtonVisual()

    -- Botão lock
    UI.LockBtn.MouseButton1Click:Connect(function()
        if State.ButtonDragging then return end
        if State.IsLocked then Unlock()
        else
            local t = FindBestTarget()
            if t then LockOn(t) end
        end
    end)

    UI.LeftBtn.MouseButton1Click:Connect(function() CycleTarget(-1) end)
    UI.RightBtn.MouseButton1Click:Connect(function() CycleTarget(1) end)

    -- Character
    if LocalPlayer.Character then
        task.spawn(function() OnCharacter(LocalPlayer.Character) end)
    end
    LocalPlayer.CharacterAdded:Connect(OnCharacter)

    -- Main loop
    RunService.RenderStepped:Connect(UpdateCamera)

    -- Cleanup ao sair
    LocalPlayer.AncestryChanged:Connect(function(_, parent)
        if not parent then
            ResetAimFriction()
            Unlock()
        end
    end)

    print("══════════════════════════════════════════════")
    print("  LOCK-ON SYSTEM v4.0 CONSOLE GRADE — ATIVO")
    print("  PC:     Q=Lock  E=Next  R=Prev")
    print("          Shift+Mouse = Orbital adjust")
    print("  Mobile: Arraste botão | ◀ ▶ | Swipe")
    print("  Gamepad: RB=Lock  RS=Cycle  RStick=Orbital")
    print("")
    print("  ✦ Predição framerate-independent")
    print("  ✦ Aim friction: " .. tostring(CONFIG.AimFrictionEnabled))
    print("  ✦ FOV dinâmico: " .. CONFIG.FOVFar .. "-" .. CONFIG.FOVClose)
    print("  ✦ Threat scoring: ON")
    print("  ✦ Wall timeout: " .. CONFIG.WallLossTimeout .. "s")
    print("══════════════════════════════════════════════")
end

Init()
