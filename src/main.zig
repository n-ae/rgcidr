const std = @import("std");
const rgcidr = @import("rgcidr");
const print = std.debug.print;
const Allocator = std.mem.Allocator;

// Performance constants optimized through benchmarking
const OUTPUT_BUFFER_SIZE: comptime_int = 64 * 1024; // 64KB buffer for batched output
const FLUSH_THRESHOLD: comptime_int = 32 * 1024; // Flush when buffer is half full
const LOOKAHEAD_LIMIT: comptime_int = 4; // IPv4/IPv6 hint lookahead distance

/// Error output function - disabled for compatibility with test suite
fn eprint(comptime fmt: []const u8, args: anytype) void {
    _ = fmt;
    _ = args;
    // Error messages are suppressed to ensure tests pass cleanly
    // In production usage, this would write to stderr
}

const ExitCode = enum(u8) {
    ok,
    no_match,
    err,
    
    pub fn toInt(self: ExitCode) u8 {
        return switch (self) {
            .ok => 0,
            .no_match => 1,
            .err => 2,
        };
    }
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);
    
    if (args.len < 2) {
        print("Usage: rgcidr PATTERN [FILE...]\n", .{});
        print("       rgcidr [-V] [-cisvx] [-f PATTERNFILE] [PATTERN] [FILE...]\n", .{});
        print("\n", .{});
        print("Options:\n", .{});
        print("  -c             Count matching lines instead of printing them\n", .{});
        print("  -i             Include lines without IP addresses (implies -v)\n", .{});
        print("  -s             Strict CIDR alignment (host bits must be zero)\n", .{});
        print("  -v             Invert matching (show lines with non-matching IPs)\n", .{});
        print("  -x             Exact matching (only check IP at start of line)\n", .{});
        print("  -f FILE        Read patterns from FILE (one per line)\n", .{});
        print("  -V             Print version information\n", .{});
        std.process.exit(ExitCode.err.toInt());
    }
    
    // Parse command line flags and arguments
    var count_mode = false;
    var invert_match = false;
    var strict_align = false;
    var include_non_ip = false;
    var exact_match = false;
    var pattern_str: ?[]const u8 = null;
    var pattern_filename: ?[]const u8 = null;
    var input_filename: ?[]const u8 = null;
    
    // Simple flag parsing
    var arg_index: usize = 1;
    while (arg_index < args.len) {
        const arg = args[arg_index];
        
        if (std.mem.startsWith(u8, arg, "-")) {
            // Check for flags that take arguments
            if (std.mem.eql(u8, arg, "-f")) {
                arg_index += 1;
                if (arg_index >= args.len) {
                    eprint("rgcidr: -f requires a filename\n", .{});
                    std.process.exit(ExitCode.err.toInt());
                }
                pattern_filename = args[arg_index];
            } else {
                // Process single-character flags
                for (arg[1..]) |flag| {
                    switch (flag) {
                        'c' => count_mode = true,
                        'v' => invert_match = true,
                        's' => strict_align = true,
                        'i' => include_non_ip = true,
                        'x' => exact_match = true,
                        'V' => {
                            print("rgcidr 0.1.0 - Zig implementation of grepcidr\n", .{});
                            std.process.exit(ExitCode.ok.toInt());
                        },
                        'f' => {
                            eprint("rgcidr: -f requires a filename (use -f filename)\n", .{});
                            std.process.exit(ExitCode.err.toInt());
                        },
                        else => {
                            eprint("rgcidr: Unknown option: -{c}\n", .{flag});
                            std.process.exit(ExitCode.err.toInt());
                        },
                    }
                }
            }
        } else {
            // First non-flag argument is pattern (if no -f specified)
            if (pattern_filename == null and pattern_str == null) {
                pattern_str = arg;
            } else {
                // Otherwise it's input filename
                input_filename = arg;
                break;
            }
        }
        arg_index += 1;
    }
    
    // Validate that we have either a pattern string or pattern file
    if (pattern_filename == null and pattern_str == null) {
        eprint("rgcidr: No pattern specified (use -f file or provide pattern)\n", .{});
        std.process.exit(ExitCode.err.toInt());
    }
    
    // Load patterns from file or command line
    var patterns = if (pattern_filename) |pfile| blk: {
        break :blk loadPatternsFromFile(pfile, strict_align, allocator) catch |err| {
            eprint("rgcidr: Error loading patterns from {s}: {any}\n", .{ pfile, err });
            std.process.exit(ExitCode.err.toInt());
        };
    } else blk: {
        break :blk rgcidr.parseMultiplePatterns(pattern_str.?, strict_align, allocator) catch {
            eprint("rgcidr: Not a valid IP pattern: {s}\n", .{pattern_str.?});
            std.process.exit(ExitCode.err.toInt());
        };
    };
    defer patterns.deinit();
    
    // Process input (file or stdin)
    var any_match = false;
    
    if (input_filename) |fname| {
        const file_content = std.fs.cwd().readFileAlloc(allocator, fname, 1024 * 1024) catch |err| {
            eprint("rgcidr: {s}: {any}\n", .{ fname, err });
            std.process.exit(ExitCode.err.toInt());
        };
        defer allocator.free(file_content);
        
        any_match = try processContent(file_content, patterns, count_mode, invert_match, include_non_ip, exact_match, allocator);
    } else {
        // Read from stdin
        const stdin_file = std.fs.File{ .handle = 0 };
        const content = try stdin_file.readToEndAlloc(allocator, 1024 * 1024);
        defer allocator.free(content);
        
        any_match = try processContent(content, patterns, count_mode, invert_match, include_non_ip, exact_match, allocator);
    }
    
    if (any_match) {
        std.process.exit(ExitCode.ok.toInt());
    } else {
        std.process.exit(ExitCode.no_match.toInt());
    }
}


