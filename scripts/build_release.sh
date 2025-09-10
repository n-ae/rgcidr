#!/bin/bash

# Production release build script for rgcidr
# Builds optimized versions with different optimization levels

set -e

echo "=== Building rgcidr Production Release ==="
echo ""

# Clean previous builds
echo "🧹 Cleaning previous builds..."
rm -rf zig-out/
rm -rf .zig-cache/

# Create release directory
mkdir -p release/

# Build with different optimization levels
echo ""
echo "⚡ Building optimized versions..."

# ReleaseFast - Maximum performance
echo "  Building ReleaseFast (maximum performance)..."
zig build -Doptimize=ReleaseFast
cp zig-out/bin/rgcidr release/rgcidr-fast
rm -rf zig-out/

# ReleaseSafe - Balanced performance with safety checks  
echo "  Building ReleaseSafe (balanced performance + safety)..."
zig build -Doptimize=ReleaseSafe
cp zig-out/bin/rgcidr release/rgcidr-safe
rm -rf zig-out/

# ReleaseSmall - Optimized for size
echo "  Building ReleaseSmall (size optimized)..."
zig build -Doptimize=ReleaseSmall
cp zig-out/bin/rgcidr release/rgcidr-small
rm -rf zig-out/

# Cross-compile for common platforms
echo ""
echo "🌍 Cross-compiling for different platforms..."

# Linux x86_64
echo "  Cross-compiling for Linux x86_64..."
zig build -Dtarget=x86_64-linux -Doptimize=ReleaseFast
cp zig-out/bin/rgcidr release/rgcidr-linux-x86_64
rm -rf zig-out/

# Linux aarch64
echo "  Cross-compiling for Linux aarch64..."
zig build -Dtarget=aarch64-linux -Doptimize=ReleaseFast
cp zig-out/bin/rgcidr release/rgcidr-linux-aarch64
rm -rf zig-out/

# Windows x86_64
echo "  Cross-compiling for Windows x86_64..."
zig build -Dtarget=x86_64-windows -Doptimize=ReleaseFast
cp zig-out/bin/rgcidr.exe release/rgcidr-windows-x86_64.exe
rm -rf zig-out/

# Build default version for current platform
echo ""
echo "🔧 Building default version..."
zig build -Doptimize=ReleaseFast

# Run comprehensive tests
echo ""
echo "🧪 Running comprehensive test suite..."
lua scripts/test.lua

# Performance benchmarks
echo ""
echo "📊 Running performance benchmarks..."
zig build bench > release/benchmark-early-termination.txt 2>&1 || true
zig build bench-advanced > release/benchmark-advanced.txt 2>&1 || true
zig build asm-analysis > release/analysis-assembly.txt 2>&1 || true

# Generate file sizes and information
echo ""
echo "📋 Generating release information..."

cat > release/README.txt << EOF
rgcidr - High-Performance IP CIDR Filtering in Zig
==================================================

This release contains optimized builds of rgcidr for different use cases:

Optimization Levels:
- rgcidr-fast:  Maximum performance (ReleaseFast)
- rgcidr-safe:  Balanced performance with safety checks (ReleaseSafe)  
- rgcidr-small: Size optimized (ReleaseSmall)

Cross-Platform Builds:
- rgcidr-linux-x86_64:    Linux on Intel/AMD 64-bit
- rgcidr-linux-aarch64:   Linux on ARM 64-bit
- rgcidr-windows-x86_64:  Windows on Intel/AMD 64-bit
- rgcidr (main):          Native build for this platform

Performance Benchmarks:
- benchmark-early-termination.txt: Early termination optimization results
- benchmark-advanced.txt:         Advanced optimization results  
- analysis-assembly.txt:          Hot path and cache performance analysis

Usage:
  rgcidr PATTERN [FILE...]
  rgcidr [-V] [-cisvx] [-f PATTERNFILE] [PATTERN] [FILE...]

Examples:
  echo "192.168.1.1 test" | ./rgcidr 192.168.0.0/16
  ./rgcidr -c 10.0.0.0/8 access.log
  ./rgcidr -v 192.168.0.0/16,10.0.0.0/8 server.log

For detailed documentation, see the project repository.
EOF

# Display file sizes
echo ""
echo "📊 Build Results:"
echo ""
ls -la release/ | while read -r line; do
    if [[ $line == *"rgcidr"* ]]; then
        echo "  $line"
    fi
done

# Display performance summary
echo ""
echo "🚀 Performance Summary:"
if [[ -f release/benchmark-advanced.txt ]]; then
    echo "  Single Pattern Fast Path: $(grep -o '[0-9.]*x' release/benchmark-advanced.txt | head -1) speedup"
    echo "  Early Termination:        $(grep -o '[0-9.]*x' release/benchmark-advanced.txt | tail -1) speedup"
fi

if [[ -f release/analysis-assembly.txt ]]; then
    echo "  Hot Path Performance:     $(grep 'Time per match:' release/analysis-assembly.txt | head -1 | grep -o '[0-9.]*ns')"
    echo "  Instructions per second:  $(grep 'Instructions per second:' release/analysis-assembly.txt | head -1 | grep -o '[0-9]*M')"
fi

echo ""
echo "✅ Release build complete! Files available in release/ directory"
echo ""
echo "🎯 Recommended build for production: rgcidr-fast"
echo "   (Maximum performance optimizations enabled)"
