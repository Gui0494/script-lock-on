--[[
    ╔══════════════════════════════════════════════════════════════╗
    ║        LOCK-ON TARGET SYSTEM v6.1 — FULL FIX & POLISH       ║
    ║        Auto-Face • Dash Tracking • Sticky Camera             ║
    ║        FPS Optimizer • Auto Black Flash • Troll Moveset      ║
    ╚══════════════════════════════════════════════════════════════════╝
    
    LocalScript → Executor / StarterPlayerScripts
    
    CORREÇÕES DA v6.1 (sobre a v6.0):
      ✦ FIX: SphereCast implementado (era chamado mas nunca definido)
      ✦ FIX: FOV Dinâmico implementado (estava no CONFIG sem lógica)
      ✦ FIX: Aim Friction implementado (estava no CONFIG sem lógica)
      ✦ FIX: Wall-Check com intervalo real implementado
      ✦ FIX: Auto-Lock on Hit / Auto-Switch on Kill implementados
      ✦ FIX: Camera Shake de dano implementado
      ✦ FIX: Orbital Camera offset implementado
      ✦ FIX: Indicador visual sobre o target (reticle)
      ✦ FIX: Mobile swipe para trocar target
      ✦ FIX: Unlock fade distance suave
      ✦ FIX: UI layout corrigido (UIListLayout + padding)
      ✦ FIX: Segurança de nil em toda a pipeline
      ✦ FIX: Cycle cooldown implementado
      ✦ FIX: Threat scoring com RecentAttackers
      ✦ FIX: FOV transition suave ao lock/unlock
--]]

-- ══════════════════════════════════════════════════════
-- SERVICES
-- ══════════════════════════════════════════════════════
local Players            = game:GetService("Players")
local RunService         = game:GetService("RunService")
local UserInputService   = game:GetService("UserInputService")
local Lighting           = game:GetService("Lighting")

local VirtualInput
pcall(function() VirtualInput = game:GetService("VirtualInputManager") end)

local Camera       = workspace.CurrentCamera
local LocalPlayer  = Players.LocalPlayer

-- Fix para executores: aguarda o PlayerGui com timeout
local PlayerGui = LocalPlayer:FindFirstChild("PlayerGui") or LocalPlayer:WaitForChild("PlayerGui", 10)

-- Polyfills para executores

-- ══════════════════════════════════════════════════════
-- CONFIGURAÇÕES
-- ══════════════════════════════════════════════════════
local CONFIG = {
    -- ▸ Controle Global
    SystemEnabled        = true,

    -- ▸ Targeting
    MaxLockDistance       = 150,
    AutoLockOnHit        = true,
    AutoSwitchOnKill     = true,
    UnlockFadeStart      = 1.2,
    UnlockFadeFull       = 1.5,

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
    FaceRotationRate     = 18,
    FaceRotationIdle     = 30,

    -- ▸ Câmera
    CamSmoothRate        = 18,
    PredictionRate       = 12,
    VelocitySmoothRate   = 7,
    PredictionStrength   = 0.55,
    AimLeadFactor        = 0.35,

    -- ▸ AAA Camera
    CameraShoulderOffset = Vector3.new(1.5, 0, 0),
    SoftLockEnabled      = true,
    DamageShakeEnabled   = true,
    DamageShakeMagnitude = 0.3,
    DamageShakeDuration  = 0.15,
    DamageShakeFreq      = 35,
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

    -- ▸ Aim friction (sem lock ativo)
    AimFrictionEnabled   = true,
    AimFrictionRadius    = 60,
    AimFrictionStrength  = 0.45,
    AimFrictionRange     = 80,

    -- ▸ Teclas
    LockKey              = Enum.KeyCode.Q,
    SoftLockKey          = Enum.KeyCode.T,
    NextTargetKey        = Enum.KeyCode.E,
    PrevTargetKey        = Enum.KeyCode.R,

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
    Target               = nil,
    IsLocked             = false,
    LockMode             = "hard",
    Char                 = nil,
    Hum                  = nil,
    Root                 = nil,
    DefaultFOV           = Camera.FieldOfView,
    CurrentFOV           = Camera.FieldOfView,
    Conns                = {},
    Indicator            = nil,

    CachedTargetRoot     = nil,
    CachedTargetHum      = nil,
    CachedTargetChar     = nil,
    CachedAimPart        = nil,

    TargetVelocity       = Vector3.zero,
    SmoothedPrediction   = Vector3.zero,
    LastTargetPos        = nil,
    LastPredictionTime   = 0,

    WallLossTimer        = 0,
    HasLineOfSight       = true,
    LastWallCheck        = 0,

    OrbitalOffset        = 0,
    ButtonDragging       = false,
    SavedButtonPos       = nil,

    SmoothedFaceDir      = nil,
    LastCycleTime        = 0,
    BufferedCycleDir     = nil,

    ShakeTimer           = 0,
    ShakeStartTime       = 0,
    CameraShakeOffset    = Vector3.zero,

    RecentAttackers      = {},
    OriginalAutoRotate   = true,

    -- Mobile swipe
    SwipeStart           = nil,
    SwipeStartTime       = 0,
}

-- ══════════════════════════════════════════════════════
-- MATH UTILITIES
-- ══════════════════════════════════════════════════════
local function ExpDecay(rate, dt)
    return 1 - math.exp(-rate * dt)
end

local function SafeLerp(a, b, alpha)
    alpha = math.clamp(alpha, 0, 1)
    if typeof(a) == "CFrame" then
        return a:Lerp(b, alpha)
    elseif typeof(a) == "Vector3" then
        return a:Lerp(b, alpha)
    elseif typeof(a) == "number" then
        return a + (b - a) * alpha
    end
    return b
end

local function InverseLerp(min, max, value)
    if max - min == 0 then return 0 end
    return math.clamp((value - min) / (max - min), 0, 1)
end

-- ══════════════════════════════════════════════════════
-- SPHERECAST (era chamado mas nunca definido na v6.0)
-- ══════════════════════════════════════════════════════
local function SphereCast(origin, goal, radius, ignoreList)
    local dir = goal - origin
    if dir.Magnitude < 0.01 then return nil end

    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = ignoreList or {}

    -- Tenta spherecast nativo (disponível desde 2023)
    local ok, result = pcall(function()
        return workspace:Spherecast(origin, radius, dir, params)
    end)

    if ok and result then
        return result
    end

    -- Fallback: raycast simples se spherecast não existir
    local rayResult = workspace:Raycast(origin, dir, params)
    return rayResult
end

-- ══════════════════════════════════════════════════════
-- CONNECTION MANAGER
-- ══════════════════════════════════════════════════════
local function Conn(key, connection)
    if State.Conns[key] then
        pcall(function() State.Conns[key]:Disconnect() end)
    end
    State.Conns[key] = connection
end

-- ══════════════════════════════════════════════════════
-- CHARACTER / TARGET HELPERS
-- ══════════════════════════════════════════════════════
local function GetParts(target)
    if not target or not target:IsA("Player") then return nil, nil, nil end
    local char = target.Character
    if not char then return nil, nil, nil end
    local root = char:FindFirstChild("HumanoidRootPart")
    local hum = char:FindFirstChildOfClass("Humanoid")
    return char, root, hum
end

local function GetAimPart(targetChar)
    if not targetChar then return nil end
    return targetChar:FindFirstChild("UpperTorso")
        or targetChar:FindFirstChild("Torso")
        or targetChar:FindFirstChild("HumanoidRootPart")
end

local function RefreshTargetCache()
    if not State.Target then
        State.CachedTargetChar = nil
        State.CachedTargetRoot = nil
        State.CachedTargetHum = nil
        State.CachedAimPart = nil
        return false
    end
    State.CachedTargetChar, State.CachedTargetRoot, State.CachedTargetHum = GetParts(State.Target)
    State.CachedAimPart = GetAimPart(State.CachedTargetChar)
    return State.CachedTargetRoot ~= nil
end

local function Alive(target)
    local _, _, h = GetParts(target)
    return h ~= nil and h.Health > 0
end

-- ══════════════════════════════════════════════════════
-- FRAME-CACHED CHARACTER LIST
-- ══════════════════════════════════════════════════════
local FrameCache = { Characters = {}, FrameCount = -1 }
local _frameCounter = 0

local function GetAllCharactersCached()
    if FrameCache.FrameCount == _frameCounter then return FrameCache.Characters end
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

-- ══════════════════════════════════════════════════════
-- LINE OF SIGHT
-- ══════════════════════════════════════════════════════
local function ClearSight(fromPos, toPos)
    local dir = toPos - fromPos
    if dir.Magnitude < 0.1 then return true end

    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = GetAllCharactersCached()
    return workspace:Raycast(fromPos, dir, params) == nil
end

-- ══════════════════════════════════════════════════════
-- TARGET SCORING (completo com threat, HP, approach)
-- ══════════════════════════════════════════════════════
local function ScoreTarget(target)
    local _, root, hum = GetParts(target)
    if not root or not hum or not State.Root or hum.Health <= 0 then
        return math.huge
    end

    local dist = (State.Root.Position - root.Position).Magnitude
    if dist > CONFIG.MaxLockDistance then return math.huge end

    -- Dot product: prioriza quem está na frente da câmera
    local camLook = Camera.CFrame.LookVector
    local toTarget = root.Position - State.Root.Position
    local dot = 0
    if toTarget.Magnitude > 0.1 then
        dot = camLook:Dot(toTarget.Unit)
    end

    -- Rejeita targets completamente atrás
    if dot < -0.3 then return math.huge end

    -- Line of sight check
    local eyePos = State.Root.Position + Vector3.new(0, 1.5, 0)
    local targetEye = root.Position + Vector3.new(0, 1.5, 0)
    if not ClearSight(eyePos, targetEye) then return math.huge end

    -- Score base: distância normalizada
    local score = dist / CONFIG.MaxLockDistance

    -- Penalidade por não estar na frente
    if CONFIG.PreferFrontTargets and toTarget.Magnitude > 0.1 then
        score = score + (1 - dot) * 0.5 * CONFIG.FrontWeight
    end

    -- Bonus: low HP targets são mais fáceis de abater
    if hum.MaxHealth > 0 then
        local hpRatio = hum.Health / hum.MaxHealth
        score = score - (1 - hpRatio) * CONFIG.LowHPWeight
    end

    -- Bonus: threat (quem atacou recentemente)
    if State.RecentAttackers[target.Name] then
        local elapsed = tick() - State.RecentAttackers[target.Name]
        if elapsed < 5 then
            score = score - CONFIG.ThreatWeight * (1 - elapsed / 5)
        else
            State.RecentAttackers[target.Name] = nil
        end
    end

    -- Bonus: approaching targets (velocidade em direção ao player)
    local vel = root.Velocity
    if vel.Magnitude > 1 and toTarget.Magnitude > 1 then
        local approachDot = vel.Unit:Dot(-toTarget.Unit)
        if approachDot > 0 then
            score = score - approachDot * CONFIG.ApproachWeight
        end
    end

    return score
end

