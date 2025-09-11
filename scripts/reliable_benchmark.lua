#!/usr/bin/env lua
-- Statistical benchmark with realistic variance targets (10 runs minimum, <5% target variance)

local function precise_time()
    return os.clock()
end

local function run_command(cmd)
    local handle = io.popen(cmd .. " 2>&1")
    local result = handle:read("*a")
    local success, exit_type, code = handle:close()
    return result, code or 0
end

local function calculate_stats(times)
    local n = #times
    table.sort(times)
    
    local sum = 0
    for _, t in ipairs(times) do sum = sum + t end
    local mean = sum / n
    
    local variance_sum = 0
    for _, t in ipairs(times) do
        variance_sum = variance_sum + (t - mean)^2
    end
    local std_dev = math.sqrt(variance_sum / (n - 1))
    local variance_percent = (std_dev / mean) * 100
    
    return {
        mean = mean,
        std_dev = std_dev,
        variance_percent = variance_percent,
        min = times[1],
        max = times[n],
        n = n,
        reliable = variance_percent <= 10.0  -- 10% variance target (more realistic)
    }
end

local function run_statistical_test(name, command, target_runs)
    print(string.format("Testing %s (%d runs)...", name, target_runs))
    
    local times = {}
    
    -- Warmup runs
    for i = 1, 3 do
        run_command(command)
    end
    
    -- Actual benchmark runs
    for i = 1, target_runs do
        local start = precise_time()
        local output, code = run_command(command)
        if code ~= 0 then
            return nil, string.format("Command failed: %s", command)
        end
        local elapsed = (precise_time() - start) * 1000000
        table.insert(times, elapsed)
        
        -- Progress indicator for longer tests
        if i % 5 == 0 then
            local partial_stats = calculate_stats({table.unpack(times, 1, i)})
            io.write(string.format("  %d/%d: %.1fμs (%.1f%%)\r", i, target_runs, partial_stats.mean, partial_stats.variance_percent))
            io.flush()
        end
    end
    
    print()  -- New line after progress
    local stats = calculate_stats(times)
    
    local status = stats.reliable and "✓" or "⚠"
    print(string.format("  %s %s: %.1f ± %.1f μs (%.1f%% variance)", 
        status, name, stats.mean, stats.std_dev, stats.variance_percent))
    
    return stats, nil
end

-- Main execution
print("=== Reliable Statistical Benchmark ===\n")

print("Building rgcidr...")
local build_out, build_code = run_command("zig build -Doptimize=ReleaseFast")
if build_code ~= 0 then
    print("✗ rgcidr build failed")
    os.exit(1)
end

-- Check grepcidr
local grepcidr_check, grepcidr_code = run_command("which grepcidr")
if grepcidr_code ~= 0 then
    print("✗ grepcidr not available")
    os.exit(1)
end

print("✓ Both tools available")
print("Target: 20 runs each, <10% variance for reliable results\n")

-- Test scenarios with fixed seeds for reproducibility
local scenarios = {
    {
        name = "Small Dataset (500 IPs)",
        pattern = "192.168.0.0/16",
        seed = 12345,
        size = 500
    },
    {
        name = "Medium Dataset (1500 IPs)", 
        pattern = "10.0.0.0/8",
        seed = 23456,
        size = 1500
    },
    {
        name = "Large Dataset (3000 IPs)",
        pattern = "172.16.0.0/12",
        seed = 34567,  
        size = 3000
    },
    {
        name = "Multiple Patterns",
        pattern = "192.168.0.0/16,10.0.0.0/8,172.16.0.0/12",
        seed = 45678,
        size = 2000
    }
}

local results = {}

