#!/usr/bin/env lua

-- rgcidr Unified Test & Benchmark Runner
-- Consolidates all testing and benchmarking functionality into a single script
-- 
-- Usage:
--   lua scripts/rgcidr_test.lua [options]
--
-- === TEST TYPES ===
--   --unit                Run Zig unit tests
--   --functional          Run functional tests
--   --compare             Compare with grepcidr
--   --rfc                 Run RFC compliance tests
--   --regression          Run regression tests vs baseline
--
-- === BENCHMARK TYPES ===
--   --bench               Run standard benchmarks
--   --bench-quick         Run quick benchmarks (5 runs each)
--   --bench-comprehensive Run comprehensive benchmarks (20+ runs)
--   --bench-micro         Run micro-benchmarks for optimization
--   --bench-statistical   Run statistical benchmarks (30 runs, outlier removal)
--   --bench-validation    Run optimization validation benchmarks
--
-- === PROFILING & ANALYSIS ===
--   --profile             Run performance profiling
--   --profile-deep        Run deep performance analysis
--   --optimize-validate   Validate current optimizations
--   --scaling-analysis    Test scaling characteristics
--
-- === OUTPUT OPTIONS ===
--   --csv                 Output in CSV format
--   --json                Output in JSON format  
--   --quiet               Minimal output
--   --verbose             Detailed output
--   --report              Generate comprehensive report
--
-- === BUILD OPTIONS ===
--   --build-debug         Build with debug optimization
--   --build-safe          Build with ReleaseSafe
--   --build-fast          Build with ReleaseFast (default)
--   --build-small         Build with ReleaseSmall
--   --no-build           Skip building (use existing binaries)
--
-- === UTILITY OPTIONS ===
--   --baseline=REF        Git ref for regression tests (default: main)
--   --runs=N             Number of benchmark runs (default: auto)
--   --variance-target=N  Target variance percentage (default: 10%)
--   --help               Show this help
--   --version            Show version info
--
-- === PRESETS ===
--   --all                Run everything (tests + comprehensive benchmarks)
--   --ci                 CI-friendly tests (unit, functional, quick benchmarks)
--   --development        Developer tests (unit, functional, micro-benchmarks)
--   --release            Release validation (all tests, comprehensive benchmarks)
--   --performance        Performance focus (all benchmarks, profiling, validation)

local function precise_time()
    return os.clock()
end

local function run_command(cmd)
    local handle = io.popen(cmd .. " 2>&1")
    if not handle then
        return nil, -1, "Failed to execute command"
    end
    local result = handle:read("*a")
    local success, exit_type, code = handle:close()
    return result, code or 0, nil
end

-- Configuration with defaults
local config = {
    -- Test types
    unit = false,
    functional = false,
    compare = false,
    rfc = false,
    regression = false,
    
    -- Benchmark types
    bench = false,
    bench_quick = false,
    bench_comprehensive = false,
    bench_micro = false,
    bench_statistical = false,
    bench_validation = false,
    
    -- Profiling
    profile = false,
    profile_deep = false,
    optimize_validate = false,
    scaling_analysis = false,
    
    -- Output
    csv = false,
    json = false,
    quiet = false,
    verbose = false,
    report = false,
    
    -- Build
    build_debug = false,
    build_safe = false,
    build_fast = true,  -- default
    build_small = false,
    no_build = false,
    
    -- Options
    baseline = "main",
    runs = nil,  -- auto-detect based on test type
    variance_target = 10.0,
    help = false,
    version = false,
    
    -- Presets
    all = false,
    ci = false,
    development = false,
    release = false,
    performance = false,
}