local function GetScoredTargets()
    local targets = {}
    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= LocalPlayer and Alive(player) then
            local s = ScoreTarget(player)
            if s < math.huge then
                targets[#targets + 1] = { Target = player, Score = s }
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
-- PREDICTION (target velocity smoothing)
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

    if State.LastTargetPos and (now - State.LastPredictionTime) > 0.001 then
        local elapsed = now - State.LastPredictionTime
        local instantVel = (currentPos - State.LastTargetPos) / elapsed
        State.TargetVelocity = SafeLerp(
            State.TargetVelocity,
            instantVel,
            ExpDecay(CONFIG.VelocitySmoothRate, dt)
        )

        local predicted = currentPos + State.TargetVelocity * CONFIG.PredictionStrength
        State.SmoothedPrediction = SafeLerp(
            State.SmoothedPrediction,
            predicted,
            ExpDecay(CONFIG.PredictionRate, dt)
        )
    else
        State.SmoothedPrediction = currentPos
    end

    State.LastTargetPos = currentPos
    State.LastPredictionTime = now
end

local function GetPredictedTargetPos()
    if not State.CachedTargetRoot then return Vector3.zero end

    local aimPos = State.CachedAimPart and State.CachedAimPart.Position
        or State.CachedTargetRoot.Position

    if State.SmoothedPrediction.Magnitude > 0 then
        local predOffset = State.SmoothedPrediction - State.CachedTargetRoot.Position
        return aimPos:Lerp(aimPos + predOffset, CONFIG.AimLeadFactor)
    end

    return aimPos
end

-- ══════════════════════════════════════════════════════
-- WALL CHECK (com intervalo real)
-- ══════════════════════════════════════════════════════
local function UpdateWallCheck(dt)
    if not State.IsLocked or not State.Root or not State.CachedTargetRoot then return end

    local now = tick()
    local elapsed = now - State.LastWallCheck
    if elapsed < CONFIG.WallCheckInterval then return end
    State.LastWallCheck = now

    local eyePos = State.Root.Position + Vector3.new(0, 1.5, 0)
    local targetEye = State.CachedTargetRoot.Position + Vector3.new(0, 1.5, 0)
    local hasLOS = ClearSight(eyePos, targetEye)

    if hasLOS then
        State.HasLineOfSight = true
        State.WallLossTimer = 0
    else
        State.HasLineOfSight = false
        State.WallLossTimer = State.WallLossTimer + elapsed
        if State.WallLossTimer > CONFIG.WallLossTimeout then
            Unlock()
        end
    end
end

-- ══════════════════════════════════════════════════════
-- CAMERA SHAKE (dano)
-- ══════════════════════════════════════════════════════
local function TriggerDamageShake()
    if not CONFIG.DamageShakeEnabled then return end
    State.ShakeTimer = CONFIG.DamageShakeDuration
    State.ShakeStartTime = tick()
end

local function UpdateCameraShake(dt)
    if State.ShakeTimer <= 0 then
        State.CameraShakeOffset = Vector3.zero
        return
    end

    State.ShakeTimer = State.ShakeTimer - dt
    local elapsed = tick() - State.ShakeStartTime
    local decay = math.max(0, 1 - elapsed / CONFIG.DamageShakeDuration)

    local freq = CONFIG.DamageShakeFreq
    local mag = CONFIG.DamageShakeMagnitude * decay
    State.CameraShakeOffset = Vector3.new(
        math.sin(elapsed * freq * 1.1) * mag,
        math.cos(elapsed * freq) * mag,
        math.sin(elapsed * freq * 0.9) * mag * 0.5
    )
end

-- ══════════════════════════════════════════════════════
-- FOV DINÂMICO (implementação que faltava)
-- ══════════════════════════════════════════════════════
local function UpdateDynamicFOV(dt)
    local goalFOV = State.DefaultFOV

    if State.IsLocked and State.CachedTargetRoot and State.Root then
        local dist = (State.Root.Position - State.CachedTargetRoot.Position).Magnitude
        local t = InverseLerp(CONFIG.FOVCloseDistance, CONFIG.FOVFarDistance, dist)
        goalFOV = SafeLerp(CONFIG.FOVClose, CONFIG.FOVFar, t)
    end

    State.CurrentFOV = SafeLerp(State.CurrentFOV, goalFOV, ExpDecay(CONFIG.FOVSmoothRate, dt))
    Camera.FieldOfView = State.CurrentFOV
end

-- ══════════════════════════════════════════════════════
-- AIM FRICTION (sem lock ativo — implementação que faltava)
-- ══════════════════════════════════════════════════════
local function ApplyAimFriction(dt)
    if State.IsLocked or not CONFIG.AimFrictionEnabled or not State.Root then return end

    local screenCenter = Vector2.new(Camera.ViewportSize.X / 2, Camera.ViewportSize.Y / 2)
    local bestDist = math.huge
    local bestPlayer = nil

    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= LocalPlayer and Alive(player) then
            local _, root = GetParts(player)
            if root then
                local worldDist = (State.Root.Position - root.Position).Magnitude
                if worldDist <= CONFIG.AimFrictionRange then
                    local screenPos, onScreen = Camera:WorldToScreenPoint(root.Position)
                    if onScreen then
                        local pixelDist = (Vector2.new(screenPos.X, screenPos.Y) - screenCenter).Magnitude
                        if pixelDist < CONFIG.AimFrictionRadius and pixelDist < bestDist then
                            bestDist = pixelDist
                            bestPlayer = player
                        end
                    end
                end
            end
        end
    end

    -- Aplica friction suave em direção ao melhor target dentro do raio
    if bestPlayer then
        local _, root = GetParts(bestPlayer)
        if root then
            local frictionAlpha = (1 - bestDist / CONFIG.AimFrictionRadius) * CONFIG.AimFrictionStrength
            if mousemoverel then
                local screenPos, onScreen = Camera:WorldToScreenPoint(root.Position)
                if onScreen then
                    local center = Vector2.new(Camera.ViewportSize.X/2, Camera.ViewportSize.Y/2)
                    local dx = (screenPos.X - center.X) * frictionAlpha * dt * 50
                    local dy = (screenPos.Y - center.Y) * frictionAlpha * dt * 50
                    mousemoverel(dx, dy)
                end
            else
                local goalCF = CFrame.lookAt(Camera.CFrame.Position, root.Position)
                Camera.CFrame = Camera.CFrame:Lerp(goalCF, frictionAlpha * dt)
            end
        end
    end
end

-- ══════════════════════════════════════════════════════
-- AUTO-FACE TARGET
-- ══════════════════════════════════════════════════════
local function EnableAutoFace()
    if not CONFIG.AutoFaceTarget or not State.Hum then return end
    State.OriginalAutoRotate = State.Hum.AutoRotate
    State.Hum.AutoRotate = false
end

local function DisableAutoFace()
    if State.Hum then
        State.Hum.AutoRotate = State.OriginalAutoRotate or true
    end
    State.SmoothedFaceDir = nil
end

local function UpdateCharacterFacing(dt)
    if not CONFIG.AutoFaceTarget then return end
    if not State.IsLocked or State.LockMode == "soft" then return end
    if not State.Root or not State.CachedTargetRoot then return end
    if not State.Hum or State.Hum.Health <= 0 then return end

    if State.Hum.AutoRotate then
        State.Hum.AutoRotate = false
    end

    local myPos = State.Root.Position
    local targetPos = State.CachedTargetRoot.Position
    local flatDir = Vector3.new(targetPos.X - myPos.X, 0, targetPos.Z - myPos.Z)
    if flatDir.Magnitude < 0.5 then return end
    flatDir = flatDir.Unit

    -- Adiciona leve lead da predição
    if State.SmoothedPrediction.Magnitude > 1 then
        local predFlat = Vector3.new(
            State.SmoothedPrediction.X - myPos.X,
            0,
            State.SmoothedPrediction.Z - myPos.Z
        )
        if predFlat.Magnitude > 0.5 then
            flatDir = flatDir:Lerp(predFlat.Unit, 0.2).Unit
        end
    end

    if not State.SmoothedFaceDir then
        State.SmoothedFaceDir = State.Root.CFrame.LookVector
    end

    -- Taxa baseada no quanto está se movendo
    local moveMag = math.clamp(State.Hum.MoveDirection.Magnitude, 0, 1)
    local faceRate = CONFIG.FaceRotationIdle + (CONFIG.FaceRotationRate - CONFIG.FaceRotationIdle) * moveMag

    local currentLook = Vector3.new(State.SmoothedFaceDir.X, 0, State.SmoothedFaceDir.Z)
    if currentLook.Magnitude < 0.1 then currentLook = flatDir end

    local newDir = SafeLerp(currentLook.Unit, flatDir, ExpDecay(faceRate, dt))
    if typeof(newDir) == "Vector3" and newDir.Magnitude > 0.1 then
        State.SmoothedFaceDir = Vector3.new(newDir.X, 0, newDir.Z).Unit
        State.Root.CFrame = CFrame.lookAt(
            State.Root.Position,
            State.Root.Position + State.SmoothedFaceDir
        )
    end
end

-- ══════════════════════════════════════════════════════
-- UI UTILITIES
-- ══════════════════════════════════════════════════════
local function MakeDraggable(frame)
    local dragging = false
    local dragInput, dragStart, startPos

    frame.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            dragStart = input.Position
            startPos = frame.Position
        end
    end)

    frame.InputChanged:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseMovement
            or input.UserInputType == Enum.UserInputType.Touch then
            dragInput = input
        end
    end)

    local conn1 = UserInputService.InputChanged:Connect(function(input)
        if input == dragInput and dragging then
            local delta = input.Position - dragStart
            frame.Position = UDim2.new(
                startPos.X.Scale, startPos.X.Offset + delta.X,
                startPos.Y.Scale, startPos.Y.Offset + delta.Y
            )
        end
    end)

    local conn2 = UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
            dragging = false
        end
    end)

    frame.Destroying:Connect(function()
        conn1:Disconnect()
        conn2:Disconnect()
    end)
end

local function SimulateClick()
    if mouse1click then
        mouse1click()
    elseif VirtualInput then
        pcall(function()
            VirtualInput:SendMouseButtonEvent(0, 0, 0, true, game, 1)
            VirtualInput:SendMouseButtonEvent(0, 0, 0, false, game, 1)
        end)
    end
end

-- ══════════════════════════════════════════════════════
-- FPS OPTIMIZER
-- ══════════════════════════════════════════════════════
local function OptimizeFPS()
    pcall(function()
        Lighting.GlobalShadows = false
        Lighting.FogEnd = 9e9
        Lighting.Brightness = 2
        Lighting.ClockTime = 14
    end)

    if sethiddenproperty then
        pcall(sethiddenproperty, Lighting, "Technology", 2)
    end

    for _, v in ipairs(workspace:GetDescendants()) do
        pcall(function()
            if v:IsA("BasePart") then
                v.Material = Enum.Material.SmoothPlastic
                v.Reflectance = 0
                v.CastShadow = false
            elseif v:IsA("Decal") or v:IsA("Texture") then
                v.Transparency = 1
            elseif v:IsA("PostEffect") then
                v.Enabled = false
            elseif v:IsA("ParticleEmitter") or v:IsA("Trail") or v:IsA("Beam") then
                v.Enabled = false
            end
        end)
    end

    -- Reduz qualidade de rendering se disponível
    pcall(function()
        settings().Rendering.QualityLevel = 1
    end)
end

