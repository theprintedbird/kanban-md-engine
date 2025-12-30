local M = {}

--- @param table table Table to check
function M.isEmpty(table)
	if type(table) ~= 'table' then return table end
	local next = next
	if next(table) == nil then
		-- table is empty
		return true
	else
		return false
	end
end

--- @param table table Table to extract keys from
function M.keys(table)
	if type(table) ~= 'table' then return table end
	local keyset = {}
	for k,v in pairs(table) do
		keyset[#keyset + 1] = k
	end
	return keyset
end

-- https://gist.github.com/tylerneylon/81333721109155b2d244?permalink_comment_id=3262222#gistcomment-3262222
--- @param table table Table to copy
function M.deepcopy(table, seen)
	-- Handle non-tables and previously-seen tables.
	if type(table) ~= 'table' then return table end
	if seen and seen[table] then return seen[table] end

	-- New table; mark it as seen and copy recursively.
	local s = seen or {}
	local res = {}
	s[table] = res
	for k, v in next, table do res[M.deepcopy(k, s)] = M.deepcopy(v, s) end
	return setmetatable(res, getmetatable(table))
end

--- Deep merge tables together
--- Later tables take precedence over earlier ones
--- @param ... table Tables to merge
--- @return table Merged table
function M.extend(...)
	local result = {}
	local tables = {...}

	for _, tbl in ipairs(tables) do
		if type(tbl) == 'table' then
			for k, v in pairs(tbl) do
				if type(v) == 'table' and type(result[k]) == 'table' then
					-- Recursively merge nested tables
					result[k] = M.extend(result[k], v)
				else
					-- Overwrite with new value
					result[k] = v
				end
			end
		end
	end

	return result
end

return M
