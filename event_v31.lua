--========================================================
-- GAG2 FARMER V3.1 EVENT HUNTER
-- Priority: Mega > Rainbow > Gold > normal seed packs
-- Uses shared activity lock; no core restart needed.
--========================================================

local CFG={Enabled=true,RareOnly=false,CheckEvery=0.45,ReturnHome=true,Notify=true,MaxAttempts=5,RetryAfter=30,ReachHeight=3}
local Players=game:GetService("Players")
local Workspace=game:GetService("Workspace")
local StarterGui=game:GetService("StarterGui")
local RunService=game:GetService("RunService")
local LP=Players.LocalPlayer
local ENV=(getgenv and getgenv()) or _G

if ENV.GAG2_EVENT_V31_STOP then pcall(ENV.GAG2_EVENT_V31_STOP) end
if ENV.GAG2_EVENT_V3_STOP then pcall(ENV.GAG2_EVENT_V3_STOP) end
local running=true
ENV.GAG2_EVENT_V31_STOP=function() running=false end

local function notify(text)
    print("[GAG2 V3.1 EVENT]",text)
    if not CFG.Notify then return end
    pcall(function() StarterGui:SetCore("SendNotification",{Title="GAG2 V3.1 Event Hunter",Text=text,Duration=5}) end)
end
local function hrp()
    local c=LP.Character; return c and c:FindFirstChild("HumanoidRootPart")
end
local function setCollide(on)
    local c=LP.Character; if not c then return end
    for _,p in ipairs(c:GetDescendants()) do if p:IsA("BasePart") then pcall(function() p.CanCollide=on end) end end
end
local function reach(pos)
    local r=hrp(); if not r or not pos then return false end
    local target=pos+Vector3.new(0,CFG.ReachHeight,0); setCollide(false)
    for _=1,80 do
        if not running then break end
        r=hrp(); if not r then break end
        local d=target-r.Position
        if d.Magnitude<=70 then r.CFrame=CFrame.new(target); break end
        r.CFrame=CFrame.new(r.Position+d.Unit*70); RunService.Heartbeat:Wait()
    end
    setCollide(true); return true
end
local function myPlot()
    local g=Workspace:FindFirstChild("Gardens"); if not g then return nil end
    local pid=LP:GetAttribute("PlotId")
    if pid~=nil then local p=g:FindFirstChild("Plot"..tostring(pid)); if p then return p end end
    for _,p in ipairs(g:GetChildren()) do
        if p:GetAttribute("OwnerUserId")==LP.UserId or p:GetAttribute("Owner")==LP.Name then return p end
    end
end
local function homePosition()
    local p=myPlot(); if not p then return nil end
    local sp=p:FindFirstChild("SpawnPoint"); if sp and sp:IsA("BasePart") then return sp.Position end
    local ref=p:FindFirstChild("PlotSizeReference"); if ref and ref:IsA("BasePart") then return ref.Position end
    local ok,cf=pcall(function() return p:GetPivot() end); return ok and cf.Position or nil
end
local function lower(v) return string.lower(tostring(v or "")) end
local function kindOf(obj)
    if obj:GetAttribute("MegaSeed")==true then return "Mega" end
    if obj:GetAttribute("RainbowSeed")==true then return "Rainbow" end
    if obj:GetAttribute("GoldSeed")==true then return "Gold" end
    local text=table.concat({lower(obj.Name),lower(obj:GetAttribute("SeedPack")),lower(obj:GetAttribute("PackName")),lower(obj:GetAttribute("SeedName"))}," ")
    if text:find("mega",1,true) then return "Mega" end
    if text:find("rainbow",1,true) then return "Rainbow" end
    if text:find("gold",1,true) then return "Gold" end
    if text:find("seed",1,true) or text:find("pack",1,true) then return "Pack" end
    return "Unknown"
end
local PRIORITY={Mega=400,Rainbow=300,Gold=200,Pack=100,Unknown=0}
local function objectPosition(obj)
    if obj:IsA("BasePart") then return obj.Position end
    if obj:IsA("Model") then local ok,cf=pcall(function() return obj:GetPivot() end); if ok then return cf.Position end end
    local p=obj:FindFirstChildWhichIsA("BasePart",true); return p and p.Position or nil
end
local function containers()
    local out={}; local map=Workspace:FindFirstChild("Map")
    for _,f in ipairs({map and map:FindFirstChild("SeedPackSpawnServerLocations"),map and map:FindFirstChild("SeedPackSpawnClient"),Workspace:FindFirstChild("Temporary")}) do
        if f then table.insert(out,f) end
    end
    return out
