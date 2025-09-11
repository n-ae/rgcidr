#!/usr/bin/env lua
-- Statistical benchmark runner with 1% variance requirement
-- Runs each test 10 times and validates statistical reliability

local function precise_time()
    return os.clock()
end

local function run_command(cmd)
    local handle = io.popen(cmd .. " 2>&1")
    local result = handle:read("*a")
    local success, exit_type, code = handle:close()
    return result, code or 0
end

-- Statistical analysis functions
local function calculate_statistics(times)
    local n = #times
    local sum = 0
    for _, t in ipairs(times) do
        sum = sum + t
    end
    local mean = sum / n
    
    local variance_sum = 0
    for _, t in ipairs(times) do
        variance_sum = variance_sum + (t - mean)^2
    end
    local std_dev = math.sqrt(variance_sum / (n - 1))
    local variance_percent = (std_dev / mean) * 100
    
    local min_time = math.min(table.unpack(times))
    local max_time = math.max(table.unpack(times))
    
    return {
        mean = mean,
        std_dev = std_dev,
        variance_percent = variance_percent,
        min = min_time,
        max = max_time,
        n = n
    }
end

local function run_statistical_test(name, command, min_runs, max_runs, target_variance)
    print(string.format("Running %s...", name))
    
    local times = {}
    local reliable = false
    local runs = 0
    
    -- Progressive testing: start with min_runs, increase until reliable or max_runs
    while runs < max_runs and not reliable do
        -- Run additional tests
        local batch_size = math.min(10, max_runs - runs)
        for i = 1, batch_size do
            local start = precise_time()
            local output, code = run_command(command)
            if code ~= 0 then
                return nil, string.format("Command failed: %s", command)
            end
            local elapsed = (precise_time() - start) * 1000000  -- Convert to microseconds
            table.insert(times, elapsed)
            runs = runs + 1
        end
        
        -- Check reliability if we have enough samples
        if runs >= min_runs then
            local stats = calculate_statistics(times)
            if stats.variance_percent <= target_variance then
                reliable = true
                return stats, nil
            end
        end
        
        -- Print progress for long-running tests
        if runs % 20 == 0 then
            local stats = calculate_statistics(times)
            print(string.format("  %d runs: %.1fμs avg, %.1f%% variance", 
                runs, stats.mean, stats.variance_percent))
        end
    end
    
    -- Final attempt - return best result we got
    local stats = calculate_statistics(times)
    local warning = nil
    if stats.variance_percent > target_variance then
        warning = string.format("High variance: %.1f%% (target: %.1f%%)", 
            stats.variance_percent, target_variance)
    end
    
    return stats, warning
end

-- Build both tools
print("=== Statistical Reliability Benchmark ===\n")

print("Building rgcidr...")
local build_out, build_code = run_command("zig build -Doptimize=ReleaseFast")
if build_code ~= 0 then
    print("✗ rgcidr build failed")
    print(build_out)
    os.exit(1)
end

-- Check if grepcidr is available
local grepcidr_available = false
local grepcidr_check, grepcidr_code = run_command("which grepcidr")
if grepcidr_code == 0 then
    grepcidr_available = true
    print("✓ grepcidr found")
else
    print("⚠ grepcidr not available - testing rgcidr only")
end

