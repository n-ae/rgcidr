#!/usr/bin/env lua

-- Focused performance bottleneck analysis for rgcidr
-- Identifies specific performance characteristics for optimization

local function precise_time()
    return os.clock()
end

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
    
    -- Warmup
    for i = 1, 3 do
        run_command(cmd)
    end
    
    local times = {}
    for i = 1, iterations do
        local start = precise_time()
        local _, code = run_command(cmd)
        local elapsed = precise_time() - start
        table.insert(times, elapsed)
        if code ~= 0 then
            print(string.format("❌ %s failed on iteration %d", description, i))
            break
        end
    end
    
    os.remove(temp_file)
    
    if #times == 0 then return 0 end
    
    -- Calculate statistics
    local sum = 0
    local min_time = times[1]
    local max_time = times[1]
    for _, t in ipairs(times) do
        sum = sum + t
        min_time = math.min(min_time, t)
        max_time = math.max(max_time, t)
    end
    
    local avg_time = sum / #times
    local avg_time_us = avg_time * 1000000  -- Convert to microseconds
    local min_time_us = min_time * 1000000
    local max_time_us = max_time * 1000000
    
    print(string.format("%-35s: %.1f μs/op (min: %.1f, max: %.1f)", 
        description, avg_time_us, min_time_us, max_time_us))
    return avg_time
end

print("=== Performance Bottleneck Analysis ===")
print()

-- Build optimized binary
print("Building optimized rgcidr...")
local output, code = run_command("zig build -Doptimize=ReleaseFast")
if code ~= 0 then
    print("❌ Build failed:")
    print(output)
    os.exit(1)
end
print()

-- Test 1: Scanning Performance Bottlenecks
print("1. Scanning Performance Analysis")
print("   Isolating line scanning vs pattern matching costs")

local single_ip_line = "192.168.1.100"
local multiple_ip_line = "192.168.1.1 10.0.0.1 172.16.1.1 203.0.113.1"
local long_line_few_ips = string.rep("word ", 100) .. "192.168.1.1 " .. string.rep("more ", 50) .. "10.0.0.1"
local many_short_lines = string.rep("192.168.1.1\n", 100)

benchmark_operation("Single IP per line", single_ip_line, "192.168.0.0/16", 3000)
benchmark_operation("Multiple IPs per line", multiple_ip_line, "192.168.0.0/16", 2000)
benchmark_operation("Long line with few IPs", long_line_few_ips, "192.168.0.0/16", 1500)
benchmark_operation("Many short lines", many_short_lines, "192.168.0.0/16", 500)
print()

-- Test 2: Pattern Matching Bottlenecks
print("2. Pattern Matching Performance")
print("   Testing different pattern complexities")

local test_ip = "192.168.50.100"

benchmark_operation("Single exact IP match", test_ip, "192.168.50.100", 5000)
benchmark_operation("Single CIDR match", test_ip, "192.168.0.0/16", 5000)
benchmark_operation("Multiple CIDR patterns", test_ip, "10.0.0.0/8,192.168.0.0/16,172.16.0.0/12", 3000)
benchmark_operation("Many patterns (10)", test_ip, "10.0.0.0/8,192.168.0.0/16,172.16.0.0/12,203.0.113.0/24,198.51.100.0/24,224.0.0.0/8,240.0.0.0/4,127.0.0.0/8,169.254.0.0/16,192.0.2.0/24", 2000)
print()

-- Test 3: IPv6 vs IPv4 Performance Bottlenecks
print("3. IPv4 vs IPv6 Performance")
print("   Comparing parsing and matching costs")

local ipv4_test = "192.168.1.1"
local ipv6_test = "2001:db8::1"
local ipv6_long = "2001:0db8:85a3:0000:0000:8a2e:0370:7334"
local ipv4_mapped = "::ffff:192.168.1.1"

benchmark_operation("IPv4 parsing", ipv4_test, "192.168.0.0/16", 4000)
benchmark_operation("IPv6 short parsing", ipv6_test, "2001:db8::/32", 4000)
benchmark_operation("IPv6 long parsing", ipv6_long, "2001:db8::/32", 3000)
benchmark_operation("IPv4-mapped IPv6", ipv4_mapped, "192.168.0.0/16", 3000)
print()

-- Test 4: Hint Function Efficiency
print("4. Hint Function Performance")
print("   Testing hint detection efficiency")

-- Create inputs that stress hint detection
local no_ips = string.rep("no ip addresses here just text ", 50)
local many_false_positives = string.rep("123.456.789.012 ", 20) -- Invalid IPs that might trigger hints
local mixed_valid_invalid = "192.168.1.1 999.999.999.999 10.0.0.1 123.456.789.012"

benchmark_operation("No IPs (hint rejection)", no_ips, "192.168.0.0/16", 3000)
benchmark_operation("Many false positive hints", many_false_positives, "192.168.0.0/16", 2000)
benchmark_operation("Mixed valid/invalid IPs", mixed_valid_invalid, "192.168.0.0/16", 2000)
print()

-- Test 5: Memory Access Patterns
print("5. Memory Access Patterns")
print("   Testing cache efficiency")

-- Create data that tests memory access patterns
local sequential_ips = {}
for i = 1, 100 do
    table.insert(sequential_ips, string.format("192.168.1.%d", i))
end
local sequential_input = table.concat(sequential_ips, "\n")

local random_ips = {}
for i = 1, 100 do
    local a = math.random(1, 254)
    local b = math.random(0, 255)
    local c = math.random(0, 255)
    local d = math.random(1, 254)
    table.insert(random_ips, string.format("%d.%d.%d.%d", a, b, c, d))
end
local random_input = table.concat(random_ips, "\n")

benchmark_operation("Sequential IP range", sequential_input, "192.168.0.0/16", 1000)
benchmark_operation("Random IP distribution", random_input, "192.168.0.0/16", 1000)
print()

print("=== Bottleneck Analysis Complete ===")
print("Use this data to identify optimization targets:")
print("- Compare similar operations to find slow paths")
print("- Look for significant variance (max vs min) indicating inconsistent performance")
print("- Focus on operations with highest absolute microsecond times")
print("- All measurements in microseconds (μs) for precise analysis")