--========================================================
-- GAG2 FARMER V3.2 TRANSACTION POLICY
-- Routine tasks cannot interrupt a transaction already in progress.
-- Safety / rare-event preemption remains possible where appropriate.
--========================================================

local ENV = (getgenv and getgenv()) or _G
local Brain = ENV.GAG2_V32_BRAIN
if not Brain then
    warn("[GAG2 V3.2 TX] Brain missing")
    return
end

-- Minimum priority that is allowed to interrupt each running transaction.
-- NightSecure=1000, IntruderDefense=980, RareEvent=850.
local PREEMPT_FLOOR = {
    WildPetTame = 800,       -- RareEvent / Night may interrupt; harvest/sell may not.
    SprinklerDeploy = 950,   -- Finish placement unless safety defense takes over.
    RareEvent = 950,         -- Only safety defense may interrupt a rare event.
    NormalSeedPack = 800,    -- Rare event / safety may interrupt ordinary pack collection.
}

Brain.TransactionPreemptFloor = PREEMPT_FLOOR

local originalShouldAbort = Brain.ShouldAbort

function Brain:ShouldAbort(priority, taskName)
    if not self.Running then return true end

    local floor = PREEMPT_FLOOR[taskName]
    if not floor then
        return originalShouldAbort(self, priority, taskName)
    end

    local now = os.clock()
    for _, t in ipairs(self.Tasks) do
        if t.name ~= taskName
            and t.priority >= floor
            and now >= (t.nextAt or 0)
        then
            local ok, ready = pcall(t.canRun)
            if ok and ready then
                self:Log(
                    "transaction preempt",
                    taskName,
                    "by",
                    t.name,
                    "priority",
                    t.priority
                )
                return true
            end
        end
    end

    return false
end

Brain:Notify("Hard transaction locks enabled", "GAG2 V3.2 Transactions")
