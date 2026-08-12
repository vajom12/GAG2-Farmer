--========================================================
-- GAG2 FARMER V3.2 BRAIN
-- One scheduler, one action at a time, priority + verification.
--========================================================

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")

local LP = Players.LocalPlayer
local ENV = (getgenv and getgenv()) or _G
repeat task.wait() until game:IsLoaded() and LP

if ENV.GAG2_BRAIN_V32_STOP then
    pcall(ENV.GAG2_BRAIN_V32_STOP)
end

local Brain = {
    Version = "3.2",
    Running = true,
    Tasks = {},
    TaskMap = {},
    Current = nil,
    Actions = {},
    State = {
        NightSecured = false,
        LastNight = false,
        LastAction = "boot",
        LastActionAt = os.clock(),
        ActionCount = 0,
        Errors = 0,
    },
    Config = {
        SchedulerTick = 0.08,
        MoveHop = 70,
        MoveHeight = 3,
        MoveMaxHops = 80,
        ArrivalTolerance = 14,
        -- During stealing night we do not leave a non-empty garden.
        AllowRareEventAtNightIfRiskLE = 0,
        Verbose = true,
    },
    SeedBaseValue = {},
    SeedScore = {},
}

ENV.GAG2_V32_BRAIN = Brain
ENV.GAG2_BRAIN_V32_STOP = function()
    Brain.Running = false
end

local Net = require(
    ReplicatedStorage:WaitForChild("SharedModules"):WaitForChild("Networking")
)

local PSC
pcall(function()
    PSC = require(
        ReplicatedStorage:WaitForChild("ClientModules"):WaitForChild("PlayerStateClient")
    )
end)

Brain.Net = Net
Brain.PSC = PSC
Brain.LP = LP
Brain.Services = {
    Players = Players,
    ReplicatedStorage = ReplicatedStorage,
    Workspace = Workspace,
    RunService = RunService,
    StarterGui = StarterGui,
}

function Brain:Log(...)
    print("[GAG2 V3.2]", ...)
end

function Brain:Notify(text, title)
    self:Log(text)
    pcall(function()
        StarterGui:SetCore("SendNotification", {
            Title = title or "GAG2 V3.2",
            Text = tostring(text),
            Duration = 4,
        })
    end)
end

function Brain:Fire(packet, ...)
    if not packet then
        return false
    end
    local args = {...}
    local ok, err = pcall(function()
        packet:Fire(table.unpack(args))
    end)
    if not ok then
        self.State.Errors += 1
        warn("[GAG2 V3.2] remote error:", err)
    end
    return ok
end

function Brain:GetReplica()
    if not PSC then return nil end
    local ok, replica = pcall(function()
        return PSC:GetLocalReplica()
    end)
    return ok and replica or nil
end

function Brain:GetData()
    local r = self:GetReplica()
    return r and r.Data or nil
end

function Brain:Money()
    local d = self:GetData()
    return d and tonumber(d.Sheckles) or 0
end

function Brain:FruitCount()
    return tonumber(LP:GetAttribute("FruitCount")) or 0
end

function Brain:FruitCapacity()
    return tonumber(LP:GetAttribute("MaxFruitCapacity")) or 100
end

function Brain:Character()
    return LP.Character
end

function Brain:Root()
    local c = self:Character()
    return c and c:FindFirstChild("HumanoidRootPart")
end

function Brain:Humanoid()
    local c = self:Character()
    return c and c:FindFirstChildOfClass("Humanoid")
end

function Brain:MyPlot()
    local gardens = Workspace:FindFirstChild("Gardens")
    if not gardens then return nil end

    local pid = LP:GetAttribute("PlotId")
    if pid ~= nil then
        local p = gardens:FindFirstChild("Plot" .. tostring(pid))
        if p then return p end
    end

    for _, p in ipairs(gardens:GetChildren()) do
        if p:GetAttribute("OwnerUserId") == LP.UserId
            or p:GetAttribute("Owner") == LP.Name
        then
            return p
        end
    end
end

