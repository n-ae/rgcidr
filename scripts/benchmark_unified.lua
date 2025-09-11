#!/usr/bin/env lua

-- Unified Benchmark Framework for rgcidr
-- Consolidates all benchmark functionality with consistent comparison between:
-- - rgcidr (current version)
-- - rgcidr-last-version (previous git tag)
-- - grepcidr (reference implementation)
--
-- Usage:
--   lua scripts/benchmark_unified.lua [options]
--
-- Options:
--   --quick           Run quick performance tests
--   --comprehensive   Run comprehensive benchmark suite
--   --regression      Compare against previous version only
--   --compare-all     Compare all three implementations
--   --profile         Include detailed profiling information
--   --csv             Output results in CSV format
--   --no-build        Skip building binaries (assume already built)
--   --help            Show this help message

local config = {
	quick = false,
	comprehensive = false,
	regression = false,
	compare_all = true, -- Default to full comparison
	profile = false,
	csv = false,
	no_build = false,
	help = false,
}

-- Parse command line arguments
local function parse_args(args)
	for _, arg in ipairs(args) do
		if arg == "--quick" then
			config.quick = true
		elseif arg == "--comprehensive" then
			config.comprehensive = true
		elseif arg == "--regression" then
			config.regression = true
			config.compare_all = false
		elseif arg == "--compare-all" then
			config.compare_all = true
		elseif arg == "--profile" then
			config.profile = true
		elseif arg == "--csv" then
			config.csv = true
		elseif arg == "--no-build" then
			config.no_build = true
		elseif arg == "--help" then
			config.help = true
		end
	end
end

-- Utility functions
local function run_command(cmd)
	local handle = io.popen(cmd .. " 2>&1")
	local result = handle:read("*a")
	local success, exit_type, code = handle:close()
	return result, code or 0
end

local function run_command_silent(cmd)
	local _, code = run_command(cmd .. " > /dev/null 2>&1")
	return code == 0
end

local function log(level, message)
	-- Only show debug messages if explicitly requested
	if level == "debug" and not config.verbose then
		return
	end

	if not config.csv or level == "error" or level == "normal" then
		print(message)
	end
end

local function precise_time()
	return os.clock()
end

local function write_temp_file(content)
	local filename = os.tmpname()
	local file = io.open(filename, "w")
	if not file then
		error("Could not create temp file: " .. filename)
	end
	file:write(content)
	file:close()
	return filename
end

-- Implementation detection and building
local Implementation = {}
Implementation.__index = Implementation

function Implementation.new(name, path, build_cmd)
	return setmetatable({
		name = name,
		path = path,
		build_cmd = build_cmd,
		available = false,
		build_time_us = 0,
	}, Implementation)
end

function Implementation:check_availability()
	if not self.path or self.path == "" then
		self.available = false
		return false
	end

	-- Check if file exists and is executable
	local _, code = run_command("test -x " .. self.path)
	if code == 0 then
		self.available = true
		return true
	end

	-- For system commands, check if they're in PATH
	if not string.match(self.path, "/") then
		local _, code2 = run_command("which " .. self.path)
		if code2 == 0 then
			self.available = true
			return true
		end
	end

	self.available = false
	return false
end

function Implementation:build()
	if not self.build_cmd or config.no_build then
		return self:check_availability()
	end

	log("normal", "Building " .. self.name .. "...")
	local start = precise_time()
	local output, code = run_command(self.build_cmd)
	local elapsed = precise_time() - start

	self.build_time_us = elapsed * 1000000

	if code ~= 0 then
		log("error", "Failed to build " .. self.name .. ":")
		log("error", output)
		self.available = false
		return false
	end

	log("normal", string.format("✓ %s built successfully (%.1fμs)", self.name, self.build_time_us))
	return self:check_availability()
end

-- Get previous version tag
local function get_last_version_tag()
	local output, code = run_command("git describe --tags --abbrev=0 HEAD~1 2>/dev/null")
	if code == 0 then
		return output:gsub("%s+$", "") -- trim whitespace
	end

	-- Fallback: try to get any previous tag
	output, code = run_command("git tag --sort=-version:refname | head -1")
	if code == 0 and output:gsub("%s+$", "") ~= "" then
		return output:gsub("%s+$", "")
	end

	return nil
end

