--========================================================
-- GAG2 FARMER V3.3.1 - SAFE PUNK BASE
-- Stable baseline first: harvest -> sell -> buy -> plant.
-- Extra systems stay OFF until this core is proven live.
--========================================================

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local Workspace = game:GetService("Workspace")
local StarterGui = game:GetService("StarterGui")
local VirtualUser = game:GetService("VirtualUser")

local LP = Players.LocalPlayer
local ENV = (getgenv and getgenv()) or _G
repeat task.wait() until game:IsLoaded() and LP

for _, key in ipairs({
    "GAG2_V331_STOP", "GAG2_V33_STOP", "GAG2_BRAIN_V32_STOP",
    "GAG2_CORE_V31_STOP", "GAG2_ECON_V31_STOP", "GAG2_EVENT_V31_STOP",
    "GAG2_V2_STOP", "GAG2_EVENT_V3_STOP"
}) do
    local fn = ENV[key]
    if type(fn) == "function" then pcall(fn) end
end

local running = true
ENV.GAG2_V331_STOP = function() running = false end

local Net = (function()
    local ok, m = pcall(function()
        return require(ReplicatedStorage.SharedModules.Networking)
    end)
    return ok and m or nil
end)()
local PSC = (function()
    local ok, m = pcall(function()
        return require(ReplicatedStorage.ClientModules.PlayerStateClient)
    end)
    return ok and m or nil
end)()
if not Net then warn("[GAG2 V3.3.1] Networking missing") return end

local SeedData = (function()
    local ok, d = pcall(function()
        return require(ReplicatedStorage.SharedModules.SeedData)
    end)
    return ok and d or {}
end)()
local FruitValueCalc = (function()
    local ok, m = pcall(function()
        return require(ReplicatedStorage.SharedModules.FruitValueCalc)
    end)
    return (ok and type(m) == "function") and m or nil
end)()

-- IMPORTANT: extras are separate, just like Punk's separate toggles.
-- We prove AutoProgress first, then add/enable each extra one by one.
local CFG = {
    AutoProgress = true,

    ProgressEvery = 0.75,
    HarvestDelay = 0.03,
    HarvestPasses = 2,

    BuyMaxPerPass = 6,
    BuyMaxSeedPricePercent = 50,
    CashReservePercent = 10,
    AbsoluteCashReserve = 250,

    PlantMaxPerPass = 40,
    PlantDelay = 0.075,
    PlantStep = 6,

    -- OFF during baseline validation.
    AutoExpand = false,
    AutoGear = false,
    AutoCrates = false,
    AutoEvents = false,
    AutoPets = false,
    AutoSprinklers = false,
}
ENV.GAG2_V331_CONFIG = CFG

local SeedPrice, SeedBaseValue = {}, {}
for _, e in ipairs(SeedData) do
    if type(e) == "table" and e.SeedName then
        SeedPrice[e.SeedName] = tonumber(e.PurchasePrice) or math.huge
        local base = 0
        if FruitValueCalc then
            local ok, v = pcall(FruitValueCalc, e.SeedName, 1, nil, LP, nil)
            if ok and type(v) == "number" then base = v end
        end
        SeedBaseValue[e.SeedName] = base
    end
end

local function log(...)
    print("[GAG2 V3.3.1]", ...)
end
local function notify(text)
    log(text)
    pcall(function()
        StarterGui:SetCore("SendNotification", {
            Title="GAG2 V3.3.1", Text=tostring(text), Duration=4
        })
    end)
end
local function fire(pkt, ...)
    if not pkt then return false end
    local a = {...}
    local ok, err = pcall(function() pkt:Fire(table.unpack(a)) end)
    if not ok then warn("[GAG2 V3.3.1] remote error", err) end
    return ok
end
local function spawnLoop(interval, fn)
    task.spawn(function()
        while running do
            task.wait(interval)
            if not running then break end
            local ok, err = pcall(fn)
            if not ok then warn("[GAG2 V3.3.1] loop error", err) end
        end
    end)
end
local function getReplica()
    if not PSC then return nil end
    local ok, r = pcall(function() return PSC:GetLocalReplica() end)
    return ok and r or nil
end
local function getData()
    local r = getReplica()
    return r and r.Data or nil
end
local function cash()
    local d = getData()
    return d and tonumber(d.Sheckles) or 0
end
local function reserveFor(v)
    return math.max(CFG.AbsoluteCashReserve, v * CFG.CashReservePercent/100)
