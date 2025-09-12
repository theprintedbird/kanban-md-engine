-- Trigger system with dynamic function registration

-- | Trigger_				| Default triggers						| Arguments	|
-- |----------------|-----------------------------|-----------|
-- |card_created		| Add column timestamp				| task			|
-- |								| Assign ID										| task			|
-- |card_moved			| Add column timestamp				| task			|
-- |								| Check WIP limits						| task			|
-- |								| Check transition rules			| task			|
-- |card_completed	| Add column timestamp				| task			|
-- |card_archived		| Add column timestamp				| task			|
-- |card_deleted		| Soft delete, then hard			| task			|
-- |board_opened		| Calculate and display stats	| board			|
-- |board_saved			| Update statistics						| board			|
-- |								| Validate WIP limits					| board			|
-- |card_blocked		| Add blocker property				| task			|
-- |card_prioritised| Reorder within column				| task			|
-- |card_estimated	| Add/update complexity				| task			|
-- |card_tagged			| Add tags for filtering			| task			|

local M = {}
local triggers = {}

function M.register_trigger(trigger_name, function_name, func)
	-- Create trigger table if it doesn't exist
	if not triggers[trigger_name] then
		triggers[trigger_name] = {}
		-- print("Created new trigger_: " .. trigger_name)
	end

	-- Add the specific function
	triggers[trigger_name][function_name] = func
	-- print("Registered function '" .. function_name .. "' to trigger '" .. trigger_name .. "'")
end

-- Alternative: register multiple functions at once (merging, not replacing)
function M.register_trigger_functions(trigger_name, functions)
	-- Create trigger table if it doesn't exist
	if not triggers[trigger_name] then
		triggers[trigger_name] = {}
		-- print("Created new trigger_: " .. trigger_name)
	end

	-- Merge the new functions with existing ones
	for funcName, func in pairs(functions) do
		triggers[trigger_name][funcName] = func
		-- print("Registered function '" .. funcName .. "' to trigger '" .. trigger_name .. "'")
	end
end

function M.call_trigger(trigger_name, function_name, ...)
	local trigger = triggers[trigger_name]
	if not trigger then
		error("trigger not found: " .. trigger_name)
	end

	local func = trigger[function_name]
	if not func then
		error("Function not found: " .. function_name .. " in trigger " .. trigger_name)
	end

	return func(...)
end

-- Call all functions in a trigger with the same arguments
-- Usage
-- local mathResults = call_all_trigger_functions("math", 5)
-- for funcName, result in pairs(mathResults) do
--     print(funcName .. "(5) =", result)
-- end
-- Output:
-- factorial(5) = 120
-- fibonacci(5) = 5
-- isPrime(5) = false
function M.call_all_trigger_functions(trigger_name, ...)
	local trigger = triggers[trigger_name]
	if not trigger then
		error("trigger not found: " .. trigger_name)
	end

	local results = {}
	for funcName, func in pairs(trigger) do
		local success, result = pcall(func, ...)
		if success then
			results[funcName] = result
		else
			results[funcName] = "Error: " .. result
		end
	end

	return results
end

-- Call all functions with different arguments for each
-- Usage with different arguments per function
-- local mathArgs = {
--     factorial = {6},
--     fibonacci = {10},
--     isPrime = {17}
-- }
--
-- local results = call_all_trigger_functionsWithArgs("math", mathArgs)
-- for funcName, result in pairs(results) do
--     print(funcName .. " =", result)
-- end
-- Output:
-- factorial = 720
-- fibonacci = 55
-- isPrime = true
function M.call_all_trigger_functionsWithArgs(trigger_name, argsTable)
	local trigger = triggers[trigger_name]
	if not trigger then
		error("trigger not found: " .. trigger_name)
	end

	local results = {}
	for funcName, func in pairs(trigger) do
		local args = argsTable[funcName]
		if args then
			local success, result = pcall(func, table.unpack(args))
			if success then
				results[funcName] = result
			else
				results[funcName] = "Error: " .. result
			end
		else
			results[funcName] = "No arguments provided"
		end
	end

	return results
