# Visual and map parity divergences

These are intentional differences between native Phoenix pages and Rails 1.16.0, as required by ADR-0025. Every difference the parity bench reports must be fixed or listed here with its reason. An unlisted difference is a defect.

Categories:
- `contract`: a native contract forces it;
- `wiring`: markup that only connects LiveView or hooks;
- `post-1.16.0`: a change from Rails dev after 1.16.0, kept on purpose;
- `resilience`: copying Rails would break the text-resilience rule.

| Page / area | Element or behaviour | Rails 1.16.0 | Phoenix | Category | Reason | Approved |
|---|---|---|---|---|---|---|
| `/map` realtime | Recent point after a new point | Reads the point from the `PointsChannel` payload | One `GET /native/map/data/points?per_page=1` per debounced refresh | contract | M6 receipts carry no coordinates | ADR-0025 |
| `/map` realtime | Family member update | `familyLayer.updateMember(member)` from the broadcast | One family locations + history reload, 1 s after the first event | contract | Family receipts are domain events without member data | ADR-0025 |
| `/map` realtime | Map edit (`point_moved`) | `editor.applyRealtime(event.data)` | Editor reconcile reads the affected track | contract | Receipts carry no edit payload | ADR-0025 |
| `/map` realtime | Socket reconnect | Toast only | Full layer refresh | contract | Native layers cannot know what they missed while disconnected | ADR-0025 |
| `/map` realtime | Hidden tab | MapLibre's render loop pauses; debounced timers still fire | No refresh at all until the tab is visible | contract | An idle hidden tab must not cost backend requests | ADR-0025 |
| `/map` realtime | Local resource changes (visits, places, areas, points, tracks) | Targeted layer reloads | Full layer refresh | contract | User actions, not a flood source; scoped refresh later if the bench shows a cost | plan A3 |
| `/map` | New-location toast | `Toast.info("New location recorded")` | Not shown yet | — | Pending: the native map has no toast component yet (plan C2) | open |