-- Parse command line arguments
local function parse_args()
    for i, arg in ipairs(arg or {}) do
        if arg == "--unit" then config.unit = true
        elseif arg == "--functional" then config.functional = true
        elseif arg == "--compare" then config.compare = true
        elseif arg == "--rfc" then config.rfc = true
        elseif arg == "--regression" then config.regression = true
        
        elseif arg == "--bench" then config.bench = true
        elseif arg == "--bench-quick" then config.bench_quick = true
        elseif arg == "--bench-comprehensive" then config.bench_comprehensive = true
        elseif arg == "--bench-micro" then config.bench_micro = true
        elseif arg == "--bench-statistical" then config.bench_statistical = true
        elseif arg == "--bench-validation" then config.bench_validation = true
        
        elseif arg == "--profile" then config.profile = true
        elseif arg == "--profile-deep" then config.profile_deep = true
        elseif arg == "--optimize-validate" then config.optimize_validate = true
        elseif arg == "--scaling-analysis" then config.scaling_analysis = true
        
        elseif arg == "--csv" then config.csv = true
        elseif arg == "--json" then config.json = true
        elseif arg == "--quiet" then config.quiet = true
        elseif arg == "--verbose" then config.verbose = true
        elseif arg == "--report" then config.report = true
        
        elseif arg == "--build-debug" then config.build_debug = true; config.build_fast = false
        elseif arg == "--build-safe" then config.build_safe = true; config.build_fast = false
        elseif arg == "--build-fast" then config.build_fast = true
        elseif arg == "--build-small" then config.build_small = true; config.build_fast = false
        elseif arg == "--no-build" then config.no_build = true
        
        elseif arg:match("^--baseline=") then config.baseline = arg:match("^--baseline=(.+)")
        elseif arg:match("^--runs=") then config.runs = tonumber(arg:match("^--runs=(.+)"))
        elseif arg:match("^--variance-target=") then config.variance_target = tonumber(arg:match("^--variance-target=(.+)"))
        
        elseif arg == "--help" then config.help = true
        elseif arg == "--version" then config.version = true
        
        -- Presets
        elseif arg == "--all" then
            config.all = true
            config.unit, config.functional, config.compare, config.rfc = true, true, true, true
            config.bench_comprehensive, config.profile, config.optimize_validate = true, true, true
        elseif arg == "--ci" then
            config.ci = true
            config.unit, config.functional, config.bench_quick = true, true, true
        elseif arg == "--development" then
            config.development = true  
            config.unit, config.functional, config.bench_micro, config.profile = true, true, true, true
        elseif arg == "--release" then
            config.release = true
            config.unit, config.functional, config.compare, config.rfc = true, true, true, true
            config.bench_comprehensive, config.bench_statistical = true, true
        elseif arg == "--performance" then
            config.performance = true
            config.bench, config.bench_comprehensive, config.bench_micro = true, true, true
            config.profile, config.profile_deep, config.optimize_validate, config.scaling_analysis = true, true, true, true
        else
            print("Unknown option: " .. arg)
            return false
        end
    end
    
    -- Default behavior if no options specified
    if not (config.unit or config.functional or config.compare or config.rfc or config.regression or
            config.bench or config.bench_quick or config.bench_comprehensive or config.bench_micro or
            config.bench_statistical or config.bench_validation or
            config.profile or config.profile_deep or config.optimize_validate or config.scaling_analysis or
            config.all or config.ci or config.development or config.release or config.performance) then
        config.development = true
        config.unit, config.functional, config.bench_quick = true, true, true
    end
    
    return true
end

-- Show help
local function show_help()
    print([[
rgcidr Unified Test & Benchmark Runner

USAGE:
    lua scripts/rgcidr_test.lua [options]

TEST TYPES:
    --unit                Run Zig unit tests
    --functional          Run functional tests
    --compare             Compare with grepcidr
    --rfc                 Run RFC compliance tests
    --regression          Run regression tests vs baseline

BENCHMARK TYPES:
    --bench               Run standard benchmarks
    --bench-quick         Run quick benchmarks (5 runs each)
    --bench-comprehensive Run comprehensive benchmarks (20+ runs)
    --bench-micro         Run micro-benchmarks for optimization
    --bench-statistical   Run statistical benchmarks (30 runs, outlier removal)
    --bench-validation    Run optimization validation benchmarks

PROFILING & ANALYSIS:
    --profile             Run performance profiling
    --profile-deep        Run deep performance analysis
    --optimize-validate   Validate current optimizations
    --scaling-analysis    Test scaling characteristics

OUTPUT OPTIONS:
    --csv                 Output in CSV format
    --json                Output in JSON format
    --quiet               Minimal output
    --verbose             Detailed output
    --report              Generate comprehensive report

BUILD OPTIONS:
    --build-debug         Build with debug optimization
    --build-safe          Build with ReleaseSafe
    --build-fast          Build with ReleaseFast (default)
    --build-small         Build with ReleaseSmall
    --no-build           Skip building (use existing binaries)

UTILITY OPTIONS:
    --baseline=REF        Git ref for regression tests (default: main)
    --runs=N             Number of benchmark runs (default: auto)
    --variance-target=N  Target variance percentage (default: 10%)
    --help               Show this help
    --version            Show version info

PRESETS:
    --all                Run everything (tests + comprehensive benchmarks)
    --ci                 CI-friendly tests (unit, functional, quick benchmarks)
    --development        Developer tests (unit, functional, micro-benchmarks) [default]
    --release            Release validation (all tests, comprehensive benchmarks)
    --performance        Performance focus (all benchmarks, profiling, validation)

EXAMPLES:
    lua scripts/rgcidr_test.lua                         # Default: development preset
    lua scripts/rgcidr_test.lua --ci                    # CI testing
    lua scripts/rgcidr_test.lua --performance --csv     # Performance analysis with CSV output
    lua scripts/rgcidr_test.lua --unit --functional     # Just basic tests
    lua scripts/rgcidr_test.lua --bench-statistical --runs=50 --variance-target=5.0
]])
end

