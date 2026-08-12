--========================================================
-- GAG2 FARMER V3.1 CORE
-- Plant -> Harvest -> Sell. Economy buying is handled by economy_v31.lua
--========================================================

local CFG = {
    AutoHarvest = true,
    AutoSell = true,
    AutoPlant = true,
    SellAtPercent = 85,
    SellEverySeconds = 35,
    PlantEverySeconds = 4,
    PlantDelay = 0.12,
    MaxPlantPerCycle = 35,
    GridStep = 6,
    LoopDelay = 1,
}

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local StarterGui = game:GetService("StarterGui")
local VirtualUser = game:GetService("VirtualUser")
local Workspace = game:GetService("Workspace")

local LP = Players.LocalPlayer
local ENV = (getgenv and getgenv()) or _G
repeat task.wait() until game:IsLoaded()

if ENV.GAG2_CORE_V31_STOP then pcall(ENV.GAG2_CORE_V31_STOP) end
if ENV.GAG2_V2_STOP then pcall(ENV.GAG2_V2_STOP) end

local running = true
ENV.GAG2_CORE_V31_STOP = function() running = false end

local Net = require(ReplicatedStorage:WaitForChild("SharedModules"):WaitForChild("Networking"))
local PSC
pcall(function()
    PSC = require(ReplicatedStorage:WaitForChild("ClientModules"):WaitForChild("PlayerStateClient"))
end)

local function notify(text)
    print("[GAG2 V3.1 CORE]", text)
    pcall(function()
        StarterGui:SetCore("SendNotification", {Title="GAG2 V3.1 Core", Text=text, Duration=4})
    end)
end

local function fire(packet, ...)
    if not packet then return false end
    local args = {...}
    local ok, err = pcall(function() packet:Fire(table.unpack(args)) end)
    if not ok then warn("[GAG2 V3.1 CORE] Fire error:", err) end
    return ok
end

local function locked()
    return ENV.GAG2_V31_ACTIVITY_LOCK ~= nil
end

local function getData()
    if not PSC then return nil end
    local ok, r = pcall(function() return PSC:GetLocalReplica() end)
    return ok and r and r.Data or nil
end

local function getOwnedSeeds()
    local d = getData()
    return d and d.Inventory and d.Inventory.Seeds or nil
end

local Gardens = Workspace:WaitForChild("Gardens")
local function myPlot()
    local pid = LP:GetAttribute("PlotId")
    if pid ~= nil then
        local p = Gardens:FindFirstChild("Plot" .. tostring(pid))
        if p then return p end
    end
    for _, p in ipairs(Gardens:GetChildren()) do
        if p:GetAttribute("OwnerUserId") == LP.UserId or p:GetAttribute("Owner") == LP.Name then return p end
    end
end

local function ensureGarden()
    if locked() then return end
    if LP:GetAttribute("IsInOwnGarden") == true then return end
    pcall(function() fire(Net.TeleportButton.Request, "Garden") end)
    task.wait(0.6)
end

local function ripe(m)
    local age = tonumber(m:GetAttribute("Age"))
    local mx = tonumber(m:GetAttribute("MaxAge"))
    return age and mx and age >= mx - 0.001
end

local function harvestAll()
    if not CFG.AutoHarvest or locked() then return 0 end
    local plot = myPlot(); if not plot then return 0 end
    local plants = plot:FindFirstChild("Plants"); if not plants then return 0 end
    ensureGarden()
    local n = 0
    for _, plant in ipairs(plants:GetChildren()) do
        if locked() then break end
        local ff = plant:FindFirstChild("Fruits")
        local fruits = ff and ff:GetChildren() or {}
        if #fruits > 0 then
            for _, fruit in ipairs(fruits) do
                if ripe(fruit) then
                    local pid = fruit:GetAttribute("PlantId")
                    if pid then
                        fire(Net.Garden.CollectFruit, pid, fruit:GetAttribute("FruitId") or "")
                        n += 1
                        task.wait(0.04)
                    end
                end
            end
        elseif ripe(plant) then
            local pid = plant:GetAttribute("PlantId")
            if pid then
                fire(Net.Garden.CollectFruit, pid, plant:GetAttribute("FruitId") or "")
                n += 1
                task.wait(0.04)
            end
        end
    end
    if n > 0 then print("[GAG2 V3.1 CORE] Harvested", n) end
    return n
end

local lastSell = 0
local function shouldSell()
    if not CFG.AutoSell or locked() then return false end
    local count = tonumber(LP:GetAttribute("FruitCount")) or 0
    local max = tonumber(LP:GetAttribute("MaxFruitCapacity")) or 100
    if count <= 0 then return false end
    return (count / math.max(max,1))*100 >= CFG.SellAtPercent or os.clock()-lastSell >= CFG.SellEverySeconds
