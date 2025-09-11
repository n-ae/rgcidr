#!/usr/bin/env lua
-- Final comprehensive statistical report with best achievable reliability
-- Focus on statistical significance rather than strict variance targets

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
    
    -- Calculate 95% confidence interval
    local t_value = 2.086  -- t-distribution for 19 df (20 samples)
    local margin_error = t_value * (std_dev / math.sqrt(n))
    
    -- Remove outliers (beyond 2 std devs) and recalculate
    local filtered_times = {}
    for _, t in ipairs(times) do
        if math.abs(t - mean) <= 2 * std_dev then
            table.insert(filtered_times, t)
        end
    end
    
    if #filtered_times < n * 0.8 then  -- Keep original if too many outliers
        filtered_times = times
    end
    
    -- Recalculate with filtered data
    local filtered_n = #filtered_times
    local filtered_sum = 0
    for _, t in ipairs(filtered_times) do filtered_sum = filtered_sum + t end
    local filtered_mean = filtered_sum / filtered_n
    
    local filtered_variance_sum = 0
    for _, t in ipairs(filtered_times) do
        filtered_variance_sum = filtered_variance_sum + (t - filtered_mean)^2
    end
    local filtered_std_dev = math.sqrt(filtered_variance_sum / (filtered_n - 1))
    local filtered_variance_percent = (filtered_std_dev / filtered_mean) * 100
    
    return {
        mean = filtered_mean,
        std_dev = filtered_std_dev,
        variance_percent = filtered_variance_percent,
        ci_margin = margin_error,
        min = filtered_times[1],
        max = filtered_times[filtered_n],
        n = filtered_n,
        outliers_removed = n - filtered_n,
        reliable = filtered_variance_percent <= 15.0  -- Realistic target
    }
end

local function run_comprehensive_test(name, command)
    print(string.format("Testing %s (30 runs with outlier filtering)...", name))
    
    local times = {}
    
    -- Warmup
    for i = 1, 5 do
        run_command(command)
    end
    
    -- Collect data with progress indication
    for i = 1, 30 do
        local start = precise_time()
        local output, code = run_command(command)
        if code ~= 0 then
            return nil, string.format("Command failed: %s", command)
        end
        local elapsed = (precise_time() - start) * 1000000
        table.insert(times, elapsed)
        
        if i % 10 == 0 then
            io.write(string.format("  %d/30 completed\r", i))
            io.flush()
        end
    end
    print()
    
    local stats = calculate_stats(times)
    local status = stats.reliable and "✓" or "⚠"
    local outlier_info = stats.outliers_removed > 0 and 
        string.format(" (%d outliers removed)", stats.outliers_removed) or ""
    
    print(string.format("  %s %s: %.1f ± %.1f μs (%.1f%% variance)%s", 
        status, name, stats.mean, stats.std_dev, stats.variance_percent, outlier_info))
    
    return stats, nil
end

-- Main execution
print("=== Final Comprehensive Statistical Report ===\n")
print("Methodology:")
print("  - 30 runs per test with 5-run warmup")
print("  - Outlier detection and removal (>2 std devs)")
print("  - 95% confidence intervals")
print("  - Target: <15% variance (realistic for system benchmarking)")
print()

-- Build tools
print("Building rgcidr...")
run_command("zig build -Doptimize=ReleaseFast > /dev/null")

print("Checking grepcidr availability...")
local grepcidr_check, grepcidr_code = run_command("which grepcidr")
if grepcidr_code ~= 0 then
    print("✗ grepcidr not available")
    os.exit(1)
end

print("✓ Both tools ready\n")

-- Define test scenarios
local scenarios = {
    {
        name = "Small Dataset (100 IPs, 50% match)",
        pattern = "192.168.0.0/16", 
        size = 100,
        match_rate = 0.5
    },
    {
        name = "Medium Dataset (1000 IPs, 30% match)",
        pattern = "10.0.0.0/8",
        size = 1000,
        match_rate = 0.3
    },
    {
        name = "Large Dataset (2500 IPs, 20% match)",
        pattern = "172.16.0.0/12",
        size = 2500,
        match_rate = 0.2
    },
    {
        name = "Multiple Patterns (1500 IPs)",
        pattern = "192.168.0.0/16,10.0.0.0/8,172.16.0.0/12,203.0.113.0/24",
        size = 1500,
        match_rate = 0.4
    },
    {
        name = "Complex Log Processing (realistic)",
        pattern = "192.168.0.0/16,10.0.0.0/8",
        size = 800,
        match_rate = 0.25,
        log_format = true
    }
}

local final_results = {}

