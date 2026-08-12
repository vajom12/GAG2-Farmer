--========================================================
-- GAG2 FARMER V3.2 CORE
-- Verified Harvest -> Sell -> Plant actions registered in Brain.
-- No independent automation loops.
--========================================================

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local Workspace = game:GetService("Workspace")
local VirtualUser = game:GetService("VirtualUser")

local LP = Players.LocalPlayer
local ENV = (getgenv and getgenv()) or _G
local Brain = ENV.GAG2_V32_BRAIN
if not Brain then
    warn("[GAG2 V3.2 CORE] Brain missing")
    return
end

local Net = Brain.Net

local CFG = {
    HarvestPerFruitDelay = 0.035,
    HarvestSweeps = 4,
    HarvestSweepPause = 0.12,
    SellAtPercent = 82,
    SellInterval = 32,
    PlantPerCycle = 24,
    PlantDelay = 0.10,
    GridStep = 6,
    PlantInterval = 2.5,
}

local SeedData = {}
pcall(function()
    SeedData = require(
        ReplicatedStorage:WaitForChild("SharedModules"):WaitForChild("SeedData")
    )
end)

local FruitValueCalc
pcall(function()
    FruitValueCalc = require(
        ReplicatedStorage:WaitForChild("SharedModules"):WaitForChild("FruitValueCalc")
    )
end)

local SeedInfo = {}
local GROW_KEYS = {"GrowthTime","GrowTime","TimeToGrow","HarvestTime","GrowDuration","MaxAge","Duration"}
local YIELD_KEYS = {"Yield","HarvestAmount","FruitCount","FruitsPerHarvest","ProduceCount"}

local function firstNumber(t, keys)
    if type(t) ~= "table" then return nil end
    for _, k in ipairs(keys) do
        local n = tonumber(t[k])
        if n and n > 0 then return n end
    end
end

for _, e in pairs(SeedData) do
    if type(e) == "table" and e.SeedName then
        local name = e.SeedName
        local price = tonumber(e.PurchasePrice) or math.huge
        local base = 0

        if type(FruitValueCalc) == "function" then
            local ok, v = pcall(FruitValueCalc, name, 1, nil, LP, nil)
            if ok and type(v) == "number" then
                base = v
            end
        end

        if base <= 0 and price < math.huge then
            base = price
        end

        local grow = firstNumber(e, GROW_KEYS)
        local yield = firstNumber(e, YIELD_KEYS) or 1
        local score

        if grow then
            score = (base * yield) / math.max(1, grow)
        elseif price < math.huge and price > 0 then
            score = (base * yield) / math.sqrt(price)
        else
            score = base * yield
        end

        SeedInfo[name] = {
            name = name,
            price = price,
            base = base,
            grow = grow,
            yield = yield,
            score = score,
            raw = e,
        }

        Brain.SeedBaseValue[name] = base
        Brain.SeedScore[name] = score
    end
end

Brain.SeedInfo = SeedInfo

local function ownedSeeds()
    local d = Brain:GetData()
    return d and d.Inventory and d.Inventory.Seeds or nil
end

local function ripe(m)
    if not m then return false end

    local age = tonumber(m:GetAttribute("Age"))
    local mx = tonumber(m:GetAttribute("MaxAge"))
    if age and mx and age >= mx - 0.001 then
        return true
    end

    for _, d in ipairs(m:GetDescendants()) do
        if d:IsA("ProximityPrompt") and CollectionService:HasTag(d, "HarvestPrompt") then
            return true
        end
    end

    return false
end

local function harvestTargets()
    local out = {}
    local plot = Brain:MyPlot()
    local plants = plot and plot:FindFirstChild("Plants")
    if not plants then return out end

    for _, plant in ipairs(plants:GetChildren()) do
        local ff = plant:FindFirstChild("Fruits")
        local fruits = ff and ff:GetChildren() or {}

        if #fruits > 0 then
            for _, fruit in ipairs(fruits) do
                if ripe(fruit) and fruit:GetAttribute("PlantId") then
                    table.insert(out, fruit)
                end
            end
        elseif ripe(plant) and plant:GetAttribute("PlantId") then
            table.insert(out, plant)
        end
    end

    return out
end

