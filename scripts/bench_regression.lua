#!/usr/bin/env lua
-- bench_regression.lua : Compare current branch performance against main branch baseline
-- Usage: lua scripts/bench_regression.lua [baseline-ref] [--csv]
-- 
-- This script:
-- 1. Builds current branch with ReleaseFast
-- 2. Stashes current changes (if any)
-- 3. Checks out baseline branch (default: main)
-- 4. Builds baseline with ReleaseFast
-- 5. Runs benchmarks on both versions
-- 6. Compares results and shows regression/improvement
-- 7. Restores original branch state

local baseline_ref = arg[1] or "main"
local csv_mode = false

-- Check for --csv flag
for i = 1, #arg do
    if arg[i] == "--csv" then
        csv_mode = true
        break
    end
end

local function run_command(cmd)
    local handle = io.popen(cmd .. " 2>&1")
    local result = handle:read("*a")
    local success, exit_type, exit_code = handle:close()
    return result, exit_code or 0
end

local function run_command_silent(cmd)
    local handle = io.popen(cmd .. " > /dev/null 2>&1")
    handle:read("*a")
    local success, exit_type, exit_code = handle:close()
    return exit_code or 0
end

local function get_current_branch()
    local result, exit_code = run_command("git branch --show-current")
    if exit_code ~= 0 then
        return nil
    end
    return result:gsub("\n", "")
end

local function get_git_status()
    local result, exit_code = run_command("git status --porcelain")
    return result:gsub("\n", ""), exit_code == 0
end

local function has_uncommitted_changes()
    local status = get_git_status()
    return status ~= ""
end

local function stash_changes()
    local exit_code = run_command_silent("git stash push -m 'benchmark_regression_temp_stash'")
    return exit_code == 0
end

local function restore_stash()
    run_command_silent("git stash pop")
end

local function checkout_branch(branch)
    local exit_code = run_command_silent("git checkout " .. branch)
    return exit_code == 0
end

local function build_rgcidr()
    local result, exit_code = run_command("zig build -Doptimize=ReleaseFast")
    return exit_code == 0, result
end

local function run_benchmarks()
    -- Run benchmark tests and capture timing data
    local result, exit_code = run_command("lua scripts/test.lua --benchmark --csv")
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

local function compare_benchmarks(current_results, baseline_results)
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
                ratio = ratio,
                percent_change = percent_change,
                status = status
            })
        end
    end
    
    -- Sort by test name for consistent output
    table.sort(comparisons, function(a, b) return a.test_name < b.test_name end)
    
    return comparisons
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

local function print_results(comparisons, current_branch, baseline_ref)
    if csv_mode then
        -- CSV output
        print("test_name,current_branch,baseline_branch,current_time_us,baseline_time_us,ratio,percent_change,status")
        for _, comp in ipairs(comparisons) do
            print(string.format("%s,%s,%s,%.0f,%.0f,%.3f,%.1f,%s",
                comp.test_name, current_branch, baseline_ref,
                comp.current_time, comp.baseline_time,
                comp.ratio, comp.percent_change, comp.status))
        end
    else
        -- Human readable output
        print(string.format("=== Performance Regression Test ==="))
        print(string.format("Current branch: %s", current_branch))
        print(string.format("Baseline branch: %s", baseline_ref))
        print("")
        
        local faster_count = 0
        local slower_count = 0
        local same_count = 0
        local max_regression = 0
        local max_improvement = 0
        
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
    end
end

local function main()
    -- Get current state
    local current_branch = get_current_branch()
    if not current_branch then
        print("Error: Could not determine current git branch")
        os.exit(1)
    end
    
    local had_changes = has_uncommitted_changes()
    local stashed = false
    
    if not csv_mode then
        print("=== Performance Regression Benchmark ===")
        print("Current branch: " .. current_branch)
        print("Baseline: " .. baseline_ref)
        print("")
    end
    
    -- Build current version
    if not csv_mode then print("Building current version...") end
    local build_success, build_output = build_rgcidr()
    if not build_success then
        print("Error: Failed to build current version")
        print(build_output)
        os.exit(1)
    end
    
    -- Run benchmarks on current version
    if not csv_mode then print("Running benchmarks on current version...") end
    local current_results, err = run_benchmarks()
    if not current_results then
        print("Error: " .. err)
        os.exit(1)
    end
    
    -- Stash changes if needed
    if had_changes then
        if not csv_mode then print("Stashing uncommitted changes...") end
        stashed = stash_changes()
        if not stashed then
            print("Error: Failed to stash changes")
            os.exit(1)
        end
    end
    
    -- Checkout baseline
    if not csv_mode then print("Switching to baseline branch: " .. baseline_ref) end
    if not checkout_branch(baseline_ref) then
        print("Error: Failed to checkout baseline branch: " .. baseline_ref)
        if stashed then restore_stash() end
        os.exit(1)
    end
    
    -- Build baseline version
    if not csv_mode then print("Building baseline version...") end
    local baseline_build_success, baseline_build_output = build_rgcidr()
    if not baseline_build_success then
        print("Error: Failed to build baseline version")
        print(baseline_build_output)
        -- Restore original state
        checkout_branch(current_branch)
        if stashed then restore_stash() end
        os.exit(1)
    end
    
    -- Run benchmarks on baseline
    if not csv_mode then print("Running benchmarks on baseline version...") end
    local baseline_results, baseline_err = run_benchmarks()
    if not baseline_results then
        print("Error: " .. baseline_err)
        -- Restore original state
        checkout_branch(current_branch)
        if stashed then restore_stash() end
        os.exit(1)
    end
    
    -- Restore original state
    if not csv_mode then print("Restoring original branch state...") end
    checkout_branch(current_branch)
    if stashed then restore_stash() end
    
    -- Rebuild current version for consistency
    build_rgcidr()
    
    -- Compare results
    local comparisons = compare_benchmarks(current_results, baseline_results)
    if #comparisons == 0 then
        print("No benchmark tests found for comparison")
        os.exit(1)
    end
    
    -- Print results
    print_results(comparisons, current_branch, baseline_ref)
    
    -- Exit with error code if there are regressions
    local has_regressions = false
    for _, comp in ipairs(comparisons) do
        if comp.status == "slower" and comp.percent_change > 5.0 then
            has_regressions = true
            break
        end
    end
    
    if has_regressions then
        os.exit(1)
    else
        os.exit(0)
    end
end

-- Run the main function
main()