end
local function myPlot()
    local g = Workspace:FindFirstChild("Gardens")
    if not g then return nil end
    local pid = LP:GetAttribute("PlotId")
    if pid ~= nil then
        local p = g:FindFirstChild("Plot" .. tostring(pid))
        if p then return p end
    end
    for _, p in ipairs(g:GetChildren()) do
        if p:GetAttribute("OwnerUserId") == LP.UserId then return p end
    end
end
local function homePos()
    local p = myPlot()
    local ref = p and p:FindFirstChild("PlotSizeReference")
    return ref and ref.Position + Vector3.new(0,4,0) or nil
end
local function insideOwnGarden()
    local root = LP.Character and LP.Character:FindFirstChild("HumanoidRootPart")
    local p = myPlot()
    local ref = p and p:FindFirstChild("PlotSizeReference")
    if not (root and ref) then return false end
    local q = ref.CFrame:PointToObjectSpace(root.Position)
    return math.abs(q.X) <= ref.Size.X/2 + 4 and math.abs(q.Z) <= ref.Size.Z/2 + 4
end
local function returnHome()
    if insideOwnGarden() then return true end
    fire(Net.TeleportButton and Net.TeleportButton.Request, "Garden")
    task.wait(0.25)
    local root = LP.Character and LP.Character:FindFirstChild("HumanoidRootPart")
    local hp = homePos()
    if root and hp then root.CFrame = CFrame.new(hp) end
    task.wait(0.05)
    return insideOwnGarden()
end