-- Show version
local function show_version()
    local git_hash, _ = run_command("git rev-parse --short HEAD")
    git_hash = git_hash and git_hash:gsub("%s+", "") or "unknown"
    
    local git_branch, _ = run_command("git branch --show-current")
    git_branch = git_branch and git_branch:gsub("%s+", "") or "unknown"
    
    print(string.format("rgcidr Test Runner v1.0 (git: %s/%s)", git_branch, git_hash))
end

-- Binary availability and build management
local function ensure_binary_availability()
    if not config.quiet then
        print("=== Binary Availability Check ===")
    end
    
    -- Build rgcidr if needed
    if not config.no_build then
        local build_flag = ""
        if config.build_debug then build_flag = "-Doptimize=Debug"
        elseif config.build_safe then build_flag = "-Doptimize=ReleaseSafe"
        elseif config.build_small then build_flag = "-Doptimize=ReleaseSmall"
        else build_flag = "-Doptimize=ReleaseFast" end
        
        if not config.quiet then
            print(string.format("Building rgcidr with %s...", build_flag))
        end
        
        local build_output, build_code = run_command("zig build " .. build_flag)
        if build_code ~= 0 then
            print("✗ Failed to build rgcidr:")
            print(build_output)
            return false
        end
        
        if not config.quiet then
            print("✓ rgcidr built successfully")
        end
    end
    
    -- Check rgcidr availability
    local rgcidr_check, rgcidr_code = run_command("test -f ./zig-out/bin/rgcidr && echo 'exists'")
    if rgcidr_code ~= 0 then
        print("✗ rgcidr binary not available")
        return false
    end
    
    -- Check grepcidr availability for comparison tests
    if config.compare or config.bench or config.bench_quick or config.bench_comprehensive or config.bench_statistical then
        local grepcidr_check, grepcidr_code = run_command("which grepcidr")
        if grepcidr_code ~= 0 then
            print("⚠ grepcidr not available - skipping comparison tests")
            config.compare = false
            -- Don't disable benchmarks, just note the limitation
        else
            if not config.quiet then
                print("✓ grepcidr available for comparisons")
            end
        end
    end
    
    if not config.quiet then
        print("✓ All required binaries available\n")
    end
    
    return true
end

-- Statistical utilities
local function calculate_stats(times)
    if #times == 0 then return nil end
    
    table.sort(times)
    local n = #times
    
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
        reliable = variance_percent <= config.variance_target
    }
end

-- Execute tests
local function run_tests()
    local results = {}
    
    if config.unit then
        if not config.quiet then print("=== Unit Tests ===") end
        local output, code = run_command("zig build test")
        results.unit = {success = code == 0, output = output}
        if not config.quiet then
            print(code == 0 and "✓ Unit tests passed" or "✗ Unit tests failed")
        end
    end
    
    if config.functional then
        if not config.quiet then print("=== Functional Tests ===") end
        local output, code = run_command("lua scripts/test_unified.lua --functional --quiet")
        results.functional = {success = code == 0, output = output}
        if not config.quiet then
            print(code == 0 and "✓ Functional tests passed" or "✗ Functional tests failed")
        end
    end
    
    if config.compare then
        if not config.quiet then print("=== Comparison Tests ===") end
        local output, code = run_command("lua scripts/test_unified.lua --compare --quiet")
        results.compare = {success = code == 0, output = output}
        if not config.quiet then
            print(code == 0 and "✓ Comparison tests passed" or "✗ Comparison tests failed")
        end
    end
    
    if config.rfc then
        if not config.quiet then print("=== RFC Compliance Tests ===") end
        local output, code = run_command("lua scripts/test_unified.lua --rfc --quiet")
        results.rfc = {success = code == 0, output = output}
        if not config.quiet then
            print(code == 0 and "✓ RFC compliance tests passed" or "✗ RFC compliance tests failed")
        end
    end
    
    return results
