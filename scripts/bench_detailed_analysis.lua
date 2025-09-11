#!/usr/bin/env lua

-- Detailed Performance Analysis for rgcidr Optimizations
-- This script provides in-depth analysis of various performance aspects

local function run_command(cmd)
    local handle = io.popen(cmd .. " 2>&1")
    local result = handle:read("*a")
    local success, exit_type, code = handle:close()
    return result, code or 0
end

local function write_temp_file(content)
    local filename = os.tmpname()
    local file = io.open(filename, "w")
    file:write(content)
    file:close()
    return filename
end

local function benchmark_operation(description, input, pattern, iterations)
    iterations = iterations or 1000
    
    local temp_file = write_temp_file(input)
    local cmd = string.format("./zig-out/bin/rgcidr %s < %s", pattern, temp_file)
    
    -- Use higher precision timing by measuring individual operations
    local times = {}
    for i = 1, iterations do
        local start_time = os.clock()
        run_command(cmd)
        local end_time = os.clock()
        local elapsed_seconds = end_time - start_time
        times[i] = elapsed_seconds * 1000000  -- Convert directly to microseconds
    end
    
    os.remove(temp_file)
    
    -- Calculate statistics in microseconds
    local total_time_us = 0
    for _, t in ipairs(times) do
        total_time_us = total_time_us + t
    end
    local avg_time_us = total_time_us / iterations
    local avg_time_ms = avg_time_us / 1000
    
    print(string.format("%-40s: %.1f μs/op (%.3f ms/op, %d iterations)", description, avg_time_us, avg_time_ms, iterations))
    return avg_time_ms
end

print("=== Detailed Performance Analysis ===")
print("")

-- Build optimized binary
print("Building optimized rgcidr...")
run_command("zig build -Doptimize=ReleaseFast")
print("")

-- 1. Pattern Complexity Analysis
print("1. Pattern Complexity Performance")
print("   Testing how performance scales with pattern count")

local single_ip = "192.168.1.100"
benchmark_operation("Single pattern (1 pattern)", single_ip, "192.168.1.100", 5000)
benchmark_operation("Few patterns (3 patterns)", single_ip, "192.168.1.100,10.0.0.1,172.16.1.1", 5000)
benchmark_operation("Many patterns (10 patterns)", single_ip, "192.168.0.0/16,10.0.0.0/8,172.16.0.0/12,203.0.113.0/24,198.51.100.0/24,224.0.0.0/8,240.0.0.0/4,127.0.0.0/8,169.254.0.0/16,192.0.2.0/24", 2000)
print("")

-- 2. Input Size Analysis
print("2. Input Size Scaling")
print("   Testing how performance scales with input size")

local small_input = table.concat({
    "192.168.1.1",
    "10.0.0.1", 
    "172.16.1.1"
}, "\n")

local medium_input = {}
for i = 1, 100 do
    table.insert(medium_input, string.format("192.168.1.%d", i))
end
medium_input = table.concat(medium_input, "\n")

local large_input = {}
for i = 1, 1000 do
    table.insert(large_input, string.format("192.168.%d.%d", math.floor(i/256), i%256))
end
large_input = table.concat(large_input, "\n")

benchmark_operation("Small input (3 IPs)", small_input, "192.168.0.0/16", 5000)
benchmark_operation("Medium input (100 IPs)", medium_input, "192.168.0.0/16", 1000) 
benchmark_operation("Large input (1000 IPs)", large_input, "192.168.0.0/16", 200)
print("")

-- 3. IPv6 vs IPv4 Performance
print("3. IPv4 vs IPv6 Performance Comparison")

local ipv4_input = table.concat({
    "192.168.1.1",
    "10.0.0.1",
    "172.16.1.1", 
    "203.0.113.1",
    "8.8.8.8"
}, "\n")

local ipv6_input = table.concat({
    "2001:db8::1",
    "2001:db8:85a3::8a2e:370:7334",
    "fe80::1",
    "::1",
    "::ffff:192.168.1.1"
}, "\n")