--========================================================
-- SAFE HARVEST
-- Public GAG2 autocollect only collects actual objects inside plant.Fruits.
-- We require BOTH PlantId and FruitId and NEVER fire CollectFruit(pid, "").
-- This prevents young/single-harvest plant models from being deleted by mistake.
--========================================================
local function harvestTargets()
    local out = {}
    local plot = myPlot()
    local plants = plot and plot:FindFirstChild("Plants")
    if not plants then return out end

    for _, plant in ipairs(plants:GetChildren()) do
        local fruits = plant:FindFirstChild("Fruits")
        if fruits then
            for _, fruit in ipairs(fruits:GetChildren()) do
                local pid = fruit:GetAttribute("PlantId")
                local fid = fruit:GetAttribute("FruitId")
                if pid ~= nil and fid ~= nil then
                    out[#out+1] = fruit
                end
            end
        end
    end
    return out
end

local function harvestAll()
    local total = 0
    for _ = 1, CFG.HarvestPasses do
        local targets = harvestTargets()
        if #targets == 0 then break end
        for _, fruit in ipairs(targets) do
            if fruit.Parent then
                local pid = fruit:GetAttribute("PlantId")
                local fid = fruit:GetAttribute("FruitId")
                if pid ~= nil and fid ~= nil then
                    if fire(Net.Garden and Net.Garden.CollectFruit, pid, fid) then
                        total += 1
                    end
                    task.wait(CFG.HarvestDelay)
                end
            end
        end
        task.wait(0.04)
    end
    return total
end

local function stockItems(shop)
    local sv = ReplicatedStorage:FindFirstChild("StockValues")
    sv = sv and sv:FindFirstChild(shop)
    return sv and sv:FindFirstChild("Items")
end
local function seedStockItems() return stockItems("SeedShop") end

-- Punk-style: among affordable stock, prefer highest base value.
local function bestAffordableSeed()
    local items = seedStockItems()
    if not items then return nil end
    local money = cash()
    local best, bestV
    for _, sv in ipairs(items:GetChildren()) do
        if sv:IsA("ValueBase") and sv.Value > 0 then
            local price = SeedPrice[sv.Name] or math.huge
            local val = SeedBaseValue[sv.Name] or 0
            if price > 0 and price < math.huge
                and price <= money * CFG.BuyMaxSeedPricePercent/100
                and money - price >= reserveFor(money)
                and (not bestV or val > bestV)
            then
                best, bestV = sv.Name, val
            end
        end
    end
    return best, bestV
end

local function progressBuy()
    local best = bestAffordableSeed()
    if not best then return 0 end
    local price = SeedPrice[best] or math.huge
    local n = 0
    for _ = 1, CFG.BuyMaxPerPass do
        local m = cash()
        if price > m * CFG.BuyMaxSeedPricePercent/100 or m-price < reserveFor(m) then break end
        if fire(Net.SeedShop and Net.SeedShop.PurchaseSeed, best) then n += 1 end
        task.wait(0.08)
    end
    return n, best
end

local function plantAreas(plot)
    local areas = {}
    for _, p in ipairs(CollectionService:GetTagged("PlantArea")) do
        if p:IsA("BasePart") and p:IsDescendantOf(plot) and p.Size.X*p.Size.Z > 400 then
            areas[#areas+1] = p
        end
    end
    if #areas == 0 then
        local ref = plot:FindFirstChild("PlotSizeReference")
        if ref then areas = {ref} end
    end
    return areas
end
local function plantPositions(plot)
    local seen, list = {}, {}
    local step = CFG.PlantStep
    for _, area in ipairs(plantAreas(plot)) do
        local cf, sz = area.CFrame, area.Size
        local topY = area.Position.Y + sz.Y/2 + 0.3
        local hx, hz = sz.X/2 - 3, sz.Z/2 - 3
        local nx, nz = math.floor((2*hx)/step), math.floor((2*hz)/step)
        for ix=0,nx do
            for iz=0,nz do
                local w = (cf*CFrame.new(-hx+ix*step,0,-hz+iz*step)).Position
                local key = math.floor(w.X/4+0.5)..","..math.floor(w.Z/4+0.5)
                if not seen[key] then
                    seen[key] = true
                    list[#list+1] = Vector3.new(w.X,topY,w.Z)
                end
            end
        end
    end
    return list
end
local function freePlantPositions(plot)
    local grid = plantPositions(plot)
    local plants = plot:FindFirstChild("Plants")
    local occ = {}
    if plants then
        for _, pl in ipairs(plants:GetChildren()) do
            local ok, pos = pcall(function() return pl:GetPivot().Position end)
            if ok then occ[#occ+1] = pos end
        end
    end
    local free = {}
    for _, pos in ipairs(grid) do
        local clear = true
        for _, used in ipairs(occ) do
            if (Vector3.new(used.X,0,used.Z)-Vector3.new(pos.X,0,pos.Z)).Magnitude < 6 then
                clear = false
                break
            end
        end
        if clear then free[#free+1] = pos end
    end
    return free
end

-- Punk-style baseline: plant owned seeds into free grid slots.
local function progressPlant()
    local plot = myPlot()
    if not plot then return 0 end
    local d = getData()
    local seeds = d and d.Inventory and d.Inventory.Seeds
    if type(seeds) ~= "table" then return 0 end

    local toPlant = {}
    for name, count in pairs(seeds) do
        for _=1,math.min(tonumber(count) or 0, 30) do
            toPlant[#toPlant+1] = name
            if #toPlant >= CFG.PlantMaxPerPass then break end
        end
        if #toPlant >= CFG.PlantMaxPerPass then break end
    end
    if #toPlant == 0 then return 0 end

    local free = freePlantPositions(plot)
    local cap = math.min(#free, #toPlant, CFG.PlantMaxPerPass)
    local n = 0
    for i=1,cap do
        if fire(Net.Plant and Net.Plant.PlantSeed, free[i], toPlant[i], plot) then n += 1 end
        task.wait(CFG.PlantDelay)
    end
    return n
end

local lastStatus = 0
spawnLoop(CFG.ProgressEvery, function()
    if not CFG.AutoProgress then return end
    if not insideOwnGarden() then returnHome() end

    local h = harvestAll()
    local fruitBeforeSell = tonumber(LP:GetAttribute("FruitCount")) or 0
    local cashBeforeSell = cash()
    if fruitBeforeSell > 0 then
        fire(Net.NPCS and Net.NPCS.SellAll)
        task.wait(0.15)
    end

    local b, seed = progressBuy()
    local p = progressPlant()

    if h > 0 or fruitBeforeSell > 0 or (b or 0) > 0 or p > 0 or os.clock()-lastStatus > 5 then
        lastStatus = os.clock()
        log("progress | harvest",h,
            "| sell fruit",fruitBeforeSell,
            "| cash",cashBeforeSell,"->",cash(),
            "| buy",b or 0,seed or "-",
            "| plant",p)
    end
end)

-- Safety: do not let character idle outside own plot in baseline mode.
spawnLoop(0.5, function()
    if CFG.AutoProgress and not insideOwnGarden() then returnHome() end
end)

pcall(function()
    LP.Idled:Connect(function()
        VirtualUser:CaptureController()
        VirtualUser:ClickButton2(Vector2.new())
    end)
end)

notify("SAFE PUNK BASE loaded: harvest > sell > buy > plant; extras OFF")
print("[GAG2 V3.3.1] IMPORTANT: no gear/crates/expand/events/pets during baseline test")