end

-- Call all functions and process results with a callback
-- Usage with custom processing
-- print("Processing all math functions with input 7:")
-- process_all_trigger_functions("math", function(funcName, result, input, errorMsg)
--     if errorMsg then
--         print("❌ " .. funcName .. "(" .. input .. ") failed: " .. errorMsg)
--     else
--         print("✅ " .. funcName .. "(" .. input .. ") = " .. result)
--     end
-- end, 7)
function M.process_all_trigger_functions(trigger_name, processor, ...)
	local trigger = triggers[trigger_name]
	if not trigger then
		error("trigger not found: " .. trigger_name)
	end

	for funcName, func in pairs(trigger) do
		local success, result = pcall(func, ...)
		if success then
			processor(funcName, result, ...)
		else
			processor(funcName, nil, ..., "Error: " .. result)
		end
	end
end

-- Call only functions that match a pattern or condition
-- Usage examples
-- print("\nCalling functions that start with 'f':")
-- local fibFactResults = call_matching_trigger_functions("math", "^f", 6)
-- for funcName, result in pairs(fibFactResults) do
--     print(funcName .. "(6) =", result)
-- end
--
-- print("\nCalling only specific functions:")
-- local specificResults = call_matching_trigger_functions("math", {"factorial", "isPrime"}, 11)
-- for funcName, result in pairs(specificResults) do
--     print(funcName .. "(11) =", result)
-- end
--
-- print("\nCalling functions based on custom logic:")
-- local customResults = call_matching_trigger_functions("math", function(name, func)
--     return string.len(name) > 7  -- Only functions with names longer than 7 chars
-- end, 4)
-- for funcName, result in pairs(customResults) do
--     print(funcName .. "(4) =", result)
-- end
function M.call_matching_trigger_functions(trigger_name, filter, ...)
	local trigger = triggers[trigger_name]
	if not trigger then
		error("trigger not found: " .. trigger_name)
	end

	local results = {}
	for funcName, func in pairs(trigger) do
		-- Filter can be a pattern, a function_, or a table of names
		local shouldCall = false

		if type(filter) == "string" then
			-- Pattern matching
			shouldCall = string.match(funcName, filter) ~= nil
		elseif type(filter) == "function" then
			-- Custom filter function
			shouldCall = filter(funcName, func)
		elseif type(filter) == "table" then
			-- List of function names
			for _, name in ipairs(filter) do
				if name == funcName then
					shouldCall = true
					break
				end
			end
		end

		if shouldCall then
			local success, result = pcall(func, ...)
			if success then
				results[funcName] = result
			else
				results[funcName] = "Error: " .. result
			end
		end
	end

	return results
end

-- Add a helper to show all available functions
-- Usage demonstration
-- print("Available math functions:", table.concat(get_trigger_functions("math"), ", "))
--
-- print("\n=== Calling all math functions with same input ===")
-- local allResults = call_all_trigger_functions("math", 8)
-- for funcName, result in pairs(allResults) do
--     print(string.format("%-10s = %s", funcName, tostring(result)))
-- end
--
-- print("\n=== Calling with different inputs per function ===")
-- local customArgs = {
--     factorial = {5},
--     fibonacci = {12},
--     isPrime = {29}
-- }
-- local customResults = call_all_trigger_functionsWithArgs("math", customArgs)
-- for funcName, result in pairs(customResults) do
--     print(string.format("%-10s = %s", funcName, tostring(result)))
-- end
function M.get_trigger_functions(trigger_name)
	local trigger = triggers[trigger_name]
	if not trigger then
		return nil
	end

	local functions = {}
	for funcName, _ in pairs(trigger) do
		table.insert(functions, funcName)
	end
	table.sort(functions)  -- Sort alphabetically
	return functions
end


function M.list_triggers()
	for trigger_name, functions in pairs(triggers) do
		print("trigger '" .. trigger_name .. "':")
		for funcName, _ in pairs(functions) do
			print("  - " .. funcName)
		end
	end
end


return M
