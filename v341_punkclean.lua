--========================================================
-- GAG2 FARMER V3.4.1 - AUDITED PUNK CLEAN
-- Fast Punk-style local loops. One fail-safe lock for travel jobs.
--========================================================

local Players=game:GetService("Players")
local RS=game:GetService("ReplicatedStorage")
local RunService=game:GetService("RunService")
local CS=game:GetService("CollectionService")
local Workspace=game:GetService("Workspace")
local StarterGui=game:GetService("StarterGui")
local VirtualUser=game:GetService("VirtualUser")

local LP=Players.LocalPlayer
local ENV=(getgenv and getgenv()) or _G
repeat task.wait() until game:IsLoaded() and LP

for _,key in ipairs({
    "GAG2_V341_STOP","GAG2_V34_STOP","GAG2_V331_STOP","GAG2_V33_STOP","GAG2_BRAIN_V32_STOP",
    "GAG2_CORE_V31_STOP","GAG2_ECON_V31_STOP","GAG2_EVENT_V31_STOP","GAG2_V2_STOP","GAG2_EVENT_V3_STOP"
}) do
    local fn=ENV[key]
    if type(fn)=="function" then pcall(fn) end
end
local running=true
ENV.GAG2_V341_STOP=function() running=false end
ENV.GAG2_V32_BRAIN=nil
ENV.GAG2_V31_ACTIVITY_LOCK=nil

local Net=(function() local ok,m=pcall(function() return require(RS.SharedModules.Networking) end) return ok and m or nil end)()
local PSC=(function() local ok,m=pcall(function() return require(RS.ClientModules.PlayerStateClient) end) return ok and m or nil end)()
if not Net then warn("[GAG2 V3.4.1] Networking missing") return end
local SeedData=(function() local ok,d=pcall(function() return require(RS.SharedModules.SeedData) end) return ok and d or {} end)()
local FruitValueCalc=(function() local ok,m=pcall(function() return require(RS.SharedModules.FruitValueCalc) end) return (ok and type(m)=="function") and m or nil end)()
local PetData=(function()
    local sd=RS:FindFirstChild("SharedData"); local mod=sd and sd:FindFirstChild("PetData")
    if not mod then return {} end
    local ok,d=pcall(require,mod); return ok and type(d)=="table" and d or {}
end)()

local S={
    -- Equivalent to Punk's useful toggles being ON, without duplicate autoProgress.
    autoCollect=true, autoSell=true, autoBuySeed=true, autoPlant=true, autoExpand=true,
    autoGrabPacks=true, grabNormalPacks=true,
    autoTame=true, autoEquipPets=true,
    autoBuySprinklers=true, autoPlaceSprinklers=true,
    autoOpenEggs=true, autoOpenCrates=true, autoOpenSeedPacks=false,
    panicHarvest=true, retaliate=true, antiAfk=true,

    -- Punk-like timings.
    harvestLoop=0.80, sellLoop=0.70, buyLoop=1.50, plantLoop=1.00, expandLoop=6.0,
    perFruitDelay=0.025, plantDelay=0.08, plantStep=6,
    maxPlantsPerCycle=40, maxSeedBuysPerCycle=6,

    cashReservePercent=8, absoluteCashReserve=250, maxSeedPricePercent=50,
    wholePlantGrace=2.5,

    expandMinCash=15000, expandFreeSlotsLE=1,

    eventScanLoop=0.35, eventAttempts=90, eventAttemptDelay=0.12,
    eventPromptRadius=35, eventRetryFail=3,

    petScanLoop=1.20, petAttempts=6, petReservePercent=10,

    sprinklerScanLoop=1.0, sprinklerBuyLoop=2.0,
    sprinklerReservePercent=20, sprinklerMaxSpendPercent=30,

    openLoop=2.5, openMaxPerPass=4,
    defenseLoop=0.50, statusLoop=5.0,
}
ENV.GAG2_V341_CONFIG=S

local SeedPrice,SeedBaseValue={},{}
for _,e in pairs(SeedData) do
    if type(e)=="table" and e.SeedName then
        local name=e.SeedName; local price=tonumber(e.PurchasePrice) or math.huge
        SeedPrice[name]=price
        local value=0
        if FruitValueCalc then
            local ok,v=pcall(FruitValueCalc,name,1,nil,LP,nil)
            if ok and type(v)=="number" then value=v end
        end
        if value<=0 and price<math.huge then value=price end
        SeedBaseValue[name]=value
    end
