#!/usr/bin/env lua

-- Optimized test script for rgcidr - builds both implementations with maximum optimization first
-- This ensures fair performance comparisons between rgcidr and grepcidr
--
-- Usage:
--   lua test_optimized.lua               - Run tests with standard output
--   lua test_optimized.lua --csv         - Output results in CSV format
--   lua test_optimized.lua -c            - Output results in CSV format (short form)
--   lua test_optimized.lua --benchmark   - Run only benchmark tests with separate UAT timing
--   lua test_optimized.lua --help        - Show this help message

local function run_command(cmd)
	local handle = io.popen(cmd .. " 2>&1")
	local result = handle:read("*a")
	local success, exit_type, exit_code = handle:close()
	return result, exit_code or 0
end

local function run_command_no_output(cmd)
	local handle = io.popen(cmd .. " > /dev/null 2>&1")
	local result = handle:read("*a")
	local success, exit_type, exit_code = handle:close()
	return "", exit_code or 0
end

local function file_exists(name)
	local f = io.open(name, "r")
	if f ~= nil then
		io.close(f)
		return true
	else
		return false
	end
end

local function read_file(filename)
	local file = io.open(filename, "r")
	if not file then
		error("Could not open file: " .. filename)
	end
	local content = file:read("*all")
	file:close()
	return content
end

-- Build both implementations with maximum optimization
local function build_optimized()
	print("=== Building implementations with maximum optimization ===")
	print("")

	-- Build rgcidr with ReleaseFast (maximum performance)
	print("Building rgcidr with ReleaseFast...")
	local rgcidr_output, rgcidr_code = run_command("zig build -Doptimize=ReleaseFast")
	if rgcidr_code ~= 0 then
		print("Failed to build rgcidr:")
		print(rgcidr_output)
		return false
	end
	print("✓ rgcidr built successfully with ReleaseFast optimization")

	-- Build grepcidr with maximum optimization
	print("Building grepcidr with -O3...")
	local grepcidr_build_cmd =
		"cd grepcidr && cc -O3 -march=native -flto -fomit-frame-pointer -funroll-loops -o grepcidr grepcidr.c && cd .."
	local grepcidr_output, grepcidr_code = run_command(grepcidr_build_cmd)
	if grepcidr_code ~= 0 then
		print("Failed to build grepcidr:")
		print(grepcidr_output)
		-- Try fallback build without advanced optimizations
		print("Trying fallback build without advanced optimizations...")
		grepcidr_build_cmd = "cd grepcidr && cc -O3 -o grepcidr grepcidr.c && cd .."
		grepcidr_output, grepcidr_code = run_command(grepcidr_build_cmd)
		if grepcidr_code ~= 0 then
			print("Failed to build grepcidr with fallback:")
			print(grepcidr_output)
			return false
		end
		print("✓ grepcidr built successfully with -O3 optimization (fallback)")
	else
		print("✓ grepcidr built successfully with -O3 -march=native -flto optimization")
	end

	print("")
	print("=== Both implementations built with maximum optimization ===")
	print("")
	return true
end

-- Test configuration
local test_dir = "tests"
local passed = 0
local failed = 0
local csv_mode = false
local benchmark_mode = false
local csv_results = {}
local benchmark_tests = 0
local compliance_tests = 0

