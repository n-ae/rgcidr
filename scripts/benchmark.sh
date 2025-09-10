#!/bin/bash

set -euo pipefail

# Configuration
RUNS_PER_TEST=10
RGCIDR_BIN="./zig-out/bin/rgcidr"
GREPCIDR_BIN="./grepcidr/grepcidr"
TESTS_DIR="tests"
RESULTS_FILE="benchmark_results.csv"

echo "🚀 Starting comprehensive benchmark suite..."
echo "Comparing C grepcidr vs Zig rgcidr"
echo "Running $RUNS_PER_TEST iterations per test for statistical accuracy"
echo ""

# Check if binaries exist
if [[ ! -x "$RGCIDR_BIN" ]]; then
    echo "Error: $RGCIDR_BIN not found or not executable"
    echo "Please run: zig build"
    exit 1
fi

if [[ ! -x "$GREPCIDR_BIN" ]]; then
    echo "Error: $GREPCIDR_BIN not found or not executable"
    echo "Please build grepcidr first"
    exit 1
fi

# Function to run a single benchmark
run_benchmark() {
    local implementation="$1"
    local test_name="$2"
    local cmd_args="$3"
    local input_file="$4"
    local binary
    
    if [[ "$implementation" == "rgcidr" ]]; then
        binary="$RGCIDR_BIN"
    else
        binary="$GREPCIDR_BIN"
    fi
    
    local times=()
    local success_count=0
    
    for ((run=1; run<=RUNS_PER_TEST; run++)); do
        # Build the command
        local full_cmd
        if [[ -n "$input_file" ]]; then
            full_cmd="$binary $cmd_args $input_file"
        else
            full_cmd="$binary $cmd_args"
        fi
        
        # Run with timing
        local start_time end_time duration
        start_time=$(python3 -c "import time; print(time.time())")
        
        if timeout 30s $full_cmd > /dev/null 2>&1; then
            end_time=$(python3 -c "import time; print(time.time())")
            duration=$(python3 -c "print($end_time - $start_time)")
            times+=("$duration")
            ((success_count++))
        else
            echo "    Warning: $implementation failed on run $run for $test_name"
        fi
    done
    
    if [[ $success_count -eq 0 ]]; then
        echo "0 0 0 0 0 0"
        return
    fi
    
    # Calculate statistics using Python
    local stats
    stats=$(python3 -c "
import sys
import statistics

times = [float(x) for x in sys.argv[1:]]
if not times:
    print('0 0 0 0 0 0')
else:
    mean = statistics.mean(times)
    median = statistics.median(times)
    min_val = min(times)
    max_val = max(times)
    stdev = statistics.stdev(times) if len(times) > 1 else 0
    print(f'{mean:.6f} {median:.6f} {min_val:.6f} {max_val:.6f} {stdev:.6f} {len(times)}')
" "${times[@]}")
    
    echo "$stats"
}

# Parse action file to extract command arguments and determine input method
parse_action_file() {
    local action_file="$1"
    local args=""
    local has_input_file=false
    
    while IFS= read -r line; do
        # Skip empty lines
        [[ -z "$line" ]] && continue
        
        # Extract pattern from "number|pattern" format or use line as-is
        if [[ "$line" =~ ^[0-9]+\|(.+)$ ]]; then
            local pattern="${BASH_REMATCH[1]}"
            if [[ -n "$pattern" ]]; then
                args="$args $pattern"
                # Check if the pattern contains a file path
                if [[ "$pattern" =~ tests/.+\.given ]]; then
                    has_input_file=true
                fi
            fi
        elif [[ ! "$line" =~ ^[0-9]+\|$ ]]; then
            args="$args $line"
        fi
    done < "$action_file"
    
    echo "$args|$has_input_file"
}

# Create CSV header
echo "test_name,category,rgcidr_mean_ms,rgcidr_median_ms,rgcidr_min_ms,rgcidr_max_ms,rgcidr_std_dev_ms,rgcidr_runs,grepcidr_mean_ms,grepcidr_median_ms,grepcidr_min_ms,grepcidr_max_ms,grepcidr_std_dev_ms,grepcidr_runs,speedup_factor,winner" > "$RESULTS_FILE"

# Find and process all test files
rgcidr_wins=0
grepcidr_wins=0
benchmark_tests=0
compliance_tests=0
total_tests=0

for action_file in $(find "$TESTS_DIR" -name "*.action" | sort); do
    test_name=$(basename "$action_file" .action)
    given_file="${action_file%.action}.given"
    
    # Parse action file to get command args and input method
    parse_result=$(parse_action_file "$action_file")
    cmd_args="${parse_result%|*}"
    has_input_file="${parse_result#*|}"
    
    if [[ -z "$cmd_args" ]]; then
        echo "Warning: No valid commands found in $action_file, skipping"
        continue
    fi
    
    # Determine input method
    if [[ "$has_input_file" == "true" ]]; then
        input_method="embedded"  # Input file is in the command args
        input_file=""  # No separate input file needed
    else
        input_method="separate"  # Need separate .given file
        input_file="$given_file"
        # Skip if input file doesn't exist for separate input method
        if [[ ! -f "$given_file" ]]; then
            echo "Warning: Input file $given_file not found, skipping $test_name"
            continue
        fi
    fi
    
    # Determine category
    if [[ "$test_name" =~ ^bench_ ]]; then
        category="benchmark"
        ((benchmark_tests++))
    else
        category="compliance"
        ((compliance_tests++))
    fi
    
    echo "Running benchmark: $test_name"
    
    # Run benchmarks for both implementations
    echo -n "  Running rgcidr..."
    rgcidr_stats=$(run_benchmark "rgcidr" "$test_name" "$cmd_args" "$input_file")
    echo " done"
    
    echo -n "  Running grepcidr..."
    grepcidr_stats=$(run_benchmark "grepcidr" "$test_name" "$cmd_args" "$input_file")
    echo " done"
    
    # Parse statistics
    read -r rgcidr_mean rgcidr_median rgcidr_min rgcidr_max rgcidr_stdev rgcidr_runs <<< "$rgcidr_stats"
    read -r grepcidr_mean grepcidr_median grepcidr_min grepcidr_max grepcidr_stdev grepcidr_runs <<< "$grepcidr_stats"
    
    # Skip if either implementation failed completely
    if [[ "$rgcidr_runs" -eq 0 ]] || [[ "$grepcidr_runs" -eq 0 ]]; then
        echo "  ⚠️  Insufficient successful runs, skipping"
        continue
    fi
    
    # Calculate speedup factor and winner
    speedup_factor=$(python3 -c "print($grepcidr_mean / $rgcidr_mean)")
    winner=$(python3 -c "print('rgcidr' if $grepcidr_mean > $rgcidr_mean else 'grepcidr')")
    
    # Count wins
    if [[ "$winner" == "rgcidr" ]]; then
        ((rgcidr_wins++))
    else
        ((grepcidr_wins++))
    fi
    ((total_tests++))
    
    # Convert to milliseconds for readability
    rgcidr_mean_ms=$(python3 -c "print($rgcidr_mean * 1000)")
    rgcidr_median_ms=$(python3 -c "print($rgcidr_median * 1000)")
    rgcidr_min_ms=$(python3 -c "print($rgcidr_min * 1000)")
    rgcidr_max_ms=$(python3 -c "print($rgcidr_max * 1000)")
    rgcidr_stdev_ms=$(python3 -c "print($rgcidr_stdev * 1000)")
    
    grepcidr_mean_ms=$(python3 -c "print($grepcidr_mean * 1000)")
    grepcidr_median_ms=$(python3 -c "print($grepcidr_median * 1000)")
    grepcidr_min_ms=$(python3 -c "print($grepcidr_min * 1000)")
    grepcidr_max_ms=$(python3 -c "print($grepcidr_max * 1000)")
    grepcidr_stdev_ms=$(python3 -c "print($grepcidr_stdev * 1000)")
    
    # Write to CSV
    printf "%s,%s,%.3f,%.3f,%.3f,%.3f,%.3f,%d,%.3f,%.3f,%.3f,%.3f,%.3f,%d,%.3f,%s\n" \
        "$test_name" "$category" \
        "$rgcidr_mean_ms" "$rgcidr_median_ms" "$rgcidr_min_ms" "$rgcidr_max_ms" "$rgcidr_stdev_ms" "$rgcidr_runs" \
        "$grepcidr_mean_ms" "$grepcidr_median_ms" "$grepcidr_min_ms" "$grepcidr_max_ms" "$grepcidr_stdev_ms" "$grepcidr_runs" \
        "$speedup_factor" "$winner" >> "$RESULTS_FILE"
    
    printf "  ✓ %s: %.2fx %s\n" "$test_name" "$speedup_factor" "$winner"
done

echo ""
echo "✅ Benchmark complete!"
echo "📊 Results written to: $RESULTS_FILE"
echo ""
echo "📈 Summary:"
echo "  Total tests: $total_tests"
echo "  Benchmark tests: $benchmark_tests"
echo "  Compliance tests: $compliance_tests"
echo "  Zig rgcidr wins: $rgcidr_wins"
echo "  C grepcidr wins: $grepcidr_wins"

# Calculate overall performance summary
if [[ $total_tests -gt 0 ]]; then
    rgcidr_win_percent=$(python3 -c "print(round($rgcidr_wins / $total_tests * 100, 1))")
    grepcidr_win_percent=$(python3 -c "print(round($grepcidr_wins / $total_tests * 100, 1))")
    
    echo ""
    echo "🏆 Win rates:"
    echo "  Zig rgcidr: $rgcidr_win_percent%"
    echo "  C grepcidr: $grepcidr_win_percent%"
fi
