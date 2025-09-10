#!/usr/bin/env lua

local json = require('cjson')
local socket = require('socket')

-- Configuration
local RUNS_PER_TEST = 10  -- Number of runs per test for statistical accuracy
local RGCIDR_BIN = "./zig-out/bin/rgcidr"
local GREPCIDR_BIN = "./grepcidr/grepcidr"
local TESTS_DIR = "tests"
local RESULTS_FILE = "benchmark_results.csv"
local DETAILED_RESULTS_FILE = "benchmark_detailed.json"

-- Helper functions
local function file_exists(name)
    local f = io.open(name, "r")
    if f then
        f:close()
        return true
    else
        return false
    end
end

local function read_file(path)
    local file = io.open(path, "r")
    if not file then return nil end
    local content = file:read("*all")
    file:close()
    return content
end

local function parse_action_file(action_content)
    local lines = {}
    for line in action_content:gmatch("[^\r\n]+") do
        table.insert(lines, line)
    end
    
    -- Parse the action format: "1|pattern" or just "pattern"
    local actions = {}
    for _, line in ipairs(lines) do
        local num, pattern = line:match("^(%d+)|(.*)$")
        if pattern and pattern ~= "" then
            table.insert(actions, pattern)
        elseif line ~= "" and not line:match("^%d+|$") then
            table.insert(actions, line)
        end
    end
    return actions
end

local function run_command_with_timing(cmd)
    local start_time = socket.gettime()
    local handle = io.popen(cmd .. " 2>&1")
    local result = handle:read("*a")
    local exit_code = handle:close()
    local end_time = socket.gettime()
    
    local duration = end_time - start_time
    local success = (exit_code == true or exit_code == nil)
    
    return {
        duration = duration,
        output = result,
        success = success
    }
end

local function run_benchmark_test(test_name, actions, input_file, implementation)
    local results = {}
    local binary = (implementation == "rgcidr") and RGCIDR_BIN or GREPCIDR_BIN
    
    for run = 1, RUNS_PER_TEST do
        -- Build command based on actions
        local cmd_parts = {binary}
        
        for _, action in ipairs(actions) do
            table.insert(cmd_parts, action)
        end
        
        table.insert(cmd_parts, input_file)
        local cmd = table.concat(cmd_parts, " ")
        
        local result = run_command_with_timing(cmd)
        table.insert(results, {
            run = run,
            duration = result.duration,
            success = result.success,
            output_length = #result.output
        })
        
        if not result.success then
            print(string.format("Warning: %s failed on test %s run %d", implementation, test_name, run))
        end
    end
    
    return results
end

