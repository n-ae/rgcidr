#!/usr/bin/env lua

-- benchmark_quick.lua - Quick benchmark test with limited tests

-- Load fetch_grepcidr module
package.path = package.path .. ";./?.lua"
local fetch_grepcidr = dofile("scripts/fetch_grepcidr.lua")

-- Configuration
local ITERATIONS = 3  -- Fewer iterations for quick test
local TEST_DIR = "tests"
local MAX_TESTS = 5  -- Limit number of tests

-- Colors for output
local colors = {
    reset = "\27[0m",
    bold = "\27[1m",
    green = "\27[32m",
    yellow = "\27[33m",
    blue = "\27[34m",
    red = "\27[31m",
    cyan = "\27[36m"
}

-- Helper functions
local function log(level, msg)
    local prefix = {
        info = colors.blue .. "[INFO]" .. colors.reset,
        success = colors.green .. "[✓]" .. colors.reset,
        warning = colors.yellow .. "[WARNING]" .. colors.reset,
        error = colors.red .. "[ERROR]" .. colors.reset,
        header = colors.bold .. colors.cyan .. "[QUICK BENCH]" .. colors.reset
    }
    print(prefix[level] .. " " .. msg)
end

local function run_command(cmd)
    local handle = io.popen(cmd .. " 2>&1")
    local output = handle:read("*a")
    local success = handle:close()
    return success, output
end

local function file_exists(path)
    local f = io.open(path, "r")
    if f then
        f:close()
        return true
    end
    return false
end

local function measure_time(cmd)
    local times = {}
    for i = 1, ITERATIONS do
        local start = os.clock()
        local success = os.execute(cmd .. " >/dev/null 2>&1")
        local elapsed = os.clock() - start
        
        if success then
            table.insert(times, elapsed * 1000) -- Convert to milliseconds
        end
    end
    
    if #times == 0 then
        return nil
    end
    
    -- Calculate statistics
    table.sort(times)
    local sum = 0
    for _, t in ipairs(times) do
        sum = sum + t
    end
    
    return {
        mean = sum / #times,
        min = times[1],
        max = times[#times]
    }
end

local function find_test_files()
    local tests = {}
    
    -- Find benchmark test files first (they're more interesting)
    local handle = io.popen("ls " .. TEST_DIR .. "/bench*.given 2>/dev/null")
    for file in handle:lines() do
        local base = file:gsub("%.given$", "")
        local name = base:gsub("^" .. TEST_DIR .. "/", "")
        
        local action_file = base .. ".action"
        if file_exists(action_file) then
            local f = io.open(action_file, "r")
            local args = f:read("*a"):gsub("\n$", "")
            f:close()
            
            table.insert(tests, {
                name = name,
                given = file,
                args = args
            })
            
            if #tests >= MAX_TESTS then
                break
            end
        end
    end
    handle:close()
    
    return tests
end

-- Main function
local function main()
    log("header", "Starting Quick Benchmark Test")
    log("info", string.format("Running %d iterations on up to %d tests", ITERATIONS, MAX_TESTS))
    print()
    
    -- Build rgcidr
    log("info", "Building rgcidr with ReleaseFast...")
    local success = os.execute("zig build -Doptimize=ReleaseFast 2>/dev/null")
    if not success then
        log("error", "Failed to build rgcidr")
        return 1
    end
    
    local rgcidr_path = "./zig-out/bin/rgcidr"
    if not file_exists(rgcidr_path) then
        log("error", "rgcidr binary not found")
        return 1
    end
    log("success", "Built rgcidr")
    
    -- Get official grepcidr
    log("info", "Getting official grepcidr 2.0...")
    local grepcidr_path = fetch_grepcidr.get_grepcidr_path()
    if not grepcidr_path then
        log("error", "Failed to get official grepcidr")
        return 1
    end
    log("success", "Official grepcidr ready")
    
    -- Find test files
    local tests = find_test_files()
    if #tests == 0 then
        log("error", "No test files found")
        return 1
    end
    log("success", string.format("Found %d test files", #tests))
    
    -- Run benchmarks
    print()
    log("info", "Running benchmarks...")
    local results = {}
    
    for i, test in ipairs(tests) do
        io.write(string.format("\r  Testing: %s", test.name))
        io.flush()
        
        -- Run rgcidr
        local rgcidr_cmd = string.format("%s %s %s", rgcidr_path, test.args, test.given)
        local rgcidr_stats = measure_time(rgcidr_cmd)
        
        -- Run grepcidr
        local grepcidr_cmd = string.format("%s %s %s", grepcidr_path, test.args, test.given)
        local grepcidr_stats = measure_time(grepcidr_cmd)
        
        if rgcidr_stats and grepcidr_stats then
            table.insert(results, {
                name = test.name,
                rgcidr = rgcidr_stats.mean,
                grepcidr = grepcidr_stats.mean,
                speedup = grepcidr_stats.mean / rgcidr_stats.mean
            })
        end
    end
    print("\r" .. string.rep(" ", 50) .. "\r")
    
    -- Print results
    print()
    log("header", "Quick Benchmark Results")
    print(colors.cyan .. string.rep("─", 60) .. colors.reset)
    print(string.format("%-25s %10s %10s %10s", "Test", "rgcidr", "grepcidr", "Speedup"))
    print(colors.cyan .. string.rep("─", 60) .. colors.reset)
    
    for _, r in ipairs(results) do
        local speedup_color = colors.reset
        if r.speedup > 1.1 then
            speedup_color = colors.green
        elseif r.speedup < 0.9 then
            speedup_color = colors.red
        end
        
        print(string.format("%-25s %9.2fms %9.2fms %s%9.2fx%s",
            r.name:sub(1, 25),
            r.rgcidr,
            r.grepcidr,
            speedup_color,
            r.speedup,
            colors.reset))
    end
    
    print(colors.cyan .. string.rep("─", 60) .. colors.reset)
    
    print()
    log("success", "Quick benchmark complete!")
    log("info", "For full benchmarks run: lua scripts/benchmark_official.lua")
    
    return 0
end

-- Run if executed directly
if arg and arg[0]:match("benchmark_quick%.lua$") then
    os.exit(main())
end