-- Setup implementations
local function setup_implementations()
	local implementations = {}

	-- Current rgcidr
	implementations.rgcidr = Implementation.new("rgcidr", "./zig-out/bin/rgcidr", "zig build -Doptimize=ReleaseFast")

	-- Previous version rgcidr
	local last_tag = get_last_version_tag()
	if last_tag and config.compare_all then
		implementations.rgcidr_last = Implementation.new(
			"rgcidr-last-version",
			"./zig-out/bin/rgcidr-last",
			string.format(
				[[
                git stash push -m "benchmark_stash_$(date +%%s)" &&
                git checkout %s &&
                zig build -Doptimize=ReleaseFast &&
                cp zig-out/bin/rgcidr zig-out/bin/rgcidr-last &&
                git checkout - &&
                git stash pop
            ]],
				last_tag
			)
		)
	end

	-- grepcidr (reference implementation)
	if config.compare_all then
		-- Use the fetch_grepcidr.lua script to get grepcidr
		local grepcidr_path_output, grepcidr_code = run_command("lua scripts/fetch_grepcidr.lua get")
		if grepcidr_code == 0 then
			local grepcidr_path = grepcidr_path_output:gsub("%s+$", "") -- trim whitespace
			implementations.grepcidr = Implementation.new(
				"grepcidr",
				grepcidr_path,
				nil -- Already built by fetch script
			)
		end
	end

	return implementations
end

-- Benchmark execution
local BenchmarkResult = {}
BenchmarkResult.__index = BenchmarkResult

function BenchmarkResult.new(name, impl_name)
	return setmetatable({
		name = name,
		impl_name = impl_name,
		success = false,
		reliable = false,
		avg_us = 0,
		min_us = 0,
		max_us = 0,
		stddev_us = 0,
		iterations = 0,
		variance_percent = 0,
	}, BenchmarkResult)
end