function Brain:HomePosition()
    local p = self:MyPlot()
    if not p then return nil end

    local sp = p:FindFirstChild("SpawnPoint")
    if sp and sp:IsA("BasePart") then
        return sp.Position
    end

    local ref = p:FindFirstChild("PlotSizeReference")
    if ref and ref:IsA("BasePart") then
        return ref.Position
    end

    local ok, cf = pcall(function() return p:GetPivot() end)
    return ok and cf.Position or nil
end

function Brain:IsInOwnGarden()
    if LP:GetAttribute("IsInOwnGarden") == true then
        return true
    end

    local root = self:Root()
    local plot = self:MyPlot()
    local ref = plot and plot:FindFirstChild("PlotSizeReference")
    if not (root and ref and ref:IsA("BasePart")) then
        return false
    end

    local localPos = ref.CFrame:PointToObjectSpace(root.Position)
    return math.abs(localPos.X) <= ref.Size.X / 2 + 6
        and math.abs(localPos.Z) <= ref.Size.Z / 2 + 6
end

function Brain:IsNight()
    local n = ReplicatedStorage:FindFirstChild("Night")
    if n and n:IsA("BoolValue") then
        return n.Value == true
    end

    local phase = tostring(Workspace:GetAttribute("ActivePhase") or ""):lower()
    local weather = tostring(Workspace:GetAttribute("ActiveWeather") or ""):lower()
    return phase:find("night", 1, true) ~= nil
        or weather:find("moon", 1, true) ~= nil
end

