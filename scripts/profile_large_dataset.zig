const std = @import("std");
const rgcidr = @import("rgcidr");
const time = std.time;

const BenchmarkResult = struct {
    name: []const u8,
    iterations: u64,
    total_us: i128,
    avg_us: f64,
    min_us: i128,
    max_us: i128,
    ops_per_sec: f64,
};

fn benchmark(comptime name: []const u8, iterations: u64, comptime func: anytype) !BenchmarkResult {
    var min_time: i128 = std.math.maxInt(i128);
    var max_time: i128 = 0;
    var total_time: i128 = 0;

    for (0..iterations) |_| {
        const start = time.microTimestamp();
        _ = try func();
        const elapsed = time.microTimestamp() - start;
        
        total_time += elapsed;
        min_time = @min(min_time, elapsed);
        max_time = @max(max_time, elapsed);
    }
    
    const avg_us = @as(f64, @floatFromInt(total_time)) / @as(f64, @floatFromInt(iterations));
    const ops_per_sec = 1_000_000.0 / avg_us;

    return BenchmarkResult{
        .name = name,
        .iterations = iterations,
        .total_us = total_time,
        .avg_us = avg_us,
        .min_us = min_time,
        .max_us = max_time,
        .ops_per_sec = ops_per_sec,
    };
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("=== Large Dataset Performance Profile ===\n\n", .{});

    // Create large test data similar to benchmark  
    var large_ips = std.ArrayList([]const u8){};
    large_ips = std.ArrayList([]const u8).init(allocator);
    defer {
        for (large_ips.items) |ip| {
            allocator.free(ip);
        }
        large_ips.deinit();
    }
    
    // Generate 10,000 IPs (matching benchmark_unified.lua large dataset)
    const ip_count = 10000;
    var prng = std.rand.DefaultPrng.init(12345); // Fixed seed for consistency
    const rand = prng.random();
    
    for (0..ip_count) |_| {
        const ip_str = try std.fmt.allocPrint(allocator, "{}.{}.{}.{}", .{
            rand.intRangeAtMost(u8, 1, 223),
            rand.intRangeAtMost(u8, 0, 255), 
            rand.intRangeAtMost(u8, 0, 255),
            rand.intRangeAtMost(u8, 1, 254),
        });
        try large_ips.append(ip_str);
    }
    
    // Create test patterns
    var patterns = try rgcidr.parseMultiplePatterns("172.16.0.0/12", false, allocator);
    defer patterns.deinit();
    
    std.debug.print("Generated {} test IPs\n", .{large_ips.items.len});
    std.debug.print("Pattern: 172.16.0.0/12 (matches ~780 IPs)\n\n", .{});

    // Benchmark 1: Individual IP parsing
    const ip_parse = try benchmark("IP Parsing (per IP)", 1000, struct {
        const ips = &large_ips.items;
        var idx: usize = 0;
        fn call() !u32 {
            const ip_str = ips[idx % ips.len];
            idx += 1;
            return try rgcidr.parseIPv4(ip_str);
        }
    }.call);

    // Benchmark 2: Pattern matching (per IP)
    const pattern_match = try benchmark("Pattern Matching (per IP)", 10000, struct {
        const ips = &large_ips.items;
        const pats = &patterns;
        var idx: usize = 0;
        fn call() !bool {
            const ip_str = ips[idx % ips.len];
            idx += 1;
            const ip = try rgcidr.parseIPv4(ip_str);
            return pats.matchesIPv4(ip);
        }
    }.call);

    // Benchmark 3: Line scanning simulation (full dataset)
    const line_scan = try benchmark("Full Dataset Scan", 20, struct {
        const ips = &large_ips.items;
        const pats = &patterns;
        fn call() !usize {
            var scanner = rgcidr.IpScanner.init(allocator);
            defer scanner.deinit();
            
            var matches: usize = 0;
            for (ips) |ip_str| {
                const ip = rgcidr.parseIPv4(ip_str) catch continue;
                if (pats.matchesIPv4(ip)) {
                    matches += 1;
                }
            }
            return matches;
        }
    }.call);

    // Benchmark 4: Memory allocation patterns
    const memory_stress = try benchmark("Memory Allocation Stress", 100, struct {
        fn call() !usize {
            var temp_scanner = rgcidr.IpScanner.init(allocator);
            defer temp_scanner.deinit();
            
            // Simulate scanning 100 lines with multiple IPs each
            var total_found: usize = 0;
            for (0..100) |i| {
                const line = try std.fmt.allocPrint(allocator, 
                    "Server {}.{}.{}.{} connected from {}.{}.{}.{} at port {}", .{
                    i % 192 + 1, i % 168 + 1, i % 255 + 1, i % 254 + 1,
                    i % 172 + 1, i % 16 + 1, i % 255 + 1, i % 254 + 1,
                    8080 + i % 1000
                });
                defer allocator.free(line);
                
                const found_ips = try temp_scanner.scanIPv4(line);
                total_found += found_ips.len;
            }
            return total_found;
        }
    }.call);

    // Print results
    const results = [_]BenchmarkResult{
        ip_parse,
        pattern_match, 
        line_scan,
        memory_stress,
    };

    std.debug.print("Operation                    Iterations    Avg(μs)    Min(μs)    Max(μs)    Ops/sec\n", .{});
    std.debug.print("---------------------------  ----------    -------    -------    -------    ----------\n", .{});

    for (results) |result| {
        std.debug.print("{s:<27}  {d:>10}    {d:>7.2}    {d:>7}    {d:>7}    {d:>10.0}\n", .{
            result.name,
            result.iterations,
            result.avg_us,
            result.min_us,
            result.max_us,
            result.ops_per_sec,
        });
    }

    std.debug.print("\n=== Analysis ===\n", .{});
    std.debug.print("Per-IP parsing time: {d:.2}μs\n", .{ip_parse.avg_us});
    std.debug.print("Per-IP matching time: {d:.2}μs\n", .{pattern_match.avg_us});
    std.debug.print("Full dataset scan time: {d:.1}μs ({} IPs)\n", .{line_scan.avg_us, ip_count});
    std.debug.print("Memory allocation overhead: {d:.1}μs per allocation cycle\n", .{memory_stress.avg_us});
    
    // Calculate theoretical vs actual performance
    const theoretical_time = (@as(f64, @floatFromInt(ip_count)) * (ip_parse.avg_us + pattern_match.avg_us));
    const actual_time = line_scan.avg_us;
    const efficiency = theoretical_time / actual_time;
    
    std.debug.print("\nScaling Analysis:\n", .{});
    std.debug.print("Theoretical time for {} IPs: {d:.1}μs\n", .{ip_count, theoretical_time});
    std.debug.print("Actual scan time: {d:.1}μs\n", .{actual_time});
    std.debug.print("Efficiency ratio: {d:.2}x {s}\n", .{efficiency, if (efficiency > 1) "(efficient)" else "(inefficient)"});
}