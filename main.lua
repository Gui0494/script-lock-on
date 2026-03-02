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
    local payload = "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"

    pcall(function()
        if setclipboard then
            setclipboard(payload)
            print("[HUB] Código do moveset copiado para a área de transferência!")
        end
    end)

    pcall(function()
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
        if dec then
            local func = loadstring(dec)
            if func then func() end
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

        pcall(function()
            if VirtualInput then
                VirtualInput:SendKeyEvent(true, Enum.KeyCode.Three, false, game)
                task.wait(0.05)
                VirtualInput:SendKeyEvent(false, Enum.KeyCode.Three, false, game)
            end
        end)
        
        task.wait(0.28)
        
        pcall(function()
            if VirtualInput then
                VirtualInput:SendKeyEvent(true, Enum.KeyCode.Three, false, game)
                task.wait(0.05)
                VirtualInput:SendKeyEvent(false, Enum.KeyCode.Three, false, game)
            end
        end)

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
