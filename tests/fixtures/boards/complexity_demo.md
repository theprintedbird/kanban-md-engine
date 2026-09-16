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

### Board-Level Configuration
You can set complexity defaults per board in the markdown itself:

```markdown
# My Board
<!-- kanban:config use_complexity: true, default_complexity: 3 -->

###### To Do
- New task  <!-- This will automatically get complexity: 3 -->
```

**Priority Chain:**
1. Existing card complexity (never overridden)
2. Board-level config (`board.config.use_complexity` and `board.config.default_complexity`)
3. Global plugin config (`use_complexity` and `default_complexity`)

**Example:**
```markdown
# Sprint Board
<!-- kanban:config use_complexity: true, default_complexity: 5 -->

###### To Do
- High complexity task  <!-- Will get complexity: 5 automatically -->
- Already estimated task <!-- complexity: 2 -->  <!-- Keeps its value -->
```

Board-level config overrides the global plugin config, allowing different boards to have different complexity defaults.