function Brain:GardenRiskValue()
    local plot = self:MyPlot()
    local plants = plot and plot:FindFirstChild("Plants")
    if not plants then return 0 end

    local total = 0
    for _, plant in ipairs(plants:GetChildren()) do
        local seed = plant:GetAttribute("SeedName") or plant:GetAttribute("CorePartName")
        local base = tonumber(self.SeedBaseValue[seed]) or 1
        local fruits = plant:FindFirstChild("Fruits")
        local n = fruits and math.max(1, #fruits:GetChildren()) or 1
        total += math.max(1, base) * n
    end
    return total
end

function Brain:CanLeaveGarden(reason)
    if not self:IsNight() then
        return true
    end

    if reason == "rare_event" then
        return self:GardenRiskValue() <= self.Config.AllowRareEventAtNightIfRiskLE
    end

    return false
end

function Brain:SetCollide(on)
    local c = self:Character()
    if not c then return end
    for _, p in ipairs(c:GetDescendants()) do
        if p:IsA("BasePart") then
            pcall(function() p.CanCollide = on end)
        end
    end
end

function Brain:HigherPriorityReady(priority, ignoreName)
    local now = os.clock()
    for _, t in ipairs(self.Tasks) do
        if t.name ~= ignoreName
            and t.priority > priority
            and now >= (t.nextAt or 0)
        then
            local ok, ready = pcall(t.canRun)
            if ok and ready then
                return true, t.name
            end
        end
    end
    return false
end

function Brain:ShouldAbort(priority, taskName)
    if not self.Running then return true end
    local higher = self:HigherPriorityReady(priority or 0, taskName)
    return higher == true
end

function Brain:WaitUntil(fn, timeout, interval, priority, taskName)
    local start = os.clock()
    interval = interval or 0.08
    while os.clock() - start < (timeout or 2) do
        if self:ShouldAbort(priority or 0, taskName) then
            return false, "preempted"
        end
        local ok, result = pcall(fn)
        if ok and result then
            return true, "confirmed"
        end
        task.wait(interval)
    end
    return false, "timeout"
end

function Brain:Reach(pos, priority, taskName, height)
    local root = self:Root()
    if not root or not pos then return false, "no-root" end

    local target = pos + Vector3.new(0, height or self.Config.MoveHeight, 0)
    self:SetCollide(false)

    local success = false
    local reason = "max-hops"

    for _ = 1, self.Config.MoveMaxHops do
        if self:ShouldAbort(priority or 0, taskName) then
            reason = "preempted"
            break
        end

        root = self:Root()
        if not root then
            reason = "lost-root"
            break
        end

        local delta = target - root.Position
        if delta.Magnitude <= self.Config.MoveHop then
            root.CFrame = CFrame.new(target)
            RunService.Heartbeat:Wait()
            success = true
            reason = "arrived"
            break
        end

        root.CFrame = CFrame.new(root.Position + delta.Unit * self.Config.MoveHop)
        RunService.Heartbeat:Wait()
    end

    self:SetCollide(true)

    root = self:Root()
    if root and (root.Position - target).Magnitude <= self.Config.ArrivalTolerance then
        success = true
    end

    return success, reason
end

function Brain:ReturnHome(priority, taskName)
    local home = self:HomePosition()
    if home then
        local ok = self:Reach(home, priority or 9999, taskName or "return-home", 4)
        if ok then
            task.wait(0.12)
            return self:IsInOwnGarden()
        end
    end

    pcall(function()
        self:Fire(Net.TeleportButton and Net.TeleportButton.Request, "Garden")
    end)
    task.wait(0.7)
    return self:IsInOwnGarden()
end

function Brain:RegisterTask(spec)
    assert(type(spec) == "table", "task spec required")
    assert(type(spec.name) == "string", "task name required")
    assert(type(spec.canRun) == "function", "canRun required")
    assert(type(spec.run) == "function", "run required")

    local old = self.TaskMap[spec.name]
    if old then
        for i, t in ipairs(self.Tasks) do
            if t == old then table.remove(self.Tasks, i) break end
        end
    end

    local t = {
        name = spec.name,
        priority = tonumber(spec.priority) or 0,
        interval = tonumber(spec.interval) or 1,
        canRun = spec.canRun,
        run = spec.run,
        nextAt = os.clock() + (tonumber(spec.initialDelay) or 0),
        runs = 0,
        errors = 0,
    }

    self.TaskMap[t.name] = t
    table.insert(self.Tasks, t)
    self:Log("registered", t.name, "priority", t.priority)
    return t
end

local function chooseTask()
    local now = os.clock()
    local best

    for _, t in ipairs(Brain.Tasks) do
        if now >= (t.nextAt or 0) then
            local ok, ready = pcall(t.canRun)
            if not ok then
                t.errors += 1
                t.nextAt = now + math.max(1, t.interval)
                warn("[GAG2 V3.2] canRun error", t.name, ready)
            elseif ready then
                if not best
                    or t.priority > best.priority
                    or (t.priority == best.priority and (t.nextAt or 0) < (best.nextAt or 0))
                then
                    best = t
                end
            end
        end
    end

    return best
end

local function updateNightState()
    local n = Brain:IsNight()
    if not n and Brain.State.LastNight then
        Brain.State.NightSecured = false
        Brain:Log("day detected - night lock released")
    end
    Brain.State.LastNight = n
end

Brain:Notify("Central scheduler loaded", "GAG2 V3.2 Brain")

task.spawn(function()
    while Brain.Running do
        updateNightState()

        if not Brain.Current then
            local t = chooseTask()
            if t then
                Brain.Current = t
                Brain.State.LastAction = t.name
                Brain.State.LastActionAt = os.clock()
                Brain.State.ActionCount += 1

                if Brain.Config.Verbose then
                    Brain:Log("START", t.name)
                end

                local ctx = {
                    name = t.name,
                    priority = t.priority,
                    brain = Brain,
                    shouldAbort = function()
                        return Brain:ShouldAbort(t.priority, t.name)
                    end,
                    waitUntil = function(fn, timeout, interval)
                        return Brain:WaitUntil(fn, timeout, interval, t.priority, t.name)
                    end,
                }

                local ok, result = pcall(t.run, ctx)
                if not ok then
                    t.errors += 1
                    Brain.State.Errors += 1
                    warn("[GAG2 V3.2] task error", t.name, result)
                end

                t.runs += 1
                t.nextAt = os.clock() + t.interval

                if Brain.Config.Verbose then
                    Brain:Log("END", t.name, ok and tostring(result or "ok") or "error")
                end

                Brain.Current = nil
            end
        end

        task.wait(Brain.Config.SchedulerTick)
    end
end)

return Brain
