--========================================================
-- GAG2 FARMER V3.2 ECONOMY / PROGRESSION
-- Smart reinvestment, verified sprinkler deploy, safe pets.
-- Everything is scheduled through Brain; no competing loops.
--========================================================

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local ENV = (getgenv and getgenv()) or _G
local Brain = ENV.GAG2_V32_BRAIN
if not Brain then
    warn("[GAG2 V3.2 ECON] Brain missing")
    return
end

local LP = Brain.LP
local Net = Brain.Net

local CFG = {
    CashReservePercent = 65,
    AbsoluteCashReserve = 5000,

    SeedBuyPerAction = 2,
    SeedMaxSpendPercent = 12,
    SeedMinFreeSlots = 2,

    AutoExpand = true,
    ExpandMinCash = 250000,
    ExpandOnlyWhenFreeSlotsLE = 6,
    ExpandCooldown = 90,

    AutoSprinklers = true,
    SprinklerMaxSpendPercent = 12,
    SprinklerMinCash = 12000,
    SprinklerPlacementRetry = 2,
    SprinklerFailureCooldown = 90,

    AutoTameGoodPets = true,
    PetAttempts = 6,
    PetSettleTime = 0.28,
    PetRetryCooldown = 20,

    AutoOpenEggs = true,
    AutoOpenCrates = true,
    AutoOpenSeedPacks = false,
    MaxOpenPerAction = 3,
}

local function reserveFor(cash)
    return math.max(
        CFG.AbsoluteCashReserve,
        cash * (CFG.CashReservePercent / 100)
    )
end

local function canSpend(price, maxPercent)
    price = tonumber(price)
    if not price or price <= 0 or price == math.huge then return false end

    local cash = Brain:Money()
    if cash <= 0 then return false end
    if price > cash * ((maxPercent or 100) / 100) then return false end
    return cash - price >= reserveFor(cash)
end

--========================================================
-- INVENTORY HELPERS
--========================================================

local function valueCount(v)
    if type(v) == "number" then return math.max(0, v) end
    if type(v) == "table" then
        return tonumber(v.Count or v.Amount or v.Quantity or v.Stack) or 1
    end
    return 0
end

local function recursiveNamedCount(node, target, depth, seen)
    if type(node) ~= "table" or depth > 7 then return 0 end
    seen = seen or {}
    if seen[node] then return 0 end
    seen[node] = true

    local total = 0
    for k, v in pairs(node) do
        if tostring(k) == target then
            total += valueCount(v)
        elseif type(v) == "table" then
            local name = v.Name or v.ItemName or v.GearName or v.PetType or v.SeedName
            if tostring(name or "") == target then
                total += valueCount(v)
            else
                total += recursiveNamedCount(v, target, depth + 1, seen)
            end
        end
    end
    return total
end

local function toolCount(name)
    local n = 0
    local function scan(container)
        if not container then return end
        for _, item in ipairs(container:GetChildren()) do
            if item:IsA("Tool") and item.Name == name then n += 1 end
        end
    end
    scan(LP:FindFirstChild("Backpack"))
    scan(LP.Character)
    return n
end

local function inventoryCount(name)
    local d = Brain:GetData()
    local inv = d and d.Inventory
    return recursiveNamedCount(inv, name, 0, {}) + toolCount(name)
end

local function seedCount(name)
    local d = Brain:GetData()
    local seeds = d and d.Inventory and d.Inventory.Seeds
    return seeds and tonumber(seeds[name]) or 0
end

local function totalOwnedSeeds()
    local d = Brain:GetData()
    local seeds = d and d.Inventory and d.Inventory.Seeds
    if type(seeds) ~= "table" then return 0 end
    local n = 0
    for _, count in pairs(seeds) do
        n += tonumber(count) or 0
    end
    return n
end

--========================================================
-- SMART SEED BUYER
--========================================================

local function seedStockFolder()
    local sv = ReplicatedStorage:FindFirstChild("StockValues")
    local shop = sv and sv:FindFirstChild("SeedShop")
    return shop and shop:FindFirstChild("Items")
end

