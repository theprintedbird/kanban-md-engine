-- lua/kanban-md/extras/capacity_triggers.lua
-- Optional capacity-based triggers for advanced capacity management
-- These triggers extend beyond simple WIP limits to include point-based and reviewer-based capacity

local column_helper = require('kanban-md.helpers.column')

local M = {}

-- Point-based capacity trigger
-- Checks if adding a card would exceed the column's maximum point capacity
function M.create_capacity_points_trigger(max_points)
  local execute_fn = function(column, context)
    local current_points = 0
    for _, card in ipairs(context.target_column.cards) do
      current_points = current_points + (card.properties.points or 0)
    end

    local task_points = context.card.properties.points or 0
    if (current_points + task_points) > max_points then
      return true, nil, string.format(
        "Column capacity exceeded: %d + %d > %d points",
        current_points, task_points, max_points
      )
    end

    return true
  end

  return execute_fn
end

-- Reviewer capacity trigger
-- Checks if all reviewers are currently busy in review columns
function M.create_reviewer_capacity_trigger(board)
  local execute_fn = function(column, context)
    if not context.target_column.name:match("Review") then
      return true -- Only check review columns
    end

    -- Count busy reviewers across all review columns
    local reviewers_busy = 0
    for _, col in ipairs(context.board.columns) do
      if col.name:match("Review") then
        for _, card in ipairs(col.cards) do
          if card.properties.reviewer then
            reviewers_busy = reviewers_busy + 1
          end
        end
      end
    end

    local total_reviewers = #(context.board.config.reviewers or {})
    if reviewers_busy >= total_reviewers then
      return true, nil, "All reviewers are currently busy"
    end

    return true
  end

  return execute_fn
end

-- Team velocity capacity trigger
-- Checks if the team can handle additional work based on historical velocity
function M.create_velocity_capacity_trigger(max_velocity_points)
  local execute_fn = function(column, context)
    -- Only check work-in-progress columns (not completion or Archive)
    if column_helper.is_completion_column(context.target_column, context.board) or context.target_column.name == "__ARCHIVE__" then
      return true
    end

    -- Calculate total points currently in progress across all non-completion columns
    local total_wip_points = 0
    for _, col in ipairs(context.board.columns) do
      if not column_helper.is_completion_column(col, context.board) and col.name ~= "__ARCHIVE__" then
        for _, card in ipairs(col.cards) do
          total_wip_points = total_wip_points + (card.properties.points or 0)
        end
      end
    end

    local task_points = context.card.properties.points or 0
    if (total_wip_points + task_points) > max_velocity_points then
      return true, nil, string.format(
        "Team velocity capacity exceeded: %d + %d > %d points",
        total_wip_points, task_points, max_velocity_points
      )
    end

    return true
  end

  return execute_fn
end

-- Skill-based capacity trigger
-- Checks if there are available team members with the required skills
function M.create_skill_capacity_trigger(board)
  local execute_fn = function(column, context)
    local required_skills = context.card.properties.required_skills
    if not required_skills or #required_skills == 0 then
      return true -- No specific skills required
    end

    -- Check if any team member with required skills is available
    local team_members = context.board.config.team_members or {}
    local available_skilled_members = 0

    for _, member in ipairs(team_members) do
      local member_skills = member.skills or {}
      local has_required_skills = true

      -- Check if member has all required skills
      for _, required_skill in ipairs(required_skills) do
        local has_skill = false
        for _, member_skill in ipairs(member_skills) do
          if member_skill == required_skill then
            has_skill = true
            break
          end
        end
        if not has_skill then
          has_required_skills = false
          break
        end
      end

      if has_required_skills then
        -- Check if this member is currently available (not assigned to other tasks)
        local is_busy = false
        for _, col in ipairs(context.board.columns) do
          if not column_helper.is_completion_column(col, context.board) and col.name ~= "__ARCHIVE__" then
            for _, card in ipairs(col.cards) do
              if card.properties.assignee == member.name then
                is_busy = true
                break
              end
            end
            if is_busy then break end
          end
        end

        if not is_busy then
          available_skilled_members = available_skilled_members + 1
        end
      end
    end

    if available_skilled_members == 0 then
      return true, nil, string.format(
        "No team members available with required skills: %s",
        table.concat(required_skills, ", ")
      )
    end

    return true
  end

  return execute_fn
end

return M