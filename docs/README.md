# Documentation Directory

This directory contains detailed documentation for rgcidr development and usage.

## Current Documentation

### Up-to-Date Documentation
- **[BENCHMARKING.md](BENCHMARKING.md)** - Comprehensive benchmarking guide using the unified test system
- **[ARCHITECTURE.md](ARCHITECTURE.md)** - High-level architecture and design decisions
- **[PERFORMANCE.md](PERFORMANCE.md)** - Performance optimizations and analysis

### Legacy Documentation
The following documents may contain outdated command references:

- **[TECHNICAL_DEEP_DIVE.md](TECHNICAL_DEEP_DIVE.md)** - Deep technical analysis
- **[OPTIMIZATION_SHOWCASE.md](OPTIMIZATION_SHOWCASE.md)** - Optimization examples
- **[BENCHMARK_ANALYSIS.md](BENCHMARK_ANALYSIS.md)** - Historical benchmark analysis
- **[COMPLIANCE_AND_PERFORMANCE.md](COMPLIANCE_AND_PERFORMANCE.md)** - RFC compliance testing

*Note: Legacy documentation may reference removed scripts. All testing functionality is now consolidated in `scripts/rgcidr_test.lua`.*

### For Current Usage

- **See [../README.md](../README.md)** for up-to-date build and test commands
- **See [../scripts/README.md](../scripts/README.md)** for detailed test system documentation
- **See [../CLAUDE.md](../CLAUDE.md)** for development guidance

## Contributing to Documentation

When updating documentation:

1. **Use unified test commands** (e.g., `zig build bench-compare` instead of `lua scripts/benchmark_official.lua`)
2. **Reference the consolidated test system** in `scripts/rgcidr_test.lua`
3. **Update this README** if adding new documentation
4. **Check examples and commands** work with current codebase

## Quick Reference

```bash
# Current recommended commands
zig build test-dev          # Development testing
zig build bench-compare     # Performance comparison
zig build test-all          # Comprehensive validation
lua scripts/rgcidr_test.lua --help  # All options
```