local function chooseSeedToBuy()
    local freeCount = Brain.Actions.GetFreePlantCount and Brain.Actions.GetFreePlantCount() or 0
    if freeCount < CFG.SeedMinFreeSlots then return nil end

    -- Do not hoard seeds while we already own enough to fill the current plot.
    if totalOwnedSeeds() >= freeCount then return nil end

    local folder = seedStockFolder()
    if not folder then return nil end

    local best, bestScore
    for _, stock in ipairs(folder:GetChildren()) do
        local qty = tonumber(stock.Value) or 0
        local info = Brain.SeedInfo and Brain.SeedInfo[stock.Name]
        if qty > 0 and info and canSpend(info.price, CFG.SeedMaxSpendPercent) then
            local score = tonumber(info.score) or 0
            if not bestScore or score > bestScore then
                best = stock.Name
                bestScore = score
            end
        end
    end

    return best, bestScore
end

local function smartSeedBuy(ctx)
    local name, score = chooseSeedToBuy()
    if not name then return "no-buy" end

    local info = Brain.SeedInfo[name]
    if not info then return "no-data" end

    local actionStartCash = Brain:Money()
    local maxActionSpend = actionStartCash * (CFG.SeedMaxSpendPercent / 100)
    local bought = 0

    for _ = 1, CFG.SeedBuyPerAction do
        if ctx.shouldAbort() then return "preempted" end
        if not canSpend(info.price, CFG.SeedMaxSpendPercent) then break end
        if actionStartCash - Brain:Money() + info.price > maxActionSpend then break end

        local beforeCash = Brain:Money()
        local beforeCount = seedCount(name)
        Brain:Fire(Net.SeedShop and Net.SeedShop.PurchaseSeed, name)

        local confirmed = ctx.waitUntil(function()
            return seedCount(name) > beforeCount or Brain:Money() < beforeCash
        end, 1.2, 0.08)

        if not confirmed then
            Brain:Log("seed purchase unconfirmed", name)
            break
        end

        bought += 1
        task.wait(0.08)
    end

    if bought > 0 then
        Brain:Log(
            "smart seed buy",
            bought .. "x",
            name,
            "score",
            math.floor((score or 0) * 100) / 100,
            "cash",
            Brain:Money()
        )
        return "bought:" .. bought
    end

    return "not-bought"
end

Brain:RegisterTask({
    name = "SmartSeedBuy",
    priority = 310,
    interval = 4.0,
    initialDelay = 2.5,
    canRun = function()
        return chooseSeedToBuy() ~= nil
    end,
    run = smartSeedBuy,
})

--========================================================
-- SAFE EXPANSION
--========================================================

local lastExpand = 0

local function expandReady()
    if not CFG.AutoExpand then return false end
    if os.clock() - lastExpand < CFG.ExpandCooldown then return false end
    if Brain:Money() < CFG.ExpandMinCash then return false end

    local freeCount = Brain.Actions.GetFreePlantCount and Brain.Actions.GetFreePlantCount() or 999
    return freeCount <= CFG.ExpandOnlyWhenFreeSlotsLE
end

local function expandAction(ctx)
    local plot = Brain:MyPlot()
    if not plot then return "no-plot" end

    local before = tonumber(plot:GetAttribute("GardenExpansion")) or 0
    local beforeCash = Brain:Money()

    Brain:Fire(Net.Actions and Net.Actions.ExpandGarden)

    local confirmed = ctx.waitUntil(function()
        return (tonumber(plot:GetAttribute("GardenExpansion")) or before) > before
    end, 1.8, 0.1)

    if confirmed then
        lastExpand = os.clock()
        Brain:Log(
            "garden expanded",
            before,
            "->",
            tonumber(plot:GetAttribute("GardenExpansion")) or before,
            "spent",
            math.max(0, beforeCash - Brain:Money())
        )
        return "expanded"
    end

    return "expand-unconfirmed"
end

Brain:RegisterTask({
    name = "GardenExpand",
    priority = 230,
    interval = 12,
    initialDelay = 10,
    canRun = expandReady,
    run = expandAction,
})

--========================================================
-- GEAR DATA + VERIFIED SPRINKLER DEPLOYMENT
--========================================================

local function tryRequire(parent, name)
    local m = parent and parent:FindFirstChild(name)
    if m and m:IsA("ModuleScript") then
        local ok, v = pcall(require, m)
        if ok and type(v) == "table" then return v end
    end
