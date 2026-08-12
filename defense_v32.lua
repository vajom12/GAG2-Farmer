--========================================================
-- GAG2 FARMER V3.2 DEFENSE
-- Highest-priority Night Guardian + own-plot intruder defense.
--========================================================

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local ENV = (getgenv and getgenv()) or _G
local Brain = ENV.GAG2_V32_BRAIN
if not Brain then
    warn("[GAG2 V3.2 DEFENSE] Brain missing")
    return
end

local LP = Brain.LP
local Net = Brain.Net

local CFG = {
    PanicHarvestOnNight = true,
    RetaliateOnOwnPlot = true,
    IntruderMargin = 5,
}

local function intrudersOnPlot()
    local out = {}
    local plot = Brain:MyPlot()
    local ref = plot and plot:FindFirstChild("PlotSizeReference")
    if not (ref and ref:IsA("BasePart")) then return out end

    for _, pl in ipairs(Players:GetPlayers()) do
        if pl ~= LP and pl.Character then
            local r = pl.Character:FindFirstChild("HumanoidRootPart")
            if r then
                local localPos = ref.CFrame:PointToObjectSpace(r.Position)
                if math.abs(localPos.X) <= ref.Size.X / 2 + CFG.IntruderMargin
                    and math.abs(localPos.Z) <= ref.Size.Z / 2 + CFG.IntruderMargin
                then
                    table.insert(out, pl)
                end
            end
        end
    end

    return out
end

Brain:RegisterTask({
    name = "NightSecure",
    priority = 1000,
    interval = 0.18,
    canRun = function()
        return Brain:IsNight()
            and (not Brain.State.NightSecured or not Brain:IsInOwnGarden())
    end,
    run = function(ctx)
        Brain:Log("NIGHT GUARD: securing garden")

        local home = Brain:ReturnHome(ctx.priority, ctx.name)
        if not home then
            warn("[GAG2 V3.2 DEFENSE] Could not confirm return to own garden")
            return "home-unconfirmed"
        end

        if CFG.PanicHarvestOnNight and Brain.Actions.HarvestAll then
            local n, state = Brain.Actions.HarvestAll(ctx, true)
            Brain:Log("panic harvest", n or 0, state or "")
        end

        Brain.State.NightSecured = Brain:IsInOwnGarden()
        if Brain.State.NightSecured then
            Brain:Notify("Night secured - staying in garden", "GAG2 Night Guardian")
            return "secured"
        end

        return "not-secured"
    end,
})

Brain:RegisterTask({
    name = "IntruderDefense",
    priority = 980,
    interval = 1.0,
    initialDelay = 1.0,
    canRun = function()
        return CFG.RetaliateOnOwnPlot
            and Brain:IsNight()
            and Brain:IsInOwnGarden()
            and #intrudersOnPlot() > 0
    end,
    run = function(ctx)
        local intruders = intrudersOnPlot()
        if #intruders == 0 then return "clear" end

        local hit = 0
        for _, pl in ipairs(intruders) do
            if ctx.shouldAbort() then return "preempted" end
            if Net.Shovel and Net.Shovel.HitPlayer then
                if Brain:Fire(Net.Shovel.HitPlayer, pl.UserId) then
                    hit += 1
                end
                task.wait(0.08)
            end
        end

        if hit > 0 then
            Brain:Log("defense hit", hit, "intruder(s) on own plot")
        end
        return "defended:" .. hit
    end,
})

Brain:Notify("Night Guardian registered", "GAG2 V3.2 Defense")
