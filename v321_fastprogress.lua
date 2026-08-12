--========================================================
-- GAG2 FARMER V3.2.1 FAST PROGRESS PATCH
-- Punk-style fast progression + our transaction/safety scheduler.
-- Loaded LAST so same-name tasks replace conservative V3.2 tasks.
--========================================================

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")

local ENV = (getgenv and getgenv()) or _G
local Brain = ENV.GAG2_V32_BRAIN
if not Brain then
    warn("[GAG2 V3.2.1] Brain missing")
    return
end

local LP = Brain.LP
local Net = Brain.Net
Brain.Version = "3.2.1"
Brain.State.AuthorizedNightTrip = nil

local CFG = {
    -- Fast local progression. Similar pace to Punk's useful loops.
    SellEvery = 1.25,
    PlantEvery = 0.55,
    PlantPerAction = 40,
    PlantDelay = 0.06,

    SeedBuyEvery = 0.35,
    SeedBuyPerAction = 6,
    CashReservePercent = 20,
    AbsoluteCashReserve = 1000,
    MaxSingleSeedPricePercent = 50,

    ExpandEvery = 3.0,
    ExpandRetryAfterFail = 8,
    ExpandMinCash = 10000,
    ExpandWhenFreeSlotsLE = 2,

    SprinklerBuyEvery = 1.0,
    SprinklerReservePercent = 20,
    SprinklerAbsoluteReserve = 1500,
    SprinklerMaxSpendPercent = 35,
    SprinklerMinCash = 8000,

    RareRetryFail = 3,
    RareRetrySuccess = 45,
    RareAttempts = 60,
    RareAttemptDelay = 0.10,
    RareArrivalSettle = 0.22,
    PromptRadius = 35,

    HomeAnchorEvery = 0.35,
}

local function log(...)
    Brain:Log("[FAST321]", ...)
end

local function reserve(cash)
    return math.max(CFG.AbsoluteCashReserve, cash * CFG.CashReservePercent / 100)
end

--========================================================
-- HOME = REAL GARDEN CENTER, NOT SPAWNPOINT OUTSIDE
--========================================================

function Brain:HomePosition()
    local plot = self:MyPlot()
    if not plot then return nil end

    -- Prefer the plot reference CENTER. SpawnPoint can be outside the protected area.
    local ref = plot:FindFirstChild("PlotSizeReference")
    if ref and ref:IsA("BasePart") then
        return ref.Position
    end

    local sp = plot:FindFirstChild("SpawnPoint")
    if sp and sp:IsA("BasePart") then return sp.Position end

    local ok, cf = pcall(function() return plot:GetPivot() end)
    return ok and cf.Position or nil
end

function Brain:ReturnHome(priority, taskName)
    local home = self:HomePosition()
    if home then
        local ok = self:Reach(home, priority or 9999, taskName or "return-home", 4)
        if ok then
            task.wait(0.06)
            if self:IsInOwnGarden() then return true end
        end
    end

    -- Fallback only if direct center placement failed.
    self:Fire(Net.TeleportButton and Net.TeleportButton.Request, "Garden")
    task.wait(0.25)

    home = self:HomePosition()
    if home and not self:IsInOwnGarden() then
        self:Reach(home, priority or 9999, taskName or "return-home-fallback", 4)
        task.wait(0.06)
    end

    return self:IsInOwnGarden()
end

function Brain:CanLeaveGarden(reason)
    if not self:IsNight() then return true end

    -- Rare event may leave ONLY after NightSecure banked/harvested the garden.
    if reason == "rare_event" then
        return self.State.NightSecured == true
    end

    -- Pets and ordinary packs stay home during steal-night.
    return false
end

-- Keeps the character visibly inside the protected plot whenever no travel transaction owns it.
Brain:RegisterTask({
    name = "HomeAnchor",
    priority = 790,
    interval = CFG.HomeAnchorEvery,
    initialDelay = 0.05,
    canRun = function()
        return Brain.State.AuthorizedNightTrip == nil
            and not Brain:IsInOwnGarden()
    end,
    run = function(ctx)
        return Brain:ReturnHome(ctx.priority, ctx.name) and "inside" or "failed"
    end,
})

--========================================================
-- NIGHT GUARD: SECURE ONCE, THEN ALLOW ONE AUTHORIZED RARE TRIP
--========================================================

