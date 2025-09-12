# rgcidr

A high-performance Zig library and CLI tool for filtering IPv4 and IPv6 addresses against CIDR patterns. This is a Zig reimplementation of [grepcidr](https://www.pc-tools.net/unix/grepcidr/) with optimized performance matching or exceeding the C original.

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

### Performance Validation

The unified test system provides comprehensive performance validation:

- **Statistical benchmarking**: 30 runs with outlier detection and 95% confidence intervals
- **Regression testing**: Automatic comparison against baseline branches
- **Performance targets**: Maintains performance within 1.1x of original grepcidr
- **Variance control**: Achieves 10-15% variance for reliable measurements

```bash
# Quick performance check during development
zig build bench-quick

# Comprehensive statistical analysis
zig build bench-statistical

# Compare performance vs grepcidr
zig build bench-compare

# Regression testing against main branch
zig build bench-regression
```

## Building from Source

```bash
# Development build
zig build

# Optimized builds
zig build -Doptimize=ReleaseFast    # Fast execution (use for benchmarking)
zig build -Doptimize=ReleaseSmall   # Small binary
zig build -Doptimize=ReleaseSafe    # Safety checks

# Install to system
zig build install --prefix ~/.local -Doptimize=ReleaseFast
```

## Testing and Benchmarking

### Unified Test System

All testing functionality is consolidated into a single runner:

```bash
# Basic tests (unit + functional)
zig build rgcidr-test

# Test presets
zig build test-ci          # CI-friendly tests
zig build test-dev          # Developer tests (default)
zig build test-release      # Release validation
zig build test-performance  # Performance focus
zig build test-all          # Everything

# Individual test types
zig build test-unit         # Zig unit tests only
zig build test-functional   # Functional tests only
zig build test-compare      # Compare with grepcidr
zig build test-rfc          # RFC compliance tests

# Benchmarks
zig build bench             # Standard benchmarks
zig build bench-quick       # Quick benchmarks (5 runs)
zig build bench-comprehensive # 20+ runs with statistics
zig build bench-statistical # 30 runs with outlier removal
zig build bench-compare     # Compare with grepcidr

# Performance analysis
zig build profile           # Performance profiling
zig build optimize-validate # Validate optimizations
zig build scaling-analysis  # Test scaling characteristics
```

### Advanced Usage

```bash
# Direct script usage with custom options
lua scripts/rgcidr_test.lua --help
lua scripts/rgcidr_test.lua --performance --csv
lua scripts/rgcidr_test.lua --bench-statistical --runs=50
lua scripts/rgcidr_test.lua --unit --functional --verbose

# Regression testing
zig build bench-regression  # Compare vs main branch
lua scripts/rgcidr_test.lua --regression --baseline=develop
```

### Benchmark Features

- **Automatic binary management**: Builds rgcidr and fetches/builds grepcidr as needed
- **Statistical analysis**: 30-run benchmarks with outlier detection and confidence intervals
- **Performance tracking**: Variance targets of 10-15% for reliable measurements
- **CSV/JSON output**: Machine-readable results for CI/CD integration

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

Based on the original [grepcidr](https://www.pc-tools.net/unix/grepcidr/) by Jem Berkes.
- Official source: https://www.pc-tools.net/unix/grepcidr/
- Version 2.0: https://www.pc-tools.net/files/unix/grepcidr-2.0.tar.gz
