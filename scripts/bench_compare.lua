#!/usr/bin/env lua

-- Precise benchmark comparison between rgcidr and grepcidr

local function precise_time()
    return os.clock()
end

local function run_command(cmd)
    local handle = io.popen(cmd .. " 2>&1")
    local result = handle:read("*a")
    local success, exit_type, code = handle:close()
    return result, code or 0
end

local function check_grepcidr_available()
    local _, code = run_command("which grepcidr")
    return code == 0
end

local function write_file(filename, content)
    local file = io.open(filename, "w")
    file:write(content)
    file:close()
end

-- Generate test data
local function generate_test_data()
    print("Generating test data...")
    
    -- Small dataset (100 IPs)
    local small = {}
    for i = 1, 100 do
        table.insert(small, string.format("192.168.%d.%d", i % 256, (i * 7) % 256))
    end
    write_file("test_small.txt", table.concat(small, "\n"))
    
    -- Medium dataset (1,000 IPs)
    local medium = {}
    for i = 1, 1000 do
        local octet1 = math.random(1, 255)
        local octet2 = math.random(0, 255)
        local octet3 = math.random(0, 255)
        local octet4 = math.random(0, 255)
        table.insert(medium, string.format("%d.%d.%d.%d", octet1, octet2, octet3, octet4))
    end
    write_file("test_medium.txt", table.concat(medium, "\n"))
    
    -- Large dataset (10,000 IPs)
    local large = {}
    for i = 1, 10000 do
        local octet1 = math.random(1, 255)
        local octet2 = math.random(0, 255)
        local octet3 = math.random(0, 255)
        local octet4 = math.random(0, 255)
        table.insert(large, string.format("%d.%d.%d.%d", octet1, octet2, octet3, octet4))
    end
    write_file("test_large.txt", table.concat(large, "\n"))
    
    -- IPv6 dataset (1,000 addresses)
    local ipv6 = {}
    for i = 1, 1000 do
        table.insert(ipv6, string.format("2001:db8:%x:%x::%x", 
            math.random(0, 65535), math.random(0, 65535), math.random(1, 65535)))
    end
    write_file("test_ipv6.txt", table.concat(ipv6, "\n"))
    
    -- Mixed IPv4/IPv6 (2,000 addresses)
    local mixed = {}
    for i = 1, 1000 do
        table.insert(mixed, string.format("%d.%d.%d.%d", 
            math.random(1, 255), math.random(0, 255), 
            math.random(0, 255), math.random(0, 255)))
        table.insert(mixed, string.format("2001:db8:%x:%x::%x", 
            math.random(0, 65535), math.random(0, 65535), math.random(1, 65535)))
    end
    write_file("test_mixed.txt", table.concat(mixed, "\n"))
    
    -- Log file (5,000 lines with embedded IPs)
    local logs = {}
    local templates = {
        "2024-01-01 10:00:00 Server %s responded in %dms",
        "Client connection from %s accepted",
        "Error: Failed to connect to %s (timeout)",
        "[INFO] Request from %s processed successfully",
        "No IP address in this log line at all",
        "Multiple IPs: src=%s dst=%s port=80",
    }
    for i = 1, 5000 do
        if i % 5 == 0 then
            table.insert(logs, templates[5])
        elseif i % 10 == 6 then
            local ip1 = string.format("%d.%d.%d.%d", 
                math.random(1, 255), math.random(0, 255), 
                math.random(0, 255), math.random(0, 255))
            local ip2 = string.format("%d.%d.%d.%d", 
                math.random(1, 255), math.random(0, 255), 
                math.random(0, 255), math.random(0, 255))
            table.insert(logs, string.format(templates[6], ip1, ip2))
        else
            local ip = string.format("%d.%d.%d.%d", 
                math.random(1, 255), math.random(0, 255), 
                math.random(0, 255), math.random(0, 255))
            local template_idx = (i % 4) + 1
            if template_idx == 1 then
                table.insert(logs, string.format(templates[1], ip, math.random(1, 1000)))
            else
                table.insert(logs, string.format(templates[template_idx], ip))
            end
        end
    end
    write_file("test_logs.txt", table.concat(logs, "\n"))
    
    print("Test data generated.\n")
end

