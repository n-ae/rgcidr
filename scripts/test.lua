#!/usr/bin/env lua

-- Test script for rgcidr - Zig implementation of grepcidr
-- This script tests various CIDR filtering scenarios using external test files
--
-- Usage:
--   lua test.lua               - Run tests with standard output
--   lua test.lua --csv         - Output results in CSV format
--   lua test.lua -c            - Output results in CSV format (short form)
--   lua test.lua --benchmark   - Run only benchmark tests with separate UAT timing
--   lua test.lua --help        - Show this help message
--
-- CSV Output Format:
--   uat,test scenario,result
--   rgcidr,grepcidr,test_name,pass/fail

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
			print("rgcidr Test Suite")
			print("")
			print("Usage:")
			print("  lua test.lua               - Run tests with standard output")
			print("  lua test.lua --csv         - Output results in CSV format")
			print("  lua test.lua -c            - Output results in CSV format (short form)")
			print("  lua test.lua --benchmark   - Run only benchmark tests with separate UAT timing")
			print("  lua test.lua --help        - Show this help message")
			print("")
			print("CSV Output Format:")
			print("  uat,test scenario,result")
			print("  rgcidr,grepcidr,test_name,pass/fail")
			print("")
			print("Examples:")
			print("  lua test.lua --csv > test_results.csv")
			print("  lua test.lua --benchmark --csv > benchmark_results.csv")
			os.exit(0)
		end
	end
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

	-- Execute command
	local output, exit_code
	if args:match("%.given") then
		output, exit_code = run_command("./zig-out/bin/rgcidr " .. args)
	else
		local given_file = test_dir .. "/" .. test_name .. ".given"
		if file_exists(given_file) then
			output, exit_code = run_command("./zig-out/bin/rgcidr " .. args .. " " .. given_file)
		else
			output, exit_code = run_command("./zig-out/bin/rgcidr " .. args)
		end
	end

	-- Read expected output
	local expected_file = test_dir .. "/" .. test_name .. ".expected"
	local expected = read_file(expected_file)

	-- Normalize output by trimming whitespace
	local normalized_output = output:gsub("%s+$", "")
	local normalized_expected = expected:gsub("%s+$", "")

	-- Check results
	local test_passed = (normalized_output == normalized_expected and exit_code == expected_exit_code)
	local result_status = test_passed and "pass" or "fail"

	-- Store CSV results (only rgcidr for compliance tests)
	table.insert(csv_results, {
		uat = "rgcidr",
		test_scenario = test_name,
		category = category,
		result = result_status,
		execution_time = nil,
		execution_time_microseconds = nil,
	})

	if test_passed then
		if not csv_mode then
			print("✓ " .. test_name .. " PASSED")
		end
		passed = passed + 1
	else
		if not csv_mode then
			print("✗ " .. test_name .. " FAILED")
			print("Expected exit code: " .. expected_exit_code .. ", got: " .. exit_code)
			print("Expected output:")
			if normalized_expected == "" then
				print("(empty)")
			else
				print(expected)
			end
			print("Actual output:")
			if normalized_output == "" then
				print("(empty)")
			else
				print(output)
			end
		end
		failed = failed + 1
	end
end

-- Main test execution
local function run_tests()
	if not csv_mode then
		if benchmark_mode then
			print("=== rgcidr Benchmark Suite ===")
		else
			print("=== rgcidr Test Suite ===")
		end
		print("\nBuilding rgcidr...")
	end

	local build_output, build_exit = run_command("zig build -Doptimize=ReleaseFast")
	if build_exit ~= 0 then
		if not csv_mode then
			print("Build failed!")
			print(build_output)
		end
		return
	end

	if not csv_mode then
		print("Build successful!")
		if benchmark_mode then
			print("\nRunning benchmarks...\n")
		else
			print("\nRunning tests...\n")
		end
	end

	-- Get and run all tests
	local tests = get_test_cases()
	if #tests == 0 then
		if not csv_mode then
			print("No test cases found in " .. test_dir .. "/ directory")
		end
		return
	end

	for _, test_name in ipairs(tests) do
		run_test(test_name)
	end

	-- Output results
	if csv_mode then
		-- Print CSV header
		if benchmark_mode then
			print("uat,test scenario,category,result,execution_time_microseconds")
		else
			print("uat,test scenario,category,result,execution_time")
		end

		-- Print CSV data
		for _, result in ipairs(csv_results) do
			if benchmark_mode then
				local time_str = result.execution_time_microseconds
						and string.format("%.0f", result.execution_time_microseconds)
					or ""
				print(
					string.format(
						"%s,%s,%s,%s,%s",
						result.uat,
						result.test_scenario,
						result.category,
						result.result,
						time_str
					)
				)
			else
				local time_str = result.execution_time and string.format("%.3f", result.execution_time) or ""
				print(
					string.format(
						"%s,%s,%s,%s,%s",
						result.uat,
						result.test_scenario,
						result.category,
						result.result,
						time_str
					)
				)
			end
		end
	else
		-- Print summary
		if benchmark_mode then
			print("\n=== Benchmark Summary ===")
			print("Benchmarks run: " .. benchmark_tests)
			print("Passed: " .. passed)
			print("Failed: " .. failed)
			print("Total:  " .. (passed + failed))
		else
			print("\n=== Test Summary ===")
			print("Passed: " .. passed)
			print("Failed: " .. failed)
			print("Total:  " .. (passed + failed))
			print("\n=== Test Categories ===")
			print("Compliance tests: " .. compliance_tests)
			print("Benchmark tests:  " .. benchmark_tests)
		end

		if failed == 0 then
			if benchmark_mode then
				print("\n🎉 All benchmarks passed!")
			else
				print("\n🎉 All tests passed!")
			end
		else
			if benchmark_mode then
				print("\n❌ Some benchmarks failed!")
			else
				print("\n❌ Some tests failed!")
			end
		end
	end

	-- Exit with appropriate code
	if failed == 0 then
		os.exit(0)
	else
		os.exit(1)
	end
end

-- Run tests
run_tests()
