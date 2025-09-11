//! rgcidr - A Zig library for filtering IPv4 and IPv6 addresses against CIDR patterns
//!
//! This library provides fast IP address parsing and matching capabilities,
//! supporting single IPs, CIDR ranges, and IP ranges for both IPv4 and IPv6.
//!
//! ## Usage
//!
//! ```zig
//! const rgcidr = @import("rgcidr");
//!
//! // Parse and match IPv4 addresses
//! const pattern = try rgcidr.parsePattern("192.168.0.0/16", false);
//! const ip = try rgcidr.parseIPv4("192.168.1.1");
//! const matches = pattern.matchesIPv4(ip); // true
//!
//! // Scan lines for IP addresses
//! var scanner = rgcidr.IpScanner.init(allocator);
//! defer scanner.deinit();
//! const ips = try scanner.scanIPv4("Server 192.168.1.1 responded");
//! ```

const std = @import("std");
const ArrayList = std.ArrayList;
const Allocator = std.mem.Allocator;

// # Public API Types

/// IPv4 address represented as a 32-bit integer in network byte order
pub const IPv4 = u32;

/// IPv6 address represented as a 128-bit integer
pub const IPv6 = u128;

// CIDR network specification
pub const CidrPattern = struct {
    min: IPv4,
    max: IPv4,
    network: IPv4, // Original network address
    mask_bits: u8, // Number of network bits (0-32)

    pub fn containsIP(self: CidrPattern, ip: IPv4) bool {
        return ip >= self.min and ip <= self.max;
    }
};

// IPv6 CIDR network specification
pub const Ipv6CidrPattern = struct {
    min: IPv6,
    max: IPv6,
    network: IPv6, // Original network address
    mask_bits: u8, // Number of network bits (0-128)

    pub fn containsIP(self: Ipv6CidrPattern, ip: IPv6) bool {
        return ip >= self.min and ip <= self.max;
    }
};

// IP range specification (start-end notation)
pub const IpRange = struct {
    start: IPv4,
    end: IPv4,

    pub fn containsIP(self: IpRange, ip: IPv4) bool {
        return ip >= self.start and ip <= self.end;
    }
};

/// Extract embedded IPv4 address from IPv6 address if present
/// Handles IPv4-mapped IPv6 (::ffff:x.x.x.x) and IPv6 with embedded IPv4 (::x.x.x.x)
pub fn extractEmbeddedIPv4(ipv6: IPv6) ?IPv4 {
    // IPv4-mapped IPv6: ::ffff:x.x.x.x
    // Parsed format: upper 96 bits contain 0xffff, lower 32 bits contain IPv4
    const upper_96_bits = ipv6 >> 32;
    const lower_32_bits = ipv6 & 0xFFFFFFFF;

    // Check for IPv4-mapped IPv6 (::ffff:x.x.x.x)
    if (upper_96_bits == 0xFFFF) {
        return @intCast(lower_32_bits);
    }

    // Check for IPv6 with embedded IPv4 (::x.x.x.x)
    // This means the upper 96 bits are zero and lower 32 bits contain a valid IPv4
    if (upper_96_bits == 0 and lower_32_bits != 0) {
        return @intCast(lower_32_bits);
    }

    return null;
}

// Pattern type - can be single IP, CIDR range, or IPv4 range
pub const Pattern = union(enum) {
    single_ipv4: IPv4,
    ipv4_cidr: CidrPattern,
    ipv4_range: IpRange,
    single_ipv6: IPv6,
    ipv6_cidr: Ipv6CidrPattern,

    pub fn matchesIPv4(self: Pattern, ip: IPv4) bool {
        return switch (self) {
            .single_ipv4 => |single| single == ip,
            .ipv4_cidr => |cidr| cidr.containsIP(ip),
            .ipv4_range => |range| range.containsIP(ip),
            // IPv6 patterns don't match IPv4 addresses
            .single_ipv6, .ipv6_cidr => false,
        };
    }

    pub fn matchesIPv6(self: Pattern, ip: IPv6) bool {
        return switch (self) {
            .single_ipv6 => |single| single == ip,
            .ipv6_cidr => |cidr| cidr.containsIP(ip),
            // Check if IPv6 contains embedded IPv4 that matches IPv4 patterns
            .single_ipv4, .ipv4_cidr, .ipv4_range => {
                if (extractEmbeddedIPv4(ip)) |ipv4| {
                    return self.matchesIPv4(ipv4);
                }
                return false;
            },
        };
    }
};

/// Errors that can occur during IP address and pattern parsing
pub const IpParseError = error{
    /// Invalid IP address or pattern format
    InvalidFormat,
    /// IPv4 octet value outside 0-255 range
    InvalidOctet,
    /// CIDR mask bits invalid (>32 for IPv4, >128 for IPv6)
    InvalidMask,
    /// IP range where start > end
    InvalidRange,
    /// CIDR network address not properly aligned (strict mode)
    MisalignedCidr,
    /// Insufficient memory for operation
    OutOfMemory,
};

// # Core Parsing Functions

/// Parse an IPv6 address string into a 128-bit integer
///
/// Supports standard IPv6 formats including:
/// - Full notation: 2001:0db8:85a3:0000:0000:8a2e:0370:7334
/// - Compressed notation: 2001:db8:85a3::8a2e:370:7334
/// - IPv4-mapped IPv6: ::ffff:192.168.1.1
/// - Embedded IPv4: 2001:db8::192.168.1.1
///
/// ## Parameters
/// - `ip_str`: String containing the IPv6 address
///
/// ## Returns
/// - `IPv6`: Parsed address as 128-bit integer
/// - `IpParseError`: If the address format is invalid
pub fn parseIPv6(ip_str: []const u8) IpParseError!IPv6 {

    // Handle IPv6 with embedded IPv4 (like 2001:db8::192.168.1.1)
    // Only treat as embedded IPv4 if there are dots AND it looks like a valid IPv4 at the end
    if (std.mem.lastIndexOfScalar(u8, ip_str, '.')) |dot_pos| {
        if (std.mem.lastIndexOfScalar(u8, ip_str, ':')) |colon_pos| {
            if (colon_pos < dot_pos) {
                // There's a colon before the dot, might be embedded IPv4
                const potential_ipv4 = ip_str[colon_pos + 1 ..];
                // Check if it looks like a valid IPv4 (contains at least 3 dots AND no colons)
                var dot_count: u8 = 0;
                var has_colon = false;
                for (potential_ipv4) |c| {
                    if (c == '.') dot_count += 1;
                    if (c == ':') has_colon = true;
                }
                if (dot_count == 3 and !has_colon) {
                    // Try to parse as embedded IPv4
                    return parseIPv6WithEmbeddedIPv4(ip_str);
                }
            }
        }
    }

    return parseIPv6Pure(ip_str);
}