-- Create comprehensive test datasets
local test_scenarios = {
    {
        name = "Small Dataset (100 IPs)",
        pattern = "192.168.0.0/16",
        data_gen = function()
            local ips = {}
            for i = 1, 100 do
                table.insert(ips, string.format("192.168.%d.%d", 
                    math.random(0, 255), math.random(1, 254)))
            end
            return table.concat(ips, "\n")
        end
    },
    {
        name = "Medium Dataset (1000 IPs)",  
        pattern = "192.168.0.0/16,10.0.0.0/8",
        data_gen = function()
            local ips = {}
            for i = 1, 1000 do
                if i <= 500 then
                    table.insert(ips, string.format("192.168.%d.%d", 
                        math.random(0, 255), math.random(1, 254)))
                else
                    table.insert(ips, string.format("10.%d.%d.%d", 
                        math.random(0, 255), math.random(0, 255), math.random(1, 254)))
                end
            end
            return table.concat(ips, "\n")
        end
    },
    {
        name = "Large Dataset (5000 IPs)",
        pattern = "172.16.0.0/12",
        data_gen = function()
            local ips = {}
            for i = 1, 5000 do
                if i <= 1000 then
                    -- 20% matches
                    table.insert(ips, string.format("172.%d.%d.%d", 
                        math.random(16, 31), math.random(0, 255), math.random(1, 254)))
                else
                    -- 80% non-matches
                    table.insert(ips, string.format("%d.%d.%d.%d", 
                        math.random(1, 255), math.random(0, 255), 
                        math.random(0, 255), math.random(1, 254)))
                end
            end
            return table.concat(ips, "\n")
        end
    },
    {
        name = "Multiple Patterns",
        pattern = "192.168.0.0/16,10.0.0.0/8,172.16.0.0/12,203.0.113.0/24",
        data_gen = function()
            local ips = {}
            local patterns = {
                function() return string.format("192.168.%d.%d", math.random(0, 255), math.random(1, 254)) end,
                function() return string.format("10.%d.%d.%d", math.random(0, 255), math.random(0, 255), math.random(1, 254)) end,
                function() return string.format("172.%d.%d.%d", math.random(16, 31), math.random(0, 255), math.random(1, 254)) end,
                function() return string.format("203.0.113.%d", math.random(1, 254)) end,
                function() return string.format("%d.%d.%d.%d", math.random(1, 255), math.random(0, 255), math.random(0, 255), math.random(1, 254)) end
            }
            
            for i = 1, 1500 do
                local pattern_func = patterns[math.random(1, #patterns)]
                table.insert(ips, pattern_func())
            end
            return table.concat(ips, "\n")
        end
    }
}

-- Statistical requirements
local MIN_RUNS = 10
local MAX_RUNS = 100
local TARGET_VARIANCE = 1.0  -- 1% variance requirement

print(string.format("Statistical Requirements:"))
print(string.format("  Minimum runs: %d", MIN_RUNS))
print(string.format("  Maximum runs: %d", MAX_RUNS))
print(string.format("  Target variance: %.1f%%", TARGET_VARIANCE))
print(string.format("  Target confidence: 99%%\n"))

-- Results storage
local results = {}

-- Run tests for each scenario
for _, scenario in ipairs(test_scenarios) do
    print(string.format("=== %s ===", scenario.name))
    
    -- Generate test data
    local test_data = scenario.data_gen()
    local temp_file = os.tmpname()
    local f = io.open(temp_file, "w")
    f:write(test_data)
    f:close()
    
    local scenario_results = {
        name = scenario.name,
        pattern = scenario.pattern,
        rgcidr = nil,
        grepcidr = nil
    }
    
    -- Test rgcidr
    local rgcidr_cmd = string.format('./zig-out/bin/rgcidr "%s" %s > /dev/null', scenario.pattern, temp_file)
    local rgcidr_stats, rgcidr_warning = run_statistical_test("rgcidr", rgcidr_cmd, MIN_RUNS, MAX_RUNS, TARGET_VARIANCE)
    
    if rgcidr_stats then
        scenario_results.rgcidr = rgcidr_stats
        print(string.format("  rgcidr: %.1fμs ± %.1fμs (%.2f%% variance, %d runs)", 
            rgcidr_stats.mean, rgcidr_stats.std_dev, rgcidr_stats.variance_percent, rgcidr_stats.n))
        if rgcidr_warning then
            print(string.format("  ⚠ %s", rgcidr_warning))
        else
            print("  ✓ Statistically reliable")
        end
    else
        print("  ✗ rgcidr test failed")
    end
    
    -- Test grepcidr if available
    if grepcidr_available then
        local grepcidr_cmd = string.format('grepcidr "%s" %s > /dev/null', scenario.pattern, temp_file)
        local grepcidr_stats, grepcidr_warning = run_statistical_test("grepcidr", grepcidr_cmd, MIN_RUNS, MAX_RUNS, TARGET_VARIANCE)
        
        if grepcidr_stats then
            scenario_results.grepcidr = grepcidr_stats
            print(string.format("  grepcidr: %.1fμs ± %.1fμs (%.2f%% variance, %d runs)", 
                grepcidr_stats.mean, grepcidr_stats.std_dev, grepcidr_stats.variance_percent, grepcidr_stats.n))
            if grepcidr_warning then
                print(string.format("  ⚠ %s", grepcidr_warning))
            else
                print("  ✓ Statistically reliable")
            end
        else
            print("  ✗ grepcidr test failed")
        end
    end
    
    table.insert(results, scenario_results)
    os.remove(temp_file)
    print()
end

-- Generate final statistical report
print("=== Final Statistical Results ===")
print(string.format("%-25s | %-15s | %-15s | Performance", "Benchmark", "rgcidr", "grepcidr"))
print(string.format("%-25s | %-15s | %-15s | -----------", "-------------------------", "---------------", "---------------"))

for _, result in ipairs(results) do
    local rgcidr_str = "N/A"
    local grepcidr_str = "N/A" 
    local performance_str = "N/A"
    
    if result.rgcidr then
        local reliable_mark = result.rgcidr.variance_percent <= TARGET_VARIANCE and "✓" or "⚠"
        rgcidr_str = string.format("%s %.1fμs", reliable_mark, result.rgcidr.mean)
    end
    
    if result.grepcidr then
        local reliable_mark = result.grepcidr.variance_percent <= TARGET_VARIANCE and "✓" or "⚠"
        grepcidr_str = string.format("%s %.1fμs", reliable_mark, result.grepcidr.mean)
        
        -- Calculate performance comparison
        if result.rgcidr then
            local ratio = result.grepcidr.mean / result.rgcidr.mean
            if ratio > 1.02 then
                performance_str = string.format("+%.1f%% faster", (ratio - 1) * 100)
            elseif ratio < 0.98 then
                performance_str = string.format("%.1f%% slower", (1 - ratio) * 100)
            else
                performance_str = "equivalent"
            end
        end
    end
    
    print(string.format("%-25s | %-15s | %-15s | %s", 
        result.name, rgcidr_str, grepcidr_str, performance_str))
end

print("\nLegend:")
print("  ✓ = <1% variance (statistically reliable)")
print("  ⚠ = >1% variance (needs more testing)")
print("  Performance comparison based on mean execution time")