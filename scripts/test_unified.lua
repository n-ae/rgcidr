#!/usr/bin/env lua

-- Unified Test Runner for rgcidr
-- Consolidates all testing functionality with flag-based control
--
-- Usage:
--   lua scripts/test_unified.lua [options]
--
-- Test Types:
--   --unit           Run Zig unit tests (default: included)
--   --functional     Run functional tests with .given/.action/.expected files (default: included)
--   --compare        Compare outputs with original grepcidr
--   --rfc            Run RFC compliance tests
--   --regression     Run performance regression tests vs baseline branch
--   --all            Run comprehensive test suite (includes everything)
--
-- Benchmark Options:
--   --bench          Run performance benchmarks
--   --bench-quick    Run quick benchmarks only
--   --bench-advanced Run advanced benchmark suite
--   --bench-realistic Run realistic performance tests
--   --bench-compare  Compare performance with grepcidr
--
-- Control Options:
--   --baseline=REF   Use specific git ref for regression tests (default: main)
--   --csv            Output results in CSV format
--   --quiet          Reduce output verbosity
--   --verbose        Increase output verbosity
--   --no-build       Skip building binaries (assume already built)
--   --help           Show this help message
--
-- Examples:
--   lua scripts/test_unified.lua                    # Run default tests (unit + functional)
--   lua scripts/test_unified.lua --all             # Run everything
--   lua scripts/test_unified.lua --compare --csv   # Compare with grepcidr, CSV output
--   lua scripts/test_unified.lua --bench --regression --baseline=develop
--   lua scripts/test_unified.lua --functional --rfc

-- Configuration
local config = {
	run_unit = true,
	run_functional = true,
	run_compare = false,
	run_rfc = false,
	run_regression = false,
	run_all = false,

	run_bench = false,
	run_bench_quick = false,
	run_bench_advanced = false,
	run_bench_realistic = false,
	run_bench_compare = false,

	baseline_ref = "main",
	csv_output = false,
	quiet = false,
	verbose = false,
	no_build = false,
	help = false,
}

-- Parse command line arguments
local function parse_args(args)
	for i = 1, #args do
		local arg = args[i]
		if arg == "--help" then
			config.help = true
		elseif arg == "--unit" then
			config.run_unit = true
		elseif arg == "--functional" then
			config.run_functional = true
		elseif arg == "--compare" then
			config.run_compare = true
		elseif arg == "--rfc" then
			config.run_rfc = true
		elseif arg == "--regression" then
			config.run_regression = true
		elseif arg == "--all" then
			config.run_all = true
		elseif arg == "--bench" then
			config.run_bench = true
		elseif arg == "--bench-quick" then
			config.run_bench_quick = true
		elseif arg == "--bench-advanced" then
			config.run_bench_advanced = true
		elseif arg == "--bench-realistic" then
			config.run_bench_realistic = true
		elseif arg == "--bench-compare" then
			config.run_bench_compare = true
		elseif arg == "--csv" or arg == "-c" then
			config.csv_output = true
		elseif arg == "--quiet" or arg == "-q" then
			config.quiet = true
		elseif arg == "--verbose" or arg == "-v" then
			config.verbose = true
		elseif arg == "--no-build" then
			config.no_build = true
		elseif arg:match("^--baseline=") then
			config.baseline_ref = arg:match("^--baseline=(.+)")
		else
			print("Unknown option: " .. arg)
			print("Use --help for usage information")
			os.exit(1)
		end
	end

	-- Enable everything if --all is specified
	if config.run_all then
		config.run_unit = true
		config.run_functional = true
		config.run_compare = true
		config.run_rfc = true
		config.run_regression = true
		config.run_bench_advanced = true
		config.run_bench_compare = true
	end

	-- If no specific tests selected and not --all, use defaults
	local has_specific_tests = config.run_compare
		or config.run_rfc
		or config.run_regression
		or config.run_bench
		or config.run_bench_quick
		or config.run_bench_advanced
		or config.run_bench_realistic
		or config.run_bench_compare

	if not has_specific_tests and not config.run_all then
		-- Default: unit + functional tests
		config.run_unit = true
		config.run_functional = true
	end
end

-- Utility functions
local function run_command(cmd)
	local handle = io.popen(cmd .. " 2>&1")
	local result = handle:read("*a")
	local success, exit_type, exit_code = handle:close()
	return result, exit_code or 0
end

local function run_command_silent(cmd)
	local handle = io.popen(cmd .. " > /dev/null 2>&1")
	handle:read("*a")
	local success, exit_type, exit_code = handle:close()
	return exit_code or 0
end

local function log(level, message)
	if level == "quiet" and config.quiet then
		return
	elseif level == "verbose" and not config.verbose then
		return
	end

	if config.csv_output and level ~= "csv" then
		return
	end

	print(message)