local mixed_input = table.concat({
    "192.168.1.1",
    "2001:db8::1", 
    "10.0.0.1",
    "fe80::1",
    "172.16.1.1"
}, "\n")

benchmark_operation("IPv4 only", ipv4_input, "192.168.0.0/16,10.0.0.0/8", 3000)
benchmark_operation("IPv6 only", ipv6_input, "2001:db8::/32,fe80::/10", 3000)
benchmark_operation("Mixed IPv4/IPv6", mixed_input, "192.168.0.0/16,2001:db8::/32", 3000)
print("")

-- 4. Hit Rate Analysis
print("4. Hit Rate Impact Analysis")
print("   Testing performance with different match ratios")

-- High hit rate (80% matches)
local high_hit_input = {}
for i = 1, 100 do
    if i <= 80 then
        table.insert(high_hit_input, string.format("192.168.1.%d", i))
    else
        table.insert(high_hit_input, string.format("203.0.113.%d", i))
    end
end
high_hit_input = table.concat(high_hit_input, "\n")

-- Low hit rate (20% matches)
local low_hit_input = {}
for i = 1, 100 do
    if i <= 20 then
        table.insert(low_hit_input, string.format("192.168.1.%d", i))
    else
        table.insert(low_hit_input, string.format("203.0.113.%d", i))
    end
end
low_hit_input = table.concat(low_hit_input, "\n")

benchmark_operation("High hit rate (80% matches)", high_hit_input, "192.168.0.0/16", 1000)
benchmark_operation("Low hit rate (20% matches)", low_hit_input, "192.168.0.0/16", 1000)
print("")

-- 5. Binary Search Analysis
print("5. Binary Search Efficiency Test")
print("   Testing performance with sorted vs unsorted pattern distribution")

-- Create patterns that test binary search efficiency
local patterns_ascending = "192.168.0.0/24,192.168.1.0/24,192.168.2.0/24,192.168.3.0/24,192.168.4.0/24"
local test_ip_ascending = "192.168.2.100"

local patterns_mixed = "172.16.0.0/12,192.168.0.0/16,10.0.0.0/8,203.0.113.0/24,198.51.100.0/24"
local test_ip_mixed = "192.168.2.100"

benchmark_operation("Ordered patterns (best case)", test_ip_ascending, patterns_ascending, 10000)
benchmark_operation("Mixed patterns (typical case)", test_ip_mixed, patterns_mixed, 10000)
print("")

-- 6. Cache Locality Analysis
print("6. Memory Access Pattern Analysis")

-- Test cache-friendly vs cache-unfriendly patterns
local cache_friendly_input = {}
for i = 1, 200 do
    table.insert(cache_friendly_input, string.format("192.168.1.%d", i % 254 + 1))
end
cache_friendly_input = table.concat(cache_friendly_input, "\n")

benchmark_operation("Cache-friendly access pattern", cache_friendly_input, "192.168.0.0/16", 500)
print("")

-- 7. Edge Case Performance
print("7. Edge Case Performance")

local edge_cases = {
    {"Empty input", "", "192.168.0.0/16"},
    {"Single character per line", "1\n2\n3\n4\n5", "192.168.0.0/16"},
    {"Very long lines", string.rep("not an ip address ", 100) .. "192.168.1.1", "192.168.0.0/16"},
    {"Many small patterns", "192.168.1.1", "192.168.1.1,192.168.1.2,192.168.1.3,192.168.1.4,192.168.1.5"}
}

for _, case in ipairs(edge_cases) do
    local desc, input, pattern = case[1], case[2], case[3]
    benchmark_operation(desc, input, pattern, 2000)
end

print("")
print("=== Analysis Summary ===")
print("Performance characteristics analyzed:")
print("- Pattern complexity scaling")
print("- Input size scaling")
print("- IPv4 vs IPv6 performance")
print("- Hit rate impact")
print("- Binary search efficiency")
print("- Memory access patterns")
print("- Edge case handling")
print("")
print("All measurements show microseconds (μs) and milliseconds (ms) per operation.")