-- Benchmark function
local function benchmark(name, grepcidr_cmd, rgcidr_cmd, iterations, grepcidr_available)
    iterations = iterations or 10
    
    print(string.format("=== %s ===", name))
    
    if not grepcidr_available then
        -- rgcidr-only benchmark
        print("Running rgcidr-only performance test...")
        
        -- Warmup
        for i = 1, 3 do
            run_command(rgcidr_cmd)
        end
        
        -- Benchmark rgcidr
        local rgcidr_times = {}
        for i = 1, iterations do
            local start = precise_time()
            local _, code = run_command(rgcidr_cmd)
            if code ~= 0 then
                print(string.format("❌ rgcidr failed on iteration %d", i))
                return 1.0
            end
            local elapsed = precise_time() - start
            table.insert(rgcidr_times, elapsed)
        end
        
        -- Calculate statistics
        local function calculate_stats(times)
            local sum = 0
            local min = times[1]
            local max = times[1]
            for _, t in ipairs(times) do
                sum = sum + t
                min = math.min(min, t)
                max = math.max(max, t)
            end
            return {
                avg = sum / #times,
                min = min,
                max = max
            }
        end
        
        local rg_stats = calculate_stats(rgcidr_times)
        print(string.format("rgcidr performance:"))
        print(string.format("  Average: %.1fμs (%.3fms)", rg_stats.avg * 1000000, rg_stats.avg * 1000))
        print(string.format("  Min:     %.1fμs (%.3fms)", rg_stats.min * 1000000, rg_stats.min * 1000))
        print(string.format("  Max:     %.1fμs (%.3fms)", rg_stats.max * 1000000, rg_stats.max * 1000))
        print(string.format("  Operations/sec: %.0f", 1.0 / rg_stats.avg))
        print()
        
        return 1.0 -- No comparison possible
    end
    
    -- Warmup
    for i = 1, 3 do
        run_command(grepcidr_cmd)
        run_command(rgcidr_cmd)
    end
    
    -- Benchmark grepcidr
    local grepcidr_times = {}
    for i = 1, iterations do
        local start = precise_time()
        run_command(grepcidr_cmd)
        local elapsed = precise_time() - start
        table.insert(grepcidr_times, elapsed)
    end
    
    -- Benchmark rgcidr
    local rgcidr_times = {}
    for i = 1, iterations do
        local start = precise_time()
        run_command(rgcidr_cmd)
        local elapsed = precise_time() - start
        table.insert(rgcidr_times, elapsed)
    end
    
    -- Calculate statistics
    local function stats(times)
        local sum = 0
        local min = times[1]
        local max = times[1]
        for _, t in ipairs(times) do
            sum = sum + t
            min = math.min(min, t)
            max = math.max(max, t)
        end
        return {
            avg = sum / #times,
            min = min,
            max = max,
            total = sum
        }
    end
    
    local grep_stats = stats(grepcidr_times)
    local rg_stats = stats(rgcidr_times)
    
    -- Display results
    print(string.format("grepcidr:"))
    print(string.format("  Average: %.1fμs (%.3fms)", grep_stats.avg * 1000000, grep_stats.avg * 1000))
    print(string.format("  Min:     %.1fμs (%.3fms)", grep_stats.min * 1000000, grep_stats.min * 1000))
    print(string.format("  Max:     %.1fμs (%.3fms)", grep_stats.max * 1000000, grep_stats.max * 1000))
    
    print(string.format("rgcidr:"))
    print(string.format("  Average: %.1fμs (%.3fms)", rg_stats.avg * 1000000, rg_stats.avg * 1000))
    print(string.format("  Min:     %.1fμs (%.3fms)", rg_stats.min * 1000000, rg_stats.min * 1000))
    print(string.format("  Max:     %.1fμs (%.3fms)", rg_stats.max * 1000000, rg_stats.max * 1000))
    
    local speedup = grep_stats.avg / rg_stats.avg
    print(string.format("Speedup: %.2fx %s", speedup, 
        speedup > 1.1 and "faster ✓" or 
        speedup < 0.9 and "slower ✗" or 
        "similar"))
    print()
    
    return speedup
end

-- Main
print("=== rgcidr Performance Comparison ===\n")

-- Check if grepcidr is available
local grepcidr_available = check_grepcidr_available()
if not grepcidr_available then
    print("⚠️  grepcidr not found - running rgcidr-only performance tests")
    print("   Install grepcidr for comparison benchmarks\n")
end

-- Build implementations
print("Building rgcidr...")
local output, code = run_command("zig build -Doptimize=ReleaseFast")
if code ~= 0 then
    print("❌ Failed to build rgcidr:")
    print(output)
    os.exit(1)
end

if grepcidr_available then
    print("Building grepcidr...")
    run_command("cd grepcidr && make clean && make > /dev/null 2>&1")
end
print("Build complete.\n")

-- Generate test data
generate_test_data()

-- Run benchmarks
local speedups = {}

-- Test 1: Small dataset with single CIDR
table.insert(speedups, benchmark(
    "Small dataset (100 IPs) - Single CIDR",
    "./grepcidr/grepcidr 192.168.0.0/16 < test_small.txt > /dev/null",
    "./zig-out/bin/rgcidr 192.168.0.0/16 < test_small.txt > /dev/null",
    50,
    grepcidr_available
))

