# Rails bugs fixed in Phoenix

This register records fixes made in the port under controller ruling 17.
Other package reports and expected differences remain inputs to the controller's
release-wide changelog compilation.

## Failed media purge loses its storage retry target

- Symptom: a failed physical deletion leaves private poster, route-video or
  export media in storage after Active Storage has destroyed the blob row;
  later source lookups cannot find the blob to retry the deletion.
- Rails source: `app/services/posters/purge_commands.rb:21`,
  `app/services/exports/purge_commands.rb:21`, and
  `app/services/rails_commands/a8_handlers.rb:29` call `blob.purge_later`.
  Installed Active Storage 8.1.3.1's `app/models/active_storage/blob.rb:335-338`
  destroys the blob before deleting storage; its purge job takes that blob.
- Phoenix: `app-phoenix/lib/dawarich/posters/purge_worker.ex:51` deletes storage
  while the guarded blob row is locked, before removing rows. Errors roll back
  rows and variant child changes; retries retain the target. Export/route-video
  consumers already retain object keys and services durably in Oban jobs.
- Regression: `F1 captured poster purge retains failed storage work until retry
  and drain completion` in
  `app-phoenix/test/dawarich/a12f3b_e13_purge_retry_test.exs`.
- Expected difference: ED-A12F3B-E13-F1 in
  `app-phoenix/parity/expected_diffs.md`. No deferred bug row: this is fixed.