end

local function sellAll()
    if locked() then return end
    local count = tonumber(LP:GetAttribute("FruitCount")) or 0
    if count <= 0 then return end
    fire(Net.NPCS.SellAll)
    lastSell = os.clock()
    print("[GAG2 V3.1 CORE] Sold", count, "fruits")
    task.wait(0.2)
end

local function plantAreas(plot)
    local out = {}
    for _, p in ipairs(CollectionService:GetTagged("PlantArea")) do
        if p:IsA("BasePart") and p:IsDescendantOf(plot) and p.Size.X*p.Size.Z > 400 then table.insert(out,p) end
    end
    if #out == 0 then
        local ref = plot:FindFirstChild("PlotSizeReference")
        if ref and ref:IsA("BasePart") then table.insert(out,ref) end
    end
    return out
end

local function gridPositions(plot)
    local out, step = {}, CFG.GridStep
    for _, area in ipairs(plantAreas(plot)) do
        local cf, sz = area.CFrame, area.Size
        local hx, hz = math.max(0,sz.X/2-3), math.max(0,sz.Z/2-3)
        local nx, nz = math.floor((2*hx)/step), math.floor((2*hz)/step)
        local y = area.Position.Y + sz.Y/2 + 0.3
        for ix=0,nx do
            for iz=0,nz do
                local w = (cf*CFrame.new(-hx+ix*step,0,-hz+iz*step)).Position
                table.insert(out, Vector3.new(w.X,y,w.Z))
            end
        end
    end
    return out
end

local function freePositions(plot)
    local occ, free = {}, {}
    local plants = plot:FindFirstChild("Plants")
    if plants then
        for _, pl in ipairs(plants:GetChildren()) do
            local ok, pos = pcall(function() return pl:GetPivot().Position end)
            if ok then table.insert(occ,pos) end
        end
    end
    for _, pos in ipairs(gridPositions(plot)) do
        local clear = true
        for _, used in ipairs(occ) do
            if (Vector3.new(pos.X,0,pos.Z)-Vector3.new(used.X,0,used.Z)).Magnitude < 5.5 then clear=false break end
        end
        if clear then table.insert(free,pos) end
    end
    return free
end

local function seedsToPlant()
    local owned = getOwnedSeeds(); if not owned then return {} end
    local rows = {}
    local scores = ENV.GAG2_V31_SEED_SCORE or {}
    for name,count in pairs(owned) do
        count = tonumber(count) or 0
        if count > 0 then table.insert(rows,{name=name,count=count,score=tonumber(scores[name]) or 0}) end
    end
    table.sort(rows,function(a,b)
        if a.score == b.score then return a.name < b.name end
        return a.score > b.score
    end)
    local out = {}
    for _, row in ipairs(rows) do
        for _=1,math.min(row.count,CFG.MaxPlantPerCycle) do
            table.insert(out,row.name)
            if #out >= CFG.MaxPlantPerCycle then return out end
        end
    end
    return out
end

local function autoPlant()
    if not CFG.AutoPlant or locked() then return end
    if not Net.Plant or not Net.Plant.PlantSeed then return end
    local plot = myPlot(); if not plot then return end
    local seeds = seedsToPlant(); if #seeds == 0 then return end
    ensureGarden()
    local free = freePositions(plot); if #free == 0 then return end
    local total = math.min(#free,#seeds,CFG.MaxPlantPerCycle)
    local n = 0
    for i=1,total do
        if locked() then break end
        if fire(Net.Plant.PlantSeed,free[i],seeds[i],plot) then n += 1 end
        task.wait(CFG.PlantDelay)
    end
    if n > 0 then print("[GAG2 V3.1 CORE] Plant attempts",n) end
end

pcall(function()
    LP.Idled:Connect(function()
        VirtualUser:Button2Down(Vector2.new(0,0),Workspace.CurrentCamera.CFrame)
        task.wait(0.4)
        VirtualUser:Button2Up(Vector2.new(0,0),Workspace.CurrentCamera.CFrame)
    end)
end)

notify("Core loaded: Plant > Harvest > Sell")
local lastPlant = 0
task.spawn(function()
    while running do
        if not locked() then
            pcall(harvestAll)
            task.wait(0.12)
            if shouldSell() then pcall(sellAll) end
            if os.clock()-lastPlant >= CFG.PlantEverySeconds then
                lastPlant=os.clock(); pcall(autoPlant)
            end
        end
        task.wait(CFG.LoopDelay)
    end
end)
