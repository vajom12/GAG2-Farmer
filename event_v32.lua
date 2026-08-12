--========================================================
-- GAG2 FARMER V3.2 EVENT HUNTER
-- Scheduler tasks only. Rare events preempt pets; Night Guardian preempts all.
--========================================================

local Workspace = game:GetService("Workspace")

local ENV = (getgenv and getgenv()) or _G
local Brain = ENV.GAG2_V32_BRAIN
if not Brain then
    warn("[GAG2 V3.2 EVENT] Brain missing")
    return
end

local CFG = {
    Enabled = true,
    GrabNormalPacks = true,
    MaxAttempts = 8,
    RetryCooldown = 25,
    PromptRadius = 28,
    ArrivalSettle = 0.14,
}

local handled = setmetatable({}, {__mode = "k"})
local cachedRare
local cachedPack

local function lower(v)
    return tostring(v or ""):lower()
end

local function kindOf(obj)
    if obj:GetAttribute("MegaSeed") == true then return "Mega" end
    if obj:GetAttribute("RainbowSeed") == true then return "Rainbow" end
    if obj:GetAttribute("GoldSeed") == true then return "Gold" end

    local text = table.concat({
        lower(obj.Name),
        lower(obj:GetAttribute("SeedPack")),
        lower(obj:GetAttribute("PackName")),
        lower(obj:GetAttribute("SeedName")),
        lower(obj:GetAttribute("Type")),
    }, " ")

    if text:find("mega", 1, true) then return "Mega" end
    if text:find("rainbow", 1, true) then return "Rainbow" end
    if text:find("gold", 1, true) then return "Gold" end
    if text:find("seed", 1, true) or text:find("pack", 1, true) then return "Pack" end
    return "Unknown"
end

local PRIORITY = {Mega=400, Rainbow=300, Gold=200, Pack=100, Unknown=0}

local function containers()
    local out = {}
    local map = Workspace:FindFirstChild("Map")

    for _, f in ipairs({
        map and map:FindFirstChild("SeedPackSpawnServerLocations"),
        map and map:FindFirstChild("SeedPackSpawnClient"),
        Workspace:FindFirstChild("Temporary"),
    }) do
        if f then table.insert(out, f) end
    end

    return out
end

local function objectPosition(obj)
    if not obj then return nil end
    if obj:IsA("BasePart") then return obj.Position end

    if obj:IsA("Model") then
        local ok, cf = pcall(function() return obj:GetPivot() end)
        if ok then return cf.Position end
    end

    local p = obj:FindFirstChildWhichIsA("BasePart", true)
    return p and p.Position or nil
end

local function scan()
    local out = {}
    local seen = {}

    for _, folder in ipairs(containers()) do
        for _, obj in ipairs(folder:GetChildren()) do
            if not seen[obj] and obj.Parent then
                seen[obj] = true

                local kind = kindOf(obj)
                local pos = objectPosition(obj)
                local prompt = obj:FindFirstChildWhichIsA("ProximityPrompt", true)
                local marked = obj:GetAttribute("SeedPack") ~= nil
                    or obj:GetAttribute("GoldSeed") == true
                    or obj:GetAttribute("RainbowSeed") == true
                    or obj:GetAttribute("MegaSeed") == true

                if pos and (prompt or marked or kind ~= "Unknown") then
                    local last = handled[obj] or 0
                    if os.clock() - last >= CFG.RetryCooldown then
                        table.insert(out, {
                            obj = obj,
                            kind = kind,
                            pos = pos,
                            priority = PRIORITY[kind] or 0,
                        })
                    end
                end
            end
        end
    end

    local root = Brain:Root()
    table.sort(out, function(a, b)
        if a.priority ~= b.priority then return a.priority > b.priority end
        if root then
            return (root.Position - a.pos).Magnitude < (root.Position - b.pos).Magnitude
        end
        return false
    end)

    return out
end

local function findRare()
    cachedRare = nil
    if not CFG.Enabled then return nil end
    if not Brain:CanLeaveGarden("rare_event") then return nil end

    for _, t in ipairs(scan()) do
        if t.kind == "Mega" or t.kind == "Rainbow" or t.kind == "Gold" then
            cachedRare = t
            return t
        end
    end
end

