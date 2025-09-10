# rgcidr

A high-performance Zig library and CLI tool for filtering IPv4 and IPv6 addresses against CIDR patterns. This is a Zig reimplementation of [grepcidr](https://github.com/jrlevine/grepcidr) with optimized performance matching or exceeding the C original.

## Features

- ⚡ **Fast**: Performance within 1.1x of the C implementation
- 🔍 **Dual Mode**: Available as both a library and CLI tool
- 🌐 **Full IP Support**: IPv4 and IPv6 with all notation formats
- 📦 **Zero Dependencies**: Pure Zig implementation
- 🎯 **Pattern Matching**: Single IPs, CIDR ranges, and IP ranges
- 🚀 **Optimized**: Early-exit scanning, buffered output, binary search

## Installation

### As a Zig Package (Library)

Add to your `build.zig.zon`:

```zig
.dependencies = .{
    .rgcidr = .{
        .url = "https://github.com/yourusername/rgcidr/archive/refs/tags/v0.1.0.tar.gz",
        .hash = "...", // Use `zig fetch --save` to get the hash
    },
},
```

Then in your `build.zig`:

```zig
const rgcidr = b.dependency("rgcidr", .{
    .target = target,
    .optimize = optimize,
});
exe.root_module.addImport("rgcidr", rgcidr.module("rgcidr"));
```

### As a CLI Tool

```bash
# Clone and build (always use ReleaseFast for optimal performance)
git clone https://github.com/yourusername/rgcidr
cd rgcidr
zig build -Doptimize=ReleaseFast

# Install to system
zig build install --prefix ~/.local -Doptimize=ReleaseFast

# Or use directly
./zig-out/bin/rgcidr
```

## Library Usage

```zig
const std = @import("std");
const rgcidr = @import("rgcidr");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Parse patterns
    const pattern = try rgcidr.parsePattern("192.168.0.0/16", false);

    // Check if IP matches
    const ip = try rgcidr.parseIPv4("192.168.1.100");
    if (pattern.matchesIPv4(ip)) {
        std.debug.print("IP matches!\n", .{});
    }

    // Scan text for IP addresses
    var scanner = rgcidr.IpScanner.init(allocator);
    defer scanner.deinit();

    const line = "Server 192.168.1.50 responded";
    const ips = try scanner.scanIPv4(line);
    for (ips) |found_ip| {
        if (pattern.matchesIPv4(found_ip)) {
            std.debug.print("Found matching IP\n", .{});
        }
    }

    // Multiple patterns with optimized matching
    var patterns = try rgcidr.parseMultiplePatterns(
        "10.0.0.0/8,192.168.0.0/16 172.16.0.0/12",
        false,
        allocator
    );
    defer patterns.deinit();

    const test_ip = try rgcidr.parseIPv4("10.1.1.1");
    const is_private = patterns.matchesIPv4(test_ip);
}
```

## CLI Usage

```bash
# Basic usage
rgcidr PATTERN [FILE]

# Match IPs in file
rgcidr "192.168.0.0/16" access.log

# Multiple patterns
rgcidr "10.0.0.0/8,192.168.0.0/16" logfile.txt

# IPv6 support
rgcidr "2001:db8::/32" ipv6.log

# Options
rgcidr -c "192.168.0.0/16" file.txt  # Count matches
rgcidr -v "10.0.0.0/8" file.txt      # Invert match
rgcidr -s "192.168.1.0/24" file.txt  # Strict CIDR alignment
rgcidr -x "192.168.1.1" file.txt     # Exact match (start of line)
rgcidr -f patterns.txt file.txt       # Read patterns from file
```

## API Reference

### Core Types

- `IPv4` - 32-bit IPv4 address
- `IPv6` - 128-bit IPv6 address
- `Pattern` - Single IP, CIDR range, or IP range
- `MultiplePatterns` - Optimized multi-pattern matcher

### Parsing Functions

- `parseIPv4(str)` - Parse IPv4 address
- `parseIPv6(str)` - Parse IPv6 address (with embedded IPv4 support)
- `parsePattern(str, strict)` - Parse IP pattern
- `parseMultiplePatterns(str, strict, allocator)` - Parse multiple patterns

### Scanning Functions

- `IpScanner.scanIPv4(line)` - Extract IPv4 addresses from text
- `IpScanner.scanIPv6(line)` - Extract IPv6 addresses from text

## Performance

The Zig implementation achieves excellent performance through:

- **Early-exit scanning**: Stops on first match when possible
- **Binary search**: O(log n) pattern matching
- **Buffered output**: Minimizes system calls
- **Hint-based scanning**: Efficient IP detection in text
- **Inlined hot paths**: Critical functions are inlined

Benchmarks show performance within 1.1-1.2x of the C implementation.

### Regression Testing

The project includes automated regression testing to detect performance regressions:

```bash
# Compare current branch vs main
zig build bench-regression

# Compare against specific branch
lua scripts/bench_regression.lua develop

# Get CSV output for CI/CD
lua scripts/bench_regression.lua main --csv
```

Regression testing:
- Automatically stashes/restores uncommitted changes
- Builds both versions with ReleaseFast optimization
- Compares benchmark results and flags regressions >5%
- Exits with error code 1 if significant regressions detected

## Building from Source

```bash
# Development build
zig build

# Optimized builds
zig build -Doptimize=ReleaseFast    # Fast execution
zig build -Doptimize=ReleaseSmall   # Small binary
zig build -Doptimize=ReleaseSafe    # Safety checks

# Run tests
zig build test

# Run benchmarks (automatically uses ReleaseFast)
zig build bench
zig build bench-advanced

# Regression testing (compare against main branch)
zig build bench-regression

# Manual regression testing
lua scripts/bench_regression.lua [baseline-branch] [--csv]
lua scripts/bench_regression.lua develop --csv  # Compare against develop branch

# Note: For accurate performance testing, always use ReleaseFast:
zig build -Doptimize=ReleaseFast
lua scripts/test.lua --benchmark
```

## Requirements

- Zig 0.15.1 or later
- No external dependencies

## License

MIT License - see [LICENSE](LICENSE) file for details.

## Contributing

Contributions are welcome! Please ensure:
- All tests pass (`zig build test`)
- Performance remains competitive (run benchmarks)
- Code follows Zig conventions

## Acknowledgments

Based on [grepcidr](https://github.com/jrlevine/grepcidr) by John Levine.
