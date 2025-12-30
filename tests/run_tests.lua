-- tests/run_tests.lua
-- Test runner for Kanban plugin tests

-- Add the project root to Lua path so modules can be required
local current_file = debug.getinfo(1, "S").source:sub(2)
local project_root = vim.fn.fnamemodify(current_file, ":p:h:h")
package.path = package.path .. ";" .. project_root .. "/?.lua"

-- Require plenary test harness with error checking
local plenary_success, plenary = pcall(require, "plenary.test_harness")
if not plenary_success then
  print("ERROR: Could not load plenary.test_harness: " .. tostring(plenary))
  return
end

-- Helper function to run a single test file in a separate Neovim process
local function run_test_file(test_file, plenary_path, project_root)
  local test_name = vim.fn.fnamemodify(test_file, ":t")

  -- Build the command to run the test in a separate Neovim process
  local cmd = string.format(
    'nvim --headless --cmd "set rtp+=%s,\\"%s\\"" -c "lua require(\'plenary.test_harness\').test_file(\'%s\')" -c "quit"',
    plenary_path,
    project_root,
    test_file
  )

  -- Execute the command and let output stream directly to terminal
  print("Running: " .. test_name)
  local exit_code = os.execute(cmd)

  -- os.execute returns 0 for success on Unix systems
  local success = exit_code == 0

  return {
    name = test_name,
    exit_code = exit_code,
    success = success
  }
end

-- Get plenary path (same logic as in run_tests.sh)
local xdg_cache = os.getenv("XDG_CACHE_HOME") or (os.getenv("HOME") .. "/Library/Caches")
local plenary_path = xdg_cache .. "/kanban-md/plenary.nvim"

-- Function to find test files tagged with #neovim-only
local function find_neovim_test_files(dir_path)
  local files = {}
  -- Use grep to find files containing #neovim-only tag
  local handle = io.popen('grep -l "#neovim-only" "' .. dir_path .. '"/**/*_spec.lua 2>/dev/null')
  if handle then
    for file in handle:lines() do
      table.insert(files, file)
    end
    handle:close()
  end
  return files
end

-- Find only Neovim-specific test files (tagged with #neovim-only)
-- All other tests now run via busted in standalone Lua
local test_files = find_neovim_test_files(project_root .. "/tests")

local results = {}
local total_tests = #test_files
local passed_tests = 0

for i, test_file in ipairs(test_files) do
  print("\n=== Running " .. vim.fn.fnamemodify(test_file, ":t") .. " (" .. i .. "/" .. total_tests .. ") ===\n")

  if vim.fn.filereadable(test_file) == 1 then
    local result = run_test_file(test_file, plenary_path, project_root)
    table.insert(results, result)

    if result.success then
      print("✓ " .. result.name .. " passed")
      passed_tests = passed_tests + 1
    else
      print("✗ " .. result.name .. " failed (exit code: " .. result.exit_code .. ")")
    end
  else
    print("ERROR: Test file not found: " .. test_file)
    table.insert(results, {
      name = vim.fn.fnamemodify(test_file, ":t"),
      exit_code = -1,
      success = false
    })
  end

  print("Finished processing test file " .. i .. "/" .. total_tests)
end

-- Print summary
print("\n" .. string.rep("=", 50))
print("TEST SUMMARY")
print(string.rep("=", 50))
print(string.format("Total tests: %d", total_tests))
print(string.format("Passed: %d", passed_tests))
print(string.format("Failed: %d", total_tests - passed_tests))

for _, result in ipairs(results) do
  local status = result.success and "✓" or "✗"
  print(string.format("%s %s", status, result.name))
end

if passed_tests == total_tests then
  print("\n🎉 All tests passed!")
else
  print(string.format("\n❌ %d test(s) failed", total_tests - passed_tests))
end
