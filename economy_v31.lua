--========================================================
-- GAG2 FARMER V3.1 ECONOMY
-- Smart seed buying + safe expand + gear sniper + item opening + good wild pets
--========================================================

local CFG = {
    AutoSmartSeeds = true,
    SeedCheckEvery = 12,
    BuyPerCycle = 2,
    CashReservePercent = 65,
    AbsoluteCashReserve = 5000,

    AutoExpand = true,
    ExpandCheckEvery = 20,
    ExpandMinCash = 250000,
    ExpandCooldown = 90,

    AutoGear = true,
    GearCheckEvery = 8,
    GearMaxSpendPercent = 10,
    GearMinCash = 50000,

    AutoOpenEggs = true,
    AutoOpenCrates = true,
    AutoOpenSeedPacks = false,
    OpenCheckEvery = 15,
    MaxOpenPerCycle = 4,

    AutoTameGoodPets = true,
    PetCheckEvery = 5,
    PetAttempts = 6,
}

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local LP = Players.LocalPlayer
local ENV = (getgenv and getgenv()) or _G

if ENV.GAG2_ECON_V31_STOP then pcall(ENV.GAG2_ECON_V31_STOP) end
local running = true
ENV.GAG2_ECON_V31_STOP = function() running = false end

local Net = require(ReplicatedStorage:WaitForChild("SharedModules"):WaitForChild("Networking"))
local PSC
pcall(function() PSC = require(ReplicatedStorage:WaitForChild("ClientModules"):WaitForChild("PlayerStateClient")) end)
local SeedData = {}
pcall(function() SeedData = require(ReplicatedStorage:WaitForChild("SharedModules"):WaitForChild("SeedData")) end)
local FruitValueCalc
pcall(function() FruitValueCalc = require(ReplicatedStorage:WaitForChild("SharedModules"):WaitForChild("FruitValueCalc")) end)

local function notify(text)
    print("[GAG2 V3.1 ECON]", text)
    pcall(function()
        StarterGui:SetCore("SendNotification", {Title="GAG2 V3.1 Economy",Text=text,Duration=4})
    end)
end

local function fire(packet,...)
    if not packet then return false end
    local args={...}
    local ok,err=pcall(function() packet:Fire(table.unpack(args)) end)
    if not ok then warn("[GAG2 V3.1 ECON] Fire error:",err) end
    return ok
end

local function locked() return ENV.GAG2_V31_ACTIVITY_LOCK ~= nil end
local function getData()
    if not PSC then return nil end
    local ok,r=pcall(function() return PSC:GetLocalReplica() end)
    return ok and r and r.Data or nil
end
local function money()
    local d=getData(); return d and tonumber(d.Sheckles) or 0
end
local function reserveFor(cash)
    return math.max(CFG.AbsoluteCashReserve,cash*(CFG.CashReservePercent/100))
end

--================ SMART SEED MODEL ================================
local SeedInfo = {}
local GROW_KEYS={"GrowthTime","GrowTime","TimeToGrow","HarvestTime","GrowDuration","MaxAge","Duration"}
local YIELD_KEYS={"Yield","HarvestAmount","FruitCount","FruitsPerHarvest","ProduceCount"}

local function firstNumber(t,keys)
    if type(t)~="table" then return nil end
    for _,k in ipairs(keys) do
        local v=tonumber(t[k]); if v and v>0 then return v end
    end
end

for _,e in pairs(SeedData) do
    if type(e)=="table" and e.SeedName then
        local name=e.SeedName
        local price=tonumber(e.PurchasePrice) or math.huge
        local base=0
        if type(FruitValueCalc)=="function" then
            local ok,v=pcall(FruitValueCalc,name,1,nil,LP,nil)
            if ok and type(v)=="number" then base=v end
        end
        if base<=0 and price<math.huge then base=price end
        local grow=firstNumber(e,GROW_KEYS)
        local yield=firstNumber(e,YIELD_KEYS) or 1
        local score
        if grow then
            score=(base*yield)/math.max(grow,1)
        elseif price<math.huge and price>0 then
            -- Fallback when current SeedData does not expose a growth field.
            score=(base*yield)/math.sqrt(price)
        else
            score=base*yield
        end
        SeedInfo[name]={price=price,base=base,grow=grow,yield=yield,score=score}
    end
end

local function publishScores()
    local s={}
    for name,info in pairs(SeedInfo) do s[name]=info.score end
    ENV.GAG2_V31_SEED_SCORE=s
end
publishScores()

local function seedStockFolder()
    local sv=ReplicatedStorage:FindFirstChild("StockValues")
    local sh=sv and sv:FindFirstChild("SeedShop")
    return sh and sh:FindFirstChild("Items")
end

local function chooseSeed()
    local folder=seedStockFolder(); if not folder then return nil end
    local cash=money(); if cash<=0 then return nil end
    local reserve=reserveFor(cash)
    local best,bestScore
    for _,stock in ipairs(folder:GetChildren()) do
        local count=tonumber(stock.Value) or 0
        local info=SeedInfo[stock.Name]
        if count>0 and info and info.price<math.huge and cash-info.price>=reserve then
            if not bestScore or info.score>bestScore then
                best,bestScore=stock.Name,info.score
            end
        end
    end
    return best,bestScore
