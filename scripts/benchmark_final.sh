#!/bin/bash

set -euo pipefail

# Configuration
RUNS_PER_TEST=5
RGCIDR_BIN="./zig-out/bin/rgcidr"
GREPCIDR_BIN="./grepcidr/grepcidr"
RESULTS_FILE="benchmark_comprehensive.csv"

echo "🚀 Starting comprehensive benchmark suite..."
echo "Comparing C grepcidr vs Zig rgcidr"
echo "Running $RUNS_PER_TEST iterations per test for statistical accuracy"
echo ""

# Create CSV header
echo "test_name,category,rgcidr_mean_ms,rgcidr_min_ms,rgcidr_max_ms,rgcidr_success_rate,grepcidr_mean_ms,grepcidr_min_ms,grepcidr_max_ms,grepcidr_success_rate,speedup_factor,winner" > "$RESULTS_FILE"

# Counters for summary
total_tests=0
rgcidr_wins=0
grepcidr_wins=0
benchmark_tests=0
compliance_tests=0

# Process all test files
for action_file in $(find tests -name "*.action" | sort); do
    test_name=$(basename "$action_file" .action)
    given_file="${action_file%.action}.given"
    
    # Determine category
    if [[ "$test_name" =~ ^bench_ ]]; then
        category="benchmark"
        ((benchmark_tests++))
    else
        category="compliance"
        ((compliance_tests++))
    fi
    
    echo "Running: $test_name [$category]"
    
    # Parse action file to get first valid command
    cmd_args=""
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        if [[ "$line" =~ ^[0-9]+\\|(.+)$ ]]; then
            pattern="${BASH_REMATCH[1]}"
            if [[ -n "$pattern" && "$pattern" != "" ]]; then
                cmd_args="$pattern"
                break
            fi
        fi
    done < "$action_file"
    
    if [[ -z "$cmd_args" ]]; then
        echo "  ⚠️  No valid command found, skipping"
        continue
    fi
    
    # Determine input file
    if [[ -f "$given_file" ]]; then
        input_file="$given_file"
    else
        input_file=""
    fi
    
    # Test rgcidr
    rgcidr_times=()
    rgcidr_success=0
    
    for ((run=1; run<=RUNS_PER_TEST; run++)); do
        if [[ -n "$input_file" ]]; then
            full_cmd="$RGCIDR_BIN $cmd_args $input_file"
        else
            full_cmd="$RGCIDR_BIN $cmd_args"
        fi
        
        start_time=$(python3 -c "import time; print(time.time())")
        if $full_cmd > /dev/null 2>&1; then
            end_time=$(python3 -c "import time; print(time.time())")
            duration=$(python3 -c "print($end_time - $start_time)")
            rgcidr_times+=("$duration")
            ((rgcidr_success++))
        fi
    done
    
    # Test grepcidr
    grepcidr_times=()
    grepcidr_success=0
    
    for ((run=1; run<=RUNS_PER_TEST; run++)); do
        if [[ -n "$input_file" ]]; then
            full_cmd="$GREPCIDR_BIN $cmd_args $input_file"
        else
            full_cmd="$GREPCIDR_BIN $cmd_args"
        fi
        
        start_time=$(python3 -c "import time; print(time.time())")
        if $full_cmd > /dev/null 2>&1; then
            end_time=$(python3 -c "import time; print(time.time())")
            duration=$(python3 -c "print($end_time - $start_time)")
            grepcidr_times+=("$duration")
            ((grepcidr_success++))
        fi
    done
    
    # Calculate statistics if we have successful runs
    if [[ $rgcidr_success -gt 0 && $grepcidr_success -gt 0 ]]; then
        # Format timing arrays for Python
        rgcidr_times_str=$(printf "%s," "${rgcidr_times[@]}" | sed 's/,$//')
        grepcidr_times_str=$(printf "%s," "${grepcidr_times[@]}" | sed 's/,$//')
        
        # Calculate statistics
        rgcidr_stats=$(python3 -c "times=[$rgcidr_times_str]; print(f'{sum(times)/len(times):.6f},{min(times):.6f},{max(times):.6f}')")
        grepcidr_stats=$(python3 -c "times=[$grepcidr_times_str]; print(f'{sum(times)/len(times):.6f},{min(times):.6f},{max(times):.6f}')")
        
        read -r rgcidr_mean rgcidr_min rgcidr_max <<< "${rgcidr_stats//,/ }"
        read -r grepcidr_mean grepcidr_min grepcidr_max <<< "${grepcidr_stats//,/ }"
        
        # Calculate success rates
        rgcidr_success_rate=$(python3 -c "print($rgcidr_success / $RUNS_PER_TEST)")
        grepcidr_success_rate=$(python3 -c "print($grepcidr_success / $RUNS_PER_TEST)")
        
        # Determine winner and speedup
        speedup_factor=$(python3 -c "print($grepcidr_mean / $rgcidr_mean)")
        winner=$(python3 -c "print('rgcidr' if $grepcidr_mean > $rgcidr_mean else 'grepcidr')")
        
        # Count wins
        if [[ "$winner" == "rgcidr" ]]; then
            ((rgcidr_wins++))
        else
            ((grepcidr_wins++))
        fi
        ((total_tests++))
        
        # Convert to milliseconds for CSV
        rgcidr_mean_ms=$(python3 -c "print($rgcidr_mean * 1000)")
        rgcidr_min_ms=$(python3 -c "print($rgcidr_min * 1000)")
        rgcidr_max_ms=$(python3 -c "print($rgcidr_max * 1000)")
        grepcidr_mean_ms=$(python3 -c "print($grepcidr_mean * 1000)")
        grepcidr_min_ms=$(python3 -c "print($grepcidr_min * 1000)")
        grepcidr_max_ms=$(python3 -c "print($grepcidr_max * 1000)")
        
        # Write to CSV
        printf "%s,%s,%.3f,%.3f,%.3f,%.2f,%.3f,%.3f,%.3f,%.2f,%.3f,%s\n" \
            "$test_name" "$category" \
            "$rgcidr_mean_ms" "$rgcidr_min_ms" "$rgcidr_max_ms" "$rgcidr_success_rate" \
            "$grepcidr_mean_ms" "$grepcidr_min_ms" "$grepcidr_max_ms" "$grepcidr_success_rate" \
            "$speedup_factor" "$winner" >> "$RESULTS_FILE"
        
        # Progress output
        printf "  ✓ %.2fx %s (%.1f vs %.1f ms)\n" "$speedup_factor" "$winner" "$rgcidr_mean_ms" "$grepcidr_mean_ms"
    else
        echo "  ⚠️  Insufficient successful runs (rgcidr: $rgcidr_success, grepcidr: $grepcidr_success)"
    fi
done

echo ""
echo "✅ Comprehensive benchmark complete!"
echo "📊 Results written to: $RESULTS_FILE"
echo ""
echo "📈 Summary:"
echo "  Total tests analyzed: $total_tests"
echo "  Benchmark tests: $benchmark_tests"
echo "  Compliance tests: $compliance_tests"
echo "  Zig rgcidr wins: $rgcidr_wins"
echo "  C grepcidr wins: $grepcidr_wins"

if [[ $total_tests -gt 0 ]]; then
    rgcidr_win_percent=$(python3 -c "print(round($rgcidr_wins / $total_tests * 100, 1))")
    grepcidr_win_percent=$(python3 -c "print(round($grepcidr_wins / $total_tests * 100, 1))")
    
    echo ""
    echo "🏆 Performance comparison:"
    echo "  Zig rgcidr wins: $rgcidr_win_percent% of tests"
    echo "  C grepcidr wins: $grepcidr_win_percent% of tests"
    
    echo ""
    echo "📋 Detailed results (first 10 rows):"
    head -11 "$RESULTS_FILE" | column -t -s','
fi
