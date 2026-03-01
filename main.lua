--[[
    ╔══════════════════════════════════════════════════════════╗
    ║        LOCK-ON TARGET SYSTEM v5.1 — CHASE GRADE          ║
    ║        Auto-Face • Dash Tracking • Sticky Camera         ║
    ║        Mobile + PC + Gamepad | Framerate Independent      ║
    ╚══════════════════════════════════════════════════════════════╝
    
    LocalScript → StarterPlayerScripts
    
    CONTROLES:
      PC:      Q = Lock/Unlock  |  E = Próximo  |  R = Anterior
               T = Alternar Hard/Soft Lock
               Shift+Mouse = Orbital adjust
      Mobile:  Botão arrastável |  ◀ ▶ Trocar alvo  |  Swipe
      Gamepad: RB = Lock  |  Right Stick = Orbital  |  RS Click = Cycle
    
    v5.1 FIXES SOBRE v5.0:
      ✦ FIX: CONFIG.FaceRotationRate adicionado (CRASH)
      ✦ FIX: Strafe Hum:Move() removido (conflito com PlayerModule)
      ✦ FIX: Soft lock redesenhado (CameraType.Custom + auto-face only)
      ✦ FIX: Shoulder offset ANTES do sphere cast
      ✦ FIX: Wall validation restaura auto-switch (regressão v4)
      ✦ FIX: Damage shake usa dampened sine (não ruído branco)
      ✦ FIX: Gradual unlock usa transparency (não Enabled toggle)
      ✦ FIX: Variable face rate interpolação suave
      ✦ FIX: GetAimPart cached por frame
      ✦ FIX: FaceDuringDash removido (dead config)
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

if not table.clone then
    table.clone = function(t)
        local copy = {}
        for k, v in pairs(t) do copy[k] = v end
        return copy
    end
end

-- ══════════════════════════════════════════════════════
-- CONFIG
-- ══════════════════════════════════════════════════════
local CONFIG = {
    -- ▸ Targeting
    MaxLockDistance       = 150,
    AutoLockOnHit        = true,
    AutoSwitchOnKill     = true,
    UnlockFadeStart      = 1.2,        -- gradual unlock inicia (1.2x max range)
    UnlockFadeFull       = 1.5,        -- unlock forçado (1.5x max range)

    -- ▸ Target scoring weights
    PreferFrontTargets   = true,
    FrontWeight          = 0.5,
    ThreatWeight         = 0.3,
    LowHPWeight          = 0.15,
    ApproachWeight       = 0.25,

    -- ▸ Wall validation
    WallLossTimeout      = 2.5,
    WallCheckInterval    = 0.15,

    -- ▸ CHARACTER FACING
    AutoFaceTarget       = true,
    FaceRotationRate     = 18,         -- [FIX #1] velocidade de rotação em movimento
    FaceRotationIdle     = 30,         -- velocidade de rotação parado (mais rápido)

    -- ▸ Câmera (framerate independent) — AGRESSIVA
    CamSmoothRate        = 18,
    PredictionRate       = 12,
    VelocitySmoothRate   = 7,
    PredictionStrength   = 0.55,
    AimLeadFactor        = 0.35,

    -- ▸ AAA Camera
    CameraShoulderOffset = Vector3.new(1.5, 0, 0), -- offset à direita
    SoftLockEnabled      = true,
    DamageShakeEnabled   = true,
    DamageShakeMagnitude = 0.3,
    DamageShakeDuration  = 0.15,
    DamageShakeFreq      = 35,         -- [FIX #6] frequência do sine shake
    CycleCooldown        = 0.2,

    -- ▸ Câmera orbital
    CameraDistance       = 11,
    CameraHeight         = 3.5,
    LookAtBias           = 0.72,
    OrbitalEnabled       = true,
    OrbitalSpeed         = 0.003,
    OrbitalMaxAngle      = math.rad(50),
    OrbitalDecayRate     = 3,

    -- ▸ FOV dinâmico
    FOVClose             = 68,
    FOVFar               = 45,
    FOVCloseDistance      = 12,
    FOVFarDistance        = 80,
    FOVSmoothRate        = 8,
    FOVTransitionTime    = 0.25,

    -- ▸ Aim friction (sem lock ativo)
    AimFrictionEnabled   = true,
    AimFrictionRadius    = 60,
    AimFrictionStrength  = 0.45,
    AimFrictionRange     = 80,

    -- ▸ Visual
    IndicatorEnabled     = true,
    ShowTargetInfo       = true,
    SwitchFeedback       = true,
    TargetInfoOffset     = UDim2.new(0.5, 0, 0, 55),

    -- ▸ Teclas
    LockKey              = Enum.KeyCode.Q,
    SoftLockKey          = Enum.KeyCode.T,
    NextTargetKey        = Enum.KeyCode.E,
    PrevTargetKey        = Enum.KeyCode.R,
    GamepadLock          = Enum.KeyCode.ButtonR1,
    GamepadNext          = Enum.KeyCode.ButtonR3,

    -- ▸ Mobile
    ButtonSize           = 62,
    DefaultButtonPos     = UDim2.new(1, -85, 0.35, 0),
    SwipeThreshold       = 55,
    SwipeTimeout         = 0.3,
    DragThreshold        = 8,
}

-- ══════════════════════════════════════════════════════
-- STATE
-- ══════════════════════════════════════════════════════
local State = {
    Target          = nil,
    PendingTarget   = nil,           -- para re-lock após respawn
    IsLocked        = false,
    LockMode        = "hard",        -- "hard" ou "soft"
    Char            = nil,
    Hum             = nil,
    Root            = nil,
    DefaultFOV      = Camera.FieldOfView,
    CurrentFOV      = Camera.FieldOfView,
    Conns           = {},
    Indicator       = nil,

    CachedTargetRoot = nil,
    CachedTargetHum  = nil,
    CachedTargetChar = nil,
    CachedAimPart    = nil,          -- [FIX #9] cache do aim part

    TargetVelocity      = Vector3.zero,
    SmoothedPrediction  = Vector3.zero,
    LastTargetPos       = nil,
    LastPredictionTime  = 0,

    WallLossTimer       = 0,
    HasLineOfSight      = true,
    LastWallCheck       = 0,

    OrbitalOffset       = 0,

    TouchStart      = nil,
    TouchStartTime  = 0,
    ButtonDragging  = false,
    SavedButtonPos  = nil,

    LastCameraInput = Vector2.zero,

    OriginalAutoRotate = true,
    SmoothedFaceDir    = nil,

    LastCycleTime      = 0,
    BufferedCycleDir   = nil,

    -- [FIX #6] Shake com dampened sine
    ShakeTimer         = 0,
    ShakeStartTime     = 0,
    CameraShakeOffset  = Vector3.zero,

    RecentAttackers = {},
}

-- ══════════════════════════════════════════════════════
-- MATH HELPERS
-- ══════════════════════════════════════════════════════
local function ExpDecay(rate, dt)
    return 1 - math.exp(-rate * dt)
end

local function SafeLerp(a, b, alpha)
    alpha = math.clamp(alpha, 0, 1)
    if typeof(a) == "Vector3" then return a:Lerp(b, alpha)
    elseif typeof(a) == "CFrame" then return a:Lerp(b, alpha)
    elseif typeof(a) == "number" then return a + (b - a) * alpha end
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
            if typeof(v) == "RBXScriptConnection" then v:Disconnect() end
            table.insert(toRemove, k)
        end
    end
    for _, k in ipairs(toRemove) do State.Conns[k] = nil end
end

-- ══════════════════════════════════════════════════════
-- TARGET PARTS — cached per frame
-- ══════════════════════════════════════════════════════
local function GetParts(target)
    if not target then return nil, nil, nil end
    if typeof(target) == "Instance" and target:IsA("Player") then
        local c = target.Character
        if not c then return nil, nil, nil end
        return c, c:FindFirstChild("HumanoidRootPart"), c:FindFirstChildOfClass("Humanoid")
    end
    return nil, nil, nil
end

-- [FIX #9] Mira no UpperTorso/Torso (mais preciso que HumanoidRootPart)
local function GetAimPart(targetChar)
    if not targetChar then return nil end
    return targetChar:FindFirstChild("UpperTorso")
        or targetChar:FindFirstChild("Torso")
        or targetChar:FindFirstChild("HumanoidRootPart")
end

local function RefreshTargetCache()
    if not State.Target then
        State.CachedTargetChar, State.CachedTargetRoot, State.CachedTargetHum = nil, nil, nil
        State.CachedAimPart = nil
        return
    end
    State.CachedTargetChar, State.CachedTargetRoot, State.CachedTargetHum = GetParts(State.Target)
    -- [FIX #9] Cache aim part junto (1 lookup/frame ao invés de 2-3)
    State.CachedAimPart = GetAimPart(State.CachedTargetChar)
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
-- RAYCAST — cached per frame
-- ══════════════════════════════════════════════════════
local FrameCache = { Characters = nil, FrameCount = -1 }
local _frameCounter = 0

local function GetAllCharactersCached()
    if FrameCache.FrameCount == _frameCounter then return FrameCache.Characters end
    local chars = {}
    for _, p in ipairs(Players:GetPlayers()) do
        if p.Character then chars[#chars + 1] = p.Character end
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
        local merged = table.clone(filter)
        for _, v in ipairs(extraIgnore) do merged[#merged + 1] = v end
        params.FilterDescendantsInstances = merged
    else
        params.FilterDescendantsInstances = filter
    end
    return workspace:Raycast(fromPos, dir, params) == nil
end

local function SphereCast(origin, target, radius, ignoreList)
    local dir = target - origin
    if dir.Magnitude < 0.1 then return nil end

    local forward = dir.Unit
    local right = forward:Cross(Vector3.new(0, 1, 0))
    if right.Magnitude < 0.01 then right = forward:Cross(Vector3.new(1, 0, 0)) end
    right = right.Unit
    local up = right:Cross(forward).Unit

    local offsets = { Vector3.zero, right * radius, -right * radius, up * radius }
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = ignoreList or {}
    params.RespectCanCollide = true

    local bestHit, bestDist = nil, math.huge
    for _, offset in ipairs(offsets) do
        local from = origin + offset
        local result = workspace:Raycast(from, (target + offset) - from, params)
        if result then
            local d = (result.Position - from).Magnitude
            if d < bestDist then bestDist = d; bestHit = result end
        end
    end
    return bestHit
end

-- ══════════════════════════════════════════════════════
-- THREAT SCORING
-- ══════════════════════════════════════════════════════
local function RegisterAttacker(attacker)
    State.RecentAttackers[attacker] = tick()
end

local function CleanAttackers()
    local now = tick()
    local toRemove = {}
    for k, t in pairs(State.RecentAttackers) do
        if now - t > 5 then table.insert(toRemove, k) end
    end
    for _, k in ipairs(toRemove) do State.RecentAttackers[k] = nil end
end

local function ScoreTarget(target)
    local _, root, hum = GetParts(target)
    if not root or not hum or not State.Root then return math.huge end
    if hum.Health <= 0 then return math.huge end

    local dist = (State.Root.Position - root.Position).Magnitude
    if dist > CONFIG.MaxLockDistance then return math.huge end

    -- Pré-filtro: skip raycast se alvo está atrás da câmera
    local camLook = Camera.CFrame.LookVector
    local toTarget = (root.Position - State.Root.Position)
    local dot = toTarget.Magnitude > 0.1 and camLook:Dot(toTarget.Unit) or 0
    if dot < -0.3 then return math.huge end

    local origin = State.Root.Position + Vector3.new(0, 1.5, 0)
    local targetPos = root.Position + Vector3.new(0, 1.5, 0)
    if not ClearSight(origin, targetPos) then return math.huge end

    local score = dist / CONFIG.MaxLockDistance

    if CONFIG.PreferFrontTargets and toTarget.Magnitude > 0.1 then
        score = score + (1 - dot) * 0.5 * CONFIG.FrontWeight
    end

    local attackTime = State.RecentAttackers[target]
    if attackTime then
        score = score - math.clamp(1 - (tick() - attackTime) / 5, 0, 1) * CONFIG.ThreatWeight
    end

    local hpPct = hum.Health / hum.MaxHealth
    if hpPct < 0.4 then score = score - (1 - hpPct) * CONFIG.LowHPWeight end

    local rootVel = root.AssemblyLinearVelocity
    if rootVel and rootVel.Magnitude > 1 and toTarget.Magnitude > 0.1 then
        local approachDot = rootVel.Unit:Dot((State.Root.Position - root.Position).Unit)
        if approachDot > 0.3 then score = score - approachDot * CONFIG.ApproachWeight end
    end

    return score
end

local function GetScoredTargets()
    CleanAttackers()
    local targets = {}
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
-- VELOCITY PREDICTION
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
            local instantVel = (currentPos - State.LastTargetPos) / timeDelta
            State.TargetVelocity = SafeLerp(State.TargetVelocity, instantVel, ExpDecay(CONFIG.VelocitySmoothRate, dt))
            local predicted = currentPos + State.TargetVelocity * CONFIG.PredictionStrength
            State.SmoothedPrediction = SafeLerp(State.SmoothedPrediction, predicted, ExpDecay(CONFIG.PredictionRate, dt))
        end
    else
        State.SmoothedPrediction = currentPos
    end
    State.LastTargetPos = currentPos
    State.LastPredictionTime = now
end

-- [FIX #9] Usa CachedAimPart ao invés de chamar GetAimPart repetido
local function GetPredictedTargetPos()
    if not State.CachedTargetRoot then return Vector3.zero end

    local aimPart = State.CachedAimPart or State.CachedTargetRoot
    local basePos = aimPart.Position

    if State.SmoothedPrediction.Magnitude > 0 then
        local predOffset = State.SmoothedPrediction - State.CachedTargetRoot.Position
        return basePos:Lerp(basePos + predOffset, CONFIG.AimLeadFactor)
    end
    return basePos
end

-- Forward declarations
local LockOn, Unlock, CycleTarget

-- ══════════════════════════════════════════════════════
-- CHARACTER AUTO-FACE
-- [FIX #2] Sem Hum:Move() — strafe é natural via câmera
-- [FIX #8] Face rate interpolação suave, não binário
-- ══════════════════════════════════════════════════════
local function EnableAutoFace()
    if not CONFIG.AutoFaceTarget or not State.Hum then return end
    State.OriginalAutoRotate = State.Hum.AutoRotate
    State.Hum.AutoRotate = false
end

local function DisableAutoFace()
    if not State.Hum then return end
    State.Hum.AutoRotate = State.OriginalAutoRotate or true
    State.SmoothedFaceDir = nil
end

local function UpdateCharacterFacing(dt)
    if not CONFIG.AutoFaceTarget or not State.IsLocked then return end
    if not State.Root or not State.CachedTargetRoot then return end
    if not State.Hum or State.Hum.Health <= 0 then return end

    -- Soft lock: só faz auto-face se for hard lock
    -- Soft lock deixa o player livre pra virar
    if State.LockMode == "soft" then return end

    if State.Hum.AutoRotate then State.Hum.AutoRotate = false end

    local myPos = State.Root.Position
    local targetPos = State.CachedTargetRoot.Position
    local flatDir = Vector3.new(targetPos.X - myPos.X, 0, targetPos.Z - myPos.Z)

    if flatDir.Magnitude < 0.5 then return end
    flatDir = flatDir.Unit

    -- Mistura leve com predição (80/20) pra ser responsivo sem errático
    if State.SmoothedPrediction and State.SmoothedPrediction.Magnitude > 1 then
        local predFlat = Vector3.new(State.SmoothedPrediction.X - myPos.X, 0, State.SmoothedPrediction.Z - myPos.Z)
        if predFlat.Magnitude > 0.5 then
            flatDir = flatDir:Lerp(predFlat.Unit, 0.2).Unit
        end
    end

    if not State.SmoothedFaceDir then
        State.SmoothedFaceDir = State.Root.CFrame.LookVector
    end

    -- [FIX #8] Taxa variável com INTERPOLAÇÃO suave baseada em moveMag
    -- Parado = FaceRotationIdle (30, rápido), correndo = FaceRotationRate (18, suave)
    local moveMag = math.clamp(State.Hum.MoveDirection.Magnitude, 0, 1)
    local faceRate = CONFIG.FaceRotationIdle + (CONFIG.FaceRotationRate - CONFIG.FaceRotationIdle) * moveMag

    local currentLook = Vector3.new(State.SmoothedFaceDir.X, 0, State.SmoothedFaceDir.Z)
    if currentLook.Magnitude < 0.1 then currentLook = flatDir end

    local newDir = SafeLerp(currentLook.Unit, flatDir, ExpDecay(faceRate, dt))
    if typeof(newDir) == "Vector3" and newDir.Magnitude > 0.1 then
        newDir = Vector3.new(newDir.X, 0, newDir.Z).Unit
        State.SmoothedFaceDir = newDir
        -- Aplica rotação mantendo posição
        State.Root.CFrame = CFrame.lookAt(State.Root.Position, State.Root.Position + newDir)
    end

    -- [FIX #2] NÃO chama Hum:Move() — o PlayerModule já faz isso.
    -- Com CameraType.Scriptable + AutoRotate=false, WASD já é relativo
    -- à câmera que aponta pro alvo. Strafe é NATURAL.
end

-- ══════════════════════════════════════════════════════
-- WALL VALIDATION
-- [FIX #5] Restaura auto-switch do v4
-- ══════════════════════════════════════════════════════
local function UpdateWallValidation(dt)
    if not State.IsLocked or not State.CachedTargetRoot or not State.Root then
        State.WallLossTimer = 0
        State.HasLineOfSight = true
        return
    end

    local now = tick()
    if now - State.LastWallCheck < CONFIG.WallCheckInterval then return end
    local elapsed = now - State.LastWallCheck
    State.LastWallCheck = now

    local origin = State.Root.Position + Vector3.new(0, 1.5, 0)
    local target = State.CachedTargetRoot.Position + Vector3.new(0, 1.5, 0)

    if ClearSight(origin, target) then
        State.WallLossTimer = 0
        State.HasLineOfSight = true
    else
        State.HasLineOfSight = false
        State.WallLossTimer = State.WallLossTimer + elapsed

        if State.WallLossTimer >= CONFIG.WallLossTimeout then
            -- [FIX #5] Auto-switch antes de unlock (restaurado do v4)
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
-- DAMAGE CAMERA SHAKE
-- [FIX #6] Dampened sine ao invés de ruído branco
-- ══════════════════════════════════════════════════════
local function TriggerShake()
    if not CONFIG.DamageShakeEnabled or not State.IsLocked then return end
    State.ShakeTimer = CONFIG.DamageShakeDuration
    State.ShakeStartTime = tick()
end

local function UpdateShake(dt)
    if State.ShakeTimer <= 0 then
        State.CameraShakeOffset = Vector3.zero
        return
    end

    State.ShakeTimer = State.ShakeTimer - dt
    local elapsed = tick() - State.ShakeStartTime
    local duration = CONFIG.DamageShakeDuration

    -- Dampened sine: amplitude decai exponencialmente, direção oscila suavemente
    local decay = math.exp(-elapsed / duration * 3) -- envelope de decay
    local freq = CONFIG.DamageShakeFreq
    local mag = CONFIG.DamageShakeMagnitude * decay

    State.CameraShakeOffset = Vector3.new(
        math.sin(elapsed * freq) * mag,
        math.cos(elapsed * freq * 1.3) * mag * 0.7,
        math.sin(elapsed * freq * 0.7) * mag * 0.3
    )
end

-- ══════════════════════════════════════════════════════
-- 3D INDICATOR
-- [FIX #7] Gradual unlock usa transparency, não Enabled toggle
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

    local dot = Instance.new("Frame")
    dot.Name = "Dot"
    dot.AnchorPoint = Vector2.new(0.5, 0.5)
    dot.Position = UDim2.new(0.5, 0, 0.5, 0)
    dot.Size = UDim2.new(0.08, 0, 0.08, 0)
    dot.BackgroundColor3 = Color3.fromRGB(255, 80, 80)
    dot.BorderSizePixel = 0
    dot.Parent = holder
    Instance.new("UICorner", dot).CornerRadius = UDim.new(1, 0)

    local arrowHolder = Instance.new("Frame")
    arrowHolder.Name = "Arrows"
    arrowHolder.AnchorPoint = Vector2.new(0.5, 0.5)
    arrowHolder.Position = UDim2.new(0.5, 0, 0.5, 0)
    arrowHolder.Size = UDim2.new(0.85, 0, 0.85, 0)
    arrowHolder.BackgroundTransparency = 1
    arrowHolder.Parent = holder

    local arrowData = {
        {pos = UDim2.new(0.5, 0, 0, 0), rot = 0},
        {pos = UDim2.new(1, 0, 0.5, 0), rot = 90},
        {pos = UDim2.new(0.5, 0, 1, 0), rot = 180},
        {pos = UDim2.new(0, 0, 0.5, 0), rot = 270},
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

    -- Dead flag pra parar loops quando destruído
    bb:GetPropertyChangedSignal("Parent"):Connect(function()
        if not bb.Parent then bb:SetAttribute("_dead", true) end
    end)

    -- Pulse animation
    task.spawn(function()
        local expanding = false
        while not bb:GetAttribute("_dead") do
            local szA = expanding and UDim2.new(0.95, 0, 0.95, 0) or UDim2.new(0.72, 0, 0.72, 0)
            local szD = expanding and UDim2.new(0.1, 0, 0.1, 0) or UDim2.new(0.06, 0, 0.06, 0)
            local ok = pcall(function()
                TweenService:Create(arrowHolder, TweenInfo.new(0.65, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), {Size = szA}):Play()
                TweenService:Create(dot, TweenInfo.new(0.65, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), {Size = szD}):Play()
            end)
            if not ok then break end
            expanding = not expanding
            task.wait(0.65)
        end
    end)

    -- LOS indicator: escurece atrás de parede
    task.spawn(function()
        while not bb:GetAttribute("_dead") do
            local transp = State.HasLineOfSight and 0.15 or 0.55
            pcall(function()
                TweenService:Create(ring, TweenInfo.new(0.3), {BackgroundTransparency = transp}):Play()
            end)
            task.wait(0.2)
        end
    end)

    -- Fade-in na troca de alvo
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

-- [FIX #7] Gradual unlock: indica via transparency suave (não on/off blink)
local function UpdateIndicatorFade(fadeMult)
    if not State.Indicator then return end
    -- fadeMult vai de 1 (normal) a 0 (quase unlock)
    -- Quando perto do limite, ring pulsa suavemente entre opaco e translúcido
    if fadeMult < 1 then
        local pulse = 0.5 + 0.5 * math.sin(tick() * 8)  -- oscila suave
        local transp = 0.15 + (1 - fadeMult) * pulse * 0.5  -- mais translúcido perto do limite
        for _, child in ipairs(State.Indicator:GetDescendants()) do
            if child.Name == "Ring" and child:IsA("Frame") then
                pcall(function()
                    child.BackgroundTransparency = math.clamp(transp, 0.15, 0.7)
                end)
                break
            end
        end
    end
end

-- ══════════════════════════════════════════════════════
-- UI MOBILE
-- ══════════════════════════════════════════════════════
local UI = {}

local function BuildUI()
    local old = PlayerGui:FindFirstChild("LockOnUI_v5")
    if old then old:Destroy() end

    local screen = Instance.new("ScreenGui")
    screen.Name = "LockOnUI_v5"
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

    -- Drag system
    local dragging, dragStart, startPos, totalDist = false, nil, nil, 0
    lockBtn.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging = true
            dragStart = input.Position
            startPos = btnFrame.Position
            totalDist = 0
            State.ButtonDragging = false
        end
    end)
    UserInputService.InputChanged:Connect(function(input)
        if not dragging then return end
        if input.UserInputType ~= Enum.UserInputType.Touch and input.UserInputType ~= Enum.UserInputType.MouseMovement then return end
        totalDist = math.max(totalDist, (input.Position - dragStart).Magnitude)
        if totalDist > CONFIG.DragThreshold then
            State.ButtonDragging = true
            local delta = input.Position - dragStart
            btnFrame.Position = UDim2.new(
                startPos.X.Scale, startPos.X.Offset + delta.X,
                startPos.Y.Scale, startPos.Y.Offset + delta.Y
            )
        end
    end)
    UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
            if dragging then
                dragging = false
                if State.ButtonDragging then State.SavedButtonPos = btnFrame.Position end
                task.delay(0.05, function() State.ButtonDragging = false end)
            end
        end
    end)

    -- Switch buttons
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

    -- Info panel
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

    UI = {
        Screen = screen, BtnFrame = btnFrame, LockBtn = lockBtn,
        BtnStroke = btnStroke, BtnGlow = btnGlow, LockLabel = lockLbl,
        SwitchCont = switchCont, LeftBtn = leftBtn, RightBtn = rightBtn,
        InfoPanel = infoPanel, NameLabel = nameLbl, DistLabel = distLbl,
        HPFill = hpFill, HPGhost = hpGhost, LOSDot = losDot,
    }
end

local function UpdateButtonVisual()
    if not UI.LockBtn then return end

    if State.IsLocked then
        local modeColor = State.LockMode == "soft"
            and Color3.fromRGB(255, 200, 45)
            or Color3.fromRGB(255, 45, 45)
        pcall(function()
            TweenService:Create(UI.BtnStroke, TweenInfo.new(0.2), {Color = modeColor, Thickness = 3}):Play()
            TweenService:Create(UI.BtnGlow, TweenInfo.new(0.2), {Thickness = 4, Transparency = 0.5}):Play()
            TweenService:Create(UI.LockBtn, TweenInfo.new(0.2), {BackgroundColor3 = Color3.fromRGB(65, 10, 10), BackgroundTransparency = 0.05}):Play()
        end)
        UI.LockBtn.Text = "◉"
        UI.LockBtn.TextColor3 = Color3.fromRGB(255, 85, 85)
        UI.LockLabel.Text = State.LockMode == "soft" and "SOFT" or "LOCKED"
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
    if not State.IsLocked or not State.CachedTargetHum or not UI.NameLabel then return end

    UI.NameLabel.Text = State.Target.DisplayName or State.Target.Name
    UI.DistLabel.Text = math.floor(Dist(State.Target)) .. "m"

    -- LOS dot
    local losColor = State.HasLineOfSight and Color3.fromRGB(40, 220, 80) or Color3.fromRGB(255, 180, 30)
    pcall(function() TweenService:Create(UI.LOSDot, TweenInfo.new(0.2), {BackgroundColor3 = losColor}):Play() end)

    -- HP bar
    local pct = math.clamp(State.CachedTargetHum.Health / State.CachedTargetHum.MaxHealth, 0, 1)
    pcall(function()
        TweenService:Create(UI.HPFill, TweenInfo.new(0.15), {Size = UDim2.new(pct, 0, 1, 0)}):Play()
    end)

    -- Ghost bar (delay de dano)
    if pct < lastHP - 0.01 then
        task.delay(0.4, function()
            pcall(function()
                TweenService:Create(UI.HPGhost, TweenInfo.new(0.5), {Size = UDim2.new(pct, 0, 1, 0)}):Play()
            end)
        end)
    elseif pct > lastHP then
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
    State.CachedAimPart = nil
    State.CameraShakeOffset = Vector3.zero
    State.ShakeTimer = 0
    lastHP = 1

    DestroyIndicator()
    DisableAutoFace()
    Disconn("TargetDied")
    Disconn("TargetLeft")
    Disconn("TargetCharRemoved")

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

    DestroyIndicator()
    Disconn("TargetDied")
    Disconn("TargetLeft")
    Disconn("TargetCharRemoved")

    State.Target = target
    State.IsLocked = true
    State.LastTargetPos = root.Position
    State.SmoothedPrediction = root.Position
    State.TargetVelocity = Vector3.zero
    State.WallLossTimer = 0
    State.HasLineOfSight = true
    State.OrbitalOffset = 0

    RefreshTargetCache()
    lastHP = math.clamp(hum.Health / hum.MaxHealth, 0, 1)
    if UI.HPGhost then UI.HPGhost.Size = UDim2.new(lastHP, 0, 1, 0) end

    -- [FIX #3] Hard lock = Scriptable, Soft lock = Custom (sem conflito)
    if State.LockMode == "hard" then
        Camera.CameraType = Enum.CameraType.Scriptable
    else
        Camera.CameraType = Enum.CameraType.Custom
    end

    EnableAutoFace()

    -- FOV inicial
    local dist = (State.Root.Position - root.Position).Magnitude
    local fovT = math.clamp((dist - CONFIG.FOVCloseDistance) / (CONFIG.FOVFarDistance - CONFIG.FOVCloseDistance), 0, 1)
    local targetFOV = CONFIG.FOVClose + (CONFIG.FOVFar - CONFIG.FOVClose) * fovT
    pcall(function()
        TweenService:Create(Camera, TweenInfo.new(0.3, Enum.EasingStyle.Quad), {FieldOfView = targetFOV}):Play()
    end)
    State.CurrentFOV = targetFOV

    CreateIndicator(root, isSwitching)
    if isSwitching then FlashSwitchFeedback() end
    UpdateButtonVisual()

    -- Monitor morte do alvo
    Conn("TargetDied", hum.Died:Connect(function()
        if State.Target ~= target then return end
        task.defer(function()
            if CONFIG.AutoSwitchOnKill then
                local next = FindBestTarget()
                if next then LockOn(next) else Unlock() end
            else
                Unlock()
            end
        end)
    end))

    -- Monitor saída do alvo
    Conn("TargetLeft", Players.PlayerRemoving:Connect(function(p)
        if p ~= target then return end
        task.defer(function()
            if CONFIG.AutoSwitchOnKill then
                local next = FindBestTarget()
                if next then LockOn(next) else Unlock() end
            else
                Unlock()
            end
        end)
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

    -- Input buffering cooldown
    local now = tick()
    if now - State.LastCycleTime < CONFIG.CycleCooldown then
        State.BufferedCycleDir = direction
        return
    end
    State.LastCycleTime = now

    local targets = GetScoredTargets()
    if #targets <= 1 then return end

    -- Directional switch: pega alvo na direção do swipe/input
    if State.CachedTargetRoot then
        local currentPos2D = Camera:WorldToScreenPoint(State.CachedTargetRoot.Position)
        local bestTarget, bestScore = nil, math.huge

        for _, t in ipairs(targets) do
            if t.Target ~= State.Target then
                local _, root = GetParts(t.Target)
                if root then
                    local pos2D, onScr = Camera:WorldToScreenPoint(root.Position)
                    if onScr then
                        local dx = pos2D.X - currentPos2D.X
                        -- Só aceita alvos na direção certa (direita ou esquerda)
                        if (direction > 0 and dx > 10) or (direction < 0 and dx < -10) then
                            local dist = math.abs(dx) + math.abs(pos2D.Y - currentPos2D.Y) * 2
                            if dist < bestScore then
                                bestScore = dist
                                bestTarget = t.Target
                            end
                        end
                    end
                end
            end
        end

        if bestTarget then
            LockOn(bestTarget)
            return
        end
    end

    -- Fallback: ciclo simples por score
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
-- AIM FRICTION
-- ══════════════════════════════════════════════════════
local function ResetAimFriction()
    pcall(function() UserInputService.MouseDeltaSensitivity = 1 end)
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
            if root and (State.Root.Position - root.Position).Magnitude <= CONFIG.AimFrictionRange then
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

    if frictionActive then
        local proximity = 1 - (closestScreenDist / CONFIG.AimFrictionRadius)
        pcall(function()
            UserInputService.MouseDeltaSensitivity = 1 - (proximity * CONFIG.AimFrictionStrength)
        end)
    else
        ResetAimFriction()
    end
end

game:BindToClose(ResetAimFriction)

-- ══════════════════════════════════════════════════════
-- HIT DETECTION & DAMAGE
-- ══════════════════════════════════════════════════════
local function TryAutoLock(hitPart)
    if State.IsLocked or not CONFIG.AutoLockOnHit then return end
    local model = hitPart:FindFirstAncestorOfClass("Model")
    if not model then return end
    local player = Players:GetPlayerFromCharacter(model)
    if player and player ~= LocalPlayer and Alive(player) then LockOn(player) end
end

local function SetupDamageDetection()
    if not State.Hum then return end
    local lastHealth = State.Hum.Health
    Conn("DamageTaken", State.Hum.HealthChanged:Connect(function(newHealth)
        if newHealth < lastHealth then
            -- [FIX #6] Trigger shake com dampened sine
            TriggerShake()

            -- Registra atacante mais próximo
            local nearest, nearestDist = nil, 25
            for _, player in ipairs(Players:GetPlayers()) do
                if player ~= LocalPlayer and Alive(player) then
                    local d = Dist(player)
                    if d < nearestDist then nearestDist = d; nearest = player end
                end
            end
            if nearest then RegisterAttacker(nearest) end
        end
        lastHealth = newHealth
    end))
end

local function ConnectToolHit(tool)
    if not tool:IsA("Tool") then return end
    local function HookPart(part)
        if not part or not part:IsA("BasePart") then return end
        local key = "tool_" .. tool.Name .. "_" .. part.Name .. "_" .. math.random(1000, 9999)
        Conn(key, part.Touched:Connect(function(hit) TryAutoLock(hit) end))
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
    for _, child in ipairs(char:GetChildren()) do ConnectToolHit(child) end
    Conn("CharToolAdded", char.ChildAdded:Connect(ConnectToolHit))
end

-- ══════════════════════════════════════════════════════
-- ORBITAL CAMERA
-- ══════════════════════════════════════════════════════
local function UpdateOrbital(dt)
    if not CONFIG.OrbitalEnabled then return end
    if not State.IsLocked then State.OrbitalOffset = 0; return end

    -- Gamepad right stick
    local ok, gamepadInput = pcall(UserInputService.GetGamepadState, UserInputService, Enum.UserInputType.Gamepad1)
    if ok and gamepadInput then
        for _, obj in ipairs(gamepadInput) do
            if obj.KeyCode == Enum.KeyCode.Thumbstick2 and math.abs(obj.Position.X) > 0.15 then
                State.OrbitalOffset = State.OrbitalOffset + obj.Position.X * CONFIG.OrbitalSpeed * 60 * dt
            end
        end
    end

    State.OrbitalOffset = math.clamp(State.OrbitalOffset, -CONFIG.OrbitalMaxAngle, CONFIG.OrbitalMaxAngle)
    -- Decay suave de volta ao centro
    State.OrbitalOffset = SafeLerp(State.OrbitalOffset, 0, ExpDecay(CONFIG.OrbitalDecayRate, dt) * 0.3)
end

-- Mouse orbital: shift + mouse move
Conn("MouseOrbital", UserInputService.InputChanged:Connect(function(input)
    if not State.IsLocked or not CONFIG.OrbitalEnabled then return end
    if input.UserInputType == Enum.UserInputType.MouseMovement then
        if UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) then
            State.OrbitalOffset = State.OrbitalOffset + input.Delta.X * CONFIG.OrbitalSpeed
            State.OrbitalOffset = math.clamp(State.OrbitalOffset, -CONFIG.OrbitalMaxAngle, CONFIG.OrbitalMaxAngle)
        end
    end
end))

-- ══════════════════════════════════════════════════════
-- MAIN CAMERA LOOP
-- ══════════════════════════════════════════════════════
local function UpdateCamera(dt)
    _frameCounter = _frameCounter + 1

    -- Aim friction (roda sempre, mesmo sem lock)
    ApplyAimFriction(dt)

    -- Input buffer: processa cycle bufferizado
    if State.BufferedCycleDir and tick() - State.LastCycleTime >= CONFIG.CycleCooldown then
        local dir = State.BufferedCycleDir
        State.BufferedCycleDir = nil
        CycleTarget(dir)
    end

    if not State.IsLocked or not State.Target or not State.Root then return end

    RefreshTargetCache()
    if not State.CachedTargetRoot then Unlock(); return end

    UpdateWallValidation(dt)

    -- ═══ GRADUAL DISTANCE UNLOCK ═══
    local dist = (State.Root.Position - State.CachedTargetRoot.Position).Magnitude
    local maxDist = CONFIG.MaxLockDistance

    -- Unlock forçado
    if dist > maxDist * CONFIG.UnlockFadeFull then Unlock(); return end

    -- Fade multiplier: 1 = normal, 0 = quase unlock
    local fadeMult = 1
    if dist > maxDist * CONFIG.UnlockFadeStart then
        fadeMult = 1 - (dist - maxDist * CONFIG.UnlockFadeStart) / (maxDist * (CONFIG.UnlockFadeFull - CONFIG.UnlockFadeStart))
        fadeMult = math.clamp(fadeMult, 0, 1)
    end

    -- [FIX #7] Indicator fade gradual (não on/off toggle)
    UpdateIndicatorFade(fadeMult)

    UpdatePrediction(dt)
    UpdateCharacterFacing(dt)
    UpdateOrbital(dt)
    UpdateShake(dt)

    -- [FIX #3] Soft lock: só faz auto-face + indicator, câmera é livre
    if State.LockMode == "soft" then
        UpdateTargetInfo()
        return
    end

    -- ═══ HARD LOCK CAMERA (Scriptable) ═══
    local playerPos = State.Root.Position

    -- [FIX #9] Usa CachedAimPart
    local aimPos = State.CachedAimPart and State.CachedAimPart.Position
        or (State.CachedTargetRoot.Position + Vector3.new(0, 2, 0))
    local predictedTarget = GetPredictedTargetPos()

    local toTarget = aimPos - playerPos
    local flatDir = Vector3.new(toTarget.X, 0, toTarget.Z)
    if flatDir.Magnitude < 0.5 then return end
    flatDir = flatDir.Unit

    -- Orbital offset
    local adjustedDir = (CFrame.Angles(0, State.OrbitalOffset, 0) * CFrame.new(Vector3.zero, flatDir)).LookVector

    -- Posição base da câmera
    local camGoal = playerPos
        - adjustedDir * CONFIG.CameraDistance
        + Vector3.new(0, CONFIG.CameraHeight, 0)

    -- Ponto de foco com predição
    local focusPoint = playerPos:Lerp(predictedTarget, CONFIG.LookAtBias)

    -- [FIX #4] Shoulder offset ANTES do sphere cast
    local tempCF = CFrame.lookAt(camGoal, focusPoint)
    camGoal = camGoal + tempCF.RightVector * CONFIG.CameraShoulderOffset.X

    -- Shake
    camGoal = camGoal + State.CameraShakeOffset

    -- SPHERE CAST anti-wall (4 raycasts) — DEPOIS do shoulder offset
    local wallHit = SphereCast(playerPos + Vector3.new(0, 2, 0), camGoal, 0.5, GetAllCharactersCached())
    if wallHit then
        camGoal = wallHit.Position + wallHit.Normal * 0.9
        if camGoal.Y < playerPos.Y + 1.5 then
            camGoal = Vector3.new(camGoal.X, playerPos.Y + 1.5, camGoal.Z)
        end
    end

    -- Goal CFrame final
    local goalCF = CFrame.lookAt(camGoal, focusPoint)

    -- Camera smoothing com fade (mais lento perto do limite de range)
    local camAlpha = ExpDecay(CONFIG.CamSmoothRate * fadeMult, dt)
    Camera.CFrame = SafeLerp(Camera.CFrame, goalCF, camAlpha)

    -- FOV dinâmico
    local fovT = math.clamp((dist - CONFIG.FOVCloseDistance) / (CONFIG.FOVFarDistance - CONFIG.FOVCloseDistance), 0, 1)
    local targetFOV = CONFIG.FOVClose + (CONFIG.FOVFar - CONFIG.FOVClose) * fovT
    State.CurrentFOV = SafeLerp(State.CurrentFOV, targetFOV, ExpDecay(CONFIG.FOVSmoothRate, dt))
    Camera.FieldOfView = State.CurrentFOV

    UpdateTargetInfo()
end

-- ══════════════════════════════════════════════════════
-- CHARACTER SETUP
-- ══════════════════════════════════════════════════════
local function OnCharacter(char)
    ResetAimFriction()
    DisableAutoFace()

    State.Char = char
    State.Hum = char:WaitForChild("Humanoid", 10)
    State.Root = char:WaitForChild("HumanoidRootPart", 10)

    if not State.Hum or not State.Root then
        warn("[LockOn v5.1] Humanoid/RootPart não encontrado")
        return
    end

    if State.IsLocked then Unlock() end

    Conn("SelfDied", State.Hum.Died:Connect(function()
        State.PendingTarget = State.Target  -- salva pra re-lock
        DisableAutoFace()
        Unlock()
    end))

    task.delay(0.5, function()
        if State.Char == char then
            SetupHitDetection(char)
            SetupDamageDetection()

            -- Re-lock após respawn (se alvo ainda vivo e no range)
            if State.PendingTarget and Alive(State.PendingTarget) then
                if Dist(State.PendingTarget) <= CONFIG.MaxLockDistance then
                    LockOn(State.PendingTarget)
                end
            end
            State.PendingTarget = nil
        end
    end)
end

-- ══════════════════════════════════════════════════════
-- INPUT
-- ══════════════════════════════════════════════════════
UserInputService.InputBegan:Connect(function(input, processed)
    if processed then return end
    local key = input.KeyCode

    if key == CONFIG.LockKey or key == CONFIG.GamepadLock then
        if State.IsLocked then
            Unlock()
        else
            local t = FindBestTarget()
            if t then LockOn(t) end
        end

    elseif key == CONFIG.SoftLockKey then
        -- Toggle hard/soft
        State.LockMode = State.LockMode == "hard" and "soft" or "hard"
        if State.IsLocked then
            if State.LockMode == "hard" then
                Camera.CameraType = Enum.CameraType.Scriptable
            else
                Camera.CameraType = Enum.CameraType.Custom
            end
        end
        UpdateButtonVisual()

    elseif key == CONFIG.NextTargetKey or key == CONFIG.GamepadNext then
        CycleTarget(1)
    elseif key == CONFIG.PrevTargetKey then
        CycleTarget(-1)
    end
end)

-- Touch swipe
UserInputService.TouchStarted:Connect(function(touch, processed)
    if processed or not State.IsLocked then return end
    if touch.Position.Y < Camera.ViewportSize.Y * 0.4 then
        State.TouchStart = touch.Position
        State.TouchStartTime = tick()
    end
end)

UserInputService.TouchEnded:Connect(function(touch)
    if not State.TouchStart or not State.IsLocked then
        State.TouchStart = nil
        return
    end
    if tick() - State.TouchStartTime > CONFIG.SwipeTimeout then
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

    if LocalPlayer.Character then
        task.spawn(function() OnCharacter(LocalPlayer.Character) end)
    end
    LocalPlayer.CharacterAdded:Connect(OnCharacter)

    RunService.RenderStepped:Connect(UpdateCamera)

    LocalPlayer.AncestryChanged:Connect(function(_, parent)
        if not parent then
            ResetAimFriction()
            Unlock()
        end
    end)

    print("══════════════════════════════════════════════")
    print("  LOCK-ON SYSTEM v5.1 CHASE GRADE — ATIVO")
    print("  PC:     Q=Lock  E=Next  R=Prev  T=Soft/Hard")
    print("          Shift+Mouse = Orbital adjust")
    print("  Mobile: Arraste botão | ◀ ▶ | Swipe")
    print("  Gamepad: RB=Lock  RS=Cycle  RStick=Orbital")
    print("")
    print("  ✦ Auto-face com rotação suave")
    print("  ✦ Strafe natural (sem Hum:Move hack)")
    print("  ✦ Soft/Hard lock toggle")
    print("  ✦ Shoulder offset + Vertical aim")
    print("  ✦ Directional target switch")
    print("  ✦ Dampened sine shake")
    print("  ✦ Gradual unlock com fade")
    print("  ✦ Re-lock após respawn")
    print("══════════════════════════════════════════════")
end

Init()
