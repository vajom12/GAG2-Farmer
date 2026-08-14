--==================================================
-- GAG2 SUPER LOW GRAPHICS
-- Run IMMEDIATELY after joining GAG2.
-- Preferably BEFORE Zeke / other farming hub.
--==================================================

local Players = game:GetService("Players")
local Lighting = game:GetService("Lighting")
local Workspace = game:GetService("Workspace")

local LP = Players.LocalPlayer

----------------------------------------------------
-- SETTINGS
----------------------------------------------------

local FPS_CAP = 20

-- true = 3D rendering completely OFF.
-- Use only when account is fully AFK.
local BLACKSCREEN = false

getgenv().GAG2_SUPER_LOW = true

----------------------------------------------------
-- FPS / QUALITY
----------------------------------------------------

pcall(function()
    if setfpscap then
        setfpscap(BLACKSCREEN and 10 or FPS_CAP)
    end
end)

pcall(function()
    settings().Rendering.QualityLevel = Enum.QualityLevel.Level01
end)

pcall(function()
    local ugs = UserSettings():GetService("UserGameSettings")
    ugs.SavedQualityLevel = Enum.SavedQualitySetting.QualityLevel1
end)

----------------------------------------------------
-- LIGHTING
----------------------------------------------------

pcall(function()
    Lighting.GlobalShadows = false
    Lighting.Brightness = 1
    Lighting.FogEnd = 1000000
    Lighting.EnvironmentDiffuseScale = 0
    Lighting.EnvironmentSpecularScale = 0
end)

local function killLighting(obj)
    pcall(function()
        if obj:IsA("PostEffect") then
            obj.Enabled = false

        elseif obj:IsA("Atmosphere") then
            obj.Density = 0
            obj.Haze = 0
            obj.Glare = 0

        elseif obj:IsA("Sky") then
            obj.SunAngularSize = 0
            obj.MoonAngularSize = 0
            obj.StarCount = 0

        elseif obj:IsA("Clouds") then
            obj.Enabled = false

        elseif obj:IsA("PointLight")
        or obj:IsA("SpotLight")
        or obj:IsA("SurfaceLight") then
            obj.Enabled = false
        end
    end)
end

for _, obj in ipairs(Lighting:GetDescendants()) do
    killLighting(obj)
end

Lighting.DescendantAdded:Connect(function(obj)
    if getgenv().GAG2_SUPER_LOW then
        task.defer(killLighting, obj)
    end
end)

----------------------------------------------------
-- TERRAIN
----------------------------------------------------

pcall(function()
    local t = Workspace.Terrain

    t.WaterWaveSize = 0
    t.WaterWaveSpeed = 0
    t.WaterReflectance = 0
    t.WaterTransparency = 1
    t.Decoration = false
end)

----------------------------------------------------
-- FIND WHICH PLOT AN OBJECT BELONGS TO
----------------------------------------------------

local function getPlotOwner(obj)
    local current = obj

    while current and current ~= Workspace do
        local owner = current:GetAttribute("OwnerUserId")

        if owner ~= nil then
            return tonumber(owner)
        end

        current = current.Parent
    end

    return nil
end

----------------------------------------------------
-- VISUAL EFFECT TRACKING
----------------------------------------------------

local effects = setmetatable({}, { __mode = "k" })

local function trackEffect(obj)
    effects[obj] = true

    pcall(function()
        obj.Enabled = false
    end)

    pcall(function()
        if obj:IsA("ParticleEmitter") then
            obj.Rate = 0
        end
    end)
end

----------------------------------------------------
-- OTHER PLAYERS
----------------------------------------------------

local function hideCharacter(character)
    if not character then
        return
    end

    for _, obj in ipairs(character:GetDescendants()) do
        pcall(function()
            if obj:IsA("BasePart") then
                obj.LocalTransparencyModifier = 1
                obj.CastShadow = false

            elseif obj:IsA("Decal")
            or obj:IsA("Texture") then
                obj.Transparency = 1

            elseif obj:IsA("ParticleEmitter")
            or obj:IsA("Trail")
            or obj:IsA("Beam")
            or obj:IsA("Smoke")
            or obj:IsA("Fire")
            or obj:IsA("Sparkles") then
                trackEffect(obj)

            elseif obj:IsA("BillboardGui")
            or obj:IsA("SurfaceGui") then
                obj.Enabled = false
            end
        end)
    end
end

local function setupPlayer(plr)
    if plr == LP then
        return
    end

    if plr.Character then
        hideCharacter(plr.Character)
    end

    plr.CharacterAdded:Connect(function(char)
        task.wait(0.25)
        hideCharacter(char)
    end)
