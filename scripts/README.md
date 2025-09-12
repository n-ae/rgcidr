# Scripts Directory

This directory contains the unified test and benchmark system for rgcidr.

## Unified Test System

### rgcidr_test.lua - Main Test Runner

**All testing functionality has been consolidated** into a single script that replaced 35+ individual test scripts:

```bash
# Basic usage
lua scripts/rgcidr_test.lua [options]

# Help and options
lua scripts/rgcidr_test.lua --help
```

#### Test Presets

```bash
--all                Run everything (tests + comprehensive benchmarks)
--ci                 CI-friendly tests (unit, functional, quick benchmarks)
--development        Developer tests (unit, functional, micro-benchmarks) [default]
--release            Release validation (all tests, comprehensive benchmarks)
--performance        Performance focus (all benchmarks, profiling, validation)
```

#### Individual Test Types

```bash
--unit               Run Zig unit tests
--functional         Run functional tests
--compare            Compare with grepcidr
--rfc                Run RFC compliance tests
--regression         Run regression tests vs baseline
```

#### Benchmark Types

```bash
--bench              Run standard benchmarks
--bench-quick        Run quick benchmarks (5 runs each)
--bench-comprehensive Run comprehensive benchmarks (20+ runs)
--bench-micro        Run micro-benchmarks for optimization
--bench-statistical  Run statistical benchmarks (30 runs, outlier removal)
--bench-validation   Run optimization validation benchmarks
```

#### Advanced Options

```bash
--csv                Output in CSV format
--json               Output in JSON format
--quiet              Minimal output
--verbose            Detailed output
--report             Generate comprehensive report
--runs=N             Number of benchmark runs (default: auto)
--variance-target=N  Target variance percentage (default: 10%)
--baseline=REF       Git ref for regression tests (default: main)
--build-debug        Build with debug optimization
--build-fast         Build with ReleaseFast (default)
--no-build           Skip building (use existing binaries)
```

## Key Features

### Automatic Binary Management
- **rgcidr**: Automatically builds with optimal settings
- **grepcidr**: Fetches and builds official grepcidr 2.0 from pc-tools.net via `fetch_grepcidr.lua`
- **Build optimization**: Enforces ReleaseFast for all performance tests

### Statistical Analysis
- **30-run benchmarks** with 5-run warmup
- **Outlier detection** and removal (>2 standard deviations)
- **95% confidence intervals**
- **Variance targets** of 10-15% for reliable measurements
- **Statistical significance testing** for performance comparisons

### Integration
- **Zig build system**: All `zig build` commands route through the unified script
- **CI/CD support**: CSV/JSON output for automated analysis
- **Regression testing**: Automatic comparison against baseline branches

## Supporting Scripts

### fetch_grepcidr.lua
Manages the official grepcidr 2.0 binary (used internally by the unified system):

```bash
# Get path to grepcidr binary (builds if needed)
lua scripts/fetch_grepcidr.lua get

# Show information about grepcidr source
lua scripts/fetch_grepcidr.lua info

# Clean up temporary files
lua scripts/fetch_grepcidr.lua clean
```

**Source**: https://www.pc-tools.net/files/unix/grepcidr-2.0.tar.gz  
**Author**: Jem Berkes  
**Version**: 2.0 (2014-05-26)

## Examples

```bash
# Default development testing
lua scripts/rgcidr_test.lua

# Comprehensive CI testing with CSV output
lua scripts/rgcidr_test.lua --ci --csv

# Performance analysis with custom run count
lua scripts/rgcidr_test.lua --performance --runs=50

# Statistical benchmarking with low variance target
lua scripts/rgcidr_test.lua --bench-statistical --variance-target=5.0

# Compare with grepcidr and generate report
lua scripts/rgcidr_test.lua --compare --bench-compare --report

# Regression testing against develop branch
lua scripts/rgcidr_test.lua --regression --baseline=develop
```

## Build System Integration

All `zig build` commands use the unified script:

```bash
zig build rgcidr-test      # → lua scripts/rgcidr_test.lua
zig build test-ci          # → lua scripts/rgcidr_test.lua --ci
zig build bench-statistical # → lua scripts/rgcidr_test.lua --bench-statistical
zig build test-all         # → lua scripts/rgcidr_test.lua --all
```

## Requirements

- **Lua 5.1+** (no external dependencies)
- **Zig 0.15.1+** (for building rgcidr)
- **gcc/clang and make** (for building grepcidr)
- **curl** (for downloading grepcidr)

## Performance Notes

1. **ReleaseFast optimization** is automatically enforced for all performance tests
2. **Statistical reliability** achieved through 30-run benchmarks with outlier filtering
3. **System variance** typically 10-15% (excellent for system-level benchmarking)
4. **Automatic warmup** (5 runs) before measurement collection

## Troubleshooting

If scripts fail:

1. **Check Lua is installed**: `lua -v`
2. **Verify Zig version**: `zig version` (needs 0.15.1+)
3. **Ensure make is available**: `which make`
4. **Check internet connection** for grepcidr download
5. **Clean temporary files**: `lua scripts/fetch_grepcidr.lua clean`
6. **Use verbose mode**: `lua scripts/rgcidr_test.lua --verbose`

## Contributing

When modifying the test system:
1. **Update the unified script** (`rgcidr_test.lua`) for new functionality
2. **Add new functionality** through flags and options
3. **Include statistical analysis** for any new benchmark types
4. **Update this README** with new options and examples
5. **Update build.zig** for any new build targets