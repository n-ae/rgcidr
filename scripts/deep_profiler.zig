const std = @import("std");
const rgcidr = @import("rgcidr");
const time = std.time;

const ITERATIONS = 1_000_000;

// Profile different optimization strategies
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    std.debug.print("=== Deep Performance Profiler ===\n\n", .{});
    
    // Test 1: Single pattern optimization path validation
    std.debug.print("1. Single Pattern Path Analysis\n", .{});
    
    var single_patterns = try rgcidr.parseMultiplePatterns("192.168.0.0/16", false, allocator);
    defer single_patterns.deinit();
    
    std.debug.print("   Single pattern detected: {}\n", .{single_patterns.single_ipv4_pattern != null});
    std.debug.print("   IPv4 ranges count: {}\n", .{single_patterns.ipv4_ranges.len});
    
    // Test 2: Pattern creation overhead analysis  
    std.debug.print("\n2. Pattern Creation Overhead\n", .{});
    
    const pattern_strings = [_][]const u8{
        "192.168.0.0/16",
        "192.168.0.0/16,10.0.0.0/8", 
        "192.168.0.0/16,10.0.0.0/8,172.16.0.0/12",
    };
    
    for (pattern_strings, 0..) |pattern_str, i| {
        const start = time.nanoTimestamp();
        var patterns = try rgcidr.parseMultiplePatterns(pattern_str, false, allocator);
        defer patterns.deinit();
        const elapsed = time.nanoTimestamp() - start;
        
        std.debug.print("   {} patterns: {}ns creation time\n", .{i + 1, elapsed});
    }
    
    // Test 3: Range comparison strategies
    std.debug.print("\n3. Range Comparison Strategy Analysis\n", .{});
    
    var two_patterns = try rgcidr.parseMultiplePatterns("192.168.0.0/16,10.0.0.0/8", false, allocator);
    defer two_patterns.deinit();
    
    const test_ips = [_]rgcidr.IPv4{
        try rgcidr.parseIPv4("192.168.1.1"),   // matches first
        try rgcidr.parseIPv4("10.0.0.1"),     // matches second
        try rgcidr.parseIPv4("8.8.8.8"),      // matches neither
        try rgcidr.parseIPv4("172.16.1.1"),   // matches neither
    };
    
    // Test current implementation
    var total_time: u64 = 0;
    for (0..10) |_| {
        const start = time.nanoTimestamp();
        for (0..ITERATIONS) |_| {
            for (test_ips) |ip| {
                std.mem.doNotOptimizeAway(two_patterns.matchesIPv4(ip));
            }
        }
        const elapsed = @as(u64, @intCast(time.nanoTimestamp() - start));
        total_time += elapsed;
    }
    
    const avg_time = @as(f64, @floatFromInt(total_time)) / 10.0;
    const ops_per_sec = (@as(f64, @floatFromInt(ITERATIONS * test_ips.len)) / avg_time) * 1e9;
    
    std.debug.print("   Current implementation: {d:.1}M ops/sec\n", .{ops_per_sec / 1_000_000.0});
    
    // Test 4: Memory layout analysis
    std.debug.print("\n4. Memory Layout Analysis\n", .{});
    std.debug.print("   IPv4Range size: {} bytes\n", .{@sizeOf(rgcidr.IPv4Range)});
    std.debug.print("   IPv4Range alignment: {} bytes\n", .{@alignOf(rgcidr.IPv4Range)});
    std.debug.print("   IPv6Range size: {} bytes\n", .{@sizeOf(rgcidr.IPv6Range)});
    std.debug.print("   MultiplePatterns size: {} bytes\n", .{@sizeOf(rgcidr.MultiplePatterns)});
    
    // Test 5: Cache performance simulation
    std.debug.print("\n5. Cache Performance Simulation\n", .{});
    
    // Test with many patterns to stress cache
    var many_patterns = try rgcidr.parseMultiplePatterns(
        "192.168.0.0/24,192.168.1.0/24,192.168.2.0/24,192.168.3.0/24,192.168.4.0/24,192.168.5.0/24,192.168.6.0/24,192.168.7.0/24", 
        false, allocator);
    defer many_patterns.deinit();
    
    std.debug.print("   8 patterns, {} IPv4 ranges\n", .{many_patterns.ipv4_ranges.len});
    
    total_time = 0;
    for (0..5) |_| {
        const start = time.nanoTimestamp();
        for (0..ITERATIONS / 10) |_| {
            for (test_ips) |ip| {
                std.mem.doNotOptimizeAway(many_patterns.matchesIPv4(ip));
            }
        }
        const elapsed_cache = @as(u64, @intCast(time.nanoTimestamp() - start));
        total_time += elapsed_cache;
    }
    
    const avg_cache_time = @as(f64, @floatFromInt(total_time)) / 5.0;
    const cache_ops_per_sec = (@as(f64, @floatFromInt((ITERATIONS / 10) * test_ips.len)) / avg_cache_time) * 1e9;
    
    std.debug.print("   8 patterns performance: {d:.1}M ops/sec\n", .{cache_ops_per_sec / 1_000_000.0});
    
    // Test 6: Branch prediction analysis
    std.debug.print("\n6. Branch Prediction Analysis\n", .{});
    
    const predictable_ips = [_]rgcidr.IPv4{
        try rgcidr.parseIPv4("192.168.1.1"),   // always matches
        try rgcidr.parseIPv4("192.168.1.2"),   // always matches
        try rgcidr.parseIPv4("192.168.1.3"),   // always matches
        try rgcidr.parseIPv4("192.168.1.4"),   // always matches
    };
    
    const unpredictable_ips = [_]rgcidr.IPv4{
        try rgcidr.parseIPv4("192.168.1.1"),   // matches
        try rgcidr.parseIPv4("8.8.8.8"),       // doesn't match
        try rgcidr.parseIPv4("10.0.0.1"),      // matches
        try rgcidr.parseIPv4("1.1.1.1"),       // doesn't match
    };
    
    // Test predictable pattern
    total_time = 0;
    for (0..5) |_| {
        const start = time.nanoTimestamp();
        for (0..ITERATIONS / 10) |_| {
            for (predictable_ips) |ip| {
                std.mem.doNotOptimizeAway(two_patterns.matchesIPv4(ip));
            }
        }
        const elapsed_pred = @as(u64, @intCast(time.nanoTimestamp() - start));
        total_time += elapsed_pred;
    }
    
    const predictable_ops = (@as(f64, @floatFromInt((ITERATIONS / 10) * predictable_ips.len)) / (@as(f64, @floatFromInt(total_time)) / 5.0)) * 1e9;
    
    // Test unpredictable pattern
    total_time = 0;
    for (0..5) |_| {
        const start = time.nanoTimestamp();
        for (0..ITERATIONS / 10) |_| {
            for (unpredictable_ips) |ip| {
                std.mem.doNotOptimizeAway(two_patterns.matchesIPv4(ip));
            }
        }
        const elapsed_unpred = @as(u64, @intCast(time.nanoTimestamp() - start));
        total_time += elapsed_unpred;
    }
    
    const unpredictable_ops = (@as(f64, @floatFromInt((ITERATIONS / 10) * unpredictable_ips.len)) / (@as(f64, @floatFromInt(total_time)) / 5.0)) * 1e9;
    
    std.debug.print("   Predictable branches: {d:.1}M ops/sec\n", .{predictable_ops / 1_000_000.0});
    std.debug.print("   Unpredictable branches: {d:.1}M ops/sec\n", .{unpredictable_ops / 1_000_000.0});
    std.debug.print("   Branch prediction impact: {d:.1}%\n", .{((predictable_ops - unpredictable_ops) / unpredictable_ops) * 100.0});
}