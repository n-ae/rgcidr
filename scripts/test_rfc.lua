#!/usr/bin/env lua

-- RFC Compliance Test Suite for rgcidr
-- Tests adherence to RFC standards for IP addressing and CIDR notation

print("=== RFC Compliance Test Suite ===\n")

local function run_command(cmd)
    local handle = io.popen(cmd .. " 2>&1")
    local result = handle:read("*a")
    local success, exit_type, code = handle:close()
    return result, code or 0
end

local function test_pattern(name, input, pattern, expected_output, rfc)
    local tmpfile = os.tmpname()
    local f = io.open(tmpfile, "w")
    f:write(input)
    f:close()
    
    local cmd = string.format("./zig-out/bin/rgcidr %s < %s", pattern, tmpfile)
    local output, code = run_command(cmd)
    os.remove(tmpfile)
    
    -- Normalize line endings
    output = output:gsub("\r\n", "\n"):gsub("\r", "\n")
    expected_output = expected_output:gsub("\r\n", "\n"):gsub("\r", "\n")
    
    if output == expected_output then
        print(string.format("✓ %s (%s)", name, rfc))
        return true
    else
        print(string.format("✗ %s (%s)", name, rfc))
        print("  Expected:")
        for line in expected_output:gmatch("[^\n]+") do
            print("    " .. line)
        end
        print("  Got:")
        for line in output:gmatch("[^\n]+") do
            print("    " .. line)
        end
        return false
    end
end