/// Parse IPv6 address with embedded IPv4
fn parseIPv6WithEmbeddedIPv4(ip_str: []const u8) IpParseError!IPv6 {
    // Check if the full string has :: compression before splitting
    const full_has_compression = std.mem.indexOf(u8, ip_str, "::") != null;

    // Split IPv6 prefix from IPv4 part
    if (std.mem.lastIndexOfScalar(u8, ip_str, '.')) |last_dot_pos| {
        // Find the colon that immediately precedes the IPv4 part
        var colon_pos: usize = 0;
        var found_colon = false;
        var i = last_dot_pos;
        while (i > 0) {
            i -= 1;
            if (ip_str[i] == ':') {
                colon_pos = i;
                found_colon = true;
                break;
            }
            if (!std.ascii.isDigit(ip_str[i]) and ip_str[i] != '.') {
                break; // Not part of IPv4
            }
        }

        if (!found_colon) return IpParseError.InvalidFormat;

        const ipv6_prefix = ip_str[0..colon_pos];
        const ipv4_part = ip_str[colon_pos + 1 ..];

        // Validate and parse IPv4 part
        const ipv4_addr = parseIPv4(ipv4_part) catch return IpParseError.InvalidFormat;

        // Validate IPv6 prefix has correct number of groups for embedded IPv4
        // IPv6 with embedded IPv4 should have exactly 6 groups + IPv4 = 128 bits total
        // Count groups in the prefix
        var explicit_groups: u32 = 0;
        if (ipv6_prefix.len > 0) {
            // Count explicit hex groups (non-empty between colons)
            var parts = std.mem.splitSequence(u8, ipv6_prefix, ":");
            while (parts.next()) |part| {
                if (part.len > 0) explicit_groups += 1;
            }

            if (full_has_compression) {
                // With compression, explicit_groups must be < 6
                if (explicit_groups > 6) return IpParseError.InvalidFormat;
                // Total groups after expansion will be 6
            } else {
                if (explicit_groups != 6) return IpParseError.InvalidFormat;
            }
        }

        // Parse IPv6 prefix
        var base_addr: u128 = 0;
        if (ipv6_prefix.len > 0) {
            // For addresses like "64:ff9b::192.168.1.1", we need to reconstruct the IPv6 address
            // The original address should be parsed as if the embedded IPv4 part was zeros
            var prefix_to_parse = ipv6_prefix;

            // Handle different prefix patterns:
            // - "::ffff" -> already valid, use as-is
            // - "64:ff9b:" -> add one colon to make "64:ff9b::"
            // - "2001:db8" -> add "::" to make "2001:db8::"

            if (std.mem.indexOf(u8, ipv6_prefix, "::")) |_| {
                // Contains :: already, use as-is (e.g., "::ffff", "2001::db8")
                // prefix_to_parse = ipv6_prefix; // already set
            } else if (std.mem.endsWith(u8, ipv6_prefix, ":")) {
                // Ends with single colon, add one more (e.g., "64:ff9b:" -> "64:ff9b::")
                var temp_buf: [64]u8 = undefined;
                const expanded = std.fmt.bufPrint(temp_buf[0..], "{s}:", .{ipv6_prefix}) catch return IpParseError.InvalidFormat;
                prefix_to_parse = expanded;
            } else {
                // No colons at end, add :: (e.g., "2001:db8" -> "2001:db8::")
                var temp_buf: [64]u8 = undefined;
                const expanded = std.fmt.bufPrint(temp_buf[0..], "{s}::", .{ipv6_prefix}) catch return IpParseError.InvalidFormat;
                prefix_to_parse = expanded;
            }

            base_addr = parseIPv6Pure(prefix_to_parse) catch {
                return IpParseError.InvalidFormat;
            };
        }

        // For IPv4-mapped IPv6 addresses (::ffff:x.x.x.x), the structure should be:
        // - Bits 0-79: zeros (10 bytes)
        // - Bits 80-95: 0xffff (2 bytes)
        // - Bits 96-127: IPv4 address (4 bytes)
        // So the full address should be: 0x00000000000000000000ffffIPv4

        // Check if this is the IPv4-mapped format (::ffff:x.x.x.x or ::FFFF:x.x.x.x)
        // RFC 4291: IPv6 addresses are case-insensitive for hex digits
        if (std.ascii.eqlIgnoreCase(ipv6_prefix, "::ffff") or
            std.ascii.eqlIgnoreCase(ipv6_prefix, "0:0:0:0:0:ffff"))
        {
            // IPv4-mapped IPv6 address: prefix should be 0x0000000000000000ffff0000
            // Then add the IPv4 address in the last 32 bits
            return (@as(u128, 0xffff) << 32) | @as(u128, ipv4_addr);
        } else {
            // General IPv6 with embedded IPv4 - place IPv4 in last 32 bits
            // Clear the last 32 bits and add the IPv4 address
            base_addr = (base_addr >> 32) << 32; // Clear last 32 bits
            base_addr |= @as(u128, ipv4_addr);
            return base_addr;
        }
    }

    return IpParseError.InvalidFormat;
}

// Fast hex character validation using compile-time lookup table
const HEX_CHARS = "0123456789abcdefABCDEF";
const HEX_LOOKUP: [256]bool = blk: {
    var lookup = [_]bool{false} ** 256;
    for (HEX_CHARS) |c| {
        lookup[c] = true;
    }
    break :blk lookup;
};

/// Optimized validation for IPv6 hex groups using lookup table
/// Empty groups are allowed for :: compression
fn isValidIPv6HexGroup(group_str: []const u8) bool {
    // Allow arbitrarily long groups if the extra leading chars are all '0'.
    // This matches grepcidr behavior in tests (e.g., 02001:db8::1).
    if (group_str.len == 0) return true; // empty allowed for :: compression

    // Fast validation using lookup table
    for (group_str) |c| {
        if (!HEX_LOOKUP[c]) return false;
    }

    // If length <= 4, it's valid as-is
    if (group_str.len <= 4) return true;

    // If length > 4, ensure that the prefix beyond the last 4 chars are all zeros
    const prefix = group_str[0 .. group_str.len - 4];
    for (prefix) |c| {
        if (c != '0') return false;
    }
    return true;
}

fn parseIPv6HexGroupToU16(group_str: []const u8) IpParseError!u16 {
    // Empty means it's from :: compression context; caller should not pass empty here for value parse.
    if (group_str.len == 0) return IpParseError.InvalidFormat;

    // We already validated hex chars in isValidIPv6HexGroup.
    // If len > 4, trim leading zeros and take last up to 4 chars.
    const slice = if (group_str.len <= 4) group_str else group_str[group_str.len - 4 .. group_str.len];
    return std.fmt.parseInt(u16, slice, 16) catch IpParseError.InvalidFormat;
}

/// Parse pure IPv6 address (no embedded IPv4)
fn parseIPv6Pure(ip_str: []const u8) IpParseError!IPv6 {
    // Handle special case of all zeros
    if (std.mem.eql(u8, ip_str, "::")) {
        return 0;
    }

    // RFC 4291: Validate IPv6 format strictly
    // 1. No triple colons (:::\w is invalid)
    if (std.mem.indexOf(u8, ip_str, ":::")) |_| {
        return IpParseError.InvalidFormat;
    }

    // 2. At most one :: sequence allowed
    var double_colon_count: u32 = 0;
    var i: usize = 0;
    while (i + 1 < ip_str.len) {
        if (ip_str[i] == ':' and ip_str[i + 1] == ':') {
            double_colon_count += 1;
            if (double_colon_count > 1) {
                return IpParseError.InvalidFormat;
            }
            // Skip the second colon to avoid double counting
            i += 2;
        } else {
            i += 1;
        }
    }

    // 3. Invalid colon patterns:
    // - Cannot start with single colon unless it's ::
    // - Cannot end with single colon unless part of ::
    if (ip_str.len > 0 and ip_str[0] == ':' and !std.mem.startsWith(u8, ip_str, "::")) {
        return IpParseError.InvalidFormat;
    }
    if (ip_str.len > 0 and ip_str[ip_str.len - 1] == ':' and !std.mem.endsWith(u8, ip_str, "::")) {
        return IpParseError.InvalidFormat;
    }

    var groups: [8]u16 = [_]u16{0} ** 8;

    // Check for double colon and split accordingly
    if (std.mem.indexOf(u8, ip_str, "::")) |pos| {

        // Parse left side
        const left_part = ip_str[0..pos];
        var left_groups: usize = 0;
        if (left_part.len > 0) {
            var left_parts = std.mem.splitSequence(u8, left_part, ":");
            while (left_parts.next()) |part| {
                if (part.len > 0) {
                    // Validate hex format before parsing
                    if (!isValidIPv6HexGroup(part)) {
                        return IpParseError.InvalidFormat;
                    }
                    groups[left_groups] = try parseIPv6HexGroupToU16(part);
                    left_groups += 1;
                }
            }
        }

        // Parse right side
        const right_part = ip_str[pos + 2 ..];
        var right_groups: usize = 0;
        if (right_part.len > 0) {
            var right_parts = std.mem.splitSequence(u8, right_part, ":");
            while (right_parts.next()) |part| {
                if (part.len > 0) {
                    right_groups += 1;
                }
            }

            // Parse right groups in reverse order
            var right_iter = std.mem.splitSequence(u8, right_part, ":");
            var temp_groups: [8]u16 = [_]u16{0} ** 8;
            var temp_count: usize = 0;
            while (right_iter.next()) |part| {
                if (part.len > 0) {
                    // Validate hex format before parsing
                    if (!isValidIPv6HexGroup(part)) {
                        return IpParseError.InvalidFormat;
                    }
                    temp_groups[temp_count] = try parseIPv6HexGroupToU16(part);
                    temp_count += 1;
                }
            }
            // Copy to final positions
            for (0..temp_count) |idx| {
                groups[8 - temp_count + idx] = temp_groups[idx];
            }
        }
    } else {
        // No double colon, parse all 8 groups
        var parts = std.mem.splitSequence(u8, ip_str, ":");
        var group_count: usize = 0;
        while (parts.next()) |part| {
            if (group_count >= 8) return IpParseError.InvalidFormat;
            // Validate hex format before parsing
            if (!isValidIPv6HexGroup(part)) {
                return IpParseError.InvalidFormat;
            }
            groups[group_count] = try parseIPv6HexGroupToU16(part);
            group_count += 1;
        }
        if (group_count != 8) return IpParseError.InvalidFormat;
    }

    // Convert to 128-bit integer
    var result: u128 = 0;
    for (groups, 0..) |group, group_index| {
        result |= (@as(u128, group) << @intCast(112 - group_index * 16));
    }

    return result;
}