end

local function smartBuy()
    if not CFG.AutoSmartSeeds or locked() then return end
    publishScores()
    local name,score=chooseSeed(); if not name then return end
    local info=SeedInfo[name]; if not info then return end
    local bought=0
    for _=1,CFG.BuyPerCycle do
        local cash=money()
        if cash-info.price<reserveFor(cash) then break end
        if fire(Net.SeedShop.PurchaseSeed,name) then bought+=1 end
        task.wait(0.12)
    end
    if bought>0 then
        print(("[GAG2 V3.1 ECON] Smart buy %dx %s | score %.2f | grow %s | cash %d"):format(
            bought,name,score or 0,tostring(info.grow or "ROI-fallback"),money()))
    end
end

--================ SAFE GARDEN EXPAND ==============================
local function myPlot()
    local g=Workspace:FindFirstChild("Gardens"); if not g then return nil end
    local pid=LP:GetAttribute("PlotId")
    if pid~=nil then local p=g:FindFirstChild("Plot"..tostring(pid)); if p then return p end end
    for _,p in ipairs(g:GetChildren()) do
        if p:GetAttribute("OwnerUserId")==LP.UserId or p:GetAttribute("Owner")==LP.Name then return p end
    end
end

local lastExpand=0
local function tryExpand()
    if not CFG.AutoExpand or locked() then return end
    if os.clock()-lastExpand<CFG.ExpandCooldown then return end
    local cash=money(); if cash<CFG.ExpandMinCash then return end
    local p=myPlot(); if not p then return end
    local before=tonumber(p:GetAttribute("GardenExpansion")) or 0
    local beforeCash=cash
    fire(Net.Actions and Net.Actions.ExpandGarden)
    task.wait(0.8)
    local after=tonumber(p:GetAttribute("GardenExpansion")) or before
    if after>before then
        lastExpand=os.clock()
        print("[GAG2 V3.1 ECON] Garden expanded",before,"->",after,"spent",math.max(0,beforeCash-money()))
    end
end

--================ GEAR SNIPER =====================================
local GearData
local function tryRequire(parent,name)
    local m=parent and parent:FindFirstChild(name)
    if m and m:IsA("ModuleScript") then
        local ok,v=pcall(require,m); if ok and type(v)=="table" then return v end
    end
end

local sharedModules=ReplicatedStorage:FindFirstChild("SharedModules")
local sharedData=ReplicatedStorage:FindFirstChild("SharedData")
GearData=tryRequire(sharedModules,"GearData")
    or tryRequire(sharedModules,"GearShopData")
    or tryRequire(sharedData,"GearData")
    or tryRequire(sharedData,"GearShopData")

local RARITY={Common=1,Uncommon=2,Rare=3,Epic=4,Legendary=5,Mythic=6,Divine=7,Prismatic=8,Transcendent=9}
local function gearEntry(name)
    if type(GearData)~="table" then return nil end
    if type(GearData[name])=="table" then return GearData[name] end
    for _,v in pairs(GearData) do
        if type(v)=="table" and (v.GearName==name or v.Name==name or v.ItemName==name) then return v end
    end
end
local function gearPrice(e)
    if type(e)~="table" then return nil end
    return tonumber(e.PurchasePrice or e.Price or e.Cost or e.ShecklesCost)
end
local function gearScore(e,price)
    if type(e)~="table" then return 0 end
    local rarity=tostring(e.Rarity or e.Tier or "")
    local r=RARITY[rarity] or tonumber(e.Rarity) or 0
    return r*1000000+(price or 0)
end
local function gearStockFolder()
    local sv=ReplicatedStorage:FindFirstChild("StockValues")
    local sh=sv and sv:FindFirstChild("GearShop")
    return sh and sh:FindFirstChild("Items")
end

local warnedGear=false
local function gearSniper()
    if not CFG.AutoGear or locked() then return end
    if not GearData then
        if not warnedGear then print("[GAG2 V3.1 ECON] Gear price data not found; safe mode skips gear buying") warnedGear=true end
        return
    end
    local folder=gearStockFolder(); if not folder then return end
    local cash=money(); if cash<CFG.GearMinCash then return end
    local reserve=reserveFor(cash)
    local best,bestPrice,bestScore
    for _,stock in ipairs(folder:GetChildren()) do
        if (tonumber(stock.Value) or 0)>0 then
            local e=gearEntry(stock.Name); local p=gearPrice(e)
            if p and p>0 and p<=cash*(CFG.GearMaxSpendPercent/100) and cash-p>=reserve then
                local s=gearScore(e,p)
                if not bestScore or s>bestScore then best,bestPrice,bestScore=stock.Name,p,s end
            end
        end
    end
    if best then
        local before=money()
        fire(Net.GearShop and Net.GearShop.PurchaseGear,best)
        task.wait(0.3)
        if money()<before then print("[GAG2 V3.1 ECON] Gear sniper bought",best,"for about",before-money()) end
    end
