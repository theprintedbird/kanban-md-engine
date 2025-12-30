<!-- kanban-board -->
# Complex Workflow Board
<!-- kanban:config
wip_limit: 10
cycle_time_unit: days
workflow: {
  "Backlog": ["Ready", "Blocked"],
  "Ready": ["In Progress"],
  "In Progress": ["Review", "Blocked"],
  "Review": ["Done", "In Progress"],
  "Blocked": ["Ready", "Backlog"],
  "Done": ["__ARCHIVE__"]
}
-->

###### Backlog
<!-- column:config wip_limit: 20 -->
- Implement user authentication <!-- complexity: 5 -->
- Design dashboard layout <!-- complexity: 3 -->
- Set up CI/CD pipeline <!-- complexity: 8 -->

###### Ready
<!-- column:config wip_limit: 5 -->
- Write API documentation <!-- created: 1735862400, complexity: 2 -->
- Fix navigation bug <!-- created: 1735948800, complexity: 1 -->

###### In Progress
<!-- column:config wip_limit: 3 -->
- Refactor database queries <!-- created: 1735862400, started: 1735948800, assignee: alice -->
- Add search functionality <!-- created: 1735776000, started: 1735862400, assignee: bob -->

###### Review
<!-- column:config wip_limit: 2, type: decision -->
- Update payment integration <!-- created: 1735689600, started: 1735776000, review_started: 1735948800, assignee: charlie, reviewer: alice -->

###### Blocked
<!-- column:config type: blocked, highlight: warning -->
- Deploy to production <!-- created: 1735603200, started: 1735689600, blocked: 1735862400, blocker: "Waiting for security approval", assignee: david -->
- Integrate third-party API <!-- created: 1735516800, blocked: 1735776000, blocker: "API credentials not received", assignee: eve -->

###### Done
- Set up development environment <!-- created: 1735430400, started: 1735516800, done: 1735603200 -->
- Create project repository <!-- created: 1735430400, done: 1735516800 -->

###### __ARCHIVE__
<!-- Tasks completed more than 30 days ago -->
- Initial planning <!-- created: 1733011200, done: 1733097600, archived: 1735689600 -->
