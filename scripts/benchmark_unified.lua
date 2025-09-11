#!/usr/bin/env lua

-- Unified Benchmark Framework for rgcidr
-- Consolidates all benchmark functionality with consistent comparison between:
-- - rgcidr (current version)
-- - rgcidr-last-version (previous git tag)
-- - grepcidr (reference implementation)
--
-- Usage:
--   lua scripts/benchmark_unified.lua [options]
--
-- Options:
--   --quick           Run quick performance tests
--   --comprehensive   Run comprehensive benchmark suite
--   --regression      Compare against previous version only
--   --compare-all     Compare all three implementations
--   --profile         Include detailed profiling information
--   --csv             Output results in CSV format
--   --no-build        Skip building binaries (assume already built)
--   --help            Show this help message

local config = {
    quick = false,
    comprehensive = false,
    regression = false,
    compare_all = true,  -- Default to full comparison
    profile = false,
    csv = false,
    no_build = false,
    help = false
}

-- Parse command line arguments
local function parse_args(args)
    for _, arg in ipairs(args) do
        if arg == "--quick" then
            config.quick = true
        elseif arg == "--comprehensive" then
            config.comprehensive = true
        elseif arg == "--regression" then
            config.regression = true
            config.compare_all = false
        elseif arg == "--compare-all" then
            config.compare_all = true
        elseif arg == "--profile" then
            config.profile = true
        elseif arg == "--csv" then
            config.csv = true
        elseif arg == "--no-build" then
            config.no_build = true
        elseif arg == "--help" then
            config.help = true
        end
    end
end

-- Utility functions
local function run_command(cmd)
    local handle = io.popen(cmd .. " 2>&1")
    local result = handle:read("*a")
    local success, exit_type, code = handle:close()
    return result, code or 0
end

local function run_command_silent(cmd)
    local _, code = run_command(cmd .. " > /dev/null 2>&1")
    return code == 0
end

local function log(level, message)
    if not config.csv or level == "error" then
        print(message)
    end
end

local function precise_time()
    return os.clock()
end

local function write_temp_file(content)
    local filename = os.tmpname()
    local file = io.open(filename, "w")
    if not file then
        error("Could not create temp file: " .. filename)
    end
    file:write(content)
    file:close()
    return filename
end

-- Implementation detection and building
local Implementation = {}
Implementation.__index = Implementation

function Implementation.new(name, path, build_cmd)
    return setmetatable({
        name = name,
        path = path,
        build_cmd = build_cmd,
        available = false,
        build_time_us = 0
    }, Implementation)
end

function Implementation:check_availability()
    if not self.path or self.path == "" then
        self.available = false
        return false
    end
    
    -- Check if file exists and is executable
    local _, code = run_command("test -x " .. self.path)
    if code == 0 then
        self.available = true
        return true
    end
    
    -- For system commands, check if they're in PATH
    if not string.match(self.path, "/") then
        local _, code2 = run_command("which " .. self.path)
        if code2 == 0 then
            self.available = true
            return true
        end
    end
    
    self.available = false
    return false
end

function Implementation:build()
    if not self.build_cmd or config.no_build then
        return self:check_availability()
    end
    
    log("normal", "Building " .. self.name .. "...")
    local start = precise_time()
    local output, code = run_command(self.build_cmd)
    local elapsed = precise_time() - start
    
    self.build_time_us = elapsed * 1000000
    
    if code ~= 0 then
        log("error", "Failed to build " .. self.name .. ":")
        log("error", output)
        self.available = false
        return false
    end
    
    log("normal", string.format("✓ %s built successfully (%.1fμs)", self.name, self.build_time_us))
    return self:check_availability()
end

-- Get previous version tag
local function get_last_version_tag()
    local output, code = run_command("git describe --tags --abbrev=0 HEAD~1 2>/dev/null")
    if code == 0 then
        return output:gsub("%s+$", "")  -- trim whitespace
    end
    
    -- Fallback: try to get any previous tag
    output, code = run_command("git tag --sort=-version:refname | head -1")
    if code == 0 and output:gsub("%s+$", "") ~= "" then
        return output:gsub("%s+$", "")
    end
    
    return nil
end