end

-- Execute benchmarks
local function run_benchmarks()
    local results = {}
    
    if config.bench_quick then
        if not config.quiet then print("=== Quick Benchmarks ===") end
        local output, code = run_command("lua scripts/benchmark_unified.lua --quick" .. (config.csv and " --csv" or ""))
        results.bench_quick = {success = code == 0, output = output}
    end
    
    if config.bench_comprehensive then
        if not config.quiet then print("=== Comprehensive Benchmarks ===") end
        local output, code = run_command("lua scripts/benchmark_unified.lua --comprehensive" .. (config.csv and " --csv" or ""))
        results.bench_comprehensive = {success = code == 0, output = output}
    end
    
    if config.bench_micro then
        if not config.quiet then print("=== Micro Benchmarks ===") end
        local output, code = run_command("zig build micro-bench")
        results.bench_micro = {success = code == 0, output = output}
    end
    
    if config.bench_statistical then
        if not config.quiet then print("=== Statistical Benchmarks ===") end
        local runs_arg = config.runs and string.format(" --runs=%d", config.runs) or ""
        local output, code = run_command("lua scripts/final_statistical_report.lua" .. runs_arg)
        results.bench_statistical = {success = code == 0, output = output}
    end
    
    if config.bench_validation then
        if not config.quiet then print("=== Validation Benchmarks ===") end
        local output, code = run_command("lua scripts/advanced_validation.lua")
        results.bench_validation = {success = code == 0, output = output}
    end
    
    return results
end

-- Execute profiling
local function run_profiling()
    local results = {}
    
    if config.profile then
        if not config.quiet then print("=== Performance Profiling ===") end
        local output, code = run_command("lua scripts/profile_large_simple.lua")
        results.profile = {success = code == 0, output = output}
    end
    
    if config.profile_deep then
        if not config.quiet then print("=== Deep Performance Analysis ===") end
        local output, code = run_command("zig build deep-prof")
        results.profile_deep = {success = code == 0, output = output}  
    end
    
    if config.optimize_validate then
        if not config.quiet then print("=== Optimization Validation ===") end
        local output, code = run_command("lua scripts/validate_optimizations.lua")
        results.optimize_validate = {success = code == 0, output = output}
    end
    
    if config.scaling_analysis then
        if not config.quiet then print("=== Scaling Analysis ===") end
        local output, code = run_command("zig build profile-large")
        results.scaling_analysis = {success = code == 0, output = output}
    end
    
    return results
end

-- Main execution
local function main()
    if not parse_args() then
        return 1
    end
    
    if config.help then
        show_help()
        return 0
    end
    
    if config.version then
        show_version()
        return 0
    end
    
    -- Ensure binaries are available
    if not ensure_binary_availability() then
        return 1
    end
    
    local start_time = precise_time()
    
    -- Execute selected operations
    local test_results = run_tests()
    local bench_results = run_benchmarks() 
    local profile_results = run_profiling()
    
    local end_time = precise_time()
    local total_time = (end_time - start_time) * 1000  -- Convert to milliseconds
    
    -- Summary
    if not config.quiet then
        print(string.format("\n=== Execution Summary (%.1fms) ===", total_time))
        
        local total_operations = 0
        local successful_operations = 0
        
        -- Count results
        for _, result in pairs(test_results) do
            total_operations = total_operations + 1
            if result.success then successful_operations = successful_operations + 1 end
        end
        
        for _, result in pairs(bench_results) do  
            total_operations = total_operations + 1
            if result.success then successful_operations = successful_operations + 1 end
        end
        
        for _, result in pairs(profile_results) do
            total_operations = total_operations + 1
            if result.success then successful_operations = successful_operations + 1 end
        end
        
        print(string.format("Operations: %d total, %d successful, %d failed", 
            total_operations, successful_operations, total_operations - successful_operations))
        
        if total_operations == successful_operations then
            print("✓ All operations completed successfully")
            return 0
        else
            print("⚠ Some operations failed")
            return 1
        end
    end
    
    return 0
end

-- Execute
os.exit(main())