/// Parse a dotted decimal IPv4 address string into a 32-bit integer
///
/// ## Parameters
/// - `ip_str`: String in dotted decimal format (e.g., "192.168.1.1")
///
/// ## Returns
/// - `IPv4`: Parsed address as 32-bit integer in network byte order
/// - `IpParseError`: If the address format is invalid or octets are out of range
pub fn parseIPv4(ip_str: []const u8) IpParseError!IPv4 {
    var parts = std.mem.splitSequence(u8, ip_str, ".");
    var octets: [4]u8 = undefined;
    var count: u8 = 0;

    while (parts.next()) |part| {
        if (count >= 4) return IpParseError.InvalidFormat;

        // Parse the octet
        const octet = std.fmt.parseInt(u8, part, 10) catch return IpParseError.InvalidOctet;
        octets[count] = octet;
        count += 1;
    }

    if (count != 4) return IpParseError.InvalidFormat;

    // Build 32-bit IP address (network byte order)
    return (@as(u32, octets[0]) << 24) |
        (@as(u32, octets[1]) << 16) |
        (@as(u32, octets[2]) << 8) |
        @as(u32, octets[3]);
}

/// Parse an IPv6 CIDR pattern string (e.g., "2001:db8::/32") into an Ipv6CidrPattern
pub fn parseIPv6CIDR(cidr_str: []const u8, strict_align: bool) IpParseError!Ipv6CidrPattern {
    // Split on '/' to separate IP and mask
    var slash_split = std.mem.splitSequence(u8, cidr_str, "/");
    const ip_part = slash_split.next() orelse return IpParseError.InvalidFormat;
    const mask_part = slash_split.next() orelse return IpParseError.InvalidFormat;

    // Make sure there's no extra parts
    if (slash_split.next() != null) return IpParseError.InvalidFormat;

    // Parse the IPv6 address
    const network_ip = try parseIPv6(ip_part);

    // Parse the mask bits
    const mask_bits = std.fmt.parseInt(u8, mask_part, 10) catch return IpParseError.InvalidMask;
    if (mask_bits > 128) return IpParseError.InvalidMask;

    // Calculate network mask and range
    const cidr = try calculateIPv6CidrRange(network_ip, mask_bits, strict_align);

    return cidr;
}

/// Parse a CIDR pattern string (e.g., "192.168.0.0/16") into a CidrPattern
pub fn parseCIDR(cidr_str: []const u8, strict_align: bool) IpParseError!CidrPattern {
    // Split on '/' to separate IP and mask
    var slash_split = std.mem.splitSequence(u8, cidr_str, "/");
    const ip_part = slash_split.next() orelse return IpParseError.InvalidFormat;
    const mask_part = slash_split.next() orelse return IpParseError.InvalidFormat;

    // Make sure there's no extra parts
    if (slash_split.next() != null) return IpParseError.InvalidFormat;

    // Parse the IP address
    const network_ip = try parseIPv4(ip_part);

    // Parse the mask bits
    const mask_bits = std.fmt.parseInt(u8, mask_part, 10) catch return IpParseError.InvalidMask;
    if (mask_bits > 32) return IpParseError.InvalidMask;

    // Calculate network mask and range
    const cidr = try calculateCidrRange(network_ip, mask_bits, strict_align);

    return cidr;
}

/// Calculate IPv6 CIDR range from network IP and mask bits
fn calculateIPv6CidrRange(network_ip: IPv6, mask_bits: u8, strict_align: bool) IpParseError!Ipv6CidrPattern {
    if (mask_bits == 0) {
        // Special case: /0 matches all IPv6 addresses
        if (strict_align and network_ip != 0) return IpParseError.MisalignedCidr;
        return Ipv6CidrPattern{
            .min = 0,
            .max = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF,
            .network = 0,
            .mask_bits = 0,
        };
    }

    // Create network mask for IPv6
    const host_bits: u7 = @intCast(128 - mask_bits);
    const network_mask: u128 = if (mask_bits == 128) 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF else ~(@as(u128, 0)) << host_bits;

    // Calculate network address (zero out host bits)
    const network_addr = network_ip & network_mask;

    // Check strict alignment if required
    if (strict_align and network_ip != network_addr) {
        return IpParseError.MisalignedCidr;
    }

    // Calculate broadcast address (set all host bits)
    const host_mask = (~network_mask) & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF;
    const broadcast_addr = network_addr | host_mask;

    return Ipv6CidrPattern{
        .min = network_addr,
        .max = broadcast_addr,
        .network = network_addr,
        .mask_bits = mask_bits,
    };
}

/// Calculate CIDR range from network IP and mask bits
fn calculateCidrRange(network_ip: IPv4, mask_bits: u8, strict_align: bool) IpParseError!CidrPattern {
    if (mask_bits == 0) {
        // Special case: /0 matches all IPv4 addresses
        if (strict_align and network_ip != 0) return IpParseError.MisalignedCidr;
        return CidrPattern{
            .min = 0,
            .max = 0xFFFFFFFF,
            .network = 0,
            .mask_bits = 0,
        };
    }

    // Create network mask (e.g., /24 = 0xFFFFFF00)
    const host_bits = 32 - mask_bits;
    const network_mask = ~(@as(u32, 1) << @intCast(host_bits)) + 1;

    // Calculate network address (zero out host bits)
    const network_addr = network_ip & network_mask;

    // Check strict alignment if required
    if (strict_align and network_ip != network_addr) {
        return IpParseError.MisalignedCidr;
    }

    // Calculate broadcast address (set all host bits)
    const host_mask = (~network_mask) & 0xFFFFFFFF;
    const broadcast_addr = network_addr | host_mask;

    return CidrPattern{
        .min = network_addr,
        .max = broadcast_addr,
        .network = network_addr,
        .mask_bits = mask_bits,
    };
}

/// Parse an IP range string (e.g., "192.168.1.1-192.168.1.10") into an IpRange
pub fn parseIPRange(range_str: []const u8) IpParseError!IpRange {
    // Split on '-' to separate start and end IPs
    var dash_split = std.mem.splitSequence(u8, range_str, "-");
    const start_part = dash_split.next() orelse return IpParseError.InvalidFormat;
    const end_part = dash_split.next() orelse return IpParseError.InvalidFormat;

    // Make sure there's no extra parts
    if (dash_split.next() != null) return IpParseError.InvalidFormat;

    // Trim whitespace from both parts (original grepcidr allows "IP - IP")
    const start_trimmed = std.mem.trim(u8, start_part, " \t");
    const end_trimmed = std.mem.trim(u8, end_part, " \t");

    // Check for empty parts after trimming
    if (start_trimmed.len == 0 or end_trimmed.len == 0) {
        return IpParseError.InvalidFormat;
    }

    // Parse both IP addresses
    const start_ip = try parseIPv4(start_trimmed);
    const end_ip = try parseIPv4(end_trimmed);

    // Validate that start <= end
    if (start_ip > end_ip) {
        return IpParseError.InvalidRange;
    }

    return IpRange{
        .start = start_ip,
        .end = end_ip,
    };
}