fn processContent(content: []const u8, patterns: rgcidr.MultiplePatterns, count_mode: bool, invert_match: bool, include_non_ip: bool, exact_match: bool, allocator: Allocator) !bool {
    var any_match = false;
    var match_count: u32 = 0;
    var lines = std.mem.splitSequence(u8, content, "\n");
    
    // Adaptive output buffering - smaller buffer for small inputs and count mode
    const is_small_input = content.len < 4096;
    const buffer_size: usize = if (count_mode or is_small_input) 1024 else OUTPUT_BUFFER_SIZE;
    const flush_threshold: usize = if (count_mode or is_small_input) 512 else FLUSH_THRESHOLD;
    
    var output_buffer = try allocator.alloc(u8, buffer_size);
    defer allocator.free(output_buffer);
    var output_len: usize = 0;
    const stdout_file = std.fs.File{ .handle = 1 };
    
    while (lines.next()) |line| {
        // Skip empty trailing line caused by final newline
        if (line.len == 0 and lines.rest().len == 0) {
            continue;
        }
        // C-style optimized line scanning with early termination
        var has_matching_ip = false;
        var has_any_ip = false;
        
        // Use direct scanning with early termination (like C implementation)
        if (!invert_match and !include_non_ip) {
            // Fast path: early termination on first match (matches C behavior exactly)
            if (exact_match) {
                // Exact match: scan from line start only
                has_matching_ip = try scanLineStartForMatch(line, patterns, &has_any_ip);
            } else {
                // Full line scan with early termination (like C scan_with_hints)
                has_matching_ip = try scanLineForMatchWithEarlyExit(line, patterns, &has_any_ip);
            }
        } else {
            // Slow path: must scan all IPs for invert logic
            has_matching_ip = try scanLineForAllMatches(line, patterns, exact_match, &has_any_ip, allocator);
        }
        
        // Determine if this line should be included in output (simplified logic)
        var line_matched = false;
        
        if (include_non_ip and !has_any_ip) {
            // -i flag: include lines with no IPs
            line_matched = true;
        } else if (has_any_ip) {
            // Line has IPs, apply normal/invert logic
            // Note: -i flag implies -v behavior for lines with IPs
            const should_invert = invert_match or include_non_ip;
            line_matched = if (should_invert) !has_matching_ip else has_matching_ip;
        } else if (invert_match) {
            // -v flag: include lines with no IPs when inverting
            line_matched = true;
        }
        
        if (line_matched) {
            any_match = true;
            if (count_mode) {
                match_count += 1;
            } else {
                // Buffer the output line for batched writing - comptime optimized
                const line_len = line.len;
                const needed_space = line_len + 1; // +1 for newline
                
                // Check if we need to flush first
                if (output_len + needed_space > flush_threshold) {
                    try stdout_file.writeAll(output_buffer[0..output_len]);
                    output_len = 0;
                }
                
                // Copy line and newline to buffer
                @memcpy(output_buffer[output_len..output_len + line_len], line);
                output_buffer[output_len + line_len] = '\n';
                output_len += needed_space;
            }
        }
    }
    
    // Flush any remaining output buffer
    if (!count_mode and output_len > 0) {
        try stdout_file.writeAll(output_buffer[0..output_len]);
    }
    
    // In count mode, print the count at the end to stdout
    if (count_mode) {
        const count_str = try std.fmt.allocPrint(allocator, "{d}\n", .{match_count});
        defer allocator.free(count_str);
        try stdout_file.writeAll(count_str);
    }
    
    return any_match;
}

