# Digest period execution

Status: accepted, 2026-10-07. Supersedes the digest checkpoint decisions in
`stats-native-effects.md`. Controller ruling: fix4 RX-STATS, rereview2 R2.
AFFiNE counterpart: `Dawarich — ADR-20261007-digest-period-state — One shared
digest period execution record` (`7wYcTSdinqYkkeAIvwpT-`).

## Context and decision

The previous two-checkpoint protocol could not let Rails recognize an older
native generation before native retry promoted its marker. A shared receipt
lock serialized current work but could not resolve incompatible historical
completion identities. The controller requires one authoritative period state.

Rails and Phoenix share one `phoenix.digest_executions` row per calculation
effect, user, year and month. Yearly month is zero. A fresh job ID does not create
a second generation or mail admission for the same period.

Both runtimes acquire a PostgreSQL transaction advisory lock on the JSON array
`[effect,user_id,year,month]` before reading or changing this record. The earlier
execution-receipt lock is also retained for compatibility. Decisions use the
period row; `processed_commands` markers are compatibility output and legacy
upgrade inputs.

| State | Next operation | Failure behavior |
| --- | --- | --- |
| Absent | Claim and generate | An uncommitted claim disappears on crash |
| claimed | Generate under the period lock | Failure releases the claim and preserves source notifications |
| generated, mail | Publish mail intent only | Rollback retains generated; retry never regenerates |
| generated, missing | Complete without mail | No user lookup or calculation is repeated |
| published | Finish | No generation or publication is repeated |

Successful stats/digest writes commit with `generated`. Native generation accepts
only `{:ok, result}` and `:missing` as success. A returned `{:error, reason}`
(including explicit calculator transaction rollback) or a raised failure releases
the claim, records the failure notification, admits no mail, and returns an error
for retry. Publication commits its durable mail intent with `published`.
Source continuation after internally
reported stats errors, partial intermediate stats writes on digest failure,
locale, timezone, missing-user behavior and mail eligibility remain unchanged.
Published means durable mail admission, not email delivery or `sent_at`.

Rails checks the publication savepoint's successful transaction return before
advancing the period to `published` and writing the terminal receipt. A swallowed
`ActiveRecord::Rollback` raises `IOError`, retains `generated/mail`, and admits no
mail. The period lock remains held, and mail admission, published state and the
terminal receipt still commit together in the enclosing transaction. The existing
returned-error notification path and successful no-data/mail behavior are retained.

## Alternatives and consequences

Adding another checkpoint lookup retains multiple authoritative records and
requires reconstructing irreversible historical event IDs in each runtime.
The single record makes the failure boundary explicit and permits either
runtime to finish publication. The trade-off is additive schema and upgrade
reconciliation. A period is now the effect identity, so new job IDs for an
already completed period cannot trigger another calculation or mail admission.

## Upgrade and rollback

The additive migration `20261007235900_create_digest_executions.exs` creates the
period table and flushes queued DDL before live reconciliation. It checks for
source table presence and schema/table read privileges so scratch schema bootstrap
and migration roles without public access remain usable. The native outbox is
optional; Rails 1.15.3 digest results are imported before that table exists.
Its SQL backfill imports existing digests as generated, or
published when `sent_at` or a retained durable mail intent is present. Retained Oban/outbox/reverse arguments are
scanned in batches of 500 to identify older successful generation and terminal
markers, including successful no-data generation without a digest row. Explicit
failed checkpoints are never imported as success; their erroneous matching
legacy terminal marker is released before either runtime retries. Existing new-protocol rows
are not overwritten.

Imported rows retain a `legacy` flag until their first locked reconciliation.
Published is terminal and cannot be demoted by legacy generation markers.
A matching legacy terminal marker promotes a pending imported period to published;
a matching shared or older generation marker preserves its recorded outcome.
Reconciliation clears the flag, after which execution decisions use only the
period record. An old checkpoint UUID alone is irreversible: the persisted
result or retained accepted arguments supply its period provenance.

Run the additive migration before starting upgraded consumers. Old consumers
must be quiesced during migration and upgrade; their old checkpoint protocol
does not acquire the new period lock. Do not run an unpatched historical
consumer concurrently with upgraded consumers. Rails alone continues its
source flow when the Phoenix period table is absent. No public Rails schema
change is required, and removing Phoenix leaves Rails 1.15.3 usable. Existing
mail poller/consumer recovery remains responsible for admitted delivery.

Code: `app/services/users/digests/execution.rb` and
`app-phoenix/lib/dawarich/digests/{execution,generation,execution_upgrade}.ex`.
Regression matrix: `period_execution_spec.rb` (RX15–RX21, RX26),
`fix4_rxstats_test.exs` (RX10–RX14, RX18, RX24–RX25, RX27), plus retained RX01–RX09.
The legacy regression executes the real pre-fix3 generator, rolls back terminal
publication, applies upgrade reconciliation, then checks both writer orders.
`digest_execution_migration_test.exs` (RX29) runs the actual migration against
synthetic public results and guards DDL ordering before reconciliation. RX30
checks migration roles denied public schema/table access; RX31 covers the Rails
1.15.3 schema before a native outbox exists.

## Retained boundary coverage

Round-five tests `fix5_rxstats_test.exs` add the exact monthly/yearly calculator
rollback (RX32), monitored worker crash after storing the digest but before the
period state commits (RX33), and resumption of a persisted `generated/missing`
row while its user exists (RX34). RX35 starts with no period record and adopts
legacy shared `mail` and `missing` markers. RX36 executes the historical native
missing-user generator, rolls back terminal publication, retains accepted Oban
arguments, restores the user, reconciles, and checks native-first and actual
Rails-first completion without generation or mail.

`period_boundaries_spec.rb` retains Rails persisted-missing resumption (RX37),
raw source-job terminal adoption (RX38), shared-missing adoption (RX39), original
job behavior with the period table hidden (RX40), and direct historical
calculation classes with the additive table present (RX41). RX42 kills and waits
for only its owned Ruby child at the actual saved-result/before-generated-state
boundary, waits for the period lock, then retries twice with one monthly or
twelve yearly stats calculations, one digest and one mail admission.

Coverage-gap cases pass the current baseline and detect named mutations; they
are characterization regressions. RX32 fails the unmodified round-four source
and passes the returned-error fix. These targeted tests do not certify an entire
historical Rails application or full historical suite. Existing RX05 covers the
native raw terminal; RX20 covers Rails shared-mail adoption. No claim of full
historical-app certification is made.

`publication_rollback_spec.rb` retains RX43 for both monthly and yearly Rails
jobs. Each probe rolls back the existing publication savepoint after its real
callback, checks the pending period and absence of mail/terminal receipt, then
runs two fault-free retries. Exactly one digest and one mail admission remain,
with one monthly or twelve yearly stats calculations across all attempts.
