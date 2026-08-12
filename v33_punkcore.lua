--========================================================
-- GAG2 FARMER V3.3 - PUNK-STYLE SINGLE CORE
-- Fast progression based on the same public GAG2 remotes/patterns
-- used by Punk Hub, with coordinated travel + safer improvements.
--========================================================

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local Workspace = game:GetService("Workspace")
local StarterGui = game:GetService("StarterGui")
local VirtualUser = game:GetService("VirtualUser")

local LP = Players.LocalPlayer
local ENV = (getgenv and getgenv()) or _G
repeat task.wait() until game:IsLoaded() and LP

-- Stop anything from our older builds.
for _, key in ipairs({
    "GAG2_V33_STOP", "GAG2_BRAIN_V32_STOP", "GAG2_CORE_V31_STOP",
    "GAG2_ECON_V31_STOP", "GAG2_EVENT_V31_STOP", "GAG2_V2_STOP",
    "GAG2_EVENT_V3_STOP"
}) do
    local fn = ENV[key]
    if type(fn) == "function" then pcall(fn) end
end

local running = true
ENV.GAG2_V33_STOP = function() running = false end
ENV.GAG2_V32_BRAIN = nil
ENV.GAG2_V31_ACTIVITY_LOCK = nil

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

if not Net then
    warn("[GAG2 V3.3] Networking missing - abort")
    return
end

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

local PetData = (function()
    local sd = ReplicatedStorage:FindFirstChild("SharedData")
    local mod = sd and sd:FindFirstChild("PetData")
    if not mod then return {} end
    local ok, m = pcall(require, mod)
    return ok and type(m) == "table" and m or {}
end)()

local CFG = {
    -- This intentionally follows Punk's aggressive progression philosophy.
    ProgressEvery = 0.75,
    HarvestDelay = 0.035,
    HarvestPasses = 3,
    BuyMaxPerPass = 6,
    BuyMaxSeedPricePercent = 50,
    CashReservePercent = 12,
    AbsoluteCashReserve = 500,
    PlantMaxPerPass = 40,
    PlantDelay = 0.075,
    PlantStep = 6,

    AutoExpand = true,
    ExpandEvery = 5,
    ExpandMinCash = 5000,

    AutoGear = true,
    GearEvery = 3,
    AutoCrates = true,
    CrateEvery = 4,

    AutoOpenEggs = true,
    AutoOpenCrates = true,
    AutoOpenSeedPacks = false,
    OpenEvery = 3,
    OpenMaxPerPass = 4,

    AutoPanicHarvest = true,
    AutoRetaliate = true,

    AutoEvents = true,
    GrabNormalPacks = true,
    EventScanEvery = 0.25,
    EventAttempts = 90,
    EventAttemptDelay = 0.12,
    EventPromptRadius = 35,

    AutoPets = true,
    PetScanEvery = 1.0,
    PetAttempts = 6,
    PetReservePercent = 12,

    AutoSprinklerPlace = true,
    SprinklerScanEvery = 1.0,

    HomeCheckEvery = 0.5,
}

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
    print("[GAG2 V3.3]", ...)
end

local function notify(text)
    log(text)
    pcall(function()
        StarterGui:SetCore("SendNotification", {
            Title = "GAG2 V3.3",
            Text = tostring(text),
            Duration = 4,
        })
    end)
end

local function fire(pkt, ...)
    if not pkt then return false end
    local a = {...}
    local ok, err = pcall(function() pkt:Fire(table.unpack(a)) end)
    if not ok then warn("[GAG2 V3.3] remote error", err) end
    return ok
end

