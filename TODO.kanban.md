# Kanban Engine TODOs
<!-- kanban:config persist_card_ids: true -->


###### Backlog

- Add per-operation performance regression tests with timing bounds <!-- backlog: 1789543830, id: card_01M2MHZN8C0X92YG1R15G792EV, tags: [phase2] -->
- Create SPEC.md <!-- backlog: 1789543830, id: card_01M2MHZN8S5NFSJBGMGFCTT5TR, tags: [phase2] -->
- SPEC.md: document the Adapter interface contract and opts shapes <!-- backlog: 1789543830, id: card_01M2MHZMY3XQZYG0408D3P9WVY, tags: [phase2] -->
- SPEC.md: document notify() levels and the stdout/stderr split <!-- backlog: 1789543830, id: card_01M2MHZMVRNGR649PG3HPY95V1, tags: [phase2] -->
- SPEC.md: document the markdown syntax contract <!-- backlog: 1789543830, id: card_01M2MHZMM8SH5YHEBM5MH0KYP4, tags: [phase2] -->
- SPEC.md: document config-resolution layering and board-overridable keys <!-- backlog: 1789543830, id: card_01M2MHZN5FX9ZKS34G1DNXETQ0, tags: [phase2] -->
- Refresh tests/README.md; drop stale counts and the hand-maintained tree <!-- backlog: 1789543830, id: card_01M2MHZMFTNHE16KPQM9NADC8P, tags: [phase2] -->
- Test adapters/interface.lua: Adapter.validate() and Adapter.new() <!-- backlog: 1789543830, id: card_01M2MHZMV6VGFZ1HDQFWH6WJVD, tags: [phase3] -->
- Extend virtual_text_spec: cycle time, blocked breakdown, units, archive, disabled <!-- backlog: 1789543830, id: card_01M2MHZMG4XKMKB8W1KADV1SPJ, tags: [phase3] -->
- Test core/setup.lua directly <!-- backlog: 1789543830, id: card_01M2MHZMR3PKT3A9ZWFWEB9E8X, tags: [phase3] -->
- Test extras/workflow_triggers.lua <!-- backlog: 1789543830, id: card_01M2MHZMJKW9BRAZ3QV4GJPS8A, tags: [phase3] -->
- Test extras/capacity_triggers.lua and the board.lua capacity branch <!-- backlog: 1789543830, id: card_01M2MHZN31CMXCGD8YSJD2GHYS, tags: [phase3] -->
- Unit-test extras/subtasks_triggers.lua <!-- backlog: 1789543830, id: card_01M2MHZNBRQ4WTVRYCAN5KZSZM, tags: [phase3] -->
- Test helpers/ulid.lua: format, monotonicity, collisions <!-- backlog: 1789543830, id: card_01M2MHZN6DC44M3Y6H0Q2YGZNM, tags: [phase3] -->
- Test validation_result.lua factories and state transitions <!-- backlog: 1789543830, id: card_01M2MHZNAYGGMEWY42J4WHRMYW, tags: [phase3] -->
- Test read_buffer with opts.stdin <!-- backlog: 1789543830, id: card_01M2MHZN83J0QSJRGMP1KCPGX7, tags: [phase3] -->
- Test write_buffer with opts.stdout <!-- backlog: 1789543830, id: card_01M2MHZMKQC43G7NM37CR59HQ9, tags: [phase3] -->
- Test cli.lua Neovim guard and setup() config passthrough <!-- backlog: 1789543830, id: card_01M2MHZMR6HV12GQ444TM12RD6, tags: [phase3] -->
- Test CLI error paths: unreadable file, malformed markdown, empty input <!-- backlog: 1789543830, id: card_01M2MHZNAVYDHKHRZ9X9VNK46F, tags: [phase3] -->
- Remove debug print from timestamp_on_initial_placement_spec.lua <!-- backlog: 1789543830, id: card_01M2MHZMMF9ZXD418R3AHHGDGY, tags: [phase3] -->
- Capture and assert fixture warnings instead of printing them <!-- backlog: 1789543830, id: card_01M2MHZNDM3GQ3SMCN9ZSGEYSD, tags: [phase3] -->
- Move os.tmpname() cleanup into after_each or a temp-dir helper <!-- backlog: 1789543830, id: card_01M2MHZNA56HXEA1SWJAA3886R, tags: [phase3] -->
- Scope make clean temp files per-run; drop the rm -rf /tmp/lua_* glob <!-- backlog: 1789543830, id: card_01M2MHZMFG9JMN7YM0F3Z8HTF3, tags: [phase3] -->
- Make examples/test_cli.sh write to temp and run it as a CI smoke test <!-- backlog: 1789543830, id: card_01M2MHZN6KYDRQAB1MEAXN3XYN, tags: [phase3] -->
- Inject a clock so lead/cycle/blocked time can be tested with real deltas <!-- backlog: 1789543830, id: card_01M2MHZN0RMXG8YZCX7XQQ0FPD, tags: [phase3] -->
- Add require('polyfills.vim') to the four specs missing it <!-- backlog: 1789543830, id: card_01M2MHZMQGDRKFC2T9QX6NKQ9G, tags: [phase3] -->
- Add make test-each-file running every spec in its own process <!-- backlog: 1789543830, id: card_01M2MHZMQEJE7YCFW46WKXAVB2, tags: [phase3] -->
- Audit tests asserting default or initial values on singletons <!-- backlog: 1789543830, id: card_01M2MHZMYQTEHMQ9JXZ5N9NXV4, tags: [phase3] -->
- Remove pending() from roundtrip_fixtures_spec.lua and confirm Tasks 3-6 landed <!-- backlog: 1789543830, id: card_01M2MHZMMPTGMPNVK8RX43ZMYD, tags: [phase3] -->
- De-duplicate the copied suite in kanban-md; this engine is source of truth <!-- backlog: 1789543830, id: card_01M2MHZMNEK5F53EBRQ1PK5WEP, tags: [phase4] -->
- Fix kanban-md writer_mixin_spec expecting a comma after kanban:config <!-- backlog: 1789543830, id: card_01M2MHZMZW5BCRM5NR9NC72KV8, tags: [phase4] -->
- Fix kanban-md.nvim test_helper.lua path: lib/kanban-md -> lib/kanban-md-engine <!-- backlog: 1789543830, id: card_01M2MHZMHY1BHC38DTWKPA97GN, tags: [phase5] -->
- Add engine spec: underscore-prefixed properties are never serialised <!-- backlog: 1789543830, id: card_01M2MHZN3289SY22KFAP25Y579, tags: [phase5] -->
- Add engine spec: board config enabling a default-off boolean registers its trigger <!-- backlog: 1789543830, id: card_01M2MHZN53KDY18VMY5Y6NMTYX, tags: [phase5] -->

###### Ready

- Quarantine or promote tests/manual-tests/ <!-- backlog: 1789543830, id: card_01M2MHZN1S6JQPSNMWWQ24YQ9B, ready: 1789556004, tags: [phase1] -->



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
