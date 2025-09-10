# rgcidr Architecture Guide

This document explains the architecture of rgcidr, a Zig reimplementation of grepcidr that follows a clean dual-module pattern separating SDK and CLI concerns.

## Overview

The rgcidr project implements a **dual-module architecture** that provides both:

1. **Library SDK** (`src/root.zig`) - Core CIDR functionality for embedding in other projects
2. **CLI Tool** (`src/main.zig`) - Command-line interface that uses the library

This separation enables developers to use rgcidr either as a standalone CLI tool or as a library dependency in their own Zig projects.

## Architecture Diagram

```
┌─────────────────────────────────────────────────────────────┐
│                     External Consumers                      │
├─────────────────────┬───────────────────────────────────────┤
│   Other Zig Apps   │            CLI Users                  │
│                     │                                       │
│   @import("rgcidr") │      ./rgcidr pattern file.txt       │
└─────────────────────┼───────────────────────────────────────┘
                      │
              ┌───────┴────────┐
              │  rgcidr CLI    │
              │  (src/main.zig)│
              │                │
              │ • Arg parsing  │
              │ • File I/O     │  
              │ • Exit codes   │
              │ • Help text    │
              └───────┬────────┘
                      │
                      │ @import("rgcidr")
                      │
              ┌───────▼────────┐
              │  rgcidr SDK    │
              │ (src/root.zig) │
              │                │
              │ • IP parsing   │
              │ • CIDR matching│
              │ • IPv6 support │
              │ • Pattern logic│
              └────────────────┘
```

## Module Responsibilities

### SDK Module (`src/root.zig`)

**Purpose**: Pure CIDR functionality with no I/O or CLI dependencies.

**Core Types**:
- `IPv4` / `IPv6` - IP address representations
- `Pattern` - Union type for single IPs, CIDR ranges, IP ranges
- `MultiplePatterns` - Collection of patterns with efficient matching
- `IpParseError` - Comprehensive error handling

**Key Functions**:
```zig
// Parsing
pub fn parseIPv4(ip_str: []const u8) IpParseError!IPv4;
pub fn parseIPv6(ip_str: []const u8) IpParseError!IPv6;
pub fn parsePattern(pattern_str: []const u8, strict_align: bool) IpParseError!Pattern;
pub fn parseMultiplePatterns(patterns: []const u8, strict_align: bool, allocator: Allocator) IpParseError!MultiplePatterns;

// Discovery  
pub fn findIPv4InLine(line: []const u8, allocator: Allocator) !std.ArrayList(IPv4);
pub fn findIPv6InLine(line: []const u8, allocator: Allocator) !std.ArrayList(IPv6);

// Formatting
pub fn formatIPv4(ip: IPv4, buffer: []u8) ![]u8;
```

**Design Principles**:
- ✅ No file I/O operations
- ✅ No process or system calls
- ✅ Memory management through passed allocators
- ✅ Pure functions with explicit error handling
- ✅ Comprehensive test coverage

### CLI Module (`src/main.zig`)

**Purpose**: Command-line interface that imports and uses the SDK.

**Responsibilities**:
- Command-line argument parsing (`-c`, `-v`, `-s`, `-f`, etc.)
- File and stdin I/O management
- Process lifecycle (exit codes, error messages)
- Help text and version information
- Output formatting (normal vs count mode)

**Design Principles**:
- ✅ Minimal business logic (delegates to SDK)
- ✅ No IP parsing or CIDR logic
- ✅ Clean separation of I/O from computation
- ✅ CLI-specific error handling and user feedback

## Build System Integration

The `build.zig` configuration properly exposes both aspects:

```zig
// Library module for external consumers
const mod = b.addModule("rgcidr", .{
    .root_source_file = b.path("src/root.zig"),
    .target = target,
});

// CLI executable that imports the library
const exe = b.addExecutable(.{
    .name = "rgcidr",
    .root_module = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "rgcidr", .module = mod },
        },
    }),
});
```

This setup enables:
- External projects to import `rgcidr` as a dependency
- Separate testing of library vs CLI functionality  
- Independent optimization of each module

