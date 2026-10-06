# Trips native closure

Package T extends the existing trip read models, web commands, LiveViews and native photo/export providers. Source parity remains the contract, including Rails bugs. Per-key Sidekiq ownership remains a rollback fence; the package does not activate global registry entries.

## Navigation and calculation

Trip index/new/edit render in self-hosted, explicit Cloud and unset-default modes. Show calculation uses the existing `command:trips.calculate` outbox producer for an Oban owner in either deployment mode. Future imported trips bypass calculation. Mixed-user plan graphs remain refused.

T01 and T06 selectors passed after initial failures, each named production mutation failed its assertion, and restored selectors passed. Source captures are generated through the existing trips and description generators; two passes produced identical bytes and preserved all preexisting fixtures. The prepended CloudDrain client required the fixture fault injection to wrap each constructed Sidekiq client instead of an unsupported any-instance stub.

## Handoff

`Trips.ShowCalculation.run(repo, user, id, context)` calls `Trips.WebCommands.calculate!` with actor-scoped trip, units and source clock. It persists a UUID/version-1 `trips.calculate` command, aggregate/dedupe identity and scheduled time under the existing owner lock. No native path publishes a `trips.calculate` reverse effect. Accepted-work completion remains with the existing calculation worker and shared owner APIs.

O06–O08 own final route reconciliation and source-capture reconciliation. No shared route file changed in this cut. Storage, richer content, photos, note edge envelopes and export tails are recorded as work progresses. Browser/release and integration seed gates belong to the controller.
