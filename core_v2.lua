--========================================================
-- GAG2 V2 - AUTO PROGRESS
-- Buy -> Plant -> Harvest -> Sell -> Repeat
--========================================================

local CFG = {
    AutoHarvest = true,
    AutoSell = true,
    AutoBuySeeds = true,
    AutoPlant = true,

    -- OSTAVI FALSE DOK PRVO TESTIRAMO CORE LOOP
    AutoExpand = false,

    -- Prodaj kad backpack dodje do ovog %
    SellAtPercent = 85,

    -- Ako nije pun, svakako prodaj nakon X sekundi
    SellEverySeconds = 35,

    -- Seed buying
    BuyEverySeconds = 10,
    BuyPerCycle = 3,

    -- Ne kupuj seed ako je preskup u odnosu na trenutni cash.
    -- 70 znaci da seed mora biti <= 30% trenutnog novca.
    CashReservePercent = 70,

    -- Planting
    PlantEverySeconds = 4,
    PlantDelay = 0.12,
    MaxPlantPerCycle = 35,
    GridStep = 6,

    -- Glavni loop
    LoopDelay = 1
}

--========================================================
-- SERVICES
--========================================================

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local StarterGui = game:GetService("StarterGui")
local VirtualUser = game:GetService("VirtualUser")

local LP = Players.LocalPlayer

repeat task.wait() until game:IsLoaded()
repeat task.wait() until LP

--========================================================
-- STOP PREVIOUS V2 IF EXECUTED AGAIN
--========================================================

local ENV = (getgenv and getgenv()) or _G

if ENV.GAG2_V2_STOP then
    pcall(ENV.GAG2_V2_STOP)
end

local running = true

ENV.GAG2_V2_STOP = function()
    running = false
end

--========================================================
-- MODULES
--========================================================

local Networking = require(
    ReplicatedStorage
        :WaitForChild("SharedModules")
        :WaitForChild("Networking")
)

local PSC

pcall(function()
    PSC = require(
        ReplicatedStorage
            :WaitForChild("ClientModules")
            :WaitForChild("PlayerStateClient")
    )
end)

local SeedData = {}

pcall(function()
    SeedData = require(
        ReplicatedStorage
            :WaitForChild("SharedModules")
            :WaitForChild("SeedData")
    )
end)

local FruitValueCalc

pcall(function()
    FruitValueCalc = require(
        ReplicatedStorage
            :WaitForChild("SharedModules")
            :WaitForChild("FruitValueCalc")
    )
end)

--========================================================
-- SAFE FIRE
--========================================================

local function fire(packet, ...)
    if not packet then
        return false
    end

    local args = {...}

    local ok, err = pcall(function()
        packet:Fire(table.unpack(args))
    end)

    if not ok then
        warn("[GAG2 V2] Fire error:", err)
    end

    return ok
end

--========================================================
-- NOTIFICATION
--========================================================

local function notify(text)
    print("[GAG2 V2]", text)

    pcall(function()
        StarterGui:SetCore("SendNotification", {
            Title = "GAG2 V2",
            Text = text,
            Duration = 4
        })
    end)
end

--========================================================
-- PLAYER DATA
--========================================================

local function getData()
    if not PSC then
        return nil
    end

    local ok, replica = pcall(function()
        return PSC:GetLocalReplica()
    end)

    if not ok or not replica then
        return nil
    end

    return replica.Data
end

local function getMoney()
    local data = getData()

    if data and data.Sheckles then
        return tonumber(data.Sheckles) or 0
    end

    return 0
end

local function getOwnedSeeds()
    local data = getData()

    if data
        and data.Inventory
        and data.Inventory.Seeds
    then
        return data.Inventory.Seeds
    end

    return nil
end

--========================================================
-- SEED INFORMATION
--========================================================

local SeedPrice = {}
local SeedValue = {}

for _, info in pairs(SeedData) do
    if type(info) == "table" and info.SeedName then

        local name = info.SeedName
        local price = tonumber(info.PurchasePrice) or math.huge

        SeedPrice[name] = price

        local calculatedValue = 0

        if type(FruitValueCalc) == "function" then
            local ok, value = pcall(
                FruitValueCalc,
                name,
                1,
                nil,
                LP,
                nil
            )

            if ok and type(value) == "number" then
                calculatedValue = value
            end
        end

        -- Ako calculator ne radi,
        -- koristi cijenu kao fallback za ranking.
        if calculatedValue > 0 then
            SeedValue[name] = calculatedValue
        elseif price < math.huge then
            SeedValue[name] = price
        else
            SeedValue[name] = 0
        end
    end
