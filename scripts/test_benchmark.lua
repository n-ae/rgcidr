#!/usr/bin/env lua

-- Quick test to verify benchmarking works

-- Load fetch_grepcidr module
local fetch_grepcidr = dofile("scripts/fetch_grepcidr.lua")

print("[TEST] Testing benchmark setup...")

-- Get grepcidr path
local grepcidr_path = fetch_grepcidr.get_grepcidr_path()
if not grepcidr_path then
    print("[ERROR] Failed to get grepcidr")
    os.exit(1)
end
print("[OK] grepcidr path: " .. grepcidr_path)

-- Build rgcidr
print("[TEST] Building rgcidr...")
local success = os.execute("zig build -Doptimize=ReleaseFast 2>/dev/null")
if not success then
    print("[ERROR] Failed to build rgcidr")
    os.exit(1)
end
print("[OK] rgcidr built")

-- Test both binaries
print("[TEST] Testing binaries...")

-- Create test data
local test_file = "/tmp/test_ips.txt"
local f = io.open(test_file, "w")
f:write("192.168.1.1\n")
f:write("10.0.0.1\n")
f:write("172.16.1.1\n")
f:write("8.8.8.8\n")
f:close()

-- Test grepcidr
local cmd = grepcidr_path .. " '192.168.0.0/16' " .. test_file .. " 2>/dev/null"
local handle = io.popen(cmd)
local output = handle:read("*a")
handle:close()

if output:match("192.168.1.1") then
    print("[OK] grepcidr works: found 192.168.1.1")
else
    print("[ERROR] grepcidr failed")
    os.exit(1)
end

-- Test rgcidr
cmd = "./zig-out/bin/rgcidr '192.168.0.0/16' " .. test_file .. " 2>/dev/null"
handle = io.popen(cmd)
output = handle:read("*a")
handle:close()

if output:match("192.168.1.1") then
    print("[OK] rgcidr works: found 192.168.1.1")
else
    print("[ERROR] rgcidr failed")
    os.exit(1)
end

-- Benchmark test
print("[TEST] Running mini benchmark...")

local function measure_time(cmd, iterations)
    local times = {}
    for i = 1, iterations do
        local start = os.clock()
        os.execute(cmd .. " >/dev/null 2>&1")
        local elapsed = os.clock() - start
        table.insert(times, elapsed * 1000)
    end
    
    local sum = 0
    for _, t in ipairs(times) do
        sum = sum + t
    end
    return sum / #times
end

local grepcidr_time = measure_time(grepcidr_path .. " '192.168.0.0/16' " .. test_file, 5)
local rgcidr_time = measure_time("./zig-out/bin/rgcidr '192.168.0.0/16' " .. test_file, 5)

print(string.format("[OK] grepcidr: %.2f ms", grepcidr_time))
print(string.format("[OK] rgcidr: %.2f ms", rgcidr_time))
print(string.format("[OK] Speedup: %.2fx", grepcidr_time / rgcidr_time))

-- Cleanup
os.remove(test_file)

print("\n[SUCCESS] All tests passed! Benchmarking system is working.")
print("You can now run: lua scripts/benchmark_official.lua")
