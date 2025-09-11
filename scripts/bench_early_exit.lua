#!/usr/bin/env lua
-- bench_early_exit.lua : quick micro-benchmark for rgcidr early-exit scan
-- Usage: lua scripts/bench_early_exit.lua [count]
-- It builds rgcidr (if needed) and runs the binary COUNT times over a small dataset

local COUNT = tonumber(arg[1] or "5")

print("Building rgcidr ...")
os.execute("zig build -Doptimize=ReleaseFast --summary all > /dev/null")

local exe = "./zig-out/bin/rgcidr"
local pattern = "192.168.0.0/16"
local infile = "tests/data/test_input.txt"

print(string.format("Running %d iterations ...", COUNT))
local t0 = os.clock()
for i=1,COUNT do
  os.execute(string.format("%s %s %s > /dev/null", exe, pattern, infile))
end
local dt = os.clock()-t0
local dt_us = dt * 1000000
local avg_us = dt_us / COUNT
print(string.format("Total time: %.1fμs/op (%.3fs total, %d runs)", avg_us, dt, COUNT))