## Library Usage Examples

### Basic Integration

Add to your `build.zig.zon`:
```zig
.dependencies = .{
    .rgcidr = .{
        .url = "https://github.com/user/rgcidr/archive/main.tar.gz",
        .hash = "...", // zig fetch will provide this
    },
},
```

Add to your `build.zig`:
```zig
const rgcidr_dep = b.dependency("rgcidr", .{
    .target = target,
    .optimize = optimize,
});
exe.root_module.addImport("rgcidr", rgcidr_dep.module("rgcidr"));
```

### Code Example

```zig
const std = @import("std");
const rgcidr = @import("rgcidr");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Parse corporate network patterns
    var patterns = try rgcidr.parseMultiplePatterns(
        "192.168.0.0/16 10.0.0.0/8 172.16.0.0/12", 
        false, 
        allocator
    );
    defer patterns.deinit();

    // Check if an IP is internal
    const ip = try rgcidr.parseIPv4("192.168.1.100");
    const is_internal = patterns.matchesIPv4(ip);
    
    std.debug.print("IP 192.168.1.100 is internal: {}\n", .{is_internal});
}
```

See the [`examples/`](examples/) directory for comprehensive usage examples.

## Testing Strategy

### SDK Tests (`src/root.zig`)
- Unit tests for all parsing functions
- IPv4/IPv6 compatibility testing  
- CIDR calculation verification
- Pattern matching edge cases
- Memory management validation

### CLI Tests (`src/main.zig`)
- Argument parsing validation
- Exit code verification
- I/O handling
- Integration with the SDK

### System Tests (`tests/`)
- End-to-end behavior validation
- Compatibility with original grepcidr
- Performance benchmarking
- Edge case handling

Run tests:
```bash
# All tests
zig build test

# Library only
zig test src/root.zig

# CLI only  
zig test src/main.zig
```

## Performance Characteristics

The dual-module architecture provides:

**Library Benefits**:
- No CLI parsing overhead when used as library
- Direct memory management control
- Optimizable for specific use cases
- Minimal allocation patterns

**CLI Benefits**:
- Efficient streaming I/O processing
- Memory-conscious file handling
- Proper resource cleanup

**Benchmarks**:
```bash
./scripts/benchmark.sh
```

Comparative performance is competitive with the original C implementation while providing memory safety and more maintainable code.

## Extension Points

The architecture supports easy extension:

### Adding New Pattern Types
Extend the `Pattern` union in `src/root.zig`:
```zig
pub const Pattern = union(enum) {
    // Existing patterns...
    custom_pattern: CustomPattern,
    
    pub fn matchesIPv4(self: Pattern, ip: IPv4) bool {
        return switch (self) {
            // Handle new pattern type
            .custom_pattern => |custom| custom.matches(ip),
            // ... other patterns
        };
    }
};
```

### Adding New CLI Features
Extend argument parsing in `src/main.zig` without touching the SDK:
```zig
// New flags, output formats, etc.
var new_flag = false;
// ... handle in argument parsing loop
```

## Best Practices

When using rgcidr as a library:

1. **Memory Management**: Always use appropriate allocators and defer cleanup
2. **Error Handling**: Handle all `IpParseError` variants appropriately  
3. **Performance**: Reuse `MultiplePatterns` for bulk operations
4. **IPv6 Support**: Design with both IPv4 and IPv6 in mind
5. **Testing**: Write tests that cover your specific usage patterns

When extending the CLI:

1. **Delegate Logic**: Keep business logic in the SDK, not the CLI
2. **User Experience**: Provide clear error messages and help text  
3. **Compatibility**: Maintain compatibility with original grepcidr behavior
4. **Testing**: Verify both success and failure cases

## Conclusion

The rgcidr dual-module architecture successfully separates concerns between library functionality and CLI interface. This enables both standalone usage and library integration while maintaining clean, testable, and performant code.

The architecture follows Zig idioms and best practices, providing a solid foundation for both current functionality and future extensions.
