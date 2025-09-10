
-- Display WIP limit warnings
if current_wip > wip_limit then
  vim.api.nvim_buf_set_extmark(bufnr, ns_id, line_num, 0, {
    virt_text = {{string.format(" ⚠ WIP limit exceeded (%d/%d)", current_wip, wip_limit), "WarningMsg"}},
    virt_text_pos = "eol"
  })
end

-- Display cycle time for completed cards
local cycle_time = calculate_cycle_time(card)
vim.api.nvim_buf_set_extmark(bufnr, ns_id, line_num, 0, {
  virt_text = {{string.format(" ⏱ %d days", cycle_time), "Comment"}},
  virt_text_pos = "eol"
})