/// IPv4 range for optimized storage (like C implementation)
/// Packed for better cache performance with comptime-optimized methods
pub const IPv4Range = packed struct {
    min: IPv4,
    max: IPv4,

    fn lessThan(context: void, a: IPv4Range, b: IPv4Range) bool {
        _ = context;
        return a.min < b.min;
    }

    /// Ultra-fast branchless IP containment check
    /// Uses arithmetic operations instead of branching for better performance
    inline fn containsIP(self: IPv4Range, ip: IPv4) bool {
        // Branchless implementation: (ip - min) <= (max - min)
        // This eliminates branch misprediction penalties
        return (ip -% self.min) <= (self.max -% self.min);
    }
};

/// IPv6 range for optimized storage with inline methods
pub const IPv6Range = struct {
    min: IPv6,
    max: IPv6,

    fn lessThan(context: void, a: IPv6Range, b: IPv6Range) bool {
        _ = context;
        return a.min < b.min;
    }

    /// Optimized IPv6 range containment with consistent performance
    inline fn containsIP(self: IPv6Range, ip: IPv6) bool {
        // Use branchless comparison for IPv6 as well to reduce variance
        return (ip -% self.min) <= (self.max -% self.min);
    }
};

/// Optimized multiple pattern matcher using sorted arrays and binary search
/// Similar to C implementation's approach
pub const MultiplePatterns = struct {
    // Sorted arrays for efficient binary search
    ipv4_ranges: []IPv4Range,
    ipv6_ranges: []IPv6Range,
    allocator: Allocator,

    // Fast path optimization flags
    single_ipv4_pattern: ?IPv4Range = null,
    single_ipv6_pattern: ?IPv6Range = null,

    pub fn deinit(self: *MultiplePatterns) void {
        self.allocator.free(self.ipv4_ranges);
        self.allocator.free(self.ipv6_ranges);
    }

    // Convert patterns to sorted, optimized ranges
    pub fn fromPatterns(patterns: []Pattern, allocator: Allocator) !MultiplePatterns {
        var ipv4_list = std.ArrayList(IPv4Range){};
        var ipv6_list = std.ArrayList(IPv6Range){};
        defer ipv4_list.deinit(allocator);
        defer ipv6_list.deinit(allocator);

        // Extract ranges from patterns
        for (patterns) |pattern| {
            switch (pattern) {
                .single_ipv4 => |ip| {
                    try ipv4_list.append(allocator, IPv4Range{ .min = ip, .max = ip });
                },
                .ipv4_cidr => |cidr| {
                    try ipv4_list.append(allocator, IPv4Range{ .min = cidr.min, .max = cidr.max });
                },
                .ipv4_range => |range| {
                    try ipv4_list.append(allocator, IPv4Range{ .min = range.start, .max = range.end });
                },
                .single_ipv6 => |ip| {
                    try ipv6_list.append(allocator, IPv6Range{ .min = ip, .max = ip });
                },
                .ipv6_cidr => |cidr| {
                    try ipv6_list.append(allocator, IPv6Range{ .min = cidr.min, .max = cidr.max });
                },
            }
        }

        // Convert to owned slices
        var ipv4_ranges = try ipv4_list.toOwnedSlice(allocator);
        var ipv6_ranges = try ipv6_list.toOwnedSlice(allocator);

        // Sort the arrays for binary search
        std.mem.sort(IPv4Range, ipv4_ranges, {}, IPv4Range.lessThan);
        std.mem.sort(IPv6Range, ipv6_ranges, {}, IPv6Range.lessThan);

        // Merge overlapping ranges (like C implementation)
        ipv4_ranges = mergeOverlappingIPv4Ranges(ipv4_ranges, allocator) catch ipv4_ranges;
        ipv6_ranges = mergeOverlappingIPv6Ranges(ipv6_ranges, allocator) catch ipv6_ranges;

        // Detect single pattern optimizations
        var single_ipv4: ?IPv4Range = null;
        var single_ipv6: ?IPv6Range = null;

        if (ipv4_ranges.len == 1) {
            single_ipv4 = ipv4_ranges[0];
        }
        if (ipv6_ranges.len == 1) {
            single_ipv6 = ipv6_ranges[0];
        }

        return MultiplePatterns{
            .ipv4_ranges = ipv4_ranges,
            .ipv6_ranges = ipv6_ranges,
            .allocator = allocator,
            .single_ipv4_pattern = single_ipv4,
            .single_ipv6_pattern = single_ipv6,
        };
    }

    /// Ultra-fast IPv4 matching with comptime specialization - O(1) for common cases
    /// Uses branchless comparison patterns and aggressive inlining for maximum performance
    pub inline fn matchesIPv4(self: MultiplePatterns, ip: IPv4) bool {
        // Fast path: single pattern optimization (most common case)
        if (self.single_ipv4_pattern) |single| {
            return ip >= single.min and ip <= single.max;
        }

        // Fast path: no IPv4 patterns (early exit)
        if (self.ipv4_ranges.len == 0) return false;
        
        // Comptime-specialized branchless matching for optimal performance
        // Each case hand-optimized based on benchmark analysis
        switch (self.ipv4_ranges.len) {
            1 => {
                // Single pattern - direct comparison
                const range = self.ipv4_ranges[0];
                return ip >= range.min and ip <= range.max;
            },
            2 => {
                // Two patterns - ultra-optimized branchless comparison
                const r1 = self.ipv4_ranges[0];
                const r2 = self.ipv4_ranges[1];
                // Use branchless arithmetic for maximum performance
                return r1.containsIP(ip) or r2.containsIP(ip);
            },
            3 => {
                // Three patterns - branchless optimized comparison
                const r1 = self.ipv4_ranges[0];
                const r2 = self.ipv4_ranges[1];
                const r3 = self.ipv4_ranges[2];
                return r1.containsIP(ip) or r2.containsIP(ip) or r3.containsIP(ip);
            },
            4 => {
                // Four patterns - unrolled branchless maximum throughput
                const r1 = self.ipv4_ranges[0];
                const r2 = self.ipv4_ranges[1];
                const r3 = self.ipv4_ranges[2];
                const r4 = self.ipv4_ranges[3];
                return r1.containsIP(ip) or r2.containsIP(ip) or r3.containsIP(ip) or r4.containsIP(ip);
            },
            5, 6 => {
                // 5-6 patterns - branchless optimized loop
                for (self.ipv4_ranges) |range| {
                    if (range.containsIP(ip)) return true;
                }
                return false;
            },
            else => {
                // 7+ patterns - hyper-optimized binary search
                return binarySearchIPv4Optimized(self.ipv4_ranges, ip);
            }
        }
    }

    /// Hyper-optimized binary search with cache-friendly access patterns
    inline fn binarySearchIPv4Optimized(ranges: []const IPv4Range, ip: IPv4) bool {
        if (ranges.len == 0) return false;
        
        var left: usize = 0;
        var right: usize = ranges.len;
        
        // Optimized binary search with better cache locality
        while (right - left > 4) {
            const mid = left + (right - left) / 2;
            const range = ranges[mid];
            
            if (range.containsIP(ip)) return true;
            
            // Use branchless update for better performance
            const go_left = ip < range.min;
            right = if (go_left) mid else right;
            left = if (go_left) left else mid + 1;
        }
        
        // Linear search for remaining elements (better for small counts)
        for (ranges[left..right]) |range| {
            if (range.containsIP(ip)) return true;
        }
        
        return false;
    }

    /// Legacy binary search for compatibility
    inline fn binarySearchIPv4(ranges: []const IPv4Range, ip: IPv4) bool {
        return binarySearchIPv4Optimized(ranges, ip);
    }

    /// Ultra-fast IPv6 matching with comptime specialization and embedded IPv4 support
    pub inline fn matchesIPv6(self: MultiplePatterns, ip: IPv6) bool {
        // Fast path: single pattern optimization (most common case)
        if (self.single_ipv6_pattern) |single| {
            return ip >= single.min and ip <= single.max;
        }

        // Fast path: no IPv6 patterns - check embedded IPv4 immediately
        if (self.ipv6_ranges.len == 0) {
            if (extractEmbeddedIPv4(ip)) |ipv4| {
                return self.matchesIPv4(ipv4);
            }
            return false;
        }
        
        // Comptime-specialized matching with embedded IPv4 support
        switch (self.ipv6_ranges.len) {
            1 => {
                const range = self.ipv6_ranges[0];
                if (ip >= range.min and ip <= range.max) return true;
                // Check embedded IPv4 as fallback
                if (extractEmbeddedIPv4(ip)) |ipv4| {
                    return self.matchesIPv4(ipv4);
                }
                return false;
            },
            2 => {
                // Two patterns - stabilized branchless comparison
                const r1 = self.ipv6_ranges[0];
                const r2 = self.ipv6_ranges[1];
                if (r1.containsIP(ip) or r2.containsIP(ip)) return true;
                return if (extractEmbeddedIPv4(ip)) |ipv4| self.matchesIPv4(ipv4) else false;
            },
            3, 4, 5, 6 => {
                // 3-6 patterns - stabilized loop with consistent performance
                for (self.ipv6_ranges) |range| {
                    if (range.containsIP(ip)) return true;
                }
                return if (extractEmbeddedIPv4(ip)) |ipv4| self.matchesIPv4(ipv4) else false;
            },
            else => {
                // 7+ patterns - optimized binary search with IPv4 fallback
                return binarySearchIPv6Optimized(self.ipv6_ranges, ip) or 
                       (if (extractEmbeddedIPv4(ip)) |ipv4| self.matchesIPv4(ipv4) else false);
            }
        }
    }

    /// Stabilized IPv6 binary search with reduced variance
    inline fn binarySearchIPv6Optimized(ranges: []const IPv6Range, ip: IPv6) bool {
        if (ranges.len == 0) return false;
        
        var left: usize = 0;
        var right: usize = ranges.len;
        
        // Consistent binary search with predictable performance
        while (right - left > 4) {
            const mid = left + (right - left) / 2;
            const range = ranges[mid];
            
            if (range.containsIP(ip)) return true;
            
            // Stabilized branching for consistent timing
            if (ip < range.min) {
                right = mid;
            } else {
                left = mid + 1;
            }
        }
        
        // Linear search for remaining elements
        for (ranges[left..right]) |range| {
            if (range.containsIP(ip)) return true;
        }
        
        return false;
    }

    /// Legacy IPv6 binary search for compatibility
    inline fn binarySearchIPv6(ranges: []const IPv6Range, ip: IPv6) bool {
        return binarySearchIPv6Optimized(ranges, ip);
    }
};

