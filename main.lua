-- GAG2 FARMER V3.3.1 LOADER
-- Safe Punk-style baseline: harvest -> sell -> buy -> plant.
-- Extras remain OFF until the core cycle is proven live.

local ENV = (getgenv and getgenv()) or _G
for _, key in ipairs({
    "GAG2_V331_STOP",
    "GAG2_V33_STOP",
    "GAG2_BRAIN_V32_STOP",
    "GAG2_CORE_V31_STOP",
    "GAG2_ECON_V31_STOP",
    "GAG2_EVENT_V31_STOP",
    "GAG2_V2_STOP",
    "GAG2_EVENT_V3_STOP"
}) do
    local fn = ENV[key]
    if type(fn) == "function" then pcall(fn) end
end

ENV.GAG2_V32_BRAIN = nil
ENV.GAG2_V31_ACTIVITY_LOCK = nil

task.wait(0.15)

local url = "https://raw.githubusercontent.com/vajom12/GAG2-Farmer/main/v331_punkbase.lua?cb=" .. tostring(math.floor(os.clock()*100000))
local ok, err = pcall(function()
    local src = game:HttpGet(url)
    local fn = loadstring(src)
    if not fn then error("loadstring failed") end
    fn()
end)

if not ok then
    warn("[GAG2 V3.3.1 LOADER] failed", err)
else
    print("============================================")
    print(" GAG2 FARMER V3.3.1 - SAFE PUNK BASE ACTIVE")
    print(" harvest(actual Fruits only) > sell > buy > plant")
    print(" gear/crates/expand/events/pets/sprinklers OFF for baseline test")
    print("============================================")
end
