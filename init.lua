-- lua/kanban-md/init.lua
local M = {}

-- Load modules
M.parser = require("kanban-md.parser")
M.writer = require("kanban-md.writer")
M.actions = require("kanban-md.actions")
M.config = require("kanban-md.config")

-- Setup function
function M.setup(opts)
    opts = opts or {}
    
    -- Configure centralized config with user options
    M.config.setup(opts)
    
    -- Create commands
    vim.api.nvim_create_user_command("KanbanNewBoard", M.actions.create_board, {})
    vim.api.nvim_create_user_command("KanbanNewTask", M.actions.create_task, {})
    vim.api.nvim_create_user_command("KanbanMoveTask", M.actions.move_task, {})
    vim.api.nvim_create_user_command("KanbanMoveForward", M.actions.move_task_forward, {})
    vim.api.nvim_create_user_command("KanbanMoveBackward", M.actions.move_task_backward, {})
    vim.api.nvim_create_user_command("KanbanDeleteTask", M.actions.delete_task, {})
    vim.api.nvim_create_user_command("KanbanEditTask", M.actions.edit_task, {})
    vim.api.nvim_create_user_command("KanbanEditProperty", M.actions.edit_task_property, {})
    vim.api.nvim_create_user_command("KanbanTaskDetails", M.actions.show_task_details, {})
    vim.api.nvim_create_user_command("KanbanArchive", M.actions.archive_done_tasks, {})
    vim.api.nvim_create_user_command("KanbanFilter", M.actions.filter_tasks, {})
    vim.api.nvim_create_user_command("KanbanUndo", M.actions.undo, {})
    vim.api.nvim_create_user_command("KanbanJump", M.actions.jump_to_column, {})

    -- Set up keybindings
    M.setup_keybindings()
end

-- Keybindings setup
function M.setup_keybindings()
    local wk = require("which-key")

    wk.add({
        { "<leader>k", group = "Kanban" },
        { "<leader>kb", "<cmd>KanbanNewBoard<CR>", desc = "New board" },
        { "<leader>kn", "<cmd>KanbanNewTask<CR>", desc = "New task" },
        { "<leader>km", "<cmd>KanbanMoveTask<CR>", desc = "Move task" },
        { "<leader>kf", "<cmd>KanbanMoveForward<CR>", desc = "Move forward" },
        { "<leader>kF", "<cmd>KanbanMoveBackward<CR>", desc = "Move backward" },
        { "<leader>kd", "<cmd>KanbanDeleteTask<CR>", desc = "Delete task" },
				{ "<leader>ke", "<cmd>KanbanEditTask<CR>", desc = "Edit task" },
       { "<leader>kp", "<cmd>KanbanEditProperty<CR>", desc = "Edit property" },
       { "<leader>ki", "<cmd>KanbanTaskDetails<CR>", desc = "Task info" },
       { "<leader>ka", "<cmd>KanbanArchive<CR>", desc = "Archive done" },
       { "<leader>k/", "<cmd>KanbanFilter<CR>", desc = "Filter tasks" },
       { "<leader>ku", "<cmd>KanbanUndo<CR>", desc = "Undo" },
       { "<leader>kj", "<cmd>KanbanJump<CR>", desc = "Jump to column" },
       { "<leader>ks", "<cmd>KanbanShowStats<CR>", desc = "Show stats" },
   })
   
   -- Buffer-local keymaps for markdown files
   vim.api.nvim_create_autocmd("FileType", {
       pattern = "markdown",
       callback = function()
           -- Quick task movement with Alt+arrows
           vim.keymap.set("n", "<M-Right>", "<cmd>KanbanMoveForward<CR>", 
               { buffer = true, desc = "Move task forward" })
           vim.keymap.set("n", "<M-Left>", "<cmd>KanbanMoveBackward<CR>", 
               { buffer = true, desc = "Move task backward" })
           
       end
   })
end

return M