end

local Stats={harvest=0,sells=0,buys=0,plants=0,expands=0,events=0,pets=0,sprinklers=0}
local function log(...) print("[GAG2 V3.4.1]",...) end
local function notify(text)
    log(text)
    pcall(function() StarterGui:SetCore("SendNotification",{Title="GAG2 V3.4.1",Text=tostring(text),Duration=4}) end)
end
local function fire(pkt,...)
    if not pkt then return false end
    local a={...}; local ok,err=pcall(function() pkt:Fire(table.unpack(a)) end)
    if not ok then warn("[GAG2 V3.4.1] remote error",err) end
    return ok
end
local function spawnLoop(interval,fn)
    task.spawn(function()
        while running do
            task.wait(interval); if not running then break end
            local ok,err=pcall(fn); if not ok then warn("[GAG2 V3.4.1] loop error",err) end
        end
    end)
end

local function getReplica()
    if not PSC then return nil end
    local ok,r=pcall(function() return PSC:GetLocalReplica() end); return ok and r or nil
end
local function getData() local r=getReplica(); return r and r.Data or nil end
local function cash() local d=getData(); return d and tonumber(d.Sheckles) or 0 end
local function reserveFor(v,pct) return math.max(S.absoluteCashReserve,v*((pct or S.cashReservePercent)/100)) end
local function fruitCount() return tonumber(LP:GetAttribute("FruitCount")) or 0 end
local function fruitCapacity() return tonumber(LP:GetAttribute("MaxFruitCapacity")) or 100 end
local function ownedSeeds() local d=getData(); return d and d.Inventory and d.Inventory.Seeds or nil end
local function ownedSeedTotal()
    local seeds=ownedSeeds(); if type(seeds)~="table" then return 0 end
    local n=0; for _,count in pairs(seeds) do n=n+(tonumber(count) or 0) end; return n
end

local function myPlot()
    local gardens=Workspace:FindFirstChild("Gardens"); if not gardens then return nil end
    local pid=LP:GetAttribute("PlotId")
    if pid~=nil then local p=gardens:FindFirstChild("Plot"..tostring(pid)); if p then return p end end
    for _,p in ipairs(gardens:GetChildren()) do
        if p:GetAttribute("OwnerUserId")==LP.UserId or p:GetAttribute("Owner")==LP.Name then return p end
    end
end
local function char() return LP.Character end
local function hrp() local c=char(); return c and c:FindFirstChild("HumanoidRootPart") end
local function homePos()
    local p=myPlot(); local ref=p and p:FindFirstChild("PlotSizeReference")
    if ref and ref:IsA("BasePart") then return ref.Position+Vector3.new(0,4,0) end
    local sp=p and p:FindFirstChild("SpawnPoint"); return sp and sp.Position+Vector3.new(0,4,0) or nil
end
local function insideOwnGarden()
    local r=hrp(); local p=myPlot(); local ref=p and p:FindFirstChild("PlotSizeReference")
    if not (r and ref and ref:IsA("BasePart")) then return false end
    local q=ref.CFrame:PointToObjectSpace(r.Position)
    return math.abs(q.X)<=ref.Size.X/2+4 and math.abs(q.Z)<=ref.Size.Z/2+4
end
local function isNight() local n=RS:FindFirstChild("Night"); return n and n.Value==true or false end

local originalCollide=setmetatable({}, {__mode="k"})
local function setCollide(on)
    local c=char(); if not c then return end
    for _,p in ipairs(c:GetDescendants()) do
        if p:IsA("BasePart") then pcall(function()
            if not on then
                if originalCollide[p]==nil then originalCollide[p]=p.CanCollide end; p.CanCollide=false
            elseif originalCollide[p]~=nil then p.CanCollide=originalCollide[p]; originalCollide[p]=nil end
        end) end
    end
end
local function reach(pos)
    local r=hrp(); if not (r and pos) then return false end
    setCollide(false)
    for _=1,60 do
        r=hrp(); if not r then break end
        local delta=pos-r.Position
        if delta.Magnitude<=70 then r.CFrame=CFrame.new(pos); RunService.Heartbeat:Wait(); break end
        r.CFrame=CFrame.new(r.Position+delta.Unit*70); RunService.Heartbeat:Wait()
    end
    setCollide(true); r=hrp(); return r and (r.Position-pos).Magnitude<=16 or false
