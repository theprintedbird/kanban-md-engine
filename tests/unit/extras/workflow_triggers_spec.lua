-- tests/unit/extras/workflow_triggers_spec.lua
-- Unit tests for lua/kanban-md/extras/workflow_triggers.lua
--
-- Every function here is a factory returning an on_checking execute_fn of the
-- shape execute_fn(column, context). The triggers are pure with respect to the
-- context they are handed, so they are exercised directly with a hand-built
-- context rather than through a whole board move -- the point is the rule, not
-- the plumbing that delivers it.
--
-- Two result conventions are in play, and that is deliberate on the module's
-- part: the four business-rule triggers return the bare
-- (ok, error_message, warning_message) tuple, while create_workflow_rules_trigger
-- returns a Triggerable result table.
require('polyfills.vim')

local workflow_triggers = require('kanban-md.extras.workflow_triggers')

local HOUR = 3600

--- Build an on_checking context for a move between two named columns.
--- @param opts table|nil {properties, source, target, target_config, timestamp, columns}
local function make_context(opts)
  opts = opts or {}

  local source = { name = opts.source or "In Progress", config = {} }
  local target = { name = opts.target or "Done", config = opts.target_config or {} }

  return {
    card = { properties = opts.properties or {} },
    source_column = opts.source == false and nil or source,
    target_column = target,
    target_column_name = target.name,
    timestamp = opts.timestamp,
    board = { columns = opts.columns or { source, target }, config = {} },
  }
end

