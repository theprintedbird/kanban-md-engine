require("kanban-md").setup({
  -- Board defaults
  default_columns = {"Backlog", "Ready", "In Progress", "Done"},
  archive_after_days = 30,
  
  -- WIP limits
  default_wip_limit = nil,
  warn_on_wip_exceeded = true,
  block_on_wip_exceeded = false,
  
  -- Display
  show_stats_virtual_text = true,
  show_cycle_time = true,
  date_format = "epoch", -- or "iso", "relative"
  
  -- Automation
  auto_archive = true,
  auto_timestamp = true,
  auto_id = true,
})
