# Kanban Engine TODOs
<!-- kanban:config persist_card_ids: true -->


###### Backlog

- Add a linter, if appropriate <!-- backlog: 1792738201, id: card_01M5KRC47FW471FWV6JW46696H -->
- Property values containing -->: parse_properties strips every <!-- and --+> before scanning (parser.lua:85), and a written --> ends the HTML comment early, so quoting does not protect such a value. Needs an escape or encoding the writer emits and the parser reverses; same question for newlines inside a value. <!-- backlog: 1792390465, id: card_01M59CR24KV1GZBPNY9AE0Q6KT -->
- Add command for tagging. <!-- backlog: 1792460694, id: card_01M5BFQ981W2JF2GHRQBHVHSXB -->
- Add versioning for SPEC and boards. <!-- backlog: 1792547679, id: card_01M5E2NTV4GT1PVG6AW2A9YCXM -->
- Add versioning in the board config, so that collaborative editing can occur. <!-- backlog: 1792547703, id: card_01M5E2PJS9RHTSZX5ZPXTKR9NX -->
- Add an on_update trigger point and Board:update_card so card text and property edits go through the engine <!-- complexity: 3, id: card_01M5XM5JDXD78Y24AVQV43NQ5K -->
    **Why**
    - Moving and adding cards go through the engine (move_card, add_card), so on_checking, on_entry and on_exit
    triggers run. Editing a card does not. The only way to change a card's text or properties is to assign
    card.text or card.properties[k] directly, so no trigger, validation or rule can see an edit.
    - SPEC §6.1 lists five trigger points (on_create, on_checking, on_entry, on_exit, on_stay). None fires when
    a card is edited in place.
    - Every host reimplements editing. For example, the kanban-md skill's `set` command assigns fields directly
    and can only warn when a column timestamp key is set by hand. That is the rule SPEC §6.2 states: "completion
    timestamps MUST NOT be assigned by hand". The engine has no way to enforce it.
    - Rules that ought to apply to edits cannot be written today. Examples: a capacity_points limit checked when
    a card's complexity changes, required properties, an `updated` timestamp, or a refusal to give a card an id
    that another card already has.
    - board.validation goes stale after an edit until the next parse, so a host cannot report a WIP or
    duplicate-id problem that the edit caused.

    **What to build**
    1. Triggerable: add register_on_update(name, fn, metadata), and add "on_update" to the TRIGGER EVENTS doc
    comment in triggerable.lua.
    2. Board:register_trigger_from_config: add an on_update branch, so board `triggers` config and type-declared
    triggers (SPEC §10.5) can register one. Check that auto_register_triggers passes the key through.
    3. Board:update_card(card, changes, context), with changes = { text = string|nil, set = { key = value }|nil,
    unset = { key, ... }|nil }:
       - Find the card's column (card.column holds the column id; the archive counts). Raise an error if the 
    card is not on the board.
       - Validate the input before running any trigger. text must be a non-empty single line (SPEC §7.4). Keys 
    must match [%w_]+.
       - Timestamp keys: refuse to set or unset archived or any normalised column name
    (helpers.column.normalize_column_name) unless context.allow_timestamp_keys = true, which exists to correct
    history. This is the design decision in this card. Record it in SPEC whichever way it goes.
       - Copy-and-commit, as Column:add_card does: card:deep_copy(), apply the changes to the copy, then run the
    column's on_update triggers on the copy. Context: { card = copy, original = card, column, board, changes, 
    event_type = "update", timestamp = clock.now(), _bypass_categories }. A trigger refuses by raising an error or
    by returning a result with success = false, as on_entry does. Honour bypassable/category metadata, as 
    build_context_and_checking does.
       - On success, copy text and properties back to the original card (the original object stays in
    column.cards), then call calculate_stats() and validate(). On failure, raise an error and leave the original 
    card untouched.
       - Leave content_lines alone. SPEC §4.2 says text is authoritative for the first line.
    4. Do NOT run the existing on_checking triggers for an update. They assume a move: wip_limit refuses when
    #self.cards >= limit, so it would refuse every edit in a full column. on_update is a separate point.
    5. Optional follow-up, to show the point is useful: a capacity_points on_update trigger that refuses a 
    complexity change that would take the column over capacity.max_points. Register it in register_basic_triggers
    alongside the on_checking version.

    **SPEC.md changes (same change)**
    - §6.1: add register_on_update to the table ("A card's text or properties are about to change; MAY block the
    edit").
    - New subsection under §6 for update_card: the changes shape, copy-and-commit, refusal semantics,
    timestamp-key protection, that validation is refreshed afterwards, and that on_checking does not run.
    - §6.2: if the capacity trigger is added, list it.

    **Tests**
    - A text-only edit, a set, an unset, and a combined edit, each round-tripping through write and parse.
    - A refusing on_update trigger leaves the card and the written board unchanged.
    - A timestamp key is refused by default and allowed with allow_timestamp_keys.
    - A bypassable trigger is skipped only for its listed category.
    - A full WIP column still allows edits (on_checking is not run).
    - board.validation reflects a duplicate id introduced by an edit.
    - A multi-line card keeps its continuation lines after a text edit.

    **Also noticed**
    - on_stay is registered (register_on_stay, register_trigger_from_config) but nothing ever fires it, although
    SPEC §6.1 says it fires "when an attempted move left the card where it was". This is spec/implementation 
    drift and needs its own card.

    I scored it complexity 3: it adds a public engine API, a trigger point and a spec section. It also needs one
    design decision, whether timestamp keys are locked by default. I've recommended locking them, because §6.2
    already says those timestamps must not be set by hand.

    The on_stay drift would be worth its own card on the engine board.

###### Ready

###### In Progress



###### Done

- Drop cursor_triggers require from board.lua and remove enable_cursor_positioning <!-- backlog: 1789543830, done: 1789547153, id: card_01M2MHZMFRPHJGZ27A9Z33986Y, in_progress: 1789545981, ready: 1789544697, tags: [phase0] -->
- Mark templates.lua as unimplemented (file is empty) <!-- backlog: 1789543830, done: 1789547223, id: card_01M2MHZN7ZVSAZWWS1NET8SVZB, in_progress: 1789547162, ready: 1789544699, tags: [phase0] -->
- Fix mojibake in CLIAdapter:notify() prefixes <!-- backlog: 1789543830, done: 1789547314, id: card_01M2MHZMWBFAFQNRQRW012ZTYS, in_progress: 1789547224, ready: 1789544701, tags: [phase0] -->
- Assert notify() prefix and level routing in tests <!-- backlog: 1789543830, done: 1789547652, id: card_01M2MHZMMEXN1QQP5HZZCYATEN, in_progress: 1789547314, ready: 1789544703, tags: [phase0] -->
- Update CLAUDE.md: register_on_entry not on_entering; parser.lua not parser_mixin.lua <!-- backlog: 1789543830, done: 1789547748, id: card_01M2MHZMS66A2X3ZY41YYZQ3XC, in_progress: 1789547652, ready: 1789545313, tags: [phase0] -->
- Add Alpine Docker image for tests; verify under Podman <!-- backlog: 1789543830, done: 1789549456, id: card_01M2MHZMMRN3VTNVS2T4W8S6F4, in_progress: 1789548943, ready: 1789548217, tags: [phase1] -->
- Add local GitHub Actions testing setup (act) <!-- backlog: 1789545044, done: 1789549710, id: card_01M2MK4PDNRH70E767YD3CNHPQ, in_progress: 1789549515, ready: 1789548220, tags: [phase1] -->
- Add GitHub Actions workflow running busted, luacheck and coverage <!-- backlog: 1789543830, done: 1789549917, id: card_01M2MHZMRRD78BCAABA1F8EMXJ, in_progress: 1789549750, ready: 1789548224, tags: [phase1] -->
- Add Lua 5.1 and LuaJIT to the CI matrix <!-- backlog: 1789543830, done: 1789550325, id: card_01M2MHZMZGR7BJA5P6EFDXMPAV, in_progress: 1789549946, ready: 1789548226, tags: [phase1] -->
- Run busted --shuffle in CI <!-- backlog: 1789543830, done: 1789550398, id: card_01M2MHZNEEP7A0KN22XGPV27KA, in_progress: 1789550338, ready: 1789548227, tags: [phase1] -->
- Wire TAP output into CI and run_tests_standalone.sh <!-- backlog: 1789543830, done: 1789550462, id: card_01M2MHZN1Q5MRWV6C840ZFVZ53, in_progress: 1789550398, ready: 1789548230, tags: [phase1] -->
- Add luacov; report coverage without a threshold <!-- backlog: 1789543830, done: 1789550536, id: card_01M2MHZMS86PZ9RWTFQXPB79HW, in_progress: 1789550462, ready: 1789548233, tags: [phase1] -->
- Add luacheck and .luacheckrc declaring vim and _TEST globals <!-- backlog: 1789543830, done: 1789551335, id: card_01M2MHZMH3DQ8S0CT0WNZ2S98G, in_progress: 1789550536, ready: 1789548242, tags: [phase1] -->
- Add a rockspec declaring busted, luacov, luacheck and the Lua version <!-- backlog: 1789543830, done: 1789551581, id: card_01M2MHZMR8J95CSX9F9HSTDT84, in_progress: 1789551335, ready: 1789548245, tags: [phase1] -->
- Fix tests/run_tests_standalone.sh: add shebang and set -e <!-- backlog: 1789543830, done: 1789556527, id: card_01M2MHZMJH15FW5CJ5EBFQWR95, in_progress: 1789556487, ready: 1789555998, tags: [phase1] -->
- Delete plenary leftovers tests/run_tests.sh and tests/run_tests.lua <!-- backlog: 1789543830, done: 1789556558, id: card_01M2MHZNCKPYVZE4G7YX262587, in_progress: 1789556535, ready: 1789556000, tags: [phase1] -->
- Remove hardcoded /opt/local/bin/lua from examples/test_cli.sh and CLAUDE.md <!-- backlog: 1789543830, done: 1789556652, id: card_01M2MHZN4K4C1PJF217YSG4Q63, in_progress: 1789556587, ready: 1789556001, tags: [phase1] -->
- Quarantine or promote tests/manual-tests/ <!-- backlog: 1789543830, done: 1789556862, id: card_01M2MHZN1S6JQPSNMWWQ24YQ9B, in_progress: 1789556666, ready: 1789556004, tags: [phase1] -->
- Parser treats list items and H6 headers inside fenced code blocks as cards/columns; stats then errors on non-numeric complexity <!-- backlog: 1789556873, done: 1789557390, id: card_01M2MYDPKYSCF7QNB3XA9H7BS0, in_progress: 1789557159 -->
- Create SPEC.md <!-- backlog: 1789543830, done: 1789566258, id: card_01M2MHZN8S5NFSJBGMGFCTT5TR, in_progress: 1789565956, ready: 1789565171, tags: [phase2] -->
- SPEC.md: document the Adapter interface contract and opts shapes <!-- backlog: 1789543830, done: 1789566551, id: card_01M2MHZMY3XQZYG0408D3P9WVY, in_progress: 1789566390, ready: 1789565174, tags: [phase2] -->
- SPEC.md: document notify() levels and the stdout/stderr split <!-- backlog: 1789543830, done: 1789566678, id: card_01M2MHZMVRNGR649PG3HPY95V1, in_progress: 1789566552, ready: 1789565176, tags: [phase2] -->
- SPEC.md: document the markdown syntax contract <!-- backlog: 1789543830, done: 1789566819, id: card_01M2MHZMM8SH5YHEBM5MH0KYP4, in_progress: 1789566679, ready: 1789565178, tags: [phase2] -->
- SPEC.md: document config-resolution layering and board-overridable keys <!-- backlog: 1789543830, done: 1789566879, id: card_01M2MHZN5FX9ZKS34G1DNXETQ0, in_progress: 1789566820, ready: 1789565180, tags: [phase2] -->
- Refresh tests/README.md; drop stale counts and the hand-maintained tree <!-- backlog: 1789543830, done: 1789604231, id: card_01M2MHZMFTNHE16KPQM9NADC8P, in_progress: 1789604148, tags: [phase2] -->
- Add per-operation performance regression tests with timing bounds <!-- backlog: 1789543830, done: 1789614311, id: card_01M2MHZN8C0X92YG1R15G792EV, in_progress: 1789604727, tags: [phase2] -->
- Test adapters/interface.lua: Adapter.validate() and Adapter.new() <!-- backlog: 1789543830, done: 1789622677, id: card_01M2MHZMV6VGFZ1HDQFWH6WJVD, in_progress: 1789622540, ready: 1789620896, tags: [phase3] -->
- Extend virtual_text_spec: cycle time, blocked breakdown, units, archive, disabled <!-- backlog: 1789543830, done: 1789622869, id: card_01M2MHZMG4XKMKB8W1KADV1SPJ, in_progress: 1789622711, ready: 1789620899, tags: [phase3] -->
- Test core/setup.lua directly <!-- backlog: 1789543830, done: 1789622969, id: card_01M2MHZMR3PKT3A9ZWFWEB9E8X, in_progress: 1789622879, ready: 1789620901, tags: [phase3] -->
- Test extras/workflow_triggers.lua <!-- backlog: 1789543830, done: 1789623091, id: card_01M2MHZMJKW9BRAZ3QV4GJPS8A, in_progress: 1789622975, ready: 1789620903, tags: [phase3] -->
- Test extras/capacity_triggers.lua and the board.lua capacity branch <!-- backlog: 1789543830, done: 1789623177, id: card_01M2MHZN31CMXCGD8YSJD2GHYS, in_progress: 1789623098, ready: 1789620904, tags: [phase3] -->
- Unit-test extras/subtasks_triggers.lua <!-- backlog: 1789543830, done: 1789623401, id: card_01M2MHZNBRQ4WTVRYCAN5KZSZM, in_progress: 1789623190, ready: 1789620905, tags: [phase3] -->
- Test helpers/ulid.lua: format, monotonicity, collisions <!-- backlog: 1789543830, done: 1789624217, id: card_01M2MHZN6DC44M3Y6H0Q2YGZNM, in_progress: 1789623435, ready: 1789620909, tags: [phase3] -->
- Test validation_result.lua factories and state transitions <!-- backlog: 1789543830, done: 1789624306, id: card_01M2MHZNAYGGMEWY42J4WHRMYW, in_progress: 1789624241, ready: 1789620910, tags: [phase3] -->
- Test read_buffer with opts.stdin <!-- backlog: 1789543830, done: 1789625068, id: card_01M2MHZN83J0QSJRGMP1KCPGX7, in_progress: 1789624335, ready: 1789620912, tags: [phase3] -->
- Test write_buffer with opts.stdout <!-- backlog: 1789543830, done: 1789625201, id: card_01M2MHZMKQC43G7NM37CR59HQ9, in_progress: 1789625076, ready: 1789620914, tags: [phase3] -->
- Test cli.lua Neovim guard and setup() config passthrough <!-- backlog: 1789543830, done: 1789625263, id: card_01M2MHZMR6HV12GQ444TM12RD6, in_progress: 1789625207, ready: 1789620915, tags: [phase3] -->
- Test CLI error paths: unreadable file, malformed markdown, empty input <!-- backlog: 1789543830, done: 1789625617, id: card_01M2MHZNAVYDHKHRZ9X9VNK46F, in_progress: 1789625270, ready: 1789620916, tags: [phase3] -->
- Remove debug print from timestamp_on_initial_placement_spec.lua <!-- backlog: 1789543830, done: 1789625712, id: card_01M2MHZMMF9ZXD418R3AHHGDGY, in_progress: 1789625644, ready: 1789620919, tags: [phase3] -->
- Capture and assert fixture warnings instead of printing them <!-- backlog: 1789543830, done: 1789626054, id: card_01M2MHZNDM3GQ3SMCN9ZSGEYSD, in_progress: 1789625817, ready: 1789620921, tags: [phase3] -->
- Move os.tmpname() cleanup into after_each or a temp-dir helper <!-- backlog: 1789543830, done: 1789626232, id: card_01M2MHZNA56HXEA1SWJAA3886R, in_progress: 1789626134, ready: 1789620922, tags: [phase3] -->
- Scope make clean temp files per-run; drop the rm -rf /tmp/lua_* glob <!-- backlog: 1789543830, done: 1789626351, id: card_01M2MHZMFG9JMN7YM0F3Z8HTF3, in_progress: 1789626282, ready: 1789620924, tags: [phase3] -->
- Make examples/test_cli.sh write to temp and run it as a CI smoke test <!-- backlog: 1789543830, done: 1789626791, id: card_01M2MHZN6KYDRQAB1MEAXN3XYN, ready: 1789620925, tags: [phase3] -->
- Inject a clock so lead/cycle/blocked time can be tested with real deltas <!-- backlog: 1789543830, done: 1789627617, id: card_01M2MHZN0RMXG8YZCX7XQQ0FPD, in_progress: 1789626830, ready: 1789620926, tags: [phase3] -->
- Add require('polyfills.vim') to the four specs missing it <!-- backlog: 1789543830, done: 1789627791, id: card_01M2MHZMQGDRKFC2T9QX6NKQ9G, in_progress: 1789627660, ready: 1789620927, tags: [phase3] -->
- Add make test-each-file running every spec in its own process <!-- backlog: 1789543830, done: 1789627866, id: card_01M2MHZMQEJE7YCFW46WKXAVB2, in_progress: 1789627792, ready: 1789620928, tags: [phase3] -->
- Audit tests asserting default or initial values on singletons <!-- backlog: 1789543830, done: 1789629105, id: card_01M2MHZMYQTEHMQ9JXZ5N9NXV4, in_progress: 1789627878, ready: 1789620930, tags: [phase3] -->
- Remove pending() from roundtrip_fixtures_spec.lua and confirm Tasks 3-6 landed <!-- backlog: 1789543830, done: 1789629235, id: card_01M2MHZMMPTGMPNVK8RX43ZMYD, in_progress: 1789629173, ready: 1789620932, tags: [phase3] -->
- Fix kanban-md writer_mixin_spec expecting a comma after kanban:config <!-- backlog: 1789543830, done: 1789631574, id: card_01M2MHZMZW5BCRM5NR9NC72KV8, in_progress: 1789631441, ready: 1789630450, tags: [phase4] -->
- Add engine spec: underscore-prefixed properties are never serialised <!-- backlog: 1789543830, done: 1789632857, id: card_01M2MHZN3289SY22KFAP25Y579, in_progress: 1789632610, ready: 1789632172, tags: [phase5] -->
- Add engine spec: board config enabling a default-off boolean registers its trigger <!-- backlog: 1789543830, done: 1789634770, id: card_01M2MHZN53KDY18VMY5Y6NMTYX, in_progress: 1789634558, ready: 1789632174, tags: [phase5] -->
- Fix kanban-md.nvim test_helper.lua path: lib/kanban-md -> lib/kanban-md-engine <!-- backlog: 1789543830, done: 1789634906, id: card_01M2MHZMHY1BHC38DTWKPA97GN, tags: [phase5] -->
- An update-version script, so that the number is changed in all the right places (SPEC.md and lua/kanban-md/version.lua). <!-- backlog: 1789604497, done: 1789636043, id: card_01M2PBV1ZWA3JCJPRED1PHG8HF, in_progress: 1789635236, ready: 1789634964 -->
- Test type-defined triggers end to end: auto_register_triggers registers a column type's triggers on a parsed board, and a missing trigger module raises the 'could not be registered' error <!-- backlog: 1789774469, done: 1789974375, id: card_01M2VDY68B65CB0DCA984KYWJZ, in_progress: 1789971680, ready: 1789971574, tags: [Opus] -->
- kanban-md.triggers.mark_complete no longer exists, remove references to it in tests. <!-- backlog: 1789974228, done: 1789974550, id: card_01M31CEBBPGRZM5WVP7MQ5X5NY, in_progress: 1789974473, ready: 1789974433 -->
- Assert column-type warnings through auto_register_triggers: the invalid-type-reference and missing-required-property notify() strings, at every missing_property_requirement level, via a captured adapter (tests/integration/column_type_spec.lua only checks column.type today) <!-- backlog: 1789774469, done: 1789975162, id: card_01M2VDY6R08S37N6VJMMD73YRE, in_progress: 1789974964, ready: 1789974846, tags: [Sonnet] -->
- Document column types in README.md: column_config types/definitions/patterns, type: in a column config, the short 'config' comment syntax without the column: prefix, requires_* with missing_property_requirement, write_full_config_to_markdown, and the type path in Completion Tracking <!-- backlog: 1789774469, done: 1789982330, id: card_01M2VDY69VXK4JJ5HWV5Z1RJYX, in_progress: 1789982195, ready: 1789981939, tags: [Sonnet] -->
- Make pattern-matching statements accurate: SPEC 10.5 should say matching is case-insensitive with longest pattern then alphabetical type name as tie-break; rename the misleading tests 'matches first pattern when multiple patterns exist' and '(case-sensitive)' in the column type specs <!-- backlog: 1789774469, done: 1789982682, id: card_01M2VDY60WYYWB26PJE5MXW1NN, in_progress: 1789982389, ready: 1789981944, tags: [Haiku] -->
- A card containing a literal HTML comment gets truncated at the comment, because the engine reads it as a property block, look in to improving the parser to handle that. <!-- backlog: 1789774846, done: 1789982683, id: card_01M2VE9PYZB2NM79GJFA8DA2XJ, in_progress: 1789982389, ready: 1789981950 -->
- Retire finished plans in features/: PLAN-H6, AbstractionPlan, standalone-runner-testing, multiline-lists, COMPLEXITY_IMPLEMENTATION_SUMMARY, PLAN-config-fixes (header says Not started but all ten tasks landed), Testing Improvements, improve-tests (collect_validation_results no longer exists), PLAN.md (pre-trigger architecture) and dynamic-columns (its claim that extras still hardcode Done is false). Mark each complete or move to features/done/; dependency.md is a Neovim command plan and belongs in kanban-md.nvim. Also drop the config.lua comments that point at commands.lua and the unused fixture tests/fixtures/boards/board_auto_move.md <!-- backlog: 1789775117, done: 1789982683, id: card_01M2VEHZ048TNX910JJEJGTPEN, in_progress: 1789982389, ready: 1789981955, tags: [Haiku] -->
- Refresh features/roadmap.md as the one live plan: it still calls this the kanban-md plugin, cites Neovim commands and parser_mixin.lua, and lists column-type API docs as remaining. Keep only genuinely open items (auto-move, time-based transitions, swim lanes, is_active_state unused by the engine, the complexity-overload check idea) and point each at the engine's trigger API <!-- backlog: 1789775117, done: 1789982683, id: card_01M2VEHZCBYCZMFDHJ031K57BR, in_progress: 1789982389, ready: 1789981958, tags: [Sonnet] -->
- Update features/CONFIG_PLAN.md status: everything through the writer flag is implemented and tested; tick the checklists and leave only type inheritance, computed properties, transition validation and UI indicators as future <!-- backlog: 1789774469, done: 1789982688, id: card_01M2VDY6F20C5KMYD1SNBA9Y2S, in_progress: 1789982389, ready: 1789981948, tags: [Haiku] -->
- Audit the 13 spec files that still call os.time(): any assertion on ordering or duration between column transitions is passing by coincidence at second resolution. Route those through tests/helpers/clock.lua with real deltas (Testing Improvements, time-dependent assertions) <!-- backlog: 1789775117, done: 1789982723, id: card_01M2VEHYPE8W9GYMNVEP0ETP0B, in_progress: 1789982389, ready: 1789981961, tags: [Sonnet] -->
- Document multi-line cards in README.md: continuation lines indented by two or more spaces with no blank line, and column prose separated from cards by a blank line. multiline-lists.md ticks this as done but README.md has no mention; SPEC 7.4 is the source <!-- backlog: 1789775117, done: 1789982748, id: card_01M2VEHYZD9FK31Q10Q9K9G1MF, in_progress: 1789982389, ready: 1789981968, tags: [Sonnet] -->
- Implement the multiline-lists.md decision on empty list items: a dash with nothing after it followed by continuation lines is currently kept silently as prose. Parser should notify() at warn level that list items may not start with a blank line; assert the emitted string in a test and state the rule in SPEC 7.4 <!-- backlog: 1789775117, done: 1789983198, id: card_01M2VEHZE8KB4V17EP3DWPET6V, in_progress: 1789982389, ready: 1789981973, tags: [Sonnet] -->
- Writer drops a blank line before the first card when a column has prose: with a blank line both after the column header and before the first card, the writer trims the latter and does not restore it, so that form does not round-trip. Found while documenting multi-line cards (SPEC 7.4) <!-- backlog: 1789983158, done: 1789984040, id: card_01M31MYVV295BESHRMVPW7QXD3, in_progress: 1789983891, ready: 1789983836 -->
- Remove duplicate tests from kanban-md consumer project. <!-- backlog: 1789985079, done: 1790227358, id: card_01M31PSGDYF875Z4RXH1MTFNB9, in_progress: 1790226591, ready: 1790226199 -->
- Update leafo/gh-actions-lua to v13 and leafo/gh-actions-luarocks to v6 <!-- backlog: 1791183501, done: 1791183672, id: card_01M45DPDY2E5F9QMMBEETWWQGY, in_progress: 1791183521, ready: 1791183506 -->
- CI 8: bump actions/upload-artifact in .github/workflows/ci.yml from v4 to the current major - it lags the other actions (checkout v7, gh-actions-lua v13, gh-actions-luarocks v6); check its changelog for breaking changes to name/path/if-no-files-found; do it alongside or before the SHA pinning so the pin targets the new release <!-- backlog: 1791251237, done: 1791252568, id: card_01M47E9JRETVC8KZ6Z0YAFMEN0, in_progress: 1791252483, ready: 1791252450 -->
- CI 1: harden .github/workflows/ci.yml checkouts and action refs: pin every uses: to a full commit SHA with a "# vX.Y.Z" comment - actions/checkout, leafo/gh-actions-lua and leafo/gh-actions-luarocks in both jobs, plus actions/upload-artifact (the 7 unpinned-uses zizmor reports); the leafo actions matter most as single-maintainer third-party code that runs with the job token; add persist-credentials: false to both checkouts so GITHUB_TOKEN is not left in .git/config (no step pushes or otherwise uses git credentials; clears the 2 artipacked findings); verify with make ci-local (act, using .actrc) <!-- backlog: 1791250545, done: 1791265835, id: card_01M47DMEN4Q50JKNZR8N8WCJAE, in_progress: 1791252795, ready: 1791252657 -->
- CI 2: add workflow linting: a job in .github/workflows/ci.yml beside Luacheck (or a separate lint-workflows.yml triggered on changes to .github/**) running zizmor (zizmorcore/zizmor-action or pipx run zizmor .github; optionally upload SARIF to code scanning with security-events: write scoped to that job only) and actionlint (expression/type errors, shellcheck on run: blocks); needs CI 1 first or zizmor reports unpinned-uses and artipacked immediately; add a make lint-workflows target and list it in make help; document it in README beside the make ci-local section and in the CLAUDE.md Testing section <!-- backlog: 1791250598, depends_on: [card_01M47DMEN4Q50JKNZR8N8WCJAE], done: 1791266226, id: card_01M47DP2REKHEDZ3YTWNHPWVDS, in_progress: 1791265917, ready: 1791265847 -->
- CI 3: add .github/dependabot.yml: github-actions ecosystem, weekly, grouped into one PR, so the SHA pins from CI 1 do not go stale (Dependabot updates the # vX.Y.Z comments with the SHA); target the dev branch, since master is the release branch; Dependabot has no luarocks ecosystem, so the rockspec's test_dependencies (busted, luacov, luacheck) stay unpinned and unwatched - note that in the file; needs CI 1 <!-- backlog: 1791250642, depends_on: [card_01M47DMEN4Q50JKNZR8N8WCJAE], done: 1791266745, id: card_01M47DQE1J1NCNB5A68HV69MRR, in_progress: 1791266330, ready: 1791266298 -->
- CI 4: add top-level permissions: contents: read to .github/workflows/ci.yml so neither job gets a write-scoped GITHUB_TOKEN by default (zizmor --persona pedantic reports 3 excessive-permissions); widen per job only if a step ever needs it; verify with zizmor .github and actionlint <!-- backlog: 1791250477, done: 1791266891, id: card_01M47DJCPRN8QV2W13TZ25HE9M, in_progress: 1791266806, ready: 1791266783 -->
- CI 5: add timeout-minutes to every job in .github/workflows/ci.yml (lint and each test matrix leg) so a hung busted or luarocks run is killed rather than burning the 6-hour default; size each from recent run times with headroom for a slow shared runner; verify with actionlint <!-- backlog: 1791251220, done: 1791267878, id: card_01M47E92EZXWZ0H06TXEHF93YS, in_progress: 1791266977, ready: 1791266955 -->
- Perf: skip the scaling assertions in tests/integration/performance_spec.lua under LuaJIT (detect via the jit global), keeping its budgets; write measured 10.6x for 6x the cards on CI because LuaJIT's per-card cost is cheap enough for cache/memory effects to dominate (locally 3.2 -> 4.4 us/card from 240 to 5760 cards, vs flat under 5.3), the same reason validate/find_task/move_card have no scaling check. A quadratic shows on every interpreter, so 5.1/5.3/5.4 still guard it. Update the spec comment and tests/README.md <!-- done: 1791275487, id: card_01M47Y3NFGWJ48MA1SZM98GBB2, in_progress: 1791275112, ready: 1791267821 -->
- CI 6: add a concurrency group to .github/workflows/ci.yml keyed on workflow and ref (e.g. group: ci-${{ github.workflow }}-${{ github.ref }}) with cancel-in-progress true for pull_request only, so a new push to a PR cancels the superseded run but pushes to dev and master always finish; clears zizmor's concurrency-limits finding; verify with zizmor .github and actionlint <!-- backlog: 1791251228, done: 1791275839, id: card_01M47E99BA0MV0TWXTRG078RAG, in_progress: 1791275653, ready: 1791275603 -->
- CI 7: fix the template-injection zizmor reports in the Run tests step of .github/workflows/ci.yml: the run block expands ${{ matrix.lua }} straight into the shell (tee busted-tap-...txt); pass it through env (LUA_VERSION: ${{ matrix.lua }}) and reference "$LUA_VERSION" instead; verify with zizmor .github and actionlint <!-- backlog: 1791251232, done: 1791276088, id: card_01M47E9D9JZZ0DX8SN91TH17P8, in_progress: 1791275983, ready: 1791275928 -->
- Update Busted and Luacheck to latest versions and pin them. <!-- backlog: 1791449034, done: 1791449241, id: card_01M4DAXVJ8ADQXY2RRVM8CYZSN, in_progress: 1791449133, ready: 1791449040 -->
- Fix quoting <!-- backlog: 1792389486, done: 1792390880, id: card_01M59BT5FBHX95A51FZ32Y5P52, in_progress: 1792389929, ready: 1792389758 -->
- Saving a board with nested lists splits a card into several cards with new ids; treat indented list items as continuation lines <!-- backlog: 1792374795, complexity: 3, depends_on: [card_01M59BT5FBHX95A51FZ32Y5P52], done: 1792391707, id: card_01M58XSXPV2HSF73HVEFTHC9YY, in_progress: 1792391567 -->
- Quote array elements: parse_properties splits [a, b] on every comma and format_property_value writes elements with tostring, so an element containing a comma, bracket or leading/trailing space does not survive a round trip. Reuse the scalar quoting rules (SPEC.md 7.6) per element, on both sides. <!-- backlog: 1792390463, done: 1792461225, id: card_01M59CR0BKH1FZQJWV7WET9Z2K, in_progress: 1792460805, ready: 1792460762 -->
- Kanban writer ignores card.text <!-- backlog: 1792331365, done: 1792550921, id: card_01M57MCESJEWQRG5HDWE8RCG8H, in_progress: 1792549159, ready: 1792549078, tags: [bug] -->
    The engine ignores card.text in the writer, in lua/kanban-md/writer_mixin.lua:
      · writer_mixin.lua:126 checks if task.content_lines then. Any multi-line card goes down this path.
      · writer_mixin.lua:128 uses local first_line = task.content_lines[1]. This is the line that skips task.text: the first line comes from content_lines, so an edit to card.text never reaches the file.
      · writer_mixin.lua:143-145 writes the continuation lines from content_lines.
      · writer_mixin.lua:147 returns early. Only single-line cards reach line 151 (string.format("%s- %s", config.task_indent, task.text)), the only place the writer reads task.text.
    The parser is where the two values get copied, after which nothing keeps them in step:
      · parser.lua:284 sets content_lines[1] = "- " .. card_data.text. This is the only place they're made to match, and it happens once, at parse time.
      · parser.lua:301-302 only sets card.content_lines when the card has more than one line. That's why single-line cards were never affected.
      · card.lua:28 declares the content_lines field. Nothing in card.lua updates it when text changes.
      · card.lua:105-106 is get_full_text(), which reads content_lines for multi-line cards. Anything that displays a card through it will show the old text after an edit, too.
      Line 128 has a second difference: the multi-line path never applies config.task_indent, which the single-line path at line 151 does. With the default empty indent you wouldn't see it.
- Register the ID trigger regardless of global auto_id, so a board-file `auto_id: true` can turn IDs on (core/setup.lua:28 gates registration on the global value; the trigger already checks auto_id itself) <!-- backlog: 1792645359, complexity: 3, done: 1792646926, id: card_01M5GZTT850SSG4K73CENGZYFQ, in_progress: 1792645910, ready: 1792645867 -->
- Blank lines accumulate under a column heading each time a card moves in and back out of it. Moving one card A -> B -> A -> B -> A, saving after each move, leaves the blank lines under the headings growing 1 -> 2 -> 3, with the card written above the blank lines when it lands in an empty column. A plain parse and write is stable, so the move path is the likely culprit. Seen in TODO.kanban.md, where Ready and In Progress gain a line on every move. <!-- backlog: 1792645043, done: 1792649311, id: card_01M5GZH505V6K8YPYC73W0TGYQ, in_progress: 1792649301, ready: 1792647143, tags: [bug] -->
- Perf specs all report `performance_spec.lua @ 81` and a wrong skip location: `perf_it` calls `it()` itself, so busted records the wrapper's line for every spec; and `return pending(...)` is a tail call, which on Lua 5.1 shows as `(tail call):-1` and on 5.3+ as busted's `bin/busted:3`. Have each spec call `it()` itself (with a guard wrapper around its fn) and drop the `return`. <!-- backlog: 1792654280, complexity: 1, done: 1792660538, id: card_01M5H8B21CMXESDXBF6EVSZAB6, in_progress: 1792660387, ready: 1792660042 -->
- Write scaling spec is flaky on CI: it measured 9.05x for 6x the cards against a 9.00x limit (linear is 6x, quadratic about 36x). `KANBAN_PERF_TOLERANCE` only scales the time budgets, not `MAX_SCALING_RATIO`, so the `=2` CI sets gives this assertion no slack. Options: take the best ratio of several runs, raise the limit to about 10, or let the tolerance widen the ratio limit too. <!-- backlog: 1792654523, complexity: 2, done: 1792664004, id: card_01M5H8JEP7T49VHSYN1ZPQDN9T, in_progress: 1792663948, ready: 1792663891 -->
- The spec, in 4.3 Identifiers doesn't explicitly specify where board and column identifiers are kept, if at all, be clearer on this <!-- backlog: 1792647028, done: 1792714897, id: card_01M5H1DR0HWJ2WXTV4JKFDYK5A, in_progress: 1792714828, ready: 1792714696 -->
- Create CHANGELOG.md according to https://keepachangelog.com/en/1.1.0/ <!-- backlog: 1792724628, done: 1792724896, id: card_01M5KBDX8G597JP2DHEGR64CB4, in_progress: 1792724856, ready: 1792724668 -->
- The "Add an on_update trigger" card gets split upon parse. <!-- backlog: 1793069699, done: 1793070166, id: card_01M5XMGM1DD006BJ37E12NKGQW, in_progress: 1793070072, tags: [bug] -->
- Column prose between two cards is moved below the column's last card on write: the parser flushes it to a board-level markdown block after the column block, and write_from_blocks renders header_markdown then every card, so interleaved prose loses its place (SPEC 5.2 round-trip). Found while fixing the multi-paragraph card split. <!-- backlog: 1793070164, complexity: 3, done: 1793073167, id: card_01M5XMYT30BGR39Z9E57P6NGT5, in_progress: 1793072883, ready: 1793072680, tags: [bug] -->