-- Check command line arguments
if arg and #arg > 0 then
	for i = 1, #arg do
		if arg[i] == "--csv" or arg[i] == "-c" then
			csv_mode = true
		elseif arg[i] == "--benchmark" then
			benchmark_mode = true
		elseif arg[i] == "--help" or arg[i] == "-h" then
			print("rgcidr Optimized Test Suite")
			print("")
			print("This script builds both implementations with maximum optimization before testing.")
			print("")
			print("Usage:")
			print("  lua test_optimized.lua               - Run tests with standard output")
			print("  lua test_optimized.lua --csv         - Output results in CSV format")
			print("  lua test_optimized.lua -c            - Output results in CSV format (short form)")
			print("  lua test_optimized.lua --benchmark   - Run only benchmark tests with separate UAT timing")
			print("  lua test_optimized.lua --help        - Show this help message")
			print("")
			print("Build Optimizations:")
			print("  rgcidr:    Built with 'zig build -Doptimize=ReleaseFast'")
			print("  grepcidr:  Built with 'cc -O3 -march=native -flto -fomit-frame-pointer -funroll-loops'")
			print("")
			print("CSV Output Format:")
			print("  uat,test scenario,result")
			print("  rgcidr,grepcidr,test_name,pass/fail")
			print("")
			print("Examples:")
			print("  lua test_optimized.lua --csv > test_results.csv")
			print("  lua test_optimized.lua --benchmark --csv > benchmark_results.csv")
			os.exit(0)
		end
	end
end

-- Build both implementations with optimization before running tests
if not build_optimized() then
	print("ERROR: Failed to build implementations with optimization")
	os.exit(1)
end

-- Determine if a test is a benchmark test
local function is_benchmark_test(test_name)
	return test_name:match("^bench_") ~= nil
end

