# Phoenix test storage

Routine fixture cleanup uses `Dawarich.FixtureCleanup.delete!/2` in ExUnit and
`FixtureCleanup.delete!` in RSpec. Both delete dependent tables before their
parents, preserving the existing committed visibility across connections.
Avoid routine `TRUNCATE`, which replaces table and index storage files.

JobsCase owns the common reset; nested case templates do not repeat it.
Rails installs Phoenix control tables before suite transactions and reuses them.
Simple ScratchCase layouts use `tables:` and `setup_all`; migration and trigger
tests retain their isolated DDL setup. Reset sequences with `setval` only where
fixture assertions require specific generated IDs.

Deleted fixtures preserve heap storage, so queries must not rely on heap order.
Visits index queries break equal start-time ties by ID; unordered tile epoch
timestamps are compared as values. The storage regressions check committed
visibility and unchanged relation filenodes across repeated cleanup calls.
