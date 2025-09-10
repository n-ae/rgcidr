//! Examples demonstrating rgcidr library usage

const std = @import("std");
const rgcidr = @import("rgcidr");

/// Basic pattern matching example
pub fn basicExample(allocator: std.mem.Allocator) !void {
    std.debug.print("\n=== Basic Pattern Matching ===\n", .{});
    
    // Parse a CIDR pattern
    const pattern = try rgcidr.parsePattern("192.168.0.0/16", false);
    
    // Check if an IP matches
    const ip1 = try rgcidr.parseIPv4("192.168.1.1");
    const ip2 = try rgcidr.parseIPv4("10.0.0.1");
    
    std.debug.print("192.168.1.1 matches 192.168.0.0/16: {}\n", .{pattern.matchesIPv4(ip1)});
    std.debug.print("10.0.0.1 matches 192.168.0.0/16: {}\n", .{pattern.matchesIPv4(ip2)});
}

/// Multiple patterns with optimized matching
pub fn multiplePatternExample(allocator: std.mem.Allocator) !void {
    std.debug.print("\n=== Multiple Pattern Matching ===\n", .{});
    
    // Parse multiple patterns (private IP ranges)
    var patterns = try rgcidr.parseMultiplePatterns(
        "10.0.0.0/8,172.16.0.0/12,192.168.0.0/16",
        false,
        allocator
    );
    defer patterns.deinit();
    
    // Test various IPs
    const test_ips = [_][]const u8{
        "10.1.1.1",      // Private Class A
        "172.20.1.1",    // Private Class B
        "192.168.1.1",   // Private Class C
        "8.8.8.8",       // Public (Google DNS)
    };
    
    for (test_ips) |ip_str| {
        const ip = try rgcidr.parseIPv4(ip_str);
        const is_private = patterns.matchesIPv4(ip);
        std.debug.print("{s}: {s}\n", .{ 
            ip_str, 
            if (is_private) "Private" else "Public" 
        });
    }
}

/// Scanning text for IP addresses
pub fn scannerExample(allocator: std.mem.Allocator) !void {
    std.debug.print("\n=== IP Scanner Example ===\n", .{});
    
    var scanner = rgcidr.IpScanner.init(allocator);
    defer scanner.deinit();
    
    const log_line = "2024-01-01 10:00:00 Server 192.168.1.50 connected to 2001:db8::1 from 10.0.0.1";
    
    // Scan for IPv4 addresses
    const ipv4s = try scanner.scanIPv4(log_line);
    std.debug.print("Found {} IPv4 addresses:\n", .{ipv4s.len});
    for (ipv4s) |ip| {
        var buf: [16]u8 = undefined;
        const ip_str = try std.fmt.bufPrint(&buf, "{}.{}.{}.{}", .{
            (ip >> 24) & 0xFF,
            (ip >> 16) & 0xFF,
            (ip >> 8) & 0xFF,
            ip & 0xFF,
        });
        std.debug.print("  {s}\n", .{ip_str});
    }
    
    // Scan for IPv6 addresses
    const ipv6s = try scanner.scanIPv6(log_line);
    std.debug.print("Found {} IPv6 addresses:\n", .{ipv6s.len});
    for (ipv6s) |ip| {
        std.debug.print("  {x}\n", .{ip});
    }
}

/// IPv6 pattern matching
pub fn ipv6Example(allocator: std.mem.Allocator) !void {
    std.debug.print("\n=== IPv6 Pattern Matching ===\n", .{});
    
    // Parse IPv6 CIDR
    const pattern = try rgcidr.parsePattern("2001:db8::/32", false);
    
    // Test various IPv6 addresses
    const test_addrs = [_][]const u8{
        "2001:db8::1",           // Matches
        "2001:db8:1234::5678",   // Matches
        "2001:db9::1",           // Doesn't match
        "::1",                   // Doesn't match (loopback)
    };
    
    for (test_addrs) |addr| {
        const ip = try rgcidr.parseIPv6(addr);
        const matches = pattern.matchesIPv6(ip);
        std.debug.print("{s}: {s}\n", .{
            addr,
            if (matches) "matches" else "no match"
        });
    }
}

/// IP range matching (non-CIDR)
pub fn rangeExample(allocator: std.mem.Allocator) !void {
    std.debug.print("\n=== IP Range Matching ===\n", .{});
    
    // Parse an IP range
    const pattern = try rgcidr.parsePattern("192.168.1.10-192.168.1.20", false);
    
    // Test IPs
    const test_ips = [_][]const u8{
        "192.168.1.9",   // Before range
        "192.168.1.10",  // Start of range
        "192.168.1.15",  // Middle of range
        "192.168.1.20",  // End of range
        "192.168.1.21",  // After range
    };
    
    for (test_ips) |ip_str| {
        const ip = try rgcidr.parseIPv4(ip_str);
        const in_range = pattern.matchesIPv4(ip);
        std.debug.print("{s}: {s}\n", .{
            ip_str,
            if (in_range) "in range" else "out of range"
        });
    }
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    try basicExample(allocator);
    try multiplePatternExample(allocator);
    try scannerExample(allocator);
    try ipv6Example(allocator);
    try rangeExample(allocator);
    
    std.debug.print("\n", .{});
}
