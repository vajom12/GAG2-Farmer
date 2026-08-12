-- GAG2 FARMER V3.1 LOADER
-- Core + Smart Economy + Event Hunter

local BASE = "https://raw.githubusercontent.com/vajom12/GAG2-Farmer/main/"

local function run(path)
    local url = BASE .. path .. "?cb=" .. tostring(math.floor(os.clock() * 1000))
    local ok, err = pcall(function()
        loadstring(game:HttpGet(url))()
    end)
    if not ok then
        warn("[GAG2 V3.1 LOADER] Failed:", path, err)
    end
    return ok
end

-- Stop old modules if this loader is executed again.
local ENV = (getgenv and getgenv()) or _G
if ENV.GAG2_CORE_V31_STOP then pcall(ENV.GAG2_CORE_V31_STOP) end
if ENV.GAG2_ECON_V31_STOP then pcall(ENV.GAG2_ECON_V31_STOP) end
if ENV.GAG2_EVENT_V31_STOP then pcall(ENV.GAG2_EVENT_V31_STOP) end
if ENV.GAG2_V2_STOP then pcall(ENV.GAG2_V2_STOP) end
if ENV.GAG2_EVENT_V3_STOP then pcall(ENV.GAG2_EVENT_V3_STOP) end
ENV.GAG2_V31_ACTIVITY_LOCK = nil

task.wait(0.15)
run("core_v31.lua")
task.wait(0.35)
run("economy_v31.lua")
task.wait(0.35)
run("event_v31.lua")