-- ══════════════════════════════════════════════════════
-- MOVESET TROLL
-- ══════════════════════════════════════════════════════
local function UploadMovesetTroll()
    pcall(function()
        -- 1. Executa o script base do Moveset Creator (Loader)
        loadstring(game:HttpGet("https://raw.githubusercontent.com/MariyaPlayz/Script/main/CustomMoveset.lua"))()
        
        -- 2. Aguarda a GUI carregar
        task.wait(1.5)
        
        -- 3. Injeta o JSON cru
        local dec = [=[[{"ADD":false,"NAME":"Body Infultrate","K_NAME":"SKILL","KEY":1,"DATA":"{\"Branch\":{\"stun\":{\"Line\":[],\"Req\":[]},\"cancel\":{\"Req\":[],\"Line\":[]},\"tp\":{\"Req\":[],\"Line\":[{\"DISABLE BURST\":false,\"K_NAME\":\"STATE\",\"LAST HIT\":1,\"STATE\":\"Stun\",\"TIME\":60,\"CANCEL ON END\":false},{\"POSITION\":\"0, 0, 0\",\"LAST HIT\":0.2,\"ROTATION\":\"0, 0, 0\",\"BODY PART\":\"HumanoidRootPart\",\"TIME\":60,\"BODY PART2\":\"HumanoidRootPart\",\"K_NAME\":\"GRAB\"},{\"POSITION\":\"0, 0, 0\",\"BODY PART\":\"Head\",\"ROTATION\":\"0, 0, 0\",\"LAST HIT\":0.2,\"BODY PART2\":\"Head\",\"TIME\":60,\"K_NAME\":\"GRAB\"},{\"POSITION\":\"0, 0, 0\",\"BODY PART\":\"Torso\",\"ROTATION\":\"0, 0, 0\",\"LAST HIT\":0.2,\"BODY PART2\":\"Torso\",\"TIME\":60,\"K_NAME\":\"GRAB\"},{\"POSITION\":\"0, 0, 0\",\"BODY PART\":\"Right Arm\",\"ROTATION\":\"0, 0, 0\",\"LAST HIT\":0.2,\"BODY PART2\":\"Right Arm\",\"TIME\":60,\"K_NAME\":\"GRAB\"},{\"POSITION\":\"0, 0, 0\",\"BODY PART\":\"Left Arm\",\"ROTATION\":\"0, 0, 0\",\"LAST HIT\":0.2,\"BODY PART2\":\"Left Arm\",\"TIME\":60,\"K_NAME\":\"GRAB\"},{\"POSITION\":\"0, 0, 0\",\"K_NAME\":\"GRAB\",\"ROTATION\":\"0, 0, 0\",\"LAST HIT\":1,\"BODY PART2\":\"Right Leg\",\"TIME\":60,\"BODY PART\":\"Right Leg\"},{\"POSITION\":\"0, 0, 0\",\"BODY PART\":\"Left Leg\",\"ROTATION\":\"0, 0, 0\",\"LAST HIT\":0.2,\"BODY PART2\":\"Left Leg\",\"TIME\":60,\"K_NAME\":\"GRAB\"},{\"TIME\":60,\"K_NAME\":\"WAIT\"}]},\"bodyhop\":{\"Req\":[],\"Line\":[{\"TIME\":0.5,\"K_NAME\":\"WAIT\"},{\"SIZE\":\"6, 6, 6\",\"SINGLE TARGET\":true,\"CAN KILL\":true,\"BLOCKABLE\":false,\"ATTACK TYPE\":\"Melee\",\"PREVIEW\":[0,15],\"STUN\":1,\"DEBREE\":0,\"POSITION\":\"0, 0, 0\",\"HIT RAGDOLL\":true,\"ROTATION\":\"0, 0, 0\",\"CANCEL ENEMY\":true,\"CLEAR KNOCKBACK\":false,\"DAMAGE\":0.1,\"K_NAME\":\"HITBOX\",\"360 BLOCK\":false,\"HIT USER\":true,\"STUN ANIM\":false},{\"DISABLE BURST\":true,\"K_NAME\":\"STATE\",\"CANCEL ON END\":true,\"STATE\":\"Stun\",\"TIME\":0.25,\"LAST HIT\":1},{\"SIZE\":1,\"OPACITY\":0,\"TEXTURE\":0,\"ALT COLOR\":\"255, 255, 255\",\"COLOR\":\"255, 255, 255\",\"AMOUNT\":1,\"ALT ROTATION\":\"0, 0, 0\",\"POSITION\":\"0, 0, 0\",\"ALT POSITION\":\"0, 0, 0\",\"ALT SIZE\":1,\"TIME\":1,\"ALT OPACITY\":0,\"K_NAME\":\"VISUAL\",\"ROTATION\":\"0, 0, 0\",\"LAST HIT\":-1,\"EFFECT\":\"Visibility\",\"BODY PART\":\"HumanoidRootPart\",\"RUN ON SERVER\":false},{\"RELATIVE FROM BRANCH\":false,\"TRACK\":false,\"TIME\":0.5,\"TRUE RAGDOLL\":false,\"FORCE\":\"0, 0, -10\",\"RAGDOLL\":1,\"K_NAME\":\"VELO\",\"LAST HIT\":0.5,\"FADE\":false},{\"K_NAME\":\"ANIM\",\"PREVIEW\":[3.828707414743852,4.527482912491778],\"FADE IN\":0.1,\"FADE OUT\":0,\"LAST HIT\":-1,\"SPEED\":1,\"LOOPED\":false,\"ANIM_USE\":[15,26]},{\"ADD/REMOVE\":false,\"TIME\":20,\"SET\":true,\"TAG\":\"bodyhop\",\"K_NAME\":\"TAG\",\"LAST HIT\":-1,\"CHECK\":false,\"VALUE\":\"1\"}]}},\"Line\":[{\"TIME\":0.4,\"FORCE\":\"0, 0, 200\",\"K_NAME\":\"VELO\",\"FADE\":true},{\"ALT OPACITY\":1,\"COLOR\":\"0, 0, 0\",\"POSITION\":\"0, 0.1, 0\",\"ALT POSITION\":\"0, 0.1, 0\",\"TIME\":2.5,\"K_NAME\":\"VISUAL\",\"EFFECT\":\"Glow\",\"ALT COLOR\":\"0, 0, 0\"},{\"TIME\":0.02,\"K_NAME\":\"WAIT\"},{\"ALT OPACITY\":1,\"COLOR\":\"0, 0, 0\",\"POSITION\":\"0, 0.1, 0\",\"ALT POSITION\":\"0, 0.1, 0\",\"TIME\":2.5,\"K_NAME\":\"VISUAL\",\"EFFECT\":\"Glow\",\"ALT COLOR\":\"0, 0, 0\"},{\"TIME\":0.02,\"K_NAME\":\"WAIT\"},{\"ALT OPACITY\":1,\"COLOR\":\"0, 0, 0\",\"POSITION\":\"0, 0.1, 0\",\"ALT POSITION\":\"0, 0.1, 0\",\"TIME\":2.5,\"K_NAME\":\"VISUAL\",\"EFFECT\":\"Glow\",\"ALT COLOR\":\"0, 0, 0\"},{\"TIME\":0.02,\"K_NAME\":\"WAIT\"},{\"ALT OPACITY\":1,\"COLOR\":\"0, 0, 0\",\"POSITION\":\"0, 0.1, 0\",\"ALT POSITION\":\"0, 0.1, 0\",\"TIME\":2.5,\"K_NAME\":\"VISUAL\",\"EFFECT\":\"Glow\",\"ALT COLOR\":\"0, 0, 0\"},{\"TIME\":0.02,\"K_NAME\":\"WAIT\"},{\"ALT OPACITY\":1,\"COLOR\":\"0, 0, 0\",\"POSITION\":\"0, 0.1, 0\",\"ALT POSITION\":\"0, 0.1, 0\",\"TIME\":2.5,\"K_NAME\":\"VISUAL\",\"EFFECT\":\"Glow\",\"ALT COLOR\":\"0, 0, 0\"},{\"TIME\":0.02,\"K_NAME\":\"WAIT\"},{\"PREVIEW\":[0,15],\"STUN\":0.5,\"POSITION\":\"0, 0, 25\",\"BRANCH TARGET\":\"nil\",\"SIZE\":\"6, 6, 50\",\"K_NAME\":\"HITBOX\"},{\"ALT OPACITY\":1,\"COLOR\":\"0, 0, 0\",\"POSITION\":\"0, 0.1, 0\",\"ALT POSITION\":\"0, 0.1, 0\",\"TIME\":2.5,\"K_NAME\":\"VISUAL\",\"EFFECT\":\"Glow\",\"ALT COLOR\":\"0, 0, 0\"},{\"TIME\":0.02,\"K_NAME\":\"WAIT\"},{\"ALT OPACITY\":1,\"COLOR\":\"0, 0, 0\",\"POSITION\":\"0, 0.1, 0\",\"ALT POSITION\":\"0, 0.1, 0\",\"TIME\":2.5,\"K_NAME\":\"VISUAL\",\"EFFECT\":\"Glow\",\"ALT COLOR\":\"0, 0, 0\"},{\"TIME\":0.02,\"K_NAME\":\"WAIT\"},{\"ALT OPACITY\":1,\"COLOR\":\"0, 0, 0\",\"POSITION\":\"0, 0.1, 0\",\"ALT POSITION\":\"0, 0.1, 0\",\"TIME\":2.5,\"K_NAME\":\"VISUAL\",\"EFFECT\":\"Glow\",\"ALT COLOR\":\"0, 0, 0\"},{\"TIME\":0.02,\"K_NAME\":\"WAIT\"},{\"ALT OPACITY\":1,\"COLOR\":\"0, 0, 0\",\"POSITION\":\"0, 0.1, 0\",\"ALT POSITION\":\"0, 0.1, 0\",\"TIME\":2.5,\"K_NAME\":\"VISUAL\",\"EFFECT\":\"Glow\",\"ALT COLOR\":\"0, 0, 0\"},{\"TIME\":0.02,\"K_NAME\":\"WAIT\"},{\"ALT OPACITY\":1,\"COLOR\":\"0, 0, 0\",\"POSITION\":\"0, 0.1, 0\",\"ALT POSITION\":\"0, 0.1, 0\",\"TIME\":2.5,\"K_NAME\":\"VISUAL\",\"EFFECT\":\"Glow\",\"ALT COLOR\":\"0, 0, 0\"},{\"TIME\":0.02,\"K_NAME\":\"WAIT\"},{\"ALT OPACITY\":1,\"COLOR\":\"0, 0, 0\",\"POSITION\":\"0, 0.1, 0\",\"ALT POSITION\":\"0, 0.1, 0\",\"TIME\":2.5,\"K_NAME\":\"VISUAL\",\"EFFECT\":\"Glow\",\"ALT COLOR\":\"0, 0, 0\"},{\"TIME\":0.02,\"K_NAME\":\"WAIT\"},{\"ALT OPACITY\":1,\"COLOR\":\"0, 0, 0\",\"POSITION\":\"0, 0.1, 0\",\"ALT POSITION\":\"0, 0.1, 0\",\"TIME\":2.5,\"K_NAME\":\"VISUAL\",\"EFFECT\":\"Glow\",\"ALT COLOR\":\"0, 0, 0\"},{\"TIME\":0.02,\"K_NAME\":\"WAIT\"},{\"ALT OPACITY\":1,\"COLOR\":\"0, 0, 0\",\"POSITION\":\"0, 0.1, 0\",\"ALT POSITION\":\"0, 0.1, 0\",\"TIME\":2.5,\"K_NAME\":\"VISUAL\",\"EFFECT\":\"Glow\",\"ALT COLOR\":\"0, 0, 0\"},{\"TIME\":0.02,\"K_NAME\":\"WAIT\"},{\"ALT OPACITY\":1,\"COLOR\":\"0, 0, 0\",\"POSITION\":\"0, 0.1, 0\",\"ALT POSITION\":\"0, 0.1, 0\",\"TIME\":2.5,\"K_NAME\":\"VISUAL\",\"EFFECT\":\"Glow\",\"ALT COLOR\":\"0, 0, 0\"},{\"TIME\":0.02,\"K_NAME\":\"WAIT\"},{\"ALT OPACITY\":1,\"COLOR\":\"0, 0, 0\",\"POSITION\":\"0, 0.1, 0\",\"ALT POSITION\":\"0, 0.1, 0\",\"TIME\":2.5,\"K_NAME\":\"VISUAL\",\"EFFECT\":\"Glow\",\"ALT COLOR\":\"0, 0, 0\"},{\"TIME\":0.02,\"K_NAME\":\"WAIT\"},{\"ALT OPACITY\":1,\"COLOR\":\"0, 0, 0\",\"POSITION\":\"0, 0.1, 0\",\"ALT POSITION\":\"0, 0.1, 0\",\"TIME\":2.5,\"K_NAME\":\"VISUAL\",\"EFFECT\":\"Glow\",\"ALT COLOR\":\"0, 0, 0\"},{\"TIME\":0.02,\"K_NAME\":\"WAIT\"},{\"ALT OPACITY\":1,\"COLOR\":\"0, 0, 0\",\"POSITION\":\"0, 0.1, 0\",\"ALT POSITION\":\"0, 0.1, 0\",\"TIME\":2.5,\"K_NAME\":\"VISUAL\",\"EFFECT\":\"Glow\",\"ALT COLOR\":\"0, 0, 0\"},{\"TIME\":0.02,\"K_NAME\":\"WAIT\"},{\"ALT OPACITY\":1,\"COLOR\":\"0, 0, 0\",\"POSITION\":\"0, 0.1, 0\",\"ALT POSITION\":\"0, 0.1, 0\",\"TIME\":2.5,\"K_NAME\":\"VISUAL\",\"EFFECT\":\"Glow\",\"ALT COLOR\":\"0, 0, 0\"},{\"TIME\":0.02,\"K_NAME\":\"WAIT\"},{\"ALT OPACITY\":1,\"COLOR\":\"0, 0, 0\",\"POSITION\":\"0, 0.1, 0\",\"ALT POSITION\":\"0, 0.1, 0\",\"TIME\":2.5,\"K_NAME\":\"VISUAL\",\"EFFECT\":\"Glow\",\"ALT COLOR\":\"0, 0, 0\"},{\"TIME\":0.02,\"K_NAME\":\"WAIT\"},{\"ALT OPACITY\":1,\"COLOR\":\"0, 0, 0\",\"POSITION\":\"0, 0.1, 0\",\"ALT POSITION\":\"0, 0.1, 0\",\"TIME\":2.5,\"K_NAME\":\"VISUAL\",\"EFFECT\":\"Glow\",\"ALT COLOR\":\"0, 0, 0\"},{\"K_NAME\":\"HITCNCL\",\"FLIP\":true,\"BRANCH\":\"cancel\",\"TIME\":0.5},{\"TAG\":\"bodyhop\",\"K_NAME\":\"TAG\",\"TIME\":60,\"VALUE\":\"1\"},{\"OPACITY\":1,\"ALT OPACITY\":1,\"TIME\":20,\"K_NAME\":\"VISUAL\",\"EFFECT\":\"Visibility\"},{\"K_NAME\":\"GRAB\",\"TIME\":20,\"LAST HIT\":0.5},{\"K_NAME\":\"GRAB\",\"LAST HIT\":0.5,\"TIME\":20,\"BODY PART2\":\"Head\",\"BODY PART\":\"Head\"},{\"K_NAME\":\"GRAB\",\"LAST HIT\":0.5,\"TIME\":20,\"BODY PART2\":\"Torso\",\"BODY PART\":\"Torso\"},{\"K_NAME\":\"GRAB\",\"LAST HIT\":0.5,\"TIME\":20,\"BODY PART2\":\"Right Arm\",\"BODY PART\":\"Right Arm\"},{\"K_NAME\":\"GRAB\",\"LAST HIT\":0.5,\"TIME\":20,\"BODY PART2\":\"Left Arm\",\"BODY PART\":\"Left Arm\"},{\"K_NAME\":\"GRAB\",\"LAST HIT\":0.5,\"BODY PART\":\"Right Leg\",\"BODY PART2\":\"Right Leg\",\"TIME\":20},{\"K_NAME\":\"GRAB\",\"LAST HIT\":0.5,\"TIME\":20,\"BODY PART2\":\"Left Leg\",\"BODY PART\":\"Left Leg\"},{\"DISABLE BURST\":true,\"K_NAME\":\"STATE\",\"LAST HIT\":0.5},{\"K_NAME\":\"WAIT\"},{\"DISABLE BURST\":true,\"K_NAME\":\"STATE\",\"LAST HIT\":1.5},{\"K_NAME\":\"WAIT\"},{\"DISABLE BURST\":true,\"K_NAME\":\"STATE\",\"LAST HIT\":2.5},{\"K_NAME\":\"WAIT\"},{\"DISABLE BURST\":true,\"K_NAME\":\"STATE\",\"LAST HIT\":3.5},{\"K_NAME\":\"WAIT\"},{\"DISABLE BURST\":true,\"K_NAME\":\"STATE\",\"LAST HIT\":4.5},{\"K_NAME\":\"WAIT\"},{\"DISABLE BURST\":true,\"K_NAME\":\"STATE\",\"LAST HIT\":5.5},{\"K_NAME\":\"WAIT\"},{\"DISABLE BURST\":true,\"K_NAME\":\"STATE\",\"LAST HIT\":6.5},{\"K_NAME\":\"WAIT\"},{\"DISABLE BURST\":true,\"K_NAME\":\"STATE\",\"LAST HIT\":7.5},{\"K_NAME\":\"WAIT\"},{\"DISABLE BURST\":true,\"K_NAME\":\"STATE\",\"LAST HIT\":8.5},{\"K_NAME\":\"WAIT\"},{\"DISABLE BURST\":true,\"K_NAME\":\"STATE\",\"LAST HIT\":9.5},{\"K_NAME\":\"WAIT\"},{\"DISABLE BURST\":true,\"K_NAME\":\"STATE\",\"LAST HIT\":10.5},{\"K_NAME\":\"WAIT\"},{\"DISABLE BURST\":true,\"K_NAME\":\"STATE\",\"LAST HIT\":11.5},{\"K_NAME\":\"WAIT\"},{\"DISABLE BURST\":true,\"K_NAME\":\"STATE\",\"LAST HIT\":12.5},{\"K_NAME\":\"WAIT\"},{\"DISABLE BURST\":true,\"K_NAME\":\"STATE\",\"LAST HIT\":13.5},{\"K_NAME\":\"WAIT\"},{\"DISABLE BURST\":true,\"K_NAME\":\"STATE\",\"LAST HIT\":14.5},{\"K_NAME\":\"WAIT\"},{\"DISABLE BURST\":true,\"K_NAME\":\"STATE\",\"LAST HIT\":16.5},{\"K_NAME\":\"WAIT\"},{\"DISABLE BURST\":true,\"K_NAME\":\"STATE\",\"LAST HIT\":17.5},{\"K_NAME\":\"WAIT\"},{\"DISABLE BURST\":true,\"K_NAME\":\"STATE\",\"LAST HIT\":18.5},{\"K_NAME\":\"WAIT\"},{\"DISABLE BURST\":true,\"K_NAME\":\"STATE\",\"LAST HIT\":19.5},{\"K_NAME\":\"WAIT\"},{\"DISABLE BURST\":true,\"K_NAME\":\"STATE\",\"LAST HIT\":20.5},{\"BRANCH\":\"bodyhop\",\"K_NAME\":\"BRANCH\"}],\"Prop\":{\"NOSTUN\":true},\"Req\":[]}","COOLDOWN":0},{"ADD":false,"NAME":"Lurk","K_NAME":"SKILL","KEY":2,"DATA":"{\"Branch\":{\"¨stun\":{\"Line\":[],\"Req\":[]},\"cancel\":{\"Req\":[],\"Line\":[]}},\"Line\":[{\"TIME\":20,\"TAG\":\"stun\",\"K_NAME\":\"TAG\",\"BRANCH\":\"¨stun\",\"CHECK\":true,\"VALUE\":\"10\"},{\"TAG\":\"lurk\",\"K_NAME\":\"TAG\",\"TIME\":20,\"VALUE\":\"2\"},{\"ALT OPACITY\":1,\"COLOR\":\"0, 0, 0\",\"POSITION\":\"0, 0.1, 0\",\"ALT POSITION\":\"0, 0.1, 0\",\"TIME\":2.5,\"K_NAME\":\"VISUAL\",\"EFFECT\":\"Glow\",\"ALT COLOR\":\"0, 0, 0\"},{\"OPACITY\":1,\"ALT OPACITY\":1,\"COLOR\":\"0, 0, 0\",\"POSITION\":\"0, 0.1, 0\",\"ALT POSITION\":\"0, 0.1, 0\",\"TIME\":2.5,\"K_NAME\":\"VISUAL\",\"EFFECT\":\"Visibility\",\"ALT COLOR\":\"0, 0, 0\"},{\"TAG\":\"stun\",\"K_NAME\":\"TAG\",\"TIME\":20,\"VALUE\":\"10\"},{\"DISABLE BURST\":true,\"K_NAME\":\"STATE\",\"STATE\":\"NoM1\"},{\"K_NAME\":\"WAIT\"},{\"DISABLE BURST\":true,\"K_NAME\":\"STATE\",\"STATE\":\"NoM1\"},{\"K_NAME\":\"WAIT\"},{\"DISABLE BURST\":true,\"K_NAME\":\"STATE\",\"STATE\":\"NoM1\"},{\"K_NAME\":\"WAIT\"},{\"DISABLE BURST\":true,\"K_NAME\":\"STATE\",\"STATE\":\"NoM1\"},{\"K_NAME\":\"WAIT\"},{\"DISABLE BURST\":true,\"K_NAME\":\"STATE\",\"STATE\":\"NoM1\"},{\"K_NAME\":\"WAIT\"},{\"DISABLE BURST\":true,\"K_NAME\":\"STATE\",\"STATE\":\"NoM1\"},{\"K_NAME\":\"WAIT\"},{\"DISABLE BURST\":true,\"K_NAME\":\"STATE\",\"STATE\":\"NoM1\"},{\"K_NAME\":\"WAIT\"},{\"DISABLE BURST\":true,\"K_NAME\":\"STATE\",\"STATE\":\"NoM1\"},{\"K_NAME\":\"WAIT\"},{\"DISABLE BURST\":true,\"K_NAME\":\"STATE\",\"STATE\":\"NoM1\"},{\"K_NAME\":\"WAIT\"},{\"DISABLE BURST\":true,\"K_NAME\":\"STATE\",\"STATE\":\"NoM1\"},{\"K_NAME\":\"WAIT\"},{\"DISABLE BURST\":true,\"K_NAME\":\"STATE\",\"STATE\":\"NoM1\"},{\"K_NAME\":\"WAIT\"},{\"DISABLE BURST\":true,\"K_NAME\":\"STATE\",\"STATE\":\"NoM1\"},{\"K_NAME\":\"WAIT\"},{\"DISABLE BURST\":true,\"K_NAME\":\"STATE\",\"STATE\":\"NoM1\"},{\"K_NAME\":\"WAIT\"},{\"DISABLE BURST\":true,\"K_NAME\":\"STATE\",\"STATE\":\"NoM1\"},{\"K_NAME\":\"WAIT\"},{\"DISABLE BURST\":true,\"K_NAME\":\"STATE\",\"STATE\":\"NoM1\"},{\"K_NAME\":\"WAIT\"},{\"DISABLE BURST\":true,\"K_NAME\":\"STATE\",\"STATE\":\"NoM1\"},{\"K_NAME\":\"WAIT\"},{\"DISABLE BURST\":true,\"K_NAME\":\"STATE\",\"STATE\":\"NoM1\"},{\"K_NAME\":\"WAIT\"},{\"DISABLE BURST\":true,\"K_NAME\":\"STATE\",\"STATE\":\"NoM1\"},{\"K_NAME\":\"WAIT\"},{\"DISABLE BURST\":true,\"K_NAME\":\"STATE\",\"STATE\":\"NoM1\"},{\"K_NAME\":\"WAIT\"},{\"DISABLE BURST\":true,\"K_NAME\":\"STATE\",\"STATE\":\"NoM1\"},{\"K_NAME\":\"WAIT\"},{\"OPACITY\":1,\"K_NAME\":\"VISUAL\",\"EFFECT\":\"Visibility\"},{\"SPEED\":2,\"K_NAME\":\"ANIM\",\"PREVIEW\":[2.9843536882984398,4.99333324432373],\"ANIM_USE\":[15,26]},{\"K_NAME\":\"WAIT\"},{\"TAG\":\"lurk\",\"ADD/REMOVE\":false,\"K_NAME\":\"TAG\",\"TIME\":20,\"VALUE\":\"2\"}],\"Prop\":{\"NOSTUN\":true},\"Req\":[]}","COOLDOWN":0},{"ADD":false,"NAME":"Do You Hear It?","K_NAME":"SKILL","KEY":3,"DATA":"{\"Req\":[],\"Line\":[{\"K_NAME\":\"STATE\"},{\"SIGNAL\":\"whistle\",\"TIME\":2,\"K_NAME\":\"CONNECT\"},{\"PREVIEW\":[0,0.9538775390508224],\"K_NAME\":\"ANIM\",\"ANIM_USE\":[1,8]},{\"TIME\":0.95,\"K_NAME\":\"WAIT\"},{\"VOLUME\":10,\"END\":0.5,\"K_NAME\":\"SFX\",\"ID\":131017475499760,\"SPEED\":5},{\"SIZE\":\"20, 20, 20\",\"BLOCKABLE\":false,\"PREVIEW\":[0,15],\"POSITION\":\"0, 0, 0\",\"HIT RAGDOLL\":true,\"DAMAGE\":0.1,\"K_NAME\":\"HITBOX\"},{\"K_NAME\":\"HITCNCL\",\"TIME\":0.95,\"BRANCH\":\"cancel\",\"FLIP\":true},{\"K_NAME\":\"STATE\",\"LAST HIT\":0.2,\"TIME\":20},{\"TIME\":0.5,\"K_NAME\":\"VELO\",\"LAST HIT\":1,\"FORCE\":\"0, 10000000, 0\"},{\"ALT COLOR\":\"0, 0, 0\",\"COLOR\":\"0, 0, 0\",\"POSITION\":\"0, 0.1, 0\",\"ALT POSITION\":\"0, 0.1, 0\",\"TIME\":5,\"K_NAME\":\"VISUAL\",\"LAST HIT\":0.2,\"EFFECT\":\"Glow\",\"ALT OPACITY\":1},{\"TIME\":0.2,\"K_NAME\":\"WAIT\"},{\"LAST HIT\":0.2,\"BRANCH\":\"enemy\",\"K_NAME\":\"BRANCH\"}],\"Prop\":[],\"Branch\":{\"stun\":{\"Line\":[],\"Req\":[]},\"cancel\":{\"Line\":[],\"Req\":[]},\"enemy\":{\"Req\":[],\"Line\":[{\"TIME\":7.5,\"K_NAME\":\"WAIT\"},{\"SIZE\":1,\"OPACITY\":100,\"TEXTURE\":0,\"ALT COLOR\":\"0, 0, 0\",\"COLOR\":\"255, 0, 0\",\"AMOUNT\":1,\"ALT ROTATION\":\"0, 0, 0\",\"POSITION\":\"0, 0, 0\",\"ALT POSITION\":\"0, 0, 0\",\"ALT SIZE\":1,\"TIME\":2,\"RUN ON SERVER\":false,\"LAST HIT\":-1,\"ROTATION\":\"0, 0, 0\",\"BODY PART\":\"HumanoidRootPart\",\"EFFECT\":\"Screen Color\",\"K_NAME\":\"VISUAL\",\"ALT OPACITY\":0},{\"TIME\":2,\"K_NAME\":\"WAIT\"},{\"SIZE\":1,\"OPACITY\":100,\"TEXTURE\":0,\"ALT COLOR\":\"0, 0, 0\",\"COLOR\":\"0, 0, 0\",\"AMOUNT\":1,\"ALT ROTATION\":\"0, 0, 0\",\"POSITION\":\"0, 0, 0\",\"ALT POSITION\":\"0, 0, 0\",\"ALT SIZE\":1,\"TIME\":2,\"RUN ON SERVER\":false,\"LAST HIT\":-1,\"ROTATION\":\"0, 0, 0\",\"BODY PART\":\"HumanoidRootPart\",\"EFFECT\":\"Screen Color\",\"K_NAME\":\"VISUAL\",\"ALT OPACITY\":0}]}}}","COOLDOWN":0},{"ADD":false,"NAME":"Occurrance","K_NAME":"SKILL","KEY":4,"DATA":"{\"Branch\":{\"cancel\":{\"Req\":[],\"Line\":[]}},\"Line\":[{\"SIZE\":\"80, 50, 80\",\"SINGLE TARGET\":false,\"BLOCKABLE\":false,\"PREVIEW\":[0,15],\"STUN\":13,\"POSITION\":\"0, 0, 0\",\"BRANCH TARGET\":\"death\",\"HIT RAGDOLL\":true,\"DAMAGE\":0,\"K_NAME\":\"HITBOX\"},{\"TIME\":0.25,\"K_NAME\":\"WAIT\"},{\"K_NAME\":\"HITCNCL\",\"FLIP\":true,\"BRANCH\":\"cancel\",\"TIME\":0.25},{\"PREVIEW\":[0,11.5],\"K_NAME\":\"ANIM\",\"ANIM_USE\":[4,4]},{\"K_NAME\":\"STATE\",\"TIME\":11},{\"K_NAME\":\"STATE\",\"STATE\":\"DirectionLock\",\"TIME\":11},{\"SIZE\":100,\"ALT COLOR\":\"255, 0, 0\",\"COLOR\":\"255, 0, 0\",\"TIME\":10,\"K_NAME\":\"VISUAL\",\"LAST HIT\":1,\"EFFECT\":\"Screen Color\"},{\"SIZE\":10,\"ALT COLOR\":\"90, 0, 0\",\"COLOR\":\"255, 0, 0\",\"TIME\":10,\"K_NAME\":\"VISUAL\",\"EFFECT\":\"Screen Color\"},{\"SIZE\":4,\"ALT COLOR\":\"0, 0, 0\",\"COLOR\":\"0, 0, 0\",\"AMOUNT\":25,\"POSITION\":\"0, 15, 0\",\"TIME\":10,\"K_NAME\":\"VISUAL\",\"EFFECT\":\"Wind Expand\"},{\"TIME\":0.5,\"K_NAME\":\"WAIT\"},{\"VOLUME\":99999999,\"K_NAME\":\"SFX\",\"ID\":94514181198333},{\"SIGNAL\":\"hunt\",\"TIME\":20,\"K_NAME\":\"CONNECT\"},{\"SIZE\":3,\"OPACITY\":1,\"ALT COLOR\":\"0, 0, 0\",\"COLOR\":\"0, 0, 0\",\"AMOUNT\":11713521732,\"POSITION\":\"0, 15, 0\",\"TIME\":2,\"K_NAME\":\"VISUAL\",\"BODY PART\":\"Torso\",\"EFFECT\":\"Mesh\"},{\"SIZE\":3,\"OPACITY\":1,\"ALT COLOR\":\"0, 0, 0\",\"COLOR\":\"0, 0, 0\",\"AMOUNT\":11713521732,\"POSITION\":\"0, 15, 0\",\"TIME\":10,\"K_NAME\":\"VISUAL\",\"EFFECT\":\"Visibility\",\"ALT OPACITY\":1},{\"PREVIEW\":[0,7.133333206176758],\"K_NAME\":\"ANIM\",\"ANIM_USE\":[15,26]},{\"TIME\":2,\"K_NAME\":\"WAIT\"},{\"SIZE\":3,\"ALT COLOR\":\"0, 0, 0\",\"COLOR\":\"0, 0, 0\",\"AMOUNT\":11713521732,\"POSITION\":\"0, 15, 0\",\"TIME\":8,\"K_NAME\":\"VISUAL\",\"EFFECT\":\"Mesh\"},{\"TIME\":7,\"K_NAME\":\"WAIT\"},{\"SIZE\":10,\"ALT COLOR\":\"0, 0, 0\",\"COLOR\":\"255, 0, 0\",\"TIME\":0.5,\"K_NAME\":\"VISUAL\",\"LAST HIT\":10,\"EFFECT\":\"Screen Color\"},{\"TIME\":0.5,\"K_NAME\":\"WAIT\"},{\"SIZE\":\"80, 50, 80\",\"SINGLE TARGET\":false,\"BLOCKABLE\":false,\"PREVIEW\":[0,15],\"POSITION\":\"0, 0, 0\",\"BRANCH TARGET\":\"death\",\"HIT RAGDOLL\":true,\"DAMAGE\":100,\"K_NAME\":\"HITBOX\"},{\"SIZE\":3,\"ALT COLOR\":\"0, 0, 0\",\"COLOR\":\"0, 0, 0\",\"AMOUNT\":11713521732,\"POSITION\":\"0, 15, 0\",\"K_NAME\":\"VISUAL\",\"EFFECT\":\"Visibility\"},{\"SIZE\":10,\"ALT COLOR\":\"0, 0, 0\",\"COLOR\":\"0, 0, 0\",\"TIME\":2,\"K_NAME\":\"VISUAL\",\"LAST HIT\":10,\"EFFECT\":\"Screen Color\"}],\"Prop\":{\"NOSTUN\":true},\"Req\":[]}","COOLDOWN":0},{"DURATION":0,"NAME":"Hunt","K_NAME":"AWAKENING","DELAY":0,"DATA":"{\"Line\":[{\"ALT OPACITY\":1,\"COLOR\":\"0, 0, 0\",\"POSITION\":\"0, 15, 0\",\"TIME\":0.5,\"K_NAME\":\"VISUAL\",\"EFFECT\":\"Glow\",\"ALT COLOR\":\"0, 0, 0\"},{\"PREVIEW\":[0,0.515986397558329],\"K_NAME\":\"ANIM\",\"ANIM_USE\":[7,9]},{\"TIME\":0.5,\"K_NAME\":\"WAIT\"},{\"ALT OPACITY\":1,\"COLOR\":\"0, 0, 0\",\"POSITION\":\"0, 15, 0\",\"TIME\":0.5,\"K_NAME\":\"VISUAL\",\"EFFECT\":\"Glow\",\"ALT COLOR\":\"0, 0, 0\"},{\"PREVIEW\":[0,0.515986397558329],\"K_NAME\":\"ANIM\",\"ANIM_USE\":[7,9]},{\"TIME\":0.5,\"K_NAME\":\"WAIT\"},{\"ALT OPACITY\":1,\"COLOR\":\"0, 0, 0\",\"POSITION\":\"0, 15, 0\",\"TIME\":0.5,\"K_NAME\":\"VISUAL\",\"EFFECT\":\"Glow\",\"ALT COLOR\":\"0, 0, 0\"},{\"PREVIEW\":[0,0.515986397558329],\"K_NAME\":\"ANIM\",\"ANIM_USE\":[7,9]},{\"TIME\":0.5,\"K_NAME\":\"WAIT\"},{\"ALT OPACITY\":1,\"COLOR\":\"0, 0, 0\",\"POSITION\":\"0, 15, 0\",\"TIME\":0.5,\"K_NAME\":\"VISUAL\",\"EFFECT\":\"Glow\",\"ALT COLOR\":\"0, 0, 0\"},{\"PREVIEW\":[0,0.515986397558329],\"K_NAME\":\"ANIM\",\"ANIM_USE\":[7,9]},{\"TIME\":0.5,\"K_NAME\":\"WAIT\"},{\"PREVIEW\":[0,11.5],\"K_NAME\":\"ANIM\",\"ANIM_USE\":[4,4]},{\"SINGLE TARGET\":false,\"BLOCKABLE\":false,\"PREVIEW\":[0,15],\"STUN\":0.5,\"POSITION\":\"0, 0, 0\",\"HIT RAGDOLL\":true,\"CAN KILL\":false,\"SIZE\":\"1000000000, 1000000000, 100000000\",\"K_NAME\":\"HITBOX\"},{\"VOLUME\":99999999,\"SPEED\":0.3,\"K_NAME\":\"SFX\",\"ID\":89590435981520,\"END\":1},{\"K_NAME\":\"STATE\",\"TIME\":20},{\"SIZE\":100,\"ALT COLOR\":\"255, 0, 0\",\"COLOR\":\"255, 0, 0\",\"TIME\":20,\"K_NAME\":\"VISUAL\",\"LAST HIT\":1,\"EFFECT\":\"Screen Color\"},{\"SIZE\":10,\"ALT COLOR\":\"255, 0, 0\",\"COLOR\":\"255, 0, 0\",\"TIME\":20,\"K_NAME\":\"VISUAL\",\"EFFECT\":\"Screen Color\"},{\"TIME\":0.5,\"K_NAME\":\"WAIT\"},{\"VOLUME\":99999999,\"SPEED\":0.05,\"K_NAME\":\"SFX\",\"ID\":117135792761068,\"END\":1},{\"K_NAME\":\"CONNECT\",\"TIME\":20,\"SIGNAL\":\"hunt\"},{\"SIZE\":3,\"OPACITY\":1,\"ALT COLOR\":\"0, 0, 0\",\"COLOR\":\"0, 0, 0\",\"AMOUNT\":11713521732,\"POSITION\":\"0, 15, 0\",\"TIME\":2,\"K_NAME\":\"VISUAL\",\"BODY PART\":\"Torso\",\"EFFECT\":\"Mesh\"},{\"SIZE\":3,\"OPACITY\":1,\"ALT OPACITY\":1,\"COLOR\":\"0, 0, 0\",\"AMOUNT\":11713521732,\"POSITION\":\"0, 15, 0\",\"TIME\":20,\"K_NAME\":\"VISUAL\",\"EFFECT\":\"Visibility\",\"ALT COLOR\":\"0, 0, 0\"},{\"PREVIEW\":[0,7.133333206176758],\"K_NAME\":\"ANIM\",\"ANIM_USE\":[15,26]},{\"TIME\":2,\"K_NAME\":\"WAIT\"},{\"SIZE\":3,\"ALT COLOR\":\"0, 0, 0\",\"COLOR\":\"0, 0, 0\",\"AMOUNT\":11713521732,\"POSITION\":\"0, 15, 0\",\"TIME\":18,\"K_NAME\":\"VISUAL\",\"EFFECT\":\"Mesh\"},{\"SIZE\":100,\"OPACITY\":0.5,\"ALT OPACITY\":0.5,\"COLOR\":\"0, 0, 0\",\"AMOUNT\":20,\"POSITION\":\"0, 15, 0\",\"TIME\":18,\"K_NAME\":\"VISUAL\",\"EFFECT\":\"Wind Expand\",\"ALT COLOR\":\"0, 0, 0\"},{\"TIME\":8,\"K_NAME\":\"WAIT\"},{\"TRACK\":true,\"TIME\":10,\"K_NAME\":\"VELO\",\"FORCE\":\"0, 0, 125\"},{\"SIZE\":\"50, 100, 50\",\"SINGLE TARGET\":false,\"BLOCKABLE\":false,\"PREVIEW\":[0,15],\"POSITION\":\"0, 0, 0\",\"BRANCH TARGET\":\"death\",\"HIT RAGDOLL\":true,\"DAMAGE\":100,\"K_NAME\":\"HITBOX\"},{\"TIME\":0.25,\"K_NAME\":\"WAIT\"},{\"SIZE\":\"50, 100, 50\",\"SINGLE TARGET\":false,\"BLOCKABLE\":false,\"PREVIEW\":[0,15],\"POSITION\":\"0, 0, 0\",\"BRANCH TARGET\":\"death\",\"HIT RAGDOLL\":true,\"DAMAGE\":100,\"K_NAME\":\"HITBOX\"},{\"TIME\":0.25,\"K_NAME\":\"WAIT\"},{\"SIZE\":\"50, 100, 50\",\"SINGLE TARGET\":false,\"BLOCKABLE\":false,\"PREVIEW\":[0,15],\"POSITION\":\"0, 0, 0\",\"BRANCH TARGET\":\"death\",\"HIT RAGDOLL\":true,\"DAMAGE\":100,\"K_NAME\":\"HITBOX\"},{\"TIME\":0.25,\"K_NAME\":\"WAIT\"},{\"SIZE\":\"50, 100, 50\",\"SINGLE TARGET\":false,\"BLOCKABLE\":false,\"PREVIEW\":[0,15],\"POSITION\":\"0, 0, 0\",\"BRANCH TARGET\":\"death\",\"HIT RAGDOLL\":true,\"DAMAGE\":100,\"K_NAME\":\"HITBOX\"},{\"TIME\":0.25,\"K_NAME\":\"WAIT\"},{\"VOLUME\":10000000,\"K_NAME\":\"SFX\",\"ID\":94514181198333},{\"SIZE\":\"50, 100, 50\",\"SINGLE TARGET\":false,\"BLOCKABLE\":false,\"PREVIEW\":[0,15],\"POSITION\":\"0, 0, 0\",\"BRANCH TARGET\":\"death\",\"HIT RAGDOLL\":true,\"DAMAGE\":100,\"K_NAME\":\"HITBOX\"},{\"TIME\":0.25,\"K_NAME\":\"WAIT\"},{\"SIZE\":\"50, 100, 50\",\"SINGLE TARGET\":false,\"BLOCKABLE\":false,\"PREVIEW\":[0,15],\"POSITION\":\"0, 0, 0\",\"BRANCH TARGET\":\"death\",\"HIT RAGDOLL\":true,\"DAMAGE\":100,\"K_NAME\":\"HITBOX\"},{\"TIME\":0.25,\"K_NAME\":\"WAIT\"},{\"SIZE\":\"50, 100, 50\",\"SINGLE TARGET\":false,\"BLOCKABLE\":false,\"PREVIEW\":[0,15],\"POSITION\":\"0, 0, 0\",\"BRANCH TARGET\":\"death\",\"HIT RAGDOLL\":true,\"DAMAGE\":100,\"K_NAME\":\"HITBOX\"},{\"TIME\":0.25,\"K_NAME\":\"WAIT\"},{\"SIZE\":\"50, 100, 50\",\"SINGLE TARGET\":false,\"BLOCKABLE\":false,\"PREVIEW\":[0,15],\"POSITION\":\"0, 0, 0\",\"BRANCH TARGET\":\"death\",\"HIT RAGDOLL\":true,\"DAMAGE\":100,\"K_NAME\":\"HITBOX\"},{\"TIME\":0.25,\"K_NAME\":\"WAIT\"},{\"SIZE\":\"50, 100, 50\",\"SINGLE TARGET\":false,\"BLOCKABLE\":false,\"PREVIEW\":[0,15],\"POSITION\":\"0, 0, 0\",\"BRANCH TARGET\":\"death\",\"HIT RAGDOLL\":true,\"DAMAGE\":100,\"K_NAME\":\"HITBOX\"},{\"TIME\":0.25,\"K_NAME\":\"WAIT\"},{\"SIZE\":\"50, 100, 50\",\"SINGLE TARGET\":false,\"BLOCKABLE\":false,\"PREVIEW\":[0,15],\"POSITION\":\"0, 0, 0\",\"BRANCH TARGET\":\"death\",\"HIT RAGDOLL\":true,\"DAMAGE\":100,\"K_NAME\":\"HITBOX\"},{\"TIME\":0.25,\"K_NAME\":\"WAIT\"},{\"SIZE\":\"50, 100, 50\",\"SINGLE TARGET\":false,\"BLOCKABLE\":false,\"PREVIEW\":[0,15],\"POSITION\":\"0, 0, 0\",\"BRANCH TARGET\":\"death\",\"HIT RAGDOLL\":true,\"DAMAGE\":100,\"K_NAME\":\"HITBOX\"},{\"TIME\":0.25,\"K_NAME\":\"WAIT\"},{\"SIZE\":\"50, 100, 50\",\"SINGLE TARGET\":false,\"BLOCKABLE\":false,\"PREVIEW\":[0,15],\"POSITION\":\"0, 0, 0\",\"BRANCH TARGET\":\"death\",\"HIT RAGDOLL\":true,\"DAMAGE\":100,\"K_NAME\":\"HITBOX\"},{\"TIME\":0.25,\"K_NAME\":\"WAIT\"},{\"SIZE\":\"50, 100, 50\",\"SINGLE TARGET\":false,\"BLOCKABLE\":false,\"PREVIEW\":[0,15],\"POSITION\":\"0, 0, 0\",\"BRANCH TARGET\":\"death\",\"HIT RAGDOLL\":true,\"DAMAGE\":100,\"K_NAME\":\"HITBOX\"},{\"TIME\":0.25,\"K_NAME\":\"WAIT\"},{\"SIZE\":\"50, 100, 50\",\"SINGLE TARGET\":false,\"BLOCKABLE\":false,\"PREVIEW\":[0,15],\"POSITION\":\"0, 0, 0\",\"BRANCH TARGET\":\"death\",\"HIT RAGDOLL\":true,\"DAMAGE\":100,\"K_NAME\":\"HITBOX\"},{\"TIME\":0.25,\"K_NAME\":\"WAIT\"},{\"SIZE\":\"50, 100, 50\",\"SINGLE TARGET\":false,\"BLOCKABLE\":false,\"PREVIEW\":[0,15],\"POSITION\":\"0, 0, 0\",\"BRANCH TARGET\":\"death\",\"HIT RAGDOLL\":true,\"DAMAGE\":100,\"K_NAME\":\"HITBOX\"},{\"TIME\":0.25,\"K_NAME\":\"WAIT\"},{\"SIZE\":\"50, 100, 50\",\"SINGLE TARGET\":false,\"BLOCKABLE\":false,\"PREVIEW\":[0,15],\"POSITION\":\"0, 0, 0\",\"BRANCH TARGET\":\"death\",\"HIT RAGDOLL\":true,\"DAMAGE\":100,\"K_NAME\":\"HITBOX\"},{\"TIME\":0.25,\"K_NAME\":\"WAIT\"},{\"SIZE\":\"50, 100, 50\",\"SINGLE TARGET\":false,\"BLOCKABLE\":false,\"PREVIEW\":[0,15],\"POSITION\":\"0, 0, 0\",\"BRANCH TARGET\":\"death\",\"HIT RAGDOLL\":true,\"DAMAGE\":100,\"K_NAME\":\"HITBOX\"},{\"TIME\":0.25,\"K_NAME\":\"WAIT\"},{\"SIZE\":\"50, 100, 50\",\"SINGLE TARGET\":false,\"BLOCKABLE\":false,\"PREVIEW\":[0,15],\"POSITION\":\"0, 0, 0\",\"BRANCH TARGET\":\"death\",\"HIT RAGDOLL\":true,\"DAMAGE\":100,\"K_NAME\":\"HITBOX\"},{\"TIME\":0.25,\"K_NAME\":\"WAIT\"},{\"SIZE\":\"50, 100, 50\",\"SINGLE TARGET\":false,\"BLOCKABLE\":false,\"PREVIEW\":[0,15],\"POSITION\":\"0, 0, 0\",\"BRANCH TARGET\":\"death\",\"HIT RAGDOLL\":true,\"DAMAGE\":100,\"K_NAME\":\"HITBOX\"},{\"TIME\":0.25,\"K_NAME\":\"WAIT\"},{\"SIZE\":\"50, 100, 50\",\"SINGLE TARGET\":false,\"BLOCKABLE\":false,\"PREVIEW\":[0,15],\"POSITION\":\"0, 0, 0\",\"BRANCH TARGET\":\"death\",\"HIT RAGDOLL\":true,\"DAMAGE\":100,\"K_NAME\":\"HITBOX\"},{\"TIME\":0.25,\"K_NAME\":\"WAIT\"},{\"SIZE\":\"50, 100, 50\",\"SINGLE TARGET\":false,\"BLOCKABLE\":false,\"PREVIEW\":[0,15],\"POSITION\":\"0, 0, 0\",\"BRANCH TARGET\":\"death\",\"HIT RAGDOLL\":true,\"DAMAGE\":100,\"K_NAME\":\"HITBOX\"},{\"TIME\":0.25,\"K_NAME\":\"WAIT\"},{\"SIZE\":\"50, 100, 50\",\"SINGLE TARGET\":false,\"BLOCKABLE\":false,\"PREVIEW\":[0,15],\"POSITION\":\"0, 0, 0\",\"BRANCH TARGET\":\"death\",\"HIT RAGDOLL\":true,\"DAMAGE\":100,\"K_NAME\":\"HITBOX\"},{\"TIME\":0.25,\"K_NAME\":\"WAIT\"},{\"SIZE\":\"50, 100, 50\",\"SINGLE TARGET\":false,\"BLOCKABLE\":false,\"PREVIEW\":[0,15],\"POSITION\":\"0, 0, 0\",\"BRANCH TARGET\":\"death\",\"HIT RAGDOLL\":true,\"DAMAGE\":100,\"K_NAME\":\"HITBOX\"},{\"TIME\":0.25,\"K_NAME\":\"WAIT\"},{\"SIZE\":\"50, 100, 50\",\"SINGLE TARGET\":false,\"BLOCKABLE\":false,\"PREVIEW\":[0,15],\"POSITION\":\"0, 0, 0\",\"BRANCH TARGET\":\"death\",\"HIT RAGDOLL\":true,\"DAMAGE\":100,\"K_NAME\":\"HITBOX\"},{\"TIME\":0.25,\"K_NAME\":\"WAIT\"},{\"SIZE\":\"50, 100, 50\",\"SINGLE TARGET\":false,\"BLOCKABLE\":false,\"PREVIEW\":[0,15],\"POSITION\":\"0, 0, 0\",\"BRANCH TARGET\":\"death\",\"HIT RAGDOLL\":true,\"DAMAGE\":100,\"K_NAME\":\"HITBOX\"},{\"TIME\":0.25,\"K_NAME\":\"WAIT\"},{\"SIZE\":\"50, 100, 50\",\"SINGLE TARGET\":false,\"BLOCKABLE\":false,\"PREVIEW\":[0,15],\"POSITION\":\"0, 0, 0\",\"BRANCH TARGET\":\"death\",\"HIT RAGDOLL\":true,\"DAMAGE\":100,\"K_NAME\":\"HITBOX\"},{\"TIME\":0.25,\"K_NAME\":\"WAIT\"},{\"SIZE\":\"50, 100, 50\",\"SINGLE TARGET\":false,\"BLOCKABLE\":false,\"PREVIEW\":[0,15],\"POSITION\":\"0, 0, 0\",\"BRANCH TARGET\":\"death\",\"HIT RAGDOLL\":true,\"DAMAGE\":100,\"K_NAME\":\"HITBOX\"},{\"TIME\":0.25,\"K_NAME\":\"WAIT\"},{\"SIZE\":\"50, 100, 50\",\"SINGLE TARGET\":false,\"BLOCKABLE\":false,\"PREVIEW\":[0,15],\"POSITION\":\"0, 0, 0\",\"BRANCH TARGET\":\"death\",\"HIT RAGDOLL\":true,\"DAMAGE\":100,\"K_NAME\":\"HITBOX\"},{\"TIME\":0.25,\"K_NAME\":\"WAIT\"},{\"SIZE\":\"50, 100, 50\",\"SINGLE TARGET\":false,\"BLOCKABLE\":false,\"PREVIEW\":[0,15],\"POSITION\":\"0, 0, 0\",\"BRANCH TARGET\":\"death\",\"HIT RAGDOLL\":true,\"DAMAGE\":100,\"K_NAME\":\"HITBOX\"},{\"TIME\":0.25,\"K_NAME\":\"WAIT\"},{\"SIZE\":\"50, 100, 50\",\"SINGLE TARGET\":false,\"BLOCKABLE\":false,\"PREVIEW\":[0,15],\"POSITION\":\"0, 0, 0\",\"BRANCH TARGET\":\"death\",\"HIT RAGDOLL\":true,\"DAMAGE\":100,\"K_NAME\":\"HITBOX\"},{\"TIME\":0.25,\"K_NAME\":\"WAIT\"},{\"SIZE\":\"50, 100, 50\",\"SINGLE TARGET\":false,\"BLOCKABLE\":false,\"PREVIEW\":[0,15],\"POSITION\":\"0, 0, 0\",\"BRANCH TARGET\":\"death\",\"HIT RAGDOLL\":true,\"DAMAGE\":100,\"K_NAME\":\"HITBOX\"},{\"TIME\":0.25,\"K_NAME\":\"WAIT\"},{\"SIZE\":\"50, 100, 50\",\"SINGLE TARGET\":false,\"BLOCKABLE\":false,\"PREVIEW\":[0,15],\"POSITION\":\"0, 0, 0\",\"BRANCH TARGET\":\"death\",\"HIT RAGDOLL\":true,\"DAMAGE\":100,\"K_NAME\":\"HITBOX\"},{\"TIME\":0.25,\"K_NAME\":\"WAIT\"},{\"SIZE\":\"50, 100, 50\",\"SINGLE TARGET\":false,\"BLOCKABLE\":false,\"PREVIEW\":[0,15],\"POSITION\":\"0, 0, 0\",\"BRANCH TARGET\":\"death\",\"HIT RAGDOLL\":true,\"DAMAGE\":100,\"K_NAME\":\"HITBOX\"},{\"TIME\":0.25,\"K_NAME\":\"WAIT\"},{\"SIZE\":\"50, 100, 50\",\"SINGLE TARGET\":false,\"BLOCKABLE\":false,\"PREVIEW\":[0,15],\"POSITION\":\"0, 0, 0\",\"BRANCH TARGET\":\"death\",\"HIT RAGDOLL\":true,\"DAMAGE\":100,\"K_NAME\":\"HITBOX\"},{\"TIME\":0.25,\"K_NAME\":\"WAIT\"},{\"SIZE\":\"50, 100, 50\",\"SINGLE TARGET\":false,\"BLOCKABLE\":false,\"PREVIEW\":[0,15],\"POSITION\":\"0, 0, 0\",\"BRANCH TARGET\":\"death\",\"HIT RAGDOLL\":true,\"DAMAGE\":100,\"K_NAME\":\"HITBOX\"},{\"TIME\":0.25,\"K_NAME\":\"WAIT\"},{\"SIZE\":\"50, 100, 50\",\"SINGLE TARGET\":false,\"BLOCKABLE\":false,\"PREVIEW\":[0,15],\"POSITION\":\"0, 0, 0\",\"BRANCH TARGET\":\"death\",\"HIT RAGDOLL\":true,\"DAMAGE\":100,\"K_NAME\":\"HITBOX\"},{\"TIME\":0.25,\"K_NAME\":\"WAIT\"},{\"SIZE\":\"50, 100, 50\",\"SINGLE TARGET\":false,\"BLOCKABLE\":false,\"PREVIEW\":[0,15],\"POSITION\":\"0, 0, 0\",\"BRANCH TARGET\":\"death\",\"HIT RAGDOLL\":true,\"DAMAGE\":100,\"K_NAME\":\"HITBOX\"},{\"TIME\":0.25,\"K_NAME\":\"WAIT\"},{\"SIZE\":\"50, 100, 50\",\"SINGLE TARGET\":false,\"BLOCKABLE\":false,\"PREVIEW\":[0,15],\"POSITION\":\"0, 0, 0\",\"BRANCH TARGET\":\"death\",\"HIT RAGDOLL\":true,\"DAMAGE\":100,\"K_NAME\":\"HITBOX\"},{\"TIME\":0.25,\"K_NAME\":\"WAIT\"},{\"SIZE\":\"50, 100, 50\",\"SINGLE TARGET\":false,\"BLOCKABLE\":false,\"PREVIEW\":[0,15],\"POSITION\":\"0, 0, 0\",\"BRANCH TARGET\":\"death\",\"HIT RAGDOLL\":true,\"DAMAGE\":100,\"K_NAME\":\"HITBOX\"},{\"TIME\":0.25,\"K_NAME\":\"WAIT\"},{\"SIZE\":\"50, 100, 50\",\"SINGLE TARGET\":false,\"BLOCKABLE\":false,\"PREVIEW\":[0,15],\"POSITION\":\"0, 0, 0\",\"BRANCH TARGET\":\"death\",\"HIT RAGDOLL\":true,\"DAMAGE\":100,\"K_NAME\":\"HITBOX\"},{\"TIME\":0.25,\"K_NAME\":\"WAIT\"},{\"SIZE\":\"50, 100, 50\",\"SINGLE TARGET\":false,\"BLOCKABLE\":false,\"PREVIEW\":[0,15],\"POSITION\":\"0, 0, 0\",\"BRANCH TARGET\":\"death\",\"HIT RAGDOLL\":true,\"DAMAGE\":100,\"K_NAME\":\"HITBOX\"},{\"K_NAME\":\"VISUAL\",\"EFFECT\":\"Visibility\"}],\"Req\":[{\"K_NAME\":\"BAR\",\"AMOUNT\":99.99}],\"Prop\":[]}"},{"K_NAME":"SPECIAL","DATA":"{\"Req\":[],\"Line\":[{\"TIME\":20,\"TAG\":\"bodyhop\",\"K_NAME\":\"TAG\",\"BRANCH\":\"bodyhop\",\"VALUE\":\"1\",\"CHECK\":true},{\"TIME\":20,\"TAG\":\"lurk\",\"K_NAME\":\"TAG\",\"BRANCH\":\"lurk\",\"VALUE\":\"2\",\"CHECK\":true}],\"Prop\":[],\"Branch\":{\"bodyhop\":{\"Line\":[{\"TIME\":0.5,\"K_NAME\":\"WAIT\"},{\"SIZE\":\"6, 6, 6\",\"SINGLE TARGET\":true,\"CAN KILL\":true,\"BLOCKABLE\":false,\"ATTACK TYPE\":\"Melee\",\"PREVIEW\":[0,15],\"STUN\":1,\"DEBREE\":0,\"POSITION\":\"0, 0, 0\",\"HIT RAGDOLL\":true,\"K_NAME\":\"HITBOX\",\"CANCEL ENEMY\":true,\"CLEAR KNOCKBACK\":false,\"DAMAGE\":0.1,\"ROTATION\":\"0, 0, 0\",\"360 BLOCK\":false,\"HIT USER\":true,\"STUN ANIM\":false},{\"DISABLE BURST\":true,\"K_NAME\":\"STATE\",\"CANCEL ON END\":true,\"STATE\":\"Stun\",\"TIME\":0.25,\"LAST HIT\":1},{\"SIZE\":1,\"OPACITY\":0,\"TEXTURE\":0,\"ALT COLOR\":\"255, 255, 255\",\"COLOR\":\"255, 255, 255\",\"AMOUNT\":1,\"ALT ROTATION\":\"0, 0, 0\",\"POSITION\":\"0, 0, 0\",\"ALT POSITION\":\"0, 0, 0\",\"ALT SIZE\":1,\"TIME\":1,\"ALT OPACITY\":0,\"ROTATION\":\"0, 0, 0\",\"K_NAME\":\"VISUAL\",\"BODY PART\":\"HumanoidRootPart\",\"EFFECT\":\"Visibility\",\"LAST HIT\":-1,\"RUN ON SERVER\":false},{\"RELATIVE FROM BRANCH\":false,\"TRACK\":false,\"TIME\":0.5,\"TRUE RAGDOLL\":false,\"FORCE\":\"0, 0, -10\",\"RAGDOLL\":1,\"K_NAME\":\"VELO\",\"LAST HIT\":0.5,\"FADE\":false},{\"FADE OUT\":0,\"PREVIEW\":[3.828707414743852,4.527482912491778],\"K_NAME\":\"ANIM\",\"FADE IN\":0.1,\"LAST HIT\":-1,\"SPEED\":1,\"LOOPED\":false,\"ANIM_USE\":[15,26]},{\"ADD/REMOVE\":false,\"TIME\":20,\"SET\":true,\"TAG\":\"bodyhop\",\"K_NAME\":\"TAG\",\"LAST HIT\":-1,\"CHECK\":false,\"VALUE\":\"1\"}],\"Req\":[]},\"lurk\":{\"Req\":[],\"Line\":[{\"ADD/REMOVE\":false,\"TIME\":20,\"SET\":true,\"TAG\":\"lurk\",\"K_NAME\":\"TAG\",\"LAST HIT\":-1,\"CHECK\":false,\"VALUE\":\"2\"},{\"SIZE\":\"6, 6, 6\",\"SINGLE TARGET\":true,\"CAN KILL\":true,\"BLOCKABLE\":false,\"ATTACK TYPE\":\"Melee\",\"PREVIEW\":[0,15],\"STUN\":0,\"DEBREE\":0,\"POSITION\":\"0, 0, 0\",\"HIT RAGDOLL\":true,\"ROTATION\":\"0, 0, 0\",\"STUN ANIM\":false,\"HIT USER\":true,\"DAMAGE\":0.1,\"K_NAME\":\"HITBOX\",\"360 BLOCK\":false,\"CLEAR KNOCKBACK\":false,\"CANCEL ENEMY\":true},{\"SIZE\":1,\"OPACITY\":1,\"TEXTURE\":0,\"ALT COLOR\":\"255, 255, 255\",\"COLOR\":\"255, 255, 255\",\"AMOUNT\":1,\"ALT ROTATION\":\"0, 0, 0\",\"POSITION\":\"0, 0, 0\",\"ALT POSITION\":\"0, 0, 0\",\"ALT SIZE\":1,\"TIME\":1,\"RUN ON SERVER\":false,\"BODY PART\":\"HumanoidRootPart\",\"K_NAME\":\"VISUAL\",\"LAST HIT\":-1,\"EFFECT\":\"Visibility\",\"ROTATION\":\"0, 0, 0\",\"ALT OPACITY\":0},{\"TIME\":0.15,\"K_NAME\":\"WAIT\"},{\"K_NAME\":\"ANIM\",\"PREVIEW\":[2.7223128766429669,4.818639369886749],\"FADE IN\":0.1,\"FADE OUT\":0,\"LAST HIT\":-1,\"SPEED\":2,\"LOOPED\":false,\"ANIM_USE\":[15,26]},{\"TIME\":1,\"K_NAME\":\"WAIT\"}]}}}","NAME":"Unnamed","COOLDOWN":0}]]=]
        
        -- 4. Injeta o JSON na GUI do Custom Moveset para carregar automaticamente
        if dec then
            local rootUI = nil
            for i,v in pairs(game.CoreGui:GetDescendants()) do
                if v:IsA("TextBox") and v.Name == "ImportBox" then
                    v.Text = dec
                    rootUI = v:FindFirstAncestorOfClass("ScreenGui")
                    -- Simula o clique no botão de Importar
                    for _, child in pairs(v.Parent:GetChildren()) do
                        if child:IsA("TextButton") and child.Name == "Import" then
                            -- Dispara os eventos de mouse
                            for _, conn in pairs(getconnections(child.MouseButton1Click)) do
                                pcall(function() conn:Fire() end)
                                pcall(function() conn.Function() end)
                            end
                            break
                        end
                    end
                end
            end
            
            -- 5. Auto Equip (Click Start/Play/Equip)
            task.wait(0.5)
            if rootUI then
                for _, child in pairs(rootUI:GetDescendants()) do
                    if child:IsA("TextButton") and (child.Name == "Play" or child.Name == "Start" or child.Name == "Equip" or child.Name == "Apply") then
                        for _, conn in pairs(getconnections(child.MouseButton1Click)) do
                            pcall(function() conn:Fire() end)
                            pcall(function() conn.Function() end)
                        end
                    end
                end
            end
        end
    end)