end

--================ AUTO OPEN WITH RARE PROTECTION ===================
local PROTECTED={"mega","gold","rainbow","divine","prismatic","mythic"}
local function protectedName(name)
    local s=string.lower(tostring(name or ""))
    for _,k in ipairs(PROTECTED) do if s:find(k,1,true) then return true end end
    return false
end
local function openBag(invKey,packet,enabled,protect)
    if not enabled or locked() then return end
    local d=getData(); local bag=d and d.Inventory and d.Inventory[invKey]; if type(bag)~="table" then return end
    local opened=0
    for name,count in pairs(bag) do
        if opened>=CFG.MaxOpenPerCycle then break end
        local n=(type(count)=="number") and count or 1
        if not (protect and protectedName(name)) then
            for _=1,math.min(n,CFG.MaxOpenPerCycle-opened) do
                fire(packet,name); opened+=1; task.wait(0.15)
            end
        end
    end
    if opened>0 then print("[GAG2 V3.1 ECON] Opened",opened,invKey) end
end
local function autoOpen()
    openBag("Eggs",Net.Egg and Net.Egg.OpenEgg,CFG.AutoOpenEggs,false)
    openBag("Crates",Net.Crate and Net.Crate.OpenCrate,CFG.AutoOpenCrates,true)
    openBag("SeedPacks",Net.SeedPack and Net.SeedPack.OpenSeedPack,CFG.AutoOpenSeedPacks,true)
end

--================ GOOD WILD PET HUNTER =============================
local GOOD_PETS={
    Raccoon=true,Dragonfly=true,["Dragon Fly"]=true,Dragonling=true,Mimic=true,
    ["Disco Bee"]=true,["Queen Bee"]=true,Kitsune=true,["Red Fox"]=true,Fox=true,
    Owl=true,["Night Owl"]=true,Bear=true,["Polar Bear"]=true,Butterfly=true,
    ["Golden Lab"]=true,Cat=true,["Red Giant Ant"]=true,Snail=true,
}
local function hrp()
    local c=LP.Character; return c and c:FindFirstChild("HumanoidRootPart")
end
local function setCollide(on)
    local c=LP.Character; if not c then return end
    for _,p in ipairs(c:GetDescendants()) do if p:IsA("BasePart") then pcall(function() p.CanCollide=on end) end end
end
local function reach(pos)
    local r=hrp(); if not r or not pos then return end
    local target=pos+Vector3.new(0,3,0); setCollide(false)
    for _=1,60 do
        r=hrp(); if not r then break end
        local d=target-r.Position
        if d.Magnitude<=70 then r.CFrame=CFrame.new(target); break end
        r.CFrame=CFrame.new(r.Position+d.Unit*70); RunService.Heartbeat:Wait()
    end
    setCollide(true)
end
local function homePos()
    local p=myPlot(); if not p then return nil end
    local sp=p:FindFirstChild("SpawnPoint"); if sp and sp:IsA("BasePart") then return sp.Position end
    local ref=p:FindFirstChild("PlotSizeReference"); if ref and ref:IsA("BasePart") then return ref.Position end
end
local function tameGoodPet()
    if not CFG.AutoTameGoodPets or locked() then return end
    local map=Workspace:FindFirstChild("Map"); local refs=map and map:FindFirstChild("WildPetRef"); if not refs then return end
    for _,pet in ipairs(refs:GetChildren()) do
        local species=pet:GetAttribute("PetName")
        local owner=tonumber(pet:GetAttribute("OwnerUserId")) or 0
        if species and GOOD_PETS[species] and (owner==0 or owner==LP.UserId) and pet:IsA("BasePart") then
            ENV.GAG2_V31_ACTIVITY_LOCK="pet"
            local ok,err=pcall(function()
                notify("Good wild pet: "..species.." - taming")
                reach(pet.Position)
                for _=1,CFG.PetAttempts do
                    if not pet.Parent then break end
                    fire(Net.Pets and Net.Pets.WildPetTame,pet)
                    task.wait(0.09)
                end
                local home=homePos(); if home then reach(home) end
            end)
            ENV.GAG2_V31_ACTIVITY_LOCK=nil
            if not ok then warn("[GAG2 V3.1 ECON] Pet hunter error:",err) end
            break
        end
    end
end

notify("Smart Economy loaded: seeds + upgrades + gear + items + pets")

local tSeed,tExpand,tGear,tOpen,tPet=0,0,0,0,0
task.spawn(function()
    while running do
        local now=os.clock()
        if not locked() then
            if now-tSeed>=CFG.SeedCheckEvery then tSeed=now; pcall(smartBuy) end
            if now-tExpand>=CFG.ExpandCheckEvery then tExpand=now; pcall(tryExpand) end
            if now-tGear>=CFG.GearCheckEvery then tGear=now; pcall(gearSniper) end
            if now-tOpen>=CFG.OpenCheckEvery then tOpen=now; pcall(autoOpen) end
            if now-tPet>=CFG.PetCheckEvery then tPet=now; pcall(tameGoodPet) end
        end
        task.wait(0.5)
    end
end)