Brain:RegisterTask({
    name = "NightSecure",
    priority = 1000,
    interval = 0.12,
    canRun = function()
        if not Brain:IsNight() then return false end
        if Brain.State.AuthorizedNightTrip ~= nil then return false end
        return not Brain.State.NightSecured or not Brain:IsInOwnGarden()
    end,
    run = function(ctx)
        local home = Brain:ReturnHome(ctx.priority, ctx.name)
        if not home then
            Brain.State.NightSecured = false
            return "home-failed"
        end

        if Brain.Actions.HarvestAll then
            Brain.Actions.HarvestAll(ctx, true)
        end

        -- Bank harvested fruit before any rare-event trip.
        if Brain:FruitCount() > 0 and Brain.Actions.SellAll then
            pcall(function() Brain.Actions.SellAll(ctx) end)
        end

        Brain.State.NightSecured = Brain:IsInOwnGarden()
        if Brain.State.NightSecured then
            log("night secured inside garden")
            return "secured"
        end
        return "not-secured"
    end,
})

--========================================================
-- FAST HARVEST / SELL / PLANT
--========================================================

Brain:RegisterTask({
    name = "Harvest",
    priority = 730,
    interval = 0.08,
    canRun = function()
        return Brain.Actions.RipeCount and Brain.Actions.RipeCount() > 0
    end,
    run = function(ctx)
        return Brain.Actions.HarvestAll and Brain.Actions.HarvestAll(ctx, false) or "no-action"
    end,
})

local lastFastSell = 0
Brain:RegisterTask({
    name = "Sell",
    priority = 690,
    interval = 0.10,
    canRun = function()
        local n = Brain:FruitCount()
        if n <= 0 then return false end
        local cap = math.max(1, Brain:FruitCapacity())
        return n >= cap * 0.60 or os.clock() - lastFastSell >= CFG.SellEvery
    end,
    run = function(ctx)
        local result = Brain.Actions.SellAll and Brain.Actions.SellAll(ctx) or "no-action"
        if result == "sold" then lastFastSell = os.clock() end
        return result
    end,
})

local function ownedSeeds()
    local d = Brain:GetData()
    return d and d.Inventory and d.Inventory.Seeds or nil
end

