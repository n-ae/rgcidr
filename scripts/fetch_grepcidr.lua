#!/usr/bin/env lua

-- fetch_grepcidr.lua - Fetch and build the official grepcidr for benchmarking
-- Source: https://www.pc-tools.net/unix/grepcidr/

-- Configuration
local GREPCIDR_URL = "https://www.pc-tools.net/files/unix/grepcidr-2.0.tar.gz"
local GREPCIDR_VERSION = "2.0"
local TEMP_DIR = "/tmp/grepcidr-benchmark"
local GREPCIDR_ARCHIVE = TEMP_DIR .. "/grepcidr-" .. GREPCIDR_VERSION .. ".tar.gz"
local GREPCIDR_DIR = TEMP_DIR .. "/grepcidr-" .. GREPCIDR_VERSION
local GREPCIDR_BINARY = GREPCIDR_DIR .. "/grepcidr"

-- Colors for output
local colors = {
    reset = "\27[0m",
    bold = "\27[1m",
    green = "\27[32m",
    yellow = "\27[33m",
    blue = "\27[34m",
    red = "\27[31m",
    cyan = "\27[36m"
}

-- Helper functions
local function log(level, msg)
    local prefix = {
        info = colors.blue .. "[INFO]" .. colors.reset,
        success = colors.green .. "[SUCCESS]" .. colors.reset,
        warning = colors.yellow .. "[WARNING]" .. colors.reset,
        error = colors.red .. "[ERROR]" .. colors.reset
    }
    print(prefix[level] .. " " .. msg)
end

local function run_command(cmd, silent)
    if not silent then
        log("info", "Running: " .. cmd)
    end
    
    local handle = io.popen(cmd .. " 2>&1")
    local output = handle:read("*a")
    local success = handle:close()
    
    if not success and not silent then
        log("error", "Command failed: " .. cmd)
        log("error", "Output: " .. output)
    end
    
    return success, output
end

local function file_exists(path)
    local f = io.open(path, "r")
    if f then
        f:close()
        return true
    end
    return false
end

local function ensure_directory(path)
    -- Check if directory exists using test command
    local check_cmd = "test -d " .. path
    local exists = os.execute(check_cmd .. " 2>/dev/null")
    
    if not exists then
        local success = os.execute("mkdir -p " .. path .. " 2>/dev/null")
        if not success then
            log("error", "Failed to create directory: " .. path)
            return false
        end
    end
    return true
end

local function cleanup()
    log("info", "Cleaning up temporary directory...")
    os.execute("rm -rf " .. TEMP_DIR)
end

local function fetch_grepcidr()
    log("info", "Fetching official grepcidr " .. GREPCIDR_VERSION .. " from pc-tools.net...")
    
    -- Create temp directory
    if not ensure_directory(TEMP_DIR) then
        return false
    end
    
    -- Download archive
    local download_cmd = string.format("curl -L -o %s %s", GREPCIDR_ARCHIVE, GREPCIDR_URL)
    local success, output = run_command(download_cmd)
    
    if not success then
        log("error", "Failed to download grepcidr")
        return false
    end
    
    if not file_exists(GREPCIDR_ARCHIVE) then
        log("error", "Downloaded file not found: " .. GREPCIDR_ARCHIVE)
        return false
    end
    
    log("success", "Downloaded grepcidr archive")
    return true
end

local function extract_archive()
    log("info", "Extracting archive...")
    
    local extract_cmd = string.format("cd %s && tar -xzf %s", TEMP_DIR, GREPCIDR_ARCHIVE)
    local success = run_command(extract_cmd)
    
    if not success then
        log("error", "Failed to extract archive")
        return false
    end
    
    -- Check if extracted directory exists
    local check_cmd = "test -d " .. GREPCIDR_DIR
    if not os.execute(check_cmd .. " 2>/dev/null") then
        log("error", "Extracted directory not found: " .. GREPCIDR_DIR)
        return false
    end
    
    log("success", "Extracted grepcidr source")
    return true
end

local function build_grepcidr()
    log("info", "Building grepcidr...")
    
    -- Build with optimizations (as recommended by the Makefile)
    local build_cmd = string.format("cd %s && make clean && make CFLAGS='-O3'", GREPCIDR_DIR)
    local success, output = run_command(build_cmd)
    
    if not success then
        log("error", "Failed to build grepcidr")
        log("error", "Build output: " .. output)
        return false
    end
    
    if not file_exists(GREPCIDR_BINARY) then
        log("error", "Built binary not found: " .. GREPCIDR_BINARY)
        return false
    end
    
    -- Test the binary (grepcidr -V returns exit code 2 even on success)
    local handle = io.popen(GREPCIDR_BINARY .. " -V 2>&1")
    local version = handle:read("*a")
    handle:close()  -- Ignore exit code
    
    if version and version:match("grepcidr") then
        log("success", "Built grepcidr successfully: " .. version:gsub("\n", ""))
    else
        log("error", "Built binary doesn't work properly")
        return false
    end
    
    return true
end

local function get_grepcidr_path()
    -- Check if already built
    if file_exists(GREPCIDR_BINARY) then
        -- Test if binary works (grepcidr -V returns exit code 2 even on success)
        local handle = io.popen(GREPCIDR_BINARY .. " -V 2>&1")
        local version = handle:read("*a")
        handle:close()
        
        if version and version:match("grepcidr") then
            return GREPCIDR_BINARY
        end
    end
    
    -- Otherwise, fetch and build
    if not fetch_grepcidr() then
        return nil
    end
    
    if not extract_archive() then
        cleanup()
        return nil
    end
    
    if not build_grepcidr() then
        cleanup()
        return nil
    end
    
    return GREPCIDR_BINARY
end

-- Main function
local function main(args)
    local action = args[1] or "get"
    
    if action == "clean" then
        cleanup()
        log("success", "Cleaned up temporary files")
        return 0
    elseif action == "get" then
        local path = get_grepcidr_path()
        if path then
            print(path)  -- Output just the path for scripts to use
            return 0
        else
            log("error", "Failed to get grepcidr binary")
            return 1
        end
    elseif action == "info" then
        log("info", "Official grepcidr source: " .. GREPCIDR_URL)
        log("info", "Version: " .. GREPCIDR_VERSION)
        log("info", "Temporary directory: " .. TEMP_DIR)
        log("info", "Binary path (when built): " .. GREPCIDR_BINARY)
        
        if file_exists(GREPCIDR_BINARY) then
            local handle = io.popen(GREPCIDR_BINARY .. " -V 2>&1")
            local version = handle:read("*a")
            handle:close()
            if version and version:match("grepcidr") then
                log("success", "Binary is available: " .. version:gsub("\n", ""))
            end
        else
            log("warning", "Binary not yet built (run without arguments to build)")
        end
        return 0
    else
        print("Usage: " .. arg[0] .. " [get|clean|info]")
        print("  get   - Get path to grepcidr binary (fetches and builds if needed)")
        print("  clean - Remove temporary files")
        print("  info  - Show information about grepcidr source and status")
        return 1
    end
end

-- Run if executed directly
if arg and arg[0]:match("fetch_grepcidr%.lua$") then
    os.exit(main(arg))
end

-- Export for use as module
return {
    get_grepcidr_path = get_grepcidr_path,
    cleanup = cleanup,
    GREPCIDR_URL = GREPCIDR_URL,
    GREPCIDR_VERSION = GREPCIDR_VERSION
}
