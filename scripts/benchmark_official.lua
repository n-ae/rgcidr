#!/usr/bin/env lua

-- benchmark_official.lua - Benchmark rgcidr against official grepcidr from pc-tools.net
-- This script fetches the official grepcidr 2.0 and runs comparative benchmarks

-- Load fetch_grepcidr module
package.path = package.path .. ";./?.lua"
local fetch_grepcidr = dofile("scripts/fetch_grepcidr.lua")

-- Configuration
local ITERATIONS = 5
local TEST_DIR = "tests"

-- Colors for output
local colors = {
    reset = "\27[0m",
    bold = "\27[1m",
    green = "\27[32m",
    yellow = "\27[33m",
    blue = "\27[34m",
    red = "\27[31m",
    cyan = "\27[36m",
    magenta = "\27[35m"
}

-- Helper functions
local function log(level, msg)
    local prefix = {
        info = colors.blue .. "[INFO]" .. colors.reset,
        success = colors.green .. "[✓]" .. colors.reset,
        warning = colors.yellow .. "[WARNING]" .. colors.reset,
        error = colors.red .. "[ERROR]" .. colors.reset,
        header = colors.bold .. colors.cyan .. "[BENCHMARK]" .. colors.reset
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

local function get_file_size(path)
    local f = io.open(path, "r")
    if f then
        local size = f:seek("end")
        f:close()
        return size
    end
    return 0
end

local function format_size(bytes)
    if bytes < 1024 then
        return string.format("%d B", bytes)
    elseif bytes < 1024 * 1024 then
        return string.format("%.1f KB", bytes / 1024)
    else
        return string.format("%.1f MB", bytes / (1024 * 1024))
    end
end

local function measure_time(cmd)
    local times = {}
    for i = 1, ITERATIONS do
        local start = os.clock()
        local success, output = run_command(cmd)
        local elapsed = os.clock() - start
        
        if not success then
            return nil, "Command failed: " .. cmd
        end
        
        table.insert(times, elapsed * 1000) -- Convert to milliseconds
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
        max = times[#times],
        median = times[math.ceil(#times / 2)]
    }
end

local function find_test_files()
    local tests = {}
    
    -- Find all .given files in tests directory
    local handle = io.popen("find " .. TEST_DIR .. " -name '*.given' 2>/dev/null")
    for file in handle:lines() do
        local base = file:gsub("%.given$", "")
        local name = base:gsub("^" .. TEST_DIR .. "/", "")
        
        -- Check if corresponding action file exists
        local action_file = base .. ".action"
        if file_exists(action_file) then
            -- Read action file to get arguments
            local f = io.open(action_file, "r")
            local args = f:read("*a"):gsub("\n$", "")
            f:close()
            
            table.insert(tests, {
                name = name,
                given = file,
                action = action_file,
                args = args,
                size = get_file_size(file)
            })
        end
    end
    handle:close()
    
    -- Sort by file size (largest first for better benchmark visibility)
    table.sort(tests, function(a, b) return a.size > b.size end)
    
    return tests
end

local function run_benchmark(rgcidr_path, grepcidr_path, test)
    -- Run rgcidr
    local rgcidr_cmd = string.format("%s %s %s", rgcidr_path, test.args, test.given)
    local rgcidr_stats = measure_time(rgcidr_cmd)
    
    -- Run official grepcidr
    local grepcidr_cmd = string.format("%s %s %s", grepcidr_path, test.args, test.given)
    local grepcidr_stats = measure_time(grepcidr_cmd)
    
    if not rgcidr_stats or not grepcidr_stats then
        return nil
    end
    
    return {
        test_name = test.name,
        file_size = test.size,
        rgcidr = rgcidr_stats,
        grepcidr = grepcidr_stats,
        speedup = grepcidr_stats.mean / rgcidr_stats.mean
    }
end

local function print_results(results)
    -- Header
    print()
    log("header", "Benchmark Results: rgcidr vs Official grepcidr 2.0")
    log("info", "Source: " .. fetch_grepcidr.GREPCIDR_URL)
    print(colors.cyan .. string.rep("─", 80) .. colors.reset)
    
    -- Summary statistics
    local total_tests = #results
    local rgcidr_wins = 0
    local grepcidr_wins = 0
    local total_rgcidr_time = 0
    local total_grepcidr_time = 0
    
    for _, r in ipairs(results) do
        total_rgcidr_time = total_rgcidr_time + r.rgcidr.mean
        total_grepcidr_time = total_grepcidr_time + r.grepcidr.mean
        
        if r.speedup > 1.0 then
            rgcidr_wins = rgcidr_wins + 1
        else
            grepcidr_wins = grepcidr_wins + 1
        end
    end
    
    -- Print summary
    print()
    print(colors.bold .. "Summary:" .. colors.reset)
    print(string.format("  Total tests: %d", total_tests))
    print(string.format("  rgcidr wins: %s%d (%.1f%%)%s", 
        rgcidr_wins > grepcidr_wins and colors.green or colors.yellow,
        rgcidr_wins, (rgcidr_wins / total_tests) * 100, colors.reset))
    print(string.format("  grepcidr wins: %s%d (%.1f%%)%s",
        grepcidr_wins > rgcidr_wins and colors.green or colors.yellow,
        grepcidr_wins, (grepcidr_wins / total_tests) * 100, colors.reset))
    print(string.format("  Overall speedup: %s%.2fx%s",
        total_rgcidr_time < total_grepcidr_time and colors.green or colors.red,
        total_grepcidr_time / total_rgcidr_time, colors.reset))
    
    -- Detailed results table
    print()
    print(colors.bold .. "Detailed Results:" .. colors.reset)
    print(colors.cyan .. string.rep("─", 80) .. colors.reset)
    print(string.format("%-30s %10s %12s %12s %10s", 
        "Test", "Size", "rgcidr (ms)", "grepcidr (ms)", "Speedup"))
    print(colors.cyan .. string.rep("─", 80) .. colors.reset)
    
    -- Sort by speedup (best improvements first)
    table.sort(results, function(a, b) return a.speedup > b.speedup end)
    
    for _, r in ipairs(results) do
        local speedup_color = colors.reset
        if r.speedup > 1.1 then
            speedup_color = colors.green
        elseif r.speedup < 0.9 then
            speedup_color = colors.red
        end
        
        print(string.format("%-30s %10s %12.2f %12.2f %s%10.2fx%s",
            r.test_name:sub(1, 30),
            format_size(r.file_size),
            r.rgcidr.mean,
            r.grepcidr.mean,
            speedup_color,
            r.speedup,
            colors.reset))
    end
    
    print(colors.cyan .. string.rep("─", 80) .. colors.reset)
    
    -- Performance categories
    print()
    print(colors.bold .. "Performance Analysis:" .. colors.reset)
    
    local categories = {
        excellent = {},  -- rgcidr >1.5x faster
        good = {},       -- rgcidr 1.1-1.5x faster
        comparable = {}, -- within 10%
        slower = {},     -- grepcidr 1.1-2x faster
        poor = {}        -- grepcidr >2x faster
    }
    
    for _, r in ipairs(results) do
        if r.speedup > 1.5 then
            table.insert(categories.excellent, r)
        elseif r.speedup > 1.1 then
            table.insert(categories.good, r)
        elseif r.speedup > 0.9 then
            table.insert(categories.comparable, r)
        elseif r.speedup > 0.5 then
            table.insert(categories.slower, r)
        else
            table.insert(categories.poor, r)
        end
    end
    
    if #categories.excellent > 0 then
        print(colors.green .. "  Excellent (>1.5x faster): " .. colors.reset .. #categories.excellent .. " tests")
    end
    if #categories.good > 0 then
        print(colors.green .. "  Good (1.1-1.5x faster): " .. colors.reset .. #categories.good .. " tests")
    end
    if #categories.comparable > 0 then
        print(colors.yellow .. "  Comparable (±10%): " .. colors.reset .. #categories.comparable .. " tests")
    end
    if #categories.slower > 0 then
        print(colors.red .. "  Slower (1.1-2x slower): " .. colors.reset .. #categories.slower .. " tests")
    end
    if #categories.poor > 0 then
        print(colors.red .. "  Poor (>2x slower): " .. colors.reset .. #categories.poor .. " tests")
    end
    
    -- Write CSV output
    local csv_file = "benchmark_official.csv"
    local f = io.open(csv_file, "w")
    f:write("test_name,file_size_bytes,rgcidr_mean_ms,rgcidr_min_ms,rgcidr_max_ms,")
    f:write("grepcidr_mean_ms,grepcidr_min_ms,grepcidr_max_ms,speedup\n")
    
    for _, r in ipairs(results) do
        f:write(string.format("%s,%d,%.3f,%.3f,%.3f,%.3f,%.3f,%.3f,%.3f\n",
            r.test_name, r.file_size,
            r.rgcidr.mean, r.rgcidr.min, r.rgcidr.max,
            r.grepcidr.mean, r.grepcidr.min, r.grepcidr.max,
            r.speedup))
    end
    f:close()
    
    print()
    log("success", "Results written to " .. csv_file)
end

-- Main function
local function main()
    log("header", "Starting Official grepcidr Benchmark")
    log("info", "This benchmark compares rgcidr against the official grepcidr 2.0")
    log("info", "from pc-tools.net (the original implementation by Jem Berkes)")
    print()
    
    -- Build rgcidr with optimizations
    log("info", "Building rgcidr with ReleaseFast optimizations...")
    local success, output = run_command("zig build -Doptimize=ReleaseFast")
    if not success then
        log("error", "Failed to build rgcidr")
        return 1
    end
    
    local rgcidr_path = "./zig-out/bin/rgcidr"
    if not file_exists(rgcidr_path) then
        log("error", "rgcidr binary not found at " .. rgcidr_path)
        return 1
    end
    log("success", "Built rgcidr successfully")
    
    -- Get official grepcidr
    log("info", "Getting official grepcidr 2.0...")
    local grepcidr_path = fetch_grepcidr.get_grepcidr_path()
    if not grepcidr_path then
        log("error", "Failed to get official grepcidr")
        return 1
    end
    log("success", "Official grepcidr ready: " .. grepcidr_path)
    
    -- Find test files
    log("info", "Finding test files...")
    local tests = find_test_files()
    if #tests == 0 then
        log("error", "No test files found")
        return 1
    end
    log("success", string.format("Found %d test files", #tests))
    
    -- Run benchmarks
    print()
    log("info", string.format("Running benchmarks (%d iterations per test)...", ITERATIONS))
    local results = {}
    
    for i, test in ipairs(tests) do
        io.write(string.format("\r  Progress: %d/%d - %s", i, #tests, test.name))
        io.flush()
        
        local result = run_benchmark(rgcidr_path, grepcidr_path, test)
        if result then
            table.insert(results, result)
        end
    end
    print("\r" .. string.rep(" ", 80) .. "\r")
    
    -- Print results
    print_results(results)
    
    -- Cleanup option
    print()
    io.write("Clean up temporary grepcidr files? (y/n): ")
    local answer = io.read()
    if answer:lower() == "y" then
        fetch_grepcidr.cleanup()
        log("success", "Cleaned up temporary files")
    end
    
    return 0
end

-- Run if executed directly
if arg and arg[0]:match("benchmark_official%.lua$") then
    os.exit(main())
end
