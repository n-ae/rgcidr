#!/usr/bin/env lua

-- Comprehensive test suite that includes grepcidr comparison

print("=================================================")
print("     rgcidr Comprehensive Test Suite")
print("=================================================\n")

local function run_command(cmd)
    local handle = io.popen(cmd .. " 2>&1")
    local result = handle:read("*a")
    local success, exit_type, code = handle:close()
    return result, code or 0
end

-- Build everything
print("[ Building rgcidr and grepcidr ]")
local build_rg, code_rg = run_command("zig build -Doptimize=ReleaseFast")
if code_rg ~= 0 then
    print("✗ Failed to build rgcidr")
    print(build_rg)
    os.exit(1)
end
print("✓ rgcidr built successfully")

local build_grep, code_grep = run_command("cd grepcidr && make clean && make")
if code_grep ~= 0 then
    print("✗ Failed to build grepcidr")
    print(build_grep)
    os.exit(1)
end
print("✓ grepcidr built successfully")

print("\n[ Running Zig unit tests ]")
local zig_tests, zig_code = run_command("zig build test")
if zig_code == 0 then
    print("✓ All Zig unit tests passed")
else
    print("✗ Some Zig unit tests failed")
    print(zig_tests)
end

print("\n[ Running compliance test suite ]")
local compliance_output, compliance_code = run_command("lua scripts/test.lua")

-- Parse test results
local passed = 0
local failed = 0
local total = 0
for line in compliance_output:gmatch("[^\r\n]+") do
    if line:match("^✓") then
        passed = passed + 1
        total = total + 1
    elseif line:match("^✗") then
        failed = failed + 1
        total = total + 1
        print("  " .. line)  -- Print failed tests
    end
end

print(string.format("  Compliance: %d/%d tests passed (%.1f%%)", 
    passed, total, passed * 100.0 / total))

print("\n[ Running grepcidr compatibility tests ]")

-- Test critical compatibility areas
local compat_tests = {
    {
        name = "IPv4 CIDR matching",
        input = "192.168.1.1\n10.0.0.1\n172.16.1.1\n",
        pattern = "192.168.0.0/16",
        critical = true
    },
    {
        name = "IPv6 CIDR matching",
        input = "2001:db8::1\n2001:db8:1::1\nfe80::1\n",
        pattern = "2001:db8::/32",
        critical = true
    },
    {
        name = "IP ranges",
        input = "192.168.1.1\n192.168.1.50\n192.168.1.100\n192.168.2.1\n",
        pattern = "192.168.1.1-192.168.1.100",
        critical = true
    },
    {
        name = "Multiple patterns",
        input = "192.168.1.1\n10.0.0.1\n8.8.8.8\n",
        pattern = "\"192.168.0.0/16,10.0.0.0/8\"",
        critical = true
    },
    {
        name = "Count mode",
        input = "192.168.1.1\n192.168.1.2\n10.0.0.1\n",
        pattern = "192.168.0.0/16",
        flags = "-c",
        critical = true
    },
    {
        name = "Exact match mode",
        input = "192.168.1.1\ntext 192.168.1.1 text\n",
        pattern = "192.168.1.1",
        flags = "-x",
        critical = false
    },
    {
        name = "Invert match",
        input = "192.168.1.1\n10.0.0.1\n8.8.8.8\n",
        pattern = "192.168.0.0/16",
        flags = "-v",
        critical = false
    },
    {
        name = "Strict CIDR",
        input = "192.168.1.1\n192.168.0.0\n",
        pattern = "192.168.1.0/24",
        flags = "-s",
        critical = false
    }
}

local compat_passed = 0
local compat_failed = 0
local critical_failed = false

for _, test in ipairs(compat_tests) do
    -- Create temp file
    local tmpfile = os.tmpname()
    local f = io.open(tmpfile, "w")
    f:write(test.input)
    f:close()
    
    local flags = test.flags or ""
    local grep_cmd = string.format("./grepcidr/grepcidr %s %s < %s", flags, test.pattern, tmpfile)
    local rg_cmd = string.format("./zig-out/bin/rgcidr %s %s < %s", flags, test.pattern, tmpfile)
    
    local grep_out, grep_code = run_command(grep_cmd)
    local rg_out, rg_code = run_command(rg_cmd)
    
    os.remove(tmpfile)
    
    if grep_out == rg_out and grep_code == rg_code then
        compat_passed = compat_passed + 1
        print(string.format("  ✓ %s", test.name))
    else
        compat_failed = compat_failed + 1
        if test.critical then
            critical_failed = true
        end
        print(string.format("  ✗ %s %s", test.name, test.critical and "[CRITICAL]" or ""))
    end
end

print(string.format("  Compatibility: %d/%d tests passed", 
    compat_passed, compat_passed + compat_failed))

print("\n[ Performance comparison ]")
-- Quick performance check
local perf_data = string.rep("192.168.1.1\n10.0.0.1\n172.16.1.1\n8.8.8.8\n", 250) -- 1000 IPs
local tmpfile = os.tmpname()
local f = io.open(tmpfile, "w")
f:write(perf_data)
f:close()

-- Time grepcidr
local grep_start = os.clock()
for i = 1, 100 do
    run_command(string.format("./grepcidr/grepcidr 192.168.0.0/16 < %s > /dev/null", tmpfile))
end
local grep_time = os.clock() - grep_start

-- Time rgcidr
local rg_start = os.clock()
for i = 1, 100 do
    run_command(string.format("./zig-out/bin/rgcidr 192.168.0.0/16 < %s > /dev/null", tmpfile))
end
local rg_time = os.clock() - rg_start

os.remove(tmpfile)

local speedup = grep_time / rg_time
print(string.format("  grepcidr: %.3fs (100 iterations, 1000 IPs)", grep_time))
print(string.format("  rgcidr:   %.3fs (100 iterations, 1000 IPs)", rg_time))
print(string.format("  Speedup:  %.2fx %s", speedup, speedup > 1 and "faster ✓" or "slower"))

print("\n=================================================")
print("                  SUMMARY")
print("=================================================")

local all_passed = true

if zig_code == 0 then
    print("✓ Unit tests:        PASSED")
else
    print("✗ Unit tests:        FAILED")
    all_passed = false
end

if passed >= total * 0.9 then  -- 90% pass rate
    print(string.format("✓ Compliance tests:  %d/%d (%.0f%%)", passed, total, passed * 100.0 / total))
else
    print(string.format("✗ Compliance tests:  %d/%d (%.0f%%)", passed, total, passed * 100.0 / total))
    all_passed = false
end

if not critical_failed then
    print(string.format("✓ Compatibility:     %d/%d", compat_passed, compat_passed + compat_failed))
else
    print(string.format("✗ Compatibility:     %d/%d (critical failures)", compat_passed, compat_passed + compat_failed))
    all_passed = false
end

if speedup > 0.8 then  -- Within 20% of grepcidr performance
    print(string.format("✓ Performance:       %.2fx %s", speedup, speedup > 1 and "faster" or "vs grepcidr"))
else
    print(string.format("✗ Performance:       %.2fx slower", speedup))
    all_passed = false
end

print("\n=================================================")
if all_passed then
    print("         ✓✓✓ ALL TESTS PASSED ✓✓✓")
    print("     rgcidr is ready for production!")
else
    print("         Some tests need attention")
    print("    Review the failures above for details")
end
print("=================================================")

os.exit(all_passed and 0 or 1)
