<!-- kanban-board -->
# Auto-Move Test Board

<!-- kanban:config
wip_limit: 15
cycle_time_unit: days
workflow:
  "Backlog": ["Ready", "In Progress"]
  "Ready": ["In Progress", "Done"]
  "In Progress": ["Review", "Done", "Blocked"]
  "Review": ["Done", "In Progress"]
  "Blocked": ["In Progress"]
-->

###### Backlog
- Simple task <!-- id: simple1, complexity: 2, priority: low -->
- High priority task <!-- id: high1, complexity: 1, priority: high -->
- Complex task <!-- id: complex1, complexity: 8, priority: medium -->

###### Ready
<!-- column:config wip_limit: 4 -->
- Ready task <!-- id: ready1, complexity: 3, priority: medium -->

###### In Progress
<!-- column:config
wip_limit: 3
triggers:
  on_checking:
    - name: "capacity_check"
      module: "kanban-md.extras.capacity_triggers"
      function: "create_wip_limit_checking_trigger"
      args: [3]
-->
- Working task <!-- id: work1, complexity: 5, started: 1735948800 -->

###### Review
<!-- column:config wip_limit: 2 -->
- Code review task <!-- id: review1, complexity: 2, assignee: reviewer1 -->

###### Blocked
- Blocked task <!-- id: blocked1, complexity: 4, blocker: "waiting for API" -->

###### Done
- Completed simple <!-- id: done1, complexity: 1, done: 1735948800 -->
- Completed complex <!-- id: done2, complexity: 7, done: 1735862400 -->

###### __ARCHIVE__
- Archived task <!-- id: archived1, created: 1735000000, done: 1735086400 -->