local tests = {
    -- RFC 791: IPv4 Address Format
    {
        name = "RFC 791: Valid IPv4 addresses",
        rfc = "RFC 791 §3.2",
        input = "192.168.1.1\n10.0.0.1\n172.16.0.1\n127.0.0.1\n255.255.255.255\n0.0.0.0\n",
        pattern = "0.0.0.0/0",
        expected = "192.168.1.1\n10.0.0.1\n172.16.0.1\n127.0.0.1\n255.255.255.255\n0.0.0.0\n"
    },
    
    -- RFC 4632: CIDR for IPv4
    {
        name = "RFC 4632: IPv4 CIDR /8",
        rfc = "RFC 4632 §3",
        input = "10.0.0.1\n10.255.255.254\n11.0.0.1\n9.255.255.255\n",
        pattern = "10.0.0.0/8",
        expected = "10.0.0.1\n10.255.255.254\n"
    },
    {
        name = "RFC 4632: IPv4 CIDR /16",
        rfc = "RFC 4632 §3",
        input = "192.168.0.1\n192.168.255.254\n192.169.0.1\n192.167.255.255\n",
        pattern = "192.168.0.0/16",
        expected = "192.168.0.1\n192.168.255.254\n"
    },
    {
        name = "RFC 4632: IPv4 CIDR /24",
        rfc = "RFC 4632 §3",
        input = "192.168.1.1\n192.168.1.254\n192.168.2.1\n192.168.0.255\n",
        pattern = "192.168.1.0/24",
        expected = "192.168.1.1\n192.168.1.254\n"
    },
    {
        name = "RFC 4632: IPv4 CIDR /32 (host)",
        rfc = "RFC 4632 §3",
        input = "192.168.1.1\n192.168.1.2\n",
        pattern = "192.168.1.1/32",
        expected = "192.168.1.1\n"
    },
    
    -- RFC 4291: IPv6 Address Format
    {
        name = "RFC 4291: Valid IPv6 addresses",
        rfc = "RFC 4291 §2.2",
        input = "2001:db8::1\n2001:db8:85a3::8a2e:370:7334\nfe80::1\n::1\n::\nff02::1\n",
        pattern = "::/0",
        expected = "2001:db8::1\n2001:db8:85a3::8a2e:370:7334\nfe80::1\n::1\n::\nff02::1\n"
    },
    {
        name = "RFC 4291: IPv6 loopback",
        rfc = "RFC 4291 §2.5.3",
        input = "::1\n::2\n127.0.0.1\n",
        pattern = "::1/128",
        expected = "::1\n"
    },
    {
        name = "RFC 4291: IPv6 unspecified",
        rfc = "RFC 4291 §2.5.2",
        input = "::\n::1\n0.0.0.0\n",
        pattern = "::/128",
        expected = "::\n"
    },
    {
        name = "RFC 4291: IPv6 link-local",
        rfc = "RFC 4291 §2.5.6",
        input = "fe80::1\nfe80::1234:5678:90ab:cdef\nfec0::1\n2001:db8::1\n",
        pattern = "fe80::/10",
        expected = "fe80::1\nfe80::1234:5678:90ab:cdef\n"
    },
    {
        name = "RFC 4291: IPv6 multicast",
        rfc = "RFC 4291 §2.7",
        input = "ff02::1\nff05::1:3\nfe80::1\n2001:db8::1\n",
        pattern = "ff00::/8",
        expected = "ff02::1\nff05::1:3\n"
    },
    
    -- RFC 4291: IPv6 with embedded IPv4
    {
        name = "RFC 4291: IPv6 with embedded IPv4",
        rfc = "RFC 4291 §2.5.5",
        input = "::192.168.1.1\n::ffff:192.168.1.1\n2001:db8::192.168.1.1\n",
        pattern = "::/0",
        expected = "::192.168.1.1\n::ffff:192.168.1.1\n2001:db8::192.168.1.1\n"
    },
    
    -- RFC 5952: IPv6 Text Representation
    {
        name = "RFC 5952: Compressed zeros",
        rfc = "RFC 5952 §4.2",
        input = "2001:db8:0:0:0:0:0:1\n2001:db8::1\n",
        pattern = "2001:db8::1/128",
        expected = "2001:db8:0:0:0:0:0:1\n2001:db8::1\n"  -- Both forms match (same address)
    },
    {
        name = "RFC 5952: Leading zeros",
        rfc = "RFC 5952 §4.1",
        input = "2001:0db8:0000:0000:0000:0000:0000:0001\n2001:db8::1\n",
        pattern = "2001:db8::/32",
        expected = "2001:0db8:0000:0000:0000:0000:0000:0001\n2001:db8::1\n"
    },
    
    -- CIDR boundary tests
    {
        name = "RFC 4632: CIDR /0 (all IPv4)",
        rfc = "RFC 4632",
        input = "0.0.0.0\n127.0.0.1\n255.255.255.255\n",
        pattern = "0.0.0.0/0",
        expected = "0.0.0.0\n127.0.0.1\n255.255.255.255\n"
    },
    {
        name = "RFC 4291: CIDR /0 (all IPv6)",
        rfc = "RFC 4291",
        input = "::\n::1\n2001:db8::1\nffff:ffff:ffff:ffff:ffff:ffff:ffff:ffff\n",
        pattern = "::/0",
        expected = "::\n::1\n2001:db8::1\nffff:ffff:ffff:ffff:ffff:ffff:ffff:ffff\n"
    },
    
    -- Private address ranges (RFC 1918)
    {
        name = "RFC 1918: Private IPv4 Class A",
        rfc = "RFC 1918",
        input = "10.0.0.1\n10.255.255.254\n11.0.0.1\n",
        pattern = "10.0.0.0/8",
        expected = "10.0.0.1\n10.255.255.254\n"
    },
    {
        name = "RFC 1918: Private IPv4 Class B",
        rfc = "RFC 1918",
        input = "172.16.0.1\n172.31.255.254\n172.32.0.1\n172.15.255.255\n",
        pattern = "172.16.0.0/12",
        expected = "172.16.0.1\n172.31.255.254\n"
    },
    {
        name = "RFC 1918: Private IPv4 Class C",
        rfc = "RFC 1918",
        input = "192.168.0.1\n192.168.255.254\n192.169.0.1\n",
        pattern = "192.168.0.0/16",
        expected = "192.168.0.1\n192.168.255.254\n"
    },
    
    -- Edge cases that should NOT match
    {
        name = "Invalid: Malformed IPv4",
        rfc = "RFC 791",
        input = "192.168.1.256\n192.168.1\n192.168.1.1.1\n",
        pattern = "192.168.0.0/16",
        expected = ""
    },
    {
        name = "Invalid: Malformed IPv6",
        rfc = "RFC 4291",
        input = "2001:db8::gggg\n2001:db8::1::2\n2001:db8:1text\n",
        pattern = "2001:db8::/32",
        expected = ""
    },
    
    -- Special addresses
    {
        name = "RFC 1122: Loopback range",
        rfc = "RFC 1122",
        input = "127.0.0.1\n127.0.0.2\n127.255.255.254\n128.0.0.1\n",
        pattern = "127.0.0.0/8",
        expected = "127.0.0.1\n127.0.0.2\n127.255.255.254\n"
    },
    {
        name = "RFC 5735: Documentation addresses",
        rfc = "RFC 5735",
        input = "192.0.2.1\n198.51.100.1\n203.0.113.1\n192.0.1.1\n",
        pattern = "192.0.2.0/24,198.51.100.0/24,203.0.113.0/24",
        expected = "192.0.2.1\n198.51.100.1\n203.0.113.1\n"
    },
    {
        name = "RFC 3927: Link-local IPv4",
        rfc = "RFC 3927",
        input = "169.254.0.1\n169.254.255.254\n169.253.255.255\n169.255.0.1\n",
        pattern = "169.254.0.0/16",
        expected = "169.254.0.1\n169.254.255.254\n"
    },
}

-- Run all tests
local passed = 0
local failed = 0

for _, test in ipairs(tests) do
    if test_pattern(test.name, test.input, test.pattern, test.expected, test.rfc) then
        passed = passed + 1
    else
        failed = failed + 1
    end
end

-- Summary
print("\n=== RFC Compliance Summary ===")
print(string.format("Total tests: %d", passed + failed))
print(string.format("Passed: %d", passed))
print(string.format("Failed: %d", failed))
print(string.format("Compliance rate: %.1f%%", passed * 100.0 / (passed + failed)))

if failed == 0 then
    print("\n✓ Full RFC compliance achieved!")
else
    print("\n✗ Some RFC compliance issues detected")
end

os.exit(failed == 0 and 0 or 1)
