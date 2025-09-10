#!/bin/bash

set -euo pipefail

# Configuration
RUNS_PER_TEST=5  # Fewer runs for testing
RGCIDR_BIN="./zig-out/bin/rgcidr"
GREPCIDR_BIN="./grepcidr/grepcidr"
RESULTS_FILE="benchmark_results.csv"

echo "🚀 Starting simple benchmark test..."
echo "Comparing C grepcidr vs Zig rgcidr"
echo ""

# Create CSV header
echo "test_name,category,rgcidr_mean_ms,grepcidr_mean_ms,speedup_factor,winner" > "$RESULTS_FILE"

# Test the benchmark tests specifically
declare -a test_cases=(
    "bench_ipv6_large"
    "bench_large_dataset" 
    "bench_multiple_patterns"
    "bench_count_large"
)

for test_name in "${test_cases[@]}"; do
    action_file="tests/${test_name}.action"
    given_file="tests/${test_name}.given"
    
    if [[ ! -f "$action_file" ]]; then
        echo "Warning: Action file $action_file not found, skipping"
        continue
    fi
    
    echo "Running benchmark: $test_name"
    
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
        echo "  No valid command found, skipping"
        continue
    fi
    
    # Determine input method
    if [[ -f "$given_file" ]]; then
        input_file="$given_file"
    else
        input_file=""
    fi
    
    echo "  Command: $cmd_args"
    echo "  Input: ${input_file:-'(embedded in command)'}"
    
    # Run rgcidr timing
    rgcidr_times=()
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
        fi
    done
    
    # Run grepcidr timing
    grepcidr_times=()
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
        fi
    done
    
    # Calculate averages
    if [[ ${#rgcidr_times[@]} -gt 0 && ${#grepcidr_times[@]} -gt 0 ]]; then
        rgcidr_times_str=$(printf "%s," "${rgcidr_times[@]}" | sed 's/,$//')
        grepcidr_times_str=$(printf "%s," "${grepcidr_times[@]}" | sed 's/,$//')
        rgcidr_mean=$(python3 -c "times=[$rgcidr_times_str]; print(sum(times)/len(times))")
        grepcidr_mean=$(python3 -c "times=[$grepcidr_times_str]; print(sum(times)/len(times))")
        
        speedup_factor=$(python3 -c "print($grepcidr_mean / $rgcidr_mean)")
        winner=$(python3 -c "print('rgcidr' if $grepcidr_mean > $rgcidr_mean else 'grepcidr')")
        
        # Convert to milliseconds
        rgcidr_mean_ms=$(python3 -c "print($rgcidr_mean * 1000)")
        grepcidr_mean_ms=$(python3 -c "print($grepcidr_mean * 1000)")
        
        printf "%s,benchmark,%.3f,%.3f,%.3f,%s\\n" \
            "$test_name" "$rgcidr_mean_ms" "$grepcidr_mean_ms" "$speedup_factor" "$winner" >> "$RESULTS_FILE"
        
        printf "  ✓ %s: %.2fx %s (%.1fms vs %.1fms)\\n" \
            "$test_name" "$speedup_factor" "$winner" "$rgcidr_mean_ms" "$grepcidr_mean_ms"
    else
        echo "  ⚠️  Failed to get timing data"
    fi
done

echo ""
echo "✅ Simple benchmark complete!"
echo "📊 Results written to: $RESULTS_FILE"
echo ""
echo "📋 Results summary:"
cat "$RESULTS_FILE" | column -t -s','
