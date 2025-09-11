#!/usr/bin/env lua

-- Comprehensive comparison test between rgcidr and grepcidr
-- Tests both functionality and performance

local function run_command(cmd)
	local handle = io.popen(cmd .. " 2>&1")
	local result = handle:read("*a")
	local success, exit_type, code = handle:close()
	return result, code or 0
end

local function write_temp_file(content)
	local filename = os.tmpname()
	local file = io.open(filename, "w")
	file:write(content)
	file:close()
	return filename
end

local function get_grepcidr_path()
	local handle = io.popen("lua scripts/fetch_grepcidr.lua get 2>/dev/null")
	local path = handle:read("*a"):gsub("%s+$", "")
	handle:close()
	return path
end

local function compare_outputs(test_name, input, pattern, flags)
	flags = flags or ""

	-- Get grepcidr path
	local grepcidr_path = get_grepcidr_path()
	if not grepcidr_path or grepcidr_path == "" then
		print(string.format("✗ %s: SKIPPED (grepcidr not available)", test_name))
		return false
	end

	-- Create temp input file
	local input_file = write_temp_file(input)

	-- Run both commands
	local grepcidr_cmd = string.format("%s %s %s < %s", grepcidr_path, flags, pattern, input_file)
	local rgcidr_cmd = string.format("./zig-out/bin/rgcidr %s %s < %s", flags, pattern, input_file)

	local grepcidr_out, grepcidr_code = run_command(grepcidr_cmd)
	local rgcidr_out, rgcidr_code = run_command(rgcidr_cmd)

	-- Clean up
	os.remove(input_file)

	-- Compare results
	local passed = (grepcidr_out == rgcidr_out) and (grepcidr_code == rgcidr_code)

	if passed then
		print(string.format("✓ %s: PASSED", test_name))
	else
		print(string.format("✗ %s: FAILED", test_name))
		if grepcidr_out ~= rgcidr_out then
			print("  Output mismatch:")
			print("  grepcidr output:")
			print("  " .. grepcidr_out:gsub("\n", "\n  "))
			print("  rgcidr output:")
			print("  " .. rgcidr_out:gsub("\n", "\n  "))
		end
		if grepcidr_code ~= rgcidr_code then
			print(string.format("  Exit code mismatch: grepcidr=%d, rgcidr=%d", grepcidr_code, rgcidr_code))
		end
	end

	return passed
end

local function benchmark_comparison(test_name, input, pattern, iterations)
	iterations = iterations or 100

	-- Get grepcidr path
	local grepcidr_path = get_grepcidr_path()
	if not grepcidr_path or grepcidr_path == "" then
		print(string.format("%s: SKIPPED (grepcidr not available)", test_name))
		return 1.0
	end

	-- Create temp input file
	local input_file = write_temp_file(input)

	-- Benchmark grepcidr
	local grepcidr_start = os.clock()
	for i = 1, iterations do
		run_command(string.format("%s %s < %s > /dev/null", grepcidr_path, pattern, input_file))
	end
	local grepcidr_time = os.clock() - grepcidr_start

	-- Benchmark rgcidr
	local rgcidr_start = os.clock()
	for i = 1, iterations do
		run_command(string.format("./zig-out/bin/rgcidr %s < %s > /dev/null", pattern, input_file))
	end
	local rgcidr_time = os.clock() - rgcidr_start

	-- Clean up
	os.remove(input_file)

	-- Report results (convert to microseconds)
	local speedup = grepcidr_time / rgcidr_time
	local grepcidr_time_us = grepcidr_time * 1000000
	local rgcidr_time_us = rgcidr_time * 1000000
	local avg_grepcidr_us = grepcidr_time_us / iterations
	local avg_rgcidr_us = rgcidr_time_us / iterations
	
	print(string.format("%s:", test_name))
	print(string.format("  grepcidr: %.1fμs/op (%.3fs total, %d iterations)", avg_grepcidr_us, grepcidr_time, iterations))
	print(string.format("  rgcidr:   %.1fμs/op (%.3fs total, %d iterations)", avg_rgcidr_us, rgcidr_time, iterations))
	print(string.format("  Speedup:  %.2fx %s", speedup, speedup > 1 and "faster ✓" or "slower"))

	return speedup
end