// Merge overlapping IPv4 ranges (like C implementation does)
fn mergeOverlappingIPv4Ranges(ranges: []IPv4Range, allocator: Allocator) ![]IPv4Range {
    if (ranges.len <= 1) return ranges;

    // Fast path: Check if merging is actually needed
    var needs_merge = false;
    for (ranges[0..ranges.len-1], ranges[1..]) |current, next| {
        if (next.min <= current.max + 1) {
            needs_merge = true;
            break;
        }
    }
    
    // If no merging needed, return original array (common case)
    if (!needs_merge) return ranges;

    // Slow path: Actually merge ranges
    var merged = std.ArrayList(IPv4Range){};
    defer merged.deinit(allocator);

    var current = ranges[0];

    for (ranges[1..]) |range| {
        if (range.min <= current.max + 1) {
            // Overlapping or adjacent - merge
            current.max = @max(current.max, range.max);
        } else {
            // Non-overlapping - add current and start new
            try merged.append(allocator, current);
            current = range;
        }
    }

    try merged.append(allocator, current);

    // Free original array and return merged
    allocator.free(ranges);
    return try merged.toOwnedSlice(allocator);
}

// Merge overlapping IPv6 ranges
fn mergeOverlappingIPv6Ranges(ranges: []IPv6Range, allocator: Allocator) ![]IPv6Range {
    if (ranges.len <= 1) return ranges;

    // Fast path: Check if merging is actually needed
    var needs_merge = false;
    for (ranges[0..ranges.len-1], ranges[1..]) |current, next| {
        if (next.min <= current.max + 1) {
            needs_merge = true;
            break;
        }
    }
    
    // If no merging needed, return original array (common case)
    if (!needs_merge) return ranges;

    // Slow path: Actually merge ranges
    var merged = std.ArrayList(IPv6Range){};
    defer merged.deinit(allocator);

    var current = ranges[0];

    for (ranges[1..]) |range| {
        if (range.min <= current.max + 1) {
            // Overlapping or adjacent - merge
            current.max = @max(current.max, range.max);
        } else {
            // Non-overlapping - add current and start new
            try merged.append(allocator, current);
            current = range;
        }
    }

    try merged.append(allocator, current);

    // Free original array and return merged
    allocator.free(ranges);
    return try merged.toOwnedSlice(allocator);
}

/// Parse a single pattern string that could be single IP, CIDR, or IP range (IPv4 or IPv6)
fn parseSinglePattern(pattern_str: []const u8, strict_align: bool) IpParseError!Pattern {
    // Determine if this is IPv6 or IPv4 based on presence of colons
    const is_ipv6 = std.mem.indexOfScalar(u8, pattern_str, ':') != null;

    if (is_ipv6) {
        // IPv6 pattern
        if (std.mem.indexOfScalar(u8, pattern_str, '/')) |_| {
            // IPv6 CIDR
            const cidr = try parseIPv6CIDR(pattern_str, strict_align);
            return Pattern{ .ipv6_cidr = cidr };
        } else {
            // Single IPv6 address
            const ip = try parseIPv6(pattern_str);
            return Pattern{ .single_ipv6 = ip };
        }
    } else {
        // IPv4 pattern
        if (std.mem.indexOfScalar(u8, pattern_str, '/')) |_| {
            // IPv4 CIDR
            const cidr = try parseCIDR(pattern_str, strict_align);
            return Pattern{ .ipv4_cidr = cidr };
        } else if (std.mem.indexOfScalar(u8, pattern_str, '-')) |_| {
            // IPv4 range
            const range = try parseIPRange(pattern_str);
            return Pattern{ .ipv4_range = range };
        } else {
            // Single IPv4 address
            const ip = try parseIPv4(pattern_str);
            return Pattern{ .single_ipv4 = ip };
        }
    }
}

/// Parse multiple patterns separated by whitespace or commas
///
/// Creates an optimized matcher that can efficiently test IP addresses
/// against multiple patterns using binary search.
///
/// ## Parameters
/// - `pattern_str`: String with space or comma-separated patterns
/// - `strict_align`: If true, CIDR network addresses must be properly aligned
/// - `allocator`: Memory allocator for internal data structures
///
/// ## Returns
/// - `MultiplePatterns`: Optimized matcher for multiple patterns
/// - `IpParseError`: If any pattern format is invalid
///
/// ## Example
/// ```zig
/// var patterns = try parseMultiplePatterns("192.168.0.0/16,10.0.0.0/8 172.16.1.1", false, allocator);
/// defer patterns.deinit();
/// const matches = patterns.matchesIPv4(try parseIPv4("192.168.1.1")); // true
/// ```
pub fn parseMultiplePatterns(pattern_str: []const u8, strict_align: bool, allocator: Allocator) IpParseError!MultiplePatterns {
    var patterns = std.ArrayList(Pattern){};
    defer patterns.deinit(allocator);

    // Optimize: Avoid allocation by directly tokenizing with comma and space separators
    var tokens = std.mem.tokenizeAny(u8, pattern_str, " \t\r\n,");

    while (tokens.next()) |token| {
        const pattern = parseSinglePattern(token, strict_align) catch |err| {
            return err;
        };
        patterns.append(allocator, pattern) catch {
            return IpParseError.OutOfMemory;
        };
    }

    if (patterns.items.len == 0) {
        return IpParseError.InvalidFormat;
    }

    // Convert to optimized format
    const patterns_slice = try patterns.toOwnedSlice(allocator);
    defer allocator.free(patterns_slice);

    return MultiplePatterns.fromPatterns(patterns_slice, allocator);
}

// # Pattern Parsing Functions