end

--========================================================
-- FIND OUR GARDEN
--========================================================

local Gardens = workspace:WaitForChild("Gardens")

local function getMyPlot()

    -- Prvo probaj PlotId
    local plotId = LP:GetAttribute("PlotId")

    if plotId ~= nil then
        local byId = Gardens:FindFirstChild(
            "Plot" .. tostring(plotId)
        )

        if byId then
            return byId
        end
    end

    -- Fallback
    for _, plot in ipairs(Gardens:GetChildren()) do

        local ownerId = plot:GetAttribute("OwnerUserId")
        local ownerName = plot:GetAttribute("Owner")

        if ownerId == LP.UserId
            or ownerName == LP.Name
        then
            return plot
        end
    end

    return nil
end

--========================================================
-- GO TO GARDEN AUTOMATICALLY
--========================================================

local function ensureGarden()

    if LP:GetAttribute("IsInOwnGarden") == true then
        return
    end

    pcall(function()
        fire(
            Networking.TeleportButton.Request,
            "Garden"
        )
    end)

    task.wait(0.7)
end

--========================================================
-- HARVEST
--========================================================

local function isRipe(model)

    if not model then
        return false
    end

    local age = tonumber(
        model:GetAttribute("Age")
    )

    local maxAge = tonumber(
        model:GetAttribute("MaxAge")
    )

    if age and maxAge then
        return age >= maxAge
    end

    return false
end

local function harvestAll()

    if not CFG.AutoHarvest then
        return 0
    end

    local plot = getMyPlot()

    if not plot then
        return 0
    end

    local plants = plot:FindFirstChild("Plants")

    if not plants then
        return 0
    end

    ensureGarden()

    local harvested = 0

    for _, plant in ipairs(plants:GetChildren()) do

        local fruitsFolder =
            plant:FindFirstChild("Fruits")

        if fruitsFolder
            and #fruitsFolder:GetChildren() > 0
        then

            for _, fruit in ipairs(
                fruitsFolder:GetChildren()
            ) do

                if isRipe(fruit) then

                    local plantId =
                        fruit:GetAttribute("PlantId")

                    local fruitId =
                        fruit:GetAttribute("FruitId") or ""

                    if plantId then
                        fire(
                            Networking.Garden.CollectFruit,
                            plantId,
                            fruitId
                        )

                        harvested += 1

                        task.wait(0.04)
                    end
                end
            end

        elseif isRipe(plant) then

            local plantId =
                plant:GetAttribute("PlantId")

            local fruitId =
                plant:GetAttribute("FruitId") or ""

            if plantId then
                fire(
                    Networking.Garden.CollectFruit,
                    plantId,
                    fruitId
                )

                harvested += 1
                task.wait(0.04)
            end
        end
    end

    if harvested > 0 then
        print(
            "[GAG2 V2] Harvested:",
            harvested
        )
    end

    return harvested
end

--========================================================
-- AUTO SELL
--========================================================

local lastSell = 0

local function shouldSell()

    if not CFG.AutoSell then
        return false
    end

    local count =
        tonumber(LP:GetAttribute("FruitCount"))
        or 0

    local max =
        tonumber(LP:GetAttribute("MaxFruitCapacity"))
        or 100

    if count <= 0 then
        return false
    end

    local percent = (count / max) * 100

    if percent >= CFG.SellAtPercent then
        return true
    end

    if os.clock() - lastSell
        >= CFG.SellEverySeconds
    then
        return true
    end

    return false
end

local function sellAll()

    local count =
        tonumber(LP:GetAttribute("FruitCount"))
        or 0

    if count <= 0 then
        return
    end

    fire(Networking.NPCS.SellAll)

    lastSell = os.clock()

    print(
        "[GAG2 V2] Auto sold:",
        count,
        "fruits"
    )

    task.wait(0.25)
end

--========================================================
-- AUTO BUY BEST CURRENT SEED
--========================================================

