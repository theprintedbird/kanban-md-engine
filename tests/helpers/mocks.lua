return {
  create_mock_trigger = function(name, behaviour)
    -- Returns a trigger that tracks calls
    local call_count = 0
    local call_history = {}

    local trigger = {
      name = name,
      get_call_count = function() return call_count end,
      get_call_history = function() return call_history end,
      reset = function()
        call_count = 0
        call_history = {}
      end
    }

    -- Make the trigger callable so it works with the trigger system
    -- The trigger system calls: trigger_fn(column, context)
    setmetatable(trigger, {
      __call = function(_, column_or_triggerable, context)
        call_count = call_count + 1
        table.insert(call_history, {
          timestamp = os.time(),
          context = context
        })

        if behaviour and type(behaviour) == "function" then
          return behaviour(context)
        end

        return { success = true }
      end
    })

    return trigger
  end,
  
  create_failing_trigger = function(name, error_msg)
    -- Returns a trigger that fails
    local trigger = {
      name = name
    }

    setmetatable(trigger, {
      __call = function(_, column_or_triggerable, context)
        error(error_msg or "Mock trigger failure")
      end
    })

    return trigger
  end,
  
  create_conditional_trigger = function(name, condition)
    -- Returns a trigger with conditions
    local trigger = {
      name = name,
      condition = condition
    }

    setmetatable(trigger, {
      __call = function(_, column_or_triggerable, context)
        if condition and not condition(context) then
          return { success = false, reason = "Condition not met" }
        end
        return { success = true }
      end
    })

    return trigger
  end
}