local function spawnLoop(interval, fn)
    task.spawn(function()
        while running do
            task.wait(interval)
            if not running then break end
            local ok, err = pcall(fn)
            if not ok then warn("[GAG2 V3.3] loop error", err) end
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

local function reserveFor(v, pct)
    return math.max(CFG.AbsoluteCashReserve, v * ((pct or CFG.CashReservePercent) / 100))
end

local function myPlot()
    local g = Workspace:FindFirstChild("Gardens")
    if not g then return nil end
    for _, plot in ipairs(g:GetChildren()) do
        if plot:GetAttribute("OwnerUserId") == LP.UserId then return plot end
    end
end

local function char()
    return LP.Character
end

local function hrp()
    local c = char()
    return c and c:FindFirstChild("HumanoidRootPart")
end

local function humanoid()
    local c = char()
    return c and c:FindFirstChildOfClass("Humanoid")
end

local function isNight()
    local n = ReplicatedStorage:FindFirstChild("Night")
    return n and n.Value == true
end

local function homePos()
    local plot = myPlot()
    if not plot then return nil end
    -- Prefer actual plot center, not the outside SpawnPoint.
    local ref = plot:FindFirstChild("PlotSizeReference")
    if ref and ref:IsA("BasePart") then return ref.Position + Vector3.new(0, 4, 0) end
    local sp = plot:FindFirstChild("SpawnPoint")
    if sp and sp:IsA("BasePart") then return sp.Position + Vector3.new(0, 4, 0) end
end

local function insideOwnGarden()
    local root = hrp()
    local plot = myPlot()
    local ref = plot and plot:FindFirstChild("PlotSizeReference")
    if not (root and ref and ref:IsA("BasePart")) then return false end
    local p = ref.CFrame:PointToObjectSpace(root.Position)
    return math.abs(p.X) <= ref.Size.X/2 + 4 and math.abs(p.Z) <= ref.Size.Z/2 + 4
end

local originalCollide = setmetatable({}, {__mode="k"})
local function setCharCollide(on)
    local c = char()
    if not c then return end
    for _, p in ipairs(c:GetDescendants()) do
        if p:IsA("BasePart") then
            pcall(function()
                if not on then
                    if originalCollide[p] == nil then originalCollide[p] = p.CanCollide end
                    p.CanCollide = false
                elseif originalCollide[p] ~= nil then
                    p.CanCollide = originalCollide[p]
                    originalCollide[p] = nil
                end
            end)
        end
    end
end

local function reach(pos)
    local r = hrp()
    if not (r and pos) then return false end
    local target = pos
    setCharCollide(false)
    for _ = 1, 60 do
        r = hrp()
        if not r then break end
        local delta = target - r.Position
        if delta.Magnitude <= 70 then
            r.CFrame = CFrame.new(target)
            RunService.Heartbeat:Wait()
            break
        end
        r.CFrame = CFrame.new(r.Position + delta.Unit * 70)
        RunService.Heartbeat:Wait()
    end
    setCharCollide(true)
    r = hrp()
    return r and (r.Position-target).Magnitude <= 16 or false
end

local function returnHome()
    local p = homePos()
    if p and reach(p) then return true end
    fire(Net.TeleportButton and Net.TeleportButton.Request, "Garden")
    task.wait(0.35)
    p = homePos()
    if p then reach(p) end
    return insideOwnGarden()
end

--========================================================
-- ONE TRAVEL LOCK ONLY. Local progression never uses it.
-- Event/pet/sprinkler travel cannot overlap.
--========================================================
local travelOwner = nil
local function travelLocked()
    return travelOwner ~= nil
end
local function acquireTravel(owner)
    if travelOwner then return false end
    travelOwner = owner
    return true
end
local function releaseTravel(owner)
    if travelOwner == owner then travelOwner = nil end
end

--========================================================
-- PUNK-STYLE RIPE DETECTION / HARVEST
--========================================================
local function modelRipe(m)
    if not m then return false end
    local age = tonumber(m:GetAttribute("Age"))
    local mx = tonumber(m:GetAttribute("MaxAge"))
    if age and mx then return age >= mx - 0.001 end
    for _, d in ipairs(m:GetDescendants()) do
        if d:IsA("ProximityPrompt") and CollectionService:HasTag(d, "HarvestPrompt") then
            return true
        end
    end
    return false
end

local function ownHarvestTargets()
    local out = {}
    local plot = myPlot()
    local plants = plot and plot:FindFirstChild("Plants")
    if not plants then return out end
    for _, plant in ipairs(plants:GetChildren()) do
        local fr = plant:FindFirstChild("Fruits")
        local fruits = fr and fr:GetChildren() or {}
        if #fruits > 0 then
            for _, fruit in ipairs(fruits) do
                if modelRipe(fruit) and fruit:GetAttribute("PlantId") then
                    out[#out+1] = fruit
                end
            end
        elseif modelRipe(plant) and plant:GetAttribute("PlantId") then
            out[#out+1] = plant
        end
    end
    return out
end

local function harvestAll()
    local total = 0
    for _ = 1, CFG.HarvestPasses do
        local t = ownHarvestTargets()
        if #t == 0 then break end
        for _, m in ipairs(t) do
            if m.Parent then
                local pid = m:GetAttribute("PlantId")
                if pid then
                    fire(Net.Garden and Net.Garden.CollectFruit, pid, m:GetAttribute("FruitId") or "")
                    total += 1
                    task.wait(CFG.HarvestDelay)
                end
            end
        end
        task.wait(0.06)
    end
    return total
end

--========================================================
-- PUNK-STYLE STOCK / PLANTING
--========================================================
local function stockItems(shop)
    local sv = ReplicatedStorage:FindFirstChild("StockValues")
    sv = sv and sv:FindFirstChild(shop)
    return sv and sv:FindFirstChild("Items")
end

local function seedStockItems()
    return stockItems("SeedShop")
end

local function gearStockItems()
    return stockItems("GearShop")
end

local function bestAffordableSeed()
    local items = seedStockItems()
    if not items then return nil end
    local money = cash()
    local best, bestV
    for _, sv in ipairs(items:GetChildren()) do
        if sv:IsA("ValueBase") and sv.Value > 0 then
            local price = SeedPrice[sv.Name] or math.huge
            local val = SeedBaseValue[sv.Name] or 0
            if price <= money * (CFG.BuyMaxSeedPricePercent/100)
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
        if price > m * (CFG.BuyMaxSeedPricePercent/100) or m-price < reserveFor(m) then break end
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
            local ok, pv = pcall(function() return pl:GetPivot().Position end)
            if ok then occ[#occ+1] = pv end
        end
    end
    local free = {}
    for _, pos in ipairs(grid) do
        local clear = true
        for _, o in ipairs(occ) do
            if (Vector3.new(o.X,0,o.Z)-Vector3.new(pos.X,0,pos.Z)).Magnitude < 6 then
                clear = false
                break
            end
        end
        if clear then free[#free+1] = pos end
    end
    return free
end

local function progressPlant()
    local plot = myPlot()
    if not plot then return 0 end
    local d = getData()
    local seeds = d and d.Inventory and d.Inventory.Seeds
    if not seeds then return 0 end

    local rows = {}
    for name, count in pairs(seeds) do
        if (tonumber(count) or 0) > 0 then
            rows[#rows+1] = {name=name,count=tonumber(count) or 0,value=SeedBaseValue[name] or 0}
        end
    end
    table.sort(rows,function(a,b) return a.value>b.value end)

    local toPlant = {}
    for _, row in ipairs(rows) do
        for _=1,math.min(row.count,CFG.PlantMaxPerPass) do
            toPlant[#toPlant+1] = row.name
            if #toPlant >= CFG.PlantMaxPerPass then break end
        end
        if #toPlant >= CFG.PlantMaxPerPass then break end
    end
    if #toPlant == 0 then return 0 end

    local free = freePlantPositions(plot)
    local cap = math.min(#free,#toPlant,CFG.PlantMaxPerPass)
    local n = 0
    for i=1,cap do
        if fire(Net.Plant and Net.Plant.PlantSeed, free[i], toPlant[i], plot) then n += 1 end
        task.wait(CFG.PlantDelay)
    end
    return n
end

--========================================================
-- FAST PROGRESSION LOOP: same useful sequence as Punk AutoProgress
-- harvest -> sell -> buy -> plant
--========================================================
spawnLoop(CFG.ProgressEvery, function()
    if travelLocked() then return end
    if not insideOwnGarden() then returnHome() end

    local h = harvestAll()
    local beforeCash = cash()
    local fc = tonumber(LP:GetAttribute("FruitCount")) or 0
    if fc > 0 then
        fire(Net.NPCS and Net.NPCS.SellAll)
        task.wait(0.15)
    end

    local b, seed = progressBuy()
    local p = progressPlant()

    if h > 0 or (b or 0) > 0 or p > 0 or cash() ~= beforeCash then
        log("progress | harvest",h,"| buy",b or 0,seed or "-","| plant",p,"| cash",cash())
    end
end)

-- Emergency full sell check, independent but local-only.
spawnLoop(0.6, function()
    if travelLocked() then return end
    local fc = tonumber(LP:GetAttribute("FruitCount")) or 0
    local mx = tonumber(LP:GetAttribute("MaxFruitCapacity")) or 100
    if fc >= math.max(1,mx-2) then fire(Net.NPCS and Net.NPCS.SellAll) end
end)

--========================================================
-- EXPAND: Punk behavior, but with a small minimum cash guard.
--========================================================
local lastExpand = 0
spawnLoop(CFG.ExpandEvery, function()
    if travelLocked() or not CFG.AutoExpand then return end
    if cash() < CFG.ExpandMinCash or os.clock()-lastExpand < CFG.ExpandEvery then return end
    local plot = myPlot()
    if not plot then return end
    local before = tonumber(plot:GetAttribute("GardenExpansion")) or 0
    fire(Net.Actions and Net.Actions.ExpandGarden)
    task.wait(0.6)
    local after = tonumber(plot:GetAttribute("GardenExpansion")) or before
    if after > before then
        lastExpand = os.clock()
        log("garden expanded",before,"->",after)
    end
end)

--========================================================
-- GEAR / CRATES: same stock remotes Punk uses.
-- We buy in-stock gear only when game accepts it; sprinkler placement below.
--========================================================
spawnLoop(CFG.GearEvery, function()
    if travelLocked() or not CFG.AutoGear then return end
    local items = gearStockItems()
    if not items then return end
    for _, sv in ipairs(items:GetChildren()) do
        if sv:IsA("ValueBase") and sv.Value > 0 then
            -- Let the server reject unaffordable items just like Punk.
            fire(Net.GearShop and Net.GearShop.PurchaseGear, sv.Name)
            task.wait(0.08)
        end
    end
end)

spawnLoop(CFG.CrateEvery, function()
    if travelLocked() or not CFG.AutoCrates then return end
    local items = stockItems("CrateShop")
    if not items then return end
    for _, sv in ipairs(items:GetChildren()) do
        if sv:IsA("ValueBase") and sv.Value > 0 then
            fire(Net.CrateShop and Net.CrateShop.PurchaseCrate, sv.Name)
            task.wait(0.1)
        end
    end
end)

--========================================================
-- OPEN ITEMS
--========================================================
local function openBag(invKey,pkt,protectPacks)
    local d = getData()
    local bag = d and d.Inventory and d.Inventory[invKey]
    if type(bag) ~= "table" or not pkt then return 0 end
    local opened = 0
    for name,count in pairs(bag) do
        if opened >= CFG.OpenMaxPerPass then break end
        local lower = tostring(name):lower()
        local protected = protectPacks and (lower:find("mega",1,true) or lower:find("gold",1,true) or lower:find("rainbow",1,true))
        if not protected then
            local n = type(count)=="number" and count or 1
            for _=1,math.min(n,CFG.OpenMaxPerPass-opened) do
                fire(pkt,name)
                opened += 1
                task.wait(0.12)
            end
        end
    end
    return opened
end

spawnLoop(CFG.OpenEvery, function()
    if travelLocked() then return end
    if CFG.AutoOpenEggs then openBag("Eggs",Net.Egg and Net.Egg.OpenEgg,false) end
    if CFG.AutoOpenCrates then openBag("Crates",Net.Crate and Net.Crate.OpenCrate,true) end
    if CFG.AutoOpenSeedPacks then openBag("SeedPacks",Net.SeedPack and Net.SeedPack.OpenSeedPack,true) end
end)

--========================================================
-- NIGHT DEFENSE
-- Never interrupts an active event/pet transaction.
--========================================================
local wasNight = false
spawnLoop(0.35, function()
    local n = isNight()
    if n and not wasNight and CFG.AutoPanicHarvest then
        if not travelLocked() then
            returnHome()
            local h = harvestAll()
            if (tonumber(LP:GetAttribute("FruitCount")) or 0) > 0 then
                fire(Net.NPCS and Net.NPCS.SellAll)
            end
            log("night panic harvest",h)
        end
    end
    wasNight = n
end)

spawnLoop(0.5, function()
    if travelLocked() or not isNight() then return end
    if not insideOwnGarden() then returnHome() end

    if CFG.AutoRetaliate then
        local plot = myPlot()
        local ref = plot and plot:FindFirstChild("PlotSizeReference")
        if ref then
            for _, pl in ipairs(Players:GetPlayers()) do
                if pl ~= LP and pl.Character then
                    local r = pl.Character:FindFirstChild("HumanoidRootPart")
                    if r then
                        local p = ref.CFrame:PointToObjectSpace(r.Position)
                        if math.abs(p.X) < ref.Size.X/2+4 and math.abs(p.Z) < ref.Size.Z/2+4 then
                            fire(Net.Shovel and Net.Shovel.HitPlayer,pl.UserId)
                        end
                    end
                end
            end
        end
    end
end)

--========================================================
-- EVENTS: Punk's long stay-at-target behavior + one travel lock.
--========================================================
local function packKind(loc)
    if loc:GetAttribute("MegaSeed") == true then return "Mega Seed" end
    if loc:GetAttribute("GoldSeed") == true then return "Gold Seed" end
    if loc:GetAttribute("RainbowSeed") == true then return "Rainbow Seed" end
    local sp = loc:GetAttribute("SeedPack")
    if sp ~= nil then return tostring(sp) end
    local txt = tostring(loc.Name):lower()
    if txt:find("mega",1,true) then return "Mega Seed" end
    if txt:find("gold",1,true) then return "Gold Seed" end
    if txt:find("rainbow",1,true) then return "Rainbow Seed" end
    return "Pack"
end

local function isRarePack(loc)
    local k = packKind(loc):lower()
    return k:find("mega",1,true) or k:find("gold",1,true) or k:find("rainbow",1,true)
end

local function packLocations()
    local map = Workspace:FindFirstChild("Map")
    local f = map and map:FindFirstChild("SeedPackSpawnServerLocations")
    return f and f:GetChildren() or {}
end

local function locPart(loc)
    return loc:IsA("BasePart") and loc or loc:FindFirstChildWhichIsA("BasePart",true)
end
local function locPos(loc)
    if loc:IsA("BasePart") then return loc.Position end
    local ok,cf = pcall(function() return loc:GetPivot() end)
    if ok then return cf.Position end
    local p = locPart(loc)
    return p and p.Position or nil
end

local function firePrompt(d)
    pcall(function()
        local hold = tonumber(d.HoldDuration) or 0
        if fireproximityprompt then
            if hold > 0 then fireproximityprompt(d,hold) else fireproximityprompt(d) end
        else
            d:InputHoldBegin(); task.wait(hold+0.08); d:InputHoldEnd()
        end
    end)
end

local function holdSeedPrompts(pos)
    local map = Workspace:FindFirstChild("Map")
    for _,cont in ipairs({
        map and map:FindFirstChild("SeedPackSpawnServerLocations"),
        map and map:FindFirstChild("SeedPackSpawnClient"),
        Workspace:FindFirstChild("Temporary")
    }) do
        if cont then
            for _,d in ipairs(cont:GetDescendants()) do
                if d:IsA("ProximityPrompt") then
                    local pp
                    pcall(function()
                        if d.Parent:IsA("BasePart") then pp=d.Parent.Position
                        elseif d.Parent:IsA("Model") then pp=d.Parent:GetPivot().Position end
                    end)
                    if (not pp) or (pp-pos).Magnitude <= CFG.EventPromptRadius then firePrompt(d) end
                end
            end
        end
    end
end

local handledEvent = setmetatable({}, {__mode="k"})
local function grabPack(loc)
    if not loc or not loc.Parent or not acquireTravel("event") then return end
    local kind = packKind(loc)
    notify(kind.." detected")

    local originalParent = loc.Parent
    for _=1,CFG.EventAttempts do
        if not running or not loc.Parent then break end
        local pos = locPos(loc)
        if not pos then break end
        local r = hrp()
        if not r or (r.Position-pos).Magnitude > 7 then
            reach(pos+Vector3.new(0,3,0))
            task.wait(0.10)
        end
        for _,d in ipairs(loc:GetDescendants()) do
            if d:IsA("ProximityPrompt") then firePrompt(d) end
        end
        holdSeedPrompts(pos)
        local part = locPart(loc)
        if firetouchinterest and part and hrp() then
            pcall(function()
                firetouchinterest(hrp(),part,0)
                task.wait(0.03)
                firetouchinterest(hrp(),part,1)
            end)
        end
        if not loc.Parent or loc.Parent ~= originalParent then break end
        task.wait(CFG.EventAttemptDelay)
    end

    returnHome()
    releaseTravel("event")
    log("event transaction finished",kind)
end

spawnLoop(CFG.EventScanEvery,function()
    if not CFG.AutoEvents or travelLocked() then return end
    local best
    for _,loc in ipairs(packLocations()) do
        if loc.Parent and (not handledEvent[loc] or os.clock()-handledEvent[loc] > 8) then
            local rare = isRarePack(loc)
            if rare or CFG.GrabNormalPacks then
                if not best or (rare and not isRarePack(best)) then best=loc end
            end
        end
    end
    if best then
        handledEvent[best] = os.clock()
        task.spawn(function() grabPack(best) end)
    end
end)

--========================================================
-- PETS: only travel if we can determine cost AND afford it.
--========================================================
local GOOD_PETS = {
    Raccoon=true, Dragonfly=true, ["Dragon Fly"]=true, Dragonling=true, Mimic=true,
    ["Disco Bee"]=true, ["Queen Bee"]=true, Kitsune=true, ["Red Fox"]=true, Fox=true,
    Owl=true, ["Night Owl"]=true, Bear=true, ["Polar Bear"]=true, Butterfly=true,
    ["Golden Lab"]=true, Cat=true, ["Red Giant Ant"]=true, Snail=true,
}
local COST_KEYS = {"TameCost","TamePrice","PriceToTame","PurchasePrice","ShecklesCost","Cost","Price","Coins","CoinCost"}
local function petDataEntry(species)
    if type(PetData[species])=="table" then return PetData[species] end
    for k,v in pairs(PetData) do
        if type(v)=="table" then
            local n=v.PetName or v.Name or v.PetType or k
            if tostring(n)==tostring(species) then return v end
        end
    end
end
local function petCost(pet,species)
    for _,k in ipairs(COST_KEYS) do
        local n=tonumber(pet:GetAttribute(k)); if n then return n end
    end
    local d=petDataEntry(species)
    if type(d)=="table" then
        for _,k in ipairs(COST_KEYS) do
            local n=tonumber(d[k]); if n then return n end
        end
    end
end
local petCooldown=setmetatable({}, {__mode="k"})
spawnLoop(CFG.PetScanEvery,function()
    if not CFG.AutoPets or travelLocked() or isNight() then return end
    local map=Workspace:FindFirstChild("Map")
    local refs=map and map:FindFirstChild("WildPetRef")
    if not refs then return end
    for _,pet in ipairs(refs:GetChildren()) do
        local species=pet:GetAttribute("PetName")
        local owner=tonumber(pet:GetAttribute("OwnerUserId")) or 0
        if pet:IsA("BasePart") and species and GOOD_PETS[species] and (owner==0 or owner==LP.UserId)
            and os.clock()>=(petCooldown[pet] or 0)
        then
            local cost=petCost(pet,species)
            local m=cash()
            if cost and m-cost>=reserveFor(m,CFG.PetReservePercent) and acquireTravel("pet") then
                local before=m
                reach(pet.Position+Vector3.new(0,3,0))
                task.wait(0.25)
                for _=1,CFG.PetAttempts do
                    if not pet.Parent then break end
                    local now=cash()
                    if now-cost<reserveFor(now,CFG.PetReservePercent) then break end
                    fire(Net.Pets and Net.Pets.WildPetTame,pet)
                    task.wait(0.12)
                    local newOwner=pet.Parent and tonumber(pet:GetAttribute("OwnerUserId")) or LP.UserId
                    if newOwner==LP.UserId or cash()<before then break end
                end
                returnHome()
                fire(Net.Pets and Net.Pets.RequestEquipByName,species)
                releaseTravel("pet")
                petCooldown[pet]=os.clock()+15
                log("pet transaction finished",species)
                break
            elseif cost then
                petCooldown[pet]=os.clock()+5
            end
        end
    end
end)

--========================================================
-- SPRINKLER DEPLOY: buy loop above acquires gear, this places owned Tools.
-- One travel/local placement transaction at a time.
--========================================================
local placedSprinklerNames={}
local function findSprinklerTool()
    local function scan(c)
        if not c then return nil end
        for _,x in ipairs(c:GetChildren()) do
            if x:IsA("Tool") and tostring(x.Name):lower():find("sprinkler",1,true) then return x end
        end
    end
    return scan(LP:FindFirstChild("Backpack")) or scan(char())
end
local function sprinklerCount()
    local p=myPlot(); local f=p and p:FindFirstChild("Sprinklers")
    return f and #f:GetChildren() or 0
end
spawnLoop(CFG.SprinklerScanEvery,function()
    if not CFG.AutoSprinklerPlace or travelLocked() then return end
    local tool=findSprinklerTool()
    if not tool or placedSprinklerNames[tool.Name] then return end
    if not (Net.Prop and Net.Prop.PlaceProp) then return end
    if not acquireTravel("sprinkler") then return end
    returnHome()
    local p=myPlot(); local ref=p and p:FindFirstChild("PlotSizeReference")
    if ref then
        local before=sprinklerCount()
        fire(Net.Prop.PlaceProp,ref.Position+Vector3.new(0,ref.Size.Y/2+0.25,0),tool.Name,0,0)
        for _=1,20 do
            if sprinklerCount()>before then
                placedSprinklerNames[tool.Name]=true
                log("sprinkler placed",tool.Name)
                break
            end
            task.wait(0.1)
        end
    end
    releaseTravel("sprinkler")
end)

--========================================================
-- HOME ANCHOR: when nothing is travelling, keep character inside garden.
--========================================================
spawnLoop(CFG.HomeCheckEvery,function()
    if travelLocked() then return end
    if not insideOwnGarden() then returnHome() end
end)

-- Anti-AFK
pcall(function()
    LP.Idled:Connect(function()
        VirtualUser:CaptureController()
        VirtualUser:ClickButton2(Vector2.new())
    end)
end)

notify("V3.3 Punk-style core active: harvest > sell > buy > plant")
log("cash",cash(),"| plot",myPlot() and myPlot().Name or "?")