local function harvestAll(ctx, emergency)
    local priority = ctx and ctx.priority or 1000
    local taskName = ctx and ctx.name or "EmergencyHarvest"

    if not Brain:IsInOwnGarden() then
        Brain:ReturnHome(priority, taskName)
    end

    local total = 0
    local beforeFruit = Brain:FruitCount()

    for sweep = 1, CFG.HarvestSweeps do
        local targets = harvestTargets()
        if #targets == 0 then break end

        for _, m in ipairs(targets) do
            if not emergency and ctx and ctx.shouldAbort() then
                return total, "preempted"
            end

            if m.Parent then
                local pid = m:GetAttribute("PlantId")
                if pid then
                    Brain:Fire(
                        Net.Garden and Net.Garden.CollectFruit,
                        pid,
                        m:GetAttribute("FruitId") or ""
                    )
                    total += 1
                    task.wait(CFG.HarvestPerFruitDelay)
                end
            end
        end

        task.wait(CFG.HarvestSweepPause)
    end

    local remaining = #harvestTargets()
    local afterFruit = Brain:FruitCount()

    if total > 0 then
        Brain:Log(
            "harvest",
            total,
            "attempts | backpack",
            beforeFruit,
            "->",
            afterFruit,
            "| ripe remaining",
            remaining
        )
    end

    return total, remaining == 0 and "cleared" or ("remaining:" .. remaining)
end

Brain.Actions.HarvestAll = harvestAll
Brain.Actions.RipeCount = function()
    return #harvestTargets()
end

local lastSell = 0

local function shouldSell()
    local count = Brain:FruitCount()
    if count <= 0 then return false end

    local cap = math.max(1, Brain:FruitCapacity())
    if (count / cap) * 100 >= CFG.SellAtPercent then
        return true
    end

    return os.clock() - lastSell >= CFG.SellInterval
end

local function sellAll(ctx)
    local beforeCount = Brain:FruitCount()
    if beforeCount <= 0 then return "empty" end

    local beforeCash = Brain:Money()
    Brain:Fire(Net.NPCS and Net.NPCS.SellAll)

    local confirmed = ctx.waitUntil(function()
        return Brain:FruitCount() < beforeCount or Brain:Money() > beforeCash
    end, 1.6, 0.08)

    if not confirmed then
        Brain:Fire(Net.NPCS and Net.NPCS.SellAll)
        confirmed = ctx.waitUntil(function()
            return Brain:FruitCount() < beforeCount or Brain:Money() > beforeCash
        end, 1.4, 0.08)
    end

    if confirmed then
        lastSell = os.clock()
        Brain:Log(
            "sell confirmed | fruit",
            beforeCount,
            "->",
            Brain:FruitCount(),
            "| cash",
            beforeCash,
            "->",
            Brain:Money()
        )
        return "sold"
    end

    warn("[GAG2 V3.2 CORE] SellAll sent but state did not confirm")
    return "unconfirmed"
end

Brain.Actions.SellAll = sellAll

local function plantAreas(plot)
    local out = {}

    for _, p in ipairs(CollectionService:GetTagged("PlantArea")) do
        if p:IsA("BasePart")
            and p:IsDescendantOf(plot)
            and p.Size.X * p.Size.Z > 400
        then
            table.insert(out, p)
        end
    end

    if #out == 0 then
        local ref = plot:FindFirstChild("PlotSizeReference")
        if ref and ref:IsA("BasePart") then
            table.insert(out, ref)
        end
    end

    return out
end

local function gridPositions(plot)
    local out = {}
    local step = CFG.GridStep

    for _, area in ipairs(plantAreas(plot)) do
        local cf, sz = area.CFrame, area.Size
        local hx = math.max(0, sz.X / 2 - 3)
        local hz = math.max(0, sz.Z / 2 - 3)
        local nx = math.floor((2 * hx) / step)
        local nz = math.floor((2 * hz) / step)
        local y = area.Position.Y + sz.Y / 2 + 0.3

        for ix = 0, nx do
            for iz = 0, nz do
                local w = (cf * CFrame.new(-hx + ix * step, 0, -hz + iz * step)).Position
                table.insert(out, Vector3.new(w.X, y, w.Z))
            end
        end
    end

    return out
end

