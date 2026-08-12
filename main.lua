-- GAG2 FARMER V3.3 LOADER
-- Single-core Punk-style progression + coordinated travel fixes.

local ENV = (getgenv and getgenv()) or _G
for _, key in ipairs({
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

local url = "https://raw.githubusercontent.com/vajom12/GAG2-Farmer/main/v33_punkcore.lua?cb=" .. tostring(math.floor(os.clock()*100000))
local ok, err = pcall(function()
    local src = game:HttpGet(url)
    local fn = loadstring(src)
    if not fn then error("loadstring failed") end
    fn()
end)

if not ok then
    warn("[GAG2 V3.3 LOADER] failed", err)
else
    print("============================================")
    print(" GAG2 FARMER V3.3 - PUNK-STYLE CORE ACTIVE")
    print(" harvest > sell > buy > plant")
    print(" travel lock only for event / pet / sprinkler")
    print("============================================")
end
