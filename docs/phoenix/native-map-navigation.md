# Native map navigation

Native pages keep Rails Turbo HTML responses in standalone mode. The Phoenix client tears down LiveView roots and retained Stimulus bridges before Turbo replaces or caches a body, then mounts bridges and reconnects LiveView on `turbo:load`. This covers map date searches, tracks, replay, studios, and controls on stats/digest pages. Map applications unload controllers and remove their portaled studios through the existing map shell lifecycle. Repeated bridge boot is idempotent; flash observers attach once per container.

The shared API timestamp admission accepts ISO local date-times as well as dates, epochs and date-times with offsets. Local timestamps retain their text until the existing Rails timezone context parses them. Calendar and clock validation remain in place. The monthly stats map's retained controller sends local month boundaries; March in Europe/Berlin spans the DST change and must use the viewer's timezone at each boundary.

Source characterization uses real Rails map Turbo requests and authenticated monthly points requests. Native regression names in `map_navigation_test.exs` cover these envelopes and client lifecycle, with production mutations disabling Turbo remounting or requiring a timestamp offset. Existing bridge, map shell, map API and timestamp caller tests supplement browser coverage.

Cold digest creation also admits the retained method-link form’s `_method=post` body field. The digest request removes this transport field before applying the existing session/CSRF checks. Other method overrides and invalid CSRF tokens remain refused.

These corrections restore working Rails behavior; they do not fix a Rails defect. The Cloud lifecycle admission is unchanged. Verification results are maintained in the controller implementation report and the AFFiNE counterpart titled `Dawarich — Native map Turbo navigation`.

Acceptance verification completed three consecutive standalone browser runs and one coexistence run, each with 14 passes, zero failures, zero skips and zero retries. Coverage includes date search, tracks, replay, all five Video Studio scenarios, the monthly map and cold digest generation.

The seed-404 full gate ran 9,897 tests and found one obsolete golden ownership expectation for `replay_points_local_time_without_offset`. That case now requires a native response while preserving the recorded Rails status, body, headers and unchanged database assertions. A production mutation that shifts its local lower bound fails the exact recorded-body assertion; restored golden, timestamp and navigation tests pass 144 tests. Compile with warnings as errors and formatting pass. A second full gate requires controller approval under the assignment's single-run limit; zero-failure full acceptance remains pending. The controller implementation report contains exact evidence and current status.