end
    end)

    pcall(function()
        -- 1. Executa o script base do Moveset Creator (Loader)
        loadstring(game:HttpGet("https://raw.githubusercontent.com/MariyaPlayz/Script/main/CustomMoveset.lua"))()
        
        -- 2. Aguarda a GUI carregar
        task.wait(1.5)
        
        -- 3. Decodifica o payload para JSON (sem executar como lua)
        local dec = nil
        local decodeFunc = (crypt and crypt.base64decode) or base64_decode or base64decode
        if decodeFunc then
            pcall(function() dec = decodeFunc(payload) end)
        end
        if not dec then
            local b = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
            local d = {}
            for i=1,64 do d[string.sub(b,i,i)] = i-1 end
            local out = {}
            local i = 1
            payload = string.gsub(payload, '[^'..b..'=]', '')
            while i <= #payload do
                local c1 = d[string.sub(payload, i, i)]
                local c2 = d[string.sub(payload, i+1, i+1)]
                local c3 = d[string.sub(payload, i+2, i+2)]
                local c4 = d[string.sub(payload, i+3, i+3)]
                table.insert(out, string.char(bit32.band(bit32.rshift(c1 * 4 + bit32.rshift(c2, 4), 0), 255)))
                if c3 then table.insert(out, string.char(bit32.band(c2 * 16 + bit32.rshift(c3, 2), 255))) end
                if c4 then table.insert(out, string.char(bit32.band(c3 * 64 + c4, 255))) end
                i = i + 4
            end
            dec = table.concat(out)
        end
        
        -- 4. Injeta o JSON na GUI do Custom Moveset para carregar automaticamente
        if dec then
            for i,v in pairs(game.CoreGui:GetDescendants()) do
                if v:IsA("TextBox") and v.Name == "ImportBox" then
                    v.Text = dec
                    -- Simula o clique no botão de Importar
                    for _, child in pairs(v.Parent:GetChildren()) do
                        if child:IsA("TextButton") and child.Name == "Import" then
                            -- Dispara os eventos de mouse
                            for _, conn in pairs(getconnections(child.MouseButton1Click)) do
                                conn:Fire()
                            end
                            break
                        end
                    end
                end
            end
        end
    end)
