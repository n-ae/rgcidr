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
    
    # Test both implementations
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
        rgcidr_times_str=$(printf "%s," "${rgcidr_times[@]}" | sed 's/,$//')\n        grepcidr_times_str=$(printf "%s," "${grepcidr_times[@]}" | sed 's/,$//')\n        \n        # Calculate statistics\n        rgcidr_stats=$(python3 -c "\ntimes=[$rgcidr_times_str]\nprint(f'{sum(times)/len(times):.6f},{min(times):.6f},{max(times):.6f}')")\n        grepcidr_stats=$(python3 -c "\ntimes=[$grepcidr_times_str]\nprint(f'{sum(times)/len(times):.6f},{min(times):.6f},{max(times):.6f}')")\n        \n        read -r rgcidr_mean rgcidr_min rgcidr_max <<< "${rgcidr_stats//,/ }"\n        read -r grepcidr_mean grepcidr_min grepcidr_max <<< "${grepcidr_stats//,/ }"\n        \n        # Calculate success rates\n        rgcidr_success_rate=$(python3 -c "print($rgcidr_success / $RUNS_PER_TEST)")\n        grepcidr_success_rate=$(python3 -c "print($grepcidr_success / $RUNS_PER_TEST)")\n        \n        # Determine winner and speedup\n        speedup_factor=$(python3 -c "print($grepcidr_mean / $rgcidr_mean)")\n        winner=$(python3 -c "print('rgcidr' if $grepcidr_mean > $rgcidr_mean else 'grepcidr')")\n        \n        # Count wins\n        if [[ "$winner" == "rgcidr" ]]; then\n            ((rgcidr_wins++))\n        else\n            ((grepcidr_wins++))\n        fi\n        ((total_tests++))\n        \n        # Convert to milliseconds for CSV\n        rgcidr_mean_ms=$(python3 -c "print($rgcidr_mean * 1000)")\n        rgcidr_min_ms=$(python3 -c "print($rgcidr_min * 1000)")\n        rgcidr_max_ms=$(python3 -c "print($rgcidr_max * 1000)")\n        grepcidr_mean_ms=$(python3 -c "print($grepcidr_mean * 1000)")\n        grepcidr_min_ms=$(python3 -c "print($grepcidr_min * 1000)")\n        grepcidr_max_ms=$(python3 -c "print($grepcidr_max * 1000)")\n        \n        # Write to CSV\n        printf "%s,%s,%.3f,%.3f,%.3f,%.2f,%.3f,%.3f,%.3f,%.2f,%.3f,%s\\n" \\\n            "$test_name" "$category" \\\n            "$rgcidr_mean_ms" "$rgcidr_min_ms" "$rgcidr_max_ms" "$rgcidr_success_rate" \\\n            "$grepcidr_mean_ms" "$grepcidr_min_ms" "$grepcidr_max_ms" "$grepcidr_success_rate" \\\n            "$speedup_factor" "$winner" >> "$RESULTS_FILE"\n        \n        # Progress output\n        printf "  ✓ %.2fx %s (%.1f vs %.1f ms)\\n" "$speedup_factor" "$winner" "$rgcidr_mean_ms" "$grepcidr_mean_ms"\n    else\n        echo "  ⚠️  Insufficient successful runs (rgcidr: $rgcidr_success, grepcidr: $grepcidr_success)"\n    fi\ndone\n\necho ""\necho "✅ Comprehensive benchmark complete!"\necho "📊 Results written to: $RESULTS_FILE"\necho ""\necho "📈 Summary:"\necho "  Total tests analyzed: $total_tests"\necho "  Benchmark tests: $benchmark_tests"\necho "  Compliance tests: $compliance_tests"\necho "  Zig rgcidr wins: $rgcidr_wins"\necho "  C grepcidr wins: $grepcidr_wins"\n\nif [[ $total_tests -gt 0 ]]; then\n    rgcidr_win_percent=$(python3 -c "print(round($rgcidr_wins / $total_tests * 100, 1))")\n    grepcidr_win_percent=$(python3 -c "print(round($grepcidr_wins / $total_tests * 100, 1))")\n    \n    echo ""\n    echo "🏆 Performance comparison:"\n    echo "  Zig rgcidr wins: $rgcidr_win_percent% of tests"\n    echo "  C grepcidr wins: $grepcidr_win_percent% of tests"\n    \n    # Calculate average speedup for each winner\n    echo ""\n    echo "📋 Detailed results (first 10 rows):"\n    head -11 "$RESULTS_FILE" | column -t -s','\nfi
