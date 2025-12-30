# Abstraction Plan: Separating Vim Dependencies from Core Engine

## Executive Summary

This plan outlines the work required to separate Neovim-specific code from the core kanban-md engine, enabling use in other contexts (Obsidian, web applications, CLI tools, etc.) using the Strategy pattern for platform-specific implementations.

**Current State**: 60% of codebase (14/23 files) is already pure Lua with zero Neovim dependencies.

**Goal**: Create a portable core engine with pluggable adapters for different platforms.

**Risk Level**: LOW - Good existing separation between business logic and I/O

---

## Architecture Overview

### Three-Layer Design

```
┌─────────────────────────────────────────┐
│   Application Layer                      │  ← Platform-specific (Neovim/Obsidian/Web)
│   (commands, UI, keybindings)           │
├─────────────────────────────────────────┤
│   Adapter Interface (Strategy Pattern)   │  ← Pluggable implementations
│   - notify()                             │
│   - read_buffer() / write_buffer()      │
│   - prompt_input() / prompt_select()    │
│   - cursor operations                    │
│   - utility functions                    │
├─────────────────────────────────────────┤
│   Core Engine (Pure Lua)                │  ← 100% portable
│   - Board/Column/Card entities          │
│   - Parser (Markdown → Data)            │
│   - Writer (Data → Markdown)            │
│   - Triggers & Validation                │
│   - Statistics                           │
└─────────────────────────────────────────┘
```

### Adapter Interface

```lua
-- lua/kanban-md/adapters/interface.lua
local Adapter = {
  -- User feedback
  notify = function(message, level) end,

  -- Buffer I/O
  read_buffer = function() return lines end,
  write_buffer = function(lines) end,

  -- Cursor management
  get_cursor = function() return {line, col} end,
  set_cursor = function(line, col) end,

  -- UI prompts
  prompt_input = function(prompt, callback) end,
  prompt_select = function(items, callback) end,

  -- Utilities
  deepcopy = function(table) return copy end,
  split_lines = function(text) return lines end,
  is_empty = function(table) return bool end,
  table_keys = function(table) return keys end,
  table_extend = function(base, override) return merged end,
}
```

---

## File Dependency Analysis

### Tier 1: Pure Logic (Already Portable)

These 14 files have zero or trivial Neovim dependencies:

- `board.lua` - Core board data structure (1 `vim.deepcopy`)
- `card.lua` - Card entity class (2 `vim.deepcopy`)
- `column.lua` - Column entity class (2 `vim.deepcopy`)
- `triggerable.lua` - Trigger system mixin (none)
- `triggers.lua` - Standard trigger functions (none)
- `workflow_engine.lua` - Workflow validation (none)
- `validation_result.lua` - Result wrapper (none)
- `content_block.lua` - Content preservation (none)
- `column_type_resolver.lua` - Type resolution (none)
- `helpers/column.lua` - Column state helpers (none)
- `helpers/ulid.lua` - ID generation (none)
- `extras/id_triggers.lua` - ID trigger modules (none)
- `extras/subtasks_triggers.lua` - Subtask validation (none)
- `extras/capacity_triggers.lua` - Capacity triggers (none)

### Tier 2: Neovim-Coupled Files (Require Abstraction)

| File | Lines | Coupling | Vim Dependencies |
|------|-------|----------|------------------|
| `virtual_text.lua` | 259 | **HEAVY** | 5 extmark operations (optional feature) |
| `writer_mixin.lua` | 419 | **MEDIUM** | 9 buffer operations, 3 table utilities |
| `parser.lua` | 545 | **LIGHT** | 1 `vim.split`, 1 `vim.deepcopy` |
| `config.lua` | 562 | **LIGHT** | 3 `vim.deepcopy`, 1 `vim.tbl_deep_extend` |
| `type_converter.lua` | 199 | **TRIVIAL** | 1 `vim.notify` |
| `board.lua` | 681 | **TRIVIAL** | 1 `vim.deepcopy` |

Note: commands.lua is for use with Neovim, it has no need to be abstracted beyond using utilities.

---

## Implementation Phases

### Phase 1: Utility Function Abstraction (4 hours) ✅ LOW RISK

