# Complexity Feature Demo

This board demonstrates the complexity property feature.

###### To Do
- Simple task
- Medium task <!-- complexity: 3 -->
- Complex task <!-- complexity: 5 -->

###### In Progress
- Current work <!-- complexity: 2, started: 1735862400 -->

###### Done
- Finished task <!-- complexity: 1, done: 1735948800 -->

## Usage

### Setting Complexity on Existing Cards
1. Place cursor on any card line (e.g., "Simple task")
2. Run `:KanbanSetComplexity`
3. Enter a complexity value (e.g., "2")
4. The card will be updated with the complexity property

### Auto-adding Complexity to New Cards
To enable auto-adding default complexity to all new cards:

```lua
require('kanban-md').setup({
  use_complexity = true,     -- Enable auto-add
  default_complexity = 1,    -- Default value for new cards
})
```

With this enabled, when you create new cards via `:KanbanNewCard`, they will automatically receive the default complexity value.
