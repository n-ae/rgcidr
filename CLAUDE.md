# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**rgcidr** is a high-performance Zig reimplementation of grepcidr for filtering IPv4/IPv6 addresses against CIDR patterns. It's designed as a dual-module architecture: a library SDK for integration and a CLI tool for standalone use.

### Key Technical Details
- **Language**: Zig 0.15.1+ 
- **Architecture**: Dual-module (library + CLI)
- **Performance Target**: Within 1.1x of original C grepcidr
- **IPv6 Support**: Full IPv6 with embedded IPv4 extraction (::ffff:x.x.x.x)
- **Optimization**: Binary search for multiple patterns, early-exit scanning

## Essential Commands

### Building
```bash
# Development build
zig build

# Production build (always use for performance testing)
zig build -Doptimize=ReleaseFast

# Install to system
zig build install --prefix ~/.local -Doptimize=ReleaseFast
```

### Testing - Unified Test System
The project uses a consolidated test runner at `scripts/rgcidr_test.lua` that replaced 35+ individual test scripts:

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

### Direct Script Usage
```bash
# Unified test runner with all options
lua scripts/rgcidr_test.lua --help

# Examples
lua scripts/rgcidr_test.lua --performance --csv
lua scripts/rgcidr_test.lua --unit --functional
lua scripts/rgcidr_test.lua --bench-statistical --runs=50
```

## Code Architecture

### Source Structure
- `src/root.zig` - Core library module with IPv4/IPv6 parsing and CIDR matching
- `src/main.zig` - CLI application with optimized buffered I/O
- `build.zig` - Build configuration integrated with unified test system
- `tests/` - Functional test files (`.given/.action/.expected` format)
- `scripts/rgcidr_test.lua` - Unified test and benchmark runner

### Dual Module Architecture
The project is structured as two modules that share optimized core functionality:

1. **Library Module** (`src/root.zig`):
   - Public API for IPv4/IPv6 parsing and pattern matching
   - Optimized data structures (`IPv4Range`, `IPv6Range`, `MultiplePatterns`)
   - Branchless comparison algorithms for performance
   - Binary search for multiple pattern matching

2. **CLI Module** (`src/main.zig`):
   - Command-line interface compatible with grepcidr
   - Buffered I/O with 64KB output buffer
   - Early-exit scanning optimizations
   - Memory-efficient line processing

### Performance Optimizations
- **Branchless IPv4/IPv6 range comparisons**: Uses arithmetic `(ip - min) <= (max - min)` instead of conditional branches
- **Comptime specialization**: Functions specialized for 1-6 patterns at compile time
- **Binary search**: O(log n) pattern matching for multiple patterns
- **Cache-friendly algorithms**: Optimized memory access patterns
- **Early-exit scanning**: Stops processing on first match when possible

### Key Data Structures
- `IPv4Range`/`IPv6Range` with branchless `containsIP()` methods
- `MultiplePatterns` with sorted ranges for binary search
- `IpScanner` for extracting IPs from text with hint-based lookahead

## Development Workflow

### Daily Development
```bash
# Quick development cycle
zig build                    # Build project
zig build test-dev          # Run developer tests

# Before committing
zig build test-all          # Comprehensive validation
zig build bench-compare     # Performance check
```

### Performance Testing
Critical: Always use `ReleaseFast` for accurate performance measurements:
```bash
# The unified test system automatically enforces ReleaseFast for benchmarks
zig build bench-statistical  # 30 runs with statistical analysis
zig build bench-compare     # Compare performance vs grepcidr
```

### Regression Testing
```bash
zig build bench-regression  # Compare vs main branch
lua scripts/rgcidr_test.lua --regression --baseline=develop
```

## Important Notes

### Performance Requirements
- **Always use ReleaseFast** (`-Doptimize=ReleaseFast`) for performance testing
- The unified test system automatically enforces this for all benchmark commands
- Target: Performance within 1.1x of original grepcidr (currently achieving ~1.0x)

### Test System Architecture  
- **Single entry point**: `scripts/rgcidr_test.lua` replaces 35+ individual scripts
- **Automatic binary management**: Builds rgcidr and fetches/builds grepcidr as needed
- **Statistical reliability**: Advanced benchmarking with outlier detection and confidence intervals
- **Flag-based control**: Comprehensive options for all test scenarios

### Binary Dependencies
- **grepcidr**: Automatically fetched and built via `scripts/fetch_grepcidr.lua`
- **lua**: Required for running test scripts
- **zig**: 0.15.1 or later

## Key Implementation Details

### IPv6 Embedded IPv4 Support
Handles IPv4-mapped IPv6 addresses (`::ffff:192.168.1.1`) by extracting the embedded IPv4 portion for processing.