local function plantCount()
    local plot = Brain:MyPlot()
    local plants = plot and plot:FindFirstChild("Plants")
    return plants and #plants:GetChildren() or 0
end

local function freePositions()
    local plot = Brain:MyPlot()
    if not plot then return {} end

    local occ = {}
    local plants = plot:FindFirstChild("Plants")
    if plants then
        for _, pl in ipairs(plants:GetChildren()) do
            local ok, pos = pcall(function() return pl:GetPivot().Position end)
            if ok then table.insert(occ, pos) end
        end
    end

    local free = {}
    for _, pos in ipairs(gridPositions(plot)) do
        local clear = true
        for _, used in ipairs(occ) do
            local a = Vector3.new(pos.X, 0, pos.Z)
            local b = Vector3.new(used.X, 0, used.Z)
            if (a - b).Magnitude < 5.5 then
                clear = false
                break
            end
        end
        if clear then table.insert(free, pos) end
    end

    return free
end

Brain.Actions.GetFreePlantPositions = freePositions
Brain.Actions.GetFreePlantCount = function()
    return #freePositions()
end
Brain.Actions.GetPlantCount = plantCount

local function seedQueue()
    local seeds = ownedSeeds()
    if type(seeds) ~= "table" then return {} end

    local rows = {}
    for name, count in pairs(seeds) do
        count = tonumber(count) or 0
        if count > 0 then
            table.insert(rows, {
                name = name,
                count = count,
                score = tonumber(Brain.SeedScore[name]) or 0,
            })
        end
    end

    table.sort(rows, function(a, b)
        if a.score == b.score then return a.name < b.name end
        return a.score > b.score
    end)

    local out = {}
    for _, row in ipairs(rows) do
        for _ = 1, math.min(row.count, CFG.PlantPerCycle) do
            table.insert(out, row.name)
            if #out >= CFG.PlantPerCycle then return out end
        end
    end

    return out
end

local function plantAction(ctx)
    if not Brain:IsInOwnGarden() then
        Brain:ReturnHome(ctx.priority, ctx.name)
    end

    local plot = Brain:MyPlot()
    if not plot then return "no-plot" end

    local free = freePositions()
    local seeds = seedQueue()
    local total = math.min(#free, #seeds, CFG.PlantPerCycle)
    if total <= 0 then return "nothing" end

    local before = plantCount()
    local attempts = 0

    for i = 1, total do
        if ctx.shouldAbort() then
            return "preempted"
        end

        local sent = Brain:Fire(
            Net.Plant and Net.Plant.PlantSeed,
            free[i],
            seeds[i],
            plot
        )

        if sent then attempts += 1 end
        task.wait(CFG.PlantDelay)
    end

    local confirmed = ctx.waitUntil(function()
        return plantCount() > before
    end, 1.4, 0.08)

    Brain:Log(
        "plant",
        attempts,
        "attempts | plants",
        before,
        "->",
        plantCount(),
        confirmed and "confirmed" or "unconfirmed"
    )

    return confirmed and "planted" or "unconfirmed"
end

Brain.Actions.Plant = plantAction

Brain:RegisterTask({
    name = "Harvest",
    priority = 700,
    interval = 0.35,
    canRun = function()
        return #harvestTargets() > 0
    end,
    run = function(ctx)
        return harvestAll(ctx, false)
    end,
})

Brain:RegisterTask({
    name = "Sell",
    priority = 650,
    interval = 0.4,
    canRun = shouldSell,
    run = sellAll,
})

Brain:RegisterTask({
    name = "Plant",
    priority = 360,
    interval = CFG.PlantInterval,
    initialDelay = 1.5,
    canRun = function()
        local seeds = ownedSeeds()
        return type(seeds) == "table"
            and next(seeds) ~= nil
            and #freePositions() > 0
    end,
    run = plantAction,
})

-- Passive anti-AFK; this does not move the character or compete with scheduler actions.
pcall(function()
    LP.Idled:Connect(function()
        VirtualUser:Button2Down(Vector2.new(0, 0), Workspace.CurrentCamera.CFrame)
        task.wait(0.35)
        VirtualUser:Button2Up(Vector2.new(0, 0), Workspace.CurrentCamera.CFrame)
    end)
end)

Brain:Notify("Verified harvest/sell/plant registered", "GAG2 V3.2 Core")
