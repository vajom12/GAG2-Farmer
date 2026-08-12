-- GAG2 FARMER V3 LOADER
-- Core V2 + Event Hunter V3

local BASE = "https://raw.githubusercontent.com/vajom12/GAG2-Farmer/main/"

local function run(path)
    local url = BASE .. path .. "?cb=" .. tostring(math.floor(os.clock() * 1000))
    local ok, err = pcall(function()
        loadstring(game:HttpGet(url))()
    end)
    if not ok then
        warn("[GAG2 V3 LOADER] Failed:", path, err)
    end
end

run("core_v2.lua")
task.wait(0.5)
run("event.lua")