-- Setup implementations
local function setup_implementations()
    local implementations = {}
    
    -- Current rgcidr
    implementations.rgcidr = Implementation.new(
        "rgcidr",
        "./zig-out/bin/rgcidr",
        "zig build -Doptimize=ReleaseFast"
    )
    
    -- Previous version rgcidr
    local last_tag = get_last_version_tag()
    if last_tag and config.compare_all then
        implementations.rgcidr_last = Implementation.new(
            "rgcidr-last-version",
            "./zig-out/bin/rgcidr-last",
            string.format([[
                git stash push -m "benchmark_stash_$(date +%%s)" && 
                git checkout %s && 
                zig build -Doptimize=ReleaseFast && 
                cp zig-out/bin/rgcidr zig-out/bin/rgcidr-last && 
                git checkout - && 
                git stash pop
            ]], last_tag)
        )
    end
    
    -- grepcidr (reference implementation)
    if config.compare_all then
        -- Use the fetch_grepcidr.lua script to get grepcidr
        local grepcidr_path_output, grepcidr_code = run_command("lua scripts/fetch_grepcidr.lua get")
        if grepcidr_code == 0 then
            local grepcidr_path = grepcidr_path_output:gsub("%s+$", "") -- trim whitespace
            implementations.grepcidr = Implementation.new(
                "grepcidr",
                grepcidr_path,
                nil  -- Already built by fetch script
            )
        end
    end
    
    return implementations
end

-- Benchmark execution
local BenchmarkResult = {}
BenchmarkResult.__index = BenchmarkResult

function BenchmarkResult.new(name, impl_name)
    return setmetatable({
        name = name,
        impl_name = impl_name,
        success = false,
        avg_us = 0,
        min_us = 0,
        max_us = 0,
        stddev_us = 0,
        iterations = 0,
        variance_percent = 0
    }, BenchmarkResult)
end

