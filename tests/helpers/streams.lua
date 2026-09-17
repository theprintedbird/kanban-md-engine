-- tests/helpers/streams.lua
-- Capture what a test writes to stderr (the CLI adapter's notifications) so it
-- can be asserted rather than printed into the middle of the run.
--
-- Usage:
--
--   local streams = require('helpers.streams')
--   local stderr
--
--   before_each(function() stderr = streams.capture_stderr() end)
--   after_each(function() stderr.restore() end)
--
--   it("notifies", function()
--     CLIAdapter:write_buffer({ "x" }, { file = path })
--     assert.matches("Wrote 1 lines", stderr.output())
--   end)
--
-- restore() is idempotent, so calling it from after_each is safe even when the
-- test body restored it already.

local M = {}

--- Redirect io.stderr into a buffer.
--- @return table handle with output() and restore()
function M.capture_stderr()
  local real_stderr = io.stderr
  local written = {}

  io.stderr = {
    write = function(_, text)
      table.insert(written, text)
      return io.stderr
    end,
    flush = function() end,
  }

  return {
    --- Everything written to stderr so far, as one string.
    output = function()
      return table.concat(written)
    end,

    --- Put the real stderr back.
    restore = function()
      io.stderr = real_stderr
    end,
  }
end

return M
