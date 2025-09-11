const std = @import("std");
const rgcidr = @import("rgcidr");
const time = std.time;

const BenchmarkResult = struct {
    name: []const u8,
    iterations: u64,
    total_us: i128,
    min_us: i128,
    max_us: i128,
    avg_us: f64,
    ops_per_sec: f64,
};

fn benchmark(comptime name: []const u8, iterations: u64, func: anytype) !BenchmarkResult {
    var min_time: i128 = std.math.maxInt(i128);
    var max_time: i128 = 0;
    var total_time: i128 = 0;
    
    // Warmup
    for (0..100) |_| {
        _ = try func();
    }
    
    // Actual benchmark
    for (0..iterations) |_| {
        const start = time.microTimestamp();
        _ = try func();
        const end = time.microTimestamp();
        const elapsed_us = end - start;
        
        min_time = @min(min_time, elapsed_us);
        max_time = @max(max_time, elapsed_us);
        total_time += elapsed_us;
    }
    
    const avg_us = @as(f64, @floatFromInt(total_time)) / @as(f64, @floatFromInt(iterations));
    const ops_per_sec = 1_000_000.0 / avg_us;
    
    return BenchmarkResult{
        .name = name,
        .iterations = iterations,
        .total_us = total_time,
        .min_us = min_time,
        .max_us = max_time,
        .avg_us = avg_us,
        .ops_per_sec = ops_per_sec,
    };
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    std.debug.print("=== Detailed Performance Profile ===\n\n", .{});
    
    // Benchmark 1: IPv4 parsing
    const ipv4_parse = try benchmark("IPv4 Parsing", 1_000_000, struct {
        fn call() !void {
            _ = try rgcidr.parseIPv4("192.168.1.1");
        }
    }.call);
    
    // Benchmark 2: IPv6 parsing  
    const ipv6_parse = try benchmark("IPv6 Parsing", 1_000_000, struct {
        fn call() !void {
            _ = try rgcidr.parseIPv6("2001:db8::1");
        }
    }.call);
    
    // Benchmark 3: Pattern parsing
    const pattern_parse = try benchmark("Pattern Parsing", 100_000, struct {
        fn call() !void {
            _ = try rgcidr.parsePattern("192.168.0.0/16", false);
        }
    }.call);
    
    // Benchmark 4: Pattern matching (single)    
    const pattern_match = try benchmark("Single Pattern Match", 10_000_000, struct {
        fn call() !bool {
            const pattern = try rgcidr.parsePattern("192.168.0.0/16", false);
            const ip = try rgcidr.parseIPv4("192.168.1.1");
            return pattern.matchesIPv4(ip);
        }
    }.call);
    
    // Benchmark 5: Multiple pattern setup and matching
    var patterns = try rgcidr.parseMultiplePatterns(
        "10.0.0.0/8,192.168.0.0/16,172.16.0.0/12",
        false,
        allocator
    );
    defer patterns.deinit();
    
    const multi_match = try benchmark("Multi Pattern Match", 5_000_000, struct {
        fn call() !bool {
            // Parse patterns in each call
            var gpa2 = std.heap.GeneralPurposeAllocator(.{}){};
            defer _ = gpa2.deinit();
            const alloc = gpa2.allocator();
            
            var pats = try rgcidr.parseMultiplePatterns(
                "10.0.0.0/8,192.168.0.0/16",
                false,
                alloc
            );
            defer pats.deinit();
            const ip = try rgcidr.parseIPv4("192.168.1.1");
            return pats.matchesIPv4(ip);
        }
    }.call);
    
    // Benchmark 6: Line scanning
    const line_scan = try benchmark("Line Scan IPv4", 50_000, struct {
        fn call() !usize {
            var gpa2 = std.heap.GeneralPurposeAllocator(.{}){};
            defer _ = gpa2.deinit();
            const alloc = gpa2.allocator();
            
            var scan = rgcidr.IpScanner.init(alloc);
            defer scan.deinit();
            
            const line = "Server 192.168.1.50 connected from 10.0.0.1";
            const ips = try scan.scanIPv4(line);
            return ips.len;
        }
    }.call);
    
    const line_scan_ipv6 = try benchmark("Line Scan IPv6", 50_000, struct {
        fn call() !usize {
            var gpa2 = std.heap.GeneralPurposeAllocator(.{}){};
            defer _ = gpa2.deinit();
            const alloc = gpa2.allocator();
            
            var scan = rgcidr.IpScanner.init(alloc);
            defer scan.deinit();
            
            const line = "Server 2001:db8::1 connected from fe80::1";
            const ips = try scan.scanIPv6(line);
            return ips.len;
        }
    }.call);
    
    // Benchmark 7: Binary search performance  
    const binary_search = try benchmark("Binary Search", 10_000_000, struct {
        fn call() !bool {
            // Simulate binary search on sorted array
            const test_ranges = [_]rgcidr.IPv4Range{
                .{ .min = 0x0A000000, .max = 0x0AFFFFFF }, // 10.0.0.0/8
                .{ .min = 0xAC100000, .max = 0xAC1FFFFF }, // 172.16.0.0/12
                .{ .min = 0xC0A80000, .max = 0xC0A8FFFF }, // 192.168.0.0/16
            };
            const ip = 0xC0A80101; // 192.168.1.1
            
            var left: usize = 0;
            var right: usize = test_ranges.len;
            
            while (left < right) {
                const mid = (left + right) / 2;
                const range = test_ranges[mid];
                
                if (ip < range.min) {
                    right = mid;
                } else if (ip > range.max) {
                    left = mid + 1;
                } else {
                    return true;
                }
            }
            return false;
        }
    }.call);
    
    // Print results
    const results = [_]BenchmarkResult{
        ipv4_parse,
        ipv6_parse,
        pattern_parse,
        pattern_match,
        multi_match,
        line_scan,
        line_scan_ipv6,
        binary_search,
    };
    
    std.debug.print("Operation                   Iterations    Min(μs)    Avg(μs)    Max(μs)    Avg(ns)    Ops/sec\n", .{});
    std.debug.print("-------------------------   ----------   --------   --------   --------   --------   ----------\n", .{});
    
    for (results) |result| {
        const avg_ns = result.avg_us * 1_000.0; // Convert to nanoseconds for display only
        
        std.debug.print("{s:<25}   {d:>10}   {d:>8.3}   {d:>8.3}   {d:>8.3}   {d:>8.1}   {d:>10.0}\n", .{
            result.name,
            result.iterations,
            @as(f64, @floatFromInt(result.min_us)),
            result.avg_us,
            @as(f64, @floatFromInt(result.max_us)),
            avg_ns,
            result.ops_per_sec,
        });
    }
    
    // Memory analysis
    std.debug.print("\n=== Memory Analysis ===\n", .{});
    std.debug.print("IPv4Range size: {} bytes\n", .{@sizeOf(rgcidr.IPv4Range)});
    std.debug.print("IPv6Range size: {} bytes\n", .{@sizeOf(rgcidr.IPv6Range)});
    std.debug.print("Pattern size: {} bytes\n", .{@sizeOf(rgcidr.Pattern)});
    std.debug.print("MultiplePatterns size: {} bytes\n", .{@sizeOf(rgcidr.MultiplePatterns)});
    
    // Cache line analysis
    std.debug.print("\n=== Cache Analysis ===\n", .{});
    const cache_line_size = 64;
    std.debug.print("IPv4Ranges per cache line: {}\n", .{cache_line_size / @sizeOf(rgcidr.IPv4Range)});
    std.debug.print("Binary search depth for {} patterns: {}\n", .{ patterns.ipv4_ranges.len, std.math.log2(patterns.ipv4_ranges.len) });
}