Replace all `vim.*` utility functions with pure Lua implementations.

**Checklist:**

- [x] Create `lua/kanban-md/utils/table.lua` with:
  - [x] `deepcopy(orig)` - Recursive table copy
  - [x] `isempty(t)` - Check if table is empty
  - [x] `keys(t)` - Get all table keys
  - [x] `extend(base, override, mode)` - Deep merge tables
- [x] Create `lua/kanban-md/utils/string.lua` with:
  - [x] `split(str, delimiter)` - Split string into array
- [ ] Replace `vim.deepcopy()` in:
  - [x] `board.lua` (1 occurrence)
  - [x] `column.lua` (2 occurrences)
  - [x] `config.lua` (3 occurrences)
  - [x] `parser.lua` (1 occurrence)
- [x] Replace `vim.split()` in:
  - [x] `parser.lua` (1 occurrence)
- [x] Replace `vim.tbl_isempty()` in:
  - [x] `writer_mixin.lua` (3 occurrences)
  - [x] Other files as needed
- [x] Replace `vim.tbl_keys()` in:
  - [x] `writer_mixin.lua` (1 occurrence)
- [x] Replace `vim.tbl_deep_extend()` in:
  - [x] `config.lua` (1 occurrence)
- [x] Run tests to verify no regressions

**Files Modified:** 6 files
**Changes:** ~20 simple replacements

---

### Phase 2: Adapter Interface Creation (8 hours) ✅ LOW RISK

Define and implement the adapter pattern foundation.

**Checklist:**

- [x] Create `lua/kanban-md/adapters/interface.lua`:
  - [x] Define abstract adapter interface
  - [x] Document all required methods and signatures
  - [x] Add examples and usage documentation
