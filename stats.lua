local M = {}

-- Calculate cycle time using first and last timestamps chronologically
-- @param task_properties table: Task properties containing timestamp fields
-- @return number|nil: Cycle time in seconds, or nil if insufficient timestamps
function M.calculate_cycle_time(task_properties)
	-- Known timestamp properties in chronological order
	local timestamp_keys = {"created", "ready", "started", "done", "archived"}
	local timestamps = {}
	
	-- Collect all existing timestamps
	for _, key in ipairs(timestamp_keys) do
		if task_properties[key] then
			table.insert(timestamps, {key = key, value = task_properties[key]})
		end
	end
	
	-- Need at least 2 timestamps for cycle time
	if #timestamps < 2 then
		return nil
	end
	
	-- Sort by timestamp value (chronological order)
	table.sort(timestamps, function(a, b) return a.value < b.value end)
	
	-- Return difference between first and last timestamps
	return timestamps[#timestamps].value - timestamps[1].value
end

return M