/// Parse a pattern string that could be single IP, CIDR, or IP range
///
/// Automatically detects the pattern type based on format:
/// - Single IP: "192.168.1.1" or "2001:db8::1"
/// - CIDR range: "192.168.0.0/16" or "2001:db8::/32"
/// - IPv4 range: "192.168.1.1-192.168.1.10"
///
/// ## Parameters
/// - `pattern_str`: String containing the pattern
/// - `strict_align`: If true, CIDR network addresses must be properly aligned
///
/// ## Returns
/// - `Pattern`: Parsed pattern that can match IP addresses
/// - `IpParseError`: If the pattern format is invalid
pub fn parsePattern(pattern_str: []const u8, strict_align: bool) IpParseError!Pattern {
    return parseSinglePattern(pattern_str, strict_align);
}

// IPv6 field character validation using compile-time lookup table
// Only hex digits (0-9, a-f, A-F), colons, and dots (for embedded IPv4)
const IPV6_FIELD = "0123456789abcdefABCDEF:.";
const IPV6_LOOKUP: [256]bool = blk: {
    var lookup = [_]bool{false} ** 256;
    for (IPV6_FIELD) |c| {
        lookup[c] = true;
    }
    break :blk lookup;
};

inline fn isIPv6FieldChar(c: u8) bool {
    return IPV6_LOOKUP[c];
}

// IPv6 hint detection functions for optimized scanning
/// Optimized IPv6 hint detection with unified logic for better branch prediction
inline fn ipv6HintFast(p: []const u8, pos: usize) bool {
    if (pos >= p.len) return false;

    const c = p[pos];

    // Fast path: Check for double colon (::) - most common IPv6 indicator
    if (c == ':' and pos + 1 < p.len and p[pos + 1] == ':') {
        return true;
    }

    // Check for hex digit followed by colon (single branch for all hex lengths)
    if (std.ascii.isHex(c)) {
        // Look ahead for colon at positions 1-4 (unified check)
        const max_check = @min(pos + 5, p.len);
        for (pos + 1..max_check) |i| {
            if (p[i] == ':') return true;
            if (!std.ascii.isHex(p[i])) break;
        }
    }

    return false;
}
// Additional hint for standalone :: at start of line or after whitespace
inline fn ipv6HintStandalone(p: []const u8, pos: usize) bool {
    if (pos + 1 >= p.len) return false;
    if (p[pos] != ':' or p[pos + 1] != ':') return false;
    // Check if we're at the start or after whitespace
    if (pos == 0) return true; // :: at start of line
    if (pos > 0 and std.ascii.isWhitespace(p[pos - 1])) return true; // After whitespace
    return false;
}

// IPv4 field character validation using compile-time lookup table
// Only digits and dots for IPv4
const IPV4_FIELD = "0123456789.";
const IPV4_LOOKUP: [256]bool = blk: {
    var lookup = [_]bool{false} ** 256;
    for (IPV4_FIELD) |c| {
        lookup[c] = true;
    }
    break :blk lookup;
};

/// Optimized IPv4 hint detection with early termination
inline fn ipv4Hint(p: []const u8, pos: usize) bool {
    if (pos >= p.len or !std.ascii.isDigit(p[pos])) return false;
    
    // Check for dot at positions 1, 2, or 3 with early termination
    const max_check = @min(pos + 4, p.len);
    for (pos + 1..max_check) |i| {
        if (p[i] == '.') return true;
    }
    return false;
}

inline fn isIPv4FieldChar(c: u8) bool {
    return IPV4_LOOKUP[c];
}

// # Line Scanning API

/// Memory-efficient IP scanner with reusable buffers
///
/// Provides fast extraction of IP addresses from text lines using
/// hint-based scanning similar to the original C implementation.
///
/// ## Usage
/// ```zig
/// var scanner = IpScanner.init(allocator);
/// defer scanner.deinit();
///
/// const line = "Server 192.168.1.1 responded from 2001:db8::1";
/// const ipv4s = try scanner.scanIPv4(line);
/// const ipv6s = try scanner.scanIPv6(line);
/// ```
pub const IpScanner = struct {
    ipv4_buffer: std.ArrayList(IPv4),
    ipv6_buffer: std.ArrayList(IPv6),
    allocator: Allocator,

    /// Initialize a new IP scanner with the given allocator
    pub fn init(allocator: Allocator) IpScanner {
        return IpScanner{
            .ipv4_buffer = std.ArrayList(IPv4){},
            .ipv6_buffer = std.ArrayList(IPv6){},
            .allocator = allocator,
        };
    }

    /// Clean up scanner resources
    pub fn deinit(self: *IpScanner) void {
        self.ipv4_buffer.deinit(self.allocator);
        self.ipv6_buffer.deinit(self.allocator);
    }

    /// Scan line for IPv4 addresses using hint-based detection
    pub fn scanIPv4(self: *IpScanner, line: []const u8) ![]IPv4 {
        self.ipv4_buffer.clearRetainingCapacity();

        var i: usize = 0;
        const lookahead_limit = if (line.len >= 4) line.len - 4 else 0;

        while (i < lookahead_limit) {
            if (ipv4Hint(line, i)) {
                var j = i;
                while (j < line.len and isIPv4FieldChar(line[j])) {
                    j += 1;
                }

                const potential_ip = line[i..j];
                if (parseIPv4(potential_ip)) |ip| {
                    try self.ipv4_buffer.append(self.allocator, ip);
                } else |_| {}

                i = j;
            } else {
                i += 1;
            }
        }

        return self.ipv4_buffer.items;
    }

    /// Scan line for IPv4 addresses with early termination on first match
    pub fn scanIPv4WithEarlyExit(self: *IpScanner, line: []const u8, patterns: MultiplePatterns) !?IPv4 {
        self.ipv4_buffer.clearRetainingCapacity();

        var i: usize = 0;
        const lookahead_limit = if (line.len >= 4) line.len - 4 else 0;

        while (i < lookahead_limit) {
            if (ipv4Hint(line, i)) {
                var j = i;
                while (j < line.len and isIPv4FieldChar(line[j])) {
                    j += 1;
                }

                const potential_ip = line[i..j];
                if (parseIPv4(potential_ip)) |ip| {
                    if (patterns.matchesIPv4(ip)) {
                        return ip; // Early exit on first match
                    }
                } else |_| {}

                i = j;
            } else {
                i += 1;
            }
        }

        return null;
    }

    /// Scan line for IPv6 addresses using hint-based detection
    pub fn scanIPv6(self: *IpScanner, line: []const u8) ![]IPv6 {
        self.ipv6_buffer.clearRetainingCapacity();

        var i: usize = 0;
        while (i < line.len) {
            if (ipv6HintFast(line, i) or ipv6HintStandalone(line, i)) {
                var j = i;
                while (j < line.len and isIPv6FieldChar(line[j])) {
                    j += 1;
                }

                const potential_ip = line[i..j];
                if (std.mem.indexOfScalar(u8, potential_ip, ':')) |_| {
                    // Check if we have a valid boundary
                    // If the next character is alphanumeric and we stopped scanning,
                    // it means we hit an invalid character that looks like it could be part of IPv6
                    var valid_extraction = true;
                    if (j < line.len) {
                        const next_char = line[j];
                        // If we stopped at a letter (not valid hex), the whole field is invalid
                        if (std.ascii.isAlphabetic(next_char) and !std.ascii.isHex(next_char)) {
                            valid_extraction = false;
                        }
                    }

                    if (valid_extraction) {
                        if (parseIPv6(potential_ip)) |ip| {
                            try self.ipv6_buffer.append(self.allocator, ip);
                        } else |_| {}
                    }
                }

                i = j;
            } else {
                i += 1;
            }
        }

        return self.ipv6_buffer.items;
    }

    /// Scan line for IPv6 addresses with early termination on first match
    pub fn scanIPv6WithEarlyExit(self: *IpScanner, line: []const u8, patterns: MultiplePatterns) !?IPv6 {
        self.ipv6_buffer.clearRetainingCapacity();

        var i: usize = 0;
        while (i < line.len) {
            if (ipv6HintFast(line, i) or ipv6HintStandalone(line, i)) {
                var j = i;
                while (j < line.len and isIPv6FieldChar(line[j])) {
                    j += 1;
                }

                const potential_ip = line[i..j];
                if (std.mem.indexOfScalar(u8, potential_ip, ':')) |_| {
                    if (parseIPv6(potential_ip)) |ip| {
                        if (patterns.matchesIPv6(ip)) {
                            return ip;
                        }
                    } else |_| {}
                }

                i = j;
            } else {
                i += 1;
            }
        }

        return null;
    }
};