end

local function log_csv(data)
	if config.csv_output then
		print(data)
	end
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

local function show_help()
	print([[
Unified Test Runner for rgcidr

Usage: lua scripts/test_unified.lua [options]

Test Types:
  --unit           Run Zig unit tests (default: included)
  --functional     Run functional tests with .given/.action/.expected files (default: included)
  --compare        Compare outputs with original grepcidr
  --rfc            Run RFC compliance tests
  --regression     Run performance regression tests vs baseline branch
  --all            Run comprehensive test suite (includes everything)

Benchmark Options:
  --bench          Run performance benchmarks
  --bench-quick    Run quick benchmarks only
  --bench-advanced Run advanced benchmark suite
  --bench-realistic Run realistic performance tests
  --bench-compare  Compare performance with grepcidr

Control Options:
  --baseline=REF   Use specific git ref for regression tests (default: main)
  --csv            Output results in CSV format
  --quiet          Reduce output verbosity
  --verbose        Increase output verbosity
  --no-build       Skip building binaries (assume already built)
  --help           Show this help message

Examples:
  lua scripts/test_unified.lua                    # Run default tests (unit + functional)
  lua scripts/test_unified.lua --all             # Run everything
  lua scripts/test_unified.lua --compare --csv   # Compare with grepcidr, CSV output
  lua scripts/test_unified.lua --bench --regression --baseline=develop
  lua scripts/test_unified.lua --functional --rfc
]])
end

-- Test execution functions
local function run_build()
	if config.no_build then
		log("normal", "Skipping build (--no-build specified)")
		return true
	end

	log("normal", "Building rgcidr...")
	local output, code = run_command("zig build -Doptimize=ReleaseFast")
	if code ~= 0 then
		log("normal", "✗ Failed to build rgcidr")
		log("verbose", output)
		return false
	end
	log("normal", "✓ rgcidr built successfully")
	return true
end

local function run_unit_tests()
	if not config.run_unit then
		return true
	end

	log("normal", "\n=== Zig Unit Tests ===")
	local output, code = run_command("zig build test")

	if config.csv_output then
		log_csv("test_type,result,details")
		log_csv("unit," .. (code == 0 and "pass" or "fail") .. ",zig_unit_tests")
	else
		if code == 0 then
			log("normal", "✓ All Zig unit tests passed")
		else
			log("normal", "✗ Some Zig unit tests failed")
			log("verbose", output)
		end
	end

	return code == 0
end

local function run_functional_tests()
	if not config.run_functional then
		return true
	end

	log("normal", "\n=== Functional Tests ===")

	-- Find all test files
	local test_files = {}
	local output, _ = run_command("find tests -name '*.given' 2>/dev/null | sort")
	for line in output:gmatch("[^\r\n]+") do
		if line ~= "" then
			table.insert(test_files, line:match("(.+)%.given$"))
		end
	end

	if #test_files == 0 then
		log("normal", "No functional test files found")
		return true
	end

	local passed = 0
	local failed = 0

	if config.csv_output then
		log_csv("test_type,test_name,result,details")
	end

	for _, base_name in ipairs(test_files) do
		local test_name = base_name:match("tests/(.+)$")
		local given_file = base_name .. ".given"
		local action_file = base_name .. ".action"
		local expected_file = base_name .. ".expected"

		if file_exists(action_file) and file_exists(expected_file) then
			local input_data = read_file(given_file)
			local action = read_file(action_file):gsub("%s+$", "")
			local expected_output = read_file(expected_file)

			-- Create temp file for input
			local temp_file = os.tmpname()
			local f = io.open(temp_file, "w")
			f:write(input_data)
			f:close()

			-- Run test
			local cmd = string.format("./zig-out/bin/rgcidr %s < %s", action, temp_file)
			local actual_output, exit_code = run_command(cmd)

			-- Clean up
			os.remove(temp_file)

			-- Compare results
			local test_passed = (actual_output == expected_output)

			if config.csv_output then
				log_csv(string.format("functional,%s,%s,%s", test_name, test_passed and "pass" or "fail", action))
			else
				if test_passed then
					log("normal", string.format("✓ %s", test_name))
					passed = passed + 1
				else
					log("normal", string.format("✗ %s", test_name))
					log("verbose", string.format("  Expected: %s", expected_output:gsub("\n", "\\n")))
					log("verbose", string.format("  Actual:   %s", actual_output:gsub("\n", "\\n")))
					failed = failed + 1
				end
			end
		end
	end

	if not config.csv_output then
		log("normal", string.format("\nFunctional Tests: %d passed, %d failed", passed, failed))
	end

	return failed == 0