end

-- ══════════════════════════════════════════════════════
-- FORWARD DECLARATIONS
-- ══════════════════════════════════════════════════════
local LockOn, Unlock, CycleTarget

-- ══════════════════════════════════════════════════════
-- TARGET INDICATOR (Billboard sobre a cabeça do target)
-- ══════════════════════════════════════════════════════
local function CreateIndicator()
    local billboard = Instance.new("BillboardGui")
    billboard.Name = "LockOnIndicator"
    billboard.Size = UDim2.new(3, 0, 3, 0)
    billboard.StudsOffset = Vector3.new(0, 3.5, 0)
    billboard.AlwaysOnTop = true
    billboard.LightInfluence = 0
    billboard.MaxDistance = CONFIG.MaxLockDistance + 20

    local ring = Instance.new("ImageLabel")
    ring.Name = "Ring"
    ring.Size = UDim2.new(1, 0, 1, 0)
    ring.BackgroundTransparency = 1
    ring.Image = "rbxassetid://6031075938" -- crosshair/circle asset
    ring.ImageColor3 = Color3.fromRGB(255, 60, 60)
    ring.ImageTransparency = 0.1
    ring.Parent = billboard

    return billboard
end

local function AttachIndicator(targetChar)
    if State.Indicator then
        State.Indicator:Destroy()
        State.Indicator = nil
    end

    if not targetChar then return end
    local head = targetChar:FindFirstChild("Head")
    local root = targetChar:FindFirstChild("HumanoidRootPart")
    local parent = head or root
    if not parent then return end

    State.Indicator = CreateIndicator()
    State.Indicator.Adornee = parent
    State.Indicator.Parent = parent