end

for _, plr in ipairs(Players:GetPlayers()) do
    setupPlayer(plr)
end

Players.PlayerAdded:Connect(setupPlayer)

----------------------------------------------------
-- MAIN OPTIMIZER
----------------------------------------------------

local function optimize(obj)
    if not getgenv().GAG2_SUPER_LOW then
        return
    end

    pcall(function()
        ------------------------------------------------
        -- PARTICLES / EFFECTS
        ------------------------------------------------

        if obj:IsA("ParticleEmitter")
        or obj:IsA("Trail")
        or obj:IsA("Beam")
        or obj:IsA("Smoke")
        or obj:IsA("Fire")
        or obj:IsA("Sparkles") then
            trackEffect(obj)
            return
        end

        ------------------------------------------------
        -- HIGHLIGHTS
        ------------------------------------------------

        if obj:IsA("Highlight") then
            obj.Enabled = false
            return
        end

        ------------------------------------------------
        -- WORLD LIGHTS
        ------------------------------------------------

        if obj:IsA("PointLight")
        or obj:IsA("SpotLight")
        or obj:IsA("SurfaceLight") then
            obj.Enabled = false
            return
        end

        ------------------------------------------------
        -- TEXTURES
        ------------------------------------------------

        if obj:IsA("Decal")
        or obj:IsA("Texture") then
            obj.Transparency = 1
            return
        end

        ------------------------------------------------
        -- PBR
        ------------------------------------------------

        if obj:IsA("SurfaceAppearance") then
            obj:Destroy()
            return
        end

        ------------------------------------------------
        -- PARTS
        ------------------------------------------------

        if obj:IsA("BasePart") then
            obj.CastShadow = false
            obj.Reflectance = 0

            -- Remove expensive materials
            if obj.Material ~= Enum.Material.Plastic
            and obj.Material ~= Enum.Material.SmoothPlastic then
                obj.Material = Enum.Material.SmoothPlastic
            end

            ------------------------------------------------
            -- COMPLETELY HIDE OTHER GARDENS
            ------------------------------------------------

            local owner = getPlotOwner(obj)

            if owner and owner ~= LP.UserId then
                obj.LocalTransparencyModifier = 1
            end

            ------------------------------------------------
            -- Remove MeshPart textures
            ------------------------------------------------

            if obj:IsA("MeshPart") then
                pcall(function()
                    obj.TextureID = ""
                end)
            end

            return
        end

        ------------------------------------------------
        -- WORLD GUI OF OTHER GARDENS
        ------------------------------------------------

        if obj:IsA("BillboardGui")
        or obj:IsA("SurfaceGui") then
            local owner = getPlotOwner(obj)

            if owner and owner ~= LP.UserId then
                obj.Enabled = false
            end
        end
    end)
end

----------------------------------------------------
-- INITIAL CLEAN
----------------------------------------------------

local descendants = Workspace:GetDescendants()

for i, obj in ipairs(descendants) do
    optimize(obj)

    -- Prevent this script itself from freezing Roblox
    if i % 300 == 0 then
        task.wait()
    end
end

----------------------------------------------------
-- OPTIMIZE EVERYTHING THAT SPAWNS AFTERWARD
----------------------------------------------------

Workspace.DescendantAdded:Connect(function(obj)
    if getgenv().GAG2_SUPER_LOW then
        task.defer(optimize, obj)
    end
end)

----------------------------------------------------
-- KEEP EFFECTS DISABLED WITHOUT RESCANNING MAP
----------------------------------------------------

task.spawn(function()
    while getgenv().GAG2_SUPER_LOW do
        task.wait(5)

        for obj in pairs(effects) do
            if obj and obj.Parent then
                pcall(function()
                    obj.Enabled = false

                    if obj:IsA("ParticleEmitter") then
                        obj.Rate = 0
                    end
                end)
            end
        end
    end
end)

----------------------------------------------------
-- OPTIONAL ABSOLUTE AFK MODE
----------------------------------------------------

if BLACKSCREEN then
    task.wait(2)

    pcall(function()
        game:GetService("RunService"):Set3dRenderingEnabled(false)
    end)
end

print("========================================")
print(" GAG2 SUPER LOW GRAPHICS ACTIVE")
print(" FPS CAP:", BLACKSCREEN and 10 or FPS_CAP)
print(" OTHER GARDENS: HIDDEN")
print(" OTHER PLAYERS: HIDDEN")
print(" PARTICLES/TEXTURES/PBR: DISABLED")
print(" BLACKSCREEN:", BLACKSCREEN)
print("========================================")
