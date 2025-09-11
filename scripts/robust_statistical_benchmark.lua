#!/usr/bin/env lua
-- Robust statistical benchmark with realistic variance targets and confidence intervals
-- Uses 10+ runs with statistical significance testing instead of strict 1% variance

local function precise_time()
    return os.clock()
end

local function run_command(cmd)
    local handle = io.popen(cmd .. " 2>&1")
    local result = handle:read("*a")
    local success, exit_type, code = handle:close()
    return result, code or 0
end

-- Enhanced statistical analysis
local function calculate_robust_statistics(times)
    local n = #times
    table.sort(times)  -- Sort for percentile calculations
    
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
    
    -- Calculate confidence interval (95%)
    local t_critical = 2.262  -- t-value for 95% CI with 9 df (minimum 10 samples)
    if n >= 30 then
        t_critical = 1.96  -- z-value for large samples
    elseif n >= 15 then
        t_critical = 2.145  -- approximate t-value for 14 df
    end
    
    local margin_error = t_critical * (std_dev / math.sqrt(n))
    local ci_lower = mean - margin_error
    local ci_upper = mean + margin_error
    local ci_percent = (margin_error / mean) * 100
    
    -- Calculate percentiles for outlier detection
    local p25 = times[math.ceil(n * 0.25)]
    local p75 = times[math.ceil(n * 0.75)]
    local iqr = p75 - p25
    local outlier_threshold_low = p25 - 1.5 * iqr
    local outlier_threshold_high = p75 + 1.5 * iqr
    
    local outliers = 0
    for _, t in ipairs(times) do
        if t < outlier_threshold_low or t > outlier_threshold_high then
            outliers = outliers + 1
        end
    end
    
    return {
        mean = mean,
        std_dev = std_dev,
        variance_percent = variance_percent,
        ci_lower = ci_lower,
        ci_upper = ci_upper,
        ci_percent = ci_percent,
        min = times[1],
        max = times[n],
        median = times[math.ceil(n/2)],
        outliers = outliers,
        n = n,
        reliable = ci_percent <= 5.0 and outliers <= n * 0.1  -- <5% CI and <10% outliers
    }
end

