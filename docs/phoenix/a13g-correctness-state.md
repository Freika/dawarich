# A13g shared registration and trial welcome state

A13g completes the row 13 T6 registration policy and T4 trial welcome claim cuts.
Revised Rails and native Phoenix callers use the same PostgreSQL authority wherever
the corresponding Phoenix table exists. This cut adds no supervisor child, queue,
pool, dependency, route switch or runtime readiness change. Redis remains required
by the other runtime owners.

## Registration upgrade

The forward Phoenix migration makes `registration_setting.enabled` nullable.
Stored `nil` remains distinct from an absent singleton and is source parity, not
an expected difference. Existing `true`, `false` and `nil` rows take precedence
over the legacy cache and prevent any upgrade Redis read.

After Phoenix and Oban migrations, `Release.migrate` copies the absent singleton
through the caller's dynamic repo. The source is the allocated cache database 0,
not the Sidekiq database. The transient Redix connection follows existing URL/TLS
configuration and closes before decoding on success and refusal. No request opens
that upgrade connection.

Only real Rails 7.1 and Marshal70 unversioned, non-expiring boolean/nil entries are
accepted. Unknown formats, versions, expiry metadata and other values refuse the
copy with a bounded error. Genuine tiny Marshal70 scalars remain uncompressed;
the source corpus separately exercises actual compression with a larger payload.
A missing legacy key seeds the singleton once from the exact environment value
`ALLOW_EMAIL_PASSWORD_REGISTRATION == "true"`.

The copy uses insert-on-conflict-do-nothing and rereads the winner. An initialized
admin value cannot be overwritten by a stale copy. Refusal leaves no copy marker
or phantom default; the operator can retry the upgrade after correcting the source.
Existing public Rails tables and its migration ledger do not change.

With the table present, Rails and Phoenix registration readers/writers use PG.
A missing singleton or SQL failure refuses service instead of falling back to
Redis or an environment default. Rails retains its original cache behavior only
before table presence. Self-hosted registration denial, invitations, Cloud rules,
admin authorization and existing reader-specific hand-back boundaries remain.

## Welcome consumption

Both callers derive exactly `trial_welcome:consumed:sha256:` followed by the
lowercase hexadecimal SHA-256 of the original JTI's UTF-8 bytes. No normalization
or literal JTI is stored in the PG key. Unicode and embedded NUL values preserve
their source consume and replay outcomes. Native admission retains the original
1024-byte limit on the old prefix plus JTI; larger signed values return to revised
Rails before an effect. Rails adds no native size guard.

`State.claim` performs one atomic insert or expired-row replacement. The TTL is
the existing integer expiry conversion minus caller time, with a 60-second floor;
PG measures expiry from statement time. A live replay does not extend expiry.
The existing purge worker remains responsible for physical cleanup.

The claim commits before Trackable sign-in. A sign-in failure retains the claim
and returns a terminal response without issuing a cookie or replaying upstream.
A claim database error also produces no sign-in or upstream replay. Guest replay
goes to sign-in; same-actor replay keeps the map redirect and does not retrack.
Original cache-control, pragma and referrer-policy headers remain.

Before `once_claims` exists, revised Rails retains its original literal-key cache
database 0 NX write. It does not call the generic claims adapter's absent-table
Sidekiq fallback. Once the table exists, no Redis fallback is permitted.

## Activation and rollback boundary

ED-490 records the accepted D5 initial welcome-claim reset. An already consumed,
still-valid legacy welcome token can replay once at the authority switch; the
actual signed expiry defines that window. Eugene's release activation review
remains required. ED-491 covers one-time registration copy/seeding, ED-492 bounded
PG/incomplete-copy refusal, and ED-493 statement-clock expiry and durability.

Existing `settings`, `admin`, `trial` and `home` page switches and independent
`DAWARICH_PHOENIX_AUTH` flow selection return requests to revised Rails without
changing this authority. They are routing rollback controls, not an old-binary
downgrade. An old Rails binary still reads/writes Redis; an old native binary
cannot share the initialized PG nil through its Redis reader. Do not use either concurrently after the
switch. Downgrade of the nullable migration refuses a stored nil row.

## Verification and remaining work

Migration/history cleanup, genuine source decoding, stale-copy contention,
restricted-cloud dynamic repo, connection closure, reader/authorization boundaries,
SQL claim contention, terminal failures and bilateral Rails/native replay have
named mutation proofs in the existing targeted tests. Interoperability runs real
Open3 native callers and Rails requests against one private Rails database.
The large-JTI unit checks prove effect-free native refusal and real Rails replay;
actual stand forwarding is deferred to the controller mini lane.

The five existing generators run twice, including an exact comparison of the
whole activation JSON. Branch merge gates use the existing resync/seed scripts
and only full ExUnit seeds 404 and 202; the controller owns the third seed on the
integration head. Exact results and tested head belong in
`SP/orch/out/impl-a13g.report.md`. Browser, stand, Docker/image and release topology
checks are deferred to the controller mini lane. No AFFiNE writes are permitted
for this security-sensitive task.

T1-T3, T5, T7-T8 and T10-T13 remain with their named auth, callback, pending upload,
operation/progress, epoch and raw-data owners. This cut does not remove Redix,
Sidekiq, Cable, limiter configuration or their runtime readiness dependencies.