local function getSeedStockFolder()

    local stocks =
        ReplicatedStorage:FindFirstChild(
            "StockValues"
        )

    if not stocks then
        return nil
    end

    local seedShop =
        stocks:FindFirstChild("SeedShop")

    if not seedShop then
        return nil
    end

    return seedShop:FindFirstChild("Items")
end

local function chooseBestAffordableSeed()

    local folder = getSeedStockFolder()

    if not folder then
        return nil
    end

    local money = getMoney()

    if money <= 0 then
        return nil
    end

    local maxSpend =
        money
        * ((100 - CFG.CashReservePercent) / 100)

    local bestName = nil
    local bestValue = -1

    for _, stock in ipairs(folder:GetChildren()) do

        local amount =
            tonumber(stock.Value) or 0

        if amount > 0 then

            local name = stock.Name
            local price = SeedPrice[name]

            if price
                and price <= maxSpend
            then

                local value =
                    SeedValue[name]
                    or price

                if value > bestValue then
                    bestValue = value
                    bestName = name
                end
            end
        end
    end

    return bestName
end

local function autoBuySeeds()

    if not CFG.AutoBuySeeds then
        return
    end

    local seedName =
        chooseBestAffordableSeed()

    if not seedName then
        return
    end

    local bought = 0

    for _ = 1, CFG.BuyPerCycle do

        local money = getMoney()

        local price =
            SeedPrice[seedName]

        if not price then
            break
        end

        local maxSpend =
            money
            * ((100 - CFG.CashReservePercent) / 100)

        if price > maxSpend then
            break
        end

        fire(
            Networking.SeedShop.PurchaseSeed,
            seedName
        )

        bought += 1

        task.wait(0.12)
    end

    if bought > 0 then
        print(
            "[GAG2 V2] Bought",
            bought,
            "x",
            seedName
        )
    end
end

--========================================================
-- PLANTING GRID
--========================================================

local function getPlantAreas(plot)

    local areas = {}

    for _, part in ipairs(
        CollectionService:GetTagged("PlantArea")
    ) do

        if part:IsA("BasePart")
            and part:IsDescendantOf(plot)
            and part.Size.X * part.Size.Z > 400
        then
            table.insert(areas, part)
        end
    end

    -- fallback
    if #areas == 0 then

        local ref =
            plot:FindFirstChild(
                "PlotSizeReference"
            )

        if ref and ref:IsA("BasePart") then
            table.insert(areas, ref)
        end
    end

    return areas
end

local function generatePlantGrid(plot)

    local result = {}
    local step = CFG.GridStep

    for _, area in ipairs(
        getPlantAreas(plot)
    ) do

        local size = area.Size
        local cf = area.CFrame

        local halfX =
            math.max(0, size.X / 2 - 3)

        local halfZ =
            math.max(0, size.Z / 2 - 3)

        local countX =
            math.floor((halfX * 2) / step)

        local countZ =
            math.floor((halfZ * 2) / step)

        local y =
            area.Position.Y
            + size.Y / 2
            + 0.3

        for x = 0, countX do
            for z = 0, countZ do

                local localOffset =
                    CFrame.new(
                        -halfX + x * step,
                        0,
                        -halfZ + z * step
                    )

                local world =
                    (cf * localOffset).Position

                table.insert(
                    result,
                    Vector3.new(
                        world.X,
                        y,
                        world.Z
                    )
                )
            end
        end
    end

    return result
end

local function getFreePlantPositions(plot)

    local positions =
        generatePlantGrid(plot)

    local plants =
        plot:FindFirstChild("Plants")

    local occupied = {}

    if plants then

        for _, plant in ipairs(
            plants:GetChildren()
        ) do

            local ok, pos = pcall(function()
                return plant:GetPivot().Position
            end)

            if ok then
                table.insert(
                    occupied,
                    pos
                )
            end
        end
    end

    local free = {}

    for _, pos in ipairs(positions) do

        local available = true

        for _, used in ipairs(occupied) do

            local a =
                Vector3.new(
                    pos.X,
                    0,
                    pos.Z
                )

            local b =
                Vector3.new(
                    used.X,
                    0,
                    used.Z
                )

            if (a - b).Magnitude < 5.5 then
                available = false
                break
            end
        end

        if available then
            table.insert(free, pos)
        end
    end

    return free