end

local function ensure_grepcidr()
	log("normal", "Ensuring grepcidr is available for comparison tests...")

	-- Check if grepcidr is already available
	local grepcidr_path, _ = run_command("lua scripts/fetch_grepcidr.lua get")
	if grepcidr_path and grepcidr_path:match("^/tmp/grepcidr%-benchmark/") then
		log("normal", "✓ grepcidr is available")
		return true
	end

	-- Try to fetch/build grepcidr
	log("normal", "Fetching and building grepcidr...")
	local output, code = run_command("lua scripts/fetch_grepcidr.lua get")
	if code ~= 0 then
		log("normal", "⚠ Failed to setup grepcidr - comparison tests will be skipped")
		log("verbose", output)
		return false
	end

	log("normal", "✓ grepcidr setup complete")
	return true
end

local function run_compare_tests()
	if not config.run_compare then
		return true
	end

	log("normal", "\n=== Comparison Tests (vs grepcidr) ===")

	-- Ensure grepcidr is available
	if not ensure_grepcidr() then
		log("normal", "⚠ Skipping comparison tests - grepcidr not available")
		return true -- Don't fail the overall test run
	end

	local output, code = run_command("lua scripts/test_compare.lua")

	if config.csv_output then
		log_csv("test_type,result,details")
		log_csv("compare," .. (code == 0 and "pass" or "fail") .. ",grepcidr_comparison")
	else
		log("normal", output)
	end

	return code == 0
end

local function run_rfc_tests()
	if not config.run_rfc then
		return true
	end

	log("normal", "\n=== RFC Compliance Tests ===")

	local output, code = run_command("lua scripts/test_rfc.lua")

	if config.csv_output then
		log_csv("test_type,result,details")
		log_csv("rfc," .. (code == 0 and "pass" or "fail") .. ",rfc_compliance")
	else
		log("normal", output)
	end

	return code == 0
end

local function run_regression_tests()
	if not config.run_regression then
		return true
	end

	log("normal", "\n=== Performance Regression Tests ===")

	local cmd = string.format("lua scripts/bench_regression.lua %s", config.baseline_ref)
	if config.csv_output then
		cmd = cmd .. " --csv"
	end

	local output, code = run_command(cmd)

	if config.csv_output then
		log("normal", output)
	else
		log("normal", output)
	end

	return code == 0
end

local function run_benchmarks()
	local any_bench = config.run_bench
		or config.run_bench_quick
		or config.run_bench_advanced
		or config.run_bench_realistic
		or config.run_bench_compare

	if not any_bench then
		return true
	end

	log("normal", "\n=== Performance Benchmarks ===")

	-- Ensure grepcidr is available for benchmark comparisons
	if config.run_bench_compare or config.run_bench_advanced then
		ensure_grepcidr()
	end

	local success = true

	if config.run_bench or config.run_bench_quick then
		log("normal", "\n--- Quick Benchmarks ---")
		local output, code = run_command("lua scripts/bench_early_exit.lua")
		log("normal", output)
		success = success and (code == 0)
	end

	if config.run_bench_advanced then
		log("normal", "\n--- Advanced Benchmarks ---")
		local output, code = run_command("lua scripts/bench_advanced.lua")
		log("normal", output)
		success = success and (code == 0)
	end

	if config.run_bench_realistic then
		log("normal", "\n--- Realistic Benchmarks ---")
		local output, code = run_command("zig build bench-realistic")
		log("normal", output)
		success = success and (code == 0)
	end

	if config.run_bench_compare then
		log("normal", "\n--- Performance Comparison ---")
		local output, code = run_command("lua scripts/bench_compare.lua")
		log("normal", output)
		success = success and (code == 0)
	end

	return success
end

-- Main execution
local function main()
	parse_args(arg)

	if config.help then
		show_help()
		return
	end

	if not config.csv_output then
		log("normal", "=================================================")
		log("normal", "         rgcidr Unified Test Runner")
		log("normal", "=================================================")
	end

	local overall_success = true

	-- Build phase
	if not run_build() then
		os.exit(1)
	end

	-- Test execution
	overall_success = run_unit_tests() and overall_success
	overall_success = run_functional_tests() and overall_success
	overall_success = run_compare_tests() and overall_success
	overall_success = run_rfc_tests() and overall_success
	overall_success = run_regression_tests() and overall_success
	overall_success = run_benchmarks() and overall_success

	-- Summary
	if not config.csv_output then
		log("normal", "\n=================================================")
		if overall_success then
			log("normal", "✓ All tests completed successfully")
		else
			log("normal", "✗ Some tests failed")
		end
		log("normal", "=================================================")
	end

	os.exit(overall_success and 0 or 1)
end

-- Execute main function
main()

