--========================================================
-- GAG2 FARMER V3.2 LOADER
-- One Brain scheduler -> Core -> Defense -> Economy -> Sprinklers -> Events
--========================================================

local BASE = "https://raw.githubusercontent.com/vajom12/GAG2-Farmer/main/"
local ENV = (getgenv and getgenv()) or _G

-- Stop every older generation before V3.2 starts.
for _, stopName in ipairs({
    "GAG2_BRAIN_V32_STOP",
    "GAG2_CORE_V31_STOP",
    "GAG2_ECON_V31_STOP",
    "GAG2_EVENT_V31_STOP",
    "GAG2_V2_STOP",
    "GAG2_EVENT_V3_STOP",
}) do
    local fn = ENV[stopName]
    if type(fn) == "function" then
        pcall(fn)
    end
end

ENV.GAG2_V31_ACTIVITY_LOCK = nil
ENV.GAG2_V32_BRAIN = nil

task.wait(0.18)

local function run(path)
    local url = BASE .. path .. "?cb=" .. tostring(math.floor(os.clock() * 100000))
    local ok, err = pcall(function()
        local source = game:HttpGet(url)
        local fn = loadstring(source)
        if not fn then error("loadstring failed for " .. path) end
        fn()
    end)

    if not ok then
        warn("[GAG2 V3.2 LOADER] Failed:", path, err)
    else
        print("[GAG2 V3.2 LOADER] Loaded", path)
    end

    return ok
end

if not run("brain_v32.lua") then
    warn("[GAG2 V3.2 LOADER] Brain failed; stopping loader")
    return
end

task.wait(0.30)
run("core_v32.lua")
task.wait(0.20)
run("defense_v32.lua")
task.wait(0.20)
run("economy_v32.lua")
task.wait(0.20)
run("sprinkler_v32.lua")
task.wait(0.20)
run("event_v32.lua")

print("============================================")
print(" GAG2 FARMER V3.2 - CENTRAL BRAIN ACTIVE")
print(" One action at a time; higher priority can preempt")
print(" Night > Intruder > Rare Event > Harvest > Sell > Pet > Sprinkler > Pack > Plant > Buy > Expand")
print("============================================")