end

local sharedModules = ReplicatedStorage:FindFirstChild("SharedModules")
local sharedData = ReplicatedStorage:FindFirstChild("SharedData")

local GearData = tryRequire(sharedModules, "GearData")
    or tryRequire(sharedModules, "GearShopData")
    or tryRequire(sharedData, "GearData")
    or tryRequire(sharedData, "GearShopData")

local function gearEntry(name)
    if type(GearData) ~= "table" then return nil end
    if type(GearData[name]) == "table" then return GearData[name] end

    for _, v in pairs(GearData) do
        if type(v) == "table"
            and (v.GearName == name or v.Name == name or v.ItemName == name)
        then
            return v
        end
    end
end

local function gearPrice(name)
    local e = gearEntry(name)
    if type(e) ~= "table" then return nil end
    return tonumber(e.PurchasePrice or e.Price or e.Cost or e.ShecklesCost)
end

local function gearStockFolder()
    local sv = ReplicatedStorage:FindFirstChild("StockValues")
    local shop = sv and sv:FindFirstChild("GearShop")
    return shop and shop:FindFirstChild("Items")
end

local function isSprinkler(name)
    return tostring(name or ""):lower():find("sprinkler", 1, true) ~= nil
end

local function sprinklerFolder()
    local plot = Brain:MyPlot()
    return plot and plot:FindFirstChild("Sprinklers")
end

local function placedSprinklerCount(name)
    local folder = sprinklerFolder()
    if not folder then return 0 end

    local n = 0
    for _, s in ipairs(folder:GetChildren()) do
        local kind = s:GetAttribute("PropName")
            or s:GetAttribute("ItemName")
            or s:GetAttribute("Name")
            or s:GetAttribute("Type")
            or s.Name
        if not name or tostring(kind) == tostring(name) then n += 1 end
    end
    return n
end

local function totalPlacedSprinklers()
    local folder = sprinklerFolder()
    return folder and #folder:GetChildren() or 0
end

local placementFailureUntil = {}