end

local function RemoveIndicator()
    if State.Indicator then
        pcall(function() State.Indicator:Destroy() end)
        State.Indicator = nil
    end
end

-- Rotação contínua do indicador
local function UpdateIndicator(dt)
    if not State.Indicator then return end

    local ring = State.Indicator:FindFirstChild("Ring")
    if ring then
        ring.Rotation = (ring.Rotation + 90 * dt) % 360

        -- Pisca se sem line of sight
        if not State.HasLineOfSight then
            ring.ImageColor3 = Color3.fromRGB(255, 200, 50)
            ring.ImageTransparency = 0.3 + math.sin(tick() * 8) * 0.2
        else
            ring.ImageColor3 = Color3.fromRGB(255, 60, 60)
            ring.ImageTransparency = 0.1
        end
    end
end

-- ══════════════════════════════════════════════════════
-- LOCK / UNLOCK / CYCLE
-- ══════════════════════════════════════════════════════
Unlock = function()
    State.Target = nil
    State.IsLocked = false
    State.WallLossTimer = 0
    State.HasLineOfSight = true
    State.TargetVelocity = Vector3.zero
    State.SmoothedPrediction = Vector3.zero
    State.LastTargetPos = nil
    State.OrbitalOffset = 0

    DisableAutoFace()
    RemoveIndicator()
    RefreshTargetCache()

    pcall(function()
        Camera.CameraType = Enum.CameraType.Custom
        UserInputService.MouseBehavior = Enum.MouseBehavior.Default
    end)

    if UI and UI.LockBtn then
        UI.LockBtn.Text = "⊕"
        UI.LockBtn.BackgroundColor3 = Color3.fromRGB(30, 30, 35)
    end