local function run_benchmark(impl, test_name, input_data, pattern, iterations)
    iterations = iterations or 100
    local result = BenchmarkResult.new(test_name, impl.name)
    result.iterations = iterations
    
    if not impl.available then
        log("error", string.format("⚠️  %s not available for %s", impl.name, test_name))
        return result
    end
    
    -- Create temp input file
    local temp_file = write_temp_file(input_data)
    local cmd = string.format("%s %s < %s > /dev/null", impl.path, pattern, temp_file)
    
    -- Warmup runs
    for i = 1, 5 do
        run_command_silent(cmd)
    end
    
    -- Timed runs
    local times = {}
    local failed_runs = 0
    
    for i = 1, iterations do
        local start = precise_time()
        local _, code = run_command(cmd)
        local elapsed_us = (precise_time() - start) * 1000000
        
        if code == 0 then
            table.insert(times, elapsed_us)
        else
            failed_runs = failed_runs + 1
        end
    end
    
    os.remove(temp_file)
    
    if #times == 0 then
        log("error", string.format("✗ %s failed all runs for %s", impl.name, test_name))
        return result
    end
    
    if failed_runs > 0 then
        log("normal", string.format("⚠️  %s had %d failed runs for %s", impl.name, failed_runs, test_name))
    end
    
    -- Calculate statistics
    local sum = 0
    result.min_us = times[1]
    result.max_us = times[1]
    
    for _, t in ipairs(times) do
        sum = sum + t
        result.min_us = math.min(result.min_us, t)
        result.max_us = math.max(result.max_us, t)
    end
    
    result.avg_us = sum / #times
    
    -- Calculate standard deviation and variance
    local variance_sum = 0
    for _, t in ipairs(times) do
        variance_sum = variance_sum + (t - result.avg_us) ^ 2
    end
    
    result.stddev_us = math.sqrt(variance_sum / #times)
    result.variance_percent = (result.stddev_us / result.avg_us) * 100
    result.success = true
    
    return result
end

-- Test data generation
local function generate_test_data()
    local data = {}
    
    -- Small dataset (100 IPs)
    local small_ips = {}
    for i = 1, 100 do
        table.insert(small_ips, string.format("192.168.1.%d", i))
    end
    data.small = table.concat(small_ips, "\n")
    
    -- Medium dataset (1000 IPs)  
    local medium_ips = {}
    for i = 1, 1000 do
        table.insert(medium_ips, string.format("10.%d.%d.%d", 
            math.random(0, 255), math.random(0, 255), math.random(1, 254)))
    end
    data.medium = table.concat(medium_ips, "\n")
    
    -- Large dataset (10000 IPs)
    local large_ips = {}
    for i = 1, 10000 do
        table.insert(large_ips, string.format("%d.%d.%d.%d",
            math.random(1, 223), math.random(0, 255), 
            math.random(0, 255), math.random(1, 254)))
    end
    data.large = table.concat(large_ips, "\n")
    
    -- IPv6 dataset
    local ipv6_ips = {}
    for i = 1, 500 do
        table.insert(ipv6_ips, string.format("2001:db8::%x:%x:%x:%x",
            math.random(0, 65535), math.random(0, 65535),
            math.random(0, 65535), math.random(0, 65535)))
    end
    data.ipv6 = table.concat(ipv6_ips, "\n")
    
    -- Mixed dataset
    data.mixed = data.small .. "\n" .. data.ipv6
    
    -- Log-like data
    local log_lines = {}
    for i = 1, 1000 do
        local ip = string.format("192.168.%d.%d", math.random(1, 10), math.random(1, 254))
        table.insert(log_lines, string.format("2024-01-01 %02d:%02d:%02d Server %s connection", 
            math.random(0, 23), math.random(0, 59), math.random(0, 59), ip))
    end
    data.logs = table.concat(log_lines, "\n")
    
    return data
end

-- Benchmark suites
local function run_quick_benchmarks(implementations, test_data)
    local benchmarks = {
        {name = "Small Dataset (100 IPs)", data = test_data.small, pattern = "192.168.0.0/16", iterations = 50},
        {name = "Medium Dataset (1000 IPs)", data = test_data.medium, pattern = "10.0.0.0/8", iterations = 20},
        {name = "IPv6 Performance", data = test_data.ipv6, pattern = "2001:db8::/32", iterations = 20}
    }
    
    return benchmarks
end

local function run_comprehensive_benchmarks(implementations, test_data)
    local benchmarks = {
        {name = "Small Dataset (100 IPs)", data = test_data.small, pattern = "192.168.0.0/16", iterations = 100},
        {name = "Medium Dataset (1000 IPs)", data = test_data.medium, pattern = "10.0.0.0/8", iterations = 50},
        {name = "Large Dataset (10000 IPs)", data = test_data.large, pattern = "172.16.0.0/12", iterations = 20},
        {name = "IPv6 Performance", data = test_data.ipv6, pattern = "2001:db8::/32", iterations = 50},
        {name = "Mixed IPv4/IPv6", data = test_data.mixed, pattern = "192.168.0.0/16,2001:db8::/32", iterations = 30},
        {name = "Log File Scanning", data = test_data.logs, pattern = "192.168.0.0/16", iterations = 30},
        {name = "Multiple Patterns", data = test_data.medium, pattern = "10.0.0.0/8,192.168.0.0/16,172.16.0.0/12", iterations = 30},
        {name = "Count Mode", data = test_data.medium, pattern = "-c 10.0.0.0/8", iterations = 50},
        {name = "Inverted Match", data = test_data.small, pattern = "-v 192.168.0.0/16", iterations = 50}
    }
    
    return benchmarks
end

-- Results reporting
local function print_results(all_results, implementations)
    if config.csv then
        -- CSV Header
        print("benchmark,implementation,avg_us,min_us,max_us,variance_percent,iterations,success")
        
        for benchmark_name, results in pairs(all_results) do
            for impl_name, result in pairs(results) do
                print(string.format("%s,%s,%.3f,%.3f,%.3f,%.2f,%d,%s",
                    benchmark_name, impl_name, result.avg_us, result.min_us, result.max_us,
                    result.variance_percent, result.iterations, result.success and "true" or "false"))
            end
        end
        return
    end
    
    -- Human-readable output
    log("normal", "\n=== Benchmark Results ===\n")
    
    for benchmark_name, results in pairs(all_results) do
        log("normal", string.format("📊 %s:", benchmark_name))
        
        -- Sort implementations for consistent output
        local impl_names = {}
        for name, _ in pairs(results) do
            table.insert(impl_names, name)
        end
        table.sort(impl_names)
        
        for _, impl_name in ipairs(impl_names) do
            local result = results[impl_name]
            if result.success then
                local status = result.variance_percent < 5.0 and "✓" or "⚠"
                log("normal", string.format("  %s %s: %.1fμs/op (±%.1f%%, %d runs)",
                    status, impl_name, result.avg_us, result.variance_percent, result.iterations))
            else
                log("normal", string.format("  ✗ %s: FAILED", impl_name))
            end
        end
        
        -- Show performance comparisons
        if results.rgcidr and results.rgcidr.success then
            for _, other_impl in ipairs(impl_names) do
                if other_impl ~= "rgcidr" and results[other_impl] and results[other_impl].success then
                    local speedup = results[other_impl].avg_us / results.rgcidr.avg_us
                    log("normal", string.format("    vs %s: %.2fx %s",
                        other_impl, speedup, speedup > 1 and "faster" or "slower"))
                end
            end
        end
        
        log("normal", "")
    end
end

-- Help display
local function show_help()
    print([[
Unified Benchmark Framework for rgcidr

This script consolidates all benchmark functionality with consistent comparison between:
- rgcidr (current version)
- rgcidr-last-version (previous git tag) 
- grepcidr (reference implementation)

Usage: lua scripts/benchmark_unified.lua [options]

Options:
  --quick           Run quick performance tests (3 benchmarks)
  --comprehensive   Run comprehensive benchmark suite (9+ benchmarks)  
  --regression      Compare current vs previous version only
  --compare-all     Compare all three implementations (default)
  --profile         Include detailed profiling information
  --csv             Output results in CSV format
  --no-build        Skip building binaries (assume already built)
  --help            Show this help message

Examples:
  lua scripts/benchmark_unified.lua --quick
  lua scripts/benchmark_unified.lua --comprehensive --csv
  lua scripts/benchmark_unified.lua --regression
  lua scripts/benchmark_unified.lua --compare-all --profile
]])
end

-- Main execution
local function main()
    parse_args(arg)
    
    if config.help then
        show_help()
        return
    end
    
    if not config.csv then
        log("normal", "🚀 rgcidr Unified Benchmark Framework")
        log("normal", "=====================================\n")
    end
    
    -- Setup implementations
    local implementations = setup_implementations()
    
    -- Build all available implementations
    local available_impls = {}
    for name, impl in pairs(implementations) do
        if impl:build() then
            available_impls[name] = impl
            if not config.csv then
                log("normal", string.format("✓ %s ready", impl.name))
            end
        else
            if not config.csv then
                log("normal", string.format("⚠️  %s not available", impl.name))
            end
        end
    end
    
    if next(available_impls) == nil then
        log("error", "❌ No implementations available for benchmarking!")
        return
    end
    
    -- Generate test data
    local test_data = generate_test_data()
    
    -- Select benchmark suite
    local benchmarks
    if config.comprehensive then
        benchmarks = run_comprehensive_benchmarks(available_impls, test_data)
    else
        benchmarks = run_quick_benchmarks(available_impls, test_data)
    end
    
    -- Run benchmarks
    local all_results = {}
    
    for _, benchmark in ipairs(benchmarks) do
        if not config.csv then
            log("normal", string.format("Running: %s", benchmark.name))
        end
        
        all_results[benchmark.name] = {}
        
        for impl_name, impl in pairs(available_impls) do
            local result = run_benchmark(impl, benchmark.name, benchmark.data, 
                                       benchmark.pattern, benchmark.iterations)
            all_results[benchmark.name][impl_name] = result
        end
    end
    
    -- Print results
    print_results(all_results, available_impls)
    
    -- Summary
    if not config.csv then
        log("normal", "🎉 Benchmark suite completed!")
        log("normal", string.format("Tested %d benchmarks across %d implementations", 
            #benchmarks, #available_impls))
    end
end

-- Error handling wrapper
local function safe_main()
    local success, err = pcall(main)
    if not success then
        log("error", "❌ Benchmark failed: " .. tostring(err))
        os.exit(1)
    end
end

safe_main()