-- Build both implementations
print("=== Building implementations ===")
-- grepcidr will be fetched/built automatically via fetch_grepcidr.lua
run_command("zig build -Doptimize=ReleaseFast")

print("\n=== Functional Comparison Tests ===\n")

local tests_passed = 0
local tests_total = 0

-- Test 1: Basic IPv4 CIDR matching
tests_total = tests_total + 1
if compare_outputs("Basic IPv4 CIDR", "192.168.1.1\n10.0.0.1\n172.16.1.1\n8.8.8.8\n", "192.168.0.0/16") then
	tests_passed = tests_passed + 1
end

-- Test 2: IPv6 CIDR matching
tests_total = tests_total + 1
if compare_outputs("IPv6 CIDR", "2001:db8::1\n2001:db8:1::1\nfe80::1\n::1\n", "2001:db8::/32") then
	tests_passed = tests_passed + 1
end

-- Test 3: Multiple patterns
tests_total = tests_total + 1
if
	compare_outputs("Multiple patterns", "192.168.1.1\n10.0.0.1\n172.16.1.1\n8.8.8.8\n", '"192.168.0.0/16,10.0.0.0/8"')
then
	tests_passed = tests_passed + 1
end

-- Test 4: IP ranges
tests_total = tests_total + 1
if
	compare_outputs("IP ranges", "192.168.1.1\n192.168.1.50\n192.168.1.100\n192.168.2.1\n", "192.168.1.1-192.168.1.100")
then
	tests_passed = tests_passed + 1
end

-- Test 5: Count mode
tests_total = tests_total + 1
if compare_outputs("Count mode", "192.168.1.1\n192.168.1.2\n10.0.0.1\n", "192.168.0.0/16", "-c") then
	tests_passed = tests_passed + 1
end

-- Test 6: Invert match
tests_total = tests_total + 1
if compare_outputs("Invert match", "192.168.1.1\n10.0.0.1\n8.8.8.8\n", "192.168.0.0/16", "-v") then
	tests_passed = tests_passed + 1
end

-- Test 7: Exact match
tests_total = tests_total + 1
if compare_outputs("Exact match", "192.168.1.1\n192.168.1.1 with text\ntext 192.168.1.1\n", "192.168.1.1", "-x") then
	tests_passed = tests_passed + 1
end

-- Test 8: Include non-IP lines
tests_total = tests_total + 1
if compare_outputs("Include non-IP", "192.168.1.1\nno ip here\n10.0.0.1\njust text\n", "192.168.0.0/16", "-i") then
	tests_passed = tests_passed + 1
end

-- Test 9: Strict CIDR alignment
tests_total = tests_total + 1
if compare_outputs("Strict alignment", "192.168.1.1\n192.168.0.0\n", "192.168.1.0/24", "-s") then
	tests_passed = tests_passed + 1
end

-- Test 10: Mixed IPv4 and IPv6
tests_total = tests_total + 1
if compare_outputs("Mixed protocols", "192.168.1.1\n2001:db8::1\n10.0.0.1\nfe80::1\n::1\n", '"::/0,0.0.0.0/0"') then
	tests_passed = tests_passed + 1
end

-- Test 11: Empty input
tests_total = tests_total + 1
if compare_outputs("Empty input", "", "192.168.0.0/16") then
	tests_passed = tests_passed + 1
end

-- Test 12: No matches
tests_total = tests_total + 1
if compare_outputs("No matches", "10.0.0.1\n172.16.1.1\n", "192.168.0.0/16") then
	tests_passed = tests_passed + 1
end

-- Test 13: Special IPv6 addresses
tests_total = tests_total + 1
if compare_outputs("Special IPv6", "::1\n::\n::ffff:192.168.1.1\nfe80::1\nff02::1\n", "::/0") then
	tests_passed = tests_passed + 1
end

-- Test 14: Embedded IPs in text
tests_total = tests_total + 1
if
	compare_outputs(
		"Embedded IPs",
		"Server 192.168.1.50 responded\nClient from 10.0.0.1 connected\nError at 8.8.8.8:53\n",
		"192.168.0.0/16"
	)
then
	tests_passed = tests_passed + 1
end

-- Test 15: Large CIDR blocks
tests_total = tests_total + 1
if compare_outputs("Large CIDR", "1.2.3.4\n100.200.100.200\n255.255.255.255\n0.0.0.0\n", "0.0.0.0/0") then
	tests_passed = tests_passed + 1
