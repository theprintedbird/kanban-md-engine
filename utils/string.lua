local M = {}

-- vim.split({s}, {sep}, {opts})
function M.split(inputstr, sep)
	sep = sep or "%s"  -- default to whitespace
	local t = {}
	for str in string.gmatch(inputstr, "([^" .. sep .. "]+)") do
		table.insert(t, str)
	end
	return t
end

return M
