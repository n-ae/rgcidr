const std = @import("std");
const rgcidr = @import("rgcidr");
const time = std.time;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    std.debug.print("\n=== Realistic Performance Benchmarks ===\n\n", .{});
    
    // Set up patterns once (realistic usage)
    var patterns = try rgcidr.parseMultiplePatterns(
        "10.0.0.0/8,192.168.0.0/16,172.16.0.0/12,127.0.0.0/8",
        false,
        allocator
    );
    defer patterns.deinit();
    
    // Test data
    const test_ips = [_]rgcidr.IPv4{
        try rgcidr.parseIPv4("192.168.1.1"),  // match
        try rgcidr.parseIPv4("10.0.0.1"),     // match
        try rgcidr.parseIPv4("8.8.8.8"),      // no match
        try rgcidr.parseIPv4("172.16.5.5"),   // match
        try rgcidr.parseIPv4("1.2.3.4"),      // no match
        try rgcidr.parseIPv4("127.0.0.1"),    // match
    };
    
    const test_lines = [_][]const u8{
        "2024-01-01 10:32:45 Server 192.168.1.50 connected",
        "2024-01-01 10:32:46 Client 10.0.5.20 authenticated",
        "2024-01-01 10:32:47 External 8.8.8.8 DNS query",
        "2024-01-01 10:32:48 Internal 172.16.10.100 request",
        "2024-01-01 10:32:49 Public 1.2.3.4 connection attempt",
    };
    
    // Benchmark 1: Pattern matching throughput
    std.debug.print("1. Pattern Matching Throughput\n", .{});
    std.debug.print("   Testing {} IPs against {} patterns\n", .{ test_ips.len, patterns.ipv4_ranges.len });
    
    const iterations: u64 = 10_000_000;
    var matches: u64 = 0;
    
    const start = time.nanoTimestamp();
    for (0..iterations) |i| {
        const ip = test_ips[i % test_ips.len];
        if (patterns.matchesIPv4(ip)) {
            matches += 1;
        }
    }
    const elapsed = time.nanoTimestamp() - start;
    
    const ns_per_op = @as(f64, @floatFromInt(elapsed)) / @as(f64, @floatFromInt(iterations));
    const ops_per_sec = 1_000_000_000.0 / ns_per_op;
    
    std.debug.print("   Results: {} iterations in {d:.2}ms\n", .{ iterations, @as(f64, @floatFromInt(elapsed)) / 1_000_000.0 });
    std.debug.print("   Speed: {d:.1} ns/op, {d:.0} ops/sec\n", .{ ns_per_op, ops_per_sec });
    std.debug.print("   Hit rate: {d:.1}%\n\n", .{ @as(f64, @floatFromInt(matches)) * 100.0 / @as(f64, @floatFromInt(iterations)) });
    
    // Benchmark 2: Line scanning with matching
    std.debug.print("2. Line Scanning + Matching\n", .{});
    
    var scanner = rgcidr.IpScanner.init(allocator);
    defer scanner.deinit();
    
    const scan_iterations: u64 = 100_000;
    var found_matches: u64 = 0;
    var total_ips: u64 = 0;
    
    const scan_start = time.nanoTimestamp();
    for (0..scan_iterations) |i| {
        const line = test_lines[i % test_lines.len];
        const ips = try scanner.scanIPv4(line);
        total_ips += ips.len;
        
        for (ips) |ip| {
            if (patterns.matchesIPv4(ip)) {
                found_matches += 1;
            }
        }
    }
    const scan_elapsed = time.nanoTimestamp() - scan_start;
    
    const lines_per_sec = @as(f64, @floatFromInt(scan_iterations)) * 1_000_000_000.0 / @as(f64, @floatFromInt(scan_elapsed));
    
    std.debug.print("   Processed: {} lines\n", .{scan_iterations});
    std.debug.print("   Found: {} IPs total, {} matches\n", .{ total_ips, found_matches });
    std.debug.print("   Speed: {d:.0} lines/sec\n\n", .{lines_per_sec});
    
    // Benchmark 3: Early exit optimization
    std.debug.print("3. Early Exit Optimization Test\n", .{});
    
    const early_iterations: u64 = 100_000;
    var early_matches: u64 = 0;
    
    const early_start = time.nanoTimestamp();
    for (0..early_iterations) |i| {
        const line = test_lines[i % test_lines.len];
        if (try scanner.scanIPv4WithEarlyExit(line, patterns)) |_| {
            early_matches += 1;
        }
    }
    const early_elapsed = time.nanoTimestamp() - early_start;
    
    const early_lines_per_sec = @as(f64, @floatFromInt(early_iterations)) * 1_000_000_000.0 / @as(f64, @floatFromInt(early_elapsed));
    
    std.debug.print("   Processed: {} lines with early exit\n", .{early_iterations});
    std.debug.print("   Matches: {} lines contained matching IPs\n", .{early_matches});
    std.debug.print("   Speed: {d:.0} lines/sec\n", .{early_lines_per_sec});
    std.debug.print("   Speedup vs full scan: {d:.1}x\n\n", .{ early_lines_per_sec / lines_per_sec });
    
    // Benchmark 4: Memory usage
    std.debug.print("4. Memory Efficiency\n", .{});
    std.debug.print("   Pattern storage: {} bytes for {} ranges\n", .{ 
        patterns.ipv4_ranges.len * @sizeOf(rgcidr.IPv4Range),
        patterns.ipv4_ranges.len
    });
    std.debug.print("   Bytes per pattern: {d:.1}\n", .{
        @as(f64, @floatFromInt(patterns.ipv4_ranges.len * @sizeOf(rgcidr.IPv4Range))) / 
        @as(f64, @floatFromInt(patterns.ipv4_ranges.len))
    });
    
    // Benchmark 5: Compare with original estimate
    std.debug.print("\n5. Performance vs C Implementation\n", .{});
    const c_ns_per_match: f64 = 28.0; // From original benchmark
    const zig_ns_per_match = ns_per_op;
    
    std.debug.print("   C implementation: ~{d:.1} ns/match\n", .{c_ns_per_match});
    std.debug.print("   Zig implementation: {d:.1} ns/match\n", .{zig_ns_per_match});
    if (zig_ns_per_match < c_ns_per_match) {
        std.debug.print("   Zig is {d:.1}x faster! ✓\n", .{ c_ns_per_match / zig_ns_per_match });
    } else {
        std.debug.print("   Zig is {d:.1}x slower\n", .{ zig_ns_per_match / c_ns_per_match });
    }
}
