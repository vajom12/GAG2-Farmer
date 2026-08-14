--==================================================
-- GAG2 GARDEN CENTER TELEPORT
-- Teleports the local player to the center of their garden plot.
-- Useful for quickly returning to the garden while testing/farming.
--==================================================

local Players = game:GetService("Players")
local LP = Players.LocalPlayer

local function getHRP()
    local char = LP.Character or LP.CharacterAdded:Wait()
    return char:WaitForChild("HumanoidRootPart")
end

local function findMyPlot()
    for _, obj in ipairs(workspace:GetDescendants()) do
        if obj:GetAttribute("OwnerUserId") == LP.UserId then
            return obj
        end
    end
end

local function getCenter(obj)
    -- Ako je plot Model
    if obj:IsA("Model") then
        local cf = obj:GetBoundingBox()
        return cf.Position
    end

    -- Ako je Folder ili nešto drugo, izračunaj sredinu svih njegovih partova
    local minV, maxV

    for _, v in ipairs(obj:GetDescendants()) do
        if v:IsA("BasePart") then
            local p = v.Position

            if not minV then
                minV = p
                maxV = p
            else
                minV = Vector3.new(
                    math.min(minV.X, p.X),
                    math.min(minV.Y, p.Y),
                    math.min(minV.Z, p.Z)
                )

                maxV = Vector3.new(
                    math.max(maxV.X, p.X),
                    math.max(maxV.Y, p.Y),
                    math.max(maxV.Z, p.Z)
                )
            end
        end
    end

    if minV and maxV then
        return (minV + maxV) / 2
    end
end

local plot = findMyPlot()

if not plot then
    warn("Nisam pronašao tvoj garden plot.")
    return
end

local center = getCenter(plot)

if not center then
    warn("Našao sam plot, ali ne mogu odrediti sredinu.")
    return
end

local hrp = getHRP()

-- +4 Y da ne završiš u zemlji/biljkama
hrp.CFrame = CFrame.new(center + Vector3.new(0, 4, 0))

print("Teleportovan u sredinu svoje bašte.")