end

--========================================================
-- OWNED SEEDS SORTED BEST FIRST
--========================================================

local function seedsToPlant()

    local owned =
        getOwnedSeeds()

    if not owned then
        return {}
    end

    local names = {}

    for name, count in pairs(owned) do

        count = tonumber(count) or 0

        if count > 0 then
            table.insert(names, {
                Name = name,
                Count = count,
                Value =
                    SeedValue[name]
                    or SeedPrice[name]
                    or 0
            })
        end
    end

    table.sort(
        names,
        function(a, b)
            return a.Value > b.Value
        end
    )

    local result = {}

    for _, seed in ipairs(names) do

        for _ = 1, math.min(
            seed.Count,
            CFG.MaxPlantPerCycle
        ) do

            table.insert(
                result,
                seed.Name
            )

            if #result
                >= CFG.MaxPlantPerCycle
            then
                return result
            end
        end
    end

    return result
end

--========================================================
-- AUTO PLANT
--========================================================

local function autoPlant()

    if not CFG.AutoPlant then
        return
    end

    if not Networking.Plant
        or not Networking.Plant.PlantSeed
    then

        warn(
            "[GAG2 V2] PlantSeed packet not found"
        )

        return
    end

    local plot =
        getMyPlot()

    if not plot then
        return
    end

    local seeds =
        seedsToPlant()

    if #seeds == 0 then
        return
    end

    ensureGarden()

    local positions =
        getFreePlantPositions(plot)

    if #positions == 0 then
        return
    end

    local total =
        math.min(
            #positions,
            #seeds,
            CFG.MaxPlantPerCycle
        )

    local planted = 0

    for i = 1, total do

        local ok =
            fire(
                Networking.Plant.PlantSeed,
                positions[i],
                seeds[i],
                plot
            )

        if ok then
            planted += 1
        end

        task.wait(CFG.PlantDelay)
    end

    if planted > 0 then
        print(
            "[GAG2 V2] Plant attempts:",
            planted
        )
    end
end

--========================================================
-- AUTO EXPAND
--========================================================

local function autoExpand()

    if not CFG.AutoExpand then
        return
    end

    if Networking.Actions
        and Networking.Actions.ExpandGarden
    then

        fire(
            Networking.Actions.ExpandGarden
        )
    end
end

--========================================================
-- ANTI AFK
--========================================================

pcall(function()

    LP.Idled:Connect(function()

        VirtualUser:Button2Down(
            Vector2.new(0, 0),
            workspace.CurrentCamera.CFrame
        )

        task.wait(0.5)

        VirtualUser:Button2Up(
            Vector2.new(0, 0),
            workspace.CurrentCamera.CFrame
        )
    end)
end)

--========================================================
-- START
--========================================================

notify(
    "FULL AUTO loaded: Buy > Plant > Harvest > Sell"
)

local lastBuy = 0
local lastPlant = 0
local lastExpand = 0

task.spawn(function()

    while running do

        local now = os.clock()

        -- 1. HARVEST
        pcall(harvestAll)

        task.wait(0.15)

        -- 2. SELL
        if shouldSell() then
            pcall(sellAll)
        end

        -- 3. BUY
        if CFG.AutoBuySeeds
            and now - lastBuy
                >= CFG.BuyEverySeconds
        then

            lastBuy = now
            pcall(autoBuySeeds)
        end

        -- 4. PLANT
        if CFG.AutoPlant
            and now - lastPlant
                >= CFG.PlantEverySeconds
        then

            lastPlant = now
            pcall(autoPlant)
        end

        -- 5. EXPAND
        if CFG.AutoExpand
            and now - lastExpand >= 15
        then

            lastExpand = now
            pcall(autoExpand)
        end

        task.wait(CFG.LoopDelay)
    end
end)

print("====================================")
print(" GAG2 V2 FULL AUTO RUNNING")
print(" Auto Harvest :", CFG.AutoHarvest)
print(" Auto Sell    :", CFG.AutoSell)
print(" Auto Buy     :", CFG.AutoBuySeeds)
print(" Auto Plant   :", CFG.AutoPlant)
print(" Auto Expand  :", CFG.AutoExpand)
print("====================================")
