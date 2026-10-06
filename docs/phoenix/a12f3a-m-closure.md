# A12f-3a package M closure

Source baseline: Rails 1.15.3; implementation base c3197844f. Main map journey first, per ruling 15.

## M01 — map shell selection

Both `/map` and `/map/v2` render natively, including explicit date selection, timeline panel, studio hosts and HEAD. Text dates captured from Rails include slash-separated dates and day/month-name/year. Tests run in self-hosted, explicit Cloud and unset-default modes with no Rails upstream.

The tagged M01 aggregate initially failed on the selected start date; implementation passed. Ignoring `date` in `MapWindow.bound/4` failed that assertion; restoring passed. Existing map parity, import range, settings, locale and LiveView tests are retained.

O03 source captures were not at this base. Package M extends the existing source generators and records task captures itself. Capture normalization and source clock remain the existing generator convention. Source recording, gate counts and mutation assertions are recorded in the execution report.

## Ownership and handoff

M owns presentation and frame reads. No native jobs or reverse effects are produced. Map/track refresh uses the existing A12a channel contracts. W owns point/segment/area effects; V owns visit effects/cache invalidation; R owns video hooks. Global transport and final route wiring remain A12f-2/O-owned.

M02–M07 closure and final full-suite gates are pending in this first commit. G44 browser proof and integrated producer-to-refresh proof remain controller release checks.