// # Utility Functions

/// Extract IPv4 addresses from a line (convenience function)
///
/// ## Parameters
/// - `line`: Text line to scan for IPv4 addresses
/// - `allocator`: Memory allocator for the returned list
///
/// ## Returns
/// - `ArrayList(IPv4)`: List of found IPv4 addresses (caller owns)
/// - `error`: If memory allocation fails
pub fn findIPv4InLine(line: []const u8, allocator: Allocator) !std.ArrayList(IPv4) {
    var ips = std.ArrayList(IPv4){};
    var scanner = IpScanner.init(allocator);
    defer scanner.deinit();

    const found_ips = try scanner.scanIPv4(line);
    for (found_ips) |ip| {
        try ips.append(allocator, ip);
    }
    return ips;
}

/// Extract IPv6 addresses from a line (convenience function)
///
/// ## Parameters
/// - `line`: Text line to scan for IPv6 addresses
/// - `allocator`: Memory allocator for the returned list
///
/// ## Returns
/// - `ArrayList(IPv6)`: List of found IPv6 addresses (caller owns)
/// - `error`: If memory allocation fails
pub fn findIPv6InLine(line: []const u8, allocator: Allocator) !std.ArrayList(IPv6) {
    var ips = std.ArrayList(IPv6){};
    var scanner = IpScanner.init(allocator);
    defer scanner.deinit();

    const found_ips = try scanner.scanIPv6(line);
    for (found_ips) |ip| {
        try ips.append(allocator, ip);
    }
    return ips;
}

/// Check if an IPv4 address matches a pattern (convenience function)
pub fn matchesPattern(ip: IPv4, pattern: Pattern) bool {
    return pattern.matchesIPv4(ip);
}

/// Format IPv4 address as dotted decimal string
///
/// ## Parameters
/// - `ip`: IPv4 address as 32-bit integer
/// - `buffer`: Output buffer (must be at least 16 bytes)
///
/// ## Returns
/// - `[]u8`: Formatted string slice within the buffer
/// - `error`: If buffer is too small
pub fn formatIPv4(ip: IPv4, buffer: []u8) ![]u8 {
    const a = (ip >> 24) & 0xFF;
    const b = (ip >> 16) & 0xFF;
    const c = (ip >> 8) & 0xFF;
    const d = ip & 0xFF;

    return std.fmt.bufPrint(buffer, "{d}.{d}.{d}.{d}", .{ a, b, c, d });
}

test "IPv4 parsing" {
    try std.testing.expect(try parseIPv4("192.168.1.1") == 0xC0A80101);
    try std.testing.expect(try parseIPv4("10.0.0.1") == 0x0A000001);
    try std.testing.expect(try parseIPv4("255.255.255.255") == 0xFFFFFFFF);
    try std.testing.expect(try parseIPv4("0.0.0.0") == 0x00000000);
}

test "IPv4 parsing errors" {
    try std.testing.expectError(IpParseError.InvalidFormat, parseIPv4("192.168.1"));
    try std.testing.expectError(IpParseError.InvalidFormat, parseIPv4("192.168.1.1.1"));
    try std.testing.expectError(IpParseError.InvalidOctet, parseIPv4("256.168.1.1"));
    try std.testing.expectError(IpParseError.InvalidOctet, parseIPv4("192.168.1.999"));
}

test "find IPv4 in line" {
    const allocator = std.testing.allocator;

    var ips = try findIPv4InLine("192.168.1.1 test", allocator);
    defer ips.deinit(allocator);
    try std.testing.expect(ips.items.len == 1);
    try std.testing.expect(ips.items[0] == try parseIPv4("192.168.1.1"));

    var ips2 = try findIPv4InLine("no IP here", allocator);
    defer ips2.deinit(allocator);
    try std.testing.expect(ips2.items.len == 0);

    var ips3 = try findIPv4InLine("192.168.1.1 and 10.0.0.1", allocator);
    defer ips3.deinit(allocator);
    try std.testing.expect(ips3.items.len == 2);
}

test "IPv4 matching" {
    const ip1 = try parseIPv4("192.168.1.1");
    const pattern1 = Pattern{ .single_ipv4 = ip1 };
    const pattern2 = Pattern{ .single_ipv4 = try parseIPv4("10.0.0.1") };

    try std.testing.expect(pattern1.matchesIPv4(ip1));
    try std.testing.expect(!pattern2.matchesIPv4(ip1));
}

test "CIDR parsing" {
    // Test /24 network
    const cidr24 = try parseCIDR("192.168.1.0/24", false);
    try std.testing.expect(cidr24.mask_bits == 24);
    try std.testing.expect(cidr24.min == try parseIPv4("192.168.1.0"));
    try std.testing.expect(cidr24.max == try parseIPv4("192.168.1.255"));

    // Test /16 network
    const cidr16 = try parseCIDR("192.168.0.0/16", false);
    try std.testing.expect(cidr16.mask_bits == 16);
    try std.testing.expect(cidr16.min == try parseIPv4("192.168.0.0"));
    try std.testing.expect(cidr16.max == try parseIPv4("192.168.255.255"));

    // Test /0 (matches all)
    const cidr0 = try parseCIDR("0.0.0.0/0", false);
    try std.testing.expect(cidr0.mask_bits == 0);
    try std.testing.expect(cidr0.min == 0);
    try std.testing.expect(cidr0.max == 0xFFFFFFFF);

    // Test /32 (single host)
    const cidr32 = try parseCIDR("192.168.1.1/32", false);
    try std.testing.expect(cidr32.mask_bits == 32);
    try std.testing.expect(cidr32.min == try parseIPv4("192.168.1.1"));
    try std.testing.expect(cidr32.max == try parseIPv4("192.168.1.1"));
}

test "CIDR matching" {
    const cidr = try parseCIDR("192.168.0.0/16", false);
    const pattern = Pattern{ .ipv4_cidr = cidr };

    // Should match IPs in range
    try std.testing.expect(pattern.matchesIPv4(try parseIPv4("192.168.1.1")));
    try std.testing.expect(pattern.matchesIPv4(try parseIPv4("192.168.0.1")));
    try std.testing.expect(pattern.matchesIPv4(try parseIPv4("192.168.255.254")));

    // Should not match IPs outside range
    try std.testing.expect(!pattern.matchesIPv4(try parseIPv4("192.167.1.1")));
    try std.testing.expect(!pattern.matchesIPv4(try parseIPv4("192.169.1.1")));
    try std.testing.expect(!pattern.matchesIPv4(try parseIPv4("10.0.0.1")));
}

test "Pattern parsing" {
    // Test single IP pattern
    const single = try parsePattern("192.168.1.1", false);
    try std.testing.expect(single == .single_ipv4);
    try std.testing.expect(single.single_ipv4 == try parseIPv4("192.168.1.1"));

    // Test CIDR pattern
    const cidr = try parsePattern("192.168.0.0/16", false);
    try std.testing.expect(cidr == .ipv4_cidr);
    try std.testing.expect(cidr.ipv4_cidr.mask_bits == 16);

    // Test IP range pattern
    const range = try parsePattern("192.168.1.1-192.168.1.10", false);
    try std.testing.expect(range == .ipv4_range);
    try std.testing.expect(range.ipv4_range.start == try parseIPv4("192.168.1.1"));
    try std.testing.expect(range.ipv4_range.end == try parseIPv4("192.168.1.10"));
}

test "Strict CIDR alignment" {
    // Should allow properly aligned CIDR
    _ = try parseCIDR("192.168.0.0/16", true);

    // Should reject misaligned CIDR
    try std.testing.expectError(IpParseError.MisalignedCidr, parseCIDR("192.168.1.0/16", true));
    try std.testing.expectError(IpParseError.MisalignedCidr, parseCIDR("192.168.1.1/24", true));

    // Special case: /0 should only allow 0.0.0.0
    _ = try parseCIDR("0.0.0.0/0", true);
    try std.testing.expectError(IpParseError.MisalignedCidr, parseCIDR("1.0.0.0/0", true));
}