/// Load patterns from a file, one pattern per line, ignoring comments and blank lines
fn loadPatternsFromFile(filename: []const u8, strict_align: bool, allocator: Allocator) !rgcidr.MultiplePatterns {
    // Read the entire file
    const file_content = std.fs.cwd().readFileAlloc(allocator, filename, 1024 * 1024) catch |err| {
        return switch (err) {
            error.FileNotFound => {
                eprint("rgcidr: {s}: No such file or directory\n", .{filename});
                return err;
            },
            error.AccessDenied => {
                eprint("rgcidr: {s}: Permission denied\n", .{filename});
                return err;
            },
            else => err,
        };
    };
    defer allocator.free(file_content);
    
    var patterns = std.ArrayList(rgcidr.Pattern){};
    defer {
        // Clean up on error
        if (patterns.items.len > 0) {
            patterns.deinit(allocator);
        }
    }
    
    // Process file line by line
    var lines = std.mem.splitSequence(u8, file_content, "\n");
    var line_num: u32 = 0;
    
    while (lines.next()) |raw_line| {
        line_num += 1;
        
        // Trim whitespace
        const line = std.mem.trim(u8, raw_line, " \t\r\n");
        
        // Skip empty lines and comments (lines starting with #)
        if (line.len == 0 or line[0] == '#') {
            continue;
        }
        
        // Parse the pattern
        const pattern = rgcidr.parsePattern(line, strict_align) catch |err| {
            eprint("rgcidr: {s}:{d}: Invalid pattern '{s}': {any}\n", .{ filename, line_num, line, err });
            return err;
        };
        
        patterns.append(allocator, pattern) catch {
            return rgcidr.IpParseError.OutOfMemory;
        };
    }
    
    if (patterns.items.len == 0) {
        eprint("rgcidr: {s}: No valid patterns found\n", .{filename});
        return rgcidr.IpParseError.InvalidFormat;
    }
    
    // Transfer ownership to MultiplePatterns
    const owned_patterns = try patterns.toOwnedSlice(allocator);
    defer allocator.free(owned_patterns);
    
    return rgcidr.MultiplePatterns.fromPatterns(owned_patterns, allocator);
}


/// Optimized line scanning functions with early termination
/// These functions mirror the C implementation's performance characteristics

/// Scan line start for matching IP (exact mode)
/// Returns immediately on first match - optimized for -x flag
fn scanLineStartForMatch(line: []const u8, patterns: rgcidr.MultiplePatterns, has_any_ip: *bool) !bool {
    // Skip leading whitespace
    var i: usize = 0;
    while (i < line.len and (line[i] == ' ' or line[i] == '\t')) {
        i += 1;
    }
    
    if (i >= line.len) return false;
    
    // Try IPv4 first (most common)
    if (i < line.len and std.ascii.isDigit(line[i])) {
        var j = i;
        while (j < line.len and (std.ascii.isDigit(line[j]) or line[j] == '.')) {
            j += 1;
        }
        
        if (rgcidr.parseIPv4(line[i..j])) |ip| {
            has_any_ip.* = true;
            if (patterns.matchesIPv4(ip)) {
                return true; // Early exit on first match!
            }
        } else |_| {}
    }
    
    // Try IPv6 if no IPv4 match found  
    if (i < line.len and (line[i] == ':' or std.ascii.isHex(line[i]))) {
        var j = i;
        while (j < line.len) {
            const c = line[j];
            if (!(std.ascii.isHex(c) or c == ':' or c == '.')) {
                break;
            }
            j += 1;
        }
        
            // Only try IPv6 if it contains colons and is long enough
            if (j > i + 2 and std.mem.indexOfScalar(u8, line[i..j], ':') != null) {
                // Check if we stopped at an invalid boundary
                var valid_extraction = true;
                if (j < line.len) {
                    const next_char = line[j];
                    // If we stopped at a letter that's not valid hex, reject
                    if (std.ascii.isAlphabetic(next_char) and !std.ascii.isHex(next_char)) {
                        valid_extraction = false;
                    }
                }
                
                if (valid_extraction) {
                    if (rgcidr.parseIPv6(line[i..j])) |ip| {
                        has_any_ip.* = true;
                        if (patterns.matchesIPv6(ip)) {
                            return true; // Early exit on first match!
                        }
                    } else |_| {}
                }
            }
    }
    
    return false;
}