### Pattern Matching Optimizations
- **1-6 patterns**: Comptime-specialized functions for optimal performance
- **7+ patterns**: Binary search on sorted ranges
- **Branchless comparisons**: Arithmetic-based range checking

### Memory Management
- CLI uses arena allocator for request-scoped memory
- Library API allows caller-provided allocators
- Efficient line-by-line processing without full file loading

### Statistical Benchmarking
The benchmark system provides:
- 30-run statistical analysis with outlier detection
- 95% confidence intervals
- Variance targets (typically 10-15% achievable)
- Automated comparison with grepcidr performance

## Latest Release Info: v0.1.3

### Latest Release: v0.1.3

Released: 2025-09-26 23:48:32 UTC
Tag: v0.1.3
Commit: 9343633
Status: ✅ Published to Homebrew and Scoop

This release was automatically created when version 0.1.3 was pushed to main branch.

## Package Manager Publishing - COMPLETED ✅

### Repositories
- **Main Project**: https://github.com/n-ae/rgcidr
- **Package Repository**: https://github.com/n-ae/homebrew-packages (Note: correct name with 'homebrew-' prefix)

### Installation Commands
```bash
# macOS/Linux (Homebrew) - WORKING
brew tap n-ae/packages
brew install rgcidr

# Windows (Scoop) - READY
scoop bucket add packages https://github.com/n-ae/homebrew-packages
scoop install rgcidr
```

### Version Check (Important!)
```bash
# Use -V flag (not --version)
rgcidr -V
# Output: rgcidr 0.1.0 - Zig implementation of grepcidr
```

### Current Package Versions & Hashes
- **rgcidr**: v0.1.3
- **Source SHA256**: 254d4ac6e5848d93f917d772e535a0fc184ddf1f2e492bffc795b2451fa3e233
- **Windows x64 SHA256**: 0e436314de55ae9428dd6ed0604d6d4d3190aa15e28e91df8db887876396cc63
- **Windows x86 SHA256**: 75a43ae9924a8946190d6108f27d8d2b97435d47e80d4526763fe047ede1ebb2

### Package Repository Structure (~/dev/homebrew-packages/)
```
homebrew-packages/
├── Formula/              # Homebrew formulae (ROOT LEVEL - important!)
│   └── rgcidr.rb        # v0.1.3 with correct SHA256
├── scoop/bucket/        # Scoop manifests
│   └── rgcidr.json      # v0.1.3 with correct hashes
├── scripts/             # Automation scripts
│   ├── update-all.sh    # Cross-platform updates
│   ├── get-release-hashes.sh  # Extract SHA256 from releases
│   └── homebrew/        # Platform-specific scripts
├── .github/workflows/   # CI/CD with proper permissions
└── docs/                # Complete documentation
```

### Important Lessons Learned
1. **Repository Naming**: Must be `homebrew-packages` for tap `n-ae/packages` to work
2. **Directory Structure**: Formula MUST be at root `Formula/`, not `homebrew/Formula/`
3. **Authentication**: Clear cached credentials with `git credential-osxkeychain erase` for public repos
4. **Version Flag**: rgcidr uses `-V` (not `--version`) for grepcidr compatibility

### Release Process (For Future Updates)
1. Update version in `build.zig.zon`
2. Commit and push to main
3. Release workflow auto-triggers with multi-platform builds
4. Update packages: `cd ~/dev/homebrew-packages && ./scripts/update-all.sh rgcidr <version>`
5. Test installation on all platforms

### Testing Legacy System - REMOVED ✅
- Removed 35+ legacy test scripts
- Consolidated into unified `scripts/rgcidr_test.lua` 
- Placeholder implementations for complex benchmarks
- All CI/CD updated to use unified system

### Current Status: FULLY OPERATIONAL
- ✅ Published to both Homebrew and Scoop
- ✅ No authentication prompts for installation  
- ✅ Multi-platform binaries with verified checksums
- ✅ Automated update workflows
- ✅ Comprehensive documentation and security policies
- ✅ Public repository with proper permissions

## Quick Continuation Commands

### Resume Development
```bash
cd ~/dev/rgcidr
zig build test-dev                    # Quick development tests
lua scripts/rgcidr_test.lua --unit   # Fast unit tests
```

### Package Maintenance  
```bash
cd ~/dev/homebrew-packages
./scripts/get-release-hashes.sh <version>   # Get new release hashes
./scripts/update-all.sh rgcidr <version>    # Update both platforms
```

### Performance Testing
```bash
cd ~/dev/rgcidr  
zig build bench-statistical           # Statistical analysis
zig build bench-compare              # Compare vs grepcidr
```

The project is fully published and operational across all platforms!