local function calculate_stats(durations)
    if #durations == 0 then return {} end
    
    table.sort(durations)
    
    local sum = 0
    for _, d in ipairs(durations) do
        sum = sum + d
    end
    
    local mean = sum / #durations
    
    -- Calculate standard deviation
    local variance_sum = 0
    for _, d in ipairs(durations) do
        variance_sum = variance_sum + (d - mean) ^ 2
    end
    local std_dev = math.sqrt(variance_sum / #durations)
    
    local median = durations[math.ceil(#durations / 2)]
    local min_val = durations[1]
    local max_val = durations[#durations]
    
    return {
        mean = mean,
        median = median,
        min = min_val,
        max = max_val,
        std_dev = std_dev,
        count = #durations
    }
end

-- Main benchmarking function
local function run_benchmarks()
    print("🚀 Starting comprehensive benchmark suite...")
    print("Comparing C grepcidr vs Zig rgcidr")
    print(string.format("Running %d iterations per test for statistical accuracy", RUNS_PER_TEST))
    
    -- Find all test files
    local test_files = {}
    local handle = io.popen("find " .. TESTS_DIR .. " -name '*.action' | sort")
    for line in handle:lines() do
        local test_name = line:match("([^/]+)%.action$")
        if test_name then
            table.insert(test_files, {
                name = test_name,
                action_file = line,
                given_file = line:gsub("%.action$", ".given"),
                expected_file = line:gsub("%.action$", ".expected")
            })
        end
    end
    handle:close()
    
    local detailed_results = {}
    local csv_data = {}
    
    -- CSV header
    table.insert(csv_data, "test_name,category,rgcidr_mean_ms,rgcidr_median_ms,rgcidr_min_ms,rgcidr_max_ms,rgcidr_std_dev_ms,grepcidr_mean_ms,grepcidr_median_ms,grepcidr_min_ms,grepcidr_max_ms,grepcidr_std_dev_ms,speedup_factor,winner")
    
    for _, test in ipairs(test_files) do
        print(string.format("Running benchmark: %s", test.name))
        
        if not file_exists(test.given_file) then
            print(string.format("Warning: Input file %s not found, skipping", test.given_file))
            goto continue
        end
        
        -- Read and parse action file
        local action_content = read_file(test.action_file)
        if not action_content then
            print(string.format("Warning: Cannot read action file %s, skipping", test.action_file))
            goto continue
        end
        
        local actions = parse_action_file(action_content)
        if #actions == 0 then
            print(string.format("Warning: No valid actions found in %s, skipping", test.action_file))
            goto continue
        end
        
        -- Determine test category
        local category = test.name:match("^bench_") and "benchmark" or "compliance"
        
        -- Run benchmarks for both implementations
        local rgcidr_results = run_benchmark_test(test.name, actions, test.given_file, "rgcidr")
        local grepcidr_results = run_benchmark_test(test.name, actions, test.given_file, "grepcidr")
        
        -- Extract durations for statistical analysis
        local rgcidr_durations = {}
        local grepcidr_durations = {}
        
        for _, result in ipairs(rgcidr_results) do
            if result.success then
                table.insert(rgcidr_durations, result.duration)
            end
        end
        
        for _, result in ipairs(grepcidr_results) do
            if result.success then
                table.insert(grepcidr_durations, result.duration)
            end
        end
        
        if #rgcidr_durations == 0 or #grepcidr_durations == 0 then
            print(string.format("Warning: Insufficient successful runs for %s, skipping", test.name))
            goto continue
        end
        
        -- Calculate statistics
        local rgcidr_stats = calculate_stats(rgcidr_durations)
        local grepcidr_stats = calculate_stats(grepcidr_durations)
        
        -- Determine winner and speedup
        local speedup_factor = grepcidr_stats.mean / rgcidr_stats.mean
        local winner = (speedup_factor > 1) and "rgcidr" or "grepcidr"
        
        -- Store detailed results
        detailed_results[test.name] = {
            category = category,
            rgcidr = {
                results = rgcidr_results,
                stats = rgcidr_stats
            },
            grepcidr = {
                results = grepcidr_results,
                stats = grepcidr_stats
            },
            speedup_factor = speedup_factor,
            winner = winner
        }
        
        -- Add to CSV data (convert to milliseconds for readability)
        table.insert(csv_data, string.format(
            "%s,%s,%.3f,%.3f,%.3f,%.3f,%.3f,%.3f,%.3f,%.3f,%.3f,%.3f,%.3f,%s",
            test.name,
            category,
            rgcidr_stats.mean * 1000,
            rgcidr_stats.median * 1000,
            rgcidr_stats.min * 1000,
            rgcidr_stats.max * 1000,
            rgcidr_stats.std_dev * 1000,
            grepcidr_stats.mean * 1000,
            grepcidr_stats.median * 1000,
            grepcidr_stats.min * 1000,
            grepcidr_stats.max * 1000,
            grepcidr_stats.std_dev * 1000,
            speedup_factor,
            winner
        ))
        
        print(string.format("  ✓ %s: %.2fx %s", test.name, math.abs(speedup_factor), winner))
        
        ::continue::
    end
    
    -- Write CSV results
    local csv_file = io.open(RESULTS_FILE, "w")
    for _, line in ipairs(csv_data) do
        csv_file:write(line .. "\n")
    end
    csv_file:close()
    
    -- Write detailed JSON results
    local json_file = io.open(DETAILED_RESULTS_FILE, "w")
    json_file:write(json.encode(detailed_results))
    json_file:close()
    
    print(string.format("\n✅ Benchmark complete!"))
    print(string.format("📊 Results written to: %s", RESULTS_FILE))
    print(string.format("📋 Detailed results: %s", DETAILED_RESULTS_FILE))
    
    -- Print summary
    local rgcidr_wins = 0
    local grepcidr_wins = 0
    local benchmark_tests = 0
    local compliance_tests = 0
    
    for _, result in pairs(detailed_results) do
        if result.winner == "rgcidr" then
            rgcidr_wins = rgcidr_wins + 1
        else
            grepcidr_wins = grepcidr_wins + 1
        end
        
        if result.category == "benchmark" then
            benchmark_tests = benchmark_tests + 1
        else
            compliance_tests = compliance_tests + 1
        end
    end
    
    print(string.format("\n📈 Summary:"))
    print(string.format("  Total tests: %d", rgcidr_wins + grepcidr_wins))
    print(string.format("  Benchmark tests: %d", benchmark_tests))
    print(string.format("  Compliance tests: %d", compliance_tests))
    print(string.format("  Zig rgcidr wins: %d", rgcidr_wins))
    print(string.format("  C grepcidr wins: %d", grepcidr_wins))
end

-- Run the benchmarks
run_benchmarks()