end
local function candidates()
    local out,seen={},{}
    for _,folder in ipairs(containers()) do
        for _,obj in ipairs(folder:GetChildren()) do
            if not seen[obj] then
                seen[obj]=true
                local pos=objectPosition(obj); local kind=kindOf(obj)
                local prompt=obj:FindFirstChildWhichIsA("ProximityPrompt",true)
                local marked=obj:GetAttribute("SeedPack")~=nil or obj:GetAttribute("GoldSeed")==true or obj:GetAttribute("RainbowSeed")==true or obj:GetAttribute("MegaSeed")==true
                if pos and (prompt or marked or kind~="Unknown") and (not CFG.RareOnly or kind=="Mega" or kind=="Rainbow" or kind=="Gold") then
                    table.insert(out,{obj=obj,pos=pos,kind=kind,priority=PRIORITY[kind] or 0})
                end
            end
        end
    end
    local root=hrp()
    table.sort(out,function(a,b)
        if a.priority~=b.priority then return a.priority>b.priority end
        if root then return (root.Position-a.pos).Magnitude<(root.Position-b.pos).Magnitude end
        return false
    end)
    return out
end
local function triggerPrompt(p)
    if not p or not p.Parent then return end
    if fireproximityprompt then pcall(function() fireproximityprompt(p) end)
    else pcall(function() p:InputHoldBegin(); task.wait(math.max(tonumber(p.HoldDuration) or 0,0.05)+0.05); p:InputHoldEnd() end) end
end
local function triggerNearby(pos)
    for _,folder in ipairs(containers()) do
        for _,d in ipairs(folder:GetDescendants()) do
            if d:IsA("ProximityPrompt") then
                local pp
                pcall(function()
                    if d.Parent:IsA("BasePart") then pp=d.Parent.Position elseif d.Parent:IsA("Model") then pp=d.Parent:GetPivot().Position end
                end)
                if pp and (pp-pos).Magnitude<=14 then triggerPrompt(d) end
            end
        end
    end
end
local function touch(obj)
    if not firetouchinterest then return end
    local root=hrp(); if not root then return end
    local p=obj:IsA("BasePart") and obj or obj:FindFirstChildWhichIsA("BasePart",true)
    if p then pcall(function() firetouchinterest(root,p,0); task.wait(0.05); firetouchinterest(root,p,1) end) end
end
local busy=false
local function collect(t)
    if busy or ENV.GAG2_V31_ACTIVITY_LOCK or not t or not t.obj or not t.obj.Parent then return false end
    busy=true; ENV.GAG2_V31_ACTIVITY_LOCK="event"
    local success=false
    local ok,err=pcall(function()
        local obj=t.obj; local originalParent=obj.Parent
        notify(t.kind.." spawn detected - collecting")
        for _=1,CFG.MaxAttempts do
            if not running or not obj.Parent then break end
            local pos=objectPosition(obj) or t.pos
            if pos then
                reach(pos); task.wait(0.08)
                for _,d in ipairs(obj:GetDescendants()) do if d:IsA("ProximityPrompt") then triggerPrompt(d) end end
                triggerNearby(pos); touch(obj)
            end
            task.wait(0.18)
            if not obj.Parent or obj.Parent~=originalParent then break end
        end
        success=(not obj.Parent) or obj.Parent~=originalParent
        print("[GAG2 V3.1 EVENT]",success and "COLLECTED" or "ATTEMPTED",t.kind)
        if CFG.ReturnHome then local home=homePosition(); if home then reach(home) end end
    end)
    ENV.GAG2_V31_ACTIVITY_LOCK=nil; busy=false
    if not ok then warn("[GAG2 V3.1 EVENT] collect error:",err) end
    return success
end

notify("Event Hunter loaded: Mega > Rainbow > Gold > Packs")
local handled={}
task.spawn(function()
    while running do
        if CFG.Enabled and not busy and not ENV.GAG2_V31_ACTIVITY_LOCK then
            for _,t in ipairs(candidates()) do
                local last=handled[t.obj]
                if t.obj.Parent and (not last or os.clock()-last>=CFG.RetryAfter) then
                    handled[t.obj]=os.clock(); pcall(function() collect(t) end); break
                end
            end
            for obj,ts in pairs(handled) do if not obj.Parent or os.clock()-ts>180 then handled[obj]=nil end end
        end
        task.wait(CFG.CheckEvery)
    end
end)
