--========================================================
-- GAG2 FARMER V3.2 SPRINKLER TRANSACTION GUARD
-- Overrides Economy's SprinklerBuy/SprinklerDeploy tasks.
-- Strict rule: placement succeeds ONLY if a new plot sprinkler appears.
--========================================================

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ENV = (getgenv and getgenv()) or _G
local Brain = ENV.GAG2_V32_BRAIN
if not Brain then
    warn("[GAG2 V3.2 SPRINKLER] Brain missing")
    return
end

local LP = Brain.LP
local Net = Brain.Net

local CFG = {
    DesiredPerType = 1,
    ReservePercent = 65,
    AbsoluteReserve = 5000,
    MaxSpendPercent = 12,
    MinCash = 12000,
    FailureBlockSeconds = 180,
    PlaceAttempts = 2,
}

local function reserve(cash)
    return math.max(CFG.AbsoluteReserve, cash * CFG.ReservePercent / 100)
end

local function canSpend(price)
    price = tonumber(price)
    if not price or price <= 0 then return false end
    local cash = Brain:Money()
    return cash >= CFG.MinCash
        and price <= cash * CFG.MaxSpendPercent / 100
        and cash - price >= reserve(cash)
end

local function valueCount(v)
    if type(v) == "number" then return math.max(0, v) end
    if type(v) == "table" then
        return tonumber(v.Count or v.Amount or v.Quantity or v.Stack) or 1
    end
    return 0
end

local function recursiveCount(node, target, depth, seen)
    if type(node) ~= "table" or depth > 7 then return 0 end
    seen = seen or {}
    if seen[node] then return 0 end
    seen[node] = true

    local total = 0
    for k, v in pairs(node) do
        if tostring(k) == target then
            total += valueCount(v)
        elseif type(v) == "table" then
            local name = v.Name or v.ItemName or v.GearName or v.PetType
            if tostring(name or "") == target then
                total += valueCount(v)
            else
                total += recursiveCount(v, target, depth + 1, seen)
            end
        end
    end
    return total
end

local function toolCount(name)
    local n = 0
    local function scan(c)
        if not c then return end
        for _, x in ipairs(c:GetChildren()) do
            if x:IsA("Tool") and x.Name == name then n += 1 end
        end
    end
    scan(LP:FindFirstChild("Backpack"))
    scan(LP.Character)
    return n
end

local function inventoryCount(name)
    local d = Brain:GetData()
    local inv = d and d.Inventory
    return recursiveCount(inv, name, 0, {}) + toolCount(name)
end

local function gearStock()
    local sv = ReplicatedStorage:FindFirstChild("StockValues")
    local shop = sv and sv:FindFirstChild("GearShop")
    return shop and shop:FindFirstChild("Items")
end

local function isSprinkler(name)
    return tostring(name or ""):lower():find("sprinkler", 1, true) ~= nil
end

local function tryRequire(parent, name)
    local m = parent and parent:FindFirstChild(name)
    if m and m:IsA("ModuleScript") then
        local ok, v = pcall(require, m)
        if ok and type(v) == "table" then return v end
    end
end

local sm = ReplicatedStorage:FindFirstChild("SharedModules")
local sd = ReplicatedStorage:FindFirstChild("SharedData")
local GearData = tryRequire(sm, "GearData")
    or tryRequire(sm, "GearShopData")
    or tryRequire(sd, "GearData")
    or tryRequire(sd, "GearShopData")

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
    return type(e) == "table"
        and tonumber(e.PurchasePrice or e.Price or e.Cost or e.ShecklesCost)
        or nil
end

local function sprinklerFolder()
    local plot = Brain:MyPlot()
    return plot and plot:FindFirstChild("Sprinklers")
end

local function placedTotal()
    local f = sprinklerFolder()
    return f and #f:GetChildren() or 0
end

local function placedType(name)
    local f = sprinklerFolder()
    if not f then return 0 end
    local n = 0
    for _, s in ipairs(f:GetChildren()) do
        local kind = s:GetAttribute("PropName")
            or s:GetAttribute("ItemName")
            or s:GetAttribute("Name")
            or s:GetAttribute("Type")
            or s.Name
        if tostring(kind) == tostring(name) then n += 1 end
    end
    return n
end

local blockedUntil = {}
local ambiguousPurchase = {}

