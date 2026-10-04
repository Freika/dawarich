# A12c residual mail

Implementation is in progress on `feat/phoenix-a12c-mail`, starting at `0672ae88e`.
Acceptance is tests only; stand/browser/image acceptance is deferred to the controller mini lane.
No mail ownership has changed. Auth mail is security-sensitive; no AFFiNE writes are made.

## Rails corpus

The existing `app-phoenix/scripts/parity/explore_features_mail_spec.rb` captures deterministic
fixtures under `app-phoenix/test/fixtures/mail/residual/`. Write mode requires
`WRITE_PHOENIX_FIXTURES=1`; ordinary execution compares bytes without writing.
The original explore-features corpus remains byte-identical.

- `content.json`: 23 reachable OTP-lock, test, location-request and Devise content rows,
  including recipient/ambient locales, special characters, time zones and decoded MIME trees.
- `auth_intents.json`: 17 real-model callback/OTP cases, including suppressed notifications,
  old-email recipients, synchronous delivery failure, OTP cache throttling and enqueue failure.
  The existing A11 recovery mail/lifecycle/token/effects oracles remain dependencies.
- `digest_content.json`: 27 monthly/yearly cases and 21 chart helper cases, with exact decoded
  bodies, MIME trees and data projections. Cases cover units/locales, leap dates, strict
  60-minute filtering, Unicode/tied ranks, nil/malformed JSON, negative/fractional values,
  sparse yearly stats, trend boundaries and sharing links.
- `effects.json`: 44 digest staging/transport cases and 10 location reverse-command cases.
  Real serialized jobs retain ambient locale/time zone; mail rendering reads current preferences.
  Enqueue failure preserves nil `sent_at`, validation failure can leave mail queued, and later
  SMTP failure preserves the timestamp. Negative distances and inactive users remain eligible.
- `http.json`: 27 real test-mail endpoint cases, exact Turbo append responses, source-safe
  SMTP error descriptions, HTML flashes/redirects, locale selection, unsupported method/format
  behavior and a missing-CSRF 422. Trial mail actions produce no delivery and no native mapping;
  the retained member-joined template has no runtime producer or native mail mapping.

Devise 5.0.4 Cloud email/password callbacks invoke `deliver_now`; the capture intercepts that
delivery boundary while retaining actual saves, callback predicates and rendering. They remain
Rails-owned, as does OTP lockout accounting and mail enqueue. Supported reset/unlock flows keep
their existing native recovery owner.

User does not enable Confirmable. Confirmation fields, route and producer are absent;
`reconfirmable = true` alone does not enable it. The dormant confirmation template remains.
Successful confirmation/reconfirmation parity awaits an enabled real Rails contract.
Account-destruction confirmation is a separate existing route.

Runtime source search finds no `member_joined` producer. Its mailer/template remain for fallback.
The four trial lifecycle mail actions remain no-ops and their job wrapper skips them.

## Verification progress

R1's two named captures have initial RED and restored GREEN evidence. M-R1-case omits
reachable email-change rows and fails the fixed case list. M-R1-recipient changes the installed
Devise callback recipient to the new email and fails the old-recipient assertion; source restored.
R1's three generator examples now pass in no-write mode after the controller's Postgres recovery;
Ruby lint passes with cache disabled. Binary fixture bytes compare against generated binary
bytes, preserving the original UTF-8 content.

R2 captures source rendering without calculation or delivery. M-R2-threshold changes the
significant-minute threshold to 61 and fails because the 61-minute country disappears.
The threshold is restored to 60. Rails sorts UTM query keys, and yearly sharing links depend
on a present UUID even when sharing is disabled; the corpus retains those source behaviors.
Malformed location integers and mixed-sign bars raise rather than producing empty mail.

R3 observes delivery enqueue before the timestamp update. Its save-failure case uses an actual
invalid month and model validation, with no mocked database behavior. Missing serialized digest
records discard delivery; queued soft-deleted User records still deliver under Rails GlobalID
lookup. Accepted/expired location requests still mail, missing targets fail rendering, missing
requests discard, repeated reverse commands enqueue once, and enqueue failure releases the cache
claim. Generation's retained Rails reverse handler selects `user.locale` before queueing.
M-R3-sent-order moves the timestamp before enqueue and fails the explicit enqueue-failure
case. The source is restored; the named capture and no-write fixture comparison pass.

R4's M-R4-sync replaces synchronous Mail delivery and fails the first send-count assertion.
M-R4-trial lets trial-expired past the compatibility skip and fails with UnknownEmailType.
Both source changes are restored. Unsupported JSON/plain response formats reach SMTP before
Rails returns 406; the native route must hand unsupported requests back before SMTP starts.

