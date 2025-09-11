const std = @import("std");
const rgcidr = @import("rgcidr");
const time = std.time;

const ITERATIONS = 100_000;

// Test patterns for micro-benchmarks
const TEST_PATTERNS = [_][]const u8{
    "192.168.0.0/16",
    "10.0.0.0/8,192.168.0.0/16",
    "172.16.0.0/12,192.168.0.0/16,10.0.0.0/8",
    "172.16.0.0/12,192.168.0.0/16,10.0.0.0/8,203.0.113.0/24,198.51.100.0/24,198.18.0.0/15",
    "172.16.0.0/12,192.168.0.0/16,10.0.0.0/8,203.0.113.0/24,198.51.100.0/24,198.18.0.0/15,100.64.0.0/10,169.254.0.0/16",
};

// Test IPs - mix of matching and non-matching
const TEST_IPS = [_][]const u8{
    "192.168.1.100",  // matches common patterns
    "10.0.0.1",       // matches 10.0.0.0/8
    "172.16.5.5",     // matches 172.16.0.0/12
    "8.8.8.8",        // public IP - won't match most patterns
    "1.2.3.4",        // another public IP
    "203.0.113.50",   // test pattern specific
    "127.0.0.1",      // localhost
    "169.254.1.1",    // link-local
};

// Benchmark structure
const MicroBenchmark = struct {
    name: []const u8,
    pattern_count: usize,
    total_time_ns: u64,
    min_time_ns: u64,
    max_time_ns: u64,
    ops_per_sec: f64,
};

fn runMicroBenchmark(name: []const u8, pattern_str: []const u8, allocator: std.mem.Allocator) !MicroBenchmark {
    // Setup patterns once
    var patterns = try rgcidr.parseMultiplePatterns(pattern_str, false, allocator);
    defer patterns.deinit();
    
    // Parse test IPs once
    var test_ips: [TEST_IPS.len]rgcidr.IPv4 = undefined;
    for (TEST_IPS, 0..) |ip_str, i| {
        test_ips[i] = try rgcidr.parseIPv4(ip_str);
    }
    
    var min_time: u64 = std.math.maxInt(u64);
    var max_time: u64 = 0;
    var total_time: u64 = 0;
    
    // Warmup
    for (0..1000) |_| {
        for (test_ips) |ip| {
            _ = patterns.matchesIPv4(ip);
        }
    }
    
    // Actual benchmark
    const iterations_per_run = ITERATIONS / 10;
    for (0..10) |_| {
        const start = time.nanoTimestamp();
        
        // Core benchmark loop - test each IP against patterns
        for (0..iterations_per_run) |_| {
            for (test_ips) |ip| {
                std.mem.doNotOptimizeAway(patterns.matchesIPv4(ip));
            }
        }
        
        const elapsed = @as(u64, @intCast(time.nanoTimestamp() - start));
        total_time += elapsed;
        min_time = @min(min_time, elapsed);
        max_time = @max(max_time, elapsed);
    }
    
    const avg_time_ns = total_time / 10;
    const total_ops = iterations_per_run * TEST_IPS.len * 10;
    const ops_per_sec = @as(f64, @floatFromInt(total_ops)) / (@as(f64, @floatFromInt(total_time)) / 1e9);
    
    return MicroBenchmark{
        .name = name,
        .pattern_count = std.mem.count(u8, pattern_str, ",") + 1,
        .total_time_ns = avg_time_ns,
        .min_time_ns = min_time,
        .max_time_ns = max_time,
        .ops_per_sec = ops_per_sec,
    };
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    std.debug.print("=== rgcidr Micro-Benchmark Suite ===\n\n", .{});
    std.debug.print("Testing pattern matching performance with {} iterations\n", .{ITERATIONS});
    std.debug.print("Each test uses {} different IP addresses\n\n", .{TEST_IPS.len});
    
    var results = std.ArrayList(MicroBenchmark){};
    defer results.deinit(allocator);
    
    // Test different pattern counts
    for (TEST_PATTERNS, 0..) |pattern, i| {
        const test_name = switch (i) {
            0 => "Single Pattern",
            1 => "Two Patterns", 
            2 => "Three Patterns",
            3 => "Six Patterns",
            4 => "Eight Patterns",
            else => "Unknown",
        };
        
        const result = try runMicroBenchmark(test_name, pattern, allocator);
        try results.append(allocator, result);
        
        std.debug.print("✓ Completed: {s}\n", .{test_name});
    }
    
    // Print results table
    std.debug.print("\n=== Micro-Benchmark Results ===\n", .{});
    std.debug.print("Test                 | Patterns | Avg(ns) | Min(ns) | Max(ns) | M ops/sec\n", .{});
    std.debug.print("---------------------|----------|---------|---------|---------|----------\n", .{});
    
    for (results.items) |result| {
        std.debug.print("{s:<20} | {d:>8} | {d:>7} | {d:>7} | {d:>7} | {d:>9.1}\n", .{
            result.name,
            result.pattern_count,
            result.total_time_ns,
            result.min_time_ns, 
            result.max_time_ns,
            result.ops_per_sec / 1_000_000.0,
        });
    }
    
    // Analysis
    std.debug.print("\n=== Performance Analysis ===\n", .{});
    if (results.items.len >= 2) {
        const single_ops = results.items[0].ops_per_sec;
        const multi_ops = results.items[1].ops_per_sec;
        const overhead_percent = ((single_ops - multi_ops) / single_ops) * 100.0;
        std.debug.print("Multi-pattern overhead: {d:.1}%\n", .{overhead_percent});
        
        // Linear vs binary search analysis
        if (results.items.len >= 4) {
            const linear_ops = results.items[2].ops_per_sec; // 3 patterns (linear)
            const binary_ops = results.items[3].ops_per_sec; // 6 patterns (could be binary)
            const algorithm_diff = ((linear_ops - binary_ops) / linear_ops) * 100.0;
            std.debug.print("Linear vs Binary search impact: {d:.1}%\n", .{algorithm_diff});
        }
    }
    
    // Suggest optimizations
    std.debug.print("\n=== Optimization Opportunities ===\n", .{});
    std.debug.print("1. Inline hot functions (matchesIPv4/IPv6)\n", .{});
    std.debug.print("2. Comptime pattern count specialization\n", .{});
    std.debug.print("3. Cache-optimized memory layout\n", .{});
    std.debug.print("4. SIMD-optimized range checks\n", .{});
}