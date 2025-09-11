const std = @import("std");
const rgcidr = @import("rgcidr");
const time = std.time;

const ITERATIONS = 1_000_000;

// Test different optimization strategies
fn benchmarkOriginalMatching() !f64 {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    // Create 2-pattern matcher
    var patterns = try rgcidr.parseMultiplePatterns("192.168.0.0/16,10.0.0.0/8", false, allocator);
    defer patterns.deinit();
    
    const test_ip = try rgcidr.parseIPv4("192.168.1.1");
    
    var total_time: u64 = 0;
    
    for (0..10) |_| {
        const start = time.nanoTimestamp();
        
        for (0..ITERATIONS) |_| {
            std.mem.doNotOptimizeAway(patterns.matchesIPv4(test_ip));
        }
        
        const elapsed = @as(u64, @intCast(time.nanoTimestamp() - start));
        total_time += elapsed;
    }
    
    const avg_time = @as(f64, @floatFromInt(total_time)) / 10.0;
    const ops_per_sec = (@as(f64, @floatFromInt(ITERATIONS)) / avg_time) * 1e9;
    
    return ops_per_sec;
}

// Test optimized branchless matching
fn benchmarkOptimizedMatching() !f64 {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    _ = gpa.allocator();
    
    // Create ranges directly for testing
    const ranges = [_]rgcidr.IPv4Range{
        .{ .min = try rgcidr.parseIPv4("192.168.0.0"), .max = try rgcidr.parseIPv4("192.168.255.255") },
        .{ .min = try rgcidr.parseIPv4("10.0.0.0"), .max = try rgcidr.parseIPv4("10.255.255.255") },
    };
    
    const test_ip = try rgcidr.parseIPv4("192.168.1.1");
    
    var total_time: u64 = 0;
    
    for (0..10) |_| {
        const start = time.nanoTimestamp();
        
        for (0..ITERATIONS) |_| {
            // Optimized branchless check
            const matches = (test_ip >= ranges[0].min and test_ip <= ranges[0].max) or
                           (test_ip >= ranges[1].min and test_ip <= ranges[1].max);
            std.mem.doNotOptimizeAway(matches);
        }
        
        const elapsed = @as(u64, @intCast(time.nanoTimestamp() - start));
        total_time += elapsed;
    }
    
    const avg_time = @as(f64, @floatFromInt(total_time)) / 10.0;
    const ops_per_sec = (@as(f64, @floatFromInt(ITERATIONS)) / avg_time) * 1e9;
    
    return ops_per_sec;
}

// Test single pattern baseline
fn benchmarkSinglePattern() !f64 {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    // Create single pattern matcher
    var patterns = try rgcidr.parseMultiplePatterns("192.168.0.0/16", false, allocator);
    defer patterns.deinit();
    
    const test_ip = try rgcidr.parseIPv4("192.168.1.1");
    
    var total_time: u64 = 0;
    
    for (0..10) |_| {
        const start = time.nanoTimestamp();
        
        for (0..ITERATIONS) |_| {
            std.mem.doNotOptimizeAway(patterns.matchesIPv4(test_ip));
        }
        
        const elapsed = @as(u64, @intCast(time.nanoTimestamp() - start));
        total_time += elapsed;
    }
    
    const avg_time = @as(f64, @floatFromInt(total_time)) / 10.0;
    const ops_per_sec = (@as(f64, @floatFromInt(ITERATIONS)) / avg_time) * 1e9;
    
    return ops_per_sec;
}

pub fn main() !void {
    std.debug.print("=== Optimization Strategy Benchmark ===\n", .{});
    std.debug.print("Testing {} operations each\n\n", .{ITERATIONS});
    
    const single_ops = try benchmarkSinglePattern();
    const original_ops = try benchmarkOriginalMatching();  
    const optimized_ops = try benchmarkOptimizedMatching();
    
    std.debug.print("Results (Million ops/sec):\n", .{});
    std.debug.print("Single Pattern:      {d:>8.1}\n", .{single_ops / 1_000_000.0});
    std.debug.print("Two Patterns (orig): {d:>8.1}\n", .{original_ops / 1_000_000.0});
    std.debug.print("Two Patterns (opt):  {d:>8.1}\n", .{optimized_ops / 1_000_000.0});
    
    const original_overhead = ((single_ops - original_ops) / single_ops) * 100.0;
    const optimized_overhead = ((single_ops - optimized_ops) / single_ops) * 100.0;
    const improvement = ((optimized_ops - original_ops) / original_ops) * 100.0;
    
    std.debug.print("\nAnalysis:\n", .{});
    std.debug.print("Original overhead:   {d:>6.1}%\n", .{original_overhead});
    std.debug.print("Optimized overhead:  {d:>6.1}%\n", .{optimized_overhead});
    std.debug.print("Improvement:         {d:>6.1}%\n", .{improvement});
}