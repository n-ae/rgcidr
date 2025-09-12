# Benchmarking Guide

This document describes how to benchmark rgcidr against the official grepcidr implementation and analyze performance.

## Official grepcidr Source

The benchmarks compare against the **original grepcidr 2.0** by Jem Berkes:
- **Official Website**: https://www.pc-tools.net/unix/grepcidr/
- **Source Archive**: https://www.pc-tools.net/files/unix/grepcidr-2.0.tar.gz
- **Version**: 2.0 (released 2014-05-26)
- **License**: GNU GPL
- **Author**: Jem Berkes

Note: This is the original implementation. There is also a fork by John Levine, but our benchmarks use the official source from pc-tools.net.

## Quick Start

### Unified Test System

The easiest way to benchmark using the consolidated test system:

```bash
# Compare performance with grepcidr (recommended)
zig build bench-compare

# Statistical benchmarking with 30 runs
zig build bench-statistical

# Quick performance check
zig build bench-quick

# Comprehensive performance analysis
zig build test-performance
```

The unified system automatically:
1. Downloads and builds official grepcidr 2.0 from pc-tools.net
2. Builds rgcidr with ReleaseFast optimization
3. Runs statistical analysis with outlier detection
4. Generates detailed reports with confidence intervals

### Binary Management

The unified system automatically manages binaries, but you can also control them manually:

```bash
# Show information about grepcidr source
lua scripts/fetch_grepcidr.lua info

# Get path to grepcidr binary (builds if needed)
GREPCIDR_PATH=$(lua scripts/fetch_grepcidr.lua get)

# Clean up temporary files
lua scripts/fetch_grepcidr.lua clean

# Skip building (use existing binaries)
lua scripts/rgcidr_test.lua --bench-compare --no-build
```

## Benchmark Types

### 1. Standard Benchmarks

```bash
# Quick benchmarks (5 runs each)
zig build bench-quick

# Standard benchmarks
zig build bench

# Comprehensive benchmarks (20+ runs)
zig build bench-comprehensive

# Statistical benchmarks (30 runs with outlier removal)
zig build bench-statistical
```

### 2. Performance Comparison

```bash
# Compare against official grepcidr 2.0
zig build bench-compare

# Performance validation suite
zig build bench-validation
```

Output includes:
- Statistical analysis with confidence intervals
- Variance measurements (target: 10-15%)
- Performance comparisons with significance testing
- CSV/JSON output for automation

### 3. Regression Testing

```bash
# Compare current branch against main
zig build bench-regression

# Advanced regression testing with custom baseline
lua scripts/rgcidr_test.lua --regression --baseline=develop --csv
```

### 4. Direct Script Usage

```bash
# Full control over benchmarking options
lua scripts/rgcidr_test.lua --help
lua scripts/rgcidr_test.lua --bench-statistical --runs=50 --variance-target=5.0
lua scripts/rgcidr_test.lua --performance --csv --report
```

## Understanding Results

### Performance Metrics

- **Mean Time**: Average execution time across iterations
- **Min/Max Time**: Best and worst case performance
- **Speedup Factor**: Ratio of grepcidr time to rgcidr time
  - `> 1.0`: rgcidr is faster
  - `< 1.0`: grepcidr is faster
  - `≈ 1.0`: Similar performance

### Performance Categories

- **Excellent** (>1.5x): rgcidr significantly faster
- **Good** (1.1-1.5x): rgcidr moderately faster
- **Comparable** (0.9-1.1x): Similar performance
- **Slower** (0.5-0.9x): grepcidr moderately faster
- **Poor** (<0.5x): grepcidr significantly faster

### Key Files

Generated outputs:
- `benchmark_official.csv`: Detailed results in CSV format
- `benchmark_results.csv`: Simple benchmark results
- `benchmark_comprehensive.csv`: Full test suite results

## Building for Benchmarks

### Optimization Levels

Always use `ReleaseFast` for benchmarking:

```bash
# Optimal for benchmarking
zig build -Doptimize=ReleaseFast

# Other options (not recommended for benchmarks)
zig build -Doptimize=Debug        # Development only
zig build -Doptimize=ReleaseSafe  # With safety checks
zig build -Doptimize=ReleaseSmall # Size optimization
```

### Official grepcidr Build

The fetch script builds grepcidr with:
- `-O3` optimization (maximum performance)
- Standard C compiler (gcc/clang)
- No debug symbols

## Test Data

### Test Structure

Tests are located in `tests/` with three components:
- `*.given`: Input data file
- `*.action`: Command-line arguments
- `*.expected`: Expected output

### Benchmark Tests

Large-scale performance tests:
- `bench_ipv6_large`: Large IPv6 dataset
- `bench_large_dataset`: Large mixed IP dataset  
- `bench_multiple_patterns`: Multiple CIDR patterns
- `bench_count_large`: Count mode with large file

### Creating Custom Benchmarks

1. Create a large input file:
```bash
# Generate test data
cat > tests/custom_bench.given <<EOF
192.168.1.1
10.0.0.1
172.16.0.1
# ... more IPs
EOF
```

2. Create action file:
```bash
echo "192.168.0.0/16" > tests/custom_bench.action
```

3. Run benchmark:
```bash
lua scripts/benchmark_official.lua
```

## Performance Tips

### For rgcidr Development

1. **Always benchmark with ReleaseFast**
2. **Use official grepcidr as baseline**
3. **Test with various data sizes**
4. **Consider both IPv4 and IPv6 performance**

### For Production Use

1. **Build with ReleaseFast for deployment**
2. **Consider memory vs speed tradeoffs**
3. **Profile specific use cases**
4. **Monitor regression between releases**

## Troubleshooting

### Common Issues

**Cannot download grepcidr:**
- Check internet connection
- Try manual download from https://www.pc-tools.net/files/unix/grepcidr-2.0.tar.gz
- Verify curl is installed

**Build failures:**
- Ensure gcc/clang is installed
- Check make is available
- Verify Zig 0.15.1+ for rgcidr

**Inconsistent results:**
- Close other applications
- Run multiple iterations
- Use consistent optimization levels
- Ensure thermal throttling isn't occurring

### Manual Benchmark

For custom testing:

```bash
# Use the unified system (recommended)
lua scripts/rgcidr_test.lua --bench-compare --verbose

# Manual testing (advanced users)
zig build -Doptimize=ReleaseFast
GREPCIDR_PATH=$(lua scripts/fetch_grepcidr.lua get)
time $GREPCIDR_PATH "192.168.0.0/16" large_file.txt
time ./zig-out/bin/rgcidr "192.168.0.0/16" large_file.txt
```

## Contributing

When submitting performance improvements:

1. Run official benchmarks before and after changes
2. Include benchmark results in PR description
3. Document any algorithmic changes
4. Ensure no regression in correctness tests
5. Consider impact on both IPv4 and IPv6 performance

## References

- [Official grepcidr](https://www.pc-tools.net/unix/grepcidr/): Original implementation
- [grepcidr README](grepcidr/README): Original documentation
- [Performance Analysis](PERFORMANCE.md): Detailed optimization documentation
- [Benchmark Analysis](BENCHMARK_ANALYSIS.md): Comparative performance study