-- Define tests based on files in the test directory
local function get_test_cases()
	local tests = {}
	local handle = io.popen("ls " .. test_dir .. "/*.action 2>/dev/null")
	local result = handle:read("*a")
	handle:close()

	for file in result:gmatch("[^\n]+") do
		local test_name = file:match("([^/]+)%.action$")
		if test_name then
			tests[#tests + 1] = test_name
		end
	end

	return tests
end

-- Run a single UAT for benchmark testing with multiple iterations
local function run_uat_benchmark(test_name, uat_name, executable_path, iterations)
	iterations = iterations or 5 -- default to 5 iterations
	local max_attempts = 3 -- retry if variance is too high
	local target_variance = 3.0 -- target CV% for very high statistical significance
	-- Read action file to get command arguments
	local action_file = test_dir .. "/" .. test_name .. ".action"
	local args = read_file(action_file):gsub("\n", "")

	-- Determine expected exit code
	local expected_exit_code = 0
	if test_name == "no_match" or test_name == "empty_file" or test_name == "mvp_no_match" then
		expected_exit_code = 1
	elseif test_name == "strict_misaligned" then
		expected_exit_code = 2
	end

	-- Build command once
	local cmd_with_output
	if args:match("%.given") then
		cmd_with_output = executable_path .. " " .. args
	else
		local given_file = test_dir .. "/" .. test_name .. ".given"
		if file_exists(given_file) then
			cmd_with_output = executable_path .. " " .. args .. " " .. given_file
		else
			cmd_with_output = executable_path .. " " .. args
		end
	end

	local scan_cv, full_cv
	local best_result = nil
	local output, exit_code -- declare at function scope

	for attempt = 1, max_attempts do
		-- Extended warmup runs to reduce cold start variance and stabilize CPU
		for warmup = 1, 25 do
			local _, _ = run_command_no_output(cmd_with_output)
		end

		-- Longer settling time to let CPU frequencies stabilize
		os.execute("sleep 0.2")

		-- Collect multiple timing samples
		local scan_times = {}
		local full_times = {}

		for i = 1, iterations do
			-- Time with output (first iteration only to get output)
			local start_time_full = os.clock()
			if i == 1 then
				output, exit_code = run_command(cmd_with_output)
			else
				_, _ = run_command(cmd_with_output)
			end
			local full_time = (os.clock() - start_time_full) * 1000000
			table.insert(full_times, full_time)

			-- Time without output (pure scanning)
			local start_time_scan = os.clock()
			local _, exit_code_no_output = run_command_no_output(cmd_with_output)
			local scan_time = (os.clock() - start_time_scan) * 1000000
			table.insert(scan_times, scan_time)
		end

		-- Calculate statistics with outlier removal and trimmed mean for better stability
		local function calculate_stats(times)
			table.sort(times)
			local n = #times

			-- Remove top and bottom 20% of samples (very aggressive outlier trimming)
			local trim_count = math.floor(n * 0.20)
			local trimmed_times = {}
			for i = trim_count + 1, n - trim_count do
				table.insert(trimmed_times, times[i])
			end

			-- Calculate trimmed statistics
			local sum = 0
			for _, t in ipairs(trimmed_times) do
				sum = sum + t
			end
			local trimmed_mean = sum / #trimmed_times
			local median = times[math.ceil(n / 2)]
			local min_val = times[1]
			local max_val = times[n]

			-- Calculate standard deviation on trimmed data
			local variance_sum = 0
			for _, t in ipairs(trimmed_times) do
				variance_sum = variance_sum + (t - trimmed_mean) ^ 2
			end
			local std_dev = math.sqrt(variance_sum / #trimmed_times)
			local cv = (std_dev / trimmed_mean) * 100 -- coefficient of variation as percentage

			return trimmed_mean, median, min_val, max_val, std_dev, cv
		end

		local scan_mean, scan_median, scan_min, scan_max, scan_std, current_scan_cv = calculate_stats(scan_times)
		local full_mean, full_median, full_min, full_max, full_std, current_full_cv = calculate_stats(full_times)

		-- Check if variance is acceptable
		if current_scan_cv <= target_variance and current_full_cv <= target_variance then
			-- Good variance, use this result
			scan_cv = current_scan_cv
			full_cv = current_full_cv
			best_result = {
				scan_mean = scan_mean,
				full_mean = full_mean,
				scan_cv = scan_cv,
				full_cv = full_cv,
			}
			break
		elseif attempt == max_attempts or (best_result == nil) then
			-- Last attempt or first attempt, use this result anyway
			scan_cv = current_scan_cv
			full_cv = current_full_cv
			best_result = {
				scan_mean = scan_mean,
				full_mean = full_mean,
				scan_cv = scan_cv,
				full_cv = full_cv,
			}
		end

		-- If variance too high, wait longer before retrying for system to stabilize
		if attempt < max_attempts then
			os.execute("sleep 1.0")
		end
	end

	-- Use results from best attempt
	local execution_time = best_result.scan_mean / 1000000
	local execution_time_microseconds = best_result.scan_mean
	local execution_time_with_output = best_result.full_mean / 1000000
	local execution_time_with_output_microseconds = best_result.full_mean
	scan_cv = best_result.scan_cv
	full_cv = best_result.full_cv

	-- Read expected output
	local expected_file = test_dir .. "/" .. test_name .. ".expected"
	local expected = read_file(expected_file)

	-- Normalize output by trimming whitespace
	local normalized_output = output:gsub("%s+$", "")
	local normalized_expected = expected:gsub("%s+$", "")

	-- Check results
	local test_passed = (normalized_output == normalized_expected and exit_code == expected_exit_code)
	local result_status = test_passed and "pass" or "fail"

	return {
		uat = uat_name,
		test_scenario = test_name,
		category = "benchmark",
		result = result_status,
		execution_time = execution_time,
		execution_time_microseconds = execution_time_microseconds,
		execution_time_with_output = execution_time_with_output,
		execution_time_with_output_microseconds = execution_time_with_output_microseconds,
		scan_cv = scan_cv,
		full_cv = full_cv,
		test_passed = test_passed,
		expected_exit_code = expected_exit_code,
		actual_exit_code = exit_code,
		expected_output = normalized_expected,
		actual_output = normalized_output,
	}
end

-- Run a single test case
local function run_test(test_name)
	local is_benchmark = is_benchmark_test(test_name)
	local category = is_benchmark and "benchmark" or "compliance"

	-- Skip non-benchmark tests in benchmark mode
	if benchmark_mode and not is_benchmark then
		return
	end

	if is_benchmark then
		benchmark_tests = benchmark_tests + 1
	else
		compliance_tests = compliance_tests + 1
	end

	if not csv_mode then
		print("Running: " .. test_name .. " [" .. category .. "]")
	end

	-- Handle benchmark tests separately
	if benchmark_mode and is_benchmark then
		-- Run each UAT separately for benchmarks (100 iterations for very low variance)
		local rgcidr_result = run_uat_benchmark(test_name, "rgcidr", "./zig-out/bin/rgcidr", 100)
		local grepcidr_result = run_uat_benchmark(test_name, "grepcidr", "./grepcidr/grepcidr", 100)

		-- Store results for both UATs
		table.insert(csv_results, rgcidr_result)
		table.insert(csv_results, grepcidr_result)

		-- Check if both passed (for summary counting)
		local both_passed = rgcidr_result.test_passed and grepcidr_result.test_passed

		if both_passed then
			if not csv_mode then
				local rgcidr_scan = string.format("%.0fμs", rgcidr_result.execution_time_microseconds)
				local grepcidr_scan = string.format("%.0fμs", grepcidr_result.execution_time_microseconds)
				local rgcidr_full = string.format("%.0fμs", rgcidr_result.execution_time_with_output_microseconds)
				local grepcidr_full = string.format("%.0fμs", grepcidr_result.execution_time_with_output_microseconds)

				local scan_ratio = rgcidr_result.execution_time_microseconds
					/ grepcidr_result.execution_time_microseconds
				local full_ratio = rgcidr_result.execution_time_with_output_microseconds
					/ grepcidr_result.execution_time_with_output_microseconds

				local pass_symbol = "✓"
				local warning = ""

				-- Check for statistical significance
				local max_cv = math.max(
					rgcidr_result.scan_cv,
					grepcidr_result.scan_cv,
					rgcidr_result.full_cv,
					grepcidr_result.full_cv
				)
				if max_cv > 5.0 then
					pass_symbol = "⚠"
					warning = string.format(" (HIGH VARIANCE: %.1f%%)", max_cv)
				end

				print(pass_symbol .. " " .. test_name .. " PASSED" .. warning)
				print(
					string.format(
						"  Scanning only: rgcidr: %s (%.1f%% var), grepcidr: %s (%.1f%% var) [%.2fx]",
						rgcidr_scan,
						rgcidr_result.scan_cv,
						grepcidr_scan,
						grepcidr_result.scan_cv,
						scan_ratio
					)
				)
				print(
					string.format(
						"  With output:   rgcidr: %s (%.1f%% var), grepcidr: %s (%.1f%% var) [%.2fx]",
						rgcidr_full,
						rgcidr_result.full_cv,
						grepcidr_full,
						grepcidr_result.full_cv,
						full_ratio
					)
				)
			end
			passed = passed + 1
		else
			if not csv_mode then
				print("✗ " .. test_name .. " FAILED")
				if not rgcidr_result.test_passed then
					print(
						"  rgcidr - Expected exit code: "
							.. rgcidr_result.expected_exit_code
							.. ", got: "
							.. rgcidr_result.actual_exit_code
					)
				end
				if not grepcidr_result.test_passed then
					print(
						"  grepcidr - Expected exit code: "
							.. grepcidr_result.expected_exit_code
							.. ", got: "
							.. grepcidr_result.actual_exit_code
					)
				end
			end
			failed = failed + 1
		end
		return
	end

	-- Regular compliance test execution (only rgcidr)
	local action_file = test_dir .. "/" .. test_name .. ".action"
	local args = read_file(action_file):gsub("\n", "")

	-- Determine expected exit code
	local expected_exit_code = 0
	if test_name == "no_match" or test_name == "empty_file" or test_name == "mvp_no_match" then
		expected_exit_code = 1
	elseif test_name == "strict_misaligned" then
		expected_exit_code = 2
	end

	-- Build command
	local cmd
	if args:match("%.given") then
		cmd = "./zig-out/bin/rgcidr " .. args
	else
		local given_file = test_dir .. "/" .. test_name .. ".given"
		if file_exists(given_file) then
			cmd = "./zig-out/bin/rgcidr " .. args .. " " .. given_file
		else
			cmd = "./zig-out/bin/rgcidr " .. args
		end
	end

	-- Run test with timing
	local start_time = os.clock()
	local output, exit_code = run_command(cmd)
	local execution_time = os.clock() - start_time

	-- Read expected output
	local expected_file = test_dir .. "/" .. test_name .. ".expected"
	local expected = read_file(expected_file)

	-- Normalize output by trimming whitespace
	local normalized_output = output:gsub("%s+$", "")
	local normalized_expected = expected:gsub("%s+$", "")

	-- Check results
	local test_passed = (normalized_output == normalized_expected and exit_code == expected_exit_code)

	if test_passed then
		if not csv_mode then
			if category == "benchmark" then
				print(string.format("✓ %s PASSED [%.3fs]", test_name, execution_time))
			else
				print("✓ " .. test_name .. " PASSED")
			end
		end
		passed = passed + 1
		table.insert(csv_results, {
			uat = "rgcidr",
			test_scenario = test_name,
			category = category,
			result = "pass",
			execution_time = execution_time,
		})
	else
		if not csv_mode then
			print("✗ " .. test_name .. " FAILED")
			if normalized_output ~= normalized_expected then
				print("  Output mismatch:")
				print("  Expected (length " .. #normalized_expected .. "):")
				if #normalized_expected > 100 then
					print("  " .. normalized_expected:sub(1, 100) .. "... (truncated)")
				else
					print("  " .. normalized_expected)
				end
				print("  Actual (length " .. #normalized_output .. "):")
				if #normalized_output > 100 then
					print("  " .. normalized_output:sub(1, 100) .. "... (truncated)")
				else
					print("  " .. normalized_output)
				end
			end
			if exit_code ~= expected_exit_code then
				print("  Expected exit code: " .. expected_exit_code .. ", got: " .. exit_code)
			end
		end
		failed = failed + 1
		table.insert(csv_results, {
			uat = "rgcidr",
			test_scenario = test_name,
			category = category,
			result = "fail",
			execution_time = execution_time,
		})
	end
end

-- Get all test cases
local tests = get_test_cases()

-- Sort tests to group benchmark tests together
table.sort(tests, function(a, b)
	local a_is_bench = is_benchmark_test(a)
	local b_is_bench = is_benchmark_test(b)
	if a_is_bench ~= b_is_bench then
		return b_is_bench -- non-benchmark tests first
	end
	return a < b
end)

-- Run all tests
for _, test in ipairs(tests) do
	run_test(test)
end

-- Output results
if csv_mode then
	-- Print CSV header
	if benchmark_mode then
		print("uat,test_scenario,result,scan_time_us,full_time_us,scan_cv,full_cv")
	else
		print("uat,test_scenario,result,execution_time")
	end

	-- Print CSV data
	for _, result in ipairs(csv_results) do
		if benchmark_mode then
			print(
				string.format(
					"%s,%s,%s,%.0f,%.0f,%.1f,%.1f",
					result.uat,
					result.test_scenario,
					result.result,
					result.execution_time_microseconds or 0,
					result.execution_time_with_output_microseconds or 0,
					result.scan_cv or 0,
					result.full_cv or 0
				)
			)
		else
			print(
				string.format(
					"%s,%s,%s,%.6f",
					result.uat,
					result.test_scenario,
					result.result,
					result.execution_time or 0
				)
			)
		end
	end
else
	-- Print summary
	print("")
	print("===========================================")
	print("Test Summary:")
	print("  Passed: " .. passed)
	print("  Failed: " .. failed)
	print("  Total:  " .. (passed + failed))
	if benchmark_tests > 0 or compliance_tests > 0 then
		print("")
		print("Test Categories:")
		if compliance_tests > 0 then
			print("  Compliance tests: " .. compliance_tests)
		end
		if benchmark_tests > 0 then
			print("  Benchmark tests:  " .. benchmark_tests)
		end
	end
	print("===========================================")
	if failed > 0 then
		os.exit(1)
	end
end
