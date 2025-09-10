#!/usr/bin/env lua
-- test_regression.lua : Test the regression benchmark functionality without switching branches
-- This simulates regression testing by running benchmarks twice and adding artificial variance

local function run_command(cmd)
    local handle = io.popen(cmd .. " 2>&1")
    local result = handle:read("*a")
    local success, exit_type, exit_code = handle:close()
    return result, exit_code or 0
end

local function format_time(microseconds)
    if microseconds < 1000 then
        return string.format("%.0fμs", microseconds)
    elseif microseconds < 1000000 then
        return string.format("%.1fms", microseconds / 1000)
    else
        return string.format("%.2fs", microseconds / 1000000)
    end
end

local function run_benchmarks()
    print("Building and running benchmarks...")
    local result, exit_code = run_command("zig build -Doptimize=ReleaseFast > /dev/null && lua scripts/test.lua --benchmark --csv")
    -- Note: benchmark may return exit code 1 if some tests fail, but we can still parse the results
    if exit_code ~= 0 and exit_code ~= 1 then
        return nil, "Failed to run benchmarks"
    end
    
    -- Parse CSV output
    local benchmarks = {}
    local lines = {}
    for line in result:gmatch("[^\n]+") do
        table.insert(lines, line)
    end
    
    -- Skip header line
    for i = 2, #lines do
        local line = lines[i]
        local fields = {}
        for field in line:gmatch("[^,]+") do
            table.insert(fields, field)
        end
        
        if #fields >= 5 then
            local uat = fields[1]
            local test_name = fields[2]
            local time_str = fields[5]
            local time_microseconds = tonumber(time_str)
            
            -- Only collect rgcidr results (not grepcidr) for benchmarks
            if time_microseconds and test_name:match("^bench_") and uat == "rgcidr" then
                benchmarks[test_name] = time_microseconds
            end
        end
    end
    
    return benchmarks, nil
end

local function simulate_baseline(current_results)
    local baseline = {}
    math.randomseed(os.time())
    
    for test_name, current_time in pairs(current_results) do
        -- Add random variance: -5% to +10% to simulate different performance
        local variance = (math.random() * 0.15) - 0.05  -- -5% to +10%
        local baseline_time = current_time * (1.0 + variance)
        baseline[test_name] = baseline_time
    end
    
    return baseline
end

local function compare_and_print(current_results, baseline_results)
    print("=== Simulated Regression Test Demo ===")
    print("Current branch: feature-branch (simulated)")
    print("Baseline branch: main (simulated)")
    print("")
    
    local faster_count = 0
    local slower_count = 0
    local same_count = 0
    local max_regression = 0
    local max_improvement = 0
    
    local comparisons = {}
    for test_name, current_time in pairs(current_results) do
        if baseline_results[test_name] then
            local baseline_time = baseline_results[test_name]
            local ratio = current_time / baseline_time
            local percent_change = (ratio - 1.0) * 100
            
            local status
            if math.abs(percent_change) < 2.0 then
                status = "same"
            elseif percent_change > 0 then
                status = "slower"
            else
                status = "faster"
            end
            
            table.insert(comparisons, {
                test_name = test_name,
                current_time = current_time,
                baseline_time = baseline_time,
                percent_change = percent_change,
                status = status
            })
        end
    end
    
    -- Sort by test name
    table.sort(comparisons, function(a, b) return a.test_name < b.test_name end)
    
    for _, comp in ipairs(comparisons) do
        local symbol
        if comp.status == "faster" then
            symbol = "🚀"
            faster_count = faster_count + 1
            max_improvement = math.max(max_improvement, -comp.percent_change)
        elseif comp.status == "slower" then
            symbol = "🐌" 
            slower_count = slower_count + 1
            max_regression = math.max(max_regression, comp.percent_change)
        else
            symbol = "="
            same_count = same_count + 1
        end
        
        print(string.format("%s %-25s %s -> %s (%.1f%% %s)",
            symbol, comp.test_name,
            format_time(comp.baseline_time),
            format_time(comp.current_time),
            math.abs(comp.percent_change),
            comp.status == "same" and "change" or comp.status))
    end
    
    print("")
    print("=== Summary ===")
    print(string.format("Faster:     %d tests", faster_count))
    print(string.format("Same:       %d tests", same_count))
    print(string.format("Slower:     %d tests", slower_count))
    
    if max_improvement > 0 then
        print(string.format("Best improvement: %.1f%% faster", max_improvement))
    end
    if max_regression > 0 then
        print(string.format("Worst regression: %.1f%% slower", max_regression))
    end
    
    if slower_count > 0 then
        print("")
        print("⚠️  Performance regressions detected!")
    elseif faster_count > 0 then
        print("")
        print("✅ Performance improvements detected!")
    else
        print("")
        print("✅ No significant performance changes")
    end
    
    print("")
    print("Note: This is a simulated demo. Use 'zig build bench-regression' for real regression testing.")
end

-- Main execution
local current_results, err = run_benchmarks()
if not current_results then
    print("Error: " .. err)
    os.exit(1)
end

if next(current_results) == nil then
    print("No benchmark results found")
    os.exit(1)
end

local baseline_results = simulate_baseline(current_results)
compare_and_print(current_results, baseline_results)