local function fastSeedQueue(limit)
    local seeds = ownedSeeds()
    if type(seeds) ~= "table" then return {} end

    local rows = {}
    for name, count in pairs(seeds) do
        count = tonumber(count) or 0
        if count > 0 then
            rows[#rows + 1] = {
                name = name,
                count = count,
                score = tonumber(Brain.SeedScore[name]) or tonumber(Brain.SeedBaseValue[name]) or 0,
            }
        end
    end

    table.sort(rows, function(a, b)
        if a.score == b.score then return a.name < b.name end
        return a.score > b.score
    end)

    local out = {}
    for _, row in ipairs(rows) do
        for _ = 1, row.count do
            out[#out + 1] = row.name
            if #out >= limit then return out end
        end
    end
    return out
end

local function fastPlant(ctx)
    if not Brain:IsInOwnGarden() then Brain:ReturnHome(ctx.priority, ctx.name) end

    local plot = Brain:MyPlot()
    local positions = Brain.Actions.GetFreePlantPositions and Brain.Actions.GetFreePlantPositions() or {}
    local queue = fastSeedQueue(math.min(#positions, CFG.PlantPerAction))
    local total = math.min(#positions, #queue, CFG.PlantPerAction)
    if not plot or total <= 0 then return "nothing" end

    local before = Brain.Actions.GetPlantCount and Brain.Actions.GetPlantCount() or 0
    local attempts = 0

    for i = 1, total do
        if ctx.shouldAbort() then return "preempted" end
        if Brain:Fire(Net.Plant and Net.Plant.PlantSeed, positions[i], queue[i], plot) then
            attempts += 1
        end
        task.wait(CFG.PlantDelay)
    end

    local confirmed = ctx.waitUntil(function()
        return (Brain.Actions.GetPlantCount and Brain.Actions.GetPlantCount() or before) > before
    end, 0.65, 0.05)

    if attempts > 0 then
        log("plant", attempts, confirmed and "confirmed" or "sent")
    end
    return confirmed and "planted" or "sent"
end

Brain:RegisterTask({
    name = "Plant",
    priority = 400,
    interval = CFG.PlantEvery,
    initialDelay = 0.2,
    canRun = function()
        local seeds = ownedSeeds()
        return type(seeds) == "table"
            and next(seeds) ~= nil
            and Brain.Actions.GetFreePlantCount
            and Brain.Actions.GetFreePlantCount() > 0
    end,
    run = fastPlant,
})

--========================================================
-- PUNK-LIKE AGGRESSIVE SEED REINVESTMENT, BUT WITH 20% RESERVE
--========================================================

local function seedStock()
    local sv = ReplicatedStorage:FindFirstChild("StockValues")
    local shop = sv and sv:FindFirstChild("SeedShop")
    return shop and shop:FindFirstChild("Items")
end

local function seedCount(name)
    local seeds = ownedSeeds()
    return seeds and tonumber(seeds[name]) or 0
end

local function totalOwnedSeeds()
    local seeds = ownedSeeds()
    if type(seeds) ~= "table" then return 0 end
    local n = 0
    for _, c in pairs(seeds) do n += tonumber(c) or 0 end
    return n
end

local function affordableBestSeed()
    local folder = seedStock()
    if not folder then return nil end

    local cash = Brain:Money()
    local keep = reserve(cash)
    local best, bestBase, bestPrice

    for _, stock in ipairs(folder:GetChildren()) do
        local qty = tonumber(stock.Value) or 0
        local info = Brain.SeedInfo and Brain.SeedInfo[stock.Name]
        local price = info and tonumber(info.price)
        local base = tonumber(Brain.SeedBaseValue[stock.Name]) or (info and tonumber(info.base)) or 0

        if qty > 0 and price and price > 0
            and price <= cash * CFG.MaxSingleSeedPricePercent / 100
            and cash - price >= keep
        then
            if bestBase == nil or base > bestBase then
                best, bestBase, bestPrice = stock.Name, base, price
            end
        end
    end

    return best, bestPrice, bestBase
end

local function needSeeds()
    if not Brain.Actions.GetFreePlantCount then return 0 end
    local free = Brain.Actions.GetFreePlantCount()
    return math.max(0, free - totalOwnedSeeds())
end

local function fastBuySeeds(ctx)
    local needed = needSeeds()
    if needed <= 0 then return "enough" end

    local bought = 0
    for _ = 1, math.min(CFG.SeedBuyPerAction, needed) do
        if ctx.shouldAbort() then return "preempted" end

        local name, price = affordableBestSeed()
        if not name then break end

        local beforeCash = Brain:Money()
        local beforeCount = seedCount(name)
        Brain:Fire(Net.SeedShop and Net.SeedShop.PurchaseSeed, name)

        local ok = ctx.waitUntil(function()
            return seedCount(name) > beforeCount or Brain:Money() < beforeCash
        end, 0.50, 0.04)

        if not ok then break end
        bought += 1
        task.wait(0.04)
    end

    if bought > 0 then
        log("bought", bought, "seed(s) | cash", Brain:Money(), "| still need", needSeeds())
        return "bought:" .. bought
    end
    return "no-buy"
end

Brain:RegisterTask({
    name = "SmartSeedBuy",
    priority = 380,
    interval = CFG.SeedBuyEvery,
    initialDelay = 0.15,
    canRun = function()
        return needSeeds() > 0 and affordableBestSeed() ~= nil
    end,
    run = fastBuySeeds,
})

--========================================================
-- EXPAND: TRY WHEN PLOT IS FULL, NOT ONLY AT 250K
--========================================================

local nextExpandTry = 0
Brain:RegisterTask({
    name = "GardenExpand",
    priority = 250,
    interval = CFG.ExpandEvery,
    initialDelay = 1.0,
    canRun = function()
        if os.clock() < nextExpandTry then return false end
        if Brain:Money() < CFG.ExpandMinCash then return false end
        local free = Brain.Actions.GetFreePlantCount and Brain.Actions.GetFreePlantCount() or 999
        return free <= CFG.ExpandWhenFreeSlotsLE
    end,
    run = function(ctx)
        local plot = Brain:MyPlot()
        if not plot then return "no-plot" end
        local before = tonumber(plot:GetAttribute("GardenExpansion")) or 0
        local beforeCash = Brain:Money()

        Brain:Fire(Net.Actions and Net.Actions.ExpandGarden)
        local ok = ctx.waitUntil(function()
            return (tonumber(plot:GetAttribute("GardenExpansion")) or before) > before
        end, 0.75, 0.05)

        if ok then
            log("EXPANDED", before, "->", tonumber(plot:GetAttribute("GardenExpansion")) or before,
                "cash", beforeCash, "->", Brain:Money())
            nextExpandTry = os.clock() + 1
            return "expanded"
        end

        nextExpandTry = os.clock() + CFG.ExpandRetryAfterFail
        return "not-affordable"
    end,
})

--========================================================
-- FASTER SPRINKLER BUY (STRICT EXISTING DEPLOY TASK STAYS)
--========================================================

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
        if type(v) == "table" and (v.GearName == name or v.Name == name or v.ItemName == name) then
            return v
        end
    end
end

local function gearPrice(name)
    local e = gearEntry(name)
    return type(e) == "table" and tonumber(e.PurchasePrice or e.Price or e.Cost or e.ShecklesCost) or nil
end

local function gearStock()
    local sv = ReplicatedStorage:FindFirstChild("StockValues")
    local shop = sv and sv:FindFirstChild("GearShop")
    return shop and shop:FindFirstChild("Items")
end

local function isSprinkler(name)
    return tostring(name or ""):lower():find("sprinkler", 1, true) ~= nil
end

local function recursiveNamedCount(node, target, depth, seen)
    if type(node) ~= "table" or depth > 7 then return 0 end
    seen = seen or {}
    if seen[node] then return 0 end
    seen[node] = true
    local total = 0
    for k, v in pairs(node) do
        if tostring(k) == target then
            if type(v) == "number" then total += v else total += 1 end
        elseif type(v) == "table" then
            local n = v.Name or v.ItemName or v.GearName
            if tostring(n or "") == target then
                total += tonumber(v.Count or v.Amount or v.Quantity) or 1
            else
                total += recursiveNamedCount(v, target, depth + 1, seen)
            end
        end
    end
    return total
end

local function gearInvCount(name)
    local d = Brain:GetData()
    local inv = d and d.Inventory
    local n = recursiveNamedCount(inv, name, 0, {})
    local function scan(c)
        if c then for _, t in ipairs(c:GetChildren()) do if t:IsA("Tool") and t.Name == name then n += 1 end end end
    end
    scan(LP:FindFirstChild("Backpack")); scan(LP.Character)
    return n
end

local function placedSprinklerType(name)
    local plot = Brain:MyPlot()
    local f = plot and plot:FindFirstChild("Sprinklers")
    if not f then return 0 end
    local n = 0
    for _, s in ipairs(f:GetChildren()) do
        local kind = s:GetAttribute("PropName") or s:GetAttribute("ItemName") or s:GetAttribute("Name") or s:GetAttribute("Type") or s.Name
        if tostring(kind) == tostring(name) then n += 1 end
    end
    return n
end

local sprinklerBlocked = {}
local function sprinklerCandidate()
    local folder = gearStock()
    if not folder or Brain:Money() < CFG.SprinklerMinCash then return nil end

    local cash = Brain:Money()
    local keep = math.max(CFG.SprinklerAbsoluteReserve, cash * CFG.SprinklerReservePercent / 100)
    local best, bestPrice

    for _, stock in ipairs(folder:GetChildren()) do
        local name = stock.Name
        local qty = tonumber(stock.Value) or 0
        local price = gearPrice(name)
        if qty > 0 and isSprinkler(name)
            and placedSprinklerType(name) < 1
            and gearInvCount(name) <= 0
            and os.clock() >= (sprinklerBlocked[name] or 0)
            and price and price > 0
            and price <= cash * CFG.SprinklerMaxSpendPercent / 100
            and cash - price >= keep
        then
            if not bestPrice or price > bestPrice then best, bestPrice = name, price end
        end
    end
    return best, bestPrice
end

Brain:RegisterTask({
    name = "SprinklerBuy",
    priority = 330,
    interval = CFG.SprinklerBuyEvery,
    initialDelay = 0.7,
    canRun = function() return sprinklerCandidate() ~= nil end,
    run = function(ctx)
        local name, price = sprinklerCandidate()
        if not name then return "none" end
        local beforeCash = Brain:Money()
        local beforeInv = gearInvCount(name)
        Brain:Fire(Net.GearShop and Net.GearShop.PurchaseGear, name)
        local ok = ctx.waitUntil(function()
            return gearInvCount(name) > beforeInv or Brain:Money() < beforeCash
        end, 0.8, 0.05)
        if ok then
            log("sprinkler bought", name, "price", price, "cash", beforeCash, "->", Brain:Money())
            return "bought"
        end
        sprinklerBlocked[name] = os.clock() + 15
        return "unconfirmed"
    end,
})

--========================================================
-- RARE EVENT: USE PUNK'S AUTHORITATIVE SERVER LOCATIONS,
-- BUT ONE LOCKED TRIP + GUARANTEED RETURN HOME.
--========================================================

local eventHandledUntil = setmetatable({}, {__mode = "k"})
local cachedRare
local cachedPack

local function kindOf(loc)
    if loc:GetAttribute("MegaSeed") == true then return "Mega" end
    if loc:GetAttribute("RainbowSeed") == true then return "Rainbow" end
    if loc:GetAttribute("GoldSeed") == true then return "Gold" end

    local seedPack = tostring(loc:GetAttribute("SeedPack") or "")
    local text = (tostring(loc.Name) .. " " .. seedPack):lower()
    if text:find("mega", 1, true) then return "Mega" end
    if text:find("rainbow", 1, true) then return "Rainbow" end
    if text:find("gold", 1, true) then return "Gold" end
    if seedPack ~= "" or text:find("pack", 1, true) or text:find("seed", 1, true) then return "Pack" end
    return "Unknown"
end

local function packLocations()
    local map = Workspace:FindFirstChild("Map")
    local f = map and map:FindFirstChild("SeedPackSpawnServerLocations")
    return f and f:GetChildren() or {}
end

local function locPosition(loc)
    if loc:IsA("BasePart") then return loc.Position end
    local ok, cf = pcall(function() return loc:GetPivot() end)
    if ok then return cf.Position end
    local p = loc:FindFirstChildWhichIsA("BasePart", true)
    return p and p.Position or nil
end

local function isRareKind(k)
    return k == "Mega" or k == "Rainbow" or k == "Gold"
end

local function chooseEvent(wantRare)
    local best, bestScore
    local scores = {Mega=400, Rainbow=300, Gold=200, Pack=100}
    for _, loc in ipairs(packLocations()) do
        if loc.Parent and os.clock() >= (eventHandledUntil[loc] or 0) then
            local k = kindOf(loc)
            if (wantRare and isRareKind(k)) or ((not wantRare) and k == "Pack") then
                local s = scores[k] or 0
                if not bestScore or s > bestScore then
                    best, bestScore = {loc=loc, kind=k}, s
                end
            end
        end
    end
    return best
end

local function firePrompt(p)
    if not p or not p.Parent then return end
    pcall(function()
        local hold = tonumber(p.HoldDuration) or 0
        if fireproximityprompt then
            if hold > 0 then fireproximityprompt(p, hold) else fireproximityprompt(p) end
        else
            p:InputHoldBegin(); task.wait(hold + 0.06); p:InputHoldEnd()
        end
    end)
end

local function holdNearbyPrompts(pos)
    local map = Workspace:FindFirstChild("Map")
    for _, cont in ipairs({
        map and map:FindFirstChild("SeedPackSpawnServerLocations"),
        map and map:FindFirstChild("SeedPackSpawnClient"),
        Workspace:FindFirstChild("Temporary"),
    }) do
        if cont then
            for _, d in ipairs(cont:GetDescendants()) do
                if d:IsA("ProximityPrompt") then
                    local pp
                    pcall(function()
                        if d.Parent:IsA("BasePart") then pp = d.Parent.Position
                        elseif d.Parent:IsA("Model") then pp = d.Parent:GetPivot().Position end
                    end)
                    if not pp or (pp - pos).Magnitude <= CFG.PromptRadius then firePrompt(d) end
                end
            end
        end
    end
end

local function touch(loc)
    if not firetouchinterest then return end
    local root = Brain:Root()
    local p = loc:IsA("BasePart") and loc or loc:FindFirstChildWhichIsA("BasePart", true)
    if root and p then
        pcall(function()
            firetouchinterest(root, p, 0)
            task.wait(0.03)
            firetouchinterest(root, p, 1)
        end)
    end
end

local function collectEvent(ctx, target, rare)
    if not target or not target.loc or not target.loc.Parent then return "gone" end
    local loc, kind = target.loc, target.kind

    if rare and Brain:IsNight() and not Brain.State.NightSecured then
        return "night-not-secured"
    end

    -- Finish local money cycle before leaving.
    if rare and Brain.Actions.HarvestAll and Brain.Actions.RipeCount and Brain.Actions.RipeCount() > 0 then
        Brain.Actions.HarvestAll(ctx, true)
    end
    if rare and Brain:FruitCount() > 0 and Brain.Actions.SellAll then
        pcall(function() Brain.Actions.SellAll(ctx) end)
    end

    if rare and Brain:IsNight() then
        Brain.State.AuthorizedNightTrip = "RareEvent"
    end

    local success = false
    local result = "unconfirmed"
    local ok, err = pcall(function()
        local pos = locPosition(loc)
        if not pos then result = "no-position" return end

        local moved, why = Brain:Reach(pos, ctx.priority, ctx.name, 3)
        if not moved then result = "move-failed:" .. tostring(why) return end
        task.wait(CFG.RareArrivalSettle)

        for _ = 1, CFG.RareAttempts do
            if ctx.shouldAbort() then result = "preempted" break end
            if not loc.Parent then success = true; result = "collected"; break end

            pos = locPosition(loc) or pos
            local root = Brain:Root()
            if root and (root.Position - pos).Magnitude > 7 then
                Brain:Reach(pos, ctx.priority, ctx.name, 3)
            end

            for _, d in ipairs(loc:GetDescendants()) do
                if d:IsA("ProximityPrompt") then firePrompt(d) end
            end
            holdNearbyPrompts(pos)
            touch(loc)

            task.wait(CFG.RareAttemptDelay)
            if not loc.Parent then success = true; result = "collected"; break end
        end
    end)

    -- Keep night authorization while returning, otherwise NightSecure would fight the return movement.
    local returned = false
    for _ = 1, 3 do
        if Brain:ReturnHome(995, "EventReturn") then returned = true break end
        task.wait(0.08)
    end
    Brain.State.AuthorizedNightTrip = nil
    if Brain:IsNight() and returned then Brain.State.NightSecured = true end

    if not ok then
        warn("[GAG2 V3.2.1 EVENT]", err)
        result = "error"
    end

    eventHandledUntil[loc] = os.clock() + (success and CFG.RareRetrySuccess or CFG.RareRetryFail)
    log("event", kind, result, "returned", returned)
    return result .. ":" .. kind
end

Brain:RegisterTask({
    name = "RareEvent",
    priority = 860,
    interval = 0.15,
    initialDelay = 0.4,
    canRun = function()
        cachedRare = nil
        if Brain:IsNight() and not Brain.State.NightSecured then return false end
        if not Brain:CanLeaveGarden("rare_event") then return false end
        cachedRare = chooseEvent(true)
        return cachedRare ~= nil
    end,
    run = function(ctx)
        local t = cachedRare or chooseEvent(true)
        cachedRare = nil
        return collectEvent(ctx, t, true)
    end,
})

Brain:RegisterTask({
    name = "NormalSeedPack",
    priority = 500,
    interval = 0.45,
    initialDelay = 1.0,
    canRun = function()
        cachedPack = nil
        if Brain:IsNight() then return false end
        cachedPack = chooseEvent(false)
        return cachedPack ~= nil
    end,
    run = function(ctx)
        local t = cachedPack or chooseEvent(false)
        cachedPack = nil
        return collectEvent(ctx, t, false)
    end,
})

Brain:Notify(
    "V3.2.1 FAST PROGRESS active: Punk speed + coordinated transactions",
    "GAG2 Farmer"
)

print("====================================================")
print(" GAG2 V3.2.1 FAST PROGRESS")
print(" Home=center | Harvest fast | Sell~1.25s | Buy up to 6 | Plant fast")
print(" Night secure -> authorized rare trip -> collect -> guaranteed return")
print("====================================================")