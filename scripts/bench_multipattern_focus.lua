#!/usr/bin/env lua
-- Focused benchmark for multiple pattern performance
-- Usage: lua scripts/bench_multipattern_focus.lua

local function precise_time()
    local handle = io.popen("lua -e 'print(os.clock())'")
    local result = tonumber(handle:read("*a"))
    handle:close()
    return result
end

local function run_command(cmd)
    local handle = io.popen(cmd .. " 2>&1")
    local result = handle:read("*a")
    local success, exit_type, code = handle:close()
    return result, code or 0
end

-- Build rgcidr
print("Building rgcidr...")
local build_output, build_code = run_command("zig build -Doptimize=ReleaseFast")
if build_code ~= 0 then
    print("✗ Failed to build rgcidr:")
    print(build_output)
    os.exit(1)
end

-- Get grepcidr
local grepcidr_path_output, grepcidr_code = run_command("lua scripts/fetch_grepcidr.lua get")
local grepcidr_path = "./grepcidr/grepcidr" -- fallback
if grepcidr_code == 0 then
    grepcidr_path = grepcidr_path_output:gsub("%s+$", "")
end

-- Test data - 1000 IPs that will match various patterns
local test_ips = {}
for i = 1, 300 do
    table.insert(test_ips, string.format("10.0.%d.%d", math.random(0, 255), math.random(1, 254)))
end
for i = 1, 400 do  
    table.insert(test_ips, string.format("192.168.%d.%d", math.random(0, 255), math.random(1, 254)))
end
for i = 1, 300 do
    table.insert(test_ips, string.format("172.16.%d.%d", math.random(0, 15), math.random(1, 254)))
end

local test_data = table.concat(test_ips, "\n")
local tmpfile = os.tmpname()
local f = io.open(tmpfile, "w")
f:write(test_data)
f:close()

-- Test patterns
local patterns = {
    {name = "Single Pattern", pattern = "192.168.0.0/16"},
    {name = "Two Patterns", pattern = "192.168.0.0/16,10.0.0.0/8"}, 
    {name = "Three Patterns", pattern = "10.0.0.0/8,192.168.0.0/16,172.16.0.0/12"},
    {name = "Four Patterns", pattern = "10.0.0.0/8,192.168.0.0/16,172.16.0.0/12,8.8.8.0/24"},
}

print("\n=== Multiple Pattern Performance Analysis ===")
print(string.format("Testing with %d IPs", #test_ips))
print("Pattern                   rgcidr(μs)    grepcidr(μs)    Ratio")
print("----------------------    ----------    ------------    -----")

for _, test in ipairs(patterns) do
    local iterations = 30
    
    -- Test rgcidr
    local rgcidr_total = 0
    for i = 1, iterations do
        local start = precise_time() 
        local cmd = string.format("./zig-out/bin/rgcidr %s < %s", test.pattern, tmpfile)
        run_command(cmd .. " > /dev/null")
        rgcidr_total = rgcidr_total + (precise_time() - start)
    end
    local rgcidr_avg_us = (rgcidr_total / iterations) * 1000000
    
    -- Test grepcidr  
    local grepcidr_total = 0
    for i = 1, iterations do
        local start = precise_time()
        local cmd = string.format("%s %s < %s", grepcidr_path, test.pattern, tmpfile)
        run_command(cmd .. " > /dev/null")
        grepcidr_total = grepcidr_total + (precise_time() - start)
    end  
    local grepcidr_avg_us = (grepcidr_total / iterations) * 1000000
    
    local ratio = rgcidr_avg_us / grepcidr_avg_us
    local status = ratio > 1.05 and "⚠" or (ratio < 0.95 and "✓" or "≈")
    
    print(string.format("%s %-20s %8.1f      %10.1f      %.2fx", 
        status, test.name, rgcidr_avg_us, grepcidr_avg_us, ratio))
end

os.remove(tmpfile)
print("\n✓ Analysis complete")