end
local function returnHome()
    if insideOwnGarden() then return true end
    fire(Net.TeleportButton and Net.TeleportButton.Request,"Garden"); task.wait(0.35)
    local hp=homePos(); if hp and not insideOwnGarden() then reach(hp) end
    task.wait(0.08); return insideOwnGarden()
end
local function returnHomeReliable()
    for _=1,3 do if returnHome() then return true end task.wait(0.20) end
    return false
end

-- Fail-safe travel transaction. releaseTravel ALWAYS happens even on errors.
local travelOwner=nil
local function travelLocked() return travelOwner~=nil end
local function acquireTravel(owner)
    if travelOwner then return false end
    travelOwner=owner; log("travel lock ->",owner); return true
end
local function releaseTravel(owner)
    if travelOwner==owner then travelOwner=nil; log("travel unlock <-",owner) end
end
local function withTravel(owner,fn)
    if not acquireTravel(owner) then return false,"busy" end
    local ok,result=pcall(fn)
    if not ok then warn("[GAG2 V3.4.1] travel error",owner,result) end
    releaseTravel(owner)
    return ok,result
end

--========================================================
-- PLANT GRID
--========================================================
local function plantAreas(plot)
    local out={}
    for _,p in ipairs(CS:GetTagged("PlantArea")) do
        if p:IsA("BasePart") and p:IsDescendantOf(plot) and p.Size.X*p.Size.Z>400 then out[#out+1]=p end
    end
    if #out==0 then local ref=plot and plot:FindFirstChild("PlotSizeReference"); if ref and ref:IsA("BasePart") then out[1]=ref end end
    return out
end
local function plantPositions(plot)
    local out,seen={},{}; local step=S.plantStep
    for _,area in ipairs(plantAreas(plot)) do
        local cf,sz=area.CFrame,area.Size
        local hx,hz=math.max(0,sz.X/2-3),math.max(0,sz.Z/2-3)
        local nx,nz=math.floor((2*hx)/step),math.floor((2*hz)/step)
        local y=area.Position.Y+sz.Y/2+0.3
        for ix=0,nx do for iz=0,nz do
            local w=(cf*CFrame.new(-hx+ix*step,0,-hz+iz*step)).Position
            local key=math.floor(w.X/4+0.5)..","..math.floor(w.Z/4+0.5)
            if not seen[key] then seen[key]=true; out[#out+1]=Vector3.new(w.X,y,w.Z) end
        end end
    end
    return out
end
local function freePlantPositions(plot)
    local occ,free={},{}; local plants=plot and plot:FindFirstChild("Plants")
    if plants then for _,pl in ipairs(plants:GetChildren()) do
        local ok,pos=pcall(function() return pl:GetPivot().Position end); if ok then occ[#occ+1]=pos end
    end end
    for _,pos in ipairs(plantPositions(plot)) do
        local clear=true
        for _,used in ipairs(occ) do
            if (Vector3.new(used.X,0,used.Z)-Vector3.new(pos.X,0,pos.Z)).Magnitude<6 then clear=false; break end
        end
        if clear then free[#free+1]=pos end
    end
    return free
end
local function freeSlotCount() local p=myPlot(); return p and #freePlantPositions(p) or 0 end

--========================================================
-- SAFE HARVEST
-- Fruiting: actual fruit objects. Single-harvest: mature whole plant.
--========================================================
local firstSeen=setmetatable({}, {__mode="k"})
local function seenAt(plant) if not firstSeen[plant] then firstSeen[plant]=os.clock() end return firstSeen[plant] end
local function harvestPromptReady(model)
    for _,d in ipairs(model:GetDescendants()) do
        if d:IsA("ProximityPrompt") and CS:HasTag(d,"HarvestPrompt") then
            local ok,en=pcall(function() return d.Enabled end); if (not ok) or en then return true end
        end
    end
    return false
end
local function wholePlantRipe(plant)
    local first=seenAt(plant); local age=tonumber(plant:GetAttribute("Age")); local mx=tonumber(plant:GetAttribute("MaxAge"))
    if age~=nil and mx~=nil then
        if mx<=0 then return false end -- fixes freshly-planted transient 0/0
        if age<mx-0.001 then return false end
        return os.clock()-first>=0.35
    end
    return os.clock()-first>=S.wholePlantGrace and harvestPromptReady(plant)
end
local function harvestAll()
    local p=myPlot(); local plants=p and p:FindFirstChild("Plants"); if not plants then return 0 end
    local n=0
    for _,plant in ipairs(plants:GetChildren()) do
        seenAt(plant)
        local ff=plant:FindFirstChild("Fruits"); local fruits=ff and ff:GetChildren() or {}
        if #fruits>0 then
            for _,fruit in ipairs(fruits) do
                local pid=fruit:GetAttribute("PlantId"); local fid=fruit:GetAttribute("FruitId")
                if pid~=nil and fid~=nil then
                    if fire(Net.Garden and Net.Garden.CollectFruit,pid,fid) then n=n+1 end
                    task.wait(S.perFruitDelay)
                end
            end
        elseif wholePlantRipe(plant) then
            local pid=plant:GetAttribute("PlantId")
            if pid~=nil then
                if fire(Net.Garden and Net.Garden.CollectFruit,pid,plant:GetAttribute("FruitId") or "") then n=n+1 end
                task.wait(S.perFruitDelay)
            end
        end
    end
    if n>0 then Stats.harvest=Stats.harvest+n; log("harvest",n) end
    return n
end
local function sellNow()
    local fc=fruitCount(); if fc<=0 then return false end
    local before=cash(); fire(Net.NPCS and Net.NPCS.SellAll); task.wait(0.12)
    Stats.sells=Stats.sells+1
    if cash()~=before then log("sell",fc,"fruit | cash",before,"->",cash()) end
    return true
end

--========================================================
-- BUY / PLANT
--========================================================
local function stockItems(shop)
    local sv=RS:FindFirstChild("StockValues"); sv=sv and sv:FindFirstChild(shop); return sv and sv:FindFirstChild("Items")
end
local function seedStockItems() return stockItems("SeedShop") end
local function gearStockItems() return stockItems("GearShop") end
local function bestAffordableSeed()
    local items=seedStockItems(); if not items then return nil end
    local money=cash(); local best,bestV,bestStock
    for _,sv in ipairs(items:GetChildren()) do
        if sv:IsA("ValueBase") and (tonumber(sv.Value) or 0)>0 then
            local price=SeedPrice[sv.Name] or math.huge; local value=SeedBaseValue[sv.Name] or 0
            if price>0 and price<math.huge and price<=money*S.maxSeedPricePercent/100
                and money-price>=reserveFor(money) and (not bestV or value>bestV)
            then best,bestV,bestStock=sv.Name,value,tonumber(sv.Value) or 0 end
        end
    end
    return best,bestStock
end
local function buySeeds()
    local need=freeSlotCount()-ownedSeedTotal(); if need<=0 then return 0 end
    local best,stock=bestAffordableSeed(); if not best then return 0 end
    local price=SeedPrice[best] or math.huge; local cap=math.min(S.maxSeedBuysPerCycle,need,stock or S.maxSeedBuysPerCycle); local n=0
    for _=1,cap do
        local money=cash(); if price>money*S.maxSeedPricePercent/100 or money-price<reserveFor(money) then break end
        if fire(Net.SeedShop and Net.SeedShop.PurchaseSeed,best) then n=n+1 end; task.wait(0.09)
    end
    if n>0 then Stats.buys=Stats.buys+n; log("buy",n,"x",best,"| cash",cash()) end
    return n
end
local function seedQueue()
    local seeds=ownedSeeds(); if type(seeds)~="table" then return {} end
    local rows={}
    for name,count in pairs(seeds) do count=tonumber(count) or 0; if count>0 then rows[#rows+1]={name=name,count=count,value=SeedBaseValue[name] or 0} end end
    table.sort(rows,function(a,b) if a.value==b.value then return a.name<b.name end return a.value>b.value end)
    local q={}
    for _,row in ipairs(rows) do for _=1,math.min(row.count,S.maxPlantsPerCycle) do
        q[#q+1]=row.name; if #q>=S.maxPlantsPerCycle then return q end
    end end
    return q
end
local function plantSeeds()
    local p=myPlot(); if not p then return 0 end
    if not insideOwnGarden() then returnHome() end
    local free=freePlantPositions(p); local q=seedQueue(); local cap=math.min(#free,#q,S.maxPlantsPerCycle); if cap<=0 then return 0 end
    local n=0
    for i=1,cap do if fire(Net.Plant and Net.Plant.PlantSeed,free[i],q[i],p) then n=n+1 end; task.wait(S.plantDelay) end
    if n>0 then Stats.plants=Stats.plants+n; log("plant attempts",n) end
    return n
end

-- Punk's useful standalone-loop behavior, but paused as a group during travel.
spawnLoop(S.harvestLoop,function() if S.autoCollect and not travelLocked() then harvestAll() end end)
spawnLoop(S.sellLoop,function() if S.autoSell and not travelLocked() and fruitCount()>0 then sellNow() end end)
spawnLoop(S.buyLoop,function() if S.autoBuySeed and not travelLocked() then buySeeds() end end)
spawnLoop(S.plantLoop,function() if S.autoPlant and not travelLocked() then plantSeeds() end end)
spawnLoop(S.expandLoop,function()
    if not S.autoExpand or travelLocked() or freeSlotCount()>S.expandFreeSlotsLE or cash()<S.expandMinCash then return end
    local p=myPlot(); if not p then return end
    local before=tonumber(p:GetAttribute("GardenExpansion")) or 0; local cb=cash()
    fire(Net.Actions and Net.Actions.ExpandGarden); task.wait(0.9)
    local after=tonumber(p:GetAttribute("GardenExpansion")) or before
    if after>before then Stats.expands=Stats.expands+1; log("expand",before,"->",after,"| cash",cb,"->",cash()) end
end)

--========================================================
-- SPRINKLERS
--========================================================
local function tryRequire(parent,name)
    local m=parent and parent:FindFirstChild(name); if m and m:IsA("ModuleScript") then local ok,v=pcall(require,m); if ok and type(v)=="table" then return v end end
end
local sm=RS:FindFirstChild("SharedModules"); local sd=RS:FindFirstChild("SharedData")
local GearData=tryRequire(sm,"GearData") or tryRequire(sm,"GearShopData") or tryRequire(sd,"GearData") or tryRequire(sd,"GearShopData")
local function gearEntry(name)
    if type(GearData)~="table" then return nil end
    if type(GearData[name])=="table" then return GearData[name] end
    for _,v in pairs(GearData) do if type(v)=="table" and (v.GearName==name or v.Name==name or v.ItemName==name) then return v end end
end
local function gearPrice(name) local e=gearEntry(name); return type(e)=="table" and tonumber(e.PurchasePrice or e.Price or e.Cost or e.ShecklesCost) or nil end
local function isSprinkler(name) return tostring(name or ""):lower():find("sprinkler",1,true)~=nil end
local function sprinklerFolder() local p=myPlot(); return p and p:FindFirstChild("Sprinklers") end
local function placedSprinklerCount(name)
    local f=sprinklerFolder(); if not f then return 0 end; local n=0
    for _,x in ipairs(f:GetChildren()) do local kind=x:GetAttribute("PropName") or x:GetAttribute("ItemName") or x:GetAttribute("Type") or x.Name; if not name or tostring(kind)==tostring(name) then n=n+1 end end
    return n
end
local function findSprinklerTool()
    local function scan(c) if c then for _,x in ipairs(c:GetChildren()) do if x:IsA("Tool") and isSprinkler(x.Name) then return x end end end end
    return scan(LP:FindFirstChild("Backpack")) or scan(char())
end
local sprinklerBlocked={}; local sprinklerAmbiguous={}
local function sprinklerBuyCandidate()
    if not GearData then return nil end
    local items=gearStockItems(); if not items then return nil end
    local money=cash(); local best,bestPrice
    for _,sv in ipairs(items:GetChildren()) do
        local name=sv.Name; local price=gearPrice(name)
        if sv:IsA("ValueBase") and (tonumber(sv.Value) or 0)>0 and isSprinkler(name)
            and placedSprinklerCount(name)==0 and not sprinklerAmbiguous[name] and os.clock()>=(sprinklerBlocked[name] or 0)
            and price and price>0 and price<=money*S.sprinklerMaxSpendPercent/100 and money-price>=reserveFor(money,S.sprinklerReservePercent)
        then if not bestPrice or price>bestPrice then best,bestPrice=name,price end end
    end
    return best,bestPrice
end
spawnLoop(S.sprinklerBuyLoop,function()
    if not S.autoBuySprinklers or travelLocked() or findSprinklerTool() then return end
    local name,price=sprinklerBuyCandidate(); if not name then return end
    local before=cash(); fire(Net.GearShop and Net.GearShop.PurchaseGear,name); task.wait(0.30)
    if findSprinklerTool() then log("sprinkler purchase confirmed",name,"~",price)
    elseif cash()<before then sprinklerAmbiguous[name]=true; warn("[GAG2 V3.4.1] sprinkler cash moved but tool not visible; blocking rebuy",name)
    else sprinklerBlocked[name]=os.clock()+10 end
end)
spawnLoop(S.sprinklerScanLoop,function()
    if not S.autoPlaceSprinklers or travelLocked() then return end
    local tool=findSprinklerTool(); if not tool or not (Net.Prop and Net.Prop.PlaceProp) then return end
    local name=tool.Name; if os.clock()<(sprinklerBlocked[name] or 0) then return end
    withTravel("sprinkler",function()
        returnHomeReliable()
        local p=myPlot(); local ref=p and p:FindFirstChild("PlotSizeReference"); local before=placedSprinklerCount(name)
        if ref then
            fire(Net.Prop.PlaceProp,ref.Position+Vector3.new(0,ref.Size.Y/2+0.25,0),name,0,0)
            for _=1,20 do if placedSprinklerCount(name)>before then break end task.wait(0.10) end
        end
        if placedSprinklerCount(name)>before then Stats.sprinklers=Stats.sprinklers+1; log("sprinkler placed",name)
        else sprinklerBlocked[name]=os.clock()+60; warn("[GAG2 V3.4.1] sprinkler placement unconfirmed; 60s block",name) end
    end)
end)

--========================================================
-- EVENTS
--========================================================
local function packLocations() local map=Workspace:FindFirstChild("Map"); local f=map and map:FindFirstChild("SeedPackSpawnServerLocations"); return f and f:GetChildren() or {} end
local function packKind(loc)
    if loc:GetAttribute("MegaSeed")==true then return "Mega Seed" end
    if loc:GetAttribute("GoldSeed")==true then return "Gold Seed" end
    if loc:GetAttribute("RainbowSeed")==true then return "Rainbow Seed" end
    local sp=loc:GetAttribute("SeedPack"); if sp~=nil then return tostring(sp) end
    local t=tostring(loc.Name):lower(); if t:find("mega",1,true) then return "Mega Seed" end; if t:find("gold",1,true) then return "Gold Seed" end; if t:find("rainbow",1,true) then return "Rainbow Seed" end
    return "Pack"
end
local function rarePack(loc) local k=packKind(loc):lower(); return k:find("mega",1,true) or k:find("gold",1,true) or k:find("rainbow",1,true) end
local function locPart(loc) return loc:IsA("BasePart") and loc or loc:FindFirstChildWhichIsA("BasePart",true) end
local function locPos(loc)
    if loc:IsA("BasePart") then return loc.Position end
    local ok,cf=pcall(function() return loc:GetPivot() end); if ok then return cf.Position end
    local p=locPart(loc); return p and p.Position or nil
end
local function firePrompt(d)
    pcall(function()
        local hold=tonumber(d.HoldDuration) or 0
        if fireproximityprompt then if hold>0 then fireproximityprompt(d,hold) else fireproximityprompt(d) end
        else d:InputHoldBegin(); task.wait(hold+0.08); d:InputHoldEnd() end
    end)
end
local function holdNearbyPrompts(pos)
    local map=Workspace:FindFirstChild("Map")
    for _,cont in ipairs({map and map:FindFirstChild("SeedPackSpawnServerLocations"),map and map:FindFirstChild("SeedPackSpawnClient"),Workspace:FindFirstChild("Temporary")}) do
        if cont then for _,d in ipairs(cont:GetDescendants()) do if d:IsA("ProximityPrompt") then
            local pp; pcall(function() if d.Parent:IsA("BasePart") then pp=d.Parent.Position elseif d.Parent:IsA("Model") then pp=d.Parent:GetPivot().Position end end)
            if not pp or (pp-pos).Magnitude<=S.eventPromptRadius then firePrompt(d) end
        end end end
    end
end
local handledEvent=setmetatable({}, {__mode="k"})
local function grabPack(loc)
    if not loc or not loc.Parent then return end
    withTravel("event",function()
        local kind=packKind(loc); local originalParent=loc.Parent; notify(kind.." detected - collecting")
        if insideOwnGarden() then harvestAll(); if fruitCount()>0 then sellNow() end end
        for _=1,S.eventAttempts do
            if not running or not loc.Parent then break end
            local pos=locPos(loc); if not pos then break end
            local r=hrp(); if not r or (r.Position-pos).Magnitude>7 then reach(pos+Vector3.new(0,3,0)); task.wait(0.10) end
            for _,d in ipairs(loc:GetDescendants()) do if d:IsA("ProximityPrompt") then firePrompt(d) end end
            holdNearbyPrompts(pos)
            local part=locPart(loc)
            if firetouchinterest and part and hrp() then pcall(function() firetouchinterest(hrp(),part,0); task.wait(0.03); firetouchinterest(hrp(),part,1) end) end
            if not loc.Parent or loc.Parent~=originalParent then break end
            task.wait(S.eventAttemptDelay)
        end
        local success=(not loc.Parent) or loc.Parent~=originalParent
        returnHomeReliable(); handledEvent[loc]=os.clock()+(success and 30 or S.eventRetryFail)
        if success then Stats.events=Stats.events+1 end
        log("event finished",kind,success and "collected" or "unconfirmed")
    end)
end
spawnLoop(S.eventScanLoop,function()
    if not S.autoGrabPacks or travelLocked() then return end
    local best,bestRare
    for _,loc in ipairs(packLocations()) do
        if loc.Parent and os.clock()>=(handledEvent[loc] or 0) then
            local rare=rarePack(loc) and true or false
            -- Night: protect garden, only leave for high-value rare event.
            local eligible=rare or (S.grabNormalPacks and not isNight())
            if eligible and (not best or (rare and not bestRare)) then best,bestRare=loc,rare end
        end
    end
    if best then task.spawn(function() local ok,err=pcall(grabPack,best); if not ok then warn("[GAG2 V3.4.1] event task error",err) end end) end
end)

--========================================================
-- PETS
--========================================================
local GOOD_PETS={Raccoon=true,Dragonfly=true,["Dragon Fly"]=true,Dragonling=true,Mimic=true,["Disco Bee"]=true,["Queen Bee"]=true,Kitsune=true,["Red Fox"]=true,Fox=true,Owl=true,["Night Owl"]=true,Bear=true,["Polar Bear"]=true,Butterfly=true,["Golden Lab"]=true,Cat=true,["Red Giant Ant"]=true,Snail=true}
local COST_KEYS={"TameCost","TamePrice","PriceToTame","PurchasePrice","ShecklesCost","Cost","Price","Coins","CoinCost"}
local function petDataEntry(species)
    if type(PetData[species])=="table" then return PetData[species] end
    for k,v in pairs(PetData) do if type(v)=="table" then local name=v.PetName or v.Name or v.PetType or k; if tostring(name)==tostring(species) then return v end end end
end
local function petCost(pet,species)
    for _,k in ipairs(COST_KEYS) do local n=tonumber(pet:GetAttribute(k)); if n~=nil then return n end end
    local d=petDataEntry(species); if type(d)=="table" then for _,k in ipairs(COST_KEYS) do local n=tonumber(d[k]); if n~=nil then return n end end end
end
local petCooldown=setmetatable({}, {__mode="k"}); local unknownPetLogged={}
local function rareEventWaiting() for _,loc in ipairs(packLocations()) do if loc.Parent and rarePack(loc) then return true end end return false end
spawnLoop(S.petScanLoop,function()
    if not S.autoTame or travelLocked() or isNight() or rareEventWaiting() then return end
    local map=Workspace:FindFirstChild("Map"); local refs=map and map:FindFirstChild("WildPetRef"); if not refs then return end
    for _,pet in ipairs(refs:GetChildren()) do
        local species=pet:GetAttribute("PetName"); local owner=tonumber(pet:GetAttribute("OwnerUserId")) or 0
        if pet:IsA("BasePart") and species and GOOD_PETS[species] and owner==0 and os.clock()>=(petCooldown[pet] or 0) then
            local cost=petCost(pet,species); local money=cash()
            if cost==nil then
                if not unknownPetLogged[species] then unknownPetLogged[species]=true; log("pet skipped - cost unknown",species) end
                petCooldown[pet]=os.clock()+10
            elseif money-cost>=reserveFor(money,S.petReservePercent) then
                local success=false
                local ok=withTravel("pet",function()
                    harvestAll(); if fruitCount()>0 then sellNow() end
                    reach(pet.Position+Vector3.new(0,3,0)); task.wait(0.25)
                    for _=1,S.petAttempts do
                        if not pet.Parent then success=true; break end
                        local cur=cash(); if cur-cost<reserveFor(cur,S.petReservePercent) then break end
                        fire(Net.Pets and Net.Pets.WildPetTame,pet); task.wait(0.12)
                        local newOwner=pet.Parent and (tonumber(pet:GetAttribute("OwnerUserId")) or 0) or LP.UserId
                        if newOwner==LP.UserId or not pet.Parent then success=true; break end
                    end
                    returnHomeReliable()
                    if success and S.autoEquipPets then fire(Net.Pets and Net.Pets.RequestEquipByName,species) end
                end)
                petCooldown[pet]=os.clock()+(success and 30 or 8)
                if ok and success then Stats.pets=Stats.pets+1 end
                log("pet finished",species,success and "tamed" or "failed")
                break
            else petCooldown[pet]=os.clock()+4 end
        end
    end
end)

--========================================================
-- OPEN ITEMS
--========================================================
local function protectedPack(name) local s=tostring(name or ""):lower(); return s:find("mega",1,true) or s:find("gold",1,true) or s:find("rainbow",1,true) end
local function openBag(key,pkt,protect)
    local d=getData(); local bag=d and d.Inventory and d.Inventory[key]; if type(bag)~="table" or not pkt then return 0 end
    local opened=0
    for name,count in pairs(bag) do
        if opened>=S.openMaxPerPass then break end
        if not (protect and protectedPack(name)) then
            local n=type(count)=="number" and count or 1
            for _=1,math.min(n,S.openMaxPerPass-opened) do fire(pkt,name); opened=opened+1; task.wait(0.12) end
        end
    end
    return opened
end
spawnLoop(S.openLoop,function()
    if travelLocked() then return end
    if S.autoOpenEggs then openBag("Eggs",Net.Egg and Net.Egg.OpenEgg,false) end
    if S.autoOpenCrates then openBag("Crates",Net.Crate and Net.Crate.OpenCrate,true) end
    if S.autoOpenSeedPacks then openBag("SeedPacks",Net.SeedPack and Net.SeedPack.OpenSeedPack,true) end
end)

--========================================================
-- NIGHT DEFENSE
--========================================================
local wasNight=false
spawnLoop(S.defenseLoop,function()
    local n=isNight()
    if n and not wasNight and S.panicHarvest and not travelLocked() then returnHomeReliable(); harvestAll(); if fruitCount()>0 then sellNow() end; log("night secured") end
    wasNight=n
    if n and not travelLocked() then
        if not insideOwnGarden() then returnHomeReliable() end
        if S.retaliate then
            local p=myPlot(); local ref=p and p:FindFirstChild("PlotSizeReference")
            if ref then for _,pl in ipairs(Players:GetPlayers()) do
                if pl~=LP and pl.Character then
                    local r=pl.Character:FindFirstChild("HumanoidRootPart")
                    if r then local q=ref.CFrame:PointToObjectSpace(r.Position); if math.abs(q.X)<ref.Size.X/2+4 and math.abs(q.Z)<ref.Size.Z/2+4 then fire(Net.Shovel and Net.Shovel.HitPlayer,pl.UserId) end end
                end
            end end
        end
    end
end)

-- Status makes "waiting for growth/stock" visible instead of looking frozen.
spawnLoop(S.statusLoop,function()
    local p=myPlot(); local plants=p and p:FindFirstChild("Plants"); local pc=plants and #plants:GetChildren() or 0
    log("STATUS | cash",cash(),"| fruit",fruitCount().."/"..fruitCapacity(),"| plants",pc,"| free",freeSlotCount(),"| seeds",ownedSeedTotal(),"| travel",travelOwner or "none","| H/S/B/P",Stats.harvest.."/"..Stats.sells.."/"..Stats.buys.."/"..Stats.plants)
end)

pcall(function() LP.Idled:Connect(function() if S.antiAfk then VirtualUser:CaptureController(); VirtualUser:ClickButton2(Vector2.new()) end end) end)

notify("AUDITED PUNK CLEAN loaded")
print("================================================")
print(" GAG2 V3.4.1 AUDITED PUNK CLEAN RUNNING")
print(" harvest/sell/buy/plant = fast independent local loops")
print(" event/pet/sprinkler = one fail-safe travel lock")
print(" whole-plant harvest = MaxAge>0 guard + grace fallback")
print(" ordinary event packs never pull you out at night")
print("================================================")