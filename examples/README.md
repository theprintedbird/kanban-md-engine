# Kanban-MD CLI Examples

This directory contains examples demonstrating standalone usage of kanban-md without Neovim, using the CLI adapter.

## Files

- `cli_example.lua` - Comprehensive demonstration of CLI adapter usage
- `sample_board.md` - Sample kanban board for testing
- `test_cli.sh` - Test script using Neovim's Lua runtime (works now)

## Running the Example

### Method 1: Using Neovim's Lua Runtime (Current Setup)

Since the system doesn't have a standalone Lua interpreter, you can test using Neovim's Lua runtime in headless mode. This still demonstrates that the core engine works with the CLI adapter without any Neovim APIs:

```bash
cd /Users/iainb/Projects/ThePrintedBird/nvim-plugins/kanban-md
./examples/test_cli.sh
```

Or manually:
```bash
cd /Users/iainb/Projects/ThePrintedBird/nvim-plugins/kanban-md
nvim --headless --noplugin \
  --cmd "set rtp+=$(pwd)" \
  -c "lua dofile('examples/cli_example.lua')" \
  -c "quit"
```

### Method 2: Using Standalone Lua Interpreter (Recommended)

For true standalone testing without Neovim, install a Lua interpreter:

#### Install Lua via Homebrew:
```bash
brew install lua
```

#### Install LuaJIT (faster, compatible):
```bash
brew install luajit
```

#### Then run directly:
```bash
cd /Users/iainb/Projects/ThePrintedBird/nvim-plugins/kanban-md
lua examples/cli_example.lua
```

Or:
```bash
luajit examples/cli_example.lua
```

## What the Example Demonstrates

The `cli_example.lua` script demonstrates:

1. **Initialising kanban-md with CLI adapter** - No Neovim required
2. **Loading a board from file** - Parse markdown into data structures
3. **Reading board statistics** - WIP counts, column breakdowns
4. **Finding and inspecting cards** - Search by properties
5. **Moving cards between columns** - Core board operations
6. **Adding new cards** - Programmatic card creation
7. **Calculating statistics** - Complexity totals, WIP tracking
8. **Writing modified board** - Generate markdown output
9. **Board validation** - WIP limits, structural checks
10. **Archive functionality** - Move completed cards

## Expected Output

When you run the example, you should see output like:

```
=== Kanban-MD CLI Example ===

1. Initialising kanban-md with CLI adapter...
✓ Initialised with CLI adapter

2. Loading board from file...
✓ Loaded board: 'Project Tasks'
  Columns: 5
  Total cards: 9

3. Board statistics:
  WIP (all active columns): 7
  Board WIP limit: 5
  - Backlog:        3 cards
  - In Progress:    2 cards (limit: 2)
  - Review:         1 cards
  - Done:           2 cards
  - __ARCHIVE__:    1 cards

... [continues with each operation]

=== Summary ===
This example demonstrated:
  ✓ Loading the CLI adapter without Neovim
  ✓ Parsing a markdown kanban board
  ✓ Reading board statistics and card properties
  ✓ Moving cards between columns
  ✓ Adding new cards programmatically
  ✓ Validating board state
  ✓ Writing the modified board back to markdown
  ✓ Archive functionality

All operations completed without Neovim!
Check 'sample_board_modified.md' to see the changes.
```

## Output Files

After running the example:
- `sample_board_modified.md` - Modified board with changes applied

## Use Cases

This CLI adapter approach enables:

- **CI/CD automation** - Update kanban boards in pipelines
- **Command-line tools** - Build CLI utilities for board management
- **Batch processing** - Process multiple boards programmatically
- **Integration testing** - Test core logic without Neovim
- **Web services** - Use the engine in web applications
- **Obsidian plugins** - Reuse core engine with different adapter

## Adapter Pattern

The CLI adapter implements the adapter interface in `lua/kanban-md/adapters/interface.lua`:

```lua
-- Initialize with CLI adapter
local CLIAdapter = require('kanban-md.adapters.cli')
local kanban = require('kanban-md')

kanban.setup({
  -- config options
}, {
  adapter = CLIAdapter  -- Inject CLI adapter
})
```

This pattern allows the same core engine to work across:
- Neovim (NeovimAdapter)
- Command-line (CLIAdapter)
- Obsidian (future ObsidianAdapter)
- Web browsers (future WebAdapter)
- VSCode (future VSCodeAdapter)

## Next Steps

1. Install Lua or LuaJIT with Homebrew
2. Run `lua examples/cli_example.lua`
3. Examine `sample_board_modified.md` to see the changes
4. Modify the example to test your own use cases
5. Build your own CLI tools using the adapter pattern
