# A12d3 schedules and drain

## Stop order

Stop new source incoming, manual and callback producers first. After an explicitly
selected key activates, disable its retained source cron loading/enqueue controls.
Keep Sidekiq consuming queued, scheduled and retry work, and keep the Rails reverse
poller running while native workers can still publish Rails effects. Accepted native
work remains native when ownership returns to pinned Sidekiq.

Observe all future work, retries, children and busy workers before the final process
stop. Sidekiq quiet stops acceptance; it does not consume scheduled/retry sets.
Quiet only after the relevant sets and busy counts are empty. Unknown classes and
dead work require controller disposition; retain them rather than purging them.

Native shutdown stops the jobs workers subtree, then locally pauses Oban queues,
before draining the front and stopping Oban and the database. The existing 12-second
Oban shutdown grace remains unchanged. Pausing prevents new local execution; it
neither cancels accepted work nor proves completion. Other nodes continue accepting
work. Accepted work may commit durable successors and Rails reverse effects while
the local queues are paused, so both consumers remain necessary until those debts
resolve.

Forward Sidekiq retirement and binary rollback have separate drain checks. Current
reverse producers remain BLOCKED even with an empty observed backlog. Ownership
hand-back alone does not authorize stopping either runtime or rolling back binaries.

## Source cron restoration after rollback

Keep producers quiescent while releasing affected keys to pinned Sidekiq. Rehome
only supported pending commands, including future commands; preserve failed pushes,
unsupported versions and quarantined rows for disposition. Never clone dispatched
native jobs. Joint Lite cron/mail ownership moves together, and tracks rehoming also
handles the supported anomaly recalculation alias. Accepted native bulk work can
still complete and publish source-owned children after hand-back.

After ownership and drain checks permit reopening, restore the installed Sidekiq
cron loading configuration and enable the affected retained cron jobs using their
installed controls. Preserve the original schedule, arguments and timezone. The
rollback regression uses the configured TeslaMate schedule and the installed
`Sidekiq::Cron::Job.enable!` control; repeated polls of one original slot enqueue one
source batch, and replay of that accepted batch retains its receipt. Restore any
process-level cron control as well before restarting the source poller, then reopen
incoming/manual/callback producers. An empty observed set cannot authorize binary
rollback while native work or compatibility effects remain.