-- Test 2: Medium dataset with single CIDR
table.insert(speedups, benchmark(
    "Medium dataset (1,000 IPs) - Single CIDR",
    "./grepcidr/grepcidr 10.0.0.0/8 < test_medium.txt > /dev/null",
    "./zig-out/bin/rgcidr 10.0.0.0/8 < test_medium.txt > /dev/null",
    50,
    grepcidr_available
))

-- Test 3: Large dataset with multiple CIDRs
table.insert(speedups, benchmark(
    "Large dataset (10,000 IPs) - Multiple CIDRs",
    "./grepcidr/grepcidr '192.168.0.0/16,10.0.0.0/8,172.16.0.0/12' < test_large.txt > /dev/null",
    "./zig-out/bin/rgcidr '192.168.0.0/16,10.0.0.0/8,172.16.0.0/12' < test_large.txt > /dev/null",
    20,
    grepcidr_available
))

-- Test 4: IPv6 dataset
table.insert(speedups, benchmark(
    "IPv6 dataset (1,000 addresses)",
    "./grepcidr/grepcidr '2001:db8::/32' < test_ipv6.txt > /dev/null",
    "./zig-out/bin/rgcidr '2001:db8::/32' < test_ipv6.txt > /dev/null",
    50,
    grepcidr_available
))

-- Test 5: Mixed IPv4/IPv6
table.insert(speedups, benchmark(
    "Mixed IPv4/IPv6 (2,000 addresses)",
    "./grepcidr/grepcidr '2001:db8::/32,192.168.0.0/16' < test_mixed.txt > /dev/null",
    "./zig-out/bin/rgcidr '2001:db8::/32,192.168.0.0/16' < test_mixed.txt > /dev/null",
    30,
    grepcidr_available
))

-- Test 6: Log file scanning
table.insert(speedups, benchmark(
    "Log file scanning (5,000 lines)",
    "./grepcidr/grepcidr '192.168.0.0/16,10.0.0.0/8' < test_logs.txt > /dev/null",
    "./zig-out/bin/rgcidr '192.168.0.0/16,10.0.0.0/8' < test_logs.txt > /dev/null",
    30,
    grepcidr_available
))

-- Test 7: Count mode
table.insert(speedups, benchmark(
    "Count mode (10,000 IPs)",
    "./grepcidr/grepcidr -c '10.0.0.0/8,192.168.0.0/16' < test_large.txt > /dev/null",
    "./zig-out/bin/rgcidr -c '10.0.0.0/8,192.168.0.0/16' < test_large.txt > /dev/null",
    30,
    grepcidr_available
))

-- Test 8: Inverted match
table.insert(speedups, benchmark(
    "Inverted match (1,000 IPs)",
    "./grepcidr/grepcidr -v '192.168.0.0/16' < test_medium.txt > /dev/null",
    "./zig-out/bin/rgcidr -v '192.168.0.0/16' < test_medium.txt > /dev/null",
    30,
    grepcidr_available
))

-- Clean up test files
os.remove("test_small.txt")
os.remove("test_medium.txt")
os.remove("test_large.txt")
os.remove("test_ipv6.txt")
os.remove("test_mixed.txt")
os.remove("test_logs.txt")

-- Summary
print("=== SUMMARY ===")

if not grepcidr_available then
    print(string.format("Total rgcidr performance tests: %d", #speedups))
    print("✅ rgcidr performance validation complete!")
    print("📊 Install grepcidr for comparative benchmarks")
else
    local total_speedup = 0
    local faster_count = 0
    local slower_count = 0

    for i, speedup in ipairs(speedups) do
        total_speedup = total_speedup + speedup
        if speedup > 1.1 then
            faster_count = faster_count + 1
        elseif speedup < 0.9 then
            slower_count = slower_count + 1
        end
    end

    local avg_speedup = total_speedup / #speedups
    print(string.format("Average speedup: %.2fx", avg_speedup))
    print(string.format("Tests where rgcidr was faster: %d/%d", faster_count, #speedups))
    print(string.format("Tests where rgcidr was slower: %d/%d", slower_count, #speedups))
    print(string.format("Tests with similar performance: %d/%d", #speedups - faster_count - slower_count, #speedups))

    if avg_speedup > 1.0 then
        print(string.format("\n✓ rgcidr is on average %.1f%% faster than grepcidr!", (avg_speedup - 1) * 100))
    elseif avg_speedup < 1.0 then
        print(string.format("\n✗ rgcidr is on average %.1f%% slower than grepcidr", (1 - avg_speedup) * 100))
    else
        print("\n≈ rgcidr and grepcidr have similar performance")
    end
end
