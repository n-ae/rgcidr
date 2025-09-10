# Scripts Directory

This directory contains various scripts for testing, benchmarking, and analyzing rgcidr performance.

## Benchmarking Scripts

### fetch_grepcidr.lua
Fetches and builds the official grepcidr 2.0 from pc-tools.net.

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

### benchmark_official.lua
Comprehensive benchmark comparing rgcidr against the official grepcidr 2.0.

```bash
# Run full benchmark suite
lua scripts/benchmark_official.lua
```

Features:
- Automatically fetches and builds official grepcidr
- Runs all test files with multiple iterations
- Generates detailed performance analysis
- Creates CSV output for further analysis
- Interactive cleanup option

### benchmark_quick.lua
Quick benchmark test with limited tests for rapid feedback.

```bash
# Run quick benchmark (4 tests, 3 iterations)
lua scripts/benchmark_quick.lua
```

Useful for:
- Quick performance checks during development
- Verifying benchmark system is working
- Getting rapid feedback on changes

### test_benchmark.lua
Verification script to ensure benchmarking system is properly configured.

```bash
# Test benchmark setup
lua scripts/test_benchmark.lua
```

Checks:
- grepcidr can be fetched and built
- rgcidr builds successfully
- Both binaries work correctly
- Basic timing measurements work

## Testing Scripts

### test.lua
Main test runner for the rgcidr test suite.

```bash
# Run all tests
lua scripts/test.lua

# Run with benchmark mode
lua scripts/test.lua --benchmark

# Run specific test
lua scripts/test.lua simple_ipv4
```

### bench_regression.lua
Regression testing script that compares performance between branches.

```bash
# Compare against main branch
lua scripts/bench_regression.lua

# Compare against specific branch
lua scripts/bench_regression.lua develop

# Generate CSV output
lua scripts/bench_regression.lua main --csv
```

## Legacy Scripts

### benchmark_comparison.sh
Bash script for comparing rgcidr and grepcidr performance.

```bash
# Run comparison benchmark
./scripts/benchmark_comparison.sh
```

**Note**: Prefer using `benchmark_official.lua` for more accurate results.

### benchmark_comprehensive.sh
Comprehensive benchmark script in bash.

```bash
# Run comprehensive benchmark
./scripts/benchmark_comprehensive.sh
```

**Note**: Prefer using `benchmark_official.lua` for more accurate results.

## Requirements

All Lua scripts require:
- Lua 5.1+ (no external dependencies)
- Zig 0.15.1+ (for building rgcidr)
- gcc/clang and make (for building grepcidr)
- curl (for downloading grepcidr)

## Performance Notes

1. **Always use ReleaseFast** optimization for benchmarking
2. **Close other applications** to reduce noise in measurements
3. **Run multiple iterations** for statistical accuracy
4. **Use official grepcidr** as the baseline for comparison

## Output Files

Benchmark scripts generate:
- `benchmark_official.csv` - Detailed benchmark results
- `benchmark_results.csv` - Simple benchmark comparison
- `benchmark_comprehensive.csv` - Full test suite results

## Troubleshooting

If scripts fail:

1. **Check Lua is installed**: `lua -v`
2. **Verify Zig version**: `zig version` (needs 0.15.1+)
3. **Ensure make is available**: `which make`
4. **Check internet connection** for grepcidr download
5. **Clean temporary files**: `lua scripts/fetch_grepcidr.lua clean`

## Contributing

When adding new scripts:
1. Use Lua for consistency (per user preference)
2. Include clear documentation in script header
3. Add error handling and helpful error messages
4. Update this README with usage instructions