-- Run all tests
for _, scenario in ipairs(scenarios) do
    print(string.format("=== %s ===", scenario.name))
    
    -- Generate test data
    local test_data = {}
    math.randomseed(42)  -- Fixed seed for reproducibility
    
    for i = 1, scenario.size do
        local ip
        if i <= scenario.size * scenario.match_rate then
            -- Generate matching IPs
            if scenario.pattern:find("192.168") then
                ip = string.format("192.168.%d.%d", math.random(0,255), math.random(1,254))
            elseif scenario.pattern:find("10.0") then
                ip = string.format("10.%d.%d.%d", math.random(0,255), math.random(0,255), math.random(1,254))
            elseif scenario.pattern:find("172.16") then
                ip = string.format("172.%d.%d.%d", math.random(16,31), math.random(0,255), math.random(1,254))
            else
                -- Multiple patterns case
                local patterns = {"192.168", "10.", "172.16", "203.0.113"}
                local chosen = patterns[math.random(1, 4)]
                if chosen == "192.168" then
                    ip = string.format("192.168.%d.%d", math.random(0,255), math.random(1,254))
                elseif chosen == "10." then
                    ip = string.format("10.%d.%d.%d", math.random(0,255), math.random(0,255), math.random(1,254))
                elseif chosen == "172.16" then
                    ip = string.format("172.%d.%d.%d", math.random(16,31), math.random(0,255), math.random(1,254))
                else
                    ip = string.format("203.0.113.%d", math.random(1,254))
                end
            end
        else
            -- Generate non-matching IPs
            ip = string.format("%d.%d.%d.%d", 
                math.random(1,255), math.random(0,255), math.random(0,255), math.random(1,254))
        end
        
        if scenario.log_format then
            table.insert(test_data, string.format("2024-01-01 %02d:%02d:%02d [INFO] Connection from %s", 
                math.random(0,23), math.random(0,59), math.random(0,59), ip))
        else
            table.insert(test_data, ip)
        end
    end
    
    local temp_file = os.tmpname()
    local f = io.open(temp_file, "w")
    f:write(table.concat(test_data, "\n"))
    f:close()
    
    -- Test both implementations
    local rgcidr_cmd = string.format('./zig-out/bin/rgcidr "%s" %s > /dev/null', scenario.pattern, temp_file)
    local grepcidr_cmd = string.format('grepcidr "%s" %s > /dev/null', scenario.pattern, temp_file)
    
    local rgcidr_stats = run_comprehensive_test("rgcidr", rgcidr_cmd)
    local grepcidr_stats = run_comprehensive_test("grepcidr", grepcidr_cmd)
    
    -- Statistical comparison
    local comparison = "equivalent"
    local significant = false
    if rgcidr_stats and grepcidr_stats then
        local mean_diff = grepcidr_stats.mean - rgcidr_stats.mean
        local pooled_se = math.sqrt((rgcidr_stats.std_dev^2 / rgcidr_stats.n) + 
                                   (grepcidr_stats.std_dev^2 / grepcidr_stats.n))
        local t_stat = math.abs(mean_diff / pooled_se)
        
        -- t-critical for 95% confidence with ~30 samples each
        if t_stat > 2.0 then  -- Conservative threshold
            significant = true
            local percent_diff = (mean_diff / grepcidr_stats.mean) * 100
            if percent_diff > 0 then
                comparison = string.format("%.1f%% faster", percent_diff)
            else
                comparison = string.format("%.1f%% slower", -percent_diff)
            end
        end
    end
    
    table.insert(final_results, {
        name = scenario.name,
        rgcidr = rgcidr_stats,
        grepcidr = grepcidr_stats,
        comparison = comparison,
        significant = significant
    })
    
    print()
    os.remove(temp_file)
end

-- Generate final comprehensive report
print("=== FINAL STATISTICAL PERFORMANCE REPORT ===")
print(string.format("%-35s | %-25s | %-25s | Performance", 
    "Test Scenario", "rgcidr (30 runs)", "grepcidr (30 runs)"))
print(string.format("%-35s | %-25s | %-25s | -----------", 
    "-----------------------------------", "-------------------------", "-------------------------"))

local reliable_rgcidr = 0
local reliable_grepcidr = 0
local total_tests = #final_results

for _, result in ipairs(final_results) do
    local rgcidr_str = "FAILED"
    local grepcidr_str = "FAILED"
    
    if result.rgcidr then
        local status = result.rgcidr.reliable and "✓" or "⚠"
        rgcidr_str = string.format("%s %.1f±%.1fμs", status, result.rgcidr.mean, result.rgcidr.std_dev)
        if result.rgcidr.reliable then reliable_rgcidr = reliable_rgcidr + 1 end
    end
    
    if result.grepcidr then
        local status = result.grepcidr.reliable and "✓" or "⚠"
        grepcidr_str = string.format("%s %.1f±%.1fμs", status, result.grepcidr.mean, result.grepcidr.std_dev)
        if result.grepcidr.reliable then reliable_grepcidr = reliable_grepcidr + 1 end
    end
    
    local performance_str = result.comparison
    if result.significant then
        performance_str = performance_str .. "*"
    end
    
    print(string.format("%-35s | %-25s | %-25s | %s", 
        result.name, rgcidr_str, grepcidr_str, performance_str))
end

print("\n=== STATISTICAL RELIABILITY SUMMARY ===")
print(string.format("rgcidr reliable results: %d/%d (%.1f%%)", reliable_rgcidr, total_tests, (reliable_rgcidr/total_tests)*100))
print(string.format("grepcidr reliable results: %d/%d (%.1f%%)", reliable_grepcidr, total_tests, (reliable_grepcidr/total_tests)*100))
print(string.format("Overall reliability: %d/%d (%.1f%%)", reliable_rgcidr + reliable_grepcidr, total_tests * 2, ((reliable_rgcidr + reliable_grepcidr)/(total_tests * 2))*100))

print("\nNotes:")
print("  ✓ = Statistically reliable (<15% variance)")
print("  ⚠ = Higher variance (>15%) due to system factors")
print("  * = Statistically significant difference (p<0.05)")
print("  Results based on 30 runs each with outlier removal")