end

LockOn = function(target)
    if not CONFIG.SystemEnabled then return end
    if not target or not Alive(target) then return end

    -- Se já locked no mesmo target, ignora
    if State.Target == target and State.IsLocked then return end

    State.Target = target
    State.IsLocked = true
    State.WallLossTimer = 0
    State.HasLineOfSight = true
    State.OrbitalOffset = 0

    if not RefreshTargetCache() then
        Unlock()
        return
    end

    pcall(function()
        Camera.CameraType = State.LockMode == "hard"
            and Enum.CameraType.Scriptable
            or Enum.CameraType.Custom
        UserInputService.MouseBehavior = State.LockMode == "hard"
            and Enum.MouseBehavior.LockCenter
            or Enum.MouseBehavior.Default
    end)

    EnableAutoFace()
    AttachIndicator(State.CachedTargetChar)

    if UI and UI.LockBtn then
        UI.LockBtn.Text = "◉"
        UI.LockBtn.BackgroundColor3 = Color3.fromRGB(200, 50, 50)
    end

    -- Auto-switch quando o target morrer
    if CONFIG.AutoSwitchOnKill and State.CachedTargetHum then
        Conn("TargetDied", State.CachedTargetHum.Died:Connect(function()
            task.defer(function()
                if not CONFIG.SystemEnabled then Unlock(); return end
                local nxt = FindBestTarget()
                if nxt then
                    LockOn(nxt)
                else
                    Unlock()
                end
            end)
        end))
    end

    -- Detecta se o target respawna / character muda
    Conn("TargetCharRemoved", target.CharacterRemoving:Connect(function()
        task.defer(function()
            if State.Target == target then
                if CONFIG.AutoSwitchOnKill then
                    local nxt = FindBestTarget()
                    if nxt then LockOn(nxt) else Unlock() end
                else
                    Unlock()
                end
            end
        end)
    end))
end

CycleTarget = function(direction)
    if not State.IsLocked or not CONFIG.SystemEnabled then return end

    -- Cooldown
    local now = tick()
    if now - State.LastCycleTime < CONFIG.CycleCooldown then
        State.BufferedCycleDir = direction
        return
    end
    State.LastCycleTime = now
    State.BufferedCycleDir = nil

    local targets = GetScoredTargets()
    if #targets <= 1 then return end

    local idx = 0
    for i, t in ipairs(targets) do
        if t.Target == State.Target then
            idx = i
            break
        end
    end

    idx = idx + direction
    if idx < 1 then idx = #targets end
    if idx > #targets then idx = 1 end

    LockOn(targets[idx].Target)
end

-- ══════════════════════════════════════════════════════
-- AUTO-LOCK ON HIT (detecta dano recebido)
-- ══════════════════════════════════════════════════════
local function SetupAutoLockOnHit()
    if not CONFIG.AutoLockOnHit or not State.Hum then return end

    local lastHP = State.Hum.Health

    Conn("AutoLockHP", State.Hum.HealthChanged:Connect(function(newHP)
        if newHP >= lastHP then
            lastHP = newHP
            return
        end
        lastHP = newHP

        -- Não auto-lock se já locked
        if State.IsLocked then
            TriggerDamageShake()
            return
        end

        if not CONFIG.SystemEnabled then return end

        -- Tenta achar quem está mais perto e na frente
        local best = FindBestTarget()
        if best then
            State.RecentAttackers[best.Name] = tick()
            LockOn(best)
            TriggerDamageShake()
        end
    end))
end

-- ══════════════════════════════════════════════════════
-- ORBITAL CAMERA (mouse horizontal move com lock)
-- ══════════════════════════════════════════════════════
local function UpdateOrbitalOffset(dt)
    if not CONFIG.OrbitalEnabled or not State.IsLocked or State.LockMode ~= "hard" then
        State.OrbitalOffset = 0
        return
    end

    local mouseDelta = UserInputService:GetMouseDelta()
    State.OrbitalOffset = State.OrbitalOffset + mouseDelta.X * CONFIG.OrbitalSpeed

    -- Clamp ao ângulo máximo
    State.OrbitalOffset = math.clamp(
        State.OrbitalOffset,
        -CONFIG.OrbitalMaxAngle,
        CONFIG.OrbitalMaxAngle
    )

    -- Decay natural de volta ao centro
    State.OrbitalOffset = State.OrbitalOffset * (1 - ExpDecay(CONFIG.OrbitalDecayRate, dt))
end

-- ══════════════════════════════════════════════════════
-- MAIN CAMERA LOOP
-- ══════════════════════════════════════════════════════
local UI = {}

local function UpdateCamera(dt)
    _frameCounter = _frameCounter + 1

    -- Sistema desativado
    if not CONFIG.SystemEnabled then
        if State.IsLocked then Unlock() end
        return
    end

    -- Atualiza FOV sempre (transição suave ao unlock também)
    UpdateDynamicFOV(dt)

    -- Atualiza shake
    UpdateCameraShake(dt)

    -- Se não está locked
    if not State.IsLocked or not State.Target or not State.Root then
        ApplyAimFriction(dt)
        return
    end

    -- Refresh cache
    if not RefreshTargetCache() then
        Unlock()
        return
    end

    -- Distância com fade
    local dist = (State.Root.Position - State.CachedTargetRoot.Position).Magnitude
    local maxDist = CONFIG.MaxLockDistance * CONFIG.UnlockFadeFull
    if dist > maxDist then
        Unlock()
        return
    end

    -- Wall check
    UpdateWallCheck(dt)

    -- Prediction
    UpdatePrediction(dt)

    -- Character facing
    UpdateCharacterFacing(dt)

    -- Indicator
    UpdateIndicator(dt)

    -- Orbital
    UpdateOrbitalOffset(dt)

    -- Buffered cycle
    if State.BufferedCycleDir and tick() - State.LastCycleTime >= CONFIG.CycleCooldown then
        CycleTarget(State.BufferedCycleDir)
    end

    -- Soft lock: não controla câmera
    if State.LockMode == "soft" then return end

    -- ═══ HARD LOCK CAMERA ═══
    local playerPos = State.Root.Position
    local aimPos = State.CachedAimPart and State.CachedAimPart.Position
        or (State.CachedTargetRoot.Position + Vector3.new(0, 2, 0))
    local predictedTarget = GetPredictedTargetPos()

    local toTarget = aimPos - playerPos
    local flatDir = Vector3.new(toTarget.X, 0, toTarget.Z)
    if flatDir.Magnitude < 0.5 then return end
    flatDir = flatDir.Unit

    -- Aplica offset orbital
    if math.abs(State.OrbitalOffset) > 0.001 then
        local orbitalCF = CFrame.Angles(0, State.OrbitalOffset, 0)
        flatDir = (orbitalCF * CFrame.new(flatDir)).Position
        if flatDir.Magnitude > 0.1 then flatDir = flatDir.Unit end
    end

    -- Posição da câmera
    local camGoal = playerPos - flatDir * CONFIG.CameraDistance + Vector3.new(0, CONFIG.CameraHeight, 0)
    local focusPoint = playerPos:Lerp(predictedTarget, CONFIG.LookAtBias)

    -- Shoulder offset
    local tempCF = CFrame.lookAt(camGoal, focusPoint)
    camGoal = camGoal + tempCF.RightVector * CONFIG.CameraShoulderOffset.X

    -- Unlock fade: suaviza ao se afastar
    local fadeStart = CONFIG.MaxLockDistance * CONFIG.UnlockFadeStart
    local fadeFull = CONFIG.MaxLockDistance * CONFIG.UnlockFadeFull
    local fadeAlpha = 1
    if dist > fadeStart then
        fadeAlpha = 1 - InverseLerp(fadeStart, fadeFull, dist)
    end

    -- Wall avoidance para câmera
    local wallResult = SphereCast(
        playerPos + Vector3.new(0, 2, 0),
        camGoal,
        0.5,
        GetAllCharactersCached()
    )
    if wallResult then
        camGoal = wallResult.Position + wallResult.Normal * 0.9
        if camGoal.Y < playerPos.Y + 1.5 then
            camGoal = Vector3.new(camGoal.X, playerPos.Y + 1.5, camGoal.Z)
        end
    end

    -- Aplica shake
    camGoal = camGoal + State.CameraShakeOffset

    local goalCF = CFrame.lookAt(camGoal, focusPoint)
    local smoothAlpha = ExpDecay(CONFIG.CamSmoothRate, dt) * fadeAlpha
    Camera.CFrame = SafeLerp(Camera.CFrame, goalCF, smoothAlpha)
end

-- ══════════════════════════════════════════════════════
-- BUILD UI
-- ══════════════════════════════════════════════════════
local MiniBlackFlashBtn = nil