local function run_benchmark(impl, test_name, input_data, pattern, iterations)
	-- Increase minimum iterations for better statistical significance
	iterations = math.max(iterations or 100, 50)
	local result = BenchmarkResult.new(test_name, impl.name)
	result.iterations = iterations

	if not impl.available then
		log("error", string.format("⚠️  %s not available for %s", impl.name, test_name))
		return result
	end

	-- Create temp input file once and reuse
	local temp_file = write_temp_file(input_data)

	-- Handle different command formats based on pattern type
	local cmd
	if string.match(pattern, "^%-[a-z]") then
		-- Pattern contains flags, use file argument format
		cmd = string.format("%s %s %s > /dev/null 2>/dev/null", impl.path, pattern, temp_file)
	else
		-- Normal pattern, use stdin redirection
		cmd = string.format("%s %s < %s > /dev/null 2>/dev/null", impl.path, pattern, temp_file)
	end

	-- Extended warmup runs to stabilize performance
	for i = 1, 15 do
		run_command_silent(cmd)
	end

	-- Multiple measurement rounds to detect and handle system noise
	local all_times = {}
	local failed_runs = 0

	-- Run measurements in multiple rounds to detect system interference
	local rounds = math.max(3, math.floor(iterations / 25))
	local measurements_per_round = math.floor(iterations / rounds)

	for round = 1, rounds do
		local round_times = {}

		for i = 1, measurements_per_round do
			local start = precise_time()
			local _, code = run_command(cmd)
			local elapsed_us = (precise_time() - start) * 1000000

			if code == 0 then
				table.insert(round_times, elapsed_us)
			else
				failed_runs = failed_runs + 1
			end
		end

		-- Add round measurements to overall pool
		for _, time in ipairs(round_times) do
			table.insert(all_times, time)
		end

		-- Brief pause between rounds to reduce thermal/scheduler effects
		if round < rounds then
			run_command_silent("sleep 0.1")
		end
	end

	local times = all_times

	os.remove(temp_file)

	if #times == 0 then
		log("error", string.format("✗ %s failed all runs for %s", impl.name, test_name))
		return result
	end

	if failed_runs > 0 then
		log("normal", string.format("⚠️  %s had %d failed runs for %s", impl.name, failed_runs, test_name))
	end

	-- Sort times for statistical analysis
	table.sort(times)

	-- Remove statistical outliers using IQR method for more stable measurements
	local function remove_outliers(data)
		if #data < 10 then
			return data
		end -- Too few points for outlier removal

		local q1_idx = math.floor(#data * 0.25)
		local q3_idx = math.floor(#data * 0.75)
		local q1 = data[q1_idx]
		local q3 = data[q3_idx]
		local iqr = q3 - q1
		local lower_bound = q1 - 1.5 * iqr
		local upper_bound = q3 + 1.5 * iqr

		local filtered = {}
		local outliers_removed = 0
		for _, t in ipairs(data) do
			if t >= lower_bound and t <= upper_bound then
				table.insert(filtered, t)
			else
				outliers_removed = outliers_removed + 1
			end
		end

		if outliers_removed > 0 then
			log("debug", string.format("  Removed %d outliers from %s %s", outliers_removed, impl.name, test_name))
		end

		return #filtered >= 5 and filtered or data -- Keep original if too few remain
	end

	times = remove_outliers(times)

	-- Calculate robust statistics
	local sum = 0
	result.min_us = times[1]
	result.max_us = times[#times]

	for _, t in ipairs(times) do
		sum = sum + t
	end

	result.avg_us = sum / #times

	-- Calculate standard deviation and variance
	local variance_sum = 0
	for _, t in ipairs(times) do
		variance_sum = variance_sum + (t - result.avg_us) ^ 2
	end

	result.stddev_us = math.sqrt(variance_sum / (#times - 1)) -- Sample standard deviation
	result.variance_percent = (result.stddev_us / result.avg_us) * 100

	-- Statistical reliability validation
	local is_reliable = true
	local reliability_issues = {}

	-- Check variance threshold (should be <10% for reliable measurements)
	if result.variance_percent > 10.0 then
		is_reliable = false
		table.insert(reliability_issues, string.format("high variance (%.1f%%)", result.variance_percent))
	end

	-- Check minimum sample size for statistical significance
	if #times < 30 then
		is_reliable = false
		table.insert(reliability_issues, string.format("insufficient samples (%d)", #times))
	end

	-- Check for extremely unstable measurements
	if result.max_us > result.min_us * 3 then
		is_reliable = false
		table.insert(reliability_issues, "extreme outliers detected")
	end

	-- Report reliability issues
	if not is_reliable then
		log(
			"normal",
			string.format(
				"⚠️  %s %s: UNRELIABLE - %s",
				impl.name,
				test_name,
				table.concat(reliability_issues, ", ")
			)
		)
	end

	result.success = true
	result.reliable = is_reliable

	return result
end

-- Test data generation
local function generate_test_data()
	local data = {}

	-- Small dataset (100 IPs)
	local small_ips = {}
	for i = 1, 100 do
		table.insert(small_ips, string.format("192.168.1.%d", i))
	end
	data.small = table.concat(small_ips, "\n")

	-- Medium dataset (1000 IPs)
	local medium_ips = {}
	for i = 1, 1000 do
		table.insert(
			medium_ips,
			string.format("10.%d.%d.%d", math.random(0, 255), math.random(0, 255), math.random(1, 254))
		)
	end
	data.medium = table.concat(medium_ips, "\n")

	-- Large dataset (10000 IPs)
	local large_ips = {}
	for i = 1, 10000 do
		table.insert(
			large_ips,
			string.format(
				"%d.%d.%d.%d",
				math.random(1, 223),
				math.random(0, 255),
				math.random(0, 255),
				math.random(1, 254)
			)
		)
	end
	data.large = table.concat(large_ips, "\n")

	-- IPv6 dataset
	local ipv6_ips = {}
	for i = 1, 500 do
		table.insert(
			ipv6_ips,
			string.format(
				"2001:db8::%x:%x:%x:%x",
				math.random(0, 65535),
				math.random(0, 65535),
				math.random(0, 65535),
				math.random(0, 65535)
			)
		)
	end
	data.ipv6 = table.concat(ipv6_ips, "\n")

	-- Mixed dataset
	data.mixed = data.small .. "\n" .. data.ipv6

	-- Log-like data
	local log_lines = {}
	for i = 1, 1000 do
		local ip = string.format("192.168.%d.%d", math.random(1, 10), math.random(1, 254))
		table.insert(
			log_lines,
			string.format(
				"2024-01-01 %02d:%02d:%02d Server %s connection",
				math.random(0, 23),
				math.random(0, 59),
				math.random(0, 59),
				ip
			)
		)
	end
	data.logs = table.concat(log_lines, "\n")

	return data
end

-- Benchmark suites
local function run_quick_benchmarks(implementations, test_data)
	local benchmarks = {
		{ name = "Small Dataset (100 IPs)", data = test_data.small, pattern = "192.168.0.0/16", iterations = 50 },
		{ name = "Medium Dataset (1000 IPs)", data = test_data.medium, pattern = "10.0.0.0/8", iterations = 20 },
		{ name = "IPv6 Performance", data = test_data.ipv6, pattern = "2001:db8::/32", iterations = 20 },
	}

	return benchmarks
end

local function run_comprehensive_benchmarks(implementations, test_data)
	local benchmarks = {
		{ name = "Small Dataset (100 IPs)", data = test_data.small, pattern = "192.168.0.0/16", iterations = 100 },
		{ name = "Medium Dataset (1000 IPs)", data = test_data.medium, pattern = "10.0.0.0/8", iterations = 75 },
		{ name = "Large Dataset (10000 IPs)", data = test_data.large, pattern = "172.16.0.0/12", iterations = 50 }, -- Increased from 20
		{ name = "IPv6 Performance", data = test_data.ipv6, pattern = "2001:db8::/32", iterations = 75 },
		{ name = "Mixed IPv4/IPv6", data = test_data.mixed, pattern = "192.168.0.0/16,2001:db8::/32", iterations = 60 }, -- Increased from 30
		{ name = "Log File Scanning", data = test_data.logs, pattern = "192.168.0.0/16", iterations = 75 }, -- Increased from 30
		{
			name = "Multiple Patterns",
			data = test_data.medium,
			pattern = "10.0.0.0/8,192.168.0.0/16,172.16.0.0/12",
			iterations = 60,
		}, -- Increased from 30
		{ name = "Count Mode", data = test_data.medium, pattern = "-c 10.0.0.0/8", iterations = 75 },
		{ name = "Inverted Match", data = test_data.medium, pattern = "-v 192.168.0.0/16", iterations = 75 }, -- medium has 10.x and 172.x IPs that won't match
	}

	return benchmarks
end

-- Results reporting
local function print_results(all_results, implementations)
	if config.csv then
		-- CSV Header
		print("benchmark,implementation,avg_us,min_us,max_us,variance_percent,iterations,success")

		for benchmark_name, results in pairs(all_results) do
			for impl_name, result in pairs(results) do
				print(
					string.format(
						"%s,%s,%.3f,%.3f,%.3f,%.2f,%d,%s",
						benchmark_name,
						impl_name,
						result.avg_us,
						result.min_us,
						result.max_us,
						result.variance_percent,
						result.iterations,
						result.success and "true" or "false"
					)
				)
			end
		end
		return
	end

	-- Human-readable output
	log("normal", "\n=== Benchmark Results ===\n")

	for benchmark_name, results in pairs(all_results) do
		log("normal", string.format("📊 %s:", benchmark_name))

		-- Sort implementations for consistent output
		local impl_names = {}
		for name, _ in pairs(results) do
			table.insert(impl_names, name)
		end
		table.sort(impl_names)

		for _, impl_name in ipairs(impl_names) do
			local result = results[impl_name]
			if result.success then
				-- Determine status based on variance and reliability
				local status
				if result.reliable and result.variance_percent < 5.0 then
					status = "✓" -- Excellent
				elseif result.reliable and result.variance_percent < 10.0 then
					status = "⚠" -- Good but not excellent
				elseif result.reliable then
					status = "△" -- Acceptable but high variance
				else
					status = "✗" -- Unreliable
				end

				local reliability_marker = result.reliable and "" or " [UNRELIABLE]"
				log(
					"normal",
					string.format(
						"  %s %s: %.1fμs/op (±%.1f%%, %d runs)%s",
						status,
						impl_name,
						result.avg_us,
						result.variance_percent,
						result.iterations,
						reliability_marker
					)
				)
			else
				log("normal", string.format("  ✗ %s: FAILED", impl_name))
			end
		end

		-- Show performance comparisons with statistical significance
		if results.rgcidr and results.rgcidr.success then
			for _, other_impl in ipairs(impl_names) do
				if other_impl ~= "rgcidr" and results[other_impl] and results[other_impl].success then
					local rgcidr_result = results.rgcidr
					local other_result = results[other_impl]

					local speedup = other_result.avg_us / rgcidr_result.avg_us

					-- Statistical significance test using t-test approximation
					local function is_statistically_significant(r1, r2)
						if not (r1.reliable and r2.reliable) then
							return false
						end

						-- Cohen's d effect size
						local pooled_stddev = math.sqrt((r1.stddev_us ^ 2 + r2.stddev_us ^ 2) / 2)
						local effect_size = math.abs(r1.avg_us - r2.avg_us) / pooled_stddev

						-- Consider significant if effect size > 0.5 (medium effect) and difference > 3%
						local percent_diff = math.abs(r1.avg_us - r2.avg_us) / r1.avg_us * 100
						return effect_size > 0.5 and percent_diff > 3.0
					end

					local is_significant = is_statistically_significant(rgcidr_result, other_result)
					local significance_marker = is_significant and "" or " [not significant]"

					-- Only show comparison if both measurements are reliable
					if rgcidr_result.reliable and other_result.reliable then
						log(
							"normal",
							string.format(
								"    vs %s: %.2fx %s%s",
								other_impl,
								speedup,
								speedup > 1 and "faster" or "slower",
								significance_marker
							)
						)
					else
						log(
							"normal",
							string.format("    vs %s: COMPARISON INVALID (unreliable measurements)", other_impl)
						)
					end
				end
			end
		end

		log("normal", "")
	end
end

-- Help display
local function show_help()
	print([[
Unified Benchmark Framework for rgcidr

This script consolidates all benchmark functionality with consistent comparison between:
- rgcidr (current version)
- rgcidr-last-version (previous git tag)
- grepcidr (reference implementation)

Usage: lua scripts/benchmark_unified.lua [options]

Options:
  --quick           Run quick performance tests (3 benchmarks)
  --comprehensive   Run comprehensive benchmark suite (9+ benchmarks)
  --regression      Compare current vs previous version only
  --compare-all     Compare all three implementations (default)
  --profile         Include detailed profiling information
  --csv             Output results in CSV format
  --no-build        Skip building binaries (assume already built)
  --help            Show this help message

Examples:
  lua scripts/benchmark_unified.lua --quick
  lua scripts/benchmark_unified.lua --comprehensive --csv
  lua scripts/benchmark_unified.lua --regression
  lua scripts/benchmark_unified.lua --compare-all --profile
]])
end

-- Main execution
local function main()
	parse_args(arg)

	if config.help then
		show_help()
		return
	end

	if not config.csv then
		log("normal", "🚀 rgcidr Unified Benchmark Framework")
		log("normal", "=====================================\n")
	end

	-- Setup implementations
	local implementations = setup_implementations()

	-- Build all available implementations
	local available_impls = {}
	for name, impl in pairs(implementations) do
		if impl:build() then
			available_impls[name] = impl
			if not config.csv then
				log("normal", string.format("✓ %s ready", impl.name))
			end
		else
			if not config.csv then
				log("normal", string.format("⚠️  %s not available", impl.name))
			end
		end
	end

	if next(available_impls) == nil then
		log("error", "❌ No implementations available for benchmarking!")
		return
	end

	-- Generate test data
	local test_data = generate_test_data()

	-- Select benchmark suite
	local benchmarks
	if config.comprehensive then
		benchmarks = run_comprehensive_benchmarks(available_impls, test_data)
	else
		benchmarks = run_quick_benchmarks(available_impls, test_data)
	end

	-- Run benchmarks
	local all_results = {}

	for _, benchmark in ipairs(benchmarks) do
		if not config.csv then
			log("normal", string.format("Running: %s", benchmark.name))
		end

		all_results[benchmark.name] = {}

		for impl_name, impl in pairs(available_impls) do
			local result = run_benchmark(impl, benchmark.name, benchmark.data, benchmark.pattern, benchmark.iterations)
			all_results[benchmark.name][impl_name] = result
		end
	end

	-- Print results
	print_results(all_results, available_impls)

	-- Summary
	if not config.csv then
		log("normal", "🎉 Benchmark suite completed!")
		log("normal", string.format("Tested %d benchmarks across %d implementations", #benchmarks, #available_impls))
	end
end

-- Error handling wrapper
local function safe_main()
	local success, err = pcall(main)
	if not success then
		log("error", "❌ Benchmark failed: " .. tostring(err))
		os.exit(1)
	end
end

safe_main()