local function deploymentPosition()
    local plot = Brain:MyPlot()
    local ref = plot and plot:FindFirstChild("PlotSizeReference")
    if not (ref and ref:IsA("BasePart")) then return Brain:HomePosition() end

    local offsets = {
        Vector3.new(0,0,0),
        Vector3.new(9,0,0), Vector3.new(-9,0,0),
        Vector3.new(0,0,9), Vector3.new(0,0,-9),
        Vector3.new(9,0,9), Vector3.new(-9,0,9),
        Vector3.new(9,0,-9), Vector3.new(-9,0,-9),
    }

    local idx = (totalPlacedSprinklers() % #offsets) + 1
    local localPos = offsets[idx]
    local world = (ref.CFrame * CFrame.new(localPos)).Position
    return Vector3.new(world.X, ref.Position.Y + ref.Size.Y / 2 + 0.25, world.Z)
end

local function ownedSprinklers()
    local names = {}
    local folder = gearStockFolder()
    if folder then
        for _, stock in ipairs(folder:GetChildren()) do
            if isSprinkler(stock.Name) and inventoryCount(stock.Name) > 0 then
                table.insert(names, stock.Name)
            end
        end
    end
    table.sort(names, function(a, b)
        return (gearPrice(a) or 0) > (gearPrice(b) or 0)
    end)
    return names
end

local function deployableSprinkler()
    if not CFG.AutoSprinklers then return nil end
    if not (Net.Prop and Net.Prop.PlaceProp) then return nil end

    for _, name in ipairs(ownedSprinklers()) do
        if os.clock() >= (placementFailureUntil[name] or 0) then
            return name
        end
    end
end

local function deploySprinkler(ctx)
    local name = deployableSprinkler()
    if not name then return "none" end

    if not Brain:IsInOwnGarden() then
        Brain:ReturnHome(ctx.priority, ctx.name)
    end

    local beforeInv = inventoryCount(name)
    local beforePlaced = placedSprinklerCount(name)

    for attempt = 1, CFG.SprinklerPlacementRetry do
        if ctx.shouldAbort() then return "preempted" end

        local pos = deploymentPosition()
        if not pos then return "no-position" end

        Brain:Fire(Net.Prop.PlaceProp, pos, name, 0, 0)

        local confirmed = ctx.waitUntil(function()
            return placedSprinklerCount(name) > beforePlaced
                or inventoryCount(name) < beforeInv
        end, 1.5, 0.08)

        if confirmed then
            Brain:Log(
                "sprinkler deployed",
                name,
                "placed",
                beforePlaced,
                "->",
                placedSprinklerCount(name),
                "inventory",
                beforeInv,
                "->",
                inventoryCount(name)
            )
            return "deployed"
        end

        task.wait(0.15)
    end

    placementFailureUntil[name] = os.clock() + CFG.SprinklerFailureCooldown
    warn("[GAG2 V3.2 ECON] Sprinkler placement not confirmed; pausing purchases for", name)
    return "placement-failed"
end

Brain:RegisterTask({
    name = "SprinklerDeploy",
    priority = 540,
    interval = 0.8,
    initialDelay = 3,
    canRun = function()
        return deployableSprinkler() ~= nil
    end,
    run = deploySprinkler,
})

local function chooseSprinklerToBuy()
    if not CFG.AutoSprinklers then return nil end
    if Brain:Money() < CFG.SprinklerMinCash then return nil end
    if not (Net.Prop and Net.Prop.PlaceProp) then return nil end

    local folder = gearStockFolder()
    if not folder then return nil end

    local best, bestPrice
    for _, stock in ipairs(folder:GetChildren()) do
        if (tonumber(stock.Value) or 0) > 0 and isSprinkler(stock.Name) then
            local name = stock.Name
            local price = gearPrice(name)

            -- One undeployed copy at a time. We buy more only after the previous one was placed.
            if inventoryCount(name) <= 0
                and os.clock() >= (placementFailureUntil[name] or 0)
                and price
                and canSpend(price, CFG.SprinklerMaxSpendPercent)
            then
                if not bestPrice or price > bestPrice then
                    best = name
                    bestPrice = price
                end
            end
        end
    end

    return best, bestPrice
end

local function buySprinkler(ctx)
    local name, price = chooseSprinklerToBuy()
    if not name then return "none" end

    local beforeCash = Brain:Money()
    local beforeInv = inventoryCount(name)

    Brain:Fire(Net.GearShop and Net.GearShop.PurchaseGear, name)

    local confirmed = ctx.waitUntil(function()
        return inventoryCount(name) > beforeInv or Brain:Money() < beforeCash
    end, 1.5, 0.08)

    if confirmed then
        Brain:Log(
            "sprinkler bought",
            name,
            "expected price",
            price,
            "cash",
            beforeCash,
            "->",
            Brain:Money()
        )
        return "bought"
    end

    placementFailureUntil[name] = os.clock() + 30
    return "buy-unconfirmed"
end

Brain:RegisterTask({
    name = "SprinklerBuy",
    priority = 305,
    interval = 5,
    initialDelay = 5,
    canRun = function()
        return chooseSprinklerToBuy() ~= nil
    end,
    run = buySprinkler,
})

--========================================================
-- SAFE WILD PET HUNTER
--========================================================

local PetData = tryRequire(sharedData, "PetData") or {}

local GOOD_PETS = {
    Raccoon=true, Dragonfly=true, ["Dragon Fly"]=true, Dragonling=true, Mimic=true,
    ["Disco Bee"]=true, ["Queen Bee"]=true, Kitsune=true, ["Red Fox"]=true, Fox=true,
    Owl=true, ["Night Owl"]=true, Bear=true, ["Polar Bear"]=true, Butterfly=true,
    ["Golden Lab"]=true, Cat=true, ["Red Giant Ant"]=true, Snail=true,
}

local PET_COST_KEYS = {
    "TameCost", "TamePrice", "PriceToTame", "PurchasePrice",
    "ShecklesCost", "Cost", "Price", "Coins", "CoinCost",
}

local function petDataEntry(species)
    if type(PetData) ~= "table" then return nil end
    if type(PetData[species]) == "table" then return PetData[species] end

    for k, v in pairs(PetData) do
        if type(v) == "table" then
            local name = v.PetName or v.Name or v.PetType or k
            if tostring(name) == tostring(species) then return v end
        end
    end
end

local function extractCost(t)
    if type(t) ~= "table" then return nil end
    for _, key in ipairs(PET_COST_KEYS) do
        local n = tonumber(t[key])
        if n and n >= 0 then return n, key end
    end
end

local function petCost(pet, species)
    if pet then
        for _, key in ipairs(PET_COST_KEYS) do
            local n = tonumber(pet:GetAttribute(key))
            if n and n >= 0 then return n, "attr:" .. key end
        end
    end

    local info = petDataEntry(species)
    local n, key = extractCost(info)
    if n then return n, "data:" .. tostring(key) end
end

local unknownPetLogged = {}
local petRetryUntil = setmetatable({}, {__mode = "k"})

local function logUnknownPet(pet, species)
    if unknownPetLogged[species] then return end
    unknownPetLogged[species] = true

    local attrs = {}
    pcall(function()
        for k, v in pairs(pet:GetAttributes()) do
            if type(v) ~= "table" then
                table.insert(attrs, tostring(k) .. "=" .. tostring(v))
            end
        end
    end)

    local info = petDataEntry(species)
    local keys = {}
    if type(info) == "table" then
        for k, v in pairs(info) do
            if type(v) ~= "table" then
                table.insert(keys, tostring(k) .. "=" .. tostring(v))
            end
        end
    end

    Brain:Log("PET COST UNKNOWN - skipping", species)
    print("[GAG2 V3.2 PET ATTRS]", table.concat(attrs, " | "))
    print("[GAG2 V3.2 PET DATA]", table.concat(keys, " | "))
end

local function petInventoryCount(species)
    local d = Brain:GetData()
    local pets = d and d.Inventory and d.Inventory.Pets
    if type(pets) ~= "table" then return 0 end

    local n = 0
    for k, v in pairs(pets) do
        if tostring(k) == species then
            n += valueCount(v)
        elseif type(v) == "table" then
            local name = v.PetType or v.PetName or v.Name
            if tostring(name or "") == species then n += 1 end
        end
    end
    return n
end

local cachedPetCandidate

local function findAffordablePet()
    cachedPetCandidate = nil
    if not CFG.AutoTameGoodPets then return nil end
    if not Brain:CanLeaveGarden("pet") then return nil end

    local map = Workspace:FindFirstChild("Map")
    local refs = map and map:FindFirstChild("WildPetRef")
    if not refs then return nil end

    local cash = Brain:Money()
    for _, pet in ipairs(refs:GetChildren()) do
        local species = pet:GetAttribute("PetName")
        local owner = tonumber(pet:GetAttribute("OwnerUserId")) or 0

        if pet:IsA("BasePart")
            and species
            and GOOD_PETS[species]
            and (owner == 0 or owner == LP.UserId)
            and os.clock() >= (petRetryUntil[pet] or 0)
        then
            local cost, source = petCost(pet, species)
            if cost == nil then
                logUnknownPet(pet, species)
            elseif cash - cost >= reserveFor(cash) then
                cachedPetCandidate = {
                    pet = pet,
                    species = species,
                    cost = cost,
                    costSource = source,
                }
                return cachedPetCandidate
            end
        end
    end
end

local function tamePet(ctx)
    local c = cachedPetCandidate or findAffordablePet()
    cachedPetCandidate = nil
    if not c or not c.pet or not c.pet.Parent then return "none" end
    if not Brain:CanLeaveGarden("pet") then return "night-blocked" end

    local pet = c.pet
    local species = c.species
    local cost = c.cost

    -- Recheck affordability immediately before leaving the garden.
    local cashNow = Brain:Money()
    if cashNow - cost < reserveFor(cashNow) then
        return "became-unaffordable"
    end

    local beforeCash = cashNow
    local beforePets = petInventoryCount(species)

    local moved, moveReason = Brain:Reach(pet.Position, ctx.priority, ctx.name, 3)
    if not moved then
        Brain:ReturnHome(ctx.priority, ctx.name)
        return "move-failed:" .. tostring(moveReason)
    end

    task.wait(CFG.PetSettleTime)

    local success = false
    for _ = 1, CFG.PetAttempts do
        if ctx.shouldAbort() then break end
        if not pet.Parent then
            success = petInventoryCount(species) > beforePets
            break
        end

        local currentCost = petCost(pet, species) or cost
        local cash = Brain:Money()
        if cash - currentCost < reserveFor(cash) then
            break
        end

        Brain:Fire(Net.Pets and Net.Pets.WildPetTame, pet)

        local confirmed = ctx.waitUntil(function()
            local owner = pet.Parent and tonumber(pet:GetAttribute("OwnerUserId")) or LP.UserId
            return not pet.Parent
                or owner == LP.UserId
                or petInventoryCount(species) > beforePets
                or Brain:Money() < beforeCash
        end, 0.7, 0.07)

        if confirmed then
            success = true
            break
        end

        task.wait(0.12)
    end

    Brain:ReturnHome(ctx.priority, ctx.name)

    if success then
        -- Equipping does not require travel, so do it only after returning home.
        if Net.Pets and Net.Pets.RequestEquipByName then
            Brain:Fire(Net.Pets.RequestEquipByName, species)
            task.wait(0.15)
        end

        Brain:Log(
            "pet tame confirmed",
            species,
            "cost source",
            c.costSource,
            "cash",
            beforeCash,
            "->",
            Brain:Money()
        )
        return "tamed:" .. species
    end

    petRetryUntil[pet] = os.clock() + CFG.PetRetryCooldown
    Brain:Log("pet tame not confirmed", species, "- cooldown")
    return "tame-failed"
end

Brain:RegisterTask({
    name = "WildPetTame",
    priority = 600,
    interval = 0.7,
    initialDelay = 3,
    canRun = function()
        return findAffordablePet() ~= nil
    end,
    run = tamePet,
})

--========================================================
-- CONTROLLED AUTO-OPEN
--========================================================

local PROTECTED = {"mega", "gold", "rainbow", "divine", "prismatic", "mythic"}

local function protectedName(name)
    local s = tostring(name or ""):lower()
    for _, key in ipairs(PROTECTED) do
        if s:find(key, 1, true) then return true end
    end
    return false
end

local function bag(invKey)
    local d = Brain:GetData()
    return d and d.Inventory and d.Inventory[invKey]
end

local function hasOpenable()
    for _, spec in ipairs({
        {key="Eggs", enabled=CFG.AutoOpenEggs},
        {key="Crates", enabled=CFG.AutoOpenCrates},
        {key="SeedPacks", enabled=CFG.AutoOpenSeedPacks},
    }) do
        local b = spec.enabled and bag(spec.key)
        if type(b) == "table" then
            for name, count in pairs(b) do
                if (tonumber(count) or 1) > 0 and not protectedName(name) then
                    return true
                end
            end
        end
    end
    return false
end

local function openOne(ctx, invKey, packet)
    local b = bag(invKey)
    if type(b) ~= "table" or not packet then return 0 end

    local opened = 0
    for name, count in pairs(b) do
        if opened >= CFG.MaxOpenPerAction then break end
        if not protectedName(name) and (tonumber(count) or 1) > 0 then
            local before = tonumber(bag(invKey) and bag(invKey)[name]) or 1
            Brain:Fire(packet, name)
            ctx.waitUntil(function()
                local nb = bag(invKey)
                local after = nb and tonumber(nb[name]) or 0
                return after < before
            end, 0.8, 0.08)
            opened += 1
            task.wait(0.08)
        end
    end
    return opened
end

local function openItems(ctx)
    local total = 0
    if CFG.AutoOpenEggs then
        total += openOne(ctx, "Eggs", Net.Egg and Net.Egg.OpenEgg)
    end
    if total < CFG.MaxOpenPerAction and CFG.AutoOpenCrates then
        total += openOne(ctx, "Crates", Net.Crate and Net.Crate.OpenCrate)
    end
    if total < CFG.MaxOpenPerAction and CFG.AutoOpenSeedPacks then
        total += openOne(ctx, "SeedPacks", Net.SeedPack and Net.SeedPack.OpenSeedPack)
    end
    if total > 0 then Brain:Log("opened items", total) end
    return "opened:" .. total
end

Brain:RegisterTask({
    name = "OpenItems",
    priority = 170,
    interval = 4,
    initialDelay = 8,
    canRun = hasOpenable,
    run = openItems,
})

Brain:Notify(
    "Smart economy + verified sprinklers + affordable pets registered",
    "GAG2 V3.2 Economy"
)