local function BuildUI()
    if not PlayerGui then return end

    -- Limpa UI antiga
    local old = PlayerGui:FindFirstChild("LockOnUI_v6")
    if old then old:Destroy() end

    local screen = Instance.new("ScreenGui")
    screen.Name = "LockOnUI_v6"
    screen.ResetOnSpawn = false
    screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    screen.Parent = PlayerGui

    -- ═══════════ MENU HUB ═══════════
    local hubFrame = Instance.new("Frame")
    hubFrame.Name = "HubFrame"
    hubFrame.Size = UDim2.new(0, 220, 0, 290) -- maior pra caber tudo
    hubFrame.Position = UDim2.new(0.02, 0, 0.3, 0)
    hubFrame.BackgroundColor3 = Color3.fromRGB(15, 15, 20)
    hubFrame.BackgroundTransparency = 0.05
    hubFrame.BorderSizePixel = 0
    hubFrame.Active = true
    hubFrame.Parent = screen
    Instance.new("UICorner", hubFrame).CornerRadius = UDim.new(0, 10)

    local hubStroke = Instance.new("UIStroke")
    hubStroke.Color = Color3.fromRGB(255, 60, 60)
    hubStroke.Thickness = 1.5
    hubStroke.Transparency = 0.3
    hubStroke.Parent = hubFrame

    -- Título como handle de drag (não o frame inteiro, evita conflito com botões)
    local hubDragHandle = Instance.new("Frame")
    hubDragHandle.Name = "DragHandle"
    hubDragHandle.Size = UDim2.new(1, 0, 0, 35)
    hubDragHandle.BackgroundTransparency = 1
    hubDragHandle.Parent = hubFrame
    MakeDraggable(hubFrame) -- drag no frame todo funciona pq botões absorvem input

    local hubTitle = Instance.new("TextLabel")
    hubTitle.Size = UDim2.new(1, 0, 0, 35)
    hubTitle.BackgroundTransparency = 1
    hubTitle.Text = "⚡ LOCK-ON HUB v6.1"
    hubTitle.TextColor3 = Color3.fromRGB(255, 80, 80)
    hubTitle.Font = Enum.Font.GothamBold
    hubTitle.TextSize = 14
    hubTitle.Parent = hubFrame

    -- Container para botões (com padding e layout)
    local btnContainer = Instance.new("Frame")
    btnContainer.Name = "ButtonContainer"
    btnContainer.Size = UDim2.new(1, -20, 1, -45)
    btnContainer.Position = UDim2.new(0, 10, 0, 40)
    btnContainer.BackgroundTransparency = 1
    btnContainer.Parent = hubFrame

    local listLayout = Instance.new("UIListLayout")
    listLayout.Parent = btnContainer
    listLayout.Padding = UDim.new(0, 8)
    listLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
    listLayout.SortOrder = Enum.SortOrder.LayoutOrder

    -- Helper: cria botão do hub
    local function MakeHubButton(text, color, textColor, order)
        local btn = Instance.new("TextButton")
        btn.Size = UDim2.new(1, 0, 0, 38)
        btn.BackgroundColor3 = color
        btn.Text = text
        btn.TextColor3 = textColor or Color3.fromRGB(255, 255, 255)
        btn.Font = Enum.Font.GothamBold
        btn.TextSize = 13
        btn.LayoutOrder = order
        btn.AutoButtonColor = true
        btn.Parent = btnContainer
        Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 6)
        return btn
    end

    -- Botão 1: Toggle System
    local btnToggle = MakeHubButton(
        CONFIG.SystemEnabled and "ON — Sistema Ativo" or "OFF — Sistema Desativado",
        CONFIG.SystemEnabled and Color3.fromRGB(40, 120, 40) or Color3.fromRGB(120, 40, 40),
        nil, 1
    )

    -- Botão 2: Otimizar FPS
    local btnFPS = MakeHubButton("⚙ Otimizar FPS", Color3.fromRGB(35, 35, 50), Color3.fromRGB(180, 180, 255), 2)

    -- Botão 3: Toggle Black Flash Btn
    local btnBF = MakeHubButton("⚫ Toggle Black Flash", Color3.fromRGB(20, 20, 20), Color3.fromRGB(255, 60, 60), 3)
    local bfStroke = Instance.new("UIStroke")
    bfStroke.Color = Color3.fromRGB(255, 0, 0)
    bfStroke.Thickness = 1
    bfStroke.Parent = btnBF

    -- Botão 4: Moveset Troll
    local btnMoveset = MakeHubButton("🎭 Moveset Troll", Color3.fromRGB(80, 40, 120), nil, 4)

    -- Botão 5: Lock Mode Toggle
    local btnMode = MakeHubButton(
        "Mode: " .. string.upper(State.LockMode),
        Color3.fromRGB(40, 50, 80),
        Color3.fromRGB(150, 200, 255),
        5
    )

    -- ═══════════ BLACK FLASH FLOATING BUTTON ═══════════
    MiniBlackFlashBtn = Instance.new("TextButton")
    MiniBlackFlashBtn.Name = "BF_Button"
    MiniBlackFlashBtn.Size = UDim2.new(0, 65, 0, 65)
    MiniBlackFlashBtn.Position = UDim2.new(0.5, -32, 0.7, 0)
    MiniBlackFlashBtn.BackgroundColor3 = Color3.fromRGB(10, 10, 10)
    MiniBlackFlashBtn.Text = "B.FLASH\n0.28s"
    MiniBlackFlashBtn.TextColor3 = Color3.fromRGB(255, 0, 0)
    MiniBlackFlashBtn.TextScaled = true
    MiniBlackFlashBtn.Font = Enum.Font.GothamBlack
    MiniBlackFlashBtn.TextSize = 11
    MiniBlackFlashBtn.Visible = false
    MiniBlackFlashBtn.Active = true
    MiniBlackFlashBtn.Parent = screen
    Instance.new("UICorner", MiniBlackFlashBtn).CornerRadius = UDim.new(1, 0)

    local bfOuterStroke = Instance.new("UIStroke")
    bfOuterStroke.Color = Color3.fromRGB(255, 0, 0)
    bfOuterStroke.Thickness = 2
    bfOuterStroke.Parent = MiniBlackFlashBtn

    MakeDraggable(MiniBlackFlashBtn)

    -- ═══════════ LOCK-ON BUTTON (original) ═══════════
    local btnFrame = Instance.new("Frame")
    btnFrame.Name = "DragContainer"
    btnFrame.Size = UDim2.new(0, CONFIG.ButtonSize + 10, 0, CONFIG.ButtonSize + 10)
    btnFrame.Position = State.SavedButtonPos or CONFIG.DefaultButtonPos
    btnFrame.BackgroundTransparency = 1
    btnFrame.Active = true
    btnFrame.Parent = screen

    local lockBtn = Instance.new("TextButton")
    lockBtn.Size = UDim2.new(0, CONFIG.ButtonSize, 0, CONFIG.ButtonSize)
    lockBtn.Position = UDim2.new(0, 5, 0, 5)
    lockBtn.BackgroundColor3 = Color3.fromRGB(30, 30, 35)
    lockBtn.Text = "⊕"
    lockBtn.TextColor3 = Color3.fromRGB(190, 190, 200)
    lockBtn.TextScaled = true
    lockBtn.Font = Enum.Font.GothamBold
    lockBtn.AutoButtonColor = true
    lockBtn.Parent = btnFrame
    Instance.new("UICorner", lockBtn).CornerRadius = UDim.new(1, 0)

    local lockStroke = Instance.new("UIStroke")
    lockStroke.Color = Color3.fromRGB(100, 100, 110)
    lockStroke.Thickness = 1.5
    lockStroke.Parent = lockBtn

    -- Drag do botão lock-on
    local dragging, dragStart, startPos, totalDist = false, nil, nil, 0

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

    local btnDragConn1 = UserInputService.InputChanged:Connect(function(input)
        if not dragging then return end
        if input.UserInputType ~= Enum.UserInputType.Touch
            and input.UserInputType ~= Enum.UserInputType.MouseMovement then return end

        totalDist = math.max(totalDist, (input.Position - dragStart).Magnitude)
        if totalDist > CONFIG.DragThreshold then
            State.ButtonDragging = true
            btnFrame.Position = UDim2.new(
                startPos.X.Scale, startPos.X.Offset + (input.Position.X - dragStart.X),
                startPos.Y.Scale, startPos.Y.Offset + (input.Position.Y - dragStart.Y)
            )
        end
    end)

    local btnDragConn2 = UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.Touch
            or input.UserInputType == Enum.UserInputType.MouseButton1 then
            if dragging then
                dragging = false
                if State.ButtonDragging then
                    State.SavedButtonPos = btnFrame.Position
                end
                task.delay(0.05, function() State.ButtonDragging = false end)
            end
        end
    end)

    lockBtn.Destroying:Connect(function()
        btnDragConn1:Disconnect()
        btnDragConn2:Disconnect()
    end)

    -- ═══════════ MOBILE SWIPE (trocar target) ═══════════
    local swipeStartPos = nil
    local swipeStartTime = 0

    lockBtn.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.Touch then
            swipeStartPos = input.Position
            swipeStartTime = tick()
        end
    end)

    lockBtn.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.Touch and swipeStartPos then
            local delta = input.Position - swipeStartPos
            local timeElapsed = tick() - swipeStartTime
            
            if timeElapsed < CONFIG.SwipeTimeout and math.abs(delta.X) > CONFIG.SwipeThreshold and math.abs(delta.Y) < CONFIG.SwipeThreshold then
                if State.IsLocked then
                    if delta.X > 0 then
                        CycleTarget(1)
                    else
                        CycleTarget(-1)
                    end
                end
            end
            swipeStartPos = nil
        end
    end)

    -- ═══════════ HUB BUTTON ACTIONS ═══════════
    btnToggle.MouseButton1Click:Connect(function()
        CONFIG.SystemEnabled = not CONFIG.SystemEnabled
        btnToggle.BackgroundColor3 = CONFIG.SystemEnabled
            and Color3.fromRGB(40, 120, 40)
            or Color3.fromRGB(120, 40, 40)
        btnToggle.Text = CONFIG.SystemEnabled
            and "ON — Sistema Ativo"
            or "OFF — Sistema Desativado"
        if not CONFIG.SystemEnabled and State.IsLocked then
            Unlock()
        end
    end)

    btnFPS.MouseButton1Click:Connect(function()
        OptimizeFPS()
        btnFPS.Text = "✓ FPS Otimizado!"
        btnFPS.BackgroundColor3 = Color3.fromRGB(40, 100, 40)
        task.wait(1.5)
        btnFPS.Text = "⚙ Otimizar FPS"
        btnFPS.BackgroundColor3 = Color3.fromRGB(35, 35, 50)
    end)

    btnBF.MouseButton1Click:Connect(function()
        MiniBlackFlashBtn.Visible = not MiniBlackFlashBtn.Visible
        btnBF.Text = MiniBlackFlashBtn.Visible
            and "⚫ Black Flash: ON"
            or "⚫ Toggle Black Flash"
    end)

    btnMoveset.MouseButton1Click:Connect(function()
        UploadMovesetTroll()
        btnMoveset.Text = "✓ Moveset Enviado!"
        task.wait(1.5)
        btnMoveset.Text = "🎭 Moveset Troll"
    end)

    btnMode.MouseButton1Click:Connect(function()
        State.LockMode = State.LockMode == "hard" and "soft" or "hard"
        btnMode.Text = "Mode: " .. string.upper(State.LockMode)

        if State.IsLocked then
            pcall(function()
                Camera.CameraType = State.LockMode == "hard"
                    and Enum.CameraType.Scriptable
                    or Enum.CameraType.Custom
                UserInputService.MouseBehavior = State.LockMode == "hard"
                    and Enum.MouseBehavior.LockCenter
                    or Enum.MouseBehavior.Default
            end)
        end
    end)

    -- Black Flash action
    local bfCooldown = false
    MiniBlackFlashBtn.MouseButton1Click:Connect(function()
        if bfCooldown then return end
        bfCooldown = true

        -- Visual feedback
        MiniBlackFlashBtn.BackgroundColor3 = Color3.fromRGB(255, 0, 0)
        MiniBlackFlashBtn.TextColor3 = Color3.fromRGB(255, 255, 255)

        local function Press3()
            pcall(function()
                if keypress and keyrelease then
                    keypress(0x33)
                    task.wait(0.05)
                    keyrelease(0x33)
                elseif VirtualInput then
                    VirtualInput:SendKeyEvent(true, Enum.KeyCode.Three, false, game)
                    task.wait(0.05)
                    VirtualInput:SendKeyEvent(false, Enum.KeyCode.Three, false, game)
                end
            end)
        end

        Press3()
        task.wait(0.28)
        Press3()

        -- Reset visual
        MiniBlackFlashBtn.BackgroundColor3 = Color3.fromRGB(10, 10, 10)
        MiniBlackFlashBtn.TextColor3 = Color3.fromRGB(255, 0, 0)

        task.wait(0.15) -- mini cooldown anti-spam
        bfCooldown = false
    end)

    -- Lock button click
    lockBtn.MouseButton1Click:Connect(function()
        if State.ButtonDragging or not CONFIG.SystemEnabled then return end
        if State.IsLocked then
            Unlock()
        else
            local t = FindBestTarget()
            if t then LockOn(t) end
        end
    end)

    UI = {
        Screen = screen,
        BtnFrame = btnFrame,
        LockBtn = lockBtn,
        HubFrame = hubFrame,
        BtnToggle = btnToggle,
        BtnMode = btnMode,
    }
end

-- ══════════════════════════════════════════════════════
-- CHARACTER SETUP
-- ══════════════════════════════════════════════════════
local function OnCharacter(char)
    DisableAutoFace()
    RemoveIndicator()

    State.Char = char
    State.Hum = char:WaitForChild("Humanoid", 10)
    State.Root = char:WaitForChild("HumanoidRootPart", 10)

    if not State.Hum or not State.Root then return end

    if State.IsLocked then Unlock() end

    -- Reconecta auto-lock on hit
    SetupAutoLockOnHit()

    Conn("SelfDied", State.Hum.Died:Connect(function()
        DisableAutoFace()
        RemoveIndicator()
        Unlock()
    end))
end

-- ══════════════════════════════════════════════════════
-- KEYBOARD INPUT
-- ══════════════════════════════════════════════════════
UserInputService.InputBegan:Connect(function(input, processed)
    if processed or not CONFIG.SystemEnabled then return end
    local key = input.KeyCode

    if key == CONFIG.LockKey then
        if State.IsLocked then
            Unlock()
        else
            local t = FindBestTarget()
            if t then LockOn(t) end
        end

    elseif key == CONFIG.SoftLockKey then
        State.LockMode = State.LockMode == "hard" and "soft" or "hard"
        if State.IsLocked then
            pcall(function()
                Camera.CameraType = State.LockMode == "hard"
                    and Enum.CameraType.Scriptable
                    or Enum.CameraType.Custom
                UserInputService.MouseBehavior = State.LockMode == "hard"
                    and Enum.MouseBehavior.LockCenter
                    or Enum.MouseBehavior.Default
            end)
        end
        -- Sincroniza UI
        if UI.BtnMode then
            UI.BtnMode.Text = "Mode: " .. string.upper(State.LockMode)
        end

    elseif key == CONFIG.NextTargetKey then
        CycleTarget(1)

    elseif key == CONFIG.PrevTargetKey then
        CycleTarget(-1)
    end
end)

-- ══════════════════════════════════════════════════════
-- INIT
-- ══════════════════════════════════════════════════════
local function Init()
    -- MouseBehavior gerido dinamicamente

    BuildUI()

    if LocalPlayer.Character then
        task.spawn(function() OnCharacter(LocalPlayer.Character) end)
    end
    LocalPlayer.CharacterAdded:Connect(OnCharacter)

    -- Main render loop
    RunService.RenderStepped:Connect(UpdateCamera)

    print("══════════════════════════════════════════════════")
    print("  LOCK-ON SYSTEM v6.1 — FULL FIX & POLISH")
    print("  ✦ SphereCast implementado (com fallback)")
    print("  ✦ FOV dinâmico funcional")
    print("  ✦ Aim Friction funcional")
    print("  ✦ Wall-check com timeout e indicador visual")
    print("  ✦ Auto-lock on hit + Auto-switch on kill")
    print("  ✦ Camera shake de dano")
    print("  ✦ Orbital camera offset")
    print("  ✦ Target indicator (billboard)")
    print("  ✦ Cycle cooldown + buffer")
    print("  ✦ Unlock fade suave por distância")
    print("  ✦ Mobile swipe support")
    print("══════════════════════════════════════════════════")
end

Init()