describe("workflow_triggers", function()
  describe("create_sla_compliance_trigger", function()
    it("passes a card with no SLA and no default", function()
      local trigger = workflow_triggers.create_sla_compliance_trigger({})

      local ok, err, warning = trigger(nil, make_context())

      assert.is_true(ok)
      assert.is_nil(err)
      assert.is_nil(warning)
    end)

    it("warns when a card completes after the SLA deadline", function()
      local trigger = workflow_triggers.create_sla_compliance_trigger({})
      local now = os.time()
      local context = make_context({
        target_config = { is_completion_state = true },
        timestamp = now,
        properties = {
          sla = { completion_hours = 24 },
          in_progress = now - 48 * HOUR,
        },
      })

      local ok, err, warning = trigger(nil, context)

      -- A breach is reported as a warning, not a refusal: the move still goes
      -- through.
      assert.is_true(ok)
      assert.is_nil(err)
      assert.matches("completed after SLA deadline: 48%.0 hours %(limit: 24 hours%)", warning)
    end)

    it("stays quiet when completion is inside the deadline", function()
      local trigger = workflow_triggers.create_sla_compliance_trigger({})
      local now = os.time()
      local context = make_context({
        target_config = { is_completion_state = true },
        timestamp = now,
        properties = {
          sla = { completion_hours = 24 },
          in_progress = now - 2 * HOUR,
        },
      })

      local ok, _, warning = trigger(nil, context)

      assert.is_true(ok)
      assert.is_nil(warning)
    end)

    it("falls back to the configured default SLA", function()
      local trigger = workflow_triggers.create_sla_compliance_trigger({
        default_sla = { completion_hours = 1 },
      })
      local now = os.time()
      local context = make_context({
        target_config = { is_completion_state = true },
        timestamp = now,
        properties = { in_progress = now - 5 * HOUR },
      })

      local _, _, warning = trigger(nil, context)

      assert.matches("limit: 1 hours", warning)
    end)

    it("prefers the card's own SLA over the default", function()
      local trigger = workflow_triggers.create_sla_compliance_trigger({
        default_sla = { completion_hours = 1 },
      })
      local now = os.time()
      local context = make_context({
        target_config = { is_completion_state = true },
        timestamp = now,
        properties = {
          sla = { completion_hours = 100 },
          in_progress = now - 5 * HOUR,
        },
      })

      local _, _, warning = trigger(nil, context)

      assert.is_nil(warning)
    end)

    it("treats __ARCHIVE__ as a completion target", function()
      local trigger = workflow_triggers.create_sla_compliance_trigger({})
      local now = os.time()
      local context = make_context({
        target = "__ARCHIVE__",
        timestamp = now,
        properties = {
          sla = { completion_hours = 1 },
          in_progress = now - 5 * HOUR,
        },
      })

      local _, _, warning = trigger(nil, context)

      assert.matches("completed after SLA deadline", warning)
    end)

    it("passes when the card has no timestamp to measure from", function()
      local trigger = workflow_triggers.create_sla_compliance_trigger({})
      local context = make_context({
        target_config = { is_completion_state = true },
        properties = { sla = { completion_hours = 1 } },
      })

      local ok, _, warning = trigger(nil, context)

      assert.is_true(ok)
      assert.is_nil(warning)
    end)

    it("measures from the earliest timestamp-looking property", function()
      local trigger = workflow_triggers.create_sla_compliance_trigger({})
      local now = os.time()
      local context = make_context({
        target_config = { is_completion_state = true },
        timestamp = now,
        properties = {
          sla = { completion_hours = 10 },
          backlog = now - 20 * HOUR,
          in_progress = now - 5 * HOUR,
          -- Not a timestamp: outside the epoch-seconds window the trigger
          -- uses to tell timestamps from ordinary numbers.
          story_points = 3,
        },
      })

      local _, _, warning = trigger(nil, context)

      assert.matches("20%.0 hours", warning)
    end)

    it("warns when a card has sat in a column past max_column_hours", function()
      local trigger = workflow_triggers.create_sla_compliance_trigger({})
      local now = os.time()
      local context = make_context({
        timestamp = now,
        properties = {
          sla = { completion_hours = 1000, max_column_hours = 4 },
          started = now - 9 * HOUR,
        },
      })

      local ok, _, warning = trigger(nil, context)

      assert.is_true(ok)
      assert.matches("in column too long: 9%.0 hours %(limit: 4 hours%)", warning)
    end)
  end)

  describe("create_business_hours_trigger", function()
    -- A Wednesday at 11:00 and the same day at 20:00, taken through os.time so
    -- the trigger's os.date("*t", ...) reads them back in the same local zone.
    local function local_time(hour, day)
      return os.time({ year = 2026, month = 9, day = day or 16, hour = hour, min = 0, sec = 0 })
    end

    local config = { restricted_columns = { "^Done$", "Release" } }

    it("allows transitions to unrestricted columns at any hour", function()
      local trigger = workflow_triggers.create_business_hours_trigger(config)

      local ok, err = trigger(nil, make_context({ target = "In Review", timestamp = local_time(3) }))

      assert.is_true(ok)
      assert.is_nil(err)
    end)

    it("allows a restricted transition during business hours", function()
      local trigger = workflow_triggers.create_business_hours_trigger(config)

      assert.is_true(trigger(nil, make_context({ target = "Done", timestamp = local_time(11) })))
    end)

    it("refuses a restricted transition outside business hours", function()
      local trigger = workflow_triggers.create_business_hours_trigger(config)

      local ok, err = trigger(nil, make_context({ target = "Done", timestamp = local_time(20) }))

      assert.is_false(ok)
      assert.matches("only allowed during business hours %(9:00%-17:00%)", err)
    end)

    it("honours configured start and end hours", function()
      local trigger = workflow_triggers.create_business_hours_trigger({
        restricted_columns = { "^Done$" },
        start_hour = 6,
        end_hour = 22,
      })

      local ok = trigger(nil, make_context({ target = "Done", timestamp = local_time(20) }))

      assert.is_true(ok)
    end)

    it("refuses restricted transitions at the weekend", function()
      local trigger = workflow_triggers.create_business_hours_trigger(config)
      -- 2026-09-19 is a Saturday; 2026-09-20 a Sunday.
      for _, day in ipairs({ 19, 20 }) do
        local ok, err = trigger(nil, make_context({
          target = "Done",
          timestamp = local_time(11, day),
        }))

        assert.is_false(ok)
        assert.matches("not allowed on weekends", err)
      end
    end)

    it("matches restricted columns as Lua patterns", function()
      local trigger = workflow_triggers.create_business_hours_trigger(config)

      local ok, err = trigger(nil, make_context({
        target = "Release Candidate",
        timestamp = local_time(20),
      }))

      assert.is_false(ok)
      assert.matches("Release Candidate", err)
    end)

    it("treats a missing restricted_columns list as no restrictions", function()
      local trigger = workflow_triggers.create_business_hours_trigger({})

      assert.is_true(trigger(nil, make_context({ target = "Done", timestamp = local_time(3) })))
    end)
  end)

  describe("create_priority_workflow_trigger", function()
    local workflows = {
      urgent = {
        ["In Progress"] = { "Done", "Blocked" },
      },
    }

    it("allows a priority whose workflow is not described", function()
      local trigger = workflow_triggers.create_priority_workflow_trigger(workflows)

      assert.is_true(trigger(nil, make_context({ properties = { priority = "low" } })))
    end)

    it("treats a card with no priority as 'normal'", function()
      local trigger = workflow_triggers.create_priority_workflow_trigger({
        normal = { ["In Progress"] = { "Blocked" } },
      })

      local ok, err = trigger(nil, make_context())

      assert.is_false(ok)
      assert.matches("Priority 'normal' tasks cannot move", err)
    end)

    it("allows a transition in the priority's allowed list", function()
      local trigger = workflow_triggers.create_priority_workflow_trigger(workflows)

      assert.is_true(trigger(nil, make_context({ properties = { priority = "urgent" } })))
    end)

    it("refuses a transition outside the allowed list", function()
      local trigger = workflow_triggers.create_priority_workflow_trigger(workflows)

      local ok, err = trigger(nil, make_context({
        properties = { priority = "urgent" },
        target = "In Review",
      }))

      assert.is_false(ok)
      assert.matches("Priority 'urgent' tasks cannot move from 'In Progress' to 'In Review'", err)
    end)

    it("allows any transition from a source column the workflow omits", function()
      local trigger = workflow_triggers.create_priority_workflow_trigger(workflows)

      assert.is_true(trigger(nil, make_context({
        properties = { priority = "urgent" },
        source = "Backlog",
        target = "In Review",
      })))
    end)
  end)

  describe("create_approval_requirement_trigger", function()
    local config = {
      columns = { ["^Done$"] = { reason = "Sign-off required before Done" } },
      authorized_approvers = { "alice", "bob" },
    }

    it("allows a transition into a column that needs no approval", function()
      local trigger = workflow_triggers.create_approval_requirement_trigger(config)

      assert.is_true(trigger(nil, make_context({ target = "In Review" })))
    end)

    it("refuses an unapproved transition, giving the configured reason", function()
      local trigger = workflow_triggers.create_approval_requirement_trigger(config)

      local ok, err = trigger(nil, make_context({ target = "Done" }))

      assert.is_false(ok)
      assert.matches("Approval required: Sign%-off required before Done", err)
    end)

    it("allows it once an authorized approver has signed off", function()
      local trigger = workflow_triggers.create_approval_requirement_trigger(config)

      assert.is_true(trigger(nil, make_context({
        target = "Done",
        properties = { approved_by = "alice" },
      })))
    end)

    it("refuses an approver who is not on the authorized list", function()
      local trigger = workflow_triggers.create_approval_requirement_trigger(config)

      local ok, err = trigger(nil, make_context({
        target = "Done",
        properties = { approved_by = "mallory" },
      }))

      assert.is_false(ok)
      assert.matches("Approver 'mallory' is not authorized", err)
      assert.matches("alice, bob", err)
    end)

    it("requires approval above the high-value threshold", function()
      local trigger = workflow_triggers.create_approval_requirement_trigger({
        high_value_threshold = 1000,
        authorized_approvers = { "alice" },
      })

      local ok, err = trigger(nil, make_context({
        target = "In Review",
        properties = { estimated_value = 2500 },
      }))

      assert.is_false(ok)
      assert.matches("High value task %(%$2500%.00%) requires approval", err)
    end)

    it("leaves a below-threshold card alone", function()
      local trigger = workflow_triggers.create_approval_requirement_trigger({
        high_value_threshold = 1000,
      })

      assert.is_true(trigger(nil, make_context({
        target = "In Review",
        properties = { estimated_value = 999 },
      })))
    end)

    it("reports every reason approval is needed", function()
      local trigger = workflow_triggers.create_approval_requirement_trigger({
        columns = { ["^Done$"] = { reason = "Sign-off required" } },
        high_value_threshold = 1000,
      })

      local _, err = trigger(nil, make_context({
        target = "Done",
        properties = { estimated_value = 2500 },
      }))

      assert.matches("Sign%-off required", err)
      assert.matches("High value task", err)
      assert.matches("; ", err)
    end)

    it("uses a default reason when the column config gives none", function()
      local trigger = workflow_triggers.create_approval_requirement_trigger({
        columns = { ["^Done$"] = {} },
      })

      local _, err = trigger(nil, make_context({ target = "Done" }))

      assert.matches("Column transition requires approval", err)
    end)
  end)

  describe("create_workflow_rules_trigger", function()
    it("allows a direct add, which has no source column", function()
      local trigger = workflow_triggers.create_workflow_rules_trigger({
        ["In Progress"] = { "Done" },
      })
      local context = make_context({ source = false })

      assert.is_true(trigger(nil, context).success)
    end)

    it("allows any target from a source the workflow does not mention", function()
      local trigger = workflow_triggers.create_workflow_rules_trigger({
        Backlog = { "In Progress" },
      })

      assert.is_true(trigger(nil, make_context()).success)
    end)

    it("allows a target listed in a simple array", function()
      local trigger = workflow_triggers.create_workflow_rules_trigger({
        ["In Progress"] = { "Done", "Blocked" },
      })

      assert.is_true(trigger(nil, make_context()).success)
    end)

    it("refuses a target the array omits", function()
      local trigger = workflow_triggers.create_workflow_rules_trigger({
        ["In Progress"] = { "Blocked" },
      })

      local result = trigger(nil, make_context())

      assert.is_false(result.success)
      assert.equals(
        "Workflow does not allow transition from 'In Progress' to 'Done'",
        result.errors[1]
      )
    end)

    it("accepts a single target given as a string", function()
      local trigger = workflow_triggers.create_workflow_rules_trigger({
        ["In Progress"] = "Done",
      })

      assert.is_true(trigger(nil, make_context()).success)
    end)

    it("refuses when the single string target does not match", function()
      local trigger = workflow_triggers.create_workflow_rules_trigger({
        ["In Progress"] = "Blocked",
      })

      assert.is_false(trigger(nil, make_context()).success)
    end)

    it("allows a conditional target whose condition holds", function()
      local trigger = workflow_triggers.create_workflow_rules_trigger({
        ["In Progress"] = { Done = { when = "reviewed == true" } },
      })

      local result = trigger(nil, make_context({ properties = { reviewed = true } }))

      assert.is_true(result.success)
    end)

    it("refuses a conditional target whose condition fails, naming it", function()
      local trigger = workflow_triggers.create_workflow_rules_trigger({
        ["In Progress"] = { Done = { when = "reviewed == true" } },
      })

      local result = trigger(nil, make_context({ properties = { reviewed = false } }))

      assert.is_false(result.success)
      assert.matches("Workflow condition 'reviewed == true' not met", result.errors[1])
    end)

    it("sets context.auto_move for an auto transition", function()
      local trigger = workflow_triggers.create_workflow_rules_trigger({
        ["In Progress"] = { Done = { auto = true } },
      })
      local context = make_context()

      assert.is_true(trigger(nil, context).success)
      assert.is_true(context.auto_move)
    end)

    it("sets context.auto_move only once its condition holds", function()
      local trigger = workflow_triggers.create_workflow_rules_trigger({
        ["In Progress"] = { Done = { when = "reviewed == true", auto = true } },
      })

      local blocked = make_context({ properties = { reviewed = false } })
      trigger(nil, blocked)
      assert.is_nil(blocked.auto_move)

      local allowed = make_context({ properties = { reviewed = true } })
      trigger(nil, allowed)
      assert.is_true(allowed.auto_move)
    end)

    it("leaves context.auto_move unset for an ordinary transition", function()
      local trigger = workflow_triggers.create_workflow_rules_trigger({
        ["In Progress"] = { "Done" },
      })
      local context = make_context()

      trigger(nil, context)

      assert.is_nil(context.auto_move)
    end)
  end)
end)