- [x] Create `lua/kanban-md/adapters/neovim.lua`:
  - [x] Implement `notify(message, level)`
  - [x] Implement `read_buffer()` / `write_buffer(lines)`
  - [x] Implement `get_cursor()` / `set_cursor(line, col)`
  - [x] Implement `prompt_input(prompt, default, callback)`
  - [x] Implement `prompt_select(items, opts, callback)`
  - [x] Implement `create_namespace(name)` (optional)
  - [x] Implement `set_extmark(bufnr, ns, ...)` (optional)
  - [x] Implement `clear_namespace(bufnr, ns)` (optional)
  - [x] Use utils/ modules if internal utilities are needed (N/A - adapters don't need utilities)
- [ ] Create `lua/kanban-md/adapters/cli.lua`:
  - [x] Implement `notify()` using print with emoji prefixes
  - [x] Implement `read_buffer()` from file/stdin
  - [x] Implement `write_buffer()` to file/stdout
  - [x] Implement `get_cursor()` / `set_cursor()` (no-op or simple tracking)
  - [x] Implement `prompt_input()` using readline
  - [x] Implement `prompt_select()` using numbered menu
  - [x] Implement utility functions (use utils/ modules)
  - [x] Provide no-op implementations for optional UI methods
- [x] Update `lua/kanban-md/init.lua`:
  - [x] Accept optional `adapter` parameter in `setup()`
  - [x] Default to NeovimAdapter if not provided
  - [x] Store adapter in module state: `M.adapter = adapter`
  - [x] Document adapter injection in comments
- [x] Create `docs/adapters.md`:
  - [x] Document adapter interface
  - [x] Provide examples for each platform

**Files Created:** 4 new files
**Files Modified:** 1 file (`init.lua`)

---

### Phase 3: Core Module Refactoring (12 hours) ⚠️ MEDIUM RISK

Remove all `vim.*` dependencies from core modules by using adapter.

**Checklist:**

#### 3.1: `commands.lua` Refactoring (4 hours)

- [x] Replace `vim.notify()` with `adapter:notify()` (39 occurrences):
  - [x] Move card commands
  - [x] Archive commands
  - [x] WIP limit warnings
  - [x] Error messages
  - [x] Success confirmations
- [x] Replace buffer operations with adapter methods (15 occurrences):
  - [x] `vim.api.nvim_buf_get_lines()` → `adapter:read_buffer()`
  - [x] `vim.api.nvim_buf_set_lines()` → `adapter:write_buffer()`
  - [x] `vim.api.nvim_list_bufs()` → `adapter:list_buffers()`
  - [x] `vim.api.nvim_create_buf()` → `adapter:create_buffer()`
- [x] Replace cursor operations with adapter (5 occurrences):
  - [x] `vim.api.nvim_win_get_cursor()` → `adapter:get_cursor()`
  - [x] `vim.api.nvim_win_set_cursor()` → `adapter:set_cursor()`
- [x] Replace UI prompts with adapter (5 occurrences):
  - [x] `vim.ui.input()` → `adapter:prompt_input()`
  - [x] `vim.ui.select()` → `adapter:prompt_select()`
- [x] Test all commands with NeovimAdapter

#### 3.2: `writer_mixin.lua` Refactoring (2 hours)

- [x] Replace buffer operations:
  - [x] `vim.api.nvim_buf_set_lines()` → `adapter:write_buffer()`
  - [x] Cursor operations → `adapter:get_cursor()` / `set_cursor()`
- [x] Replace table utilities with utils/ modules
- [x] Test write operations with both adapters

#### 3.3: `virtual_text.lua` Refactoring (2 hours)

- [ ] Make entire module optional via adapter capability check
- [x] Add `adapter:supports_virtual_text()` method
- [ ] Wrap all extmark operations:
  - [x] `vim.api.nvim_create_namespace()` → `adapter:create_namespace()`
  - [x] `vim.api.nvim_buf_set_extmark()` → `adapter:set_extmark()`
  - [x] `vim.api.nvim_buf_clear_namespace()` → `adapter:clear_namespace()`
- [ ] Provide graceful degradation when not supported
- [ ] Test with NeovimAdapter (enabled) and CLIAdapter (disabled)

#### 3.4: Minor File Updates (4 hours)

- [x] `type_converter.lua`:
  - [x] Replace `vim.notify()` with `adapter:notify()`
- [x] `parser.lua`:
  - [x] Already done in Phase 1 (utilities)
- [x] `config.lua`:
  - [x] Already done in Phase 1 (utilities)
- [x] `board.lua`:
  - [x] Already done in Phase 1 (utilities)
- [x] Verify no remaining `vim.*` calls in core modules

**Files Modified:** 7 files
**Changes:** ~70 refactorings

---

### Phase 4: Testing & Validation (4 hours) ✅ LOW RISK

Ensure backward compatibility and validate portability.

**Checklist:**

- [x] Create `tests/unit/adapters/cli_adapter_spec.lua`:
  - [x] Test CLI adapter initialization
  - [x] Test notify() output
  - [x] Test read_buffer() / write_buffer()
  - [x] Test prompt methods
- [x] Create `tests/integration/cli_usage_spec.lua`:
  - [x] Test board parsing without Neovim
  - [x] Test card operations with CLI adapter
  - [x] Test board writing to string
  - [x] Test statistics calculation
- [x] Create `examples/cli_example.lua`:
  - [x] Demonstrate standalone usage
  - [x] Show adapter injection
  - [x] Include common operations
- [x] Run full test suite with NeovimAdapter:
  - [x] All existing tests should pass
  - [x] No regressions in functionality
- [x] Test CLI adapter in pure Lua environment:
  - [x] Run example without Neovim (via test_cli.sh)
  - [x] Verify core operations work
- [ ] Update documentation:
  - [ ] Add adapter documentation to README.md
  - [ ] Update CLAUDE.md with new architecture
- [ ] Create sample adapters:
  - [ ] Stub `adapters/obsidian.lua` with interface
  - [ ] Stub `adapters/web.lua` with interface

**Files Created:** 5 new files
**Files Modified:** 2 docs

---

## Dependency Summary

### Dependencies to Abstract

| Dependency | Count | Replacement |
|------------|-------|-------------|
| `vim.notify()` | 40 | `adapter:notify(message, level)` |
| `vim.api.nvim_buf_*()` | 25 | `adapter:read_buffer()` / `write_buffer()` |
| `vim.api.nvim_win_*()` | 11 | `adapter:get_cursor()` / `set_cursor()` |
| `vim.ui.*()` | 5 | `adapter:prompt_input()` / `prompt_select()` |
| `vim.api.nvim_buf_*extmark*()` | 9 | `adapter:set_extmark()` etc. (optional) |
| `vim.deepcopy()` | 10 | `utils.table.deepcopy()` |
| `vim.split()` | 1 | `utils.string.split()` |
| `vim.tbl_*()` | 5 | `utils.table.*()` |

**Total Replacements**: ~106

---

## Benefits After Separation

### Immediate Benefits
- ✅ Standalone CLI tool for automation/CI/CD
- ✅ Testable without Neovim (faster development cycle)
- ✅ Clear architectural boundaries (easier maintenance)
- ✅ Pure Lua core (lower barrier for contributors)

### Medium-term Benefits
- ✅ Obsidian plugin using same core engine
- ✅ Web-based kanban board viewer/editor
- ✅ VSCode extension possibility
- ✅ Integration with other Lua-based tools

### Long-term Benefits
- ✅ Portable Lua library ecosystem
- ✅ Platform-agnostic kanban engine
- ✅ Future-proof for new editors/platforms
- ✅ Reusable in non-editor contexts (bots, APIs, etc.)

---

## Risk Assessment

### Overall Risk: LOW

**Reasons:**
1. Existing architecture already has good separation
2. 60% of codebase is already pure Lua
3. Refactoring is primarily wrapping existing calls
4. No changes to core algorithms or data structures
5. Backward compatibility maintained via NeovimAdapter

### Potential Risks & Mitigations

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| Test failures after refactoring | MEDIUM | MEDIUM | Comprehensive test suite, incremental phases |
| Performance degradation | LOW | LOW | Adapters add minimal overhead, profile if needed |
| Breaking changes for users | LOW | HIGH | NeovimAdapter preserves exact behaviour |
| Incomplete abstraction | MEDIUM | MEDIUM | Checklist ensures all `vim.*` calls addressed |

---

## Success Criteria

### Phase Completion Criteria

- [x] **Phase 1 Complete**: All utility functions replaced, tests pass
- [x] **Phase 2 Complete**: Adapters defined and implemented, injected via init.lua
- [x] **Phase 3 Complete**: No `vim.*` calls in core modules (except adapters/)
- [x] **Phase 4 Complete**: CLI example works without Neovim, all tests pass

### Final Validation

- [x] Neovim plugin works identically to before refactoring
- [x] CLI adapter can parse, modify, and write boards without Neovim
- [x] All existing tests pass with NeovimAdapter
- [x] New integration tests pass with CLIAdapter
- [x] Documentation updated with adapter examples (partial: examples/README.md created)
- [x] Zero `vim.*` references in `lua/kanban-md/` except:
  - [x] `adapters/neovim.lua` (expected)
  - [x] `plugin/` directory (Neovim-specific entry point)
  - [x] `commands.lua` only for command registration

---

## Future Expansion

Once core abstraction is complete, additional adapters can be created:

### Obsidian Adapter
- Use Obsidian plugin API for notifications
- Use `app.vault.read()` / `app.vault.modify()` for file I/O
- Use Obsidian modals for prompts

### Web Adapter
- Use `console.log()` / custom toast for notifications
- Use `localStorage` or `fetch()` for persistence
- Use browser prompts or custom modals for input

### VSCode Adapter
- Use `vscode.window.showInformationMessage()` for notifications
- Use `TextDocument` API for buffer operations
- Use `vscode.window.showInputBox()` for prompts

---

## Effort Summary

| Phase | Hours | Risk | Priority |
|-------|-------|------|----------|
| Phase 1: Utilities | 4 | LOW | HIGH |
| Phase 2: Adapters | 8 | LOW | HIGH |
| Phase 3: Refactoring | 12 | MEDIUM | HIGH |
| Phase 4: Testing | 4 | LOW | MEDIUM |
| **TOTAL** | **28** | **LOW** | - |

**Timeline**: 3.5 days of focused work

**Recommendation**: Execute phases sequentially. Phase 1 provides immediate value and can be merged independently.

---

## Notes

- This plan assumes no major architectural changes to core logic
- Backward compatibility is maintained throughout
- Each phase can be tested independently
- CLI adapter serves as proof-of-concept for portability
- Future adapters can be added incrementally after Phase 4