local function placementPosition()
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
    local offset = offsets[(placedTotal() % #offsets) + 1]
    local world = (ref.CFrame * CFrame.new(offset)).Position
    return Vector3.new(world.X, ref.Position.Y + ref.Size.Y/2 + 0.25, world.Z)
end

local function ownedCandidate()
    local stock = gearStock()
    if not stock or not (Net.Prop and Net.Prop.PlaceProp) then return nil end

    local names = {}
    for _, item in ipairs(stock:GetChildren()) do
        local name = item.Name
        if isSprinkler(name)
            and inventoryCount(name) > 0
            and placedType(name) < CFG.DesiredPerType
            and os.clock() >= (blockedUntil[name] or 0)
        then
            table.insert(names, name)
        end
    end

    table.sort(names, function(a, b)
        return (gearPrice(a) or 0) > (gearPrice(b) or 0)
    end)

    return names[1]
end

local function deploy(ctx)
    local name = ownedCandidate()
    if not name then return "none" end

    if not Brain:IsInOwnGarden() then
        Brain:ReturnHome(ctx.priority, ctx.name)
    end

    local beforePlacedTotal = placedTotal()
    local beforeType = placedType(name)
    local beforeInv = inventoryCount(name)

    for _ = 1, CFG.PlaceAttempts do
        if ctx.shouldAbort() then return "preempted" end
        local pos = placementPosition()
        if not pos then return "no-position" end

        Brain:Fire(Net.Prop.PlaceProp, pos, name, 0, 0)

        local confirmed = ctx.waitUntil(function()
            return placedTotal() > beforePlacedTotal
                or placedType(name) > beforeType
        end, 1.8, 0.08)

        if confirmed then
            Brain:Log(
                "STRICT sprinkler placement confirmed",
                name,
                "plot sprinklers",
                beforePlacedTotal,
                "->",
                placedTotal(),
                "inventory",
                beforeInv,
                "->",
                inventoryCount(name)
            )
            ambiguousPurchase[name] = nil
            return "deployed"
        end

        task.wait(0.15)
    end

    blockedUntil[name] = os.clock() + CFG.FailureBlockSeconds
    warn(
        "[GAG2 V3.2 SPRINKLER] Placement FAILED verification for",
        name,
        "inventory before/after",
        beforeInv,
        inventoryCount(name),
        "- blocking this tier"
    )
    return "blocked"
end

local function buyCandidate()
    local stock = gearStock()
    if not stock or not (Net.Prop and Net.Prop.PlaceProp) then return nil end
    if Brain:Money() < CFG.MinCash then return nil end

    local best, bestPrice
    for _, item in ipairs(stock:GetChildren()) do
        local name = item.Name
        local qty = tonumber(item.Value) or 0
        local price = gearPrice(name)

        if qty > 0
            and isSprinkler(name)
            and placedType(name) < CFG.DesiredPerType
            and inventoryCount(name) <= 0
            and not ambiguousPurchase[name]
            and os.clock() >= (blockedUntil[name] or 0)
            and price
            and canSpend(price)
        then
            if not bestPrice or price > bestPrice then
                best, bestPrice = name, price
            end
        end
    end

    return best, bestPrice
end

local function buy(ctx)
    local name, price = buyCandidate()
    if not name then return "none" end

    local beforeCash = Brain:Money()
    local beforeInv = inventoryCount(name)
    Brain:Fire(Net.GearShop and Net.GearShop.PurchaseGear, name)

    local inventoryConfirmed = ctx.waitUntil(function()
        return inventoryCount(name) > beforeInv
    end, 1.5, 0.08)

    if inventoryConfirmed then
        Brain:Log("sprinkler purchase confirmed", name, "price", price)
        return "bought"
    end

    if Brain:Money() < beforeCash then
        -- Money moved but we cannot see the item. Never spend again blindly.
        ambiguousPurchase[name] = true
        warn(
            "[GAG2 V3.2 SPRINKLER] Cash decreased but inventory did not expose",
            name,
            "- further purchases blocked"
        )
        return "ambiguous-blocked"
    end

    blockedUntil[name] = os.clock() + 30
    return "buy-unconfirmed"
end

-- Same names intentionally replace Economy's earlier task registrations.
Brain:RegisterTask({
    name = "SprinklerDeploy",
    priority = 545,
    interval = 0.7,
    initialDelay = 0.2,
    canRun = function()
        return ownedCandidate() ~= nil
    end,
    run = deploy,
})

Brain:RegisterTask({
    name = "SprinklerBuy",
    priority = 305,
    interval = 5,
    initialDelay = 1.5,
    canRun = function()
        return buyCandidate() ~= nil
    end,
    run = buy,
})

Brain:Notify("Strict sprinkler guard registered", "GAG2 V3.2 Sprinklers")
