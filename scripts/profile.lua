#!/usr/bin/env lua
-- profile.lua : simple end-to-end performance profile for rgcidr
-- Measures user+sys time via the 'time' command and prints RSS.
-- Usage: lua scripts/profile.lua [file] [pattern]

local infile = arg[1] or "tests/data/test_input.txt"
local pattern = arg[2] or "192.168.0.0/16"

print("Building rgcidr ...")
os.execute("zig build -Doptimize=ReleaseFast --summary all > /dev/null")

local exe = "./zig-out/bin/rgcidr"
print(string.format("Profiling: %s %s %s", exe, pattern, infile))

-- Use /usr/bin/time for portability on macOS
local cmd = string.format("/usr/bin/time -l %s %s %s > /dev/null", exe, pattern, infile)
os.execute(cmd)