P1 adds pure OTP-lock/test/location rendering and five templates, with shared neutral layouts
used by existing ExploreFeatures and Wave2. Eleven basic corpus rows match decoded bodies,
headers, locales and MIME parts. M-P1-escape removes requester escaping and fails the location
HTML comparison; restored rendering passes with existing layout/recovery regression tests.
Test-mail takes an explicit clock projection (local time, offset, zone and validity), obtained
by its caller through existing Postgres time-zone helpers. No time-zone dependency is added.
The MIME test helper handles absent multipart transfer headers and preserves RFC2047 spaces
across adjacent encoded words. The production SMTP serializer is unchanged.

P2 adds only pure HTML renderers for reachable Devise email-changed/password-change content.
All twelve reachable Devise/recovery corpus rows match bodies, headers and decoded MIME.
The email-changed recipient stays the old address while its body describes the new address.
M-P2-branch substitutes the old body address and fails; M-P2-retained-enqueue introduces an
actual recovery job at the Cloud hand-back and fails the zero-enqueue check. Both are restored.
OTP/Cloud callers, recovery worker/lifecycle and dormant confirmation files stay with their owners.

P3 projects the captured monthly/yearly data with parameterized digest and user/year stat queries.
All twenty successful R2 rows match, including December, invalid days, source units and significant
locations. M-P3-user removes the yearly owner predicate and fails the explicit foreign-user
January assertion; restored selection passes. No calculator or page entitlement filter is used.

P4 reproduces all twenty-one captured ASCII helper rows, preserving code-point label widths,
stable rank ties, Ruby half rounding, chart errors, sparse heatmaps and translated trends.
M-P4-quartile makes the first quartile inclusive and fails the boundary case; restored helpers pass.

P5 compares every R2 content row: twenty complete messages and seven data/render errors.
Subjects, recipients, locale, URLs, HTML/text whitespace and decoded MIME parts match source.
Control-only template lines preserve Rails newline removal, and inline style quotes are escaped.
M-P5-utm removes monthly manage-preferences content and fails the complete message comparison;
restored rendering and the scoped basic/Devise/ExploreFeatures/Wave2/recovery regressions pass.
Source Ruby exceptions map to native data/type/date errors; no empty message rescue is added.

The R1–R4/P1–P5 barrier is complete. Resume at P6's queued-before-sent-at staging contract.
Delivery workers, ownership wiring, test-mail HTTP,
ED allocation and final C1–C5 gates are pending. Rails source/specs and dormant stubs are retained.

P6 adds separate monthly/yearly mail enqueue workers with exact locale-bearing command decoders.
All 44 Rails effects rows pass against real Oban inserts and database constraints: enqueue occurs
before the validated timestamp update; enqueue failure keeps nil sent_at, and invalid digest
validation leaves its queued delivery observable. Ambient locale/timezone survive staging.
M-P6-save-first moves timestamp persistence before insertion and fails monthly_enqueue_failure;
restored staging passes. The shared digest Store now exposes only the source-equivalent validated
sent_at update. SMTP and ownership remain pending at P7/P9.

P7 adds the separate digest DeliveryWorker. It loads serialized-record identities afresh,
including soft-deleted queued users, and does not recheck sent_at or settings guards. Missing
digests discard delivery, matching the Rails ActionMailer deserialization result. Existing
Delivery claims retain duplicate/held/retry behavior; keys include the originating event so a
source-legal later send after timestamp clearing remains possible. SMTP and render errors
return bounded codes, with no mail-map/body/token logging. The inherited crash-after-accept
ambiguity remains; this does not provide exactly-once SMTP delivery.
Both P7 tests pass, including eight exact Rails body/subject locale cases through both stages.
M-P7-sent-guard suppresses queued SMTP and fails; M-P7-locale replaces fr with en between queues
and fails. Each is restored and green, with inherited Delivery regressions.

P8 adds the location-request mail worker for the already-merged API producer's version-1
request/requester payload. Target preference controls rendering; request status/expiry do not
add delivery guards. Missing source requests/requesters skip, while a missing target returns a
bounded source rendering failure. Real request identities and existing Delivery claims suppress
same-request duplicate SMTP, preserve held claims, and retain the inherited ambiguous-send
behavior. Exact Rails bodies match for eligible source rows. M-P8-recipient sends to the requester
and fails pending's target assertion; restored worker is green. Rails reverse-handler Redis
cache/enqueue failure contracts remain on the retained fallback; no new Redis namespace is added.

P9 registers exactly three unclaimable mail commands. Existing digest terminal settlement and
family API creation now choose their mail owner under the current Ownership lock. OFF retains
exact Rails reverse kinds/payloads; ON writes the existing public outbox and dispatches one worker.
Digest payload locale uses the source reverse handler's fresh user.locale/default-en convention,
without changing calculator arguments. The original settlement transaction still couples mail
selection to its processed marker, and terminal failure rolls back both. No owner is activated.
M-P9-off forces native selection under Sidekiq and fails the retained reverse assertion; restored
selection, real family API creation, generation, registry and owner inventory tests pass.
The job inventory records the location command's real native API producer separately because
there is no corresponding concrete Rails job class; digest jobs receive their exact mail keys.
