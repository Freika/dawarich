# Integrated page parity triage

The E1 round compares native pages with frozen Rails 1.16.0. Integrated capture `e1-final2` remains a before-change baseline; controller recapture and repeat browser acceptance are separate.

## Corrections

- Native CSS preserves the Rails compiled grain result in both themes. The source theme tokens are already identical. A local Chromium probe measures light RGB 247/247/247 and dark 27/27/27 at 20/20.
- All month hero photographs are declared native static inputs; monthly stats use the native digest path. The captured static asset audit finds the month photograph missing; the dynamically requested RTL worker also used a retired URL. Both now resolve through native static delivery. Normalized DOM asset prefixes are comparison artifacts.
- Data-page redaction preserves only the normalized onboarding completion boolean. Completed users no longer regain the account indicator; provider settings and credentials remain absent.
- Trips use application chrome, source initial map fitting and day colors. Day dots are keyed, ignored hook-owned nodes. Empty editor upload-status text no longer adds four pixels.
- Direct Insights details stay within one full-width application flex child. Overview skeleton versus ready-content captures remain asynchronous evidence, not a reason to delay native reads.
- All already-stored yearly digests appear on the list. Generation and API year admission keep their existing policy. The fixture recorder takes the index method from tag 1.16.0 because the checkout contains a later exclusion.
- Private month maps use the Rails point-density heatmap, exact source paint, purple point layer, reader theme, compass-free controls, scale and coordinate bounds. Repeated layer clicks follow the source heatmap → points → none cycle. Public H3 previews keep their existing renderer.
- Achievement material rendering uses the Rails 160 px observer margin. Registration refusal persists an explicit reader locale before its redirect using the shared locale policy.
- Notifications reproduce the source subscription gap through native root padding, without a transport element.

## Retained differences

The [visual divergence register](visual-parity-divergences.md) retains trip mobile wrapping, upload readiness, background-job narrow cards/native health, credential/QR delivery, and auth flash focus/wrapping. E1 adds only the notification gap representation and the clipped accessible-chart-table representation. A 31-row chart probe reproduces scroll height 6761 before containment and 720 afterwards while preserving every accessible row.

No native map/chart waits, retries, sleeps, release admission, Rails fallback, generation authorization, queue behavior or budget cap is changed. The original month-map discrepancy included a real H3-versus-point-heatmap mismatch as well as asynchronous capture timing. Native month-map readiness and all-route final pixels must be checked on the rebuilt controller bench; the source capture does not wait for a map on the month route.

## Verification and controller handoff

Named regressions have failing originals, green implementations, failing mutations, and restored green results. Existing page-family parity and build tests are retained. The Tailwind source hash changes from `3be9b5f906148aa1e103ebe23f072e585133e46a109ba78ecee01cdf87a0d55c` to `5bb3b3ffee5254d42802b611b421f76a2612568d889beef6f9bdb32d1240b966`; the only emitted rule added is `.empty\:hidden:empty{display:none}`. No rule is removed and native closure caps are unchanged.

Touched external browser specs:

- `auth/registration-disabled.spec.js`
- `chrome/layout.spec.js` (also mirrored as app `e2e/chrome/layout.spec.js`)
- `stats/digests-current-year.spec.js`
- `stats/stats-year-month.spec.js`

The existing trips, Insights, achievements, imports, notifications, account and background-job browser families remain part of controller acceptance. No mini execution, SSH, push, merge, full suite or bench write is performed by this round.

## Fix round 1: upload names within a LiveView

The imports page and the shell's onboarding component coexist on `/imports/new`. LiveView looks up programmatic upload inputs by name across that view, so form-scoped `uploadTo` still fails when both transports are named `files`.

`ImportsUpload.configure/2` retains `:files` for the page and accepts `:onboarding_files` for onboarding. Checksum lookup, cancellation, completion and consumption use the configured name; the hook's `data-upload-name` comes from the upload configuration that renders the live file input. Both visible Rails file controls retain `import[files][]`.

`ImportsLiveUploadTest` renders both forms, checks their distinct transport names and matching hook names, then completes and submits the page upload with one persisted import and attachment. `NativeOnboardingLiveTest` retains its completed onboarding upload journey with the separate name. Reusing `:files` for onboarding is the named regression mutation.

## Round 2: settled states and remaining bench regions

The `e1-final3` capture is the round-2 baseline. Read-only browser comparisons use existing saved bench sessions and reject non-GET/HEAD requests. Both Rails lazy frames must finish: resolving only `insights_details` can leave the residency/calendar skeleton behind. Fresh desktop and phone pages avoid transient canvas dimensions after a viewport resize. Theme probes change only client document state.

After both frames settle, `/insights` has equal Rails/native dimensions of 1440×3028 and 390×5077; direct `/insights/details` has 1440×1359 and 390×2560 in both themes. Activity ties, weekly values and the callout then agree. All remaining differing pixels belong to the monthly weekly chart: the native payload had dropped Rails' hidden legend, hidden Y ticks and grid configuration. `NativeMonthly` now retains those exact options. There is no artificial native readiness delay.

The light desktop month map in the baseline is a not-yet-rendered capture. A second, real defect appears in settled dark maps: the bundled dark style still names a retired PMTiles source. Rails' style manager substitutes the default vector source for every bundled palette. Native styling now makes the same substitution, including source type, bounds, default/custom tile URL and attribution; it preserves full custom style documents and raster/fallback paths. Read-only client replay of the final source function produces identical monthly screenshots in both themes and both widths, with ten successful vector responses and no failed tile response per page. This replay changes no bench server file or stored setting; final integrated recapture remains controller-owned.

Trip details regain the source's empty-subscription 20 px gap through native document padding. Header wrapping and intrinsic width constraints now apply only below the desktop breakpoint. The desktop replay measures identical source/native map, title and action rectangles. Phone wrapping and shrinking remain intentional under the existing resilience row; source page width is 520 px while native stays at 390 px. No Rails transport element is added.

The rich editor status contained newline text, defeating `:empty` despite the prior class fix. A childless status element restores the missing four pixels while keeping live error text. Native attachment tools stay visible under the editor's upload contract. Achievement material observers now watch the card wrapper: their hook slot is `display: contents` and has a zero-sized box. Observing that slot prevented real material initialization, leaving fallback artwork. Lazy loading, the 160 px margin and teardown remain.

The region audit verifies that import-new differences are confined to the registered disabled submit, account differences to the registered QR, and background-job differences to the registered card/alert widths plus the native health section. The registration redirect differs only in the already-registered bounded flash and focus treatment. No new blanket visual exception is introduced.

Named regressions have original RED, GREEN, failing named mutations and restored GREEN evidence in the controller report. The final affected packet passes 663 ExUnit checks, including build/register readers; JavaScript callers pass 75 checks. Browser discovery and exact controller spec scope are recorded in that report. No E2E fixture or browser spec changes in this round. No Rails defect is newly fixed.

Tailwind changes only by adding desktop `min-width:auto` and `overflow-wrap:normal` rules; its pin becomes `009835542bef0e6c1bdd43574329280422e8cd2da289e8480c487bd33659e5c3`. The corrected map source increases its measured closure by six raw bytes and four gzip bytes, so its exact caps become 126407/45047. Other caps are unchanged. Controller repeat acceptance and integrated capture on the final feature head remain pending.