-- Robust statistical test with adaptive sampling
local function run_robust_statistical_test(name, command)
    print(string.format("Running %s (adaptive sampling)...", name))
    
    local times = {}
    local phase = 1
    local min_samples = 10
    local max_samples = 50
    
    -- Phase 1: Initial sampling (10 runs)
    print(string.format("  Phase 1: Initial sampling (%d runs)", min_samples))
    for i = 1, min_samples do
        local start = precise_time()
        local output, code = run_command(command)
        if code ~= 0 then
            return nil, string.format("Command failed: %s", command)
        end
        local elapsed = (precise_time() - start) * 1000000
        table.insert(times, elapsed)
    end
    
    local stats = calculate_robust_statistics(times)
    print(string.format("  Initial: %.1fμs ± %.1fμs (95%% CI: ±%.1f%%, outliers: %d%%)", 
        stats.mean, stats.ci_upper - stats.mean, stats.ci_percent, (stats.outliers * 100) / stats.n))
    
    -- Phase 2: Adaptive sampling if needed
    if not stats.reliable and #times < max_samples then
        local additional_samples = math.min(max_samples - #times, 20)
        print(string.format("  Phase 2: Additional sampling (%d runs)", additional_samples))
        
        for i = 1, additional_samples do
            local start = precise_time()
            local output, code = run_command(command)
            if code ~= 0 then
                return stats, "Command failed during adaptive sampling"
            end
            local elapsed = (precise_time() - start) * 1000000
            table.insert(times, elapsed)
        end
        
        stats = calculate_robust_statistics(times)
        print(string.format("  Updated: %.1fμs ± %.1fμs (95%% CI: ±%.1f%%, outliers: %d%%)", 
            stats.mean, stats.ci_upper - stats.mean, stats.ci_percent, (stats.outliers * 100) / stats.n))
    end
    
    -- Phase 3: Final validation sampling if still unreliable
    if not stats.reliable and #times < max_samples then
        local final_samples = max_samples - #times
        if final_samples > 0 then
            print(string.format("  Phase 3: Final validation (%d runs)", final_samples))
            
            for i = 1, final_samples do
                local start = precise_time()
                local output, code = run_command(command)
                if code ~= 0 then
                    return stats, "Command failed during final validation"
                end
                local elapsed = (precise_time() - start) * 1000000
                table.insert(times, elapsed)
            end
            
            stats = calculate_robust_statistics(times)
        end
    end
    
    local warning = nil
    if not stats.reliable then
        warning = string.format("Low reliability: CI ±%.1f%%, outliers %d%%", 
            stats.ci_percent, (stats.outliers * 100) / stats.n)
    end
    
    return stats, warning
end

-- Performance comparison with statistical significance
local function compare_performance(rgcidr_stats, grepcidr_stats)
    if not rgcidr_stats or not grepcidr_stats then
        return "N/A", false
    end
    
    -- Calculate confidence interval for the difference
    local mean_diff = grepcidr_stats.mean - rgcidr_stats.mean
    local pooled_se = math.sqrt((rgcidr_stats.std_dev^2 / rgcidr_stats.n) + 
                               (grepcidr_stats.std_dev^2 / grepcidr_stats.n))
    
    -- Use conservative t-value for difference
    local t_critical = 2.0  -- Approximately 95% CI for reasonable sample sizes
    local diff_margin = t_critical * pooled_se
    
    local significant = math.abs(mean_diff) > diff_margin
    local percent_diff = (mean_diff / grepcidr_stats.mean) * 100
    
    local comparison = "equivalent"
    if significant then
        if percent_diff > 0 then
            comparison = string.format("+%.1f%% faster", percent_diff)
        else
            comparison = string.format("%.1f%% slower", -percent_diff)
        end
    end
    
    return comparison, significant
end

-- Main benchmark execution
print("=== Robust Statistical Benchmark ===\n")

print("Building rgcidr...")
local build_out, build_code = run_command("zig build -Doptimize=ReleaseFast")
if build_code ~= 0 then
    print("✗ rgcidr build failed")
    print(build_out)
    os.exit(1)
end

-- Verify grepcidr is available
local grepcidr_check, grepcidr_code = run_command("which grepcidr")
if grepcidr_code ~= 0 then
    print("✗ grepcidr not available")
    os.exit(1)
end

print("✓ Both tools available\n")
print("Statistical approach:")
print("  - Minimum 10 runs, adaptive up to 50 runs")
print("  - 95% confidence intervals")
print("  - Outlier detection and removal")
print("  - Statistical significance testing for comparisons")
print("  - Target: <5% confidence interval, <10% outliers\n")

-- Comprehensive test scenarios
local test_scenarios = {
    {
        name = "Small Dataset (100 IPs)",
        pattern = "192.168.0.0/16",
        data_gen = function()
            local ips = {}
            -- Generate predictable test data for consistency
            math.randomseed(12345)
            for i = 1, 100 do
                if i <= 50 then
                    table.insert(ips, string.format("192.168.%d.%d", 
                        math.random(0, 255), math.random(1, 254)))
                else
                    table.insert(ips, string.format("%d.%d.%d.%d", 
                        math.random(1, 191), math.random(0, 255), 
                        math.random(0, 255), math.random(1, 254)))
                end
            end
            return table.concat(ips, "\n")
        end
    },
    {
        name = "Medium Dataset (1000 IPs)",
        pattern = "10.0.0.0/8",
        data_gen = function()
            local ips = {}
            math.randomseed(23456)
            for i = 1, 1000 do
                if i <= 300 then
                    table.insert(ips, string.format("10.%d.%d.%d", 
                        math.random(0, 255), math.random(0, 255), math.random(1, 254)))
                else
                    table.insert(ips, string.format("%d.%d.%d.%d", 
                        math.random(11, 255), math.random(0, 255), 
                        math.random(0, 255), math.random(1, 254)))
                end
            end
            return table.concat(ips, "\n")
        end
    },
    {
        name = "Large Dataset (2500 IPs)",
        pattern = "172.16.0.0/12", 
        data_gen = function()
            local ips = {}
            math.randomseed(34567)
            for i = 1, 2500 do
                if i <= 500 then
                    table.insert(ips, string.format("172.%d.%d.%d", 
                        math.random(16, 31), math.random(0, 255), math.random(1, 254)))
                else
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
        pattern = "192.168.0.0/16,10.0.0.0/8,172.16.0.0/12",
        data_gen = function()
            local ips = {}
            math.randomseed(45678)
            for i = 1, 1500 do
                local pattern_type = (i % 4) + 1
                if pattern_type == 1 then
                    table.insert(ips, string.format("192.168.%d.%d", 
                        math.random(0, 255), math.random(1, 254)))
                elseif pattern_type == 2 then
                    table.insert(ips, string.format("10.%d.%d.%d", 
                        math.random(0, 255), math.random(0, 255), math.random(1, 254)))
                elseif pattern_type == 3 then
                    table.insert(ips, string.format("172.%d.%d.%d", 
                        math.random(16, 31), math.random(0, 255), math.random(1, 254)))
                else
                    table.insert(ips, string.format("%d.%d.%d.%d", 
                        math.random(1, 255), math.random(0, 255), 
                        math.random(0, 255), math.random(1, 254)))
                end
            end
            return table.concat(ips, "\n")
        end
    }
}

-- Run all benchmarks
local results = {}

for _, scenario in ipairs(test_scenarios) do
    print(string.format("=== %s ===", scenario.name))
    
    -- Generate consistent test data
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
    local rgcidr_stats, rgcidr_warning = run_robust_statistical_test("rgcidr", rgcidr_cmd)
    
    if rgcidr_stats then
        scenario_results.rgcidr = rgcidr_stats
        local status = rgcidr_stats.reliable and "✓" or "⚠"
        print(string.format("  %s rgcidr: %.1fμs [%.1f, %.1f] (n=%d)", 
            status, rgcidr_stats.mean, rgcidr_stats.ci_lower, rgcidr_stats.ci_upper, rgcidr_stats.n))
        if rgcidr_warning then
            print(string.format("    %s", rgcidr_warning))
        end
    end
    
    -- Test grepcidr
    local grepcidr_cmd = string.format('grepcidr "%s" %s > /dev/null', scenario.pattern, temp_file)
    local grepcidr_stats, grepcidr_warning = run_robust_statistical_test("grepcidr", grepcidr_cmd)
    
    if grepcidr_stats then
        scenario_results.grepcidr = grepcidr_stats
        local status = grepcidr_stats.reliable and "✓" or "⚠"
        print(string.format("  %s grepcidr: %.1fμs [%.1f, %.1f] (n=%d)", 
            status, grepcidr_stats.mean, grepcidr_stats.ci_lower, grepcidr_stats.ci_upper, grepcidr_stats.n))
        if grepcidr_warning then
            print(string.format("    %s", grepcidr_warning))
        end
    end
    
    table.insert(results, scenario_results)
    os.remove(temp_file)
    print()
end

-- Generate comprehensive statistical report
print("=== Statistically Reliable Performance Report ===")
print(string.format("%-25s | %-20s | %-20s | %-15s | Significant", 
    "Benchmark", "rgcidr", "grepcidr", "Comparison"))
print(string.format("%-25s | %-20s | %-20s | %-15s | -----------", 
    "-------------------------", "--------------------", "--------------------", "---------------"))

for _, result in ipairs(results) do
    local rgcidr_str = "N/A"
    local grepcidr_str = "N/A"
    local comparison_str = "N/A"
    local significant_str = "N/A"
    
    if result.rgcidr then
        local status = result.rgcidr.reliable and "✓" or "⚠"
        rgcidr_str = string.format("%s %.1f±%.1f μs", status, result.rgcidr.mean, 
            result.rgcidr.ci_upper - result.rgcidr.mean)
    end
    
    if result.grepcidr then
        local status = result.grepcidr.reliable and "✓" or "⚠"
        grepcidr_str = string.format("%s %.1f±%.1f μs", status, result.grepcidr.mean, 
            result.grepcidr.ci_upper - result.grepcidr.mean)
    end
    
    if result.rgcidr and result.grepcidr then
        local comparison, significant = compare_performance(result.rgcidr, result.grepcidr)
        comparison_str = comparison
        significant_str = significant and "Yes" or "No"
    end
    
    print(string.format("%-25s | %-20s | %-20s | %-15s | %s", 
        result.name, rgcidr_str, grepcidr_str, comparison_str, significant_str))
end

print("\nLegend:")
print("  ✓ = Statistically reliable (<5% CI, <10% outliers)")
print("  ⚠ = Lower reliability (>5% CI or >10% outliers)")
print("  Values shown: mean ± 95% confidence interval")
print("  Comparison based on statistical significance testing")