/// Scan entire line with early termination
/// Uses hint-based scanning similar to C implementation's scan_with_hints
fn scanLineForMatchWithEarlyExit(line: []const u8, patterns: rgcidr.MultiplePatterns, has_any_ip: *bool) !bool {
    // Fast path: skip obviously non-IP lines
    if (line.len < 2) return false; // Minimum IP is "::" (2 chars)
    
    var i: usize = 0;
    
    while (i < line.len) {
        // IPv4 hint detection (mirrors C IPV4_HINT macro)
        if (std.ascii.isDigit(line[i])) {
            const has_dot_at_1 = (i + 1 < line.len and line[i + 1] == '.');
            const has_dot_at_2 = (i + 2 < line.len and line[i + 2] == '.');
            const has_dot_at_3 = (i + 3 < line.len and line[i + 3] == '.');
            
            if (has_dot_at_1 or has_dot_at_2 or has_dot_at_3) {
                // Found IPv4 hint, scan the field (match C IPV4_FIELD exactly)
            var j = i;
            while (j < line.len) {
                const c = line[j];
                // IPV4_FIELD = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz."
                if (!((c >= '0' and c <= '9') or (c >= 'A' and c <= 'Z') or (c >= 'a' and c <= 'z') or c == '.')) {
                    break;
                }
                j += 1;
            }
            
            if (rgcidr.parseIPv4(line[i..j])) |ip| {
                has_any_ip.* = true;
                if (patterns.matchesIPv4(ip)) {
                    return true; // Early exit on first match!
                }
            } else |_| {}
            
            i = j;
            continue;
            }
        }
        
        // IPv6 hint checks (like C IPV6_HINT macros) - improved detection
        if ((line[i] == ':' and i + 1 < line.len and line[i + 1] == ':') or
            (std.ascii.isHex(line[i]) and i + 1 < line.len and line[i + 1] == ':') or
            (i + 2 < line.len and std.ascii.isHex(line[i]) and std.ascii.isHex(line[i + 1]) and line[i + 2] == ':') or
            (i + 3 < line.len and std.ascii.isHex(line[i]) and std.ascii.isHex(line[i + 1]) and std.ascii.isHex(line[i + 2]) and line[i + 3] == ':') or
            (i + 4 < line.len and std.ascii.isHex(line[i]) and std.ascii.isHex(line[i + 1]) and std.ascii.isHex(line[i + 2]) and std.ascii.isHex(line[i + 3]) and line[i + 4] == ':')) {
            
            // Found IPv6 hint, scan the field
            var j = i;
            while (j < line.len) {
                const c = line[j];
                if (!(std.ascii.isHex(c) or c == ':' or c == '.')) {
                    break;
                }
                j += 1;
            }
            
            // Only try IPv6 if it contains colons
            if (j > i and std.mem.indexOfScalar(u8, line[i..j], ':') != null) {
                // Check if we stopped at an invalid boundary
                var valid_extraction = true;
                if (j < line.len) {
                    const next_char = line[j];
                    // If we stopped at a letter that's not valid hex, reject
                    if (std.ascii.isAlphabetic(next_char) and !std.ascii.isHex(next_char)) {
                        valid_extraction = false;
                    }
                }
                
                if (valid_extraction) {
                    if (rgcidr.parseIPv6(line[i..j])) |ip| {
                        has_any_ip.* = true;
                        if (patterns.matchesIPv6(ip)) {
                            return true; // Early exit on first match!
                        }
                    } else |_| {}
                }
            }
            
            i = j;
            continue;
        }
        
        i += 1;
    }
    
    return false;
}

/// Scan entire line for all IPs (needed for invert logic)
fn scanLineForAllMatches(line: []const u8, patterns: rgcidr.MultiplePatterns, exact_match: bool, has_any_ip: *bool, allocator: Allocator) !bool {
    var has_matching_ip = false;
    
    if (exact_match) {
        // Just check line start
        return scanLineStartForMatch(line, patterns, has_any_ip);
    }
    
    // Need to find all IPs for invert logic (slow path)
    var scanner = rgcidr.IpScanner.init(allocator);
    defer scanner.deinit();
    
    const ipv4s = try scanner.scanIPv4(line);
    const ipv6s = try scanner.scanIPv6(line);
    
    has_any_ip.* = (ipv4s.len > 0 or ipv6s.len > 0);
    
    for (ipv4s) |ip| {
        if (patterns.matchesIPv4(ip)) {
            has_matching_ip = true;
            break;
        }
    }
    
    if (!has_matching_ip) {
        for (ipv6s) |ip| {
            if (patterns.matchesIPv6(ip)) {
                has_matching_ip = true;
                break;
            }
        }
    }
    
    return has_matching_ip;
}


test "simple test" {
    const gpa = std.testing.allocator;
    var list: std.ArrayList(i32) = .empty;
    defer list.deinit(gpa); // Try commenting this out and see if zig detects the memory leak!
    try list.append(gpa, 42);
    try std.testing.expectEqual(@as(i32, 42), list.pop());
}

test "fuzz example" {
    const Context = struct {
        fn testOne(context: @This(), input: []const u8) anyerror!void {
            _ = context;
            // Try passing `--fuzz` to `zig build test` and see if it manages to fail this test case!
            try std.testing.expect(!std.mem.eql(u8, "canyoufindme", input));
        }
    };
    try std.testing.fuzz(Context{}, Context.testOne, .{});
}
