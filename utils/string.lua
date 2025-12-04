local M = {}

-- vim.split({s}, {sep}, {opts})
-- Splits a string by separator, preserving empty strings (blank lines)
function M.split(inputstr, sep)
	sep = sep or "%s"  -- default to whitespace
	local t = {}
	local pattern = "([^" .. sep .. "]*)" .. sep .. "?"

	-- Special handling for newline separator to preserve blank lines
	if sep == "\n" then
		local pos = 1
		while pos <= #inputstr do
			local newline_pos = inputstr:find("\n", pos, true)
			if newline_pos then
				-- Extract line (may be empty for blank lines)
				table.insert(t, inputstr:sub(pos, newline_pos - 1))
				pos = newline_pos + 1
			else
				-- Last line (no trailing newline)
				table.insert(t, inputstr:sub(pos))
				break
			end
		end
	else
		-- Original behaviour for other separators
		for str in string.gmatch(inputstr, "([^" .. sep .. "]+)") do
			table.insert(t, str)
		end
	end
	return t
end

return M
