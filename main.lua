--[[
    ╔══════════════════════════════════════════════════════════════╗
    ║        LOCK-ON TARGET SYSTEM v6.2 — COMBAT FIXES            ║
    ║        Menu Toggle • UI Clamp • Câmera Estável               ║
    ║        Fix Morte • Auto-Lock Toggle • Seta 2v1               ║
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

    -- ▸ Detecção de atacante (independente da câmera)
    AttackerFacingWeight   = 30,  -- bônus se o inimigo está virado pra você
    AttackerApproachWeight = 18,  -- bônus se o inimigo vem na sua direção

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
    CameraMaxSpeed       = 240,  -- studs/s máximos da câmera (anti-teleporte, por segundo e não por frame)
    CamWallRecoverRate   = 4,    -- velocidade de retorno da câmera após desviar de parede
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
    DashLeftKey          = Enum.KeyCode.Z,
    DashRightKey         = Enum.KeyCode.C,

    -- ▸ Mobile
    ButtonSize           = 62,
    DefaultButtonPos     = UDim2.new(1, -85, 0.35, 0),
    SwipeThreshold       = 55,
    SwipeTimeout         = 0.3,
    DragThreshold        = 8,

    -- ▸ Menu / UI
    MenuToggleSize       = 46,
    DefaultMenuTogglePos = UDim2.new(0.02, 0, 0.2, 0),
    DefaultHubPos        = UDim2.new(0.02, 0, 0.3, 0),
    DefaultBFPos         = UDim2.new(0.5, -32, 0.7, 0),
    MenuOpenDefault      = false,
    ViewportMargin       = 24,   -- mínimo de pixels visíveis ao clampar

    -- ▸ 2v1 (seta no segundo atacante)
    SecondThreatTimeout  = 3.0,  -- segundos sem novo dano antes de sumir a seta
    SecondThreatRange    = 120,  -- distância máxima pra considerar segundo atacante

    -- ▸ Side Dash
    DashSpeed            = 90,    -- studs/s durante o dash
    DashDuration         = 0.18,  -- duração do dash lateral (sem lock)
    DashCooldown         = 0.35,  -- cooldown antes do próximo dash
    DashMaxDuration      = 0.45,  -- teto do dash guiado (lockado)
    DashBehindDistance   = 5,     -- studs atrás do inimigo (ponto de chegada)
    DashStopRadius       = 3,     -- raio de chegada pra encerrar o dash guiado
    DashButtonSize       = 58,
    DefaultDashLeftPos   = UDim2.new(1, -150, 0.78, 0),
    DefaultDashRightPos  = UDim2.new(1, -85, 0.78, 0),
    ShowDashButtonsDefault = true,
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
    SmoothCamDist        = nil,  -- distância suavizada da câmera (desvio de parede)

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

    -- UI
    MenuOpen             = false,
    SavedMenuTogglePos   = nil,
    SavedHubPos          = nil,
    SavedBFPos           = nil,

    -- 2v1 second-attacker arrow
    SecondThreat         = nil,
    SecondThreatTime     = 0,
    ThreatArrow          = nil,

    -- Side dash
    Dashing              = false,
    SavedDashLeftPos     = nil,
    SavedDashRightPos    = nil,
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

-- Detecta NaN / inf num Vector3 (evita CFrame inválido travando a câmera)
local function IsFiniteVec(v)
    if typeof(v) ~= "Vector3" then return false end
    return v.X == v.X and v.Y == v.Y and v.Z == v.Z
        and v.Magnitude < math.huge
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

        -- Só reescreve o CFrame se a direção mudou de verdade: escrever todo
        -- frame sem necessidade faz o personagem (e a câmera) micro-tremer
        local curLook = State.Root.CFrame.LookVector
        local curFlat = Vector3.new(curLook.X, 0, curLook.Z)
        if curFlat.Magnitude < 0.1
            or curFlat.Unit:Dot(State.SmoothedFaceDir) < 0.99995 then
            State.Root.CFrame = CFrame.lookAt(
                State.Root.Position,
                State.Root.Position + State.SmoothedFaceDir
            )
        end
    end
end

-- ══════════════════════════════════════════════════════
-- UI UTILITIES
-- ══════════════════════════════════════════════════════
-- Mantém um GuiObject dentro da área do pai (ScreenGui).
-- Usa o espaço do PAI (não Camera.ViewportSize): coordenadas de GUI descontam o
-- GuiInset do topo, então viewport cru clampava errado no eixo Y.
local function ClampToViewport(frame)
    if not frame or not frame.Parent then return end
    local parent = frame.Parent
    local ok, area, parentAbsPos = pcall(function()
        return parent.AbsoluteSize, parent.AbsolutePosition
    end)
    if not ok or not area or area.X <= 0 or area.Y <= 0 then return end

    local absSize = frame.AbsoluteSize
    -- posição relativa ao pai (espaço em que Position/offset operam)
    local relX = frame.AbsolutePosition.X - parentAbsPos.X
    local relY = frame.AbsolutePosition.Y - parentAbsPos.Y
    local margin = CONFIG.ViewportMargin

    -- Contenção total quando o elemento cabe na área; senão, garante ≥ margin visível
    local minX, maxX, minY, maxY
    if absSize.X <= area.X then
        minX, maxX = 0, area.X - absSize.X
    else
        minX, maxX = area.X - absSize.X, 0 -- maior que a tela: encosta nas bordas
    end
    if absSize.Y <= area.Y then
        minY, maxY = 0, area.Y - absSize.Y
    else
        minY, maxY = -(absSize.Y - margin), area.Y - margin
    end

    local clampedX = math.clamp(relX, minX, maxX)
    local clampedY = math.clamp(relY, minY, maxY)

    if clampedX ~= relX or clampedY ~= relY then
        local pos = frame.Position
        frame.Position = UDim2.new(
            pos.X.Scale, math.floor(clampedX - pos.X.Scale * area.X + 0.5),
            pos.Y.Scale, math.floor(clampedY - pos.Y.Scale * area.Y + 0.5)
        )
    end
end

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
            ClampToViewport(frame) -- nunca deixa sair, nem durante o arrasto
        end
    end)

    local conn2 = UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
            if dragging then
                dragging = false
                ClampToViewport(frame)
            end
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
-- 2v1 — SETA NO SEGUNDO ATACANTE
-- ══════════════════════════════════════════════════════
local function CreateThreatArrow()
    local billboard = Instance.new("BillboardGui")
    billboard.Name = "SecondThreatArrow"
    billboard.Size = UDim2.new(0, 70, 0, 70)
    billboard.StudsOffset = Vector3.new(0, 4.2, 0)
    billboard.AlwaysOnTop = true
    billboard.LightInfluence = 0
    billboard.MaxDistance = CONFIG.SecondThreatRange + 40

    local label = Instance.new("TextLabel")
    label.Name = "Arrow"
    label.Size = UDim2.new(1, 0, 1, 0)
    label.BackgroundTransparency = 1
    label.Text = "⚠▼"
    label.TextColor3 = Color3.fromRGB(255, 170, 40)
    label.TextStrokeTransparency = 0.2
    label.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
    label.Font = Enum.Font.GothamBlack
    label.TextScaled = true
    label.Parent = billboard

    return billboard
end

local function RemoveSecondThreat()
    if State.ThreatArrow then
        pcall(function() State.ThreatArrow:Destroy() end)
        State.ThreatArrow = nil
    end
    State.SecondThreat = nil
    State.SecondThreatTime = 0
end

local function AttachThreatArrow(targetChar)
    if State.ThreatArrow then
        State.ThreatArrow:Destroy()
        State.ThreatArrow = nil
    end
    if not targetChar then return end
    local head = targetChar:FindFirstChild("Head")
    local root = targetChar:FindFirstChild("HumanoidRootPart")
    local parent = head or root
    if not parent then return end

    State.ThreatArrow = CreateThreatArrow()
    State.ThreatArrow.Adornee = parent
    State.ThreatArrow.Parent = parent
end

-- Acha o provável segundo atacante: inimigo vivo, != alvo atual, mais perto e na frente
-- Estima quem te atacou SEM usar a direção da câmera (o cliente não informa o agressor).
-- Heurística: inimigo mais próximo, virado pra você e/ou vindo na sua direção.
local function FindLikelyAttacker(excludeTarget, maxRange)
    if not State.Root then return nil end
    local myPos = State.Root.Position
    local eyePos = myPos + Vector3.new(0, 1.5, 0)
    local best, bestScore = nil, math.huge

    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= LocalPlayer and player ~= excludeTarget and Alive(player) then
            local _, root = GetParts(player)
            if root then
                local toMe = myPos - root.Position
                local dist = toMe.Magnitude
                if dist <= maxRange and dist > 0.01 then
                    local dirToMe = toMe.Unit

                    -- filtro leve: ignora quem está atrás de parede (evita lock errado)
                    if ClearSight(eyePos, root.Position + Vector3.new(0, 1.5, 0)) then
                        local score = dist

                        -- inimigo virado pra você = provável agressor
                        local facing = root.CFrame.LookVector:Dot(dirToMe)
                        score = score - facing * CONFIG.AttackerFacingWeight

                        -- inimigo se aproximando de você
                        local vel = root.Velocity
                        if vel.Magnitude > 1 then
                            local approach = vel.Unit:Dot(dirToMe)
                            if approach > 0 then
                                score = score - approach * CONFIG.AttackerApproachWeight
                            end
                        end

                        if score < bestScore then
                            bestScore = score
                            best = player
                        end
                    end
                end
            end
        end
    end
    return best
end

local function FindSecondAttacker()
    return FindLikelyAttacker(State.Target, CONFIG.SecondThreatRange)
end

-- Chamado quando o player leva dano estando lockado
local function FlagSecondThreat()
    local attacker = FindSecondAttacker()
    if not attacker then return end

    State.SecondThreatTime = tick()
    if State.SecondThreat ~= attacker then
        State.SecondThreat = attacker
        local char = attacker.Character
        AttachThreatArrow(char)
    end
end

-- Atualiza/expira a seta do segundo atacante
local function UpdateSecondThreat(dt)
    if not State.SecondThreat then return end

    -- Some se: não está mais lockado, virou o alvo principal, morreu, ou expirou
    local stillValid = State.IsLocked
        and State.SecondThreat ~= State.Target
        and Alive(State.SecondThreat)
        and (tick() - State.SecondThreatTime) < CONFIG.SecondThreatTimeout

    if not stillValid then
        RemoveSecondThreat()
        return
    end

    -- Reatacha se o character respawnou / a seta sumiu
    if not State.ThreatArrow or not State.ThreatArrow.Parent then
        AttachThreatArrow(State.SecondThreat.Character)
    end

    -- Pulsa o aviso pra chamar atenção
    if State.ThreatArrow then
        local arrow = State.ThreatArrow:FindFirstChild("Arrow")
        if arrow then
            local pulse = 0.5 + math.abs(math.sin(tick() * 6)) * 0.5
            arrow.TextTransparency = 1 - pulse
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
    State.SmoothCamDist = nil

    DisableAutoFace()
    RemoveIndicator()
    RemoveSecondThreat()
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

    -- Troca de alvo limpa o aviso de segundo atacante (contexto mudou)
    if State.SecondThreat == target or State.Target ~= target then
        RemoveSecondThreat()
    end

    State.Target = target
    State.IsLocked = true
    State.WallLossTimer = 0
    State.HasLineOfSight = true
    State.OrbitalOffset = 0

    -- Reset da predição: sem isso, trocar de alvo gera uma "velocidade" gigante
    -- (posição do alvo antigo → novo) e a câmera chicoteia/voa
    State.TargetVelocity = Vector3.zero
    State.SmoothedPrediction = Vector3.zero
    State.LastTargetPos = nil
    State.SmoothedFaceDir = nil
    State.SmoothCamDist = nil

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
-- SIDE DASH (lateral; lockado = contorna pras costas do alvo)
-- ══════════════════════════════════════════════════════
local function SideDash(side) -- side: -1 esquerda, +1 direita
    if State.Dashing or not CONFIG.SystemEnabled then return end
    local root = State.Root
    if not root then return end

    local function EndDash(faceEnemy)
        if State.Conns.Dash then
            pcall(function() State.Conns.Dash:Disconnect() end)
            State.Conns.Dash = nil
        end
        if faceEnemy then
            local r, enemy = State.Root, State.CachedTargetRoot
            if r and enemy then
                -- corta o embalo horizontal e encara o inimigo (pronto pra atacar)
                local v = r.AssemblyLinearVelocity
                r.AssemblyLinearVelocity = Vector3.new(0, v.Y, 0)
                local look = enemy.Position - r.Position
                look = Vector3.new(look.X, 0, look.Z)
                if look.Magnitude > 0.5 then
                    r.CFrame = CFrame.lookAt(r.Position, r.Position + look.Unit)
                    State.SmoothedFaceDir = look.Unit
                end
            end
        end
        task.delay(CONFIG.DashCooldown, function() State.Dashing = false end)
    end

    -- ── Sem lock: dash lateral simples relativo ao personagem ──
    if not (State.IsLocked and State.CachedTargetRoot) then
        local rv = root.CFrame.RightVector
        rv = Vector3.new(rv.X, 0, rv.Z)
        if rv.Magnitude < 0.1 then return end
        local dir = rv.Unit * side

        State.Dashing = true
        local startTime = tick()
        Conn("Dash", RunService.Heartbeat:Connect(function()
            local r = State.Root
            if not r or (tick() - startTime) >= CONFIG.DashDuration then
                EndDash(false)
                return
            end
            local curY = r.AssemblyLinearVelocity.Y
            r.AssemblyLinearVelocity = dir * CONFIG.DashSpeed + Vector3.new(0, curY, 0)
        end))
        return
    end

    -- ── Lockado: dash GUIADO — persegue o ponto às costas do inimigo ──
    -- (recalculado a cada frame, então funciona mesmo com o inimigo se movendo)
    State.Dashing = true
    local startTime = tick()

    Conn("Dash", RunService.Heartbeat:Connect(function()
        local r = State.Root
        local enemy = State.IsLocked and State.CachedTargetRoot or nil
        local elapsed = tick() - startTime

        if not r or not enemy or not enemy.Parent then
            EndDash(false)
            return
        end
        if elapsed >= CONFIG.DashMaxDuration then
            EndDash(true)
            return
        end

        -- Ponto às costas: oposto pra onde o inimigo está olhando
        local enemyPos = enemy.Position
        local fwd = enemy.CFrame.LookVector
        fwd = Vector3.new(fwd.X, 0, fwd.Z)
        local behind
        if fwd.Magnitude > 0.1 then
            behind = enemyPos - fwd.Unit * CONFIG.DashBehindDistance
        else
            -- fallback: lado oposto ao jogador
            local away = enemyPos - r.Position
            away = Vector3.new(away.X, 0, away.Z)
            if away.Magnitude < 0.1 then
                EndDash(true)
                return
            end
            behind = enemyPos + away.Unit * CONFIG.DashBehindDistance
        end

        local toBehind = Vector3.new(behind.X - r.Position.X, 0, behind.Z - r.Position.Z)
        if toBehind.Magnitude <= CONFIG.DashStopRadius then
            EndDash(true) -- chegou às costas: para e encara o inimigo
            return
        end

        -- Arco: começa tangencial (contorna pelo lado escolhido) e converge pro ponto
        local dir = toBehind.Unit
        local t = math.clamp(elapsed / CONFIG.DashMaxDuration, 0, 1)
        local toEnemyFlat = Vector3.new(enemyPos.X - r.Position.X, 0, enemyPos.Z - r.Position.Z)
        if toEnemyFlat.Magnitude > 0.1 then
            local tangent = toEnemyFlat.Unit:Cross(Vector3.yAxis) * side
            if tangent.Magnitude > 0.1 then
                dir = (dir + tangent.Unit * (1 - t)).Unit
            end
        end

        local curY = r.AssemblyLinearVelocity.Y
        r.AssemblyLinearVelocity = dir * CONFIG.DashSpeed + Vector3.new(0, curY, 0)
    end))
end

-- ══════════════════════════════════════════════════════
-- AUTO-LOCK ON HIT (detecta dano recebido)
-- ══════════════════════════════════════════════════════
local function SetupAutoLockOnHit()
    -- Sempre conecta: precisamos do evento de dano pro shake e pra detecção 2v1.
    -- O comportamento de auto-lock é decidido em runtime por CONFIG.AutoLockOnHit.
    if not State.Hum then return end

    local lastHP = State.Hum.Health

    Conn("AutoLockHP", State.Hum.HealthChanged:Connect(function(newHP)
        if newHP >= lastHP then
            lastHP = newHP
            return
        end
        lastHP = newHP

        if not CONFIG.SystemEnabled then return end

        -- Feedback de dano sempre
        TriggerDamageShake()

        -- Já lockado: mantém o alvo, mas sinaliza o segundo atacante (seta 2v1)
        if State.IsLocked then
            FlagSecondThreat()
            return
        end

        -- Sem lock: auto-lock só se o toggle estiver ligado
        if not CONFIG.AutoLockOnHit then return end

        -- Foca em quem te atacou (heurística), não em quem está na frente da câmera
        local best = FindLikelyAttacker(nil, CONFIG.MaxLockDistance) or FindBestTarget()
        if best then
            State.RecentAttackers[best.Name] = tick()
            LockOn(best)
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
        -- Não mexe na câmera se o personagem estiver morto (evita travar no chão)
        if State.Hum and State.Hum.Health > 0 then
            ApplyAimFriction(dt)
        end
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

    -- Seta do segundo atacante (2v1)
    UpdateSecondThreat(dt)

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

    -- Posição ideal da câmera
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

    -- Wall avoidance SUAVIZADO: em vez de saltar entre "atrás da parede" e
    -- "distância cheia" (o que fazia a câmera tremer), suavizamos a DISTÂNCIA:
    -- encurta na hora (não atravessa parede), alonga de volta devagar.
    local camOrigin = playerPos + Vector3.new(0, 2, 0)
    local toGoal = camGoal - camOrigin
    local fullDist = toGoal.Magnitude
    if fullDist > 0.1 then
        local goalDir = toGoal.Unit
        local desiredDist = fullDist

        local wallResult = SphereCast(camOrigin, camGoal, 0.5, GetAllCharactersCached())
        if wallResult then
            desiredDist = math.max((wallResult.Position - camOrigin).Magnitude - 0.9, 1.5)
        end

        if not State.SmoothCamDist then
            State.SmoothCamDist = desiredDist
        elseif desiredDist < State.SmoothCamDist then
            State.SmoothCamDist = desiredDist -- encurtar: instantâneo (evita clipar)
        else
            State.SmoothCamDist = SafeLerp(
                State.SmoothCamDist, desiredDist,
                ExpDecay(CONFIG.CamWallRecoverRate, dt)
            )
        end

        camGoal = camOrigin + goalDir * State.SmoothCamDist
    end

    -- Altura mínima sempre (nunca enterra a câmera no chão)
    if camGoal.Y < playerPos.Y + 1.5 then
        camGoal = Vector3.new(camGoal.X, playerPos.Y + 1.5, camGoal.Z)
    end

    -- Aplica shake
    camGoal = camGoal + State.CameraShakeOffset

    -- Guarda de sanidade: vetores inválidos travariam a câmera
    if not IsFiniteVec(camGoal) or not IsFiniteVec(focusPoint) then
        Unlock()
        return
    end

    -- Limita a velocidade da câmera (studs/s) pra bloquear teleporte sem afetar o follow normal
    local camPos = Camera.CFrame.Position
    local step = camGoal - camPos
    local maxStep = math.max(CONFIG.CameraMaxSpeed * dt, 1)
    if step.Magnitude > maxStep then
        camGoal = camPos + step.Unit * maxStep
    end

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
    -- Altura adaptativa: nunca maior que a tela (em celular o conteúdo rola)
    local screenH = screen.AbsoluteSize.Y
    if screenH <= 0 then screenH = Camera.ViewportSize.Y - 60 end
    local hubHeight = math.min(440, math.max(200, screenH - 20))

    local hubFrame = Instance.new("Frame")
    hubFrame.Name = "HubFrame"
    hubFrame.Size = UDim2.new(0, 220, 0, hubHeight)
    hubFrame.Position = State.SavedHubPos or CONFIG.DefaultHubPos
    State.MenuOpen = CONFIG.MenuOpenDefault
    hubFrame.Visible = State.MenuOpen
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
    hubTitle.Text = "⚡ LOCK-ON HUB v6.2"
    hubTitle.TextColor3 = Color3.fromRGB(255, 80, 80)
    hubTitle.Font = Enum.Font.GothamBold
    hubTitle.TextSize = 14
    hubTitle.Parent = hubFrame

    -- Container para botões: ScrollingFrame (rola quando a tela é pequena)
    local btnContainer = Instance.new("ScrollingFrame")
    btnContainer.Name = "ButtonContainer"
    btnContainer.Size = UDim2.new(1, -20, 1, -45)
    btnContainer.Position = UDim2.new(0, 10, 0, 40)
    btnContainer.BackgroundTransparency = 1
    btnContainer.BorderSizePixel = 0
    btnContainer.ScrollBarThickness = 4
    btnContainer.ScrollBarImageColor3 = Color3.fromRGB(255, 80, 80)
    btnContainer.ScrollingDirection = Enum.ScrollingDirection.Y
    btnContainer.CanvasSize = UDim2.new(0, 0, 0, 0)
    -- A propriedade AutomaticCanvasSize usa o enum Enum.AutomaticSize.
    -- pcall pra degradar em clientes/executores antigos sem derrubar a UI toda.
    pcall(function()
        btnContainer.AutomaticCanvasSize = Enum.AutomaticSize.Y
    end)
    btnContainer.Parent = hubFrame

    local listLayout = Instance.new("UIListLayout")
    listLayout.Parent = btnContainer
    listLayout.Padding = UDim.new(0, 8)
    listLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
    listLayout.SortOrder = Enum.SortOrder.LayoutOrder

    -- Helper: cria botão do hub
    local function MakeHubButton(text, color, textColor, order)
        local btn = Instance.new("TextButton")
        btn.Size = UDim2.new(1, -8, 0, 38) -- -8 deixa espaço pra barra de rolagem
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

    -- Botão 6: Auto-Lock ao Apanhar (toggle)
    local btnAutoLock = MakeHubButton(
        CONFIG.AutoLockOnHit and "🎯 Auto-Lock ao Apanhar: ON" or "🎯 Auto-Lock ao Apanhar: OFF",
        CONFIG.AutoLockOnHit and Color3.fromRGB(40, 110, 90) or Color3.fromRGB(70, 70, 80),
        nil, 6
    )

    -- Botão 7: Side Dash (toggle visibilidade dos botões de dash)
    local btnDash = MakeHubButton(
        CONFIG.ShowDashButtonsDefault and "💨 Side Dash: ON" or "💨 Side Dash: OFF",
        CONFIG.ShowDashButtonsDefault and Color3.fromRGB(25, 60, 90) or Color3.fromRGB(70, 70, 80),
        Color3.fromRGB(140, 200, 255), 7
    )

    -- Botão 8: Resetar posições dos botões
    local btnReset = MakeHubButton("↺ Resetar Posições", Color3.fromRGB(60, 45, 25), Color3.fromRGB(255, 210, 150), 8)

    -- ═══════════ BLACK FLASH FLOATING BUTTON ═══════════
    MiniBlackFlashBtn = Instance.new("TextButton")
    MiniBlackFlashBtn.Name = "BF_Button"
    MiniBlackFlashBtn.Size = UDim2.new(0, 65, 0, 65)
    MiniBlackFlashBtn.Position = State.SavedBFPos or CONFIG.DefaultBFPos
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

    -- ═══════════ MENU TOGGLE (abre/fecha o hub) ═══════════
    local menuToggle = Instance.new("TextButton")
    menuToggle.Name = "MenuToggle"
    menuToggle.Size = UDim2.new(0, CONFIG.MenuToggleSize, 0, CONFIG.MenuToggleSize)
    menuToggle.Position = State.SavedMenuTogglePos or CONFIG.DefaultMenuTogglePos
    menuToggle.BackgroundColor3 = Color3.fromRGB(20, 20, 28)
    menuToggle.Text = "☰"
    menuToggle.TextColor3 = Color3.fromRGB(255, 90, 90)
    menuToggle.TextScaled = true
    menuToggle.Font = Enum.Font.GothamBold
    menuToggle.Active = true
    menuToggle.Parent = screen
    Instance.new("UICorner", menuToggle).CornerRadius = UDim.new(0, 10)
    local mtStroke = Instance.new("UIStroke")
    mtStroke.Color = Color3.fromRGB(255, 60, 60)
    mtStroke.Thickness = 1.5
    mtStroke.Transparency = 0.3
    mtStroke.Parent = menuToggle

    -- Helper: botão flutuante com tap (ação) vs arrasto (mover) + clamp
    local function WireTapDrag(btn, onTap, onMoved)
        local dragging, dragStart, startPos, moved = false, nil, nil, false
        btn.InputBegan:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.Touch
                or input.UserInputType == Enum.UserInputType.MouseButton1 then
                dragging = true
                dragStart = input.Position
                startPos = btn.Position
                moved = false
            end
        end)
        local c1 = UserInputService.InputChanged:Connect(function(input)
            if not dragging then return end
            if input.UserInputType ~= Enum.UserInputType.Touch
                and input.UserInputType ~= Enum.UserInputType.MouseMovement then return end
            local delta = input.Position - dragStart
            if delta.Magnitude > CONFIG.DragThreshold then
                moved = true
                btn.Position = UDim2.new(
                    startPos.X.Scale, startPos.X.Offset + delta.X,
                    startPos.Y.Scale, startPos.Y.Offset + delta.Y
                )
                ClampToViewport(btn)
            end
        end)
        local c2 = UserInputService.InputEnded:Connect(function(input)
            if (input.UserInputType == Enum.UserInputType.Touch
                or input.UserInputType == Enum.UserInputType.MouseButton1) and dragging then
                dragging = false
                if moved then
                    ClampToViewport(btn)
                    if onMoved then onMoved(btn) end
                elseif onTap then
                    onTap()
                end
            end
        end)
        btn.Destroying:Connect(function()
            c1:Disconnect()
            c2:Disconnect()
        end)
    end

    WireTapDrag(menuToggle, function()
        State.MenuOpen = not State.MenuOpen
        hubFrame.Visible = State.MenuOpen
        menuToggle.BackgroundColor3 = State.MenuOpen
            and Color3.fromRGB(200, 50, 50)
            or Color3.fromRGB(20, 20, 28)
        if State.MenuOpen then ClampToViewport(hubFrame) end
    end, function(b)
        State.SavedMenuTogglePos = b.Position
    end)

    -- ═══════════ SIDE DASH BUTTONS (flutuantes) ═══════════
    local function MakeDashButton(text, pos)
        local b = Instance.new("TextButton")
        b.Name = "DashButton"
        b.Size = UDim2.new(0, CONFIG.DashButtonSize, 0, CONFIG.DashButtonSize)
        b.Position = pos
        b.BackgroundColor3 = Color3.fromRGB(25, 35, 55)
        b.Text = text
        b.TextColor3 = Color3.fromRGB(140, 200, 255)
        b.TextScaled = true
        b.Font = Enum.Font.GothamBlack
        b.Visible = CONFIG.ShowDashButtonsDefault
        b.Active = true
        b.Parent = screen
        Instance.new("UICorner", b).CornerRadius = UDim.new(0, 12)
        local s = Instance.new("UIStroke")
        s.Color = Color3.fromRGB(80, 160, 255)
        s.Thickness = 1.5
        s.Transparency = 0.2
        s.Parent = b
        return b
    end

    local dashLeftBtn = MakeDashButton("⟵", State.SavedDashLeftPos or CONFIG.DefaultDashLeftPos)
    local dashRightBtn = MakeDashButton("⟶", State.SavedDashRightPos or CONFIG.DefaultDashRightPos)

    WireTapDrag(dashLeftBtn, function() SideDash(-1) end, function(b)
        State.SavedDashLeftPos = b.Position
    end)
    WireTapDrag(dashRightBtn, function() SideDash(1) end, function(b)
        State.SavedDashRightPos = b.Position
    end)

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
            ClampToViewport(btnFrame)
        end
    end)

    local btnDragConn2 = UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.Touch
            or input.UserInputType == Enum.UserInputType.MouseButton1 then
            if dragging then
                dragging = false
                if State.ButtonDragging then
                    ClampToViewport(btnFrame)
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

    -- Botão 6: Auto-Lock ao Apanhar (toggle)
    btnAutoLock.MouseButton1Click:Connect(function()
        CONFIG.AutoLockOnHit = not CONFIG.AutoLockOnHit
        btnAutoLock.Text = CONFIG.AutoLockOnHit
            and "🎯 Auto-Lock ao Apanhar: ON"
            or "🎯 Auto-Lock ao Apanhar: OFF"
        btnAutoLock.BackgroundColor3 = CONFIG.AutoLockOnHit
            and Color3.fromRGB(40, 110, 90)
            or Color3.fromRGB(70, 70, 80)
    end)

    -- Botão 7: Side Dash (mostra/esconde os botões de dash)
    btnDash.MouseButton1Click:Connect(function()
        local vis = not dashLeftBtn.Visible
        dashLeftBtn.Visible = vis
        dashRightBtn.Visible = vis
        btnDash.Text = vis and "💨 Side Dash: ON" or "💨 Side Dash: OFF"
        btnDash.BackgroundColor3 = vis
            and Color3.fromRGB(25, 60, 90)
            or Color3.fromRGB(70, 70, 80)
    end)

    -- Botão 8: Resetar posições de todos os botões
    btnReset.MouseButton1Click:Connect(function()
        State.SavedButtonPos = nil
        State.SavedBFPos = nil
        State.SavedMenuTogglePos = nil
        State.SavedHubPos = nil
        State.SavedDashLeftPos = nil
        State.SavedDashRightPos = nil
        btnFrame.Position = CONFIG.DefaultButtonPos
        MiniBlackFlashBtn.Position = CONFIG.DefaultBFPos
        menuToggle.Position = CONFIG.DefaultMenuTogglePos
        hubFrame.Position = CONFIG.DefaultHubPos
        dashLeftBtn.Position = CONFIG.DefaultDashLeftPos
        dashRightBtn.Position = CONFIG.DefaultDashRightPos
        btnReset.Text = "✓ Posições Resetadas!"
        task.wait(1.2)
        btnReset.Text = "↺ Resetar Posições"
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
                if VirtualInput then
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
        BFButton = MiniBlackFlashBtn,
        MenuToggle = menuToggle,
        DashLeft = dashLeftBtn,
        DashRight = dashRightBtn,
    }
end

-- Reposiciona todos os elementos visíveis pra dentro da tela
local function ReclampAllUI()
    if UI.HubFrame and UI.HubFrame.Visible then ClampToViewport(UI.HubFrame) end
    if UI.BtnFrame then ClampToViewport(UI.BtnFrame) end
    if UI.BFButton and UI.BFButton.Visible then ClampToViewport(UI.BFButton) end
    if UI.MenuToggle then ClampToViewport(UI.MenuToggle) end
    if UI.DashLeft and UI.DashLeft.Visible then ClampToViewport(UI.DashLeft) end
    if UI.DashRight and UI.DashRight.Visible then ClampToViewport(UI.DashRight) end
end

-- ══════════════════════════════════════════════════════
-- CHARACTER SETUP
-- ══════════════════════════════════════════════════════
-- Devolve o controle da câmera ao Roblox (usado ao morrer / respawnar)
local function ReleaseCamera(subject)
    pcall(function()
        Camera = workspace.CurrentCamera or Camera
        Camera.CameraType = Enum.CameraType.Custom
        if subject then
            Camera.CameraSubject = subject
        end
        UserInputService.MouseBehavior = Enum.MouseBehavior.Default
        State.CurrentFOV = State.DefaultFOV
        Camera.FieldOfView = State.DefaultFOV
    end)
end

local function OnCharacter(char)
    DisableAutoFace()
    RemoveIndicator()
    RemoveSecondThreat()

    State.Char = char
    State.Hum = char:WaitForChild("Humanoid", 10)
    State.Root = char:WaitForChild("HumanoidRootPart", 10)

    if not State.Hum or not State.Root then return end

    if State.IsLocked then Unlock() end

    -- Garante que o respawn volte a seguir o personagem novo (corrige câmera travada)
    ReleaseCamera(State.Hum)

    -- Reconecta auto-lock on hit
    SetupAutoLockOnHit()

    Conn("SelfDied", State.Hum.Died:Connect(function()
        DisableAutoFace()
        RemoveIndicator()
        RemoveSecondThreat()
        Unlock()
        -- Solta a câmera no local da morte pra não ficar travada no chão
        ReleaseCamera(State.Hum)
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

    elseif key == CONFIG.DashLeftKey then
        SideDash(-1)

    elseif key == CONFIG.DashRightKey then
        SideDash(1)
    end
end)

-- ══════════════════════════════════════════════════════
-- INIT
-- ══════════════════════════════════════════════════════
local function Init()
    -- MouseBehavior gerido dinamicamente

    -- BuildUI isolado: se algo na UI falhar, o resto do sistema (câmera, input)
    -- ainda conecta, em vez de deixar tudo silencioso
    local uiOk, uiErr = pcall(BuildUI)
    if not uiOk then
        warn("[Lock-On] Falha ao montar a UI: " .. tostring(uiErr))
    else
        -- Clamp inicial (deferido: AbsoluteSize só é válido após o primeiro layout)
        task.defer(ReclampAllUI)
    end

    if LocalPlayer.Character then
        task.spawn(function() OnCharacter(LocalPlayer.Character) end)
    end
    LocalPlayer.CharacterAdded:Connect(OnCharacter)

    -- Referência dinâmica da câmera (alguns jogos recriam a CurrentCamera no respawn)
    local function BindViewportListener()
        Conn("ViewportSize", Camera:GetPropertyChangedSignal("ViewportSize"):Connect(ReclampAllUI))
    end
    BindViewportListener()
    Conn("CurrentCamera", workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
        if workspace.CurrentCamera then
            Camera = workspace.CurrentCamera
            State.DefaultFOV = Camera.FieldOfView
            BindViewportListener()
        end
    end))

    -- Main render loop
    RunService.RenderStepped:Connect(UpdateCamera)

    print("══════════════════════════════════════════════════")
    print("  LOCK-ON SYSTEM v6.2 — COMBAT FIXES")
    print("  ✦ Menu com botão de abrir/fechar (☰)")
    print("  ✦ Botões e menu não saem mais da tela (clamp + reset)")
    print("  ✦ Câmera no lock estável (anti-teleporte/overshoot)")
    print("  ✦ Fix: câmera não trava mais no chão ao morrer")
    print("  ✦ Auto-lock ao apanhar agora é toggle no menu")
    print("  ✦ 2v1: seta aponta o segundo atacante")
    print("  ✦ Auto-lock foca em quem te atacou (não na frente)")
    print("  ✦ Side Dash (Z/C ou botões) — contorna pras costas do alvo")
    print("══════════════════════════════════════════════════")
end

-- Init protegido: qualquer erro vira aviso no console em vez de matar o script
local initOk, initErr = pcall(Init)
if not initOk then
    warn("[Lock-On] Erro no Init: " .. tostring(initErr))
end
