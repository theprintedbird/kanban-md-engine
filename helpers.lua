local M = {}

-- Simple ID generation based on text hash and timestamp
function M.generate_id(task)
	if not task.properties.id then
		local id_source = task.text .. os.time()
		local hash = 0
		for i = 1, #id_source do
			hash = (hash * 31 + string.byte(id_source, i)) % 0x100000000
		end
		task.properties.id = string.format("%08x", hash)
	end
	return task
end

return M