end

print(
	string.format(
		"\nFunctional Tests: %d/%d passed (%.1f%%)\n",
		tests_passed,
		tests_total,
		tests_passed * 100.0 / tests_total
	)
)

print("=== Performance Benchmarks ===\n")

-- Generate test data for benchmarks
local function generate_ips(count)
	local ips = {}
	for i = 1, count do
		table.insert(
			ips,
			string.format(
				"%d.%d.%d.%d",
				math.random(1, 255),
				math.random(0, 255),
				math.random(0, 255),
				math.random(0, 255)
			)
		)
	end
	return table.concat(ips, "\n")
end

local function generate_mixed_ips(count)
	local ips = {}
	for i = 1, count do
		if i % 2 == 0 then
			table.insert(
				ips,
				string.format(
					"%d.%d.%d.%d",
					math.random(1, 255),
					math.random(0, 255),
					math.random(0, 255),
					math.random(0, 255)
				)
			)
		else
			table.insert(
				ips,
				string.format("2001:db8:%x:%x::%x", math.random(0, 65535), math.random(0, 65535), math.random(1, 65535))
			)
		end
	end
	return table.concat(ips, "\n")
end

local function generate_log_lines(count)
	local lines = {}
	local templates = {
		"2024-01-01 10:00:00 Server %s responded",
		"Client connection from %s accepted",
		"Error: Failed to connect to %s",
		"[INFO] Request from %s processed",
		"No IP in this line at all",
	}
	for i = 1, count do
		if i % 5 == 0 then
			table.insert(lines, templates[5])
		else
			local ip = string.format(
				"%d.%d.%d.%d",
				math.random(1, 255),
				math.random(0, 255),
				math.random(0, 255),
				math.random(0, 255)
			)
			table.insert(lines, string.format(templates[(i % 4) + 1], ip))
		end
	end
	return table.concat(lines, "\n")
end

-- Benchmark 1: Small dataset (100 IPs)
benchmark_comparison("Small dataset (100 IPs)", generate_ips(100), "192.168.0.0/16", 100)

-- Benchmark 2: Medium dataset (1000 IPs)
benchmark_comparison("Medium dataset (1000 IPs)", generate_ips(1000), "10.0.0.0/8", 50)

-- Benchmark 3: Large dataset (10000 IPs)
benchmark_comparison("Large dataset (10000 IPs)", generate_ips(10000), '"192.168.0.0/16,10.0.0.0/8,172.16.0.0/12"', 10)

-- Benchmark 4: Mixed IPv4/IPv6
benchmark_comparison("Mixed IPv4/IPv6 (1000)", generate_mixed_ips(1000), '"2001:db8::/32,192.168.0.0/16"', 50)

-- Benchmark 5: Log file scanning
benchmark_comparison("Log scanning (5000 lines)", generate_log_lines(5000), "192.168.0.0/16", 20)

-- Benchmark 6: Count mode performance
local count_input = generate_ips(1000)
local count_file = write_temp_file(count_input)
print("\nCount mode (1000 IPs):")
local grep_start = os.clock()
for i = 1, 50 do
	run_command(string.format("./grepcidr/grepcidr -c 10.0.0.0/8 < %s > /dev/null", count_file))
end
local grep_time = os.clock() - grep_start
local rg_start = os.clock()
for i = 1, 50 do
	run_command(string.format("./zig-out/bin/rgcidr -c 10.0.0.0/8 < %s > /dev/null", count_file))
end
local rg_time = os.clock() - rg_start
os.remove(count_file)
print(string.format("  grepcidr: %.3fs (50 iterations)", grep_time))
print(string.format("  rgcidr:   %.3fs (50 iterations)", rg_time))
print(string.format("  Speedup:  %.2fx %s", grep_time / rg_time, grep_time / rg_time > 1 and "faster ✓" or "slower"))

print("\n=== Summary ===")
print(
	string.format(
		"Functional compatibility: %d/%d tests passed (%.1f%%)",
		tests_passed,
		tests_total,
		tests_passed * 100.0 / tests_total
	)
)

-- Check if rgcidr is consistently faster
if tests_passed == tests_total then
	print("✓ Full functional compatibility with grepcidr achieved!")
else
	print("⚠ Some functional differences detected - review failed tests")
end