test "IP range parsing" {
    // Test basic range
    const range1 = try parseIPRange("192.168.1.1-192.168.1.10");
    try std.testing.expect(range1.start == try parseIPv4("192.168.1.1"));
    try std.testing.expect(range1.end == try parseIPv4("192.168.1.10"));

    // Test range with spaces (original grepcidr allows this)
    const range2 = try parseIPRange("192.168.1.1 - 192.168.1.10");
    try std.testing.expect(range2.start == try parseIPv4("192.168.1.1"));
    try std.testing.expect(range2.end == try parseIPv4("192.168.1.10"));

    // Test single IP range (start == end)
    const range3 = try parseIPRange("192.168.1.1-192.168.1.1");
    try std.testing.expect(range3.start == try parseIPv4("192.168.1.1"));
    try std.testing.expect(range3.end == try parseIPv4("192.168.1.1"));

    // Test large range
    const range4 = try parseIPRange("0.0.0.0-255.255.255.255");
    try std.testing.expect(range4.start == 0);
    try std.testing.expect(range4.end == 0xFFFFFFFF);
}

test "IP range matching" {
    const range = try parseIPRange("192.168.1.5-192.168.1.15");
    const pattern = Pattern{ .ipv4_range = range };

    // Should match IPs in range
    try std.testing.expect(pattern.matchesIPv4(try parseIPv4("192.168.1.5"))); // start
    try std.testing.expect(pattern.matchesIPv4(try parseIPv4("192.168.1.10"))); // middle
    try std.testing.expect(pattern.matchesIPv4(try parseIPv4("192.168.1.15"))); // end

    // Should not match IPs outside range
    try std.testing.expect(!pattern.matchesIPv4(try parseIPv4("192.168.1.4"))); // below
    try std.testing.expect(!pattern.matchesIPv4(try parseIPv4("192.168.1.16"))); // above
    try std.testing.expect(!pattern.matchesIPv4(try parseIPv4("192.168.2.10"))); // different subnet
    try std.testing.expect(!pattern.matchesIPv4(try parseIPv4("10.0.0.10"))); // different network
}

test "IP range parsing errors" {
    // Invalid format - no dash
    try std.testing.expectError(IpParseError.InvalidFormat, parseIPRange("192.168.1.1"));

    // Invalid format - too many dashes
    try std.testing.expectError(IpParseError.InvalidFormat, parseIPRange("192.168.1.1-192.168.1.10-192.168.1.20"));

    // Invalid range - start > end
    try std.testing.expectError(IpParseError.InvalidRange, parseIPRange("192.168.1.10-192.168.1.5"));

    // Invalid IP addresses
    try std.testing.expectError(IpParseError.InvalidOctet, parseIPRange("256.168.1.1-192.168.1.10"));
    try std.testing.expectError(IpParseError.InvalidOctet, parseIPRange("192.168.1.1-256.168.1.10"));

    // Empty parts
    try std.testing.expectError(IpParseError.InvalidFormat, parseIPRange("-192.168.1.10"));
    try std.testing.expectError(IpParseError.InvalidFormat, parseIPRange("192.168.1.1-"));
}

test "CIDR parsing errors" {
    // Invalid mask bits
    try std.testing.expectError(IpParseError.InvalidMask, parseCIDR("192.168.0.0/33", false));
    try std.testing.expectError(IpParseError.InvalidMask, parseCIDR("192.168.0.0/abc", false));

    // Invalid format
    try std.testing.expectError(IpParseError.InvalidFormat, parseCIDR("192.168.0.0", false));
    try std.testing.expectError(IpParseError.InvalidFormat, parseCIDR("192.168.0.0/24/extra", false));

    // Invalid IP
    try std.testing.expectError(IpParseError.InvalidOctet, parseCIDR("256.168.0.0/24", false));
}

test "Multiple patterns parsing" {
    const allocator = std.testing.allocator;

    // Test space-separated patterns
    var patterns1 = try parseMultiplePatterns("192.168.1.1 10.0.0.0/8", false, allocator);
    defer patterns1.deinit();
    try std.testing.expect(patterns1.ipv4_ranges.len == 2);

    // Test comma-separated patterns
    var patterns2 = try parseMultiplePatterns("192.168.0.0/16,10.0.0.1,172.16.0.0/12", false, allocator);
    defer patterns2.deinit();
    try std.testing.expect(patterns2.ipv4_ranges.len == 3);

    // Test mixed separation
    var patterns3 = try parseMultiplePatterns("192.168.1.1 10.0.0.0/8,172.16.0.1-172.16.0.10", false, allocator);
    defer patterns3.deinit();
    try std.testing.expect(patterns3.ipv4_ranges.len == 3);

    // Test single pattern (should still work)
    var patterns4 = try parseMultiplePatterns("192.168.1.1", false, allocator);
    defer patterns4.deinit();
    try std.testing.expect(patterns4.ipv4_ranges.len == 1);
}

test "Multiple patterns matching" {
    const allocator = std.testing.allocator;

    // Create patterns: private networks
    var patterns = try parseMultiplePatterns("192.168.0.0/16 10.0.0.0/8,172.16.0.0/12", false, allocator);
    defer patterns.deinit();

    // Should match IPs from any pattern
    try std.testing.expect(patterns.matchesIPv4(try parseIPv4("192.168.1.1"))); // 192.168.0.0/16
    try std.testing.expect(patterns.matchesIPv4(try parseIPv4("10.0.0.1"))); // 10.0.0.0/8
    try std.testing.expect(patterns.matchesIPv4(try parseIPv4("172.16.1.1"))); // 172.16.0.0/12
    try std.testing.expect(patterns.matchesIPv4(try parseIPv4("172.31.255.254"))); // 172.16.0.0/12

    // Should not match IPs outside all patterns
    try std.testing.expect(!patterns.matchesIPv4(try parseIPv4("8.8.8.8"))); // Public DNS
    try std.testing.expect(!patterns.matchesIPv4(try parseIPv4("1.2.3.4"))); // Random public
    try std.testing.expect(!patterns.matchesIPv4(try parseIPv4("172.15.1.1"))); // Just outside 172.16.0.0/12
}

test "Multiple patterns with ranges" {
    const allocator = std.testing.allocator;

    // Mix different pattern types
    var patterns = try parseMultiplePatterns("192.168.1.1-192.168.1.10 10.0.0.0/24,172.16.0.1", false, allocator);
    defer patterns.deinit();
    try std.testing.expect(patterns.ipv4_ranges.len == 3);

    // Test matching different pattern types
    try std.testing.expect(patterns.matchesIPv4(try parseIPv4("192.168.1.5"))); // IP range
    try std.testing.expect(patterns.matchesIPv4(try parseIPv4("10.0.0.100"))); // CIDR
    try std.testing.expect(patterns.matchesIPv4(try parseIPv4("172.16.0.1"))); // Single IP

    // Should not match outside patterns
    try std.testing.expect(!patterns.matchesIPv4(try parseIPv4("192.168.1.11"))); // Outside range
    try std.testing.expect(!patterns.matchesIPv4(try parseIPv4("10.0.1.1"))); // Outside CIDR
    try std.testing.expect(!patterns.matchesIPv4(try parseIPv4("172.16.0.2"))); // Different single IP
}

test "Multiple patterns parsing errors" {
    const allocator = std.testing.allocator;

    // Empty pattern string
    try std.testing.expectError(IpParseError.InvalidFormat, parseMultiplePatterns("", false, allocator));
    try std.testing.expectError(IpParseError.InvalidFormat, parseMultiplePatterns("   ", false, allocator));

    // Invalid pattern in list
    try std.testing.expectError(IpParseError.InvalidOctet, parseMultiplePatterns("192.168.1.1 256.1.1.1", false, allocator));
    try std.testing.expectError(IpParseError.InvalidMask, parseMultiplePatterns("192.168.0.0/16,10.0.0.0/33", false, allocator));
}

test "IPv4 formatting" {
    var buffer: [16]u8 = undefined;
    const ip = try parseIPv4("192.168.1.1");
    const formatted = try formatIPv4(ip, &buffer);
    try std.testing.expectEqualStrings("192.168.1.1", formatted);
}