for _, scenario in ipairs(scenarios) do
    print(string.format("=== %s ===", scenario.name))
    
    -- Generate test data
    math.randomseed(scenario.seed)
    local ips = {}
    for i = 1, scenario.size do
        if i <= scenario.size * 0.3 then  -- 30% matches
            if scenario.pattern:find("192.168") then
                table.insert(ips, string.format("192.168.%d.%d", math.random(0,255), math.random(1,254)))
            elseif scenario.pattern:find("10.0") then
                table.insert(ips, string.format("10.%d.%d.%d", math.random(0,255), math.random(0,255), math.random(1,254)))
            elseif scenario.pattern:find("172.16") then
                table.insert(ips, string.format("172.%d.%d.%d", math.random(16,31), math.random(0,255), math.random(1,254)))
            else
                -- Multiple patterns - mix them
                local choice = math.random(1,3)
                if choice == 1 then
                    table.insert(ips, string.format("192.168.%d.%d", math.random(0,255), math.random(1,254)))
                elseif choice == 2 then
                    table.insert(ips, string.format("10.%d.%d.%d", math.random(0,255), math.random(0,255), math.random(1,254)))
                else
                    table.insert(ips, string.format("172.%d.%d.%d", math.random(16,31), math.random(0,255), math.random(1,254)))
                end
            end
        else  -- 70% non-matches
            table.insert(ips, string.format("%d.%d.%d.%d", 
                math.random(1,255), math.random(0,255), math.random(0,255), math.random(1,254)))
        end
    end
    
    local temp_file = os.tmpname()
    local f = io.open(temp_file, "w")
    f:write(table.concat(ips, "\n"))
    f:close()
    
    -- Test both tools
    local rgcidr_cmd = string.format('./zig-out/bin/rgcidr "%s" %s > /dev/null', scenario.pattern, temp_file)
    local grepcidr_cmd = string.format('grepcidr "%s" %s > /dev/null', scenario.pattern, temp_file)
    
    local rgcidr_stats = run_statistical_test("rgcidr", rgcidr_cmd, 20)
    local grepcidr_stats = run_statistical_test("grepcidr", grepcidr_cmd, 20)
    
    -- Calculate performance difference
    local performance = "equivalent"
    local significant = false
    if rgcidr_stats and grepcidr_stats then
        local diff_percent = ((grepcidr_stats.mean - rgcidr_stats.mean) / grepcidr_stats.mean) * 100
        -- Simple significance test: difference > combined standard errors
        local combined_se = math.sqrt((rgcidr_stats.std_dev^2 + grepcidr_stats.std_dev^2) / 20)
        local diff_magnitude = math.abs(grepcidr_stats.mean - rgcidr_stats.mean)
        
        if diff_magnitude > 2 * combined_se then  -- ~95% confidence
            significant = true
            if diff_percent > 0 then
                performance = string.format("+%.1f%% faster", diff_percent)
            else
                performance = string.format("%.1f%% slower", -diff_percent)
            end
        end
    end
    
    table.insert(results, {
        name = scenario.name,
        rgcidr = rgcidr_stats,
        grepcidr = grepcidr_stats,
        performance = performance,
        significant = significant
    })
    
    print()
    os.remove(temp_file)
end

-- Final report
print("=== Statistical Performance Report (20 runs each) ===")
print(string.format("%-25s | %-18s | %-18s | %-12s | Significant", 
    "Benchmark", "rgcidr", "grepcidr", "rgcidr vs grepcidr"))
print(string.format("%-25s | %-18s | %-18s | %-12s | -----------", 
    "-------------------------", "------------------", "------------------", "------------"))

for _, result in ipairs(results) do
    local rgcidr_str = result.rgcidr and 
        string.format("%s%.1f±%.1fμs", result.rgcidr.reliable and "✓" or "⚠", result.rgcidr.mean, result.rgcidr.std_dev) or "FAILED"
    local grepcidr_str = result.grepcidr and 
        string.format("%s%.1f±%.1fμs", result.grepcidr.reliable and "✓" or "⚠", result.grepcidr.mean, result.grepcidr.std_dev) or "FAILED"
    
    print(string.format("%-25s | %-18s | %-18s | %-12s | %s", 
        result.name, rgcidr_str, grepcidr_str, result.performance, 
        result.significant and "Yes" or "No"))
end

print("\nReliability Summary:")
local reliable_count = 0
local total_tests = #results * 2
for _, result in ipairs(results) do
    if result.rgcidr and result.rgcidr.reliable then reliable_count = reliable_count + 1 end
    if result.grepcidr and result.grepcidr.reliable then reliable_count = reliable_count + 1 end
end

print(string.format("  Reliable tests: %d/%d (%.1f%%)", reliable_count, total_tests, (reliable_count/total_tests)*100))
print("  ✓ = <10% variance (reliable)")
print("  ⚠ = >10% variance (less reliable)")
print("  Significance based on 95% confidence intervals")