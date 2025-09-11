#!/usr/bin/env lua
-- Simple large dataset profiling to identify performance bottlenecks

local function precise_time()
    return os.clock()
end

local function run_command(cmd)
    local handle = io.popen(cmd .. " 2>&1")
    local result = handle:read("*a")
    local success, exit_type, code = handle:close()
    return result, code or 0
end

print("=== Large Dataset Performance Analysis ===\n")

-- Build rgcidr with optimizations
print("Building rgcidr...")
local build_output, build_code = run_command("zig build -Doptimize=ReleaseFast")
if build_code ~= 0 then
    print("✗ Failed to build rgcidr")
    os.exit(1)
end

-- Generate different dataset sizes to find scaling issues
local function generate_ips(count, seed)
    math.randomseed(seed or 12345)
    local ips = {}
    for i = 1, count do
        table.insert(ips, string.format("%d.%d.%d.%d",
            math.random(1, 223), math.random(0, 255), 
            math.random(0, 255), math.random(1, 254)))
    end
    return table.concat(ips, "\n")
end

-- Test different dataset sizes
local sizes = {100, 500, 1000, 2500, 5000, 10000}
local pattern = "172.16.0.0/12"

print("Dataset Size   | Time (μs) | μs/IP   | Scaling Factor")
print("---------------|-----------|---------|---------------")

local baseline_time_per_ip = nil

for _, size in ipairs(sizes) do
    -- Generate test data
    local test_data = generate_ips(size)
    local temp_file = os.tmpname()
    local f = io.open(temp_file, "w")
    f:write(test_data)
    f:close()
    
    -- Warmup
    for i = 1, 5 do
        run_command(string.format("./zig-out/bin/rgcidr %s %s > /dev/null", pattern, temp_file))
    end
    
    -- Time multiple runs
    local times = {}
    for i = 1, 10 do
        local start = precise_time()
        run_command(string.format("./zig-out/bin/rgcidr %s %s > /dev/null", pattern, temp_file))
        local elapsed_us = (precise_time() - start) * 1000000
        table.insert(times, elapsed_us)
    end
    
    os.remove(temp_file)
    
    -- Calculate statistics
    local sum = 0
    for _, t in ipairs(times) do
        sum = sum + t
    end
    local avg_us = sum / #times
    local us_per_ip = avg_us / size
    
    -- Calculate scaling factor
    local scaling_factor = "baseline"
    if baseline_time_per_ip then
        scaling_factor = string.format("%.2fx", us_per_ip / baseline_time_per_ip)
    else
        baseline_time_per_ip = us_per_ip
    end
    
    print(string.format("%10d     | %7.1f   | %7.3f | %s", 
        size, avg_us, us_per_ip, scaling_factor))
end

print("\n=== Pattern Complexity Analysis ===\n")

-- Test different pattern complexities on 5000 IP dataset
local test_data_5k = generate_ips(5000)
local temp_file_5k = os.tmpname()
local f = io.open(temp_file_5k, "w")  
f:write(test_data_5k)
f:close()

local patterns = {
    {name = "Single CIDR", pattern = "172.16.0.0/12"},
    {name = "Two CIDRs", pattern = "172.16.0.0/12,192.168.0.0/16"},
    {name = "Three CIDRs", pattern = "10.0.0.0/8,172.16.0.0/12,192.168.0.0/16"},
    {name = "Five CIDRs", pattern = "10.0.0.0/8,172.16.0.0/12,192.168.0.0/16,203.0.113.0/24,198.51.100.0/24"},
}

print("Pattern Type     | Time (μs) | vs Single | Patterns")
print("-----------------|-----------|----------|----------")

local single_pattern_time = nil

for _, test in ipairs(patterns) do
    -- Warmup
    for i = 1, 5 do
        run_command(string.format('./zig-out/bin/rgcidr "%s" %s > /dev/null', test.pattern, temp_file_5k))
    end
    
    -- Time multiple runs  
    local times = {}
    for i = 1, 15 do
        local start = precise_time()
        run_command(string.format('./zig-out/bin/rgcidr "%s" %s > /dev/null', test.pattern, temp_file_5k))
        local elapsed_us = (precise_time() - start) * 1000000
        table.insert(times, elapsed_us)
    end
    
    -- Calculate average
    local sum = 0
    for _, t in ipairs(times) do
        sum = sum + t
    end
    local avg_us = sum / #times
    
    -- Calculate ratio
    local ratio = "baseline"
    if single_pattern_time then
        ratio = string.format("%.2fx", avg_us / single_pattern_time)
    else
        single_pattern_time = avg_us
    end
    
    local pattern_count = select(2, string.gsub(test.pattern, ",", ",")) + 1
    
    print(string.format("%-16s | %7.1f   | %-8s | %d", 
        test.name, avg_us, ratio, pattern_count))
end

os.remove(temp_file_5k)

print("\n=== Memory Usage Analysis ===")
print("Running with different optimization levels...\n")

local optimizations = {
    {name = "Debug", flag = "-Doptimize=Debug"},
    {name = "ReleaseSafe", flag = "-Doptimize=ReleaseSafe"}, 
    {name = "ReleaseFast", flag = "-Doptimize=ReleaseFast"},
    {name = "ReleaseSmall", flag = "-Doptimize=ReleaseSmall"},
}

for _, opt in ipairs(optimizations) do
    print(string.format("Building with %s...", opt.name))
    local build_out, build_code = run_command(string.format("zig build %s", opt.flag))
    if build_code == 0 then
        -- Test with medium dataset
        local medium_data = generate_ips(1000)
        local temp_med = os.tmpname()
        local f = io.open(temp_med, "w")
        f:write(medium_data)
        f:close()
        
        local start = precise_time()
        run_command(string.format("./zig-out/bin/rgcidr %s %s > /dev/null", pattern, temp_med))
        local elapsed_us = (precise_time() - start) * 1000000
        
        os.remove(temp_med)
        print(string.format("  %s: %.1fμs (1000 IPs)", opt.name, elapsed_us))
    else
        print(string.format("  %s: BUILD FAILED", opt.name))
    end
end

-- Restore ReleaseFast build
run_command("zig build -Doptimize=ReleaseFast > /dev/null")

print("\n=== Analysis Complete ===")
print("Key findings will help identify optimization opportunities.")