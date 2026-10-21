# Rails 1.16.0 layout chrome

D1 implements the shared layout contract from the visual/map parity plan. Browser and pixel acceptance remains pending. The AFFiNE counterpart is **Dawarich — Layout chrome parity (D1)**, document `DatBh8jUwl5h_C2nqjSO6`.

## Components and behavior

`Navbar` owns the signed-in navigation and guest auth-page affordances. `NavbarEnd` renders notification, account and subscription menus; `NavbarAccount` retains keyboard-accessible dialog controls and CSRF-protected sign-out forms. `NavbarParts` renders theme, version, help and family indicators. Navbar data must be preloaded; rendering does not query it inline.

Map roots use the Rails full-screen body and viewport through `NativeMapChrome`, and retain the hidden legal footer. Notification receipts refresh scoped unread data and coalesce queued receipts; unrelated map events do not load the navbar. Ordinary application chrome uses the existing native notification session. Admission and session-refusal checks remain in place.

HTTP auth and LiveView flash messages share `Chrome.flash_message`. HTTP focus, dismissal and success timeout use the existing local auth module. LiveView dismissal uses its local dispatch. Public shared documents use `NativePublicChrome` for both header and footer.

The [divergence register](visual-parity-divergences.md) enumerates native control wiring and retained narrow-screen safeguards. Layout-specific comparison helpers normalize only the declared control/form representations and exact class substitutions. They preserve meaningful text, paths, icon geometry, severity, structure and attributes. They validate the effective DELETE/CSRF fields before comparing a native sign-out form with the Rails UJS action.

## Fixtures and checks

The source recorder is `app-phoenix/scripts/parity/layout_fixtures_spec.rb`. The external fixture corpus contains 186 layout states, 42 flash variants and two public shared-layout documents. It includes self-hosted, Cloud Lite, Cloud Pro, trial/payment/family variants, guest sign-in/recovery/registration, seven-locale navbar cases, and English/German light/dark application/map shells. Map content is excluded from layout captures. The recorder uses synthetic users and redacts stream signatures, CSRF metadata and manager JWTs.

`layout_parity_test.exs` compares normalized navbar, footer, locale suggestion, complete application container, map header and root language/theme attributes. It checks both HTTP and LiveView flash renderers and public header/footer callers. `native_map_chrome_test.exs` checks idle/event/burst query work, map root attributes, notification updates and consent persistence. New readers are registered in `native-m7-reconciliation.json`. Use the controller's assigned targeted runner; the root Rails test target is not the Phoenix gate.

For request costs, both native chrome hosts are observed for 60 seconds after mount. Publication writes and initial mounts are excluded. Twelve notification receipts are queued deterministically by suspending/resuming only the test LiveView process. The recorded Rails comparison instruments SELECTs in twelve `Notification#broadcast_notification` calls. This measures shared chrome rather than page-specific data hooks.

| Shared chrome check | Rails | Native map | Native application |
|---|---:|---:|---:|
| 60-second idle SELECTs | 0, inferred from push-only source | 0 measured | 0 measured |
| 60-second idle HTTP requests | 0, inferred from push-only source | 0 measured | 0 measured |
| 12 queued notifications, SELECTs | 12 measured | 2 measured | 3 measured |
| 12 queued notifications, HTTP requests | 0 | 0 | 0 |

Both E2E trees contain `chrome/layout.spec.js` for English/German desktop/mobile menus, theme persistence, guest navigation and local flash dismissal. Existing notification realtime/lifecycle, account reconciliation and family-indicator checks remain relevant. Mini repeat-2 acceptance and all-route chrome pixel/request captures are separate outstanding gates.

## CSS integration

The generated CSS changes only by adding `.sm\:inline-flex{display:inline-flex}` for Rails' version-badge visibility. The base hash is `33f391705f3ac4ddb39a0a5674b19ebb5c89b5a124c74bf89646492d801b3c99`; D1 generates `39f6ceed71ec9c4e5673e6aa36e1abd78ca9c31615d0980f1ffb35301cd7693b`. The controller plan reserves committed CSS and pin updates for integration. The class-source digest assertion therefore needs that integration repin; the source-closure, deterministic CSS and remaining budget checks pass without changing the pins.

Rails bugs fixed: none. Existing native text-resilience safeguards are retained and registered.

## Browser acceptance fix round 1

The guest chrome browser journey follows the sign-in form's `/users/password/new` link, then requires the recovery URL and the navbar Login link. It still checks the absence of private navigation, both flash icons, local dismissal and mobile overflow. The app and external E2E copies are identical.

The initial browser failure occurred after successful flash dismissal: manually requesting `/users/password/new?locale=en` returned 422 before rendering the layout. Rails 1.16.0 accepts the query (`ApplicationController#switch_locale`), and the recorded guest recovery fixture includes Login. Native `Auth.Recovery.Flow.parameters/1` rejects `locale`. This is an outstanding D6 auth-query parity defect, outside D1's file ownership; following the source form's canonical link exercises D1 chrome without changing recovery admission. No Rails defect is fixed.