local function findPack()
    cachedPack = nil
    if not CFG.Enabled or not CFG.GrabNormalPacks then return nil end
    if not Brain:CanLeaveGarden("pack") then return nil end

    for _, t in ipairs(scan()) do
        if t.kind == "Pack" then
            cachedPack = t
            return t
        end
    end
end

local function triggerPrompt(p)
    if not p or not p.Parent then return end

    if fireproximityprompt then
        pcall(function()
            local hold = tonumber(p.HoldDuration) or 0
            if hold > 0 then fireproximityprompt(p, hold) else fireproximityprompt(p) end
        end)
    else
        pcall(function()
            p:InputHoldBegin()
            task.wait(math.max(tonumber(p.HoldDuration) or 0, 0.05) + 0.08)
            p:InputHoldEnd()
        end)
    end
end

local function triggerNearby(pos)
    for _, folder in ipairs(containers()) do
        for _, d in ipairs(folder:GetDescendants()) do
            if d:IsA("ProximityPrompt") then
                local pp
                pcall(function()
                    if d.Parent:IsA("BasePart") then
                        pp = d.Parent.Position
                    elseif d.Parent:IsA("Model") then
                        pp = d.Parent:GetPivot().Position
                    end
                end)

                if pp and (pp - pos).Magnitude <= CFG.PromptRadius then
                    triggerPrompt(d)
                end
            end
        end
    end
end

local function touch(obj)
    if not firetouchinterest then return end
    local root = Brain:Root()
    if not root then return end

    local p = obj:IsA("BasePart") and obj or obj:FindFirstChildWhichIsA("BasePart", true)
    if p then
        pcall(function()
            firetouchinterest(root, p, 0)
            task.wait(0.04)
            firetouchinterest(root, p, 1)
        end)
    end
end

local function collectTarget(ctx, target)
    if not target or not target.obj or not target.obj.Parent then return "gone" end

    local obj = target.obj
    local originalParent = obj.Parent
    handled[obj] = os.clock()

    Brain:Notify(
        target.kind .. " spawn detected - collecting",
        "GAG2 V3.2 Event"
    )

    local pos = objectPosition(obj) or target.pos
    local moved, reason = Brain:Reach(pos, ctx.priority, ctx.name, 3)
    if not moved then
        Brain:ReturnHome(ctx.priority, ctx.name)
        return "move-failed:" .. tostring(reason)
    end

    task.wait(CFG.ArrivalSettle)

    local success = false
    for _ = 1, CFG.MaxAttempts do
        if ctx.shouldAbort() then break end
        if not obj.Parent or obj.Parent ~= originalParent then
            success = true
            break
        end

        pos = objectPosition(obj) or pos
        if pos then
            local root = Brain:Root()
            if root and (root.Position - pos).Magnitude > 8 then
                Brain:Reach(pos, ctx.priority, ctx.name, 3)
            end

            for _, d in ipairs(obj:GetDescendants()) do
                if d:IsA("ProximityPrompt") then triggerPrompt(d) end
            end

            triggerNearby(pos)
            touch(obj)
        end

        local confirmed = ctx.waitUntil(function()
            return not obj.Parent or obj.Parent ~= originalParent
        end, 0.45, 0.06)

        if confirmed then
            success = true
            break
        end
    end

    Brain:ReturnHome(ctx.priority, ctx.name)

    if success then
        Brain:Log("event collected", target.kind)
        return "collected:" .. target.kind
    end

    Brain:Log("event collection unconfirmed", target.kind)
    return ctx.shouldAbort() and "preempted" or "unconfirmed"
end

Brain:RegisterTask({
    name = "RareEvent",
    priority = 850,
    interval = 0.25,
    initialDelay = 2,
    canRun = function()
        return findRare() ~= nil
    end,
    run = function(ctx)
        local t = cachedRare or findRare()
        cachedRare = nil
        return collectTarget(ctx, t)
    end,
})

Brain:RegisterTask({
    name = "NormalSeedPack",
    priority = 500,
    interval = 0.7,
    initialDelay = 3,
    canRun = function()
        return findPack() ~= nil
    end,
    run = function(ctx)
        local t = cachedPack or findPack()
        cachedPack = nil
        return collectTarget(ctx, t)
    end,
})

Brain:Notify("Mega > Rainbow > Gold > Packs registered", "GAG2 V3.2 Event")
